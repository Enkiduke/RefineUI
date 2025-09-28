----------------------------------------------------------------------------------------
--	AutoSellJunk Module for RefineUI
--	This module automatically sells junk items when interacting with a merchant
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

-- Disable legacy junk seller if unified AutoSell is enabled to avoid double scans
if C and C.autosell and C.autosell.enable == true then
    return
end

----------------------------------------------------------------------------------------
--	Upvalues
----------------------------------------------------------------------------------------
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
local GetItemInfo = C_Item.GetItemInfo
local MerchantFrame = MerchantFrame
local UseContainerItem = C_Container.UseContainerItem

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------
local MAX_BAG_ID = 4

----------------------------------------------------------------------------------------
--	AutoSellJunk Mixin
----------------------------------------------------------------------------------------
local AutoSellJunk = {}

----------------------------------------------------------------------------------------
--	Frame Creation
----------------------------------------------------------------------------------------
local AutoSellJunkFrame = CreateFrame("Frame")

----------------------------------------------------------------------------------------
--	Event Handling
----------------------------------------------------------------------------------------
function AutoSellJunk:OnLoad()
    self:RegisterEvent("MERCHANT_SHOW")
    self:SetScript("OnEvent", self.OnEvent)
end

function AutoSellJunk:OnEvent(event)
    if event == "MERCHANT_SHOW" then
        C_Timer.After(0.1, function() self:OnMerchantShow() end)
    end
end

----------------------------------------------------------------------------------------
--	Core Functionality
----------------------------------------------------------------------------------------
function AutoSellJunk:OnMerchantShow()
    if not MerchantFrame:IsVisible() or MerchantFrame.selectedTab ~= 1 then
        return
    end

    local profitInCopper, itemsSold = 0, 0

    for bag = 0, MAX_BAG_ID do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue and not info.isLocked then
                local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.hyperlink or info.itemID)
                if sellPrice and sellPrice > 0 then
                    C_Container.UseContainerItem(bag, slot)
                    itemsSold = itemsSold + 1
                    profitInCopper = profitInCopper + (sellPrice * (info.stackCount or 1))
                end
            end
        end
    end

    if profitInCopper > 0 then
        print("|cFFFFD200Auto Sell Junk:|r " .. GetCoinTextureString(profitInCopper))
    end
end

----------------------------------------------------------------------------------------
--	Helper Functions
----------------------------------------------------------------------------------------
function AutoSellJunk:IsJunk(itemInfo)
    return itemInfo.Rarity == 0
end

function AutoSellJunk:GetItemInfo(link)
    local name, _, rarity, level, minLevel, type, subType, stackCount,
    equipLoc, icon, sellPrice, classId, subClassId, bindType = GetItemInfo(link)

    return {
        Name = name,
        Rarity = rarity,
        Level = level,
        MinLevel = minLevel,
        Type = type,
        SubType = subType,
        StackCount = stackCount,
        EquipLocation = equipLoc,
        Icon = icon,
        SellPrice = sellPrice,
        ClassId = classId,
        SubClassId = subClassId,
        BindType = bindType,
    }
end

function AutoSellJunk:GetContainerItemInfo(bag, slot)
    local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemId =
    GetContainerItemInfo(bag, slot)

    return {
        ItemCount = itemCount,
        Quality = quality,
        ItemLink = itemLink,
        ItemId = itemId,
    }
end

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------
-- Apply the mixin to the frame
for k, v in pairs(AutoSellJunk) do
    AutoSellJunkFrame[k] = v
end

-- Initialize the frame
AutoSellJunkFrame:OnLoad()