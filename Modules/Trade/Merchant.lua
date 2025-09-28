local R, C, L = unpack(RefineUI)

-- Performance: Cache stack sizes to avoid repeated API calls
local stackSizeCache = {}

-- Performance: Pre-compile regex pattern
local ITEM_ID_PATTERN = "item:(%d+):"

-- KISS: Extract item ID parsing for clarity
local function extractItemID(itemLink)
    return tonumber(itemLink:match(ITEM_ID_PATTERN))
end

-- KISS: Extract stack size logic for clarity
local function getMaxStackSize(itemID)
    if not stackSizeCache[itemID] then
        stackSizeCache[itemID] = (C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)) or 1
    end
    return stackSizeCache[itemID]
end

----------------------------------------------------------------------------------------
--	Alt+Click to buy a stack
----------------------------------------------------------------------------------------
hooksecurefunc("MerchantItemButton_OnModifiedClick", function(self)
    if not IsAltKeyDown() then return end
    
    local id = self:GetID()
    local itemLink = GetMerchantItemLink and GetMerchantItemLink(id)
    if not itemLink then return end
    
    local itemID = extractItemID(itemLink)
    if not itemID then return end
    
    local maxStack = getMaxStackSize(itemID)
    if maxStack > 1 then
        BuyMerchantItem(id, maxStack)
    end
end)

-- Performance: Do string concatenation once at load time
ITEM_VENDOR_STACK_BUY = _G.ITEM_VENDOR_STACK_BUY.."\n|cff00ff00<"..L_MISC_BUY_STACK..">|r"

