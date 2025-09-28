local _E
local oGlow = rawget(_G, "oGlow")
-- Hooks
local displayButtonHook
local frameOnShowHook
local scrollHook

local getID = function(loc)
	-- Handle new ItemLocation table format (modern WoW)
	if type(loc) == "table" then
		-- Check for equipment slot format
		if loc.equipmentSlotIndex then
			if C_Item.DoesItemExist(loc) then
				return C_Item.GetItemLink(loc)
			end
			return nil
		end
		
		-- Check for bag and slot format (used in upgrade UI and other contexts)
		if loc.bagID and loc.slotIndex then
			if C_Item.DoesItemExist(loc) then
				return C_Item.GetItemLink(loc)
			end
			return nil
		end
		
		-- Fallback: try to use the table directly as ItemLocation
		if C_Item.DoesItemExist(loc) then
			return C_Item.GetItemLink(loc)
		end
		return nil
	end
	
	-- Handle legacy integer location format (fallback)
	if type(loc) == "number" then
		local player, bank, bags, voidStorage, slot, bag = EquipmentManager_UnpackLocation(loc)
		if not player and not bank and not bags and not voidStorage then return end

		if not bags then
			if slot then
				return GetInventoryItemLink("player", slot)
			end
		else
			if bag and slot then
				return C_Container.GetContainerItemLink(bag, slot)
			end
		end
	end
	
	return nil
end

local processButton = function(button)
	-- Process only if pipe is enabled, button exists, is shown, and has location data
	if not _E or not button or not button:IsShown() or not button.location then 
		return 
	end
	
	-- Removed check: if button:GetParent() ~= EquipmentFlyoutFrame then return end
	-- This check might have been too strict, especially for the DisplayButton hook

    local location, id = button.location, nil
    
    -- Handle ItemLocation table format (modern WoW)
    if type(location) == "table" then
        -- Handle equipment slot format
        if location.equipmentSlotIndex then
            id = getID(location)
        -- Handle bag and slot format (upgrade UI, bags, etc.)
        elseif location.bagID and location.slotIndex then
            id = getID(location)
        else
            -- Fallback: try any table as ItemLocation
            id = getID(location)
        end
    -- Handle legacy integer location format (fallback) 
    elseif type(location) == "number" and location < EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
        id = getID(location)
    end
    
    -- Debug print for troubleshooting (can be removed later)
    if not id and button.location then
        -- For bag items that might not be loaded yet, try to trigger loading
        if type(button.location) == "table" and button.location.bagID then
            local bagID, slotIndex = button.location.bagID, button.location.slotIndex
            if bagID and slotIndex then
                -- Attempt to get item info to trigger loading
                local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
                if itemID then
                    -- Item is loaded, retry getting the link
                    id = getID(button.location)
                else
                    -- Item not loaded, use ContinueOnItemLoad if available
                    if C_Item and C_Item.ContinueOnItemLoad then
                        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
                        if itemLocation and itemLocation:IsValid() then
                            C_Item.ContinueOnItemLoad(itemLocation, function()
                                -- Retry processing this button once data is loaded
                                local newID = getID(button.location)
                                if newID then
                                    oGlow:CallFilters("char-flyout", button, newID)
                                end
                            end)
                        end
                    end
                end
            end
        end
    end

	oGlow:CallFilters("char-flyout", button, _E and id)
end

-- Processes all currently visible buttons in the flyout
local processFlyout = function()
	if not _E or not EquipmentFlyoutFrame or not EquipmentFlyoutFrame:IsShown() then return end

	if EquipmentFlyoutFrame.buttons then
		for _, button in ipairs(EquipmentFlyoutFrame.buttons) do
			if button:IsShown() then
				processButton(button) -- Process each visible button
			end
		end
	end
end

-- Update function with delay, called by frame/scroll hooks
local updateWithDelay = function()
	C_Timer.After(0.1, processFlyout) -- Delay allows frame state to settle
end

local enable = function(self)
	_E = true

	-- 1. Hook individual button display (for initial creation)
	if not displayButtonHook then
		displayButtonHook = function(button)
			-- No delay needed, process this specific button immediately
			if _E then processButton(button) end 
		end
		hooksecurefunc("EquipmentFlyout_DisplayButton", displayButtonHook)
	end

	-- Attempt to hook frame events only if the frame exists
	if EquipmentFlyoutFrame then
		-- 2. Hook the frame's OnShow event
		if not frameOnShowHook then
			frameOnShowHook = true -- Mark as hooked
			EquipmentFlyoutFrame:HookScript("OnShow", function()
				if _E then updateWithDelay() end
			end)
		end

		-- 3. Hook the scrollbar value changing
		if EquipmentFlyoutFrame.ScrollFrame and EquipmentFlyoutFrame.ScrollFrame.ScrollBar then
			if not scrollHook then
				scrollHook = true -- Mark as hooked
				EquipmentFlyoutFrame.ScrollFrame.ScrollBar:HookScript("OnValueChanged", function()
					if _E then updateWithDelay() end
				end)
			end
		end
	end
end

local disable = function(self)
	_E = nil
	-- Proper unhooking would go here if needed
end

-- Register the pipe
oGlow:RegisterPipe("char-flyout", enable, disable, updateWithDelay, "Character equipment flyout frame")