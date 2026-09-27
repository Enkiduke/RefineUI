----------------------------------------------------------------------------------------
-- Tooltip
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:RegisterModule("Tooltip", "Tooltip")
Tooltip.Private = {}

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Tooltip:OnInitialize()
    if not RefineUI.Config.Tooltip.Enable then
        return
    end

    -- Style registers its post-calls first so borders and fonts apply before feature lines.
    self:InitializeTooltipStyle()
    self:InitializeTooltipAnchor()
    self:InitializeTooltipEditMode()
    self:InitializeTooltipUnit()
    self:InitializeHyperlinkSupport()

    -- Item handler order sets line order: icon, counts, token rows, then the ID line.
    self:InitializeTooltipIcons()
    self:InitializeItemCountStorage()
    self:InitializeItemCount()
    self:InitializeItemTokens()
    self:InitializeSpellID()
end
