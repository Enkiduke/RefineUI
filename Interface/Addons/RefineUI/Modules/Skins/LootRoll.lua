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
local _G = _G
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:LootRoll"
local DEFAULT_FONT_SIZE = 12

local EVENT_KEY = {
    ADDON_LOADED = COMPONENT_KEY .. ":ADDON_LOADED",
}

local HOOK_KEY = {
    FRAME_ON_SHOW = COMPONENT_KEY .. ":GroupLootHistoryFrame:OnShow",
    FRAME_DO_FULL_REFRESH = COMPONENT_KEY .. ":LootHistoryFrameMixin:DoFullRefresh",
    ELEMENT_ON_LOAD = COMPONENT_KEY .. ":LootHistoryElementMixin:OnLoad",
    ELEMENT_INIT = COMPONENT_KEY .. ":LootHistoryElementMixin:Init",
    TOOLTIP_LINE_INIT = COMPONENT_KEY .. ":LootHistoryRollTooltipLineMixin:Init",
    TOOLTIP_LINE_ALL_PASSED = COMPONENT_KEY .. ":LootHistoryRollTooltipLineMixin:SetToAllPassed",
}

----------------------------------------------------------------------------------------
-- Local State
----------------------------------------------------------------------------------------
local setupComplete = false

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsUsableFrame(frame)
    if not frame then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end
    return true
end

local function IsUsableFontString(fontString)
    if not fontString then
        return false
    end
    if fontString.IsForbidden and fontString:IsForbidden() then
        return false
    end
    return type(fontString.GetObjectType) == "function"
        and fontString:GetObjectType() == "FontString"
        and type(fontString.GetFont) == "function"
end

local function GetFontSize(fontString)
    local _, size = fontString:GetFont()
    if type(size) == "number" and size > 0 then
        return size
    end
    return DEFAULT_FONT_SIZE
end

local function StyleFontString(fontString)
    if not IsUsableFontString(fontString) then
        return
    end

    RefineUI.Font(fontString, GetFontSize(fontString), nil, "OUTLINE", true)
end

local function StyleFrameFontStrings(frame, visited)
    if not IsUsableFrame(frame) then
        return
    end

    visited = visited or {}
    if visited[frame] then
        return
    end
    visited[frame] = true

    if type(frame.GetRegions) == "function" then
        local regions = { frame:GetRegions() }
        for index = 1, #regions do
            StyleFontString(regions[index])
        end
    end

    if type(frame.GetChildren) == "function" then
        local children = { frame:GetChildren() }
        for index = 1, #children do
            StyleFrameFontStrings(children[index], visited)
        end
    end
end

local function StyleLootHistoryElement(elementFrame)
    StyleFrameFontStrings(elementFrame)
end

local function StyleGroupLootHistoryFrame(frame)
    if not IsUsableFrame(frame) then
        return
    end

    StyleFrameFontStrings(frame)

    local scrollBox = frame.ScrollBox
    if scrollBox and type(scrollBox.GetFrames) == "function" then
        local visibleFrames = scrollBox:GetFrames()
        if type(visibleFrames) == "table" then
            for index = 1, #visibleFrames do
                StyleLootHistoryElement(visibleFrames[index])
            end
        end
    end
end

local function InstallHooks()
    local groupLootHistoryFrame = _G.GroupLootHistoryFrame

    if IsUsableFrame(groupLootHistoryFrame) and type(groupLootHistoryFrame.HookScript) == "function" then
        RefineUI:HookScriptOnce(HOOK_KEY.FRAME_ON_SHOW, groupLootHistoryFrame, "OnShow", function(frame)
            StyleGroupLootHistoryFrame(frame)
        end)
    end

    local lootHistoryFrameMixin = _G.LootHistoryFrameMixin
    if lootHistoryFrameMixin and type(lootHistoryFrameMixin.DoFullRefresh) == "function" then
        RefineUI:HookOnce(HOOK_KEY.FRAME_DO_FULL_REFRESH, lootHistoryFrameMixin, "DoFullRefresh", function(frame)
            StyleGroupLootHistoryFrame(frame or _G.GroupLootHistoryFrame)
        end)
    end

    local lootHistoryElementMixin = _G.LootHistoryElementMixin
    if lootHistoryElementMixin and type(lootHistoryElementMixin.OnLoad) == "function" then
        RefineUI:HookOnce(HOOK_KEY.ELEMENT_ON_LOAD, lootHistoryElementMixin, "OnLoad", function(frame)
            StyleLootHistoryElement(frame)
        end)
    end
    if lootHistoryElementMixin and type(lootHistoryElementMixin.Init) == "function" then
        RefineUI:HookOnce(HOOK_KEY.ELEMENT_INIT, lootHistoryElementMixin, "Init", function(frame)
            StyleLootHistoryElement(frame)
        end)
    end

    local lootHistoryRollTooltipLineMixin = _G.LootHistoryRollTooltipLineMixin
    if lootHistoryRollTooltipLineMixin and type(lootHistoryRollTooltipLineMixin.Init) == "function" then
        RefineUI:HookOnce(HOOK_KEY.TOOLTIP_LINE_INIT, lootHistoryRollTooltipLineMixin, "Init", function(frame)
            StyleFrameFontStrings(frame)
        end)
    end
    if lootHistoryRollTooltipLineMixin and type(lootHistoryRollTooltipLineMixin.SetToAllPassed) == "function" then
        RefineUI:HookOnce(HOOK_KEY.TOOLTIP_LINE_ALL_PASSED, lootHistoryRollTooltipLineMixin, "SetToAllPassed", function(frame)
            StyleFrameFontStrings(frame)
        end)
    end

    StyleGroupLootHistoryFrame(_G.GroupLootHistoryFrame)
    return true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupLootRollSkin()
    if setupComplete then
        return
    end
    setupComplete = true

    InstallHooks()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_UIPanels_Game" then
            InstallHooks()
        end
    end, EVENT_KEY.ADDON_LOADED)
end
