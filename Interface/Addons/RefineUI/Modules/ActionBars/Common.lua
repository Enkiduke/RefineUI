----------------------------------------------------------------------------------------
-- ActionBars Common
-- Description: Shared constants, registries, lookup tables, and helper methods.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local pairs = pairs
local next = next
local type = type
local tostring = tostring
local UnitExists = UnitExists

local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12
local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS = NUM_STANCE_SLOTS or 10

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ACTION_BARS_STATE_REGISTRY = "ActionBarsState"
local ACTION_BARS_BUTTON_STATE_REGISTRY = "ActionBarsButtonState"
local ACTION_BARS_SKINNED_BUTTONS_REGISTRY = "ActionBarsSkinnedButtons"
local ACTION_BARS_BUTTON_BAR_KEY_REGISTRY = "ActionBarsButtonBarKey"
local ACTION_BARS_ACTION_BUTTONS_REGISTRY = "ActionBarsActionButtons"
local ACTION_BARS_PAGED_BUTTONS_REGISTRY = "ActionBarsPagedButtons"
local ACTION_BARS_STATEFUL_BUTTONS_REGISTRY = "ActionBarsStatefulButtons"
local ACTION_BARS_PET_BUTTONS_REGISTRY = "ActionBarsPetButtons"
local ACTION_BARS_STANCE_BUTTONS_REGISTRY = "ActionBarsStanceButtons"

local BAR_KEY = {
    MAIN = "MainMenuBar",
    PET = "PetActionBar",
    STANCE = "StanceBar",
}

local BAR_KEY_TO_PREFIX = {
    MainMenuBar = "ActionButton",
    MultiBarBottomLeft = "MultiBarBottomLeftButton",
    MultiBarBottomRight = "MultiBarBottomRightButton",
    MultiBarRight = "MultiBarRightButton",
    MultiBarLeft = "MultiBarLeftButton",
    MultiBar5 = "MultiBar5Button",
    MultiBar6 = "MultiBar6Button",
    MultiBar7 = "MultiBar7Button",
    PetActionBar = "PetActionButton",
    StanceBar = "StanceButton",
}

local BUTTON_GROUPS = {
    {
        names = {
            "ActionButton",
            "MultiBarBottomLeftButton",
            "MultiBarLeftButton",
            "MultiBarRightButton",
            "MultiBarBottomRightButton",
            "MultiBar5Button",
            "MultiBar6Button",
            "MultiBar7Button",
        },
        count = NUM_ACTIONBAR_BUTTONS,
    },
    { names = { "PetActionButton" }, count = NUM_PET_ACTION_SLOTS },
    { names = { "StanceButton" }, count = NUM_STANCE_SLOTS },
}

local ACTION_FULL_RESYNC_EVENTS = {
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "SPELLS_CHANGED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
}

local PREFIX_TO_BAR_KEY = {}
for barKey, prefix in pairs(BAR_KEY_TO_PREFIX) do
    PREFIX_TO_BAR_KEY[prefix] = barKey
end

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private or {}
ActionBars.Private = private

private.ActionBarState = private.ActionBarState or RefineUI:CreateDataRegistry(ACTION_BARS_STATE_REGISTRY, "k")
private.ButtonState = private.ButtonState or RefineUI:CreateDataRegistry(ACTION_BARS_BUTTON_STATE_REGISTRY, "k")
private.SkinnedButtons = private.SkinnedButtons or RefineUI:CreateDataRegistry(ACTION_BARS_SKINNED_BUTTONS_REGISTRY, "k")
private.ButtonBarKeyCache = private.ButtonBarKeyCache or RefineUI:CreateDataRegistry(ACTION_BARS_BUTTON_BAR_KEY_REGISTRY, "k")
private.ActionButtons = private.ActionButtons or RefineUI:CreateDataRegistry(ACTION_BARS_ACTION_BUTTONS_REGISTRY, "k")
private.PagedButtons = private.PagedButtons or RefineUI:CreateDataRegistry(ACTION_BARS_PAGED_BUTTONS_REGISTRY, "k")
private.StateTrackedButtons = private.StateTrackedButtons or RefineUI:CreateDataRegistry(ACTION_BARS_STATEFUL_BUTTONS_REGISTRY, "k")
private.PetButtons = private.PetButtons or RefineUI:CreateDataRegistry(ACTION_BARS_PET_BUTTONS_REGISTRY, "k")
private.StanceButtons = private.StanceButtons or RefineUI:CreateDataRegistry(ACTION_BARS_STANCE_BUTTONS_REGISTRY, "k")
private.DeferredManager = private.DeferredManager or {
    PressButtons = {},
    CooldownButtons = {},
    StateButtons = {},
    RangeButtons = {},
}
private.ActionResyncDebug = private.ActionResyncDebug or {
    queued = 0,
    executed = 0,
    totalButtonsTouched = 0,
    lastReason = nil,
    fullPasses = 0,
    cooldownPasses = 0,
    rangePasses = 0,
}
private.actionbarsSetup = private.actionbarsSetup or false
private.deferredFlushScheduled = private.deferredFlushScheduled or false
private.fullResyncPendingSetup = private.fullResyncPendingSetup or false
private.pendingActionSlotRefresh = private.pendingActionSlotRefresh or {}
private.pendingActionPageRefresh = private.pendingActionPageRefresh or false
private.pendingAllActionRefresh = private.pendingAllActionRefresh or false

private.ACTION_FULL_RESYNC_DEBOUNCE = 0.03
private.ACTION_FULL_RESYNC_EVENTS = ACTION_FULL_RESYNC_EVENTS
private.BAR_KEY = BAR_KEY
private.BAR_KEY_TO_PREFIX = BAR_KEY_TO_PREFIX
private.BUTTON_GROUPS = BUTTON_GROUPS
private.DEBOUNCE_KEY = {
    ACTION_BUTTON_REFRESH = "ActionBars:ActionButtonRefresh",
    FULL_RESYNC = "ActionBars:FullResync",
}
private.HOVER_BORDER_COLOR = { 1, 0.82, 0, 1 }
private.RANGE_COLORS = {
    normal = { 1.0, 1.0, 1.0 },
    oor = { 0.8, 0.4, 0.4 },
    oom = { 0.4, 0.6, 1.0 },
    unusable = { 0.3, 0.3, 0.3 },
}
private.COOLDOWN_VISUAL = {
    shadeAlpha = 0.25,
    alphaEpsilon = 0.01,
    gcdDuration = 1.55,
    gcdAlpha = 0.75,
    normalAlpha = 0.25,
    alphaStep = 0.01,
}

ActionBars.SkinnedButtons = private.SkinnedButtons

----------------------------------------------------------------------------------------
-- Shared Helpers
----------------------------------------------------------------------------------------
function private.GetActionBarState(owner, key, defaultValue)
    return RefineUI:RegistryGet(ACTION_BARS_STATE_REGISTRY, owner, key, defaultValue)
end

function private.SetActionBarState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(ACTION_BARS_STATE_REGISTRY, owner, key)
    else
        RefineUI:RegistrySet(ACTION_BARS_STATE_REGISTRY, owner, key, value)
    end
end

function private.BuildHookKey(owner, method, qualifier)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end

    local key = "ActionBars:" .. ownerId .. ":" .. method
    if qualifier and qualifier ~= "" then
        key = key .. ":" .. qualifier
    end
    return key
end

function private.GetButtonState(button)
    local state = private.ButtonState[button]
    if not state then
        state = {}
        private.ButtonState[button] = state
    end
    return state
end

function private.GetBarKeyForButton(button)
    if not button then
        return nil
    end

    local cached = private.ButtonBarKeyCache[button]
    if cached ~= nil then
        return cached or nil
    end

    local name = button.GetName and button:GetName()
    if not name then
        return nil
    end

    for prefix, barKey in pairs(PREFIX_TO_BAR_KEY) do
        if name:sub(1, #prefix) == prefix then
            private.ButtonBarKeyCache[button] = barKey
            return barKey
        end
    end

    private.ButtonBarKeyCache[button] = false
    return nil
end

function private.RegisterButtonCollections(button)
    if not button then
        return
    end

    local barKey = private.GetBarKeyForButton(button)
    if not barKey then
        return
    end

    private.StateTrackedButtons[button] = true

    if barKey == BAR_KEY.PET then
        private.PetButtons[button] = true
        return
    end

    if barKey == BAR_KEY.STANCE then
        private.StanceButtons[button] = true
        return
    end

    private.ActionButtons[button] = true
    if barKey == BAR_KEY.MAIN then
        private.PagedButtons[button] = true
    end
end

function private.RefreshButton(button, refreshCooldown, refreshState, forceState, hasTarget)
    if not button or not button:IsVisible() then
        return false
    end

    if refreshCooldown then
        private.HandleButtonCooldownUpdate(button)
    end
    if refreshState then
        private.RefreshButtonState(button, forceState == true, hasTarget)
    end

    return true
end

function private.RefreshButtonCollection(buttons, refreshCooldown, refreshState, forceState)
    if not buttons or not next(buttons) then
        return 0
    end

    local hasTargetValue
    local touched = 0
    for button in pairs(buttons) do
        if refreshState and hasTargetValue == nil and button and button:IsVisible() then
            hasTargetValue = UnitExists("target")
        end

        if private.RefreshButton(button, refreshCooldown, refreshState, forceState, hasTargetValue) then
            touched = touched + 1
        end
    end

    return touched
end

function private.IsHotkeyEnabledForButton(button)
    local db = ActionBars.db
    if not db or not db.ShowHotkeys then
        return false
    end

    local barKey = private.GetBarKeyForButton(button)
    if not barKey then
        return false
    end

    return db.ShowHotkeys[barKey] == true
end

function private.ForEachButtonCooldownFrame(button, callback)
    if not button or not callback then
        return
    end

    if button.cooldown then
        callback(button.cooldown, "cooldown")
    end
    if button.chargeCooldown then
        callback(button.chargeCooldown, "chargeCooldown")
    end
    if button.lossOfControlCooldown then
        callback(button.lossOfControlCooldown, "lossOfControlCooldown")
    end
end

function private.IsActionResyncDebugEnabled()
    return type(RefineUI.IsObservabilityEnabled) == "function" and RefineUI:IsObservabilityEnabled()
end
