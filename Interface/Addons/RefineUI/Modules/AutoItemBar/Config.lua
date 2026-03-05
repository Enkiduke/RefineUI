----------------------------------------------------------------------------------------
-- AutoItemBar Component: Config
-- Description: Configuration schema and EditMode integrations.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local Config = RefineUI.Config

local tonumber = tonumber
local type = type
local ipairs = ipairs
local floor = math.floor

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local DEFAULTS = {
    ButtonSize = 36,
    ButtonSpacing = 6,
    ButtonLimit = AutoItemBar.BUTTONS_PER_LINE,
    BarAlpha = 1,
    BarVisible = AutoItemBar.VISIBILITY_MOUSEOVER,
    MinItemLevel = 1,
    Orientation = AutoItemBar.ORIENTATION_HORIZONTAL,
    ButtonWrap = AutoItemBar.WRAP_FORWARD,
    ButtonDirection = AutoItemBar.DIRECTION_FORWARD,
    ShowPotions = true,
    ShowFlasks = true,
    ShowFoodAndDrink = true,
    ShowItemEnhancements = true,
    ShowOtherConsumables = true,
    TrackedItems = {},
    HiddenItems = {},
    EnabledOrder = {},
}

----------------------------------------------------------------------------------------
--	Config API
----------------------------------------------------------------------------------------

function AutoItemBar:GetConfig()
    Config.Automation = Config.Automation or {}
    Config.Automation.AutoItemBar = Config.Automation.AutoItemBar or {}

    local cfg = Config.Automation.AutoItemBar

    if cfg.ButtonSize == nil then cfg.ButtonSize = DEFAULTS.ButtonSize end
    if cfg.ButtonSpacing == nil then cfg.ButtonSpacing = DEFAULTS.ButtonSpacing end
    if type(cfg.ButtonLimit) ~= "number" then
        cfg.ButtonLimit = DEFAULTS.ButtonLimit
    end
    if cfg.ButtonLimit < 1 then
        cfg.ButtonLimit = 1
    elseif cfg.ButtonLimit > AutoItemBar.BUTTONS_PER_LINE then
        cfg.ButtonLimit = AutoItemBar.BUTTONS_PER_LINE
    end
    if type(cfg.BarAlpha) ~= "number" then
        cfg.BarAlpha = DEFAULTS.BarAlpha
    end
    if cfg.BarAlpha < 0 then
        cfg.BarAlpha = 0
    elseif cfg.BarAlpha > 1 then
        cfg.BarAlpha = 1
    end
    if type(cfg.BarVisible) ~= "string" then
        if cfg.MouseOver == false then
            cfg.BarVisible = AutoItemBar.VISIBILITY_ALWAYS
        else
            cfg.BarVisible = DEFAULTS.BarVisible
        end
    end
    if cfg.BarVisible ~= AutoItemBar.VISIBILITY_ALWAYS
        and cfg.BarVisible ~= AutoItemBar.VISIBILITY_IN_COMBAT
        and cfg.BarVisible ~= AutoItemBar.VISIBILITY_OUT_OF_COMBAT
        and cfg.BarVisible ~= AutoItemBar.VISIBILITY_NEVER then
        cfg.BarVisible = AutoItemBar.VISIBILITY_MOUSEOVER
    end
    if cfg.MinItemLevel == nil then cfg.MinItemLevel = DEFAULTS.MinItemLevel end
    if cfg.ShowPotions == nil then cfg.ShowPotions = DEFAULTS.ShowPotions end
    if cfg.ShowFlasks == nil then cfg.ShowFlasks = DEFAULTS.ShowFlasks end
    if cfg.ShowFoodAndDrink == nil then cfg.ShowFoodAndDrink = DEFAULTS.ShowFoodAndDrink end
    if cfg.ShowItemEnhancements == nil then cfg.ShowItemEnhancements = DEFAULTS.ShowItemEnhancements end
    if cfg.ShowOtherConsumables == nil then cfg.ShowOtherConsumables = DEFAULTS.ShowOtherConsumables end
    if cfg.Orientation ~= AutoItemBar.ORIENTATION_VERTICAL then
        cfg.Orientation = AutoItemBar.ORIENTATION_HORIZONTAL
    end
    if cfg.ButtonWrap ~= AutoItemBar.WRAP_REVERSE then
        cfg.ButtonWrap = AutoItemBar.WRAP_FORWARD
    end
    if cfg.ButtonDirection ~= AutoItemBar.DIRECTION_REVERSE then
        cfg.ButtonDirection = AutoItemBar.DIRECTION_FORWARD
    end
    if type(cfg.TrackedItems) ~= "table" then
        cfg.TrackedItems = {}
    end
    if type(cfg.HiddenItems) ~= "table" then
        cfg.HiddenItems = {}
    end
    if type(cfg.CategoryOrder) ~= "table" then
        cfg.CategoryOrder = {}
    end
    if type(cfg.CategoryEnabled) ~= "table" then
        cfg.CategoryEnabled = {}
    end
    if type(cfg.CategorySchemaVersion) ~= "number" then
        cfg.CategorySchemaVersion = 0
    end
    if type(cfg.EnabledOrder) ~= "table" then
        cfg.EnabledOrder = {}
    end
    if cfg.EditModeTutorialSeen == nil then
        cfg.EditModeTutorialSeen = false
    end

    return cfg
end

function AutoItemBar:GetButtonLimit()
    local cfg = self:GetConfig()
    return cfg.ButtonLimit or AutoItemBar.BUTTONS_PER_LINE
end

function AutoItemBar:GetBarVisibilityMode()
    local cfg = self:GetConfig()
    local mode = cfg.BarVisible
    if mode == AutoItemBar.VISIBILITY_ALWAYS
        or mode == AutoItemBar.VISIBILITY_IN_COMBAT
        or mode == AutoItemBar.VISIBILITY_OUT_OF_COMBAT
        or mode == AutoItemBar.VISIBILITY_NEVER then
        return mode
    end
    return AutoItemBar.VISIBILITY_MOUSEOVER
end

function AutoItemBar:GetButtonWrap()
    local cfg = self:GetConfig()
    return (cfg.ButtonWrap == AutoItemBar.WRAP_REVERSE) and AutoItemBar.WRAP_REVERSE or AutoItemBar.WRAP_FORWARD
end

function AutoItemBar:GetButtonDirection()
    local cfg = self:GetConfig()
    return (cfg.ButtonDirection == AutoItemBar.DIRECTION_REVERSE) and AutoItemBar.DIRECTION_REVERSE or AutoItemBar.DIRECTION_FORWARD
end

function AutoItemBar:GetButtonDirectionLabel(value)
    local orientation = self:GetOrientation()
    if orientation == AutoItemBar.ORIENTATION_VERTICAL then
        return (value == AutoItemBar.DIRECTION_REVERSE) and "Bottom to Top" or "Top to Bottom"
    end
    return (value == AutoItemBar.DIRECTION_REVERSE) and "Right to Left" or "Left to Right"
end

function AutoItemBar:GetButtonWrapLabel(value)
    local orientation = self:GetOrientation()
    if orientation == AutoItemBar.ORIENTATION_VERTICAL then
        return (value == AutoItemBar.WRAP_REVERSE) and "Wrap Left" or "Wrap Right"
    end
    return (value == AutoItemBar.WRAP_REVERSE) and "Wrap Up" or "Wrap Down"
end

function AutoItemBar:GetCategoryDefaultEnabled(definition)
    if not definition then
        return true
    end
    return definition.defaultEnabled ~= false
end

function AutoItemBar:GetOrientation()
    local cfg = self:GetConfig()
    return (cfg.Orientation == AutoItemBar.ORIENTATION_VERTICAL) and AutoItemBar.ORIENTATION_VERTICAL or AutoItemBar.ORIENTATION_HORIZONTAL
end

function AutoItemBar:RegisterEditModeSettings()
    if not RefineUI.LibEditMode or self._editModeSettingsRegistered then
        return
    end

    local function RoundAlpha(value)
        local alpha = tonumber(value) or DEFAULTS.BarAlpha
        alpha = floor((alpha * 20) + 0.5) / 20
        if alpha < 0 then
            alpha = 0
        elseif alpha > 1 then
            alpha = 1
        end
        return alpha
    end

    local settings = {}

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Orientation",
        default = DEFAULTS.Orientation,
        values = {
            { text = "Horizontal", value = AutoItemBar.ORIENTATION_HORIZONTAL },
            { text = "Vertical", value = AutoItemBar.ORIENTATION_VERTICAL },
        },
        get = function()
            return self:GetOrientation()
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.Orientation = (value == AutoItemBar.ORIENTATION_VERTICAL) and AutoItemBar.ORIENTATION_VERTICAL or AutoItemBar.ORIENTATION_HORIZONTAL
            if self.InvalidateLayoutCache then
                self:InvalidateLayoutCache()
            end
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Button Size",
        default = DEFAULTS.ButtonSize,
        minValue = 20,
        maxValue = 60,
        valueStep = 1,
        get = function()
            return self:GetConfig().ButtonSize
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.ButtonSize = value
            self.buttonSize = value
            if self.InvalidateLayoutCache then
                self:InvalidateLayoutCache()
            end
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Button Spacing",
        default = DEFAULTS.ButtonSpacing,
        minValue = 1,
        maxValue = 20,
        valueStep = 1,
        get = function()
            return self:GetConfig().ButtonSpacing
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.ButtonSpacing = value
            self.buttonSpacing = value
            if self.InvalidateLayoutCache then
                self:InvalidateLayoutCache()
            end
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Button Limit",
        default = DEFAULTS.ButtonLimit,
        minValue = 1,
        maxValue = AutoItemBar.BUTTONS_PER_LINE,
        valueStep = 1,
        get = function()
            return self:GetButtonLimit()
        end,
        set = function(_, value)
            local config = self:GetConfig()
            local limit = tonumber(value) or DEFAULTS.ButtonLimit
            if limit < 1 then
                limit = 1
            elseif limit > AutoItemBar.BUTTONS_PER_LINE then
                limit = AutoItemBar.BUTTONS_PER_LINE
            end
            config.ButtonLimit = limit
            if self.InvalidateLayoutCache then
                self:InvalidateLayoutCache()
            end
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Button Direction",
        default = DEFAULTS.ButtonDirection,
        generator = function(_, rootDescription)
            local options = {
                AutoItemBar.DIRECTION_FORWARD,
                AutoItemBar.DIRECTION_REVERSE,
            }
            for _, value in ipairs(options) do
                rootDescription:CreateRadio(
                    self:GetButtonDirectionLabel(value),
                    function(data)
                        return self:GetButtonDirection() == data.value
                    end,
                    function(data)
                        local config = self:GetConfig()
                        config.ButtonDirection = data.value
                        self:RequestUpdate()
                    end,
                    { value = value }
                )
            end
        end,
        get = function()
            return self:GetButtonDirection()
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.ButtonDirection = (value == AutoItemBar.DIRECTION_REVERSE) and AutoItemBar.DIRECTION_REVERSE or AutoItemBar.DIRECTION_FORWARD
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Button Wrap",
        default = DEFAULTS.ButtonWrap,
        generator = function(_, rootDescription)
            local options = {
                AutoItemBar.WRAP_FORWARD,
                AutoItemBar.WRAP_REVERSE,
            }
            for _, value in ipairs(options) do
                rootDescription:CreateRadio(
                    self:GetButtonWrapLabel(value),
                    function(data)
                        return self:GetButtonWrap() == data.value
                    end,
                    function(data)
                        local config = self:GetConfig()
                        config.ButtonWrap = data.value
                        self:RequestUpdate()
                    end,
                    { value = value }
                )
            end
        end,
        get = function()
            return self:GetButtonWrap()
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.ButtonWrap = (value == AutoItemBar.WRAP_REVERSE) and AutoItemBar.WRAP_REVERSE or AutoItemBar.WRAP_FORWARD
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Bar Visible",
        default = DEFAULTS.BarVisible,
        values = {
            { text = "Always Visible", value = AutoItemBar.VISIBILITY_ALWAYS },
            { text = "Mouseover", value = AutoItemBar.VISIBILITY_MOUSEOVER },
            { text = "Out of Combat", value = AutoItemBar.VISIBILITY_OUT_OF_COMBAT },
            { text = "In Combat", value = AutoItemBar.VISIBILITY_IN_COMBAT },
            { text = "Never", value = AutoItemBar.VISIBILITY_NEVER },
        },
        get = function()
            return self:GetBarVisibilityMode()
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.BarVisible = value
            self:UpdateBarVisibility()
            self:ShowBar()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Bar Alpha",
        default = DEFAULTS.BarAlpha,
        minValue = 0,
        maxValue = 1,
        valueStep = 0.05,
        formatter = function(value)
            local alpha = tonumber(value) or DEFAULTS.BarAlpha
            alpha = floor((alpha * 100) + 0.5) / 100
            return alpha
        end,
        get = function()
            local alpha = self:GetConfig().BarAlpha or DEFAULTS.BarAlpha
            return RoundAlpha(alpha)
        end,
        set = function(_, value)
            local config = self:GetConfig()
            config.BarAlpha = RoundAlpha(value)
            self._lastVisibleState = nil
            self:EvaluateMouseoverVisibility()
        end,
    }

    self._editModeSettings = settings
    self._editModeSettingsRegistered = true
end
