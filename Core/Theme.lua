local ADDON_NAME, ns = ...
ns.Theme = {}
local Theme = ns.Theme

-- [ THEME DEFINITIONS ] -------------------------------------------------------
local THEMES = {}

THEMES["mellow"] = {
    skin       = "flat",
    bg         = { 0.09, 0.09, 0.11, 0.88 },
    bgPanel    = { 0.11, 0.11, 0.14, 0.95 },
    bgRow      = { 0.14, 0.15, 0.18, 1.00 },
    bgInput    = { 0.08, 0.08, 0.11, 1.00 },
    accent     = { 0.42, 0.62, 0.88, 1.00 },
    accentDim  = { 0.28, 0.42, 0.62, 1.00 },
    accentHL   = { 0.42, 0.62, 0.88, 0.15 },
    border     = { 0.38, 0.52, 0.72, 0.45 },
    barBg      = { 0.12, 0.13, 0.16, 1.00 },
    barFill    = { 0.42, 0.62, 0.88, 1.00 },
    text       = { 0.95, 0.95, 0.95, 1.00 },
    textDim    = { 0.62, 0.65, 0.68, 1.00 },
    textHeader = { 0.55, 0.72, 0.92, 1.00 },
    toggleOn   = { 0.42, 0.62, 0.88, 1.00 },
    toggleOff  = { 0.28, 0.30, 0.34, 1.00 },
}

THEMES["blizzard"] = {
    skin       = "blizzard",
    bg         = { 0.04, 0.03, 0.02, 0.92 },
    bgPanel    = { 0.07, 0.05, 0.04, 0.97 },
    bgRow      = { 0.10, 0.08, 0.06, 1.00 },
    bgInput    = { 0.04, 0.03, 0.02, 1.00 },
    accent     = { 0.84, 0.68, 0.28, 1.00 },
    accentDim  = { 0.58, 0.46, 0.18, 1.00 },
    accentHL   = { 0.84, 0.68, 0.28, 0.15 },
    border     = { 0.70, 0.56, 0.20, 0.55 },
    barBg      = { 0.08, 0.06, 0.04, 1.00 },
    barFill    = { 0.84, 0.68, 0.28, 1.00 },
    text       = { 1.00, 1.00, 1.00, 1.00 },
    textDim    = { 0.72, 0.68, 0.60, 1.00 },
    textHeader = { 0.96, 0.82, 0.40, 1.00 },
    toggleOn   = { 0.84, 0.68, 0.28, 1.00 },
    toggleOff  = { 0.28, 0.24, 0.18, 1.00 },
}

-- [ FLAT SKIN ] ---------------------------------------------------------------
-- Color-drawn surfaces via SetColorTexture. Used by "mellow".
local FlatSkin = {}

-- Creates a BACKGROUND-layer solid-color texture covering the entire frame.
-- token: optional color key (default "bgPanel"). Pass "bg" for HUD frames.
function FlatSkin:ApplyBg(frame, token)
    local c = self[token or "bgPanel"]
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(c[1], c[2], c[3], c[4])
    return t
end

-- Draws a 1px colored border on all four edges of the frame.
function FlatSkin:ApplyBorder(frame)
    local c = self.border
    local function Edge(p1, p2, isH)
        local e = frame:CreateTexture(nil, "BORDER")
        if isH then e:SetHeight(1) else e:SetWidth(1) end
        e:SetPoint(p1); e:SetPoint(p2)
        e:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    Edge("TOPLEFT",    "TOPRIGHT",    true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT",    "BOTTOMLEFT",  false)
    Edge("TOPRIGHT",   "BOTTOMRIGHT", false)
end

-- Sets the bar fill color (initial setup).  Use PaintFill for dynamic updates.
function FlatSkin:ApplyBarFill(texture)
    local c = self.barFill
    texture:SetColorTexture(c[1], c[2], c[3], c[4])
end

-- Updates a fill texture's color at runtime (e.g. during bar update logic).
-- Flat skin: overrides with SetColorTexture.
function FlatSkin:PaintFill(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- [ BLIZZARD SKIN ] -----------------------------------------------------------
-- Atlas/BackdropTemplate-based surfaces. Used by "blizzard".
local BlizzardSkin = {}

-- Applies a background to the frame using the tiled dark-dialog backdrop.
-- token: optional color key (default "bgPanel"). Pass "bg" for HUD frames.
function BlizzardSkin:ApplyBg(frame, token)
    local c = self[token or "bgPanel"]
    local bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bd:SetAllPoints()
    bd:SetFrameLevel(frame:GetFrameLevel())
    bd:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        tile     = true,
        tileSize = 256,
    })
    bd:SetBackdropColor(c[1], c[2], c[3], c[4])
    return bd
end

-- Creates a NineSlice "Dialog" border (UI-Frame-DiamondMetal atlas) that
-- overhangs 5 px outside the frame — same as Blizzard's own dialog windows.
function BlizzardSkin:ApplyBorder(frame)
    local bd = CreateFrame("Frame", nil, frame)
    bd:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -5,  5)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  5, -5)
    bd:SetFrameLevel(frame:GetFrameLevel() + 100)
    NineSliceUtil.ApplyLayoutByName(bd, "Dialog")
    return bd
end

-- Sets a status-bar texture on the fill, tinted gold (initial setup).
-- Use PaintFill for dynamic color updates — it preserves the texture.
function BlizzardSkin:ApplyBarFill(texture)
    local c = self.barFill
    texture:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    texture:SetVertexColor(c[1], c[2], c[3], c[4])
end

-- Updates a fill texture's tint at runtime.
-- Blizzard skin: uses SetVertexColor to preserve the bar fill texture.
function BlizzardSkin:PaintFill(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- [ BAR BACKGROUND ] ---------------------------------------------------------
-- Sets the bar trough texture. FlatSkin: solid barBg color.
-- BlizzardSkin: same UI-StatusBar texture as the fill, tinted dark.
function FlatSkin:ApplyBarBg(texture)
    local c = self.barBg
    texture:SetColorTexture(c[1], c[2], c[3], 1)
end

function BlizzardSkin:ApplyBarBg(texture)
    local c = self.barBg
    texture:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    texture:SetVertexColor(c[1], c[2], c[3], 1)
end

-- [ COMPACT BORDER ] ----------------------------------------------------------
-- Uses SimplePanelTemplate NineSlice (UI-Frame-SimpleMetal).
-- Smaller corners than Dialog — suited for HUD-size frames (≤ 350 px wide).
-- FlatSkin delegates to the same flat 1px lines as ApplyBorder.
function FlatSkin:ApplyBorderCompact(frame) return self:ApplyBorder(frame) end

function BlizzardSkin:ApplyBorderCompact(frame)
    local bd = CreateFrame("Frame", nil, frame)
    bd:SetAllPoints(frame)
    bd:SetFrameLevel(frame:GetFrameLevel() + 100)
    NineSliceUtil.ApplyLayoutByName(bd, "SimplePanelTemplate")
    return bd
end ---------------------------------------------------------
-- Applies themed header decoration (bg + banner) to a header frame.
-- Call this before placing labels inside the header so labels layer on top.
function FlatSkin:ApplyHeader(header)
    local c = self.accent
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1]*0.10, c[2]*0.10, c[3]*0.10, 1)
    local line = header:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    line:SetColorTexture(c[1], c[2], c[3], 0.7)
end

-- Uses the WoW DiamondMetal header atlas: CornerLeft + tiling Center + CornerRight.
-- Same art as used on Blizzard's DialogHeaderTemplate and all system dialogs.
function BlizzardSkin:ApplyHeader(header)
    local c = self.bgPanel
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1]*1.6, c[2]*1.4, c[3]*1.0, 1)
    local left = header:CreateTexture(nil, "OVERLAY")
    left:SetAtlas("UI-Frame-DiamondMetal-Header-CornerLeft", false)
    left:SetSize(32, 39)  -- explicit size matching DialogHeaderTemplate; intrinsic atlas is larger
    left:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    local right = header:CreateTexture(nil, "OVERLAY")
    right:SetAtlas("UI-Frame-DiamondMetal-Header-CornerRight", false)
    right:SetSize(32, 39)
    right:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    local center = header:CreateTexture(nil, "OVERLAY")
    center:SetAtlas("_UI-Frame-DiamondMetal-Header-Tile")
    center:SetHorizTile(true)
    center:SetPoint("TOPLEFT",  left,  "TOPRIGHT", 0, 0)
    center:SetPoint("TOPRIGHT", right, "TOPLEFT",  0, 0)
    center:SetHeight(39)
end

-- [ BUTTON STYLING ] ----------------------------------------------------------
-- Applies theme-specific button art. Called from MakeButton in Options.lua.
function FlatSkin:StyleButton(btn, w, h)
    local c = self.bgRow
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0.15)
    local line = btn:CreateTexture(nil, "OVERLAY")
    line:SetSize(w, 1); line:SetPoint("BOTTOM")
    line:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0.8)
    hooksecurefunc(btn, "Disable", function() bg:SetVertexColor(0.4, 0.4, 0.4, 0.6) end)
    hooksecurefunc(btn, "Enable",  function() bg:SetVertexColor(1, 1, 1, 1) end)
end

-- Three-piece gold button art (Interface\Buttons\UI-DialogBox-goldbutton-*).
-- Swaps textures on push/release and Disable/Enable.
function BlizzardSkin:StyleButton(btn, w, h)
    local PAD = 14
    local function SetState(state)
        local p = "Interface\\Buttons\\UI-DialogBox-goldbutton-" .. state .. "-"
        btn._btnL:SetTexture(p .. "left")
        btn._btnM:SetTexture(p .. "middle")
        btn._btnR:SetTexture(p .. "right")
    end
    local left = btn:CreateTexture(nil, "BACKGROUND")
    left:SetSize(PAD, h); left:SetPoint("LEFT", btn, "LEFT", 0, 0)
    btn._btnL = left
    local mid = btn:CreateTexture(nil, "BACKGROUND")
    mid:SetPoint("LEFT",  left, "RIGHT", 0, 0)
    mid:SetPoint("RIGHT", btn,  "RIGHT", -PAD, 0)
    mid:SetHeight(h)
    btn._btnM = mid
    local right = btn:CreateTexture(nil, "BACKGROUND")
    right:SetSize(PAD, h); right:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    btn._btnR = right
    SetState("up")
    -- ButtonHilight-Square with ADD blending is the WoW-standard hover glow for dialog buttons.
    -- It brightens the gold art on mouse-over and is exactly scoped to the button's hit rect —
    -- no "larger hover box" artefact from HIGHLIGHT draw-layer SetAllPoints.
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then SetState("down") end
    end)
    btn:SetScript("OnMouseUp", function(self)
        SetState(self:IsEnabled() and "up" or "disabled")
    end)
    hooksecurefunc(btn, "Disable", function() SetState("disabled") end)
    hooksecurefunc(btn, "Enable",  function() SetState("up") end)
end

-- [ TAB STYLING ] -------------------------------------------------------------
-- InitTabBar: called once after creating the sliding indicator.
-- FlatSkin keeps the indicator; BlizzardSkin hides it (uses per-tab bg instead).
function FlatSkin:InitTabBar(indicator)  end

function BlizzardSkin:InitTabBar(indicator)
    indicator:Hide()
end

-- StyleTab: called once per tab button at creation time.
function FlatSkin:StyleTab(btn)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0.08)
end

function BlizzardSkin:StyleTab(btn)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0)
    btn._tabBg = bg
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0.10)
    local bar = btn:CreateTexture(nil, "BORDER")
    bar:SetSize(3, 0)
    bar:SetPoint("TOPLEFT",    btn, "TOPLEFT",    0, 0)
    bar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bar:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 1)
    bar:Hide()
    btn._tabBar = bar
end

-- SetTabActive: called by SetTab for every tab button on each tab switch.
function FlatSkin:SetTabActive(btn, isActive)
    if isActive then
        btn.lbl:SetTextColor(self.accent[1], self.accent[2], self.accent[3], 1)
    else
        btn.lbl:SetTextColor(self.textDim[1], self.textDim[2], self.textDim[3], 1)
    end
end

function BlizzardSkin:SetTabActive(btn, isActive)
    if isActive then
        btn._tabBg:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0.15)
        btn.lbl:SetTextColor(self.accent[1], self.accent[2], self.accent[3], 1)
        if btn._tabBar then btn._tabBar:Show() end
    else
        btn._tabBg:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 0)
        btn.lbl:SetTextColor(self.textDim[1], self.textDim[2], self.textDim[3], 1)
        if btn._tabBar then btn._tabBar:Hide() end
    end
end

-- [ CONTENT INSET ] -----------------------------------------------------------
-- Applies an inner shadow/bevel using Blizzard's InsetFrameTemplate NineSlice.
-- FlatSkin: no decoration. BlizzardSkin: renders UI-Frame-Inner* at frame edges.
function FlatSkin:ApplyInset(frame)  end

function BlizzardSkin:ApplyInset(frame)
    local inset = CreateFrame("Frame", nil, frame)
    inset:SetAllPoints()
    inset:SetFrameLevel(frame:GetFrameLevel() + 1)
    NineSliceUtil.ApplyLayoutByName(inset, "InsetFrameTemplate")
end

-- [ INIT ] --------------------------------------------------------------------
-- Called from yaqol:OnInitialize after AceDB is ready.
-- Populates ns.Theme with the active theme's tokens and skin methods.
function Theme.Init()
    local key = ns.Addon.db.global.theme or "mellow"
    local tokens = THEMES[key] or THEMES["mellow"]
    for k, v in pairs(tokens) do Theme[k] = v end
    local skin = (tokens.skin == "blizzard") and BlizzardSkin or FlatSkin
    for k, v in pairs(skin) do Theme[k] = v end
end

-- Returns a |cffRRGGBB escape sequence for the named color token.
-- Usage: Theme.EscapeColor("accent") → "|cff6b9ee0" (or current theme accent)
function Theme.EscapeColor(key)
    local c = Theme[key]
    if not c then return "|r" end
    return string.format("|cff%02x%02x%02x",
        math.floor(c[1] * 255),
        math.floor(c[2] * 255),
        math.floor(c[3] * 255))
end
