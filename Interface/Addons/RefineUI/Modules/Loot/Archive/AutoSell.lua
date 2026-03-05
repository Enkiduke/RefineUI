local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
--	Auto Sell Low iLevel Gear at Merchants
----------------------------------------------------------------------------------------
local AutoSell = RefineUI:RegisterModule("AutoSell")

-- Locals
local CreateFrame = CreateFrame
local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local MerchantFrame = MerchantFrame
local GameTooltip = GameTooltip
local MenuUtil = MenuUtil
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local GetCursorInfo = GetCursorInfo
local format = string.format
local tonumber = tonumber
local wipe = wipe
local tinsert = tinsert
local tremove = tremove
local pairs = pairs

local SELL_DELAY = 0.05
local sellQueue = {}
local isSelling = false
local sellTimer = nil
local settingsButtonCreated = false
local ilvlPopup = nil

-- SavedVariables initialization
RefineUIAutoSellDB = RefineUIAutoSellDB or { AlwaysSell = {} }

----------------------------------------------------------------------------------------
--	Helper Functions
----------------------------------------------------------------------------------------
local itemIDPattern = "item:(%d+):"
local function GetItemIDFromLink(link)
	if not link then return nil end
	local match = string.match(link, itemIDPattern)
	return match and tonumber(match)
end

-- Cache protected item IDs (ID based)
local function GetProtectedItemIDs()
	local protectedIDs = {}
	local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
	if not setIDs then return protectedIDs end
	
	for _, setID in ipairs(setIDs) do
		local itemIDs = C_EquipmentSet.GetItemIDs(setID)
		if itemIDs then
			for _, itemID in pairs(itemIDs) do
				if itemID and itemID > 0 then
					protectedIDs[itemID] = true
				end
			end
		end
	end
	return protectedIDs
end

----------------------------------------------------------------------------------------
--	iLevel Threshold Popup
----------------------------------------------------------------------------------------
local function CreateIlvlThresholdPopup()
	if ilvlPopup then return ilvlPopup end

	ilvlPopup = CreateFrame("Frame", "RefineUI_AutoSellIlvlPopup", UIParent, "DialogBoxFrame")
	ilvlPopup:SetSize(320, 130)
	ilvlPopup:SetPoint("CENTER")
	ilvlPopup:SetFrameStrata("DIALOG")
	ilvlPopup:EnableMouse(true)
	ilvlPopup:SetMovable(true)
	ilvlPopup:RegisterForDrag("LeftButton")
	ilvlPopup:SetScript("OnDragStart", ilvlPopup.StartMoving)
	ilvlPopup:SetScript("OnDragStop", ilvlPopup.StopMovingOrSizing)
	ilvlPopup:Hide()

	if ilvlPopup.OkayButton then ilvlPopup.OkayButton:Hide() end
	if ilvlPopup.CancelButton then ilvlPopup.CancelButton:Hide() end

	local title = ilvlPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText("Set AutoSell iLevel Threshold")

	local label = ilvlPopup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", 20, -50)
	label:SetText("Sell items below iLevel:")

	local editBox = CreateFrame("EditBox", nil, ilvlPopup, "InputBoxTemplate")
	editBox:SetPoint("LEFT", label, "RIGHT", 10, 0)
	editBox:SetSize(60, 30)
	editBox:SetNumeric(true)
	editBox:SetMaxLetters(4)
	editBox:SetAutoFocus(true)
	editBox:SetJustifyH("CENTER")
	ilvlPopup.editBox = editBox

	local okButton = CreateFrame("Button", nil, ilvlPopup, "UIPanelButtonTemplate")
	okButton:SetSize(80, 25)
	okButton:SetPoint("BOTTOMRIGHT", ilvlPopup, "BOTTOMRIGHT", -15, 15)
	okButton:SetText("OK")
	okButton:SetScript("OnClick", function()
		local value = tonumber(ilvlPopup.editBox:GetText())
		if value and value >= 0 then
			RefineUI.Config.Loot.AutoSellIlvlThreshold = value
			RefineUI:Print(format("AutoSell iLevel Threshold set to: %d", value))
			PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
			ilvlPopup:Hide()
		else
			RefineUI:Print("Invalid iLevel Threshold")
		end
	end)

	local cancelButton = CreateFrame("Button", nil, ilvlPopup, "UIPanelButtonTemplate")
	cancelButton:SetSize(80, 25)
	cancelButton:SetPoint("RIGHT", okButton, "LEFT", -5, 0)
	cancelButton:SetText("Cancel")
	cancelButton:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
		ilvlPopup:Hide()
	end)

	ilvlPopup:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
			self:Hide()
		end
	end)
	ilvlPopup:SetPropagateKeyboardInput(true)

	return ilvlPopup
end

local function ShowIlvlThresholdPopup()
	local popup = CreateIlvlThresholdPopup()
	popup.editBox:SetText(tostring(RefineUI.Config.Loot.AutoSellIlvlThreshold or 0))
	popup:Show()
	popup.editBox:SetFocus()
end

----------------------------------------------------------------------------------------
--	Settings Panel (Custom Floating Panel)
----------------------------------------------------------------------------------------
local settingsPanel = nil

-- Get the player's average equipped item level
local function GetPlayerAverageIlvl()
	local _, equipped = GetAverageItemLevel()
	return math.floor(equipped or 0)
end

-- Calculate threshold as percentage of current ilvl
local function GetThresholdFromPercent(percent)
	local ilvl = GetPlayerAverageIlvl()
	return math.floor(ilvl * (percent / 100))
end

local function UpdateThresholdDisplay()
	if not settingsPanel then return end
	local threshold = RefineUI.Config.Loot.AutoSellIlvlThreshold or 0
	local playerIlvl = GetPlayerAverageIlvl()

	local percent
	if threshold < 1 then
		percent = math.floor(threshold * 100)
		if settingsPanel.thresholdEdit then
			settingsPanel.thresholdEdit:SetText(tostring(math.floor(playerIlvl * threshold)))
		end
	else
		percent = playerIlvl > 0 and math.floor((threshold / playerIlvl) * 100) or 0
		if settingsPanel.thresholdEdit then
			settingsPanel.thresholdEdit:SetText(tostring(threshold))
		end
	end

	if settingsPanel.percentText then
		settingsPanel.percentText:SetText(format("~%d%%", percent))
	end
end

local function CreateSettingsPanel()
	if settingsPanel then return settingsPanel end

	-- Use WoW's native BasicFrameTemplateWithInset for RPG styling
	local panel = CreateFrame("Frame", "RefineUI_AutoSellPanel", UIParent, "BasicFrameTemplateWithInset")
	panel:SetSize(240, 135)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()

	-- Title (use the template's title text)
	panel.TitleText:SetText("AutoSell Settings")

	-- Close button is automatically provided by template

	-- Equipment checkbox
	local equipCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	equipCheck:SetSize(24, 24)
	equipCheck:SetPoint("TOPLEFT", 10, -32)
	equipCheck:SetChecked(RefineUI.Config.Loot.AutoSellOnlyEquipment)
	equipCheck:SetScript("OnClick", function(self)
		RefineUI.Config.Loot.AutoSellOnlyEquipment = self:GetChecked()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	panel.equipCheck = equipCheck
	
	local equipLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	equipLabel:SetPoint("LEFT", equipCheck, "RIGHT", 2, 0)
	equipLabel:SetText("Sell Only Equipment")

	-- Ignore Equipment Sets checkbox
	local ignoreSetCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	ignoreSetCheck:SetSize(24, 24)
	ignoreSetCheck:SetPoint("TOPLEFT", equipCheck, "BOTTOMLEFT", 0, 4)
	ignoreSetCheck:SetChecked(RefineUI.Config.Loot.AutoSellIgnoreEquipmentSets)
	ignoreSetCheck:SetScript("OnClick", function(self)
		RefineUI.Config.Loot.AutoSellIgnoreEquipmentSets = self:GetChecked()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	panel.ignoreSetCheck = ignoreSetCheck
	
	local ignoreSetLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ignoreSetLabel:SetPoint("LEFT", ignoreSetCheck, "RIGHT", 2, 0)
	ignoreSetLabel:SetText("Ignore Equipment Sets")

	-- iLevel threshold row
	local ilvlLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ilvlLabel:SetPoint("TOPLEFT", 12, -84)
	ilvlLabel:SetText("iLvl:")

	-- -10% button
	local minusBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minusBtn:SetSize(40, 22)
	minusBtn:SetPoint("LEFT", ilvlLabel, "RIGHT", 6, 0)
	minusBtn:SetText("-10%")
	minusBtn:SetScript("OnClick", function()
		local playerIlvl = GetPlayerAverageIlvl()
		local current = RefineUI.Config.Loot.AutoSellIlvlThreshold or 0
		local currentPercent
		if current < 1 then
			currentPercent = math.floor(current * 100)
		else
			currentPercent = playerIlvl > 0 and math.floor((current / playerIlvl) * 100) or 70
		end
		local newPercent = math.max(10, currentPercent - 10)
		RefineUI.Config.Loot.AutoSellIlvlThreshold = GetThresholdFromPercent(newPercent)
		UpdateThresholdDisplay()
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	end)

	-- Threshold EditBox
	local thresholdEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	thresholdEdit:SetSize(50, 20)
	thresholdEdit:SetPoint("LEFT", minusBtn, "RIGHT", 8, 0)
	thresholdEdit:SetNumeric(true)
	thresholdEdit:SetMaxLetters(4)
	thresholdEdit:SetJustifyH("CENTER")
	thresholdEdit:SetAutoFocus(false)
	thresholdEdit:SetScript("OnEnterPressed", function(self)
		local value = tonumber(self:GetText())
		if value and value >= 0 then
			RefineUI.Config.Loot.AutoSellIlvlThreshold = value
			UpdateThresholdDisplay()
			PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		end
		self:ClearFocus()
	end)
	thresholdEdit:SetScript("OnEscapePressed", function(self)
		UpdateThresholdDisplay()
		self:ClearFocus()
	end)
	panel.thresholdEdit = thresholdEdit

	-- +10% button
	local plusBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plusBtn:SetSize(40, 22)
	plusBtn:SetPoint("LEFT", thresholdEdit, "RIGHT", 8, 0)
	plusBtn:SetText("+10%")
	plusBtn:SetScript("OnClick", function()
		local playerIlvl = GetPlayerAverageIlvl()
		local current = RefineUI.Config.Loot.AutoSellIlvlThreshold or 0
		local currentPercent
		if current < 1 then
			currentPercent = math.floor(current * 100)
		else
			currentPercent = playerIlvl > 0 and math.floor((current / playerIlvl) * 100) or 70
		end
		local newPercent = math.min(100, currentPercent + 10)
		RefineUI.Config.Loot.AutoSellIlvlThreshold = GetThresholdFromPercent(newPercent)
		UpdateThresholdDisplay()
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
	end)

	-- Percent display
	local percentText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	percentText:SetPoint("LEFT", plusBtn, "RIGHT", 6, 0)
	percentText:SetText("~0%")
	percentText:SetTextColor(0.7, 0.7, 0.7)
	panel.percentText = percentText

	-- ESC to close
	tinsert(UISpecialFrames, "RefineUI_AutoSellPanel")

	settingsPanel = panel
	return panel
end

local function ToggleSettingsPanel()
	local panel = CreateSettingsPanel()
	if panel:IsShown() then
		panel:Hide()
	else
		-- Update checkbox states
		if panel.equipCheck then
			panel.equipCheck:SetChecked(RefineUI.Config.Loot.AutoSellOnlyEquipment)
		end
		if panel.ignoreSetCheck then
			panel.ignoreSetCheck:SetChecked(RefineUI.Config.Loot.AutoSellIgnoreEquipmentSets)
		end
		UpdateThresholdDisplay()
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 5, 0)
		panel:Show()
	end
end

function AutoSell:ToggleSettingsPanel()
	ToggleSettingsPanel()
end

local function CreateSettingsButton()
	local button = CreateFrame("Button", "RefineUI_AutoSellSettingsButton", MerchantFrame)
	button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -20, 3)
	button:SetSize(32, 32)
	button:SetFrameStrata("HIGH")

	local icon = button:CreateTexture(nil, "OVERLAY")
	icon:SetAtlas("GM-icon-settings", true)
	icon:SetAllPoints(button)
	button.Icon = icon

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("AutoSell Settings", 1, 1, 1)
		GameTooltip:Show()
		self.Icon:SetVertexColor(1, 1, 0.5)
	end)

	button:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self.Icon:SetVertexColor(1, 1, 1)
	end)

	button:SetScript("OnClick", ToggleSettingsPanel)
end

----------------------------------------------------------------------------------------
--	Sell Queue Processing
----------------------------------------------------------------------------------------
local function ProcessSellQueue()
	if #sellQueue == 0 then
		isSelling = false
		if sellTimer then
			sellTimer:Cancel()
			sellTimer = nil
		end
		return
	end

	if not MerchantFrame:IsShown() or GetCursorInfo() then
		RefineUI:Print("AutoSell interrupted.")
		wipe(sellQueue)
		isSelling = false
		if sellTimer then
			sellTimer:Cancel()
			sellTimer = nil
		end
		return
	end

	local item = tremove(sellQueue, 1)
	if item then
		RefineUI:Print(format("Selling %s (ilvl: %d)", item.link or "Unknown", item.ilvl or 0))
		C_Container.UseContainerItem(item.bag, item.slot)
	end

	sellTimer = C_Timer.After(SELL_DELAY, ProcessSellQueue)
end

function AutoSell:OnMerchantShow()
	if isSelling then return end

	wipe(sellQueue)

	local ilvlThreshold = self:GetAutoSellThreshold()
	local sellOnlyEquipment = RefineUI.Config.Loot.AutoSellOnlyEquipment
	local ignoreEquipmentSets = RefineUI.Config.Loot.AutoSellIgnoreEquipmentSets
	local alwaysSellList = RefineUIAutoSellDB.AlwaysSell or {}

	-- Cache protected item IDs if enabled
	local protectedItemIDs = nil
	if ignoreEquipmentSets then
		protectedItemIDs = GetProtectedItemIDs()
	end

	for bag = 0, Enum.BagIndex.ReagentBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemLink = C_Container.GetContainerItemLink(bag, slot)
			if itemLink then
				local itemName, _, itemQuality, itemLevelBasic, _, itemType, _, _, _, _, itemSellPrice
				if C_Item and C_Item.GetItemInfo then
					itemName, _, itemQuality, itemLevelBasic, _, itemType, _, _, _, _, itemSellPrice = C_Item.GetItemInfo(itemLink)
				end
				
				local detailedItemLevel
				if C_Item and C_Item.GetDetailedItemLevelInfo then
					detailedItemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
				end
				local effectiveIlvl = detailedItemLevel or itemLevelBasic or 0
				local itemID = GetItemIDFromLink(itemLink)

				if itemSellPrice and itemSellPrice > 0 then
					local isAlwaysSell = itemID and alwaysSellList[itemID]

					if isAlwaysSell then
						tinsert(sellQueue, { bag = bag, slot = slot, link = itemLink, ilvl = effectiveIlvl })
					else
						local shouldCheckIlvl = true

						if sellOnlyEquipment and not (itemType == "Armor" or itemType == "Weapon") then
							shouldCheckIlvl = false
						end

						-- Check if item is in an equipment set (by ID)
						if shouldCheckIlvl and ignoreEquipmentSets and protectedItemIDs and protectedItemIDs[itemID] then
							shouldCheckIlvl = false
						end

						if shouldCheckIlvl and effectiveIlvl > 0 and effectiveIlvl < ilvlThreshold then
							tinsert(sellQueue, { bag = bag, slot = slot, link = itemLink, ilvl = effectiveIlvl })
						end
					end
				end
			end
		end
	end

	if #sellQueue > 0 then
		isSelling = true
		ProcessSellQueue()
	end
end

local function OnMerchantClosed()
	if isSelling then
		RefineUI:Print("AutoSell stopped.")
		wipe(sellQueue)
		isSelling = false
		if sellTimer then
			sellTimer:Cancel()
			sellTimer = nil
		end
	end
end

----------------------------------------------------------------------------------------
--	Slash Commands
----------------------------------------------------------------------------------------
local function SetupSlashCommands()
	SLASH_AUTOSELL1 = "/as"
	SlashCmdList["AUTOSELL"] = function(msg)
		msg = msg:trim()
		local command, rest = msg:match("^(%S+)%s*(.*)$")
		command = command and command:lower() or ""

		if command == "add" and rest ~= "" then
			local itemID = GetItemIDFromLink(rest)
			if itemID then
				RefineUIAutoSellDB.AlwaysSell[itemID] = true
				RefineUI:Print(format("Added %s to Always Sell list.", rest))
			else
				RefineUI:Print("Invalid item link.")
			end
		elseif command == "remove" and rest ~= "" then
			local itemID = GetItemIDFromLink(rest)
			if itemID and RefineUIAutoSellDB.AlwaysSell[itemID] then
				RefineUIAutoSellDB.AlwaysSell[itemID] = nil
				RefineUI:Print(format("Removed ID %d from Always Sell list.", itemID))
			else
				RefineUI:Print("Item not found in list.")
			end
		elseif command == "list" then
			RefineUI:Print("Always Sell List:")
			local count = 0
			for itemID in pairs(RefineUIAutoSellDB.AlwaysSell) do
				local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
				RefineUI:Print(format("  - %s (ID: %d)", name or "Unknown", itemID))
				count = count + 1
			end
			if count == 0 then
				RefineUI:Print("  List is empty.")
			end
		else
			RefineUI:Print("/as add [item link] - Add to list")
			RefineUI:Print("/as remove [item link] - Remove from list")
			RefineUI:Print("/as list - Show list")
		end
	end
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoSell:OnEnable()
	if not RefineUI.Config.Loot.AutoSell or not RefineUI.Config.Loot.Enable then
		return
	end

	RefineUIAutoSellDB = RefineUIAutoSellDB or { AlwaysSell = {} }

	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("MERCHANT_SHOW")
	eventFrame:RegisterEvent("MERCHANT_CLOSED")
	eventFrame:SetScript("OnEvent", function(_, event)
		if event == "MERCHANT_SHOW" then
			C_Timer.After(0.2, function()
				if MerchantFrame:IsShown() then
					if not settingsButtonCreated then
						CreateSettingsButton()
						settingsButtonCreated = true
					end
					AutoSell:OnMerchantShow()
				end
			end)
		elseif event == "MERCHANT_CLOSED" then
			OnMerchantClosed()
		end
	end)

	SetupSlashCommands()
end

-- Helper to get effective threshold (handles percentage vs fixed)
function AutoSell:GetAutoSellThreshold()
	local val = RefineUI.Config.Loot.AutoSellIlvlThreshold or 0
	if val < 1 then -- Percentage mode
		local _, equipped = GetAverageItemLevel()
		return math.floor((equipped or 0) * val)
	else
		return val
	end
end

