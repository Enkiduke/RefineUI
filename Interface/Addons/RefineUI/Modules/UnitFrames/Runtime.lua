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
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local ipairs = ipairs
local pairs = pairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = UnitFrames:GetPrivate()
local Runtime = Private.Runtime

local EVENT_KEY = {
    POWER = "UnitFrames:PowerType",
    PET_HEALTH = "UnitFrames:PetHealth",
    PET_UNIT = "UnitFrames:PetUnit",
    PET_UI = "UnitFrames:PetUI",
    BOSS_ENGAGE = "UnitFrames:BossEngage",
    REGEN_ENABLED = "UnitFrames:RegenEnabled",
    UI_SCALE = "UnitFrames:UIScaleChanged",
    DISPLAY_SIZE = "UnitFrames:DisplaySizeChanged",
}

local POWER_EVENT_UNITS = { "player", "vehicle", "target", "focus" }
for index = 1, Private.Constants.MAX_BOSS_FRAMES do
    POWER_EVENT_UNITS[#POWER_EVENT_UNITS + 1] = "boss" .. index
end

----------------------------------------------------------------------------------------
-- Shared Helpers
----------------------------------------------------------------------------------------
-- TargetFrameMixin:Update and UNIT_FACTION both run CheckFaction, so it tracks the
-- unit, reaction, and tap changes that decide the cached bar colors.
local function OnCheckFaction(frame)
    UnitFrames:ApplyDynamicStyle(frame)
end

-- CheckDead runs on every UNIT_HEALTH, so only a death or resurrection recolors.
local function OnCheckDead(frame)
    if UnitIsDeadOrGhost(frame.unit) ~= UnitFrames:GetFrameData(frame).isDead then
        UnitFrames:ApplyDynamicStyle(frame)
    end
end

local function RegisterBossFrameHooks(frame)
    if not frame or frame == PlayerFrame or frame == TargetFrame or frame == FocusFrame then
        return
    end

    if UnitFrames:GetState(frame, "BossHooksRegistered", false) then
        return
    end

    if frame.CheckFaction then
        RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "CheckFaction:Boss"), frame, "CheckFaction", OnCheckFaction)
        RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "CheckDead:Boss"), frame, "CheckDead", OnCheckDead)
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
    RefineUI:HookOnce("UnitFrames:PlayerFrame_UpdateStatus:RestPresentation", "PlayerFrame_UpdateStatus", function()
        if UnitFrames.UpdatePlayerRestPresentation then
            UnitFrames:UpdatePlayerRestPresentation(PlayerFrame)
        end
    end)

    if PetFrame then
        RefineUI:HookScriptOnce("UnitFrames:PetFrame:OnShow", PetFrame, "OnShow", function(selfFrame)
            UnitFrames:StylePetFrame(selfFrame)
        end)
        RefineUI:HookOnce("UnitFrames:PetFrame_Update", "PetFrame_Update", function()
            UnitFrames:StylePetFrame(PetFrame)
        end)
    end

    for _, frame in ipairs({ TargetFrame, FocusFrame }) do
        local frameName = frame:GetName()
        RefineUI:HookOnce("UnitFrames:" .. frameName .. ":CheckClassification", frame, "CheckClassification", function(selfFrame)
            UnitFrames:StyleFrame(selfFrame)
        end)
        RefineUI:HookOnce("UnitFrames:" .. frameName .. ":CheckFaction", frame, "CheckFaction", OnCheckFaction)
        RefineUI:HookOnce("UnitFrames:" .. frameName .. ":CheckDead", frame, "CheckDead", OnCheckDead)
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
        if unit == PlayerFrame.unit then
            UnitFrames:RefreshFrame(PlayerFrame)
        elseif unit == "target" then
            UnitFrames:RefreshFrame(TargetFrame)
        elseif unit == "focus" then
            UnitFrames:RefreshFrame(FocusFrame)
        elseif UnitFrames:IsBossUnit(unit) then
            UnitFrames:RefreshFrame(UnitFrames:GetBossFrameForUnit(unit))
        end
    end

    for _, unit in ipairs(POWER_EVENT_UNITS) do
        RefineUI:OnUnitEvents(unit, { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }, OnPowerEvent, EVENT_KEY.POWER .. ":" .. unit)
    end

    -- Health changes already reach the text through PetFrameHealthBar's OnValueChanged hook.
    RefineUI:OnUnitEvents("pet", { "UNIT_MAXHEALTH", "UNIT_CONNECTION" }, function()
        UnitFrames:UpdatePetFrameHealthText(PetFrame)
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

    -- Deferred a frame so RefineUI.mult is updated before pixel sizes are recomputed.
    local function ReapplyStylesAfterScaleChange()
        UnitFrames:ReapplyStyles()
    end
    local function OnScaleChanged()
        C_Timer.After(0, ReapplyStylesAfterScaleChange)
    end
    RefineUI:RegisterEventCallback("UI_SCALE_CHANGED", OnScaleChanged, EVENT_KEY.UI_SCALE)
    RefineUI:RegisterEventCallback("DISPLAY_SIZE_CHANGED", OnScaleChanged, EVENT_KEY.DISPLAY_SIZE)

    Runtime.runtimeEventsRegistered = true
end

function UnitFrames:EnableRuntime()
    self:ReapplyStyles()
    self:RegisterRuntimeHooks()
    self:RegisterRuntimeEvents()
end
