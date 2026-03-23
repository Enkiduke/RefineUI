----------------------------------------------------------------------------------------
-- Tooltip Anchor
-- Description: Default tooltip anchoring with lightweight compare-tooltip spacing.
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

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local Enum = Enum
local select = select
local type = type
local pcall = pcall
local tonumber = tonumber
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_COMPARISON_ADDON_LOADED_KEY = "Tooltip:ComparisonSpacing:OnAddonLoaded"
local TOOLTIP_COMPARISON_VISIBLE_GAP = 4
local TOOLTIP_COMPARISON_MANAGER_HOOK_KEY = "Tooltip:ComparisonSpacing:AnchorShoppingTooltips"
local TOOLTIP_COMPARISON_HOST_ONHIDE_HOOK_KEY_PREFIX = "Tooltip:ComparisonSpacing:OnHide:"
local TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY = "Tooltip:GameTooltip_SetDefaultAnchor"
local TOOLTIP_COMPARISON_SETPOINT_HOOK_KEY_PREFIX = "Tooltip:ComparisonSpacing:SetPoint:"
local TOOLTIP_COMPARISON_HOST_FRAME_NAMES = {
    "GameTooltip",
    "ItemRefTooltip",
    "GameTooltipTooltip",
    "ItemRefTooltipTooltip",
}
local SHOPPING_TOOLTIP_FRAME_NAMES = {
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
}
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType
local TOOLTIP_ANCHOR_MOVER_FRAME_NAME = "RefineUI_TooltipAnchorMover"
local TOOLTIP_ANCHOR_MODE = {
    MOUSE = "MOUSE",
    MOVER = "MOVER",
}
local TOOLTIP_ANCHOR_PLACEMENT = {
    TOPLEFT = "TOPLEFT",
    TOPRIGHT = "TOPRIGHT",
    BOTTOMLEFT = "BOTTOMLEFT",
    BOTTOMRIGHT = "BOTTOMRIGHT",
}
local TOOLTIP_MOUSE_ANCHOR_X = 10
local TOOLTIP_MOUSE_ANCHOR_Y = 10
local TOOLTIP_DEFAULT_ANCHOR_CONFIG = {
    Mode = TOOLTIP_ANCHOR_MODE.MOUSE,
    Placement = TOOLTIP_ANCHOR_PLACEMENT.TOPRIGHT,
    OffsetX = 0,
    OffsetY = 4,
    ClampToScreen = true,
}
local TOOLTIP_MOVER_ANCHOR_POINTS = {
    [TOOLTIP_ANCHOR_PLACEMENT.TOPLEFT] = {
        point = "BOTTOMLEFT",
        relativePoint = "TOPLEFT",
    },
    [TOOLTIP_ANCHOR_PLACEMENT.TOPRIGHT] = {
        point = "BOTTOMRIGHT",
        relativePoint = "TOPRIGHT",
    },
    [TOOLTIP_ANCHOR_PLACEMENT.BOTTOMLEFT] = {
        point = "TOPLEFT",
        relativePoint = "BOTTOMLEFT",
    },
    [TOOLTIP_ANCHOR_PLACEMENT.BOTTOMRIGHT] = {
        point = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
    },
}

Tooltip.TOOLTIP_ANCHOR_MOVER_FRAME_NAME = TOOLTIP_ANCHOR_MOVER_FRAME_NAME
Tooltip.TOOLTIP_ANCHOR_MODE = TOOLTIP_ANCHOR_MODE
Tooltip.TOOLTIP_ANCHOR_PLACEMENT = TOOLTIP_ANCHOR_PLACEMENT

----------------------------------------------------------------------------------------
-- Comparison Tooltip Spacing
----------------------------------------------------------------------------------------
local applyingComparisonGapByFrame = setmetatable({}, { __mode = "k" })
local comparisonAnchorStateByTooltip = setmetatable({}, { __mode = "k" })
local comparisonHostEligibilityByTooltip = setmetatable({}, { __mode = "k" })
local comparisonSpacingRetryRegistered = false

local function IsDirectItemComparisonHost(tooltip)
    if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return false
    end

    local cachedEligibility = comparisonHostEligibilityByTooltip[tooltip]
    if cachedEligibility ~= nil then
        return cachedEligibility == true
    end

    if not TOOLTIP_DATA_TYPE or not TOOLTIP_DATA_TYPE.Item then
        comparisonHostEligibilityByTooltip[tooltip] = true
        return true
    end

    local okPrimaryData, primaryData = Tooltip:SafeObjectMethodCall(tooltip, "GetPrimaryTooltipData")
    if not okPrimaryData then
        comparisonHostEligibilityByTooltip[tooltip] = false
        return false
    end

    local isItemTooltip = Tooltip:GetTooltipDataType(primaryData) == TOOLTIP_DATA_TYPE.Item
    comparisonHostEligibilityByTooltip[tooltip] = isItemTooltip == true
    return isItemTooltip == true
end

local function ResolveComparisonSideAnchorFrame(anchorFrame)
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

    if not Tooltip:CanAccessObjectSafe(sideAnchorFrame) or Tooltip:IsForbiddenFrameSafe(sideAnchorFrame) then
        return anchorFrame
    end

    return sideAnchorFrame
end

local function CacheComparisonAnchorState(manager)
    if type(manager) ~= "table" or not Tooltip:CanAccessObjectSafe(manager) then
        return nil
    end

    local tooltip, okTooltip = Tooltip:SafeGetField(manager, "tooltip")
    if not okTooltip or not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return nil
    end

    local anchorFrame = select(1, Tooltip:SafeGetField(manager, "anchorFrame"))
    if not Tooltip:CanAccessObjectSafe(anchorFrame) or Tooltip:IsForbiddenFrameSafe(anchorFrame) then
        anchorFrame = tooltip
    end

    local state = comparisonAnchorStateByTooltip[tooltip]
    if type(state) ~= "table" then
        state = {}
        comparisonAnchorStateByTooltip[tooltip] = state
    end

    state.anchorFrame = anchorFrame
    state.sideAnchorFrame = ResolveComparisonSideAnchorFrame(anchorFrame)
    return state
end

local function GetComparisonAnchorState(tooltip)
    if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return nil
    end

    local state = comparisonAnchorStateByTooltip[tooltip]
    if type(state) == "table" and state.anchorFrame and state.sideAnchorFrame then
        return state
    end

    local comparisonManager = _G.TooltipComparisonManager
    if type(comparisonManager) ~= "table" or not Tooltip:CanAccessObjectSafe(comparisonManager) then
        return nil
    end

    local managerTooltip, okManagerTooltip = Tooltip:SafeGetField(comparisonManager, "tooltip")
    if not okManagerTooltip or managerTooltip ~= tooltip then
        return nil
    end

    return CacheComparisonAnchorState(comparisonManager)
end

local function ResolveEmbeddedParentTooltip(ownerTooltip)
    local okOwner, embeddedHost = Tooltip:SafeObjectMethodCall(ownerTooltip, "GetOwner")
    if not okOwner or not Tooltip:CanAccessObjectSafe(embeddedHost) or Tooltip:IsForbiddenFrameSafe(embeddedHost) then
        return nil, nil
    end

    local okParent, parentTooltip = Tooltip:SafeObjectMethodCall(embeddedHost, "GetParent")
    if not okParent or not Tooltip:CanAccessObjectSafe(parentTooltip) or Tooltip:IsForbiddenFrameSafe(parentTooltip) then
        return embeddedHost, nil
    end

    return embeddedHost, parentTooltip
end

local function IsComparisonHostSideAnchor(relativeTo, ownerTooltip)
    if relativeTo == ownerTooltip then
        return true
    end

    local anchorState = GetComparisonAnchorState(ownerTooltip)
    if anchorState and relativeTo == anchorState.sideAnchorFrame then
        return true
    end

    local embeddedHost, parentTooltip = ResolveEmbeddedParentTooltip(ownerTooltip)
    if relativeTo == embeddedHost then
        return true
    end

    if not parentTooltip then
        return false
    end

    -- World-quest reward compares can anchor the first shopping tooltip to the parent
    -- quest tooltip or its BackdropFrame instead of the embedded item tooltip host.
    if relativeTo == parentTooltip then
        return true
    end

    local backdropFrame = select(1, Tooltip:SafeGetField(parentTooltip, "BackdropFrame"))
    return relativeTo == backdropFrame
end

local function ResetComparisonAnchorState(tooltip)
    if tooltip then
        comparisonAnchorStateByTooltip[tooltip] = nil
        comparisonHostEligibilityByTooltip[tooltip] = nil
    end
end

local function GetComparisonAnchorGap()
    local borderInset = select(1, Tooltip:GetTooltipBorderParams()) or 0
    if type(borderInset) ~= "number" or borderInset < 0 then
        borderInset = 0
    end

    -- Tooltip borders extend outward on both frames, so compensate here to preserve
    -- an actual visible gap between compare tooltips.
    return TOOLTIP_COMPARISON_VISIBLE_GAP + (borderInset * 2)
end

local function ResolveComparisonGapForPoint(point, relativeTo, relativePoint, xOffset, ownerTooltip, shoppingTooltips)
    local safePoint = Tooltip:ReadSafeString(point)
    local safeRelativePoint = Tooltip:ReadSafeString(relativePoint)
    local safeXOffset = Tooltip:ReadSafeNumber(xOffset)
    local gap = GetComparisonAnchorGap()
    local isHostSideAnchor = IsComparisonHostSideAnchor(relativeTo, ownerTooltip)

    if type(safeXOffset) ~= "number" then
        safeXOffset = 0
    end

    if isHostSideAnchor then
        if (safePoint == "LEFT" or safePoint == "TOPLEFT" or safePoint == "BOTTOMLEFT")
            and (safeRelativePoint == "RIGHT" or safeRelativePoint == "TOPRIGHT" or safeRelativePoint == "BOTTOMRIGHT")
        then
            return gap
        end
        if (safePoint == "RIGHT" or safePoint == "TOPRIGHT" or safePoint == "BOTTOMRIGHT")
            and (safeRelativePoint == "LEFT" or safeRelativePoint == "TOPLEFT" or safeRelativePoint == "BOTTOMLEFT")
        then
            return -gap
        end
    end

    if type(shoppingTooltips) ~= "table" then
        return nil
    end

    local primaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 1))
    local secondaryTooltip = select(1, Tooltip:SafeGetField(shoppingTooltips, 2))
    local isComparisonTooltip = relativeTo == primaryTooltip or relativeTo == secondaryTooltip
    if not isComparisonTooltip then
        return nil
    end

    if safePoint == "TOPLEFT" and safeRelativePoint == "TOPRIGHT" then
        return gap
    end
    if safePoint == "TOPRIGHT" and safeRelativePoint == "TOPLEFT" then
        return -gap
    end

    return nil
end

local function TryHookShoppingTooltipSpacing()
    local hookedCount = 0

    for index = 1, #SHOPPING_TOOLTIP_FRAME_NAMES do
        local frameName = SHOPPING_TOOLTIP_FRAME_NAMES[index]
        local shoppingTooltip = _G[frameName]
        if Tooltip:IsGameTooltipFrameSafe(shoppingTooltip) then
            local hookKey = TOOLTIP_COMPARISON_SETPOINT_HOOK_KEY_PREFIX .. frameName
            local ok, reason = RefineUI:HookOnce(hookKey, shoppingTooltip, "SetPoint", function(frame, point, relativeTo, relativePoint, xOffset, yOffset)
                if applyingComparisonGapByFrame[frame] then
                    return
                end

                local okOwner, ownerTooltip = Tooltip:SafeObjectMethodCall(frame, "GetOwner")
                if not okOwner or not IsDirectItemComparisonHost(ownerTooltip) then
                    return
                end

                local shoppingTooltips = select(1, Tooltip:SafeGetField(ownerTooltip, "shoppingTooltips"))
                local adjustedXOffset = ResolveComparisonGapForPoint(
                    point,
                    relativeTo,
                    relativePoint,
                    xOffset,
                    ownerTooltip,
                    shoppingTooltips
                )

                if type(adjustedXOffset) ~= "number" then
                    return
                end

                local safeXOffset = Tooltip:ReadSafeNumber(xOffset)
                if type(safeXOffset) == "number" and safeXOffset == adjustedXOffset then
                    return
                end

                local safeYOffset = Tooltip:ReadSafeNumber(yOffset)
                if type(safeYOffset) ~= "number" then
                    safeYOffset = 0
                end

                applyingComparisonGapByFrame[frame] = true
                Tooltip:SafeObjectMethodCall(frame, "SetPoint", point, relativeTo, relativePoint, adjustedXOffset, safeYOffset)
                applyingComparisonGapByFrame[frame] = nil
            end)

            if ok or reason == "already_hooked" then
                hookedCount = hookedCount + 1
            end
        end
    end

    return hookedCount == #SHOPPING_TOOLTIP_FRAME_NAMES
end

local function TryHookComparisonTooltipStateReset()
    local hookedCount = 0

    for index = 1, #TOOLTIP_COMPARISON_HOST_FRAME_NAMES do
        local frameName = TOOLTIP_COMPARISON_HOST_FRAME_NAMES[index]
        local tooltipFrame = _G[frameName]
        if Tooltip:IsGameTooltipFrameSafe(tooltipFrame) then
            local hostOnHideHookKey = TOOLTIP_COMPARISON_HOST_ONHIDE_HOOK_KEY_PREFIX .. frameName
            local okOnHide, onHideReason = RefineUI:HookScriptOnce(hostOnHideHookKey, tooltipFrame, "OnHide", function(frame)
                ResetComparisonAnchorState(frame)
            end)

            if okOnHide or onHideReason == "already_hooked" then
                hookedCount = hookedCount + 1
            end
        end
    end

    return hookedCount == #TOOLTIP_COMPARISON_HOST_FRAME_NAMES
end

function Tooltip:TryHookComparisonTooltipSpacing()
    local hasManagerHook = false
    local comparisonManager = _G.TooltipComparisonManager
    if type(comparisonManager) == "table" and Tooltip:CanAccessObjectSafe(comparisonManager) then
        local anchorShoppingTooltips = select(1, Tooltip:SafeGetField(comparisonManager, "AnchorShoppingTooltips"))
        if type(anchorShoppingTooltips) == "function" then
            local ok, reason = RefineUI:HookOnce(TOOLTIP_COMPARISON_MANAGER_HOOK_KEY, comparisonManager, "AnchorShoppingTooltips", function(manager)
                CacheComparisonAnchorState(manager)
            end)
            hasManagerHook = ok or reason == "already_hooked"
        end
    end

    local hasSpacingHooks = TryHookShoppingTooltipSpacing()
    local hasStateResetHooks = TryHookComparisonTooltipStateReset()
    return hasManagerHook and hasSpacingHooks and hasStateResetHooks
end

----------------------------------------------------------------------------------------
-- Tooltip Anchor
----------------------------------------------------------------------------------------
local function EnsureTooltipAnchorConfig()
    Config.Tooltip = Config.Tooltip or {}
    if type(Config.Tooltip.Anchor) ~= "table" then
        Config.Tooltip.Anchor = {}
    end
    return Config.Tooltip.Anchor
end

local function IsWorldMapAnchorParent(parent)
    local worldMapFrame = _G.WorldMapFrame
    if not parent or not worldMapFrame then
        return false
    end

    local check = parent
    while check do
        if check == worldMapFrame then
            return true
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

    return false
end

local function ResetTooltipClamp(tooltipFrame)
    if tooltipFrame and type(tooltipFrame.SetClampedToScreen) == "function" then
        tooltipFrame:SetClampedToScreen(false)
    end
end

local function ApplyFixedTooltipAnchor(targetFrame, anchorFrame, anchorConfig)
    if not targetFrame or not anchorFrame then
        return false
    end

    local placementData = TOOLTIP_MOVER_ANCHOR_POINTS[anchorConfig.Placement] or TOOLTIP_MOVER_ANCHOR_POINTS[TOOLTIP_DEFAULT_ANCHOR_CONFIG.Placement]
    if type(targetFrame.SetClampedToScreen) == "function" then
        targetFrame:SetClampedToScreen(anchorConfig.ClampToScreen == true)
    end

    targetFrame:ClearAllPoints()
    targetFrame:SetPoint(
        placementData.point,
        anchorFrame,
        placementData.relativePoint,
        anchorConfig.OffsetX,
        anchorConfig.OffsetY
    )
    return true
end

function Tooltip:GetTooltipAnchorConfig()
    local anchorConfig = EnsureTooltipAnchorConfig()

    local mode = Tooltip:ReadSafeString(anchorConfig.Mode)
    if mode ~= TOOLTIP_ANCHOR_MODE.MOUSE and mode ~= TOOLTIP_ANCHOR_MODE.MOVER then
        mode = TOOLTIP_DEFAULT_ANCHOR_CONFIG.Mode
    end

    local placement = Tooltip:ReadSafeString(anchorConfig.Placement)
    if not TOOLTIP_MOVER_ANCHOR_POINTS[placement] then
        placement = TOOLTIP_DEFAULT_ANCHOR_CONFIG.Placement
    end

    local offsetX = tonumber(anchorConfig.OffsetX)
    if type(offsetX) ~= "number" then
        offsetX = TOOLTIP_DEFAULT_ANCHOR_CONFIG.OffsetX
    end

    local offsetY = tonumber(anchorConfig.OffsetY)
    if type(offsetY) ~= "number" then
        offsetY = TOOLTIP_DEFAULT_ANCHOR_CONFIG.OffsetY
    end

    local clampToScreen = anchorConfig.ClampToScreen ~= false

    anchorConfig.Mode = mode
    anchorConfig.Placement = placement
    anchorConfig.OffsetX = offsetX
    anchorConfig.OffsetY = offsetY
    anchorConfig.ClampToScreen = clampToScreen

    return {
        Mode = mode,
        Placement = placement,
        OffsetX = offsetX,
        OffsetY = offsetY,
        ClampToScreen = clampToScreen,
    }
end

function Tooltip:IsTooltipMoverModeEnabled()
    return self:GetTooltipAnchorConfig().Mode == TOOLTIP_ANCHOR_MODE.MOVER
end

function Tooltip:GetTooltipAnchorMover()
    local mover = _G[TOOLTIP_ANCHOR_MOVER_FRAME_NAME]
    if mover and type(mover.SetPoint) == "function" then
        return mover
    end
    return nil
end

function Tooltip:ApplyTooltipFixedAnchor(targetFrame, anchorFrame, anchorConfig)
    local resolvedConfig = anchorConfig or self:GetTooltipAnchorConfig()
    return ApplyFixedTooltipAnchor(targetFrame, anchorFrame, resolvedConfig)
end

function Tooltip:ApplyMouseTooltipAnchor(tooltipFrame, parent)
    if not tooltipFrame then
        return false
    end

    local anchorParent = parent or _G.UIParent
    ResetTooltipClamp(tooltipFrame)

    if anchorParent ~= _G.UIParent then
        tooltipFrame:SetOwner(anchorParent, "ANCHOR_NONE")
        tooltipFrame:ClearAllPoints()
        tooltipFrame:SetPoint("BOTTOMRIGHT", anchorParent, "TOPRIGHT", 0, 4)
    else
        tooltipFrame:SetOwner(anchorParent, "ANCHOR_CURSOR_RIGHT", TOOLTIP_MOUSE_ANCHOR_X, TOOLTIP_MOUSE_ANCHOR_Y)
    end

    return true
end

local function ApplyLegacyMouseTooltipAnchorUpdate(tt, parent)
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
        tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", TOOLTIP_MOUSE_ANCHOR_X, TOOLTIP_MOUSE_ANCHOR_Y)
    end
end

function Tooltip:IsTooltipAnchorEligible(tooltipFrame, parent)
    if tooltipFrame ~= _G.GameTooltip then
        return false
    end

    if not Tooltip:IsGameTooltipFrameSafe(tooltipFrame) or Tooltip:IsEmbeddedTooltipFrame(tooltipFrame) then
        return false
    end

    if parent and (not Tooltip:CanAccessObjectSafe(parent) or Tooltip:IsForbiddenFrameSafe(parent)) then
        return false
    end

    return not IsWorldMapAnchorParent(parent)
end

function Tooltip:ApplyMoverTooltipAnchor(tooltipFrame, parent)
    if not tooltipFrame then
        return false
    end

    local mover = self:GetTooltipAnchorMover()
    if not mover then
        return self:ApplyMouseTooltipAnchor(tooltipFrame, parent)
    end

    return ApplyFixedTooltipAnchor(tooltipFrame, mover, self:GetTooltipAnchorConfig())
end

function Tooltip.TooltipAnchorUpdate(tt, parent)
    if not tt or not Tooltip:IsGameTooltipFrameSafe(tt) then
        return
    end

    if not Tooltip:IsTooltipMoverModeEnabled() then
        ApplyLegacyMouseTooltipAnchorUpdate(tt, parent)
        return
    end

    local anchorParent = parent or _G.UIParent
    if not Tooltip:IsTooltipAnchorEligible(tt, anchorParent) then
        ResetTooltipClamp(tt)
        return
    end

    Tooltip:ApplyMoverTooltipAnchor(tt, anchorParent)
end

function Tooltip:SetTooltipAnchor()
    RefineUI:HookOnce(TOOLTIP_DEFAULT_ANCHOR_HOOK_KEY, "GameTooltip_SetDefaultAnchor", Tooltip.TooltipAnchorUpdate)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipAnchor()
    Tooltip:SetTooltipAnchor()
    local hooksReady = Tooltip:TryHookComparisonTooltipSpacing()
    if hooksReady then
        comparisonSpacingRetryRegistered = false
        return
    end

    if comparisonSpacingRetryRegistered then
        return
    end

    comparisonSpacingRetryRegistered = true
    RefineUI:RegisterEventCallback("ADDON_LOADED", function()
        if Tooltip:TryHookComparisonTooltipSpacing() then
            RefineUI:OffEvent("ADDON_LOADED", TOOLTIP_COMPARISON_ADDON_LOADED_KEY)
            comparisonSpacingRetryRegistered = false
        end
    end, TOOLTIP_COMPARISON_ADDON_LOADED_KEY)
end
