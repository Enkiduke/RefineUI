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
local tostring = tostring

local function ReportModuleError(module, phase, err)
    print("|cffff0000Refine|rUI Module Error (" .. phase .. "):", module.Name or "Unknown", tostring(err))
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
        if not module._initialized and module.OnInitialize then
            local ok, err = xpcall(function()
                module:OnInitialize()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnInitialize", err)
            end
        end

        module._initialized = true
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
        if not module._enabled and module.OnEnable then
            local ok, err = xpcall(function()
                module:OnEnable()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnEnable", err)
            end
        end

        module._enabled = true
    end

    self._modulesEnabled = true
end

RefineUI:RegisterStartupCallback("Core:Modules", function()
    RefineUI:InitializeModules()
    RefineUI:EnableModules()
end, 50)
