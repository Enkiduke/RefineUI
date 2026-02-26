----------------------------------------------------------------------------------------
-- LootRules Component: OptionsUI
-- Description: Inline options layout orchestration for rule rows.
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
local type = type
local max = math.max

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_FIELD_HEIGHT = 18
local DEFAULT_FIELD_GAP = 1

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetRenderer()
    return LootRules.OptionControlRenderer
end

local function GetFieldMetrics()
    local renderer = GetRenderer()
    local fieldHeight = DEFAULT_FIELD_HEIGHT
    local fieldGap = DEFAULT_FIELD_GAP
    if renderer then
        if type(renderer.FIELD_HEIGHT) == "number" then
            fieldHeight = renderer.FIELD_HEIGHT
        end
        if type(renderer.FIELD_GAP) == "number" then
            fieldGap = renderer.FIELD_GAP
        end
    end
    return fieldHeight, fieldGap
end

local function EstimateSchemaHeight(schema)
    local renderer = GetRenderer()
    if renderer and renderer.EstimateSchemaHeight then
        local height = renderer.EstimateSchemaHeight(schema)
        if type(height) == "number" and height >= 0 then
            return height
        end
    end
    local fieldHeight, fieldGap = GetFieldMetrics()
    local fields = #schema
    return (fields * fieldHeight) + ((fields - 1) * fieldGap)
end

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function LootRules:ReleaseInlineRuleOptions(row)
    local renderer = GetRenderer()
    if renderer and renderer.ReleaseRowOptions then
        renderer.ReleaseRowOptions(row)
        return
    end

    if not row then
        return
    end
    if row._inlineFramePool then
        for i = 1, #row._inlineFramePool do
            row._inlineFramePool[i]:Hide()
        end
    end
end

function LootRules:GetInlineRuleEstimatedHeight(rule)
    if type(rule) ~= "table" then
        return 30
    end
    local schema = self:GetRuleOptionSchema(rule.id)
    if type(schema) ~= "table" or #schema == 0 then
        return 30
    end

    local contentHeight = EstimateSchemaHeight(schema)
    return max(34, 15 + contentHeight)
end

function LootRules:BuildInlineRuleOptions(row, rule)
    if not row or not rule or not row.OptionsHost then
        return 30
    end

    local renderer = GetRenderer()
    local options = self:EnsureRuleOptions(rule)
    local schema = self:GetRuleOptionSchema(rule.id)
    local width = row.OptionsHost:GetWidth() or 0
    if width < 100 then
        width = row._optionColumnWidth or 0
    end
    if width < 100 then
        width = (row:GetWidth() or 760) - 430
    end
    if width < 220 then
        width = 220
    end

    if renderer and renderer.ResetRowPools then
        renderer.ResetRowPools(row)
    else
        row._inlineFrameUsed = 0
    end

    if type(schema) ~= "table" or #schema == 0 then
        if renderer and renderer.HideUnusedControls then
            renderer.HideUnusedControls(row)
        end
        row.OptionsHost:Hide()
        row.OptionsHost:SetHeight(1)
        return 30
    end

    row.OptionsHost:Show()

    local y = 0
    for i = 1, #schema do
        local field = schema[i]
        if renderer and renderer.BuildFieldControl then
            y = renderer.BuildFieldControl(row, options, field, y, width)
        end
    end

    if renderer and renderer.HideUnusedControls then
        renderer.HideUnusedControls(row)
    end

    local optionsHeight = max(12, -y)
    local totalHeight = max(34, 16 + optionsHeight)
    row.OptionsHost:SetHeight(max(12, optionsHeight))

    return totalHeight
end

