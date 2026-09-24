----------------------------------------------------------------------------------------
-- ActionBars
-- Description: Root module registration and lifecycle orchestration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:RegisterModule("ActionBars", "ActionBars")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:SetupActionBars()
    local private = self.Private
    if not private or InCombatLockdown() or private.actionbarsSetup then
        return
    end

    for _, group in ipairs(private.BUTTON_GROUPS) do
        private.StyleButtons(group.names, group.count)
    end

    self:SetupExtraActionBars()
    self:SetupVehicleActionBars()

    private.actionbarsSetup = true
    self:QueueFullResync()
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function ActionBars:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.ActionBars or RefineUI.Config.ActionBars
end

function ActionBars:OnEnable()
    if not self.db or not self.db.Enable then
        return
    end

    self:SetupHooks()

    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        self:RefreshCombatButtonStates(true)
    end, "ActionBars:RefreshEnterCombat")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        self:SetupActionBars()
        self:RefreshCombatButtonStates(true)
    end, "ActionBars:RefreshLeaveCombat")

    RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function()
        self:RefreshTargetButtonRanges(true)
    end, "ActionBars:RefreshTargetChanged")

    RefineUI:RegisterEventCallback("ACTIONBAR_SLOT_CHANGED", function(event, slot)
        self:QueueActionButtonRefresh(event, slot)
    end, "ActionBars:ActionSlotRefresh")

    RefineUI:RegisterEventCallback("ACTIONBAR_PAGE_CHANGED", function(event)
        self:QueueActionButtonRefresh(event)
    end, "ActionBars:ActionPageRefresh")

    RefineUI:RegisterEventCallback("PET_BAR_UPDATE", function()
        self.Private.RefreshButtonCollection(self.Private.PetButtons, true, true, true)
    end, "ActionBars:PetBarRefresh")

    RefineUI:RegisterEventCallback("UPDATE_SHAPESHIFT_FORMS", function()
        self.Private.RefreshButtonCollection(self.Private.StanceButtons, true, true, true)
    end, "ActionBars:StanceBarRefresh")

    RefineUI:OnEvents(self.Private.ACTION_FULL_RESYNC_EVENTS, function()
        self:QueueFullResync()
    end, "ActionBars:FullResync")

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        self:SetupActionBars()
    end, "ActionBars:Setup")

    self:RegisterEditModeSettings()
end
