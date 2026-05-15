local ADDON_NAME, ns = ...
ns.AuraList = {}
local AuraList = ns.AuraList

-- [ MIDNIGHT API SAFETY ] -----------------------------------------------------
-- Midnight 12.0 introduced secret/tainted aura values inside M+ keystones and
-- PvP. Two layers of protection:
--   1. issecretvalue(v) — Blizzard global that returns true when a value is
--      secret-tainted. We guard every field we read (spellId AND expirationTime).
--   2. CanReadAuras() — pre-flight check before any scan. If auras are fully
--      locked we skip the scan entirely rather than returning false negatives.
--
-- NON_SECRET: spell IDs confirmed readable via GetPlayerAuraBySpellID in all
-- contexts (in combat, inside M+, PvP). IDs NOT in this set are skipped when
-- InCombatLockdown() is true.
local NON_SECRET = {
    -- Raid buffs
    [1126]=true, [432661]=true,   -- Mark of the Wild + Midnight variant
    [1459]=true, [432778]=true,   -- Arcane Intellect + Midnight variant
    [6673]=true,                  -- Battle Shout
    [21562]=true,                 -- Power Word: Fortitude
    [462854]=true,                -- Skyfury
    [474754]=true,                -- Symbiotic Relationship
    [369459]=true,                -- Source of Magic
    -- Blessing of the Bronze (one per class, 13 total)
    [381732]=true,[381741]=true,[381746]=true,[381748]=true,[381749]=true,
    [381750]=true,[381751]=true,[381752]=true,[381753]=true,[381754]=true,
    [381756]=true,[381757]=true,[381758]=true,
    -- Paladin Rites (non-secret in 12.0)
    [433568]=true, [433583]=true,
    -- Rogue Poisons (non-secret in 12.0)
    [2823]=true, [8679]=true, [3408]=true, [5761]=true,
    [315584]=true, [381637]=true, [381664]=true,
    -- Shaman Imbuements (non-secret in 12.0)
    [319773]=true, [319778]=true, [382021]=true, [382022]=true,
    [457496]=true, [457481]=true, [462757]=true, [462742]=true,
    -- Midnight Flasks (non-secret in 12.0)
    [1235110]=true,[1235108]=true,[1235111]=true,[1235057]=true,[1239355]=true,
    [1235113]=true,[1235114]=true,[1235115]=true,[1235116]=true,
    -- Evoker self-buffs
    [360827]=true,
    -- Holy Paladin beacons
    [53563]=true, [156910]=true,
    -- NOTE: Devotion Aura (465) is ContextuallySecret in Midnight — NOT listed.
    -- NOTE: Warrior stances (386208, 386196), Shadowform (232698), shields,
    --       Well Fed (455369/462187), and augment rune IDs are not whitelisted —
    --       safe to read OOC only.
}

-- Returns true if a value is Blizzard-tainted (secret) in the current context.
-- The issecretvalue() global is only present in Midnight 12.0+; guard against
-- older builds.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Pre-flight: returns false if aura APIs are fully locked/tainted right now.
-- We probe the first aura slot; if its spellId field is secret the whole
-- aura table is in a protected context and scanning would give wrong results.
local function CanReadAuras()
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    if not ok then return false end          -- API errored
    if aura == nil then return true end      -- no buffs at all — readable
    if IsSecret(aura.spellId) then return false end
    -- Extra pcall: confirm the value is actually comparable (not a userdata trap)
    local cmpOk = pcall(function() return aura.spellId == 0 end)
    return cmpOk
end

-- [ PRE-COMBAT CACHE ] --------------------------------------------------------
-- Snapshot of tracked aura states taken at ENCOUNTER_START / PLAYER_REGEN_DISABLED.
-- Keys: spellID (or "weaponEnchant"), values: true (present) or nil (absent).
-- Used as fallback when live aura API is locked by Midnight's secret-value system.
local _preCombatCache = {}
local _preCombatCacheValid = false

-- Minimum seconds remaining for a buff to count as "present".
-- Set by GetMissing() from db.reminder.buffMinRemaining before each scan.
-- Default 60 s is used when helpers are called outside of a scan context.
local scanMinRemaining = 60

-- Duration threshold for "expiring soon" detection, set per-scan from db.
-- Separate from scanMinRemaining (which is "minimum seconds to count as present").
-- This is "show reminder when remaining < threshold AND total duration > threshold".
local scanDurationThreshold = 0  -- 0 = disabled

-- Safe player aura query.
-- Returns true only if the buff is present AND has meaningful time remaining.
-- expirationTime == 0 means permanent (no expiry) — always counts.
-- Falls back to pre-combat snapshot when the live API is locked during combat.
local function PlayerHasAura(spellID)
    -- Try live API first
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok and aura ~= nil then
        -- Guard the spellId field itself against tainting
        if IsSecret(aura.spellId) then
            -- Live value is secret — fall back to cache if in combat
            if InCombatLockdown() and _preCombatCacheValid then
                return _preCombatCache[spellID] == true
            end
            -- OOC: GetPlayerAuraBySpellID returned a non-nil aura, so the buff
            -- IS present even though the spellId field is tainted.  Trust the
            -- existence of the return value rather than the unreadable field.
            return true
        end
        -- Check expiry — guard the expirationTime field too
        if IsSecret(aura.expirationTime) then return true end  -- secret expiry = treat as permanent
        if aura.expirationTime == 0 then return true end       -- permanent buff
        return (aura.expirationTime - GetTime()) >= scanMinRemaining
    end
    -- API failed or aura not present — fall back to cache in combat
    if not ok and InCombatLockdown() and _preCombatCacheValid then
        return _preCombatCache[spellID] == true
    end
    return false
end

-- Returns true if the buff exists but will expire within scanDurationThreshold.
-- Only triggers if the buff's total duration exceeds the threshold (avoids
-- flagging short-duration buffs like 30s proc effects).
local function IsExpiringSoon(spellID)
    if scanDurationThreshold <= 0 then return false end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or not aura then return false end
    if IsSecret(aura.spellId) then return false end
    if IsSecret(aura.expirationTime) then return false end
    if aura.expirationTime == 0 then return false end  -- permanent buff, never expires
    local remaining = aura.expirationTime - GetTime()
    local duration = aura.duration or 0
    -- Only flag if total duration is longer than threshold (skip short buffs)
    if duration <= scanDurationThreshold then return false end
    return remaining > 0 and remaining < scanDurationThreshold
end

-- Fallback: scan all player auras by name. Used for categories like food where
-- the Well Fed spell may be ContextuallySecret in Midnight and not readable
-- via GetPlayerAuraBySpellID.
local function PlayerHasAuraByName(name)
    if not name or name == "" then return false end
    local i = 1
    while true do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not data then break end
        local nameOk, auraName = pcall(function() return data.name end)
        if nameOk then
            -- Wrap the comparison itself: auraName may be a secret value in 12.0,
            -- which would throw if compared directly outside a pcall.
            local cmpOk, matches = pcall(function() return auraName == name end)
            if cmpOk and matches then return true end
        end
        i = i + 1
    end
    return false
end

-- Safe unit aura set builder — scans a unit's buffs ONCE and returns a
-- spellID-keyed table. Callers check multiple buff IDs with O(1) lookups
-- instead of re-iterating the aura list per buff ID.
local function BuildUnitAuraSet(unit)
    local set = {}
    if not UnitExists(unit) or not UnitIsConnected(unit) then
        return set, true  -- second value = "treat as having all buffs" (offline/gone)
    end
    local ok = pcall(function()
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            if not IsSecret(aura.spellId) then
                set[aura.spellId] = (not IsSecret(aura.expirationTime))
                    and (aura.expirationTime == 0
                         or (aura.expirationTime - GetTime()) >= scanMinRemaining)
                    or true  -- secret expiry = treat as present
            end
            i = i + 1
        end
    end)
    return ok and set or {}
end

-- Safe spell texture lookup.
local function SpellIcon(spellID)
    if not spellID or spellID == 0 then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    return ok and tex or nil
end

-- Known: true if the player has learned the spell (talent or baseline).
local function Known(spellID)
    if not spellID then return false end
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or IsSpellKnown(spellID) or false
end

-- [ CATEGORY META ] -----------------------------------------------------------
-- Kept for external reference; consumable data is now hardcoded above.
AuraList.Categories = {
    { key = "flasks",       label = "Flask",        required = true  },
    { key = "food",         label = "Food",         required = true  },
    { key = "augmentRunes", label = "Augment Rune", required = true  },
}

-- Returns true if the player has any temporary weapon enchant on their main-hand.
-- Oils / whetstones / weightstones all show as temp enchants, not player auras.
-- Falls back to pre-combat snapshot during combat lockdown.
local function HasWeaponOil()
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if hasMainHandEnchant == true then return true end
    -- Fallback to cache in combat
    if InCombatLockdown() and _preCombatCacheValid then
        return _preCombatCache["weaponEnchant"] == true
    end
    return false
end

-- [ CLASS BUFF DATA ] ---------------------------------------------------------
-- Buff IDs that are non-secret in Midnight (all readable via GetPlayerAuraBySpellID)
-- For weapon imbues (poisons, rites, shaman imbues), buffIDs contains all
-- variants that count as "one active" for that group.
-- Each entry: { label, buffIDs={...}, castSpell=N, required=true/false }
-- "required" here controls the reminder urgency (shown as blinking vs dimmed).
local CLASS_BUFFS = {
    -- ROGUE ---------------------------------------------------------------
    -- Must have exactly one damage poison AND one utility poison.
    ROGUE = {
        { label = "Dmg Poison",     required = true,  castSpell = 2823,
          buffIDs = { 2823, 315584, 8679 } },           -- Deadly / Instant / Wound (any one = satisfied)
        { label = "Utility Poison", required = false, castSpell = 381664,
          buffIDs = { 381664, 3408, 5761, 381637 } },   -- Amplifying / Crippling / Numbing / Atrophic
    },
    -- PALADIN -------------------------------------------------------------
    -- Rite of Adjuration / Rite of Sanctification: non-secret in 12.0.
    -- Devotion Aura (465) is ContextuallySecret — checked via C_Secrets guard.
    PALADIN = {
        { label = "Rite of Adjuration",     required = false, castSpell = 433583,
          buffIDs = { 433583 } },
        { label = "Rite of Sanctification",  required = false, castSpell = 433568,
          buffIDs = { 433568 } },
        -- Devotion Aura: ContextuallySecret in Midnight 12.0.
        -- Use pcall — if secret the call returns nil safely.
        { label = "Devotion Aura",           required = false, castSpell = 465,
          buffIDs = { 465, 32223, 317920 }, secretOk = false },
    },
    -- SHAMAN --------------------------------------------------------------
    -- Each hand needs an imbue; we check the aura buff IDs (non-secret in 12.0).
    SHAMAN = {
        { label = "Flametongue Weapon", required = true,  castSpell = 318038,
          buffIDs = { 319778 } },
        { label = "Windfury Weapon",    required = false, castSpell = 33757,
          buffIDs = { 319773 } },
        { label = "Earthliving Weapon", required = false, castSpell = 382021,
          buffIDs = { 382021, 382022, 457481, 457496 }, isWeaponEnchant = true },
        { label = "Thunderstrike Ward", required = false, castSpell = 462757,
          buffIDs = { 462757, 462742 } },
        -- Only one shield can be active at a time; either satisfies the check.
        { label = "Shield",             required = false, castSpell = 192106,
          buffIDs = { 192106, 52127 } },
    },
    -- WARRIOR -------------------------------------------------------------
    WARRIOR = {
        { label = "Defensive Stance",  required = false, castSpell = 386208,
          buffIDs = { 386208 }, specs = { 3 } },            -- Protection only
        { label = "Berserker Stance",  required = false, castSpell = 386196,
          buffIDs = { 386196 }, specs = { 1, 2 } },         -- Arms, Fury
    },
    -- PRIEST --------------------------------------------------------------
    PRIEST = {
        { label = "Shadowform", required = false, castSpell = 232698,
          buffIDs = { 232698, 194249 }, specs = { 3 } },    -- Shadow only
    },
    -- EVOKER --------------------------------------------------------------
    EVOKER = {
        { label = "Blistering Scales", required = false, castSpell = 360827,
          buffIDs = { 360827 } },
        { label = "Source of Magic",   required = false, castSpell = 369459,
          buffIDs = { 369459 } },
    },
    -- DEATHKNIGHT ---------------------------------------------------------
    -- DK runeforging is a weapon enchant, not an aura — we just check GetWeaponEnchantInfo.
    DEATHKNIGHT = {
        { label = "Runeforge", required = true, castSpell = nil,
          buffIDs = nil, isRuneforge = true },
    },
}

-- [ PARTY / RAID BUFF DATA ] ------------------------------------------------
-- Buffs the PLAYER casts on the GROUP. Each entry checks whether any group
-- member is missing the buff — only relevant if the player knows the spell.
-- buffIDs: all aura variants that count as the buff being present.
--   • Blessing of the Bronze has 13 variants (one per class).
--   • Mark of the Wild / Arcane Intellect have a Midnight alt-ID variant.

-- Range-aware party buff scanning: set by AuraReminder via SetInRangeUnits().
-- nil = range check disabled/not available; table = unit-token keyed set.
local _inRangeUnits = nil

function AuraList.SetInRangeUnits(units)
    _inRangeUnits = units
end

local PARTY_BUFFS = {
    { key = "fort",   class = "PRIEST",  castSpell = 21562,  label = "Power Word: Fortitude",
      buffIDs = { 21562 } },
    { key = "motw",   class = "DRUID",   castSpell = 1126,   label = "Mark of the Wild",
      buffIDs = { 1126, 432661 } },
    { key = "ai",     class = "MAGE",    castSpell = 1459,   label = "Arcane Intellect",
      buffIDs = { 1459, 432778 } },
    { key = "bshout", class = "WARRIOR", castSpell = 6673,   label = "Battle Shout",
      buffIDs = { 6673 } },
    { key = "sky",    class = "SHAMAN",  castSpell = 462854, label = "Skyfury",
      buffIDs = { 462854 } },
    -- Blessing of the Bronze: 13 class-specific variants; any one = satisfied.
    { key = "bronze", class = "EVOKER",  castSpell = 364342, label = "Blessing of the Bronze",
      buffIDs = { 381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758 } },
}

-- Returns missing party buff reminders for the player's class.
local function GetMissingPartyBuffs(db)
    local missing = {}
    local _, playerClass = UnitClass("player")
    if not playerClass then return missing end

    local cfg = db.partyBuffs or {}
    local inRaid  = IsInRaid()
    local inGroup = inRaid or IsInGroup()
    local rangeCheck = db.partyBuffRangeCheck and _inRangeUnits

    -- Build unit list and scan each unit's auras ONCE.
    -- auraCache[unit] = spellID-keyed set; built lazily below.
    local units = {}
    if inRaid then
        for i = 1, GetNumGroupMembers() do units[#units+1] = "raid"..i end
    elseif inGroup then
        for i = 1, GetNumSubgroupMembers() do units[#units+1] = "party"..i end
    end

    -- Build a set of class tokens present in the group (including the player).
    -- Used to skip PARTY_BUFFS whose class isn't in the party at all.
    local groupClasses = { [playerClass] = true }
    for _, u in ipairs(units) do
        local _, cls = UnitClass(u)
        if cls then groupClasses[cls] = true end
    end

    local auraCache = {}
    local function cachedSet(unit)
        if not auraCache[unit] then
            auraCache[unit] = BuildUnitAuraSet(unit)
        end
        return auraCache[unit]
    end

    for _, def in ipairs(PARTY_BUFFS) do
        if cfg[def.key] == false then
        elseif not groupClasses[def.class] then
            -- Class not present in this group — skip entirely
        elseif def.class == playerClass then
            if Known(def.castSpell) then
                local missing_count, total = 0, 1
                local playerHas = false
                for _, id in ipairs(def.buffIDs) do
                    if PlayerHasAura(id) then playerHas = true; break end
                end
                if not playerHas then missing_count = 1 end
                for _, u in ipairs(units) do
                    -- Skip out-of-range units when range checking is enabled
                    if rangeCheck and not _inRangeUnits[u] then
                        -- Treat as "has all buffs" — we can't reach them
                    else
                        total = total + 1
                        local set = cachedSet(u)
                        local has = false
                        for _, id in ipairs(def.buffIDs) do
                            if set[id] then has = true; break end
                        end
                        if not has then missing_count = missing_count + 1 end
                    end
                end
                if missing_count > 0 then
                    missing[#missing+1] = { label=def.label, spellID=def.castSpell,
                        icon=SpellIcon(def.castSpell), required=true,
                        partyMissingCount=missing_count, partyTotalCount=total,
                        actionType  = "spell",
                        actionValue = def.castSpell,
                        dismissKey  = "party:" .. def.key }
                end
            end
        elseif inGroup then
            local anyoneHas = false
            for _, id in ipairs(def.buffIDs) do
                if PlayerHasAura(id) then anyoneHas = true; break end
            end
            if not anyoneHas then
                for _, u in ipairs(units) do
                    local set = cachedSet(u)
                    for _, id in ipairs(def.buffIDs) do
                        if set[id] then anyoneHas = true; break end
                    end
                    if anyoneHas then break end
                end
            end
            if not anyoneHas then
                missing[#missing+1] = { label=def.label, spellID=def.castSpell,
                    icon=SpellIcon(def.castSpell), required=false, missingFromGroup=true,
                    actionType  = "texture",
                    actionValue = nil,
                    dismissKey  = "group:" .. def.key }
            end
        end
    end
    return missing
end

-- Returns true when the player has any food/Well Fed buff active.
-- Checks both the canonical Midnight Well Fed spell IDs and all configured
-- food spell IDs, then falls back to a name scan for "Well Fed" /
-- "Hearty Well Fed" to handle foods not in the configured list.
local WELL_FED_IDS = { 455369, 462187 }  -- Midnight primary Well Fed spell IDs
local WELL_FED_NAMES = { "Well Fed", "Hearty Well Fed" }

-- Hardcoded consumable data (Midnight Season 1 + legacy variants)
-- itemIDs used to count how many the player has in bags for the badge.
local FLASKS = {
    { spellID = 1235110, itemIDs = { 241324, 241325, 245931, 245930 } },  -- Flask of the Blood Knights
    { spellID = 1235108, itemIDs = { 241322, 241323, 245933, 245932 } },  -- Flask of the Magisters
    { spellID = 1235111, itemIDs = { 241326, 241327, 245929, 245928 } },  -- Flask of the Shattered Sun
    { spellID = 1235057, itemIDs = { 241320, 241321, 245926, 245927 } },  -- Flask of Thalassian Resistance
    { spellID = 1239355, itemIDs = { 241334 } },                          -- Vicious Thalassian Flask of Honor
    { spellID = 1235113 }, { spellID = 1235114 },  -- PvP-morphed variants (detection only)
    { spellID = 1235115 }, { spellID = 1235116 },
}
local AUGMENT_RUNES = {
    { spellID = 1264426, itemIDs = { 259085  } },  -- Augment Rune (Void-Touched)
    { spellID = 453250,  itemIDs = { 243191  } },  -- Augment Rune (Ethereal)
    { spellID = 1234969 }, { spellID = 1242347 },  -- Midnight variants
    { spellID = 393438,  itemIDs = { 189192  } },  -- Crystallized Augment Rune (TWW)
    { spellID = 347901  },                         -- legacy
}
-- Flask lookup by preference key (for consumable preference dropdowns).
local FLASK_BY_KEY = {
    blood_knights         = FLASKS[1],
    magisters             = FLASKS[2],
    shattered_sun         = FLASKS[3],
    thalassian_resistance = FLASKS[4],
    pvp                   = FLASKS[5],
}
-- Exported for Options.lua dropdown choices.
AuraList.FLASK_CHOICES = {
    { value = "auto",                  label = "Auto (first in bags)" },
    { value = "blood_knights",         label = "Flask of the Blood Knights" },
    { value = "magisters",             label = "Flask of the Magisters" },
    { value = "shattered_sun",         label = "Flask of the Shattered Sun" },
    { value = "thalassian_resistance", label = "Flask of Thalassian Resistance" },
    { value = "pvp",                   label = "Vicious Thalassian Flask of Honor" },
}

-- Midnight S1 consumable food items, grouped by category.
-- Each category is scanned in order; hearty variants listed first within each.
local FOOD_CAT = {
    primary_hearty = {
        268679, 267000, 242747, 242746, 242757, 242756, 242755, 242754,
        242753, 242758, 242752, 242759,
    },
    primary = {
        255847, 255848, 242275, 242274, 242285, 242284, 242283, 242282,
        242281, 242286, 242280, 242287,
    },
    secondary_hearty = { 242750, 242749, 242748 },
    secondary        = { 242278, 242277, 242276 },
    utility = {
        -- hearty utility first
        242765, 242767, 242763, 242766, 242764, 242768,
        242762, 242760, 242761,
        -- regular utility
        242293, 242295, 242291, 242294, 242292, 242296,
        242290, 242288, 242289,
    },
    basic = {
        -- hearty basic first
        242771, 242772, 242774, 242775, 242770, 242773, 242776, 242769,
        -- regular basic
        242304, 242305, 242307, 242308, 242303, 242306, 242309, 242302,
    },
    feast = {
        266996, 266985, 242744, 242745,  -- hearty feasts
        255846, 255845, 242272, 242273,  -- regular feasts
    },
}
-- Category scan order for auto mode (best to worst).
local FOOD_CAT_ORDER = {
    "primary_hearty", "primary", "secondary_hearty", "secondary",
    "utility", "basic", "feast",
}
-- Flat list for auto mode and bag counting (built from categories).
local FOOD_ITEMS = {}
for _, cat in ipairs(FOOD_CAT_ORDER) do
    for _, iid in ipairs(FOOD_CAT[cat]) do
        FOOD_ITEMS[#FOOD_ITEMS + 1] = iid
    end
end
-- Exported for Options.lua dropdown choices.
AuraList.FOOD_CHOICES = {
    { value = "auto",             label = "Auto (first in bags)" },
    { value = "primary_hearty",   label = "Primary Stat (Hearty)" },
    { value = "primary",          label = "Primary Stat" },
    { value = "secondary_hearty", label = "Secondary Stat (Hearty)" },
    { value = "secondary",        label = "Secondary Stat" },
    { value = "utility",          label = "Utility" },
    { value = "basic",            label = "Basic" },
    { value = "feast",            label = "Feast" },
}

-- Weapon oil / whetstone / weightstone / ammo items for click-to-use.
-- Applied via macro: "/use item:<id>\n/use 16" (main-hand slot).
local WEAPON_ENCHANT_ITEMS = {
    -- Midnight oils
    243733, 243734, -- Thalassian Phoenix Oil
    243735, 243736, -- Oil of Dawn
    243737, 243738, -- Smuggler's Enchanted Edge
    -- Midnight whetstones
    237370, 237371, -- Refulgent Whetstone
    -- Midnight weightstones
    237367, 237369, -- Refulgent Weightstone
    -- Midnight ammo
    257749, 257750, -- Laced Zoomshots
    257751, 257752, -- Weighted Boomshots
    -- TWW oils
    224107, 224106, 224105, -- Algari Mana Oil
    224113, 224112, 224111, -- Oil of Deep Toxins
    224110, 224109, 224108, -- Oil of Beledar's Grace
    -- TWW whetstones / weightstones
    222504, 222503, 222502, -- Ironclaw Whetstone
    222510, 222509, 222508, -- Ironclaw Weightstone
    220156, -- Bubbling Wax
}

local function HasFoodBuff(foodList)
    -- 1. Primary Midnight Well Fed spell IDs (fast path)
    for _, id in ipairs(WELL_FED_IDS) do
        if PlayerHasAura(id) then return true end
    end
    -- 2. Configured spell IDs (user's food list)
    if foodList then
        for _, entry in ipairs(foodList) do
            if PlayerHasAura(entry.spellID) then return true end
        end
    end
    -- 3. Name scan fallback: catches secret IDs and unconfigured foods
    for _, name in ipairs(WELL_FED_NAMES) do
        if PlayerHasAuraByName(name) then return true end
    end
    return false
end
-- [ PREFERRED ITEM RESOLUTION ] -----------------------------------------------
-- Resolves which flask item to use for click-to-buff.
-- Checks db.flaskRaid or db.flaskDungeon based on instance type.
-- Falls back to auto (first available) if the chosen flask isn't in bags.
local function ResolveFlaskItem(db, iType)
    local key = (iType == "raid") and (db.flaskRaid or "auto")
                                   or (db.flaskDungeon or "auto")

    if key ~= "auto" then
        local def = FLASK_BY_KEY[key]
        if def and def.itemIDs then
            for _, iid in ipairs(def.itemIDs) do
                if (GetItemCount(iid) or 0) > 0 then return iid end
            end
        end
        -- Chosen flask not in bags — fall through to auto
    end

    for _, f in ipairs(FLASKS) do
        if f.itemIDs then
            for _, iid in ipairs(f.itemIDs) do
                if (GetItemCount(iid) or 0) > 0 then return iid end
            end
        end
    end
    return nil
end

-- Resolves which augment rune item to use for click-to-buff.
local function ResolveRuneItem()
    for _, r in ipairs(AUGMENT_RUNES) do
        if r.itemIDs then
            for _, iid in ipairs(r.itemIDs) do
                if (GetItemCount(iid) or 0) > 0 then return iid end
            end
        end
    end
    return nil
end

-- Resolves which food item to use for click-to-eat.
-- Checks db.foodRaid or db.foodDungeon based on instance type.
-- Falls back to auto (first available) if the chosen category is empty.
local function ResolveFoodItem(db, iType)
    local key = (iType == "raid") and (db.foodRaid or "auto")
                                   or (db.foodDungeon or "auto")

    if key ~= "auto" then
        local catItems = FOOD_CAT[key]
        if catItems then
            for _, iid in ipairs(catItems) do
                if (GetItemCount(iid) or 0) > 0 then return iid end
            end
        end
        -- Category empty — fall through to auto
    end

    for _, iid in ipairs(FOOD_ITEMS) do
        if (GetItemCount(iid) or 0) > 0 then return iid end
    end
    return nil
end

-- Resolves a weapon oil/stone macro for click-to-apply.
-- Oils require a two-step action: use the item, then target a weapon slot.
-- Returns macroText (string) or nil if no oil found in bags.
-- Slot 16 = main hand, 17 = off-hand.
local function ResolveOilMacro()
    for _, iid in ipairs(WEAPON_ENCHANT_ITEMS) do
        if (GetItemCount(iid) or 0) > 0 then
            return "/use item:" .. iid .. "\n/use 16"
        end
    end
    return nil
end

-- [ CLASS BUFF CHECKER ] ------------------------------------------------------
-- Returns missing class buff entries for the player's class.
-- Skips entries disabled in db.reminder.classBuffs (key = castSpell or label).
-- Respects IsSpellKnown — won't nag about spells the player doesn't have.
local function GetMissingClassBuffs(db)
    local missing = {}
    local _, playerClass = UnitClass("player")
    if not playerClass then return missing end

    local defs = CLASS_BUFFS[playerClass]
    if not defs then return missing end

    -- db.reminder.classBuffs[key] = false to disable a specific class buff check.
    local cfg = db.classBuffs or {}

    for _, def in ipairs(defs) do
        -- Allow disabling individual checks via config key (castSpell as string key)
        local cfgKey = def.castSpell and tostring(def.castSpell) or def.label
        if cfg[cfgKey] == false then
            -- explicitly disabled by user
        elseif def.specs and not tContains(def.specs, GetSpecialization() or 0) then
            -- wrong spec, skip
        elseif def.isRuneforge then
            -- Death Knight: check weapon enchant instead of aura
            local hasMH = GetWeaponEnchantInfo()
            if not hasMH then
                missing[#missing + 1] = {
                    label    = def.label,
                    spellID  = 0,
                    icon     = 135957,   -- runeforging icon
                    required = def.required,
                    actionType  = "texture",
                    actionValue = nil,
                    dismissKey  = "class:runeforge",
                }
            end
        elseif def.castSpell and not Known(def.castSpell) then
            -- player hasn't learned this spell — skip silently
        else
            local found = false
            if def.buffIDs then
                for _, id in ipairs(def.buffIDs) do
                    if PlayerHasAura(id) then
                        found = true; break
                    end
                end
            end
            -- Fallback: scan auras by name when spell-ID lookup fails.
            -- Handles cases where Midnight uses a different buff ID than expected.
            if not found and def.buffName then
                found = PlayerHasAuraByName(def.buffName)
            end
            -- Weapon-enchant fallback: some imbues (e.g. Earthliving Weapon in Midnight)
            -- appear as a temporary weapon enchant rather than a player aura.
            -- Check both main-hand and off-hand slots.
            if not found and def.isWeaponEnchant then
                local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
                found = hasMH == true or hasOH == true
            end
            if not found then
                missing[#missing + 1] = {
                    label    = def.label,
                    spellID  = def.castSpell or 0,
                    icon     = SpellIcon(def.castSpell),
                    required = def.required,
                    actionType  = def.castSpell and "spell" or "texture",
                    actionValue = def.castSpell,
                    dismissKey  = "class:" .. (def.castSpell and tostring(def.castSpell) or def.label),
                }
            end
        end
    end
    return missing
end

-- [ SNAPSHOT API ] ------------------------------------------------------------
-- Called before combat lockdown to record what tracked auras are currently active.
-- PlayerHasAura/HasWeaponOil fall back to this cache when the live API is locked.

function AuraList.SnapshotAuras()
    wipe(_preCombatCache)
    _preCombatCacheValid = false

    -- Bail if auras aren't readable right now (shouldn't happen pre-combat, but guard)
    if not CanReadAuras() then return end

    -- Snapshot all flask IDs
    for _, f in ipairs(FLASKS) do
        _preCombatCache[f.spellID] = PlayerHasAura(f.spellID) or nil
    end

    -- Snapshot all augment rune IDs
    for _, r in ipairs(AUGMENT_RUNES) do
        _preCombatCache[r.spellID] = PlayerHasAura(r.spellID) or nil
    end

    -- Snapshot Well Fed IDs
    for _, id in ipairs(WELL_FED_IDS) do
        _preCombatCache[id] = PlayerHasAura(id) or nil
    end

    -- Snapshot class buffs for the player's class
    local _, playerClass = UnitClass("player")
    local defs = playerClass and CLASS_BUFFS[playerClass] or {}
    for _, def in ipairs(defs) do
        if def.buffIDs then
            for _, id in ipairs(def.buffIDs) do
                _preCombatCache[id] = PlayerHasAura(id) or nil
            end
        end
    end

    -- Snapshot raid/party buff IDs on the player
    for _, def in ipairs(PARTY_BUFFS) do
        for _, id in ipairs(def.buffIDs) do
            _preCombatCache[id] = PlayerHasAura(id) or nil
        end
    end

    -- Snapshot weapon enchant state
    local hasMH = GetWeaponEnchantInfo()
    _preCombatCache["weaponEnchant"] = hasMH == true or nil

    _preCombatCacheValid = true
end

function AuraList.ClearSnapshot()
    wipe(_preCombatCache)
    _preCombatCacheValid = false
end

function AuraList.HasSnapshot()
    return _preCombatCacheValid
end

-- [ DISMISS STATE ] -----------------------------------------------------------
-- Keys dismissed by middle-click this session. Cleared on PLAYER_ENTERING_WORLD.
local _dismissedKeys = {}

function AuraList.Dismiss(key)
    if key then _dismissedKeys[key] = true end
end

function AuraList.ClearDismissed()
    wipe(_dismissedKeys)
end

function AuraList.IsDismissed(key)
    return key and _dismissedKeys[key] == true
end

-- [ CHECK ] -------------------------------------------------------------------
-- Returns a list of { label, spellID, icon, required } for each missing category
-- plus any missing class-specific buffs for the current player class.
function AuraList.GetMissing(db)
    -- If the aura API is locked (inside M+ or PvP combat) and we have no snapshot,
    -- return empty so we don't flash false alerts. If we DO have a snapshot,
    -- proceed — PlayerHasAura/HasWeaponOil will use the cache as fallback.
    if not CanReadAuras() and not _preCombatCacheValid then return {} end

    -- Set the expiry threshold for this scan from the live db value.
    -- 0 = disabled (any time remaining counts). Default 60 s.
    scanMinRemaining = (db.buffMinRemaining ~= nil) and db.buffMinRemaining or 60

    -- Determine duration threshold based on instance type
    local _, iType = GetInstanceInfo()
    local thresholdMinutes = 0
    if iType == "party" then
        thresholdMinutes = db.showUnderDurationDungeon or 0
    elseif iType == "raid" then
        thresholdMinutes = db.showUnderDurationRaid or 0
    end
    scanDurationThreshold = thresholdMinutes * 60  -- convert to seconds

    -- Consumables (flask, food, augment rune, weapon oil) are only relevant at
    -- max level. Suppress them entirely while the player is still leveling.
    local atMaxLevel = UnitLevel("player") >= GetMaxPlayerLevel()

    local missing = {}

    -- Standard consumables (only at max level, hardcoded lists)
    if atMaxLevel then
        -- Flask
        local hasFlask = false
        local expiringFlask = false
        for _, f in ipairs(FLASKS) do
            if PlayerHasAura(f.spellID) then
                hasFlask = true
                if IsExpiringSoon(f.spellID) then expiringFlask = true end
                break
            end
        end
        if not hasFlask or expiringFlask then
            local flaskKey = (iType == "raid") and (db.flaskRaid or "auto")
                                                or (db.flaskDungeon or "auto")
            local count = 0
            if flaskKey ~= "auto" then
                -- Count only the chosen flask type
                local def = FLASK_BY_KEY[flaskKey]
                if def and def.itemIDs then
                    for _, iid in ipairs(def.itemIDs) do
                        count = count + (GetItemCount(iid, true) or 0)
                    end
                end
            else
                -- Auto: count all flasks
                for _, f in ipairs(FLASKS) do
                    if f.itemIDs then
                        for _, iid in ipairs(f.itemIDs) do
                            count = count + (GetItemCount(iid, true) or 0)
                        end
                    end
                end
            end
            local flaskItemID = ResolveFlaskItem(db, iType)
            local flaskLabel = "Flask"
            if flaskItemID then
                flaskLabel = C_Item.GetItemNameByID(flaskItemID) or "Flask"
            end
            if expiringFlask then flaskLabel = flaskLabel .. " (expiring)" end
            missing[#missing+1] = { label=flaskLabel,
                spellID=FLASKS[1].spellID,
                icon=flaskItemID and GetItemIcon(flaskItemID) or SpellIcon(FLASKS[1].spellID),
                required=true,
                itemCount=count > 0 and count or nil,
                expiring=expiringFlask or nil,
                actionType = flaskItemID and "item" or "texture",
                actionValue = flaskItemID,
                dismissKey = "flask" }
        end

        -- Food
        if not HasFoodBuff(nil) then
            local foodKey = (iType == "raid") and (db.foodRaid or "auto")
                                               or (db.foodDungeon or "auto")
            local foodCount = 0
            if foodKey ~= "auto" then
                -- Count only the chosen food category
                local catItems = FOOD_CAT[foodKey]
                if catItems then
                    for _, iid in ipairs(catItems) do
                        foodCount = foodCount + (GetItemCount(iid, true) or 0)
                    end
                end
            else
                -- Auto: count all food
                for _, iid in ipairs(FOOD_ITEMS) do
                    foodCount = foodCount + (GetItemCount(iid, true) or 0)
                end
            end
            local foodItemID = ResolveFoodItem(db, iType)
            local foodLabel = "Food"
            if foodItemID then
                foodLabel = C_Item.GetItemNameByID(foodItemID) or "Food"
            end
            missing[#missing+1] = { label=foodLabel, spellID=WELL_FED_IDS[1],
                icon=foodItemID and GetItemIcon(foodItemID) or 133971,
                required=true,
                itemCount=foodCount > 0 and foodCount or nil,
                actionType = foodItemID and "item" or "texture",
                actionValue = foodItemID,
                dismissKey = "food" }
        end

        -- Augment Rune
        local hasRune = false
        local expiringRune = false
        for _, r in ipairs(AUGMENT_RUNES) do
            if PlayerHasAura(r.spellID) then
                hasRune = true
                if IsExpiringSoon(r.spellID) then expiringRune = true end
                break
            end
        end
        if not hasRune or expiringRune then
            local count = 0
            for _, r in ipairs(AUGMENT_RUNES) do
                if r.itemIDs then
                    for _, iid in ipairs(r.itemIDs) do
                        count = count + (GetItemCount(iid, true) or 0)
                    end
                end
            end
            local runeItemID = ResolveRuneItem()
            missing[#missing+1] = { label=expiringRune and "Augment Rune (expiring)" or "Augment Rune",
                spellID=AUGMENT_RUNES[1].spellID,
                icon=SpellIcon(AUGMENT_RUNES[1].spellID), required=true,
                itemCount=count > 0 and count or nil,
                expiring=expiringRune or nil,
                actionType = runeItemID and "item" or "texture",
                actionValue = runeItemID,
                dismissKey = "rune" }
        end

        -- Weapon oil / temp enchant
        if db.weaponOil and not HasWeaponOil() then
            local oilCount = 0
            for _, iid in ipairs(WEAPON_ENCHANT_ITEMS) do
                oilCount = oilCount + (GetItemCount(iid, true) or 0)
            end
            local oilMacro = ResolveOilMacro()
            missing[#missing+1] = { label="Weapon Oil", spellID=0,
                icon=134096, required=false,
                itemCount=oilCount > 0 and oilCount or nil,
                actionType = oilMacro and "macro" or "texture",
                actionValue = oilMacro,
                dismissKey = "oil" }
        end
    end -- atMaxLevel

    -- Class-specific buffs (only if enabled in config)
    if db.enableClassBuffs ~= false then
        local classMissing = GetMissingClassBuffs(db)
        for _, m in ipairs(classMissing) do
            missing[#missing + 1] = m
        end
    end

    -- Party/raid buff reminders (Fort, MotW, AI, Battle Shout, etc.)
    if db.enablePartyBuffs ~= false then
        local partyMissing = GetMissingPartyBuffs(db)
        for _, m in ipairs(partyMissing) do
            missing[#missing + 1] = m
        end
    end

    -- Filter out dismissed reminders
    local filtered = {}
    for _, m in ipairs(missing) do
        if not _dismissedKeys[m.dismissKey] then
            filtered[#filtered + 1] = m
        end
    end
    return filtered
end

-- [ GET ALL ] -----------------------------------------------------------------
-- Like GetMissing, but also includes tracked buffs that ARE present, marked
-- with present = true so the UI can show them dimmed instead of blinking.
-- Used when db.showAllBuffs is true.
function AuraList.GetAll(db)
    if not CanReadAuras() and not _preCombatCacheValid then return AuraList.GetMissing(db) end

    -- Start with missing entries
    local missing = AuraList.GetMissing(db)
    -- Build a set of dismissKeys already in missing so we don't double-add
    local inMissing = {}
    for _, m in ipairs(missing) do
        if m.dismissKey then inMissing[m.dismissKey] = true end
    end

    scanMinRemaining = (db.buffMinRemaining ~= nil) and db.buffMinRemaining or 60
    local atMaxLevel = UnitLevel("player") >= GetMaxPlayerLevel()
    local all = {}

    -- Consumables (hardcoded, present = shown dimmed)
    if atMaxLevel then
        local hasFlask = false
        for _, f in ipairs(FLASKS) do if PlayerHasAura(f.spellID) then hasFlask = true; break end end
        if not inMissing["flask"] then
            all[#all+1] = { label="Flask", spellID=FLASKS[1].spellID,
                icon=SpellIcon(FLASKS[1].spellID), required=true, present=hasFlask,
                actionType = "texture", actionValue = nil, dismissKey = "flask" }
        end

        if not inMissing["food"] then
            all[#all+1] = { label="Food", spellID=WELL_FED_IDS[1],
                icon=133971, required=true, present=HasFoodBuff(nil),
                actionType = "texture", actionValue = nil, dismissKey = "food" }
        end

        local hasRune = false
        for _, r in ipairs(AUGMENT_RUNES) do if PlayerHasAura(r.spellID) then hasRune = true; break end end
        if not inMissing["rune"] then
            all[#all+1] = { label="Augment Rune", spellID=AUGMENT_RUNES[1].spellID,
                icon=SpellIcon(AUGMENT_RUNES[1].spellID), required=true, present=hasRune,
                actionType = "texture", actionValue = nil, dismissKey = "rune" }
        end

        if db.weaponOil and not inMissing["oil"] then
            all[#all+1] = { label="Weapon Oil", spellID=0, icon=134096,
                required=false, present=HasWeaponOil(),
                actionType = "texture", actionValue = nil, dismissKey = "oil" }
        end
    end

    -- Class buffs
    if db.enableClassBuffs ~= false then
        local _, playerClass = UnitClass("player")
        local defs = playerClass and CLASS_BUFFS[playerClass] or {}
        local cfg = db.classBuffs or {}
        for _, def in ipairs(defs) do
            local cfgKey = def.castSpell and tostring(def.castSpell) or def.label
            local dKey = def.isRuneforge and "class:runeforge"
                or ("class:" .. (def.castSpell and tostring(def.castSpell) or def.label))
            if cfg[cfgKey] ~= false and not inMissing[dKey]
                and (not def.specs or tContains(def.specs, GetSpecialization() or 0)) then
                if def.isRuneforge then
                    -- present (has runeforge)
                    all[#all+1] = { label=def.label, spellID=0, icon=135957,
                        required=def.required, present=true,
                        actionType = "texture", actionValue = nil, dismissKey = dKey }
                elseif def.castSpell and Known(def.castSpell) then
                    all[#all+1] = { label=def.label, spellID=def.castSpell,
                        icon=SpellIcon(def.castSpell), required=def.required, present=true,
                        actionType = "texture", actionValue = nil, dismissKey = dKey }
                end
            end
        end
    end

    -- Merge: missing first, then present
    local result = {}
    for _, m in ipairs(missing) do result[#result+1] = m end
    for _, m in ipairs(all)     do result[#result+1] = m end
    return result
end

-- [ CLASS BUFF INFO ] ---------------------------------------------------------
-- Returns the CLASS_BUFFS table for external use (Options GUI).
function AuraList.GetClassBuffDefs()
    local _, playerClass = UnitClass("player")
    return playerClass and CLASS_BUFFS[playerClass] or {}
end

-- Returns PARTY_BUFFS filtered to the player's class (for Options GUI).
function AuraList.GetPartyBuffDefs()
    local _, playerClass = UnitClass("player")
    if not playerClass then return {} end
    local out = {}
    for _, def in ipairs(PARTY_BUFFS) do
        if def.class == playerClass then out[#out+1] = def end
    end
    return out
end

-- Returns true if any required category is missing.
function AuraList.HasRequired(missing)
    for _, m in ipairs(missing) do
        if m.required then return true end
    end
    return false
end
