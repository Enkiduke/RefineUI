----------------------------------------------------------------------------------------
-- Nameplates
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:RegisterModule("Nameplates")

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Nameplates:OnEnable()
    if self.EnableRuntime then
        self:EnableRuntime()
    end
end
