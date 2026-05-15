local ADDON_NAME, ns = ...
ns.Theme = {}
local Theme = ns.Theme

-- [ COLOR TOKENS ] ------------------------------------------------------------
-- Single minimal palette. No skin switching.
local TOKENS = {
    bg         = { 0.06, 0.06, 0.08, 0.85 },  -- panel backdrops only
    bgRow      = { 0.10, 0.10, 0.13, 1.00 },  -- alternating row tint in tables
    bgInput    = { 0.05, 0.05, 0.07, 1.00 },  -- edit box / dropdown backgrounds
    accent     = { 0.45, 0.58, 0.78, 1.00 },  -- active tabs, toggle on, bar fill, hover text
    accentDim  = { 0.30, 0.40, 0.58, 1.00 },  -- slider fill, secondary highlights
    accentHL   = { 0.45, 0.58, 0.78, 0.12 },  -- hover highlight fill on rows/tabs
    barBg      = { 0.15, 0.15, 0.18, 0.50 },  -- bar track (faint, semi-transparent)
    barFill    = { 0.45, 0.58, 0.78, 1.00 },  -- bar fill (same as accent)
    text       = { 0.92, 0.92, 0.92, 1.00 },  -- primary text
    textDim    = { 0.55, 0.58, 0.62, 1.00 },  -- secondary / inactive text
    toggleOn   = { 0.45, 0.58, 0.78, 1.00 },  -- toggle pill "on"
    toggleOff  = { 0.25, 0.26, 0.30, 1.00 },  -- toggle pill "off"
}

-- [ INIT ] --------------------------------------------------------------------
-- Called from yaqol:OnInitialize after AceDB is ready.
-- Copies tokens directly onto ns.Theme.
function Theme.Init()
    for k, v in pairs(TOKENS) do Theme[k] = v end
end

-- [ ESCAPE COLOR ] ------------------------------------------------------------
-- Returns a |cffRRGGBB escape sequence for the named color token.
function Theme.EscapeColor(key)
    local c = Theme[key]
    if not c then return "|r" end
    return string.format("|cff%02x%02x%02x",
        math.floor(c[1] * 255),
        math.floor(c[2] * 255),
        math.floor(c[3] * 255))
end

-- [ BACKGROUND ] --------------------------------------------------------------
-- Creates a BACKGROUND-layer solid-color texture covering the entire frame.
-- token: optional color key (default "bg").
function Theme:ApplyBg(frame, token)
    local c = self[token or "bg"]
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(c[1], c[2], c[3], c[4])
    return t
end

-- [ BAR RENDERING ] -----------------------------------------------------------
-- Sets the bar fill color (initial setup). Flat SetColorTexture.
function Theme:ApplyBarFill(texture)
    local c = self.barFill
    texture:SetColorTexture(c[1], c[2], c[3], c[4])
end

-- Sets the bar track/trough texture. Faint semi-transparent.
function Theme:ApplyBarBg(texture)
    local c = self.barBg
    texture:SetColorTexture(c[1], c[2], c[3], c[4])
end

-- Updates a fill texture's color at runtime (e.g. during bar update logic).
function Theme:PaintFill(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- [ HUD FONT TREATMENT ] -----------------------------------------------------
-- Applies OUTLINE + soft shadow for readability over the game world.
-- Call on every FontString in HUD modules at creation time.
function Theme:ApplyHudFont(fontString)
    local path, size = fontString:GetFont()
    if path and size then
        fontString:SetFont(path, size, "OUTLINE")
    end
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.6)
end

-- [ BUTTON STYLING ] ----------------------------------------------------------
-- Text-only button. No background. Hover shifts text to accent color.
function Theme:StyleButton(btn, w, h)
    local accent = self.accent
    local text   = self.text
    local hl     = self.accentHL

    -- Subtle hover fill
    local hlTex = btn:CreateTexture(nil, "HIGHLIGHT")
    hlTex:SetAllPoints()
    hlTex:SetColorTexture(hl[1], hl[2], hl[3], hl[4])

    -- Text color management (FontString may not exist yet at call time)
    local fs = btn:GetFontString()
    if fs then fs:SetTextColor(text[1], text[2], text[3], 1) end
    btn:SetScript("OnEnter", function(self)
        local f = self:GetFontString()
        if f then f:SetTextColor(accent[1], accent[2], accent[3], 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        local f = self:GetFontString()
        if f then f:SetTextColor(text[1], text[2], text[3], 1) end
    end)

    hooksecurefunc(btn, "Disable", function(self)
        local f = self:GetFontString()
        if f then f:SetTextColor(0.4, 0.4, 0.4, 0.6) end
    end)
    hooksecurefunc(btn, "Enable", function(self)
        local f = self:GetFontString()
        if f then f:SetTextColor(text[1], text[2], text[3], 1) end
    end)
end

-- [ TAB STYLING ] -------------------------------------------------------------
-- StyleTab: hover gets accentHL fill. No other decoration.
function Theme:StyleTab(btn)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(self.accentHL[1], self.accentHL[2], self.accentHL[3], self.accentHL[4])
end

-- SetTabActive: active text in accent, inactive text in textDim.
function Theme:SetTabActive(btn, isActive)
    if isActive then
        btn.lbl:SetTextColor(self.accent[1], self.accent[2], self.accent[3], 1)
    else
        btn.lbl:SetTextColor(self.textDim[1], self.textDim[2], self.textDim[3], 1)
    end
end
