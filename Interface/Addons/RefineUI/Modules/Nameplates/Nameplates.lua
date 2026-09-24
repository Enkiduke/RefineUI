----------------------------------------------------------------------------------------
-- Nameplates
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:RegisterModule("Nameplates", "Nameplates")

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Nameplates:OnEnable()
    self:RegisterNpcTitleEvents()
    self:RegisterPortraitEvents()

    if self.EnableRuntime then
        self:EnableRuntime()
    end
end
