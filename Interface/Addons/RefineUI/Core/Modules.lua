----------------------------------------------------------------------------------------
-- RefineUI Modules
-- Description: Module registration and lifecycle management system.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
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
    if RefineUI.Modules[name] then
        print("Module already exists:", name)
        return RefineUI.Modules[name]
    end

    local module = {}
    
    -- Mixin base functionality
    for k, v in pairs(ModuleMixin) do
        module[k] = v
    end

    module.Name = name
    
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
    -- Phase 1: Initialize (ADDON_LOADED) - Load settings, etc.
    for _, module in ipairs(RefineUI.ModuleRegistry) do
        if module.OnInitialize then
            local ok, err = xpcall(function()
                module:OnInitialize()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnInitialize", err)
            end
        end
    end
end

local function RunModuleLifecycle()
    -- Initialize modules first.
    RefineUI:InitializeModules()

    -- Then enable modules.
    for _, module in ipairs(RefineUI.ModuleRegistry) do
        if module.OnEnable then
            local ok, err = xpcall(function()
                module:OnEnable()
            end, function(e)
                return e
            end)
            if not ok then
                ReportModuleError(module, "OnEnable", err)
            end
        end
    end
end

RefineUI:RegisterStartupCallback("Core:Modules", RunModuleLifecycle, 50)
