----------------------------------------------------------------------------------------
-- BuffReminder for RefineUI
-- Description: Displays missing buffs for the player and their party/raid.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:RegisterModule("BuffReminder")

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
BuffReminder.AURA_FILTER = "HELPFUL"

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function BuffReminder:Refresh()
    self:RenderEntries(self:CollectMissingEntries())
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
            if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" or not self:IsTrackedUnitToken(unit) then
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

    RefineUI:OnEvents({
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE",
        "UNIT_AURA",
        "PLAYER_ROLES_ASSIGNED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "UNIT_INVENTORY_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_PET",
        "PET_BAR_UPDATE",
    }, OnEvent, "BuffReminder")

    self:Refresh()
end
