----------------------------------------------------------------------------------------
-- UnitFrames Component: Target Aura Settings
-- Description: Edit Mode companion dialog for Target/Focus aura layout controls.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local CreateMinimalSliderFormatter = CreateMinimalSliderFormatter
local floor = math.floor
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local PlaySound = PlaySound
local tostring = tostring
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local settingsWindow
local settingsDialogHooked = false

local WINDOW_WIDTH = 300
local WINDOW_HEIGHT = 578
local CONTROL_WIDTH = 343
local DIALOG_GAP = 8
local TOP_OFFSET = -47

local SLIDERS = {
    { key = "Size", label = "Aura Size", min = 8, max = 30, step = 1 },
    { key = "LargeSize", label = "Large Aura Size", min = 8, max = 36, step = 1 },
    { key = "HorizontalSpacing", label = "Horizontal Spacing", min = 0, max = 16, step = 1 },
    { key = "VerticalSpacing", label = "Vertical Spacing", min = 0, max = 16, step = 1 },
    { key = "GroupGap", label = "Buff/Debuff Gap", min = 0, max = 24, step = 1 },
    { key = "OffsetX", label = "Anchor X Offset", min = -40, max = 40, step = 1 },
    { key = "OffsetY", label = "Anchor Y Offset", min = 0, max = 40, step = 1 },
    { key = "WrapWidth", label = "Wrap Width", min = 40, max = 200, step = 1 },
    { key = "WrapWidthWithToT", label = "Wrap Width With ToT", min = 40, max = 200, step = 1 },
}

local COLOR_SWATCHES = {
    { key = "SmallBuffBorderColor", label = "Small Buff Border" },
    { key = "LargeBuffBorderColor", label = "Large Buff Border" },
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsTargetOrFocusEditModeSystem(systemFrame)
    local enum = _G.Enum
    if not systemFrame or type(systemFrame) ~= "table" or type(enum) ~= "table" then
        return false
    end

    if systemFrame.system ~= (enum.EditModeSystem and enum.EditModeSystem.UnitFrame) then
        return false
    end

    local index = systemFrame.systemIndex
    local indices = enum.EditModeUnitFrameSystemIndices
    return indices and (index == indices.Target or index == indices.Focus)
end

local function GetTargetOrFocusSystemKey(systemFrame)
    local indices = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    if not indices or not systemFrame then
        return nil
    end

    if systemFrame.systemIndex == indices.Target then
        return "target"
    end
    if systemFrame.systemIndex == indices.Focus then
        return "focus"
    end

    return nil
end

local function GetAuraConfigBySystemKey(systemKey)
    if systemKey == "focus" then
        Config.UnitFrames.FocusAuras = Config.UnitFrames.FocusAuras or {}
        return Config.UnitFrames.FocusAuras
    end

    Config.UnitFrames.TargetAuras = Config.UnitFrames.TargetAuras or {}
    return Config.UnitFrames.TargetAuras
end

local function GetDefaultAuraConfigBySystemKey(systemKey)
    local defaults = RefineUI.DefaultConfig and RefineUI.DefaultConfig.UnitFrames
    if not defaults then
        return nil
    end

    if systemKey == "focus" then
        return defaults.FocusAuras
    end

    return defaults.TargetAuras
end

local function RefreshAuraLayoutForSystemKey(systemKey)
    if systemKey == "focus" then
        UnitFrames.RefreshTargetFocusAuraLayout(FocusFrame)
        return
    end

    UnitFrames.RefreshTargetFocusAuraLayout(TargetFrame)
end

local function ApplyDefaultAuraConfig(systemKey)
    local cfg = GetAuraConfigBySystemKey(systemKey)
    local defaults = GetDefaultAuraConfigBySystemKey(systemKey)
    if not cfg or not defaults then
        return
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            local copy = {}
            for index = 1, #value do
                copy[index] = value[index]
            end
            cfg[key] = copy
        else
            cfg[key] = value
        end
    end
end

local function RoundSliderValue(definition, value)
    local numeric = tonumber(value) or definition.min or 0
    local step = definition.step or 1
    if step <= 0 then
        step = 1
    end

    numeric = floor((numeric / step) + 0.5) * step
    if numeric < definition.min then
        numeric = definition.min
    elseif numeric > definition.max then
        numeric = definition.max
    end

    if step == floor(step) then
        numeric = floor(numeric + 0.5)
    end

    return numeric
end

local function SetSliderRowEnabled(row, enabled)
    row.Slider:SetEnabled(enabled)
    row.Label:SetTextColor((enabled and WHITE_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
    row:SetAlpha(enabled and 1 or 0.6)
end

local function SetCheckboxRowEnabled(row, enabled)
    row.Button:SetEnabled(enabled)
    row.Label:SetTextColor((enabled and WHITE_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
    row:SetAlpha(enabled and 1 or 0.6)
end

local function NormalizeColorValue(value, fallback)
    local source = type(value) == "table" and value or fallback
    if type(source) ~= "table" then
        source = { 1, 1, 1 }
    end

    return {
        type(source[1]) == "number" and source[1] or 1,
        type(source[2]) == "number" and source[2] or 1,
        type(source[3]) == "number" and source[3] or 1,
    }
end

local function CreateCheckboxRow(parent, label)
    local row = CreateFrame("Frame", nil, parent, "EditModeSettingCheckboxTemplate")
    row:SetSize(CONTROL_WIDTH, 32)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, TOP_OFFSET)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, TOP_OFFSET)
    row.Label:SetText(label)

    function row:SetChecked(checked)
        self.Button:SetChecked(checked and true or false)
    end

    return row
end

local function CreateSliderRow(parent, definition, anchor)
    local row = CreateFrame("Frame", nil, parent, "EditModeSettingSliderTemplate")
    row:SetSize(CONTROL_WIDTH, 32)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    row:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    row.definition = definition
    row.Label:SetText(definition.label)
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Slider:SetWidth(200)
    row.Slider.MinText:Hide()
    row.Slider.MaxText:Hide()

    row.OnSliderValueChanged = function(self, value)
        local roundedValue = RoundSliderValue(self.definition, value)
        if not self.ownerWindow or self.ownerWindow.isRefreshing then
            return
        end

        if value ~= roundedValue then
            self.initInProgress = true
            self.Slider:SetValue(roundedValue)
            self.initInProgress = false
            return
        end

        self.ownerWindow:ApplyChange(self.definition.key, roundedValue)
    end

    row.OnSliderInteractStart = function() end
    row.OnSliderInteractEnd = function() end
    row:OnLoad()

    local steps = (definition.max - definition.min) / (definition.step or 1)
    row.formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right,
            function(value)
                return tostring(RoundSliderValue(definition, value))
            end
        ),
    }

    row.initInProgress = true
    row.Slider:Init(definition.min, definition.min, definition.max, steps, row.formatters)
    row.initInProgress = false

    return row
end

local function CreateColorSwatchRow(parent, definition, anchor)
    local row = CreateFrame("Frame", nil, parent, "ResizeLayoutFrame")
    row:SetSize(CONTROL_WIDTH, 32)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    row:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    row.definition = definition

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Label:SetSize(140, 32)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(definition.label)

    row.Swatch = CreateFrame("Button", nil, row, "ColorSwatchTemplate")
    row.Swatch:SetSize(32, 32)
    row.Swatch:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)

    function row:SetColor(color)
        local normalized = NormalizeColorValue(color)
        self.color = normalized
        self.Swatch:SetColorRGB(normalized[1], normalized[2], normalized[3])
    end

    function row:SetSettingEnabled(enabled)
        self.Swatch:SetEnabled(enabled)
        self.Label:SetTextColor((enabled and WHITE_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
        self:SetAlpha(enabled and 1 or 0.6)
    end

    row.Swatch:SetScript("OnClick", function()
        if row.ownerWindow and row.ownerWindow.isRefreshing then
            return
        end
        if not ColorPickerFrame or type(ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
            return
        end

        local oldColor = NormalizeColorValue(row.color)
        ColorPickerFrame:SetupColorPickerAndShow({
            hasOpacity = false,
            r = oldColor[1],
            g = oldColor[2],
            b = oldColor[3],
            opacity = 1,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                row:SetColor({ r, g, b })
                row.ownerWindow:ApplyChange(row.definition.key, { r, g, b })
            end,
            opacityFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                row:SetColor({ r, g, b })
                row.ownerWindow:ApplyChange(row.definition.key, { r, g, b })
            end,
            cancelFunc = function()
                row:SetColor(oldColor)
                row.ownerWindow:ApplyChange(row.definition.key, oldColor)
            end,
        })
    end)

    return row
end

local function PositionSettingsWindow(window, dialog)
    if not window or not dialog then
        return
    end

    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -DIALOG_GAP)
    window:SetPoint("TOPRIGHT", dialog, "BOTTOMRIGHT", 0, -DIALOG_GAP)
end

local function EnsureSettingsWindow()
    if settingsWindow then
        return settingsWindow
    end

    local window = CreateFrame("Frame", "RefineUI_TargetFocusAuraSettingsWindow", UIParent, "ResizeLayoutFrame")
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(240)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:Hide()

    window.Border = CreateFrame("Frame", nil, window, "DialogBorderTranslucentTemplate")
    window.Border:SetAllPoints()
    window.Border:EnableMouse(false)

    window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    window.Title:SetPoint("TOP", 0, -15)

    window.CloseButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    window.CloseButton:SetPoint("TOPRIGHT")
    window.CloseButton:SetScript("OnClick", function()
        local dialog = _G.EditModeSystemSettingsDialog
        if dialog and dialog.CloseButton and dialog.CloseButton:IsShown() then
            dialog.CloseButton:Click()
        else
            window:Hide()
        end
    end)

    window.EnableCheck = CreateCheckboxRow(window, "Use Custom Dense Aura Layout")
    window.EnableCheck.ownerWindow = window
    window.EnableCheck.OnCheckButtonClick = function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self.ownerWindow:ApplyChange("Enable", self.Button:GetChecked() == true)
    end

    window.OnlyPlayerDebuffsCheck = CreateCheckboxRow(window, "Only Player Debuffs on Enemies")
    window.OnlyPlayerDebuffsCheck.ownerWindow = window
    window.OnlyPlayerDebuffsCheck:ClearAllPoints()
    window.OnlyPlayerDebuffsCheck:SetPoint("TOPLEFT", window.EnableCheck, "BOTTOMLEFT", 0, -2)
    window.OnlyPlayerDebuffsCheck:SetPoint("TOPRIGHT", window.EnableCheck, "BOTTOMRIGHT", 0, -2)
    window.OnlyPlayerDebuffsCheck.OnCheckButtonClick = function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        self.ownerWindow:ApplyChange("OnlyPlayerDebuffsOnEnemies", self.Button:GetChecked() == true)
    end

    window.Sliders = {}
    local previous = window.OnlyPlayerDebuffsCheck
    for index = 1, #SLIDERS do
        local slider = CreateSliderRow(window, SLIDERS[index], previous)
        slider.ownerWindow = window
        slider:Show()
        window.Sliders[#window.Sliders + 1] = slider
        previous = slider
    end

    window.ColorRows = {}
    for index = 1, #COLOR_SWATCHES do
        local row = CreateColorSwatchRow(window, COLOR_SWATCHES[index], previous)
        row.ownerWindow = window
        row:Show()
        window.ColorRows[#window.ColorRows + 1] = row
        previous = row
    end
    window.EnableCheck:Show()
    window.OnlyPlayerDebuffsCheck:Show()

    window.Divider = window:CreateTexture(nil, "ARTWORK")
    window.Divider:SetTexture([[Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider]])
    window.Divider:SetSize(330, 16)
    window.Divider:SetPoint("LEFT", window, "LEFT", 20, 0)
    window.Divider:SetPoint("RIGHT", window, "RIGHT", -20, 0)

    window.ResetButton = CreateFrame("Button", nil, window, "EditModeSystemSettingsDialogButtonTemplate")
    window.ResetButton:SetPoint("BOTTOM", window, "BOTTOM", 0, 16)
    window.ResetButton:SetText(RESET_TO_DEFAULT)
    window.ResetButton:SetScript("OnClick", function()
        local systemKey = window:GetSystemKey()
        if not systemKey then
            return
        end

        ApplyDefaultAuraConfig(systemKey)
        window:RefreshValues()
        RefreshAuraLayoutForSystemKey(systemKey)
    end)

    window.Divider:SetPoint("BOTTOM", window.ResetButton, "TOP", 0, 6)

    function window:GetSystemKey()
        return self.systemKey
    end

    function window:GetSystemConfig()
        local systemKey = self:GetSystemKey()
        return systemKey and GetAuraConfigBySystemKey(systemKey) or nil
    end

    function window:UpdateControlState()
        local cfg = self:GetSystemConfig()
        local enabled = cfg and cfg.Enable ~= false or false

        SetCheckboxRowEnabled(self.OnlyPlayerDebuffsCheck, enabled)
        for index = 1, #self.Sliders do
            SetSliderRowEnabled(self.Sliders[index], enabled)
        end
        for index = 1, #self.ColorRows do
            self.ColorRows[index]:SetSettingEnabled(enabled)
        end
    end

    function window:RefreshValues()
        local cfg = self:GetSystemConfig()
        if not cfg then
            return
        end

        self.isRefreshing = true
        self.EnableCheck:SetChecked(cfg.Enable ~= false)
        self.OnlyPlayerDebuffsCheck:SetChecked(cfg.OnlyPlayerDebuffsOnEnemies == true)

        for index = 1, #self.Sliders do
            local slider = self.Sliders[index]
            local key = slider.definition.key
            local value = RoundSliderValue(slider.definition, cfg[key] or slider.definition.min)

            slider.initInProgress = true
            slider.Slider:SetValue(value)
            slider.initInProgress = false
        end

        for index = 1, #self.ColorRows do
            local row = self.ColorRows[index]
            row:SetColor(cfg[row.definition.key])
        end

        self.isRefreshing = false
        self:UpdateControlState()
    end

    function window:ApplyChange(key, value)
        if self.isRefreshing then
            return
        end

        local cfg = self:GetSystemConfig()
        if not cfg then
            return
        end

        cfg[key] = value
        self:UpdateControlState()
        RefreshAuraLayoutForSystemKey(self:GetSystemKey())
    end

    settingsWindow = window
    return settingsWindow
end

local function RefreshSettingsWindowVisibility(systemFrame)
    local editMode = _G.EditModeManagerFrame
    local dialog = _G.EditModeSystemSettingsDialog
    local inEditMode = editMode and editMode.IsEditModeActive and editMode:IsEditModeActive()
    local activeSystem = systemFrame or (dialog and dialog.attachedToSystem)

    if not inEditMode or not dialog or not dialog:IsShown() or not IsTargetOrFocusEditModeSystem(activeSystem) then
        if settingsWindow then
            settingsWindow:Hide()
        end
        return
    end

    local systemKey = GetTargetOrFocusSystemKey(activeSystem)
    if not systemKey then
        if settingsWindow then
            settingsWindow:Hide()
        end
        return
    end

    local window = EnsureSettingsWindow()
    window.systemKey = systemKey
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 20)
    window.Title:SetText(systemKey == "focus" and "Focus Aura Layout" or "Target Aura Layout")
    window:RefreshValues()
    PositionSettingsWindow(window, dialog)
    window:Show()
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function UnitFrames:HookTargetFocusAuraSettingsDialog()
    if settingsDialogHooked then
        return
    end

    local dialog = _G.EditModeSystemSettingsDialog
    if not dialog then
        return
    end

    hooksecurefunc(dialog, "UpdateDialog", function(_, systemFrame)
        RefreshSettingsWindowVisibility(systemFrame)
    end)
    dialog:HookScript("OnShow", function(self)
        RefreshSettingsWindowVisibility(self.attachedToSystem)
    end)
    dialog:HookScript("OnHide", function()
        if settingsWindow then
            settingsWindow:Hide()
        end
    end)
    dialog:HookScript("OnSizeChanged", function(self)
        if settingsWindow and settingsWindow:IsShown() then
            PositionSettingsWindow(settingsWindow, self)
        end
    end)

    local editMode = _G.EditModeManagerFrame
    if editMode then
        hooksecurefunc(editMode, "ExitEditMode", function()
            if settingsWindow then
                settingsWindow:Hide()
            end
        end)
    end

    settingsDialogHooked = true
    RefreshSettingsWindowVisibility(dialog.attachedToSystem)
end
