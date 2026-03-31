local ADDON_NAME, ns = ...
ns.Teleport = {}
local Teleport = ns.Teleport

-- [ CONSTANTS ] ---------------------------------------------------------------
local DUNGEONS = {
    { name = "The Rookery",              spellID = 393273  },
    { name = "Priory of the Sacred Flame",spellID = 1254572 },
    { name = "The Nexus-Princess",       spellID = 1254563 },
    { name = "The Stonevault Spire",     spellID = 1254400 },
    { name = "Skyreach",                 spellID = 159898  },
    { name = "City of Threads Caverns",  spellID = 1254559 },
    { name = "Pit of Saron",             spellID = 1254555 },
    { name = "Operation: Floodgate",     spellID = 1254551 },
}

-- challengeMapID → DUNGEONS index, built at runtime from C_ChallengeMode
local challengeMapToDungeon = {}

local function BuildChallengeMapTable()
    if not C_ChallengeMode or not C_ChallengeMode.GetMapTable then return end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps then return end
    for _, mapID in ipairs(maps) do
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            for i, d in ipairs(DUNGEONS) do
                if d.name == name then
                    challengeMapToDungeon[mapID] = i
                    break
                end
            end
        end
    end
end

local BTN_W, BTN_H = 180, 22
local BTN_PAD = 1
local PANEL_PAD = 8 -- Increased for a slightly larger drag target
local HEADER_H = 16  -- thin strip at top for the close button
local FRAME_W = BTN_W + PANEL_PAD * 2

local DISABLED_ALPHA = 0.3
local LEARNED_COLOR = { 0.9, 0.9, 0.9 }
local UNKNOWN_COLOR = { 0.5, 0.5, 0.5 }

-- [ FRAME ] -------------------------------------------------------------------
local panel, buttons
local userClosed = false  -- set when user clicks X; cleared on group roster change

local function SavePos()
    local db = ns.Addon:Profile().teleport
    db.point, _, db.relPoint, db.x, db.y = panel:GetPoint()
end

local function ApplyPos()
    local db = ns.Addon:Profile().teleport
    panel:ClearAllPoints()
    panel:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function CheckVisibility()
    local db = ns.Addon:Profile().teleport
    if not panel then return end
    if not db.enabled then
        panel:Hide()
        return
    end

    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
        panel:Hide()
        return
    end

    local minSize = db.minGroupSize or 2
    local count = GetNumGroupMembers()  -- 0 when solo, includes player when in party
    -- GetNumGroupMembers returns 0 when solo (not in a group).
    -- When in a party it returns the total member count including the player.
    local effectiveCount = IsInGroup() and count or 1
    if effectiveCount >= minSize then
        if not userClosed then
            panel:Show()
        end
        -- Full group (5) = fully opaque so it demands attention
        local restingAlpha = (effectiveCount >= 5) and 1 or 0.8
        panel:SetAlpha(restingAlpha)
        -- Keep the OnLeave handler in sync with whatever the resting alpha should be
        panel.restingAlpha = restingAlpha
    else
        userClosed = false  -- group shrank below threshold — reset so it shows again when it grows
        panel:Hide()
    end
end

local function MakePanel()
    local totalH = (#DUNGEONS * (BTN_H + BTN_PAD)) + PANEL_PAD * 2 - BTN_PAD + HEADER_H
    local f = CreateFrame("Frame", "yaqolTeleportPanel", UIParent)
    f:SetSize(FRAME_W, totalH)
    f:SetFrameStrata("MEDIUM")
    f.restingAlpha = 0.8

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.75)

    -- Thin header divider line
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -HEADER_H)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
    div:SetColorTexture(1, 1, 1, 0.08)

    -- Close button (×) in the top-right of the header
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(HEADER_H, HEADER_H)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeLbl:SetAllPoints()
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("|cffaaaaaa\195\151|r")  -- × in grey (UTF-8 0xC3 0x97)
    closeBtn:SetScript("OnEnter", function(self)
        f:SetAlpha(1)
        closeLbl:SetText("|cffffffff\195\151|r")
    end)
    closeBtn:SetScript("OnLeave", function(self)
        f:SetAlpha(f.restingAlpha)
        closeLbl:SetText("|cffaaaaaa\195\151|r")
    end)
    closeBtn:SetScript("OnClick", function()
        userClosed = true
        f:Hide()
    end)

    f:SetAlpha(0.8)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    f:SetClampedToScreen(true)

    f:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    f:SetScript("OnLeave", function(self) self:SetAlpha(self.restingAlpha) end)

    return f
end

local function MakeButton(parent, dungeon, idx)
    local yOff = -(HEADER_H + PANEL_PAD + (idx - 1) * (BTN_H + BTN_PAD))
    local btn = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PANEL_PAD, yOff)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- Use spell type with numeric spellID — same pattern as BigWigs teleport buttons
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", dungeon.spellID)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    btn.bg = bg

    -- Spell icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BTN_H - 4, BTN_H - 4)
    icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(dungeon.name)
    btn.label = label

    -- Hover highlight + tooltip
    btn:SetScript("OnEnter", function(self)
        parent:SetAlpha(1)
        if self.learned then self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(dungeon.spellID)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        parent:SetAlpha(0.8)
        self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        GameTooltip:Hide()
    end)

    btn.spellID = dungeon.spellID
    return btn
end

-- [ REFRESH LOGIC ] -----------------------------------------------------------
local function RefreshButtons()
    if not buttons then return end
    local db = ns.Addon:Profile().teleport

    -- Determine player's own keystone dungeon index (if any)
    local keystoneIdx = nil
    local keystoneLevel = nil
    if C_MythicPlus then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        if mapID then keystoneIdx = challengeMapToDungeon[mapID] end
    end

    for i, btn in ipairs(buttons) do
        local known = IsSpellKnown(btn.spellID)
        btn.learned = known
        local iconID = C_Spell.GetSpellTexture(btn.spellID)
        btn.icon:SetTexture(iconID)
        if known then
            btn.label:SetTextColor(LEARNED_COLOR[1], LEARNED_COLOR[2], LEARNED_COLOR[3])
            btn:SetAlpha(1)
            btn:EnableMouse(true)
        else
            btn.label:SetTextColor(UNKNOWN_COLOR[1], UNKNOWN_COLOR[2], UNKNOWN_COLOR[3])
            btn:SetAlpha(DISABLED_ALPHA)
            btn:EnableMouse(false)
        end
        if not known and not db.showUnknown then
            btn:Hide()
        else
            btn:Show()
        end

        -- Keystone badge: show "+N" and gold border on the button matching the player's key
        if i == keystoneIdx and keystoneLevel then
            if not btn.keyBadge then
                -- Gold border (four 1-px edge textures)
                local function MakeEdge(anchor, w, h, xOff, yOff)
                    local t = btn:CreateTexture(nil, "OVERLAY")
                    t:SetSize(w, h)
                    t:SetPoint(anchor, btn, anchor, xOff, yOff)
                    t:SetColorTexture(1, 0.82, 0.1, 1)
                    return t
                end
                btn.borderT = MakeEdge("TOPLEFT",    BTN_W, 1,  0,  0)
                btn.borderB = MakeEdge("BOTTOMLEFT", BTN_W, 1,  0,  0)
                btn.borderL = MakeEdge("TOPLEFT",    1, BTN_H,  0,  0)
                btn.borderR = MakeEdge("TOPRIGHT",   1, BTN_H,  0,  0)

                -- Tiny key icon
                local keyIcon = btn:CreateTexture(nil, "OVERLAY")
                keyIcon:SetSize(14, 14)
                keyIcon:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                keyIcon:SetTexture("Interface\\Icons\\INV_Misc_Key_14")
                keyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                btn.keyIcon = keyIcon

                local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                badge:SetPoint("RIGHT", keyIcon, "LEFT", -2, 0)
                badge:SetTextColor(1, 0.85, 0, 1)  -- gold
                btn.keyBadge = badge
            end
            btn.keyBadge:SetText("+" .. keystoneLevel)
            btn.keyBadge:Show()
            btn.keyIcon:Show()
            btn.borderT:Show(); btn.borderB:Show()
            btn.borderL:Show(); btn.borderR:Show()
            -- Shift label right edge so it doesn't overlap the badge
            btn.label:SetPoint("RIGHT", btn.keyBadge, "LEFT", -4, 0)
        else
            if btn.keyBadge then btn.keyBadge:Hide() end
            if btn.keyIcon  then btn.keyIcon:Hide()  end
            if btn.borderT  then
                btn.borderT:Hide(); btn.borderB:Hide()
                btn.borderL:Hide(); btn.borderR:Hide()
            end
            btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        end
    end
end

-- [ PUBLIC API ] --------------------------------------------------------------
function Teleport.Init(addon)
    panel = MakePanel()
    buttons = {}
    for i, dungeon in ipairs(DUNGEONS) do
        buttons[i] = MakeButton(panel, dungeon, i)
    end
    panel:SetScale(addon:Profile().teleport.scale)
    ApplyPos()
    BuildChallengeMapTable()
    RefreshButtons()
    CheckVisibility()

    -- Refresh known spells when spellbook changes and monitor group status
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("SPELLS_CHANGED")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:SetScript("OnEvent", function(self, event)
        if event == "SPELLS_CHANGED" then
            RefreshButtons()
        elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" or event == "BAG_UPDATE_DELAYED" then
            RefreshButtons()
        else
            CheckVisibility()
        end
    end)
end

function Teleport.Refresh(addon)
    if not panel then return end
    local db = addon:Profile().teleport
    panel:SetScale(db.scale)
    ApplyPos()
    RefreshButtons()
    CheckVisibility()
end

function Teleport.Toggle()
    if not panel then return end
    if panel:IsShown() then panel:Hide() else panel:Show(); RefreshButtons() end
end

function Teleport.GetPanel()
    return panel
end


