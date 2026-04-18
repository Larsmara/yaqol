local ADDON_NAME, ns = ...
ns.GroupFilter = {}
local GroupFilter = ns.GroupFilter

-- [ CONSTANTS ] ---------------------------------------------------------------
local FRAME_W      = 280
local PAD          = 10
local ROW_H        = 22
local ROW_GAP      = 2
local SECT_GAP     = 10
local HEADER_H     = 16
local DIV_GAP      = 5
local DUNGEONS_CAT = 2  -- GROUP_FINDER_CATEGORY_ID_DUNGEONS

-- [ STATE ] -------------------------------------------------------------------
local panel
local searchView
local checkRows    = {}  -- all toggle rows: { getVal, setVal, pill, lbl }
local dungeonRows  = {}  -- dungeon activity rows: { activityID, pill }
local ratingBox
local isDungeonCat = true
local hooked       = false
local loadWatcher

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return ns.Addon:Profile().groupFilter end

local function GetSearchPanel()
    return LFGListFrame and LFGListFrame.SearchPanel
end

-- Read-modify-write the live AdvancedFilter then re-run the search.
local function CommitAndSearch()
    local sp = GetSearchPanel()
    if not sp or not sp:IsShown() then return end
    local f = C_LFGList.GetAdvancedFilter()
    local d = cfg()
    f.needsTank            = d.needTank
    f.needsHealer          = d.needHealer
    f.needsDamage          = d.needDps
    f.needsMyClass         = d.needMyClass
    f.hasTank              = d.hasTank
    f.hasHealer            = d.hasHealer
    f.difficultyNormal     = d.difficultyNormal
    f.difficultyHeroic     = d.difficultyHeroic
    f.difficultyMythic     = d.difficultyMythic
    f.difficultyMythicPlus = d.difficultyMythicPlus
    f.generalPlaystyle1    = d.playstyle1
    f.generalPlaystyle2    = d.playstyle2
    f.generalPlaystyle3    = d.playstyle3
    f.generalPlaystyle4    = d.playstyle4
    f.minimumRating        = d.minRating or 0
    C_LFGList.SaveAdvancedFilter(f)
    LFGListSearchPanel_DoSearch(sp)
end

-- Toggle a dungeon activity ID in/out of the live AdvancedFilter activities table.
local function ToggleDungeonActivity(activityID)
    local sp = GetSearchPanel()
    if not sp or not sp:IsShown() then return end
    local f = C_LFGList.GetAdvancedFilter()
    local found = false
    for i, id in ipairs(f.activities) do
        if id == activityID then table.remove(f.activities, i); found = true; break end
    end
    if not found then table.insert(f.activities, activityID) end
    C_LFGList.SaveAdvancedFilter(f)
    LFGListSearchPanel_DoSearch(sp)
end

-- Blizzard convention: empty activities list = no filter (all included).
local function IsDungeonActivityChecked(activityID)
    local f = C_LFGList.GetAdvancedFilter()
    if not f or not f.activities or #f.activities == 0 then return true end
    for _, id in ipairs(f.activities) do
        if id == activityID then return true end
    end
    return false
end

-- [ SYNC ] --------------------------------------------------------------------
local function SyncAllRows()
    for _, r in ipairs(checkRows) do
        r.cb:SetChecked(r.getVal())
    end
    for _, r in ipairs(dungeonRows) do
        r.cb:SetChecked(IsDungeonActivityChecked(r.activityID))
    end
    if ratingBox then
        local d = cfg()
        if d.minRating and d.minRating > 0 then
            ratingBox:SetNumber(d.minRating)
        else
            ratingBox:SetText("")
        end
    end
end

-- [ WIDGET BUILDERS ] ---------------------------------------------------------
-- Creates a Blizzard-style checkbox matching LFGListOptionCheckButtonTemplate.
local function MakeCheckbox(parent, label, yOff)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOff)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(label)
    lbl:SetJustifyH("LEFT")
    -- Extend the hit area rightward over the label
    cb:SetHitRectInsets(0, -(lbl:GetStringWidth() + 4), 0, 0)
    return cb
end

-- Appends a toggle row. getVal/setVal read-write cfg(). Returns height consumed.
local function MakeToggleRow(parent, label, getVal, setVal, yOff)
    local cb = MakeCheckbox(parent, label, yOff)
    cb:SetChecked(getVal())
    cb:SetScript("OnClick", function(self)
        setVal(self:GetChecked())
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                                    or  SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        CommitAndSearch()
    end)
    checkRows[#checkRows + 1] = { cb = cb, getVal = getVal }
    return ROW_H + ROW_GAP
end

-- Appends a dungeon activity toggle. Returns height consumed.
local function MakeDungeonRow(parent, name, activityID, yOff)
    local cb = MakeCheckbox(parent, name, yOff)
    cb:SetChecked(IsDungeonActivityChecked(activityID))
    cb:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                                    or  SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ToggleDungeonActivity(activityID)
        self:SetChecked(IsDungeonActivityChecked(activityID))
    end)
    dungeonRows[#dungeonRows + 1] = { cb = cb, activityID = activityID }
    return ROW_H + ROW_GAP
end

-- Returns height consumed by section header (label + divider).
local function MakeSectionHeader(parent, text, yOff)
    local T  = ns.Theme
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOff)
    fs:SetText(text)
    fs:SetTextColor(T.textHeader[1], T.textHeader[2], T.textHeader[3], 1)
    local div = parent:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PAD,  yOff - HEADER_H)
    div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, yOff - HEADER_H)
    div:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
    return HEADER_H + DIV_GAP
end

-- [ SEARCH CONTENT ] ----------------------------------------------------------
local function BuildSearchContent(scrollChild)
    local T = ns.Theme
    local d = cfg()
    local y = -PAD

    -- ── REQUIRE ───────────────────────────────────────────────────────────
    y = y - MakeSectionHeader(scrollChild, "REQUIRE", y)
    local availTank, availHealer, availDPS = C_LFGList.GetAvailableRoles()
    if availTank then
        y = y - MakeToggleRow(scrollChild, "Needs Tank",
            function() return cfg().needTank end,
            function(v) cfg().needTank = v end, y)
    end
    if availHealer then
        y = y - MakeToggleRow(scrollChild, "Needs Healer",
            function() return cfg().needHealer end,
            function(v) cfg().needHealer = v end, y)
    end
    if availDPS then
        y = y - MakeToggleRow(scrollChild, "Needs DPS",
            function() return cfg().needDps end,
            function(v) cfg().needDps = v end, y)
    end
    y = y - MakeToggleRow(scrollChild, "Needs My Class",
        function() return cfg().needMyClass end,
        function(v) cfg().needMyClass = v end, y)
    y = y - MakeToggleRow(scrollChild, "Has Tank",
        function() return cfg().hasTank end,
        function(v) cfg().hasTank = v end, y)
    y = y - MakeToggleRow(scrollChild, "Has Healer",
        function() return cfg().hasHealer end,
        function(v) cfg().hasHealer = v end, y)
    y = y - SECT_GAP

    -- ── DUNGEONS (current season + expansion, max level only) ─────────────
    if IsPlayerAtEffectiveMaxLevel() then
        y = y - MakeSectionHeader(scrollChild, "DUNGEONS", y)
        local seasonGroups = C_LFGList.GetAvailableActivityGroups(
            DUNGEONS_CAT, bit.bor(Enum.LFGListFilter.CurrentSeason, Enum.LFGListFilter.PvE))
        for _, actID in ipairs(seasonGroups) do
            local name = C_LFGList.GetActivityGroupInfo(actID)
            if name then y = y - MakeDungeonRow(scrollChild, name, actID, y) end
        end
        if #seasonGroups > 0 then y = y - 4 end
        local expansionGroups = C_LFGList.GetAvailableActivityGroups(
            DUNGEONS_CAT, bit.bor(Enum.LFGListFilter.CurrentExpansion,
                Enum.LFGListFilter.NotCurrentSeason, Enum.LFGListFilter.PvE))
        for _, actID in ipairs(expansionGroups) do
            local name = C_LFGList.GetActivityGroupInfo(actID)
            if name then y = y - MakeDungeonRow(scrollChild, name, actID, y) end
        end
        y = y - SECT_GAP
    end

    -- ── MIN RATING ────────────────────────────────────────────────────────
    if IsPlayerAtEffectiveMaxLevel() then
        y = y - MakeSectionHeader(scrollChild, "MIN RATING", y)
        local eb = CreateFrame("EditBox", nil, scrollChild)
        eb:SetSize(FRAME_W - PAD * 2, 20)
        eb:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, y)
        eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(5)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(T.bgInput[1], T.bgInput[2], T.bgInput[3], 1)
        local ebBorder = eb:CreateTexture(nil, "BORDER")
        ebBorder:SetHeight(1)
        ebBorder:SetPoint("BOTTOMLEFT",  eb, "BOTTOMLEFT")
        ebBorder:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT")
        ebBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
        local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ph:SetPoint("LEFT", eb, "LEFT", 4, 0)
        ph:SetText("0  (no filter)")
        ph:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], T.textDim[4])
        eb:SetScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
        local function CommitRating()
            cfg().minRating = eb:GetNumber() or 0
            CommitAndSearch()
        end
        eb:SetScript("OnEnterPressed", function(self) CommitRating(); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost",  CommitRating)
        ratingBox = eb
        y = y - 26 - SECT_GAP
    end

    -- ── DIFFICULTY ────────────────────────────────────────────────────────
    y = y - MakeSectionHeader(scrollChild, "DIFFICULTY", y)
    y = y - MakeToggleRow(scrollChild, "Normal",
        function() return cfg().difficultyNormal end,
        function(v) cfg().difficultyNormal = v end, y)
    y = y - MakeToggleRow(scrollChild, "Heroic",
        function() return cfg().difficultyHeroic end,
        function(v) cfg().difficultyHeroic = v end, y)
    y = y - MakeToggleRow(scrollChild, "Mythic",
        function() return cfg().difficultyMythic end,
        function(v) cfg().difficultyMythic = v end, y)
    y = y - MakeToggleRow(scrollChild, "Mythic+",
        function() return cfg().difficultyMythicPlus end,
        function(v) cfg().difficultyMythicPlus = v end, y)
    y = y - SECT_GAP

    -- ── PLAYSTYLE ─────────────────────────────────────────────────────────
    y = y - MakeSectionHeader(scrollChild, "PLAYSTYLE", y)
    y = y - MakeToggleRow(scrollChild, "Learning",
        function() return cfg().playstyle1 end,
        function(v) cfg().playstyle1 = v end, y)
    y = y - MakeToggleRow(scrollChild, "Fun / Relaxed",
        function() return cfg().playstyle2 end,
        function(v) cfg().playstyle2 = v end, y)
    y = y - MakeToggleRow(scrollChild, "Fun / Serious",
        function() return cfg().playstyle3 end,
        function(v) cfg().playstyle3 = v end, y)
    y = y - MakeToggleRow(scrollChild, "Expert",
        function() return cfg().playstyle4 end,
        function(v) cfg().playstyle4 = v end, y)

    scrollChild:SetHeight(math.abs(y) + PAD)
end

-- [ SEARCH VIEW ] -------------------------------------------------------------
local function BuildSearchView(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints(parent)

    -- Scroll frame (leaves 8px gap on right for scrollbar)
    local sf = CreateFrame("ScrollFrame", nil, v)
    sf:SetPoint("TOPLEFT",     v, "TOPLEFT",     0,   0)
    sf:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -8,  0)

    local sb = CreateFrame("Slider", nil, v, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    2, -16)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2,  16)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetValue(0)
    sb:SetWidth(6)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(mn, math.min(mx, cur - delta * 20)))
    end)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(FRAME_W - 10)
    sf:SetScrollChild(sc)

    BuildSearchContent(sc)

    -- Defer scrollbar range update until layout pass completes
    C_Timer.After(0, function()
        local ch    = sc:GetHeight()  or 0
        local fh    = sf:GetHeight()  or 0
        local range = math.max(0, ch - fh)
        sb:SetMinMaxValues(0, range)
        sb:SetShown(range > 0)
    end)

    v:SetShown(false)
    return v
end

-- [ PANEL ] -------------------------------------------------------------------
local STUB_GAP = 4  -- space between LFGListPVEStub and our panel

local function BuildPanel()
    if panel then return end
    local T = ns.Theme
    -- Parent inside PVEFrame so the PortraitFrameTemplate NineSlice
    -- covers our area; no separate backdrop needed.
    panel = CreateFrame("Frame", "yaqolGroupFilter", PVEFrame)
    panel:SetWidth(FRAME_W)
    local stub = _G["LFGListPVEStub"]
    panel:SetPoint("TOPLEFT",    stub, "TOPRIGHT",    STUB_GAP, 0)
    panel:SetPoint("BOTTOMLEFT", stub, "BOTTOMRIGHT", STUB_GAP, 0)
    -- Vertical divider at the left edge of our panel
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetWidth(1)
    div:SetPoint("TOPLEFT",    panel, "TOPLEFT",    0, -30)
    div:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0,   4)
    div:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4] * 0.5)
    searchView = BuildSearchView(panel)
end

-- [ PANEL SHOW / HIDE ] -------------------------------------------------------
local function SetBlizzardSearchControlsVisible(visible)
    local sp = GetSearchPanel()
    if not sp then return end
    if sp.FilterButton then sp.FilterButton:SetShown(visible) end
    -- Expand SearchBox into the space freed by hiding FilterButton.
    -- Blizzard uses 228 with FilterButton, 319 without.
    if sp.SearchBox then
        sp.SearchBox:SetWidth(visible and 228 or 319)
    end
end

local function OnActivePanelChanged(lfgFrame, activePanel)
    if not panel then return end
    local lff = LFGListFrame
    if not lff then return end
    local isSearch = (activePanel == lff.SearchPanel)
    panel:SetShown(isSearch)
    searchView:SetShown(isSearch)
    -- Expand / contract PVEFrame to match
    if isSearch and cfg().enabled then
        PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH + FRAME_W + STUB_GAP)
        SetBlizzardSearchControlsVisible(false)
    else
        PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH)
        SetBlizzardSearchControlsVisible(true)
    end
    UpdateUIPanelPositions(PVEFrame)
end

local function ShowPanel()
    if not panel or not cfg().enabled then return end
    local lff = LFGListFrame
    if lff and lff.activePanel then OnActivePanelChanged(lff, lff.activePanel) end
    SyncAllRows()
end

local function HidePanel()
    if panel      then panel:Hide()      end
    if searchView then searchView:Hide() end
    SetBlizzardSearchControlsVisible(true)
    PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH)
    UpdateUIPanelPositions(PVEFrame)
end

local function ApplyWidthForTab()
    local lff = LFGListFrame
    local isSearch = lff and lff.activePanel == lff.SearchPanel
    if cfg().enabled and PVEFrame.activeTabIndex == 1 and isSearch then
        PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH + FRAME_W + STUB_GAP)
    else
        PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH)
    end
    UpdateUIPanelPositions(PVEFrame)
end

-- [ CATEGORY CHANGE ] ---------------------------------------------------------
local function OnCategoryChanged(_, categoryID)
    isDungeonCat = (categoryID == DUNGEONS_CAT)
end

-- [ HOOKS ] -------------------------------------------------------------------
local function SetupBlizzardHooks()
    if hooked then return end
    hooked = true
    -- PVEFrame_ShowFrame fires AFTER resetting width, and covers both
    -- the initial open and every tab switch.
    hooksecurefunc("PVEFrame_ShowFrame", function()
        if not cfg().enabled then
            if panel then panel:Hide() end
            SetBlizzardSearchControlsVisible(true)
            return
        end
        if PVEFrame.activeTabIndex == 1 then
            BuildPanel()
            ApplyWidthForTab()
            ShowPanel()
        else
            -- Switching to PvP / Mythic+ tab — hide our panel
            HidePanel()
            PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH)
            UpdateUIPanelPositions(PVEFrame)
        end
    end)
    hooksecurefunc(PVEFrame, "Hide", HidePanel)
    hooksecurefunc("LFGListFrame_SetActivePanel",    OnActivePanelChanged)
    hooksecurefunc("LFGListSearchPanel_SetCategory", OnCategoryChanged)

    -- LFGListSearchPanel_OnShow explicitly calls FilterButton:Show() and resets
    -- SearchBox width every time the panel is shown. Hook it to re-hide FilterButton
    -- and expand SearchBox into the freed space.
    hooksecurefunc("LFGListSearchPanel_OnShow", function(searchPanel)
        if not cfg().enabled then return end
        if searchPanel.FilterButton then searchPanel.FilterButton:Hide() end
        if searchPanel.SearchBox    then searchPanel.SearchBox:SetWidth(319) end
    end)

    if PVEFrame:IsShown() and cfg().enabled and PVEFrame.activeTabIndex == 1 then
        BuildPanel()
        ApplyWidthForTab()
        ShowPanel()
    end
end

-- [ PUBLIC API ] --------------------------------------------------------------
function GroupFilter.Init(addon)
    -- Blizzard_GroupFinder is demand-loaded; if it's already loaded (e.g. after
    -- /reload with Group Finder open) the ADDON_LOADED event already fired, so
    -- hook immediately. Otherwise wait for it.
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") then
        SetupBlizzardHooks()
        return
    end
    loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function(_, _, addonName)
        if addonName ~= "Blizzard_GroupFinder" then return end
        loadWatcher:UnregisterEvent("ADDON_LOADED")
        loadWatcher = nil
        SetupBlizzardHooks()
    end)
end

function GroupFilter.Refresh(addon)
    if not cfg().enabled then
        HidePanel()
        PVEFrame:SetWidth(PVE_FRAME_BASE_WIDTH)
        UpdateUIPanelPositions(PVEFrame)
        return
    end
    SyncAllRows()
    if hooked and PVEFrame and PVEFrame:IsShown() and PVEFrame.activeTabIndex == 1 then
        BuildPanel()
        ApplyWidthForTab()
        ShowPanel()
        if isDungeonCat then CommitAndSearch() end
    end
end
