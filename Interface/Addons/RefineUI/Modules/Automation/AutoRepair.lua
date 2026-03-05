local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
--	AutoRepair Module for RefineUI
--	This module automatically repairs equipment when interacting with a merchant
----------------------------------------------------------------------------------------

local AutoRepair = RefineUI:RegisterModule("AutoRepair")

function AutoRepair:OnMerchantShow()
    -- Check if auto repair is enabled
    if not RefineUI.Config.Automation.AutoRepair then return end
    if not CanMerchantRepair() then return end

    local repairAllCost, canRepair = GetRepairAllCost()

    if repairAllCost > 0 and canRepair then
        -- Try guild repair first if enabled and available
        if RefineUI.Config.Automation.GuildRepair and IsInGuild() and CanGuildBankRepair() then
            RepairAllItems(true)
            if GetRepairAllCost() == 0 then
                RefineUI:Print("Auto Repaired using guild funds.")
                return
            end
        end
        
        -- Fall back to personal repair
        if repairAllCost <= GetMoney() then
            RepairAllItems(false)
            RefineUI:Print("Auto Repaired for: " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost))
        else
            RefineUI:Print("Not enough money for repair. Required: " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost))
        end
    end
end

function AutoRepair:OnEnable()
    RefineUI:RegisterEventCallback("MERCHANT_SHOW", function()
        self:OnMerchantShow()
    end, "AutoRepair:OnMerchantShow")
end
