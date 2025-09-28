local R, C, L = unpack(RefineUI)
local LEM = LibStub('LibEditMode')

--------------------------------------------------------------------------------
-- Upvalues / locals
--------------------------------------------------------------------------------
local _G = _G
local tostring = tostring
local format   = string.format
local pairs    = pairs
local type     = type

-- Local forward declarations
local TryDirectEditModeIntegration

-- Local helpers and constants (KISS/DRY)
local function GetClassKey()
    return UnitClass("player") or "UNKNOWN"
end

local function EnsureClassProfile()
    local classKey = GetClassKey()
    RefineUI_FilgerClassProfiles = RefineUI_FilgerClassProfiles or {}
    RefineUI_FilgerClassProfiles[classKey] = RefineUI_FilgerClassProfiles[classKey] or {}
    return RefineUI_FilgerClassProfiles[classKey]
end

local function SaveAllToClassProfile()
    local profile = EnsureClassProfile()
    profile.ManagedSpells = R.Filger.ManagedSpells
    profile.FrameSettings = R.Filger.FrameSettings
    profile.SpecFilter = R.Filger.SpecFilter
end

local function SafeUpdateAuras()
    if R.Filger.UpdateAuras then
        R.Filger:UpdateAuras()
    end
end

-- Ensure R.Filger exists
R.Filger = R.Filger or {}

-- Initialize custom spell lists
R.Filger.CustomSpells = R.Filger.CustomSpells or {
    LEFT_BUFF = {},
    RIGHT_BUFF = {},
    BOTTOM_BUFF = {}
}

-- Initialize Frame Settings Table if it doesn't exist
R.Filger.FrameSettings = R.Filger.FrameSettings or {}

-- Initialize Spec Filter Settings
R.Filger.SpecFilter = R.Filger.SpecFilter or "ALL"

-- Spec Information Helper Functions
local function GetSpecInfo()
    local playerClass = UnitClass("player")
    if not playerClass then 
        return {} 
    end
    
    local specs = {}
    local numSpecs = GetNumSpecializations()
    
    for i = 1, numSpecs do
        local specID, specName = GetSpecializationInfo(i)
        if specID and specName then
            table.insert(specs, {
                id = specID,
                name = specName,
                index = i
            })
        end
    end
    
    return specs
end

local function GetSpecDisplayText(specValue)
    if specValue == "ALL" or specValue == nil then
        return "All Specs"
    end
    
    local specs = GetSpecInfo()
    for _, spec in ipairs(specs) do
        -- Handle both string and number comparisons
        if spec.id == specValue or spec.index == specValue or tostring(spec.id) == tostring(specValue) then
            return spec.name
        end
    end
    
    return "Unknown Spec"
end

-- This table will hold the spells actually managed and saved
R.Filger.ManagedSpells = R.Filger.ManagedSpells or {
    LEFT_BUFF = {},
    RIGHT_BUFF = {},
    BOTTOM_BUFF = {}
}

-- Need a way to potentially refresh the settings panel if LEM allows
--[[ Removed - GetFrameByName is not a standard function and refresh isn't supported
local function RequestSettingsRefresh(frame)
    print("Filger: Spell list changed. Re-open settings panel to see updated settings.")
end
]]

local function AddSpell(location, spellID)
    -- Verify the spell exists
    local spellName = GetSpellInfo(spellID)
    if not spellName then
        print("|cFFFFD200Error:|r Spell ID " .. spellID .. " does not exist.")
        return
    end

    -- Use ManagedSpells (which now contains tables)
    R.Filger.ManagedSpells[location] = R.Filger.ManagedSpells[location] or {}

    -- Check if spell is already in the list by iterating through tables
    local exists = false
    for _, spellData in ipairs(R.Filger.ManagedSpells[location]) do
        if spellData.spellID == spellID then
            exists = true
            break
        end
    end

    if exists then
        print("|cFFFFD200Note:|r " .. spellName .. " (ID: " .. spellID .. ") is already being tracked.")
        return
    end

    -- Add spell as a table to managed list
    local newSpellEntry = {
        spellID = spellID,
        filter = "BUFF", -- Default filter
        caster = "player", -- Default caster
        spec = R.Filger.SpecFilter, -- Use current spec filter setting
        -- absID, color, duration default to nil
    }
    
    -- Set better defaults for certain spell types
    -- If it's a well-known missing buff spell, set appropriate defaults
    local missingBuffSpells = {
        [188370] = true, -- Consecration (Protection Paladin)
        [465] = true,    -- Devotion Aura (Paladin) 
        [48792] = true,  -- Icebound Fortitude (Death Knight)
        [48707] = true,  -- Anti-Magic Shell (Death Knight)
    }
    
    -- If it's a well-known stacking buff spell, set stacks filter
    local stacksBuffSpells = {
        [344179] = true, -- Maelstrom Weapon (Shaman)
        [334195] = true, -- Hailstorm (Enhancement Shaman)
        [393785] = true, -- Icy Talons (Frost Death Knight)
        [195181] = true, -- Bone Shield (Death Knight)
        [974] = true,    -- Earth Shield (Shaman)
        [33763] = true,  -- Lifebloom (Druid)
    }
    
    if missingBuffSpells[spellID] then
        newSpellEntry.filter = "MISSING"
    elseif stacksBuffSpells[spellID] then
        newSpellEntry.filter = "STACKS"
    end
    
    table.insert(R.Filger.ManagedSpells[location], newSpellEntry)
    print("|cFFFFD200Added:|r " .. spellName .. " (ID: " .. spellID .. ") to managed list for " .. location)

    -- Save and refresh
    SaveAllToClassProfile()
    SafeUpdateAuras()

    -- Advise user to reopen settings (for UI feedback, though not strictly needed now)
end

local function RemoveSpell(location, spellID)
    local spellName = GetSpellInfo(spellID) or "Unknown Spell"
    local foundIndex = nil

    -- Use ManagedSpells (which now contains tables)
    R.Filger.ManagedSpells[location] = R.Filger.ManagedSpells[location] or {}

    -- Find the index of the spell table to remove
    for i, spellData in ipairs(R.Filger.ManagedSpells[location]) do
        if spellData.spellID == spellID then
            foundIndex = i
            break
        end
    end

    if foundIndex then
        table.remove(R.Filger.ManagedSpells[location], foundIndex)
        print("|cFFFFD200Removed:|r " .. spellName .. " (ID: " .. spellID .. ") from managed list for " .. location)

        -- Save and refresh
        SaveAllToClassProfile()
        SafeUpdateAuras()

        -- Advise user to reopen settings
    else
        print("|cFFFFD200Error:|r Spell ID " .. spellID .. " not found in the managed tracking list for " .. location .. ".")
    end
end

local function CreateSpellEditUI(frame, location)
    local spellInput, addButton 
    local RefreshSpellList -- Declare early

    -- Create a panel for the spell management UI (made wider for inline controls)
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetSize(680, 520) -- Wider window to avoid column overlap
    panel:SetPoint("CENTER", frame, "CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:EnableKeyboard(true)

    -- Title (also serves as drag handle)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Manage " .. location .. " Spells")

    -- Create invisible drag area for better dragging experience
    local dragArea = CreateFrame("Frame", nil, panel)
    dragArea:SetPoint("TOPLEFT", 0, 0)
    dragArea:SetPoint("TOPRIGHT", 0, 0)
    dragArea:SetHeight(40) -- Cover title area
    dragArea:EnableMouse(true)
    dragArea:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            panel:StartMoving()
        end
    end)
    dragArea:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            panel:StopMovingOrSizing()
        end
    end)
    -- No custom cursor to keep default Edit Mode feel

    -- Instructions
    local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    instructions:SetText("Enter spell name or ID:")
    instructions:SetTextColor(1, 0.82, 0)

    -- Spell Input
    spellInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    spellInput:SetSize(170, 20)
    spellInput:SetPoint("TOPLEFT", instructions, "BOTTOMLEFT", 0, -8)
    spellInput:SetAutoFocus(false)
    spellInput:SetScript("OnEnterPressed", function()
        addButton:Click()
    end)

    -- Add Button
    addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetSize(80, 22)
    addButton:SetPoint("LEFT", spellInput, "RIGHT", 10, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function()
        local input = spellInput:GetText()
        if input and input ~= "" then
            local spellID = tonumber(input)
            if not spellID then
                spellID = select(7, GetSpellInfo(input))
            end
        if spellID then
            AddSpell(location, spellID)
            spellInput:SetText("")
                if RefreshSpellList then RefreshSpellList() end -- Refresh UI list
            else
                print("|cFFFFD200Error:|r Invalid spell name or ID: " .. input)
            end
        end
    end)

    -- Current Spells Header with column headers
    local currentHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentHeader:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -15)
    currentHeader:SetText("Current Spells:")
    currentHeader:SetTextColor(1, 0.82, 0)
    
    -- Column Headers
    local columnHeaders = CreateFrame("Frame", nil, panel)
    columnHeaders:SetSize(620, 20)
    columnHeaders:SetPoint("TOPLEFT", currentHeader, "BOTTOMLEFT", 5, -8)
    
    -- Column positions (kept consistent for rows)
    local COL = {
        Icon = 5,
        Spell = 30,
        Type = 220,
        Caster = 310,
        Spec = 400,
        Color = 520, -- tightened gap to delete column
        Delete = 560, -- explicit delete column (avoids scrollbar overlap)
    }
    
    local spellHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellHeader:SetPoint("LEFT", COL.Spell, 0)
    spellHeader:SetText("Spell")
    spellHeader:SetTextColor(0.9, 0.9, 0.9)
    
    local typeHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") 
    typeHeader:SetPoint("LEFT", COL.Type, 0)
    typeHeader:SetText("Type")
    typeHeader:SetTextColor(0.9, 0.9, 0.9)
    
    local casterHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    casterHeader:SetPoint("LEFT", COL.Caster, 0)
    casterHeader:SetText("Caster")
    casterHeader:SetTextColor(0.9, 0.9, 0.9)
    
    local specHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specHeader:SetPoint("LEFT", COL.Spec, 0)
    specHeader:SetText("Spec")
    specHeader:SetTextColor(0.9, 0.9, 0.9)
    
    local colorHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorHeader:SetPoint("LEFT", COL.Color, 0)
    colorHeader:SetText("Color")
    colorHeader:SetTextColor(0.9, 0.9, 0.9)
    
    -- Delete header (aligned to delete column)
    local deleteHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deleteHeader:SetPoint("LEFT", columnHeaders, "LEFT", COL.Delete + 4, 0)
    deleteHeader:SetText("Delete")
    deleteHeader:SetTextColor(0.9, 0.9, 0.9)
    
    -- Subtle divider under headers
    local headerDivider = columnHeaders:CreateTexture(nil, "ARTWORK")
    headerDivider:SetColorTexture(1, 1, 1, 0.06)
    headerDivider:SetPoint("TOPLEFT", columnHeaders, "BOTTOMLEFT", -5, -2)
    headerDivider:SetPoint("TOPRIGHT", columnHeaders, "BOTTOMRIGHT", 5, -2)
    headerDivider:SetHeight(1)
    
    -- Removed Action header since we're removing the text

    -- Spell List (Scrollable) - adjusted position and size
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(620, 340)
    scrollFrame:SetPoint("TOPLEFT", columnHeaders, "BOTTOMLEFT", 0, -5)

    local listContent = CreateFrame("Frame", nil, scrollFrame)
    listContent:SetSize(600, 1)
    scrollFrame:SetScrollChild(listContent)

    -- Close Button
    local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)

    -- Helper function to get display text for filter types
    local function GetFilterDisplayText(filter)
        local filterNames = {
            ["BUFF"] = "Buff",
            ["DEBUFF"] = "Debuff", 
            ["CD"] = "Cooldown",
            ["ICD"] = "ICD",
            ["MISSING"] = "Missing",
            ["STACKS"] = "Stacks"
        }
        return filterNames[filter] or filter
    end
    
    -- Helper function to get display text for caster types
    local function GetCasterDisplayText(caster)
        local casterNames = {
            ["player"] = "Player",
            ["target"] = "Target",
            ["pet"] = "Pet", 
            ["focus"] = "Focus",
            ["all"] = "All"
        }
        return casterNames[caster] or caster
    end

    -- Helper function to create type dropdown
    local function CreateTypeDropdown(parent, spellData, onSelectionChanged)
        local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown:SetSize(85, 20) -- Increased width from 70 to 85
        
        -- Set the current value as default text instead of generic "Type"
        local currentDisplayText = GetFilterDisplayText(spellData.filter or "BUFF")
        dropdown:SetDefaultText(currentDisplayText)
        
        local function GenerateMenu(dropdown, rootDescription)
            local types = {
                {text = "Buff", value = "BUFF"},
                {text = "Debuff", value = "DEBUFF"}, 
                {text = "Cooldown", value = "CD"},
                {text = "ICD", value = "ICD"},
                {text = "Missing", value = "MISSING"},
                {text = "Stacks", value = "STACKS"}
            }
            
            for _, typeData in ipairs(types) do
                local function IsSelected() 
                    return spellData.filter == typeData.value 
                end
                
                local function SetSelected()
                    spellData.filter = typeData.value
                    -- Update the dropdown's display text
                    dropdown:SetDefaultText(GetFilterDisplayText(typeData.value))
                    if onSelectionChanged then
                        onSelectionChanged()
                    end
                    dropdown:GenerateMenu() -- Update display text
                end
                
                rootDescription:CreateRadio(typeData.text, IsSelected, SetSelected)
            end
        end
        
        -- Set custom selection text translator
        dropdown:SetSelectionTranslator(function(selection)
            return GetFilterDisplayText(selection.data)
        end)
        
        dropdown:SetupMenu(GenerateMenu)
        dropdown:GenerateMenu() -- Initialize display
        return dropdown
    end

    -- Helper function to create caster dropdown  
    local function CreateCasterDropdown(parent, spellData, onSelectionChanged)
        local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown:SetSize(85, 20) -- Increased width from 70 to 85
        
        -- Set the current value as default text instead of generic "Caster"
        local currentDisplayText = GetCasterDisplayText(spellData.caster or "player")
        dropdown:SetDefaultText(currentDisplayText)
        
        local function GenerateMenu(dropdown, rootDescription)
            local casters = {
                {text = "Player", value = "player"},
                {text = "Target", value = "target"},
                {text = "Pet", value = "pet"},
                {text = "Focus", value = "focus"}, 
                {text = "All", value = "all"}
            }
            
            for _, casterData in ipairs(casters) do
                local function IsSelected()
                    return spellData.caster == casterData.value
                end
                
                local function SetSelected()
                    spellData.caster = casterData.value
                    -- Update the dropdown's display text
                    dropdown:SetDefaultText(GetCasterDisplayText(casterData.value))
                    if onSelectionChanged then
                        onSelectionChanged()
                    end
                    dropdown:GenerateMenu() -- Update display text
                end
                
                rootDescription:CreateRadio(casterData.text, IsSelected, SetSelected)
            end
        end
        
        -- Set custom selection text translator
        dropdown:SetSelectionTranslator(function(selection)
            return GetCasterDisplayText(selection.data)
        end)
        
        dropdown:SetupMenu(GenerateMenu)
        dropdown:GenerateMenu() -- Initialize display
        return dropdown
    end

    -- Helper function to create spec dropdown
    local function CreateSpecDropdown(parent, spellData, onSelectionChanged)
        local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        dropdown:SetSize(100, 20) -- Slightly wider for spec names
        
        -- Set the current value as default text
        local currentDisplayText = GetSpecDisplayText(spellData.spec or "ALL")
        dropdown:SetDefaultText(currentDisplayText)
        
        local function GenerateMenu(dropdown, rootDescription)
            local specs = {{text = "All Specs", value = "ALL"}}
            
            -- Add class-specific specs
            local classSpecs = GetSpecInfo()
            for _, spec in ipairs(classSpecs) do
                table.insert(specs, {text = spec.name, value = spec.id})
            end
            
            for _, specData in ipairs(specs) do
                local function IsSelected()
                    return (spellData.spec or "ALL") == specData.value
                end
                
                local function SetSelected()
                    spellData.spec = specData.value
                    -- Update the dropdown's display text
                    dropdown:SetDefaultText(GetSpecDisplayText(specData.value))
                    if onSelectionChanged then
                        onSelectionChanged()
                    end
                    dropdown:GenerateMenu() -- Update display text
                end
                
                rootDescription:CreateRadio(specData.text, IsSelected, SetSelected)
            end
        end
        
        -- Note: SetSelectionTranslator removed to avoid table concatenation error
        -- The dropdown should use the text from the CreateRadio calls directly
        
        dropdown:SetupMenu(GenerateMenu)
        dropdown:GenerateMenu() -- Initialize display
        
        return dropdown
    end

    -- Helper function to create color picker button
    local function CreateColorPickerButton(parent, spellData, onColorChanged)
        -- Create just a color square button (no text) with BackdropTemplate
        local colorButton = CreateFrame("Button", nil, parent, "BackdropTemplate")
        colorButton:SetSize(20, 20)
        
        -- Create backdrop for the color square
        colorButton:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        colorButton:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) -- Dark border
        
        local function UpdateColorSwatch()
            if spellData.color then
                colorButton:SetBackdropColor(unpack(spellData.color))
            else
                -- Default class color
                local r, g, b = unpack(R.oUF_colors.class[R.class] or {1, 1, 1})
                colorButton:SetBackdropColor(r, g, b, 1)
            end
        end
        
        colorButton:SetScript("OnClick", function()
            local currentColor = spellData.color or {unpack(R.oUF_colors.class[R.class] or {1, 1, 1})}
            
            local function OnColorChanged()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                spellData.color = {newR, newG, newB, newA}
                UpdateColorSwatch()
                if onColorChanged then
                    onColorChanged()
                end
            end
            
            local function OnCancel()
                spellData.color = currentColor
                UpdateColorSwatch()
                if onColorChanged then
                    onColorChanged()
                end
            end
            
            local options = {
                swatchFunc = OnColorChanged,
                opacityFunc = OnColorChanged, 
                cancelFunc = OnCancel,
                hasOpacity = true,
                opacity = currentColor[4] or 1,
                r = currentColor[1] or 1,
                g = currentColor[2] or 1, 
                b = currentColor[3] or 1,
            }
            
            ColorPickerFrame:SetupColorPickerAndShow(options)
        end)
        
        colorButton.UpdateColorSwatch = UpdateColorSwatch
        UpdateColorSwatch() -- Initial color
        return colorButton
    end

    -- Define RefreshSpellList function
    RefreshSpellList = function()
        -- Clear existing entries
        for _, child in ipairs({listContent:GetChildren()}) do
            child:Hide()
            child:SetParent(nil) -- Ensure proper cleanup
        end

        -- *** Read from R.Filger.ManagedSpells[location] (which now contains tables) ***
        local managedSpells = R.Filger.ManagedSpells[location] or {}
        local yOffset = 5

        if #managedSpells == 0 then
            -- Display "No spells added." text
            local noSpells = listContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noSpells:SetPoint("TOPLEFT", 5, -yOffset)
            noSpells:SetText("No spells added.")
            noSpells:SetTextColor(0.7, 0.7, 0.7)
            yOffset = yOffset + 30
        else
            -- Populate list rows from managedSpells (using spellData.spellID)
            for i, spellData in ipairs(managedSpells) do
                local spellID = spellData.spellID -- Extract the ID
                local spellName, _, spellIcon = GetSpellInfo(spellID)
                
                -- Create row container (Button for hover highlighting)
                local row = CreateFrame("Button", nil, listContent)
                row:SetSize(670, 35) -- Match content width to prevent overlap
                row:SetPoint("TOPLEFT", 0, -yOffset)
                
                -- Alternating row background
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                local shade = (i % 2 == 0) and 0.06 or 0.03
                bg:SetColorTexture(1, 1, 1, shade)

                -- Subtle hover highlight
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                -- Disable clicking but keep mouse interaction for highlighting
                row:SetScript("OnClick", function() end)

                -- Spell icon
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(28, 28) -- Slightly larger icon 
                icon:SetPoint("LEFT", COL.Icon, 0)
                icon:SetTexture(spellIcon)
                icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

                -- Spell name
                local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                name:SetPoint("LEFT", icon, "RIGHT", 8, 8) -- Positioned higher in row
                name:SetSize(150, 0) -- Set width to prevent overflow
                name:SetJustifyH("LEFT")
                name:SetText(spellName or "Unknown Spell")

                -- Spell ID (smaller, below name)
                local id = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") 
                id:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
                id:SetText("ID: " .. spellID)
                id:SetTextColor(0.7, 0.7, 0.7)

                -- Type Dropdown
                local typeDropdown = CreateTypeDropdown(row, spellData, function()
                    SaveAllToClassProfile()
                    SafeUpdateAuras()
                end)
                typeDropdown:SetPoint("LEFT", COL.Type, 0)

                -- Caster Dropdown  
                local casterDropdown = CreateCasterDropdown(row, spellData, function()
                    SaveAllToClassProfile()
                    SafeUpdateAuras()
                end)
                casterDropdown:SetPoint("LEFT", COL.Caster, 0)

                -- Spec Dropdown
                local specDropdown = CreateSpecDropdown(row, spellData, function()
                    SaveAllToClassProfile()
                    SafeUpdateAuras()
                end)
                specDropdown:SetPoint("LEFT", COL.Spec, 0)

                -- Color Picker
                local colorButton = CreateColorPickerButton(row, spellData, function()
                    SaveAllToClassProfile()
                    SafeUpdateAuras()
                end)
                colorButton:SetPoint("LEFT", COL.Color, 0)
                
                -- Tooltip + right-click to clear color
                colorButton:HookScript("OnEnter", function()
                    GameTooltip:SetOwner(colorButton, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Icon Color", 1, 0.82, 0)
                    GameTooltip:AddLine("Left-click: choose color", 1, 1, 1)
                    GameTooltip:AddLine("Right-click: clear color", 1, 1, 1)
                    GameTooltip:Show()
                end)
                colorButton:HookScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                colorButton:HookScript("OnMouseUp", function(_, btn)
                    if btn == "RightButton" then
                        spellData.color = nil
                        SaveAllToClassProfile()
                        SafeUpdateAuras()
                        -- Refresh the swatch visually
                        if colorButton.UpdateColorSwatch then colorButton:UpdateColorSwatch() end
                    end
                end)

                -- Delete Button (icon-only)
                local deleteButton = CreateFrame("Button", nil, row)
                deleteButton:SetSize(24, 24)
                -- Anchor using explicit column to avoid scrollbar overlap
                deleteButton:SetPoint("LEFT", row, "LEFT", COL.Delete, 0)
                if deleteButton.SetNormalAtlas then
                    deleteButton:SetNormalAtlas("GM-raidMarker-remove")
                    deleteButton:SetPushedAtlas("GM-raidMarker-remove")
                    deleteButton:SetHighlightAtlas("GM-raidMarker-remove")
                    local ht = deleteButton:GetHighlightTexture()
                    if ht then ht:SetAlpha(0.25) end
                else
                    -- Fallback for older clients
                    local n = deleteButton:CreateTexture(nil, "ARTWORK")
                    n:SetAllPoints()
                    n:SetAtlas("GM-raidMarker-remove", true)
                    deleteButton:SetNormalTexture(n)
                end
                deleteButton:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(deleteButton, "ANCHOR_LEFT")
                    GameTooltip:SetText("Delete", 1, 0.1, 0.1)
                    GameTooltip:AddLine("Click to remove this spell", 1, 1, 1)
                    GameTooltip:Show()
                end)
                deleteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
                deleteButton:SetScript("OnClick", function()
                    -- Show confirmation dialog
                    StaticPopup_Show("FILGER_CONFIRM_DELETE", spellName or ("Spell ID " .. spellID), nil, {
                        spellID = spellID,
                        location = location,
                        refreshFunc = RefreshSpellList
                    })
                end)

                yOffset = yOffset + 40 -- Increased spacing for larger rows
            end
        end
        
        listContent:SetHeight(math.max(yOffset, scrollFrame:GetHeight()))
    end

    panel:Hide() -- Initially hide the panel

    -- Close panel when Edit Mode is exited using EventRegistry
    local editModeCallbackOwner = {}
    local isCallbackRegistered = false
    
    local function RegisterEditModeCallback()
        if not isCallbackRegistered then
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                if panel:IsShown() then
                    panel:Hide()
                end
            end, editModeCallbackOwner)
            isCallbackRegistered = true
        end
    end
    
    local function UnregisterEditModeCallback()
        if isCallbackRegistered then
            EventRegistry:UnregisterCallback("EditMode.Exit", editModeCallbackOwner)
            isCallbackRegistered = false
        end
    end

    -- Show/Hide toggle function
    local function TogglePanel()
        if panel:IsShown() then
            panel:Hide()
        else
            panel:Show()
            RegisterEditModeCallback() -- Register callback when showing panel
            if RefreshSpellList then RefreshSpellList() end -- Refresh UI on show
        end
    end
    
    -- Override panel Hide to unregister callback
    local originalHide = panel.Hide
    panel.Hide = function(self)
        UnregisterEditModeCallback() -- Unregister when hiding
        originalHide(self)
    end

    -- ESC to close
    panel:SetScript("OnKeyDown", function(_, key)
        if key == GetBindingKey("TOGGLEGAMEMENU") or key == "ESCAPE" then
            panel:Hide()
        end
    end)

    if RefreshSpellList then RefreshSpellList() end -- Initial refresh

    -- Return the toggle function
    return TogglePanel
end

-- Implement GetSpacing if it doesn't exist (Keep for now, might be used elsewhere)
if not R.Filger.GetSpacing then
    R.Filger.GetSpacing = function(self, frameName)
        -- Read from frame-specific settings if available
        return (R.Filger.FrameSettings[frameName] and R.Filger.FrameSettings[frameName].space) or 3
    end
end

-- Modify RegisterFilgerFrames to use the new CreateSpellEditUI
local function RegisterFilgerFrames()
    local frames = {
        {name = "LEFT_BUFF", frame = LEFT_BUFF_Anchor},
        {name = "RIGHT_BUFF", frame = RIGHT_BUFF_Anchor},
        {name = "BOTTOM_BUFF", frame = BOTTOM_BUFF_Anchor}
    }

    -- Check available LEM functions
    local addFrameSettingsAvailable = (LEM.AddFrameSettings ~= nil)
    local addFrameButtonAvailable = (LEM.AddFrameSettingsButton ~= nil)
    

    for _, frameInfo in ipairs(frames) do
        -- Ensure settings table exists for this frame
        R.Filger.FrameSettings[frameInfo.name] = R.Filger.FrameSettings[frameInfo.name] or {}
        local frameSettings = R.Filger.FrameSettings[frameInfo.name]
        
        -- Get default values
        local defaultSize = R.Filger.FrameSettings[frameInfo.name].size or C.filger.buffs_size or 36
        local defaultSpace = R.Filger.FrameSettings[frameInfo.name].space or C.filger.buffs_space or 3
        
        if LEM.AddFrame then
            -- Ensure the frame has a name for Edit Mode
            frameInfo.frame.EditModeFrameName = "RefineUI_" .. frameInfo.name
            
            -- Register the frame with EditMode
            LEM:AddFrame(frameInfo.frame, function(_, _, point, x, y)
                -- print("Frame moved:", frameInfo.name, point, x, y)
                if R.Filger.UpdateAnchorPosition then
                    R.Filger:UpdateAnchorPosition(frameInfo.name, point, x, y)
                end
            end, {
                point = "CENTER",
                x = 0,
                y = 0
            })
            
            -- Create the detailed spell management UI instance (but don't show it yet)
            local toggleSpellUI = CreateSpellEditUI(frameInfo.frame, frameInfo.name)
            
            -- Create settings (Sliders and Dropdowns)
            if addFrameSettingsAvailable then
                local sliderSettings = {
                    -- Icon Size Slider 
                    {
                        kind = Enum.EditModeSettingDisplayType.Slider,
                        name = "Icon Size",
                        default = defaultSize,
                        minValue = 24, maxValue = 64, valueStep = 4,
                        get = function() return R.Filger.FrameSettings[frameInfo.name].size or defaultSize end,
                        set = function(_, value)
                            R.Filger.FrameSettings[frameInfo.name].size = value
                            SaveAllToClassProfile()
                            if R.Filger.UpdateDisplaySettings then R.Filger:UpdateDisplaySettings(frameInfo.name, nil, {size = value}) end
                        end
                    },
                    -- Spacing Slider
                    {
                        kind = Enum.EditModeSettingDisplayType.Slider,
                        name = "Icon Spacing",
                        default = defaultSpace,
                        minValue = 0, maxValue = 20, valueStep = 1,
                        get = function() return R.Filger.FrameSettings[frameInfo.name].space or defaultSpace end,
                        set = function(_, value)
                            R.Filger.FrameSettings[frameInfo.name].space = value
                            SaveAllToClassProfile()
                            if R.Filger.UpdateDisplaySettings then R.Filger:UpdateDisplaySettings(frameInfo.name, nil, {space = value}) end
                        end
                    },
                }
                -- Register slider settings
                local success, errorMsg = pcall(function() LEM:AddFrameSettings(frameInfo.frame, sliderSettings) end)
                if not success then print("|cFFFFD200Error adding slider settings:|r " .. tostring(errorMsg)) end
            end

            -- Create Button Setting
            if addFrameButtonAvailable then
                 -- Working Structure: Pass button object directly
                 local buttonDataDirect = {
                     text = "Manage Buffs", -- Final button text
                     click = function()
                         toggleSpellUI()
                     end
                 }
                 local success, errorMsg = pcall(function() LEM:AddFrameSettingsButton(frameInfo.frame, buttonDataDirect) end)
                 
                 if not success then 
                     print("|cFFFFD200Error adding button setting:|r " .. tostring(errorMsg))
                 end
                 
            else
            end

        else
            print("|cFFFFD200Error:|r LibEditMode:AddFrame not available")
        end
    end
end

-- Try using direct EditMode integration if LibEditMode doesn't work
local function TryDirectEditModeIntegration()
    
    -- Make sure we have access to the C_EditMode API
    if not C_EditMode then
        return
    end
    
    -- Register an EditMode system handler if it exists
    if _G.EditModeManagerFrame and _G.EditModeManagerFrame.RegisterSystemFrame then
        local frames = {
            {name = "LEFT_BUFF", frame = LEFT_BUFF_Anchor},
            {name = "RIGHT_BUFF", frame = RIGHT_BUFF_Anchor},
            {name = "BOTTOM_BUFF", frame = BOTTOM_BUFF_Anchor}
        }
        
        for _, frameInfo in ipairs(frames) do
        local toggleSpellUI = CreateSpellEditUI(frameInfo.frame, frameInfo.name)

            -- Attach a button to the frame
            if not frameInfo.frame.manageButton then
                local btn = CreateFrame("Button", nil, frameInfo.frame, "UIPanelButtonTemplate")
                btn:SetSize(100, 22)
                btn:SetPoint("BOTTOM", frameInfo.frame, "BOTTOM", 0, -30)
                btn:SetText("Manage Spells")
                btn:SetScript("OnClick", toggleSpellUI)
                frameInfo.frame.manageButton = btn
                btn:Hide() -- Initially hide
                
                -- Create a simple update handler
                local function UpdateButtonVisibility()
                    if C_EditMode and C_EditMode.IsEditModeActive and C_EditMode.IsEditModeActive() then
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end
                
                -- Update on frame show
                frameInfo.frame:HookScript("OnShow", UpdateButtonVisibility)
                
                -- Create a visibility checker that runs periodically
                local ticker
                ticker = C_Timer.NewTicker(0.5, function()
                    UpdateButtonVisibility()
                end)
            end
        end
        
    else
        -- silently ignore if EditModeManagerFrame isn't available
    end
end

-- Debug function to check what's registered
-- (Removed unused InspectLEMRegistrations for simplicity)

-- Load managed spells from saved variables OR populate with defaults
local function LoadManagedSpells()
    -- Initialize the base table if it doesn't exist (redundant but safe)
    R.Filger.ManagedSpells = R.Filger.ManagedSpells or {
        LEFT_BUFF = {},
        RIGHT_BUFF = {},
        BOTTOM_BUFF = {}
    }

    -- Get current class for class-specific profiles
    local playerClass = UnitClass("player")
    if not playerClass then
        playerClass = "UNKNOWN"
    end

    -- Initialize class-based saved variables if they don't exist
    RefineUI_FilgerClassProfiles = RefineUI_FilgerClassProfiles or {}
    RefineUI_FilgerClassProfiles[playerClass] = RefineUI_FilgerClassProfiles[playerClass] or {}

    -- *** Step 1: Attempt to load from class-specific SavedVariables ***
    local classProfile = RefineUI_FilgerClassProfiles[playerClass]
    if classProfile.ManagedSpells then
       -- Basic validation for the NEW structure
       local isValidSavedData = true
       if type(classProfile.ManagedSpells) ~= "table" or
          type(classProfile.ManagedSpells.LEFT_BUFF) ~= "table" or
          type(classProfile.ManagedSpells.RIGHT_BUFF) ~= "table" or
          type(classProfile.ManagedSpells.BOTTOM_BUFF) ~= "table" then
           isValidSavedData = false
           
       else
           -- Check first element (if exists) in each list for table structure and spellID
           for _, locationData in pairs(classProfile.ManagedSpells) do
               if #locationData > 0 then
                   local firstSpell = locationData[1]
                   if type(firstSpell) ~= "table" or firstSpell.spellID == nil then
                       isValidSavedData = false
                       
                       break -- Stop checking if invalid format found
                   end
               end
           end
       end

           if isValidSavedData then
               R.Filger.ManagedSpells = classProfile.ManagedSpells
               -- Also load Frame Settings from class profile
               if classProfile.FrameSettings and type(classProfile.FrameSettings) == "table" then
                   R.Filger.FrameSettings = classProfile.FrameSettings
               end
               -- Load Spec Filter from class profile
               if classProfile.SpecFilter then
                   R.Filger.SpecFilter = classProfile.SpecFilter
               end
               return -- Don't load defaults if loaded from class profile
           end
    end

    -- *** Step 2: Check for legacy individual character saves and migrate ***
    local migratedFromLegacy = false
    if RefineUI_FilgerManagedSpells then
        -- Basic validation for the legacy structure
        local isValidLegacyData = true
        if type(RefineUI_FilgerManagedSpells) ~= "table" or
           type(RefineUI_FilgerManagedSpells.LEFT_BUFF) ~= "table" or
           type(RefineUI_FilgerManagedSpells.RIGHT_BUFF) ~= "table" or
           type(RefineUI_FilgerManagedSpells.BOTTOM_BUFF) ~= "table" then
            isValidLegacyData = false
        else
            -- Check first element (if exists) in each list for table structure and spellID
            for _, locationData in pairs(RefineUI_FilgerManagedSpells) do
                if #locationData > 0 then
                    local firstSpell = locationData[1]
                    if type(firstSpell) ~= "table" or firstSpell.spellID == nil then
                        isValidLegacyData = false
                        break -- Stop checking if invalid format found
                    end
                end
            end
        end
        
        if isValidLegacyData then
            -- Migrate legacy data to class profile
            R.Filger.ManagedSpells = RefineUI_FilgerManagedSpells
            RefineUI_FilgerClassProfiles[playerClass].ManagedSpells = RefineUI_FilgerManagedSpells
            
            -- Migrate frame settings too if available
            if RefineUI_FilgerFrameSettings and type(RefineUI_FilgerFrameSettings) == "table" then
                R.Filger.FrameSettings = RefineUI_FilgerFrameSettings
                RefineUI_FilgerClassProfiles[playerClass].FrameSettings = RefineUI_FilgerFrameSettings
            end
            
            -- Set default spec filter for migrated data
            R.Filger.SpecFilter = "ALL"
            RefineUI_FilgerClassProfiles[playerClass].SpecFilter = "ALL"
            
            -- Clear legacy variables to prevent confusion
            RefineUI_FilgerManagedSpells = nil
            RefineUI_FilgerFrameSettings = nil
            
            migratedFromLegacy = true
            
            return -- Don't load defaults since we migrated existing data
        end
    end

    -- *** Step 3: If no valid saved variables, populate with defaults (NEW STRUCTURE) ***
    

    local locationsToPopulate = {"LEFT_BUFF", "RIGHT_BUFF", "BOTTOM_BUFF"}
    local defaultSources = {C["filger_spells"] and C["filger_spells"][R.class], C["filger_spells"] and C["filger_spells"]["ALL"]}

    for _, location in ipairs(locationsToPopulate) do
        
        R.Filger.ManagedSpells[location] = {} -- Start fresh for default population
        local addedSpells = {} -- Use spellID as key to track additions

        for _, sourceTable in ipairs(defaultSources) do
            if sourceTable then
                for _, section in ipairs(sourceTable) do
                    if type(section) == "table" and section.Name == location then
                        for i = 1, #section do
                            local spellData = section[i]
                            -- Check if it's a valid spell entry with a spellID and not already added
                            if type(spellData) == "table" and spellData.spellID and not addedSpells[spellData.spellID] then
                                -- Create the new table with only the desired fields
                                local newSpellEntry = {
                                    spellID = spellData.spellID,
                                    caster = spellData.caster, -- Copy directly if exists, else nil
                                    filter = spellData.filter, -- Copy directly if exists, else nil
                                    absID = spellData.absID,   -- Copy directly if exists, else nil
                                    color = spellData.color,   -- Copy directly if exists, else nil
                                    duration = spellData.duration -- Copy directly if exists, else nil
                                }
                                table.insert(R.Filger.ManagedSpells[location], newSpellEntry)
                                addedSpells[spellData.spellID] = true -- Track added spell ID
                            end
                        end
                    end
                end
            end
        end
        
    end

    -- Populate default frame settings if not loaded
    if not R.Filger.FrameSettings or not next(R.Filger.FrameSettings) then
        
        R.Filger.FrameSettings = {}
        local defaultSize = C.filger.buffs_size or 36
        local defaultSpace = C.filger.buffs_space or 3
        for _, location in ipairs(locationsToPopulate) do
             R.Filger.FrameSettings[location] = { size = defaultSize, space = defaultSpace }
        end
    end

    -- Save to class profile
    SaveAllToClassProfile()
    
end

-- Initialize on load and when ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "RefineUI" then
        LoadManagedSpells() -- Load SV or Defaults
        
        -- Register the delete confirmation dialog
        StaticPopupDialogs["FILGER_CONFIRM_DELETE"] = {
            text = "Are you sure you want to delete %s from the spell list?",
            button1 = "Delete",
            button2 = "Cancel", 
            OnAccept = function(self, data)
                if data and data.spellID and data.location then
                    RemoveSpell(data.location, data.spellID)
                    if data.refreshFunc then
                        data.refreshFunc()
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Separate frame for PLAYER_LOGIN to ensure LoadManagedSpells runs first
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
     if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function()
            -- Initialize Edit Mode UI components
            if R.Filger.InitializeEditMode then
                R.Filger:InitializeEditMode()
            end

            -- *** Crucial Step: Rebuild internal tracking data from loaded settings ***
            if R.Filger.RefreshTrackedSpells then
                R.Filger:RefreshTrackedSpells()
            else
                 print("|cFFFFD200Error:|r R.Filger:RefreshTrackedSpells function not found after login!")
            end
        end)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Initialize Function 
R.Filger.InitializeEditMode = function()
    -- Initialize tables if they weren't loaded from SV
    R.Filger.ManagedSpells = R.Filger.ManagedSpells or { LEFT_BUFF = {}, RIGHT_BUFF = {}, BOTTOM_BUFF = {} }
    R.Filger.FrameSettings = R.Filger.FrameSettings or {}
    
    -- Define anchor frames if they don't exist
    if not LEFT_BUFF_Anchor then
        LEFT_BUFF_Anchor = CreateFrame("Frame", "LEFT_BUFF_Anchor", UIParent)
        LEFT_BUFF_Anchor:SetSize(C.filger.buffs_size, C.filger.buffs_size)
        LEFT_BUFF_Anchor:SetPoint(unpack(C.position.filger.left_buff))
    end
    
    if not RIGHT_BUFF_Anchor then
        RIGHT_BUFF_Anchor = CreateFrame("Frame", "RIGHT_BUFF_Anchor", UIParent)
        RIGHT_BUFF_Anchor:SetSize(C.filger.buffs_size, C.filger.buffs_size)
        RIGHT_BUFF_Anchor:SetPoint(unpack(C.position.filger.right_buff))
    end
    
    if not BOTTOM_BUFF_Anchor then
        BOTTOM_BUFF_Anchor = CreateFrame("Frame", "BOTTOM_BUFF_Anchor", UIParent)
        BOTTOM_BUFF_Anchor:SetSize(C.filger.buffs_size, C.filger.buffs_size)
        BOTTOM_BUFF_Anchor:SetPoint(unpack(C.position.filger.bottom_buff))
    end

    -- Register frames with LibEditMode
    RegisterFilgerFrames()
    -- Also try direct Edit Mode integration as a fallback/companion
    if TryDirectEditModeIntegration then
        TryDirectEditModeIntegration()
    end
        
    -- Register for events to save settings (Placeholder)
    local saveFrame = CreateFrame("Frame")
    saveFrame:RegisterEvent("PLAYER_LOGOUT")
    saveFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGOUT" then
            -- Save class profile silently
            SaveAllToClassProfile()
        end
    end)
    
    -- initialization message removed to reduce chat noise
end

-- Implement Filger.UpdateAuras - Now triggers refined refresh
if not R.Filger.UpdateAuras then
    R.Filger.UpdateAuras = function(self)
        -- Silent refresh for a clean user experience
        
        -- Step 1: Rebuild the internal SpellGroups data structure
        if R.Filger.RefreshTrackedSpells then
            R.Filger:RefreshTrackedSpells()
        else
            print("|cFFFFD200Error:|r R.Filger:RefreshTrackedSpells function not found! Cannot update spell data.")
            return
        end
        
        -- Step 2: Force an update check on existing frames
        if _G.FilgerFrames then
            for _, frame in ipairs(_G.FilgerFrames) do
                -- Update display settings (size, spacing) in case they changed
                if R.Filger.UpdateDisplaySettings then
                    local frameSettings = R.Filger.FrameSettings and R.Filger.FrameSettings[frame.Name] or {}
                    R.Filger:UpdateDisplaySettings(frame.Name, nil, frameSettings)
                end
                
                -- Clear actives and re-run aura/cooldown checks
                if frame.actives then frame.actives = {} end -- Clear current display state
                
                -- Trigger relevant event handlers to re-scan
                local onEvent = frame:GetScript("OnEvent")
                if onEvent then
                    -- Check for Auras if the frame is registered for it
                    if frame:IsEventRegistered("UNIT_AURA") then
                         FindAuras(frame, "player") -- Use the global FindAuras
                         if UnitExists("target") then FindAuras(frame, "target") end
                         if UnitExists("pet") then FindAuras(frame, "pet") end
                         if UnitExists("focus") then FindAuras(frame, "focus") end
                    end
                     -- Check for Cooldowns if the frame is registered for it
                    if frame:IsEventRegistered("SPELL_UPDATE_COOLDOWN") then
                         onEvent(frame, "SPELL_UPDATE_COOLDOWN")
                    end
                    -- Add other checks (e.g., UNIT_SPELLCAST_SUCCEEDED) if necessary
                end
            end
        else
            -- No frames available to refresh
        end
    end
end
