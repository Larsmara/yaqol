local ADDON_NAME, ns = ...
ns.AuraReminder = {}
local AuraReminder = ns.AuraReminder

-- [ CONSTANTS ] -------------------------------------------------------------------
local ICON_SIZE    = 36
local ICON_PAD     = 4
local PANEL_PAD    = 6

-- [ STATE ] -------------------------------------------------------------------
local frame, rows
local inInstance   = false
local isActive     = false
local dismissTimer = nil

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

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    iconBorder:SetPoint("CENTER", icon, "CENTER")
    iconBorder:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
    iconBorder:SetBlendMode("ADD")
    iconBorder:SetAlpha(0)
    row.iconBorder = iconBorder

    -- Glowing animation
    local ag = iconBorder:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.2)
    alpha:SetToAlpha(1.0)
    alpha:SetDuration(0.7)
    alpha:SetSmoothing("IN_OUT")
    row.ag = ag

    -- Tooltip handling
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        frame:SetAlpha(1)
        local db = ns.Addon:Profile().reminder
        if db.showTooltip ~= false and self.spellLabel then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.spellLabel, 1, 1, 1)
            if self.required then GameTooltip:AddLine("Required", 1, 0.3, 0.3)
            else GameTooltip:AddLine("Optional", 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self) 
        frame:SetAlpha(0.7)
        GameTooltip:Hide() 
    end)

    -- Make dragging pass through to parent
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function() frame:StartMoving() end)
    row:SetScript("OnDragStop", function() 
        frame:StopMovingOrSizing()
        local db = ns.Addon:Profile().reminder
        db.point, _, db.relPoint, db.x, db.y = frame:GetPoint()
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
        if row:IsShown() and row.required then
            row.iconBorder:SetVertexColor(1, 0.4, 0.4, 1) -- red alert border
            row.iconBorder:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
            row.ag:Play()
        else
            row.ag:Stop()
            row.iconBorder:SetVertexColor(0.8, 0.8, 0.8, 0.5) -- calm border
            row.iconBorder:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
            row.iconBorder:SetAlpha(0)
        end
    end
end

local function StopBlink()
    for _, row in ipairs(frame.rows) do
        row.ag:Stop()
    end
end

-- [ SHOW / HIDE ] -------------------------------------------------------------
function AuraReminder.Hide()
    if not frame then return end
    StopBlink()
    if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
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
        row:Show()
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
            local lvl = tonumber(C_ChallengeMode.GetActiveKeystoneInfo()) or 0
            if lvl >= db.minKeystoneLevel then return true end
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
    local missing = ns.AuraList.GetMissing(db)
    ShowMissing(missing)
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
                    local missing = ns.AuraList.GetMissing(rdb)
                    if #missing > 0 then
                        ShowMissing(missing)
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
        -- We need the 1-second ticker only for classes whose weapon buff check
        -- relies on GetWeaponEnchantInfo() rather than UNIT_AURA.
        -- Currently that is only DEATHKNIGHT (runeforge).
        -- All other weapon imbues (shaman, rogue poisons) fire UNIT_AURA normally.
        local _, cls = UnitClass("player")
        return cls == "DEATHKNIGHT"
    end
    local function StartWeaponTicker()
        if weaponTicker then return end
        if not HasWeaponBuffDefs() then return end
        weaponTicker = C_Timer.NewTicker(1, function()
            if not isActive or InCombatLockdown() then return end
            local wdb = ns.Addon:Profile().reminder
            if wdb.onlyOutOfCombat and InCombatLockdown() then return end
            local missing = ns.AuraList.GetMissing(wdb)
            if #missing > 0 then
                ShowMissing(missing)
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
    local pendingSeq = 0
    local function ScheduleCheck()
        pendingSeq = pendingSeq + 1
        local seq = pendingSeq
        local delay = ns.Addon:Profile().reminder.enterDelay
        -- First check next frame (GetInstanceInfo is valid immediately)
        C_Timer.After(0, function()
            if seq ~= pendingSeq then return end
            isActive = ShouldActivate()
            if isActive then
                CheckAndShow()
                StartPeriodic()
                StartWeaponTicker()
            else
                -- Not in instance yet on frame 0 — try again after full delay
                C_Timer.After(delay, function()
                    if seq ~= pendingSeq then return end
                    isActive = ShouldActivate()
                    if isActive then
                        CheckAndShow()
                        StartPeriodic()
                        StartWeaponTicker()
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
            local missing = ns.AuraList.GetMissing(rdb)
            if #missing == 0 then
                AuraReminder.Hide()
            else
                ShowMissing(missing)
            end
        end
    end)
end
