local ADDON_NAME, ns = ...
ns.CombatRess = {}
local CombatRess = ns.CombatRess

-- [ CONSTANTS ] ---------------------------------------------------------------
local SIZE          = 40              -- icon frame size (px)
-- Spell ID 20484 (Rebirth) keys the *shared* raid combat-rez charge pool in WoW.
-- Any class's battle rez (Rebirth, Raise Ally, Soulstone, Intercession) uses and
-- regenerates charges from the same pool.  GetSpellCharges(20484) returns the
-- pool regardless of the player's class.
local RESS_SPELL_ID = 20484
local FALLBACK_ICON = 136048          -- generic spell icon if lookup fails

-- [ STATE ] -------------------------------------------------------------------
local frame

-- [ HELPERS ] -----------------------------------------------------------------
local function cfg() return ns.Addon:Profile().combatRess end

local function ShouldShow()
    if not cfg().enabled then return false end
    local _, iType = GetInstanceInfo()
    if iType == "raid" then return true end
    if iType == "party" and C_ChallengeMode.IsChallengeModeActive() then
        local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
        return (lvl or 0) >= 1
    end
    return false
end

local function CheckVisibility()
    if not frame then return end
    if InCombatLockdown() then return end
    if ShouldShow() then
        frame:Show()
    else
        frame:Hide()
    end
end

local function UpdateDisplay()
    if not frame then return end
    local charges = C_Spell.GetSpellCharges(RESS_SPELL_ID)
    if not charges then
        -- Charge data unavailable (e.g. not in the instance yet).
        -- Show zero and clear the cooldown swipe.
        frame.countText:SetText("0")
        frame.cd:Clear()
        return
    end
    -- currentCharges, cooldownStartTime, cooldownDuration may be secret values
    -- in Midnight 12.0.  Never compare or do arithmetic on them — pass directly
    -- to widget APIs that accept secrets:
    --   SetFormattedText:  string formatting works with secrets
    --   SetAlpha:          alpha is clamped [0..1]; secret 0 = hidden, ≥1 = shown
    --   Cooldown:SetCooldown: the Cooldown widget API accepts secret values
    frame.countText:SetFormattedText("%d", charges.currentCharges)
    -- Out of combat: hide the charge label when it would show "0" (via the alpha
    -- trick).  In combat, always keep it visible to avoid Show/Hide taint.
    if InCombatLockdown() then
        frame.countText:SetAlpha(1)
    else
        frame.countText:SetAlpha(charges.currentCharges)
    end
    frame.cd:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
end

-- [ BUILD ] -------------------------------------------------------------------
local function BuildFrame()
    local db = cfg()
    local f = CreateFrame("Frame", "yaqolCombatRessFrame", UIParent)
    f:SetSize(SIZE, SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local d = cfg()
        d.point, _, d.relPoint, d.x, d.y = self:GetPoint()
    end)
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale or 1.0)
    f:Hide()

    -- [ ICON ] ----------------------------------------------------------------
    local spellInfo = C_Spell.GetSpellInfo(RESS_SPELL_ID)
    local iconTex = (spellInfo and spellInfo.iconID) or FALLBACK_ICON
    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(f)
    icon:SetTexture(iconTex)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- [ DARK BORDER ] ---------------------------------------------------------
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetAllPoints(f)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 0.9)

    -- [ COOLDOWN SWIPE + COUNTDOWN NUMBERS ] ----------------------------------
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetFrameLevel(f:GetFrameLevel() + 1)
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(false)
    cd:SetUseAuraDisplayTime(true)
    cd:SetCountdownAbbrevThreshold(600)
    f.cd = cd

    -- [ CHARGE COUNT LABEL ] --------------------------------------------------
    -- Bottom-right corner; hidden when charges = 0 via SetAlpha trick.
    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    countText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    countText:SetFont(countText:GetFont(), 12, "OUTLINE")
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    f.countText = countText

    -- [ TOOLTIP ] -------------------------------------------------------------
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Combat Resurrection", 1, 1, 1)
        GameTooltip:AddLine("Available combat rez charges for this pull.", 0.68, 0.72, 0.74, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- [ PUBLIC API ] --------------------------------------------------------------
function CombatRess.Init(addon)
    frame = BuildFrame()

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    watcher:RegisterEvent("CHALLENGE_MODE_START")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("SPELL_UPDATE_CHARGES")   -- fires when a charge is used or gained

    watcher:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_CHARGES" or event == "PLAYER_REGEN_DISABLED" then
            UpdateDisplay()
        else
            CheckVisibility()
            if ShouldShow() then UpdateDisplay() end
        end
    end)
end

function CombatRess.Refresh(addon)
    if not frame then return end
    local db = cfg()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    frame:SetScale(db.scale or 1.0)
    CheckVisibility()
    if ShouldShow() then UpdateDisplay() end
end

function CombatRess.GetFrame() return frame end
