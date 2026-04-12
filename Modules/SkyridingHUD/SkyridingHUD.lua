local ADDON_NAME, ns = ...
ns.SkyridingHUD = {}
local SkyridingHUD = ns.SkyridingHUD

-- ============================================================================
-- SKYRIDING HUD  (Midnight 12.0 — vigor removed in 11.2.7)
--   Surge Forward (372608) and Skyward Ascent (372610) share a pool of
--   up to 6 charges, each recharging in 15 seconds.
--   HUD rows:
--     • Charge pips     — filled squares for ready charges, partial for recharging
--     • Whirling Surge  — cooldown bar (hidden when ready), spell 361584
-- ============================================================================

-- [ CONSTANTS ] ---------------------------------------------------------------
local SPELL_SURGE_FORWARD  = 372608  -- shared charge pool with Skyward Ascent 372610
local SPELL_WHIRLING_SURGE = 361584  -- Whirling Surge cooldown
local UPDATE_HZ           = 10
local HUD_W               = 200
local BAR_H               = 8
local PIP_H               = 14
local PIP_GAP             = 3
local LABEL_H             = 14
local ROW_GAP             = 5
local MAX_PIPS            = 6

-- Colours
local R, G, B              = 0.18, 0.78, 0.72
local R_DIM, G_DIM, B_DIM  = 0.06, 0.26, 0.24
local WS_R, WS_G, WS_B     = 0.85, 0.50, 0.18  -- orange for Whirling Surge CD

-- [ STATE ] -------------------------------------------------------------------
local panel
local surgeRow, surgeFill, surgeLabel
local pipFrames = {}
local isVisible = false

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg()
    return ns.Addon:Profile().skyridingHUD
end

-- Returns SpellChargeInfo or nil.
local function GetCharges()
    local ok, info = pcall(C_Spell.GetSpellCharges, SPELL_SURGE_FORWARD)
    if not ok or not info then return nil end
    return info
end

-- [ VISIBILITY ] --------------------------------------------------------------
local function ShouldShow()
    if not cfg().enabled then return false end
    if not IsMounted() then return false end
    -- Surge Forward is only usable when actively on a skyriding mount in Skyriding
    -- mode (not Steady Flight). This is the most direct mount-style check available.
    local ok, isUsable = pcall(C_Spell.IsSpellUsable, SPELL_SURGE_FORWARD)
    return ok and isUsable == true
end

local function ShowHUD()
    if not panel or not cfg().enabled then return end
    isVisible = true
    panel:Show()
    UpdateCharges()
    UpdateWhirlingSurge()
end

local function HideHUD()
    if not panel then return end
    isVisible = false
    panel:Hide()
end

-- [ UPDATE LOGIC ] ------------------------------------------------------------
local function UpdateCharges()
    local info    = GetCharges()
    local numPips = (info and info.maxCharges) or MAX_PIPS
    local cur     = (info and info.currentCharges) or 0

    local rechargeFrac = 0
    if info and info.currentCharges < info.maxCharges and info.cooldownDuration > 0 then
        rechargeFrac = math.min((GetTime() - info.cooldownStartTime) / info.cooldownDuration, 1)
    end

    for i = 1, MAX_PIPS do
        local pip = pipFrames[i]
        if i > numPips then
            pip:Hide()
        else
            pip:Show()
            local frac
            if     i <= cur     then frac = 1
            elseif i == cur + 1 then frac = rechargeFrac
            else                     frac = 0
            end
            pip.fill:SetWidth(math.max(1, frac * pip.trackW))
            if frac >= 1 then
                pip.fill:SetColorTexture(R, G, B, 1)
            elseif frac > 0 then
                pip.fill:SetColorTexture(R * 0.55, G * 0.55, B * 0.55, 1)
            else
                pip.fill:SetColorTexture(R_DIM, G_DIM, B_DIM, 1)
            end
        end
    end

end

local function UpdateWhirlingSurge()
    local ok, info = pcall(C_Spell.GetSpellCooldown, SPELL_WHIRLING_SURGE)
    if not ok or not info or info.startTime == 0 or info.duration <= 1.5 then
        surgeRow:Hide()
        return
    end
    local remaining = math.max(0, info.startTime + info.duration - GetTime())
    if remaining <= 0 then
        surgeRow:Hide()
        return
    end
    surgeRow:Show()
    local frac = remaining / info.duration
    surgeFill:SetWidth(math.max(1, frac * HUD_W))
    surgeLabel:SetText(string.format("%.1fs", remaining))
end

-- [ PANEL CONSTRUCTION ] ------------------------------------------------------
local function BuildPanel()
    local d   = cfg()
    local PAD = 6

    local totalH = LABEL_H + 2 + PIP_H
                 + ROW_GAP
                 + LABEL_H + 2 + BAR_H
                 + 14  -- top + bottom padding

    local f = CreateFrame("Frame", "yaqolSkyridingHUD", UIParent)
    f:SetSize(HUD_W + PAD * 2, totalH)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = cfg()
        p.point, _, p.relPoint, p.x, p.y = self:GetPoint()
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.06, 0.07, 0.82)

    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, 0)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(R, G, B, 0.30)

    local y = -6

    -- ── CHARGES ──────────────────────────────────────────────────────────
    local chargeLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chargeLbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    chargeLbl:SetText("Charges")
    chargeLbl:SetTextColor(R, G, B, 0.8)
    y = y - LABEL_H - 2

    local trackW = math.floor((HUD_W - (MAX_PIPS - 1) * PIP_GAP) / MAX_PIPS)
    for i = 1, MAX_PIPS do
        local pip = CreateFrame("Frame", nil, f)
        pip:SetSize(trackW, PIP_H)
        pip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (trackW + PIP_GAP), y)

        local track = pip:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(R_DIM, G_DIM, B_DIM, 1)

        local fill = pip:CreateTexture(nil, "BORDER")
        fill:SetPoint("LEFT", pip, "LEFT", 0, 0)
        fill:SetHeight(PIP_H)
        fill:SetWidth(1)
        fill:SetColorTexture(R, G, B, 1)

        pip.fill   = fill
        pip.trackW = trackW
        pipFrames[i] = pip
    end
    y = y - PIP_H - ROW_GAP

    -- ── WHIRLING SURGE CD ─────────────────────────────────────────────────
    surgeRow = CreateFrame("Frame", nil, f)
    surgeRow:SetSize(HUD_W + PAD * 2, LABEL_H + 2 + BAR_H)
    surgeRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)

    local wsLbl = surgeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wsLbl:SetPoint("TOPLEFT", surgeRow, "TOPLEFT", PAD, 0)
    wsLbl:SetText("Whirling Surge")
    wsLbl:SetTextColor(WS_R, WS_G, WS_B, 0.8)

    surgeLabel = surgeRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    surgeLabel:SetPoint("TOPRIGHT", surgeRow, "TOPRIGHT", -PAD, 0)
    surgeLabel:SetText("")
    surgeLabel:SetTextColor(WS_R, WS_G, WS_B, 1)

    local wsTrack = surgeRow:CreateTexture(nil, "BACKGROUND")
    wsTrack:SetSize(HUD_W, BAR_H)
    wsTrack:SetPoint("TOPLEFT", surgeRow, "TOPLEFT", PAD, -(LABEL_H + 2))
    wsTrack:SetColorTexture(0.30, 0.15, 0.05, 1)

    surgeFill = surgeRow:CreateTexture(nil, "BORDER")
    surgeFill:SetPoint("LEFT", wsTrack, "LEFT", 0, 0)
    surgeFill:SetHeight(BAR_H)
    surgeFill:SetWidth(1)
    surgeFill:SetColorTexture(WS_R, WS_G, WS_B, 1)

    surgeRow:Hide()

    -- ── POSITION ─────────────────────────────────────────────────────────
    f:ClearAllPoints()
    f:SetPoint(d.point or "CENTER", UIParent, d.relPoint or "CENTER", d.x or 0, d.y or -250)

    local ticker = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        ticker = ticker + elapsed
        if ticker < (1 / UPDATE_HZ) then return end
        ticker = 0
        UpdateCharges()
        UpdateWhirlingSurge()
    end)

    f:Hide()
    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function SkyridingHUD.Init(addon)
    panel = BuildPanel()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("SPELL_UPDATE_CHARGES")
    watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            if ShouldShow() then ShowHUD() else HideHUD() end
        elseif event == "SPELL_UPDATE_CHARGES" then
            if isVisible then UpdateCharges() end
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            if isVisible then UpdateWhirlingSurge() end
        end
    end)
end

function SkyridingHUD.Refresh(addon)
    if not panel then return end
    local d = cfg()
    if not d.enabled then HideHUD(); return end
    panel:ClearAllPoints()
    panel:SetPoint(d.point or "CENTER", UIParent, d.relPoint or "CENTER", d.x or 0, d.y or -250)
    if ShouldShow() then ShowHUD(); UpdateCharges(); UpdateWhirlingSurge() end
end

function SkyridingHUD.GetPanel()
    return panel
end
