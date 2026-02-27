----------------------------------------------------------------------------------------
-- Tooltip
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:RegisterModule("Tooltip")
Tooltip.Private = Tooltip.Private or {}
Tooltip.ItemHandlers = Tooltip.ItemHandlers or {}

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Tooltip:OnInitialize()
    if not Config.Tooltip or not Config.Tooltip.Enable then
        return
    end

    if self.InitializeTooltipCore then
        self:InitializeTooltipCore()
    end
    if self.InitializeTooltipStyle then
        self:InitializeTooltipStyle()
    end
    if self.InitializeTooltipAnchor then
        self:InitializeTooltipAnchor()
    end
    if self.InitializeTooltipUnit then
        self:InitializeTooltipUnit()
    end

    if self.InitializeHyperlinkSupport then
        self:InitializeHyperlinkSupport()
    end
    if self.InitializeTooltipIcons then
        self:InitializeTooltipIcons()
    end
    if self.InitializeSpellID then
        self:InitializeSpellID()
    end
    if self.InitializeItemCountStorage then
        self:InitializeItemCountStorage()
    end
    if self.InitializeItemCount then
        self:InitializeItemCount()
    end
end
