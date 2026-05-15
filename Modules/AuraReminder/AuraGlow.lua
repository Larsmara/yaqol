local ADDON_NAME, ns = ...
ns.AuraGlow = {}
local AuraGlow = ns.AuraGlow

-- [ GLOW ENGINES ] ------------------------------------------------------------
-- Wraps LibCustomGlow (Pixel, Autocast, ActionButton) plus a custom alpha pulse.
-- Public API:
--   AuraGlow.Start(frame, glowType, color)  -- start glow on a frame
--   AuraGlow.Stop(frame)                    -- stop all glows on a frame
--   AuraGlow.StopAll()                      -- stop all active glows

local LCG = LibStub("LibCustomGlow-1.0", true)
local activeGlows = {}  -- frame -> glowType (track what's active for cleanup)

-- [ GLOW TYPE REGISTRY ] -----------------------------------------------------
local GLOW_TYPES = {
    NONE     = "NONE",
    BLIZZARD = "BLIZZARD",
    PIXEL    = "PIXEL",
    AUTOCAST = "AUTOCAST",
    PULSE    = "PULSE",
}
AuraGlow.Types = GLOW_TYPES

-- [ ALPHA PULSE ] -------------------------------------------------------------
-- Custom alpha-bounce animation (the original yaqol blink, kept as an option).
-- Manages its own AnimationGroup per frame.
local function StartPulse(frame, color)
    if not frame._pulseAG then
        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.4)
        alpha:SetToAlpha(1.0)
        alpha:SetDuration(0.7)
        frame._pulseAG = ag
    end
    frame._pulseAG:Play()
end

local function StopPulse(frame)
    if frame._pulseAG then
        frame._pulseAG:Stop()
        -- Reset alpha to full after stopping
        if frame.icon then frame.icon:SetAlpha(1) end
    end
end

-- [ CLICK-THROUGH ] -----------------------------------------------------------
-- LibCustomGlow overlay frames can intercept mouse clicks, blocking the
-- SecureActionButton underneath.  After every LCG start call, grab the
-- overlay it created and disable mouse interaction on it.
local function DisableGlowMouse(fr, glowType)
    local overlay
    if glowType == "BLIZZARD" then
        overlay = fr._ButtonGlow
    elseif glowType == "PIXEL" then
        overlay = fr._PixelGlow        -- key="" → "_PixelGlow"..""
    elseif glowType == "AUTOCAST" then
        overlay = fr._AutoCastGlow      -- key="" → "_AutoCastGlow"..""
    end
    if overlay and overlay.EnableMouse then
        overlay:EnableMouse(false)
    end
end

-- [ START GLOW ] --------------------------------------------------------------
function AuraGlow.Start(frame, glowType, color)
    if not frame then return end

    glowType = glowType or "BLIZZARD"

    -- If the same glow type is already running on this frame, skip the
    -- stop-then-restart cycle.  ButtonGlow_Stop triggers a fade-out animation;
    -- immediately calling ButtonGlow_Start restarts fade-in while fade-out is
    -- still in-flight, producing a visible pulse every periodic refresh.
    if activeGlows[frame] == glowType then
        return
    end

    -- Different type (or first start): stop the old glow before starting new
    AuraGlow.Stop(frame)

    local r = color and color.r or 1
    local g = color and color.g or 0.8
    local b = color and color.b or 0
    local a = color and color.a or 1

    if glowType == "NONE" then
        return

    elseif glowType == "BLIZZARD" and LCG then
        LCG.ButtonGlow_Start(frame, { r, g, b, a })
        DisableGlowMouse(frame, glowType)

    elseif glowType == "PIXEL" and LCG then
        -- PixelGlow_Start(frame, color, lineCount, frequency, length, thickness, xOff, yOff, border, key)
        LCG.PixelGlow_Start(frame, { r, g, b, a }, 8, 0.25, nil, 2, 0, 0, false)
        DisableGlowMouse(frame, glowType)

    elseif glowType == "AUTOCAST" and LCG then
        -- AutoCastGlow_Start(frame, color, particleCount, frequency, scale, xOff, yOff, key)
        LCG.AutoCastGlow_Start(frame, { r, g, b, a }, 4, 0.2, 1)
        DisableGlowMouse(frame, glowType)

    elseif glowType == "PULSE" then
        StartPulse(frame, color)

    else
        -- Fallback: if LCG is missing and type isn't PULSE, use pulse
        StartPulse(frame, color)
    end

    activeGlows[frame] = glowType
end

-- [ STOP GLOW ] ---------------------------------------------------------------
function AuraGlow.Stop(frame)
    if not frame then return end
    local glowType = activeGlows[frame]
    if not glowType then return end

    if LCG then
        -- Stop all LCG glow types (safe to call even if that type wasn't active)
        pcall(LCG.ButtonGlow_Stop, frame)
        pcall(LCG.PixelGlow_Stop, frame)
        pcall(LCG.AutoCastGlow_Stop, frame)
    end
    StopPulse(frame)

    activeGlows[frame] = nil
end

-- [ STOP ALL ] ----------------------------------------------------------------
function AuraGlow.StopAll()
    for frame in pairs(activeGlows) do
        AuraGlow.Stop(frame)
    end
    wipe(activeGlows)
end

-- [ AVAILABLE CHECK ] ---------------------------------------------------------
-- Returns true if LibCustomGlow is loaded (for UI to show/hide options).
function AuraGlow.HasLibrary()
    return LCG ~= nil
end
