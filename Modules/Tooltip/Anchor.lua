----------------------------------------------------------------------------------------
-- Tooltip Anchor
-- Description: Default tooltip anchoring and equipped-comparison spacing behavior.
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
local type = type
local pcall = pcall
local min = math.min
local max = math.max

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GetScreenWidth = GetScreenWidth

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_COMPARISON_ADDON_LOADED_KEY = "Tooltip:ComparisonSpacing:OnAddonLoaded"
local TOOLTIP_COMPARISON_PLAYER_LOGIN_KEY = "Tooltip:ComparisonSpacing:OnPlayerLogin"
local TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY = "Tooltip:GameTooltip_SetDefaultAnchor"
local SHOPPING_TOOLTIP_COMPARE_AFTER_KEY_PREFIX = "Tooltip:ComparisonSpacing:CompareItemAfter:"

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- Comparison Tooltip Gap Helpers
----------------------------------------------------------------------------------------

local function IsFrameUsable(frame)
    local frameType = type(frame)
    if frameType ~= "table" and frameType ~= "userdata" then
        return false
    end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        return false
    end
    return true
end

local function GetComparisonTooltips(tooltip)
    if not IsFrameUsable(tooltip) then
        return nil, nil
    end

    local shoppingTooltips = tooltip.shoppingTooltips
    if type(shoppingTooltips) ~= "table" then
        return nil, nil
    end

    local primaryTooltip = shoppingTooltips[1]
    local secondaryTooltip = shoppingTooltips[2]
    if not IsFrameUsable(primaryTooltip) then
        return nil, nil
    end
    if secondaryTooltip and not IsFrameUsable(secondaryTooltip) then
        secondaryTooltip = nil
    end

    return primaryTooltip, secondaryTooltip
end

local function GetAnchorFrames(manager, tooltip)
    local anchorFrame = manager and manager.anchorFrame or tooltip
    if not IsFrameUsable(anchorFrame) then
        anchorFrame = tooltip
    end

    local sideAnchorFrame = anchorFrame
    if sideAnchorFrame and sideAnchorFrame.IsEmbedded then
        local parentFrame = sideAnchorFrame:GetParent()
        local grandParentFrame = parentFrame and parentFrame:GetParent() or nil
        if IsFrameUsable(grandParentFrame) then
            sideAnchorFrame = grandParentFrame
        end
    end
    if not IsFrameUsable(sideAnchorFrame) then
        sideAnchorFrame = tooltip
    end

    return anchorFrame, sideAnchorFrame
end

local function DetermineComparisonSide(anchorType, totalWidth, leftPos, rightDist)
    if anchorType and totalWidth < leftPos and (
        anchorType == "ANCHOR_LEFT"
        or anchorType == "ANCHOR_TOPLEFT"
        or anchorType == "ANCHOR_BOTTOMLEFT"
    ) then
        return "left"
    end
    if anchorType and totalWidth < rightDist and (
        anchorType == "ANCHOR_RIGHT"
        or anchorType == "ANCHOR_TOPRIGHT"
        or anchorType == "ANCHOR_BOTTOMRIGHT"
    ) then
        return "right"
    end
    if rightDist < leftPos then
        return "left"
    end
    return "right"
end

local function AnchorComparisonTooltipsWithGap(manager, primaryShown, secondaryShown)
    if type(manager) ~= "table" then
        return
    end

    local tooltip = manager.tooltip
    if not IsFrameUsable(tooltip) then
        return
    end

    local primaryTooltip, secondaryTooltip = GetComparisonTooltips(tooltip)
    if not primaryTooltip then
        return
    end

    primaryShown = primaryShown == true
    secondaryShown = secondaryShown == true and secondaryTooltip ~= nil

    primaryTooltip:SetShown(primaryShown)
    if secondaryTooltip then
        secondaryTooltip:SetShown(secondaryShown)
    end

    if not primaryShown and not secondaryShown then
        return
    end

    local gap = Tooltip:GetTooltipComparisonGap()
    local anchorFrame, sideAnchorFrame = GetAnchorFrames(manager, tooltip)
    if not IsFrameUsable(anchorFrame) or not IsFrameUsable(sideAnchorFrame) then
        return
    end

    local leftPos = sideAnchorFrame:GetLeft()
    local rightPos = sideAnchorFrame:GetRight()
    local selfLeftPos = tooltip:GetLeft()
    local selfRightPos = tooltip:GetRight()
    if leftPos and selfLeftPos then
        leftPos = min(selfLeftPos, leftPos)
        rightPos = max(selfRightPos, rightPos)
    else
        leftPos = leftPos or selfLeftPos or 0
        rightPos = rightPos or selfRightPos or 0
    end

    local anchorType = sideAnchorFrame.GetAnchorType and sideAnchorFrame:GetAnchorType() or tooltip:GetAnchorType()
    local totalWidth = 0
    if primaryShown then
        totalWidth = totalWidth + primaryTooltip:GetWidth()
    end
    if secondaryShown and secondaryTooltip then
        totalWidth = totalWidth + secondaryTooltip:GetWidth() + gap
    end
    if totalWidth > 0 then
        totalWidth = totalWidth + gap
    end

    local screenWidth = GetScreenWidth()
    local rightDist = screenWidth - rightPos
    local side = DetermineComparisonSide(anchorType, totalWidth, leftPos, rightDist)

    if totalWidth > 0 and anchorType and anchorType ~= "ANCHOR_PRESERVE" then
        local slideAmount = 0
        if side == "left" and totalWidth > leftPos then
            slideAmount = totalWidth - leftPos
        elseif side == "right" and (rightPos + totalWidth) > screenWidth then
            slideAmount = screenWidth - (rightPos + totalWidth)
        end

        if slideAmount ~= 0 then
            if sideAnchorFrame.SetAnchorType then
                sideAnchorFrame:SetAnchorType(anchorType, slideAmount, 0)
            else
                tooltip:SetAnchorType(anchorType, slideAmount, 0)
            end
        end
    end

    if secondaryShown and secondaryTooltip then
        primaryTooltip:ClearAllPoints()
        secondaryTooltip:ClearAllPoints()
        primaryTooltip:SetPoint("TOP", anchorFrame, 0, 0)
        secondaryTooltip:SetPoint("TOP", anchorFrame, 0, 0)

        if side == "left" then
            primaryTooltip:SetPoint("RIGHT", sideAnchorFrame, "LEFT", -gap, 0)
            secondaryTooltip:SetPoint("TOPRIGHT", primaryTooltip, "TOPLEFT", -gap, 0)
        else
            secondaryTooltip:SetPoint("LEFT", sideAnchorFrame, "RIGHT", gap, 0)
            primaryTooltip:SetPoint("TOPLEFT", secondaryTooltip, "TOPRIGHT", gap, 0)
        end
    else
        primaryTooltip:ClearAllPoints()
        primaryTooltip:SetPoint("TOP", anchorFrame, 0, 0)
        if side == "left" then
            primaryTooltip:SetPoint("RIGHT", sideAnchorFrame, "LEFT", -gap, 0)
        else
            primaryTooltip:SetPoint("LEFT", sideAnchorFrame, "RIGHT", gap, 0)
        end
    end
end

local function ApplyComparisonTooltipGapFromTooltip(tooltip)
    if not IsFrameUsable(tooltip) then
        return
    end

    local primaryTooltip, secondaryTooltip = GetComparisonTooltips(tooltip)
    if not primaryTooltip then
        return
    end

    local primaryShown = primaryTooltip:IsShown()
    local secondaryShown = secondaryTooltip and secondaryTooltip:IsShown() or false
    if not primaryShown and not secondaryShown then
        return
    end

    local manager = _G.TooltipComparisonManager
    if type(manager) == "table" and manager.tooltip == tooltip then
        AnchorComparisonTooltipsWithGap(manager, primaryShown, secondaryShown)
        return
    end

    AnchorComparisonTooltipsWithGap({
        tooltip = tooltip,
        anchorFrame = tooltip,
    }, primaryShown, secondaryShown)
end

----------------------------------------------------------------------------------------
-- Tooltip Anchor
----------------------------------------------------------------------------------------
function Tooltip.TooltipAnchorUpdate(tt, parent)
    if not tt then
        return
    end
    if not Tooltip:IsGameTooltipFrameSafe(tt) then
        return
    end

    if parent and (not Tooltip:CanAccessObjectSafe(parent) or Tooltip:IsForbiddenFrameSafe(parent)) then
        return
    end
    if not parent then
        parent = _G.UIParent
    end

    local worldMapFrame = _G.WorldMapFrame
    if parent and worldMapFrame then
        local check = parent
        while check do
            if check == worldMapFrame then
                return
            end

            local getParent, okField = Tooltip:SafeGetField(check, "GetParent")
            if not okField or type(getParent) ~= "function" then
                break
            end

            local okParent, parentValue = pcall(getParent, check)
            if not okParent then
                break
            end
            check = parentValue
        end
    end

    if parent ~= _G.UIParent then
        tt:SetOwner(parent, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 4)
    else
        tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 10, 10)
    end
end

function Tooltip:SetTooltipAnchor()
    RefineUI:HookOnce(TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY, "GameTooltip_SetDefaultAnchor", Tooltip.TooltipAnchorUpdate)
end

function Tooltip:TryHookComparisonTooltipSpacing()
    local comparisonHookKey = Tooltip:GetTooltipComparisonHookKey()
    local compareItemHookKey = Tooltip:GetTooltipCompareItemHookKey()
    local hasCompareItemHook = RefineUI:IsHookRegistered(compareItemHookKey)
    if not hasCompareItemHook then
        local compareItemHooked, compareItemReason = RefineUI:HookOnce(
            compareItemHookKey,
            "GameTooltip_ShowCompareItem",
            function(tt)
                local targetTooltip = tt or _G.GameTooltip
                if not Tooltip:IsGameTooltipFrameSafe(targetTooltip) then
                    return
                end

                ApplyComparisonTooltipGapFromTooltip(targetTooltip)
                local tooltipName = Tooltip:GetTooltipNameSafe(targetTooltip) or "UnknownTooltip"
                local afterKey = SHOPPING_TOOLTIP_COMPARE_AFTER_KEY_PREFIX .. tooltipName
                RefineUI:After(afterKey, 0, function()
                    ApplyComparisonTooltipGapFromTooltip(targetTooltip)
                end)
            end
        )
        hasCompareItemHook = compareItemHooked or compareItemReason == "already_hooked"
    end

    local hasComparisonHook = RefineUI:IsHookRegistered(comparisonHookKey)
    if not hasComparisonHook then
        local comparisonManager = _G.TooltipComparisonManager
        if type(comparisonManager) == "table" and type(comparisonManager.AnchorShoppingTooltips) == "function" then
            local ok, reason = RefineUI:HookOnce(
                comparisonHookKey,
                comparisonManager,
                "AnchorShoppingTooltips",
                function(manager, primaryShown, secondaryShown)
                    AnchorComparisonTooltipsWithGap(manager, primaryShown, secondaryShown)
                end
            )
            hasComparisonHook = ok or reason == "already_hooked"
        end
    end

    return hasComparisonHook or hasCompareItemHook
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipAnchor()
    Tooltip:SetTooltipAnchor()
    Tooltip:TryHookComparisonTooltipSpacing()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function()
        Tooltip:TryHookComparisonTooltipSpacing()
    end, TOOLTIP_COMPARISON_ADDON_LOADED_KEY)

    RefineUI:RegisterEventCallback("PLAYER_LOGIN", function()
        Tooltip:TryHookComparisonTooltipSpacing()
    end, TOOLTIP_COMPARISON_PLAYER_LOGIN_KEY)
end
