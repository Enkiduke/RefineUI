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
local type = type
local tostring = tostring
local pcall = pcall

local C_NamePlate = C_NamePlate

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local NAMEPLATE_STATE_REGISTRY = "NameplatesState"
local NAMEPLATE_DATA_REGISTRY = "NameplatesData"

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
Nameplates.Private = Nameplates.Private or {}
local Private = Nameplates.Private

Private.Util = Private.Util or RefineUI.NameplatesUtil
Private.Constants = Private.Constants or {
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
Private.Constants.NPC_TITLE_RESOLVE_JOB_KEY = Private.Constants.NPC_TITLE_RESOLVE_JOB_KEY or "Nameplates:NPCTitleResolve"
Private.Constants.NPC_TITLE_RESOLVE_INTERVAL_SECONDS = Private.Constants.NPC_TITLE_RESOLVE_INTERVAL_SECONDS or 0.03
Private.Constants.NPC_TITLE_RESOLVE_BUDGET_PER_TICK = Private.Constants.NPC_TITLE_RESOLVE_BUDGET_PER_TICK or 4
Private.Constants.NPC_TITLE_DEFER_ACTIVE_PLATE_THRESHOLD = Private.Constants.NPC_TITLE_DEFER_ACTIVE_PLATE_THRESHOLD or 10
Private.Constants.PORTRAIT_REFRESH_JOB_KEY = Private.Constants.PORTRAIT_REFRESH_JOB_KEY or "Nameplates:PortraitRefresh"
Private.Constants.PORTRAIT_REFRESH_INTERVAL_SECONDS = Private.Constants.PORTRAIT_REFRESH_INTERVAL_SECONDS or 0.03
Private.Constants.PORTRAIT_REFRESH_BUDGET_PER_TICK = Private.Constants.PORTRAIT_REFRESH_BUDGET_PER_TICK or 6

Private.Textures = Private.Textures or {
    HEALTH_BAR = (Media and Media.Textures and Media.Textures.HealthBar) or nil,
    PORTRAIT_BORDER = (Media and Media.Textures and Media.Textures.PortraitBorder) or nil,
    PORTRAIT_BG = (Media and Media.Textures and Media.Textures.PortraitBG) or nil,
    PORTRAIT_MASK = (Media and Media.Textures and Media.Textures.PortraitMask) or nil,
}

Private.ActiveNameplates = Private.ActiveNameplates or {}
Private.Runtime = Private.Runtime or {
    npcTitleCacheByGUID = {},
    npcTitleResolveQueue = {},
    npcTitleResolveHead = 1,
    npcTitleResolveQueuedByFrame = setmetatable({}, { __mode = "k" }),
    unitLevelPattern = nil,
    playerThreatRole = nil,
    runtimeEventsRegistered = false,
    runtimeHooksRegistered = false,
    pendingPortraitRefreshQueue = {},
    pendingPortraitRefreshHead = 1,
    pendingPortraitRefreshByFrame = setmetatable({}, { __mode = "k" }),
    nameplateSizeHooksRegistered = {
        base = false,
        unit = false,
        anchors = false,
    },
    pendingNameplateSizeApply = false,
    lastAppliedNameplateWidth = nil,
    lastAppliedNameplateHeight = nil,
    lastCVarState = {
        inCombat = nil,
        inGroupContent = nil,
        showPetNames = nil,
    },
}
Private.Runtime.npcTitleCacheByGUID = Private.Runtime.npcTitleCacheByGUID or {}
Private.Runtime.npcTitleResolveQueue = Private.Runtime.npcTitleResolveQueue or {}
Private.Runtime.npcTitleResolveHead = Private.Runtime.npcTitleResolveHead or 1
Private.Runtime.npcTitleResolveQueuedByFrame = Private.Runtime.npcTitleResolveQueuedByFrame or setmetatable({}, { __mode = "k" })
Private.Runtime.pendingPortraitRefreshQueue = Private.Runtime.pendingPortraitRefreshQueue or {}
Private.Runtime.pendingPortraitRefreshHead = Private.Runtime.pendingPortraitRefreshHead or 1
Private.Runtime.pendingPortraitRefreshByFrame = Private.Runtime.pendingPortraitRefreshByFrame or setmetatable({}, { __mode = "k" })
if type(Private.Runtime.runtimeEventsRegistered) ~= "boolean" then
    Private.Runtime.runtimeEventsRegistered = false
end
if type(Private.Runtime.runtimeHooksRegistered) ~= "boolean" then
    Private.Runtime.runtimeHooksRegistered = false
end
Private.Runtime.lastCVarState = Private.Runtime.lastCVarState or {
    inCombat = nil,
    inGroupContent = nil,
    showPetNames = nil,
}

-- Compatibility aliases used by existing components and EditMode.
RefineUI.ActiveNameplates = Private.ActiveNameplates
RefineUI.NameplateData = RefineUI.NameplateData or RefineUI:CreateDataRegistry(NAMEPLATE_DATA_REGISTRY, "k")

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

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        data = {}
        RefineUI.NameplateData[unitFrame] = data
    end
    return data
end

function Nameplates:GetNameplateState(owner, key, defaultValue)
    return RefineUI:RegistryGet(NAMEPLATE_STATE_REGISTRY, owner, key, defaultValue)
end

function Nameplates:SetNameplateState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(NAMEPLATE_STATE_REGISTRY, owner, key)
        return
    end

    RefineUI:RegistrySet(NAMEPLATE_STATE_REGISTRY, owner, key, value)
end

function Nameplates:BuildHookKey(owner, method)
    local util = Private.Util
    if util and util.BuildHookKey then
        return util.BuildHookKey("Nameplates", owner, method)
    end
    return "Nameplates:" .. tostring(owner) .. ":" .. tostring(method)
end

function Nameplates:SafeGetNamePlateForUnit(unit, includeForbidden)
    local util = Private.Util
    if util and util.IsDisallowedNameplateUnitToken and util.IsDisallowedNameplateUnitToken(unit) then
        return nil
    end

    if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        return nil
    end

    local ok, nameplate
    if includeForbidden == nil then
        ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    else
        ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, unit, includeForbidden)
    end

    if not ok then
        return nil
    end

    return nameplate
end

function Nameplates:GetConfiguredNameplatesConfig()
    return Config and Config.Nameplates or nil
end
