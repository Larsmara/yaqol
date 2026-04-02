local ADDON_NAME, ns = ...
ns.FriendList = {}
local FriendList = ns.FriendList

-- [ LOCALS ] ------------------------------------------------------------------
local pcall     = pcall
local tostring  = tostring
local type      = type
local pairs     = pairs
local ipairs    = ipairs
local strsplit  = strsplit
local unpack    = unpack or table.unpack
local wipe      = _G.wipe
local math_min  = math.min
local math_max  = math.max

local C_Timer   = _G.C_Timer
local CreateFrame = _G.CreateFrame

local FRIENDS_BUTTON_TYPE_WOW      = _G.FRIENDS_BUTTON_TYPE_WOW
local FRIENDS_BUTTON_TYPE_BNET     = _G.FRIENDS_BUTTON_TYPE_BNET
local FRIENDS_BUTTON_TYPE_DIVIDER  = _G.FRIENDS_BUTTON_TYPE_DIVIDER
local BNConnected                  = _G.BNConnected

-- Shorthand to the live profile sub-table.
local function cfg()
    return ns.Addon:Profile().friendList
end

-- [ MEDIA PATHS ] -------------------------------------------------------------
local MEDIA_BASE  = "Interface\\AddOns\\yaqol\\Modules\\FriendList\\Media\\"
local CLIENT_BASE = MEDIA_BASE .. "Client\\"
local STATUS_BASE = MEDIA_BASE .. "Status\\"

-- [ WOW PROJECT ICONS ] -------------------------------------------------------
local PROJECTS = {
    { 1,  "WOW_PROJECT_MAINLINE",                "WoW_Retail_simple"   },
    { 2,  "WOW_PROJECT_CLASSIC",                 "WoW_Classic_simple"  },
    { 5,  "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WoW_TBC_simple"      },
    { 11, "WOW_PROJECT_WRATH_CLASSIC",           "WoW_Wrath_simple"    },
    { 14, "WOW_PROJECT_CATACLYSM_CLASSIC",       "WoW_Cata_simple"     },
    { 19, "WOW_PROJECT_MISTS_CLASSIC",           "WoW_MoP_simple"      },
    { 3,  "WOW_PROJECT_WOWLABS",                 "WoW_WoWLabs"         },
}

local function BuildWoWProjectIconMap()
    local icons = {}
    for _, p in ipairs(PROJECTS) do
        local fallbackId, constName, suffix = p[1], p[2], p[3]
        local id = _G[constName]
        if type(id) ~= "number" then id = fallbackId end
        icons[id] = CLIENT_BASE .. suffix
    end
    return icons
end

local WOW_PROJECT_ICONS = BuildWoWProjectIconMap()

local function IsWoWClientProgram(clientProgram)
    if not clientProgram then return false end
    local up = tostring(clientProgram):upper()
    return up:match("^WOW") ~= nil
end

local CLASSIC_PROJECT_ID = _G.WOW_PROJECT_CLASSIC or 2
local CLASSIC_VARIANTS = {
    { { "anniversary", "20th" },        "WoW_Classic_Anniversary" },
    { { "season", "discovery", "sod" }, "WoW_SoD"                 },
    { { "hardcore", " hc" },            "WoW_HC"                  },
    { { "era" },                        "WoW_Era"                  },
    { { "ptr" },                        "WoW_PTR"                  },
}

local function ResolveClientIconTexture(clientProgram, wowProjectID, versionString, extraText)
    if type(wowProjectID) == "number" then
        if wowProjectID == CLASSIC_PROJECT_ID then
            local hay = (tostring(versionString or "") .. " " .. tostring(extraText or "")):lower()
            for _, rule in ipairs(CLASSIC_VARIANTS) do
                local needles, suffix = rule[1], rule[2]
                for _, needle in ipairs(needles) do
                    if hay:find(needle, 1, true) then
                        return CLIENT_BASE .. suffix
                    end
                end
            end
        end
        local tex = WOW_PROJECT_ICONS[wowProjectID]
        if tex then return tex end
    end
    if clientProgram and type(_G.BNet_GetClientTexture) == "function" then
        local ok, tex = pcall(_G.BNet_GetClientTexture, clientProgram)
        if ok and tex then return tex end
    end
    return nil
end

-- [ STATUS HELPERS ] ----------------------------------------------------------
local function GetFriendStatus_WoW(friendInfo)
    if not friendInfo then return nil end
    if not friendInfo.connected then return "Offline" end
    if friendInfo.afk           then return "AFK"     end
    if friendInfo.dnd           then return "DND"     end
    return "Online"
end

local function GetFriendStatus_BNet(accountInfo, gameInfo)
    if not accountInfo or not gameInfo then return nil end
    if not gameInfo.isOnline then return "Offline" end
    if accountInfo.isAFK or gameInfo.isGameAFK  then return "AFK" end
    if accountInfo.isDND or gameInfo.isGameBusy then return "DND" end
    return "Online"
end

-- [ STATUS ICON PACKS ] -------------------------------------------------------
local STATUS_ICON_PACKS = {
    SQUARE = {
        Online  = STATUS_BASE .. "Square\\Online",
        AFK     = STATUS_BASE .. "Square\\Afk",
        DND     = STATUS_BASE .. "Square\\Dnd",
        Offline = STATUS_BASE .. "Square\\Offline",
    },
}

local function ResolveStatusIconTexture(statusKey)
    local db = cfg()
    if not db then return nil end
    local pack = db.statusIconPack
    if not pack or pack == "NONE" then return nil end
    local set = STATUS_ICON_PACKS[pack]
    if not set then return nil end
    return set[statusKey]
end

-- [ TEXTURE HELPERS ] ---------------------------------------------------------
local function ApplySquareTexCoord(tex)
    if tex and tex.SetTexCoord then tex:SetTexCoord(0.15, 0.85, 0.15, 0.85) end
end

local function ApplyDefaultTexCoord(tex)
    if tex and tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
end

local function MakeIconCrisp(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid  then tex:SetSnapToPixelGrid(false)  end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0)   end
end

local function TextEquals(fs, expected)
    if not fs or not fs.GetText then return false end
    return (fs:GetText() or "") == (expected or "")
end

local function SetTextIfChanged(fs, expected)
    if not fs or not fs.SetText then return end
    local cur = fs.GetText and fs:GetText() or nil
    if cur ~= expected then fs:SetText(expected or "") end
end

local function TextureEquals(texObj, desired)
    if not texObj or not texObj.GetTexture then return false end
    local cur = texObj:GetTexture()
    if cur == desired then return true end
    return tostring(cur) == tostring(desired)
end

local function SetTextureIfChanged(texObj, desired)
    if not texObj or not texObj.SetTexture then return end
    if desired == nil then return end
    if not TextureEquals(texObj, desired) then texObj:SetTexture(desired) end
end

-- [ HELPERS ] -----------------------------------------------------------------
local function RGBToHex(r, g, b)
    r = (r or 1) * 255; g = (g or 1) * 255; b = (b or 1) * 255
    return string.format("%02x%02x%02x", r, g, b)
end

local function ColorText(text, r, g, b)
    if not text or text == "" then return text end
    return "|cff" .. RGBToHex(r, g, b) .. text .. "|r"
end

local function ClassNameToFile(className)
    if not className or className == "" then return nil end
    local male = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(male) == "table" then
        for classFile, localized in pairs(male) do
            if className == localized then return classFile end
        end
    end
    local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
    if type(female) == "table" then
        for classFile, localized in pairs(female) do
            if className == localized then return classFile end
        end
    end
    return nil
end

local maxLevelCache = nil
local function ResetMaxLevelCache() maxLevelCache = nil end

local function GetMaxLevelSafe()
    if maxLevelCache then return maxLevelCache end
    if type(_G.GetMaxLevelForExpansionLevel) == "function" then
        local ok, v = pcall(_G.GetMaxLevelForExpansionLevel, _G.LE_EXPANSION_LEVEL_CURRENT or 10)
        if ok and type(v) == "number" and v > 0 then maxLevelCache = v; return v end
    end
    if type(_G.MAX_PLAYER_LEVEL_TABLE) == "table" then
        local lvl = _G.MAX_PLAYER_LEVEL_TABLE[_G.LE_EXPANSION_LEVEL_CURRENT or 10]
        if type(lvl) == "number" and lvl > 0 then maxLevelCache = lvl; return lvl end
    end
    return nil
end

local function GetClassColorFromLocalizedName(className)
    local classFile = ClassNameToFile(className)
    if not classFile then return nil end
    if _G.C_ClassColor and _G.C_ClassColor.GetClassColor then
        local ok, c = pcall(_G.C_ClassColor.GetClassColor, classFile)
        if ok and c then return c.r, c.g, c.b end
    end
    local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return nil
end

-- [ FACTION TINT ] ------------------------------------------------------------
local FACTION_TINT = {
    Horde    = { r = 0.75, g = 0.10, b = 0.10 },
    Alliance = { r = 0.10, g = 0.35, b = 0.80 },
}

local function NormalizeFaction(v)
    if not v then return nil end
    if type(v) == "string" then
        local s = v:lower()
        if s:find("horde",    1, true) then return "Horde"    end
        if s:find("alliance", 1, true) then return "Alliance" end
        return nil
    end
    if type(v) == "number" then
        if v == 0 then return "Alliance" end
        if v == 1 then return "Horde"    end
    end
    return nil
end

local function EnsureFactionBG(button)
    if button.__ccfFactionBG then return end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetAllPoints(button); bg:Hide()
    button.__ccfFactionBG = bg
end

local function ApplyFactionTint(button, factionKey, isOffline)
    local db = cfg()
    if not db or not db.factionTint then
        if button.__ccfFactionBG then button.__ccfFactionBG:Hide() end
        button.__ccfFactionKey = nil
        return
    end
    EnsureFactionBG(button)
    local bg = button.__ccfFactionBG
    local t = factionKey and FACTION_TINT[factionKey] or nil
    if not t then bg:Hide(); button.__ccfFactionKey = nil; return end

    local baseA = db.factionTintAlpha
    if type(baseA) ~= "number" then baseA = 0.14 end
    baseA = math_max(0, math_min(0.30, baseA))
    local a = baseA
    if isOffline then a = a * 0.45 end

    local lastKey = button.__ccfFactionKey
    local lastA   = button.__ccfFactionA
    local lastOff = button.__ccfFactionOff
    if lastKey == factionKey and lastA == a and lastOff == (isOffline and true or false) and bg:IsShown() then
        return
    end
    bg:SetColorTexture(t.r, t.g, t.b, a)
    bg:Show()
    button.__ccfFactionKey = factionKey
    button.__ccfFactionA   = a
    button.__ccfFactionOff = isOffline and true or false
end

-- [ FAVORITE STYLING ] --------------------------------------------------------
local FAVORITE_GOLD = { 1.0, 0.82, 0.2, 0.85 }

local function EnsureFavoriteWidgets(button)
    if not button or button.__ccfFavStripe then return end
    local stripe = button:CreateTexture(nil, "ARTWORK")
    stripe:SetColorTexture(unpack(FAVORITE_GOLD))
    stripe:Hide()
    button.__ccfFavStripe = stripe
end

local function ClearFavoriteVisuals(button)
    if not button then return end
    if button.__ccfFavStripe then button.__ccfFavStripe:Hide() end
end

local function ApplyFavoriteVisuals(button, isFavorite)
    local db = cfg()
    if not db then return end
    EnsureFavoriteWidgets(button)
    local style = db.favoriteStyle or "BAR"
    local fav = isFavorite and true or false
    local star = button.Favorite or button.favoriteIcon or button.FavoriteIcon

    if style == "STAR" then
        ClearFavoriteVisuals(button)
        if not fav then
            if star and star.Hide then star:Hide() end
            return
        end
        if star and star.Show and star.ClearAllPoints then
            star:Show(); star:ClearAllPoints()
            if button.gameIcon and button.gameIcon.GetLeft then
                star:SetPoint("RIGHT", button.gameIcon, "LEFT", -3, 0)
            else
                star:SetPoint("RIGHT", button, "RIGHT", -40, 0)
            end
            if star.SetSize  then star:SetSize(12, 12)     end
            if star.SetAlpha then star:SetAlpha(0.95)       end
        end
        return
    end

    if style == "BAR" then
        if star and star.Hide then star:Hide() end
        if not fav then ClearFavoriteVisuals(button); return end
        local stripe = button.__ccfFavStripe
        stripe:ClearAllPoints()
        stripe:SetPoint("TOPLEFT",    button, "TOPLEFT",    0,  -1)
        stripe:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0,   1)
        stripe:SetWidth(3)
        stripe:Show()
        return
    end

    if star and star.Hide then star:Hide() end
    ClearFavoriteVisuals(button)
end

-- [ CORE STYLING ] ------------------------------------------------------------
local function StyleFriendButton(button)
    local db = cfg()
    if not db or not db.enable or not button or not button.buttonType then return false end
    if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return false end

    local nameLine = button.name
    local infoLine = button.info
    if not nameLine or not infoLine then return false end

    local buttonType = button.buttonType
    local charName, realm, className, level, area, note, realID
    local isWoW = false
    local clientProgram
    local status
    local isFavorite = false
    local factionKey

    local blizzInfoText = infoLine:GetText()
    button.__ccfBlizzInfoText = blizzInfoText

    local function ReadFavoriteFromStar()
        local star = button.Favorite or button.favoriteIcon or button.FavoriteIcon
        if star and star.IsShown then return star:IsShown() and true or false end
        return false
    end

    if buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local friendInfo = _G.C_FriendList and _G.C_FriendList.GetFriendInfoByIndex and
            _G.C_FriendList.GetFriendInfoByIndex(button.id)
        if not friendInfo then return false end

        isWoW         = true
        clientProgram = "WOW"
        button.__ccfClientProgram = "WOW"
        local wowProjectID = _G.WOW_PROJECT_ID or _G.WOW_PROJECT_MAINLINE or 1
        button.__ccfWowProjectID  = wowProjectID

        charName = friendInfo.name or ""
        if charName:find("-") then
            local a, b = strsplit("-", charName); charName, realm = a, b
        end
        className  = friendInfo.className
        level      = friendInfo.level
        area       = friendInfo.area
        note       = friendInfo.notes
        status     = GetFriendStatus_WoW(friendInfo)
        isFavorite = ReadFavoriteFromStar()
        factionKey = NormalizeFaction(friendInfo.factionName or friendInfo.faction or friendInfo.factionID)

    elseif buttonType == FRIENDS_BUTTON_TYPE_BNET and type(BNConnected) == "function" and BNConnected() then
        local acct = _G.C_BattleNet and _G.C_BattleNet.GetFriendAccountInfo and
            _G.C_BattleNet.GetFriendAccountInfo(button.id)
        if not acct then return false end

        realID     = acct.accountName or ""
        note       = acct.note
        isFavorite = (acct.isFavorite == true)

        local game = acct.gameAccountInfo
        if game then
            clientProgram              = game.clientProgram
            status                     = GetFriendStatus_BNet(acct, game)
            button.__ccfClientProgram  = game.clientProgram
            button.__ccfWowProjectID   = game.wowProjectID
            button.__ccfVersionString  = game.version
            button.__ccfRichPresence   = game.richPresence or game.gameText or game.gameName or game.gameAccountName
        else
            button.__ccfClientProgram  = nil
            button.__ccfWowProjectID   = nil
            button.__ccfVersionString  = nil
            button.__ccfRichPresence   = nil
        end

        if game and game.isOnline and IsWoWClientProgram(game.clientProgram) then
            isWoW         = true
            charName      = game.characterName   or ""
            level         = game.characterLevel  or 0
            className     = game.className       or ""
            area          = game.areaName        or ""
            realm         = game.realmDisplayName or ""
            clientProgram = game.clientProgram
            factionKey    = NormalizeFaction(game.factionName or game.faction or game.factionID)
        end
    else
        return false
    end

    if status == "Offline" then isFavorite = false end

    -- Display name
    local baseName = charName or ""
    if db.useNoteAsName and note and note ~= "" then
        if buttonType == FRIENDS_BUTTON_TYPE_BNET and realID and realID ~= "" then
            realID = note
        else
            baseName = note
        end
    end

    -- Class colorize
    if db.useClassColor and isWoW and className and className ~= "" then
        local r, g, b = GetClassColorFromLocalizedName(className)
        if r then baseName = ColorText(baseName, r, g, b) end
    end

    -- Level
    if db.showLevel and isWoW and type(level) == "number" and level > 0 then
        local maxLevel = GetMaxLevelSafe()
        local shouldShow = true
        if maxLevel and level == maxLevel then shouldShow = false end
        if shouldShow and type(_G.GetQuestDifficultyColor) == "function" then
            local c = _G.GetQuestDifficultyColor(level)
            baseName = (baseName or "") .. ColorText(": " .. level, c.r, c.g, c.b)
        end
    end

    -- Title
    local displayTitle
    if buttonType == FRIENDS_BUTTON_TYPE_BNET and realID and realID ~= "" then
        displayTitle = (baseName and baseName ~= "") and (realID .. " || " .. baseName) or realID
    else
        displayTitle = baseName or ""
    end

    -- Info line
    local displayInfo
    local realmPart = realm or ""
    if db.hideRealm then realmPart = "" end
    if status == "Offline" then
        displayInfo = (blizzInfoText and blizzInfoText ~= "") and blizzInfoText or ""
    else
        if area and area ~= "" and realmPart ~= "" then
            displayInfo = area .. " - " .. realmPart
        elseif area and area ~= "" then
            displayInfo = area
        else
            displayInfo = realmPart
        end
    end

    -- Faction fallback
    if isWoW and not factionKey and type(_G.UnitFactionGroup) == "function" then
        factionKey = _G.UnitFactionGroup("player")
    end

    -- Signature cache
    local iconClientProgram = button.__ccfClientProgram or clientProgram
    local extraText = button.__ccfRichPresence or button.__ccfBlizzInfoText
    local desiredGameIcon = nil
    if db.forceClientIcons and iconClientProgram then
        desiredGameIcon = ResolveClientIconTexture(iconClientProgram, button.__ccfWowProjectID,
            button.__ccfVersionString, extraText)
    end
    local desiredStatusTex = (db.statusIconPack and db.statusIconPack ~= "NONE")
        and ResolveStatusIconTexture(status) or nil

    local sig = tostring(db.enable)..tostring(db.useClassColor)..tostring(db.showLevel)
        ..tostring(db.hideRealm)..tostring(db.useNoteAsName)..tostring(db.squareIcons)
        ..tostring(db.forceClientIcons)..tostring(db.statusIconPack)..tostring(db.favoriteStyle)
        ..tostring(isFavorite)..tostring(status)..tostring(displayTitle)..tostring(displayInfo)
        ..tostring(isWoW)..tostring(factionKey)..tostring(db.factionTint)
        ..tostring(db.factionTintAlpha)..tostring(desiredGameIcon)..tostring(desiredStatusTex)

    local sigSame = (button.__ccfSig == sig)

    if not sigSame or not TextEquals(nameLine, displayTitle) then
        SetTextIfChanged(nameLine, displayTitle or "")
    end
    if not sigSame or not TextEquals(infoLine, displayInfo) then
        SetTextIfChanged(infoLine, displayInfo or "")
    end

    ApplyFavoriteVisuals(button, isFavorite)

    if not sigSame then
        if isWoW then ApplyFactionTint(button, factionKey, status == "Offline")
        else          ApplyFactionTint(button, nil, false) end

        if button.gameIcon then
            MakeIconCrisp(button.gameIcon)
            if desiredGameIcon then SetTextureIfChanged(button.gameIcon, desiredGameIcon) end
            if db.squareIcons then ApplySquareTexCoord(button.gameIcon)
            else                   ApplyDefaultTexCoord(button.gameIcon) end
        end

        if button.status then
            MakeIconCrisp(button.status)
            if desiredStatusTex and status then
                SetTextureIfChanged(button.status, desiredStatusTex)
                ApplyDefaultTexCoord(button.status)
            else
                if db.squareIcons then ApplySquareTexCoord(button.status)
                else                   ApplyDefaultTexCoord(button.status) end
            end
            if status then button.status:SetAlpha(1) end
        end

        button.__ccfSig = sig
    else
        if isWoW then ApplyFactionTint(button, factionKey, status == "Offline")
        else          ApplyFactionTint(button, nil, false) end

        if button.gameIcon and desiredGameIcon and not TextureEquals(button.gameIcon, desiredGameIcon) then
            SetTextureIfChanged(button.gameIcon, desiredGameIcon)
            if db.squareIcons then ApplySquareTexCoord(button.gameIcon)
            else                   ApplyDefaultTexCoord(button.gameIcon) end
        end
        if button.status and desiredStatusTex and status and not TextureEquals(button.status, desiredStatusTex) then
            SetTextureIfChanged(button.status, desiredStatusTex)
            ApplyDefaultTexCoord(button.status)
        end
    end

    return true
end

-- [ HOOKS ] -------------------------------------------------------------------
local hooked = false

local function HookOnce()
    if hooked then return end
    hooked = true

    if type(_G.FriendsFrame_UpdateFriendButton) == "function" then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
            local ok = StyleFriendButton(button)
            if not ok and C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if button and button.IsShown and button:IsShown() then
                        StyleFriendButton(button)
                    end
                end)
            end
        end)
    end

    -- RecentAllies: light-touch class coloring only
    if _G.RecentAlliesFrame and _G.RecentAlliesFrame.List and _G.RecentAlliesFrame.List.ScrollBox then
        local sb = _G.RecentAlliesFrame.List.ScrollBox
        if sb and sb.Update then
            hooksecurefunc(sb, "Update", function(scrollBox)
                local db = cfg()
                if not db or not db.enable or not db.useClassColor then return end
                scrollBox:ForEachFrame(function(btn)
                    local data = btn and btn.elementData
                    local cd   = btn and btn.CharacterData
                    if not data or not cd or not cd.Name then return end
                    local characterData = data.characterData
                    local stateData     = data.stateData
                    if not characterData or not stateData or not stateData.isOnline then return end
                    local classID = characterData.classID
                    if not classID then return end
                    if type(_G.GetClassInfo) ~= "function" then return end
                    local _, classFile = _G.GetClassInfo(classID)
                    if not classFile then return end
                    if not _G.C_ClassColor or not _G.C_ClassColor.GetClassColor then return end
                    local c = _G.C_ClassColor.GetClassColor(classFile)
                    if not c then return end
                    local n = characterData.name
                    if not n or n == "" then return end
                    cd.Name:SetText(ColorText(n, c.r, c.g, c.b))
                end)
            end)
        end
    end
end

-- [ UI REFRESH ] --------------------------------------------------------------
local function RefreshFriendsUI()
    if type(_G.FriendsFrame_Update) == "function" then
        _G.FriendsFrame_Update()
    end
end

-- [ PUBLIC API ] --------------------------------------------------------------
function FriendList.Init(addon)
    HookOnce()
    RefreshFriendsUI()
end

function FriendList.Refresh(addon)
    RefreshFriendsUI()
end

-- Watcher for max-level cache reset
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ResetMaxLevelCache()
    end
end)
