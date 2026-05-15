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
--   Movable, position saved. Optional fade-out on mouse leave.
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

local BTN_SZ    = 26   -- uniform button height (and marker button width)
local BTN_GAP   = 2    -- gap between all buttons
local PAD       = 6    -- inner padding

-- Action button widths (height = BTN_SZ for all)
local ACT_W_CD  = 34   -- countdown button width

-- Separator between markers and action buttons
local SEP_W     = 1    -- separator line width
local SEP_GAP   = 4    -- gap on each side of separator

-- Fade behaviour
local FADE_ALPHA   = 0.15  -- ghosted alpha when faded out
local FADE_IN_DUR  = 0.2   -- seconds to fade in
local FADE_OUT_DUR = 0.2   -- seconds to fade out
local FADE_DELAY   = 0.5   -- seconds after mouse leave before fade-out starts

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

-- [ FADE ] --------------------------------------------------------------------
local fadeTimer = nil

local function CancelFadeTimer()
    if fadeTimer then
        fadeTimer:Cancel()
        fadeTimer = nil
    end
end

local function FadeTo(frame, targetAlpha, duration)
    CancelFadeTimer()
    local startAlpha = frame:GetAlpha()
    if math.abs(startAlpha - targetAlpha) < 0.01 then
        frame:SetAlpha(targetAlpha)
        return
    end
    local elapsed = 0
    if not frame._fadeFrame then
        frame._fadeFrame = CreateFrame("Frame")
    end
    local ff = frame._fadeFrame
    ff:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local pct = math.min(elapsed / duration, 1)
        frame:SetAlpha(startAlpha + (targetAlpha - startAlpha) * pct)
        if pct >= 1 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function ApplyFadeState(frame)
    local db = ns.Addon:Profile().raidTools
    if not db.fadeOut then
        CancelFadeTimer()
        if frame._fadeFrame then frame._fadeFrame:SetScript("OnUpdate", nil) end
        frame:SetAlpha(1)
        return
    end
    -- Start ghosted
    frame:SetAlpha(FADE_ALPHA)
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
    -- ── dimensions ────────────────────────────────────────────────────────
    local markerW    = 8 * BTN_SZ + 7 * BTN_GAP
    local sepW       = SEP_GAP + SEP_W + SEP_GAP  -- gap + line + gap
    local actionW    = BTN_SZ + BTN_GAP + BTN_SZ + BTN_GAP + 3 * ACT_W_CD + 2 * BTN_GAP  -- CLR + RC + 3 countdowns
    local innerW     = markerW + sepW + actionW
    local contentW   = innerW + PAD * 2
    local barH       = BTN_SZ + PAD * 2

    -- ── root frame (full size, drag target + clamp) ──────────────────────
    local f = CreateFrame("Frame", "yaqolRaidToolsBar", UIParent)
    f:SetSize(contentW, barH)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)

    -- ── single panel background ──────────────────────────────────────────
    local bg = ns.Theme:ApplyBg(f, "bg")
    bg:SetAlpha(0.70)

    -- ── fade-on-hover logic ──────────────────────────────────────────────
    f:SetScript("OnEnter", function(self)
        local db = ns.Addon:Profile().raidTools
        if not db.fadeOut then return end
        CancelFadeTimer()
        FadeTo(self, 1, FADE_IN_DUR)
    end)
    f:SetScript("OnLeave", function(self)
        local db = ns.Addon:Profile().raidTools
        if not db.fadeOut then return end
        CancelFadeTimer()
        fadeTimer = C_Timer.NewTimer(FADE_DELAY, function()
            fadeTimer = nil
            FadeTo(self, FADE_ALPHA, FADE_OUT_DUR)
        end)
    end)

    -- Propagate mouse enter/leave from child frames to root for fade
    local function ChildEnter(self)
        local root = self:GetParent()
        -- Walk up to the root panel
        while root and root ~= f do root = root:GetParent() end
        if root then
            local script = root:GetScript("OnEnter")
            if script then script(root) end
        end
    end
    local function ChildLeave(self)
        local root = self:GetParent()
        while root and root ~= f do root = root:GetParent() end
        if root then
            local script = root:GetScript("OnLeave")
            if script then script(root) end
        end
    end

    -- ── layout cursor (x relative to root left) ──────────────────────────
    local cx   = PAD
    local actY = -PAD

    -- ── helper: small action button ───────────────────────────────────────
    local function ActionBtn(label, w, onClick, tooltip)
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(w, BTN_SZ)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, actY)

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accentHL[1], T.accentHL[2], T.accentHL[3], T.accentHL[4])

        local lbl = btn:CreateFontString(nil, "OVERLAY", "SystemFont_Small")
        lbl:SetPoint("CENTER")
        lbl:SetText(label)
        ns.Theme:ApplyHudFont(lbl)

        if tooltip then
            btn:SetScript("OnEnter", function(self)
                ChildEnter(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                ChildLeave(self)
                GameTooltip:Hide()
            end)
        else
            btn:SetScript("OnEnter", ChildEnter)
            btn:SetScript("OnLeave", ChildLeave)
        end

        btn:SetScript("OnClick", onClick)
        cx = cx + w
        allActionBtns[#allActionBtns + 1] = btn
        return btn
    end

    -- ── 8 world marker buttons ────────────────────────────────────────────
    local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "X", "Skull" }
    for i = 1, 8 do
        local btn = CreateFrame("Button", "yaqolMarkerBtn"..i, f, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, actY)
        -- Left-click: place; right-click: clear
        btn:SetAttribute("type1", "worldmarker")
        btn:SetAttribute("marker1", i)
        btn:SetAttribute("action1", "set")
        btn:SetAttribute("type2", "worldmarker")
        btn:SetAttribute("marker2", i)
        btn:SetAttribute("action2", "clear")
        btn:RegisterForClicks("AnyUp", "AnyDown")

        local activeBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        activeBg:SetAllPoints()
        activeBg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.22)
        activeBg:Hide()

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accentHL[1], T.accentHL[2], T.accentHL[3], T.accentHL[4])

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BTN_SZ - 4, BTN_SZ - 4)
        icon:SetPoint("CENTER")
        icon:SetTexture(MARKER_ICONS[i])
        icon:SetVertexColor(0.55, 0.55, 0.55, 1)

        btn:SetScript("OnEnter", function(self)
            ChildEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(MARKER_NAMES[i] .. " (L: place / R: clear)", 1, 1, 1, 1, true)
            if not CanAct() then
                GameTooltip:AddLine("Requires leader or assistant", 1, 0.4, 0.4, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            ChildLeave(self)
            GameTooltip:Hide()
        end)
        btn:HookScript("OnClick", function() C_Timer.After(0.1, RefreshMarkerStates) end)

        markerBtns[i] = { btn = btn, activeBg = activeBg, icon = icon }
        cx = cx + BTN_SZ + BTN_GAP
    end
    cx = cx - BTN_GAP  -- trim last gap

    -- ── separator between markers and action buttons ──────────────────────
    cx = cx + SEP_GAP
    do
        local s = f:CreateTexture(nil, "ARTWORK")
        s:SetWidth(SEP_W)
        s:SetHeight(BTN_SZ)
        s:SetPoint("TOPLEFT", f, "TOPLEFT", cx, actY)
        s:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.25)
    end
    cx = cx + SEP_W + SEP_GAP

    -- ── Clear All ─────────────────────────────────────────────────────────
    do
        local btn = CreateFrame("Button", "yaqolMarkerBtnCLR", f, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, actY)
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", "/cwm all")
        btn:RegisterForClicks("AnyUp", "AnyDown")

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accentHL[1], T.accentHL[2], T.accentHL[3], T.accentHL[4])

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BTN_SZ - 6, BTN_SZ - 6)
        icon:SetPoint("CENTER")
        icon:SetAtlas("transmog-icon-remove", false)

        btn:SetScript("OnEnter", function(self)
            ChildEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Clear all world markers", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            ChildLeave(self)
            GameTooltip:Hide()
        end)
        btn:HookScript("OnClick", function() C_Timer.After(0.1, RefreshMarkerStates) end)

        cx = cx + BTN_SZ
    end

    -- ── Ready Check ───────────────────────────────────────────────────────
    cx = cx + BTN_GAP
    do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, actY)

        local bhl = btn:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(T.accentHL[1], T.accentHL[2], T.accentHL[3], T.accentHL[4])

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BTN_SZ - 6, BTN_SZ - 6)
        icon:SetPoint("CENTER")
        icon:SetAtlas("UI-LFG-ReadyMark", false)

        btn:SetScript("OnEnter", function(self)
            ChildEnter(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Initiate a ready check", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            ChildLeave(self)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if not CanAct() then return end
            DoReadyCheck()
        end)
        allActionBtns[#allActionBtns + 1] = btn

        cx = cx + BTN_SZ
    end

    -- ── Countdown buttons ─────────────────────────────────────────────────
    cx = cx + BTN_GAP
    for i, secs in ipairs({ 3, 5, 10 }) do
        ActionBtn(secs .. "s", ACT_W_CD, function()
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
    ApplyFadeState(panel)

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
        ApplyFadeState(panel)
    elseif not InCombatLockdown() then
        panel:Hide()
    end
end

function RaidTools.GetPanel()
    return panel
end
