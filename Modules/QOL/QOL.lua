local ADDON_NAME, ns = ...
ns.QOL = {}
local QOL = ns.QOL

-- [ LOCAL STATE ] -------------------------------------------------------------
local addon
local db        -- shortcut to addon.db.profile.qol
local frame     -- single event-listener frame

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return addon.db.profile.qol end

-- Print a short coloured notice to chat
local function Notify(msg)
    print("|cff2dc9b8LarsQOL:|r " .. msg)
end

-- ============================================================================
-- AUTOMATE QUESTS
--   QUEST_DETAIL     – NPC just offered us a quest  → AcceptQuest()
--   QUEST_PROGRESS   – quest turn-in screen, items already given → CompleteQuest()
--   QUEST_COMPLETE   – reward-picker screen → GetQuestReward()  (auto only when
--                      there is exactly one reward or no choice needed)
-- ============================================================================
local function OnQuestDetail()
    if not cfg().autoQuest then return end
    -- IsQuestCompletable is true if we already have all objectives
    -- (shared-quest confirmation is handled separately by ConfirmAcceptQuest)
    AcceptQuest()
end

local function OnQuestProgress()
    if not cfg().autoQuest then return end
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

local function OnQuestComplete()
    if not cfg().autoQuest then return end
    local numChoices = GetNumQuestChoices()
    if numChoices <= 1 then
        -- Zero or one reward choice – safe to auto-collect
        GetQuestReward(numChoices == 1 and 1 or 0)
    end
    -- Multiple reward choices: leave it to the player
end

-- ============================================================================
-- AUTOMATE GOSSIP
--   GOSSIP_SHOW / QUEST_GREETING – NPC gossip / quest list dialog
--   If there is exactly one available quest and no gossip options we auto-
--   select it.  If there is only one gossip option we auto-select that.
-- ============================================================================
local function OnGossipShow()
    if not cfg().autoGossip then return end

    -- Use the new C_GossipInfo API (10.x+)
    local options = C_GossipInfo.GetOptions()
    local quests  = C_GossipInfo.GetAvailableQuests()

    -- Single gossip option with no quests → select it
    if #options == 1 and #quests == 0 then
        C_GossipInfo.SelectOption(options[1].gossipOptionID)
        return
    end

    -- No gossip options and exactly one available quest → open it
    if #options == 0 and #quests == 1 then
        C_GossipInfo.SelectAvailableQuest(quests[1].questID)
        return
    end
end

local function OnQuestGreeting()
    if not cfg().autoGossip then return end

    local numActive    = GetNumActiveQuests()
    local numAvailable = GetNumAvailableQuests()

    -- One active (in-progress) quest and nothing else → select it
    if numActive == 1 and numAvailable == 0 then
        SelectActiveQuest(1)
        return
    end

    -- One available quest and nothing else → select it
    if numAvailable == 1 and numActive == 0 then
        SelectAvailableQuest(1)
        return
    end
end

-- ============================================================================
-- ACCEPT SUMMON  (with a small safety delay)
--   CONFIRM_SUMMON fires when a party/raid member creates a summoning stone for us.
--   We wait SUMMON_DELAY seconds (≤ the 60-second window) then confirm – but only
--   if the summoner hasn't changed (i.e. the stone is still waiting for us).
-- ============================================================================
local SUMMON_DELAY = 5   -- seconds before auto-confirming

local function OnConfirmSummon()
    if not cfg().autoSummon then return end

    local summoner = C_SummonInfo.GetSummonConfirmSummoner()

    C_Timer.After(SUMMON_DELAY, function()
        if not cfg().autoSummon then return end
        -- Only confirm if the same stone is still active
        local current = C_SummonInfo.GetSummonConfirmSummoner()
        if current and current == summoner then
            C_SummonInfo.ConfirmSummon()
            StaticPopup_Hide("CONFIRM_SUMMON")
        end
    end)
end

-- ============================================================================
-- ACCEPT RESURRECTION
--   RESURRECT_REQUEST fires when another player (or NPC) attempts to rez us.
--   arg1 = resurrecting unit name.
--   We only auto-accept if the resurrecter is an actual player character
--   (not a battle-res pylon or other object) and is NOT in combat
--   (to avoid accidentally accepting a combat rez mid-pull if that option is off).
-- ============================================================================
local function OnResurrectRequest(raisingUnit)
    if not cfg().autoRez then return end

    -- Safety: ignore if the raising unit is in combat (configurable later)
    if UnitAffectingCombat(raisingUnit) and not cfg().autoRezInCombat then return end

    AcceptResurrect()
    StaticPopup_Hide("RESURRECT_NO_TIMER")
end

-- ============================================================================
-- HOLD-TO-RELEASE  (modifier key required to release spirit)
--   We hook the StaticPopup "DEATH" button to require ALT, SHIFT, or CTRL before
--   the click goes through.  This prevents accidental spirit release.
-- ============================================================================
local holdHooked = false

local function HookHoldToRelease()
    if holdHooked then return end
    holdHooked = true

    -- We hook RepopMe — the function the "Release Spirit" button calls.
    -- hooksecurefunc fires BEFORE the original, so we can suppress the release
    -- by checking for a modifier key.  When no modifier is held we immediately
    -- re-open the DEATH popup on the next frame to undo any visual flicker.
    --
    -- StaticPopup_OnClick is the wrong hook point: it fires after the action
    -- has already been dispatched, so re-showing the popup there doesn't help.
    hooksecurefunc("RepopMe", function()
        if not cfg().holdToRelease then return end
        -- Only intercept when the player is actually dead/ghost via the UI popup
        if not StaticPopup_Visible("DEATH") then return end
        if IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
        -- No modifier: cancel the release by re-queuing the popup next frame.
        -- RepopMe has already been called by the time our hook fires, so we
        -- re-show the dialog and let the player try again with a modifier.
        C_Timer.After(0, function()
            if UnitIsDeadOrGhost("player") then
                StaticPopup_Show("DEATH")
            end
        end)
    end)
end

-- ============================================================================
-- SELL JUNK  (grey quality items) on MERCHANT_SHOW
-- ============================================================================
local function SellJunk()
    if not cfg().sellJunk then return end

    local gold = 0
    local count = 0

    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                -- GetItemInfo returns: name,link,rarity,level,minLevel,type,subtype,
                --                      stackCount,equipLoc,texture,vendorPrice,classID
                local _, _, rarity, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
                if rarity == 0 and price and price > 0 then
                    local cInfo = C_Container.GetContainerItemInfo(bag, slot)
                    if cInfo then
                        gold  = gold  + price * (cInfo.stackCount or 1)
                        count = count + 1
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
    end

    if count > 0 then
        Notify(string.format("Sold %d junk item%s for %s.",
            count, count == 1 and "" or "s",
            C_CurrencyInfo.GetCoinTextureString(gold)))
    end
end

-- ============================================================================
-- AUTO REPAIR on MERCHANT_SHOW
-- ============================================================================
local function AutoRepair()
    if not cfg().autoRepair then return end
    if not CanMerchantRepair() then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost == 0 then return end

    -- Try guild bank first (if enabled and we have permission)
    local usedGuild = false
    if cfg().repairGuild and IsInGuild() then
        local guildMoney = GetGuildBankMoney()
        if guildMoney and guildMoney >= cost then
            RepairAllItems(1)   -- 1 = use guild funds
            usedGuild = true
        end
    end

    if not usedGuild then
        RepairAllItems()
    end

    Notify(string.format("Repaired gear for %s.%s",
        C_CurrencyInfo.GetCoinTextureString(cost),
        usedGuild and " (Guild funds)" or ""))
end

-- ============================================================================
-- DECLINE DUEL
-- ============================================================================
local function OnDuelRequested()
    if not cfg().declineDuel then return end
    DeclineDuel()
    StaticPopup_Hide("DUEL_REQUESTED")
end

-- ============================================================================
-- DECLINE GUILD INVITE
-- ============================================================================
local function OnGuildInviteRequest()
    if not cfg().declineGuild then return end
    DeclineGuild()
    StaticPopup_Hide("GUILD_INVITE")
end

-- ============================================================================
-- LOW DURABILITY WARNING
--   Fires on UPDATE_INVENTORY_DURABILITY.  Throttled to once per 60 s.
--   Shows a red on-screen text frame that fades out after 8 seconds.
-- ============================================================================
local EQUIP_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }
local durWarnThrottle = 0
local durFrame  -- on-screen warning frame, built lazily
local durFadeTimer

local function GetOrMakeDurFrame()
    if durFrame then return durFrame end

    local db = addon.db.profile.qol
    local f = CreateFrame("Frame", "LarsQOLDurabilityFrame", UIParent)
    f:SetSize(260, 44)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = addon.db.profile.qol
        d.durPoint, _, d.durRelPoint, d.durX, d.durY = self:GetPoint()
    end)

    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    txt:SetPoint("CENTER")
    txt:SetJustifyH("CENTER")
    f.txt = txt

    -- Restore saved position, falling back to sensible default
    local d = addon.db.profile.qol
    f:SetPoint(
        d.durPoint    or "CENTER",
        UIParent,
        d.durRelPoint or "CENTER",
        d.durX        or 0,
        d.durY        or -200
    )

    f:Hide()
    durFrame = f
    return f
end

local function ShowDurWarning(pct)
    local f = GetOrMakeDurFrame()
    -- Colour: orange above 10%, deep red at/below 10%
    local r, g = 1, pct <= 10 and 0 or 0.45
    f.txt:SetText(string.format("|cff%02x%02x00⚠ Low Durability: %.0f%%|r", math.floor(r*255), math.floor(g*255), pct))
    f:SetAlpha(1)
    f:Show()

    -- Cancel any existing fade timer
    if durFadeTimer then durFadeTimer:Cancel() end
    -- Fade out after 8 seconds
    durFadeTimer = C_Timer.NewTicker(0.05, function(ticker)
        local a = f:GetAlpha() - 0.008
        if a <= 0 then
            f:Hide()
            f:SetAlpha(1)
            ticker:Cancel()
            durFadeTimer = nil
        else
            f:SetAlpha(a)
        end
    end)
end

local function OnDurabilityUpdate()
    if not cfg().durabilityWarn then return end
    local now = GetTime()
    if now - durWarnThrottle < 60 then return end

    local threshold = cfg().durabilityThresh or 20
    local worst = 101

    for _, slot in ipairs(EQUIP_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = (cur / max) * 100
            if pct < worst then worst = pct end
        end
    end

    if worst <= threshold then
        durWarnThrottle = now
        ShowDurWarning(worst)
    end
end

-- Returns the durability warning frame (created lazily on first use).
-- Used by LayoutMode to show and position it.
function QOL.GetDurabilityFrame()
    -- Ensure addon ref is set before building the frame
    if not addon then return nil end
    return GetOrMakeDurFrame()
end

-- ============================================================================
-- M+ AFFIX REMINDER  – on-screen frame shown on login/reload
-- ============================================================================

-- Milestone key levels at which new affixes are added.
-- In Midnight Season 1 the schedule is: all keys (base), +4, +7.
-- Adjust these if Blizzard changes the season milestone levels.
local AFFIX_MILESTONES = { 2, 4, 7 }

-- Theme colours (match the Options panel palette)
local AT = {
    bg      = { 0.10, 0.11, 0.13, 0.96 },
    header  = { 0.13, 0.14, 0.16, 0.97 },
    accent  = { 0.18, 0.78, 0.72, 1.00 },
    text    = { 1.00, 1.00, 1.00, 1.00 },
    textDim = { 0.68, 0.72, 0.74, 1.00 },
    border  = { 0.18, 0.70, 0.65, 0.55 },
}

local affixFrame   -- the popup frame, built once
local affixShownThisSession = false

-- Build the affix popup frame (called once, lazily)
local function BuildAffixFrame()
    local ICON_SIZE   = 36
    local ROW_H       = ICON_SIZE + 6   -- row height per affix
    local PAD         = 12
    local W           = 360

    local f = CreateFrame("Frame", "LarsQOLAffixFrame", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(AT.bg[1], AT.bg[2], AT.bg[3], AT.bg[4])

    -- Border stripe (left)
    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetWidth(3); stripe:SetPoint("TOPLEFT"); stripe:SetPoint("BOTTOMLEFT")
    stripe:SetColorTexture(AT.accent[1], AT.accent[2], AT.accent[3], 1)

    -- Header bar
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(32); header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(AT.accent[1]*0.10, AT.accent[2]*0.10, AT.accent[3]*0.10, 1)
    local hline = header:CreateTexture(nil, "OVERLAY")
    hline:SetHeight(1); hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT")
    hline:SetColorTexture(AT.accent[1], AT.accent[2], AT.accent[3], 0.7)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", PAD, 0)
    title:SetText("|cff2dc9b8M+|r Affixes This Week")
    title:SetTextColor(AT.text[1], AT.text[2], AT.text[3], 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24); closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- "Show on startup" toggle button in the header
    local startupBtn = CreateFrame("Button", nil, header)
    startupBtn:SetSize(18, 18)
    startupBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    local startupIcon = startupBtn:CreateTexture(nil, "ARTWORK")
    startupIcon:SetAllPoints()
    startupBtn.icon = startupIcon

    local function RefreshStartupBtn()
        local on = cfg().affixReminder
        startupIcon:SetTexture(on
            and "Interface/Buttons/UI-CheckBox-Check"
            or  "Interface/Buttons/UI-CheckBox-Check-Disabled")
        startupBtn:SetAlpha(on and 1 or 0.5)
    end
    RefreshStartupBtn()

    local startupTip = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    startupTip:SetPoint("RIGHT", startupBtn, "LEFT", -4, 0)
    startupTip:SetText("Show on login")
    startupTip:SetTextColor(AT.textDim[1], AT.textDim[2], AT.textDim[3], 1)

    startupBtn:SetScript("OnClick", function()
        cfg().affixReminder = not cfg().affixReminder
        ns.QOL.Refresh(addon)
        RefreshStartupBtn()
    end)

    -- Content area (rows added dynamically)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -32)
    body:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -32)
    f.body = body
    f.rows = {}   -- recycled row frames

    -- Populate affixes into the frame
    function f:Populate(affixList)
        -- Hide old rows
        for _, r in ipairs(self.rows) do r:Hide() end
        self.rows = {}

        if not affixList or #affixList == 0 then
            self:SetSize(W, 32 + 40)
            body:SetHeight(40)
            local nodata = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nodata:SetPoint("CENTER", body, "CENTER", 0, 0)
            nodata:SetText("No affix data available yet.")
            nodata:SetTextColor(AT.textDim[1], AT.textDim[2], AT.textDim[3], 1)
            return
        end

        local y = -PAD
        -- Group by milestone
        for mi, milestone in ipairs(AFFIX_MILESTONES) do
            local entry = affixList[mi]
            if not entry then break end

            local id   = entry.id
            local name, desc, fileDataID = C_ChallengeMode.GetAffixInfo(id)
            if not name then break end

            -- Milestone label
            local mileLbl = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            mileLbl:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + ICON_SIZE + 8, y + 2)
            mileLbl:SetTextColor(AT.accent[1], AT.accent[2], AT.accent[3], 0.9)
            mileLbl:SetText(string.format("+%d and above", milestone))
            y = y - 16

            -- Row
            local row = CreateFrame("Frame", nil, body)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
            row:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, y)
            table.insert(self.rows, row)

            -- Affix icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if fileDataID and fileDataID ~= 0 then
                icon:SetTexture(fileDataID)
            else
                icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
            end

            -- Affix name
            local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLbl:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
            nameLbl:SetText(name)
            nameLbl:SetTextColor(AT.text[1], AT.text[2], AT.text[3], 1)

            -- Description (wrapped)
            local descLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            descLbl:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -2)
            descLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            descLbl:SetJustifyH("LEFT")
            descLbl:SetWordWrap(true)
            descLbl:SetText(desc or "")
            descLbl:SetTextColor(AT.textDim[1], AT.textDim[2], AT.textDim[3], 1)

            -- Tooltip on icon hover
            icon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(name, AT.accent[1], AT.accent[2], AT.accent[3])
                if desc and desc ~= "" then
                    GameTooltip:AddLine(desc, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
            icon:EnableMouse(true)

            -- Estimate row height: assume ~2 lines for long descriptions
            local descH = math.max(30, math.ceil(#(desc or "") / 70) * 14)
            local rowH  = ICON_SIZE + descH
            row:SetHeight(rowH)
            y = y - rowH - 14
        end

        -- Divider line before total count
        local div = body:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  body, "TOPLEFT",  PAD,  y)
        div:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, y)
        div:SetColorTexture(AT.border[1], AT.border[2], AT.border[3], AT.border[4])
        y = y - 10

        local totalH = math.abs(y) + PAD
        body:SetHeight(totalH)
        self:SetSize(W, 32 + totalH)
    end

    f:Hide()
    return f
end

local function ShowAffixFrame()
    if not affixFrame then
        affixFrame = BuildAffixFrame()
    end

    -- Always request fresh data from the server.
    if C_MythicPlus and C_MythicPlus.RequestCurrentAffixes then
        C_MythicPlus.RequestCurrentAffixes()
    end

    -- Populate from whatever is cached right now.
    local affixList = C_MythicPlus and C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes()
    local hasData = affixList and #affixList > 0
    affixFrame:Populate(affixList)

    if hasData then
        -- We have real data: show immediately.
        affixFrame._pendingShow = nil
        affixFrame:Show()
    else
        -- No data yet (server response pending): mark the frame so
        -- OnAffixUpdate will show it once the data arrives.
        affixFrame._pendingShow = true
    end
end

local function OnAffixUpdate()
    -- Repopulate whenever the frame exists:
    --   * If shown: keep the live data current.
    --   * If hidden but built: it means ShowAffixFrame() already requested data
    --     and will show the frame; populate now so it has fresh content when shown.
    if not affixFrame then return end
    local list = C_MythicPlus and C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes()
    affixFrame:Populate(list)
    -- If the frame was waiting for data (built but hidden), show it now.
    if affixFrame._pendingShow then
        affixFrame._pendingShow = nil
        affixFrame:Show()
    end
end

local function MaybeShowAffixFrame()
    if not cfg().affixReminder then return end
    if affixShownThisSession then return end
    affixShownThisSession = true

    -- Data may not be ready immediately on login; request it and show
    -- once the MYTHIC_PLUS_CURRENT_AFFIX_UPDATE event fires
    if C_MythicPlus and C_MythicPlus.RequestCurrentAffixes then
        C_MythicPlus.RequestCurrentAffixes()
    end
    -- Small delay so the server response can arrive before we try to render
    C_Timer.After(2, function()
        if cfg().affixReminder then
            ShowAffixFrame()
        end
    end)
end

-- ============================================================================
-- EVENT DISPATCH
-- ============================================================================
local function OnEvent(self, event, arg1)
    if     event == "QUEST_DETAIL"               then OnQuestDetail()
    elseif event == "QUEST_PROGRESS"             then OnQuestProgress()
    elseif event == "QUEST_COMPLETE"             then OnQuestComplete()
    elseif event == "GOSSIP_SHOW"                then OnGossipShow()
    elseif event == "QUEST_GREETING"             then OnQuestGreeting()
    elseif event == "CONFIRM_SUMMON"             then OnConfirmSummon()
    elseif event == "RESURRECT_REQUEST"          then OnResurrectRequest(arg1)
    elseif event == "DUEL_REQUESTED"             then OnDuelRequested()
    elseif event == "GUILD_INVITE_REQUEST"        then OnGuildInviteRequest()
    elseif event == "UPDATE_INVENTORY_DURABILITY"    then OnDurabilityUpdate()
    elseif event == "PLAYER_ENTERING_WORLD"           then MaybeShowAffixFrame()
    elseif event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then OnAffixUpdate()
    elseif event == "MERCHANT_SHOW"                   then
        SellJunk()
        AutoRepair()
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Called from Init.lua: OnEnable
function QOL.Init(addonObj)
    addon = addonObj
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    QOL.Refresh(addon)
    HookHoldToRelease()
    -- Build the durability frame now so LayoutMode can find it immediately.
    GetOrMakeDurFrame()
end

-- Opens the affix popup frame manually (e.g. from the Options panel)
function QOL.ShowAffixes()
    ShowAffixFrame()
end

-- Called whenever settings change (profile switch, toggle in options)
function QOL.Refresh(addonObj)
    addon = addonObj or addon
    local d = cfg()

    local function Reg(event, flag)
        if flag then
            frame:RegisterEvent(event)
        else
            frame:UnregisterEvent(event)
        end
    end

    Reg("QUEST_DETAIL",      d.autoQuest)
    Reg("QUEST_PROGRESS",    d.autoQuest)
    Reg("QUEST_COMPLETE",    d.autoQuest)
    Reg("GOSSIP_SHOW",       d.autoGossip or d.autoQuest)
    Reg("QUEST_GREETING",    d.autoGossip or d.autoQuest)
    Reg("CONFIRM_SUMMON",              d.autoSummon)
    Reg("RESURRECT_REQUEST",           d.autoRez)
    Reg("DUEL_REQUESTED",              d.declineDuel)
    Reg("GUILD_INVITE_REQUEST",        d.declineGuild)
    Reg("UPDATE_INVENTORY_DURABILITY",        d.durabilityWarn)
    Reg("PLAYER_ENTERING_WORLD",              d.affixReminder)
    Reg("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",   true)  -- always needed to refresh open frame

    -- MERCHANT_SHOW is needed for either sell-junk or auto-repair
    Reg("MERCHANT_SHOW", d.sellJunk or d.autoRepair)
end
