----------------------------------------------------------------------------------------
-- RadBar for RefineUI
-- Description: Absolute-Strata Secure Action Bar with Macro-based Execution
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local RadBar = RefineUI:RegisterModule("RadBar", "RadBar")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local GetBindingAction = GetBindingAction
local SetBinding = SetBinding
local SaveBindings = SaveBindings
local GetCurrentBindingSet = GetCurrentBindingSet

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local EVENT_KEY = "RadBar"

----------------------------------------------------------------------------------------
-- Internal Shared State
----------------------------------------------------------------------------------------
RadBar.Private = RadBar.Private or {}

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function RadBar:ResetMainRing()
    if InCombatLockdown() then
        self._pendingResetMainRing = true
        self:Print("RadBar reset queued until combat ends.")
        return
    end

    self.db.Rings.Main = self.Private.GetDefaultMainRing()

    if self.Core then
        self:BuildRing("Main")
    end
    self:Print("RadBar reset.")
end

function RadBar:HandleSlash(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "reset" then
        self:ResetMainRing()
        return
    end

    if InCombatLockdown() then
        self._pendingToggle = not self._pendingToggle
        self:Print("RadBar toggle queued until combat ends.")
        return
    end

    if not self.Core then
        return
    end

    if self.mode ~= "closed" then
        self:CloseRing()
    elseif self.Private.IsSupportedActionType(GetCursorInfo()) then
        self:CURSOR_CHANGED()
    else
        self:OpenRing()
    end
end

function RadBar:HandleEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function RadBar:OnInitialize()
    local private = self.Private
    local bindingAction = private.CLICK_BINDING_ACTION

    -- Profile defaults are merged before modules initialize.
    self.db = RefineUI.DB.RadBar
    if private.IsLegacyDefaultMainRing(self.db.Rings.Main) then
        self.db.Rings.Main = private.GetDefaultMainRing()
    end

    self.Buttons = {}

    -- Default Bind (only if not set)
    if not InCombatLockdown() and not GetBindingKey(bindingAction) then
        local f8Binding = GetBindingAction("F8")
        if not f8Binding or f8Binding == "" then
            SetBinding("F8", bindingAction)
            SaveBindings(GetCurrentBindingSet())
        end
    end

    RefineUI:RegisterChatCommand("radbar", function(msg)
        RadBar:HandleSlash(msg)
    end)
end

function RadBar:OnEnable()
    self:SetupCore()
    self:SetupVisuals()
    self:BuildRing("Main")

    RefineUI:OnEvents({
        "CURSOR_CHANGED",
        "ACTIONBAR_SHOWGRID",
        "ACTIONBAR_HIDEGRID",
        "PLAYER_REGEN_ENABLED",
        "UPDATE_MACROS",
    }, function(event, ...)
        RadBar:HandleEvent(event, ...)
    end, EVENT_KEY)
    self:CURSOR_CHANGED()
end

function RadBar:PLAYER_REGEN_ENABLED()
    local pendingRing = self._pendingBuildRing
    self._pendingBuildRing = nil
    if self._pendingResetMainRing then
        self._pendingResetMainRing = nil
        self:ResetMainRing()
    elseif pendingRing then
        self:BuildRing(pendingRing)
    end

    -- Cursor/grid events can arrive during lockdown; reconcile current state now.
    self:CURSOR_CHANGED()

    if self._pendingToggle then
        self._pendingToggle = nil
        self:HandleSlash("")
    end
end

function RadBar:UPDATE_MACROS()
    self:BuildRing(self.activeRing or "Main")
end
