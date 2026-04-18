local ADDON_NAME, ns = ...
ns.AuraReminder = {}
local AuraReminder = ns.AuraReminder

-- [ CONSTANTS ] -------------------------------------------------------------------
local ICON_SIZE    = 36
local ICON_PAD     = 4
local PANEL_PAD    = 6
local T = ns.Theme  -- populated by Theme.Init() before any frame is built

-- [ STATE ] -------------------------------------------------------------------
local frame, rows
local inInstance      = false
local isActive        = false
local dismissTimer    = nil
local _unitAuraPending = false  -- coalesce UNIT_AURA burst into one deferred scan

-- [ FRAME CONSTRUCTION ] ------------------------------------------------------
local function MakeFrame()
    local f = CreateFrame("Frame", "yaqolReminderFrame", UIParent)
    f:SetFrameStrata("HIGH")
    
    f:SetAlpha(0.7)
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
    f:SetScript("OnLeave", function(self) self:SetAlpha(0.7) end)
    f:SetClampedToScreen(true)
    f:Hide()

    f.rows = {}
    return f
end

local function GetOrMakeRow(idx)
    if frame.rows[idx] then return frame.rows[idx] end
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(ICON_SIZE, ICON_SIZE)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)

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
    local countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    countText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    countText:SetTextColor(1, 1, 1, 1)
    countText:Hide()
    row.countText = countText
    
    local countBg = MakeBadgeBg(countText)
    countBg:SetPoint("TOPLEFT", countText, "TOPLEFT", -2, 2)
    countBg:SetPoint("BOTTOMRIGHT", countText, "BOTTOMRIGHT", 2, -2)
    countText.bg = countBg

    -- Party missing badge (top-right corner): red number = how many members missing
    local partyBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    partyBadge:SetShadowColor(0, 0, 0, 1)
    partyBadge:SetShadowOffset(1, -1)
    partyBadge:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
    partyBadge:SetTextColor(1, 0.25, 0.25, 1)
    partyBadge:Hide()
    row.partyBadge = partyBadge
    
    local partyBg = MakeBadgeBg(partyBadge)
    partyBg:SetPoint("TOPLEFT", partyBadge, "TOPLEFT", -2, 2)
    partyBg:SetPoint("BOTTOMRIGHT", partyBadge, "BOTTOMRIGHT", 2, -2)
    partyBadge.bg = partyBg

    -- "Missing from group" indicator (top-left): orange ! when another class's buff is absent
    local groupBadge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupBadge:SetShadowColor(0, 0, 0, 1)
    groupBadge:SetShadowOffset(1, -1)
    groupBadge:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
    groupBadge:SetTextColor(1, 0.55, 0.1, 1)
    groupBadge:SetText("!")
    groupBadge:Hide()
    row.groupBadge = groupBadge
    
    local groupBg = MakeBadgeBg(groupBadge)
    groupBg:SetPoint("TOPLEFT", groupBadge, "TOPLEFT", -2, 2)
    groupBg:SetPoint("BOTTOMRIGHT", groupBadge, "BOTTOMRIGHT", 2, -2)
    groupBadge.bg = groupBg

    -- Glowing animation
    local ag = icon:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.4)
    alpha:SetToAlpha(1.0)
    alpha:SetDuration(0.7)
    row.ag = ag

    -- Tooltip handling
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        frame:SetAlpha(1)
        local db = ns.Addon:Profile().reminder
        if db.showTooltip ~= false and self.spellLabel then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.spellLabel, 1, 1, 1)
            if self.missingFromGroup then
                GameTooltip:AddLine("Missing from group", 1, 0.6, 0.1)
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
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        frame:SetAlpha(0.7)
        GameTooltip:Hide()
    end)

    frame.rows[idx] = row
    return row
end

local function ResizeFrame(colCount)
    local w = PANEL_PAD * 2 + colCount * ICON_SIZE + (colCount - 1) * ICON_PAD
    local h = PANEL_PAD * 2 + ICON_SIZE
    frame:SetSize(w, h)
end

-- [ BLINK ] -------------------------------------------------------------------
local function StartBlink()
    for _, row in ipairs(frame.rows) do
        if row:IsShown() and row.required and not row.present then
            row.iconBorder:SetAlpha(0)
            row.ag:Play()
        else
            row.ag:Stop()
            row.iconBorder:SetAlpha(0)
            if not row.present then row.icon:SetAlpha(1) end
        end
    end
end

local function StopBlink()
    for _, row in ipairs(frame.rows) do
        row.ag:Stop()
        row.icon:SetAlpha(1)
    end
end

-- [ SHOW / HIDE ] -------------------------------------------------------------
function AuraReminder.Hide()
    if not frame then return end
    StopBlink()
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
    -- Hide all existing rows
    for _, row in ipairs(frame.rows) do row:Hide() end

    if #missing == 0 then AuraReminder.Hide(); return end

    ResizeFrame(#missing)

    local xOff = PANEL_PAD
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
        row:Show()
        -- Dim icons that are already present (show-all mode)
        if m.present then
            row.icon:SetAlpha(0.35)
            row.iconBorder:SetAlpha(0)
        else
            row.icon:SetAlpha(1)
        end
        xOff = xOff + ICON_SIZE + ICON_PAD
    end

    frame:Show()
    StartBlink()

    local db = ns.Addon:Profile().reminder
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
            local _, _, lvl = C_ChallengeMode.GetActiveKeystoneInfo()
            if (lvl or 0) >= db.minKeystoneLevel then return true end
        end
        return db.enabledDungeon
    elseif iType == "raid" then
        return db.enabledRaid
    end
    return false
end

local function CheckAndShow()
    if not ShouldActivate() then AuraReminder.Hide(); return end
    local db = ns.Addon:Profile().reminder
    if db.onlyOutOfCombat and InCombatLockdown() then AuraReminder.Hide(); return end
    -- GetMissing() has its own CanReadAuras() guard, but bail here too so we
    -- don't hide the frame mid-combat if it was already showing valid data.
    if InCombatLockdown() then return end
    local db = ns.Addon:Profile().reminder
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

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    watcher:RegisterEvent("CHALLENGE_MODE_START")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("UNIT_AURA")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")

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
            if not isActive or InCombatLockdown() then return end
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
            isActive = false
            AuraReminder.Hide()
            StopPeriodic()
            StopWeaponTicker()
            ScheduleCheck()

        elseif event == "PLAYER_REGEN_ENABLED" then
            if isActive then CheckAndShow() end

        elseif event == "PLAYER_REGEN_DISABLED" then
            local rdb = ns.Addon:Profile().reminder
            if rdb.onlyOutOfCombat then AuraReminder.Hide() end

        elseif event == "GROUP_ROSTER_UPDATE" then
            if isActive and not InCombatLockdown() then CheckAndShow() end

        elseif event == "UNIT_AURA" then
            local unit = ...
            local isParty = unit and (unit:sub(1,5) == "party" or unit:sub(1,4) == "raid")
            if unit ~= "player" and not isParty then return end
            local rdb = ns.Addon:Profile().reminder
            if not isActive then return end
            if not rdb.remindOnBuffLost then return end
            if rdb.onlyOutOfCombat and InCombatLockdown() then AuraReminder.Hide(); return end
            -- Coalesce burst: UNIT_AURA can fire many times per frame (one per member).
            -- Defer the actual scan to the next frame so N events = 1 scan.
            if not _unitAuraPending then
                _unitAuraPending = true
                C_Timer.After(0, function()
                    _unitAuraPending = false
                    if not isActive then return end
                    local cdb = ns.Addon:Profile().reminder
                    if cdb.onlyOutOfCombat and InCombatLockdown() then return end
                    local missing = ns.AuraList.GetMissing(cdb)
                    if #missing == 0 then
                        AuraReminder.Hide()
                    else
                        ShowMissing(missing)
                    end
                end)
            end
        end
    end)
end
