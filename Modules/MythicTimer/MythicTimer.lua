local ADDON_NAME, ns = ...
ns.MythicTimer = {}
local MT = ns.MythicTimer

-- [ CONSTANTS ] ---------------------------------------------------------------
local PLUS_2_FRACTION = 0.8   -- +2 at ≤ 80% of time limit
local PLUS_3_FRACTION = 0.6   -- +3 at ≤ 60% of time limit
local DEATH_PENALTY   = 5     -- seconds lost per death
local UPDATE_HZ       = 10    -- timer OnUpdate ticks per second
local BAR_W, BAR_H    = 300, 14
local FRAME_W         = 320
local BOSS_ICON_SIZE  = 20
local MT_HEADER_H     = 40    -- height of the DiamondMetal header band
local KILL_TIME_W     = 54    -- width reserved for kill-time labels (left boss column)
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

-- Show/update the timed-key completion banner.
-- Called when CHALLENGE_MODE_COMPLETED fires, or from UpdateDisplay when dungeonCompleted=true.
local function ShowTimedBanner(elapsed, limit)
    local f = timerFrame
    if not f then return end

    local remaining = limit - elapsed
    local upgrades
    if     elapsed <= limit * PLUS_3_FRACTION then upgrades = 3
    elseif elapsed <= limit * PLUS_2_FRACTION then upgrades = 2
    elseif elapsed <= limit                   then upgrades = 1
    else                                           upgrades = 0
    end

    -- Colour and text
    local mainColour, label
    if upgrades == 3 then
        mainColour = "|cff44ee44"; label = "TIMED  +3"
    elseif upgrades == 2 then
        mainColour = "|cffeeee44"; label = "TIMED  +2"
    elseif upgrades == 1 then
        mainColour = "|cffee8822"; label = "TIMED  +1"
    else
        mainColour = "|cffee2222"; label = "TIME EXPIRED"
    end

    -- Sub-line: final elapsed and how far under/over time
    local diff = math.abs(remaining)
    local diffStr = FormatTime(diff)
    local subLine
    if remaining >= 0 then
        subLine = string.format("%s with %s remaining|r", mainColour, diffStr)
    else
        subLine = string.format("|cffee2222+%s over the time limit|r", diffStr)
    end

    f.timedBannerText:SetText(mainColour .. label .. "|r")
    f.timedBannerSub:SetText(subLine)

    -- Death count line
    if deathCount > 0 then
        f.timedBannerDeaths:SetText(string.format("|cffee4444%d death%s|r  |cff888888(-%s penalty)|r",
            deathCount, deathCount == 1 and "" or "s", FormatTime(timeLost)))
    else
        f.timedBannerDeaths:SetText("|cff44ee44No deaths|r")
    end

    -- Colour the body bg to give a faint tint
    local r, g, b = 0.04, 0.07, 0.02
    if upgrades == 0 then r, g, b = 0.07, 0.02, 0.02 end
    f.timedBannerBg:SetColorTexture(r, g, b, 0.92)

    f.timedBanner:Show()
end

local function HideTimedBanner()
    local f = timerFrame
    if f and f.timedBanner then f.timedBanner:Hide() end
end

-- [ UI CONSTRUCTION ] ---------------------------------------------------------
local function GetOrMakeFrame()
    if timerFrame then return timerFrame end
    local d = cfg()

    local f = CreateFrame("Frame", "yaqolMythicTimerFrame", UIParent)
    f:SetSize(FRAME_W, 160)
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

    -- Body background: theme-aware texture on BACKGROUND layer.
    -- FlatSkin: solid themed color. BlizzardSkin: dark dialog texture tinted to theme bg.
    local bodyBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    if T.skin == "blizzard" then
        bodyBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
        bodyBg:SetHorizTile(true); bodyBg:SetVertTile(true)
        bodyBg:SetVertexColor(T.bg[1], T.bg[2], T.bg[3], T.bg[4])
    else
        bodyBg:SetColorTexture(T.bgPanel[1], T.bgPanel[2], T.bgPanel[3], T.bgPanel[4])
    end
    bodyBg:SetAllPoints()

    -- Dialog NineSlice border (same art as the Options panel) — overhangs 5 px outside f.
    ns.Theme:ApplyBorder(f)

    -- Header band (same height / art as the Options panel header).
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(FRAME_W, MT_HEADER_H)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    ns.Theme:ApplyHeader(header)

    -- Dungeon medallion icon — lives inside the header (set in ActivateTimer)
    local dungeonIcon = header:CreateTexture(nil, "ARTWORK")
    dungeonIcon:SetSize(24, 24)
    dungeonIcon:SetPoint("LEFT", header, "LEFT", 10, 0)
    dungeonIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    dungeonIcon:Hide()
    f.dungeonIcon = dungeonIcon

    -- Dungeon name + key level — inside the header, right of the icon.
    -- Right bound is inset from right edge to leave space for affix icons.
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT",  header, "LEFT",  40, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -68, 0)
    title:SetJustifyH("LEFT")
    f.title = title

    -- Affix icons — up to 3 small icons right-aligned inside the header.
    -- Populated in ActivateTimer from C_MythicPlus.GetCurrentAffixes().
    local AFFIX_SZ = 16
    f.affixIcons = {}
    f.affixIDs   = {}  -- store affix IDs for tooltip lookup
    for a = 1, 3 do
        local aIcon = header:CreateTexture(nil, "ARTWORK")
        aIcon:SetSize(AFFIX_SZ, AFFIX_SZ)
        aIcon:SetPoint("RIGHT", header, "RIGHT", -(2 + (3 - a) * (AFFIX_SZ + 3)), 0)
        aIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        aIcon:Hide()
        f.affixIcons[a] = aIcon
        -- Invisible button for tooltip (textures can't receive mouse events)
        local aBtn = CreateFrame("Button", nil, header)
        aBtn:SetAllPoints(aIcon)
        aBtn:SetScript("OnEnter", function(self)
            local id = f.affixIDs[a]
            if id then
                local name, desc = C_ChallengeMode.GetAffixInfo(id)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(name or "Affix", 1, 1, 1)
                if desc then GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end
        end)
        aBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Timer display (large) — starts 4 px below the header band
    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    timerText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(MT_HEADER_H + 4))
    timerText:SetJustifyH("LEFT")
    f.timerText = timerText

    -- +3 / +2 pace labels — GameFontNormalHuge is ~22 px tall, add 4 px gap
    local paceText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    paceText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(MT_HEADER_H + 30))
    paceText:SetJustifyH("LEFT")
    f.paceText = paceText

    -- Section divider — GameFontNormal ~14 px, 4 px gap below paceText
    local sectionDiv = f:CreateTexture(nil, "ARTWORK")
    sectionDiv:SetHeight(1)
    sectionDiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  10, -(MT_HEADER_H + 46))
    sectionDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(MT_HEADER_H + 46))
    sectionDiv:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Progress bar background
    local barY = -(MT_HEADER_H + 48)
    local barBg = f:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, BAR_H)
    barBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, barY)
    ns.Theme:ApplyBarBg(barBg)
    f.barBg = barBg

    -- Progress bar fill
    local barFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    barFill:SetSize(1, BAR_H)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    ns.Theme:ApplyBarFill(barFill)
    f.barFill = barFill

    -- +3 marker on progress bar
    local mark3 = f:CreateTexture(nil, "ARTWORK", nil, 2)
    mark3:SetSize(1, BAR_H)
    mark3:SetColorTexture(0.3, 1.0, 0.3, 0.7)
    f.mark3 = mark3

    -- +2 marker on progress bar
    local mark2 = f:CreateTexture(nil, "ARTWORK", nil, 2)
    mark2:SetSize(1, BAR_H)
    mark2:SetColorTexture(1.0, 1.0, 0.3, 0.7)
    f.mark2 = mark2

    -- Bar percentage label  (removed — bar is now pull-count progress, label rendered inline)

    -- Death count (skull icon + text)
    local deathIcon = f:CreateTexture(nil, "OVERLAY")
    deathIcon:SetSize(14, 14)
    deathIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -108)
    deathIcon:SetAtlas("poi-graveyard-neutral")
    deathIcon:SetVertexColor(0.93, 0.13, 0.13, 1)
    deathIcon:Hide()
    f.deathIcon = deathIcon

    local deathText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deathText:SetPoint("LEFT", deathIcon, "RIGHT", 4, 0)
    deathText:SetJustifyH("LEFT")
    f.deathText = deathText

    -- Pull count label (centered on the bar)
    local pullText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pullText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
    pullText:SetJustifyH("CENTER")
    f.pullText = pullText

    -- Boss progress area (dynamic icons/text)
    -- We'll create boss entries dynamically
    f.bossFrames = {}

    -- ── TIMED BANNER ─────────────────────────────────────────────────────
    -- Shown when CHALLENGE_MODE_COMPLETED fires; replaces the timer text area.
    -- Sits in its own DIALOG-strata child so it layers above the body texture.
    local banner = CreateFrame("Frame", nil, f)
    banner:SetPoint("TOPLEFT",     f, "TOPLEFT",     4, -(MT_HEADER_H))
    banner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    banner:SetFrameLevel(f:GetFrameLevel() + 20)
    banner:Hide()
    f.timedBanner = banner

    local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints()
    bannerBg:SetColorTexture(0.04, 0.03, 0.02, 0.92)
    f.timedBannerBg = bannerBg

    local bannerStar = banner:CreateTexture(nil, "ARTWORK")
    bannerStar:SetSize(32, 32)
    bannerStar:SetAtlas("UI-Frame-DiamondMetal-Header-CornerLeft")
    bannerStar:SetPoint("LEFT", banner, "LEFT", 8, 0)
    bannerStar:Hide()
    f.timedBannerStar = bannerStar

    local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    bannerText:SetPoint("CENTER", banner, "CENTER", 0, 0)
    bannerText:SetJustifyH("CENTER")
    f.timedBannerText = bannerText

    local bannerSub = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bannerSub:SetPoint("TOP", bannerText, "BOTTOM", 0, -4)
    bannerSub:SetJustifyH("CENTER")
    f.timedBannerSub = bannerSub

    local bannerDeaths = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bannerDeaths:SetPoint("TOP", bannerSub, "BOTTOM", 0, -2)
    bannerDeaths:SetJustifyH("CENTER")
    f.timedBannerDeaths = bannerDeaths

    f:SetPoint(
        d.point    or "CENTER",
        UIParent,
        d.relPoint or "CENTER",
        d.x        or 300,
        d.y        or 200
    )
    f:Hide()
    timerFrame = f
    return f
end

-- [ BOSS FRAMES ] -------------------------------------------------------------
local function EnsureBossFrames(count)
    local f = GetOrMakeFrame()
    for i = 1, count do
        if not f.bossFrames[i] then
            local row = CreateFrame("Frame", nil, f)
            row:SetSize(FRAME_W - 20, BOSS_ICON_SIZE)
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -124 - (i - 1) * (BOSS_ICON_SIZE + 4))

            -- Left column: kill time stamp (MM:SS elapsed when boss died; "—" while alive)
            local killTimeLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            killTimeLbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            killTimeLbl:SetWidth(KILL_TIME_W)
            killTimeLbl:SetJustifyH("LEFT")
            row.killTimeLbl = killTimeLbl

            -- Right side: icon (alive state) anchored to the row's right edge
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(BOSS_ICON_SIZE, BOSS_ICON_SIZE)
            icon:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            icon:SetTexture("Interface\\EncounterJournal\\UI-EJ-HeroicTextIcon")
            row.icon = icon

            -- Right side: check mark (dead state) at same position as icon
            local check = row:CreateTexture(nil, "OVERLAY")
            check:SetSize(BOSS_ICON_SIZE, BOSS_ICON_SIZE)
            check:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            check:SetAtlas("ui-questtracker-tracker-check")
            check:Hide()
            row.check = check

            -- Boss name: fills the space between the kill-time column and the icon,
            -- right-justified so it reads flush against the icon.
            local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            name:SetPoint("LEFT",  row,  "LEFT",  KILL_TIME_W + 4, 0)
            name:SetPoint("RIGHT", icon, "LEFT",  -4, 0)
            name:SetJustifyH("RIGHT")
            row.name = name

            f.bossFrames[i] = row
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
                    if not prevBossCompleted[numBosses] and not bossKillTimes[numBosses] then
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
    if not isActive or not cfg().enabled then
        f:Hide()
        return
    end

    -- Hide banner while key is actively running (it will show when completed)
    HideTimedBanner()

    -- Title
    f.title:SetText(format("%s[+%d]|r %s", ns.Theme.EscapeColor("accent"), keystoneLevel, dungeonName))

    -- Elapsed time
    local elapsed = elapsedBase + elapsedAccum
    local remaining = timeLimit - elapsed
    local colour = ColourTime(remaining, timeLimit)
    f.timerText:SetText(colour .. FormatTime(remaining) .. "|r")

    -- +2 / +3 cutoffs (time remaining at each threshold)
    local plus3Limit = timeLimit * PLUS_3_FRACTION
    local plus2Limit = timeLimit * PLUS_2_FRACTION
    local plus3Remain = plus3Limit - elapsed
    local plus2Remain = plus2Limit - elapsed

    local p3str = plus3Remain > 0 and ("|cff44ee44+3 " .. FormatTime(plus3Remain) .. "|r") or "|cff666666+3 —|r"
    local p2str = plus2Remain > 0 and ("|cffeeee44+2 " .. FormatTime(plus2Remain) .. "|r") or "|cff666666+2 —|r"
    f.paceText:SetText(p3str .. "       " .. p2str)

    -- Progress bar — pull count (enemy forces %)
    if pullTotal > 0 then
        local pullPct = pullQty / pullTotal
        local fillW = math.min(pullPct, 1.0) * BAR_W
        f.barFill:SetWidth(math.max(fillW, 1))
        if pullQty >= pullTotal then
            ns.Theme:PaintFill(f.barFill, T.barFill)  -- accent: full
        else
            ns.Theme:PaintFill(f.barFill, {0.55, 0.72, 0.18, 1})  -- yellow-green: filling
        end
        f.pullText:SetText(format("%s%.2f%%|r",
            (pullQty >= pullTotal) and ns.Theme.EscapeColor("accent") or "|cffaacc44",
            pullPct * 100))
    else
        f.barFill:SetWidth(1)
        ns.Theme:PaintFill(f.barFill, T.barBg)
        f.pullText:SetText("|cff666666Pull %|r")
    end

    -- +3 / +2 markers on bar (still mark time thresholds — kept as reference)
    local mark3X = PLUS_3_FRACTION * BAR_W
    f.mark3:ClearAllPoints()
    f.mark3:SetPoint("TOPLEFT", f.barBg, "TOPLEFT", mark3X, 0)
    f.mark3:Show()

    local mark2X = PLUS_2_FRACTION * BAR_W
    f.mark2:ClearAllPoints()
    f.mark2:SetPoint("TOPLEFT", f.barBg, "TOPLEFT", mark2X, 0)
    f.mark2:Show()

    -- Death count
    if deathCount > 0 then
        f.deathIcon:Show()
        f.deathText:SetText(format("|cffee2222%d death%s|r  |cff999999(-%s)|r",
            deathCount, deathCount == 1 and "" or "s", FormatTime(timeLost)))
    else
        f.deathIcon:Hide()
        f.deathText:SetText("")
    end

    -- Boss progress
    EnsureBossFrames(numBosses)
    local bossIdx = 0
    for i, data in ipairs(criteriaData) do
        if not data.isWeighted then
            bossIdx = bossIdx + 1
            local row = f.bossFrames[bossIdx]
            if row then
                row.name:SetText(data.completed and ("|cff44ee44" .. data.desc .. "|r") or ("|cffcccccc" .. data.desc .. "|r"))
                row.icon:SetShown(not data.completed)
                row.check:SetShown(data.completed)
                -- Kill time: show elapsed at death when dead; dim dash while alive
                if data.completed and bossKillTimes[bossIdx] then
                    row.killTimeLbl:SetText("|cff44ee44" .. FormatTime(bossKillTimes[bossIdx]) .. "|r")
                else
                    row.killTimeLbl:SetText("|cff555555—|r")
                end
                row:Show()
            end
        end
    end

    -- Resize frame height dynamically
    local frameH = 124 + numBosses * (BOSS_ICON_SIZE + 4) + 10
    f:SetHeight(frameH)

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
    timerID = worldTimerID
    timeLimit = limit
    elapsedBase = worldElapsed
    elapsedAccum = 0
    updateAccum = 0
    wipe(bossKillTimes)

    local _, affixes, level = C_ChallengeMode.GetActiveKeystoneInfo()
    keystoneLevel = level or 0
    affixIDs = affixes or {}

    -- Populate affix icons in the header
    local currentAffixes = C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes() or {}
    local f = GetOrMakeFrame()
    wipe(f.affixIDs)
    for a = 1, 3 do
        local aIcon = f.affixIcons[a]
        if aIcon then
            local affixInfo = currentAffixes[a]
            if affixInfo then
                local _, _, tex = C_ChallengeMode.GetAffixInfo(affixInfo.id)
                f.affixIDs[a] = affixInfo.id
                if tex then
                    aIcon:SetTexture(tex)
                    aIcon:Show()
                else
                    aIcon:Hide()
                end
            else
                aIcon:Hide()
            end
        end
    end

    local scenarioName = C_Scenario.GetInfo()
    dungeonName = scenarioName or "Mythic+"

    -- Dungeon medallion icon (4th return of GetMapUIInfo = fileDataID)
    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    if activeMapID then
        local _, _, _, iconTexture = C_ChallengeMode.GetMapUIInfo(activeMapID)
        local f = GetOrMakeFrame()
        if f.dungeonIcon then
            if iconTexture and iconTexture ~= 0 then
                f.dungeonIcon:SetTexture(iconTexture)
                f.dungeonIcon:Show()
            else
                f.dungeonIcon:Hide()
            end
        end
    end

    UpdateDeathCount()
    GatherCriteriaData()

    local f = GetOrMakeFrame()
    f:SetScript("OnUpdate", OnUpdate)
    UpdateDisplay()
end

local function DeactivateTimer()
    isActive = false
    dungeonCompleted = false
    timerID = nil
    wipe(bossKillTimes)
    RestoreObjectiveTracker()
    local f = timerFrame
    if f then
        f:SetScript("OnUpdate", nil)
        if f.dungeonIcon then f.dungeonIcon:Hide() end
        -- Hide affix icons
        if f.affixIcons then
            for _, aIcon in ipairs(f.affixIcons) do aIcon:Hide() end
        end
        HideTimedBanner()
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

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        RestoreObjectiveTracker()
        dungeonCompleted = true  -- keep frame alive until player leaves the dungeon
        if timerFrame then
            timerFrame:SetScript("OnUpdate", nil)  -- freeze display at final time
        end
        -- Show completion banner now that we have the final elapsed
        local elapsed = elapsedBase + elapsedAccum
        ShowTimedBanner(elapsed, timeLimit)

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
-- When hideBlizzard is on we also hide the entire ObjectiveTrackerFrame while
-- inside a Mythic+ dungeon (quest objectives are noise during a key), then
-- restore it when the key ends or the player leaves.
local objTrackerHidden = false

HideObjectiveTracker = function()
    if objTrackerHidden then return end
    if not cfg().enabled or not cfg().hideBlizzard then return end
    if not ObjectiveTrackerFrame then return end
    if InCombatLockdown() then return end
    ObjectiveTrackerFrame:Hide()
    objTrackerHidden = true
end

RestoreObjectiveTracker = function()
    if not objTrackerHidden then return end
    objTrackerHidden = false
    if not ObjectiveTrackerFrame then return end
    if InCombatLockdown() then return end
    ObjectiveTrackerFrame:Show()
end

-- [ BLIZZARD BLOCK MANAGEMENT ] -----------------------------------------------
-- Optionally hide the default Blizzard Challenge Mode block in the objective
-- tracker so it doesn't duplicate our display.
local blizzBlockHooked = false

-- Immediately apply the current hideBlizzard setting to any already-visible block.
local function ApplyBlizzardBlockVisibility()
    if not ScenarioObjectiveTracker or not ScenarioObjectiveTracker.ChallengeModeBlock then return end
    local block = ScenarioObjectiveTracker.ChallengeModeBlock
    if cfg().enabled and cfg().hideBlizzard then
        if block:IsShown() then block:Hide() end
        -- Also hide the full objective tracker if we're in an active key
        if C_ChallengeMode.IsChallengeModeActive() then
            HideObjectiveTracker()
        end
    else
        -- Restore: let Blizzard re-layout the tracker naturally.
        RestoreObjectiveTracker()
        ScenarioObjectiveTracker:MarkDirty()
    end
end

local function HookBlizzardBlock()
    if blizzBlockHooked then return end
    blizzBlockHooked = true

    local function AttachHook()
        if not ScenarioObjectiveTracker or not ScenarioObjectiveTracker.ChallengeModeBlock then return false end
        hooksecurefunc(ScenarioObjectiveTracker.ChallengeModeBlock, "Show", function(block)
            if cfg().enabled and cfg().hideBlizzard then
                block:Hide()
            end
        end)
        -- Hide immediately in case the block is already shown (e.g. /reload inside a key).
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

    -- After the last boss dies, freeze the OnUpdate and show the completion banner
    DemoSchedule(34, function()
        if not demoActive then return end
        local f = GetOrMakeFrame()
        f:SetScript("OnUpdate", nil)
        ShowTimedBanner(DEMO_BOSS_KILL_TIMES[4], DEMO_TIME_LIMIT)
    end)

    -- After the cycle ends, pause briefly then loop (banner visible for the gap)
    DemoSchedule(DEMO_CYCLE_LEN, function()
        if demoActive then
            HideTimedBanner()
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

    -- Populate demo affix icons; C_MythicPlus.GetCurrentAffixes() returns nothing
    -- outside a real key, so we use fixed demo IDs instead.
    local f = GetOrMakeFrame()
    wipe(f.affixIDs)
    for a = 1, 3 do
        local aIcon = f.affixIcons[a]
        if aIcon then
            local id = DEMO_AFFIX_IDS[a]
            local _, _, tex = C_ChallengeMode.GetAffixInfo(id)
            f.affixIDs[a] = id
            if tex then
                aIcon:SetTexture(tex)
                aIcon:Show()
            else
                aIcon:Hide()
            end
        end
    end

    Notify("Demo started — simulating a +" .. DEMO_LEVEL .. " " .. DEMO_DUNGEON .. " run.")
    DemoRunCycle()
end

function MT.StopDemo()
    if not demoActive then return end
    demoActive = false
    for _, t in ipairs(demoTickers) do
        t:Cancel()
    end
    wipe(demoTickers)
    DeactivateTimer()
end

function MT.IsDemoActive()
    return demoActive
end
