local ADDON_NAME, ns = ...
ns.Teleport = {}
local Teleport = ns.Teleport

-- [ CONSTANTS ] ---------------------------------------------------------------
-- searchKey: lowercase substring that will match this dungeon's name as returned
-- by C_ChallengeMode.GetMapUIInfo() — used to build challengeMapToDungeon dynamically.
local DUNGEONS = {
    { name = "Academy",      searchKey = "academy",     spellID = 393273  },
    { name = "Terrace",      searchKey = "terrace",     spellID = 1254572 },
    { name = "Nexuspoint",   searchKey = "nexus",       spellID = 1254563 },
    { name = "Spire",        searchKey = "spire",       spellID = 1254400 },
    { name = "Skyreach",     searchKey = "skyreach",    spellID = 159898  },
    { name = "Caverns",      searchKey = "caverns",     spellID = 1254559 },
    { name = "Pit of Saron", searchKey = "pit of saron",spellID = 1254555 },
    { name = "Triumvirate",  searchKey = "triumvirate", spellID = 1254551 },
}

-- challengeMapID → DUNGEONS index.
-- Seeded with known-good fallback values; rebuilt at runtime via
-- BuildChallengeMapLookup() once C_ChallengeMode data is available.
local challengeMapToDungeon = {
    [402] = 1,  -- Algeth'ar Academy
    [558] = 2,  -- Magister's Terrace
    [559] = 3,  -- Nexus-Point Xenas
    [557] = 4,  -- Windrunner's Spire
    [161] = 5,  -- Skyreach
    [560] = 6,  -- Maisara Caverns
    [556] = 7,  -- Pit of Saron
    [583] = 8,  -- Seat of the Triumvirate
}

-- Rebuild challengeMapToDungeon by asking C_ChallengeMode for the current season's
-- map list and name-matching against DUNGEONS[i].searchKey.
-- Safe to call multiple times; only updates entries we can confirm.
local function BuildChallengeMapLookup()
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps then return end
    for _, mapID in ipairs(maps) do
        local mapName = C_ChallengeMode.GetMapUIInfo(mapID)
        if mapName then
            local lowerMap = mapName:lower()
            for i, dungeon in ipairs(DUNGEONS) do
                if lowerMap:find(dungeon.searchKey, 1, true) then
                    challengeMapToDungeon[mapID] = i
                    break
                end
            end
        end
    end
end

local BTN_W, BTN_H = 180, 22
local BTN_PAD = 1
local MAX_PILLS = 3    -- max per-owner keystone pills shown per button
local PILL_W    = 24   -- pill chip width in pixels
local PANEL_PAD = 8 -- Increased for a slightly larger drag target
local HEADER_H = 26  -- header strip containing title + controls
local FRAME_W = BTN_W + PANEL_PAD * 2

local DISABLED_ALPHA = 0.3
local LEARNED_COLOR = { 0.9, 0.9, 0.9 }
local UNKNOWN_COLOR = { 0.5, 0.5, 0.5 }
local T = ns.Theme  -- populated by Theme.Init() before BuildPanel runs

-- [ KEYSTONE DATA VIA LIBKEYSTONE ] -----------------------------------------
-- LibKeystone is compatible with BigWigs, DBM, and any addon using the same
-- library. It broadcasts over "LibKS" prefix automatically.
-- Callback args: keyLevel, keyMapID, playerRating, playerName, channel

local LibKeystone = LibStub and LibStub("LibKeystone", true)
local partyKeyCache = {}  -- ["PlayerName"] = { mapID=n, level=n }
local libKeystoneTable = {}  -- unique table used as our identifier with LibKeystone

local function OnLibKeystoneData(keyLevel, keyMapID, playerRating, playerName, channel)
    if channel ~= "PARTY" then return end  -- ignore GUILD broadcasts
    -- LibKeystone captures pName at library load time (before PLAYER_LOGIN), so it
    -- may arrive as nil. Fall back to UnitName("player") — by the time this callback
    -- fires we are logged in and the name is available.
    if not playerName or playerName == "" then
        playerName = UnitName("player") or ""
        if playerName == "" then return end
    end
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
    local myName = (UnitName("player") or ""):lower()
    local ownKeyHandled = false

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

    -- All party data (including self) comes through LibKeystone cache.
    -- Own key arrives via LKS.Request callback; party members via CHAT_MSG_ADDON.
    for playerName, data in pairs(partyKeyCache) do
        local lowerName = playerName:lower()
        if lowerName == myName then
            -- Own key came through LibKeystone — add it with "player" unit for class color.
            AddEntry(data.mapID, data.level, "player", playerName)
            ownKeyHandled = true
        else
            -- Resolve unit token for class colour; search raid OR party tokens
            local unit = nil
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
            AddEntry(data.mapID, data.level, unit, playerName)
        end
    end

    -- Always supplement with direct C_MythicPlus read for own key.
    -- This covers: LibKeystone not loaded, pName nil at lib load, or data not yet in cache.
    if C_MythicPlus then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        if mapID and mapID > 0 and level and level > 0 then
            local name = UnitName("player") or "player"
            if not ownKeyHandled then
                -- Cache it so OnLibKeystoneData can normalise it later
                local shortName = name:match("^([^%-]+)") or name
                partyKeyCache[shortName] = { mapID = mapID, level = level }
                AddEntry(mapID, level, "player", shortName)
            end
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
    local totalH = (#DUNGEONS * (BTN_H + BTN_PAD)) + PANEL_PAD * 2 - BTN_PAD + HEADER_H
    local f = CreateFrame("Frame", "yaqolTeleportPanel", UIParent)
    f:SetSize(FRAME_W, totalH)
    f:SetFrameStrata("MEDIUM")
    f.restingAlpha = 0.8

    ns.Theme:ApplyBg(f)
    ns.Theme:ApplyBorderCompact(f)

    -- Header strip
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(FRAME_W, HEADER_H)
    header:SetPoint("TOPLEFT")
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(T.accent[1]*0.08, T.accent[2]*0.08, T.accent[3]*0.08, 1)
    local hdiv = header:CreateTexture(nil, "OVERLAY")
    hdiv:SetHeight(1)
    hdiv:SetPoint("BOTTOMLEFT"); hdiv:SetPoint("BOTTOMRIGHT")
    hdiv:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45)
    local titleLbl = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLbl:SetPoint("LEFT", header, "LEFT", PANEL_PAD, 0)
    titleLbl:SetText("DUNGEONS")
    titleLbl:SetTextColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)

    -- Close button (inside header) — uses WoW minimize button texture (always renders)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, HEADER_H)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    local cHl = closeBtn:CreateTexture(nil, "HIGHLIGHT")
    cHl:SetAllPoints(); cHl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.20)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(14, 14)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeIcon:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    closeBtn:SetScript("OnEnter", function()
        f:SetAlpha(1)
        closeIcon:SetVertexColor(1, 1, 1, 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        f:SetAlpha(f.restingAlpha)
        closeIcon:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    end)
    closeBtn:SetScript("OnClick", function()
        userClosed = true
        f:Hide()
    end)

    -- Refresh button (inside header, left of close)
    local refreshBtn = CreateFrame("Button", nil, header)
    refreshBtn:SetSize(22, HEADER_H)
    refreshBtn:SetPoint("RIGHT", closeBtn, "LEFT", 0, 0)
    local rHl = refreshBtn:CreateTexture(nil, "HIGHLIGHT")
    rHl:SetAllPoints(); rHl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.20)
    local rIcon = refreshBtn:CreateTexture(nil, "OVERLAY")
    rIcon:SetPoint("CENTER"); rIcon:SetSize(12, 12)
    rIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    rIcon:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
    refreshBtn:SetScript("OnEnter", function()
        f:SetAlpha(1)
        rIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        -- Count how many keys are in cache
        local keyCount = 0
        for _ in pairs(partyKeyCache) do keyCount = keyCount + 1 end
        local partySize = GetNumSubgroupMembers() + 1  -- +1 for self
        GameTooltip:SetOwner(refreshBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Refresh keystones", 1, 1, 1, 1, true)
        GameTooltip:AddLine(string.format("Keys in cache: %d / %d party members", keyCount, partySize), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Re-requests from party. Only works if they have BigWigs, DBM, or another LibKeystone addon.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Shift+Click to print cache to chat for debugging.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function()
        f:SetAlpha(f.restingAlpha)
        rIcon:SetVertexColor(T.textDim[1], T.textDim[2], T.textDim[3], 1)
        GameTooltip:Hide()
    end)
    refreshBtn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            -- Debug: print cache state to chat
            print("|cff4fc3f7yaqol TeleportKeys debug:|r")
            local keyCount = 0
            for name, data in pairs(partyKeyCache) do
                local dungIdx = challengeMapToDungeon[data.mapID]
                local dungName = dungIdx and DUNGEONS[dungIdx] and DUNGEONS[dungIdx].name or ("??mapID="..tostring(data.mapID))
                print(string.format("  [%s] +%d %s (mapID=%d, dungIdx=%s)", name, data.level, dungName, data.mapID, tostring(dungIdx)))
                keyCount = keyCount + 1
            end
            if keyCount == 0 then print("  (cache is empty)") end
            -- Also show challengeMapToDungeon entries
            print("  Challenge map mappings:")
            for mapID, idx in pairs(challengeMapToDungeon) do
                print(string.format("    mapID=%d → %s", mapID, DUNGEONS[idx] and DUNGEONS[idx].name or "?"))
            end
            return
        end
        -- Normal click: don't wipe the cache (keep what we have visible while waiting
        -- for updated responses). Just re-request and refresh after delay.
        RefreshButtons()
        RequestPartyKeystones()
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
    local yOff = -(HEADER_H + PANEL_PAD + (idx - 1) * (BTN_H + BTN_PAD))
    local btn = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PANEL_PAD, yOff)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- Use spell type with numeric spellID — same pattern as BigWigs teleport buttons
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", dungeon.spellID)

    -- 1px neutral border using OVERLAY sublayer 7 so they render above
    -- InsecureActionButtonTemplate's own overlay textures.
    local function MakeEdge()
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.6)
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
    bg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])
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

    -- Left accent bar: class color of primary keystone owner; hidden when no keys.
    local accentBar = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    accentBar:SetWidth(3)
    accentBar:SetPoint("TOPLEFT",    btn, "TOPLEFT",    1, 0)
    accentBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 0)
    accentBar:Hide()
    btn.accentBar = accentBar

    -- Pre-created owner pills (shown in RefreshButtons when party has this key).
    -- pills[1] is rightmost; pills[MAX_PILLS] is leftmost when all are showing.
    btn.pills = {}
    for p = 1, MAX_PILLS do
        local pill = CreateFrame("Frame", nil, btn)
        pill:SetSize(PILL_W, BTN_H - 2)
        if p == 1 then
            pill:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        else
            pill:SetPoint("RIGHT", btn.pills[p - 1].frame, "LEFT", -2, 0)
        end
        pill:Hide()
        local pillBg = pill:CreateTexture(nil, "BACKGROUND")
        pillBg:SetAllPoints()
        local pillBar = pill:CreateTexture(nil, "BORDER")
        pillBar:SetWidth(2)
        pillBar:SetPoint("TOPLEFT",    pill, "TOPLEFT",    0, 0)
        pillBar:SetPoint("BOTTOMLEFT", pill, "BOTTOMLEFT", 0, 0)
        local pillText = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pillText:SetPoint("CENTER", pill, "CENTER", 1, 0)
        pillText:SetShadowColor(0, 0, 0, 1)
        pillText:SetShadowOffset(1, -1)
        btn.pills[p] = { frame = pill, bg = pillBg, bar = pillBar, text = pillText }
    end

    -- Hover highlight + tooltip
    btn:SetScript("OnEnter", function(self)
        parent:SetAlpha(1)
        if self.learned then
            self.bg:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(dungeon.spellID)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        parent:SetAlpha(parent.restingAlpha)
        self.bg:SetColorTexture(T.bgRow[1], T.bgRow[2], T.bgRow[3], T.bgRow[4])
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
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PAD, -(HEADER_H + PANEL_PAD + (visibleCount - 1) * (BTN_H + BTN_PAD)))
        end

        if owners and #owners > 0 then
            -- Sort: player first (primary), then alphabetical
            table.sort(owners, function(a, b)
                if a.unit == "player" then return true end
                if b.unit == "player" then return false end
                return (a.name or "") < (b.name or "")
            end)

            -- Left accent bar: primary owner's class color
            local o1 = owners[1]
            btn.accentBar:SetColorTexture(o1.r, o1.g, o1.b, 1)
            btn.accentBar:Show()

            -- One pill per owner (rightmost = owners[1], leftmost = owners[nPills])
            local nPills = math.min(#owners, MAX_PILLS)
            for p = 1, MAX_PILLS do
                local pill = btn.pills[p]
                if p <= nPills then
                    local o = owners[p]
                    pill.frame:Show()
                    pill.bg:SetColorTexture(o.r, o.g, o.b, 0.28)
                    pill.bar:SetColorTexture(o.r, o.g, o.b, 0.90)
                    pill.text:SetText("+" .. o.level)
                    pill.text:SetTextColor(1, 1, 1, 1)
                else
                    pill.frame:Hide()
                end
            end

            -- Label shrinks right to accommodate the leftmost visible pill
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.label:SetPoint("RIGHT", btn.pills[nPills].frame, "LEFT", -3, 0)
        else
            -- No keystones: full-width label, no accent bar, no pills
            btn.accentBar:Hide()
            for p = 1, MAX_PILLS do btn.pills[p].frame:Hide() end
            btn.label:ClearAllPoints()
            btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        end
    end
    
    -- Dynamically shrink the main panel if spells are hidden
    local dynamicH = HEADER_H + (visibleCount > 0 and (visibleCount * (BTN_H + BTN_PAD)) + PANEL_PAD * 2 - BTN_PAD or PANEL_PAD * 2)
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
    -- Build dynamic challenge map → dungeon lookup from available season maps.
    -- C_ChallengeMode data may not be ready at load time; we rebuild again on
    -- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE and PLAYER_ENTERING_WORLD.
    BuildChallengeMapLookup()
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
            -- Re-read our own key, update cache, and repaint.
            RequestPartyKeystones()
            RefreshButtons()

        elseif event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
            -- M+ data became available (delayed on login). Rebuild map lookup first,
            -- then re-read own key into cache.
            BuildChallengeMapLookup()
            RequestPartyKeystones()  -- re-seed own key into cache
            C_Timer.After(1, RefreshButtons)
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
            BuildChallengeMapLookup()
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
            -- Always request own key; if also in a group, request from all members too.
            if IsInGroup() then
                RequestWithRetries(2, 6, 12)
            else
                C_Timer.After(2, function()
                    RequestPartyKeystones()
                    C_Timer.After(1, RefreshButtons)
                end)
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



