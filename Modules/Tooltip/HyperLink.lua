----------------------------------------------------------------------------------------
-- Tooltip Hyperlink Support
-- Description: Chat hyperlink tooltip hover behavior.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local strsplit = strsplit
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local HYPERLINK_TYPES = {
    item = true,
    enchant = true,
    spell = true,
    quest = true,
    unit = true,
    talent = true,
    achievement = true,
    glyph = true,
    instancelock = true,
    currency = true,
}

----------------------------------------------------------------------------------------
-- Hyperlink Handlers
----------------------------------------------------------------------------------------
local function OnHyperlinkEnter(frame, link)
    if type(link) ~= "string" or link == "" then
        return
    end

    local linkType = link:match("^([^:]+)")
    if linkType == "battlepet" then
        GameTooltip:SetOwner(frame, "ANCHOR_TOPLEFT", -3, 0)
        GameTooltip:Show()

        local _, speciesID, level, breedQuality, maxHealth, power, speed = strsplit(":", link)
        if type(BattlePetToolTip_Show) == "function" then
            BattlePetToolTip_Show(
                tonumber(speciesID),
                tonumber(level),
                tonumber(breedQuality),
                tonumber(maxHealth),
                tonumber(power),
                tonumber(speed)
            )
        end
    elseif HYPERLINK_TYPES[linkType] then
        GameTooltip:SetOwner(frame, "ANCHOR_TOPLEFT", -3, 0)
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function OnHyperlinkLeave()
    local battlePetTooltip = _G.BattlePetTooltip
    if battlePetTooltip and battlePetTooltip.IsShown and battlePetTooltip:IsShown() then
        battlePetTooltip:Hide()
    else
        GameTooltip:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeHyperlinkSupport()
    for chatIndex = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. chatIndex]
        if frame then
            RefineUI:HookScriptOnce("Tooltip:ChatFrame" .. chatIndex .. ":OnHyperlinkEnter", frame, "OnHyperlinkEnter", OnHyperlinkEnter)
            RefineUI:HookScriptOnce("Tooltip:ChatFrame" .. chatIndex .. ":OnHyperlinkLeave", frame, "OnHyperlinkLeave", OnHyperlinkLeave)
        end
    end
end
