----------------------------------------------------------------------------------------
-- UnitFrames Component: Runtime
-- Description: Event wiring, hook registration, and startup orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local pairs = pairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = UnitFrames:GetPrivate()
local Runtime = Private.Runtime

local EVENT_KEY = {
    POWER_MAX = "UnitFrames:PowerType:Max",
    POWER_DISPLAY = "UnitFrames:PowerType:Display",
    PET_HEALTH = "UnitFrames:PetHealth",
    PET_UNIT = "UnitFrames:PetUnit",
    PET_UI = "UnitFrames:PetUI",
    BOSS_ENGAGE = "UnitFrames:BossEngage",
    REGEN_ENABLED = "UnitFrames:RegenEnabled",
}

----------------------------------------------------------------------------------------
-- Shared Helpers
----------------------------------------------------------------------------------------
local function RegisterBossFrameHooks(frame)
    if not frame or frame == PlayerFrame or frame == TargetFrame or frame == FocusFrame then
        return
    end

    if UnitFrames:GetState(frame, "BossHooksRegistered", false) then
        return
    end

    if frame.CheckClassification then
        RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "CheckClassification:Boss"), frame, "CheckClassification", function(selfFrame)
            UnitFrames:StyleFrame(selfFrame)
        end)
    end
    RefineUI:HookScriptOnce(UnitFrames:BuildHookKey(frame, "OnShow:Boss"), frame, "OnShow", function(selfFrame)
        UnitFrames:StyleFrame(selfFrame)
    end)

    UnitFrames:SetState(frame, "BossHooksRegistered", true)
end

----------------------------------------------------------------------------------------
-- Public Runtime API
----------------------------------------------------------------------------------------
function UnitFrames:FlushQueuedStaticStyles()
    if InCombatLockdown() then
        return
    end

    for frame in pairs(Private.PendingStaticStyleFrames) do
        Private.PendingStaticStyleFrames[frame] = nil
        self:StyleFrame(frame)
    end
end

function UnitFrames:RefreshFrame(frame)
    if not frame then
        return
    end

    self:ApplyDynamicStyle(frame)
    if InCombatLockdown() then
        self:QueueStaticStyle(frame)
        return
    end

    self:StyleFrame(frame)
end

function UnitFrames:ReapplyStyles()
    if InCombatLockdown() then
        return
    end

    local frames = self:GetManagedFrames()
    for _, frame in ipairs(frames) do
        if frame then
            RegisterBossFrameHooks(frame)
            self:StyleFrame(frame)
        end
    end

    self:FlushQueuedStaticStyles()
end

function UnitFrames:RegisterRuntimeHooks()
    if Runtime.runtimeHooksRegistered == true then
        return
    end

    self:ReapplyStyles()

    RefineUI:HookOnce("UnitFrames:PlayerFrame_ToPlayerArt", "PlayerFrame_ToPlayerArt", function()
        UnitFrames:StyleFrame(PlayerFrame)
    end)
    RefineUI:HookOnce("UnitFrames:PlayerFrame_ToVehicleArt", "PlayerFrame_ToVehicleArt", function()
        UnitFrames:StyleFrame(PlayerFrame)
    end)

    if PetFrame then
        RefineUI:HookScriptOnce("UnitFrames:PetFrame:OnShow", PetFrame, "OnShow", function(selfFrame)
            UnitFrames:StylePetFrame(selfFrame)
        end)
        RefineUI:HookOnce("UnitFrames:PetFrame_Update", "PetFrame_Update", function()
            UnitFrames:StylePetFrame(PetFrame)
        end)
    end

    if TargetFrame and TargetFrame.CheckClassification then
        RefineUI:HookOnce("UnitFrames:TargetFrame:CheckClassification", TargetFrame, "CheckClassification", function()
            UnitFrames:StyleFrame(TargetFrame)
        end)
    end
    if FocusFrame and FocusFrame.CheckClassification then
        RefineUI:HookOnce("UnitFrames:FocusFrame:CheckClassification", FocusFrame, "CheckClassification", function()
            UnitFrames:StyleFrame(FocusFrame)
        end)
    end

    for _, frame in ipairs(self:GetManagedFrames()) do
        RegisterBossFrameHooks(frame)
    end

    if EditModeManagerFrame then
        RefineUI:HookOnce("UnitFrames:EditModeManagerFrame:EnterEditMode", EditModeManagerFrame, "EnterEditMode", function()
            UnitFrames:ReapplyStyles()
            if UnitFrames.HookTargetFocusAuraSettingsDialog then
                UnitFrames:HookTargetFocusAuraSettingsDialog()
            end
        end)
        RefineUI:HookOnce("UnitFrames:EditModeManagerFrame:ExitEditMode", EditModeManagerFrame, "ExitEditMode", function()
            UnitFrames:ReapplyStyles()
        end)
    end

    if self.HookTargetFocusAuraSettingsDialog then
        self:HookTargetFocusAuraSettingsDialog()
    end

    Runtime.runtimeHooksRegistered = true
end

function UnitFrames:RegisterRuntimeEvents()
    if Runtime.runtimeEventsRegistered == true then
        return
    end

    local function OnPowerEvent(_, unit)
        if unit == "player" then
            UnitFrames:RefreshFrame(PlayerFrame)
        elseif unit == "target" then
            UnitFrames:RefreshFrame(TargetFrame)
        elseif unit == "focus" then
            UnitFrames:RefreshFrame(FocusFrame)
        elseif UnitFrames:IsBossUnit(unit) then
            UnitFrames:RefreshFrame(UnitFrames:GetBossFrameForUnit(unit))
        end
    end

    RefineUI:RegisterEventCallback("UNIT_MAXPOWER", OnPowerEvent, EVENT_KEY.POWER_MAX)
    RefineUI:RegisterEventCallback("UNIT_DISPLAYPOWER", OnPowerEvent, EVENT_KEY.POWER_DISPLAY)

    RefineUI:OnEvents({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }, function(_, unit)
        if unit == "pet" then
            UnitFrames:ApplyPetFrameDynamicStyle(PetFrame)
        end
    end, EVENT_KEY.PET_HEALTH)

    RefineUI:RegisterEventCallback("UNIT_PET", function(_, ownerUnit)
        if ownerUnit == "player" then
            UnitFrames:RefreshFrame(PetFrame)
        end
    end, EVENT_KEY.PET_UNIT)

    RefineUI:RegisterEventCallback("PET_UI_UPDATE", function()
        UnitFrames:RefreshFrame(PetFrame)
    end, EVENT_KEY.PET_UI)

    RefineUI:RegisterEventCallback("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
        for _, frame in ipairs(UnitFrames:GetManagedFrames()) do
            if frame and frame.unit and UnitFrames:IsBossUnit(frame.unit) then
                RegisterBossFrameHooks(frame)
                UnitFrames:RefreshFrame(frame)
            end
        end
    end, EVENT_KEY.BOSS_ENGAGE)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        UnitFrames:FlushQueuedStaticStyles()
    end, EVENT_KEY.REGEN_ENABLED)

    Runtime.runtimeEventsRegistered = true
end

function UnitFrames:EnableRuntime()
    self:ReapplyStyles()
    self:RegisterRuntimeHooks()
    self:RegisterRuntimeEvents()
end
