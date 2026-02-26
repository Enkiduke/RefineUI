----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Conflict
-- Description: Detects conflicting click-cast systems and suspends safely.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_ClickBindings = C_ClickBindings
local Enum = Enum
local IsAddOnLoaded = IsAddOnLoaded
local ipairs = ipairs
local type = type

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local CONFLICT_WATCH_JOB_KEY = "ClickCasting:ConflictWatch"

local function HasCliqueLoaded()
    return IsAddOnLoaded and IsAddOnLoaded("Clique")
end

local function HasCustomBlizzardClickCastBindings()
    if not C_ClickBindings or not C_ClickBindings.GetProfileInfo then
        return false
    end

    local ok, profileInfo = pcall(C_ClickBindings.GetProfileInfo)
    if not ok or type(profileInfo) ~= "table" then
        return false
    end

    local clickBindingType = Enum and Enum.ClickBindingType
    local spellType = (clickBindingType and clickBindingType.Spell) or 1
    local macroType = (clickBindingType and clickBindingType.Macro) or 2
    local petActionType = (clickBindingType and clickBindingType.PetAction) or 4

    for _, bindingInfo in ipairs(profileInfo) do
        if type(bindingInfo) == "table" then
            local bindingType = bindingInfo.type
            if bindingType == spellType or bindingType == macroType or bindingType == petActionType then
                return true
            end
        end
    end

    return false
end

----------------------------------------------------------------------------------------
-- Conflict API
----------------------------------------------------------------------------------------
function ClickCasting:IsCliqueLoaded()
    return HasCliqueLoaded()
end

function ClickCasting:SetConflictWatchEnabled(enabled)
    if not RefineUI:IsUpdateJobRegistered(CONFLICT_WATCH_JOB_KEY) then
        RefineUI:RegisterUpdateJob(CONFLICT_WATCH_JOB_KEY, 1.5, function()
            local hasConflict = self:RefreshConflictState()
            if not hasConflict then
                self:RequestRebuild("conflict-cleared")
            end
        end, {
            enabled = false,
            safe = true,
            disableOnError = true,
        })
    end

    RefineUI:SetUpdateJobEnabled(CONFLICT_WATCH_JOB_KEY, enabled == true, true)
end

function ClickCasting:EvaluateConflictState()
    if HasCliqueLoaded() then
        return true, "Clique is loaded"
    end

    if HasCustomBlizzardClickCastBindings() then
        return true, "Blizzard Mouseover Casting has custom bindings"
    end

    return false, nil
end

function ClickCasting:RefreshConflictState()
    local hadConflict = self.hasConflict == true
    local hasConflict, reason = self:EvaluateConflictState()

    self.hasConflict = hasConflict
    self.suspendReason = reason
    self.isSuspended = hasConflict

    if hasConflict and not hadConflict then
        self:DisableSecureSystem("conflict")
        self:SetConflictWatchEnabled(true)
    elseif hadConflict and not hasConflict then
        self.pendingSecureApply = true
        self:SetConflictWatchEnabled(false)
    end

    if self.UpdateSpellbookUIVisibility then
        self:UpdateSpellbookUIVisibility()
    end

    if hadConflict ~= hasConflict and self.RefreshSpellbookPanel then
        self:RefreshSpellbookPanel()
    end

    return hasConflict, reason
end

function ClickCasting:GetSuspendReasonText()
    if self.hasConflict then
        return self.suspendReason or "Conflicting mouseover-cast system is active."
    end
    return nil
end
