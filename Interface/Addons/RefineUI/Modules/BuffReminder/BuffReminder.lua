----------------------------------------------------------------------------------------
-- BuffReminder for RefineUI
-- Description: Displays missing buffs for the player and their party/raid.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:RegisterModule("BuffReminder", "BuffReminder")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues (Cache only what you actually use)
----------------------------------------------------------------------------------------
local _G = _G
local issecretvalue = _G.issecretvalue
local InCombatLockdown = InCombatLockdown
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

BuffReminder.FRAME_NAME = "RefineUI_BuffReminder"
BuffReminder.UPDATE_DEBOUNCE_KEY = "BuffReminder:Refresh"
BuffReminder.QUESTION_MARK_ICON = 134400

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function BuffReminder:Refresh()
    self:RenderEntries(self:CollectMissingEntries())
    self:UpdateGroupAuraWatch()
end

-- Unfiltered UNIT_AURA wakes Lua for every nameplate and group member. The player's
-- auras are always unit-filtered; everyone else's only while a targeted buff needs them.
local GROUP_AURA_EVENT_KEY = "BuffReminder:UNIT_AURA:Group"

function BuffReminder:UpdateGroupAuraWatch()
    local watch = self.watchGroupAuras == true and self.onGroupAuraEvent ~= nil
    if self.groupAuraWatchActive == watch then
        return
    end

    self.groupAuraWatchActive = watch
    if watch then
        RefineUI:RegisterEventCallback("UNIT_AURA", self.onGroupAuraEvent, GROUP_AURA_EVENT_KEY)
    else
        RefineUI:OffEvent("UNIT_AURA", GROUP_AURA_EVENT_KEY)
    end
end

function BuffReminder:RequestRefresh()
    RefineUI:Debounce(self.UPDATE_DEBOUNCE_KEY, 0.08, function()
        self:Refresh()
        self:RefreshBuffOptionsWindow()
    end)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function BuffReminder:OnEnable()
    if self:GetConfig().Enable == false then
        return
    end

    self:EnsureRootFrame()
    self:RegisterEditModeFrame()
    self:RegisterEditModeCallbacks()

    local function OnEvent(event, ...)
        if event == "UNIT_AURA" then
            local unit = ...
            if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" then
                return
            end
            -- Only targeted buffs read other members' auras; skip group aura churn otherwise.
            if unit ~= "player" and not (self.watchGroupAuras and self:IsTrackedUnitToken(unit)) then
                return
            end
            if InCombatLockdown() then
                return
            end
        elseif event == "UNIT_INVENTORY_CHANGED" then
            local unit = ...
            if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" or unit ~= "player" then
                return
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if unit and ((issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" or unit ~= "player") then
                return
            end
        elseif event == "UNIT_PET" then
            local unit = ...
            if unit ~= "player" then
                return
            end
        end
        self:RequestRefresh()
    end

    RefineUI:OnUnitEvents("player", { "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "UNIT_PET" }, OnEvent, "BuffReminder:Player")
    self.onGroupAuraEvent = function(event, unit)
        if unit ~= "player" then
            OnEvent(event, unit)
        end
    end

    RefineUI:OnEvents({
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "UPDATE_SHAPESHIFT_FORM",
        "TRAIT_CONFIG_UPDATED",
        "PLAYER_EQUIPMENT_CHANGED",
        "PET_BAR_UPDATE",
    }, OnEvent, "BuffReminder")

    self:Refresh()
end
