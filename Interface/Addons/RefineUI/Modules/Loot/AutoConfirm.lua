----------------------------------------------------------------------------------------
-- AutoConfirm for RefineUI
-- Description: Auto-confirms selected loot and delete confirmation dialogs.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local AutoConfirm = RefineUI:RegisterModule("AutoConfirm", function(cfg)
    local loot = cfg.Loot
    if type(loot) ~= "table" or loot.Enable == false then
        return false
    end
    return loot.AutoConfirm ~= false
end)

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local SellCursorItem = SellCursorItem
local StaticPopup_FindVisible = StaticPopup_FindVisible

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DELETE_TEXT = strupper(DELETE_ITEM_CONFIRM_STRING)

local DELETE_DIALOG_LIST = {
	["DELETE_ITEM"] = true,
	["DELETE_GOOD_ITEM"] = true,
	["DELETE_QUEST_ITEM"] = true,
	["DELETE_GOOD_QUEST_ITEM"] = true,
}

local CONFIRM_LIST = {
	["CONFIRM_LOOT_ROLL"] = true,
	["LOOT_BIND"] = true,
	["CONFIRM_DISENCHANT_ROLL"] = true,
	["EQUIP_BIND_TRADEABLE"] = true,
	["EQUIP_BIND_REFUNDABLE"] = true,
	["USE_NO_REFUND_CONFIRM"] = true,
	["CONFIRM_MAIL_ITEM_UNREFUNDABLE"] = true,
	["ACCOUNT_BANK_DEPOSIT_NO_REFUND_CONFIRM"] = true,
	["CONFIRM_PURCHASE_TOKEN_ITEM"] = true,
	["CONFIRM_PURCHASE_NONREFUNDABLE_ITEM"] = true,
	["CONFIRM_BINDER"] = true,
	["GOSSIP_CONFIRM"] = true,
	["ABANDON_QUEST"] = true,
	["ABANDON_QUEST_WITH_ITEMS"] = true,
}

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function AutoConfirm:OnEnable()
	RefineUI:HookOnce("AutoConfirm:StaticPopup_Show", "StaticPopup_Show", function(which, _, _, data)
		local isDelete = DELETE_DIALOG_LIST[which]
		if not isDelete and (not CONFIRM_LIST[which] or InCombatLockdown()) then
			return
		end

		local dialog = StaticPopup_FindVisible(which, data)
		if not dialog then
			return
		end

		if isDelete then
			-- Blizzard's EditBoxOnTextChanged enables Button1 once the text matches.
			local editBox = dialog:GetEditBox()
			if editBox:IsShown() then
				editBox:SetText(DELETE_TEXT)
				editBox:HighlightText()
			end
			return
		end

		local button = dialog:GetButton1()
		if button:IsShown() and button:IsEnabled() then
			button:Click()
		end
	end)

	RefineUI:RegisterEventCallback("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", function()
		SellCursorItem()
	end, "AutoConfirm:MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")
end
