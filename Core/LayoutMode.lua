local ADDON_NAME, ns = ...
ns.LayoutMode = {}
local LayoutMode = ns.LayoutMode

-- [ LAYOUT MODE ] -------------------------------------------------------------
-- Shows all positionable yaqol frames simultaneously with a drag overlay,
-- plus a floating "Done" button to exit.  Replaces per-module demo-mode toggles
-- for the purpose of repositioning frames.
--
-- Frames managed:
--   • Teleport panel          (ns.Teleport.GetPanel)
--   • Buff Reminder frame     (ns.AuraReminder.GetFrame)
--   • Durability Warning frame (ns.QOL.GetDurabilityFrame)
--
-- Usage:  /lqol layout   OR   Options → General → "Arrange Frames" button.

-- Theme colours (same palette as the rest of the addon)
local T = {
    accent  = { 0.18, 0.78, 0.72, 1.00 },
    bg      = { 0.08, 0.09, 0.11, 0.82 },
    text    = { 1.00, 1.00, 1.00, 1.00 },
    textDim = { 0.68, 0.72, 0.74, 1.00 },
    overlay = { 0.18, 0.78, 0.72, 0.18 },  -- translucent teal fill
    border  = { 0.18, 0.78, 0.72, 0.70 },
}

local active = false

-- Overlay frames we create/reuse per managed frame.
local overlays = {}

-- The floating "Done" button frame.
local doneFrame

-- ─── OVERLAY CONSTRUCTION ───────────────────────────────────────────────────

-- Creates a single overlay parented to 'targetFrame'.  The overlay covers the
-- target entirely, shows its name, and re-dispatches drag events to the target
-- so the user just drags anywhere on it.
local function MakeOverlay(targetFrame, label)
    local ov = CreateFrame("Frame", nil, targetFrame)
    ov:SetAllPoints(targetFrame)
    ov:SetFrameStrata("TOOLTIP")    -- sit above the target content
    ov:EnableMouse(true)

    -- Translucent fill
    local fill = ov:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(T.overlay[1], T.overlay[2], T.overlay[3], T.overlay[4])

    -- Border (all four edges via a single 1-px inset box)
    local function AddEdge(p1, p2, isH)
        local e = ov:CreateTexture(nil, "OVERLAY")
        if isH then e:SetHeight(1) else e:SetWidth(1) end
        e:SetPoint(p1); e:SetPoint(p2)
        e:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
    end
    AddEdge("TOPLEFT",    "TOPRIGHT",    true)
    AddEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    AddEdge("TOPLEFT",    "BOTTOMLEFT",  false)
    AddEdge("TOPRIGHT",   "BOTTOMRIGHT", false)

    -- Label
    local lbl = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("CENTER", ov, "CENTER", 0, 4)
    lbl:SetText(label)
    lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local hint = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("CENTER", ov, "CENTER", 0, -12)
    hint:SetText("Drag to move")
    hint:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)

    -- Re-dispatch drag to the underlying target frame.
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnDragStart", function()
        targetFrame:StartMoving()
    end)
    ov:SetScript("OnDragStop", function()
        targetFrame:StopMovingOrSizing()
        -- Trigger the target's own OnDragStop to persist position.
        -- Each frame has its own script; we invoke the OnDragStop script directly.
        local fn = targetFrame:GetScript("OnDragStop")
        if fn then fn(targetFrame) end
    end)

    ov:Hide()
    return ov
end

-- ─── DONE BUTTON ────────────────────────────────────────────────────────────

local function MakeDoneFrame()
    local f = CreateFrame("Frame", "yaqolLayoutDoneFrame", UIParent)
    f:SetSize(160, 40)
    f:SetFrameStrata("TOOLTIP")
    f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(T.bg[1], T.bg[2], T.bg[3], T.bg[4])

    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetHeight(2); stripe:SetPoint("TOPLEFT"); stripe:SetPoint("TOPRIGHT")
    stripe:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

    local btn = CreateFrame("Button", nil, f)
    btn:SetAllPoints()
    btn:SetScript("OnClick", function() LayoutMode.Exit() end)

    -- Checkmark icon
    local checkIcon = btn:CreateTexture(nil, "ARTWORK")
    checkIcon:SetSize(20, 20)
    checkIcon:SetPoint("LEFT", btn, "LEFT", 12, 0)
    checkIcon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", checkIcon, "RIGHT", 4, 0)
    lbl:SetText("Done Arranging")
    lbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)

    btn:SetScript("OnEnter", function()
        lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    btn:SetScript("OnLeave", function()
        lbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
    end)

    f:Hide()
    return f
end

-- ─── ENTER / EXIT ────────────────────────────────────────────────────────────

-- Descriptor table: each entry = { getFrame, label, saveFn }
-- saveFn is called after drag to ensure position is persisted (some frames do
-- it in their OnDragStop already; we call it redundantly just to be safe).
local function GetDescriptors()
    return {
        {
            getFrame = function() return ns.Teleport.GetPanel() end,
            label    = "Teleport Panel",
            show     = function() end,  -- Teleport panel already shown by Enter()
        },
        {
            getFrame = function() return ns.AuraReminder.GetFrame() end,
            label    = "Buff Reminder",
            show     = function() ns.AuraReminder.ShowForLayout() end,
        },
        {
            getFrame = function() return ns.QOL.GetDurabilityFrame() end,
            label    = "Durability Warning",
            show     = function()
                -- Show a placeholder so the frame has visible content to drag
                local f = ns.QOL.GetDurabilityFrame()
                if f then
                    f.txt:SetText("|cffff6b00⚠ Low Durability: 15%|r")
                    f:SetAlpha(1)
                    f:Show()
                end
            end,
        },
    }
end

function LayoutMode.Enter()
    if active then return end
    active = true

    if not doneFrame then doneFrame = MakeDoneFrame() end

    local descriptors = GetDescriptors()
    for i, desc in ipairs(descriptors) do
        local target = desc.getFrame()
        if target then
            -- Use the descriptor's custom show function (handles demo content)
            desc.show()
            target:Show()

            -- Build overlay on first call; reuse thereafter.
            if not overlays[i] then
                overlays[i] = MakeOverlay(target, desc.label)
            else
                -- Re-parent in case the frame was recreated.
                overlays[i]:SetParent(target)
                overlays[i]:ClearAllPoints()
                overlays[i]:SetAllPoints(target)
            end
            overlays[i]:Show()
        end
    end

    doneFrame:ClearAllPoints()
    doneFrame:SetPoint("TOP", UIParent, "TOP", 0, -60)
    doneFrame:Show()

    print("|cff2dc9b8yaqol:|r Layout mode |cffffcc00ON|r — drag frames to reposition, then click Done.")
end

function LayoutMode.Exit()
    if not active then return end
    active = false

    -- Hide overlays
    for _, ov in ipairs(overlays) do
        ov:Hide()
    end

    -- Hide frames that were shown just for layout and shouldn't normally be visible.
    -- Teleport: restore real visibility via Refresh.
    -- AuraReminder: restore via Refresh (it will re-hide if not in an instance).
    -- Durability: hide (it only shows on real durability events).
    ns.Teleport.Refresh(ns.Addon)
    ns.AuraReminder.Refresh(ns.Addon)
    local df = ns.QOL.GetDurabilityFrame()
    if df then df:Hide() end

    doneFrame:Hide()

    print("|cff2dc9b8yaqol:|r Layout mode |cff999999OFF|r — positions saved.")
end

function LayoutMode.IsActive()
    return active
end
