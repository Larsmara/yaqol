local ADDON_NAME, ns = ...
ns.MinimapButton = {}
local MinimapButton = ns.MinimapButton

-- [ CONSTANTS ] ---------------------------------------------------------------
local ICON_TEXTURE = "Interface/Icons/achievement_dungeon_utgardepinnacle_10man" -- generic dungeon icon
local BTN_SIZE = 32
local RADIUS   = 80 -- minimap button orbit radius

-- [ MATH ] --------------------------------------------------------------------
local function AngleToPos(angle)
    local rad = math.rad(angle)
    return RADIUS * math.cos(rad), RADIUS * math.sin(rad)
end

local function PosToAngle(x, y)
    return math.deg(math.atan2(y, x))
end

-- [ BUILD ] -------------------------------------------------------------------
local btn

local function UpdatePosition()
    local angle = ns.Addon:Profile().minimap.minimapPos
    local x, y = AngleToPos(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MinimapButton.Init(addon)
    local db = addon:Profile().minimap

    btn = CreateFrame("Button", "yaqolMinimapButton", Minimap)
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:SetFrameLevel(8)
    btn:SetFrameStrata("MEDIUM")

    -- Circular mask
    local mask = btn:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(ICON_TEXTURE)
    icon:AddMaskTexture(mask)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    btn.border = border

    btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

    -- Dragging along minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
        local cx, cy = Minimap:GetCenter()
        local mx, my = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local dx, dy = (mx / scale) - cx, (my / scale) - cy
        local angle = PosToAngle(dx, dy)
        ns.Addon:Profile().minimap.minimapPos = angle
        UpdatePosition()
    end) end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    -- Left click → toggle teleport panel
    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ns.Teleport.Toggle()
        elseif button == "RightButton" then
            MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
                rootDescription:CreateTitle("|cffffcc00yaqol|r")
                rootDescription:CreateButton("Options",     function() ns.Config.Toggle() end)
                rootDescription:CreateButton("Run History", function() ns.RunHistory.Toggle() end)
            end)
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffcc00yaqol|r")
        GameTooltip:AddLine("Left Click: Toggle Teleport Panel", 1, 1, 1)
        GameTooltip:AddLine("Right Click: Open Options", 1, 1, 1)
        GameTooltip:AddLine("Tip: /lqol layout — arrange frames", 0.68, 0.72, 0.74)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    if db.hide then btn:Hide() end
end

function MinimapButton.Refresh(addon)
    if not btn then return end
    local db = addon:Profile().minimap
    UpdatePosition()
    if db.hide then btn:Hide() else btn:Show() end
end
