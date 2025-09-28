local R, C, L = unpack(RefineUI)
local LEM = LibStub('LibEditMode')

--------------------------------------------------------------------------------
-- Upvalues / locals
--------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local tostring = tostring
local print = print

-- Ensure R.SelfBuffsReminder exists
R.SelfBuffsReminder = R.SelfBuffsReminder or {}

-- Initialize Frame Settings Table if it doesn't exist
R.SelfBuffsReminder.FrameSettings = R.SelfBuffsReminder.FrameSettings or {}

-- This table will hold the spells actually managed and saved
R.SelfBuffsReminder.ManagedSpells = R.SelfBuffsReminder.ManagedSpells or {}

-- Helpers (DRY)
local function EnsureSBProfile(className)
    RefineUI_SelfBuffsClassProfiles = RefineUI_SelfBuffsClassProfiles or {}
    RefineUI_SelfBuffsClassProfiles[className] = RefineUI_SelfBuffsClassProfiles[className] or {}
    return RefineUI_SelfBuffsClassProfiles[className]
end

local function SaveSBProfile(className)
    local profile = EnsureSBProfile(className)
    profile.ManagedSpells = R.SelfBuffsReminder.ManagedSpells[className]
    profile.FrameSettings = R.SelfBuffsReminder.FrameSettings[className]
end

local function SafeUpdateReminders()
    if R.SelfBuffsReminder.UpdateManagedSpells then
        R.SelfBuffsReminder.UpdateManagedSpells()
    end
end

local function AddSpell(className, spellID)
    -- Verify the spell exists
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo or not spellInfo.name then
        print("|cFFFFD200Error:|r Spell ID " .. spellID .. " does not exist.")
        return
    end

    -- Initialize class table if it doesn't exist, and populate with defaults if this is the first time
    if not R.SelfBuffsReminder.ManagedSpells[className] then
        R.SelfBuffsReminder.ManagedSpells[className] = {}
        
        -- If this class has defaults in Reminders.lua, load them first
        if R.ReminderSelfBuffs and R.ReminderSelfBuffs[className] then
            for i, group in ipairs(R.ReminderSelfBuffs[className]) do
                table.insert(R.SelfBuffsReminder.ManagedSpells[className], {
                    spells = group.spells,
                    combat = group.combat,
                    instance = group.instance,
                    pvp = group.pvp,
                    mainhand = group.mainhand,
                    offhand = group.offhand,
                    spec = group.spec,
                    level = group.level,
                })
            end
            -- Loaded defaults for class (silent)
        end
    end

    -- Check if spell is already in the list
    for i, groupData in ipairs(R.SelfBuffsReminder.ManagedSpells[className]) do
        for j, spell in ipairs(groupData.spells) do
            if spell[3] == spellID then -- spell[3] is the spellID
                print("|cFFFFD200Note:|r " .. spellInfo.name .. " (ID: " .. spellID .. ") is already in the managed list for " .. className .. ".")
                return
            end
        end
    end

    -- Create new spell entry
    local spellTexture = C_Spell.GetSpellTexture(spellID) or "Interface\\Icons\\INV_Misc_QuestionMark"
    local newSpell = {spellInfo.name, spellTexture, spellID}

    -- Create a new group for this spell (each spell gets its own group for simplicity)
    local newGroup = {
        spells = {newSpell},
        combat = true,
        instance = true,
        pvp = true,
    }

    table.insert(R.SelfBuffsReminder.ManagedSpells[className], newGroup)
    print("|cFFFFD200Added:|r " .. spellInfo.name .. " (ID: " .. spellID .. ") to managed list for " .. className)

    SaveSBProfile(className)
    SafeUpdateReminders()
end

local function RemoveSpell(className, spellID)
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local spellName = (spellInfo and spellInfo.name) or "Unknown Spell"
    local foundGroup = nil
    local foundSpellIndex = nil

    -- Find the spell in the managed lists
    if not R.SelfBuffsReminder.ManagedSpells[className] then
        print("|cFFFFD200Error:|r No managed spells found for class " .. className .. ".")
        return
    end

    for groupIndex, groupData in ipairs(R.SelfBuffsReminder.ManagedSpells[className]) do
        for spellIndex, spell in ipairs(groupData.spells) do
            if spell[3] == spellID then -- spell[3] is the spellID
                foundGroup = groupIndex
                foundSpellIndex = spellIndex
                break
            end
        end
        if foundGroup then break end
    end

    if foundGroup then
        -- Remove the spell from the group
        table.remove(R.SelfBuffsReminder.ManagedSpells[className][foundGroup].spells, foundSpellIndex)
        
        -- If the group is now empty, remove the entire group
        if #R.SelfBuffsReminder.ManagedSpells[className][foundGroup].spells == 0 then
            table.remove(R.SelfBuffsReminder.ManagedSpells[className], foundGroup)
        end
        
        print("|cFFFFD200Removed:|r " .. spellName .. " (ID: " .. spellID .. ") from managed list for " .. className .. ".")

        SaveSBProfile(className)
        SafeUpdateReminders()
    else
        print("|cFFFFD200Error:|r Spell ID " .. spellID .. " not found in the managed list for " .. className .. ".")
    end
end

local function CreateSpellEditUI(frame, className, displayName)
    displayName = displayName or className  -- Use className if displayName not provided
    local spellInput, addButton, removeButton
    local RefreshSpellList -- Declare early

    -- Create a panel for the spell management UI
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetSize(600, 500)
    panel:SetPoint("CENTER", frame, "CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.8)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)

    -- Title (also serves as drag handle)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Manage Self Buffs for " .. displayName)

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

    -- Change cursor when hovering over drag area
    dragArea:SetScript("OnEnter", function(self)
        SetCursor("Interface\\Cursor\\UI-Cursor-Move")
    end)
    dragArea:SetScript("OnLeave", function(self)
        SetCursor(nil)
    end)

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
        local input = spellInput:GetText():trim()
        if input == "" then
            print("|cffff0000Error:|r Please enter a spell name or ID.")
            return
        end

        local spellID = tonumber(input)
        if not spellID then
            -- Try to find spell by name
            local spellInfo = C_Spell.GetSpellInfo(input)
            if spellInfo and spellInfo.spellID then
                spellID = spellInfo.spellID
            else
                print("|cffff0000Error:|r Could not find spell: " .. input)
                return
            end
        end

        AddSpell(className, spellID)
        spellInput:SetText("")
        if RefreshSpellList then RefreshSpellList() end
    end)

    -- Remove Button
    removeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    removeButton:SetSize(80, 22)
    removeButton:SetPoint("LEFT", addButton, "RIGHT", 10, 0)
    removeButton:SetText("Remove")
    removeButton:SetScript("OnClick", function()
        local input = spellInput:GetText():trim()
        if input == "" then
            print("|cffff0000Error:|r Please enter a spell name or ID to remove.")
            return
        end

        local spellID = tonumber(input)
        if not spellID then
            -- Try to find spell by name
            local spellInfo = C_Spell.GetSpellInfo(input)
            if spellInfo and spellInfo.spellID then
                spellID = spellInfo.spellID
            else
                print("|cffff0000Error:|r Could not find spell: " .. input)
                return
            end
        end

        RemoveSpell(className, spellID)
        spellInput:SetText("")
        if RefreshSpellList then RefreshSpellList() end
    end)

    -- Current Spells Header
    local currentHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currentHeader:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -15)
    currentHeader:SetText("Current Spells:")
    currentHeader:SetTextColor(1, 0.82, 0)

    -- Column Headers
    local columnHeaders = CreateFrame("Frame", nil, panel)
    columnHeaders:SetSize(570, 20)
    columnHeaders:SetPoint("TOPLEFT", currentHeader, "BOTTOMLEFT", 5, -8)

    local COL = { Icon = 5, Spell = 30, ID = 220, Delete = 480 }

    local spellHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellHeader:SetPoint("LEFT", COL.Spell, 0)
    spellHeader:SetText("Spell")
    spellHeader:SetTextColor(0.9, 0.9, 0.9)

    local idHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idHeader:SetPoint("LEFT", COL.ID, 0)
    idHeader:SetText("ID")
    idHeader:SetTextColor(0.9, 0.9, 0.9)

    local deleteHeader = columnHeaders:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deleteHeader:SetPoint("LEFT", COL.Delete + 4, 0)
    deleteHeader:SetText("Delete")
    deleteHeader:SetTextColor(0.9, 0.9, 0.9)

    local headerDivider = columnHeaders:CreateTexture(nil, "ARTWORK")
    headerDivider:SetColorTexture(1, 1, 1, 0.06)
    headerDivider:SetPoint("TOPLEFT", columnHeaders, "BOTTOMLEFT", -5, -2)
    headerDivider:SetPoint("TOPRIGHT", columnHeaders, "BOTTOMRIGHT", 5, -2)
    headerDivider:SetHeight(1)

    -- Spell List (Scrollable)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(540, 320)
    scrollFrame:SetPoint("TOPLEFT", columnHeaders, "BOTTOMLEFT", 0, -5)

    local listContent = CreateFrame("Frame", nil, scrollFrame)
    listContent:SetSize(530, 1)
    scrollFrame:SetScrollChild(listContent)

    -- Close Button
    local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)

    -- Define RefreshSpellList function
    RefreshSpellList = function()
        -- Clear existing children safely
        local children = {listContent:GetChildren()}
        for i, child in ipairs(children) do
            if child then
                child:Hide()
                child:SetParent(nil)
            end
        end

        local yOffset = 0
        local spellsList = R.SelfBuffsReminder.ManagedSpells[className] or {}

        for groupIndex, groupData in ipairs(spellsList) do
            for spellIndex, spell in ipairs(groupData.spells) do
                local spellName, spellTexture, spellID = spell[1], spell[2], spell[3]

                -- Create spell row frame
                local spellRow = CreateFrame("Button", nil, listContent)
                spellRow:SetSize(540, 30)
                spellRow:SetPoint("TOPLEFT", 0, yOffset)

                local bg = spellRow:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                local shade = ((-yOffset/30) % 2 == 0) and 0.06 or 0.03
                bg:SetColorTexture(1, 1, 1, shade)
                local hl = spellRow:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                -- Icon
                local icon = spellRow:CreateTexture(nil, "BACKGROUND")
                icon:SetSize(20, 20)
                icon:SetPoint("LEFT", COL.Icon, 0)
                icon:SetTexture(spellTexture)
                icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

                -- Spell Name
                local nameText = spellRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameText:SetPoint("LEFT", COL.Spell, 0)
                nameText:SetText(spellName)

                -- Spell ID
                local idText = spellRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                idText:SetPoint("LEFT", COL.ID, 0)
                idText:SetText(tostring(spellID))

                local deleteButton = CreateFrame("Button", nil, spellRow)
                deleteButton:SetSize(20, 20)
                deleteButton:SetPoint("LEFT", COL.Delete, 0)
                if deleteButton.SetNormalAtlas then
                    deleteButton:SetNormalAtlas("GM-raidMarker-remove")
                    deleteButton:SetPushedAtlas("GM-raidMarker-remove")
                    deleteButton:SetHighlightAtlas("GM-raidMarker-remove")
                    local ht = deleteButton:GetHighlightTexture()
                    if ht then ht:SetAlpha(0.25) end
                end
                deleteButton:SetScript("OnClick", function()
                    RemoveSpell(className, spellID)
                    RefreshSpellList()
                end)

                yOffset = yOffset - 30
            end
        end

        listContent:SetHeight(math.max(-yOffset, scrollFrame:GetHeight()))
    end

    panel:Hide() -- Initially hide the panel

    -- Close panel when Edit Mode is exited using EventRegistry
    local editModeCallbackOwner = {}
    local isCallbackRegistered = false

    local function RegisterEditModeCallback()
        if not isCallbackRegistered and EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                panel:Hide()
            end, editModeCallbackOwner)
            isCallbackRegistered = true
        end
    end

    local function UnregisterEditModeCallback()
        if isCallbackRegistered and EventRegistry and EventRegistry.UnregisterCallback then
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
            RegisterEditModeCallback()
            RefreshSpellList()
        end
    end

    -- Override panel Hide to unregister callback
    local originalHide = panel.Hide
    panel.Hide = function(self)
        UnregisterEditModeCallback()
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

-- Register Self Buffs Reminder frames with LibEditMode
local function RegisterSelfBuffsReminderFrames()
    local currentClass = UnitClass("player")
    if not currentClass then return end
    
    -- Register for the current player's class only (convert to uppercase to match data keys)
    local className = string.upper(currentClass)

    -- Check available LEM functions
    local addFrameSettingsAvailable = (LEM.AddFrameSettings ~= nil)
    local addFrameButtonAvailable = (LEM.AddFrameSettingsButton ~= nil)
    local addFrameAvailable = (LEM.AddFrame ~= nil)

    if not addFrameSettingsAvailable and not addFrameButtonAvailable then
        print("|cFFFFD200Error:|r LibEditMode functions not available for Self Buffs Reminder.")
        return
    end

    -- Get the actual reminder frame (this should be created by SelfBuffsReminder.lua)
    local frameName = "SelfBuffsReminder_" .. className
    local frame = _G["RefineUI_SelfBuffsReminder"]
    
    if not frame then
        -- Create a placeholder frame if the main one doesn't exist yet
        frame = CreateFrame("Frame", "RefineUI_SelfBuffsReminder", UIParent)
        frame:SetSize(100, 32) -- Default size
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Add the frame to LibEditMode first
    if addFrameAvailable then
        -- Ensure the frame has a name for Edit Mode
        frame.EditModeFrameName = "RefineUI_SelfBuffsReminder"
        
        -- Register the frame with EditMode (pass the frame object, not string)
        LEM:AddFrame(frame, function(_, _, point, x, y)
            -- Position callback - handles frame positioning in Edit Mode
            if frame and frame:IsShown() then
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, point, x, y)
            end
        end, {
            point = "CENTER",
            x = 0,
            y = 0
        })
    end

    if addFrameButtonAvailable then
        -- Add button only for current player's class
        local buttonText = "Manage " .. currentClass .. " Self Buffs"  -- Use mixed case for display
        local toggleUI = CreateSpellEditUI(frame, className, currentClass)  -- Pass both uppercase for data and mixed case for display
        local buttonData = {
            text = buttonText,
            click = function()
                toggleUI()
            end
        }
        LEM:AddFrameSettingsButton(frame, buttonData)
    end

    if addFrameSettingsAvailable then
        local sliderSettings = {
            {
                kind = Enum.EditModeSettingDisplayType.Slider,
                name = "Spacing",
                default = 5,
                minValue = 0,
                maxValue = 20,
                valueStep = 1,
                get = function() return (R.SelfBuffsReminder.FrameSettings[className] and R.SelfBuffsReminder.FrameSettings[className].space) or 5 end,
                set = function(_, value)
                    R.SelfBuffsReminder.FrameSettings[className] = R.SelfBuffsReminder.FrameSettings[className] or {}
                    R.SelfBuffsReminder.FrameSettings[className].space = value
                    -- Save to class profile
                    SaveSBProfile(className)
                    -- Signal to refresh
                    SafeUpdateReminders()
                end
            },
            {
                kind = Enum.EditModeSettingDisplayType.Slider,
                name = "Icon Size",
                default = C.reminder.soloBuffsSize or 32,
                minValue = 16,
                maxValue = 64,
                valueStep = 1,
                get = function() return (R.SelfBuffsReminder.FrameSettings[className] and R.SelfBuffsReminder.FrameSettings[className].size) or C.reminder.soloBuffsSize or 32 end,
                set = function(_, value)
                    R.SelfBuffsReminder.FrameSettings[className] = R.SelfBuffsReminder.FrameSettings[className] or {}
                    R.SelfBuffsReminder.FrameSettings[className].size = value
                    -- Save to class profile
                    SaveSBProfile(className)
                    -- Signal to refresh
                    SafeUpdateReminders()
                end
            }
        }
        LEM:AddFrameSettings(frame, sliderSettings)
    end
end

-- Load managed spells from saved variables or populate with defaults
local function LoadManagedSpells()
    -- Initialize the base table if it doesn't exist
    R.SelfBuffsReminder.ManagedSpells = R.SelfBuffsReminder.ManagedSpells or {}

    -- Initialize class-based saved variables if they don't exist
    RefineUI_SelfBuffsClassProfiles = RefineUI_SelfBuffsClassProfiles or {}

    -- Check if we have any saved data for any class
    local hasAnySavedData = false
    for className, profileData in pairs(RefineUI_SelfBuffsClassProfiles) do
        if profileData.ManagedSpells and next(profileData.ManagedSpells) then
            hasAnySavedData = true
            break
        end
    end

    if hasAnySavedData then
        -- Load from saved class profiles
        for className, profileData in pairs(RefineUI_SelfBuffsClassProfiles) do
            if profileData.ManagedSpells then
                R.SelfBuffsReminder.ManagedSpells[className] = profileData.ManagedSpells
            end
            if profileData.FrameSettings then
                R.SelfBuffsReminder.FrameSettings[className] = profileData.FrameSettings
            end
        end
    else
        -- First time load - populate with defaults from Reminders.lua

        -- Copy from R.ReminderSelfBuffs if it exists
        if R.ReminderSelfBuffs then
            for className, classData in pairs(R.ReminderSelfBuffs) do
                R.SelfBuffsReminder.ManagedSpells[className] = {}
                for i, group in ipairs(classData) do
                    table.insert(R.SelfBuffsReminder.ManagedSpells[className], {
                        spells = group.spells,
                        combat = group.combat,
                        instance = group.instance,
                        pvp = group.pvp,
                        mainhand = group.mainhand,
                        offhand = group.offhand,
                        spec = group.spec,
                        level = group.level,
                    })
                end
                
                -- Save this initial data to class profiles immediately
                RefineUI_SelfBuffsClassProfiles[className] = RefineUI_SelfBuffsClassProfiles[className] or {}
                RefineUI_SelfBuffsClassProfiles[className].ManagedSpells = R.SelfBuffsReminder.ManagedSpells[className]
            end
        end
    end

    -- Always update the runtime table used by the main reminder system
    R.ReminderSelfBuffs = R.ReminderSelfBuffs or {}
    for className, classData in pairs(R.SelfBuffsReminder.ManagedSpells) do
        R.ReminderSelfBuffs[className] = classData
    end
end

-- Initialize on load and when ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "RefineUI" then
        self:UnregisterEvent("ADDON_LOADED")
        LoadManagedSpells()
    end
end)

-- Separate frame for PLAYER_LOGIN to ensure everything is loaded
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        RegisterSelfBuffsReminderFrames()
    end
end)

-- Initialize Function 
R.SelfBuffsReminder.InitializeEditMode = function()
    -- Initialize tables if they weren't loaded from SV
    R.SelfBuffsReminder.ManagedSpells = R.SelfBuffsReminder.ManagedSpells or {}
    -- Quiet initialization
end

-- Refresh function to signal the reminder system
R.SelfBuffsReminder.UpdateManagedSpells = function()
    -- Update the global R.ReminderSelfBuffs table used by the main reminder system
    R.ReminderSelfBuffs = R.ReminderSelfBuffs or {}
    
    for className, classData in pairs(R.SelfBuffsReminder.ManagedSpells) do
        R.ReminderSelfBuffs[className] = classData
    end
    
    -- Signal the main reminder to refresh its frames
    if R.SelfBuffsReminder and R.SelfBuffsReminder.RefreshReminders then
        R.SelfBuffsReminder.RefreshReminders()
    end
end
