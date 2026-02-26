----------------------------------------------------------------------------------------
-- BuffReminder Component: Config
-- Description: Configuration and settings management for the BuffReminder module
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:GetModule("BuffReminder")
if not BuffReminder then return end

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
local type = type
local pairs = pairs
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local DEFAULTS = {
    Enable = true,
    Size = 44,
    Spacing = 6,
    Flash = true,
    Sound = false,
    ClassColor = true,
    CategorySettings = {},
    EntrySettings = {},
    LegacyMigratedFromAuras = false,
    LegacySettingsMigratedV2 = false,
}

local DEFAULT_CATEGORY_SETTINGS = {
    Enable = true,
    InstanceOnly = false,
    Expanded = true,
}

local DEFAULT_ENTRY_SETTINGS = {
    Enable = true,
    InstanceOnly = false,
}

local FALLBACK_CATEGORY_ORDER = { "raid", "targeted", "self" }

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function CopyValues(dest, src, overwrite)
    if type(dest) ~= "table" or type(src) ~= "table" then
        return
    end

    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dest[key]) ~= "table" then
                dest[key] = {}
            end
            CopyValues(dest[key], value, overwrite)
        elseif overwrite or dest[key] == nil then
            dest[key] = value
        end
    end
end

local function GetLegacyConfig()
    local aurasConfig = RefineUI.Config and RefineUI.Config.Auras
    if type(aurasConfig) ~= "table" then
        return nil
    end

    local legacy = aurasConfig.BuffReminder
    if type(legacy) ~= "table" then
        return nil
    end

    return legacy
end

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function BuffReminder:GetConfig()
    RefineUI.Config.BuffReminder = RefineUI.Config.BuffReminder or {}
    local cfg = RefineUI.Config.BuffReminder
    local legacy = GetLegacyConfig()
    if legacy and cfg.LegacyMigratedFromAuras ~= true then
        CopyValues(cfg, legacy, true)
        cfg.LegacyMigratedFromAuras = true
    end

    if cfg.Enable == nil then cfg.Enable = DEFAULTS.Enable end
    if cfg.Size == nil then cfg.Size = DEFAULTS.Size end
    if cfg.Spacing == nil then cfg.Spacing = DEFAULTS.Spacing end
    if cfg.Flash == nil then cfg.Flash = DEFAULTS.Flash end
    if cfg.Sound == nil then cfg.Sound = DEFAULTS.Sound end
    if cfg.ClassColor == nil then cfg.ClassColor = DEFAULTS.ClassColor end
    if cfg.LegacyMigratedFromAuras == nil then cfg.LegacyMigratedFromAuras = DEFAULTS.LegacyMigratedFromAuras end
    if cfg.LegacySettingsMigratedV2 == nil then cfg.LegacySettingsMigratedV2 = DEFAULTS.LegacySettingsMigratedV2 end

    if type(cfg.Enable) ~= "boolean" then
        cfg.Enable = cfg.Enable and true or false
    end
    if type(cfg.Size) ~= "number" then
        cfg.Size = tonumber(cfg.Size) or DEFAULTS.Size
    end
    if cfg.Size < 20 then
        cfg.Size = 20
    elseif cfg.Size > 72 then
        cfg.Size = 72
    end
    if type(cfg.Spacing) ~= "number" then
        cfg.Spacing = tonumber(cfg.Spacing) or DEFAULTS.Spacing
    end
    if cfg.Spacing < 0 then
        cfg.Spacing = 0
    elseif cfg.Spacing > 20 then
        cfg.Spacing = 20
    end
    if type(cfg.Flash) ~= "boolean" then
        cfg.Flash = cfg.Flash and true or false
    end
    if type(cfg.Sound) ~= "boolean" then
        cfg.Sound = cfg.Sound and true or false
    end
    if type(cfg.ClassColor) ~= "boolean" then
        cfg.ClassColor = cfg.ClassColor and true or false
    end
    if type(cfg.LegacyMigratedFromAuras) ~= "boolean" then
        cfg.LegacyMigratedFromAuras = cfg.LegacyMigratedFromAuras and true or false
    end
    if type(cfg.LegacySettingsMigratedV2) ~= "boolean" then
        cfg.LegacySettingsMigratedV2 = cfg.LegacySettingsMigratedV2 and true or false
    end

    if type(cfg.CategorySettings) ~= "table" then
        cfg.CategorySettings = {}
    end
    if type(cfg.EntrySettings) ~= "table" then
        cfg.EntrySettings = {}
    end

    local categoryOrder = self.CATEGORY_ORDER or FALLBACK_CATEGORY_ORDER
    if cfg.LegacySettingsMigratedV2 ~= true then
        if type(cfg.CategoryEnabled) == "table" then
            for i = 1, #categoryOrder do
                local key = categoryOrder[i]
                if cfg.CategorySettings[key] == nil and cfg.CategoryEnabled[key] ~= nil then
                    cfg.CategorySettings[key] = {
                        Enable = cfg.CategoryEnabled[key] ~= false,
                    }
                end
            end
        end
        if type(cfg.EnabledEntries) == "table" then
            for key, value in pairs(cfg.EnabledEntries) do
                if type(cfg.EntrySettings[key]) ~= "table" then
                    cfg.EntrySettings[key] = {}
                end
                if cfg.EntrySettings[key].Enable == nil then
                    cfg.EntrySettings[key].Enable = value ~= false
                end
            end
        end
        cfg.LegacySettingsMigratedV2 = true
    end

    for i = 1, #categoryOrder do
        local category = categoryOrder[i]
        local categorySettings = cfg.CategorySettings[category]
        if type(categorySettings) ~= "table" then
            categorySettings = {}
            cfg.CategorySettings[category] = categorySettings
        end
        for key, defaultValue in pairs(DEFAULT_CATEGORY_SETTINGS) do
            if categorySettings[key] == nil then
                categorySettings[key] = defaultValue
            elseif type(categorySettings[key]) ~= "boolean" then
                categorySettings[key] = categorySettings[key] and true or false
            end
        end
    end

    for key, value in pairs(cfg.EntrySettings) do
        local entrySettings = value
        if type(entrySettings) == "boolean" then
            entrySettings = { Enable = entrySettings }
            cfg.EntrySettings[key] = entrySettings
        elseif type(entrySettings) ~= "table" then
            entrySettings = {}
            cfg.EntrySettings[key] = entrySettings
        end
        for settingKey, defaultValue in pairs(DEFAULT_ENTRY_SETTINGS) do
            if entrySettings[settingKey] == nil then
                entrySettings[settingKey] = defaultValue
            elseif type(entrySettings[settingKey]) ~= "boolean" then
                entrySettings[settingKey] = entrySettings[settingKey] and true or false
            end
        end
    end

    return cfg
end

function BuffReminder:GetCategorySettings(category)
    local cfg = self:GetConfig()
    if type(cfg.CategorySettings[category]) ~= "table" then
        cfg.CategorySettings[category] = {}
    end
    local settings = cfg.CategorySettings[category]
    for key, defaultValue in pairs(DEFAULT_CATEGORY_SETTINGS) do
        if settings[key] == nil then
            settings[key] = defaultValue
        elseif type(settings[key]) ~= "boolean" then
            settings[key] = settings[key] and true or false
        end
    end
    return settings
end

function BuffReminder:GetEntrySettings(entryKey, category)
    local cfg = self:GetConfig()
    if not category then
        category = (self.CATEGORY_ORDER and self.CATEGORY_ORDER[1]) or FALLBACK_CATEGORY_ORDER[1]
    end
    if type(cfg.EntrySettings[entryKey]) ~= "table" then
        cfg.EntrySettings[entryKey] = {}
    end
    local entrySettings = cfg.EntrySettings[entryKey]
    local categorySettings = self:GetCategorySettings(category)
    for key, defaultValue in pairs(DEFAULT_ENTRY_SETTINGS) do
        if entrySettings[key] == nil then
            if key == "Enable" then
                entrySettings[key] = categorySettings.Enable ~= false
            elseif key == "InstanceOnly" then
                entrySettings[key] = categorySettings.InstanceOnly == true
            else
                entrySettings[key] = defaultValue
            end
        elseif type(entrySettings[key]) ~= "boolean" then
            entrySettings[key] = entrySettings[key] and true or false
        end
    end
    return entrySettings
end

function BuffReminder:ApplyCategorySettingToEntries(category, settingKey, value)
    local entries = self:GetConfigurableEntries(category)
    local checked = value and true or false
    for i = 1, #entries do
        local entry = entries[i]
        if entry and entry.key then
            local entrySettings = self:GetEntrySettings(entry.key, category)
            entrySettings[settingKey] = checked
        end
    end
end
