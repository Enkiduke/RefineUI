----------------------------------------------------------------------------------------
-- LootRules Component: Definitions
-- Description: Rule catalog and option schema definitions.
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
-- Constants
----------------------------------------------------------------------------------------
local STAGE_LOOT = "LOOT"
local STAGE_SELL = "SELL"

local CATEGORY_CHOICES = {
    { key = "equipment", label = "Equipment" },
    { key = "trade_goods", label = "Trade Goods" },
    { key = "consumables", label = "Consumables" },
    { key = "recipes", label = "Recipes" },
    { key = "gems", label = "Gems" },
    { key = "junk", label = "Junk" },
    { key = "misc", label = "Misc" },
}

local SELL_CATEGORY_CHOICES = {
    { key = "equipment", label = "Equipment" },
    { key = "trade_goods", label = "Trade Goods" },
    { key = "consumables", label = "Consumables" },
    { key = "recipes", label = "Recipes" },
    { key = "gems", label = "Gems" },
    { key = "misc", label = "Misc" },
}

local SELL_BIND_CHOICES = {
    { key = "boe", label = "BoE" },
    { key = "warbound", label = "WuE/Warbound" },
    { key = "soulbound", label = "Soulbound" },
}

local USABILITY_CHOICES = {
    { key = "usable", label = "Usable" },
    { key = "unusable", label = "Unusable" },
}

local QUALITY_VALUES = {
    { value = 0, label = "Poor" },
    { value = 1, label = "Common" },
    { value = 2, label = "Uncommon" },
    { value = 3, label = "Rare" },
    { value = 4, label = "Epic" },
    { value = 5, label = "Legendary" },
}

local EXPANSION_LABELS = {
    [1] = "Burning Crusade",
    [2] = "Wrath of the Lich King",
    [3] = "Cataclysm",
    [4] = "Mists of Pandaria",
    [5] = "Warlords of Draenor",
    [6] = "Legion",
    [7] = "Battle for Azeroth",
    [8] = "Shadowlands",
    [9] = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function BuildExpansionChoices()
    local choices = {}
    local maxKnown = 11
    for expansionID = maxKnown, 1, -1 do
        choices[#choices + 1] = {
            key = tostring(expansionID),
            label = EXPANSION_LABELS[expansionID] or ("Expansion " .. expansionID),
        }
    end
    return choices
end

local EXPANSION_CHOICES = BuildExpansionChoices()

local function BuildDefaultExpansionSelection()
    local selected = {}
    for i = 1, #EXPANSION_CHOICES do
        selected[EXPANSION_CHOICES[i].key] = true
    end
    return selected
end

----------------------------------------------------------------------------------------
-- Public Component Data
----------------------------------------------------------------------------------------
LootRules.STAGE_LOOT = STAGE_LOOT
LootRules.STAGE_SELL = STAGE_SELL
LootRules.STAGE_LABELS = {
    [STAGE_LOOT] = "Loot",
    [STAGE_SELL] = "Sell",
}

LootRules.DEFAULT_RULES = {
    {
        id = "loot_always_uncollected",
        stage = STAGE_LOOT,
        enabled = true,
        action = "LOOT",
        title = "Always Loot Uncollected",
        summary = "Always loot uncollected appearances, toys, pets, and mounts.",
        options = {},
    },
    {
        id = "loot_always_quest_items",
        stage = STAGE_LOOT,
        enabled = true,
        action = "LOOT",
        title = "Always Loot Quest Items",
        summary = "Always loot quest-related items.",
        options = {},
    },
    {
        id = "loot_filter_quality",
        stage = STAGE_LOOT,
        enabled = false,
        action = "SKIP",
        title = "Skip Loot if Quality Below",
        summary = "Skip loot if item quality is below this threshold.",
        options = {
            min_quality = 0,
        },
    },
    {
        id = "loot_filter_value",
        stage = STAGE_LOOT,
        enabled = false,
        action = "SKIP",
        title = "Skip Loot if Vendor Value Below",
        summary = "Skip loot if vendor value is below this threshold.",
        options = {
            min_copper = 0,
        },
    },
    {
        id = "loot_filter_expansion",
        stage = STAGE_LOOT,
        enabled = false,
        action = "SKIP",
        title = "Skip Loot for Excluded Expansions",
        summary = "Skip loot if an item belongs to an excluded expansion.",
        options = {
            expansions = {},
        },
    },
    {
        id = "loot_filter_categories",
        stage = STAGE_LOOT,
        enabled = false,
        action = "SKIP",
        title = "Skip Loot for Excluded Categories",
        summary = "Skip loot if an item belongs to an excluded category.",
        options = {
            categories = {
                equipment = false,
                trade_goods = false,
                consumables = false,
                recipes = false,
                gems = false,
                junk = false,
                misc = false,
            },
        },
    },
    {
        id = "loot_filter_min_item_level",
        stage = STAGE_LOOT,
        enabled = false,
        action = "SKIP",
        title = "Skip Loot if Item Level Below",
        summary = "Skip equipment if item level is below this threshold.",
        options = {
            min_ilvl = 0,
        },
    },
    {
        id = "sell_always_keep_equipment_set",
        stage = STAGE_SELL,
        enabled = true,
        action = "KEEP",
        title = "Always Keep Equipment Set",
        summary = "Never auto-sell items in any equipment set.",
        options = {},
    },
    {
        id = "sell_always_keep_boe_wue",
        stage = STAGE_SELL,
        enabled = true,
        action = "KEEP",
        title = "Always Keep BoE / WuE",
        summary = "Never auto-sell BoE/WuE items.",
        options = {},
    },
    {
        id = "sell_always_sell_junk",
        stage = STAGE_SELL,
        enabled = true,
        action = "SELL",
        title = "Always Sell Junk",
        summary = "Always sell poor quality junk items.",
        options = {},
    },
    {
        id = "sell_filter_quality",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Quality",
        summary = "Sell items up to this quality.",
        options = {
            max_quality = 1,
        },
    },
    {
        id = "sell_filter_value",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Value",
        summary = "Sell only if vendor value meets this threshold.",
        options = {
            min_copper = 0,
        },
    },
    {
        id = "sell_filter_expansion",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Expansion",
        summary = "Sell items from selected expansions.",
        options = {
            expansions = BuildDefaultExpansionSelection(),
        },
    },
    {
        id = "sell_filter_categories",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Categories",
        summary = "Sell only selected categories.",
        options = {
            categories = {
                equipment = true,
                trade_goods = true,
                consumables = true,
                recipes = false,
                gems = false,
                misc = false,
            },
        },
    },
    {
        id = "sell_filter_max_item_level",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Max Item Level",
        summary = "Sell equipment at or below this item level.",
        options = {
            max_ilvl = -1,
        },
    },
    {
        id = "sell_filter_bind",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Bind",
        summary = "Sell only selected bind types.",
        options = {
            bind = {
                boe = false,
                warbound = false,
                soulbound = true,
            },
        },
    },
    {
        id = "sell_filter_usability",
        stage = STAGE_SELL,
        enabled = false,
        action = "SELL",
        title = "Filter Usability",
        summary = "Sell only selected usability states.",
        options = {
            usability = {
                usable = false,
                unusable = true,
            },
        },
    },
}

LootRules.RULE_OPTION_SCHEMAS = {
    loot_filter_quality = {
        { type = "enum", key = "min_quality", label = "Min Quality", values = QUALITY_VALUES, quality_colors = true },
    },
    loot_filter_value = {
        { type = "money", key = "min_copper", label = "Min Vendor Value", legacy_key = "min_gold", max_gold = 1000000 },
    },
    loot_filter_expansion = {
        { type = "multi_toggle", key = "expansions", label = "Excluded Expansions", choices = EXPANSION_CHOICES },
    },
    loot_filter_categories = {
        { type = "multi_toggle", key = "categories", label = "Excluded Categories", choices = CATEGORY_CHOICES },
    },
    loot_filter_min_item_level = {
        { type = "number", key = "min_ilvl", label = "Min Item Level", min = 0, integer = true, dynamic_max_percent_of_player_ilvl = 2.0, show_player_ilvl_percent = true },
    },
    sell_filter_quality = {
        { type = "enum", key = "max_quality", label = "Sell Up To Quality", values = QUALITY_VALUES, quality_colors = true },
    },
    sell_filter_value = {
        { type = "money", key = "min_copper", label = "Min Vendor Value", legacy_key = "min_gold", max_gold = 1000000 },
    },
    sell_filter_expansion = {
        { type = "multi_toggle", key = "expansions", label = "Expansions", choices = EXPANSION_CHOICES },
    },
    sell_filter_categories = {
        { type = "multi_toggle", key = "categories", label = "Categories", choices = SELL_CATEGORY_CHOICES },
    },
    sell_filter_max_item_level = {
        { type = "number", key = "max_ilvl", label = "Max Item Level", min = 0, integer = true, default_percent_of_player_ilvl = 0.7, default_when_negative = true, dynamic_max_percent_of_player_ilvl = 2.0, show_player_ilvl_percent = true },
    },
    sell_filter_bind = {
        { type = "multi_toggle", key = "bind", label = "Bind Types", choices = SELL_BIND_CHOICES },
    },
    sell_filter_usability = {
        { type = "multi_toggle", key = "usability", label = "Usability", choices = USABILITY_CHOICES },
    },
}


