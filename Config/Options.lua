local ADDON_NAME, ns = ...
ns.Config = {}
local Config = ns.Config

-- [ THEME ] -------------------------------------------------------------------
local T = {
    bg          = { 0.13, 0.14, 0.16, 0.97 },
    bgRow       = { 0.18, 0.20, 0.23, 1.00 },
    bgInput     = { 0.10, 0.11, 0.13, 1.00 },
    accent      = { 0.18, 0.78, 0.72, 1.00 },
    accentDim   = { 0.14, 0.62, 0.58, 1.00 },
    border      = { 0.18, 0.70, 0.65, 0.55 },
    text        = { 1.00, 1.00, 1.00, 1.00 },
    textDim     = { 0.68, 0.72, 0.74, 1.00 },
    textHeader  = { 0.22, 0.85, 0.78, 1.00 },
    toggleOn    = { 0.18, 0.78, 0.72, 1.00 },
    toggleOff   = { 0.28, 0.30, 0.34, 1.00 },
    PANEL_W     = 700,
    PANEL_H     = 550,
    TAB_H       = 34,
    HEADER_H    = 46,
    ROW_H       = 28,
    PAD         = 14,
}

-- [ PRIMITIVES ] --------------------------------------------------------------
local function Bg(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(); t:SetColorTexture(r, g, b, a); return t
end

local function Label(parent, text, font, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(r or T.text[1], g or T.text[2], b or T.text[3], a or T.text[4])
    return fs
end

local function Divider(parent, yOff)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  T.PAD,  yOff)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.PAD, yOff)
    t:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
    return t
end

-- [ TOGGLE WIDGET ] -----------------------------------------------------------
local function MakeToggle(parent, label, getValue, setValue, yOff)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(T.PANEL_W - T.PAD*2, T.ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", T.PAD, yOff)

    local pill = CreateFrame("Button", nil, row)
    pill:SetSize(36, 18); pill:SetPoint("LEFT", row, "LEFT", 0, 0)
    local pillBg = pill:CreateTexture(nil, "BACKGROUND")
    pillBg:SetAllPoints(); pill.bg = pillBg

    local thumb = pill:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 14); pill.thumb = thumb

    local lbl = Label(row, label, "GameFontNormal")
    lbl:SetPoint("LEFT", pill, "RIGHT", 8, 0)

    local function Refresh()
        local on = getValue()
        pillBg:SetTexture("Interface/Buttons/WHITE8X8")
        pillBg:SetVertexColor(on and T.toggleOn[1] or T.toggleOff[1],
                              on and T.toggleOn[2] or T.toggleOff[2],
                              on and T.toggleOn[3] or T.toggleOff[3], 1)
        thumb:SetTexture("Interface/Buttons/WHITE8X8")
        thumb:SetVertexColor(1, 1, 1, 1)
        thumb:ClearAllPoints()
        if on then thumb:SetPoint("RIGHT", pill, "RIGHT", -2, 0)
        else       thumb:SetPoint("LEFT",  pill, "LEFT",  2,  0) end
    end
    Refresh()
    pill:SetScript("OnClick", function() setValue(not getValue()); Refresh() end)
    row.Refresh = Refresh
    return row, T.ROW_H + 4
end

-- [ SLIDER WIDGET ] -----------------------------------------------------------
local function MakeSlider(parent, label, min, max, step, getValue, setValue, yOff, fmtFn)
    local SLIDER_W = T.PANEL_W - T.PAD*2 - 80
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(T.PANEL_W - T.PAD*2, T.ROW_H + 14)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", T.PAD, yOff)

    local lbl = Label(row, label, "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    local val = Label(row, "", "GameFontNormalSmall", T.accentDim[1], T.accentDim[2], T.accentDim[3])
    val:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    local trackBg = row:CreateTexture(nil, "BACKGROUND")
    trackBg:SetSize(SLIDER_W, 4); trackBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)
    trackBg:SetTexture("Interface/Buttons/WHITE8X8")
    trackBg:SetVertexColor(T.bgRow[1], T.bgRow[2], T.bgRow[3], 1)

    local fill = row:CreateTexture(nil, "BORDER")
    fill:SetSize(0, 4); fill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    fill:SetTexture("Interface/Buttons/WHITE8X8")
    fill:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local thumb = CreateFrame("Button", nil, row)
    thumb:SetSize(12, 12)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints(); thumbTex:SetTexture("Interface/Buttons/WHITE8X8")
    thumbTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local function RefreshPos()
        local pct = (getValue() - min) / (max - min)
        local w = math.max(0, math.min(pct * SLIDER_W, SLIDER_W))
        fill:SetWidth(math.max(1, w))
        thumb:ClearAllPoints(); thumb:SetPoint("CENTER", trackBg, "LEFT", w, 0)
        val:SetText(fmtFn and fmtFn(getValue()) or tostring(getValue()))
    end
    RefreshPos()

    local dragging = false
    thumb:SetScript("OnMouseDown", function() dragging = true end)
    thumb:SetScript("OnMouseUp",   function() dragging = false end)
    row:SetScript("OnUpdate", function()
        if not dragging then return end
        local mx = GetCursorPosition() / row:GetEffectiveScale()
        local lx = trackBg:GetLeft()
        if not lx then return end
        local pct = math.max(0, math.min((mx - lx) / SLIDER_W, 1))
        local steps = math.floor(pct * (max - min) / step + 0.5)
        local newVal = math.max(min, math.min(min + steps * step, max))
        if newVal ~= getValue() then setValue(newVal); RefreshPos() end
    end)
    trackBg:EnableMouse(true)
    trackBg:SetScript("OnMouseDown", function()
        local mx = GetCursorPosition() / row:GetEffectiveScale()
        local lx = trackBg:GetLeft(); if not lx then return end
        local pct = math.max(0, math.min((mx - lx) / SLIDER_W, 1))
        local steps = math.floor(pct * (max - min) / step + 0.5)
        setValue(math.max(min, math.min(min + steps * step, max))); RefreshPos()
    end)
    row.Refresh = RefreshPos
    return row, T.ROW_H + 20
end

-- [ BUTTON WIDGET ] -----------------------------------------------------------
local function MakeButton(parent, label, onClick, w, h)
    w, h = w or 120, h or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    Bg(btn, T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
    local accentLine = btn:CreateTexture(nil, "OVERLAY")
    accentLine:SetSize(w, 1); accentLine:SetPoint("BOTTOM")
    accentLine:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.8)
    local lbl = Label(btn, label, "GameFontNormalSmall"); lbl:SetPoint("CENTER")
    btn:SetScript("OnClick", onClick)
    return btn
end

-- [ INPUT WIDGET ] ------------------------------------------------------------
local function MakeInput(parent, placeholder, onEnter, w, h)
    w, h = w or 140, h or 22
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(w, h); eb:SetAutoFocus(false); eb:SetMaxLetters(12)
    eb:SetNumeric(true); eb:SetFontObject("GameFontNormalSmall")
    eb:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
    Bg(eb, T.bgInput[1], T.bgInput[2], T.bgInput[3], T.bgInput[4])
    local border = eb:CreateTexture(nil, "BORDER")
    border:SetSize(w, 1); border:SetPoint("BOTTOM")
    border:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])
    local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph:SetPoint("LEFT", eb, "LEFT", 4, 0); ph:SetText(placeholder or "")
    ph:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], T.textDim[4])
    eb:SetScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
    eb:SetScript("OnEnterPressed", function(self)
        onEnter(self:GetText()); self:SetText(""); self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    return eb
end

-- [ SPELL LIST WIDGET ] -------------------------------------------------------
local spellRebuildFns = {}

local function MakeSpellList(parent, db, key, startY)
    if not db[key] then db[key] = {} end
    local CONTENT_W = T.PANEL_W - T.PAD * 2
    local y = startY

    local addInput = MakeInput(parent, "Add Spell ID…", function(val)
        local id = tonumber(val); if not id then return end
        local name = C_Spell.GetSpellName(id) or ("SpellID "..id)
        table.insert(db[key], { spellID = id, label = name }); Config.Refresh()
    end, 130, 22)
    addInput:SetPoint("TOPLEFT", parent, "TOPLEFT", T.PAD, y)
    y = y - 28

    local rowPool = {}
    local listAnchorY = y

    local function RebuildRows()
        for _, r in ipairs(rowPool) do r:Hide() end
        rowPool = {}
        local ry = listAnchorY
        for i, entry in ipairs(db[key]) do
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(CONTENT_W, 26)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", T.PAD, ry - (i-1)*28)
            Bg(row, T.bgRow[1], T.bgRow[2], T.bgRow[3], 0.6)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18); icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(C_Spell.GetSpellTexture(entry.spellID))
            local name = Label(row, entry.label, "GameFontNormal")
            name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            
            -- Delete Button (X)
            local delBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            delBtn:SetSize(24, 24)
            delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            delBtn:SetScript("OnClick", function()
                table.remove(db[key], i)
                Config.Refresh()
            end)

            local sid = Label(row, tostring(entry.spellID), "GameFontNormal",
                T.textDim[1], T.textDim[2], T.textDim[3])
            sid:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
            rowPool[i] = row
        end
    end
    RebuildRows()
    spellRebuildFns[key] = RebuildRows

    local totalH = 28 + (#db[key] > 0 and #db[key]*28 or 0) + 8
    return totalH
end

-- [ FPS / PERFORMANCE CVARS ] -------------------------------------------------
local PERFORMANCE_CVARS = {
    -- Graphics Tab
    ["vsync"]                            = "0",
    ["LowLatencyMode"]                   = "3",
    ["MSAAQuality"]                      = "0",
    ["ffxAntiAliasingMode"]              = "0",
    ["alphaTestMSAA"]                    = "1",
    ["cameraFov"]                        = "90",
    -- Graphics Quality
    ["graphicsQuality"]                  = "9",
    ["graphicsShadowQuality"]            = "0",
    ["graphicsLiquidDetail"]             = "1",
    ["graphicsParticleDensity"]          = "5",
    ["graphicsSSAO"]                     = "0",
    ["graphicsDepthEffects"]             = "0",
    ["graphicsComputeEffects"]           = "0",
    ["graphicsOutlineMode"]              = "1",
    ["OutlineEngineMode"]                = "1",
    ["graphicsTextureResolution"]        = "2",
    ["graphicsSpellDensity"]             = "0",
    ["spellClutter"]                     = "1",
    ["spellVisualDensityFilterSetting"]  = "1",
    ["graphicsProjectedTextures"]        = "1",
    ["projectedTextures"]                = "1",
    ["graphicsViewDistance"]             = "3",
    ["graphicsEnvironmentDetail"]        = "0",
    ["graphicsGroundClutter"]            = "0",
    -- Advanced Tab
    ["gxTripleBuffer"]                   = "0",
    ["textureFilteringMode"]             = "5",
    ["graphicsRayTracedShadows"]         = "0",
    ["rtShadowQuality"]                  = "0",
    ["ResampleQuality"]                  = "4",
    ["ffxSuperResolution"]               = "1",
    ["VRSMode"]                          = "0",
    ["GxApi"]                            = "D3D12",
    ["physicsLevel"]                     = "0",
    ["maxFPS"]                           = "144",
    ["maxFPSBk"]                         = "60",
    ["targetFPS"]                        = "61",
    ["useTargetFPS"]                     = "0",
    ["ResampleSharpness"]                = "0.2",
    ["Contrast"]                         = "75",
    ["Brightness"]                       = "50",
    ["Gamma"]                            = "1",
    -- Additional Optimisations
    ["particulatesEnabled"]              = "0",
    ["clusteredShading"]                 = "0",
    ["volumeFogLevel"]                   = "0",
    ["reflectionMode"]                   = "0",
    ["ffxGlow"]                          = "0",
    ["farclip"]                          = "5000",
    ["horizonStart"]                     = "1000",
    ["horizonClip"]                      = "5000",
    ["lodObjectCullSize"]                = "35",
    ["lodObjectFadeScale"]               = "50",
    ["lodObjectMinSize"]                 = "0",
    ["doodadLodScale"]                   = "50",
    ["entityLodDist"]                    = "7",
    ["terrainLodDist"]                   = "350",
    ["TerrainLodDiv"]                    = "512",
    ["waterDetail"]                      = "1",
    ["rippleDetail"]                     = "0",
    ["weatherDensity"]                   = "3",
    ["entityShadowFadeScale"]            = "15",
    ["groundEffectDist"]                 = "40",
    ["ResampleAlwaysSharpen"]            = "1",
    -- Special Hacks
    ["cameraDistanceMaxZoomFactor"]      = "2.6",
    ["CameraReduceUnexpectedMovement"]   = "1",
}

local function BackupFPSSettings(db)
    local backup = {}
    for cvar in pairs(PERFORMANCE_CVARS) do
        local ok, val = pcall(C_CVar.GetCVar, cvar)
        if ok and val then backup[cvar] = val end
    end
    db.fpsBackup = backup
end

local function RestoreFPSSettings(db)
    if not db.fpsBackup then return false end
    local ok_n, fail_n = 0, 0
    for cvar, val in pairs(db.fpsBackup) do
        if pcall(C_CVar.SetCVar, cvar, tostring(val)) then ok_n = ok_n + 1
        else fail_n = fail_n + 1 end
    end
    db.fpsBackup = nil
    print("|cff2dc9b8yaqol:|r Restored " .. ok_n .. " settings.")
    if fail_n > 0 then
        print("|cffff6b6byaqol:|r " .. fail_n .. " settings could not be restored.")
    end
    return true
end

local function ApplyFPSSettings(db)
    BackupFPSSettings(db)
    local ok_n, fail_n = 0, 0
    for cvar, val in pairs(PERFORMANCE_CVARS) do
        if pcall(C_CVar.SetCVar, cvar, val) then ok_n = ok_n + 1
        else fail_n = fail_n + 1 end
    end
    print("|cff2dc9b8yaqol:|r Applied " .. ok_n .. " performance settings. Use 'Restore' to undo.")
    if fail_n > 0 then
        print("|cffff6b6byaqol:|r " .. fail_n .. " settings could not be applied (may need restart).")
    end
end

-- [ TAB CONTENT BUILDERS ] ----------------------------------------------------
local tabRebuildFns = {}
local BuildSpells, BuildClassBuffs

local function BuildGeneral(content, db, addon)
    local y = -T.PAD
    local _, dh
    
    local h0 = Label(content, "GENERAL", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h0:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10
    _, dh = MakeSlider(content, "Options Window Scale", 0.5, 2.0, 0.05,
        function() return db.configScale or 1.0 end,
        function(v) 
            db.configScale = v
            if yaqolConfigPanel then yaqolConfigPanel:SetScale(v) end
        end, y,
        function(v) return string.format("%.2f", v) end)
    y = y - dh - 14

    local h1 = Label(content, "MINIMAP BUTTON", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10
    _, dh = MakeToggle(content, "Hide Minimap Button",
        function() return db.minimap.hide end,
        function(v) db.minimap.hide = v; ns.MinimapButton.Refresh(addon) end, y)
    y = y - dh - 14

    -- ── PERFORMANCE ───────────────────────────────────────────────────────
    local hPerf = Label(content, "PERFORMANCE", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    hPerf:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    local descPerf = Label(content,
        "Applies a preset of 58 graphics CVars tuned for competitive play: "
        .."disables or minimises projected textures, environmental detail, ground clutter, "
        .."shadows, and spell density — then uncaps the frame rate to 144 FPS. "
        .."These are the settings most M+ and raiding players run manually. "
        .."Your current values are snapshot automatically before applying, "
        .."so you can Restore at any time to get everything back exactly as it was.",
        "GameFontNormalSmall", T.textDim[1], T.textDim[2], T.textDim[3])
    descPerf:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    descPerf:SetWidth(T.PANEL_W - T.PAD*2 - 16)
    descPerf:SetJustifyH("LEFT")
    y = y - 62

    local restoreBtn
    local applyBtn = MakeButton(content, "Apply FPS Settings", function()
        ApplyFPSSettings(db)
        restoreBtn:Enable()
    end, 150, 24)
    applyBtn:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)

    restoreBtn = MakeButton(content, "Restore Previous", function()
        if RestoreFPSSettings(db) then
            restoreBtn:Disable()
        end
    end, 150, 24)
    restoreBtn:SetPoint("LEFT", applyBtn, "RIGHT", 10, 0)
    restoreBtn:SetPoint("TOP", applyBtn, "TOP", 0, 0)
    if not db.fpsBackup then restoreBtn:Disable() end

    -- re-sync restore button when tab is shown
    tabRebuildFns["general_fps"] = function()
        if db.fpsBackup then restoreBtn:Enable() else restoreBtn:Disable() end
    end

    return y - 30
end

local function BuildTeleport(content, db, addon)
    local y = -T.PAD
    local _, dh
    local h1 = Label(content, "TELEPORT PANEL", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10
    _, dh = MakeToggle(content, "Enable Teleport Panel",
        function() return db.teleport.enabled end,
        function(v) db.teleport.enabled = v; ns.Teleport.Refresh(addon) end, y)
    y = y - dh - 2
    _, dh = MakeToggle(content, "Show Unlearned Teleports (greyed out)",
        function() return db.teleport.showUnknown end,
        function(v) db.teleport.showUnknown = v; ns.Teleport.Refresh(addon) end, y)
    y = y - dh - 10
    _, dh = MakeSlider(content, "Show when group size \226\137\165", 1, 5, 1,
        function() return db.teleport.minGroupSize or 2 end,
        function(v) db.teleport.minGroupSize = v; ns.Teleport.Refresh(addon) end, y,
        function(v) return v == 1 and "Always (solo)" or v .. "+ members" end)
    y = y - dh - 10
    _, dh = MakeSlider(content, "Panel Scale", 0.5, 2.0, 0.05,
        function() return db.teleport.scale end,
        function(v) db.teleport.scale = v; ns.Teleport.Refresh(addon) end, y,
        function(v) return string.format("%.2f", v) end)
    y = y - dh - 10
    local resetBtn = MakeButton(content, "Reset Position", function()
        db.teleport.point="CENTER"; db.teleport.relPoint="CENTER"
        db.teleport.x=0; db.teleport.y=0; ns.Teleport.Refresh(addon)
    end, 120, 22)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    return y - 30
end

local function BuildSpells(content, db, startY)
    local y = startY or -T.PAD
    local cats = {
        { key="flasks",       label="Flasks / Phials"        },
        { key="food",         label="Food"          },
        { key="augmentRunes", label="Augment Runes" },
        { key="weaponBuffs",  label="Weapon Buffs"  },
        { key="custom",       label="Custom"        },
    }
    for _, cat in ipairs(cats) do
        local h = Label(content, cat.label:upper(), "GameFontNormalSmall",
            T.textHeader[1], T.textHeader[2], T.textHeader[3])
        h:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
        Divider(content, y); y = y - 10
        local totalH = MakeSpellList(content, db, cat.key, y)
        y = y - totalH - 10
    end
    return y
end

local function BuildClassBuffs(content, db, addon, startY)
    local y = startY or -T.PAD
    local r = db.reminder
    local _, dh

    -- ── SELF / WEAPON BUFFS ───────────────────────────────────────────────
    local h1 = Label(content, "SELF & WEAPON BUFFS", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Enable Self/Weapon Buff Reminders",
        function() return r.enableClassBuffs ~= false end,
        function(v) r.enableClassBuffs = v; ns.AuraReminder.Refresh(addon) end, y)
    y = y - dh - 8

    local defs = ns.AuraList.GetClassBuffDefs()
    if defs and #defs > 0 then
        for _, def in ipairs(defs) do
            local cfgKey = def.castSpell and tostring(def.castSpell) or def.label
            local reqTag = def.required and " |cffff4444[req]|r" or ""
            _, dh = MakeToggle(content,
                "  " .. def.label .. reqTag,
                function() return r.classBuffs[cfgKey] ~= false end,
                function(v)
                    r.classBuffs[cfgKey] = v and nil or false
                    ns.AuraReminder.Refresh(addon)
                end, y)
            y = y - dh - 6
        end
    else
        local none = Label(content, "  (none for your class)", "GameFontNormalSmall", 0.5, 0.5, 0.5)
        none:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    end

    y = y - 10

    -- ── PARTY / RAID BUFFS ────────────────────────────────────────────────
    local h2 = Label(content, "PARTY & RAID BUFFS", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h2:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    local noteP = Label(content,
        "Reminds you to cast group-wide buffs when anyone in your party/raid is missing them.",
        "GameFontNormalSmall", 0.7, 0.7, 0.7)
    noteP:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    noteP:SetWidth(T.PANEL_W - T.PAD*2 - 16)
    noteP:SetJustifyH("LEFT")
    y = y - 30

    _, dh = MakeToggle(content, "Enable Party/Raid Buff Reminders",
        function() return r.enablePartyBuffs ~= false end,
        function(v) r.enablePartyBuffs = v; ns.AuraReminder.Refresh(addon) end, y)
    y = y - dh - 8

    local pdefs = ns.AuraList.GetPartyBuffDefs()
    if pdefs and #pdefs > 0 then
        for _, def in ipairs(pdefs) do
            _, dh = MakeToggle(content,
                "  " .. def.label,
                function() return r.partyBuffs[def.key] ~= false end,
                function(v)
                    r.partyBuffs[def.key] = v and nil or false
                    ns.AuraReminder.Refresh(addon)
                end, y)
            y = y - dh - 6
        end
    else
        local none2 = Label(content, "  (none for your class)", "GameFontNormalSmall", 0.5, 0.5, 0.5)
        none2:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    end
    return y - 10
end
local function BuildReminder(content, db, addon)
    local y = -T.PAD
    local _, dh
    local h1 = Label(content, "BEHAVIOUR", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10
    local toggles = {
        { "Enable Buff Reminders",                 function() return db.reminder.enabled end,            function(v) db.reminder.enabled = v; ns.AuraReminder.Refresh(addon) end },
        { "Re-trigger if Buff Falls Off Mid-Run",  function() return db.reminder.remindOnBuffLost end,   function(v) db.reminder.remindOnBuffLost = v end },
        { "Show Tooltip on Hover",                 function()
            if db.reminder.showTooltip == nil then db.reminder.showTooltip = true end
            return db.reminder.showTooltip
        end, function(v) db.reminder.showTooltip = v end },
    }
    for _, t in ipairs(toggles) do
        _, dh = MakeToggle(content, t[1], t[2], t[3], y); y = y - dh - 2
    end
    y = y - 6
    _, dh = MakeSlider(content, "Panel Scale", 0.5, 2.0, 0.05,
        function() return db.reminder.scale or 1.0 end,
        function(v) db.reminder.scale = v; ns.AuraReminder.Refresh(addon) end, y,
        function(v) return string.format("%.2f", v) end)
    y = y - dh - 8
    _, dh = MakeSlider(content, "Buff Expiry Threshold (seconds)", 0, 300, 10,
        function() return db.reminder.buffMinRemaining or 60 end,
        function(v) db.reminder.buffMinRemaining = v end, y,
        function(v) return v == 0 and "Off" or string.format("%ds", v) end)
    y = y - dh - 8
    local resetBtn = MakeButton(content, "Reset Position", function()
        db.reminder.point="TOP"; db.reminder.relPoint="TOP"
        db.reminder.x=0; db.reminder.y=-150; ns.AuraReminder.Refresh(addon)
    end, 120, 22)
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    y = y - 40
    _, dh = MakeToggle(content, "Warn when main-hand has no weapon oil / temp enchant",
        function() return db.reminder.weaponOil end,
        function(v) db.reminder.weaponOil = v; ns.AuraReminder.Refresh(addon) end, y)
    y = y - dh - 10
    y = BuildSpells(content, db.reminder, y - 10)
    y = BuildClassBuffs(content, db, addon, y - 10)
    return y - 20
end

local function BuildQOL(content, db, addon)
    local q   = db.qol
    local y   = -T.PAD
    local _, dh

    -- ── QUESTS & DIALOGUE ─────────────────────────────────────────────────
    local h1 = Label(content, "QUESTS & DIALOGUE", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Auto-accept / complete / collect quests",
        function() return q.autoQuest end,
        function(v) q.autoQuest = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 2

    local noteQ = Label(content,
        "Single-reward quests are collected automatically. Multi-reward quests pause for your choice.",
        "GameFontNormalSmall", T.textDim[1], T.textDim[2], T.textDim[3])
    noteQ:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD + 44, y)
    noteQ:SetWidth(T.PANEL_W - T.PAD*2 - 48)
    noteQ:SetJustifyH("LEFT")
    y = y - 26

    _, dh = MakeToggle(content, "Auto-advance single-option gossip / quest dialogs",
        function() return q.autoGossip end,
        function(v) q.autoGossip = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 4

    -- Quest skip modifier row
    local qModLabel = Label(content, "  Hold to skip auto-quest:", "GameFontNormalSmall",
        T.textDim[1], T.textDim[2], T.textDim[3])
    qModLabel:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    local QMODS = { "NONE", "ALT", "SHIFT", "CTRL" }
    local qModBtns = {}
    local qBtnX = T.PAD + qModLabel:GetStringWidth() + 14
    for _, mod in ipairs(QMODS) do
        local mb = CreateFrame("Button", nil, content)
        mb:SetSize(52, 18)
        mb:SetPoint("LEFT", content, "TOPLEFT", qBtnX, y + 9)
        qBtnX = qBtnX + 56
        local mbBg = mb:CreateTexture(nil, "BACKGROUND"); mbBg:SetAllPoints()
        local mbLbl = mb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mbLbl:SetPoint("CENTER"); mbLbl:SetText(mod)
        qModBtns[mod] = { btn = mb, bg = mbBg, lbl = mbLbl }
        local function RefreshQMod()
            local cur = q.questSkipModifier or "SHIFT"
            if (mod == "NONE" and (cur == "NONE" or cur == nil)) or cur == mod then
                mbBg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
                mbLbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
            else
                mbBg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 1)
                mbLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
            end
        end
        RefreshQMod()
        mb:SetScript("OnClick", function()
            q.questSkipModifier = mod
            for _, v in pairs(qModBtns) do
                local cur = q.questSkipModifier or "SHIFT"
                local selected = (v.lbl:GetText() == cur) or (cur == "NONE" and v.lbl:GetText() == "NONE")
                if selected then
                    v.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
                    v.lbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
                else
                    v.bg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 1)
                    v.lbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
                end
            end
        end)
    end
    y = y - 30

    -- Auto-skip cinematics toggle
    _, dh = MakeToggle(content, "Auto-skip cinematics and cutscenes",
        function() return q.autoSkipCinematic end,
        function(v) q.autoSkipCinematic = v end, y)
    y = y - dh - 14

    -- ── SOCIAL / GROUP ────────────────────────────────────────────────────
    local h2 = Label(content, "SOCIAL & GROUP", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h2:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Auto-accept summoning stone (5 second delay)",
        function() return q.autoSummon end,
        function(v) q.autoSummon = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 2

    _, dh = MakeToggle(content, "Auto-decline duel requests",
        function() return q.declineDuel end,
        function(v) q.declineDuel = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 2

    _, dh = MakeToggle(content, "Auto-decline guild invite requests",
        function() return q.declineGuild end,
        function(v) q.declineGuild = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 14

    -- ── DEATH ─────────────────────────────────────────────────────────────
    local h3 = Label(content, "DEATH", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h3:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Auto-accept resurrection offers",
        function() return q.autoRez end,
        function(v) q.autoRez = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 2

    _, dh = MakeToggle(content, "  Allow auto-rez while the caster is in combat",
        function() return q.autoRezInCombat end,
        function(v) q.autoRezInCombat = v end, y)
    y = y - dh - 10

    _, dh = MakeToggle(content, "Hold modifier key to release spirit",
        function() return q.holdToRelease end,
        function(v) q.holdToRelease = v end, y)
    y = y - dh - 2

    local noteR = Label(content,
        "Prevents accidental spirit release mid-progression.",
        "GameFontNormalSmall", T.textDim[1], T.textDim[2], T.textDim[3])
    noteR:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD + 44, y)
    noteR:SetWidth(T.PANEL_W - T.PAD*2 - 48)
    noteR:SetJustifyH("LEFT")
    y = y - 20

    -- Modifier selector dropdown
    local modLabel = Label(content, "  Required modifier:", "GameFontNormalSmall",
        T.textDim[1], T.textDim[2], T.textDim[3])
    modLabel:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD + 44, y)
    local MODS = { "ANY", "ALT", "SHIFT", "CTRL" }
    local modBtns = {}
    local btnX = T.PAD + 44 + modLabel:GetStringWidth() + 10
    for _, mod in ipairs(MODS) do
        local mb = CreateFrame("Button", nil, content)
        mb:SetSize(52, 18)
        mb:SetPoint("LEFT", content, "TOPLEFT", btnX, y + 9)
        btnX = btnX + 56
        local mbBg = mb:CreateTexture(nil, "BACKGROUND"); mbBg:SetAllPoints()
        local mbLbl = mb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mbLbl:SetPoint("CENTER"); mbLbl:SetText(mod)
        modBtns[mod] = { btn = mb, bg = mbBg, lbl = mbLbl }
        local function RefreshMod()
            local cur = q.holdModifier or "ANY"
            if cur == mod then
                mbBg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
                mbLbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
            else
                mbBg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 1)
                mbLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
            end
        end
        RefreshMod()
        mb:SetScript("OnClick", function()
            q.holdModifier = mod
            for _, v in pairs(modBtns) do
                local cur = q.holdModifier or "ANY"
                if cur == v.lbl:GetText() then
                    v.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
                    v.lbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)
                else
                    v.bg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 1)
                    v.lbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
                end
            end
        end)
    end
    y = y - 28

    y = y - 8

    -- ── LOOTING ───────────────────────────────────────────────────────────
    local h4a = Label(content, "LOOTING", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h4a:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Faster looting (auto-loot without right-click)",
        function() return q.fasterLooting end,
        function(v) q.fasterLooting = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 14

    -- ── VENDOR ────────────────────────────────────────────────────────────
    local h4 = Label(content, "VENDOR", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h4:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Sell grey (junk) items automatically",
        function() return q.sellJunk end,
        function(v) q.sellJunk = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 14

    _, dh = MakeToggle(content, "Repair all gear automatically",
        function() return q.autoRepair end,
        function(v) q.autoRepair = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 2

    _, dh = MakeToggle(content, "  Prefer guild bank funds for repairs",
        function() return q.repairGuild end,
        function(v) q.repairGuild = v end, y)
    y = y - dh - 14

    -- ── GEAR ──────────────────────────────────────────────────────────────
    local h5 = Label(content, "GEAR", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h5:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Warn when gear durability drops below threshold",
        function() return q.durabilityWarn end,
        function(v) q.durabilityWarn = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 4

    _, dh = MakeSlider(content, "  Warning threshold", 5, 50, 5,
        function() return q.durabilityThresh or 20 end,
        function(v) q.durabilityThresh = v end, y,
        function(v) return v .. "%%" end)
    y = y - dh - 14

    -- ── MYTHIC PLUS ───────────────────────────────────────────────────────
    local h6 = Label(content, "MYTHIC PLUS", "GameFontNormalSmall",
        T.textHeader[1], T.textHeader[2], T.textHeader[3])
    h6:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y); y = y - 22
    Divider(content, y); y = y - 10

    _, dh = MakeToggle(content, "Show M+ affix popup on login / reload",
        function() return q.affixReminder end,
        function(v) q.affixReminder = v; ns.QOL.Refresh(addon) end, y)
    y = y - dh - 4

    local showBtn = MakeButton(content, "Preview Affixes", function()
        ns.QOL.ShowAffixes()
    end, 130, 22)
    showBtn:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, y)
    y = y - 34

    return y - 20
end

-- [ MAIN PANEL ] --------------------------------------------------------------
local panel
local TABS = {
    { key="general",    label="General"       },
    { key="teleport",   label="Teleport"      },
    { key="reminder",   label="Buff Reminder" },
    { key="qol",        label="QOL"           },
}

local function BuildPanel(addon)
    local db = addon.db.profile
    local W, H = T.PANEL_W, T.PANEL_H

    local f = CreateFrame("Frame", "yaqolConfigPanel", UIParent)
    f:SetSize(W, H); f:SetPoint("CENTER")
    f:SetScale(db.configScale or 1.0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f:Hide()
    Bg(f, T.bg[1], T.bg[2], T.bg[3], T.bg[4])

    -- left teal stripe
    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetSize(3, H); stripe:SetPoint("TOPLEFT")
    stripe:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

    -- header
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(W, T.HEADER_H); header:SetPoint("TOPLEFT")
    Bg(header, T.accent[1]*0.10, T.accent[2]*0.10, T.accent[3]*0.10, 1)
    -- single bottom border on header
    local headerLine = header:CreateTexture(nil, "OVERLAY")
    headerLine:SetHeight(1)
    headerLine:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT")
    headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
    headerLine:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.7)

    local titleLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLbl:SetPoint("LEFT", header, "LEFT", 14, 0)
    titleLbl:SetText("|cff2dc9b8ya|rqol")
    titleLbl:SetTextColor(T.text[1], T.text[2], T.text[3], 1)

    local verLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verLbl:SetPoint("LEFT", titleLbl, "RIGHT", 8, -1)
    verLbl:SetText("v" .. (C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0"))
    verLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- "What's New" changelog button — sits left of the close button
    local changelogBtn = CreateFrame("Button", nil, header)
    changelogBtn:SetSize(90, 22)
    changelogBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    local clBg = changelogBtn:CreateTexture(nil, "BACKGROUND")
    clBg:SetAllPoints()
    clBg:SetColorTexture(T.accent[1]*0.15, T.accent[2]*0.15, T.accent[3]*0.15, 1)
    local clHl = changelogBtn:CreateTexture(nil, "HIGHLIGHT")
    clHl:SetAllPoints()
    clHl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
    local clLbl = changelogBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clLbl:SetPoint("CENTER")
    clLbl:SetText("|cff2dc9b8What's New|r")
    changelogBtn:SetScript("OnEnter", function()
        clBg:SetColorTexture(T.accent[1]*0.30, T.accent[2]*0.30, T.accent[3]*0.30, 1)
        GameTooltip:SetOwner(changelogBtn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Changelog", 1, 1, 1)
        GameTooltip:AddLine("See what changed in each version.", 0.68, 0.72, 0.74, true)
        GameTooltip:Show()
    end)
    changelogBtn:SetScript("OnLeave", function()
        clBg:SetColorTexture(T.accent[1]*0.15, T.accent[2]*0.15, T.accent[3]*0.15, 1)
        GameTooltip:Hide()
    end)
    changelogBtn:SetScript("OnClick", function() ns.ChangelogUI.Toggle() end)

    -- Layout mode button — sits left of the changelog button
    local layoutBtn = CreateFrame("Button", nil, header)
    layoutBtn:SetSize(100, 22)
    layoutBtn:SetPoint("RIGHT", changelogBtn, "LEFT", -6, 0)
    local layoutBg = layoutBtn:CreateTexture(nil, "BACKGROUND")
    layoutBg:SetAllPoints()
    layoutBg:SetColorTexture(T.accent[1]*0.15, T.accent[2]*0.15, T.accent[3]*0.15, 1)
    -- Icon: move/arrange cursor
    local layoutIcon = layoutBtn:CreateTexture(nil, "ARTWORK")
    layoutIcon:SetSize(14, 14)
    layoutIcon:SetPoint("LEFT", layoutBtn, "LEFT", 6, 0)
    layoutIcon:SetTexture("Interface\\Cursor\\Move")
    local layoutLbl = layoutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layoutLbl:SetPoint("LEFT", layoutIcon, "RIGHT", 4, 0)
    layoutLbl:SetText("|cff2dc9b8Arrange|r")
    layoutBtn:SetScript("OnEnter", function()
        layoutBg:SetColorTexture(T.accent[1]*0.30, T.accent[2]*0.30, T.accent[3]*0.30, 1)
        GameTooltip:SetOwner(layoutBtn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Arrange Frames", 1, 1, 1)
        GameTooltip:AddLine("Show all movable frames and drag\nthem into position.", 0.68, 0.72, 0.74, true)
        GameTooltip:Show()
    end)
    layoutBtn:SetScript("OnLeave", function()
        layoutBg:SetColorTexture(T.accent[1]*0.15, T.accent[2]*0.15, T.accent[3]*0.15, 1)
        GameTooltip:Hide()
    end)
    layoutBtn:SetScript("OnClick", function() ns.LayoutMode.Enter() end)

    -- tab bar
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetSize(W, T.TAB_H); tabBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -T.HEADER_H)
    Bg(tabBar, T.bg[1]*0.80, T.bg[2]*0.80, T.bg[3]*0.80, 1)
    local tabBotLine = f:CreateTexture(nil, "BORDER")
    tabBotLine:SetSize(W, 1); tabBotLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(T.HEADER_H + T.TAB_H))
    tabBotLine:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- sliding tab indicator
    local indicator = tabBar:CreateTexture(nil, "OVERLAY")
    indicator:SetSize(1, 2); indicator:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT")
    indicator:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

    -- scrollable content
    local CONTENT_Y = T.HEADER_H + T.TAB_H + 1
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetSize(W - 16, H - CONTENT_Y)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -CONTENT_Y)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(W - 16, 1400)
    scrollFrame:SetScrollChild(content)

    -- scrollbar
    local scrollBar = CreateFrame("Slider", nil, f)
    scrollBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -CONTENT_Y - 4)
    scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    scrollBar:SetWidth(8)
    scrollBar:SetMinMaxValues(0, 1400 - scrollFrame:GetHeight())
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    
    local sbBg = scrollBar:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], 0.3)
    
    local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 40)
    thumb:SetColorTexture(T.accentDim[1], T.accentDim[2], T.accentDim[3], 1)
    scrollBar:SetThumbTexture(thumb)

    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = scrollBar:GetValue()
        local maxVal = select(2, scrollBar:GetMinMaxValues())
        scrollBar:SetValue(math.max(0, math.min(cur - delta * 40, maxVal)))
    end)

    -- build tab frames
    local tabFrames, tabBtns = {}, {}
    local tabHeights = {}
    local totalTabW = W / #TABS

    for i, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetSize(totalTabW, T.TAB_H)
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i-1)*totalTabW, 0)
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.08)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER"); lbl:SetText(tab.label)
        btn.lbl = lbl; btn.tabW = totalTabW; btn.tabX = (i-1)*totalTabW
        tabBtns[tab.key] = btn

        local tf = CreateFrame("Frame", nil, content)
        tf:SetSize(W - 3, 1400); tf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0); tf:Hide()
        tabFrames[tab.key] = tf

        local finalY = 0
        if tab.key == "general"    then finalY = BuildGeneral(tf, db, addon)          end
        if tab.key == "teleport"   then finalY = BuildTeleport(tf, db, addon)         end
        if tab.key == "reminder"   then finalY = BuildReminder(tf, db, addon)         end
        if tab.key == "qol"        then finalY = BuildQOL(tf, db, addon)              end
        tabHeights[tab.key] = math.abs(finalY)
    end

    local function SetTab(key)
        for _, tf in pairs(tabFrames) do tf:Hide() end
        if tabFrames[key] then 
            tabFrames[key]:Show()
            
            -- Update scroll max based on tab height
            local maxScroll = math.max(0, tabHeights[key] - scrollFrame:GetHeight())
            scrollBar:SetMinMaxValues(0, maxScroll)
            if maxScroll > 0 then
                scrollBar:Show()
            else
                scrollBar:Hide()
            end
            scrollBar:SetValue(0) 
        end
        for k, btn in pairs(tabBtns) do
            if k == key then
                btn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
                indicator:SetSize(btn.tabW, 2)
                indicator:ClearAllPoints()
                indicator:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", btn.tabX, 0)
            else
                btn.lbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
            end
        end
        if tabRebuildFns[key] then tabRebuildFns[key]() end
        if tabRebuildFns[key.."_fps"] then tabRebuildFns[key.."_fps"]() end
    end

    for _, tab in ipairs(TABS) do
        tabBtns[tab.key]:SetScript("OnClick", function() SetTab(tab.key) end)
    end
    SetTab("general")
    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function Config.Build(addon)
    Config._addon = addon  -- lazy: panel created on first Toggle
end

function Config.Toggle()
    if not panel then panel = BuildPanel(Config._addon) end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

function Config.Refresh()
    for _, fn in pairs(spellRebuildFns) do fn() end
end
