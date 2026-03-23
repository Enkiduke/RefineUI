----------------------------------------------------------------------------------------
-- RefineUI Modules
-- Description: Module registration and lifecycle management system.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local error = error
local _G = _G
local pairs, ipairs = pairs, ipairs
local tinsert = table.insert
local xpcall = xpcall
local tostring = tostring
local type = type
local UnitName = UnitName
local GetRealmName = GetRealmName

local function ReportModuleError(module, phase, err)
    print("|cffff0000Refine|rUI Module Error (" .. phase .. "):", module.Name or "Unknown", tostring(err))
end

----------------------------------------------------------------------------------------
-- Module State
----------------------------------------------------------------------------------------
local function GetStoredProfile()
    if type(RefineUI.DB) == "table" then
        return RefineUI.DB
    end

    local savedDB = _G.RefineDB
    if type(savedDB) ~= "table" then
        return nil
    end

    local realm = RefineUI.MyRealm or (GetRealmName and GetRealmName())
    local name = RefineUI.MyName or (UnitName and UnitName("player"))
    if type(realm) ~= "string" or realm == "" or type(name) ~= "string" or name == "" then
        return nil
    end

    local realmData = savedDB[realm]
    if type(realmData) ~= "table" then
        return nil
    end

    local profile = realmData[name]
    if type(profile) == "table" then
        return profile
    end

    return nil
end

local function GetConfigTable()
    if type(RefineUI.Config) == "table" then
        return RefineUI.Config
    end
    return nil
end

local function GetAutomationConfig(cfg)
    local automation = cfg and cfg.Automation
    if type(automation) == "table" then
        return automation
    end
    return nil
end

local function GetQuestsConfig(cfg)
    local quests = cfg and cfg.Quests
    if type(quests) == "table" then
        return quests
    end
    return nil
end

local function GetLootConfig(cfg)
    local loot = cfg and cfg.Loot
    if type(loot) == "table" then
        return loot
    end
    return nil
end

local function GetUnitFramesConfig(cfg)
    local unitFrames = cfg and cfg.UnitFrames
    if type(unitFrames) == "table" then
        return unitFrames
    end
    return nil
end

local MODULE_STARTUP_FALLBACK = {
    ActionBars = function(cfg)
        return not (cfg and cfg.ActionBars and cfg.ActionBars.Enable == false)
    end,
    AFK = function(cfg)
        return not (cfg and cfg.AFK and cfg.AFK.Enable == false)
    end,
    Auras = function(cfg)
        return not (cfg and cfg.Auras and cfg.Auras.Enable == false)
    end,
    AutoAccept = function(cfg)
        local quests = GetQuestsConfig(cfg)
        if not quests or quests.Enable == false then
            return false
        end
        return quests.AutoAccept == true or quests.AutoComplete == true
    end,
    AutoButton = function(cfg)
        local automation = GetAutomationConfig(cfg)
        return not (automation and automation.AutoButton and automation.AutoButton.Enable == false)
    end,
    AutoCollapse = function(cfg)
        local quests = GetQuestsConfig(cfg)
        if not quests or quests.Enable == false then
            return false
        end
        return quests.AutoCollapseMode ~= "NEVER"
    end,
    AutoConfirm = function(cfg)
        local loot = GetLootConfig(cfg)
        if not loot or loot.Enable == false then
            return false
        end
        return loot.AutoConfirm ~= false
    end,
    AutoItemBar = function(cfg)
        local automation = GetAutomationConfig(cfg)
        return not (automation and automation.AutoItemBar and automation.AutoItemBar.Enable == false)
    end,
    AutoOpenBar = function(cfg)
        local automation = GetAutomationConfig(cfg)
        return not (automation and automation.AutoOpenBar and automation.AutoOpenBar.Enable == false)
    end,
    AutoRepair = function(cfg)
        local automation = GetAutomationConfig(cfg)
        return not (automation and automation.AutoRepair == false)
    end,
    AutoZoneTrack = function(cfg)
        local quests = GetQuestsConfig(cfg)
        if not quests or quests.Enable == false then
            return false
        end
        return quests.AutoZoneTrack ~= false
    end,
    Bags = function(cfg)
        return not (cfg and cfg.Bags and cfg.Bags.Enable == false)
    end,
    BuffReminder = function(cfg)
        return not (cfg and cfg.BuffReminder and cfg.BuffReminder.Enable == false)
    end,
    CDM = function(cfg)
        return not (cfg and cfg.CDM and cfg.CDM.Enable == false)
    end,
    Chat = function(cfg)
        return not (cfg and cfg.Chat and cfg.Chat.Enable == false)
    end,
    ClickCasting = function(cfg)
        return not (cfg and cfg.ClickCasting and cfg.ClickCasting.Enable == false)
    end,
    Combat = function(cfg)
        local combat = cfg and cfg.Combat
        if type(combat) ~= "table" then
            return true
        end
        return combat.CrosshairEnable ~= false
            or combat.CursorEnable ~= false
            or combat.StickyTargeting == true
            or combat.DisableRightClickInteraction == true
            or combat.AutoTargetOnClick == true
    end,
    Dismount = function()
        return true
    end,
    EncounterAchievements = function()
        return true
    end,
    EncounterTimeline = function(cfg)
        return not (cfg and cfg.EncounterTimeline and cfg.EncounterTimeline.Enable == false)
    end,
    EntranceDifficulty = function(cfg)
        return not (cfg and cfg.EntranceDifficulty and cfg.EntranceDifficulty.Enable == false)
    end,
    ErrorFilter = function(cfg)
        return not (cfg and cfg.ErrorsFrame and cfg.ErrorsFrame.Enable == false)
    end,
    ExperienceBar = function(cfg)
        local unitFrames = GetUnitFramesConfig(cfg)
        local dataBars = unitFrames and unitFrames.DataBars
        local experienceBar = type(dataBars) == "table" and dataBars.ExperienceBar or nil
        if type(experienceBar) == "table" then
            return experienceBar.Enable ~= false
        end
        if type(experienceBar) == "boolean" then
            return experienceBar
        end
        return true
    end,
    FadeIn = function(cfg)
        return not (cfg and cfg.FadeIn and cfg.FadeIn.Enable == false)
    end,
    FasterLoot = function(cfg)
        local loot = GetLootConfig(cfg)
        if not loot or loot.Enable == false then
            return false
        end
        return loot.FasterLoot ~= false
    end,
    GameMenu = function()
        return true
    end,
    GameTime = function(cfg)
        return not (cfg and cfg.GameTime and cfg.GameTime.Enable == false)
    end,
    Install = function()
        return true
    end,
    LootRules = function(cfg)
        local loot = GetLootConfig(cfg)
        return not (loot and loot.Enable == false)
    end,
    LootSettings = function(cfg)
        local loot = GetLootConfig(cfg)
        return not (loot and loot.Enable == false)
    end,
    Maps = function(cfg)
        return not (cfg and cfg.Maps and cfg.Maps.Enable == false)
    end,
    MicroMenu = function()
        return true
    end,
    Nameplates = function(cfg)
        return not (cfg and cfg.Nameplates and cfg.Nameplates.Enable == false)
    end,
    Quests = function(cfg)
        return not (cfg and cfg.Quests and cfg.Quests.Enable == false)
    end,
    RadBar = function(cfg)
        return not (cfg and cfg.RadBar and cfg.RadBar.Enable == false)
    end,
    Skins = function(cfg)
        return not (cfg and cfg.Skins and cfg.Skins.Enable == false)
    end,
    TalkingHead = function(cfg)
        return not (cfg and cfg.TalkingHead and cfg.TalkingHead.Enable == false)
    end,
    Tooltip = function(cfg)
        return not (cfg and cfg.Tooltip and cfg.Tooltip.Enable == false)
    end,
    UnitFrames = function(cfg)
        return not (cfg and cfg.UnitFrames and cfg.UnitFrames.Enable == false)
    end,
}

function RefineUI:GetSavedModuleEnabled(moduleName)
    if type(moduleName) ~= "string" or moduleName == "" then
        return nil
    end

    local profile = GetStoredProfile()
    local moduleState = profile and profile.ModuleState
    local value
    if type(moduleState) == "table" then
        value = moduleState[moduleName]
    end
    if type(value) == "boolean" then
        return value
    end

    return nil
end

function RefineUI:SetSavedModuleEnabled(moduleName, enabled)
    if type(moduleName) ~= "string" or moduleName == "" or type(enabled) ~= "boolean" then
        return nil
    end

    local profile = GetStoredProfile()
    if type(profile) ~= "table" then
        return nil
    end

    profile.ModuleState = profile.ModuleState or {}
    profile.ModuleState[moduleName] = enabled and true or false
    return profile.ModuleState[moduleName]
end

function RefineUI:IsModuleStartupEnabled(moduleName)
    local saved = self:GetSavedModuleEnabled(moduleName)
    if type(saved) == "boolean" then
        return saved
    end

    local resolver = MODULE_STARTUP_FALLBACK[moduleName]
    if type(resolver) == "function" then
        return resolver(GetConfigTable()) ~= false
    end

    return true
end

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
RefineUI.ModuleRegistry = {} -- Ordered list of modules
RefineUI.Modules = {} -- Access table (Key = Name)

----------------------------------------------------------------------------------------
-- Module API
----------------------------------------------------------------------------------------
local ModuleMixin = {}

function ModuleMixin:Update()
    -- Default empty update function
end

function ModuleMixin:Print(...)
    print("|cffffd200Refine|rUI " .. self.Name .. ":|r", ...)
end

function ModuleMixin:Error(...)
    print("|cffff0000Refine|rUI " .. self.Name .. " Error:|r", ...)
end

function RefineUI:RegisterModule(name)
    if type(name) ~= "string" or name == "" then
        error("RefineUI:RegisterModule requires a non-empty string name.", 2)
    end

    if RefineUI.Modules[name] then
        error("RefineUI:RegisterModule duplicate module key: " .. name, 2)
    end

    local module = {}
    
    -- Mixin base functionality
    for k, v in pairs(ModuleMixin) do
        module[k] = v
    end

    module.Name = name
    module._initialized = false
    module._enabled = false
    
    RefineUI.Modules[name] = module
    tinsert(RefineUI.ModuleRegistry, module)

    return module
end

function RefineUI:GetModule(name)
    return RefineUI.Modules[name]
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function RefineUI:InitializeModules()
    if self._modulesInitialized then
        return
    end

    -- Phase 1: Initialize (ADDON_LOADED) - Load settings, etc.
    for _, module in ipairs(RefineUI.ModuleRegistry) do
        if self:IsModuleStartupEnabled(module.Name) and not module._initialized and module.OnInitialize then
            local ok, err = xpcall(function()
                module:OnInitialize()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnInitialize", err)
            end
        end
        if self:IsModuleStartupEnabled(module.Name) then
            module._initialized = true
        end
    end

    self._modulesInitialized = true
end

function RefineUI:EnableModules()
    if self._modulesEnabled then
        return
    end

    if not self._modulesInitialized then
        self:InitializeModules()
    end

    for _, module in ipairs(RefineUI.ModuleRegistry) do
        if self:IsModuleStartupEnabled(module.Name) and not module._enabled and module.OnEnable then
            local ok, err = xpcall(function()
                module:OnEnable()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnEnable", err)
            end
        end
        if self:IsModuleStartupEnabled(module.Name) then
            module._enabled = true
        end
    end

    self._modulesEnabled = true
end

RefineUI:RegisterStartupCallback("Core:Modules", function()
    RefineUI:InitializeModules()
    RefineUI:EnableModules()
end, 50)
