local ADDON_NAME, ns = ...
ns.VaultTracker = {}
local VaultTracker = ns.VaultTracker

-- [ CONSTANTS ] ---------------------------------------------------------------
local SLOT_BOX     = 20   -- coloured slot indicator square size
local SLOT_W       = 68   -- width per slot column (box + ilvl + count)
local LABEL_W      = 46   -- width of the track label on the left
local TRACK_ROW_H  = 52   -- height per track row (box + ilvl + count + padding)
local POPUP_PAD    = 10   -- inner padding
local ANCHOR_W     = 46   -- anchor button width
local ANCHOR_H     = 18   -- anchor button height
local pinned = false  -- true while popup is click-locked open

-- Vault tracks shown in the popup. "alwaysOn" tracks ignore the db toggle.
local TRACKS = {
    {
        key      = "showRaid",
        alwaysOn = false,
        type     = Enum.WeeklyRewardChestThresholdType.Raid,
        label    = "Raid",
    },
    {
        key      = "showMythicPlus",
        alwaysOn = true,
        type     = Enum.WeeklyRewardChestThresholdType.Activities, -- M+ uses Activities in 12.0
        label    = "M+",
    },
    {
        key      = "showWorld",
        alwaysOn = false,
        type     = Enum.WeeklyRewardChestThresholdType.World,
        label    = "World",
    },
    {
        key      = "showPvP",
        alwaysOn = false,
        type     = Enum.WeeklyRewardChestThresholdType.RankedPvP,
        label    = "PvP",
    },
}

-- Slot indicator colours
local COL_COMPLETE = { 0.15, 0.95, 0.40 }   -- vivid green — slot unlocked
local COL_PARTIAL  = { 0.9,  0.65, 0.1  }   -- amber  — in progress
local COL_EMPTY    = { 0.18, 0.18, 0.18 }   -- dark grey — not started

-- [ STATE ] -------------------------------------------------------------------
local anchor, popup

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return ns.Addon:Profile().vaultTracker end

local function IlvlFromLink(link)
    if not link then return nil end
    -- Attempt 1: GetDetailedItemLevelInfo reads bonus IDs without cache (12.0+)
    if GetDetailedItemLevelInfo then
        local ok, ilvl = pcall(GetDetailedItemLevelInfo, link)
        if ok and ilvl and ilvl > 0 then return ilvl end
    end
    -- Attempt 2: GetItemInfo — returns name, link, rarity, ilvl, ...
    -- Vault example-reward items are usually cached so this often works.
    local ok, _, _, _, ilvl = pcall(GetItemInfo, link)
    if ok and ilvl and ilvl > 0 then return ilvl end
    -- Can't determine ilvl; caller will show "? ilvl"
    return nil
end

-- Returns { progress, threshold, ilvl, unlocked } for each of the 3 slots of a track type.
-- Falls back gracefully if API returns nil (vault not loaded yet).
local function GetTrackData(trackType)
    local activities = C_WeeklyRewards.GetActivities(trackType)
    local slots = {}
    if not activities then return slots end
    -- Sort by index to ensure consistent ordering
    table.sort(activities, function(a, b) return a.index < b.index end)
    for _, act in ipairs(activities) do
        if act.type == trackType then -- filter stray entries if GetActivities returned mixed types
        local unlocked = act.progress >= act.threshold
        local ilvl = nil
        if unlocked then
            -- Try act.rewards first (populated after vault generates rewards post-reset)
            if act.rewards then
                for _, rewardInfo in ipairs(act.rewards) do
                    local link = C_WeeklyRewards.GetItemHyperlink(rewardInfo)
                    if link then
                        ilvl = IlvlFromLink(link)
                        if ilvl then break end
                    end
                end
            end
            -- Fall back to example hyperlinks (returns a single string, not a table)
            if not ilvl then
                local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, act.id)
                if ok and link then
                    -- API returns either a string or a table depending on build
                    if type(link) == "string" then
                        ilvl = IlvlFromLink(link)
                    elseif type(link) == "table" then
                        for _, l in ipairs(link) do
                            ilvl = IlvlFromLink(l)
                            if ilvl then break end
                        end
                    end
                end
            end
        end
        slots[act.index] = {
            progress  = act.progress,
            threshold = act.threshold,
            unlocked  = unlocked,
            ilvl      = ilvl,
        }
        end -- if act.type == trackType
    end
    return slots
end

-- [ POPUP FRAME ] -------------------------------------------------------------
local function BuildPopup()
    local T = ns.Theme
    local db = cfg()

    -- Which tracks are currently visible
    local visibleTracks = {}
    for _, track in ipairs(TRACKS) do
        if track.alwaysOn or db[track.key] then
            visibleTracks[#visibleTracks + 1] = track
        end
    end

    local HEADER_H = 24
    local popW = POPUP_PAD * 2 + LABEL_W + SLOT_W * 3
    local popH = HEADER_H + POPUP_PAD + #visibleTracks * TRACK_ROW_H + POPUP_PAD

    local f = CreateFrame("Frame", nil, UIParent)  -- no global name; avoids collision on rebuild
    f:SetFrameStrata("HIGH")
    f:SetSize(popW, popH)
    f:SetClampedToScreen(true)
    f:SetAlpha(0)
    f:Hide()
    f:EnableMouse(true)
    -- Mouse entered popup: cancel any pending close
    f:SetScript("OnEnter", function()
        if closeTimer then closeTimer:Cancel(); closeTimer = nil end
    end)
    -- Mouse left popup: schedule close unless pinned
    f:SetScript("OnLeave", function()
        if pinned then return end
        if closeTimer then closeTimer:Cancel() end
        closeTimer = C_Timer.NewTimer(0.15, function()
            closeTimer = nil
            if popup and not pinned then
                UIFrameFadeOut(popup, 0.15, popup:GetAlpha(), 0)
                C_Timer.After(0.16, function() if popup and not pinned then popup:Hide() end end)
            end
        end)
    end)
    T:ApplyBg(f)
    T:ApplyBorder(f)

    -- Header label
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, -6)
    hdr:SetTextColor(T.textHeader[1], T.textHeader[2], T.textHeader[3])
    hdr:SetText("GREAT VAULT")

    -- Divider under header
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",  POPUP_PAD, -HEADER_H)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -POPUP_PAD, -HEADER_H)
    div:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    f.trackRows = {}

    -- One row per visible track
    -- Layout inside a row (top-aligned to rowY):
    --   Track label (left, vertically centred in SLOT_BOX)
    --   Per slot column:
    --     [SLOT_BOX square]   (top of row)
    --     [ilvl text]         (below box, accent colour)
    --     [X/threshold text]  (below ilvl, dim colour)
    local rowY = -(HEADER_H + POPUP_PAD)
    for _, track in ipairs(visibleTracks) do
        local row = {}

        -- Track label, vertically centred against the box height
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PAD, rowY - (SLOT_BOX / 2 - 6))
        lbl:SetWidth(LABEL_W - 4)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(T.text[1], T.text[2], T.text[3])
        lbl:SetText(track.label)
        row.label = lbl

        row.slots = {}
        for s = 1, 3 do
            local slotX = POPUP_PAD + LABEL_W + (s - 1) * SLOT_W
            local slot = {}

            -- Coloured indicator square
            local box = f:CreateTexture(nil, "ARTWORK")
            box:SetSize(SLOT_BOX, SLOT_BOX)
            box:SetPoint("TOPLEFT", f, "TOPLEFT", slotX, rowY)
            box:SetColorTexture(COL_EMPTY[1], COL_EMPTY[2], COL_EMPTY[3], 0.9)
            slot.box = box

            -- Thin border around box — must use BORDER layer (below ARTWORK)
            -- so it doesn't cover and wash out the colored box texture
            local boxBorder = f:CreateTexture(nil, "BORDER")
            boxBorder:SetPoint("TOPLEFT",     box, "TOPLEFT",     -1,  1)
            boxBorder:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT",  1, -1)
            boxBorder:SetColorTexture(0, 0, 0, 0.8)

            -- ilvl label (below box, prominent)
            local ilvlLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ilvlLbl:SetPoint("TOPLEFT", f, "TOPLEFT", slotX, rowY - SLOT_BOX - 2)
            ilvlLbl:SetWidth(SLOT_W - 4)
            ilvlLbl:SetJustifyH("LEFT")
            ilvlLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
            ilvlLbl:SetText("")
            slot.ilvlLbl = ilvlLbl

            -- Progress count label (below ilvl)
            local cntLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            cntLbl:SetPoint("TOPLEFT", f, "TOPLEFT", slotX, rowY - SLOT_BOX - 16)
            cntLbl:SetWidth(SLOT_W - 4)
            cntLbl:SetJustifyH("LEFT")
            cntLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3])
            cntLbl:SetText("")
            slot.countLbl = cntLbl

            row.slots[s] = slot
        end

        row.trackDef = track
        f.trackRows[#f.trackRows + 1] = row
        rowY = rowY - TRACK_ROW_H
    end

    return f
end

-- Update all slot boxes, ilvl labels, and count labels from live API data.
local function RefreshPopupData()
    if not popup then return end
    for _, row in ipairs(popup.trackRows) do
        local slots = GetTrackData(row.trackDef.type)
        for s = 1, 3 do
            local slotUI  = row.slots[s]
            if not slotUI then break end
            local slotData = slots[s]

            local progress  = slotData and slotData.progress  or 0
            local threshold = slotData and slotData.threshold or 1
            local unlocked  = slotData and slotData.unlocked  or false
            local ilvl      = slotData and slotData.ilvl

            -- Slot indicator colour
            if unlocked then
                slotUI.box:SetColorTexture(COL_COMPLETE[1], COL_COMPLETE[2], COL_COMPLETE[3], 0.85)
            elseif progress > 0 then
                slotUI.box:SetColorTexture(COL_PARTIAL[1], COL_PARTIAL[2], COL_PARTIAL[3], 0.85)
            else
                slotUI.box:SetColorTexture(COL_EMPTY[1], COL_EMPTY[2], COL_EMPTY[3], 0.85)
            end

            -- ilvl (only when slot is unlocked)
            if ilvl then
                slotUI.ilvlLbl:SetText(ilvl .. " ilvl")
                slotUI.ilvlLbl:SetTextColor(ns.Theme.accent[1], ns.Theme.accent[2], ns.Theme.accent[3])
            elseif unlocked then
                slotUI.ilvlLbl:SetText("|cff888888? ilvl|r")
            else
                slotUI.ilvlLbl:SetText("")
            end

            -- Progress count — hidden when slot is fully unlocked
            if unlocked then
                slotUI.countLbl:SetText("")
            elseif progress > 0 then
                slotUI.countLbl:SetText(progress .. "/" .. threshold)
                slotUI.countLbl:SetTextColor(COL_PARTIAL[1], COL_PARTIAL[2], COL_PARTIAL[3])
            else
                slotUI.countLbl:SetText("0/" .. threshold)
                slotUI.countLbl:SetTextColor(ns.Theme.textDim[1], ns.Theme.textDim[2], ns.Theme.textDim[3])
            end
        end
    end
end

-- Reposition popup relative to the anchor
local function PositionPopup()
    if not popup or not anchor then return end
    popup:ClearAllPoints()
    -- Default: above the anchor; clamp handles screen edges
    popup:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
end

-- [ ANCHOR FRAME ] ------------------------------------------------------------
local function BuildAnchor()
    local T = ns.Theme
    local db = cfg()

    local f = CreateFrame("Button", "yaqolVaultAnchor", UIParent)
    f:SetSize(ANCHOR_W, ANCHOR_H)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:RegisterForDrag("RightButton")  -- RightButton drag to move; frees LeftButton for click
    f:SetClampedToScreen(true)
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = cfg()
        d.point, _, d.relPoint, d.x, d.y = self:GetPoint()
    end)

    T:ApplyBg(f)
    T:ApplyBorder(f)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("CENTER")
    lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    lbl:SetText("VAULT")

    local function showPopup()
        if not popup then popup = BuildPopup() end
        if closeTimer then closeTimer:Cancel(); closeTimer = nil end
        PositionPopup()
        RefreshPopupData()
        popup:Show()
        UIFrameFadeIn(popup, 0.15, popup:GetAlpha(), 1)
    end

    local function scheduleClose()
        if pinned then return end
        if closeTimer then closeTimer:Cancel() end
        closeTimer = C_Timer.NewTimer(0.15, function()
            closeTimer = nil
            if popup and not pinned then
                UIFrameFadeOut(popup, 0.15, popup:GetAlpha(), 0)
                C_Timer.After(0.16, function() if popup and not pinned then popup:Hide() end end)
            end
        end)
    end

    -- Left-click: toggle pinned
    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", function(self, btn)
        if btn ~= "LeftButton" then return end
        if pinned then
            pinned = false
            scheduleClose()
        else
            pinned = true
            showPopup()
        end
    end)

    -- Hover: show while mousing over (cancelled by popup's OnEnter if mouse slides onto it)
    f:SetScript("OnEnter", function() showPopup() end)
    f:SetScript("OnLeave", function() scheduleClose() end)

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function VaultTracker.Init(addon)
    anchor = BuildAnchor()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    watcher:SetScript("OnEvent", function()
        -- Rebuild popup on next hover so new data is shown
        if popup then popup:Hide(); popup = nil end
        pinned = false
    end)

    local db = cfg()
    if not db.enabled then anchor:Hide() end
end

function VaultTracker.Refresh(addon)
    if not anchor then return end
    local db = cfg()
    anchor:ClearAllPoints()
    anchor:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    anchor:SetScale(db.scale or 1.0)
    if db.enabled then anchor:Show() else anchor:Hide() end
    -- Force popup rebuild on next hover (track visibility may have changed)
    if popup then popup:Hide(); popup = nil end
    pinned = false
end

function VaultTracker.GetFrame() return anchor end
