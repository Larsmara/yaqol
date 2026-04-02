local ADDON_NAME, ns = ...
ns.RaidTools = {}
local RaidTools = ns.RaidTools

-- ============================================================================
-- RAID TOOLS BAR
--   A compact always-visible toolbar with:
--     • 8 world marker toggle buttons (active state shown; requires lead/assist)
--     • Clear All button
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

-- [ STATE ] -------------------------------------------------------------------
local panel
local minimized = false   -- collapse state (not persisted — resets on reload)

-- [ HELPERS ] -----------------------------------------------------------------
local function IsLeaderOrAssist()
    return UnitIsGroupLeader("player") or UnitIsRaidOfficer("player")
end

local function CanAct()
    return IsLeaderOrAssist() or not IsInGroup()
end

-- Returns the current active state of world marker index i (1–8).
-- C_WorldMarkers.GetWorldMarkerAtIndex returns nil if not active.
local function MarkerActive(i)
    if C_WorldMarkers and C_WorldMarkers.GetWorldMarkerAtIndex then
        return C_WorldMarkers.GetWorldMarkerAtIndex(i) ~= nil
    end
    return false
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
local allActionBtns = {}   -- every non-marker button, for bulk enable/disable

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
        entry.btn:SetEnabled(canAct)
        entry.btn:SetAlpha(canAct and 1 or 0.4)
    end
    for _, btn in ipairs(allActionBtns) do
        btn:SetEnabled(canAct)
        btn:SetAlpha(canAct and 1 or 0.4)
    end
end

local function MakePanel()
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
    tabBg:SetColorTexture(0.10, 0.11, 0.13, 1)

    local tabHl = tab:CreateTexture(nil, "HIGHLIGHT")
    tabHl:SetAllPoints()
    tabHl:SetColorTexture(0.18, 0.78, 0.72, 0.18)

    -- right-edge accent line on the tab
    local tabLine = tab:CreateTexture(nil, "ARTWORK")
    tabLine:SetWidth(1)
    tabLine:SetPoint("TOPRIGHT",    tab, "TOPRIGHT",    0,  0)
    tabLine:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0,  0)
    tabLine:SetColorTexture(0.18, 0.70, 0.65, 0.45)

    local tabLbl = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabLbl:SetPoint("CENTER")
    tabLbl:SetTextColor(0.55, 0.60, 0.62, 1)
    tabLbl:SetText("<")

    -- ── content panel (hides on collapse) ─────────────────────────────────
    local content = CreateFrame("Frame", nil, f)
    content:SetSize(contentW, barH)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", TAB_W, 0)

    local contentBg = content:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(0.05, 0.06, 0.07, 0.88)

    -- Border around the content area only
    local border = CreateFrame("Frame", nil, content, "BackdropTemplate")
    border:SetPoint("TOPLEFT",     content, "TOPLEFT",     0,  0)
    border:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0,  0)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0.18, 0.70, 0.65, 0.35)

    -- ── collapse logic ────────────────────────────────────────────────────
    tab:SetScript("OnClick", function()
        minimized = not minimized
        if minimized then
            content:Hide()
            f:SetWidth(TAB_W)
            tabLbl:SetText(">")
        else
            content:Show()
            f:SetWidth(totalW)
            tabLbl:SetText("<")
        end
    end)
    tab:SetScript("OnEnter", function()
        tabLbl:SetTextColor(0.18, 0.78, 0.72, 1)
    end)
    tab:SetScript("OnLeave", function()
        tabLbl:SetTextColor(0.55, 0.60, 0.62, 1)
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
        s:SetColorTexture(0.18, 0.70, 0.65, 0.25)
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
        bbg:SetColorTexture(0.15, 0.17, 0.20, 1)
        btn.bbg = bbg

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(0.18, 0.78, 0.72, 0.18)

        local line = btn:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
        line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        line:SetColorTexture(0.14, 0.62, 0.58, 0.5)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(label)
        btn.lbl = lbl

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
    for i = 1, 8 do
        local btn = CreateFrame("Button", nil, content)
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", cx, actY)

        local bbg = btn:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0.12, 0.13, 0.15, 1)

        local activeBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(0.18, 0.78, 0.72, 0.22)
        activeBg:Hide()

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(1, 1, 1, 0.12)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BTN_SZ - 4, BTN_SZ - 4)
        icon:SetPoint("CENTER")
        icon:SetTexture(MARKER_ICONS[i])
        icon:SetVertexColor(0.55, 0.55, 0.55, 1)

        local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "X", "Skull" }
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local active = MarkerActive(i)
            GameTooltip:SetText(MARKER_NAMES[i] .. (active and " — click to remove" or " — click to place at cursor"), 1, 1, 1, 1, true)
            if not CanAct() then
                GameTooltip:AddLine("Requires leader or assistant", 1, 0.4, 0.4, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            if not CanAct() then return end
            if MarkerActive(i) then
                if C_WorldMarkers and C_WorldMarkers.RemoveWorldMarker then
                    C_WorldMarkers.RemoveWorldMarker(i)
                end
            else
                if C_WorldMarkers and C_WorldMarkers.SetWorldMarker then
                    C_WorldMarkers.SetWorldMarker(i)
                else
                    RunMacroText("/wm [@cursor]" .. i)
                end
            end
            C_Timer.After(0.05, RefreshMarkerStates)
        end)

        markerBtns[i] = { btn = btn, activeBg = activeBg, icon = icon }
        cx = cx + BTN_SZ + BTN_GAP
    end
    cx = cx - BTN_GAP  -- trim last gap

    -- ── Separator + Clear All ─────────────────────────────────────────────
    cx = cx + SEP_GAP
    Separator(cx)
    cx = cx + SEP_W + SEP_GAP

    ActionBtn("CLR", ACT_W_CLR, ACT_H, function()
        if not CanAct() then return end
        if C_WorldMarkers and C_WorldMarkers.RemoveAllWorldMarkers then
            C_WorldMarkers.RemoveAllWorldMarkers()
        else
            RunMacroText("/clearworldmarkers")
        end
        C_Timer.After(0.05, RefreshMarkerStates)
    end, "Clear all world markers")

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
            RunMacroText("/countdown " .. secs)
        end, "Start a " .. secs .. "-second countdown")
        if i < 3 then cx = cx + BTN_GAP end
    end

    return f, content
end

-- [ PUBLIC API ] --------------------------------------------------------------
function RaidTools.Init(addon)
    local f, _content = MakePanel()
    panel = f

    local db = ns.Addon:Profile().raidTools
    if not db.enabled then
        panel:Hide()
        return
    end

    ApplyPos()
    RefreshMarkerStates()

    -- Event watcher: re-check leader status and marker state
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("RAID_TARGET_UPDATE")    -- fires when world markers change
    watcher:RegisterEvent("WORLD_MAP_UPDATE")
    watcher:SetScript("OnEvent", function()
        RefreshMarkerStates()
    end)
end

function RaidTools.Refresh(addon)
    if not panel then return end
    local db = ns.Addon:Profile().raidTools
    if db.enabled then
        ApplyPos()
        panel:Show()
        RefreshMarkerStates()
    else
        panel:Hide()
    end
end
