----------------------------------------------------------------------------------------
-- EncounterTimeline Component: Lifecycle
-- Description: Module enable flow once Blizzard's timeline is loaded
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ADDON_LOADED_KEY = "EncounterTimeline:AddonLoaded"
local IconMask = Enum.EncounterEventIconmask
local Severity = Enum.EncounterEventSeverity

-- Covers each severity, the long/short/queued tracks, paused, deadly, dispel, and role indicators.
local TEST_EVENTS = {
    { spellID = 133, duration = 7, severity = Severity.Low, icons = IconMask.DpsRole },
    { spellID = 686, duration = 12, severity = Severity.High, icons = bit.bor(IconMask.DeadlyEffect, IconMask.MagicEffect, IconMask.HealerRole) },
    { spellID = 116, duration = 5, maxQueueDuration = 10, severity = Severity.Medium, icons = IconMask.TankRole },
    { spellID = 589, duration = 18, severity = Severity.Medium, paused = true, icons = IconMask.PoisonEffect },
    { spellID = 8921, duration = 40, severity = Severity.Low, icons = IconMask.CurseEffect },
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local testEventIDs = {}

----------------------------------------------------------------------------------------
-- Test Command
----------------------------------------------------------------------------------------
-- Cancels only RefineUI's own script events that are still live, so other addons' custom events stay.
local function ToggleTestEvents()
    local stopped = false
    local liveEvents = C_EncounterTimeline.GetEventList()
    for index = 1, #liveEvents do
        local eventID = liveEvents[index]
        if testEventIDs[eventID] then
            C_EncounterTimeline.CancelScriptEvent(eventID)
            stopped = true
        end
    end
    wipe(testEventIDs)

    if stopped then
        RefineUI:Print("Boss timeline test stopped.")
        return
    end

    for index = 1, #TEST_EVENTS do
        local request = TEST_EVENTS[index]
        request.iconFileID = request.iconFileID or C_Spell.GetSpellTexture(request.spellID)
        testEventIDs[C_EncounterTimeline.AddScriptEvent(request)] = true
    end
    RefineUI:Print("Boss timeline test started. Type /test again to stop.")
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
local function SetupTimeline()
    local config = EncounterTimeline:GetConfig()
    if config.SkinEnabled then
        EncounterTimeline:InstallSkin()
    end
    if config.BigIconEnable then
        EncounterTimeline:InstallBigIcon()
    end
    EncounterTimeline:RegisterEditModeSettings()
    RefineUI:RegisterChatCommand("test", ToggleTestEvents)
end

function EncounterTimeline:OnEnable()
    if C_AddOns.IsAddOnLoaded(self.BLIZZARD_ADDON_NAME) then
        SetupTimeline()
        return
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
        if addonName == EncounterTimeline.BLIZZARD_ADDON_NAME then
            RefineUI:OffEvent("ADDON_LOADED", ADDON_LOADED_KEY)
            SetupTimeline()
        end
    end, ADDON_LOADED_KEY)
end
