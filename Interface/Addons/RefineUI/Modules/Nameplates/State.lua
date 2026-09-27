----------------------------------------------------------------------------------------
-- Nameplates Component: State
-- Description: Shared constants, registries, and runtime state for Nameplates components.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pcall = pcall
local setmetatable = setmetatable

local C_NamePlate = C_NamePlate

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local Private = Nameplates.Private
local Util = Private.Util

Private.Constants = {
    NAMEPLATE_THREAT_DISPLAY_CVAR = "nameplateThreatDisplay",
    THREAT_STATUS_LOW = 0,
    THREAT_STATUS_TRANSITION_LOW = 1,
    THREAT_STATUS_TRANSITION_HIGH = 2,
    THREAT_STATUS_AGGRO = 3,
    THREAT_LEAD_STATUS_NONE = 0,
    THREAT_LEAD_STATUS_YELLOW = 1,
    THREAT_LEAD_STATUS_ORANGE = 2,
    THREAT_LEAD_STATUS_RED = 3,
    DEFAULT_THREAT_SAFE_COLOR = { 0.2, 0.8, 0.2 },
    DEFAULT_THREAT_TRANSITION_COLOR = { 1, 1, 0 },
    DEFAULT_THREAT_WARNING_COLOR = { 1, 0, 0 },
    NPC_TITLE_FONT_SIZE = 9,
    NPC_TITLE_COLOR = { 0.9, 0.9, 0.9 },
    NPC_TITLE_RETRY_DELAY_SECONDS = 0.2,
    NPC_TITLE_TIMER_KEY_PREFIX = "Nameplates:NPCTitleRetry:",
    NPC_TITLE_RESOLVE_JOB_KEY = "Nameplates:NPCTitleResolve",
    NPC_TITLE_RESOLVE_INTERVAL_SECONDS = 0.03,
    NPC_TITLE_RESOLVE_BUDGET_PER_TICK = 4,
    NPC_TITLE_DEFER_ACTIVE_PLATE_THRESHOLD = 10,
    NAMEPLATE_NAME_FONT_BASE_SIZE = 12,
    NAMEPLATE_HEALTH_FONT_BASE_SIZE = 18,
    NAMEPLATE_TEXT_SCALE_MIN = 0.5,
    NAMEPLATE_TEXT_SCALE_MAX = 2.0,
    RAID_ICON_SIZE = 28,
    TOOLTIP_LINE_TYPE_UNIT_NAME = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.UnitName) or 2,
    PORTRAIT_REFRESH_JOB_KEY = "Nameplates:PortraitRefresh",
    PORTRAIT_REFRESH_INTERVAL_SECONDS = 0.03,
    PORTRAIT_REFRESH_BUDGET_PER_TICK = 6,
}

Private.Textures = {
    HEALTH_BAR = Media.Textures.HealthBar,
}

Private.ActiveNameplates = {}
Private.Runtime = {
    npcTitleCacheByGUID = {},
    npcTitleResolveQueue = {},
    npcTitleResolveHead = 1,
    npcTitleResolveQueuedByFrame = setmetatable({}, { __mode = "k" }),
    unitLevelPattern = nil,
    playerThreatRole = nil,
    threatHealthColorMirrored = nil,
    runtimeEventsRegistered = false,
    runtimeHooksRegistered = false,
    pendingPortraitRefreshQueue = {},
    pendingPortraitRefreshHead = 1,
    pendingPortraitRefreshByFrame = setmetatable({}, { __mode = "k" }),
    pendingNameplateSizeApply = false,
    lastAppliedNameplateWidth = nil,
    lastAppliedNameplateHeight = nil,
    lastCVarState = {
        inCombat = nil,
        inGroupContent = nil,
        showPetNames = nil,
    },
}

RefineUI.ActiveNameplates = Private.ActiveNameplates
RefineUI.NameplateData = RefineUI:CreateDataRegistry("NameplatesData", "k")
local NameplateData = RefineUI.NameplateData

-- Name-only plates skip health, portrait, cast, and CC work; UpdateVisibility owns the flag.
function Util.IsNameOnly(unitFrame)
    local data = unitFrame and NameplateData[unitFrame]
    return data ~= nil and data.RefineHidden == true
end

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
function Nameplates:GetPrivate()
    return Private
end

function Nameplates:GetNameplateData(unitFrame)
    if not unitFrame then
        return nil
    end

    local data = NameplateData[unitFrame]
    if not data then
        data = {}
        NameplateData[unitFrame] = data
    end
    return data
end

function Nameplates:BuildHookKey(owner, method)
    return Util.BuildHookKey("Nameplates", owner, method)
end

function Nameplates:SafeGetNamePlateForUnit(unit)
    if Util.IsDisallowedNameplateUnitToken(unit) then
        return nil
    end

    local ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then
        return nil
    end

    return nameplate
end

function Nameplates:GetConfiguredNameplatesConfig()
    return Config.Nameplates
end
