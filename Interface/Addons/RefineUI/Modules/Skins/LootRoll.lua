----------------------------------------------------------------------------------------
-- Skins Component: Loot Roll
-- Description: Applies outlined + shadow text styling to GroupLootHistoryFrame.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local select = select

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:LootRoll"
local DEFAULT_FONT_SIZE = 12

local HOOK_KEY = {
    FRAME_ON_SHOW = COMPONENT_KEY .. ":GroupLootHistoryFrame:OnShow",
    ELEMENT_INIT = COMPONENT_KEY .. ":LootHistoryElementMixin:Init",
    TOOLTIP_LINE_INIT = COMPONENT_KEY .. ":LootHistoryRollTooltipLineMixin:Init",
    TOOLTIP_LINE_ALL_PASSED = COMPONENT_KEY .. ":LootHistoryRollTooltipLineMixin:SetToAllPassed",
}

----------------------------------------------------------------------------------------
-- Local State
----------------------------------------------------------------------------------------
-- Blizzard never changes these fonts after creation, so each font string is styled once.
local styledFontStrings = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local StyleFrameFontStrings

local function StyleFontString(region)
    if styledFontStrings[region] or region:GetObjectType() ~= "FontString" then
        return
    end
    styledFontStrings[region] = true

    local _, size = region:GetFont()
    RefineUI.Font(region, size and size > 0 and size or DEFAULT_FONT_SIZE, nil, "OUTLINE", true)
end

local function StyleRegions(...)
    for index = 1, select("#", ...) do
        StyleFontString((select(index, ...)))
    end
end

local function StyleChildren(...)
    for index = 1, select("#", ...) do
        StyleFrameFontStrings((select(index, ...)))
    end
end

StyleFrameFontStrings = function(frame)
    StyleRegions(frame:GetRegions())
    StyleChildren(frame:GetChildren())
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupLootRollSkin()
    -- Scroll rows and tooltip lines are created lazily, after these mixin hooks exist.
    RefineUI:HookScriptOnce(HOOK_KEY.FRAME_ON_SHOW, GroupLootHistoryFrame, "OnShow", StyleFrameFontStrings)
    RefineUI:HookOnce(HOOK_KEY.ELEMENT_INIT, LootHistoryElementMixin, "Init", StyleFrameFontStrings)
    RefineUI:HookOnce(HOOK_KEY.TOOLTIP_LINE_INIT, LootHistoryRollTooltipLineMixin, "Init", StyleFrameFontStrings)
    RefineUI:HookOnce(HOOK_KEY.TOOLTIP_LINE_ALL_PASSED, LootHistoryRollTooltipLineMixin, "SetToAllPassed", StyleFrameFontStrings)
end
