----------------------------------------------------------------------------------------
-- Bags Component: Edit Mode
-- Description: Edit Mode integration and settings for the Bags module.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:GetModule("Bags")
if not Bags then return end

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
local type = type
local unpack = unpack
local tonumber = tonumber
local math = math
local table = table

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function ResolveDefaultPosition()
    local cfg = Bags.GetConfig and Bags.GetConfig() or {}

    if type(cfg.Position) == "table" then
        local p, _, _, x, y = unpack(cfg.Position)
        return {
            point = p or "BOTTOMRIGHT",
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
        }
    end

    local pos = RefineUI.Positions and RefineUI.Positions["RefineUI_Bags"]
    if type(pos) == "table" then
        local p, _, _, x, y = unpack(pos)
        return {
            point = p or "BOTTOMRIGHT",
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
        }
    end

    return {
        point = "BOTTOMRIGHT",
        x = -50,
        y = 100,
    }
end

local function RefreshBagLayout()
    if Bags.ApplyLayoutConfig then
        Bags.ApplyLayoutConfig()
    end

    if Bags.Frame and Bags.Frame.UpdateLayout then
        Bags.Frame:UpdateLayout()
    end
end

----------------------------------------------------------------------------------------
-- Settings Panel
----------------------------------------------------------------------------------------

function Bags.RegisterEditModeSettings()
    if not RefineUI.LibEditMode or Bags._editModeSettingsRegistered then
        return
    end

    local settings = {}

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Window Width",
        default = 600,
        minValue = 420,
        maxValue = 1200,
        valueStep = 10,
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.WindowWidth or 600
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.WindowWidth = math.floor((tonumber(value) or 600) + 0.5)
            RefreshBagLayout()
        end,
    })

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Slot Size",
        default = 37,
        minValue = 24,
        maxValue = 56,
        valueStep = 1,
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.SlotSize or 37
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.SlotSize = math.floor((tonumber(value) or 37) + 0.5)
            RefreshBagLayout()
            if Bags.RequestUpdate then
                Bags.RequestUpdate()
            end
        end,
    })

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Horizontal Spacing",
        default = 5,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.ItemSpacingX or 5
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.ItemSpacingX = math.floor((tonumber(value) or 5) + 0.5)
            RefreshBagLayout()
            if Bags.RequestUpdate then
                Bags.RequestUpdate()
            end
        end,
    })

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Vertical Spacing",
        default = 5,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.ItemSpacingY or 5
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.ItemSpacingY = math.floor((tonumber(value) or 5) + 0.5)
            RefreshBagLayout()
            if Bags.RequestUpdate then
                Bags.RequestUpdate()
            end
        end,
    })

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Quality Borders",
        default = true,
        values = {
            { text = "Enabled", value = true },
            { text = "Disabled", value = false },
        },
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.ShowQualityBorder ~= false
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.ShowQualityBorder = value and true or false
            if Bags.RequestUpdate then
                Bags.RequestUpdate()
            end
        end,
    })

    table.insert(settings, {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Item Level Text",
        default = true,
        values = {
            { text = "Enabled", value = true },
            { text = "Disabled", value = false },
        },
        get = function()
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            return cfg.ShowItemLevel ~= false
        end,
        set = function(_, value)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.ShowItemLevel = value and true or false
            if Bags.RequestUpdate then
                Bags.RequestUpdate()
            end
        end,
    })

    Bags._editModeSettings = settings
    Bags._editModeSettingsRegistered = true
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function Bags.InitializeEditMode()
    if not RefineUI.LibEditMode or Bags._editModeInitialized or not Bags.Frame then
        return
    end

    Bags.RegisterEditModeSettings()

    local frame = Bags.Frame
    local default = ResolveDefaultPosition()

    if not Bags._editModeFrameRegistered then
        RefineUI.LibEditMode:AddFrame(frame, function(_, _, point, x, y)
            local cfg = Bags.GetConfig and Bags.GetConfig() or {}
            cfg.Position = cfg.Position or {}
            cfg.Position[1] = point
            cfg.Position[2] = "UIParent"
            cfg.Position[3] = point
            cfg.Position[4] = x
            cfg.Position[5] = y
        end, default, "Bags")
        Bags._editModeFrameRegistered = true
    end

    if Bags._editModeSettings and not Bags._editModeSettingsAttached then
        RefineUI.LibEditMode:AddFrameSettings(frame, Bags._editModeSettings)
        Bags._editModeSettingsAttached = true
    end

    if not Bags._editModeCallbacksRegistered then
        RefineUI.LibEditMode:RegisterCallback("enter", function()
            Bags._editModeActive = true
            if Bags.Frame then
                Bags._bagWasShownBeforeEditMode = Bags.Frame:IsShown()
                if not Bags.Frame:IsShown() then
                    Bags.Frame:Show()
                end
                Bags.Frame:UpdateLayout(true)
                if Bags.RequestUpdate then
                    Bags.RequestUpdate({ forceReflow = true, renderOnly = true })
                end
            end
            if Bags.RefreshCategoryManagerVisibility then
                Bags.RefreshCategoryManagerVisibility()
            end
        end)

        RefineUI.LibEditMode:RegisterCallback("exit", function()
            Bags._editModeActive = false
            if Bags.Frame and not Bags._bagWasShownBeforeEditMode and Bags.Frame:IsShown() then
                Bags.Frame:Hide()
            end
            Bags._bagWasShownBeforeEditMode = nil
            if Bags.HideCategoryManagerWindow then
                Bags.HideCategoryManagerWindow()
            end
        end)

        Bags._editModeCallbacksRegistered = true
    end

    if Bags.HookCategoryManagerToDialog then
        Bags.HookCategoryManagerToDialog()
    end

    Bags._editModeInitialized = true
end

Bags.InitializeEditMode()

