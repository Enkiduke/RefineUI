----------------------------------------------------------------------------------------
-- Tooltip Hyperlink Support
-- Description: Chat hyperlink tooltip hover behavior.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
local Chat = RefineUI:GetModule("Chat")
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
local EventRegistry = _G.EventRegistry
local GameTooltip = _G.GameTooltip

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local callbacksRegistered = false

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
local function ShouldSuppressHyperlinkTooltip()
    if Chat and Chat.ShouldSuspendOptionalEnhancements and Chat:ShouldSuspendOptionalEnhancements() then
        return true
    end
    if type(Tooltip.MaybeHideInCombat) == "function" then
        return Tooltip:MaybeHideInCombat(GameTooltip) == true
    end
    return false
end

local function OnHyperlinkEnter(_, frame, link)
    if type(link) ~= "string" or link == "" then
        return
    end
    if ShouldSuppressHyperlinkTooltip() then
        local battlePetTooltip = _G.BattlePetTooltip
        if battlePetTooltip and battlePetTooltip.IsShown and battlePetTooltip:IsShown() then
            battlePetTooltip:Hide()
        end
        GameTooltip:Hide()
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
    if callbacksRegistered then
        return
    end

    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    callbacksRegistered = true
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", OnHyperlinkEnter, self)
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", OnHyperlinkLeave, self)
end
