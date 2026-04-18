local ADDON_NAME, ns = ...

-- [ INIT ] --------------------------------------------------------------------
local yaqol = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = yaqol
_G.yaqol = yaqol

function yaqol:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("yaqolDB", ns.Defaults, true)
    ns.Theme.Init()
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    -- Migrate: ensure spell list sub-tables exist for profiles created before they were added
    local r = self.db.profile.reminder
    for _, key in ipairs({"flasks","food","augmentRunes","weaponBuffs","custom","classBuffs","partyBuffs"}) do
        if not r[key] then r[key] = {} end
    end
    if r.enableClassBuffs == nil then r.enableClassBuffs = true end
    if r.enablePartyBuffs == nil then r.enablePartyBuffs = true end

    -- Migrate: new QOL settings added in v1.0.5
    local q = self.db.profile.qol
    if q.questSkipModifier == nil then q.questSkipModifier = "SHIFT" end
    if q.autoSkipCinematic == nil then q.autoSkipCinematic = false end
    if q.autoConfirmDelete == nil then q.autoConfirmDelete = false end
    if q.autoSlotKeystone == nil then q.autoSlotKeystone = false end
    if q.petReminder == nil then q.petReminder = false end
    -- Migrate: holdModifier removed; add new hold-to-release fields
    q.holdModifier = nil
    if q.holdDuration == nil then q.holdDuration = 3 end
    if q.holdAutoRelease == nil then q.holdAutoRelease = false end
    -- Migrate: move pet reminder from below-center to above-center
    if q.petY and q.petY == -240 then q.petY = 100 end
    -- Migrate: ensure mythicTimer defaults exist for old profiles
    if not self.db.profile.mythicTimer then
        self.db.profile.mythicTimer = CopyTable(ns.Defaults.profile.mythicTimer)
    end
    -- Migrate: old profiles had enabledDungeon=false by mistake; default is now true
    if r.enabledDungeon == nil or r.enabledDungeon == false then
        -- Only reset if it was never explicitly set to false by the user.
        -- Since old default was false, we can't distinguish — just upgrade to true.
        r.enabledDungeon = true
    end

    -- Migrate: if profile still has old TWW flask IDs (< Midnight S1), reset to new defaults
    local twwFlaskIDs = { [431932]=true,[431934]=true,[431935]=true,[431936]=true,[431933]=true,
                          [432021]=true,[432022]=true,[432023]=true,[432024]=true,[432025]=true }
    if r.flasks and r.flasks[1] and twwFlaskIDs[r.flasks[1].spellID] then
        r.flasks = CopyTable(ns.Defaults.profile.reminder.flasks)
    end
    -- Migrate: reset old TWW augment rune ID (441392) to new Midnight rune IDs
    if r.augmentRunes and r.augmentRunes[1] and r.augmentRunes[1].spellID == 441392 then
        r.augmentRunes = CopyTable(ns.Defaults.profile.reminder.augmentRunes)
    end
    -- Migrate: reset old individual food spell IDs to new generic Well Fed IDs
    local oldFoodIDs = { [431780]=true,[431781]=true,[431782]=true,[431783]=true,
                         [431784]=true,[431785]=true,[431786]=true }
    if r.food and r.food[1] and oldFoodIDs[r.food[1].spellID] then
        r.food = CopyTable(ns.Defaults.profile.reminder.food)
    end

    -- Migrate: ensure combatRess defaults exist for old profiles
    if not self.db.profile.combatRess then
        self.db.profile.combatRess = CopyTable(ns.Defaults.profile.combatRess)
    end

    -- Migrate: ensure skyridingHUD defaults exist for old profiles
    if not self.db.profile.skyridingHUD then
        self.db.profile.skyridingHUD = CopyTable(ns.Defaults.profile.skyridingHUD)
    end

    ns.Config.Build(self)
    self:RegisterChatCommand("yaqol", "OnSlashCommand")
    self:RegisterChatCommand("yq", "OnSlashCommand")
end

function yaqol:OnEnable()
    ns.MinimapButton.Init(self)
    ns.Teleport.Init(self)
    ns.AuraReminder.Init(self)
    ns.QOL.Init(self)
    ns.FriendList.Init(self)
    ns.Merchant.Init(self)
    ns.RaidTools.Init(self)
    ns.SkyridingHUD.Init(self)
    ns.CombatRess.Init(self)
    ns.MythicTimer.Init(self)
end

function yaqol:OnProfileChanged()
    ns.Teleport.Refresh(self)
    ns.AuraReminder.Refresh(self)
    ns.MinimapButton.Refresh(self)
    ns.QOL.Refresh(self)
    ns.FriendList.Refresh(self)
    ns.Merchant.Refresh(self)
    ns.RaidTools.Refresh(self)
    ns.SkyridingHUD.Refresh(self)
    ns.CombatRess.Refresh(self)
    ns.MythicTimer.Refresh(self)
end

function yaqol:OnSlashCommand(input)
    input = input and input:trim():lower() or ""
    if input == "teleport" or input == "tp" then
        ns.Teleport.Toggle()
    elseif input == "reminder" then
        ns.AuraReminder.ForceShow()
    elseif input == "layout" then
        if ns.LayoutMode.IsActive() then
            ns.LayoutMode.Exit()
        else
            ns.LayoutMode.Enter()
        end
    else
        ns.Config.Toggle()
    end
end

function yaqol:Profile() return self.db.profile end
