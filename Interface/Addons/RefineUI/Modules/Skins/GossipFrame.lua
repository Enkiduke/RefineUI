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
local type = type
local hooksecurefunc = hooksecurefunc
local gsub = string.gsub

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:GossipFrame"

local GOSSIP_OPTION_COLOR = { 1.0, 0.82, 0.0, 1.0 }
local GOSSIP_GREETING_COLOR = { 1.0, 1.0, 1.0, 1.0 }
local GOSSIP_INLINE_COLOR_MAP = {
    ["000000"] = "ffd200",
    ["414141"] = "ffffff",
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function ForceFontStringColor(fontString, color)
    fontString:SetFixedColor(true)
    fontString:SetTextColor(color[1], color[2], color[3], color[4])
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
    if button.__refineui_gossip_formatting or type(textFormat) ~= "string" then
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
    if button.__refineui_gossip_formatting then
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

local function StyleGossipElement(element)
    if element.GreetingText then
        ForceFontStringColor(element.GreetingText, GOSSIP_GREETING_COLOR)
        return
    end

    local fontString = element.GetFontString and element:GetFontString()
    if not fontString then
        return
    end

    ForceFontStringColor(fontString, GOSSIP_OPTION_COLOR)
    if not element.__refineui_gossip_text_hooks_installed then
        ReplaceGossipText(element, element:GetText())
        hooksecurefunc(element, "SetText", ReplaceGossipText)
        hooksecurefunc(element, "SetFormattedText", ReplaceGossipFormat)
        element.__refineui_gossip_text_hooks_installed = true
    end
end

-- Blizzard themes only the registered font strings, in UpdateTheme, which Update calls
-- last; rows acquired while scrolling keep their template color until restyled here.
local function ApplyGossipTextColor()
    GossipFrame.GreetingPanel.ScrollBox:ForEachFrame(StyleGossipElement)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupGossipFrameSkin()
    RefineUI:HookOnce(COMPONENT_KEY .. ":UpdateTheme", GossipFrame, "UpdateTheme", ApplyGossipTextColor)
    RefineUI:HookOnce(COMPONENT_KEY .. ":ScrollBox:Update", GossipFrame.GreetingPanel.ScrollBox, "Update", ApplyGossipTextColor)
end
