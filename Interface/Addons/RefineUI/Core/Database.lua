----------------------------------------------------------------------------------------
-- RefineUI Database
-- Description: Handles SavedVariables, Profiles, and Default merging.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local GetRealmName = GetRealmName
local UnitName = UnitName
local type, pairs, next = type, pairs, next
local ReloadUI = ReloadUI
local wipe = wipe

----------------------------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------------------------
local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local dest = {}
    for k, v in pairs(src) do
        dest[k] = DeepCopy(v)
    end
    return dest
end

local function CopyInto(dest, src)
    if type(dest) ~= "table" then
        dest = {}
    else
        wipe(dest)
    end

    if type(src) ~= "table" then
        return dest
    end

    for k, v in pairs(src) do
        dest[k] = DeepCopy(v)
    end

    return dest
end

local function IsValidLayoutTierKey(tierKey)
    return type(tierKey) == "string"
        and type(RefineUI.ManagedLayoutNames) == "table"
        and RefineUI.ManagedLayoutNames[tierKey] ~= nil
end

function RefineUI:GetStoredLayoutTier(profile)
    local db = profile or self.DB
    local storedTier = type(db) == "table" and db.ActiveLayoutTier or nil
    if IsValidLayoutTierKey(storedTier) then
        return storedTier
    end

    return self.ActiveLayoutTier or self:GetLayoutTier()
end

function RefineUI:SetStoredLayoutTier(tierKey, profile)
    local db = profile or self.DB
    local resolvedTier = IsValidLayoutTierKey(tierKey) and tierKey or self:GetLayoutTier()

    if type(db) == "table" then
        db.ActiveLayoutTier = resolvedTier
    end

    self.ActiveLayoutTier = resolvedTier
    return resolvedTier
end

local function EnsureLayoutProfiles(profile)
    profile.LayoutProfiles = profile.LayoutProfiles or {}

    local layoutProfiles = profile.LayoutProfiles
    local legacyPositions = type(profile.Positions) == "table" and profile.Positions or nil
    local activeTier = RefineUI:GetStoredLayoutTier(profile)

    for _, tierKey in pairs(RefineUI.LayoutTier or {}) do
        layoutProfiles[tierKey] = layoutProfiles[tierKey] or {}

        local tierProfile = layoutProfiles[tierKey]
        local defaultPositions = RefineUI:GetDefaultPositionsForTier(tierKey)

        if type(tierProfile.Positions) ~= "table" then
            if legacyPositions and tierKey == activeTier then
                tierProfile.Positions = DeepCopy(legacyPositions)
                RefineUI:CopyDefaults(defaultPositions, tierProfile.Positions)
            else
                tierProfile.Positions = DeepCopy(defaultPositions)
            end
        else
            RefineUI:CopyDefaults(defaultPositions, tierProfile.Positions)
        end
    end

    return layoutProfiles
end

function RefineUI:BindActiveLayoutProfile(profile, tierKey)
    local db = profile or self.DB
    if type(db) ~= "table" then
        return nil
    end

    local resolvedTier = self:SetStoredLayoutTier(tierKey, db)
    local layoutProfiles = EnsureLayoutProfiles(db)
    local layoutProfile = layoutProfiles[resolvedTier]
    local runtimePositions = db.Positions

    if type(runtimePositions) ~= "table" then
        runtimePositions = {}
        db.Positions = runtimePositions
    end

    CopyInto(runtimePositions, layoutProfile and layoutProfile.Positions or {})
    self.Positions = runtimePositions

    return layoutProfile, resolvedTier
end

local function BindRuntimeConfig(profile)
    local runtimeConfig = RefineUI.Config or {}

    -- Keep the same table identity so modules that cached
    -- `local C = RefineUI.Config` continue to read/write runtime values.
    setmetatable(runtimeConfig, nil)
    wipe(runtimeConfig)
    setmetatable(runtimeConfig, {
        __index = profile,
        __newindex = profile,
    })

    RefineUI.Config = runtimeConfig
    RefineUI.DB = profile
    RefineUI:BindActiveLayoutProfile(profile)
end

-- Recursive copy of defaults
function RefineUI:CopyDefaults(src, dest)
    if type(src) ~= "table" then return end
    if type(dest) ~= "table" then return end

    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = dest[k] or {}
            RefineUI:CopyDefaults(v, dest[k])
        elseif dest[k] == nil then
            dest[k] = v -- Copy value if missing
        end
    end
end

----------------------------------------------------------------------------------------
-- Default Stripping
----------------------------------------------------------------------------------------
-- Profiles are saved with only the values that differ from code defaults.
-- InitializeDatabase refills the rest on load, so default changes reach every character.
local function IsDeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for k, v in pairs(a) do
        if not IsDeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Sequence defaults (colors, offsets, positions) are compared whole so a partial
-- tuple is never saved; keyed tables are stripped per key.
local function StripDefaults(saved, defaults)
    for k, v in pairs(saved) do
        local default = defaults[k]
        if type(v) == "table" and type(default) == "table" and default[1] == nil then
            StripDefaults(v, default)
            if next(v) == nil then
                saved[k] = nil
            end
        elseif IsDeepEqual(v, default) then
            saved[k] = nil
        end
    end
end

-- Strips a copy so the live runtime config stays whole for code that runs after logout.
local function StripProfileDefaults()
    if type(RefineUI.DB) ~= "table" or type(RefineUI.DefaultConfig) ~= "table" then return end
    local profile = DeepCopy(RefineUI.DB)
    _G.RefineDB[GetRealmName()][UnitName("player")] = profile

    -- MigrateProfile reads Version before defaults are merged, so it must stay saved.
    local version = profile.Version
    StripDefaults(profile, RefineUI.DefaultConfig)
    profile.Version = version

    -- BindActiveLayoutProfile rebuilds the runtime Positions copy from the active tier.
    profile.Positions = nil

    local layoutProfiles = profile.LayoutProfiles
    if type(layoutProfiles) ~= "table" then return end

    for tierKey, tierProfile in pairs(layoutProfiles) do
        local defaultPositions = RefineUI.DefaultPositionsByTier and RefineUI.DefaultPositionsByTier[tierKey]
        if type(tierProfile) == "table" and type(tierProfile.Positions) == "table" and type(defaultPositions) == "table" then
            StripDefaults(tierProfile.Positions, defaultPositions)
            if next(tierProfile.Positions) == nil then
                tierProfile.Positions = nil
            end
            if next(tierProfile) == nil then
                layoutProfiles[tierKey] = nil
            end
        end
    end

    if next(layoutProfiles) == nil then
        profile.LayoutProfiles = nil
    end
end

function RefineUI:ResetProfile()
    local realm = GetRealmName()
    local name = UnitName("player")
    
    if _G.RefineDB[realm] and _G.RefineDB[realm][name] then
        _G.RefineDB[realm][name] = nil
    end
    
    RefineUI:Print("Profile reset. Reloading UI...")
    ReloadUI()
end

----------------------------------------------------------------------------------------
-- Migrations
----------------------------------------------------------------------------------------
-- Keyed by the config version (C.Version) they upgrade a profile to. Each runs once,
-- in order, on the saved profile before defaults are merged. Default changes need no
-- migration (profiles only save overrides); to change a saved setting's shape, bump
-- C.Version and add a migration here instead of resetting the profile.
local MIGRATIONS = {
    -- Profiles saved before versioning existed have no known shape.
    [1] = function(profile)
        wipe(profile)
    end,
    -- ClickCasting was renamed MouseoverCasting.
    [2] = function(profile)
        profile.MouseoverCasting = profile.ClickCasting
        profile.ClickCasting = nil
        local moduleState = profile.ModuleState
        if moduleState then
            moduleState.MouseoverCasting = moduleState.ClickCasting
            moduleState.ClickCasting = nil
        end
    end,
}

local function MigrateProfile(profile, currentVersion)
    local storedVersion = profile.Version or 0
    if storedVersion == currentVersion then
        return
    end

    if storedVersion > currentVersion then
        -- Saved by a newer build; its shape is unknown to this one.
        RefineUI:Print("Config version v" .. storedVersion .. " is newer than v" .. currentVersion .. ". Resetting profile to defaults.")
        wipe(profile)
    else
        for version = storedVersion + 1, currentVersion do
            local migrate = MIGRATIONS[version]
            if migrate then
                migrate(profile)
            end
        end
    end

    profile.Version = currentVersion
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
-- Global SavedVariable
_G.RefineDB = _G.RefineDB or {}

function RefineUI:InitializeDatabase()
    local realm = GetRealmName()
    local name = UnitName("player")

    -- Ensure Realm/Char tables exist
    _G.RefineDB[realm] = _G.RefineDB[realm] or {}
    _G.RefineDB[realm][name] = _G.RefineDB[realm][name] or {}

    -- The SavedVars table for this character
    local profile = _G.RefineDB[realm][name]
    
    -- Config table populated by Config/*.lua defaults.
    RefineUI.Config = RefineUI.Config or {}
    
    -- Preserve immutable code-defined defaults for merge/reset operations.
    if not RefineUI.DefaultConfig then
        RefineUI.DefaultConfig = DeepCopy(RefineUI.Config)
    end
    
    local currentVersion = (RefineUI.DefaultConfig and RefineUI.DefaultConfig.Version) or 1
    MigrateProfile(profile, currentVersion)

    -- Merge logic: "Copy-on-Load"
    RefineUI:CopyDefaults(RefineUI.DefaultConfig, profile)

    if not IsValidLayoutTierKey(profile.ActiveLayoutTier) then
        profile.ActiveLayoutTier = RefineUI:GetLayoutTier()
    end

    EnsureLayoutProfiles(profile)
    
    -- Runtime profile object + stable RefineUI.Config proxy.
    BindRuntimeConfig(profile)

    -- PLAYER_LOGOUT also fires on /reload, just before SavedVariables are written.
    RefineUI:RegisterEventCallback("PLAYER_LOGOUT", StripProfileDefaults, "Core:Database:StripDefaults")
end

