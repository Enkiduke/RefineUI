----------------------------------------------------------------------------------------
-- LootRules Component: OptionControls
-- Description: Inline rule-option control rendering primitives.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local LootRules = RefineUI:GetModule("LootRules")
if not LootRules then
    return
end

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
local CreateFrame = CreateFrame
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local GetItemQualityColor = C_Item and C_Item.GetItemQualityColor or GetItemQualityColor
local C_PaperDollInfo = C_PaperDollInfo
local GetAverageItemLevel = GetAverageItemLevel
local tonumber = tonumber
local tostring = tostring
local type = type
local floor = math.floor
local max = math.max
local concat = table.concat

local FIELD_HEIGHT = 18
local FIELD_GAP = 1
local DROPDOWN_FIELD_HEIGHT = 24
local NUMBER_FIELD_HEIGHT = 24
local NUMBER_INPUT_WIDTH = 56
local NUMBER_INPUT_GAP = 6
local NUMBER_HINT_BAND = 15
local MONEY_INPUT_WIDTH = 44
local MONEY_ICON_SIZE = 12
local MONEY_GROUP_GAP = 8
local MONEY_ICON_GAP = 3
local MENU_ROW_HEIGHT = 20
local MENU_MAX_VISIBLE_ROWS = 10
local MENU_PADDING = 10

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function PlayOptionSound()
    if PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local function ApplyScrollingMenu(rootDescription, itemCount)
    if not rootDescription or not rootDescription.SetScrollMode then
        return
    end
    local rows = tonumber(itemCount) or 0
    if rows < 1 then
        rows = 1
    elseif rows > MENU_MAX_VISIBLE_ROWS then
        rows = MENU_MAX_VISIBLE_ROWS
    end
    rootDescription:SetScrollMode((rows * MENU_ROW_HEIGHT) + MENU_PADDING)
end

local function SetDropdownDisplayText(dropdown, text)
    if not dropdown then
        return
    end
    local value = text or ""
    if dropdown.OverrideText then
        dropdown:OverrideText(value)
    elseif dropdown.SetDefaultText then
        dropdown:SetDefaultText(value)
    elseif dropdown.Text and dropdown.Text.SetText then
        dropdown.Text:SetText(value)
    end
end

local function ClampNumber(value, minValue, maxValue)
    if minValue and value < minValue then
        value = minValue
    end
    if maxValue and value > maxValue then
        value = maxValue
    end
    return value
end

local function RoundToStep(value, step)
    if not step or step <= 0 then
        return value
    end
    return floor((value / step) + 0.5) * step
end

local function SetStepperValue(stepper, value)
    if not stepper then
        return
    end
    if stepper.SetValue then
        stepper:SetValue(value)
    elseif stepper.Slider and stepper.Slider.SetValue then
        stepper.Slider:SetValue(value)
    end
end

local function ToHexByte(component)
    local value = tonumber(component) or 1
    if value < 0 then
        value = 0
    elseif value > 1 then
        value = 1
    end
    return ("%02x"):format(floor((value * 255) + 0.5))
end

local function GetQualityHex(quality)
    if not GetItemQualityColor then
        return nil
    end

    local r, g, b = GetItemQualityColor(quality)
    if r == nil or g == nil or b == nil then
        return nil
    end

    return ("|cff%s%s%s"):format(ToHexByte(r), ToHexByte(g), ToHexByte(b))
end

local function BuildEnumLabel(field, entry)
    local label = (entry and entry.label) or (entry and tostring(entry.value)) or ""
    if not (field and field.quality_colors and entry and type(entry.value) == "number") then
        return label
    end

    local hex = GetQualityHex(entry.value)
    if not hex then
        return label
    end

    return hex .. label .. "|r"
end

local function NormalizeCopperValue(value)
    value = tonumber(value) or 0
    value = floor(value + 0.5)
    if value < 0 then
        value = 0
    end
    return value
end

local function CopperToParts(value)
    local total = NormalizeCopperValue(value)
    local gold = floor(total / 10000)
    local silver = floor((total - (gold * 10000)) / 100)
    local copper = total - (gold * 10000) - (silver * 100)
    return gold, silver, copper
end

local function PartsToCopper(gold, silver, copper)
    gold = NormalizeCopperValue(gold)
    silver = NormalizeCopperValue(silver)
    copper = NormalizeCopperValue(copper)

    if silver > 99 then
        silver = 99
    end
    if copper > 99 then
        copper = 99
    end

    return (gold * 10000) + (silver * 100) + copper, gold, silver, copper
end

local function EnsureNested(root, key)
    if type(root[key]) ~= "table" then
        root[key] = {}
    end
    return root[key]
end

local function FindEnumIndex(values, current)
    if type(values) ~= "table" or #values == 0 then
        return 1
    end
    for i = 1, #values do
        if values[i].value == current then
            return i
        end
    end
    return 1
end

local function GetMultiToggleSummary(bucket, choices)
    local selected = {}
    local total = type(choices) == "table" and #choices or 0
    local selectedCount = 0

    for i = 1, total do
        local choice = choices[i]
        if bucket[choice.key] then
            selectedCount = selectedCount + 1
            selected[#selected + 1] = choice.label or choice.key
        end
    end

    if selectedCount == 0 then
        return "None"
    end
    if selectedCount == total and total > 0 then
        return "All"
    end
    if selectedCount <= 3 then
        return concat(selected, ", ")
    end
    return tostring(selectedCount) .. " selected"
end

local function ResetRowPools(row)
    row._inlineFrameUsed = 0
end

local function AcquireRowFrame(row, frameType, template)
    row._inlineFramePool = row._inlineFramePool or {}
    row._inlineFrameUsed = (row._inlineFrameUsed or 0) + 1
    local index = row._inlineFrameUsed
    local frame = row._inlineFramePool[index]

    if frame and (frame._inlineType ~= frameType or frame._inlineTemplate ~= template) then
        local swapIndex = nil
        for i = index + 1, #row._inlineFramePool do
            local candidate = row._inlineFramePool[i]
            if candidate and candidate._inlineType == frameType and candidate._inlineTemplate == template then
                swapIndex = i
                break
            end
        end

        if swapIndex then
            row._inlineFramePool[index], row._inlineFramePool[swapIndex] = row._inlineFramePool[swapIndex], row._inlineFramePool[index]
            frame = row._inlineFramePool[index]
        else
            local replaced = frame
            frame = CreateFrame(frameType, nil, row.OptionsHost, template)
            frame._inlineType = frameType
            frame._inlineTemplate = template
            row._inlineFramePool[index] = frame
            if replaced then
                replaced:Hide()
                row._inlineFramePool[#row._inlineFramePool + 1] = replaced
            end
        end
    elseif not frame then
        frame = CreateFrame(frameType, nil, row.OptionsHost, template)
        frame._inlineType = frameType
        frame._inlineTemplate = template
        row._inlineFramePool[index] = frame
    end

    frame:SetParent(row.OptionsHost)
    frame:ClearAllPoints()
    frame:Show()
    return frame
end

local function ReleaseRowOptions(row)
    if not row then
        return
    end
    if row._inlineFramePool then
        for i = 1, #row._inlineFramePool do
            row._inlineFramePool[i]:Hide()
        end
    end
end

local function HideUnusedControls(row)
    if row._inlineFramePool then
        for i = (row._inlineFrameUsed or 0) + 1, #row._inlineFramePool do
            row._inlineFramePool[i]:Hide()
        end
    end
end

local function CreateFieldRow(row, y)
    local fieldRow = AcquireRowFrame(row, "Frame", nil)
    fieldRow:SetPoint("TOPLEFT", row.OptionsHost, "TOPLEFT", 0, y)
    fieldRow:SetPoint("TOPRIGHT", row.OptionsHost, "TOPRIGHT", 0, y)
    fieldRow:SetHeight(FIELD_HEIGHT)
    return fieldRow
end

local function ApplyControlBackdrop(frame)
    if frame._lootRulesStyled then
        return
    end
    frame._lootRulesStyled = true

    if RefineUI and RefineUI.SetTemplate then
        RefineUI.SetTemplate(frame, "Transparent")
    else
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.08, 0.1, 0.15, 0.9)
        frame:SetBackdropBorderColor(0.32, 0.4, 0.56, 0.9)
    end
end

local function BuildNumberControl(row, options, field, y, maxWidth)
    local fieldRow = CreateFieldRow(row, y)
    local playerItemLevel = 0
    if field.default_percent_of_player_ilvl or field.dynamic_max_percent_of_player_ilvl or field.show_player_ilvl_percent then
        if C_PaperDollInfo and C_PaperDollInfo.GetAverageItemLevel then
            local avg, equipped = C_PaperDollInfo.GetAverageItemLevel()
            playerItemLevel = tonumber(equipped) or tonumber(avg) or 0
        elseif GetAverageItemLevel then
            local avg, equipped = GetAverageItemLevel()
            playerItemLevel = tonumber(equipped) or tonumber(avg) or 0
        end
    end

    local showPercentHint = field.show_player_ilvl_percent and true or false
    fieldRow:SetHeight(NUMBER_FIELD_HEIGHT)

    local controlRow = AcquireRowFrame(row, "Frame", nil)
    controlRow:SetParent(fieldRow)
    controlRow:SetPoint("TOPLEFT", fieldRow, "TOPLEFT", 0, 0)
    controlRow:SetPoint("TOPRIGHT", fieldRow, "TOPRIGHT", 0, 0)
    controlRow:SetHeight(NUMBER_FIELD_HEIGHT)

    local controlWidth = max(140, maxWidth)
    local minValue = tonumber(field.min) or 0
    local maxValue = tonumber(field.max) or (minValue + 100)
    if maxValue < minValue then
        minValue, maxValue = maxValue, minValue
    end

    local dynamicMaxPercent = tonumber(field.dynamic_max_percent_of_player_ilvl)
    if dynamicMaxPercent and dynamicMaxPercent > 0 and playerItemLevel > 0 then
        maxValue = floor((playerItemLevel * dynamicMaxPercent) + 0.5)
        local minDynamicMax = tonumber(field.min_dynamic_max) or 0
        if maxValue < minDynamicMax then
            maxValue = minDynamicMax
        end
        if maxValue < minValue then
            maxValue = minValue
        end
    end

    local stepSize = tonumber(field.step) or (field.integer and 1 or 0.1)
    if stepSize <= 0 then
        stepSize = field.integer and 1 or 0.1
    end
    local steps = max(1, floor(((maxValue - minValue) / stepSize) + 0.5))

    local function Normalize(value)
        value = tonumber(value) or minValue
        if field.integer then
            value = floor(value + 0.5)
        else
            value = RoundToStep(value, stepSize)
        end
        value = ClampNumber(value, minValue, maxValue)
        return value
    end

    if field.default_percent_of_player_ilvl and playerItemLevel > 0 then
        local raw = options[field.key]
        local numericRaw = tonumber(raw)
        if raw == nil or (field.default_when_negative and numericRaw and numericRaw < 0) then
            options[field.key] = floor((playerItemLevel * tonumber(field.default_percent_of_player_ilvl)) + 0.5)
        end
    end

    local currentValue = Normalize(options[field.key])
    options[field.key] = currentValue

    local stepper = AcquireRowFrame(row, "Frame", "MinimalSliderWithSteppersTemplate")
    stepper:SetParent(controlRow)
    stepper:SetPoint("TOPLEFT", controlRow, "TOPLEFT", 0, -1)
    stepper:SetPoint("BOTTOMLEFT", controlRow, "BOTTOMLEFT", 0, showPercentHint and NUMBER_HINT_BAND or 1)
    stepper:SetWidth(controlWidth - NUMBER_INPUT_WIDTH - NUMBER_INPUT_GAP)
    stepper:Show()
    if stepper.SetEnabled then
        stepper:SetEnabled(true)
    end

    local inputHolder = AcquireRowFrame(row, "Frame", "BackdropTemplate")
    inputHolder:SetParent(controlRow)
    inputHolder:SetPoint("TOPRIGHT", controlRow, "TOPRIGHT", 0, -1)
    inputHolder:SetPoint("BOTTOMRIGHT", controlRow, "BOTTOMRIGHT", 0, 1)
    inputHolder:SetWidth(NUMBER_INPUT_WIDTH)
    ApplyControlBackdrop(inputHolder)

    local edit = AcquireRowFrame(row, "EditBox", nil)
    edit:SetParent(inputHolder)
    edit:SetPoint("TOPLEFT", inputHolder, "TOPLEFT", 6, -1)
    edit:SetPoint("BOTTOMRIGHT", inputHolder, "BOTTOMRIGHT", -6, 1)
    edit:SetAutoFocus(false)
    if edit.SetFontObject then
        edit:SetFontObject("GameFontHighlightSmall")
    end
    if edit.SetNumeric then
        edit:SetNumeric(field.integer and true or false)
    end
    edit:SetJustifyH("RIGHT")

    stepper._lootRulesNumberState = stepper._lootRulesNumberState or {}
    stepper._lootRulesNumberState.options = options
    stepper._lootRulesNumberState.key = field.key
    stepper._lootRulesNumberState.edit = edit
    stepper._lootRulesNumberState.normalize = Normalize

    local helperText = controlRow._lootRulesPercentText
    if not helperText then
        helperText = controlRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        controlRow._lootRulesPercentText = helperText
    end

    if showPercentHint then
        helperText:ClearAllPoints()
        helperText:SetPoint("CENTER", stepper, "BOTTOM", 0, -6)
        helperText:SetJustifyH("CENTER")
        helperText:Show()
    else
        helperText:SetText("")
        helperText:Hide()
    end

    local function UpdatePercentHint()
        if not helperText or not helperText:IsShown() then
            return
        end
        if playerItemLevel <= 0 then
            helperText:SetText("Current iLvl unavailable")
            return
        end
        local current = tonumber(options[field.key]) or 0
        local percent = (current / playerItemLevel) * 100
        helperText:SetText(("%.0f%% of current iLvl (%.1f)"):format(percent, playerItemLevel))
    end

    local function HandleStepperValueChanged(value)
        if stepper._lootRulesNumberSyncing then
            return
        end
        local state = stepper._lootRulesNumberState
        if not state then
            return
        end
        local normalized = state.normalize(value)
        state.options[state.key] = normalized
        stepper._lootRulesNumberSyncing = true
        SetStepperValue(stepper, normalized)
        if state.edit then
            state.edit:SetText(tostring(normalized))
        end
        UpdatePercentHint()
        stepper._lootRulesNumberSyncing = nil
    end

    if not stepper._lootRulesNumberCallback and stepper.RegisterCallback then
        stepper._lootRulesNumberCallback = function(_, value)
            HandleStepperValueChanged(value)
        end
        stepper:RegisterCallback("OnValueChanged", stepper._lootRulesNumberCallback, stepper)
    elseif not stepper._lootRulesNumberScript and stepper.Slider and stepper.Slider.SetScript then
        stepper._lootRulesNumberScript = function(_, value)
            HandleStepperValueChanged(value)
        end
        stepper.Slider:SetScript("OnValueChanged", stepper._lootRulesNumberScript)
    end

    stepper._lootRulesNumberSyncing = true
    if stepper.Init then
        stepper:Init(currentValue, minValue, maxValue, steps)
    else
        if stepper.SetMinMaxValues then
            stepper:SetMinMaxValues(minValue, maxValue)
        end
        if stepper.SetValueStep then
            stepper:SetValueStep(stepSize)
        end
        if stepper.SetObeyStepOnDrag then
            stepper:SetObeyStepOnDrag(true)
        end
        SetStepperValue(stepper, currentValue)
    end
    stepper._lootRulesNumberSyncing = nil

    edit:SetText(tostring(currentValue))

    local function CommitFromEdit(playSound)
        local parsed = tonumber(edit:GetText() or "")
        local normalized = Normalize(parsed)
        options[field.key] = normalized
        stepper._lootRulesNumberSyncing = true
        SetStepperValue(stepper, normalized)
        stepper._lootRulesNumberSyncing = nil
        edit:SetText(tostring(normalized))
        UpdatePercentHint()
        if playSound then
            PlayOptionSound()
        end
    end

    edit:SetScript("OnEnterPressed", function(self)
        CommitFromEdit(true)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function()
        CommitFromEdit(false)
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(options[field.key] or currentValue))
        self:ClearFocus()
    end)

    UpdatePercentHint()

    return y - (NUMBER_FIELD_HEIGHT + FIELD_GAP)
end

local function BuildMoneyControl(row, options, field, y, maxWidth)
    local fieldRow = CreateFieldRow(row, y)
    fieldRow:SetHeight(NUMBER_FIELD_HEIGHT)

    local controlWidth = max(220, maxWidth)
    local groupWidth = ((MONEY_INPUT_WIDTH + MONEY_ICON_SIZE + MONEY_ICON_GAP) * 3) + (MONEY_GROUP_GAP * 2)
    local startX = controlWidth - groupWidth
    if startX < 0 then
        startX = 0
    end

    local container = AcquireRowFrame(row, "Frame", nil)
    container:SetParent(fieldRow)
    container:SetPoint("TOPLEFT", fieldRow, "TOPLEFT", startX, 0)
    container:SetPoint("BOTTOMLEFT", fieldRow, "BOTTOMLEFT", startX, 0)
    container:SetWidth(groupWidth)

    local function BuildCoinInput(xOffset, iconTexture, maxLetters)
        local holder = AcquireRowFrame(row, "Frame", "BackdropTemplate")
        holder:SetParent(container)
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset, -1)
        holder:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", xOffset, 1)
        holder:SetWidth(MONEY_INPUT_WIDTH + MONEY_ICON_SIZE + MONEY_ICON_GAP)
        ApplyControlBackdrop(holder)

        local icon = holder._coinIcon
        if not icon then
            icon = holder:CreateTexture(nil, "ARTWORK")
            holder._coinIcon = icon
        end
        icon:SetSize(MONEY_ICON_SIZE, MONEY_ICON_SIZE)
        icon:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
        icon:SetTexture(iconTexture)

        local edit = AcquireRowFrame(row, "EditBox", nil)
        edit:SetParent(holder)
        edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -1)
        edit:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -MONEY_ICON_GAP, 1)
        edit:SetAutoFocus(false)
        if edit.SetFontObject then
            edit:SetFontObject("GameFontHighlightSmall")
        end
        if edit.SetNumeric then
            edit:SetNumeric(true)
        end
        if edit.SetMaxLetters and maxLetters then
            edit:SetMaxLetters(maxLetters)
        end
        edit:SetJustifyH("RIGHT")

        return edit
    end

    local goldEdit = BuildCoinInput(0, GOLD_ICON, 8)
    local silverEdit = BuildCoinInput(MONEY_INPUT_WIDTH + MONEY_ICON_SIZE + MONEY_ICON_GAP + MONEY_GROUP_GAP, SILVER_ICON, 2)
    local copperEdit = BuildCoinInput(((MONEY_INPUT_WIDTH + MONEY_ICON_SIZE + MONEY_ICON_GAP) * 2) + (MONEY_GROUP_GAP * 2), COPPER_ICON, 2)

    local maxGold = tonumber(field.max_gold) or 1000000
    if maxGold < 0 then
        maxGold = 0
    end

    local legacyKey = field.legacy_key
    local initialCopper = options[field.key]
    if initialCopper == nil and legacyKey and options[legacyKey] ~= nil then
        initialCopper = (tonumber(options[legacyKey]) or 0) * 10000
    end

    local gold, silver, copper = CopperToParts(initialCopper)
    if gold > maxGold then
        gold = maxGold
    end
    local normalizedCopper
    normalizedCopper, gold, silver, copper = PartsToCopper(gold, silver, copper)
    options[field.key] = normalizedCopper
    if legacyKey then
        options[legacyKey] = nil
    end

    local function ReadCoinValue(edit, fallback, maxValue)
        local value = tonumber(edit:GetText() or "")
        if value == nil then
            value = fallback or 0
        end
        value = floor(value + 0.5)
        if value < 0 then
            value = 0
        end
        if maxValue and value > maxValue then
            value = maxValue
        end
        return value
    end

    local function UpdateTexts()
        goldEdit:SetText(tostring(gold))
        silverEdit:SetText(tostring(silver))
        copperEdit:SetText(tostring(copper))
    end

    local function Commit(playSound)
        local nextGold = ReadCoinValue(goldEdit, gold, maxGold)
        local nextSilver = ReadCoinValue(silverEdit, silver, 99)
        local nextCopper = ReadCoinValue(copperEdit, copper, 99)

        local total
        total, gold, silver, copper = PartsToCopper(nextGold, nextSilver, nextCopper)
        if gold > maxGold then
            total, gold, silver, copper = PartsToCopper(maxGold, silver, copper)
        end

        options[field.key] = total
        if legacyKey then
            options[legacyKey] = nil
        end
        UpdateTexts()

        if playSound then
            PlayOptionSound()
        end
    end

    local function AttachHandlers(edit)
        edit:SetScript("OnEnterPressed", function(self)
            Commit(true)
            self:ClearFocus()
        end)
        edit:SetScript("OnEditFocusLost", function()
            Commit(false)
        end)
        edit:SetScript("OnEscapePressed", function(self)
            UpdateTexts()
            self:ClearFocus()
        end)
    end

    AttachHandlers(goldEdit)
    AttachHandlers(silverEdit)
    AttachHandlers(copperEdit)
    UpdateTexts()

    return y - (NUMBER_FIELD_HEIGHT + FIELD_GAP)
end

local function BuildEnumControl(row, options, field, y, maxWidth)
    local fieldRow = CreateFieldRow(row, y)
    fieldRow:SetHeight(DROPDOWN_FIELD_HEIGHT)

    local values = field.values or {}
    local currentIndex = FindEnumIndex(values, options[field.key])
    if values[currentIndex] then
        options[field.key] = values[currentIndex].value
    end

    local controlWidth = max(120, maxWidth)

    local button = AcquireRowFrame(row, "DropdownButton", "WowStyle1DropdownTemplate")
    button:SetParent(fieldRow)
    button:SetPoint("TOPLEFT", fieldRow, "TOPLEFT", 0, -1)
    button:SetWidth(controlWidth)
    button:SetHeight(DROPDOWN_FIELD_HEIGHT)

    local function Apply(index, silent)
        if #values == 0 then
            SetDropdownDisplayText(button, "No values")
            return
        end
        if index < 1 then
            index = #values
        elseif index > #values then
            index = 1
        end
        currentIndex = index
        options[field.key] = values[currentIndex].value
        SetDropdownDisplayText(button, BuildEnumLabel(field, values[currentIndex]))
        if not silent then
            PlayOptionSound()
        end
    end

    button:SetupMenu(function(_, rootDescription)
        ApplyScrollingMenu(rootDescription, #values)
        for i = 1, #values do
            local entry = values[i]
            local entryIndex = i
            local entryValue = entry.value
            local entryLabel = BuildEnumLabel(field, entry)
            rootDescription:CreateRadio(entryLabel, function()
                return options[field.key] == entryValue
            end, function()
                Apply(entryIndex)
            end)
        end
    end)
    Apply(currentIndex, true)

    return y - (DROPDOWN_FIELD_HEIGHT + FIELD_GAP)
end

local function BuildMultiToggleControl(row, options, field, y, maxWidth)
    local fieldRow = CreateFieldRow(row, y)
    fieldRow:SetHeight(DROPDOWN_FIELD_HEIGHT)

    local controlWidth = max(140, maxWidth)
    local bucket = EnsureNested(options, field.key)
    local choices = field.choices or {}

    local button = AcquireRowFrame(row, "DropdownButton", "WowStyle1DropdownTemplate")
    button:SetParent(fieldRow)
    button:SetPoint("TOPLEFT", fieldRow, "TOPLEFT", 0, -1)
    button:SetWidth(controlWidth)
    button:SetHeight(DROPDOWN_FIELD_HEIGHT)

    local function RefreshSummaryText()
        SetDropdownDisplayText(button, GetMultiToggleSummary(bucket, choices))
    end

    button:SetupMenu(function(_, rootDescription)
        ApplyScrollingMenu(rootDescription, #choices)
        for i = 1, #choices do
            local choice = choices[i]
            local choiceKey = choice.key
            local choiceLabel = choice.label or choiceKey
            rootDescription:CreateCheckbox(choiceLabel, function()
                return bucket[choiceKey] and true or false
            end, function()
                bucket[choiceKey] = not bucket[choiceKey]
                RefreshSummaryText()
                PlayOptionSound()
            end)
        end
    end)

    RefreshSummaryText()

    return y - (DROPDOWN_FIELD_HEIGHT + FIELD_GAP)
end

local function BuildFieldControl(row, options, field, y, maxWidth)
    if not field or type(field) ~= "table" then
        return y
    end
    if field.type == "number" then
        return BuildNumberControl(row, options, field, y, maxWidth)
    end
    if field.type == "money" then
        return BuildMoneyControl(row, options, field, y, maxWidth)
    end
    if field.type == "enum" then
        return BuildEnumControl(row, options, field, y, maxWidth)
    end
    if field.type == "multi_toggle" then
        return BuildMultiToggleControl(row, options, field, y, maxWidth)
    end
    return y
end

local function GetFieldRenderHeight(field)
    if type(field) == "table" and (field.type == "enum" or field.type == "multi_toggle") then
        return DROPDOWN_FIELD_HEIGHT
    end
    if type(field) == "table" and field.type == "number" then
        return NUMBER_FIELD_HEIGHT
    end
    if type(field) == "table" and field.type == "money" then
        return NUMBER_FIELD_HEIGHT
    end
    return FIELD_HEIGHT
end

local function EstimateSchemaHeight(schema)
    if type(schema) ~= "table" or #schema == 0 then
        return 0
    end
    local total = 0
    for i = 1, #schema do
        total = total + GetFieldRenderHeight(schema[i])
        if i < #schema then
            total = total + FIELD_GAP
        end
    end
    return total
end

----------------------------------------------------------------------------------------
-- Public Component Data
----------------------------------------------------------------------------------------
LootRules.OptionControlRenderer = LootRules.OptionControlRenderer or {}
local OptionControlRenderer = LootRules.OptionControlRenderer

OptionControlRenderer.FIELD_HEIGHT = FIELD_HEIGHT
OptionControlRenderer.FIELD_GAP = FIELD_GAP
OptionControlRenderer.DROPDOWN_FIELD_HEIGHT = DROPDOWN_FIELD_HEIGHT
OptionControlRenderer.NUMBER_FIELD_HEIGHT = NUMBER_FIELD_HEIGHT
OptionControlRenderer.ResetRowPools = ResetRowPools
OptionControlRenderer.ReleaseRowOptions = ReleaseRowOptions
OptionControlRenderer.HideUnusedControls = HideUnusedControls
OptionControlRenderer.BuildFieldControl = BuildFieldControl
OptionControlRenderer.EstimateSchemaHeight = EstimateSchemaHeight

