local ADDON_NAME, ns = ...
ns.RaidTools = {}
local RaidTools = ns.RaidTools

-- ============================================================================
-- RAID TOOLS BAR
--   A compact always-visible toolbar with:
--     • 8 world marker buttons — left-click to place, right-click to clear
--       (uses SecureActionButtonTemplate; requires lead/assist)
--     • Clear All markers button
--     • Ready Check button          (requires lead/assist)
--     • Countdown: 3 s / 5 s / 10 s (requires lead/assist)
--   Collapsible, movable, position saved.
-- ============================================================================

-- [ CONSTANTS ] ---------------------------------------------------------------
-- World marker icon textures (same order as in-game: 1=Star … 8=Skull)
local MARKER_ICONS = {
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",   -- Star      (yellow)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",   -- Circle    (orange)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",   -- Diamond   (purple)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",   -- Triangle  (green)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",   -- Moon      (white)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",   -- Square    (blue)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",   -- Cross / X (red)
    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- Skull     (white)
}

local BTN_SZ    = 26   -- world marker button size (square)
local BTN_GAP   = 2    -- gap between buttons
local PAD       = 6    -- inner padding
local SEP_W     = 1    -- separator width
local SEP_GAP   = 5    -- gap around separators
local TAB_W     = 14   -- width of the collapse tab on the left

-- Action button sizes
local ACT_H     = 20
local ACT_W_CD  = 34   -- countdown button width
local ACT_W_RC  = 80   -- ready check button width
local ACT_W_CLR = 36   -- clear all button width
local T = ns.Theme  -- populated by Theme.Init() before MakePanel runs

-- [ STATE ] -------------------------------------------------------------------
local panel

-- [ HELPERS ] -----------------------------------------------------------------
local function CanAct()
    return IsInGroup() and (UnitIsGroupLeader("player") or UnitIsRaidOfficer("player"))
end

-- Returns the current active state of world marker index i (1–8).
-- IsRaidMarkerActive is a standard (non-restricted) global.
local function MarkerActive(i)
    return IsRaidMarkerActive and IsRaidMarkerActive(i) or false
end

-- [ SAVED POSITION ] ----------------------------------------------------------
local function SavePos()
    local db = ns.Addon:Profile().raidTools
    db.point, _, db.relPoint, db.x, db.y = panel:GetPoint()
end

local function ApplyPos()
    local db = ns.Addon:Profile().raidTools
    panel:ClearAllPoints()
    panel:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 200)
end

-- [ BUILD BAR ] ---------------------------------------------------------------
local markerBtns = {}
local allActionBtns = {}    -- non-secure action buttons (Ready Check, Countdown)

local function CheckVisibility()
    if not panel then return end
    if InCombatLockdown() then return end  -- can't Show/Hide a secure-child frame in combat
    local db = ns.Addon:Profile().raidTools
    if db.enabled and CanAct() then
        panel:Show()
    else
        panel:Hide()
    end
end

local function RefreshMarkerStates()
    local canAct = CanAct()
    for i, entry in ipairs(markerBtns) do
        local active = MarkerActive(i)
        if active then
            entry.activeBg:Show()
            entry.icon:SetVertexColor(1, 1, 1, 1)
        else
            entry.activeBg:Hide()
            entry.icon:SetVertexColor(0.55, 0.55, 0.55, 1)
        end
        entry.btn:SetAlpha(canAct and 1 or 0.4)
    end
    for _, btn in ipairs(allActionBtns) do
        btn:SetEnabled(canAct)
        btn:SetAlpha(canAct and 1 or 0.4)
    end
end

local function MakePanel()
    local minimized = false   -- actual value set in the collapse logic block below from SavedVariables
    -- ── dimensions ────────────────────────────────────────────────────────
    local markerW    = 8 * BTN_SZ + 7 * BTN_GAP
    local sep1W      = SEP_W + SEP_GAP * 2
    local clearW     = ACT_W_CLR
    local sep2W      = SEP_W + SEP_GAP * 2
    local readyW     = ACT_W_RC
    local sep3W      = SEP_W + SEP_GAP * 2
    local countdownW = 3 * ACT_W_CD + 2 * BTN_GAP
    local innerW     = markerW + sep1W + clearW + sep2W + readyW + sep3W + countdownW
    local contentW   = innerW + PAD * 2        -- width of the content area
    local barH       = math.max(BTN_SZ, ACT_H) + PAD * 2
    local totalW     = TAB_W + contentW        -- tab always present on left

    -- ── root frame (full size, no bg — just a drag target + clamp) ────────
    local f = CreateFrame("Frame", "yaqolRaidToolsBar", UIParent)
    f:SetSize(totalW, barH)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)

    -- ── collapse tab (always visible, left edge) ───────────────────────────
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(TAB_W, barH)
    tab:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

    local tabBg = tab:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints()
    tabBg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)

    local tabHl = tab:CreateTexture(nil, "HIGHLIGHT")
    tabHl:SetAllPoints()
    tabHl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)

    -- right-edge accent line on the tab
    local tabLine = tab:CreateTexture(nil, "ARTWORK")
    tabLine:SetWidth(1)
    tabLine:SetPoint("TOPRIGHT",    tab, "TOPRIGHT",    0,  0)
    tabLine:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0,  0)
    tabLine:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45)

    local tabLbl = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabLbl:SetPoint("CENTER")
    tabLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    tabLbl:SetText("<")

    -- ── content panel (hides on collapse) ─────────────────────────────────
    local content = CreateFrame("Frame", nil, f)
    content:SetSize(contentW, barH)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", TAB_W, 0)

    ns.Theme:ApplyBg(content)
    ns.Theme:ApplyBorder(content)

    -- ── collapse logic ────────────────────────────────────────────────────
    local db = ns.Addon:Profile().raidTools
    local minimized = db.minimized or false  -- restored from SavedVariables

    -- Apply saved state immediately (before any user interaction)
    local function ApplyCollapse()
        if minimized then
            content:Hide()
            f:SetWidth(TAB_W)
            tabLbl:SetText(">")
        else
            content:Show()
            f:SetWidth(totalW)
            tabLbl:SetText("<")
        end
    end
    ApplyCollapse()

    tab:SetScript("OnClick", function()
        minimized = not minimized
        db.minimized = minimized
        ApplyCollapse()
    end)
    tab:SetScript("OnEnter", function()
        tabLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    tab:SetScript("OnLeave", function()
        tabLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    end)

    -- ── layout cursor (within content, x relative to content left) ────────
    local cx   = PAD
    local actY = -PAD

    -- ── helper: vertical separator ────────────────────────────────────────
    local function Separator(x)
        local s = content:CreateTexture(nil, "ARTWORK")
        s:SetWidth(SEP_W)
        s:SetHeight(barH - PAD * 2)
        s:SetPoint("TOPLEFT", content, "TOPLEFT", x, -PAD)
        s:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.25)
        return s
    end

    -- ── helper: small action button ───────────────────────────────────────
    local function ActionBtn(label, w, h, onClick, tooltip)
        local btn = CreateFrame("Button", nil, content)
        btn:SetSize(w, h)
        -- centre vertically relative to the tallest element (BTN_SZ)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", cx, actY - (BTN_SZ - h) / 2)

        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)

        local line = btn:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
        line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        line:SetColorTexture(T.accentDim[1], T.accentDim[2], T.accentDim[3], 0.5)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(label)

        if tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        btn:SetScript("OnClick", onClick)
        cx = cx + w
        allActionBtns[#allActionBtns + 1] = btn
        return btn
    end

    -- ── 8 world marker buttons ────────────────────────────────────────────
    -- PlaceRaidMarker/ClearRaidMarker are protected (HasRestrictions=true).
    -- Use SecureActionButtonTemplate.  Critical requirements (from wMarker):
    --   • RegisterForClicks("AnyUp","AnyDown") — without this secure clicks don't fire
    --   • Numbered attributes: type1/marker1/action1 (left), type2/marker2/action2 (right)
    --   • SetScript is fine on these buttons
    local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "X", "Skull" }
    for i = 1, 8 do
        local btn = CreateFrame("Button", "yaqolMarkerBtn"..i, content, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", cx, actY)
        -- Left-click: place; right-click: clear
        btn:SetAttribute("type1", "worldmarker")
        btn:SetAttribute("marker1", i)
        btn:SetAttribute("action1", "set")
        btn:SetAttribute("type2", "worldmarker")
        btn:SetAttribute("marker2", i)
        btn:SetAttribute("action2", "clear")
        btn:RegisterForClicks("AnyUp", "AnyDown")

        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1)

        local activeBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.22)
        activeBg:Hide()

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(1, 1, 1, 0.12)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BTN_SZ - 4, BTN_SZ - 4)
        icon:SetPoint("CENTER")
        icon:SetTexture(MARKER_ICONS[i])
        icon:SetVertexColor(0.55, 0.55, 0.55, 1)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(MARKER_NAMES[i] .. " (L: place / R: clear)", 1, 1, 1, 1, true)
            if not CanAct() then
                GameTooltip:AddLine("Requires leader or assistant", 1, 0.4, 0.4, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("OnClick", function() C_Timer.After(0.1, RefreshMarkerStates) end)

        markerBtns[i] = { btn = btn, activeBg = activeBg, icon = icon }
        cx = cx + BTN_SZ + BTN_GAP
    end
    cx = cx - BTN_GAP  -- trim last gap

    -- ── Separator + Clear All ─────────────────────────────────────────────
    cx = cx + SEP_GAP
    Separator(cx)
    cx = cx + SEP_W + SEP_GAP

    -- CLR: "/cwm all" macro — same approach as wMarker addon.
    do
        local btn = CreateFrame("Button", "yaqolMarkerBtnCLR", content, "SecureActionButtonTemplate")
        btn:SetSize(ACT_W_CLR, ACT_H)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", cx, actY - (BTN_SZ - ACT_H) / 2)
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", "/cwm all")
        btn:RegisterForClicks("AnyUp", "AnyDown")

        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.18)

        local line = btn:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
        line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        line:SetColorTexture(T.accentDim[1], T.accentDim[2], T.accentDim[3], 0.5)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText("CLR")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Clear all world markers", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("OnClick", function() C_Timer.After(0.1, RefreshMarkerStates) end)

        cx = cx + ACT_W_CLR
    end

    -- ── Separator + Ready Check ───────────────────────────────────────────
    cx = cx + SEP_GAP
    Separator(cx)
    cx = cx + SEP_W + SEP_GAP

    ActionBtn("Ready Check", ACT_W_RC, ACT_H, function()
        if not CanAct() then return end
        DoReadyCheck()
    end, "Initiate a ready check")

    -- ── Separator + Countdown buttons ─────────────────────────────────────
    cx = cx + SEP_GAP
    Separator(cx)
    cx = cx + SEP_W + SEP_GAP

    for i, secs in ipairs({ 3, 5, 10 }) do
        ActionBtn(secs .. "s", ACT_W_CD, ACT_H, function()
            if not CanAct() then return end
            C_PartyInfo.DoCountdown(secs)
        end, "Start a " .. secs .. "-second countdown")
        if i < 3 then cx = cx + BTN_GAP end
    end

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function RaidTools.Init(addon)
    local f = MakePanel()
    panel = f

    local db = ns.Addon:Profile().raidTools
    if not db.enabled then
        panel:Hide()
        return
    end

    ApplyPos()
    CheckVisibility()
    RefreshMarkerStates()

    -- Event watcher: re-check leader status and marker state
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")  -- re-check visibility after combat ends
    watcher:RegisterEvent("RAID_TARGET_UPDATE")    -- fires when world markers change
    watcher:SetScript("OnEvent", function()
        CheckVisibility()
        RefreshMarkerStates()
    end)
end

function RaidTools.Refresh(addon)
    if not panel then return end
    local db = ns.Addon:Profile().raidTools
    if db.enabled then
        ApplyPos()
        CheckVisibility()
        RefreshMarkerStates()
    elseif not InCombatLockdown() then
        panel:Hide()
    end
end

function RaidTools.GetPanel()
    return panel
end
