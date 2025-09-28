local R, C, L = unpack(RefineUI)
if C.automation.autoButton ~= true then return end

----------------------------------------------------------------------------------------
--	AutoButton for quest items (adapted from Elv22) (use macro /click AutoButton)
----------------------------------------------------------------------------------------

-- Initialize quest items ignore table
R.QuestItemsIgnore = R.QuestItemsIgnore or {}

-- Create anchor
local AutoButtonAnchor = CreateFrame("Frame", "AutoButtonAnchor", UIParent)
AutoButtonAnchor:SetPoint(unpack(C.position.autoButton))
AutoButtonAnchor:SetSize(50, 50)

-- Create button
local AutoButton = CreateFrame("Button", "AutoButton", AutoButtonAnchor, "SecureActionButtonTemplate")
AutoButton:SetSize(50, 50)
AutoButton:SetPoint("CENTER", AutoButtonAnchor, "CENTER", 0, 0)
AutoButton:RegisterForClicks("AnyUp", "AnyDown")
AutoButton:SetAttribute("type1", "item")
AutoButton:SetAttribute("type2", "item")
AutoButton:SetAttribute("type3", "macro")

-- Apply RefineUI styling (same as AutoItemBar)
AutoButton:SetTemplate("Default")
if AutoButton.border then
	AutoButton.border:SetFrameStrata("HIGH")
end
AutoButton:StyleButton(true)

-- Behavior tuning (safe defaults if not configured)
local LIMIT_TO_RANGE = C.automation.autoButtonLimitToRange ~= false -- default: true
local RANGE_YARDS = tonumber(C.automation.autoButtonRangeYards) or 200 -- default: 200 yards
local RANGE_SQ = RANGE_YARDS * RANGE_YARDS
local ENABLE_BAG_FALLBACK = C.automation.autoButtonBagFallback == true -- default: off

local function AutoButtonHide()
	AutoButton:SetAlpha(0)
	if not InCombatLockdown() then
		AutoButton:Hide()
		AutoButton:EnableMouse(false)
	else
		AutoButton:RegisterEvent("PLAYER_REGEN_ENABLED")
		AutoButton:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_REGEN_ENABLED" then
				AutoButton:Hide()
				AutoButton:EnableMouse(false)
				AutoButton:UnregisterEvent("PLAYER_REGEN_ENABLED")
			end
		end)
	end
end

local function AutoButtonShow(itemID)
	AutoButton:SetAlpha(1)
	if not InCombatLockdown() then
		AutoButton:Show()
		AutoButton:EnableMouse(true)
		if itemID then
			AutoButton:SetAttribute("item1", "item:" .. itemID)
			AutoButton:SetAttribute("item2", "item:" .. itemID)
		end
	else
		AutoButton:RegisterEvent("PLAYER_REGEN_ENABLED")
		AutoButton:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_REGEN_ENABLED" then
				AutoButton:Show()
				AutoButton:EnableMouse(true)
				if itemID then
					AutoButton:SetAttribute("item1", "item:" .. itemID)
					AutoButton:SetAttribute("item2", "item:" .. itemID)
				end
				AutoButton:UnregisterEvent("PLAYER_REGEN_ENABLED")
			end
		end)
	end
end

-- Initialize as hidden
AutoButton:Hide()
AutoButton:SetAlpha(0)
AutoButton:EnableMouse(false)

-- Texture for our button
AutoButton.t = AutoButton:CreateTexture(nil, "BORDER")
AutoButton.t:SetPoint("TOPLEFT", 2, -2)
AutoButton.t:SetPoint("BOTTOMRIGHT", -2, 2)
AutoButton.t:SetTexCoord(0.1, 0.9, 0.1, 0.9)

-- Count text for our button
AutoButton.c = R.FontString(AutoButton, nil, C.font.cooldownTimers[1], C.font.cooldownTimers[2], C.font.cooldownTimers[3])
AutoButton.c:SetPoint("BOTTOMRIGHT", AutoButton, "BOTTOMRIGHT", -2, 2)

-- Hotkey text for our button
AutoButton.k = R.FontString(AutoButton, nil, C.font.actionBars[1], C.font.actionBars[2], C.font.actionBars[3])
AutoButton.k:SetTextColor(0.7, 0.7, 0.7)
AutoButton.k:SetPoint("TOPRIGHT", AutoButton, "TOPRIGHT", -2, -2)
AutoButton.k:SetJustifyH("RIGHT")
AutoButton.k:SetWidth(AutoButton:GetWidth() - 4)
AutoButton.k:SetWordWrap(false)

local frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	local bind = GetBindingKey("QUEST_BUTTON")
	if bind then
		SetOverrideBinding(AutoButton, false, bind, "CLICK AutoButton:LeftButton")

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
	AutoButton.k:SetText(bind or "")
end)

-- Cooldown
AutoButton.cd = CreateFrame("Cooldown", nil, AutoButton, "CooldownFrameTemplate")
AutoButton.cd:SetAllPoints(AutoButton.t)
AutoButton.cd:SetFrameLevel(1)

local function startScanningBags()
	AutoButtonHide()
	
	-- Helper: should we show for this quest index/id based on range?
	local function ShouldShowForQuest(index, questID)
		if not LIMIT_TO_RANGE then
			return true
		end

		-- Prefer the explicit special-item range API if available
		if IsQuestLogSpecialItemInRange then
			local inRange = IsQuestLogSpecialItemInRange(index)
			-- Some clients return 1/0 instead of true/false
			if inRange == false or inRange == 0 then
				return false
			end
			-- If true/1, we can immediately allow it
			if inRange == true or inRange == 1 then
				return true
			end
			-- If nil, fall through to distance check
		end

		-- Distance gate (approximate)
		if C_QuestLog and C_QuestLog.GetDistanceSqToQuest and questID then
			local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
			if distSq and onContinent ~= nil then
				if not onContinent then
					return false
				end
				return distSq <= RANGE_SQ
			end
		end

		-- If we could not determine, err on the side of hiding
		return false
	end

	-- Scan quest log for special items (primary method)
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader then
			local itemLink, texture, charges = GetQuestLogSpecialItemInfo(index)
			if itemLink then
				local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
				if itemID and not R.QuestItemsIgnore[itemID] then
					local count = C_Item.GetItemCount(itemID)
					
					-- Only show if we actually have the item
					if count > 0 and ShouldShowForQuest(index, info.questID) then
						local itemInfo = C_Item.GetItemInfo(itemID)
						local itemIcon = C_Item.GetItemIconByID(itemID)
						
						if itemInfo and itemIcon then
							-- Set button texture and count
							AutoButton.t:SetTexture(itemIcon)
							AutoButton.c:SetText(count > 1 and count or "")

							-- Set up tooltips
							AutoButton:SetScript("OnEnter", function(self)
								GameTooltip:SetOwner(self, "ANCHOR_LEFT")
								GameTooltip:SetHyperlink(itemLink)
								GameTooltip:AddLine(" ")
								GameTooltip:AddLine("Middle-click to hide temporarily", 0.75, 0.9, 1)
								GameTooltip:Show()
							end)

							AutoButton:SetScript("OnLeave", GameTooltip_Hide)
							AutoButton.id = itemID

							AutoButtonShow(itemID)
							return -- Only show one item at a time
						end
					end
				end
			end
		end
	end
	
	-- Fallback: Check for quest items in bags (optional and range-gated when possible)
	if ENABLE_BAG_FALLBACK then
		for b = 0, NUM_BAG_SLOTS do
			local numSlots = C_Container.GetContainerNumSlots(b)
			for s = 1, numSlots do
				local itemID = C_Container.GetContainerItemID(b, s)
				if itemID and not R.QuestItemsIgnore[itemID] then
					local questInfo = C_Container.GetContainerItemQuestInfo(b, s)
					-- Only consider items that are tied to an active quest so we can range-gate
					if questInfo and questInfo.isQuestItem and questInfo.questID then
						local count = C_Item.GetItemCount(itemID)
						local itemInfo = C_Item.GetItemInfo(itemID)
						local itemIcon = C_Item.GetItemIconByID(itemID)

						if count > 0 and itemInfo and itemIcon then
							-- Use the distance gate against the quest id; fabricate an index for range API
							local ok = true
							if LIMIT_TO_RANGE and C_QuestLog and C_QuestLog.GetDistanceSqToQuest then
								local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questInfo.questID)
								ok = (distSq and onContinent and distSq <= RANGE_SQ) or false
							end

							if ok then
								AutoButton.t:SetTexture(itemIcon)
								AutoButton.c:SetText(count > 1 and count or "")

								AutoButton:SetScript("OnEnter", function(self)
									GameTooltip:SetOwner(self, "ANCHOR_LEFT")
									GameTooltip:SetHyperlink(format("item:%s", itemID))
									GameTooltip:AddLine(" ")
									GameTooltip:AddLine("Middle-click to hide temporarily", 0.75, 0.9, 1)
									GameTooltip:Show()
								end)

								AutoButton:SetScript("OnLeave", GameTooltip_Hide)
								AutoButton.id = itemID

								AutoButtonShow(itemID)
								return -- Only show one item at a time
							end
						end
					end
				end
			end
		end
	end
end

-- Event handler for bag updates and quest changes
local Scanner = CreateFrame("Frame")
Scanner:RegisterEvent("BAG_UPDATE")
Scanner:RegisterEvent("QUEST_LOG_UPDATE")
Scanner:RegisterEvent("QUEST_ACCEPTED")
Scanner:RegisterEvent("QUEST_REMOVED")
Scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
Scanner:RegisterEvent("ZONE_CHANGED")
Scanner:RegisterEvent("ZONE_CHANGED_NEW_AREA")
Scanner:RegisterEvent("ZONE_CHANGED_INDOORS")
Scanner:SetScript("OnEvent", function(self, event, ...)
	-- Small delay to ensure quest data is loaded
	C_Timer.After(0.1, startScanningBags)
end)

-- Expose function for manual testing
R.startScanningBags = startScanningBags

-- Run initial scan when addon loads
C_Timer.After(1, startScanningBags)

-- LibEditMode integration
local LEM = LibStub('LibEditMode')

-- Show a placeholder when in Edit Mode so users can position the frame
if LEM then
    LEM:RegisterCallback('enter', function()
        -- Show the button with a placeholder texture when entering Edit Mode
        if not AutoButton:IsShown() then
            AutoButton.t:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            AutoButton.c:SetText("")
            AutoButton:SetAlpha(0.7)
            AutoButton:Show()
            AutoButton:EnableMouse(true)
            
            -- Add Edit Mode tooltip
            AutoButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText("AutoButton")
                GameTooltip:AddLine("Quest items will appear here", 1, 1, 1)
                GameTooltip:AddLine("Drag to reposition", 0.75, 0.9, 1)
                GameTooltip:Show()
            end)
            
            AutoButton:SetScript("OnLeave", GameTooltip_Hide)
        end
    end)
    
    LEM:RegisterCallback('exit', function()
        -- Hide the placeholder and restore normal function when exiting Edit Mode
        if AutoButton.id then
            -- If we have a real quest item, show it normally
            startScanningBags()
        else
            -- Hide the placeholder
            AutoButtonHide()
        end
    end)
end

local macro = "/run local R = unpack(RefineUI) R.QuestItemsIgnore[AutoButton.id] = true R.startScanningBags() C_Timer.After(0.05, function() AutoButton:SetButtonState('NORMAL') end)"
AutoButton:SetAttribute("macrotext3", macro)

-- Pixel perfect the button
R.PixelSnap(AutoButton)
R.PixelSnap(AutoButtonAnchor)
