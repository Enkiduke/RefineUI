----------------------------------------------------------------------------------------
-- LootRules Component: Config
-- Description: Rule defaults, migrations, normalization, and evaluation helpers.
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
local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local ipairs = ipairs
local pairs = pairs
local type = type
local tonumber = tonumber
local floor = math.floor
local max = math.max
local tostring = tostring
local C_PaperDollInfo = C_PaperDollInfo
local GetAverageItemLevel = GetAverageItemLevel

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local STAGE_LOOT = LootRules.STAGE_LOOT or "LOOT"
local STAGE_SELL = LootRules.STAGE_SELL or "SELL"

local DEFAULT_RULES = LootRules.DEFAULT_RULES or {}
local RULE_OPTION_SCHEMAS = LootRules.RULE_OPTION_SCHEMAS or {}

local ITEM_QUALITY_POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local LOOT_FILTER_AND_RULE = {
    id = "loot_filters_all",
}
local SELL_FILTER_AND_RULE = {
    id = "sell_filters_all",
}
local LOOT_FILTER_CATEGORY_KEYS = {
    "equipment",
    "trade_goods",
    "consumables",
    "recipes",
    "gems",
    "junk",
    "misc",
}
local LOOT_FILTER_SEMANTICS_VERSION = 2

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local DEFAULT_RULES_BY_ID = {}
for i = 1, #DEFAULT_RULES do
    local rule = DEFAULT_RULES[i]
    DEFAULT_RULES_BY_ID[rule.id] = rule
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local out = {}
    for key, nested in pairs(value) do
        out[key] = DeepCopy(nested)
    end
    return out
end

local function DeepMerge(defaults, existing)
    local out = DeepCopy(defaults or {})
    if type(existing) ~= "table" then
        return out
    end

    for key, value in pairs(existing) do
        if type(value) == "table" and type(out[key]) == "table" then
            out[key] = DeepMerge(out[key], value)
        else
            out[key] = DeepCopy(value)
        end
    end
    return out
end

local function ApplyDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return
    end

    for key, value in pairs(defaults) do
        local existing = target[key]
        if type(value) == "table" then
            if type(existing) ~= "table" then
                target[key] = DeepCopy(value)
            else
                ApplyDefaults(existing, value)
            end
        elseif existing == nil then
            target[key] = value
        end
    end
end

local function DeepCopyRules(src)
    local out = {}
    for i = 1, #src do
        out[i] = DeepCopy(src[i])
    end
    return out
end

local function CopyRule(rule)
    return DeepCopy(rule)
end

local function EnsureDefaultRulesPresent(rules)
    if type(rules) ~= "table" then
        return DeepCopyRules(DEFAULT_RULES)
    end

    local firstByID = {}
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == "table" and type(rule.id) == "string" and rule.id ~= "" and not firstByID[rule.id] then
            firstByID[rule.id] = rule
        end
    end

    local nextRules = {}
    for i = 1, #DEFAULT_RULES do
        local defaultRule = DEFAULT_RULES[i]
        local existing = firstByID[defaultRule.id]
        local merged = CopyRule(defaultRule)

        if existing and existing.enabled ~= nil then
            merged.enabled = existing.enabled and true or false
        end

        if existing and type(existing.options) == "table" then
            merged.options = DeepMerge(defaultRule.options, existing.options)
        else
            merged.options = DeepCopy(defaultRule.options or {})
        end

        if (defaultRule.id == "loot_filter_value" or defaultRule.id == "sell_filter_value")
            and existing
            and type(existing.options) == "table"
            and existing.options.min_copper == nil
            and existing.options.min_gold ~= nil
        then
            local legacyGold = tonumber(existing.options.min_gold) or 0
            if legacyGold > 0 then
                merged.options.min_copper = floor(legacyGold * 10000)
            else
                merged.options.min_copper = 0
            end
        end

        nextRules[#nextRules + 1] = merged
    end

    return nextRules
end

local function IsAlwaysRuleID(ruleID)
    if type(ruleID) ~= "string" then
        return false
    end
    return ruleID:find("^loot_always_") ~= nil or ruleID:find("^sell_always_") ~= nil
end

local function IsSellFilterRuleID(ruleID)
    if type(ruleID) ~= "string" then
        return false
    end
    return ruleID:find("^sell_filter_") ~= nil
end

local function IsLootFilterRuleID(ruleID)
    if type(ruleID) ~= "string" then
        return false
    end
    return ruleID:find("^loot_filter_") ~= nil
end

local function ToNumber(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback
    end
    return numeric
end

local function GoldToCopper(gold)
    local numeric = ToNumber(gold, 0) or 0
    if numeric <= 0 then
        return 0
    end
    return floor(numeric * 10000)
end

local function NormalizeCopper(copper)
    local numeric = ToNumber(copper, 0) or 0
    if numeric <= 0 then
        return 0
    end
    return floor(numeric)
end

local function IsValueRuleID(ruleID)
    return ruleID == "loot_filter_value" or ruleID == "sell_filter_value"
end

local function GetRuleMinCopper(options)
    if type(options) ~= "table" then
        return 0
    end
    if options.min_copper ~= nil then
        return NormalizeCopper(options.min_copper)
    end
    return GoldToCopper(options.min_gold)
end

local function GetCurrentPlayerItemLevel()
    if C_PaperDollInfo and C_PaperDollInfo.GetAverageItemLevel then
        local avg, equipped = C_PaperDollInfo.GetAverageItemLevel()
        local current = ToNumber(equipped, nil) or ToNumber(avg, nil)
        if current and current > 0 then
            return current
        end
    elseif GetAverageItemLevel then
        local avg, equipped = GetAverageItemLevel()
        local current = ToNumber(equipped, nil) or ToNumber(avg, nil)
        if current and current > 0 then
            return current
        end
    end
    return 0
end

local function ResolveConfiguredItemLevel(value, defaultPercentWhenNegative)
    local numeric = ToNumber(value, 0) or 0
    if numeric < 0 and defaultPercentWhenNegative and defaultPercentWhenNegative > 0 then
        local current = GetCurrentPlayerItemLevel()
        if current > 0 then
            numeric = floor((current * defaultPercentWhenNegative) + 0.5)
        else
            numeric = 0
        end
    end
    if numeric < 0 then
        return 0
    end
    return floor(numeric + 0.5)
end

local function GetCurrentExpansionID()
    if not GetExpansionLevel then
        return nil
    end
    local current = ToNumber(GetExpansionLevel(), nil)
    if current == nil then
        return nil
    end
    return current
end

local function NormalizeExpansionID(value)
    local id = ToNumber(value, nil)
    if id == nil then
        return nil
    end
    if id == 254 then
        return 0
    end
    if id < 0 then
        return 0
    end
    return floor(id + 0.5)
end

local function GetMaxRetailExpansionID()
    local maxKnown = 11
    local knownLevels = ToNumber(NUM_LE_EXPANSION_LEVELS, nil)
    if knownLevels and knownLevels > 1 then
        maxKnown = floor(knownLevels - 1)
    end
    if maxKnown < 11 then
        maxKnown = 11
    end
    return maxKnown
end

local function BuildAllRetailExpansionSelection()
    local selected = {}
    local maxKnown = GetMaxRetailExpansionID()
    for expansionID = 1, maxKnown do
        selected[tostring(expansionID)] = true
    end
    return selected
end

local function BuildAllLootCategorySelection()
    local selected = {}
    for i = 1, #LOOT_FILTER_CATEGORY_KEYS do
        selected[LOOT_FILTER_CATEGORY_KEYS[i]] = true
    end
    return selected
end

local function NormalizeExpansionSelectionBucket(bucket)
    if type(bucket) ~= "table" then
        return nil
    end

    local normalized = {}
    local maxKnown = GetMaxRetailExpansionID()
    for key, isSelected in pairs(bucket) do
        if isSelected then
            local expansionID = NormalizeExpansionID(key)
            if expansionID and expansionID >= 1 and expansionID <= maxKnown then
                normalized[tostring(expansionID)] = true
            end
        end
    end

    return normalized
end

local function InvertExpansionSelectionBucket(bucket)
    local include = NormalizeExpansionSelectionBucket(bucket) or {}
    local inverted = {}
    local maxKnown = GetMaxRetailExpansionID()
    for expansionID = 1, maxKnown do
        local key = tostring(expansionID)
        if not include[key] then
            inverted[key] = true
        end
    end
    return inverted
end

local function HasSelectedExpansion(bucket)
    if type(bucket) ~= "table" then
        return false
    end
    for _, isSelected in pairs(bucket) do
        if isSelected then
            return true
        end
    end
    return false
end

local function ResolveLegacyLootExpansionID(value)
    if value == nil or value == "ANY" then
        return nil
    end

    if value == "CURRENT" or value == "CURRENT_PLUS_1" or value == "CURRENT_PLUS_2" then
        return NormalizeExpansionID(GetCurrentExpansionID())
    end

    return NormalizeExpansionID(value)
end

local function ResolveLegacySellExpansionID(value)
    if value == nil or value == "ANY" then
        return nil
    end

    local current = NormalizeExpansionID(GetCurrentExpansionID())
    if value == "CURRENT" or value == "ANY_OLD" then
        if current ~= nil then
            return max(0, current - 1)
        end
        return nil
    end
    if value == "LAST_1" then
        if current ~= nil then
            return max(0, current - 2)
        end
        return nil
    end
    if value == "LAST_2" then
        if current ~= nil then
            return max(0, current - 3)
        end
        return nil
    end

    return NormalizeExpansionID(value)
end

local function ResolveLegacyExpansionSelectionBucket(ruleID, legacyValue)
    local resolvedID
    if ruleID == "sell_filter_expansion" then
        resolvedID = ResolveLegacySellExpansionID(legacyValue)
    else
        resolvedID = ResolveLegacyLootExpansionID(legacyValue)
    end

    if resolvedID == nil then
        return BuildAllRetailExpansionSelection()
    end
    if resolvedID < 1 then
        return {}
    end

    local maxKnown = GetMaxRetailExpansionID()
    if resolvedID > maxKnown then
        return {}
    end

    return {
        [tostring(resolvedID)] = true,
    }
end

local function MatchesSelectedExpansion(itemExpansion, selectionBucket, failOpenOnUnknown)
    if type(selectionBucket) ~= "table" then
        return failOpenOnUnknown and true or false
    end
    if not HasSelectedExpansion(selectionBucket) then
        return false
    end

    local item = NormalizeExpansionID(itemExpansion)
    if item == nil then
        return failOpenOnUnknown and true or false
    end
    if item < 1 then
        return false
    end

    return selectionBucket[tostring(item)] and true or false
end

local function IsEquipmentCategory(context)
    return context.category == "equipment"
end

local function IsCategorySelected(bucket, category)
    if type(bucket) ~= "table" then
        return false
    end
    if type(category) ~= "string" or category == "" then
        category = "misc"
    end
    return bucket[category] and true or false
end

local function InvertLootCategorySelectionBucket(bucket)
    local include = type(bucket) == "table" and bucket or BuildAllLootCategorySelection()
    local inverted = {}
    for i = 1, #LOOT_FILTER_CATEGORY_KEYS do
        local key = LOOT_FILTER_CATEGORY_KEYS[i]
        if not include[key] then
            inverted[key] = true
        end
    end
    return inverted
end

local function HasSelectedToggle(bucket)
    if type(bucket) ~= "table" then
        return false
    end
    for _, isEnabled in pairs(bucket) do
        if isEnabled then
            return true
        end
    end
    return false
end

local function MatchesBindSelection(bindOptions, context)
    if type(bindOptions) ~= "table" then
        return false
    end
    if not HasSelectedToggle(bindOptions) then
        return false
    end

    if context.isBoE and bindOptions.boe then
        return true
    end
    if context.isWarbound and bindOptions.warbound then
        return true
    end
    if context.isSoulbound and bindOptions.soulbound then
        return true
    end

    return false
end

local function MatchesUsabilitySelection(usabilityOptions, context)
    if type(usabilityOptions) ~= "table" then
        return false
    end
    if not HasSelectedToggle(usabilityOptions) then
        return false
    end

    if context.isUsable == true and usabilityOptions.usable then
        return true
    end
    if context.isUsable == false and usabilityOptions.unusable then
        return true
    end

    return false
end

local function CompareRuleEntries(a, b)
    local aEnabled = a and a.rule and a.rule.enabled and 1 or 0
    local bEnabled = b and b.rule and b.rule.enabled and 1 or 0
    if aEnabled ~= bEnabled then
        return aEnabled > bEnabled
    end
    return (a.index or 0) < (b.index or 0)
end

local function RuleMatches(ruleID, options, context)
    options = options or {}

    if ruleID == "loot_always_uncollected" then
        return context.isCollectibleUncollected == true
    end
    if ruleID == "loot_always_quest_items" then
        return context.isQuestItem == true
    end
    if ruleID == "loot_filter_quality" then
        local minQuality = ToNumber(options.min_quality, 0) or 0
        local quality = ToNumber(context.quality, nil)
        return quality ~= nil and quality < minQuality
    end
    if ruleID == "loot_filter_value" then
        local minCopper = GetRuleMinCopper(options)
        local value = ToNumber(context.sellPrice, 0) or 0
        return value < minCopper
    end
    if ruleID == "loot_filter_expansion" then
        return MatchesSelectedExpansion(context.expansion, options.expansions, false)
    end
    if ruleID == "loot_filter_categories" then
        return IsCategorySelected(options.categories, context.category)
    end
    if ruleID == "loot_filter_min_item_level" then
        local minItemLevel = ToNumber(options.min_ilvl, 0) or 0
        local itemLevel = ToNumber(context.itemLevel, 0) or 0
        return minItemLevel > 0 and IsEquipmentCategory(context) and itemLevel < minItemLevel
    end

    if ruleID == "sell_always_keep_equipment_set" then
        return context.isInEquipmentSet == true
    end
    if ruleID == "sell_always_keep_boe_wue" then
        return context.isBoE == true or context.isWarbound == true
    end
    if ruleID == "sell_always_sell_junk" then
        local quality = ToNumber(context.quality, nil)
        local value = ToNumber(context.sellPrice, 0) or 0
        return quality == ITEM_QUALITY_POOR and value > 0
    end
    if ruleID == "sell_filter_quality" then
        local maxQuality = ToNumber(options.max_quality, ITEM_QUALITY_POOR) or ITEM_QUALITY_POOR
        local quality = ToNumber(context.quality, nil)
        return quality ~= nil and quality <= maxQuality
    end
    if ruleID == "sell_filter_value" then
        local minCopper = GetRuleMinCopper(options)
        local value = ToNumber(context.sellPrice, 0) or 0
        return value >= minCopper
    end
    if ruleID == "sell_filter_expansion" then
        return MatchesSelectedExpansion(context.expansion, options.expansions, false)
    end
    if ruleID == "sell_filter_categories" then
        if context.category == "junk" then
            return false
        end
        return IsCategorySelected(options.categories, context.category)
    end
    if ruleID == "sell_filter_max_item_level" then
        local maxItemLevel = ResolveConfiguredItemLevel(options.max_ilvl, 0.7)
        local itemLevel = ToNumber(context.itemLevel, 0) or 0
        return maxItemLevel > 0 and IsEquipmentCategory(context) and itemLevel <= maxItemLevel
    end
    if ruleID == "sell_filter_bind" then
        return MatchesBindSelection(options.bind, context)
    end
    if ruleID == "sell_filter_usability" then
        return MatchesUsabilitySelection(options.usability, context)
    end

    return false
end

local function MigrateLootFilterSelectionSemantics(ar)
    if type(ar) ~= "table" then
        return
    end
    local currentVersion = ToNumber(ar.loot_filter_semantics_version, 0) or 0
    if currentVersion >= LOOT_FILTER_SEMANTICS_VERSION then
        return
    end
    if type(ar.Rules) ~= "table" then
        ar.loot_filter_semantics_version = LOOT_FILTER_SEMANTICS_VERSION
        return
    end

    for i = 1, #ar.Rules do
        local rule = ar.Rules[i]
        if type(rule) == "table" then
            rule.options = type(rule.options) == "table" and rule.options or {}
            if rule.id == "loot_filter_expansion" then
                local legacyInclude
                if type(rule.options.expansions) == "table" then
                    legacyInclude = rule.options.expansions
                else
                    legacyInclude = ResolveLegacyExpansionSelectionBucket(rule.id, rule.options.window)
                end
                rule.options.expansions = InvertExpansionSelectionBucket(legacyInclude)
                rule.options.window = nil
            elseif rule.id == "loot_filter_categories" then
                rule.options.categories = InvertLootCategorySelectionBucket(rule.options.categories)
            end
        end
    end

    ar.loot_filter_semantics_version = LOOT_FILTER_SEMANTICS_VERSION
end

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function LootRules:IsRuleLocked(rule)
    if type(rule) ~= "table" then
        return false
    end
    return IsAlwaysRuleID(rule.id)
end

function LootRules:GetRuleOptionSchema(ruleID)
    local schema = RULE_OPTION_SCHEMAS[ruleID]
    if type(schema) ~= "table" then
        return {}
    end
    return schema
end

function LootRules:GetDefaultRule(ruleID)
    return DEFAULT_RULES_BY_ID[ruleID]
end

function LootRules:EnsureRuleOptions(rule)
    if type(rule) ~= "table" or type(rule.id) ~= "string" then
        return {}
    end

    local defaultRule = self:GetDefaultRule(rule.id)
    local defaultOptions = defaultRule and defaultRule.options or {}

    if type(rule.options) ~= "table" then
        rule.options = DeepCopy(defaultOptions)
        return rule.options
    end

    ApplyDefaults(rule.options, defaultOptions)

    if IsValueRuleID(rule.id) then
        rule.options.min_copper = GetRuleMinCopper(rule.options)
    end

    if rule.id == "sell_filter_categories" and type(rule.options.categories) == "table" then
        rule.options.categories.junk = nil
    end

    if rule.id == "sell_filter_max_item_level" then
        local configured = ToNumber(rule.options.max_ilvl, nil)
        if configured and configured < 0 then
            local resolved = ResolveConfiguredItemLevel(configured, 0.7)
            if resolved > 0 then
                rule.options.max_ilvl = resolved
            end
        end
    end

    if rule.id == "loot_filter_expansion" then
        local expansions = NormalizeExpansionSelectionBucket(rule.options.expansions)
        if not expansions then
            local legacyInclude = ResolveLegacyExpansionSelectionBucket(rule.id, rule.options.window)
            expansions = InvertExpansionSelectionBucket(legacyInclude)
        end
        if not HasSelectedExpansion(expansions) and rule.options.window == nil and type(rule.options.expansions) ~= "table" then
            expansions = {}
        end
        rule.options.expansions = expansions or {}
        rule.options.window = nil
    elseif rule.id == "sell_filter_expansion" then
        local expansions = NormalizeExpansionSelectionBucket(rule.options.expansions)
        if not expansions then
            expansions = ResolveLegacyExpansionSelectionBucket(rule.id, rule.options.older_than)
        end
        if not HasSelectedExpansion(expansions) and rule.options.older_than == nil and type(rule.options.expansions) ~= "table" then
            expansions = BuildAllRetailExpansionSelection()
        end
        rule.options.expansions = expansions
        rule.options.older_than = nil
    end

    return rule.options
end

function LootRules:GetConfig()
    RefineUI.Config.Loot = RefineUI.Config.Loot or {}
    local cfg = RefineUI.Config.Loot

    cfg.AdvancedRules = cfg.AdvancedRules or {}
    local ar = cfg.AdvancedRules

    if self._lootRulesConfigReady
        and self._lootRulesConfigRef == ar
        and self._lootRulesConfigRulesRef == ar.Rules
        and type(ar.Rules) == "table"
        and #ar.Rules > 0
    then
        return ar
    end

    local hasExistingRules = type(ar.Rules) == "table" and #ar.Rules > 0
    if not hasExistingRules then
        ar.Rules = DeepCopyRules(DEFAULT_RULES)
        ar.loot_filter_semantics_version = LOOT_FILTER_SEMANTICS_VERSION
    else
        MigrateLootFilterSelectionSemantics(ar)
        ar.Rules = EnsureDefaultRulesPresent(ar.Rules)
    end

    for i = 1, #ar.Rules do
        local rule = ar.Rules[i]
        if type(rule) == "table" then
            self:EnsureRuleOptions(rule)
        end
    end

    self._lootRulesConfigReady = true
    self._lootRulesConfigRef = ar
    self._lootRulesConfigRulesRef = ar.Rules

    return ar
end

function LootRules:GetRulesForStage(stage, preserveOrder)
    local cfg = self:GetConfig()
    local rules = {}
    for index, rule in ipairs(cfg.Rules) do
        if rule.stage == stage then
            self:EnsureRuleOptions(rule)
            rules[#rules + 1] = {
                index = index,
                rule = rule,
            }
        end
    end
    if not preserveOrder then
        tsort(rules, CompareRuleEntries)
    end
    return rules
end

function LootRules:SortStageRulesEnabledFirst(stage)
    local cfg = self:GetConfig()
    local entries = self:GetRulesForStage(stage == STAGE_SELL and STAGE_SELL or STAGE_LOOT, true)
    if #entries < 2 then
        return false
    end

    local stageIndices = {}
    for i = 1, #entries do
        stageIndices[i] = entries[i].index
    end

    tsort(entries, CompareRuleEntries)

    local changed = false
    for i = 1, #stageIndices do
        if cfg.Rules[stageIndices[i]] ~= entries[i].rule then
            changed = true
            break
        end
    end
    if not changed then
        return false
    end

    for i = 1, #stageIndices do
        cfg.Rules[stageIndices[i]] = entries[i].rule
    end

    return true
end

function LootRules:GetRuleByID(ruleID)
    if type(ruleID) ~= "string" or ruleID == "" then
        return nil
    end
    local cfg = self:GetConfig()
    for i = 1, #cfg.Rules do
        if cfg.Rules[i].id == ruleID then
            return cfg.Rules[i]
        end
    end
    return nil
end

function LootRules:MoveRuleWithinStageTo(stage, fromPos, toPos)
    local cfg = self:GetConfig()
    local entries = self:GetRulesForStage(stage, true)
    local count = #entries

    if count < 2 then return false end
    if type(fromPos) ~= "number" or type(toPos) ~= "number" then return false end
    if fromPos < 1 or fromPos > count then return false end
    if toPos < 1 then toPos = 1 end
    if toPos > count then toPos = count end
    if fromPos == toPos then return false end
    if self:IsRuleLocked(entries[fromPos].rule) then
        return false
    end
    if self:IsRuleLocked(entries[toPos].rule) then
        return false
    end

    local stageRules = {}
    local stageIndices = {}
    for i = 1, count do
        stageRules[i] = entries[i].rule
        stageIndices[i] = entries[i].index
    end

    local moved = tremove(stageRules, fromPos)
    tinsert(stageRules, toPos, moved)

    for i = 1, count do
        cfg.Rules[stageIndices[i]] = stageRules[i]
    end

    return true
end

function LootRules:ResetStageRulesToDefaults(stage)
    if stage ~= STAGE_SELL then
        stage = STAGE_LOOT
    end

    local entries = self:GetRulesForStage(stage, true)
    for i = 1, #entries do
        local rule = entries[i].rule
        local defaultRule = self:GetDefaultRule(rule.id)
        if defaultRule then
            rule.enabled = defaultRule.enabled and true or false
            rule.action = defaultRule.action
            rule.title = defaultRule.title
            rule.summary = defaultRule.summary
            rule.options = DeepCopy(defaultRule.options or {})
            self:EnsureRuleOptions(rule)
        end
    end

    self:SortStageRulesEnabledFirst(stage)

    return true
end

function LootRules:NormalizeItemContext(input)
    input = input or {}
    return {
        itemID = input.itemID,
        link = input.link,
        quality = ToNumber(input.quality, nil),
        itemLevel = ToNumber(input.itemLevel, nil),
        itemType = input.itemType,
        itemSubType = input.itemSubType,
        itemClassID = ToNumber(input.itemClassID, nil),
        itemSubClassID = ToNumber(input.itemSubClassID, nil),
        category = input.category or "misc",
        bindType = input.bindType,
        isBound = input.isBound,
        isBoE = input.isBoE and true or false,
        isWarbound = input.isWarbound and true or false,
        isSoulbound = input.isSoulbound and true or false,
        isUsable = (input.isUsable == nil) and nil or (input.isUsable and true or false),
        isQuestItem = input.isQuestItem and true or false,
        isCollectibleUncollected = input.isCollectibleUncollected and true or false,
        isInEquipmentSet = input.isInEquipmentSet and true or false,
        expansion = ToNumber(input.expansion, nil),
        sellPrice = ToNumber(input.sellPrice, 0) or 0,
        stackCount = ToNumber(input.stackCount, 1) or 1,
        bag = input.bag,
        slot = input.slot,
        source = input.source,
    }
end

function LootRules:HasEnabledRulesForStage(stage)
    stage = (stage == STAGE_SELL) and STAGE_SELL or STAGE_LOOT
    local cfg = self:GetConfig()
    for i = 1, #cfg.Rules do
        local rule = cfg.Rules[i]
        if rule and rule.stage == stage and rule.enabled then
            return true
        end
    end
    return false
end

function LootRules:EvaluateRulesForStage(stage, context)
    stage = (stage == STAGE_SELL) and STAGE_SELL or STAGE_LOOT
    local normalized = self:NormalizeItemContext(context)
    local cfg = self:GetConfig()

    if stage == STAGE_LOOT then
        for i = 1, #cfg.Rules do
            local rule = cfg.Rules[i]
            if rule and rule.stage == STAGE_LOOT and rule.enabled and not IsLootFilterRuleID(rule.id) then
                local options = self:EnsureRuleOptions(rule)
                if RuleMatches(rule.id, options, normalized) then
                    return rule.action, rule
                end
            end
        end

        local hasEnabledFilter = false
        for i = 1, #cfg.Rules do
            local rule = cfg.Rules[i]
            if rule and rule.stage == STAGE_LOOT and rule.enabled and IsLootFilterRuleID(rule.id) then
                hasEnabledFilter = true
                local options = self:EnsureRuleOptions(rule)
                if not RuleMatches(rule.id, options, normalized) then
                    return "LOOT", rule
                end
            end
        end

        if hasEnabledFilter then
            return "SKIP", LOOT_FILTER_AND_RULE
        end

        return "LOOT", nil
    end

    if stage == STAGE_SELL then
        for i = 1, #cfg.Rules do
            local rule = cfg.Rules[i]
            if rule and rule.stage == STAGE_SELL and rule.enabled and not IsSellFilterRuleID(rule.id) then
                local options = self:EnsureRuleOptions(rule)
                if RuleMatches(rule.id, options, normalized) then
                    return rule.action, rule
                end
            end
        end

        local hasEnabledFilter = false
        for i = 1, #cfg.Rules do
            local rule = cfg.Rules[i]
            if rule and rule.stage == STAGE_SELL and rule.enabled and IsSellFilterRuleID(rule.id) then
                hasEnabledFilter = true
                local options = self:EnsureRuleOptions(rule)
                if not RuleMatches(rule.id, options, normalized) then
                    return "KEEP", rule
                end
            end
        end

        if hasEnabledFilter then
            return "SELL", SELL_FILTER_AND_RULE
        end

        return "KEEP", nil
    end

    for i = 1, #cfg.Rules do
        local rule = cfg.Rules[i]
        if rule and rule.stage == stage and rule.enabled then
            local options = self:EnsureRuleOptions(rule)
            if RuleMatches(rule.id, options, normalized) then
                return rule.action, rule
            end
        end
    end

    return "KEEP", nil
end


