local R, C, L = unpack(RefineUI)

-- Check if the feature is enabled in config
if not C or not C.autosell or C.autosell.enable ~= true then return end -- Re-enable this check

-- Localize WoW API functions for performance and safety
local GetContainerNumSlots = C_Container.GetContainerNumSlots -- Correct modern API
-- local GetContainerItemLink = _G.GetContainerItemLink -- Old API
local GetContainerItemLink = C_Container.GetContainerItemLink -- Correct modern API
local GetContainerItemInfo = C_Container.GetContainerItemInfo -- Modern API
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString
-- Prefer C_Item APIs when available; fall back to globals otherwise
-- Use modern C_Item APIs; avoid deprecated fallbacks in lint
local C_Item = rawget(_G, 'C_Item')
-- local UseContainerItem = _G.UseContainerItem -- Old API
local UseContainerItem = C_Container.UseContainerItem -- Correct modern API
local GetCursorInfo = _G.GetCursorInfo
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local MerchantFrame = rawget(_G, 'MerchantFrame') -- Reference the global Merchant frame
local wipe = _G.wipe
local tinsert = _G.tinsert
local tremove = _G.tremove
local print = _G.print
local format = string.format           -- Add format localization
local NUM_BAG_SLOTS = rawget(_G, 'NUM_BAG_SLOTS') -- Global constant
local Enum = _G.Enum                   -- Localize Enum for BagIndex
local tonumber = tonumber              -- Localize tonumber
local string_match = string.match      -- Localize string.match
local PlaySound = _G.PlaySound         -- Localize PlaySound
local SOUNDKIT = rawget(_G, 'SOUNDKIT')           -- Localize SOUNDKIT
local GameTooltip = _G.GameTooltip     -- Localize GameTooltip
local MenuUtil = _G.MenuUtil           -- Localize MenuUtil for Blizzard_Menu
local MenuConstants = rawget(_G, 'MenuConstants')   -- Localize MenuConstants
local LoadAddOn = C_AddOns.LoadAddOn     -- Correct modern API

local DEBUG_MODE = false               -- Set to true to simulate selling without actually selling
-- local ILVL_THRESHOLD = 250 -- Placeholder: Make this configurable later -- Replaced by C.loot.autoSell.ilvlThreshold
local SELL_DELAY = 0.05                -- Delay between selling items in seconds
local totalProfit = 0                   -- Accumulated vendor profit (copper)
local itemsSold = 0                     -- Number of items sold in this session

-- Helper function to extract Item ID from Link
local itemIDPattern = "item:(%d+):"
local function GetItemIDFromLink(link)
    if not link then return nil end
    local match = string_match(link, itemIDPattern)
    return match and tonumber(match)
end

local sellQueue = {}
local isSelling = false
local sellTimer = nil
local settingsButtonCreated = false -- Flag to track button creation
local ilvlPopup = nil -- Frame for the ilvl input pop-up

-- Forward declaration to satisfy linter for references earlier in the file
local OnMerchantShow

-- Function to Create/Get the iLvl Threshold Pop-up Frame
local function CreateIlvlThresholdPopup()
    if ilvlPopup then return ilvlPopup end

    -- Create the main pop-up frame using a more modern template with title + close button
    ilvlPopup = CreateFrame("Frame", "RefineUIAutoSellIlvlPopup", UIParent, "ButtonFrameTemplate")
    ilvlPopup:SetSize(420, 200)
    ilvlPopup:SetPoint("CENTER")
    ilvlPopup:SetFrameStrata("DIALOG")
    ilvlPopup:EnableMouse(true)
    ilvlPopup:SetMovable(true)
    ilvlPopup:RegisterForDrag("LeftButton")
    ilvlPopup:SetScript("OnDragStart", ilvlPopup.StartMoving)
    ilvlPopup:SetScript("OnDragStop", ilvlPopup.StopMovingOrSizing)
    ilvlPopup:Hide()

    -- Title
    if ilvlPopup.TitleText then
        ilvlPopup.TitleText:SetText("AutoSell: iLevel Threshold")
    else
        local title = ilvlPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetText("AutoSell: iLevel Threshold")
        ilvlPopup.TitleText = title
    end
    -- Reposition title lower and away from portrait ring
    if ilvlPopup.TitleText then
        ilvlPopup.TitleText:ClearAllPoints()
        ilvlPopup.TitleText:SetPoint("TOP", ilvlPopup, "TOP", 0, -30)
        ilvlPopup.TitleText:SetJustifyH("CENTER")
    end

    -- Portrait/Icon in the top-left ring (loot bag)
    if ilvlPopup.SetPortraitToAsset then
        ilvlPopup:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_08")
    elseif ilvlPopup.portrait or ilvlPopup.Portrait then
        local tex = ilvlPopup.portrait or ilvlPopup.Portrait
        tex:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
        tex:SetTexCoord(0, 1, 0, 1)
    end

    -- Ensure there is a close button
    if not ilvlPopup.CloseButton then
        local close = CreateFrame("Button", nil, ilvlPopup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", ilvlPopup, "TOPRIGHT", -5, -5)
        ilvlPopup.CloseButton = close
    end

    -- Use the inset (dark) area for content
    local content = ilvlPopup.Inset or ilvlPopup
    local topOffset = 6
    local leftMargin, rightMargin, bottomMargin = 12, 12, 5

    -- Label (centered)
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOP", content, "TOP", 0, -topOffset)
    label:SetJustifyH("CENTER")
    label:SetText("Sell items below iLevel:")

    -- EditBox (manual entry) centered below label
    local editBox = CreateFrame("EditBox", "RefineUIAutoSellIlvlEditBox", content, "InputBoxTemplate")
    editBox:SetPoint("TOP", label, "BOTTOM", 0, -8)
    editBox:SetSize(80, 24)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(4)
    editBox:SetAutoFocus(true)
    editBox:SetJustifyH("CENTER")
    ilvlPopup.editBox = editBox

    -- Slider synchronized with the edit box (below input)
    local slider = CreateFrame("Slider", "RefineUIAutoSellIlvlSlider", content, "OptionsSliderTemplate")
    slider:SetPoint("TOP", editBox, "BOTTOM", 0, -14)
    slider:SetPoint("LEFT", content, "LEFT", leftMargin, 0)
    slider:SetPoint("RIGHT", content, "RIGHT", -rightMargin, 0)
    slider:SetMinMaxValues(0, 1000)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local sliderName = slider:GetName()
    _G[sliderName .. "Low"]:SetText("0")
    _G[sliderName .. "High"]:SetText("1000")
    _G[sliderName .. "Text"]:SetText("Item Level")

    ilvlPopup.slider = slider

    -- OK Button
    local okButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    okButton:SetSize(90, 24)
    okButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -rightMargin, bottomMargin)
    okButton:SetText("OK")

    -- Cancel Button
    local cancelButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    cancelButton:SetSize(90, 24)
    cancelButton:SetPoint("RIGHT", okButton, "LEFT", -10, 0)
    cancelButton:SetText("Cancel")

    -- Wiring: keep value changes in sync
    local isUpdating = false

    slider:SetScript("OnValueChanged", function(self, value)
        if isUpdating then return end
        isUpdating = true
        local v = math.floor(tonumber(value) or 0)
        editBox:SetText(tostring(v))
        isUpdating = false
    end)

    editBox:SetScript("OnTextChanged", function(self)
        if isUpdating then return end
        local text = self:GetText()
        local n = tonumber(text) or 0
        local minV, maxV = slider:GetMinMaxValues()
        if n < minV then n = minV elseif n > maxV then n = maxV end
        isUpdating = true
        slider:SetValue(n)
        isUpdating = false
    end)

    editBox:SetScript("OnEnterPressed", function()
        okButton:Click()
    end)
    editBox:SetScript("OnEscapePressed", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
        ilvlPopup:Hide()
    end)

    okButton:SetScript("OnClick", function()
        local value = tonumber(ilvlPopup.editBox:GetText())
        if value and value >= 0 then
            C.autosell.ilvlThreshold = value
            print(format("|cFFFFD200AutoSell:|r iLevel Threshold set to: %d", value))
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
            ilvlPopup:Hide()
        else
            print(format("|cFFFFD200AutoSell:|r Invalid iLevel Threshold: %s", ilvlPopup.editBox:GetText()))
        end
    end)

    cancelButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
        ilvlPopup:Hide()
    end)

    -- Keyboard handling
    ilvlPopup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            PlaySound(SOUNDKIT.IG_MAINMENU_QUIT)
            self:Hide()
        end
    end)
    ilvlPopup:SetPropagateKeyboardInput(true)

    return ilvlPopup
end

-- Function to Show the iLvl Pop-up
local function ShowIlvlThresholdPopup()
    local popup = CreateIlvlThresholdPopup() -- Create if needed
    local current = tonumber(C.autosell.ilvlThreshold) or 0
    -- Initialize both slider and edit box in sync
    if popup.slider then
        popup.slider:SetValue(current)
    end
    if popup.editBox then
        popup.editBox:SetText(tostring(current))
        popup.editBox:SetFocus()
        popup.editBox:HighlightText()
    end
    popup:Show()
end

-- Blizzard_Menu Generator Function for AutoSell Settings
local function GenerateAutoSellSettingsMenu(owner, rootDescription)
    -- Ensure config is loaded
    if not C or not C.autosell then
        rootDescription:CreateTitle("|cffff0000Error: Config not loaded|")
        return
    end

    rootDescription:CreateTitle("AutoSell Settings")
    rootDescription:CreateDivider()

    -- Checkbox for Sell Only Equipment
    local sellOnlyEquipmentCheckbox = rootDescription:CreateCheckbox(
        "Sell Only Equipment",
        function(data) -- isSelected function
            return C.autosell.sellOnlyEquipment
        end,
        function(data, menuInputData, menu) -- onClick function
            C.autosell.sellOnlyEquipment = not C.autosell.sellOnlyEquipment
            print(format("|cFFFFD200AutoSell:|r Sell Only Equipment set to: %s", C.autosell.sellOnlyEquipment and "Enabled" or "Disabled"))
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            return MenuResponse.Refresh -- Refresh menu to show updated state
        end
    )

    -- iLevel Threshold Button (Opens separate input)
    local currentThreshold = C.autosell.ilvlThreshold or 0
    local buttonText = format("iLvl Threshold: %d", currentThreshold)
    local ilvlButtonDescription = rootDescription:CreateButton(
        buttonText, -- Use pre-formatted text
        function(data, menuInputData, menu) -- OnClick handler passed directly
            -- print("|cFFFFD200AutoSell:|r Opening iLvl Threshold input (Not Implemented Yet). ")
            -- TODO: Call function to create/show the ilvl input pop-up frame
            ShowIlvlThresholdPopup() -- Show the pop-up frame
            return MenuResponse.CloseAll -- Close menu when button is clicked
        end
    )
    -- ilvlButtonDescription:SetData(C.autosell.ilvlThreshold or 0) -- No longer needed
    --[[ -- Initializer no longer needed for text
    ilvlButtonDescription:AddInitializer(function(button, description, menu)
        -- Update button text with current value
        local currentValue = description:GetData()
        button:SetText(format("iLvl Threshold: %d", currentValue)) -- Set text dynamically
    end)
    ]]--

    -- Placeholder for iLevel Threshold setting (more complex, needs an input)
    --[[ -- Removed placeholder button
    rootDescription:CreateButton("Set iLevel Threshold (WIP)", function()
        print("|cFFFFD200AutoSell:|r iLevel Threshold setting not yet implemented.")
    end):SetEnabled(false) -- Disable until implemented
    ]]--

    -- You can add more settings here using rootDescription:Create...

    -- Example: Add a button to manually re-scan items (if needed)
    rootDescription:CreateDivider()
    rootDescription:CreateButton("Manually Rescan Items", function()
        print("|cFFFFD200AutoSell:|r Manually rescanning items...")
        -- Re-run the scan logic
        if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
            OnMerchantShow()
        end
        return MenuResponse.CloseAll -- Close the menu after action
    end)
end

-- Function to create the settings button
local function CreateSettingsButton()
    -- Create a DropdownButton without inheriting a complex visual template
    local button = CreateFrame("DropdownButton", "RefineUIAutoSellSettingsButton", MerchantFrame) -- No template inherited
    button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -20, 3)
    button:SetSize(32, 32) -- Make button size match desired icon size
    button:SetFrameStrata("HIGH") -- Set button strata to HIGH

    -- Hide potential default elements (might not exist without template, but safe to check)
    if button.Text then button.Text:Hide() end
    if button.Arrow then button.Arrow:Hide() end
    button:SetText("")

    -- Set the gear icon texture using SetAtlas
    local icon = button:CreateTexture(nil, "OVERLAY")
    -- icon:SetTexture("Interface\\COMMON\\UI-GearIcon") -- Use known standard gear icon
    icon:SetAtlas("GM-icon-settings", true) -- Use atlas name and tell it to use atlas size
    icon:SetAllPoints(button) -- Make the icon fill the button frame
    button.Icon = icon

    -- Remove basic button textures
    -- button:SetNormalTexture("Interface/Buttons/UI-Panel-Button-Up")
    -- button:SetPushedTexture("Interface/Buttons/UI-Panel-Button-Down")
    -- button:SetHighlightTexture("Interface/Buttons/UI-Panel-Button-Highlight")
    -- button:GetHighlightTexture():SetBlendMode("ADD")

    -- Set tooltip and add simple highlight effect
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("AutoSell Settings", 1, 1, 1)
        GameTooltip:Show()
        self.Icon:SetVertexColor(1, 1, 0.5) -- Yellow tint on hover
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.Icon:SetVertexColor(1, 1, 1) -- Reset color on leave
    end)

    -- Keep existing SetupMenu call
    button:SetupMenu(GenerateAutoSellSettingsMenu)

    -- We need to potentially re-anchor the button if MerchantFrame changes size/position.
    -- Hooking MerchantFrame's OnShow might be needed for robustness, but let's start simple.
end

-- Function to create the AutoSell settings dropdown (placeholder)
--[[ -- Removed old dropdown functions
local function CreateSettingsDropdown()
    -- TODO: Implement dropdown creation using CreateFrame or a library
    print("|cFFFFD200AutoSell:|r Settings dropdown creation not yet implemented.")
end

-- Function to toggle the settings dropdown
local function ToggleSettingsDropdown(anchorFrame)
    if not settingsDropdown then
        CreateSettingsDropdown()
    end
    -- TODO: Implement show/hide logic for the created dropdown
    if settingsDropdown then
        if settingsDropdown:IsShown() then
            settingsDropdown:Hide()
        else
            settingsDropdown:ClearAllPoints()
            settingsDropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -5) -- Position below the button
            settingsDropdown:Show()
        end
    end
end
]]--

local function ProcessSellQueue()
    if #sellQueue == 0 then
        isSelling = false
        if sellTimer then
            sellTimer:Cancel()
            sellTimer = nil
        end
        if itemsSold > 0 then
            print(format("|cFFFFD200AutoSell:|r Sold %d items for %s.", itemsSold, GetCoinTextureString(totalProfit)))
        end
        totalProfit = 0
        itemsSold = 0
        return
    end

    -- Check if merchant window is still open and cursor is free
    if not MerchantFrame:IsShown() or GetCursorInfo() then
        -- Stop selling if merchant closes or player is dragging
        print("|cFFFFD200AutoSell:|r AutoSell interrupted (Merchant Closed or Cursor Busy).") -- Formatted message
        wipe(sellQueue)
        isSelling = false
        if sellTimer then
            sellTimer:Cancel()
            sellTimer = nil
        end
        totalProfit = 0
        itemsSold = 0
        return
    end

    local item = tremove(sellQueue, 1)
    if item then
        if DEBUG_MODE then
            print(format("|cFFFFD200AutoSell:|r [DEBUG] Would sell %s (ilvl: %d%s)",
                item.link or "Unknown Item", item.ilvl or 0,
                item.alwaysSell and ", Always Sell" or ""))
        else
            -- Accumulate profit and count before selling
            local sellPrice
            if C_Item and C_Item.GetItemInfo then
                local _, _a, _b, _c, _d, _e, _f, _g, _h, _i, price = C_Item.GetItemInfo(item.link)
                sellPrice = price
            end
            if sellPrice and sellPrice > 0 then
                totalProfit = totalProfit + (sellPrice * (item.stackCount or 1))
                itemsSold = itemsSold + 1
            end
            UseContainerItem(item.bag, item.slot)
        end
    end

    -- Schedule next item
    sellTimer = C_Timer.After(SELL_DELAY, ProcessSellQueue)
end

-- Changed to local function
OnMerchantShow = function()
    -- Re-check config in case it changed
    if not C or not C.autosell or C.autosell.enable ~= true then return end

    if isSelling then
        print("|cFFFFD200AutoSell:|r AutoSell already in progress.") -- Formatted message
        return
    end

    -- Removed starting message here, moved after item scan
    wipe(sellQueue)
    totalProfit = 0
    itemsSold = 0

    local ilvlThreshold = C.autosell.ilvlThreshold
    local sellOnlyEquipment = C.autosell.sellOnlyEquipment
    local alwaysSellList = RefineUIAutoSellDB.AlwaysSell

    for bag = 0, Enum.BagIndex.ReagentBag do
        for slot = 1, GetContainerNumSlots(bag) do
            local info = GetContainerItemInfo(bag, slot)
            if info and not info.isLocked then
                if not info.hasNoValue then
                    local itemID = info.itemID
                    local itemLink = info.hyperlink or GetContainerItemLink(bag, slot)
                    local stackCount = info.stackCount or 1

                    -- Always sell list short-circuit
                    if itemID and alwaysSellList[itemID] then
                        tinsert(sellQueue, { bag = bag, slot = slot, link = itemLink, ilvl = 0, itemType = nil, alwaysSell = true, stackCount = stackCount })
                    -- Junk (poor quality) short-circuit
                    elseif info.quality == Enum.ItemQuality.Poor then
                        tinsert(sellQueue, { bag = bag, slot = slot, link = itemLink, ilvl = 0, itemType = nil, alwaysSell = false, stackCount = stackCount })
                    else
                        -- Only check equipment iLvl if configured
                        if sellOnlyEquipment and itemLink and C_Item and C_Item.GetItemInfo then
                            local _, _, _, itemLevelBasic, _, itemType = C_Item.GetItemInfo(itemLink)
                            if itemType == "Armor" or itemType == "Weapon" then
                                local detailed = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(itemLink)
                                local effectiveIlvl = detailed or itemLevelBasic or 0
                                if effectiveIlvl > 0 and effectiveIlvl < ilvlThreshold then
                                    tinsert(sellQueue, { bag = bag, slot = slot, link = itemLink, ilvl = effectiveIlvl, itemType = itemType, alwaysSell = false, stackCount = stackCount })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Print status after scanning
    if #sellQueue > 0 then
        isSelling = true
        ProcessSellQueue() -- Start the selling process
    end
end

-- Changed to local function
local function OnMerchantClosed()
    if isSelling then
        print("|cFFFFD200AutoSell:|r AutoSell stopped (Merchant Closed).") -- Formatted message
        wipe(sellQueue)
        isSelling = false
        if sellTimer then
            sellTimer:Cancel()
            sellTimer = nil
        end
        totalProfit = 0
        itemsSold = 0
    end
end

-- Event Handling Frame
local eventFrame = CreateFrame("Frame", "RefineUILootAutoSellEventFrame")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        -- Removed print here
        -- Delay slightly to ensure merchant frame is fully ready
        C_Timer.After(0.2, function()
            if MerchantFrame:IsShown() then  -- Double check if still open
                -- Create the settings button only once when the frame is shown
                if not settingsButtonCreated then
                    CreateSettingsButton() -- Create the button here
                    settingsButtonCreated = true
                end
                OnMerchantShow()             -- Call local function
            end
        end)
    elseif event == "MERCHANT_CLOSED" then
        -- Removed print here
        OnMerchantClosed() -- Call local function
    end
end)

-- Slash Command Handler
SLASH_AUTOSELL1 = "/as"
SlashCmdList["AUTOSELL"] = function(msg)
    msg = msg:trim()
    local command = ""
    local itemLink = ""

    -- Explicitly check for commands
    if msg:lower() == "list" then
        command = "list"
    elseif msg:lower():find("^remove%s+") then
        command = "remove"
        itemLink = msg:sub(8):trim() -- Get substring after "remove "
    elseif msg:lower():find("^add%s+") then
        command = "add"
        itemLink = msg:sub(5):trim() -- Get substring after "add "
    else
        -- Default case: Assume the whole message is an item link for adding
        command = "add"
        itemLink = msg
    end

    if command == "add" then
        if not itemLink or itemLink == "" then
            print("|cFFFFD200AutoSell:|r Usage: /as add [Item Link] (or just /as [Item Link])")
            return
        end

        local itemID = GetItemIDFromLink(itemLink)
        if not itemID then
            print(format("|cFFFFD200AutoSell:|r Could not extract Item ID from link: %s", itemLink))
            return
        end

        local itemName, _, itemQuality
        if C_Item and C_Item.GetItemInfo then
            itemName, _, itemQuality = C_Item.GetItemInfo(itemLink)
        end
        if not itemName then
            print(format("|cFFFFD200AutoSell:|r Invalid item link or item info not available for ID %d.", itemID))
            return
        end

        RefineUIAutoSellDB.AlwaysSell[itemID] = true
        print(format("|cFFFFD200AutoSell:|r Added %s to the Always Sell list.", itemLink))
    elseif command == "remove" then
        if not itemLink or itemLink == "" then
            print("|cFFFFD200AutoSell:|r Usage: /as remove [Item Link]")
            return
        end

        local itemID = GetItemIDFromLink(itemLink)
        if not itemID then
            print(format("|cFFFFD200AutoSell:|r Could not extract Item ID from link: %s", itemLink))
            return
        end

        if RefineUIAutoSellDB.AlwaysSell[itemID] then
            RefineUIAutoSellDB.AlwaysSell[itemID] = nil
            print(format("|cFFFFD200AutoSell:|r Removed ID %d from the Always Sell list.", itemID))
        else
            print(format("|cFFFFD200AutoSell:|r Item ID %d not found in the Always Sell list.", itemID))
        end
    elseif command == "list" then
        print("|cFFFFD200AutoSell:|r Always Sell List:")
        local count = 0
        for itemID, value in pairs(RefineUIAutoSellDB.AlwaysSell) do
            if value then
                local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
                local link = C_Item and C_Item.GetItemLinkByID and C_Item.GetItemLinkByID(itemID)
                print(format("  - %s (ID: %d)", link or name or ("Item"), itemID))
                count = count + 1
            end
        end
        if count == 0 then
            print("  List is empty.")
        end
    else
        print("|cFFFFD200AutoSell:|r Unknown command. Usage:")
        print("  /as add [Item Link] - Add item to list")
        print("  /as remove [Item Link] - Remove item from list")
        print("  /as list - Show the list")
    end
end

-- Create the button when the addon loads (or specifically this module)
-- If this file isn't guaranteed to run only once on load, move this call
-- to an appropriate ADDON_LOADED handler in your core addon file.
-- CreateSettingsButton() -- Removed call from here
