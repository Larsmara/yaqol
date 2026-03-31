local ADDON_NAME, ns = ...
ns.ChangelogUI = {}
local ChangelogUI = ns.ChangelogUI

-- [ THEME (mirrors Options.lua) ] ---------------------------------------------
local T = {
    bg          = { 0.13, 0.14, 0.16, 0.97 },
    bgRow       = { 0.18, 0.20, 0.23, 1.00 },
    accent      = { 0.18, 0.78, 0.72, 1.00 },
    border      = { 0.18, 0.70, 0.65, 0.55 },
    text        = { 1.00, 1.00, 1.00, 1.00 },
    textDim     = { 0.68, 0.72, 0.74, 1.00 },
    textHeader  = { 0.22, 0.85, 0.78, 1.00 },
    W           = 520,
    H           = 480,
    PAD         = 14,
    HEADER_H    = 46,
}

-- [ FRAME ] -------------------------------------------------------------------
local frame

local function BuildFrame()
    local W, H = T.W, T.H

    local configPanel = _G["yaqolConfigPanel"]
    local parent = configPanel or UIParent
    local f = CreateFrame("Frame", "yaqolChangelogFrame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- background (fully opaque so it sits cleanly over the config panel)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], 1.0)

    -- left accent stripe
    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetSize(3, H)
    stripe:SetPoint("TOPLEFT")
    stripe:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

    -- header bar
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(W, T.HEADER_H)
    header:SetPoint("TOPLEFT")
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(T.accent[1]*0.10, T.accent[2]*0.10, T.accent[3]*0.10, 1)
    local hline = header:CreateTexture(nil, "OVERLAY")
    hline:SetHeight(1)
    hline:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    hline:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.7)

    local titleLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLbl:SetPoint("LEFT", header, "LEFT", T.PAD, 0)
    titleLbl:SetText("|cff2dc9b8What's New|r")
    titleLbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- scrollable body
    local CONTENT_Y = T.HEADER_H + 1
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetSize(W - 28, H - CONTENT_Y - 8)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -CONTENT_Y)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(W - 28, 2000)
    scrollFrame:SetScrollChild(content)

    -- scrollbar
    local scrollBar = CreateFrame("Slider", nil, f)
    scrollBar:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -4, -CONTENT_Y - 4)
    scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4,  4)
    scrollBar:SetWidth(8)
    scrollBar:SetMinMaxValues(0, 100)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    local sbBg = scrollBar:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 0.3)
    local sbThumb = scrollBar:CreateTexture(nil, "ARTWORK")
    sbThumb:SetSize(8, 40)
    sbThumb:SetColorTexture(T.accent[1]*0.8, T.accent[2]*0.8, T.accent[3]*0.8, 1)
    scrollBar:SetThumbTexture(sbThumb)
    scrollBar:SetScript("OnValueChanged", function(self, val)
        scrollFrame:SetVerticalScroll(val)
    end)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = scrollBar:GetValue()
        local _, maxVal = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(0, math.min(cur - delta * 40, maxVal)))
    end)

    -- populate changelog entries
    local ENTRY_PAD = 10
    local y = -ENTRY_PAD

    for _, entry in ipairs(ns.Changelog or {}) do
        -- version + date heading
        local versionStr = string.format("|cff2dc9b8v%s|r  |cff%s%s|r",
            entry.version,
            "aaaaaa", entry.date)
        local vLbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vLbl:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
        vLbl:SetText(versionStr)
        y = y - 20

        -- divider
        local div = content:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  content, "TOPLEFT",  T.PAD,        y)
        div:SetPoint("TOPRIGHT", content, "TOPRIGHT", -T.PAD - 14,  y)
        div:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
        y = y - 8

        -- change lines
        for _, line in ipairs(entry.changes or {}) do
            local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD + 4, y)
            lbl:SetWidth(T.W - T.PAD*2 - 30)
            lbl:SetJustifyH("LEFT")
            lbl:SetText("• " .. line)
            lbl:SetTextColor(T.text[1], T.text[2], T.text[3], 0.9)
            y = y - lbl:GetStringHeight() - 4
        end

        y = y - ENTRY_PAD
    end

    -- update scrollbar range once content height is known
    local contentH = math.abs(y) + ENTRY_PAD
    content:SetHeight(math.max(contentH, H - CONTENT_Y))
    local maxScroll = math.max(0, contentH - scrollFrame:GetHeight())
    scrollBar:SetMinMaxValues(0, maxScroll)
    if maxScroll <= 0 then scrollBar:Hide() end

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function ChangelogUI.Toggle()
    if not frame then frame = BuildFrame() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function ChangelogUI.Show()
    if not frame then frame = BuildFrame() end
    frame:Show()
end
