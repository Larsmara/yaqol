local ADDON_NAME, ns = ...
ns.RunHistory = {}
local RunHistory = ns.RunHistory

-- [ CONSTANTS ] ---------------------------------------------------------------
local PANEL_W       = 680
local PANEL_H       = 520
local ROW_H         = 20
local ROW_PAD       = 2
local HEADER_H      = 36
local FILTER_H      = 32
local STATS_H       = 28
local SCROLL_INNER_H = PANEL_H - HEADER_H - FILTER_H - STATS_H - 16

-- Column widths
local COL = {
    dungeon = 180,
    key     = 40,
    time    = 60,
    delta   = 54,
    upgrade = 40,
    deaths  = 44,
    date    = 60,
}

-- Upgrade colours
local COL_PLUS3  = { 0.2,  0.85, 0.35 }  -- green
local COL_PLUS2  = { 0.3,  0.75, 0.95 }  -- blue
local COL_PLUS1  = { 0.9,  0.82, 0.1  }  -- yellow
local COL_TIMED  = { 0.7,  0.7,  0.7  }  -- grey  (0-upgrade but timed)
local COL_DEPLETE = { 0.9, 0.25, 0.25 }  -- red

-- [ STATE ] -------------------------------------------------------------------
local panel         -- main frame
local addonRef      -- saved addon reference
local currentCharKey  -- "Realm-Name" string for the logged-in character

-- Filter state (retained while panel is open)
local filterWeek    = "all"   -- "week" | "season" | "all"
local filterDungeon = "all"   -- dungeon name string or "all"
local filterMinKey  = 0       -- minimum key level

-- [ HELPERS ] -----------------------------------------------------------------
local function db()
    return ns.Addon.db.global
end

local function CharKey()
    if currentCharKey then return currentCharKey end
    local name  = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    currentCharKey = realm .. "-" .. name
    return currentCharKey
end

local function GetRuns(charKey)
    charKey = charKey or CharKey()
    local g = db()
    if not g.runHistoryByChar then g.runHistoryByChar = {} end
    if not g.runHistoryByChar[charKey] then g.runHistoryByChar[charKey] = {} end
    return g.runHistoryByChar[charKey]
end

-- Seconds → "MM:SS"
local function FmtTime(sec)
    if not sec or sec <= 0 then return "--:--" end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Seconds delta (elapsed − timeLimit) → "+MM:SS under" or "+MM:SS over"
local function FmtDelta(elapsed, timeLimit)
    if not elapsed or not timeLimit then return "" end
    local delta = timeLimit - elapsed
    if delta >= 0 then
        return string.format("|cff44ee44+%d:%02d|r", math.floor(delta/60), delta%60)
    else
        delta = -delta
        return string.format("|cffee4444-%d:%02d|r", math.floor(delta/60), delta%60)
    end
end

-- Upgrade label + colour
local function UpgradeInfo(upgrades)
    if upgrades >= 3 then return "+3", COL_PLUS3
    elseif upgrades == 2 then return "+2", COL_PLUS2
    elseif upgrades == 1 then return "+1", COL_PLUS1
    elseif upgrades == 0 then return  "✓",  COL_TIMED
    else                      return "✗",  COL_DEPLETE
    end
end

-- Compute upgrade count from elapsed vs timeLimit
local function CalcUpgrades(elapsed, timeLimit)
    if not elapsed or not timeLimit or elapsed > timeLimit then return -1 end
    if elapsed <= timeLimit * 0.6 then return 3
    elseif elapsed <= timeLimit * 0.8 then return 2
    else return 1 end
end

-- Unix timestamp → "Mmm DD" (e.g. "Apr 18")
local function FmtDate(ts)
    if not ts then return "" end
    return date("%b %d", ts)
end

-- Returns the Unix timestamp of the most recent weekly reset (Tuesday 09:00 UTC).
local function WeekResetTime()
    local now = time()
    local t   = date("!*t", now)
    -- Day of week: 1=Sun … 7=Sat. Tuesday = 3.
    local daysSinceTue = (t.wday - 3 + 7) % 7
    local resetHour    = 9  -- 09:00 UTC
    local resetTs = now - daysSinceTue * 86400
                        - (t.hour - resetHour) * 3600
                        - t.min * 60 - t.sec
    if resetTs > now then resetTs = resetTs - 7 * 86400 end
    return resetTs
end

-- [ RECORDING ] ---------------------------------------------------------------
-- Called on CHALLENGE_MODE_COMPLETED to persist the run.
-- Uses GetChallengeCompletionInfo() which is populated when the event fires.
local function RecordCurrentRun()
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if not info or not info.mapChallengeModeID then return end

    local mapID    = info.mapChallengeModeID
    local level    = info.level or 0
    local elapsedMS = info.time or 0
    local elapsed  = math.floor(elapsedMS / 1000)
    local upgrades = info.keystoneUpgradeLevels or 0

    local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    if not name then return end

    -- Affix IDs
    local affixIDs = {}
    local currentAffixes = C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes() or {}
    for _, aInfo in ipairs(currentAffixes) do
        affixIDs[#affixIDs + 1] = aInfo.id
    end

    -- Deaths (not in completion info; read from active challenge if still available)
    local deaths = 0
    if C_ChallengeMode.GetDeathCount then
        deaths = C_ChallengeMode.GetDeathCount() or 0
    end

    -- Group members (from completion info; falls back to live group)
    local members = {}
    if info.members and #info.members >= 1 then
        for _, m in ipairs(info.members) do
            if m.name then
                local _, class = m.memberGUID and GetPlayerInfoByGUID(m.memberGUID) or nil
                members[#members + 1] = {
                    name  = m.name,
                    class = class or "UNKNOWN",
                    role  = "NONE",
                }
            end
        end
    else
        -- fallback: read live group
        local function AddMember(unit)
            local uName = UnitName(unit)
            if not uName then return end
            local _, class = UnitClass(unit)
            local role = UnitGroupRolesAssigned(unit) or "NONE"
            members[#members + 1] = { name = uName, class = class or "UNKNOWN", role = role }
        end
        AddMember("player")
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do AddMember("party" .. i) end
        end
    end

    -- Current season
    local season = (C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()) or 0

    local run = {
        mapID     = mapID,
        dungeon   = name,
        level     = level,
        elapsed   = elapsed,
        timeLimit = timeLimit,
        upgrades  = upgrades,
        deaths    = deaths,
        affixIDs  = affixIDs,
        members   = members,
        date      = time(),
        season    = season,
    }

    local runs = GetRuns()
    table.insert(runs, 1, run)  -- newest first
end

-- [ FILTERING ] ---------------------------------------------------------------
local function ApplyFilters(runs)
    local out = {}
    local weekStart = (filterWeek == "week") and WeekResetTime() or nil
    local currentSeason = (C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()) or 0

    for _, r in ipairs(runs) do
        if filterWeek == "week" and r.date < weekStart then
            -- skip
        elseif filterWeek == "season" and r.season ~= currentSeason then
            -- skip
        elseif filterDungeon ~= "all" and r.dungeon ~= filterDungeon then
            -- skip
        elseif filterMinKey > 0 and r.level < filterMinKey then
            -- skip
        else
            out[#out + 1] = r
        end
    end
    return out
end

-- [ PANEL BUILD ] -------------------------------------------------------------
local scrollChild  -- inner content frame for rows
local rowFrames = {}
local statsLbl

-- Build a single column header label
local function ColHeader(parent, text, x, w, yOff)
    local T = ns.Theme
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yOff)
    lbl:SetWidth(w)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(T.textHeader[1], T.textHeader[2], T.textHeader[3])
    lbl:SetText(text)
    return lbl
end

-- Build or rebuild the visible run rows from filtered data
local function RebuildRows(charKey)
    local T = ns.Theme
    local allRuns = GetRuns(charKey)
    local runs = ApplyFilters(allRuns)

    -- Hide old rows
    for _, rf in ipairs(rowFrames) do rf:Hide() end
    rowFrames = {}

    local contentH = math.max(SCROLL_INNER_H, #runs * (ROW_H + ROW_PAD) + 4)
    scrollChild:SetHeight(contentH)

    local yOff = -2
    for i, r in ipairs(runs) do
        local rowF = CreateFrame("Button", nil, scrollChild)
        rowF:SetSize(PANEL_W - 20, ROW_H)
        rowF:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOff)

        -- Alternating row background
        local rowBg = rowF:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetColorTexture(T.bg[1] + 0.03, T.bg[2] + 0.03, T.bg[3] + 0.03, 0.6)
        else
            rowBg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.4)
        end

        local x = 4
        local function AddCell(text, w, r2, g2, b2)
            local f2 = rowF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f2:SetPoint("LEFT", rowF, "LEFT", x, 0)
            f2:SetWidth(w - 4)
            f2:SetJustifyH("LEFT")
            f2:SetTextColor(r2 or T.text[1], g2 or T.text[2], b2 or T.text[3])
            f2:SetText(text)
            x = x + w
            return f2
        end

        local upg, col = UpgradeInfo(r.upgrades)
        AddCell(r.dungeon or "?",        COL.dungeon)
        AddCell("+" .. (r.level or "?"), COL.key,     T.accent[1], T.accent[2], T.accent[3])
        AddCell(FmtTime(r.elapsed),      COL.time)
        -- Inline colour codes handled by SetText
        local deltaF = rowF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deltaF:SetPoint("LEFT", rowF, "LEFT", x, 0)
        deltaF:SetWidth(COL.delta - 4)
        deltaF:SetJustifyH("LEFT")
        deltaF:SetText(FmtDelta(r.elapsed, r.timeLimit))
        x = x + COL.delta

        AddCell(upg,                     COL.upgrade,  col[1], col[2], col[3])
        AddCell(tostring(r.deaths or 0), COL.deaths)
        AddCell(FmtDate(r.date),         COL.date,    T.textDim[1], T.textDim[2], T.textDim[3])

        -- Tooltip with group members + affixes
        rowF:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.dungeon .. " +" .. r.level, 1, 1, 1)
            if r.members and #r.members > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Group:", T.textHeader[1], T.textHeader[2], T.textHeader[3])
                for _, m in ipairs(r.members) do
                    local classColour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
                    local r2, g2, b2 = 1, 1, 1
                    if classColour then r2, g2, b2 = classColour.r, classColour.g, classColour.b end
                    GameTooltip:AddLine("  " .. m.name, r2, g2, b2)
                end
            end
            if r.affixIDs and #r.affixIDs > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Affixes:", T.textHeader[1], T.textHeader[2], T.textHeader[3])
                for _, id in ipairs(r.affixIDs) do
                    local affixName = C_ChallengeMode.GetAffixInfo(id)
                    if affixName then
                        GameTooltip:AddLine("  " .. affixName, T.textDim[1], T.textDim[2], T.textDim[3])
                    end
                end
            end
            GameTooltip:Show()
        end)
        rowF:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rowFrames[#rowFrames + 1] = rowF
        yOff = yOff - (ROW_H + ROW_PAD)
    end

    -- Stats footer
    if statsLbl then
        local total = #runs
        local sumKey, depletes, bestKey = 0, 0, 0
        for _, r in ipairs(runs) do
            sumKey = sumKey + (r.level or 0)
            if r.upgrades < 0 then depletes = depletes + 1 end
            if (r.level or 0) > bestKey then bestKey = r.level end
        end
        local avg = total > 0 and string.format("%.1f", sumKey / total) or "—"
        statsLbl:SetText(string.format(
            "%d run%s  |  Avg key +%s  |  Best +%d  |  Depletes: %d (%.0f%%)",
            total, total == 1 and "" or "s",
            avg, bestKey,
            depletes, total > 0 and (depletes / total * 100) or 0))
    end
end

-- Populate the dungeon dropdown options from stored history
local function GetDungeonNames(charKey)
    local runs = GetRuns(charKey)
    local seen, list = {}, { "all" }
    for _, r in ipairs(runs) do
        if r.dungeon and not seen[r.dungeon] then
            seen[r.dungeon] = true
            list[#list + 1] = r.dungeon
        end
    end
    table.sort(list, function(a, b)
        if a == "all" then return true end
        if b == "all" then return false end
        return a < b
    end)
    return list
end

-- Build the character dropdown options
local function GetCharKeys()
    local g = db()
    if not g.runHistoryByChar then return { CharKey() } end
    local keys = {}
    for k in pairs(g.runHistoryByChar) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function BuildPanel()
    local T = ns.Theme

    local f = CreateFrame("Frame", "yaqolRunHistoryPanel", UIParent)
    f:SetSize(PANEL_W, PANEL_H)
    local gpos = db().historyPanelPos or {}
    f:SetPoint(gpos.point or "CENTER", UIParent, gpos.relPoint or "CENTER", gpos.x or 0, gpos.y or 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local g = db()
        if not g.historyPanelPos then g.historyPanelPos = {} end
        g.historyPanelPos.point, _, g.historyPanelPos.relPoint, g.historyPanelPos.x, g.historyPanelPos.y = self:GetPoint()
    end)
    f:SetClampedToScreen(true)
    f:Hide()
    T:ApplyBg(f)
    T:ApplyBorder(f)

    -- [ HEADER ] --------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    title:SetText("RUN HISTORY")

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Character dropdown (right of title)
    local selectedChar = CharKey()
    local charDropBtn = CreateFrame("Button", nil, header)
    charDropBtn:SetSize(160, 20)
    charDropBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    T:StyleButton(charDropBtn, 160, 20)
    local charLbl = charDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLbl:SetPoint("LEFT", charDropBtn, "LEFT", 6, 0)
    charLbl:SetWidth(130)
    charLbl:SetJustifyH("LEFT")
    charLbl:SetText(selectedChar)
    charDropBtn:SetScript("OnClick", function(self)
        local keys = GetCharKeys()
        local menu = {}
        for _, k in ipairs(keys) do
            local kRef = k
            menu[#menu+1] = {
                text    = kRef,
                notCheckable = true,
                func = function()
                    selectedChar = kRef
                    charLbl:SetText(kRef)
                    RebuildRows(kRef)
                end,
            }
        end
        EasyMenu(menu, CreateFrame("Frame", "yaqolCharMenuAnchor", UIParent), "cursor", 0, 0, "MENU")
    end)

    -- Divider under header
    local hDiv = f:CreateTexture(nil, "ARTWORK")
    hDiv:SetHeight(1)
    hDiv:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -HEADER_H)
    hDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_H)
    hDiv:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- [ FILTER ROW ] ----------------------------------------------------------
    local filterY = -(HEADER_H + 6)

    -- Time range: simple button cycle
    local timeLabels = { week = "This Week", season = "This Season", all = "All Time" }
    local timeOrder  = { "week", "season", "all" }
    local timeBtn = CreateFrame("Button", nil, f)
    timeBtn:SetSize(100, 20)
    timeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 8, filterY)
    T:StyleButton(timeBtn, 100, 20)
    local timeLbl = timeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeLbl:SetPoint("CENTER"); timeLbl:SetText(timeLabels[filterWeek])
    timeBtn:SetScript("OnClick", function()
        local cur = filterWeek
        for i, v in ipairs(timeOrder) do
            if v == cur then
                filterWeek = timeOrder[(i % #timeOrder) + 1]
                break
            end
        end
        timeLbl:SetText(timeLabels[filterWeek])
        RebuildRows(selectedChar)
    end)

    -- Dungeon dropdown
    local dungeonBtn = CreateFrame("Button", nil, f)
    dungeonBtn:SetSize(160, 20)
    dungeonBtn:SetPoint("LEFT", timeBtn, "RIGHT", 6, 0)
    T:StyleButton(dungeonBtn, 160, 20)
    local dungLbl = dungeonBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dungLbl:SetPoint("LEFT", dungeonBtn, "LEFT", 6, 0)
    dungLbl:SetWidth(140)
    dungLbl:SetJustifyH("LEFT")
    dungLbl:SetText("All Dungeons")
    dungeonBtn:SetScript("OnClick", function(self)
        local names = GetDungeonNames(selectedChar)
        local menu = {}
        for _, n in ipairs(names) do
            local nRef = n
            menu[#menu+1] = {
                text = (nRef == "all") and "All Dungeons" or nRef,
                notCheckable = true,
                func = function()
                    filterDungeon = nRef
                    dungLbl:SetText((nRef == "all") and "All Dungeons" or nRef)
                    RebuildRows(selectedChar)
                end,
            }
        end
        EasyMenu(menu, CreateFrame("Frame", "yaqolDungMenuAnchor", UIParent), "cursor", 0, 0, "MENU")
    end)

    -- Min key level input
    local keyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keyLabel:SetPoint("LEFT", dungeonBtn, "RIGHT", 8, 0)
    keyLabel:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
    keyLabel:SetText("Key ≥")

    local keyEB = CreateFrame("EditBox", nil, f)
    keyEB:SetSize(36, 20)
    keyEB:SetPoint("LEFT", keyLabel, "RIGHT", 4, 0)
    keyEB:SetAutoFocus(false)
    keyEB:SetNumeric(true)
    keyEB:SetMaxLetters(3)
    keyEB:SetFontObject("GameFontNormalSmall")
    keyEB:SetTextColor(T.text[1], T.text[2], T.text[3])
    keyEB:SetTextInsets(4, 4, 0, 0)
    local keyBg = keyEB:CreateTexture(nil, "BACKGROUND")
    keyBg:SetAllPoints()
    keyBg:SetColorTexture(T.bgInput[1], T.bgInput[2], T.bgInput[3], T.bgInput[4])
    local keyBorder = keyEB:CreateTexture(nil, "BORDER")
    keyBorder:SetHeight(1); keyBorder:SetPoint("BOTTOM")
    keyBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
    keyEB:SetScript("OnEnterPressed", function(self)
        filterMinKey = tonumber(self:GetText()) or 0
        self:ClearFocus()
        RebuildRows(selectedChar)
    end)
    keyEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Clear filters button
    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetSize(80, 20)
    clearBtn:SetPoint("LEFT", keyEB, "RIGHT", 6, 0)
    T:StyleButton(clearBtn, 80, 20)
    local clearLbl = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearLbl:SetPoint("CENTER"); clearLbl:SetText("Clear Filters")
    clearBtn:SetScript("OnClick", function()
        filterWeek = "all"; filterDungeon = "all"; filterMinKey = 0
        timeLbl:SetText(timeLabels[filterWeek])
        dungLbl:SetText("All Dungeons")
        keyEB:SetText("")
        RebuildRows(selectedChar)
    end)

    -- [ COLUMN HEADERS ] ------------------------------------------------------
    local colY = -(HEADER_H + FILTER_H + 4)
    local cx = 4
    local function NextCol(text, w)
        ColHeader(f, text, cx, w, colY)
        cx = cx + w
    end
    NextCol("Dungeon",  COL.dungeon)
    NextCol("Key",      COL.key)
    NextCol("Time",     COL.time)
    NextCol("Delta",    COL.delta)
    NextCol("+/-",      COL.upgrade)
    NextCol("Deaths",   COL.deaths)
    NextCol("Date",     COL.date)

    -- Header divider
    local cDiv = f:CreateTexture(nil, "ARTWORK")
    cDiv:SetHeight(1)
    cDiv:SetPoint("TOPLEFT",  f, "TOPLEFT",  8, colY - 18)
    cDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, colY - 18)
    cDiv:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- [ SCROLL FRAME ] --------------------------------------------------------
    local scrollTop = HEADER_H + FILTER_H + 22
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     8,  -(scrollTop))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, STATS_H + 8)

    scrollChild = CreateFrame("Frame", nil, sf)
    scrollChild:SetWidth(PANEL_W - 32)
    scrollChild:SetHeight(SCROLL_INNER_H)
    sf:SetScrollChild(scrollChild)

    local scrollBar = CreateFrame("Slider", nil, f, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT",     sf, "TOPRIGHT",    4, -16)
    scrollBar:SetPoint("BOTTOMLEFT",  sf, "BOTTOMRIGHT", 4,  16)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(ROW_H + ROW_PAD)
    sf:SetScript("OnScrollRangeChanged", function(_, _, yRange)
        scrollBar:SetMinMaxValues(0, yRange)
    end)
    scrollBar:SetScript("OnValueChanged", function(self, val)
        sf:SetVerticalScroll(val)
    end)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = scrollBar:GetValue()
        scrollBar:SetValue(cur - delta * (ROW_H + ROW_PAD) * 3)
    end)

    -- [ STATS BAR ] -----------------------------------------------------------
    local statsBar = CreateFrame("Frame", nil, f)
    statsBar:SetHeight(STATS_H)
    statsBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  8,  4)
    statsBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 4)

    statsLbl = statsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsLbl:SetPoint("LEFT", statsBar, "LEFT", 4, 0)
    statsLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
    statsLbl:SetText("No runs recorded yet.")

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function RunHistory.Init(addon)
    addonRef = addon
    currentCharKey = nil  -- resolved lazily after PLAYER_LOGIN

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "CHALLENGE_MODE_COMPLETED" then
            RecordCurrentRun()
            -- Refresh panel if open
            if panel and panel:IsShown() then
                RebuildRows(CharKey())
            end
        end
    end)
end

function RunHistory.Refresh(addon)
    -- Nothing to reposition (panel is opened on demand)
end

function RunHistory.Toggle()
    if not panel then panel = BuildPanel() end
    if panel:IsShown() then
        panel:Hide()
    else
        RebuildRows(CharKey())
        panel:Show()
    end
end
