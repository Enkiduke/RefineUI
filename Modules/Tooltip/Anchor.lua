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
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local select = select
local type = type
local pcall = pcall
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_COMPARISON_ADDON_LOADED_KEY = "Tooltip:ComparisonSpacing:OnAddonLoaded"
local TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY = "Tooltip:GameTooltip_SetDefaultAnchor"
local SHOPPING_TOOLTIP_ONSHOW_HOOK_KEY_PREFIX = "Tooltip:ComparisonSpacing:OnShow:"
local SHOPPING_TOOLTIP_ONSHOW_DEBOUNCE_KEY_PREFIX = "Tooltip:ComparisonSpacing:DeferredApply:"
local SHOPPING_TOOLTIP_FRAME_NAMES = {
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local lastComparisonSideByTooltip = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------------------------
-- Comparison Tooltip Gap Helpers
----------------------------------------------------------------------------------------
local function GetTooltipWidthSafe(frame)
    if not Tooltip:IsGameTooltipFrameSafe(frame) then
        return 0
    end

    local okWidth, width = Tooltip:SafeObjectMethodCall(frame, "GetWidth")
    width = okWidth and Tooltip:ReadSafeNumber(width) or nil
    if width and width > 0 then
        return width
    end

    local okLeft, left = Tooltip:SafeObjectMethodCall(frame, "GetLeft")
    local okRight, right = Tooltip:SafeObjectMethodCall(frame, "GetRight")
    left = okLeft and Tooltip:ReadSafeNumber(left) or nil
    right = okRight and Tooltip:ReadSafeNumber(right) or nil
    if left and right and right > left then
        return right - left
    end

    return 0
end

local function GetComparisonSideAnchorFrame(anchorFrame)
    if not Tooltip:CanAccessObjectSafe(anchorFrame) or Tooltip:IsForbiddenFrameSafe(anchorFrame) then
        return nil
    end

    local sideAnchorFrame = anchorFrame
    local okEmbedded, isEmbedded = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "IsEmbedded")
    if okEmbedded and Tooltip:ReadSafeBoolean(isEmbedded) == true then
        local okParent, parent = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "GetParent")
        if okParent and parent then
            local okGrandParent, grandParent = Tooltip:SafeObjectMethodCall(parent, "GetParent")
            if okGrandParent and grandParent then
                sideAnchorFrame = grandParent
            end
        end
    end

    return sideAnchorFrame
end

local function HasAnchoredPoint(frame, expectedPoint, expectedRelativeTo, expectedRelativePoint)
    if not Tooltip:IsGameTooltipFrameSafe(frame) then
        return false
    end

    local pointCount = 1
    local okPointCount, numPoints = Tooltip:SafeObjectMethodCall(frame, "GetNumPoints")
    if okPointCount and Tooltip:ReadSafeNumber(numPoints) and numPoints > 0 then
        pointCount = numPoints
    end

    for pointIndex = 1, pointCount do
        local okPoint, point, relativeTo, relativePoint = Tooltip:SafeObjectMethodCall(frame, "GetPoint", pointIndex)
        if okPoint then
            local safePoint = Tooltip:ReadSafeString(point)
            local safeRelativePoint = Tooltip:ReadSafeString(relativePoint)
            local safeRelativeTo = nil
            if not Tooltip:IsSecretValueSafe(relativeTo) then
                safeRelativeTo = relativeTo
            end

            if safePoint == expectedPoint and safeRelativeTo == expectedRelativeTo then
                if not expectedRelativePoint or safeRelativePoint == expectedRelativePoint then
                    return true
                end
            end
        end
    end

    return false
end

local function ResolveComparisonTooltipSide(primaryTooltip, secondaryTooltip, sideAnchorFrame, secondaryShown)
    local function ResolveByBounds()
        local okSideLeft, sideLeft = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "GetLeft")
        local okSideRight, sideRight = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "GetRight")
        sideLeft = okSideLeft and Tooltip:ReadSafeNumber(sideLeft) or nil
        sideRight = okSideRight and Tooltip:ReadSafeNumber(sideRight) or nil
        if not sideLeft or not sideRight then
            return nil
        end

        local function GetBounds(frame)
            if not Tooltip:IsGameTooltipFrameSafe(frame) then
                return nil, nil
            end
            local okLeft, left = Tooltip:SafeObjectMethodCall(frame, "GetLeft")
            local okRight, right = Tooltip:SafeObjectMethodCall(frame, "GetRight")
            left = okLeft and Tooltip:ReadSafeNumber(left) or nil
            right = okRight and Tooltip:ReadSafeNumber(right) or nil
            return left, right
        end

        local primaryLeft, primaryRight = GetBounds(primaryTooltip)
        local secondaryLeft, secondaryRight = GetBounds(secondaryTooltip)

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

    if secondaryShown then
        if HasAnchoredPoint(primaryTooltip, "RIGHT", sideAnchorFrame, "LEFT") then
            return "left"
        end
        if HasAnchoredPoint(secondaryTooltip, "LEFT", sideAnchorFrame, "RIGHT") then
            return "right"
        end
        return ResolveByBounds()
    else
        if HasAnchoredPoint(primaryTooltip, "RIGHT", sideAnchorFrame, "LEFT") then
            return "left"
        end
        if HasAnchoredPoint(primaryTooltip, "LEFT", sideAnchorFrame, "RIGHT") then
            return "right"
        end
        return ResolveByBounds()
    end
end

local function ResolveComparisonTooltipSideByAnchorType(sideAnchorFrame, tooltip)
    local okAnchorType, anchorType = Tooltip:SafeObjectMethodCall(sideAnchorFrame, "GetAnchorType")
    if not okAnchorType then
        okAnchorType, anchorType = Tooltip:SafeObjectMethodCall(tooltip, "GetAnchorType")
    end
    if not okAnchorType then
        return nil
    end

    local safeAnchorType = Tooltip:ReadSafeString(anchorType)
    if not safeAnchorType then
        return nil
    end

    if safeAnchorType == "ANCHOR_LEFT" or safeAnchorType == "ANCHOR_TOPLEFT" or safeAnchorType == "ANCHOR_BOTTOMLEFT" then
        return "left"
    end
    if safeAnchorType == "ANCHOR_RIGHT" or safeAnchorType == "ANCHOR_TOPRIGHT" or safeAnchorType == "ANCHOR_BOTTOMRIGHT" then
        return "right"
    end

    return nil
end

local function ApplyComparisonTooltipGap(manager, primaryShown, secondaryShown)
    if type(manager) ~= "table" or not Tooltip:CanAccessObjectSafe(manager) then
        return
    end

    local tooltip, okTooltip = Tooltip:SafeGetField(manager, "tooltip")
    if not okTooltip or not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return
    end

    local shoppingTooltips, okShopping = Tooltip:SafeGetField(tooltip, "shoppingTooltips")
    if not okShopping or type(shoppingTooltips) ~= "table" then
        return
    end

    local primaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 1))
    if not Tooltip:IsGameTooltipFrameSafe(primaryTooltip) then
        return
    end

    local showSecondary = Tooltip:ReadSafeBoolean(secondaryShown) == true
    local secondaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 2))
    if showSecondary and not Tooltip:IsGameTooltipFrameSafe(secondaryTooltip) then
        return
    end

    local showPrimary = Tooltip:ReadSafeBoolean(primaryShown) == true
    if not showPrimary and not showSecondary then
        return
    end

    local anchorFrame = select(1, Tooltip:SafeGetField(manager, "anchorFrame")) or tooltip
    if not Tooltip:CanAccessObjectSafe(anchorFrame) or Tooltip:IsForbiddenFrameSafe(anchorFrame) then
        anchorFrame = tooltip
    end

    local sideAnchorFrame = GetComparisonSideAnchorFrame(anchorFrame)
    if not Tooltip:CanAccessObjectSafe(sideAnchorFrame) or Tooltip:IsForbiddenFrameSafe(sideAnchorFrame) then
        return
    end

    local side = ResolveComparisonTooltipSide(primaryTooltip, secondaryTooltip, sideAnchorFrame, showSecondary)
    if not side then
        side = ResolveComparisonTooltipSideByAnchorType(sideAnchorFrame, tooltip)
    end
    if not side then
        side = lastComparisonSideByTooltip[tooltip]
    end
    if not side then
        side = "right"
    else
        lastComparisonSideByTooltip[tooltip] = side
    end

    if not Tooltip:SafeObjectMethodCall(primaryTooltip, "ClearAllPoints") then
        return
    end

    if showSecondary and not Tooltip:SafeObjectMethodCall(secondaryTooltip, "ClearAllPoints") then
        return
    end

    if not Tooltip:SafeObjectMethodCall(primaryTooltip, "SetPoint", "TOP", anchorFrame, "TOP", 0, 0) then
        return
    end

    if showSecondary and not Tooltip:SafeObjectMethodCall(secondaryTooltip, "SetPoint", "TOP", anchorFrame, "TOP", 0, 0) then
        return
    end

    local gap = Tooltip:GetTooltipComparisonGap()
    if side == "left" then
        if not Tooltip:SafeObjectMethodCall(primaryTooltip, "SetPoint", "RIGHT", sideAnchorFrame, "LEFT", -gap, 0) then
            return
        end
        if showSecondary then
            local primaryWidth = GetTooltipWidthSafe(primaryTooltip)
            local secondaryOffset = -gap - ((primaryWidth > 0) and (primaryWidth + gap) or gap)
            Tooltip:SafeObjectMethodCall(secondaryTooltip, "SetPoint", "RIGHT", sideAnchorFrame, "LEFT", secondaryOffset, 0)
        end
    else
        if showSecondary then
            if not Tooltip:SafeObjectMethodCall(secondaryTooltip, "SetPoint", "LEFT", sideAnchorFrame, "RIGHT", gap, 0) then
                return
            end
            local secondaryWidth = GetTooltipWidthSafe(secondaryTooltip)
            local primaryOffset = gap + ((secondaryWidth > 0) and (secondaryWidth + gap) or gap)
            Tooltip:SafeObjectMethodCall(primaryTooltip, "SetPoint", "LEFT", sideAnchorFrame, "RIGHT", primaryOffset, 0)
        else
            Tooltip:SafeObjectMethodCall(primaryTooltip, "SetPoint", "LEFT", sideAnchorFrame, "RIGHT", gap, 0)
        end
    end
end

local function ApplyComparisonTooltipGapFromTooltip(tooltip)
    local comparisonManager = _G.TooltipComparisonManager
    local managerTooltip = nil
    if type(comparisonManager) == "table" and Tooltip:CanAccessObjectSafe(comparisonManager) then
        local rawManagerTooltip, okManagerTooltip = Tooltip:SafeGetField(comparisonManager, "tooltip")
        if okManagerTooltip and Tooltip:IsGameTooltipFrameSafe(rawManagerTooltip) then
            managerTooltip = rawManagerTooltip
        end
    end

    local targetTooltip = nil
    if tooltip and Tooltip:IsGameTooltipFrameSafe(tooltip) then
        targetTooltip = tooltip
    else
        targetTooltip = managerTooltip
    end

    if not Tooltip:IsGameTooltipFrameSafe(targetTooltip) then
        return
    end

    local shoppingTooltips, okShopping = Tooltip:SafeGetField(targetTooltip, "shoppingTooltips")
    if not okShopping or type(shoppingTooltips) ~= "table" then
        return
    end

    local primaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 1))
    if not Tooltip:IsGameTooltipFrameSafe(primaryTooltip) then
        return
    end

    local secondaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 2))
    local primaryShown = false
    local secondaryShown = false

    local okPrimaryShown, isPrimaryShown = Tooltip:SafeObjectMethodCall(primaryTooltip, "IsShown")
    if okPrimaryShown and Tooltip:ReadSafeBoolean(isPrimaryShown) == true then
        primaryShown = true
    end

    if Tooltip:IsGameTooltipFrameSafe(secondaryTooltip) then
        local okSecondaryShown, isSecondaryShown = Tooltip:SafeObjectMethodCall(secondaryTooltip, "IsShown")
        if okSecondaryShown and Tooltip:ReadSafeBoolean(isSecondaryShown) == true then
            secondaryShown = true
        end
    end

    if not primaryShown and not secondaryShown then
        return
    end

    local managerForApply = comparisonManager
    if type(managerForApply) ~= "table" or not Tooltip:CanAccessObjectSafe(managerForApply) or managerTooltip ~= targetTooltip then
        managerForApply = {
            tooltip = targetTooltip,
            anchorFrame = targetTooltip,
        }
    end

    ApplyComparisonTooltipGap(managerForApply, primaryShown, secondaryShown)
end

local function ClearComparisonTooltipsForTooltip(tooltip)
    if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return
    end

    local comparisonManager = _G.TooltipComparisonManager
    if type(comparisonManager) == "table" and Tooltip:CanAccessObjectSafe(comparisonManager) then
        Tooltip:SafeObjectMethodCall(comparisonManager, "Clear", tooltip)
    end

    local shoppingTooltips, okShopping = Tooltip:SafeGetField(tooltip, "shoppingTooltips")
    if not okShopping or type(shoppingTooltips) ~= "table" then
        return
    end

    for index = 1, 2 do
        local shoppingTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, index))
        if Tooltip:IsGameTooltipFrameSafe(shoppingTooltip) then
            Tooltip:SafeObjectMethodCall(shoppingTooltip, "Hide")
        end
    end
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

local function TryHookShoppingTooltipOnShow()
    local hookedAny = false

    for index = 1, #SHOPPING_TOOLTIP_FRAME_NAMES do
        local frameName = SHOPPING_TOOLTIP_FRAME_NAMES[index]
        local shoppingTooltip = _G[frameName]
        if Tooltip:IsGameTooltipFrameSafe(shoppingTooltip) then
            local hookKey = SHOPPING_TOOLTIP_ONSHOW_HOOK_KEY_PREFIX .. frameName
            local ok, reason = RefineUI:HookScriptOnce(hookKey, shoppingTooltip, "OnShow", function(frame)
                local okOwner, ownerTooltip = Tooltip:SafeObjectMethodCall(frame, "GetOwner")
                local debounceKey = SHOPPING_TOOLTIP_ONSHOW_DEBOUNCE_KEY_PREFIX .. frameName
                if okOwner and Tooltip:IsGameTooltipFrameSafe(ownerTooltip) then
                    RefineUI:Debounce(debounceKey, 0, function()
                        ApplyComparisonTooltipGapFromTooltip(ownerTooltip)
                    end)
                else
                    RefineUI:Debounce(debounceKey, 0, function()
                        ApplyComparisonTooltipGapFromTooltip(frame)
                    end)
                end
            end)
            if ok or reason == "already_hooked" then
                hookedAny = true
            end
        end
    end

    return hookedAny
end

function Tooltip:TryHookComparisonTooltipSpacing()
    local comparisonHookKey = Tooltip:GetTooltipComparisonHookKey()
    local compareItemHookKey = Tooltip:GetTooltipCompareItemHookKey()

    local hasComparisonHook = RefineUI:IsHookRegistered(comparisonHookKey)
    local hasCompareItemHook = RefineUI:IsHookRegistered(compareItemHookKey)
    if not hasCompareItemHook then
        local compareItemHooked, compareItemReason = RefineUI:HookOnce(
            compareItemHookKey,
            "GameTooltip_ShowCompareItem",
            function(tt)
                local targetTooltip = tt or GameTooltip
                if Tooltip:IsEmbeddedTooltipFrame(targetTooltip) then
                    ClearComparisonTooltipsForTooltip(targetTooltip)
                    return
                end

                ApplyComparisonTooltipGapFromTooltip(targetTooltip)
            end
        )
        if compareItemHooked or compareItemReason == "already_hooked" then
            hasCompareItemHook = true
        end
    end

    if not hasComparisonHook then
        local comparisonManager = _G.TooltipComparisonManager
        if type(comparisonManager) == "table" and Tooltip:CanAccessObjectSafe(comparisonManager) then
            local anchorShoppingTooltips, okField = Tooltip:SafeGetField(comparisonManager, "AnchorShoppingTooltips")
            if okField and type(anchorShoppingTooltips) == "function" then
                local ok, reason = RefineUI:HookOnce(comparisonHookKey, comparisonManager, "AnchorShoppingTooltips", function(manager, primaryShown, secondaryShown)
                    ApplyComparisonTooltipGap(manager, primaryShown, secondaryShown)
                end)
                if ok or reason == "already_hooked" then
                    hasComparisonHook = true
                end
            end
        end
    end

    local hasOnShowHook = TryHookShoppingTooltipOnShow()
    return hasCompareItemHook or hasComparisonHook or hasOnShowHook
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
end
