local ADDON_NAME, ns = ...
ns.AuraReminder = {}
local AuraReminder = ns.AuraReminder

-- [ CONSTANTS ] -------------------------------------------------------------------
local ICON_SIZE    = 36
local ICON_PAD     = 4
local PANEL_PAD    = 6

-- [ LABEL SHORTCUTS ] ---------------------------------------------------------
local SHORT_LABELS = {
    ["Power Word: Fortitude"] = "Fort",
    ["Mark of the Wild"]      = "MotW",
    ["Arcane Intellect"]      = "Int",
    ["Battle Shout"]          = "Shout",
    ["Skyfury"]               = "Skyfury",
    ["Blessing of the Bronze"] = "Bronze",
    ["Dmg Poison"]            = "Poison",
    ["Utility Poison"]        = "Util",
    ["Rite of Adjuration"]    = "Adjur",
    ["Rite of Sanctification"] = "Sanct",
    ["Devotion Aura"]         = "Devo",
    ["Flametongue Weapon"]    = "FT",
    ["Windfury Weapon"]       = "WF",
    ["Earthliving Weapon"]    = "EL",
    ["Thunderstrike Ward"]    = "TS",
    ["Defensive Stance"]      = "Def",
    ["Berserker Stance"]      = "Zerk",
    ["Shadowform"]            = "Shadow",
    ["Blistering Scales"]     = "Scales",
    ["Source of Magic"]        = "SoM",
    ["Flask"]                 = "Flask",
    ["Flask (expiring)"]      = "Flask",
    ["Food"]                  = "Food",
    ["Augment Rune"]          = "Rune",
    ["Weapon Oil"]            = "Oil",
    ["Runeforge"]             = "Rune",
    ["Shield"]                = "Shield",
}

local function ShortLabel(label)
    return SHORT_LABELS[label] or label
end

-- [ STATE ] -------------------------------------------------------------------
local frame, rows
local inInstance      = false
local isActive        = false
local dismissTimer    = nil
local _unitAuraPending = false  -- coalesce UNIT_AURA burst into one deferred scan
local CheckAndShow    -- forward declaration (defined after ShouldActivate)

-- [ KEYSTONE LABEL ] ---------------------------------------------------------
-- Cache keystone data from LibKeystone broadcasts so we can identify who holds
-- the key when inside an active Mythic+ dungeon.
local keystoneCache = {}  -- shortName → { level, mapID }
local lksRegTable   = {}  -- unique LibKeystone registration handle

local function UpdateKeyLabel()
    if not frame or not frame.keyLabel then return end
    if not C_ChallengeMode.IsChallengeModeActive() then
        frame.keyLabel:Hide()
        return
    end
    local keystoneLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    if not keystoneLevel then frame.keyLabel:Hide(); return end
    -- Try to match by active map ID first, then fall back to level match.
    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetActiveChallengeMapID() or nil
    local holder
    if activeMapID then
        for name, data in pairs(keystoneCache) do
            if data.mapID == activeMapID then holder = name; break end
        end
    end
    if not holder then
        for name, data in pairs(keystoneCache) do
            if data.level == keystoneLevel then holder = name; break end
        end
    end
    local text = holder
        and string.format("%s |cffFFD700+%d|r", holder, keystoneLevel)
        or  string.format("|cffFFD700+%d|r", keystoneLevel)
    frame.keyLabel:SetText(text)
    frame.keyLabel:Show()
end

-- [ FRAME CONSTRUCTION ] ------------------------------------------------------
local function MakeFrame()
    local db = ns.Addon:Profile().reminder
    local f = CreateFrame("Frame", "yaqolReminderFrame", UIParent)
    f:SetFrameStrata(db.frameStrata or "HIGH")
    
    f:SetAlpha(db.opacity or 0.7)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = ns.Addon:Profile().reminder
        db.point, _, db.relPoint, db.x, db.y = self:GetPoint()
    end)
    f:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    f:SetScript("OnLeave", function(self)
        local rdb = ns.Addon:Profile().reminder
        self:SetAlpha(rdb.opacity or 0.7)
    end)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Key holder label: shown above the icon row while inside an active M+ run.
    local keyLabel = f:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    keyLabel:SetPoint("BOTTOM", f, "TOP", 0, 4)
    ns.Theme:ApplyHudFont(keyLabel)
    keyLabel:Hide()
    f.keyLabel = keyLabel

    f.rows = {}
    return f
end

local function GetOrMakeRow(idx)
    if frame.rows[idx] then return frame.rows[idx] end
    local row = CreateFrame("Button", "yaqolABR_" .. idx, frame, "SecureActionButtonTemplate")
    row:SetSize(ICON_SIZE, ICON_SIZE)
    row:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    row:SetPassThroughButtons("RightButton")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetColorTexture(1, 0, 0, 1)
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    iconBorder:SetAlpha(0)
    row.iconBorder = iconBorder

    local function MakeBadgeBg(textHook)
        local frame = CreateFrame("Frame", nil, row)
        frame:SetFrameLevel(row:GetFrameLevel() + 1)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)
        frame.bg = bg
        return frame
    end

    -- Item count badge (bottom-right corner, e.g. "3 in bags")
    local countText = row:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    countText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    ns.Theme:ApplyHudFont(countText)
    countText:SetTextColor(1, 1, 1, 1)
    countText:Hide()
    row.countText = countText
    
    local countBg = MakeBadgeBg(countText)
    countBg:SetPoint("TOPLEFT", countText, "TOPLEFT", -2, 2)
    countBg:SetPoint("BOTTOMRIGHT", countText, "BOTTOMRIGHT", 2, -2)
    countText.bg = countBg

    -- Party missing badge (top-right corner): red number = how many members missing
    local partyBadge = row:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    partyBadge:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
    ns.Theme:ApplyHudFont(partyBadge)
    partyBadge:SetTextColor(1, 0.25, 0.25, 1)
    partyBadge:Hide()
    row.partyBadge = partyBadge
    
    local partyBg = MakeBadgeBg(partyBadge)
    partyBg:SetPoint("TOPLEFT", partyBadge, "TOPLEFT", -2, 2)
    partyBg:SetPoint("BOTTOMRIGHT", partyBadge, "BOTTOMRIGHT", 2, -2)
    partyBadge.bg = partyBg

    -- "Missing from group" indicator (top-left): orange ! when another class's buff is absent
    local groupBadge = row:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    groupBadge:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
    ns.Theme:ApplyHudFont(groupBadge)
    groupBadge:SetTextColor(1, 0.55, 0.1, 1)
    groupBadge:SetText("!")
    groupBadge:Hide()
    row.groupBadge = groupBadge
    
    local groupBg = MakeBadgeBg(groupBadge)
    groupBg:SetPoint("TOPLEFT", groupBadge, "TOPLEFT", -2, 2)
    groupBg:SetPoint("BOTTOMRIGHT", groupBadge, "BOTTOMRIGHT", 2, -2)
    groupBadge.bg = groupBg

    -- Text label below icon (optional, controlled by db.showText)
    local textLabel = row:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    textLabel:SetPoint("TOP", row, "BOTTOM", 0, -2)
    textLabel:Hide()
    row.textLabel = textLabel

    -- Tooltip handling (HookScript: SecureActionButtonTemplate has its own scripts)
    row:EnableMouse(true)
    row:HookScript("OnEnter", function(self)
        frame:SetAlpha(1)
        local db = ns.Addon:Profile().reminder
        if db.showTooltip ~= false and self.spellLabel then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.spellLabel, 1, 1, 1)
            if self.missingFromGroup then
                GameTooltip:AddLine("Missing from group", 1, 0.6, 0.1)
            elseif self.expiring then
                GameTooltip:AddLine("Expiring soon", 1, 0.6, 0.1)
            elseif self.required then
                GameTooltip:AddLine("Required", 1, 0.3, 0.3)
            else
                GameTooltip:AddLine("Optional", 0.7, 0.7, 0.7)
            end
            -- Consumable count
            if self.itemCount and self.itemCount > 0 then
                GameTooltip:AddLine(
                    string.format("|cff00ff00%d in bags|r", self.itemCount), 1, 1, 1)
            end
            -- Party missing count (expands on the badge)
            if self.partyMissingCount and self.partyMissingCount > 0 and self.partyTotalCount and self.partyTotalCount > 0 then
                local have = self.partyTotalCount - self.partyMissingCount
                GameTooltip:AddLine(
                    string.format("|cffff4444%d/%d members have this buff|r", have, self.partyTotalCount),
                    1, 1, 1)
            end
            -- Missing-from-group (expands on the ! badge)
            if self.missingFromGroup then
                GameTooltip:AddLine("|cffff8822Nobody in group has this buff|r", 1, 1, 1)
            end
            -- Click hints
            if self.actionType and self.actionType ~= "texture" and not InCombatLockdown() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ff00Left-click to use|r", 1, 1, 1)
            end
            if self._dismissKey then
                GameTooltip:AddLine("|cff888888Middle-click to dismiss|r", 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    row:HookScript("OnLeave", function(self)
        local rdb = ns.Addon:Profile().reminder
        frame:SetAlpha(rdb.opacity or 0.7)
        GameTooltip:Hide()
    end)

    -- Middle-click dismiss: temporarily hide this reminder until next loading screen
    row:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self._dismissKey then
            ns.AuraList.Dismiss(self._dismissKey)
            -- Refresh the display to remove the dismissed icon
            if not InCombatLockdown() then
                CheckAndShow()
            end
        end
    end)

    frame.rows[idx] = row
    return row
end

-- [ ICON ACTIONS ] ------------------------------------------------------------
-- Configure a SecureActionButton to cast a spell when left-clicked.
-- Each setter clears conflicting attributes to prevent stale values from a
-- prior configuration interfering with SecureActionButtonTemplate dispatch.
local function SetIconSpell(btn, spellID)
    if InCombatLockdown() or not spellID then return end
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", spellID)
    btn:SetAttribute("unit", "player")
    btn:SetAttribute("item", nil)
    btn:SetAttribute("macrotext", nil)
end

-- Configure a SecureActionButton to use an item when left-clicked.
local function SetIconItem(btn, itemID)
    if InCombatLockdown() or not itemID then return end
    btn:SetAttribute("type", "item")
    btn:SetAttribute("item", "item:" .. itemID)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("unit", nil)
end

-- Configure a SecureActionButton to run a macro when left-clicked.
local function SetIconMacro(btn, macrotext)
    if InCombatLockdown() or not macrotext then return end
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", macrotext)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("unit", nil)
end

-- Clear all secure attributes (display-only mode).
local function ClearIconAction(btn)
    if InCombatLockdown() then return end
    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("unit", nil)
end

local function ResizeFrame(colCount)
    local db = ns.Addon:Profile().reminder
    local spacing = db.iconSpacing or ICON_PAD
    local w = PANEL_PAD * 2 + colCount * ICON_SIZE + (colCount - 1) * spacing
    local textH = db.showText and ((db.textSize or 10) + 4) or 0
    local h = PANEL_PAD * 2 + ICON_SIZE + textH
    frame:SetSize(w, h)
end

-- [ COMBAT ICON POOL ] --------------------------------------------------------
-- Non-secure frames shown during combat as visual replicas of the secure icons.
-- These can be Show/Hide'd freely during combat lockdown.
local combatFrame   -- parent frame for combat icons
local combatRows = {}

local function MakeCombatFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetAllPoints(frame)  -- follows the main frame's position exactly
    f:Hide()
    return f
end

local function GetOrMakeCombatRow(idx)
    if combatRows[idx] then return combatRows[idx] end
    local row = CreateFrame("Frame", nil, combatFrame)
    row:SetSize(ICON_SIZE, ICON_SIZE)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    combatRows[idx] = row
    return row
end

-- [ COMBAT TRANSITIONS ] ------------------------------------------------------
local function ShowCombatIcons()
    if not combatFrame then combatFrame = MakeCombatFrame() end
    if not frame:IsShown() then return end

    local db = ns.Addon:Profile().reminder
    if not db.showInCombat then return end

    local glowType = db.glowType or "BLIZZARD"
    local glowColor = db.glowColor or { r = 1, g = 0.8, b = 0, a = 1 }

    -- Replicate the current icon layout onto combat frames
    local shown = 0
    local spacing = db.iconSpacing or ICON_PAD
    for i, row in ipairs(frame.rows) do
        if row:IsShown() then
            shown = shown + 1
            local cr = GetOrMakeCombatRow(i)
            cr:ClearAllPoints()
            cr:SetPoint("LEFT", combatFrame, "LEFT", PANEL_PAD + (i - 1) * (ICON_SIZE + spacing), 0)
            cr:SetSize(row:GetWidth(), row:GetHeight())
            cr.icon:SetTexture(row.icon:GetTexture())
            if row.present then
                cr.icon:SetAlpha(0.35)
                ns.AuraGlow.Stop(cr)
            else
                cr.icon:SetAlpha(1)
                if row.required then
                    ns.AuraGlow.Start(cr, glowType, glowColor)
                else
                    ns.AuraGlow.Stop(cr)
                end
            end
            cr:Show()
        end
    end
    -- Hide unused combat rows
    for i = #frame.rows + 1, #combatRows do
        if combatRows[i] then combatRows[i]:Hide(); ns.AuraGlow.Stop(combatRows[i]) end
    end

    if shown == 0 then return end

    -- Fade out secure icons (SetAlpha is safe during combat)
    for _, row in ipairs(frame.rows) do
        row:SetAlpha(0)
    end
    combatFrame:SetSize(frame:GetWidth(), frame:GetHeight())
    combatFrame:Show()
end

local function HideCombatIcons()
    if combatFrame then
        combatFrame:Hide()
        for _, cr in ipairs(combatRows) do
            ns.AuraGlow.Stop(cr)
            cr:Hide()
        end
    end
    -- Restore secure icon alpha
    if frame and frame.rows then
        for _, row in ipairs(frame.rows) do
            if row:IsShown() then
                row:SetAlpha(1)
            end
        end
    end
end

-- Refresh combat icons with new data (called when aura changes detected in combat)
local function RefreshCombatIcons(items)
    if not combatFrame or not combatFrame:IsShown() then return end
    if not items or #items == 0 then
        combatFrame:Hide()
        return
    end
    local db = ns.Addon:Profile().reminder
    local glowType = db.glowType or "BLIZZARD"
    local glowColor = db.glowColor or { r = 1, g = 0.8, b = 0, a = 1 }
    local spacing = db.iconSpacing or ICON_PAD
    for i, m in ipairs(items) do
        local cr = GetOrMakeCombatRow(i)
        cr:ClearAllPoints()
        cr:SetPoint("LEFT", combatFrame, "LEFT", PANEL_PAD + (i - 1) * (ICON_SIZE + spacing), 0)
        cr.icon:SetTexture(m.icon)
        if m.present then
            cr.icon:SetAlpha(0.35)
            ns.AuraGlow.Stop(cr)
        else
            cr.icon:SetAlpha(1)
            if m.required then
                ns.AuraGlow.Start(cr, glowType, glowColor)
            else
                ns.AuraGlow.Stop(cr)
            end
        end
        cr:Show()
    end
    for i = #items + 1, #combatRows do
        if combatRows[i] then combatRows[i]:Hide(); ns.AuraGlow.Stop(combatRows[i]) end
    end
    -- Update parent size to match current item count
    local w = PANEL_PAD * 2 + #items * ICON_SIZE + (#items - 1) * spacing
    local h = PANEL_PAD * 2 + ICON_SIZE
    combatFrame:SetSize(w, h)
end

-- [ GLOW ] --------------------------------------------------------------------
local function StartGlow()
    local db = ns.Addon:Profile().reminder
    local glowType = db.glowType or "BLIZZARD"
    local glowColor = db.glowColor or { r = 1, g = 0.8, b = 0, a = 1 }
    for _, row in ipairs(frame.rows) do
        if row:IsShown() and row.required and not row.present then
            row.iconBorder:SetAlpha(0)
            ns.AuraGlow.Start(row, glowType, glowColor)
        else
            ns.AuraGlow.Stop(row)
            row.iconBorder:SetAlpha(0)
            if not row.present then row.icon:SetAlpha(1) end
        end
    end
end

local function StopGlow()
    ns.AuraGlow.StopAll()
    if frame and frame.rows then
        for _, row in ipairs(frame.rows) do
            row.icon:SetAlpha(1)
        end
    end
end

-- [ SHOW / HIDE ] -------------------------------------------------------------
function AuraReminder.Hide()
    if not frame then return end
    StopGlow()
    if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
    -- frame:Hide() is blocked during combat lockdown on named protected frames.
    -- Skip the hide if we're locked down — CheckAndShow will re-evaluate on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then return end
    frame:Hide()
end

function AuraReminder.GetFrame()
    return frame
end

local function ShowMissing(missing)
    if not frame then return end
    -- Hide all existing rows (SetAttribute/Hide blocked during combat lockdown)
    if not InCombatLockdown() then
        for _, row in ipairs(frame.rows) do row:Hide() end
    end

    if #missing == 0 then AuraReminder.Hide(); return end

    ResizeFrame(#missing)

    local xOff = PANEL_PAD
    local db = ns.Addon:Profile().reminder
    local spacing = db.iconSpacing or ICON_PAD
    for i, m in ipairs(missing) do
        local row = GetOrMakeRow(i)
        row:SetPoint("LEFT", frame, "LEFT", xOff, 0)
        row.icon:SetTexture(m.icon)
        row.spellLabel = m.label
        row.required = m.required
        row.partyMissingCount = m.partyMissingCount or 0
        row.partyTotalCount   = m.partyTotalCount or 0
        row.itemCount = m.itemCount or 0
        row.missingFromGroup = m.missingFromGroup or false
        row.present = m.present or false
        row.expiring = m.expiring or false
        -- Item count badge (bottom-right)
        if m.itemCount and m.itemCount > 0 then
            row.countText:SetText(m.itemCount)
            row.countText:Show()
            row.countText.bg:Show()
        else
            row.countText:Hide()
            row.countText.bg:Hide()
        end
        if m.partyMissingCount and m.partyMissingCount > 0 then
            row.partyBadge:SetText(m.partyMissingCount)
            row.partyBadge:Show()
            row.partyBadge.bg:Show()
        else
            row.partyBadge:Hide()
            row.partyBadge.bg:Hide()
        end
        if m.missingFromGroup then
            row.groupBadge:Show()
            row.groupBadge.bg:Show()
        else
            row.groupBadge:Hide()
            row.groupBadge.bg:Hide()
        end
        -- Configure click action (OOC only -- SetAttribute is blocked in combat)
        row.actionType  = m.actionType
        row._dismissKey = m.dismissKey
        if not InCombatLockdown() then
            if m.actionType == "spell" and m.actionValue then
                SetIconSpell(row, m.actionValue)
            elseif m.actionType == "item" and m.actionValue then
                SetIconItem(row, m.actionValue)
            elseif m.actionType == "macro" and m.actionValue then
                SetIconMacro(row, m.actionValue)
            else
                ClearIconAction(row)
            end
        end
        row:Show()
        -- Dim icons that are already present (show-all mode)
        if m.present then
            row.icon:SetAlpha(0.35)
            row.iconBorder:SetAlpha(0)
        else
            row.icon:SetAlpha(1)
        end
        -- Text label below icon
        if db.showText and row.textLabel then
            row.textLabel:SetText(ShortLabel(m.label))
            local tc = db.textColor or { r = 1, g = 1, b = 1 }
            row.textLabel:SetTextColor(tc.r, tc.g, tc.b, 1)
            if db.textSize and db.textSize ~= 10 then
                local font, _, flags = row.textLabel:GetFont()
                row.textLabel:SetFont(font, db.textSize, flags)
            end
            row.textLabel:Show()
        elseif row.textLabel then
            row.textLabel:Hide()
        end
        xOff = xOff + ICON_SIZE + spacing
    end

    frame:Show()
    StartGlow()
    UpdateKeyLabel()

    if db.dismissAfter and db.dismissAfter > 0 then
        if dismissTimer then dismissTimer:Cancel() end
        dismissTimer = C_Timer.NewTimer(db.dismissAfter, AuraReminder.Hide)
    end
end

-- Shows placeholder icons for layout-mode positioning.
-- Called by LayoutMode so the frame is visible and draggable even out of combat.
function AuraReminder.ShowForLayout()
    if not frame then return end
    local placeholders = {
        { icon = 134400, label = "Flask",       required = true  },
        { icon = 133971, label = "Food",         required = true  },
        { icon = 136243, label = "Augment Rune", required = false },
    }
    ShowMissing(placeholders)
end

-- [ INSTANCE CHECK ] ----------------------------------------------------------
local function ShouldActivate()
    local db = ns.Addon:Profile().reminder
    if not db.enabled then return false end
    local _, iType = GetInstanceInfo()
    if iType == "party" then
        if not db.enabledMythicPlus and not db.enabledDungeon then return false end
        if db.enabledMythicPlus and C_ChallengeMode.IsChallengeModeActive() then
            local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
            if (lvl or 0) >= db.minKeystoneLevel then return true end
        end
        return db.enabledDungeon
    elseif iType == "raid" then
        return db.enabledRaid
    elseif db.showNonInstanced then
        -- Open world mode: show reminders everywhere
        return true
    end
    return false
end

CheckAndShow = function()
    if not ShouldActivate() then AuraReminder.Hide(); return end
    local db = ns.Addon:Profile().reminder
    if db.onlyOutOfCombat and InCombatLockdown() then AuraReminder.Hide(); return end
    -- GetMissing() has its own CanReadAuras() guard, but bail here too so we
    -- don't hide the frame mid-combat if it was already showing valid data.
    if InCombatLockdown() then return end
    local items = db.showAllBuffs and ns.AuraList.GetAll(db) or ns.AuraList.GetMissing(db)
    -- In normal mode only show if something is missing; in show-all mode always show
    if not db.showAllBuffs and #items == 0 then AuraReminder.Hide(); return end
    ShowMissing(items)
end

-- [ PUBLIC API ] --------------------------------------------------------------
function AuraReminder.IsActive() return isActive end

function AuraReminder.ForceShow()
    local db = ns.Addon:Profile().reminder
    local missing = ns.AuraList.GetMissing(db)
    ShowMissing(missing)
end

function AuraReminder.Refresh(addon)
    if not frame then return end
    local db = addon:Profile().reminder
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    frame:SetScale(db.scale or 1.0)
    frame:SetFrameStrata(db.frameStrata or "HIGH")
    frame:SetAlpha(db.opacity or 0.7)
    
    isActive = ShouldActivate()
    if isActive then
        CheckAndShow()
    else
        AuraReminder.Hide()
    end
end

-- [ INIT ] --------------------------------------------------------------------
function AuraReminder.Init(addon)
    frame = MakeFrame()
    local db = addon:Profile().reminder
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    frame:SetScale(db.scale or 1.0)

    -- Register with LibKeystone so we know who holds each party member's key.
    -- This lets us display the key holder's name above the reminder panel during M+.
    local LibKeystone = LibStub and LibStub("LibKeystone", true)
    if LibKeystone then
        LibKeystone.Register(lksRegTable, function(keyLevel, keyMapID, _, playerName, channel)
            if channel ~= "PARTY" then return end
            if not playerName or playerName == "" then
                playerName = UnitName("player") or ""
            end
            local shortName = playerName:match("^([^%-]+)") or playerName
            if keyLevel and keyLevel > 0 and keyMapID and keyMapID > 0 then
                keystoneCache[shortName] = { level = keyLevel, mapID = keyMapID }
            else
                keystoneCache[shortName] = nil
            end
        end)
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    watcher:RegisterEvent("CHALLENGE_MODE_START")
    watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("ENCOUNTER_START")
    watcher:RegisterEvent("UNIT_AURA")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("SPELLS_CHANGED")
    watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
    watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    watcher:RegisterEvent("PLAYER_DEAD")
    watcher:RegisterEvent("PLAYER_ALIVE")
    watcher:RegisterEvent("UNIT_ENTERED_VEHICLE")
    watcher:RegisterEvent("UNIT_EXITED_VEHICLE")

    -- Periodic ticker: re-check every 5s while active so party buff losses are caught.
    local periodicTicker = nil
    local function StartPeriodic()
        if periodicTicker then return end
        periodicTicker = C_Timer.NewTicker(5, function()
            if isActive and not InCombatLockdown() then
                local rdb = ns.Addon:Profile().reminder
                if not rdb.onlyOutOfCombat or not InCombatLockdown() then
                    local items = rdb.showAllBuffs and ns.AuraList.GetAll(rdb) or ns.AuraList.GetMissing(rdb)
                    if rdb.showAllBuffs or #items > 0 then
                        ShowMissing(items)
                    elseif frame:IsShown() then
                        AuraReminder.Hide()
                    end
                end
            end
        end)
    end
    local function StopPeriodic()
        if periodicTicker then periodicTicker:Cancel(); periodicTicker = nil end
    end

    -- Fix #4: Dedicated 1-second weapon-enchant ticker.
    -- UNIT_AURA does NOT fire when temporary weapon enchants change, so weapon
    -- buffs (poisons, shaman imbues, rune forges) can fall off silently.
    -- This ticker is only active while the frame is visible and we're out of combat.
    local weaponTicker = nil
    local function HasWeaponBuffDefs()
        -- We need the 1-second ticker when weapon enchant state can change
        -- without firing UNIT_AURA:
        --   • Death Knight runeforge checks (isRuneforge = true)
        --   • Weapon oil / temp enchant reminder (db.weaponOil = true)
        -- All other weapon imbues (shaman, rogue poisons) DO fire UNIT_AURA.
        local _, cls = UnitClass("player")
        if cls == "DEATHKNIGHT" then return true end
        local rdb = ns.Addon:Profile().reminder
        return rdb.weaponOil == true
    end
    local function StartWeaponTicker()
        if weaponTicker then return end
        if not HasWeaponBuffDefs() then return end
        if IsInRaid() then return end  -- enchants don't change mid-raid; 5s ticker is enough
        weaponTicker = C_Timer.NewTicker(1, function()
            if not isActive or InCombatLockdown() or IsInRaid() then return end
            local wdb = ns.Addon:Profile().reminder
            if wdb.onlyOutOfCombat and InCombatLockdown() then return end
            local items = wdb.showAllBuffs and ns.AuraList.GetAll(wdb) or ns.AuraList.GetMissing(wdb)
            if wdb.showAllBuffs or #items > 0 then
                ShowMissing(items)
            elseif frame:IsShown() then
                AuraReminder.Hide()
            end
        end)
    end
    local function StopWeaponTicker()
        if weaponTicker then weaponTicker:Cancel(); weaponTicker = nil end
    end

    -- [ RANGE POLLING ] -------------------------------------------------------
    -- Polls group member distance every 0.5s (OOC only) for party buff range checks.
    local rangeFrame
    local _lastRangeSet = {}   -- unit -> boolean (last known in-range state)
    local RANGE_POLL_INTERVAL = 0.5
    local _rangeElapsed = 0

    local function StartRangePolling()
        if rangeFrame then rangeFrame:Show(); return end
        rangeFrame = CreateFrame("Frame")
        rangeFrame:SetScript("OnUpdate", function(self, elapsed)
            _rangeElapsed = _rangeElapsed + elapsed
            if _rangeElapsed < RANGE_POLL_INTERVAL then return end
            _rangeElapsed = 0

            if InCombatLockdown() or not isActive then return end
            local rdb = ns.Addon:Profile().reminder
            if not rdb.partyBuffRangeCheck then return end

            local inGroup = IsInGroup() or IsInRaid()
            if not inGroup then
                ns.AuraList.SetInRangeUnits(nil)
                return
            end

            local changed = false
            local inRange = {}
            local inRaid = IsInRaid()
            local count = inRaid and GetNumGroupMembers() or GetNumSubgroupMembers()

            for i = 1, count do
                local u = inRaid and ("raid" .. i) or ("party" .. i)
                if UnitExists(u) then
                    -- CheckInteractDistance(unit, 4) = ~28 yards (follow distance)
                    local near = CheckInteractDistance(u, 4) or false
                    inRange[u] = near or nil
                    if _lastRangeSet[u] ~= near then changed = true end
                end
            end

            _lastRangeSet = inRange
            ns.AuraList.SetInRangeUnits(inRange)

            if changed then CheckAndShow() end
        end)
    end

    local function StopRangePolling()
        if rangeFrame then rangeFrame:Hide() end
        ns.AuraList.SetInRangeUnits(nil)
        wipe(_lastRangeSet)
    end

    -- [ DURATION TICKER ] -----------------------------------------------------
    -- 15s ticker that re-scans for expiring buffs when duration thresholds are set.
    local durationTicker = nil

    local function StartDurationTicker()
        if durationTicker then return end
        local rdb = ns.Addon:Profile().reminder
        local hasDurationThreshold = (rdb.showUnderDurationDungeon or 0) > 0
            or (rdb.showUnderDurationRaid or 0) > 0
        if not hasDurationThreshold then return end

        durationTicker = C_Timer.NewTicker(15, function()
            if not isActive or InCombatLockdown() then return end
            CheckAndShow()
        end)
    end

    local function StopDurationTicker()
        if durationTicker then durationTicker:Cancel(); durationTicker = nil end
    end

    -- Schedule a check after a short delay. Uses C_Timer.After(0) for
    -- the first frame, then a real delay so the world is fully loaded.
    -- Uses multiple retries because ZONE_CHANGED_NEW_AREA can fire after
    -- PLAYER_ENTERING_WORLD and reset the sequence, and GetInstanceInfo()
    -- sometimes returns "none" on the first frame inside an instance.
    local pendingSeq = 0
    local function ScheduleCheck()
        pendingSeq = pendingSeq + 1
        local seq = pendingSeq
        local delay = ns.Addon:Profile().reminder.enterDelay or 2

        local function TryActivate()
            if seq ~= pendingSeq then return true end  -- superseded, stop retrying
            isActive = ShouldActivate()
            if isActive then
                CheckAndShow()
                StartPeriodic()
                StartWeaponTicker()
                StartRangePolling()
                StartDurationTicker()
                return true
            end
            return false
        end

        -- Attempt 1: next frame
        C_Timer.After(0, function()
            if not TryActivate() then
                -- Attempt 2: after enterDelay
                C_Timer.After(delay, function()
                    if not TryActivate() then
                        -- Attempt 3: one more retry in case the zone was slow
                        C_Timer.After(delay, function()
                            TryActivate()
                        end)
                    end
                end)
            end
        end)
    end

    watcher:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "CHALLENGE_MODE_START" then
            ns.AuraList.ClearDismissed()  -- reset middle-click dismissals on loading screen
            isActive = false
            HideCombatIcons()
            ns.AuraList.ClearSnapshot()
            AuraReminder.Hide()
            StopPeriodic()
            StopWeaponTicker()
            StopRangePolling()
            StopDurationTicker()
            ScheduleCheck()

        elseif event == "CHALLENGE_MODE_COMPLETED" then
            UpdateKeyLabel()

        elseif event == "ENCOUNTER_START" then
            -- Snapshot auras BEFORE lockdown (ENCOUNTER_START fires before REGEN_DISABLED)
            ns.AuraList.SnapshotAuras()

        elseif event == "PLAYER_REGEN_ENABLED" then
            HideCombatIcons()
            ns.AuraList.ClearSnapshot()
            if isActive then CheckAndShow() end

        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Secondary snapshot (catches non-encounter combat like pulling trash)
            if not ns.AuraList.HasSnapshot() then
                ns.AuraList.SnapshotAuras()
            end
            local rdb = ns.Addon:Profile().reminder
            if rdb.onlyOutOfCombat then
                -- Show combat replicas if enabled, otherwise hide entirely
                if rdb.showInCombat then
                    ShowCombatIcons()
                else
                    AuraReminder.Hide()
                end
            end

        elseif event == "GROUP_ROSTER_UPDATE" then
            if isActive and not InCombatLockdown() then CheckAndShow() end

        -- Talent/spec changes: full re-evaluation (class buff defs may change)
        elseif event == "SPELLS_CHANGED"
            or event == "PLAYER_TALENT_UPDATE"
            or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "TRAIT_CONFIG_UPDATED" then
            if isActive and not InCombatLockdown() then CheckAndShow() end

        -- Bag changes: consumable counts may have changed
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Refresh display (counts may have changed)
            if isActive and not InCombatLockdown() then CheckAndShow() end

        -- Weapon enchant changes: poisons, oils, imbues, runeforges
        elseif event == "WEAPON_ENCHANT_CHANGED" then
            if isActive and not InCombatLockdown() then CheckAndShow() end

        -- Dead: hide reminders (can't buff while dead)
        elseif event == "PLAYER_DEAD" then
            AuraReminder.Hide()

        -- Alive: re-check
        elseif event == "PLAYER_ALIVE" then
            if isActive and not InCombatLockdown() then CheckAndShow() end

        -- Vehicle: suppress reminders while in a vehicle
        elseif event == "UNIT_ENTERED_VEHICLE" then
            local unit = ...
            if unit == "player" then AuraReminder.Hide() end

        elseif event == "UNIT_EXITED_VEHICLE" then
            local unit = ...
            if unit == "player" and isActive and not InCombatLockdown() then CheckAndShow() end

        elseif event == "UNIT_AURA" then
            local unit = ...
            -- Buff reminder re-scan
            local isParty = unit and (unit:sub(1,5) == "party" or unit:sub(1,4) == "raid")
            if unit ~= "player" and not isParty then return end
            local rdb = ns.Addon:Profile().reminder
            if not isActive then return end
            if not rdb.remindOnBuffLost then return end
            if rdb.onlyOutOfCombat and InCombatLockdown() and not rdb.showInCombat then return end
            -- Coalesce burst: UNIT_AURA can fire many times per frame (one per member).
            -- Throttled coalescing: 0.3s window collapses burst from raid-wide buffs.
            if not _unitAuraPending then
                _unitAuraPending = true
                C_Timer.After(0.3, function()
                    _unitAuraPending = false
                    if not isActive then return end
                    local cdb = ns.Addon:Profile().reminder
                    if InCombatLockdown() then
                        -- In combat: update combat icons if enabled
                        if cdb.showInCombat and combatFrame and combatFrame:IsShown() then
                            local items = cdb.showAllBuffs
                                and ns.AuraList.GetAll(cdb)
                                or  ns.AuraList.GetMissing(cdb)
                            RefreshCombatIcons(items)
                        end
                        return
                    end
                    -- Out of combat: normal flow
                    local items = cdb.showAllBuffs
                        and ns.AuraList.GetAll(cdb)
                        or  ns.AuraList.GetMissing(cdb)
                    if #items == 0 and not cdb.showAllBuffs then
                        AuraReminder.Hide()
                    else
                        ShowMissing(items)
                    end
                end)
            end
        end
    end)
end
