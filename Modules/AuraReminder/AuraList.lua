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

-- Minimum seconds remaining for a buff to count as "present".
-- Set by GetMissing() from db.reminder.buffMinRemaining before each scan.
-- Default 60 s is used when helpers are called outside of a scan context.
local scanMinRemaining = 60

-- Safe player aura query.
-- Returns true only if the buff is present AND has meaningful time remaining.
-- expirationTime == 0 means permanent (no expiry) — always counts.
local function PlayerHasAura(spellID)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or aura == nil then return false end
    -- Guard the spellId field itself against tainting
    if IsSecret(aura.spellId) then return false end
    -- Check expiry — guard the expirationTime field too
    if IsSecret(aura.expirationTime) then return true end  -- secret expiry = treat as permanent
    if aura.expirationTime == 0 then return true end       -- permanent buff
    return (aura.expirationTime - GetTime()) >= scanMinRemaining
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
local function HasWeaponOil()
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    return hasMainHandEnchant == true
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
          buffIDs = { 386208 } },
        { label = "Berserker Stance",  required = false, castSpell = 386196,
          buffIDs = { 386196 } },
    },
    -- PRIEST --------------------------------------------------------------
    PRIEST = {
        { label = "Shadowform", required = false, castSpell = 232698,
          buffIDs = { 232698, 194249 } },
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
                    total = total + 1
                    local set = cachedSet(u)
                    local has = false
                    for _, id in ipairs(def.buffIDs) do
                        if set[id] then has = true; break end
                    end
                    if not has then missing_count = missing_count + 1 end
                end
                if missing_count > 0 then
                    missing[#missing+1] = { label=def.label, spellID=def.castSpell,
                        icon=SpellIcon(def.castSpell), required=true,
                        partyMissingCount=missing_count, partyTotalCount=total }
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
                    icon=SpellIcon(def.castSpell), required=false, missingFromGroup=true }
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
    { spellID = 1235110, itemIDs = { 243682 } },  -- Flask of the Blood Knights
    { spellID = 1235108, itemIDs = { 243680 } },  -- Flask of the Magisters
    { spellID = 1235111, itemIDs = { 243683 } },  -- Flask of the Shattered Sun
    { spellID = 1235057, itemIDs = { 243695 } },  -- Flask of Thalassian Resistance
    { spellID = 1239355, itemIDs = { 243697 } },  -- Vicious Thalassian Flask of Honor
    { spellID = 1235113 }, { spellID = 1235114 },  -- PvP-morphed variants
    { spellID = 1235115 }, { spellID = 1235116 },
}
local AUGMENT_RUNES = {
    { spellID = 1264426, itemIDs = { 259085  } },  -- Augment Rune (Void-Touched)
    { spellID = 453250,  itemIDs = { 243191  } },  -- Augment Rune (Ethereal)
    { spellID = 1234969 }, { spellID = 1242347 },  -- Midnight variants
    { spellID = 393438,  itemIDs = { 189192  } },  -- Crystallized Augment Rune (TWW)
    { spellID = 347901  },                         -- legacy
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
        elseif def.isRuneforge then
            -- Death Knight: check weapon enchant instead of aura
            local hasMH = GetWeaponEnchantInfo()
            if not hasMH then
                missing[#missing + 1] = {
                    label    = def.label,
                    spellID  = 0,
                    icon     = 135957,   -- runeforging icon
                    required = def.required,
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
                }
            end
        end
    end
    return missing
end

-- [ CHECK ] -------------------------------------------------------------------
-- Returns a list of { label, spellID, icon, required } for each missing category
-- plus any missing class-specific buffs for the current player class.
function AuraList.GetMissing(db)
    -- If the aura API is locked (inside M+ or PvP combat) and the caller didn't
    -- already bail via onlyOutOfCombat, return empty so we don't flash false alerts.
    if not CanReadAuras() then return {} end

    -- Set the expiry threshold for this scan from the live db value.
    -- 0 = disabled (any time remaining counts). Default 60 s.
    scanMinRemaining = (db.buffMinRemaining ~= nil) and db.buffMinRemaining or 60

    -- Consumables (flask, food, augment rune, weapon oil) are only relevant at
    -- max level. Suppress them entirely while the player is still leveling.
    local atMaxLevel = UnitLevel("player") >= GetMaxPlayerLevel()

    local missing = {}

    -- Standard consumables (only at max level, hardcoded lists)
    if atMaxLevel then
        -- Flask
        local hasFlask = false
        for _, f in ipairs(FLASKS) do
            if PlayerHasAura(f.spellID) then hasFlask = true; break end
        end
        if not hasFlask then
            local count = 0
            for _, f in ipairs(FLASKS) do
                if f.itemIDs then
                    for _, iid in ipairs(f.itemIDs) do count = count + (GetItemCount(iid, true) or 0) end
                end
            end
            missing[#missing+1] = { label="Flask", spellID=FLASKS[1].spellID,
                icon=SpellIcon(FLASKS[1].spellID), required=true,
                itemCount=count > 0 and count or nil }
        end

        -- Food
        if not HasFoodBuff(nil) then
            missing[#missing+1] = { label="Food", spellID=WELL_FED_IDS[1],
                icon=133971, required=true }
        end

        -- Augment Rune
        local hasRune = false
        for _, r in ipairs(AUGMENT_RUNES) do
            if PlayerHasAura(r.spellID) then hasRune = true; break end
        end
        if not hasRune then
            local count = 0
            for _, r in ipairs(AUGMENT_RUNES) do
                if r.itemIDs then
                    for _, iid in ipairs(r.itemIDs) do count = count + (GetItemCount(iid, true) or 0) end
                end
            end
            missing[#missing+1] = { label="Augment Rune", spellID=AUGMENT_RUNES[1].spellID,
                icon=SpellIcon(AUGMENT_RUNES[1].spellID), required=true,
                itemCount=count > 0 and count or nil }
        end

        -- Weapon oil / temp enchant
        if db.weaponOil and not HasWeaponOil() then
            missing[#missing+1] = { label="Weapon Oil", spellID=0,
                icon=134096, required=false }
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

    return missing
end

-- [ GET ALL ] -----------------------------------------------------------------
-- Like GetMissing, but also includes tracked buffs that ARE present, marked
-- with present = true so the UI can show them dimmed instead of blinking.
-- Used when db.showAllBuffs is true.
function AuraList.GetAll(db)
    if not CanReadAuras() then return AuraList.GetMissing(db) end

    -- Start with missing entries
    local missing = AuraList.GetMissing(db)
    -- Build a set of labels already in missing so we don't double-add
    local inMissing = {}
    for _, m in ipairs(missing) do inMissing[m.label] = true end

    scanMinRemaining = (db.buffMinRemaining ~= nil) and db.buffMinRemaining or 60
    local atMaxLevel = UnitLevel("player") >= GetMaxPlayerLevel()
    local all = {}

    -- Consumables (hardcoded, present = shown dimmed)
    if atMaxLevel then
        local hasFlask = false
        for _, f in ipairs(FLASKS) do if PlayerHasAura(f.spellID) then hasFlask = true; break end end
        if not inMissing["Flask"] then
            all[#all+1] = { label="Flask", spellID=FLASKS[1].spellID,
                icon=SpellIcon(FLASKS[1].spellID), required=true, present=hasFlask }
        end

        if not inMissing["Food"] then
            all[#all+1] = { label="Food", spellID=WELL_FED_IDS[1],
                icon=133971, required=true, present=HasFoodBuff(nil) }
        end

        local hasRune = false
        for _, r in ipairs(AUGMENT_RUNES) do if PlayerHasAura(r.spellID) then hasRune = true; break end end
        if not inMissing["Augment Rune"] then
            all[#all+1] = { label="Augment Rune", spellID=AUGMENT_RUNES[1].spellID,
                icon=SpellIcon(AUGMENT_RUNES[1].spellID), required=true, present=hasRune }
        end

        if db.weaponOil and not inMissing["Weapon Oil"] then
            all[#all+1] = { label="Weapon Oil", spellID=0, icon=134096,
                required=false, present=HasWeaponOil() }
        end
    end

    -- Class buffs
    if db.enableClassBuffs ~= false then
        local _, playerClass = UnitClass("player")
        local defs = playerClass and CLASS_BUFFS[playerClass] or {}
        local cfg = db.classBuffs or {}
        for _, def in ipairs(defs) do
            local cfgKey = def.castSpell and tostring(def.castSpell) or def.label
            if cfg[cfgKey] ~= false and not inMissing[def.label] then
                if def.isRuneforge then
                    -- present (has runeforge)
                    all[#all+1] = { label=def.label, spellID=0, icon=135957,
                        required=def.required, present=true }
                elseif def.castSpell and Known(def.castSpell) then
                    all[#all+1] = { label=def.label, spellID=def.castSpell,
                        icon=SpellIcon(def.castSpell), required=def.required, present=true }
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
