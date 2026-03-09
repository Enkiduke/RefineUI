----------------------------------------------------------------------------------------
-- UnitFrames
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:RegisterModule("UnitFrames")

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function UnitFrames:OnInitialize()
end

function UnitFrames:OnEnable()
    if self.EnableRuntime then
        self:EnableRuntime()
    end

    if self.InitPartyHooks then
        self:InitPartyHooks()
    end
end
