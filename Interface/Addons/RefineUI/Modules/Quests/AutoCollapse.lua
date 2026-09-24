----------------------------------------------------------------------------------------
-- Auto Collapse for RefineUI
-- Description: Handles objective tracker auto collapse behavior by mode
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoCollapse = RefineUI:RegisterModule("AutoCollapse", function(cfg)
    local quests = cfg.Quests
    if type(quests) ~= "table" or quests.Enable == false then
        return false
    end
    return quests.AutoCollapseMode ~= "NEVER"
end)

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local IsInInstance = IsInInstance
local ObjectiveTrackerFrame = ObjectiveTrackerFrame

local autoCollapseState = { collapsedByAddon = false, reloadApplied = false }
local applyingCollapse = false

----------------------------------------------------------------------------------------
--	Core Collapse/Expand Functions
----------------------------------------------------------------------------------------
local function doSetCollapsed(collapsed)
    if not ObjectiveTrackerFrame or ObjectiveTrackerFrame:IsCollapsed() == collapsed then return end
    applyingCollapse = true
    ObjectiveTrackerFrame:SetCollapsed(collapsed)
    applyingCollapse = false
    autoCollapseState.collapsedByAddon = collapsed
end

----------------------------------------------------------------------------------------
--	Event Handler
----------------------------------------------------------------------------------------
function AutoCollapse:UpdateState(event)
    if not self.eventsRegistered then self:SetupEvents() end
    -- SetCollapsed performs a synchronous layout, including restricted aura reads.
    -- Reevaluate on restriction/combat exit instead of replaying an obsolete action.
    if not RefineUI:GetModule("Quests"):CanUpdateObjectiveTracker() then return end
    local mode = Config.Quests.AutoCollapseMode
    local inInstance = IsInInstance()
    local inCombat = event == "PLAYER_REGEN_DISABLED"

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
        desiredAction = autoCollapseState.collapsedByAddon and "expand" or nil
    end

    if desiredAction == "collapse" then
        doSetCollapsed(true)
    elseif desiredAction == "expand" then
        doSetCollapsed(false)
    end
end

----------------------------------------------------------------------------------------
--	Setup Auto Collapse Events
----------------------------------------------------------------------------------------
function AutoCollapse:SetupEvents()
    if self.eventsRegistered then return end
    self.eventsRegistered = true
    local events = {
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "ADDON_RESTRICTION_STATE_CHANGED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED"
    }

    RefineUI:OnEvents(events, function(event)
        if event == "ZONE_CHANGED_NEW_AREA" and Config.Quests.AutoCollapseMode ~= "INSTANCE" then return end
        self:UpdateState(event)
    end, "AutoCollapse:Update")
    RefineUI:HookOnce("AutoCollapse:ManualChange", ObjectiveTrackerFrame, "SetCollapsed", function()
        if not applyingCollapse then autoCollapseState.collapsedByAddon = false end
    end)
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoCollapse:OnInitialize()
    if not Config.Quests.Enable then
        return
    end

    self:SetupEvents()
    self:UpdateState()
end
