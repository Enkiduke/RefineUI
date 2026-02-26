local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
--	AutoButton Module for RefineUI
----------------------------------------------------------------------------------------

local AutoButton = RefineUI:RegisterModule("AutoButton")

-- Locals
local gsub = string.gsub
local format = string.format
local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4

RefineUI.QuestItemsIgnore = RefineUI.QuestItemsIgnore or {}

function AutoButton:UpdateButtonCooldown()
	if not self.frame or not self.activeBag or not self.activeSlot then return end
	local startTime, duration, enabled = C_Container.GetContainerItemCooldown(self.activeBag, self.activeSlot)
	CooldownFrame_Set(self.frame.cd, startTime or 0, duration or 0, enabled or 0)
end

function AutoButton:HideButton()
	self.activeBag = nil
	self.activeSlot = nil
	self.frame:SetAlpha(0)
	CooldownFrame_Set(self.frame.cd, 0, 0, 0)
	if not InCombatLockdown() then
		self.frame:EnableMouse(false)
	else
		RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
			self.frame:EnableMouse(false)
			RefineUI:OffEvent("PLAYER_REGEN_ENABLED", "AutoButton:HideOnExitCombat")
		end, "AutoButton:HideOnExitCombat")
	end
end

function AutoButton:ShowButton(item)
	self.frame:SetAlpha(1)
	if not InCombatLockdown() then
		self.frame:EnableMouse(true)
		if item then
			self.frame:SetAttribute("item", item)
		end
	else
		RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
			self.frame:EnableMouse(true)
			if item then
				self.frame:SetAttribute("item", item)
			end
			RefineUI:OffEvent("PLAYER_REGEN_ENABLED", "AutoButton:ShowOnExitCombat")
		end, "AutoButton:ShowOnExitCombat")
	end
end

function AutoButton:UpdateBindings()
	local bind = GetBindingKey("QUEST_BUTTON")
	if bind then
		SetOverrideBinding(self.frame, false, bind, "CLICK AutoButton:LeftButton")

		bind = gsub(bind, "(ALT%-)", "A")
		bind = gsub(bind, "(CTRL%-)", "C")
		bind = gsub(bind, "(SHIFT%-)", "S")
		bind = gsub(bind, "(Mouse Button )", "M")
		bind = gsub(bind, KEY_BUTTON3, "M3")
		bind = gsub(bind, KEY_PAGEUP, "PU")
		bind = gsub(bind, KEY_PAGEDOWN, "PD")
		bind = gsub(bind, KEY_SPACE, "SpB")
		bind = gsub(bind, KEY_INSERT, "Ins")
		bind = gsub(bind, KEY_HOME, "Hm")
		bind = gsub(bind, KEY_DELETE, "Del")
		bind = gsub(bind, KEY_NUMPADDECIMAL, "Nu.")
		bind = gsub(bind, KEY_NUMPADDIVIDE, "Nu/")
		bind = gsub(bind, KEY_NUMPADMINUS, "Nu-")
		bind = gsub(bind, KEY_NUMPADMULTIPLY, "Nu*")
		bind = gsub(bind, KEY_NUMPADPLUS, "Nu+")
		bind = gsub(bind, KEY_NUMLOCK, "NuL")
		bind = gsub(bind, KEY_MOUSEWHEELDOWN, "MWD")
		bind = gsub(bind, KEY_MOUSEWHEELUP, "MWU")
	end
	self.frame.k:SetText(bind or "")
end

function AutoButton:StartScanning()
	self:HideButton()
	-- Scan bags for quest items
	for b = 0, NUM_BAG_SLOTS do
		for s = 1, C_Container.GetContainerNumSlots(b) do
			local itemID = C_Container.GetContainerItemID(b, s)
			if itemID then
				local questInfo = C_Container.GetContainerItemQuestInfo(b, s)
				local isQuestItem = questInfo and (questInfo.isQuestItem or questInfo.questID)
				
				if isQuestItem and not RefineUI.QuestItemsIgnore[itemID] then
					local itemInfo = C_Item.GetItemInfo(itemID)
					local count = C_Item.GetItemCount(itemID)
					local itemIcon = C_Item.GetItemIconByID(itemID)

					if itemInfo and itemIcon then
						self.frame.t:SetTexture(itemIcon)

						if count and count > 1 then
							self.frame.c:SetText(count)
						else
							self.frame.c:SetText("")
						end

						self.activeBag = b
						self.activeSlot = s
						self:UpdateButtonCooldown()

						self.frame.id = itemID
						self:ShowButton(itemInfo)
						return
					end
				end
			end
		end
	end
end

function AutoButton:OnEnable()
	if not RefineUI.Config.Automation.AutoButton.Enable then return end
    
    local pos = RefineUI.Positions["RefineUI_AutoButton"] or {"BOTTOM", UIParent, "BOTTOM", 0, 200}
	local anchor = CreateFrame("Frame", "RefineUI_AutoButton", UIParent)
	RefineUI.Point(anchor, unpack(pos))
	RefineUI.Size(anchor, 40, 40)
	self.anchor = anchor

	local button = CreateFrame("Button", "AutoButton", UIParent, "SecureActionButtonTemplate")
	RefineUI.Size(button, 40, 40)
	RefineUI.Point(button, "CENTER", anchor, "CENTER", 0, 0)
	RefineUI.SetTemplate(button, "Overlay")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type1", "item")
	button:SetAttribute("type2", "item")
	button:SetAttribute("type3", "macro")
    
	button.t = button:CreateTexture(nil, "BORDER")
	RefineUI.SetInside(button.t)
	button.t:SetTexCoord(0.1, 0.9, 0.1, 0.9)

	button.c = button:CreateFontString(nil, "OVERLAY")
	RefineUI.Point(button.c, "BOTTOMRIGHT", 1, -2)
	RefineUI.Font(button.c, 12)

	button.k = button:CreateFontString(nil, "OVERLAY")
	button.k:SetTextColor(0.7, 0.7, 0.7)
	RefineUI.Point(button.k, "TOPRIGHT", 0, -2)
	button.k:SetJustifyH("RIGHT")
	button.k:SetWidth(button:GetWidth() - 1)
	button.k:SetWordWrap(false)
	RefineUI.Font(button.k, 10)

	button.cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cd:SetAllPoints(button.t)
	button.cd:SetFrameLevel(1)

	self.frame = button

	-- Internal scripts
	button:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink(format("item:%s", s.id))
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Middle-click to hide temporarily", 0.75, 0.9, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	local macro = "/run RefineUI.QuestItemsIgnore[AutoButton.id] = true; RefineUI:CallModule('AutoButton'):StartScanning(); C_Timer.After(0.05, function() AutoButton:SetButtonState('NORMAL') end)"
	button:SetAttribute("macrotext3", macro)

	-- Events
    RefineUI:RegisterEventCallback("BAG_UPDATE", function() self:StartScanning() end, "AutoButton:BagUpdate")
    RefineUI:RegisterEventCallback("BAG_UPDATE_COOLDOWN", function() self:UpdateButtonCooldown() end, "AutoButton:BagCooldown")
    RefineUI:RegisterEventCallback("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then self:StartScanning() end
    end, "AutoButton:InventoryChanged")
    
    RefineUI:RegisterEventCallback("UPDATE_BINDINGS", function() self:UpdateBindings() end, "AutoButton:Bindings")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function() 
        self:UpdateBindings()
        self:StartScanning()
    end, "AutoButton:EnteringWorld")

	self:HideButton()
end
