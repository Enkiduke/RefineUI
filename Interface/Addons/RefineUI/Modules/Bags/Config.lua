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
-- Constants
----------------------------------------------------------------------------------------

Bags.BAG_VIEW_MODE = Bags.BAG_VIEW_MODE or {
    CATEGORIES = "Categories",
    COMBINED = "Combined",
    BY_BAG = "ByBag",
}

Bags.SORT_MODE = Bags.SORT_MODE or {
    BLIZZARD = "Blizzard",
    TYPE = "Type",
    QUALITY = "Quality",
    NAME = "Name",
}

----------------------------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------------------------

local DEFAULTS = {
    Enable = true,
    ShowItemLevel = true,
    ShowQualityBorder = true,
    WindowWidth = 600,
    SlotSize = 36,
    ItemSpacingX = 5,
    ItemSpacingY = 2,
    ViewMode = Bags.BAG_VIEW_MODE.CATEGORIES,
    CombinedSortMode = Bags.SORT_MODE.BLIZZARD,
    ByBagSortMode = Bags.SORT_MODE.BLIZZARD,
    ReagentWindowShown = false,
    CategoryOrder = {},
    CategoryEnabled = {},
    CategoryPinned = {},
    PinnedOrder = {},
    CustomCategories = {},
    CustomCategoryItems = {},
    CategorySchemaVersion = 0,
}

local function NormalizeSortMode(value)
    if value == Bags.SORT_MODE.TYPE or value == Bags.SORT_MODE.QUALITY or value == Bags.SORT_MODE.NAME then
        return value
    end
    return Bags.SORT_MODE.BLIZZARD
end

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
    if cfg.ViewMode == nil then
        cfg.ViewMode = DEFAULTS.ViewMode
    end
    if cfg.CombinedSortMode == nil then
        cfg.CombinedSortMode = DEFAULTS.CombinedSortMode
    end
    if cfg.ByBagSortMode == nil then
        cfg.ByBagSortMode = DEFAULTS.ByBagSortMode
    end
    if cfg.ReagentWindowShown == nil then
        cfg.ReagentWindowShown = DEFAULTS.ReagentWindowShown
    end

    if type(cfg.Enable) ~= "boolean" then
        cfg.Enable = cfg.Enable and true or false
    end
    cfg.ShowItemLevel = true
    cfg.ShowQualityBorder = true
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
    cfg.CombinedSortMode = NormalizeSortMode(cfg.CombinedSortMode)
    cfg.ByBagSortMode = NormalizeSortMode(cfg.ByBagSortMode)
    if cfg.ViewMode ~= Bags.BAG_VIEW_MODE.COMBINED and cfg.ViewMode ~= Bags.BAG_VIEW_MODE.BY_BAG then
        cfg.ViewMode = Bags.BAG_VIEW_MODE.CATEGORIES
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

function Bags.GetViewMode()
    local cfg = Bags.GetConfig and Bags.GetConfig() or {}
    if cfg.ViewMode == Bags.BAG_VIEW_MODE.COMBINED then
        return Bags.BAG_VIEW_MODE.COMBINED
    end
    if cfg.ViewMode == Bags.BAG_VIEW_MODE.BY_BAG then
        return Bags.BAG_VIEW_MODE.BY_BAG
    end
    return Bags.BAG_VIEW_MODE.CATEGORIES
end

function Bags.IsCombinedViewEnabled()
    return Bags.GetViewMode and Bags.GetViewMode() == Bags.BAG_VIEW_MODE.COMBINED
end

function Bags.IsBagViewEnabled()
    return Bags.GetViewMode and Bags.GetViewMode() == Bags.BAG_VIEW_MODE.BY_BAG
end

function Bags.ShouldShowSortControl()
    local viewMode = Bags.GetViewMode and Bags.GetViewMode()
    return viewMode == Bags.BAG_VIEW_MODE.COMBINED or viewMode == Bags.BAG_VIEW_MODE.BY_BAG
end

function Bags.GetSortModeForView(viewMode)
    local cfg = Bags.GetConfig and Bags.GetConfig() or {}
    if viewMode == Bags.BAG_VIEW_MODE.COMBINED then
        return NormalizeSortMode(cfg.CombinedSortMode)
    end
    if viewMode == Bags.BAG_VIEW_MODE.BY_BAG then
        return Bags.SORT_MODE.BLIZZARD
    end
    return Bags.SORT_MODE.BLIZZARD
end

function Bags.GetActiveSortMode()
    local viewMode = Bags.GetViewMode and Bags.GetViewMode()
    return Bags.GetSortModeForView and Bags.GetSortModeForView(viewMode)
end

function Bags.SetSortModeForView(viewMode, sortMode)
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then return end

    local normalized = NormalizeSortMode(sortMode)
    if viewMode == Bags.BAG_VIEW_MODE.COMBINED then
        cfg.CombinedSortMode = normalized
    end
end
