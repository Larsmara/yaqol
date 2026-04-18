local ADDON_NAME, ns = ...
ns.MouseTracker = {}
local MouseTracker = ns.MouseTracker

-- [ CONSTANTS ] ---------------------------------------------------------------
local SEGMENTS      = 64   -- arc subdivisions; 64 gives a smooth, gap-free ring
local CHORD_OVERLAP = 2    -- extra px on each chord texture to close junction gaps

-- [ STATE ] -------------------------------------------------------------------
local trackerFrame         -- fullscreen transparent host frame
local ringTexs   = {}      -- [SEGMENTS] Texture objects for the ring
local crossTexs  = {}      -- [4] Texture objects: top, bottom, right, left bars
local dotTex     = nil     -- single square texture for the center dot
local chData     = {}      -- [SEGMENTS] precomputed chord geometry (radius-dependent)

-- Dirty flags — geometry only rebuilt when values actually change
local cachedRadius    = -1
local cachedThickness = -1
local crossPrevLen    = -1  -- cached crosshair length (avoid per-frame SetSize)
local crossPrevTh     = -1  -- cached crosshair thickness

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return ns.Addon:Profile().mouseTracker end

-- Recompute chord midpoints, lengths, and rotation angles when radius changes.
--   chData[i].mx/my : offset from cursor center to chord midpoint (UI px)
--   chData[i].len   : chord length (px)
--   chData[i].angle : SetRotation value so the texture aligns with the chord
local function RebuildChordData(radius)
    if radius == cachedRadius then return end
    cachedRadius = radius
    local pi2 = math.pi * 2
    for i = 1, SEGMENTS do
        local a1 = (i - 1) / SEGMENTS * pi2
        local a2 =  i      / SEGMENTS * pi2
        local x1 = math.cos(a1) * radius
        local y1 = math.sin(a1) * radius
        local x2 = math.cos(a2) * radius
        local y2 = math.sin(a2) * radius
        local dx, dy = x2 - x1, y2 - y1
        chData[i] = {
            mx    = (x1 + x2) * 0.5,
            my    = (y1 + y2) * 0.5,
            len   = math.sqrt(dx * dx + dy * dy),
            angle = math.atan2(dy, dx),
        }
    end
end

-- Apply SetSize + SetRotation to ring textures when radius or thickness changes.
local function ApplyRingGeometry()
    local db = cfg()
    local r  = db.radius    or 32
    local th = db.thickness or 2
    if r == cachedRadius and th == cachedThickness then return end
    RebuildChordData(r)
    cachedThickness = th
    for i = 1, SEGMENTS do
        local cd = chData[i]
        ringTexs[i]:SetSize(cd.len + CHORD_OVERLAP, th)
        ringTexs[i]:SetRotation(cd.angle)
    end
end

-- Apply vertex color + alpha to all ring and crosshair textures.
local function ApplyColor()
    local db = cfg()
    local T  = ns.Theme
    local r, g, b
    if db.useAccent then
        r, g, b = T.accent[1], T.accent[2], T.accent[3]
    else
        r, g, b = db.r or 1, db.g or 1, db.b or 1
    end
    local a = db.alpha or 0.85
    for i = 1, SEGMENTS do
        ringTexs[i]:SetVertexColor(r, g, b, a)
    end
    for _, tex in ipairs(crossTexs) do
        tex:SetVertexColor(r, g, b, a)
    end
    if dotTex then dotTex:SetVertexColor(r, g, b, a) end
end

-- [ FRAME BUILDER ] -----------------------------------------------------------
local function BuildTracker()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(1)
    f:EnableMouse(false)

    -- Ring: 64 solid-colored rectangular chord textures
    for i = 1, SEGMENTS do
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        ringTexs[i] = tex
    end

    -- Crosshair: 4 bars (top, bottom, right, left)
    for i = 1, 4 do
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        crossTexs[i] = tex
    end

    -- Center dot
    dotTex = f:CreateTexture(nil, "OVERLAY")
    dotTex:SetColorTexture(1, 1, 1, 1)

    cachedRadius    = -1
    cachedThickness = -1
    crossPrevLen    = -1
    crossPrevTh     = -1

    ApplyRingGeometry()
    ApplyColor()

    local scale     = UIParent:GetEffectiveScale()
    local scaleTime = 0

    f:SetScript("OnUpdate", function()
        local db = cfg()

        -- Refresh scale once per second
        local now = GetTime()
        if now - scaleTime > 1 then
            scale     = UIParent:GetEffectiveScale()
            scaleTime = now
        end

        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale

        -- Ring ------------------------------------------------------------------
        if db.showRing then
            ApplyRingGeometry()  -- no-op unless radius/thickness changed
            for i = 1, SEGMENTS do
                local cd = chData[i]
                ringTexs[i]:SetPoint("CENTER", f, "BOTTOMLEFT", cx + cd.mx, cy + cd.my)
                ringTexs[i]:Show()
            end
        else
            for i = 1, SEGMENTS do ringTexs[i]:Hide() end
        end

        -- Center dot ----------------------------------------------------------
        if db.showDot then
            local ds = db.dotSize or 6
            dotTex:SetSize(ds, ds)
            dotTex:SetPoint("CENTER", f, "BOTTOMLEFT", cx, cy)
            dotTex:Show()
        else
            dotTex:Hide()
        end

        -- Crosshair ------------------------------------------------------------
        if db.showCrosshair then
            local len = db.crosshairLength    or 20
            local gap = db.crosshairGap       or 6
            local th  = db.crosshairThickness or 2

            if len ~= crossPrevLen or th ~= crossPrevTh then
                crossTexs[1]:SetSize(th, len)   -- top (vertical)
                crossTexs[2]:SetSize(th, len)   -- bottom (vertical)
                crossTexs[3]:SetSize(len, th)   -- right (horizontal)
                crossTexs[4]:SetSize(len, th)   -- left (horizontal)
                crossPrevLen = len
                crossPrevTh  = th
            end

            -- top: BOTTOM edge anchored at gap above cursor
            crossTexs[1]:SetPoint("BOTTOM", f, "BOTTOMLEFT", cx, cy + gap)
            crossTexs[1]:Show()
            -- bottom: TOP edge anchored at gap below cursor
            crossTexs[2]:SetPoint("TOP",    f, "BOTTOMLEFT", cx, cy - gap)
            crossTexs[2]:Show()
            -- right: LEFT edge anchored at gap right of cursor
            crossTexs[3]:SetPoint("LEFT",   f, "BOTTOMLEFT", cx + gap, cy)
            crossTexs[3]:Show()
            -- left: RIGHT edge anchored at gap left of cursor
            crossTexs[4]:SetPoint("RIGHT",  f, "BOTTOMLEFT", cx - gap, cy)
            crossTexs[4]:Show()
        else
            for _, tex in ipairs(crossTexs) do tex:Hide() end
        end
    end)

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function MouseTracker.Init(addon)
    local db = cfg()
    if db.enabled then
        trackerFrame = BuildTracker()
    end
end

function MouseTracker.Refresh(addon)
    local db = cfg()
    if db.enabled then
        if not trackerFrame then
            trackerFrame = BuildTracker()
        else
            cachedRadius    = -1
            cachedThickness = -1
            crossPrevLen    = -1
            crossPrevTh     = -1
            ApplyRingGeometry()
            ApplyColor()
            trackerFrame:Show()
        end
    else
        if trackerFrame then trackerFrame:Hide() end
    end
end

function MouseTracker.GetFrame() return trackerFrame end
