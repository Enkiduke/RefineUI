----------------------------------------------------------------------------------------
-- Auto Collapse for RefineUI
-- Description: Handles objective tracker auto collapse behavior by mode
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoCollapse = RefineUI:RegisterModule("AutoCollapse")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local C_Timer = C_Timer
local C_Scenario = C_Scenario
local ObjectiveTrackerFrame = ObjectiveTrackerFrame
local GameTooltip = GameTooltip
local MenuUtil = MenuUtil

local autoCollapseState = { collapsedByAddon = false, reloadApplied = false }
local pendingAction = nil

----------------------------------------------------------------------------------------
--	Core Collapse/Expand Functions
----------------------------------------------------------------------------------------
local function doSetCollapsed(collapsed)
    if not ObjectiveTrackerFrame then return end

    if type(ObjectiveTrackerFrame.SetCollapsed) == "function" then
        ObjectiveTrackerFrame:SetCollapsed(collapsed)
        autoCollapseState.collapsedByAddon = collapsed and true or false
        return
    end

    local btn = ObjectiveTrackerFrame.Header and ObjectiveTrackerFrame.Header.MinimizeButton
    if btn then
        local isCollapsed = ObjectiveTrackerFrame.isCollapsed or (type(ObjectiveTrackerFrame.GetCollapsed) == "function" and ObjectiveTrackerFrame:GetCollapsed())
        if isCollapsed ~= collapsed then
            btn:Click()
            autoCollapseState.collapsedByAddon = collapsed and true or false
        else
            autoCollapseState.collapsedByAddon = collapsed and true or false
        end
    end
end

local function safePerform(action)
    if action ~= "collapse" and action ~= "expand" then
        return
    end

    if InCombatLockdown() then
        pendingAction = action
        return
    end

    pendingAction = nil
    C_Timer.After(0.1, function()
        if InCombatLockdown() then
            pendingAction = action
            return
        end
        if action == "collapse" then
            doSetCollapsed(true)
        elseif action == "expand" then
            doSetCollapsed(false)
        end
    end)
end

local function CollapseObjectiveTracker()
    safePerform("collapse")
end

local function ExpandObjectiveTracker()
    safePerform("expand")
end

----------------------------------------------------------------------------------------
--	Event Handler
----------------------------------------------------------------------------------------
function AutoCollapse:UpdateState(event)
    local mode = Config.Quests.AutoCollapseMode
    local inInstance, instanceType = IsInInstance()
    local inCombat = InCombatLockdown() 
    
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end

    local desiredAction

    if mode == "COMBAT" then
        if inCombat then
            desiredAction = "collapse"
        else
            desiredAction = autoCollapseState.collapsedByAddon and "expand" or nil
        end
    elseif mode == "INSTANCE" then
        if inInstance then
            desiredAction = "collapse"
        else
            desiredAction = autoCollapseState.collapsedByAddon and "expand" or nil
        end
    elseif mode == "RELOAD" then
        if not autoCollapseState.reloadApplied then
            desiredAction = "collapse"
            autoCollapseState.reloadApplied = true
        else
            desiredAction = nil
        end
    else -- NEVER
        desiredAction = nil
    end

    if desiredAction == "collapse" then
        CollapseObjectiveTracker()
    elseif desiredAction == "expand" then
        ExpandObjectiveTracker()
    elseif not inCombat then
        pendingAction = nil
    end
end

----------------------------------------------------------------------------------------
--	Setup Auto Collapse Events
----------------------------------------------------------------------------------------
function AutoCollapse:SetupEvents()
    local events = {
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_DIFFICULTY_CHANGED",
        "SCENARIO_UPDATE",
        "SCENARIO_CRITERIA_UPDATE",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED"
    }

    RefineUI:OnEvents(events, function(event)
        if event == "PLAYER_REGEN_ENABLED" and pendingAction then
            local action = pendingAction
            pendingAction = nil
            safePerform(action)
        end
        self:UpdateState(event)
    end, "AutoCollapse:Update")
    
    self:UpdateState()
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoCollapse:OnInitialize()
    if not Config.Quests.Enable then
        return
    end

    self:SetupEvents()
end
