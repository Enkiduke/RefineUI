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
local type, pairs = type, pairs
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
        -- Compatibility alias for existing call sites.
        RefineUI.Defaults = RefineUI.DefaultConfig
    end
    
    -- Version Check Logic
    -- Determine current code version
    local currentVersion = (RefineUI.DefaultConfig and RefineUI.DefaultConfig.Version) or 1
    -- Determine stored DB version (default to 0 if missing)
    local storedVersion = profile.Version or 0
    
    -- If versions differ, wipe profile (except Version/Installed status optional?)
    -- User requested: "Clear out and re-establish the defaults"
    if storedVersion ~= currentVersion then
        -- Preserve Installed flag if we want to skip the "Welcome" wizard?
        -- User said "re-initiate the install", so wiping Everything is safer.
        -- BUT if we wipe "Installed", the wizard pops up.
        -- Let's wipe everything to be clean.
        
        RefineUI:Print("Config version changed (v" .. storedVersion .. " -> v" .. currentVersion .. "). Resetting profile to defaults.")
        wipe(profile)
        
        -- Update stored version
        profile.Version = currentVersion
    end

    -- Merge logic: "Copy-on-Load"
    RefineUI:CopyDefaults(RefineUI.DefaultConfig, profile)

    if not IsValidLayoutTierKey(profile.ActiveLayoutTier) then
        profile.ActiveLayoutTier = RefineUI:GetLayoutTier()
    end

    EnsureLayoutProfiles(profile)
    
    -- Runtime profile object + stable RefineUI.Config proxy.
    BindRuntimeConfig(profile)
end

