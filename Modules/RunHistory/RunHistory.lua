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
local COL_PLUS3  = { r = 0.2,  g = 0.85, b = 0.35 }  -- green
local COL_PLUS2  = { r = 0.3,  g = 0.75, b = 0.95 }  -- blue
local COL_PLUS1  = { r = 0.9,  g = 0.82, b = 0.1  }  -- yellow
local COL_TIMED  = { r = 0.7,  g = 0.7,  b = 0.7  }  -- grey  (0-upgrade but timed)
local COL_DEPLETE = { r = 0.9, g = 0.25, b = 0.25 }  -- red

-- [ STATE ] -------------------------------------------------------------------
local panel         -- main frame
local addonRef      -- saved addon reference
local currentCharKey  -- "Realm-Name" string for the logged-in character

-- Filter state (retained while panel is open)
local filterWeek    = "all"   -- "week" | "season" | "all"
local filterDungeon = "all"   -- dungeon name string or "all"
local filterMinKey  = 0       -- minimum key level

-- Group snapshot taken at CHALLENGE_MODE_START, used by RecordCurrentRun.
-- GetChallengeCompletionInfo().members is unreliable (may return fewer members
-- than actually ran the key), so we capture the full party when the key begins.
local partySnapshot = nil

-- Player ilvl captured at CHALLENGE_MODE_START
local snapshotIlvl = nil

-- C_DamageMeter constants
local DM_SESSION_OVERALL = 0   -- DamageMeterSessionType.Overall
local DM_TYPE_DAMAGE     = 0   -- DamageMeterType.DamageDone
local DM_TYPE_HEALING    = 2   -- DamageMeterType.HealingDone

-- Forward declaration — defined after RecordCurrentRun
local PendingDamageMeterPatch

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

-- Large number → compact string (e.g. 1234567 → "1.23M", 45600 → "45.6K")
local function FmtNumber(n)
    if not n or n == 0 then return "0" end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
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

    -- Group members: prefer the snapshot captured at CHALLENGE_MODE_START.
    -- GetChallengeCompletionInfo().members is unreliable — it may contain fewer
    -- members than actually ran the key, so we never use it.
    local members = {}
    if partySnapshot and #partySnapshot > 0 then
        members = partySnapshot
    else
        -- Fallback: read live group (should still be intact at completion time).
        local function AddMember(unit)
            local uName, uRealm = UnitName(unit)
            if not uName then return end
            local _, class = UnitClass(unit)
            local role = UnitGroupRolesAssigned(unit) or "NONE"
            members[#members + 1] = { name = uName, realm = uRealm or "", class = class or "UNKNOWN", role = role }
        end
        AddMember("player")
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do AddMember("party" .. i) end
        end
    end

    -- Current season
    local season = (C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()) or 0

    -- Strip GUIDs before persisting (they change between sessions)
    -- Keep a GUID→index map for the deferred damage meter patch.
    local guidMap = {}
    for i, m in ipairs(members) do
        if m.guid then guidMap[m.guid] = i end
        m.guid = nil
    end

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
        totalDamage  = 0,
        totalHealing = 0,
        ilvl         = snapshotIlvl,
    }

    local runs = GetRuns()
    table.insert(runs, 1, run)  -- newest first

    -- Damage meter values are SecretWhenInCombat and the player is typically
    -- still in combat when CHALLENGE_MODE_COMPLETED fires. Defer the read
    -- until combat drops (PLAYER_REGEN_ENABLED), then patch the saved run.
    PendingDamageMeterPatch(run, guidMap)
end

-- Reads C_DamageMeter data and writes it into the given run record.
-- Returns true if data was successfully read.
local function ReadDamageMeter(run, guidMap)
    if not C_DamageMeter or not C_DamageMeter.GetCombatSessionFromType then return false end

    local function SafeNum(val)
        if val == nil then return nil end
        if issecretvalue(val) then return nil end
        return val
    end

    local function SafeStr(val)
        if val == nil then return nil end
        if issecretvalue(val) then return nil end
        return val
    end

    -- Damage
    local dmgSession = C_DamageMeter.GetCombatSessionFromType(DM_SESSION_OVERALL, DM_TYPE_DAMAGE)
    if dmgSession then
        local total = SafeNum(dmgSession.totalAmount)
        if total then run.totalDamage = total end
        if dmgSession.combatSources then
            for _, src in ipairs(dmgSession.combatSources) do
                local guid = SafeStr(src.sourceGUID)
                local amt  = SafeNum(src.totalAmount)
                if guid and amt then
                    local idx = guidMap[guid]
                    if idx and run.members[idx] then run.members[idx].damage = amt end
                end
            end
        end
    end

    -- Healing
    local healSession = C_DamageMeter.GetCombatSessionFromType(DM_SESSION_OVERALL, DM_TYPE_HEALING)
    if healSession then
        local total = SafeNum(healSession.totalAmount)
        if total then run.totalHealing = total end
        if healSession.combatSources then
            for _, src in ipairs(healSession.combatSources) do
                local guid = SafeStr(src.sourceGUID)
                local amt  = SafeNum(src.totalAmount)
                if guid and amt then
                    local idx = guidMap[guid]
                    if idx and run.members[idx] then run.members[idx].healing = amt end
                end
            end
        end
    end

    return (run.totalDamage or 0) > 0 or (run.totalHealing or 0) > 0
end

-- Schedule deferred damage meter read: try immediately, fall back to PLAYER_REGEN_ENABLED.
local pendingPatchFrame
PendingDamageMeterPatch = function(run, guidMap)
    -- Try immediately (player might already be out of combat)
    if not InCombatLockdown() then
        local ok, err = pcall(ReadDamageMeter, run, guidMap)
        if ok then return end
    end

    -- Defer until combat ends
    if not pendingPatchFrame then
        pendingPatchFrame = CreateFrame("Frame")
    end
    pendingPatchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    pendingPatchFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(ReadDamageMeter, run, guidMap)
    end)
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
    local lbl = parent:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yOff)
    lbl:SetWidth(w)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
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
            rowBg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])
        else
            rowBg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 0.4)
        end

        local x = 4
        local function AddCell(text, w, r2, g2, b2)
            local f2 = rowF:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
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
        local deltaF = rowF:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
        deltaF:SetPoint("LEFT", rowF, "LEFT", x, 0)
        deltaF:SetWidth(COL.delta - 4)
        deltaF:SetJustifyH("LEFT")
        deltaF:SetText(FmtDelta(r.elapsed, r.timeLimit))
        x = x + COL.delta

        AddCell(upg,                     COL.upgrade,  col.r, col.g, col.b)
        AddCell(tostring(r.deaths or 0), COL.deaths)
        AddCell(FmtDate(r.date),         COL.date,    T.textDim[1], T.textDim[2], T.textDim[3])

        -- Tooltip with group members + affixes
        rowF:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.dungeon .. " +" .. r.level, 1, 1, 1)
            if r.ilvl then
                GameTooltip:AddLine("iLvl: " .. r.ilvl, T.textDim[1], T.textDim[2], T.textDim[3])
            end
            if r.members and #r.members > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Group:", T.textDim[1], T.textDim[2], T.textDim[3])
                for _, m in ipairs(r.members) do
                    local classColour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
                    local r2, g2, b2 = 1, 1, 1
                    if classColour then r2, g2, b2 = classColour.r, classColour.g, classColour.b end
                    local suffix = ""
                    if m.damage and m.damage > 0 then suffix = suffix .. "  D:" .. FmtNumber(m.damage) end
                    if m.healing and m.healing > 0 then suffix = suffix .. "  H:" .. FmtNumber(m.healing) end
                    GameTooltip:AddLine("  " .. m.name .. (m.realm and m.realm ~= "" and "-" .. m.realm or "") .. suffix, r2, g2, b2)
                end
            end
            if (r.totalDamage and r.totalDamage > 0) or (r.totalHealing and r.totalHealing > 0) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Total Damage", FmtNumber(r.totalDamage or 0), T.textDim[1], T.textDim[2], T.textDim[3], 1, 1, 1)
                GameTooltip:AddDoubleLine("Total Healing", FmtNumber(r.totalHealing or 0), T.textDim[1], T.textDim[2], T.textDim[3], 1, 1, 1)
            end
            if r.affixIDs and #r.affixIDs > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Affixes:", T.textDim[1], T.textDim[2], T.textDim[3])
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

    -- [ HEADER ] --------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local title = header:CreateFontString(nil, "OVERLAY", "SystemFont_Med1")
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
    local charLbl = charDropBtn:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    charLbl:SetPoint("LEFT", charDropBtn, "LEFT", 6, 0)
    charLbl:SetWidth(130)
    charLbl:SetJustifyH("LEFT")
    charLbl:SetText(selectedChar)
    charDropBtn:SetScript("OnClick", function(self)
        local keys = GetCharKeys()
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            for _, k in ipairs(keys) do
                local kRef = k
                rootDescription:CreateButton(kRef, function()
                    selectedChar = kRef
                    charLbl:SetText(kRef)
                    RebuildRows(kRef)
                end)
            end
        end)
    end)

    -- Divider under header
    local hDiv = f:CreateTexture(nil, "ARTWORK")
    hDiv:SetHeight(1)
    hDiv:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -HEADER_H)
    hDiv:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_H)
    hDiv:SetColorTexture(T.textDim[1], T.textDim[2], T.textDim[3], 0.15)

    -- [ FILTER ROW ] ----------------------------------------------------------
    local filterY = -(HEADER_H + 6)

    -- Time range: simple button cycle
    local timeLabels = { week = "This Week", season = "This Season", all = "All Time" }
    local timeOrder  = { "week", "season", "all" }
    local timeBtn = CreateFrame("Button", nil, f)
    timeBtn:SetSize(100, 20)
    timeBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 8, filterY)
    T:StyleButton(timeBtn, 100, 20)
    local timeLbl = timeBtn:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
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
    local dungLbl = dungeonBtn:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    dungLbl:SetPoint("LEFT", dungeonBtn, "LEFT", 6, 0)
    dungLbl:SetWidth(140)
    dungLbl:SetJustifyH("LEFT")
    dungLbl:SetText("All Dungeons")
    dungeonBtn:SetScript("OnClick", function(self)
        local names = GetDungeonNames(selectedChar)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            for _, n in ipairs(names) do
                local nRef = n
                rootDescription:CreateButton(
                    (nRef == "all") and "All Dungeons" or nRef,
                    function()
                        filterDungeon = nRef
                        dungLbl:SetText((nRef == "all") and "All Dungeons" or nRef)
                        RebuildRows(selectedChar)
                    end)
            end
        end)
    end)

    -- Min key level input
    local keyLabel = f:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
    keyLabel:SetPoint("LEFT", dungeonBtn, "RIGHT", 8, 0)
    keyLabel:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
    keyLabel:SetText("Key ≥")

    local keyEB = CreateFrame("EditBox", nil, f)
    keyEB:SetSize(36, 20)
    keyEB:SetPoint("LEFT", keyLabel, "RIGHT", 4, 0)
    keyEB:SetAutoFocus(false)
    keyEB:SetNumeric(true)
    keyEB:SetMaxLetters(3)
    keyEB:SetFontObject("SystemFont_Small")
    keyEB:SetTextColor(T.text[1], T.text[2], T.text[3])
    keyEB:SetTextInsets(4, 4, 0, 0)
    local keyBg = keyEB:CreateTexture(nil, "BACKGROUND")
    keyBg:SetAllPoints()
    keyBg:SetColorTexture(T.bgInput[1], T.bgInput[2], T.bgInput[3], T.bgInput[4])
    local keyBorder = keyEB:CreateTexture(nil, "BORDER")
    keyBorder:SetHeight(1); keyBorder:SetPoint("BOTTOM")
    keyBorder:SetColorTexture(T.textDim[1], T.textDim[2], T.textDim[3], 0.15)
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
    local clearLbl = clearBtn:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
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
    cDiv:SetColorTexture(T.textDim[1], T.textDim[2], T.textDim[3], 0.15)

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

    statsLbl = statsBar:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
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
    watcher:RegisterEvent("CHALLENGE_MODE_START")
    watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "CHALLENGE_MODE_START" then
            -- Snapshot the full party now, before the key might cause anyone to
            -- leave. This is what RecordCurrentRun uses for the members table.
            partySnapshot = {}
            local function Snap(unit)
                local uName, uRealm = UnitName(unit)
                if not uName then return end
                local _, class = UnitClass(unit)
                local role = UnitGroupRolesAssigned(unit) or "NONE"
                local guid = UnitGUID(unit)
                partySnapshot[#partySnapshot + 1] = { name = uName, realm = uRealm or "", class = class or "UNKNOWN", role = role, guid = guid }
            end
            Snap("player")
            if IsInGroup() then
                for i = 1, GetNumSubgroupMembers() do Snap("party" .. i) end
            end
            -- Capture player ilvl (GetAverageItemLevel returns overall, equipped, pvp)
            local _, equipped = GetAverageItemLevel()
            snapshotIlvl = equipped and math.floor(equipped) or nil
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            RecordCurrentRun()
            partySnapshot = nil  -- clear for next run
            snapshotIlvl = nil
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
