----------------------------------------------------------------------------------------
-- Tooltip Anchor
-- Description: Default tooltip anchoring with lightweight compare-tooltip spacing.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
local Private = Tooltip.Private

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local IsTooltip = Private.IsTooltip
local ReadSafeNumber = Private.ReadSafeNumber
local ReadSafeString = Private.ReadSafeString

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = GameTooltip
local UIParent = UIParent
local ITEM_TOOLTIP_TYPE = Enum.TooltipDataType.Item

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
-- Tooltip borders extend outward on both frames, so compensate to keep a visible gap.
local COMPARISON_GAP = 4 + Private.BORDER_INSET * 2
local SHOPPING_TOOLTIP_FRAME_NAMES = {
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
}
local LEFT_POINTS = { LEFT = true, TOPLEFT = true, BOTTOMLEFT = true }
local RIGHT_POINTS = { RIGHT = true, TOPRIGHT = true, BOTTOMRIGHT = true }

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
local TOOLTIP_MOVER_ANCHOR_POINTS = {
    TOPLEFT = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT" },
    TOPRIGHT = { point = "BOTTOMRIGHT", relativePoint = "TOPRIGHT" },
    BOTTOMLEFT = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT" },
    BOTTOMRIGHT = { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT" },
}

Tooltip.TOOLTIP_ANCHOR_MOVER_FRAME_NAME = TOOLTIP_ANCHOR_MOVER_FRAME_NAME
Tooltip.TOOLTIP_ANCHOR_MODE = TOOLTIP_ANCHOR_MODE
Tooltip.TOOLTIP_ANCHOR_PLACEMENT = TOOLTIP_ANCHOR_PLACEMENT

----------------------------------------------------------------------------------------
-- Comparison Tooltip Spacing
----------------------------------------------------------------------------------------
local applyingComparisonGap = false

-- Mirrors TooltipComparisonManager:AnchorShoppingTooltips side-anchor resolution.
local function IsHostSideAnchor(relativeTo, ownerTooltip)
    if relativeTo == ownerTooltip then
        return true
    end

    local manager = TooltipComparisonManager
    local sideAnchorFrame = manager.tooltip == ownerTooltip and manager.anchorFrame or ownerTooltip
    if sideAnchorFrame.IsEmbedded then
        sideAnchorFrame = sideAnchorFrame:GetParent():GetParent()
    end
    return relativeTo == sideAnchorFrame
end

local function ResolveComparisonGap(point, relativeTo, relativePoint, ownerTooltip)
    point = ReadSafeString(point)
    relativePoint = ReadSafeString(relativePoint)
    if not point or not relativePoint then
        return nil
    end

    if IsHostSideAnchor(relativeTo, ownerTooltip) then
        if LEFT_POINTS[point] and RIGHT_POINTS[relativePoint] then
            return COMPARISON_GAP
        end
        if RIGHT_POINTS[point] and LEFT_POINTS[relativePoint] then
            return -COMPARISON_GAP
        end
    end

    local shoppingTooltips = ownerTooltip.shoppingTooltips
    if not shoppingTooltips or (relativeTo ~= shoppingTooltips[1] and relativeTo ~= shoppingTooltips[2]) then
        return nil
    end
    if point == "TOPLEFT" and relativePoint == "TOPRIGHT" then
        return COMPARISON_GAP
    end
    if point == "TOPRIGHT" and relativePoint == "TOPLEFT" then
        return -COMPARISON_GAP
    end
end

local function OnShoppingTooltipSetPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    if applyingComparisonGap then
        return
    end

    local ownerTooltip = frame:GetOwner()
    if not IsTooltip(ownerTooltip)
        or not ownerTooltip.IsTooltipType
        or not ownerTooltip:IsTooltipType(ITEM_TOOLTIP_TYPE)
    then
        return
    end

    local gap = ResolveComparisonGap(point, relativeTo, relativePoint, ownerTooltip)
    if not gap or ReadSafeNumber(xOffset) == gap then
        return
    end

    applyingComparisonGap = true
    frame:SetPoint(point, relativeTo, relativePoint, gap, ReadSafeNumber(yOffset) or 0)
    applyingComparisonGap = false
end

local function HookComparisonTooltipSpacing()
    for index = 1, #SHOPPING_TOOLTIP_FRAME_NAMES do
        local frameName = SHOPPING_TOOLTIP_FRAME_NAMES[index]
        local shoppingTooltip = _G[frameName]
        if shoppingTooltip then
            RefineUI:HookOnce("Tooltip:ComparisonSpacing:SetPoint:" .. frameName, shoppingTooltip, "SetPoint", OnShoppingTooltipSetPoint)
        end
    end
end

----------------------------------------------------------------------------------------
-- Tooltip Anchor
----------------------------------------------------------------------------------------
local function NormalizeAnchorConfig()
    local anchorConfig = Config.Tooltip.Anchor
    if type(anchorConfig) ~= "table" then
        anchorConfig = {}
        Config.Tooltip.Anchor = anchorConfig
    end

    if anchorConfig.Mode ~= TOOLTIP_ANCHOR_MODE.MOVER then
        anchorConfig.Mode = TOOLTIP_ANCHOR_MODE.MOUSE
    end
    if not TOOLTIP_MOVER_ANCHOR_POINTS[anchorConfig.Placement] then
        anchorConfig.Placement = TOOLTIP_ANCHOR_PLACEMENT.TOPRIGHT
    end
    anchorConfig.OffsetX = tonumber(anchorConfig.OffsetX) or 0
    anchorConfig.OffsetY = tonumber(anchorConfig.OffsetY) or 4
    anchorConfig.ClampToScreen = anchorConfig.ClampToScreen ~= false
end

function Tooltip:GetTooltipAnchorConfig()
    return Config.Tooltip.Anchor
end

local function IsInsideWorldMap(frame)
    local worldMapFrame = _G.WorldMapFrame
    while frame and not frame:IsForbidden() do
        if frame == worldMapFrame then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end

local function ApplyMouseAnchor(tooltipFrame, parent)
    if parent ~= UIParent then
        tooltipFrame:SetOwner(parent, "ANCHOR_NONE")
        tooltipFrame:ClearAllPoints()
        tooltipFrame:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 4)
    else
        tooltipFrame:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", TOOLTIP_MOUSE_ANCHOR_X, TOOLTIP_MOUSE_ANCHOR_Y)
    end
end

local function ApplyMoverAnchor(tooltipFrame, parent, anchorConfig)
    local mover = Tooltip.tooltipAnchorMover
    if not mover then
        tooltipFrame:SetClampedToScreen(false)
        ApplyMouseAnchor(tooltipFrame, parent)
        return
    end

    local placement = TOOLTIP_MOVER_ANCHOR_POINTS[anchorConfig.Placement]
    tooltipFrame:SetClampedToScreen(anchorConfig.ClampToScreen)
    tooltipFrame:ClearAllPoints()
    tooltipFrame:SetPoint(placement.point, mover, placement.relativePoint, anchorConfig.OffsetX, anchorConfig.OffsetY)
end

local function OnSetDefaultAnchor(tooltipFrame, parent)
    if not IsTooltip(tooltipFrame) then
        return
    end

    parent = parent or UIParent
    local isEligibleParent = not parent:IsForbidden() and not IsInsideWorldMap(parent)
    local anchorConfig = Config.Tooltip.Anchor

    if anchorConfig.Mode ~= TOOLTIP_ANCHOR_MODE.MOVER then
        if isEligibleParent then
            ApplyMouseAnchor(tooltipFrame, parent)
        end
        return
    end

    if tooltipFrame ~= GameTooltip or not isEligibleParent then
        tooltipFrame:SetClampedToScreen(false)
        return
    end

    ApplyMoverAnchor(tooltipFrame, parent, anchorConfig)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipAnchor()
    NormalizeAnchorConfig()
    RefineUI:HookOnce("Tooltip:GameTooltip_SetDefaultAnchor", "GameTooltip_SetDefaultAnchor", OnSetDefaultAnchor)
    HookComparisonTooltipSpacing()
end
