local ADDON_NAME, ns = ...

-- [ INIT ] --------------------------------------------------------------------
local yacol = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = yacol
_G.yacol = yacol

function yacol:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("yacolDB", ns.Defaults, true)
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

    ns.Config.Build(self)
    self:RegisterChatCommand("yacol", "OnSlashCommand")
    self:RegisterChatCommand("lqol", "OnSlashCommand")
end

function yacol:OnEnable()
    ns.MinimapButton.Init(self)
    ns.Teleport.Init(self)
    ns.AuraReminder.Init(self)
    ns.QOL.Init(self)
end

function yacol:OnProfileChanged()
    ns.Teleport.Refresh(self)
    ns.AuraReminder.Refresh(self)
    ns.MinimapButton.Refresh(self)
    ns.QOL.Refresh(self)
end

function yacol:OnSlashCommand(input)
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

function LarsQOL:Profile() return self.db.profile end
