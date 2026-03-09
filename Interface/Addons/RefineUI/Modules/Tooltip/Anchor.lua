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
local setmetatable = setmetatable

-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_COMPARISON_ADDON_LOADED_KEY = "Tooltip:ComparisonSpacing:OnAddonLoaded"
local TOOLTIP_COMPARISON_PLAYER_LOGIN_KEY = "Tooltip:ComparisonSpacing:OnPlayerLogin"
local TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY = "Tooltip:GameTooltip_SetDefaultAnchor"
local SHOPPING_TOOLTIP_CLEARPOINTS_HOOK_KEY_PREFIX = "Tooltip:ComparisonSpacing:ClearAllPoints:"
local SHOPPING_TOOLTIP_SETPOINT_HOOK_KEY_PREFIX = "Tooltip:ComparisonSpacing:SetPoint:"
local SHOPPING_TOOLTIP_FRAME_NAMES = {
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local comparisonTooltipPointState = setmetatable({}, { __mode = "k" })

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

local function GetComparisonTooltipPointState(frame)
    local state = comparisonTooltipPointState[frame]
    if type(state) ~= "table" then
        state = {}
        comparisonTooltipPointState[frame] = state
    end
    return state
end

local function ClearComparisonTooltipPointState(frame)
    local state = comparisonTooltipPointState[frame]
    if not state or state.adjusting then
        return
    end

    state.topRelativeTo = nil
    state.topRelativePoint = nil
    state.topOffsetX = nil
    state.topOffsetY = nil
end

local function NormalizeSetPointArgs(point, relativeTo, relativePoint, offsetX, offsetY)
    local safePoint = Tooltip:ReadSafeString(point)
    if not safePoint then
        return nil
    end

    local safeRelativeTo = Tooltip:IsSecretValueSafe(relativeTo) and nil or relativeTo
    local safeRelativePoint = Tooltip:ReadSafeString(relativePoint)
    local safeOffsetX = Tooltip:ReadSafeNumber(offsetX)
    local safeOffsetY = Tooltip:ReadSafeNumber(offsetY)

    if type(relativeTo) == "number" then
        safeOffsetX = Tooltip:ReadSafeNumber(relativeTo) or 0
        safeOffsetY = Tooltip:ReadSafeNumber(relativePoint) or 0
        safeRelativeTo = nil
        safeRelativePoint = nil
    elseif type(relativePoint) == "number" and offsetY == nil then
        safeOffsetX = Tooltip:ReadSafeNumber(relativePoint) or 0
        safeOffsetY = Tooltip:ReadSafeNumber(offsetX) or 0
        safeRelativePoint = safePoint
    else
        safeOffsetX = safeOffsetX or 0
        safeOffsetY = safeOffsetY or 0
        if safeRelativeTo and not safeRelativePoint then
            safeRelativePoint = safePoint
        end
    end

    return safePoint, safeRelativeTo, safeRelativePoint, safeOffsetX, safeOffsetY
end

local function HasAnchoredPoint(frame, expectedPoint, expectedRelativeTo, expectedRelativePoint)
    if not IsFrameUsable(frame) then
        return false
    end

    local okPointCount, pointCount = Tooltip:SafeObjectMethodCall(frame, "GetNumPoints")
    pointCount = okPointCount and Tooltip:ReadSafeNumber(pointCount) or 1
    if not pointCount or pointCount <= 0 then
        pointCount = 1
    end

    for pointIndex = 1, pointCount do
        local okPoint, point, relativeTo, relativePoint = Tooltip:SafeObjectMethodCall(frame, "GetPoint", pointIndex)
        if okPoint then
            local safePoint = Tooltip:ReadSafeString(point)
            local safeRelativePoint = Tooltip:ReadSafeString(relativePoint)
            local safeRelativeTo = Tooltip:IsSecretValueSafe(relativeTo) and nil or relativeTo

            if safePoint == expectedPoint then
                local relativeToMatches = expectedRelativeTo == nil or safeRelativeTo == expectedRelativeTo
                local relativePointMatches = not expectedRelativePoint or safeRelativePoint == expectedRelativePoint
                if relativeToMatches and relativePointMatches then
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
        if HasAnchoredPoint(primaryTooltip, "RIGHT") then
            return "left"
        end
        if HasAnchoredPoint(secondaryTooltip, "LEFT") then
            return "right"
        end
    else
        if HasAnchoredPoint(primaryTooltip, "RIGHT") then
            return "left"
        end
        if HasAnchoredPoint(primaryTooltip, "LEFT") then
            return "right"
        end
    end

    return nil
end

local function ResolveComparisonTooltipSideFromAnchorType(sideAnchorFrame, tooltip)
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

    if safeAnchorType == "ANCHOR_LEFT"
        or safeAnchorType == "ANCHOR_TOPLEFT"
        or safeAnchorType == "ANCHOR_BOTTOMLEFT"
        or safeAnchorType == "ANCHOR_CURSOR_LEFT"
    then
        return "left"
    end

    if safeAnchorType == "ANCHOR_RIGHT"
        or safeAnchorType == "ANCHOR_TOPRIGHT"
        or safeAnchorType == "ANCHOR_BOTTOMRIGHT"
        or safeAnchorType == "ANCHOR_CURSOR_RIGHT"
    then
        return "right"
    end

    return nil
end

local function TryApplyComparisonTooltipGapOnSetPoint(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    if not IsFrameUsable(frame) then
        return
    end

    local state = GetComparisonTooltipPointState(frame)
    if state.adjusting then
        return
    end

    local safePoint, safeRelativeTo, safeRelativePoint, safeOffsetX, safeOffsetY =
        NormalizeSetPointArgs(point, relativeTo, relativePoint, offsetX, offsetY)
    if not safePoint then
        return
    end

    if safePoint == "TOP" then
        state.topRelativeTo = safeRelativeTo
        state.topRelativePoint = safeRelativePoint or "TOP"
        state.topOffsetX = safeOffsetX
        state.topOffsetY = safeOffsetY
        return
    end

    if not safeRelativeTo or not safeRelativePoint then
        return
    end

    local gap = Tooltip:ReadSafeNumber(Tooltip:GetTooltipComparisonGap()) or 0
    local desiredOffsetX = nil
    if safePoint == "RIGHT" and safeRelativePoint == "LEFT" then
        desiredOffsetX = -gap
    elseif safePoint == "LEFT" and safeRelativePoint == "RIGHT" then
        desiredOffsetX = gap
    elseif safePoint == "TOPRIGHT" and safeRelativePoint == "TOPLEFT" then
        desiredOffsetX = -gap
    elseif safePoint == "TOPLEFT" and safeRelativePoint == "TOPRIGHT" then
        desiredOffsetX = gap
    else
        return
    end

    if safeOffsetX == desiredOffsetX then
        return
    end

    state.adjusting = true
    frame:ClearAllPoints()
    if state.topRelativeTo then
        frame:SetPoint("TOP", state.topRelativeTo, state.topRelativePoint or "TOP", state.topOffsetX or 0, state.topOffsetY or 0)
    end
    frame:SetPoint(safePoint, safeRelativeTo, safeRelativePoint, desiredOffsetX, safeOffsetY)
    state.adjusting = nil
end

local function TryHookShoppingTooltipSetPoints()
    local hookedAny = false

    for index = 1, #SHOPPING_TOOLTIP_FRAME_NAMES do
        local frameName = SHOPPING_TOOLTIP_FRAME_NAMES[index]
        local shoppingTooltip = _G[frameName]
        if IsFrameUsable(shoppingTooltip) then
            local clearHookKey = SHOPPING_TOOLTIP_CLEARPOINTS_HOOK_KEY_PREFIX .. frameName
            local clearHooked, clearReason = RefineUI:HookOnce(clearHookKey, shoppingTooltip, "ClearAllPoints", function(frame)
                ClearComparisonTooltipPointState(frame)
            end)
            if clearHooked or clearReason == "already_hooked" then
                hookedAny = true
            end

            local setPointHookKey = SHOPPING_TOOLTIP_SETPOINT_HOOK_KEY_PREFIX .. frameName
            local setPointHooked, setPointReason = RefineUI:HookOnce(setPointHookKey, shoppingTooltip, "SetPoint", function(frame, point, relativeTo, relativePoint, offsetX, offsetY)
                TryApplyComparisonTooltipGapOnSetPoint(frame, point, relativeTo, relativePoint, offsetX, offsetY)
            end)
            if setPointHooked or setPointReason == "already_hooked" then
                hookedAny = true
            end
        end
    end

    return hookedAny
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
        side = ResolveComparisonTooltipSideFromAnchorType(sideAnchorFrame, tooltip)
    end
    if not side then
        return
    end

    if secondaryShown and secondaryTooltip then
        primaryTooltip:ClearAllPoints()
        secondaryTooltip:ClearAllPoints()
        primaryTooltip:SetPoint("TOP", anchorFrame, "TOP", 0, 0)
        secondaryTooltip:SetPoint("TOP", anchorFrame, "TOP", 0, 0)

        if side == "left" then
            primaryTooltip:SetPoint("RIGHT", sideAnchorFrame, "LEFT", -gap, 0)
            secondaryTooltip:SetPoint("TOPRIGHT", primaryTooltip, "TOPLEFT", -gap, 0)
        else
            secondaryTooltip:SetPoint("LEFT", sideAnchorFrame, "RIGHT", gap, 0)
            primaryTooltip:SetPoint("TOPLEFT", secondaryTooltip, "TOPRIGHT", gap, 0)
        end
    else
        primaryTooltip:ClearAllPoints()
        primaryTooltip:SetPoint("TOP", anchorFrame, "TOP", 0, 0)
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
    local hasSetPointHooks = TryHookShoppingTooltipSetPoints()
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

    if hasComparisonHook then
        return true
    end

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
            end
        )
        hasCompareItemHook = compareItemHooked or compareItemReason == "already_hooked"
    end

    return hasSetPointHooks or hasComparisonHook or hasCompareItemHook
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
