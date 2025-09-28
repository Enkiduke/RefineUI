----------------------------------------------------------------------------------------
--	AutoItemBar Module for RefineUI
--	This module creates an automatic item bar for consumables,
--	with mouseover functionality and dynamic updating.
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

if not C.autoitembar.enable then return end

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------
local BUTTON_SIZE = C.autoitembar.buttonSize
local BUTTON_SPACING = C.autoitembar.buttonSpace
local BUTTONS_PER_ROW = 12

-- Define NUM_BAG_SLOTS constant if not available
local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4

local frameWidth = BUTTONS_PER_ROW * (BUTTON_SIZE + BUTTON_SPACING) - BUTTON_SPACING
local frameHeight = (BUTTON_SIZE + BUTTON_SPACING) - BUTTON_SPACING

----------------------------------------------------------------------------------------
--	Frame Creation
----------------------------------------------------------------------------------------

-- Create a frame to hold our consumable buttons
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local After = C_Timer.After

local ConsumableButtonsFrame = CreateFrame("Frame", "RefineUI_AutoItemBar", UIParent)
ConsumableButtonsFrame:SetPoint(unpack(C.position.autoitembar))
ConsumableButtonsFrame:SetSize(frameWidth, frameHeight)

-- Remove background styling - just a transparent container
-- ConsumableButtonsFrame:SetTemplate("Transparent")

local ConsumableBarParent = CreateFrame("Frame", "ConsumableBarParent", UIParent)
ConsumableBarParent:SetPoint(unpack(C.position.autoitembar))
ConsumableBarParent:SetSize(frameWidth, frameHeight + 10) -- Add some extra height for mouseover area
ConsumableBarParent:SetFrameLevel(ConsumableButtonsFrame:GetFrameLevel() + 1)
-- Hover-only helper frame; never intercept clicks
ConsumableBarParent:SetFrameStrata("BACKGROUND")
ConsumableBarParent:EnableMouse(false)

----------------------------------------------------------------------------------------
--	Local Variables
----------------------------------------------------------------------------------------
C.autoitembar = C.autoitembar or {}
local consumableButtons = {}
local currentConsumables = {}
local itemLocationById = {}

-- local refs and enums for faster access
local floor = math.floor
local ceil = math.ceil
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tsort = table.sort
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemIconByID = C_Item.GetItemIconByID

local Container = C_Container
local GetContainerNumSlots = Container.GetContainerNumSlots
local GetContainerItemID = Container.GetContainerItemID
local GetContainerItemInfo = Container.GetContainerItemInfo
local GetContainerItemCooldown = Container.GetContainerItemCooldown

local allowedClass = {
	[Enum.ItemClass.Consumable] = true,
	[Enum.ItemClass.ItemEnhancement] = true,
	-- Also allow string matches as fallback
	["Consumable"] = true,
	["ItemEnhancement"] = true,
}

-- Debug print for enum values (remove these when working)
-- print("AutoItemBar: Enum.ItemClass.Consumable =", Enum.ItemClass.Consumable)
-- print("AutoItemBar: Enum.ItemClass.ItemEnhancement =", Enum.ItemClass.ItemEnhancement)
-- print("AutoItemBar: allowedClass table:", allowedClass)

-- We intentionally avoid subclass filtering to reduce API fragility across versions

----------------------------------------------------------------------------------------
--	Helper Functions
---------------------------------------------------------- ------------------------------
-- Build an item token suitable for secure item usage
local function getItemUseToken(itemID)
    local name, link = GetItemInfo(itemID)
    if link then return link end
    if name then return name end
    return nil
end

-- Assign secure click action for a button to use the item
local function assignUseAction(button, itemID, loc)
    if InCombatLockdown() then return end
    -- Use item by ID; reliable across bag changes
    local macro = string.format("/use item:%d", itemID)
    if button._attrMode ~= "macro" or button._attrToken ~= macro then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macro)
        button._attrMode = "macro"
        button._attrToken = macro
        button:EnableMouse(true)
    end
end
local function isConsumable(itemID)
	-- Use GetItemInfo to get the proper class ID 
	local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID = GetItemInfo(itemID)
	
	-- Check both numeric classID and string itemType
	local isAllowed = allowedClass[classID] or allowedClass[itemType]
	
	-- If neither worked, try GetItemInfoInstant 
	if not isAllowed then
		local _, alternateClassID = GetItemInfoInstant(itemID)
		isAllowed = allowedClass[alternateClassID]
	end
	
	if not isAllowed then 
		return false 
	end

	-- Only check item level if configured
	if C.autoitembar.min_consumable_item_level and C.autoitembar.min_consumable_item_level > 0 then
		if not itemLevel or itemLevel < C.autoitembar.min_consumable_item_level then
			return false
		end
	end

	return true
end

local function ShowBar()
    -- Use smooth fade in from core API
    R.FadeIn(ConsumableButtonsFrame, 0.2)
end

local function HideBar()
    if C.autoitembar.consumable_mouseover then
        -- Use smooth fade out from core API
        R.FadeOut(ConsumableButtonsFrame, 0.3)
    end
end

local function UpdateBarVisibility()
    if C.autoitembar.consumable_mouseover then
        ConsumableButtonsFrame:SetAlpha(0)
    else
        ConsumableButtonsFrame:SetAlpha(1)
    end
end

----------------------------------------------------------------------------------------
--	Button Creation and Management
----------------------------------------------------------------------------------------
local function createConsumableButton(itemID, index)
	local button = CreateFrame("Button", "ConsumableButton" .. index, ConsumableButtonsFrame, "SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

	-- Calculate button position
	local row = floor((index - 1) / BUTTONS_PER_ROW)
	local col = (index - 1) % BUTTONS_PER_ROW
	local xOffset = col * (BUTTON_SIZE + BUTTON_SPACING)
	local yOffset = -row * (BUTTON_SIZE + BUTTON_SPACING)

	button:SetPoint("TOPLEFT", xOffset, yOffset)
	button:SetFrameStrata("HIGH")
	
	-- Apply RefineUI styling to individual buttons (restore this)
	button:SetTemplate("Default")
	if button.border then
		button.border:SetFrameStrata("HIGH")
	end
	button:StyleButton(true)
	
    button:RegisterForClicks("AnyDown", "AnyUp")
	-- Initial assignment; will be refreshed during bag scans
	assignUseAction(button, itemID, nil)

	-- Create button textures and fonts
	button.t = button:CreateTexture(nil, "BORDER")
	button.t:SetPoint("TOPLEFT", 2, -2)
	button.t:SetPoint("BOTTOMRIGHT", -2, 2)
	button.t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	button.t:SetTexture(GetItemIconByID(itemID))

	button.count = button:CreateFontString(nil, "OVERLAY")
	button.count:SetFont(unpack(C.font.actionBars))
	button.count:SetShadowOffset(1, -1)
	button.count:SetPoint("BOTTOMRIGHT", -1, 3)
	button.count:SetJustifyH("RIGHT")

    button.cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cd:SetAllPoints(button.t)
    button.cd:SetFrameLevel(1)
    if button.cd.EnableMouse then button.cd:EnableMouse(false) end

	button.itemID = itemID
	button._row = row
	button._col = col
	button._lastCountText = nil
	button._lastCooldownStart = nil
	button._lastCooldownDuration = nil
	button._attrMode = nil
	button._attrToken = nil

	-- Set up scripts for mouseover functionality (bind once)
	button:SetScript("OnEnter", function(self)
		ShowBar()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink("item:" .. self.itemID)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip_Hide()
		C_Timer.After(0.1, function()
			if not ConsumableBarParent:IsMouseOver() and not ConsumableButtonsFrame:IsMouseOver() then
				HideBar()
			end
		end)
	end)

	return button
end

local function sortConsumables(a, b)
	local _, classA, subA = GetItemInfoInstant(a)
	local _, classB, subB = GetItemInfoInstant(b)
	if classA == classB then
		if subA == subB then
			return a < b
		else
			return (subA or 0) < (subB or 0)
		end
	else
		return (classA or 0) < (classB or 0)
	end
end

-- Reusable tables to reduce GC pressure
local reusableCounts, reusableSorted = {}, {}

local function updateConsumableButtons()
    wipe(currentConsumables)
    local consumableCount = reusableCounts
    local sortedConsumables = reusableSorted
    wipe(consumableCount)
    wipe(sortedConsumables)

    -- Scan bags for consumables
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID = GetContainerItemID(bag, slot)
            if itemID and isConsumable(itemID) then
                if not currentConsumables[itemID] then
                    tinsert(sortedConsumables, itemID)
                end
                currentConsumables[itemID] = true
                itemLocationById[itemID] = { bag = bag, slot = slot }

                local info = GetContainerItemInfo(bag, slot)
                local count = info and info.stackCount or 0
                consumableCount[itemID] = (consumableCount[itemID] or 0) + count
            end
        end
    end

    -- Sort the consumables
    tsort(sortedConsumables, sortConsumables)

    -- Create or update buttons based on the sorted list
    for index, itemID in ipairs(sortedConsumables) do
        if not consumableButtons[itemID] then
            consumableButtons[itemID] = createConsumableButton(itemID, index)
        end

        local button = consumableButtons[itemID]
        
        -- Update button position
        local row = floor((index - 1) / BUTTONS_PER_ROW)
        local col = (index - 1) % BUTTONS_PER_ROW
        if not InCombatLockdown() then
            if row ~= button._row or col ~= button._col then
                local xOffset = col * (BUTTON_SIZE + BUTTON_SPACING)
                local yOffset = -row * (BUTTON_SIZE + BUTTON_SPACING)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", xOffset, yOffset)
                button._row = row
                button._col = col
            end
            button:Show()
        end
        
        -- Update count and cooldown
        local countText = (consumableCount[itemID] and consumableCount[itemID] > 1) and consumableCount[itemID] or ""
        if countText ~= button._lastCountText then
            button.count:SetText(countText)
            button._lastCountText = countText
        end
        local loc = itemLocationById[itemID]
        if loc then
            -- Ensure click action is always valid and up-to-date
            assignUseAction(button, itemID, loc)
            local start, duration, enable = GetContainerItemCooldown(loc.bag, loc.slot)
            if button.cd and button.cd.SetCooldown and start and duration then
                if start ~= button._lastCooldownStart or duration ~= button._lastCooldownDuration then
                    button.cd:SetCooldown(start, duration)
                    button._lastCooldownStart = start
                    button._lastCooldownDuration = duration
                end
            end
        end
    end

    -- Hide buttons for consumables no longer in bags
    for itemID, button in pairs(consumableButtons) do
        if not currentConsumables[itemID] and not InCombatLockdown() then
            button:Hide()
            itemLocationById[itemID] = nil
        end
    end

    -- Update frame size
    local rows = ceil(#sortedConsumables / BUTTONS_PER_ROW)
    local newHeight = rows * (BUTTON_SIZE + BUTTON_SPACING) - BUTTON_SPACING
    if not InCombatLockdown() then
        if ConsumableButtonsFrame._lastRows ~= rows then
            ConsumableButtonsFrame:SetSize(frameWidth, newHeight)
            ConsumableBarParent:SetSize(frameWidth, newHeight + 10) -- Update parent frame size
            ConsumableButtonsFrame._lastRows = rows
        end
    end

    -- Mouseover scripts are bound once at creation; no need to rebind here
end

----------------------------------------------------------------------------------------
--	Event Handling
----------------------------------------------------------------------------------------

local pendingScan
local function RequestUpdate()
	if pendingScan then return end
	pendingScan = true
	After(0.05, function()
		pendingScan = false
		updateConsumableButtons()
		UpdateBarVisibility()
	end)
end

-- Single scanner frame handles all relevant events
local Scanner = CreateFrame("Frame")
Scanner:RegisterEvent("BAG_UPDATE_DELAYED")
Scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
Scanner:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
Scanner:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    RequestUpdate()
end)

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------
-- Force an update when the script loads

After(1, function()
	updateConsumableButtons()
	UpdateBarVisibility()
end)

-- Set up mouseover functionality
ConsumableBarParent:SetScript("OnEnter", ShowBar)
ConsumableBarParent:SetScript("OnLeave", HideBar)
