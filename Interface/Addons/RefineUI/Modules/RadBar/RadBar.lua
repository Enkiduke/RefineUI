----------------------------------------------------------------------------------------
-- RadBar for RefineUI
-- Description: Absolute-Strata Secure Action Bar with Macro-based Execution
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local RadBar = RefineUI:RegisterModule("RadBar")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

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
local FALLBACK_BINDING_ACTION = "CLICK RefineUI_RadBar:LeftButton"

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

    local private = self.Private or {}
    local getDefaultMainRing = private.GetDefaultMainRing

    self.db.Rings = self.db.Rings or {}
    if getDefaultMainRing then
        self.db.Rings.Main = getDefaultMainRing()
    else
        self.db.Rings.Main = {
            Slices = {},
        }
    end

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

    if self.Core:IsShown() then
        self.Core:Hide()
    else
        self.Core:Show()
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
    local private = self.Private or {}
    local getDefaultMainRing = private.GetDefaultMainRing
    local isLegacyDefaultMainRing = private.IsLegacyDefaultMainRing
    local bindingAction = private.CLICK_BINDING_ACTION or FALLBACK_BINDING_ACTION

    RefineUI.DB = RefineUI.DB or {}
    self.db = RefineUI.DB.RadBar or {}
    RefineUI.DB.RadBar = self.db

    if self.db.Enable == nil then
        self.db.Enable = true
    end

    self.db.Rings = self.db.Rings or {}
    if not self.db.Rings.Main then
        if getDefaultMainRing then
            self.db.Rings.Main = getDefaultMainRing()
        else
            self.db.Rings.Main = {
                Slices = {},
            }
        end
    else
        self.db.Rings.Main.Slices = self.db.Rings.Main.Slices or {}
        if isLegacyDefaultMainRing and isLegacyDefaultMainRing(self.db.Rings.Main) then
            if getDefaultMainRing then
                self.db.Rings.Main = getDefaultMainRing()
            else
                self.db.Rings.Main = {
                    Slices = {},
                }
            end
        end
    end

    self.Buttons = self.Buttons or {}

    -- Default Bind (only if not set)
    if not InCombatLockdown() then
        local key = GetBindingKey(bindingAction)
        if not key then
            local f8Binding = GetBindingAction and GetBindingAction("F8")
            if not f8Binding or f8Binding == "" then
                SetBinding("F8", bindingAction)
                if SaveBindings and GetCurrentBindingSet then
                    SaveBindings(GetCurrentBindingSet())
                end
            end
        end
    end

    if not self.ChatCommandRegistered then
        RefineUI:RegisterChatCommand("radbar", function(msg)
            RadBar:HandleSlash(msg)
        end)
        self.ChatCommandRegistered = true
    end
end

function RadBar:OnEnable()
    if not self.db.Enable then
        return
    end

    self:SetupCore()
    self:BuildRing("Main")
    self:SetupVisuals()

    RefineUI:OnEvents({
        "CURSOR_CHANGED",
        "ACTIONBAR_SHOWGRID",
        "ACTIONBAR_HIDEGRID",
        "PLAYER_REGEN_ENABLED",
    }, function(event, ...)
        RadBar:HandleEvent(event, ...)
    end, EVENT_KEY)
end

function RadBar:PLAYER_REGEN_ENABLED()
    if self._pendingBuildRing then
        local ringName = self._pendingBuildRing
        self._pendingBuildRing = nil
        self:BuildRing(ringName)
    end

    if self._pendingResetMainRing then
        self._pendingResetMainRing = nil
        self:ResetMainRing()
    end

    if self._pendingToggle then
        self._pendingToggle = nil
        self:HandleSlash("")
    end
end
