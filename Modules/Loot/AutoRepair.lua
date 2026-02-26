----------------------------------------------------------------------------------------
-- AutoRepair for RefineUI
-- Description: Automatically repairs equipment when interacting with a merchant
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoRepair = RefineUI:RegisterModule("AutoRepair")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local C_CurrencyInfo = C_CurrencyInfo
local CanGuildBankRepair = CanGuildBankRepair
local CanMerchantRepair = CanMerchantRepair
local GetMoney = GetMoney
local GetRepairAllCost = GetRepairAllCost
local IsInGuild = IsInGuild
local RepairAllItems = RepairAllItems

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local EVENT_KEY = {
    MERCHANT_SHOW = "AutoRepair:OnMerchantShow",
}

----------------------------------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------------------------------
function AutoRepair:OnMerchantShow()
    if not Config.Automation.AutoRepair then return end
    if not CanMerchantRepair() then return end

    local repairAllCost, canRepair = GetRepairAllCost()

    if repairAllCost > 0 and canRepair then
        if Config.Automation.GuildRepair and IsInGuild() and CanGuildBankRepair() then
            RepairAllItems(true)
            if GetRepairAllCost() == 0 then
                RefineUI:Print("Auto Repaired using guild funds.")
                return
            end
        end
        
        if repairAllCost <= GetMoney() then
            RepairAllItems(false)
            RefineUI:Print("Auto Repaired for: " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost))
        else
            RefineUI:Print("Not enough money for repair. Required: " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost))
        end
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function AutoRepair:OnEnable()
    RefineUI:RegisterEventCallback("MERCHANT_SHOW", function()
        self:OnMerchantShow()
    end, EVENT_KEY.MERCHANT_SHOW)
end
