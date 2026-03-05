----------------------------------------------------------------------------------------
-- Bags for RefineUI
-- Description: Core configuration and registry for the Bags module.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:RegisterModule("Bags")

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
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------------------------

local DEFAULTS = {
    Enable = true,
    ShowItemLevel = true,
    ShowQualityBorder = true,
    WindowWidth = 600,
    SlotSize = 37,
    ItemSpacingX = 5,
    ItemSpacingY = 5,
    ReagentWindowShown = false,
    CategoryOrder = {},
    CategoryEnabled = {},
    CategoryPinned = {},
    PinnedOrder = {},
    CustomCategories = {},
    CustomCategoryItems = {},
    CategorySchemaVersion = 0,
}

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function Bags.GetConfig()
    RefineUI.Config.Bags = RefineUI.Config.Bags or {}
    local cfg = RefineUI.Config.Bags

    if cfg.Enable == nil then
        cfg.Enable = DEFAULTS.Enable
    end
    if cfg.ShowItemLevel == nil then
        cfg.ShowItemLevel = DEFAULTS.ShowItemLevel
    end
    if cfg.ShowQualityBorder == nil then
        cfg.ShowQualityBorder = DEFAULTS.ShowQualityBorder
    end
    if cfg.WindowWidth == nil then
        cfg.WindowWidth = DEFAULTS.WindowWidth
    end
    if cfg.SlotSize == nil then
        cfg.SlotSize = DEFAULTS.SlotSize
    end
    if cfg.ItemSpacingX == nil then
        cfg.ItemSpacingX = DEFAULTS.ItemSpacingX
    end
    if cfg.ItemSpacingY == nil then
        cfg.ItemSpacingY = DEFAULTS.ItemSpacingY
    end
    if cfg.ReagentWindowShown == nil then
        cfg.ReagentWindowShown = DEFAULTS.ReagentWindowShown
    end

    if type(cfg.Enable) ~= "boolean" then
        cfg.Enable = cfg.Enable and true or false
    end
    if type(cfg.ShowItemLevel) ~= "boolean" then
        cfg.ShowItemLevel = cfg.ShowItemLevel and true or false
    end
    if type(cfg.ShowQualityBorder) ~= "boolean" then
        cfg.ShowQualityBorder = cfg.ShowQualityBorder and true or false
    end
    if type(cfg.WindowWidth) ~= "number" then
        cfg.WindowWidth = tonumber(cfg.WindowWidth) or DEFAULTS.WindowWidth
    end
    if type(cfg.SlotSize) ~= "number" then
        cfg.SlotSize = tonumber(cfg.SlotSize) or DEFAULTS.SlotSize
    end
    if type(cfg.ItemSpacingX) ~= "number" then
        cfg.ItemSpacingX = tonumber(cfg.ItemSpacingX) or DEFAULTS.ItemSpacingX
    end
    if type(cfg.ItemSpacingY) ~= "number" then
        cfg.ItemSpacingY = tonumber(cfg.ItemSpacingY) or DEFAULTS.ItemSpacingY
    end
    if type(cfg.ReagentWindowShown) ~= "boolean" then
        cfg.ReagentWindowShown = cfg.ReagentWindowShown and true or false
    end
    if type(cfg.CategoryOrder) ~= "table" then
        cfg.CategoryOrder = {}
    end
    if type(cfg.CategoryEnabled) ~= "table" then
        cfg.CategoryEnabled = {}
    end
    if type(cfg.CategoryPinned) ~= "table" then
        cfg.CategoryPinned = {}
    end
    if type(cfg.PinnedOrder) ~= "table" then
        cfg.PinnedOrder = {}
    end
    if type(cfg.CustomCategories) ~= "table" then
        cfg.CustomCategories = {}
    end
    if type(cfg.CustomCategoryItems) ~= "table" then
        cfg.CustomCategoryItems = {}
    end
    if type(cfg.CategorySchemaVersion) ~= "number" then
        cfg.CategorySchemaVersion = 0
    end

    return cfg
end

