----------------------------------------------------------------------------------------
-- RefineUI Modules
-- Description: Module registration and lifecycle management system.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local error = error
local pairs, ipairs = pairs, ipairs
local tinsert = table.insert
local xpcall = xpcall
local ErrorHandler = RefineUI.ErrorHandler
local type = type

----------------------------------------------------------------------------------------
-- Module State
----------------------------------------------------------------------------------------
-- Startup rules declared by each module at registration.
-- A string names a config section that disables the module with `Enable = false`;
-- a function receives RefineUI.Config and returns false to disable.
local startupRules = {}

function RefineUI:GetSavedModuleEnabled(moduleName)
    if type(moduleName) ~= "string" or moduleName == "" then
        return nil
    end

    local profile = RefineUI.DB
    local moduleState = profile and profile.ModuleState
    local value
    if type(moduleState) == "table" then
        value = moduleState[moduleName]
        -- Preserve the combined module's startup preference until each new
        -- Adventure Guide module receives its own explicit setting.
        if value == nil and (moduleName == "AdventureGuideInstances" or moduleName == "AdventureGuidePlanner") then
            value = moduleState.EncounterAchievements
        end
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

    local profile = RefineUI.DB
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

    local rule = startupRules[moduleName]
    local cfg = RefineUI.Config
    if type(rule) == "string" then
        local section = cfg and cfg[rule]
        return not (type(section) == "table" and section.Enable == false)
    elseif type(rule) == "function" then
        return rule(cfg) ~= false
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

function RefineUI:RegisterModule(name, startupRule)
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
    
    startupRules[name] = startupRule
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
            xpcall(module.OnInitialize, ErrorHandler, module)
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
            xpcall(module.OnEnable, ErrorHandler, module)
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
