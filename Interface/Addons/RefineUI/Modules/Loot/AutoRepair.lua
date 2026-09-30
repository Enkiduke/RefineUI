----------------------------------------------------------------------------------------
-- AutoRepair for RefineUI
-- Description: Automatically repairs equipment when interacting with a merchant
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoRepair = RefineUI:RegisterModule("AutoRepair", function(cfg)
    local automation = cfg.Automation
    return not (type(automation) == "table" and automation.AutoRepair == false)
end)

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
    if not CanMerchantRepair() then return end

    local repairAllCost, canRepair = GetRepairAllCost()
    if not canRepair or repairAllCost <= 0 then return end

    local costText = C_CurrencyInfo.GetCoinTextureString(repairAllCost)
    -- The server covers any guild shortfall from personal funds.
    if Config.Automation.GuildRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        RefineUI:Print("Auto Repaired using guild funds: " .. costText)
    elseif repairAllCost <= GetMoney() then
        RepairAllItems(false)
        RefineUI:Print("Auto Repaired for: " .. costText)
    else
        RefineUI:Print("Not enough money for repair. Required: " .. costText)
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
