----------------------------------------------------------------------------------------
-- UnitFrames Class Resources
-- Description: Namespace/bootstrap for class resource components.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Private = UnitFrames:GetPrivate()
Private.ClassResources = Private.ClassResources or {}

local CR = Private.ClassResources
CR.Resources = CR.Resources or UnitFrames.ClassResources or {}
UnitFrames.ClassResources = CR.Resources
