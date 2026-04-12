local ADDON_NAME, ns = ...
ns.MythicTimer = {}
local MT = ns.MythicTimer

-- [ CONSTANTS ] ---------------------------------------------------------------
local PLUS_2_FRACTION = 0.8   -- +2 at ≤ 80% of time limit
local PLUS_3_FRACTION = 0.6   -- +3 at ≤ 60% of time limit
local DEATH_PENALTY   = 5     -- seconds lost per death
local UPDATE_HZ       = 10    -- timer OnUpdate ticks per second
local BAR_W, BAR_H    = 280, 14
local FRAME_W         = 300
local BOSS_ICON_SIZE  = 20

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
local keystoneLevel = 0
local dungeonName = ""
local affixIDs = {}
local criteriaData = {}  -- { [i] = { desc, qty, total, completed } }
local numBosses = 0
local bossesKilled = 0
local pullQty, pullTotal = 0, 0

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return addon.db.profile.mythicTimer end

local function Notify(msg)
    print("|cff2dc9b8yaqol:|r " .. msg)
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

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.07, 0.09, 0.85)
    f.bg = bg

    -- Accent stripe (left)
    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetSize(2, 1)
    stripe:SetPoint("TOPLEFT"); stripe:SetPoint("BOTTOMLEFT")
    stripe:SetColorTexture(0.18, 0.78, 0.72, 1)

    -- Dungeon name + key level
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetJustifyH("LEFT")
    f.title = title

    -- Timer display (large)
    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    timerText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    timerText:SetJustifyH("LEFT")
    f.timerText = timerText

    -- +2 / +3 cutoff labels
    local plus3 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plus3:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -28)
    plus3:SetJustifyH("RIGHT")
    f.plus3 = plus3

    local plus2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plus2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -42)
    plus2:SetJustifyH("RIGHT")
    f.plus2 = plus2

    -- Progress bar background
    local barY = -58
    local barBg = f:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, BAR_H)
    barBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, barY)
    barBg:SetColorTexture(0.15, 0.16, 0.19, 1)
    f.barBg = barBg

    -- Progress bar fill
    local barFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    barFill:SetSize(1, BAR_H)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetColorTexture(0.18, 0.78, 0.72, 1)
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
    deathIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -78)
    deathIcon:SetAtlas("poi-graveyard-neutral")
    deathIcon:SetVertexColor(0.93, 0.13, 0.13, 1)
    deathIcon:Hide()
    f.deathIcon = deathIcon

    local deathText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -94 - (i - 1) * (BOSS_ICON_SIZE + 4))

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(BOSS_ICON_SIZE, BOSS_ICON_SIZE)
            icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            icon:SetTexture("Interface\\EncounterJournal\\UI-EJ-HeroicTextIcon")
            row.icon = icon

            local check = row:CreateTexture(nil, "OVERLAY")
            check:SetSize(BOSS_ICON_SIZE, BOSS_ICON_SIZE)
            check:SetPoint("LEFT", row, "LEFT", 0, 0)
            check:SetAtlas("ui-questtracker-tracker-check")
            check:Hide()
            row.check = check

            local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetJustifyH("LEFT")
            name:SetWidth(FRAME_W - 20 - BOSS_ICON_SIZE - 10)
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
    wipe(criteriaData)
    numBosses = 0
    bossesKilled = 0
    pullQty, pullTotal = 0, 0

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info then
            criteriaData[i] = {
                desc      = info.description,
                qty       = info.quantity,
                total     = info.totalQuantity,
                completed = info.completed,
                isWeighted = info.isWeightedProgress,
            }
            if info.isWeightedProgress then
                -- This is the pull count (enemy forces)
                pullQty   = info.quantity
                pullTotal = info.totalQuantity
            else
                -- This is a boss
                numBosses = numBosses + 1
                if info.completed then bossesKilled = bossesKilled + 1 end
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

    -- Title
    f.title:SetText(format("|cff2dc9b8[+%d]|r %s", keystoneLevel, dungeonName))

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

    if plus3Remain > 0 then
        f.plus3:SetText("|cff44ee44+3  " .. FormatTime(plus3Remain) .. "|r")
    else
        f.plus3:SetText("|cff666666+3  —|r")
    end
    if plus2Remain > 0 then
        f.plus2:SetText("|cffeeee44+2  " .. FormatTime(plus2Remain) .. "|r")
    else
        f.plus2:SetText("|cff666666+2  —|r")
    end

    -- Progress bar — pull count (enemy forces %)
    if pullTotal > 0 then
        local pullPct = pullQty / pullTotal
        local fillW = math.min(pullPct, 1.0) * BAR_W
        f.barFill:SetWidth(math.max(fillW, 1))
        if pullQty >= pullTotal then
            f.barFill:SetColorTexture(0.18, 0.78, 0.72, 1)  -- teal: full
        else
            f.barFill:SetColorTexture(0.55, 0.72, 0.18, 1)  -- yellow-green: filling
        end
        local pullPctFloor = floor(pullPct * 100)
        f.pullText:SetText(format("|cff%s%d%%|r  (%d/%d)",
            (pullQty >= pullTotal) and "2dc9b8" or "aacc44",
            pullPctFloor, pullQty, pullTotal))
    else
        f.barFill:SetWidth(1)
        f.barFill:SetColorTexture(0.15, 0.16, 0.19, 1)
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
                row:Show()
            end
        end
    end

    -- Resize frame height dynamically
    local frameH = 98 + numBosses * (BOSS_ICON_SIZE + 4) + 10
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
    timerID = worldTimerID
    timeLimit = limit
    elapsedBase = worldElapsed
    elapsedAccum = 0
    updateAccum = 0

    local level, affixes, wasCharged = C_ChallengeMode.GetActiveKeystoneInfo()
    keystoneLevel = level or 0
    affixIDs = affixes or {}

    local scenarioName = C_Scenario.GetInfo()
    dungeonName = scenarioName or "Mythic+"

    UpdateDeathCount()
    GatherCriteriaData()

    local f = GetOrMakeFrame()
    f:SetScript("OnUpdate", OnUpdate)
    UpdateDisplay()
end

local function DeactivateTimer()
    isActive = false
    timerID = nil
    RestoreObjectiveTracker()
    local f = timerFrame
    if f then
        f:SetScript("OnUpdate", nil)
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
        -- Keep display visible for a few seconds showing final time
        if timerFrame then
            timerFrame:SetScript("OnUpdate", nil)
        end
        C_Timer.After(10, function()
            if not C_ChallengeMode.IsChallengeModeActive() then
                DeactivateTimer()
            end
        end)

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
            DeactivateTimer()
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

local function HideObjectiveTracker()
    if objTrackerHidden then return end
    if not cfg().enabled or not cfg().hideBlizzard then return end
    if not ObjectiveTrackerFrame then return end
    if InCombatLockdown() then return end
    ObjectiveTrackerFrame:Hide()
    objTrackerHidden = true
end

local function RestoreObjectiveTracker()
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
-- The demo uses fake data and a scripted timeline of events.
local demoActive = false
local demoTimer          -- C_Timer handle for sequenced events
local demoTickers = {}   -- all pending C_Timer handles so we can cancel them

local DEMO_DUNGEON   = "The Stonevault"
local DEMO_LEVEL     = 12
local DEMO_TIME_LIMIT = 2100  -- 35:00
local DEMO_BOSSES    = { "Skarmorak", "Master Machinist", "Void Speaker Eirich", "Speaker Shadowcrown" }
local DEMO_PULL_TOTAL = 320

-- Timeline: { elapsed_seconds, event_function }
-- Runs on an accelerated clock: 1 real second ≈ 30 simulated seconds
local DEMO_SPEED = 30   -- 30× speed

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

function MT.StartDemo()
    if demoActive then MT.StopDemo() end
    if isActive then
        Notify("Cannot start demo while a real M+ key is running.")
        return
    end
    demoActive = true

    -- Set initial state
    isActive      = true
    timerID       = 999
    timeLimit     = DEMO_TIME_LIMIT
    keystoneLevel = DEMO_LEVEL
    dungeonName   = DEMO_DUNGEON
    affixIDs      = {}
    DemoSetState(0, 0, 0, 0, 0)

    local f = GetOrMakeFrame()
    f:SetScript("OnUpdate", OnUpdate)
    UpdateDisplay()

    Notify("Demo started — simulating a +" .. DEMO_LEVEL .. " " .. DEMO_DUNGEON .. " run.")

    -- Scripted timeline (real seconds → simulated elapsed)
    -- Each step updates state; OnUpdate handles the ticking between steps.
    local timeline = {
        --  real_s  elapsed   deaths  timeLost  pull  bossKills
        {  2,       120,      0,       0,        42,   0 },   -- early trash
        {  5,       300,      0,       0,        95,   0 },   -- more trash
        {  8,       420,      1,       5,       120,   0 },   -- first death
        { 10,       540,      1,       5,       120,   1 },   -- Boss 1 dead
        { 13,       720,      1,       5,       165,   1 },   -- trash
        { 16,       900,      2,      10,       200,   1 },   -- second death
        { 18,      1020,      2,      10,       200,   2 },   -- Boss 2 dead
        { 21,      1200,      2,      10,       248,   2 },   -- trash
        { 24,      1380,      2,      10,       248,   3 },   -- Boss 3 dead
        { 27,      1560,      2,      10,       300,   3 },   -- trash
        { 30,      1680,      2,      10,       320,   3 },   -- pull complete
        { 33,      1800,      2,      10,       320,   4 },   -- Boss 4 dead — timed!
    }

    for _, step in ipairs(timeline) do
        DemoSchedule(step[1], function()
            if not demoActive then return end
            DemoSetState(step[2], step[3], step[4], step[5], step[6])
        end)
    end

    -- End demo after the last event + a few seconds of viewing
    DemoSchedule(38, function()
        if demoActive then
            Notify("Demo finished — key timed!")
            MT.StopDemo()
        end
    end)
end

function MT.StopDemo()
    if not demoActive then return end
    demoActive = false
    -- Cancel all pending timers
    for _, t in ipairs(demoTickers) do
        t:Cancel()
    end
    wipe(demoTickers)
    DeactivateTimer()
end

function MT.IsDemoActive()
    return demoActive
end
