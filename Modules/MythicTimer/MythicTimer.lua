local ADDON_NAME, ns = ...
ns.MythicTimer = {}
local MT = ns.MythicTimer

-- [ CONSTANTS ] ---------------------------------------------------------------
local PLUS_2_FRACTION = 0.8   -- +2 at ≤ 80% of time limit
local PLUS_3_FRACTION = 0.6   -- +3 at ≤ 60% of time limit
local DEATH_PENALTY   = 5     -- seconds lost per death
local UPDATE_HZ       = 10    -- timer OnUpdate ticks per second
local TIME_BAR_H      = 16
local FORCES_BAR_H    = 12
local FRAME_W         = 320
local FRAME_W_WIDE    = 400   -- when showKillTimes is enabled
local FRAME_H         = 102   -- base height (before boss rows)
local BOSS_LINE_H     = 18    -- height per vertical boss entry
local HDR_Y           = -16   -- center of header content row (level + deaths)
local AFFIX_Y         = -32   -- center of affix names row (below header)
local TIME_BAR_Y      = -48   -- top of time progress bar
local BOSS_LIST_Y     = -70   -- top of first boss entry (below time bar)
local BORDER_COLOR    = { r = 0.133, g = 0.133, b = 0.133 }  -- #222222
local T = ns.Theme  -- populated by Theme.Init() before GetOrMakeFrame runs

-- [ LOCAL STATE ] -------------------------------------------------------------
local addon
local frame           -- event listener
local timerFrame      -- the visible UI frame
local isActive = false
local timerID         -- world elapsed timer id
local timeLimit       -- dungeon time limit (seconds)
local startTime       -- GetTime() snapshot when key started
local elapsedBase     -- elapsed seconds at last sync
local elapsedAccum    -- running accumulator since last sync
local deathCount, timeLost = 0, 0
local dungeonCompleted = false  -- true after CHALLENGE_MODE_COMPLETED, cleared on deactivate
local finalElapsed = nil        -- frozen elapsed seconds at completion
local pendingChatMsg = nil      -- queued completion message, sent after leaving the instance
local keystoneLevel = 0
local dungeonName = ""
local affixIDs = {}
local criteriaData = {}  -- { [i] = { desc, qty, total, completed } }
local bossKillTimes = {} -- [bossIdx] = elapsed seconds when boss was killed
local numBosses = 0
local bossesKilled = 0
local pullQty, pullTotal = 0, 0
local HideObjectiveTracker
local RestoreObjectiveTracker
local ApplyBlizzardBlockVisibility

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return addon.db.profile.mythicTimer end

local function Notify(msg)
    print(ns.Theme.EscapeColor("accent") .. "yaqol:|r " .. msg)
end

-- Format seconds → "MM:SS" or "-MM:SS" for overtime
local function FormatTime(sec)
    local sign = ""
    if sec < 0 then sign = "-"; sec = -sec end
    return sign .. format("%d:%02d", floor(sec / 60), sec % 60)
end

-- Colour a time string green/yellow/red based on remaining vs thresholds
local function ColourTime(remaining, limit)
    if remaining <= 0 then return "|cffee2222" end
    local pct = remaining / limit
    if pct > PLUS_2_FRACTION then return "|cff44ee44" end  -- green, on +3 pace
    if pct > (1 - PLUS_2_FRACTION) then return "|cffeeee44" end  -- yellow
    return "|cffee8822"  -- orange
end

-- Extract the last word of a boss name for compact display
local function TruncateBossName(name)
    if not name then return "?" end
    return name:match("(%S+)%s*$") or name
end

-- [ FONT SCALING ] ------------------------------------------------------------
-- Tag a FontString with its base (unscaled) size right after creation so we can
-- re-derive the correct size at any fontScale.
local function TagBaseSize(fs)
    if not fs then return end
    local _, size = fs:GetFont()
    if size then fs._baseSize = size end
end

-- Apply the current fontScale to a single FontString.
local function ScaleFontString(fs, scale)
    if not fs or not fs._baseSize then return end
    local path = fs:GetFont()
    if path then
        fs:SetFont(path, fs._baseSize * scale, "OUTLINE")
        fs:SetShadowColor(0, 0, 0, 0.5)
        fs:SetShadowOffset(1, -1)
    end
end

-- Apply fontScale to every FontString in the timer frame.
local function ApplyFontScale(f)
    local scale = cfg().fontScale or 1.0
    ScaleFontString(f.levelText, scale)
    ScaleFontString(f.deathText, scale)
    ScaleFontString(f.affixText, scale)
    ScaleFontString(f.timerText, scale)
    ScaleFontString(f.nextUpgradeText, scale)
    ScaleFontString(f.forcesText, scale)
    if f.bossFrames then
        for _, entry in ipairs(f.bossFrames) do
            ScaleFontString(entry.lbl, scale)
        end
    end
end

-- [ BACKDROP ] ----------------------------------------------------------------
-- Optional semi-transparent backdrop + 1px hairline borders.
-- Created once on demand, shown/hidden via setting.
local function EnsureBackdrop(f)
    if f.bgTex then return end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    f.bgTex = bg
    local r, g, b = BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b
    f.borderTop = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.borderTop:SetHeight(1); f.borderTop:SetPoint("TOPLEFT"); f.borderTop:SetPoint("TOPRIGHT")
    f.borderTop:SetColorTexture(r, g, b, 1)
    f.borderBot = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.borderBot:SetHeight(1); f.borderBot:SetPoint("BOTTOMLEFT"); f.borderBot:SetPoint("BOTTOMRIGHT")
    f.borderBot:SetColorTexture(r, g, b, 1)
    f.borderLeft = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.borderLeft:SetWidth(1); f.borderLeft:SetPoint("TOPLEFT"); f.borderLeft:SetPoint("BOTTOMLEFT")
    f.borderLeft:SetColorTexture(r, g, b, 1)
    f.borderRight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.borderRight:SetWidth(1); f.borderRight:SetPoint("TOPRIGHT"); f.borderRight:SetPoint("BOTTOMRIGHT")
    f.borderRight:SetColorTexture(r, g, b, 1)
end

local function UpdateBackdrop(f)
    local show = cfg().showBackdrop
    if show then EnsureBackdrop(f) end
    if f.bgTex then
        f.bgTex:SetShown(show)
        f.borderTop:SetShown(show)
        f.borderBot:SetShown(show)
        f.borderLeft:SetShown(show)
        f.borderRight:SetShown(show)
    end
end

-- [ UI CONSTRUCTION ] ---------------------------------------------------------
local function GetOrMakeFrame()
    if timerFrame then return timerFrame end
    local d = cfg()

    local f = CreateFrame("Frame", "yaqolMythicTimerFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = cfg()
        p.point, _, p.relPoint, p.x, p.y = self:GetPoint()
    end)

    -- HUD element: no background by default, no borders, no header chrome.
    -- Content floats directly over the game world.

    -- [ HEADER ROW ] ---------------------------------------------------------
    -- Key level indicator (large, bold)
    local levelText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Huge1")
    levelText:SetPoint("LEFT", f, "TOPLEFT", 10, HDR_Y)
    levelText:SetJustifyH("LEFT")
    ns.Theme:ApplyHudFont(levelText)
    TagBaseSize(levelText)
    f.levelText = levelText

    -- Death count: skull icon + compact text, anchored after level
    local deathIcon = f:CreateTexture(nil, "OVERLAY")
    deathIcon:SetSize(16, 16)
    deathIcon:SetPoint("LEFT", levelText, "RIGHT", 12, 0)
    deathIcon:SetAtlas("poi-graveyard-neutral")
    deathIcon:SetVertexColor(0.93, 0.13, 0.13, 1)
    deathIcon:Hide()
    f.deathIcon = deathIcon

    local deathText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
    deathText:SetPoint("LEFT", deathIcon, "RIGHT", 2, 0)
    deathText:SetJustifyH("LEFT")
    ns.Theme:ApplyHudFont(deathText)
    TagBaseSize(deathText)
    f.deathText = deathText

    -- Affix names — own row below the header, right-aligned.
    local affixText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    affixText:SetPoint("RIGHT", f, "TOPRIGHT", -8, AFFIX_Y)
    affixText:SetJustifyH("RIGHT")
    affixText:SetTextColor(0.65, 0.65, 0.65, 1)
    ns.Theme:ApplyHudFont(affixText)
    TagBaseSize(affixText)
    f.affixText = affixText

    -- [ TIME BAR ] ------------------------------------------------------------
    local barW = FRAME_W - 20
    local timeBarBg = f:CreateTexture(nil, "ARTWORK")
    timeBarBg:SetSize(barW, TIME_BAR_H)
    timeBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, TIME_BAR_Y)
    ns.Theme:ApplyBarBg(timeBarBg)
    f.timeBarBg = timeBarBg

    local timeBarFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    timeBarFill:SetSize(1, TIME_BAR_H)
    timeBarFill:SetPoint("TOPLEFT", timeBarBg, "TOPLEFT", 0, 0)
    ns.Theme:ApplyBarFill(timeBarFill)
    f.timeBarFill = timeBarFill

    -- +3 marker on time bar (60% of bar width)
    local mark3 = f:CreateTexture(nil, "ARTWORK", nil, 2)
    mark3:SetSize(1, TIME_BAR_H)
    mark3:SetColorTexture(0.3, 1.0, 0.3, 0.7)
    f.mark3 = mark3

    -- +2 marker on time bar (80% of bar width)
    local mark2 = f:CreateTexture(nil, "ARTWORK", nil, 2)
    mark2:SetSize(1, TIME_BAR_H)
    mark2:SetColorTexture(1.0, 1.0, 0.3, 0.7)
    f.mark2 = mark2

    -- Timer countdown text (centered over time bar)
    local timerText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Med3")
    timerText:SetPoint("CENTER", timeBarBg, "CENTER", 0, 0)
    timerText:SetJustifyH("CENTER")
    ns.Theme:ApplyHudFont(timerText)
    TagBaseSize(timerText)
    f.timerText = timerText

    -- Next upgrade countdown (right-aligned on time bar)
    local nextUpgradeText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
    nextUpgradeText:SetPoint("RIGHT", timeBarBg, "RIGHT", -4, 0)
    nextUpgradeText:SetJustifyH("RIGHT")
    ns.Theme:ApplyHudFont(nextUpgradeText)
    TagBaseSize(nextUpgradeText)
    f.nextUpgradeText = nextUpgradeText

    -- [ FORCES BAR ] ---------------------------------------------------------
    local forcesBarBg = f:CreateTexture(nil, "ARTWORK")
    forcesBarBg:SetSize(barW, FORCES_BAR_H)
    ns.Theme:ApplyBarBg(forcesBarBg)
    f.forcesBarBg = forcesBarBg

    local forcesBarFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    forcesBarFill:SetSize(1, FORCES_BAR_H)
    forcesBarFill:SetPoint("TOPLEFT", forcesBarBg, "TOPLEFT", 0, 0)
    forcesBarFill:SetColorTexture(0.55, 0.72, 0.18, 1)
    f.forcesBarFill = forcesBarFill

    local forcesText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
    forcesText:SetPoint("CENTER", forcesBarBg, "CENTER", 0, 0)
    forcesText:SetJustifyH("CENTER")
    ns.Theme:ApplyHudFont(forcesText)
    TagBaseSize(forcesText)
    f.forcesText = forcesText

    -- [ BOSS LIST ] -----------------------------------------------------------
    f.bossFrames = {}

    f:SetPoint(
        d.point    or "CENTER",
        UIParent,
        d.relPoint or "CENTER",
        d.x        or 300,
        d.y        or 200
    )
    f:Hide()
    timerFrame = f
    ApplyFontScale(f)
    return f
end

-- [ BOSS FRAMES ] -------------------------------------------------------------
-- Create/recycle vertical boss entry slots.  Positioning happens in UpdateDisplay.
local function EnsureBossFrames(count)
    local f = GetOrMakeFrame()
    for i = 1, count do
        if not f.bossFrames[i] then
            local entry = CreateFrame("Button", nil, f)
            entry:SetHeight(18)
            local lbl = entry:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
            lbl:SetPoint("RIGHT", entry, "RIGHT", 0, 0)
            lbl:SetJustifyH("RIGHT")
            ns.Theme:ApplyHudFont(lbl)
            TagBaseSize(lbl)
            local scale = cfg().fontScale or 1.0
            ScaleFontString(lbl, scale)
            entry.lbl = lbl
            entry.fullName = nil
            entry.killTime = nil
            entry:SetScript("OnEnter", function(self)
                if self.fullName then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:AddLine(self.fullName, 1, 1, 1)
                    if self.killTime then
                        GameTooltip:AddLine("Killed at " .. FormatTime(self.killTime), 0.27, 0.93, 0.27)
                    end
                    GameTooltip:Show()
                end
            end)
            entry:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.bossFrames[i] = entry
        end
    end
    -- Hide extras
    for i = count + 1, #f.bossFrames do
        f.bossFrames[i]:Hide()
    end
end

-- [ DATA GATHERING ] ----------------------------------------------------------
local function GatherCriteriaData()
    local _, _, numCriteria = C_Scenario.GetStepInfo()
    numCriteria = numCriteria or 0

    -- Remember which boss slots were already completed before the refresh so we
    -- can detect newly-killed bosses and stamp their kill time.
    local prevBossCompleted = {}
    do
        local bIdx = 0
        for _, data in ipairs(criteriaData) do
            if not data.isWeighted then
                bIdx = bIdx + 1
                prevBossCompleted[bIdx] = data.completed
            end
        end
    end

    wipe(criteriaData)
    numBosses = 0
    bossesKilled = 0
    pullQty, pullTotal = 0, 0

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            local entry = {
                desc      = info.description,
                qty       = info.quantity,
                total     = info.totalQuantity,
                completed = info.completed,
                isWeighted = info.isWeightedProgress,
            }
            criteriaData[#criteriaData + 1] = entry  -- sequential; safe for ipairs
            if info.isWeightedProgress then
                -- quantity is a 0-100 percentage value for weighted-progress criteria
                pullQty   = info.quantity
                pullTotal = 100
            else
                -- This is a boss
                numBosses = numBosses + 1
                if info.completed then
                    bossesKilled = bossesKilled + 1
                    -- Record kill time the first time this boss flips to completed.
                    -- Re-sync from the world elapsed timer for accuracy (OnUpdate may lag).
                    -- Guard: elapsedBase is nil when this fires outside an active M+ timer
                    -- (e.g. world quest scenarios that also emit SCENARIO_CRITERIA_UPDATE).
                    if not prevBossCompleted[numBosses] and not bossKillTimes[numBosses] and elapsedBase then
                        local killElapsed = elapsedBase + (elapsedAccum or 0)
                        if timerID then
                            local _, worldSec = GetWorldElapsedTime(timerID)
                            if worldSec and worldSec > 0 then killElapsed = worldSec end
                        end
                        bossKillTimes[numBosses] = killElapsed
                    end
                end
            end
        end
    end
end

local function UpdateDeathCount()
    local count, lost = C_ChallengeMode.GetDeathCount()
    if count then
        deathCount = count
        timeLost = lost
    end
end

-- [ UI UPDATE ] ---------------------------------------------------------------
local function UpdateDisplay()
    local f = GetOrMakeFrame()
    local d = cfg()
    if not isActive or not d.enabled then
        f:Hide()
        return
    end

    -- Dynamic frame width based on showKillTimes
    local frameW = d.showKillTimes and FRAME_W_WIDE or FRAME_W
    local barW = frameW - 20
    f:SetWidth(frameW)

    -- Compute scaled layout dimensions
    local scale = d.fontScale or 1.0
    local timeBarH  = math.ceil(TIME_BAR_H * scale)
    local forcesBarH = math.ceil(FORCES_BAR_H * scale)
    local bossLineH = math.ceil(BOSS_LINE_H * scale)
    local hdrY      = math.floor(HDR_Y * scale)
    local affixY    = math.floor(AFFIX_Y * scale)
    local timeBarY  = math.floor(TIME_BAR_Y * scale)
    local bossListY = timeBarY - timeBarH - math.ceil(6 * scale)

    -- Reposition header elements
    f.levelText:ClearAllPoints()
    f.levelText:SetPoint("LEFT", f, "TOPLEFT", 10, hdrY)
    f.affixText:ClearAllPoints()
    f.affixText:SetPoint("RIGHT", f, "TOPRIGHT", -8, affixY)

    -- Reposition and resize time bar
    f.timeBarBg:ClearAllPoints()
    f.timeBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, timeBarY)
    f.timeBarBg:SetSize(barW, timeBarH)
    f.timeBarFill:SetHeight(timeBarH)

    -- Resize upgrade markers to match time bar height
    f.mark3:SetHeight(timeBarH)
    f.mark2:SetHeight(timeBarH)

    f.forcesBarBg:SetWidth(barW)
    f.forcesBarBg:SetHeight(forcesBarH)
    f.forcesBarFill:SetHeight(forcesBarH)

    -- Backdrop toggle
    UpdateBackdrop(f)

    -- Determine elapsed time
    local elapsed
    if dungeonCompleted and finalElapsed then
        elapsed = finalElapsed
    else
        elapsed = elapsedBase + elapsedAccum
    end
    local remaining = timeLimit - elapsed

    -- [ HEADER: KEY LEVEL ] --------------------------------------------------
    f.levelText:SetText(format("%s+%d|r", ns.Theme.EscapeColor("accent"), keystoneLevel))

    -- [ HEADER: DEATH COUNT ] ------------------------------------------------
    if deathCount > 0 then
        f.deathIcon:Show()
        f.deathText:SetText(format("|cffee2222%d  -%s|r", deathCount, FormatTime(timeLost)))
    else
        f.deathIcon:Hide()
        f.deathText:SetText("")
    end

    -- [ COMPLETION STATE ] ----------------------------------------------------
    if dungeonCompleted then
        local upgrades
        if     elapsed <= timeLimit * PLUS_3_FRACTION then upgrades = 3
        elseif elapsed <= timeLimit * PLUS_2_FRACTION then upgrades = 2
        elseif elapsed <= timeLimit                   then upgrades = 1
        else                                               upgrades = 0
        end
        local mainColour, label
        if     upgrades == 3 then mainColour = "|cff44ee44"; label = "TIMED  +3"
        elseif upgrades == 2 then mainColour = "|cffeeee44"; label = "TIMED  +2"
        elseif upgrades == 1 then mainColour = "|cffee8822"; label = "TIMED  +1"
        else                      mainColour = "|cffee2222"; label = "TIME EXPIRED"
        end
        f.timerText:SetText(mainColour .. label .. "|r")
        local diff = math.abs(remaining)
        if remaining >= 0 then
            f.nextUpgradeText:SetText(mainColour .. FormatTime(diff) .. " remaining|r")
        else
            f.nextUpgradeText:SetText("|cffee2222+" .. FormatTime(diff) .. " over|r")
        end
        -- Time bar: freeze at final fill, red if overtime
        local pct = math.min(elapsed / timeLimit, 1.0)
        local fillW = math.max(pct * barW, 1)
        f.timeBarFill:SetWidth(fillW)
        if elapsed > timeLimit then
            ns.Theme:PaintFill(f.timeBarFill, {0.93, 0.13, 0.13, 1})
        else
            ns.Theme:PaintFill(f.timeBarFill, T.barFill)
        end
    else
        -- [ ACTIVE TIMER ] ----------------------------------------------------
        local colour = ColourTime(remaining, timeLimit)
        f.timerText:SetText(colour .. FormatTime(remaining) .. "|r")

        -- Next upgrade countdown (show only the next threshold at risk)
        local plus3Remain = timeLimit * PLUS_3_FRACTION - elapsed
        local plus2Remain = timeLimit * PLUS_2_FRACTION - elapsed
        if plus3Remain > 0 then
            f.nextUpgradeText:SetText("|cff44ee44+3  " .. FormatTime(plus3Remain) .. "|r")
        elseif plus2Remain > 0 then
            f.nextUpgradeText:SetText("|cffeeee44+2  " .. FormatTime(plus2Remain) .. "|r")
        else
            f.nextUpgradeText:SetText("")
        end

        -- Time bar fill (elapsed as fraction of time limit)
        local pct = math.min(elapsed / timeLimit, 1.0)
        local fillW = math.max(pct * barW, 1)
        f.timeBarFill:SetWidth(fillW)
        if elapsed > timeLimit then
            ns.Theme:PaintFill(f.timeBarFill, {0.93, 0.13, 0.13, 1})
        else
            ns.Theme:PaintFill(f.timeBarFill, T.barFill)
        end
    end

    -- +3 / +2 markers on time bar
    f.mark3:ClearAllPoints()
    f.mark3:SetPoint("TOPLEFT", f.timeBarBg, "TOPLEFT", PLUS_3_FRACTION * barW, 0)
    f.mark3:Show()
    f.mark2:ClearAllPoints()
    f.mark2:SetPoint("TOPLEFT", f.timeBarBg, "TOPLEFT", PLUS_2_FRACTION * barW, 0)
    f.mark2:Show()

    -- [ BOSS LIST ] -----------------------------------------------------------
    EnsureBossFrames(numBosses)
    local showKT = d.showKillTimes
    local bossIdx = 0
    for _, data in ipairs(criteriaData) do
        if not data.isWeighted then
            bossIdx = bossIdx + 1
            local entry = f.bossFrames[bossIdx]
            if entry then
                local color = data.completed
                    and "|cff44ee44"
                    or "|cff888888"
                local numStr = tostring(bossIdx)
                local nameStr = TruncateBossName(data.desc)
                local text
                if showKT then
                    local killStr = (data.completed and bossKillTimes[bossIdx])
                        and FormatTime(bossKillTimes[bossIdx]) or "--:--"
                    text = color .. killStr .. "  " .. numStr .. " " .. nameStr .. "|r"
                else
                    text = color .. numStr .. " " .. nameStr .. "|r"
                end
                entry.lbl:SetText(text)
                entry.fullName = data.desc
                entry.killTime = bossKillTimes[bossIdx]
                entry:SetWidth(frameW - 20)
                entry:ClearAllPoints()
                entry:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, bossListY - (bossIdx - 1) * bossLineH)
                entry:Show()
            end
        end
    end

    -- [ FORCES BAR ] ---------------------------------------------------------
    local forcesY = bossListY - numBosses * bossLineH - math.ceil(6 * scale)
    f.forcesBarBg:ClearAllPoints()
    f.forcesBarBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, forcesY)
    if pullTotal > 0 then
        local pullPct = pullQty / pullTotal
        local fillW = math.min(pullPct, 1.0) * barW
        f.forcesBarFill:SetWidth(math.max(fillW, 1))
        if pullQty >= pullTotal then
            ns.Theme:PaintFill(f.forcesBarFill, T.barFill)  -- accent: full
        else
            ns.Theme:PaintFill(f.forcesBarFill, {0.55, 0.72, 0.18, 1})  -- yellow-green: filling
        end
        f.forcesText:SetText(format("%s%.2f%%|r",
            (pullQty >= pullTotal) and ns.Theme.EscapeColor("accent") or "|cffffffff",
            pullPct * 100))
    else
        f.forcesBarFill:SetWidth(1)
        ns.Theme:PaintFill(f.forcesBarFill, T.barBg)
        f.forcesText:SetText("|cff666666Pull %|r")
    end

    -- Dynamic frame height: boss list + forces bar at bottom
    local totalH = -forcesY + forcesBarH + math.ceil(6 * scale)
    f:SetHeight(math.max(totalH, FRAME_H))
    f:Show()
end

-- [ TIMER ONUPDATE ] ----------------------------------------------------------
local updateAccum = 0
local function OnUpdate(self, elapsed)
    updateAccum = updateAccum + elapsed
    if updateAccum < (1 / UPDATE_HZ) then return end
    elapsedAccum = elapsedAccum + updateAccum
    updateAccum = 0
    UpdateDisplay()
end

-- [ ACTIVATION / DEACTIVATION ] -----------------------------------------------
local function ActivateTimer(worldTimerID, worldElapsed, limit)
    isActive = true
    dungeonCompleted = false
    finalElapsed = nil
    timerID = worldTimerID
    timeLimit = limit
    elapsedBase = worldElapsed
    elapsedAccum = 0
    updateAccum = 0
    wipe(bossKillTimes)

    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
    keystoneLevel = level or 0
    affixIDs = affixes or {}

    -- Populate affix names in the header text
    local currentAffixes = C_MythicPlus.GetCurrentAffixes() or {}
    local f = GetOrMakeFrame()
    local affixNames = {}
    for _, affixInfo in ipairs(currentAffixes) do
        local name = C_ChallengeMode.GetAffixInfo(affixInfo.id)
        if name then affixNames[#affixNames + 1] = name end
    end
    f.affixText:SetText(table.concat(affixNames, " · "))

    local scenarioName = C_Scenario.GetInfo()
    dungeonName = scenarioName or "Mythic+"

    UpdateDeathCount()
    GatherCriteriaData()

    f:SetScript("OnUpdate", OnUpdate)
    UpdateDisplay()
end

local function DeactivateTimer()
    isActive = false
    dungeonCompleted = false
    finalElapsed = nil
    timerID = nil
    wipe(bossKillTimes)
    RestoreObjectiveTracker()
    local f = timerFrame
    if f then
        f:SetScript("OnUpdate", nil)
        -- Clear affix text
        if f.affixText then f.affixText:SetText("") end
        f:Hide()
    end
end

-- [ TIMER DISCOVERY ] ---------------------------------------------------------
-- Scan world elapsed timers for an active challenge mode timer.
local function CheckTimers(...)
    for i = 1, select("#", ...) do
        local id = select(i, ...)
        local _, elapsed, timerType = GetWorldElapsedTime(id)
        if timerType == Enum.WorldElapsedTimerTypes.ChallengeMode then
            local mapID = C_ChallengeMode.GetActiveChallengeMapID()
            if mapID then
                local _, _, limit = C_ChallengeMode.GetMapUIInfo(mapID)
                ActivateTimer(id, elapsed, limit)
                return
            end
        end
    end
    -- No valid timer found
    if isActive then DeactivateTimer() end
end

-- [ EVENT DISPATCH ] ----------------------------------------------------------
local function OnEvent(self, event, ...)
    if event == "CHALLENGE_MODE_START" then
        CheckTimers(GetWorldElapsedTimers())
        HideObjectiveTracker()
        ApplyBlizzardBlockVisibility()

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        RestoreObjectiveTracker()
        dungeonCompleted = true  -- keep frame alive until player leaves the dungeon
        finalElapsed = elapsedBase + elapsedAccum
        if timerFrame then
            timerFrame:SetScript("OnUpdate", nil)  -- freeze display at final time
        end
        UpdateDisplay()  -- render completion state
        -- Optional party chat announcement.
        -- SendChatMessage is blocked inside instances (12.0 restriction), so we
        -- build the message now (while the run data is still available) and queue
        -- it; PLAYER_ENTERING_WORLD fires it once the player is back in the world.
        local d = cfg()
        if d.completionMsg and d.completionMsgText and d.completionMsgText ~= "" then
            local elapsed = finalElapsed
            local remaining = timeLimit - elapsed
            local upgrades = 0
            if     elapsed <= timeLimit * PLUS_3_FRACTION then upgrades = 3
            elseif elapsed <= timeLimit * PLUS_2_FRACTION then upgrades = 2
            elseif elapsed <= timeLimit                   then upgrades = 1
            end
            local overtime = remaining < 0
            local diff = math.abs(remaining)
            local timeStr = FormatTime(diff)
            local upgradeStr = upgrades > 0 and ("+" .. upgrades) or "FAILED"
            local msg = d.completionMsgText
            msg = msg:gsub("{dungeon}",  dungeonName or "Mythic+")
            msg = msg:gsub("{level}",    tostring(keystoneLevel))
            msg = msg:gsub("{time}",     timeStr)
            msg = msg:gsub("{overtime}", overtime and timeStr or "on time")
            msg = msg:gsub("{deaths}",   tostring(deathCount))
            msg = msg:gsub("{upgrades}", upgradeStr)
            local channel = d.completionMsgChannel or "PARTY"
            if channel == "PARTY" and not IsInGroup() then channel = "SAY" end
            pendingChatMsg = { text = msg, channel = channel }
        end

    elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        UpdateDeathCount()

    elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_UPDATE" then
        GatherCriteriaData()

    elseif event == "WORLD_STATE_TIMER_START" then
        local timerId = ...
        CheckTimers(timerId)

    elseif event == "WORLD_STATE_TIMER_STOP" then
        local timerId = ...
        if timerID and timerID == timerId then
            -- freeze the display but keep it visible; PLAYER_ENTERING_WORLD cleans up on zone-out
            if timerFrame then timerFrame:SetScript("OnUpdate", nil) end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Send queued completion message now that we're outside the instance.
        if pendingChatMsg then
            local m = pendingChatMsg
            pendingChatMsg = nil
            local _, iType = GetInstanceInfo()
            if iType == "none" or iType == nil then
                if m.channel == "PARTY" and not IsInGroup() then
                    -- Group disbanded before we could send; silently discard.
                else
                    SendChatMessage(m.text, m.channel)
                end
            end
            -- If still in an instance (e.g. stayed for loot), discard — don't
            -- spam on every zone transition.
        end
        -- On login/reload, check if we're already in a M+ dungeon
        if C_ChallengeMode.IsChallengeModeActive() then
            CheckTimers(GetWorldElapsedTimers())
            HideObjectiveTracker()
        else
            DeactivateTimer()
            RestoreObjectiveTracker()
        end
    end
end

-- [ OBJECTIVE TRACKER MANAGEMENT ] -------------------------------------------
-- When hideBlizzard is on: hide the entire ObjectiveTrackerFrame for the
-- duration of the key so quest objectives, mob count, and all other tracker
-- elements stay off-screen. A secure hook on ObjectiveTrackerFrame:Show keeps
-- it suppressed even when Blizzard's code tries to re-show it (e.g. on every
-- SCENARIO_CRITERIA_UPDATE / mob kill).
local objTrackerHidden = false
local objTrackerHooked = false

local function HookObjectiveTrackerShow()
    if objTrackerHooked then return end
    if not ObjectiveTrackerFrame then return end
    objTrackerHooked = true
    hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
        if objTrackerHidden then
            self:Hide()
        end
    end)
end

HideObjectiveTracker = function()
    if objTrackerHidden then return end
    if not cfg().enabled or not cfg().hideBlizzard then return end
    if not ObjectiveTrackerFrame then return end
    HookObjectiveTrackerShow()
    objTrackerHidden = true
    ObjectiveTrackerFrame:Hide()
end

RestoreObjectiveTracker = function()
    if not objTrackerHidden then return end
    objTrackerHidden = false
    if not ObjectiveTrackerFrame then return end
    ObjectiveTrackerFrame:Show()
end

-- [ BLIZZARD BLOCK MANAGEMENT ] -----------------------------------------------
-- Optionally hide the default Blizzard Challenge Mode block in the objective
-- tracker so it doesn't duplicate our display.
-- Targets three distinct Blizzard frames:
--   1. ScenarioObjectiveTracker.ChallengeModeBlock — timer + affixes
--   2. ScenarioObjectiveTracker.ObjectivesBlock    — boss kills + mob count criteria
--   3. ScenarioTimerFrame                          — standalone HUD timer bar
local blizzBlockHooked = false

-- Immediately apply the current hideBlizzard setting to any already-visible block.
ApplyBlizzardBlockVisibility = function()
    local enabled = cfg().enabled and cfg().hideBlizzard
    if ScenarioObjectiveTracker then
        local challengeBlock = ScenarioObjectiveTracker.ChallengeModeBlock
        if challengeBlock then
            if enabled and challengeBlock:IsShown() then challengeBlock:Hide() end
        end
        local objectivesBlock = ScenarioObjectiveTracker.ObjectivesBlock
        if objectivesBlock then
            if enabled and objectivesBlock:IsShown() then objectivesBlock:Hide() end
        end
        if not enabled then
            ScenarioObjectiveTracker:MarkDirty()
        end
    end
    if ScenarioTimerFrame then
        if enabled then
            ScenarioTimerFrame:Hide()
        end
    end
    -- Also hide the full objective tracker sidebar while key is active
    if enabled and C_ChallengeMode.IsChallengeModeActive() then
        HideObjectiveTracker()
    elseif not enabled then
        RestoreObjectiveTracker()
    end
end

local function HookBlizzardBlock()
    if blizzBlockHooked then return end
    blizzBlockHooked = true

    local function AttachHook()
        if not ScenarioObjectiveTracker then return false end
        local challengeBlock = ScenarioObjectiveTracker.ChallengeModeBlock
        local objectivesBlock = ScenarioObjectiveTracker.ObjectivesBlock
        if not challengeBlock then return false end

        hooksecurefunc(challengeBlock, "Show", function(block)
            if cfg().enabled and cfg().hideBlizzard and C_ChallengeMode.IsChallengeModeActive() then block:Hide() end
        end)
        if objectivesBlock then
            hooksecurefunc(objectivesBlock, "Show", function(block)
                if cfg().enabled and cfg().hideBlizzard and C_ChallengeMode.IsChallengeModeActive() then block:Hide() end
            end)
        end
        if ScenarioTimerFrame then
            hooksecurefunc(ScenarioTimerFrame, "Show", function(f)
                if cfg().enabled and cfg().hideBlizzard and C_ChallengeMode.IsChallengeModeActive() then f:Hide() end
            end)
        end
        -- Hide immediately in case blocks are already shown (e.g. /reload inside a key).
        ApplyBlizzardBlockVisibility()
        return true
    end

    if AttachHook() then return end

    -- Blizzard_ObjectiveTracker not loaded yet — wait for it.
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(_, ev, name)
        if ev == "ADDON_LOADED" and name ~= "Blizzard_ObjectiveTracker" then return end
        if AttachHook() then hookFrame:UnregisterAllEvents() end
    end)
end

-- [ PUBLIC API ] --------------------------------------------------------------
function MT.Init(addonObj)
    addon = addonObj
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    GetOrMakeFrame()  -- pre-create for LayoutMode
    MT.Refresh(addon)
    HookBlizzardBlock()
end

function MT.Refresh(addonObj)
    addon = addonObj or addon
    local d = cfg()

    local events = {
        "CHALLENGE_MODE_START",
        "CHALLENGE_MODE_COMPLETED",
        "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
        "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_UPDATE",
        "WORLD_STATE_TIMER_START",
        "WORLD_STATE_TIMER_STOP",
        "PLAYER_ENTERING_WORLD",
    }
    for _, ev in ipairs(events) do
        if d.enabled then
            frame:RegisterEvent(ev)
        else
            frame:UnregisterEvent(ev)
        end
    end

    -- If disabled mid-run, hide the frame
    if not d.enabled and isActive then
        DeactivateTimer()
    end

    -- Apply hideBlizzard immediately (handles toggle from options and /reload inside a key)
    ApplyBlizzardBlockVisibility()

    -- Apply font scale to all text elements
    if timerFrame then ApplyFontScale(timerFrame) end

    -- If enabled and already in a key, activate
    if d.enabled and C_ChallengeMode.IsChallengeModeActive() then
        CheckTimers(GetWorldElapsedTimers())
    end
end

function MT.GetFrame()
    return GetOrMakeFrame()
end

function MT.IsActive()
    return isActive
end

-- [ DEMO / TEST MODE ] --------------------------------------------------------
-- Simulates a dungeon run so the user can see the timer in action.
-- Runs in an infinite loop at 30× speed until explicitly stopped.
local demoActive = false
local demoTickers = {}   -- all pending C_Timer handles so we can cancel them

local DEMO_DUNGEON        = "The Stonevault"
local DEMO_LEVEL          = 12
local DEMO_TIME_LIMIT     = 2100  -- 35:00
local DEMO_BOSSES         = { "Skarmorak", "Master Machinist", "Void Speaker Eirich", "Speaker Shadowcrown" }
local DEMO_PULL_TOTAL     = 320
local DEMO_BOSS_KILL_TIMES = { 540, 1020, 1380, 1800 }  -- sim elapsed when each boss dies
local DEMO_AFFIX_IDS      = { 9, 8, 124 }               -- Tyrannical, Sanguine, Storming

-- Timeline: { real_seconds, sim_elapsed, deaths, timeLost, pull, bossKills }
-- Runs at 30× speed: 1 real second ≈ 30 simulated seconds.
local DEMO_TIMELINE = {
    {  2,   120, 0,  0,   42, 0 },   -- early trash
    {  5,   300, 0,  0,   95, 0 },   -- more trash
    {  8,   420, 1,  5,  120, 0 },   -- first death
    { 10,   540, 1,  5,  120, 1 },   -- Boss 1 dead  (9:00)
    { 13,   720, 1,  5,  165, 1 },   -- trash
    { 16,   900, 2, 10,  200, 1 },   -- second death
    { 18,  1020, 2, 10,  200, 2 },   -- Boss 2 dead  (17:00)
    { 21,  1200, 2, 10,  248, 2 },   -- trash
    { 24,  1380, 2, 10,  248, 3 },   -- Boss 3 dead  (23:00)
    { 27,  1560, 2, 10,  300, 3 },   -- trash
    { 30,  1680, 2, 10,  320, 3 },   -- pull complete
    { 33,  1800, 2, 10,  320, 4 },   -- Boss 4 dead — timed! (30:00)
}
local DEMO_CYCLE_LEN = 40  -- real seconds per cycle (extra view time at end before restart)

local function DemoSetState(elapsed, deaths, lost, pull, bossKills)
    elapsedBase  = elapsed
    elapsedAccum = 0
    updateAccum  = 0
    deathCount   = deaths
    timeLost     = lost
    pullQty      = pull
    pullTotal    = DEMO_PULL_TOTAL
    -- Rebuild criteria
    wipe(criteriaData)
    wipe(bossKillTimes)
    numBosses    = #DEMO_BOSSES
    bossesKilled = bossKills
    for i, name in ipairs(DEMO_BOSSES) do
        criteriaData[#criteriaData + 1] = {
            desc      = name,
            qty       = i <= bossKills and 1 or 0,
            total     = 1,
            completed = i <= bossKills,
            isWeighted = false,
        }
        if i <= bossKills then
            bossKillTimes[i] = DEMO_BOSS_KILL_TIMES[i] or elapsed
        end
    end
    -- Enemy forces entry
    criteriaData[#criteriaData + 1] = {
        desc       = "Enemy Forces",
        qty        = pull,
        total      = DEMO_PULL_TOTAL,
        completed  = pull >= DEMO_PULL_TOTAL,
        isWeighted = true,
    }
end

local function DemoSchedule(realDelay, fn)
    local t = C_Timer.NewTimer(realDelay, fn)
    demoTickers[#demoTickers + 1] = t
    return t
end

-- Runs one complete demo cycle, then restarts itself if still active.
local function DemoRunCycle()
    wipe(demoTickers)
    dungeonCompleted = false
    finalElapsed = nil
    DemoSetState(0, 0, 0, 0, 0)
    local f = GetOrMakeFrame()
    f:SetScript("OnUpdate", OnUpdate)
    UpdateDisplay()

    for _, step in ipairs(DEMO_TIMELINE) do
        DemoSchedule(step[1], function()
            if not demoActive then return end
            DemoSetState(step[2], step[3], step[4], step[5], step[6])
        end)
    end

    -- After the last boss dies, freeze and show completion state
    DemoSchedule(34, function()
        if not demoActive then return end
        dungeonCompleted = true
        finalElapsed = DEMO_BOSS_KILL_TIMES[4]
        local f = GetOrMakeFrame()
        f:SetScript("OnUpdate", nil)
        UpdateDisplay()
    end)

    -- After the cycle ends, pause briefly then loop
    DemoSchedule(DEMO_CYCLE_LEN, function()
        if demoActive then
            dungeonCompleted = false
            finalElapsed = nil
            DemoRunCycle()
        end
    end)
end

function MT.StartDemo()
    if demoActive then MT.StopDemo() end
    if isActive then
        Notify("Cannot start demo while a real M+ key is running.")
        return
    end
    demoActive = true
    isActive      = true
    timerID       = 999
    timeLimit     = DEMO_TIME_LIMIT
    keystoneLevel = DEMO_LEVEL
    dungeonName   = DEMO_DUNGEON
    affixIDs      = {}

    -- Populate demo affix names
    local f = GetOrMakeFrame()
    local affixNames = {}
    for _, id in ipairs(DEMO_AFFIX_IDS) do
        local name = C_ChallengeMode.GetAffixInfo(id)
        if name then affixNames[#affixNames + 1] = name end
    end
    f.affixText:SetText(table.concat(affixNames, " · "))

    Notify("Demo started — simulating a +" .. DEMO_LEVEL .. " " .. DEMO_DUNGEON .. " run.")
    DemoRunCycle()
end

function MT.StopDemo()
    if not demoActive then return end
    demoActive = false
    dungeonCompleted = false
    finalElapsed = nil
    for _, t in ipairs(demoTickers) do
        t:Cancel()
    end
    wipe(demoTickers)
    DeactivateTimer()
end

function MT.IsDemoActive()
    return demoActive
end
