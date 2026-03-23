----------------------------------------------------------------------------------------
-- Chat module bootstrap for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:RegisterModule("Chat")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_InstanceEncounter = C_InstanceEncounter

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:IsEncounterActive()
    return self._encounterActive == true
end

function Chat:ShouldSuspendOptionalEnhancements()
    return self:IsEncounterActive()
end

function Chat:HasRenderedMessageEnhancements()
    return self.ShouldUseMessagePipeline and self:ShouldUseMessagePipeline() == true
end

function Chat:RefreshEncounterGatedFeatures()
    if self.RefreshCopyButtons then
        self:RefreshCopyButtons()
    end
end

function Chat:SetEncounterActive(isActive)
    local encounterActive = isActive == true
    if self._encounterActive == encounterActive then
        return false
    end

    self._encounterActive = encounterActive
    self:RefreshEncounterGatedFeatures()
    return true
end

function Chat:SyncEncounterState()
    local encounterActive = false
    if C_InstanceEncounter and type(C_InstanceEncounter.IsEncounterInProgress) == "function" then
        encounterActive = C_InstanceEncounter.IsEncounterInProgress() == true
    end

    self:SetEncounterActive(encounterActive)
end
