----------------------------------------------------------------------------------------
-- AutoConfirm for RefineUI
-- Description: Auto-confirms selected loot and delete confirmation dialogs.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local AutoConfirm = RefineUI:RegisterModule("AutoConfirm")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local InCombatLockdown = InCombatLockdown
local SellCursorItem = SellCursorItem

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DELETE_TEXT = _G.DELETE or "DELETE"

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
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetShownPopupIndexByWhich(which)
	local numDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
	for i = 1, numDialogs do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.which == which and popup:IsShown() then
			return i
		end
	end
end

function AutoConfirm:FillDeleteDialog()
	local numDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
	for i = 1, numDialogs do
		local popup = _G["StaticPopup" .. i]
		if popup and popup:IsShown() and DELETE_DIALOG_LIST[popup.which] then
			local editBox = popup.editBox or _G["StaticPopup" .. i .. "EditBox"]
			if editBox and editBox:IsShown() then
				editBox:SetText(DELETE_TEXT)
				if editBox.HighlightText then
					editBox:HighlightText()
				end
			end

			local button = popup.button1 or _G["StaticPopup" .. i .. "Button1"]
			if button and button:IsShown() then
				button:Enable()
			end
			return
		end
	end
end

function AutoConfirm:OnEnable()
	if not RefineUI.Config.Loot.AutoConfirm or not RefineUI.Config.Loot.Enable then
		return
	end

	RefineUI:HookOnce("AutoConfirm:StaticPopup_Show", "StaticPopup_Show", function(which)
		if DELETE_DIALOG_LIST[which] then
			AutoConfirm:FillDeleteDialog()
			return
		end

		if CONFIRM_LIST[which] and not InCombatLockdown() then
			local popupIndex = GetShownPopupIndexByWhich(which)
			if popupIndex then
				local button = _G["StaticPopup" .. popupIndex .. "Button1"]
				if button and button:IsShown() and button:IsEnabled() then
					button:Click()
				end
			end
		end
	end)

	RefineUI:RegisterEventCallback("DELETE_ITEM_CONFIRM", function()
		AutoConfirm:FillDeleteDialog()
	end, "AutoConfirm:DELETE_ITEM_CONFIRM")

	RefineUI:RegisterEventCallback("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", function()
		SellCursorItem()
	end, "AutoConfirm:MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")
end
