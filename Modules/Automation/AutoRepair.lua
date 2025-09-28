----------------------------------------------------------------------------------------
--	AutoRepair Module for RefineUI
--	This module automatically repairs equipment when interacting with a merchant
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Local Variables
----------------------------------------------------------------------------------------
local f = CreateFrame("Frame")

----------------------------------------------------------------------------------------
--	Event Handling
----------------------------------------------------------------------------------------
local function OnEvent(self, event)
    if event == "MERCHANT_SHOW" then
        -- Check if auto repair is enabled
        if not C.automation.autoRepair then return end
        if not CanMerchantRepair() then return end

        local repairAllCost, canRepair = GetRepairAllCost()

        if repairAllCost > 0 and canRepair then
            -- Try guild repair first if enabled and available
            if C.automation.autoGuildRepair and IsInGuild() and CanGuildBankRepair() then
                RepairAllItems(true)
                if GetRepairAllCost() == 0 then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200Auto Repaired using guild funds.|r", 255, 255, 255)
                    return
                end
            end
            
            -- Fall back to personal repair
            if repairAllCost <= GetMoney() then
                RepairAllItems(false)
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200Auto Repaired:|r " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost), 255, 255, 255)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200Not enough money for repair|r. Required: " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost), 255, 255, 255)
            end
        end
    end
end

----------------------------------------------------------------------------------------
--	Frame Setup
----------------------------------------------------------------------------------------
f:SetScript("OnEvent", OnEvent)
f:RegisterEvent("MERCHANT_SHOW")