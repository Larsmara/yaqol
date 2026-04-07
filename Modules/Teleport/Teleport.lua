local ADDON_NAME, ns = ...
ns.Teleport = {}
local Teleport = ns.Teleport

-- [ CONSTANTS ] ---------------------------------------------------------------
local DUNGEONS = {
    { name = "Academy",                  spellID = 393273  },
    { name = "Terrace",                  spellID = 1254572 },
    { name = "Nexuspoint",               spellID = 1254563 },
    { name = "Spire",                    spellID = 1254400 },
    { name = "Skyreach",                 spellID = 159898  },
    { name = "Caverns",                  spellID = 1254559 },
    { name = "Pit of Saron",             spellID = 1254555 },
    { name = "Triumvirate",              spellID = 1254551 },
}

-- challengeMapID → DUNGEONS index
-- Hardcoded to match the DUNGEONS table order above; same IDs used by BigWigs.
-- DUNGEONS order: 1=Academy, 2=Terrace, 3=Nexuspoint, 4=Spire,
--                 5=Skyreach, 6=Caverns, 7=Pit of Saron, 8=Triumvirate
local challengeMapToDungeon = {
    [402] = 1,  -- Algeth'ar Academy
    [558] = 2,  -- Magister's Terrace  ("Terrace")
    [559] = 3,  -- Nexus-Point Xenas
    [557] = 4,  -- Windrunner's Spire
    [161] = 5,  -- Skyreach
    [560] = 6,  -- Maisara Caverns
    [556] = 7,  -- Pit of Saron
    [583] = 8,  -- Seat of the Triumvirate
}

local BTN_W, BTN_H = 180, 22
local BTN_PAD = 1
local PANEL_PAD = 8 -- Increased for a slightly larger drag target
local HEADER_H = 16  -- thin strip at top for the close button
local FRAME_W = BTN_W + PANEL_PAD * 2

local DISABLED_ALPHA = 0.3
local LEARNED_COLOR = { 0.9, 0.9, 0.9 }
local UNKNOWN_COLOR = { 0.5, 0.5, 0.5 }

-- [ KEYSTONE DATA VIA LIBKEYSTONE ] -----------------------------------------
-- LibKeystone is compatible with BigWigs, DBM, and any addon using the same
-- library. It broadcasts over "LibKS" prefix automatically.
-- Callback args: keyLevel, keyMapID, playerRating, playerName, channel

local LibKeystone = LibStub and LibStub("LibKeystone", true)
local partyKeyCache = {}  -- ["PlayerName"] = { mapID=n, level=n }
local libKeystoneTable = {}  -- unique table used as our identifier with LibKeystone

local function OnLibKeystoneData(keyLevel, keyMapID, playerRating, playerName, channel)
    if channel ~= "PARTY" then return end  -- ignore GUILD broadcasts
    if not playerName or playerName == "" then return end  -- lib captured pName before player logged in
    -- Normalize: strip realm suffix so "Name-Realm" and "Name" are the same key
    local shortName = playerName:match("^([^%-]+)") or playerName
    if keyLevel and keyLevel > 0 and keyMapID and keyMapID > 0 then
        partyKeyCache[shortName] = { mapID = keyMapID, level = keyLevel }
    else
        partyKeyCache[shortName] = nil
    end
    if buttons then RefreshButtons() end
end

local function RequestPartyKeystones()
    if LibKeystone then
        LibKeystone.Request("PARTY")
    end
end

-- Build the result table that RefreshButtons consumes.
-- Returns: [dungeonIdx] = { {r,g,b,level,name,unit}, ... }
local function CollectPartyKeystones()
    local result = {}

    local function AddEntry(mapID, level, unit, nameKey)
        if not mapID or mapID == 0 or not level or level == 0 then return end
        local dungeonIdx = challengeMapToDungeon[mapID]
        if not dungeonIdx then return end
        local r, g, b = 1, 0.82, 0.1  -- fallback gold (used when unit token is unknown)
        if unit then
            local _, classFile = UnitClass(unit)
            if classFile and C_ClassColor and C_ClassColor.GetClassColor then
                local c = C_ClassColor.GetClassColor(classFile)
                if c then r, g, b = c.r, c.g, c.b end
            end
        end
        if not result[dungeonIdx] then result[dungeonIdx] = {} end
        result[dungeonIdx][#result[dungeonIdx] + 1] = { r=r, g=g, b=b, level=level, name=nameKey, unit=unit }
    end

    -- All party data (including self) comes through LibKeystone callback.
    -- LibKeystone.Request() fires our callback with the player's own key too.
    -- We also add own key directly in case not in a group / lib not loaded.
    if C_MythicPlus then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local myName = UnitName("player") or "player"
        AddEntry(mapID, level, "player", myName)
    end

    -- Party members from LibKeystone cache
    local myName = (UnitName("player") or ""):lower()
    for playerName, data in pairs(partyKeyCache) do
        -- playerName is already normalized (no realm suffix) by OnLibKeystoneData
        if playerName:lower() == myName then
            -- own key already added above via C_MythicPlus
        else
            -- Resolve unit token for class colour; search raid OR party tokens
            local unit = nil
            local lowerName = playerName:lower()
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local u = "raid" .. i
                    if UnitExists(u) and (UnitName(u) or ""):lower() == lowerName then
                        unit = u; break
                    end
                end
            else
                for i = 1, GetNumSubgroupMembers() do
                    local u = "party" .. i
                    if UnitExists(u) and (UnitName(u) or ""):lower() == lowerName then
                        unit = u; break
                    end
                end
            end
            -- unit may still be nil if the player hasn't fully loaded; AddEntry
            -- handles nil gracefully by falling back to the gold colour.
            AddEntry(data.mapID, data.level, unit, playerName)
        end
    end

    return result
end

-- [ FRAME ] -------------------------------------------------------------------
local panel, buttons
local userClosed = false  -- set when user clicks X; cleared on group roster change

local function SavePos()
    local db = ns.Addon:Profile().teleport
    db.point, _, db.relPoint, db.x, db.y = panel:GetPoint()
end

local function ApplyPos()
    local db = ns.Addon:Profile().teleport
    panel:ClearAllPoints()
    panel:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function CheckVisibility()
    local db = ns.Addon:Profile().teleport
    if not panel then return end
    if not db.enabled then
        panel:Hide()
        return
    end

    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
        panel:Hide()
        return
    end

    local minSize = db.minGroupSize or 2
    local count = GetNumGroupMembers()  -- 0 when solo, includes player when in party
    -- GetNumGroupMembers returns 0 when solo (not in a group).
    -- When in a party it returns the total member count including the player.
    local effectiveCount = IsInGroup() and count or 1
    if effectiveCount >= minSize then
        if not userClosed then
            panel:Show()
        end
        -- Full group (5) = fully opaque so it demands attention
        local restingAlpha = (effectiveCount >= 5) and 1 or 0.8
        panel:SetAlpha(restingAlpha)
        -- Keep the OnLeave handler in sync with whatever the resting alpha should be
        panel.restingAlpha = restingAlpha
    else
        userClosed = false  -- group shrank below threshold — reset so it shows again when it grows
        panel:Hide()
    end
end

local function MakePanel()
    local totalH = (#DUNGEONS * (BTN_H + BTN_PAD)) + PANEL_PAD * 2 - BTN_PAD
    local f = CreateFrame("Frame", "yaqolTeleportPanel", UIParent)
    f:SetSize(FRAME_W, totalH)
    f:SetFrameStrata("MEDIUM")
    f.restingAlpha = 0.8
    
    -- Hidden background and header as requested
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -HEADER_H)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
    div:SetColorTexture(0, 0, 0, 0)

    -- Close button (-) sitting clearly atop the panel
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -PANEL_PAD, 2)
    
    local cBorder = closeBtn:CreateTexture(nil, "BACKGROUND")
    cBorder:SetAllPoints()
    cBorder:SetColorTexture(0, 0, 0, 1)

    local cBg = closeBtn:CreateTexture(nil, "BORDER")
    cBg:SetPoint("TOPLEFT", closeBtn, "TOPLEFT", 1, -1)
    cBg:SetPoint("BOTTOMRIGHT", closeBtn, "BOTTOMRIGHT", -1, 1)
    cBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeLbl:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeLbl:SetShadowColor(0, 0, 0, 1)
    closeLbl:SetShadowOffset(1, -1)
    closeLbl:SetText("-")  -- Crisp minus icon
    
    closeBtn:SetScript("OnEnter", function(self)
        f:SetAlpha(1)
        cBg:SetColorTexture(0.2, 0.2, 0.2, 1)
        closeLbl:SetTextColor(1, 1, 1, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        f:SetAlpha(f.restingAlpha)
        cBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        closeLbl:SetTextColor(0.8, 0.8, 0.8, 1)
    end)
    closeBtn:SetScript("OnClick", function()
        userClosed = true
        f:Hide()
    end)

    -- Refresh (⟳) button — re-requests keystones from party/raid members.
    -- Useful when joining a group whose members already broadcast before we loaded.
    local refreshBtn = CreateFrame("Button", nil, f)
    refreshBtn:SetSize(18, 18)
    refreshBtn:SetPoint("BOTTOMRIGHT", closeBtn, "BOTTOMLEFT", -2, 0)

    local rBorder = refreshBtn:CreateTexture(nil, "BACKGROUND")
    rBorder:SetAllPoints()
    rBorder:SetColorTexture(0, 0, 0, 1)

    local rBg = refreshBtn:CreateTexture(nil, "BORDER")
    rBg:SetPoint("TOPLEFT",     refreshBtn, "TOPLEFT",     1, -1)
    rBg:SetPoint("BOTTOMRIGHT", refreshBtn, "BOTTOMRIGHT", -1, 1)
    rBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local rIcon = refreshBtn:CreateTexture(nil, "OVERLAY")
    rIcon:SetPoint("CENTER", refreshBtn, "CENTER", 0, 0)
    rIcon:SetSize(12, 12)
    rIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    rIcon:SetVertexColor(0.8, 0.8, 0.8, 1)

    refreshBtn:SetScript("OnEnter", function()
        f:SetAlpha(1)
        rBg:SetColorTexture(0.2, 0.2, 0.2, 1)
        rIcon:SetVertexColor(0.18, 0.78, 0.72, 1)
        GameTooltip:SetOwner(refreshBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Refresh keystones", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Re-request keystone data from party members.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function()
        f:SetAlpha(f.restingAlpha)
        rBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        rIcon:SetVertexColor(0.8, 0.8, 0.8, 1)
        GameTooltip:Hide()
    end)
    refreshBtn:SetScript("OnClick", function()
        wipe(partyKeyCache)
        RequestPartyKeystones()
        -- LibKeystone throttles broadcasts at 3s; wait 4s for all members to respond
        C_Timer.After(4, RefreshButtons)
    end)

    f:SetAlpha(0.8)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    f:SetClampedToScreen(true)

    f:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    f:SetScript("OnLeave", function(self) self:SetAlpha(self.restingAlpha) end)

    return f
end

local function MakeButton(parent, dungeon, idx)
    local yOff = -(PANEL_PAD + (idx - 1) * (BTN_H + BTN_PAD))
    local btn = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PANEL_PAD, yOff)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- Use spell type with numeric spellID — same pattern as BigWigs teleport buttons
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", dungeon.spellID)

    -- 1px border using OVERLAY sublayer 7 (highest) so they render above
    -- InsecureActionButtonTemplate's own overlay textures.
    -- Thickness is set dynamically in RefreshButtons (1px default, 2px when key present).
    local function MakeEdge()
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    local edgeT = MakeEdge(); edgeT:SetPoint("TOPLEFT",btn,"TOPLEFT",0,0);      edgeT:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,0);    edgeT:SetHeight(1)
    local edgeB = MakeEdge(); edgeB:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",0,0); edgeB:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",0,0); edgeB:SetHeight(1)
    local edgeL = MakeEdge(); edgeL:SetPoint("TOPLEFT",btn,"TOPLEFT",0,0);      edgeL:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",0,0);  edgeL:SetWidth(1)
    local edgeR = MakeEdge(); edgeR:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,0);    edgeR:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",0,0); edgeR:SetWidth(1)
    btn.edgeT, btn.edgeB, btn.edgeL, btn.edgeR = edgeT, edgeB, edgeL, edgeR

    local bg = btn:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    btn.bg = bg

    -- Spell icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BTN_H - 2, BTN_H - 2)
    icon:SetPoint("LEFT", btn, "LEFT", 1, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetText(dungeon.name)
    btn.label = label

    -- Hover highlight + tooltip
    btn:SetScript("OnEnter", function(self)
        parent:SetAlpha(1)
        if self.learned then self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(dungeon.spellID)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        parent:SetAlpha(parent.restingAlpha)
        self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        GameTooltip:Hide()
    end)

    btn.spellID = dungeon.spellID
    return btn
end

-- [ REFRESH LOGIC ] -----------------------------------------------------------
local function RefreshButtons()
    if not buttons then return end
    local db = ns.Addon:Profile().teleport

    -- Collect all party keystones (includes player)
    local partyKeys = CollectPartyKeystones()

    local visibleCount = 0
    
    for i, btn in ipairs(buttons) do
        local learned = IsSpellKnown(btn.spellID)
        btn.learned = learned
        
        local spellInfo = C_Spell.GetSpellInfo(btn.spellID)
        if spellInfo and spellInfo.iconID then
            btn.icon:SetTexture(spellInfo.iconID)
        else
            btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        btn.icon:SetDesaturated(not learned)
        
        if learned then
            btn:Enable()
            btn.label:SetTextColor(LEARNED_COLOR[1], LEARNED_COLOR[2], LEARNED_COLOR[3])
        else
            btn:Disable()
            btn.label:SetTextColor(UNKNOWN_COLOR[1], UNKNOWN_COLOR[2], UNKNOWN_COLOR[3])
        end
        
        -- ── Keystone border + badge ──────────────────────────────────────────
        local owners = partyKeys[i]  -- array of { r,g,b,level,name,unit } or nil

        -- Show if: spell learned, OR showUnknown is on, OR a party member has this key
        local hasPartyKey = owners and #owners > 0
        if not learned and not db.showUnknown and not hasPartyKey then
            btn:Hide()
        else
            btn:Show()
            visibleCount = visibleCount + 1
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -(PANEL_PAD + (visibleCount - 1) * (BTN_H + BTN_PAD)))
        end

        if owners and #owners > 0 then
            -- Sort so "player" is always first (gets the top/left border)
            table.sort(owners, function(a, b)
                if a.unit == "player" then return true end
                if b.unit == "player" then return false end
                return (a.name or "") < (b.name or "")
            end)

            local c1 = owners[1]
            local c2 = owners[2]  -- may be nil

            -- Boost class colour slightly so 2px border is vivid against the dark bg
            local function boost(v) return math.min(1, v * 1.25 + 0.1) end
            local r1b, g1b, b1b = boost(c1.r), boost(c1.g), boost(c1.b)
            local r2b, g2b, b2b = c2 and boost(c2.r) or r1b, c2 and boost(c2.g) or g1b, c2 and boost(c2.b) or b1b

            -- 2px thick colored border
            btn.edgeT:SetHeight(2); btn.edgeT:SetColorTexture(r1b, g1b, b1b, 1)
            btn.edgeL:SetWidth(2);  btn.edgeL:SetColorTexture(r1b, g1b, b1b, 1)
            btn.edgeB:SetHeight(2); btn.edgeB:SetColorTexture(r2b, g2b, b2b, 1)
            btn.edgeR:SetWidth(2);  btn.edgeR:SetColorTexture(r2b, g2b, b2b, 1)

            -- Badge: show highest level key among owners (likely the player's)
            local highestLevel = 0
            for _, o in ipairs(owners) do
                if o.level > highestLevel then highestLevel = o.level end
            end

            if not btn.keyBadge then
                local keyIcon = btn:CreateTexture(nil, "OVERLAY")
                keyIcon:SetSize(12, 12)
                keyIcon:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                keyIcon:SetTexture("Interface\\Icons\\INV_Misc_Key_14")
                keyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                btn.keyIcon = keyIcon

                local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                badge:SetPoint("RIGHT", keyIcon, "LEFT", -2, 0)
                badge:SetShadowColor(0, 0, 0, 1)
                badge:SetShadowOffset(1, -1)
                btn.keyBadge = badge
            end

            -- Colour badge text to match first owner's class colour
            btn.keyBadge:SetTextColor(c1.r, c1.g, c1.b, 1)
            btn.keyBadge:SetText("+" .. highestLevel)
            btn.keyBadge:Show()
            btn.keyIcon:Show()
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.label:SetPoint("RIGHT", btn.keyBadge, "LEFT", -4, 0)
        else
            -- Reset to 1px black border
            btn.edgeT:SetHeight(1); btn.edgeT:SetColorTexture(0, 0, 0, 1)
            btn.edgeB:SetHeight(1); btn.edgeB:SetColorTexture(0, 0, 0, 1)
            btn.edgeL:SetWidth(1);  btn.edgeL:SetColorTexture(0, 0, 0, 1)
            btn.edgeR:SetWidth(1);  btn.edgeR:SetColorTexture(0, 0, 0, 1)
            if btn.keyBadge then
                btn.keyBadge:Hide()
                btn.keyIcon:Hide()
            end
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        end
    end
    
    -- Dynamically shrink the main panel if spells are hidden
    local dynamicH = visibleCount > 0 and (visibleCount * (BTN_H + BTN_PAD)) + PANEL_PAD * 2 - BTN_PAD or PANEL_PAD * 2
    panel:SetHeight(dynamicH)
end

-- [ PUBLIC API ] --------------------------------------------------------------
function Teleport.Init(addon)
    panel = MakePanel()
    buttons = {}
    for i, dungeon in ipairs(DUNGEONS) do
        buttons[i] = MakeButton(panel, dungeon, i)
    end
    panel:SetScale(addon:Profile().teleport.scale)
    ApplyPos()
    RefreshButtons()
    CheckVisibility()

    -- Register with LibKeystone for cross-addon keystone sharing (BigWigs, DBM, etc.)
    if LibKeystone then
        LibKeystone.Register(libKeystoneTable, OnLibKeystoneData)
    end

    -- Track whether we already have a group on login (to avoid nuking the cache
    -- on /reload when we're already in an established party).
    local firstEnterWorld = true

    -- Helper: prune cache entries for players no longer in the group.
    local function PruneStaleEntries()
        local present = { [(UnitName("player") or ""):lower()] = true }
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local n = UnitName("raid" .. i)
                if n then present[n:lower()] = true end
            end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                local n = UnitName("party" .. i)
                if n then present[n:lower()] = true end
            end
        end
        for playerName in pairs(partyKeyCache) do
            if not present[playerName:lower()] then
                partyKeyCache[playerName] = nil
            end
        end
    end

    -- Helper: staggered request pattern that respects LibKeystone's 3 s throttle.
    -- Each call sends a request; the lib internally throttles and queues.
    local function RequestWithRetries(delay1, delay2, delay3)
        C_Timer.After(delay1, function()
            RequestPartyKeystones()
        end)
        if delay2 then
            C_Timer.After(delay2, function()
                RequestPartyKeystones()
                C_Timer.After(1, RefreshButtons)
            end)
        end
        if delay3 then
            C_Timer.After(delay3, function()
                RequestPartyKeystones()
                C_Timer.After(1, RefreshButtons)
            end)
        end
    end

    -- Refresh known spells when spellbook changes and monitor group status
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("SPELLS_CHANGED")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")
    watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE")
    watcher:SetScript("OnEvent", function(self, event, ...)
        if event == "SPELLS_CHANGED" then
            RefreshButtons()

        elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
            -- Key slotted — we're about to start; grab latest party keys.
            RefreshButtons()
            RequestWithRetries(1, 5)

        elseif event == "CHALLENGE_MODE_COMPLETED" then
            -- Key finished — everyone will receive a new keystone shortly.
            -- LibKeystone listens to this internally and auto-broadcasts the
            -- new key, but we need to re-request after a delay for party members.
            RequestWithRetries(4, 8, 14)

        elseif event == "BAG_UPDATE_DELAYED" then
            -- New keystone landed in bags (after key completion or weekly chest).
            -- Re-read our own key and repaint.
            RefreshButtons()

        elseif event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
            -- M+ data became available (delayed on login). Re-read own key.
            RefreshButtons()
            if IsInGroup() then
                RequestWithRetries(1, 5)
            end

        elseif event == "GROUP_ROSTER_UPDATE" then
            PruneStaleEntries()
            -- Request keystones from (possibly new) party members.
            RequestWithRetries(1.5, 5, 10)
            CheckVisibility()
            RefreshButtons()

        elseif event == "PLAYER_ENTERING_WORLD" then
            if firstEnterWorld then
                firstEnterWorld = false
                -- First login: cache is empty anyway; request aggressively.
                wipe(partyKeyCache)
            else
                -- /reload while in a group: keep the cache intact, just prune
                -- anyone who left. This avoids losing data we already have.
                PruneStaleEntries()
            end
            CheckVisibility()
            RefreshButtons()
            if IsInGroup() then
                RequestWithRetries(2, 6, 12)
            end
        end
    end)
end

function Teleport.Refresh(addon)
    if not panel then return end
    local db = addon:Profile().teleport
    panel:SetScale(db.scale)
    ApplyPos()
    RefreshButtons()
    CheckVisibility()
end

function Teleport.Toggle()
    if not panel then return end
    if panel:IsShown() then panel:Hide() else panel:Show(); RefreshButtons() end
end

function Teleport.GetPanel()
    return panel
end



