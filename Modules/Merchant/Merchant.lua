local ADDON_NAME, ns = ...
ns.Merchant = {}
local Merchant = ns.Merchant

-- [ LOCALS ] ------------------------------------------------------------------
local addon

local function cfg() return addon.db.profile.merchant end

-- How many items to show per page (vanilla = 10, we extend to 20).
-- This global is read by all of Blizzard's merchant code, so changing it here
-- is enough to make their pagination logic work with the larger page size.
local ITEMS_PER_PAGE = 20

-- Whether we have already rebuilt the frame this session.
local rebuilt = false

-- [ FRAME REBUILD ] -----------------------------------------------------------
-- Called once the first time a merchant window opens.
-- Widens MerchantFrame, creates item slots 13–20 (11 and 12 already exist in
-- Blizzard XML), and repositions all UI elements to fit the new layout.
--
-- MerchantItemTemplate is 153×44 px (from Blizzard XML).
-- Original layout: 2 columns, rows separated by 44+8=52px, cols by 153+12=165px.
-- We double that into 4 columns by placing a second 2-col block to the right.
--
-- Final layout (4 cols × 5 rows = 20 items):
--   Left block  (items  1–10): col A (x=11)  and col B (x=11+165=176)
--   Right block (items 11–20): col C (x=11+165+165+24=365) and col D (x=365+165=530)
--   The 24px gap between blocks gives a visible separation.
local function RebuildFrame()
    if rebuilt then return end
    rebuilt = true

    -- Item dimensions (from MerchantItemTemplate in Blizzard XML)
    local ITEM_W     = 153
    local ITEM_H     = 44
    local COL_GAP    = 12   -- horizontal gap between columns
    local ROW_GAP    = 8    -- vertical gap between rows (items 1–10 use 8, 9→11 uses 15)
    local BLOCK_GAP  = 24   -- extra gap between the two 2-col blocks
    local COL_STEP   = ITEM_W + COL_GAP   -- 165
    local ROW_STEP   = ITEM_H + ROW_GAP   -- 52
    local START_X    = 11   -- matches Blizzard's item1 anchor x
    local START_Y    = -69  -- matches Blizzard's item1 anchor y

    -- X origin of each of the 4 columns
    local colX = {
        START_X,                              -- col 0 (items 1,3,5,7,9   → left block left)
        START_X + COL_STEP,                   -- col 1 (items 2,4,6,8,10  → left block right)
        START_X + COL_STEP * 2 + BLOCK_GAP,  -- col 2 (items 11,13,15,17,19 → right block left)
        START_X + COL_STEP * 3 + BLOCK_GAP,  -- col 3 (items 12,14,16,18,20 → right block right)
    }

    -- Widen the frame to fit all 4 columns.
    -- Right edge = colX[4] + ITEM_W + right-padding (≈11)
    local frameW = colX[4] + ITEM_W + 11
    MerchantFrame:SetWidth(frameW)
    -- Ensure the frame is tall enough: original is 444px for 5 rows starting at y=-69.
    -- Items are arranged so that odd-numbered slots are in the left column of
    -- their block and even-numbered are in the right column, stepping down 5 rows.
    --
    -- Block 1 (items 1–10): slot order by (col, row)
    --   1=(0,0) 2=(1,0) 3=(0,1) 4=(1,1) … 9=(0,4) 10=(1,4)
    -- Block 2 (items 11–20): same pattern, cols 2 & 3
    for i = 1, ITEMS_PER_PAGE do
        local btn = _G["MerchantItem" .. i]
        btn:ClearAllPoints()

        local posInBlock = (i - 1) % 10        -- 0-based position within the 2-col block
        local block      = math.floor((i-1)/10) -- 0 = left, 1 = right
        local col        = (posInBlock % 2) + (block * 2)  -- 0,1 or 2,3
        local row        = math.floor(posInBlock / 2)

        local x = colX[col + 1]
        local y = START_Y - row * ROW_STEP

        btn:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", x, y)
    end

    -- Leave BuyBackItem below MerchantItem10 (Blizzard default), just nudge it
    -- right so it doesn't sit under the repair buttons.
    MerchantBuyBackItem:ClearAllPoints()
    MerchantBuyBackItem:SetPoint("TOPLEFT", MerchantItem10, "BOTTOMLEFT", 30, -53)

    -- Prev stays at its default BOTTOMLEFT position (x=25).
    -- Next is scaled from the right edge the same way Blizzard does it:
    --   original frame=336, Next at x=310 from BOTTOMLEFT → 26px from right edge.
    MerchantPrevPageButton:ClearAllPoints()
    MerchantPrevPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", 25, 96)
    MerchantNextPageButton:ClearAllPoints()
    MerchantNextPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", frameW - 26, 96)
    -- PageText sits centred at the bottom; just keep Blizzard's own anchor.
    MerchantPageText:ClearAllPoints()
    MerchantPageText:SetPoint("BOTTOM", MerchantFrame, "BOTTOM", 0, 86)
end

-- [ UPDATE HOOK ] -------------------------------------------------------------
-- We hook MerchantFrame_UpdateMerchantInfo so that after Blizzard's own update
-- runs (handling repair buttons, buyback slot, page text, etc.) we simply make
-- sure the extra item slots (13–20) and slots 11/12 are properly shown.
-- (Blizzard's stock code explicitly calls MerchantItem11:Hide() and 12:Hide()
-- at the end of UpdateMerchantInfo since those are normally buyback-only slots).
local function OnUpdateMerchantInfo()
    local numItems = GetMerchantNumItems()
    for i = 11, ITEMS_PER_PAGE do
        local btn = _G["MerchantItem" .. i]
        if btn then
            -- Because we widened the frame, we want all 20 slots to appear uniformly,
            -- even if empty (they look like an empty grey box).
            -- Blizzard's loop handles hiding the item contents (icon/price) for empty ones,
            -- but the stock code explicitly does `MerchantItem11:Hide()`, `MerchantItem12:Hide()`
            -- at the very end. We just ensure all frames 11-20 are shown.
            btn:Show()
        end
    end
end

-- [ INIT ] --------------------------------------------------------------------
function Merchant.Init(addonObj)
    addon = addonObj

    if not cfg().enable then return end

    -- Override the global page-size constant before any merchant code runs.
    MERCHANT_ITEMS_PER_PAGE = ITEMS_PER_PAGE

    -- Create the extra item frames immediately so Blizzard's update loop
    -- (which iterates 1–MERCHANT_ITEMS_PER_PAGE) never hits a nil frame.
    -- Blizzard XML ships items 1–12; we add 13–20 here.
    for i = 13, ITEMS_PER_PAGE do
        if not _G["MerchantItem" .. i] then
            CreateFrame("Frame", "MerchantItem" .. i, MerchantFrame, "MerchantItemTemplate")
        end
    end

    -- Hook MERCHANT_SHOW to reposition everything on first open.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("MERCHANT_SHOW")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" and cfg().enable then
            RebuildFrame()
        end
    end)

    -- Hook into the merchant update function so our extra slots stay correct.
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnUpdateMerchantInfo)
end

function Merchant.Refresh(addonObj)
    addon = addonObj
    -- If the feature gets toggled off at runtime, reset the page size so the
    -- vanilla frame at least works correctly (will take effect next merchant open).
    if not cfg().enable then
        MERCHANT_ITEMS_PER_PAGE = 10
    else
        MERCHANT_ITEMS_PER_PAGE = ITEMS_PER_PAGE
    end
end
