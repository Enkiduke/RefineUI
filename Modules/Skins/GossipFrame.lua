----------------------------------------------------------------------------------------
-- Skins Component: Gossip Frame
-- Description: Styles gossip text with white greeting text and gold clickable options.
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
local pairs = pairs
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local gsub = string.gsub

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:GossipFrame"

local EVENT_KEY = {
    ADDON_LOADED = COMPONENT_KEY .. ":ADDON_LOADED",
}

local GOSSIP_OPTION_COLOR = { 1.0, 0.82, 0.0, 1.0 }
local GOSSIP_GREETING_COLOR = { 1.0, 1.0, 1.0, 1.0 }
local GOSSIP_INLINE_COLOR_MAP = {
    ["000000"] = "ffd200",
    ["414141"] = "ffffff",
}

----------------------------------------------------------------------------------------
-- Local State
----------------------------------------------------------------------------------------
local setupComplete = false
local hooksInstalled = false
local uiThemeRegisterHookInstalled = false

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function CanUseFontString(fontString)
    if not fontString then
        return false
    end

    if fontString.IsForbidden and fontString:IsForbidden() then
        return false
    end

    return type(fontString.SetTextColor) == "function"
end

local function ForceFontStringColor(fontString, color)
    if not CanUseFontString(fontString) then
        return
    end

    if type(fontString.SetFixedColor) == "function" then
        fontString:SetFixedColor(true)
    end

    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function ForceGreetingFontString(fontString)
    ForceFontStringColor(fontString, GOSSIP_GREETING_COLOR)
end

local function ForceOptionFontString(fontString)
    ForceFontStringColor(fontString, GOSSIP_OPTION_COLOR)
end

local function IsGreetingFontString(fontString)
    if not fontString or type(fontString.GetName) ~= "function" then
        return false
    end

    local name = fontString:GetName()
    return type(name) == "string" and name:find("GreetingText", 1, true) ~= nil
end

local function ReplaceGossipInlineColors(text)
    if type(text) ~= "string" or text == "" then
        return text
    end

    text = gsub(text, ":32:32:0:0", ":32:32:0:0:64:64:5:59:5:59")
    text = gsub(text, "|c[fF][fF](%x%x%x%x%x%x)", function(hex)
        return "|cff" .. (GOSSIP_INLINE_COLOR_MAP[hex:lower()] or hex)
    end)

    return text
end

local function ReplaceGossipFormat(button, textFormat, text)
    if not button or button.__refineui_gossip_formatting then
        return
    end
    if type(textFormat) ~= "string" then
        return
    end

    local replacedFormat = gsub(textFormat, "000000", "ffd200")
    if replacedFormat == textFormat then
        return
    end

    button.__refineui_gossip_formatting = true
    button:SetFormattedText(replacedFormat, text)
    button.__refineui_gossip_formatting = nil
end

local function ReplaceGossipText(button, text)
    if not button or button.__refineui_gossip_formatting then
        return
    end

    local replaced = ReplaceGossipInlineColors(text)
    if replaced == text then
        return
    end

    button.__refineui_gossip_formatting = true
    button:SetFormattedText("%s", replaced)
    button.__refineui_gossip_formatting = nil
end

local function ApplyVisibleGossipText(frame)
    local greetingPanel = frame and frame.GreetingPanel
    local scrollBox = greetingPanel and greetingPanel.ScrollBox
    if not scrollBox or type(scrollBox.GetScrollTarget) ~= "function" then
        return
    end

    local scrollTarget = scrollBox:GetScrollTarget()
    if not scrollTarget or not scrollTarget.GetChildren then
        return
    end

    for _, child in ipairs({ scrollTarget:GetChildren() }) do
        if child then
            if type(child.GetFontString) == "function" then
                local fontString = child:GetFontString()
                ForceOptionFontString(fontString)
                if not child.__refineui_gossip_text_hooks_installed then
                    ReplaceGossipText(child, child:GetText())
                    hooksecurefunc(child, "SetText", ReplaceGossipText)
                    hooksecurefunc(child, "SetFormattedText", ReplaceGossipFormat)
                    child.__refineui_gossip_text_hooks_installed = true
                end
            end
            if child.GreetingText then
                ForceGreetingFontString(child.GreetingText)
            end
        end
    end
end

local function ApplyGossipTextColor(frame)
    frame = frame or _G.GossipFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return
    end

    if type(frame.fontStrings) == "table" then
        for fontString in pairs(frame.fontStrings) do
            if IsGreetingFontString(fontString) then
                ForceGreetingFontString(fontString)
            else
                ForceOptionFontString(fontString)
            end
        end
    end

    ApplyVisibleGossipText(frame)
end

local function InstallHooks()
    local frame = _G.GossipFrame
    if not frame then
        return false
    end

    if hooksInstalled then
        ApplyGossipTextColor(frame)
        return true
    end

    hooksInstalled = true

    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function(self)
            ApplyGossipTextColor(self)
        end)
    end

    if type(frame.Update) == "function" then
        hooksecurefunc(frame, "Update", function(self)
            ApplyGossipTextColor(self)
        end)
    end

    if type(frame.UpdateTheme) == "function" then
        hooksecurefunc(frame, "UpdateTheme", function(self)
            ApplyGossipTextColor(self)
        end)
    end

    local scrollBox = frame.GreetingPanel and frame.GreetingPanel.ScrollBox
    if scrollBox and type(scrollBox.Update) == "function" then
        hooksecurefunc(scrollBox, "Update", function()
            ApplyGossipTextColor(frame)
        end)
    end

    if not uiThemeRegisterHookInstalled and _G.UIThemeContainerMixin and type(_G.UIThemeContainerMixin.RegisterFontString) == "function" then
        uiThemeRegisterHookInstalled = true
        hooksecurefunc(_G.UIThemeContainerMixin, "RegisterFontString", function(self, fontString)
            if self == _G.GossipFrame then
                if IsGreetingFontString(fontString) then
                    ForceGreetingFontString(fontString)
                else
                    ForceOptionFontString(fontString)
                end
            end
        end)
    end

    ApplyGossipTextColor(frame)
    return true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupGossipFrameSkin()
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
