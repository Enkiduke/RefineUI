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

local function GetFrameNumber(frame, methodName)
    if not IsFrameUsable(frame) then
        return nil
    end

    local ok, value = Tooltip:SafeObjectMethodCall(frame, methodName)
    if not ok then
        return nil
    end

    return Tooltip:ReadSafeNumber(value)
end

local function HasAnchoredPoint(frame, expectedPoint, expectedRelativeTo, expectedRelativePoint)
    if not IsFrameUsable(frame) then
        return false
    end

    local pointCount = GetFrameNumber(frame, "GetNumPoints") or 1
    for pointIndex = 1, pointCount do
        local okPoint, point, relativeTo, relativePoint = Tooltip:SafeObjectMethodCall(frame, "GetPoint", pointIndex)
        if okPoint then
            local safePoint = Tooltip:ReadSafeString(point)
            local safeRelativePoint = Tooltip:ReadSafeString(relativePoint)
            local safeRelativeTo = Tooltip:IsSecretValueSafe(relativeTo) and nil or relativeTo

            if safePoint == expectedPoint and safeRelativeTo == expectedRelativeTo then
                if not expectedRelativePoint or safeRelativePoint == expectedRelativePoint then
                    return true
                end
            end
        end
    end

    return false
end

local function IsTooltipShown(frame)
    local okShown, shown = Tooltip:SafeObjectMethodCall(frame, "IsShown")
    if not okShown then
        return false
    end

    return Tooltip:ReadSafeBoolean(shown) == true
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
    if sideAnchorFrame then
        local isEmbedded = Tooltip:ReadSafeBoolean(sideAnchorFrame.IsEmbedded) == true
        if isEmbedded then
            local okParent, parentFrame = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "GetParent")
            local okGrandParent, grandParentFrame = okParent and Tooltip:SafeObjectMethodCall(parentFrame, "GetParent")
            if okGrandParent and IsFrameUsable(grandParentFrame) then
                sideAnchorFrame = grandParentFrame
            end
        end
    end
    if not IsFrameUsable(sideAnchorFrame) then
        sideAnchorFrame = tooltip
    end

    return anchorFrame, sideAnchorFrame
end

local function ResolveComparisonTooltipSideFromAnchors(primaryTooltip, secondaryTooltip, sideAnchorFrame, secondaryShown)
    if secondaryShown then
        if HasAnchoredPoint(primaryTooltip, "RIGHT", sideAnchorFrame, "LEFT") then
            return "left"
        end
        if HasAnchoredPoint(secondaryTooltip, "LEFT", sideAnchorFrame, "RIGHT") then
            return "right"
        end
    else
        if HasAnchoredPoint(primaryTooltip, "RIGHT", sideAnchorFrame, "LEFT") then
            return "left"
        end
        if HasAnchoredPoint(primaryTooltip, "LEFT", sideAnchorFrame, "RIGHT") then
            return "right"
        end
    end

    -- Optional bounds-based fallback when geometry is safe and available.
    local sideLeft = GetFrameNumber(sideAnchorFrame, "GetLeft")
    local sideRight = GetFrameNumber(sideAnchorFrame, "GetRight")
    if not sideLeft or not sideRight then
        return nil
    end

    local primaryLeft = GetFrameNumber(primaryTooltip, "GetLeft")
    local primaryRight = GetFrameNumber(primaryTooltip, "GetRight")
    local secondaryLeft = secondaryShown and GetFrameNumber(secondaryTooltip, "GetLeft") or nil
    local secondaryRight = secondaryShown and GetFrameNumber(secondaryTooltip, "GetRight") or nil

    if secondaryShown and secondaryRight and secondaryRight <= sideLeft then
        return "left"
    end
    if secondaryShown and secondaryLeft and secondaryLeft >= sideRight then
        return "right"
    end
    if primaryRight and primaryRight <= sideLeft then
        return "left"
    end
    if primaryLeft and primaryLeft >= sideRight then
        return "right"
    end

    return nil
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

    local requestedPrimaryShown = Tooltip:ReadSafeBoolean(primaryShown)
    local requestedSecondaryShown = Tooltip:ReadSafeBoolean(secondaryShown)
    if requestedPrimaryShown == nil then
        primaryShown = IsTooltipShown(primaryTooltip)
    else
        primaryShown = requestedPrimaryShown
    end
    if secondaryTooltip then
        if requestedSecondaryShown == nil then
            secondaryShown = IsTooltipShown(secondaryTooltip)
        else
            secondaryShown = requestedSecondaryShown
        end
    else
        secondaryShown = false
    end

    if not primaryShown and not secondaryShown then
        return
    end

    local gap = Tooltip:ReadSafeNumber(Tooltip:GetTooltipComparisonGap()) or 0
    local anchorFrame, sideAnchorFrame = GetAnchorFrames(manager, tooltip)
    if not IsFrameUsable(anchorFrame) or not IsFrameUsable(sideAnchorFrame) then
        return
    end

    local side = ResolveComparisonTooltipSideFromAnchors(primaryTooltip, secondaryTooltip, sideAnchorFrame, secondaryShown)
    if not side then
        -- Unknown side in tainted/secret geometry paths: keep Blizzard placement unchanged.
        return
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

    local primaryShown = IsTooltipShown(primaryTooltip)
    local secondaryShown = secondaryTooltip and IsTooltipShown(secondaryTooltip) or false
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
