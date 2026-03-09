----------------------------------------------------------------------------------------
-- CDM Component: CooldownCatalog
-- Description: Read-only cooldown metadata catalog backed by C_CooldownViewer.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

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
local _G = _G
local type = type
local pcall = pcall
local wipe = _G.wipe or table.wipe
local bitband = bit and bit.band

local C_CooldownViewer = C_CooldownViewer
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CATEGORY = CDM.BLIZZARD_CATEGORY
local HIDE_AURA_FLAG = Enum and Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideAura or 1

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local cooldownInfoCache = {}
local categorySetCache = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function CopyArray(source)
    if type(source) ~= "table" then
        return {}
    end

    local copy = {}
    for i = 1, #source do
        copy[i] = source[i]
    end
    return copy
end

local function CopyNumericArray(source)
    if type(source) ~= "table" then
        return {}
    end

    local copy = {}
    for i = 1, #source do
        local value = source[i]
        if type(value) == "number" and not IsSecret(value) and value > 0 then
            copy[#copy + 1] = value
        end
    end
    return copy
end

local function CopyCooldownInfo(info, fallbackCooldownID)
    if type(info) ~= "table" then
        return nil
    end

    local copy = {}

    local cooldownID = info.cooldownID
    if type(cooldownID) ~= "number" or IsSecret(cooldownID) or cooldownID <= 0 then
        cooldownID = fallbackCooldownID
    end
    if type(cooldownID) ~= "number" or cooldownID <= 0 then
        return nil
    end

    copy.cooldownID = cooldownID

    local spellID = info.spellID
    if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 then
        copy.spellID = spellID
    else
        copy.spellID = nil
    end

    local overrideSpellID = info.overrideSpellID
    if type(overrideSpellID) == "number" and not IsSecret(overrideSpellID) and overrideSpellID > 0 then
        copy.overrideSpellID = overrideSpellID
    end

    local overrideTooltipSpellID = info.overrideTooltipSpellID
    if type(overrideTooltipSpellID) == "number" and not IsSecret(overrideTooltipSpellID) and overrideTooltipSpellID > 0 then
        copy.overrideTooltipSpellID = overrideTooltipSpellID
    end

    copy.linkedSpellIDs = CopyNumericArray(info.linkedSpellIDs)

    local selfAura = info.selfAura
    if type(selfAura) == "boolean" and not IsSecret(selfAura) then
        copy.selfAura = selfAura
    end

    local hasAura = info.hasAura
    if type(hasAura) == "boolean" and not IsSecret(hasAura) then
        copy.hasAura = hasAura
    end

    local charges = info.charges
    if type(charges) == "boolean" and not IsSecret(charges) then
        copy.charges = charges
    end

    local isKnown = info.isKnown
    if type(isKnown) == "boolean" and not IsSecret(isKnown) then
        copy.isKnown = isKnown
    end

    local flags = info.flags
    if type(flags) == "number" and not IsSecret(flags) then
        copy.flags = flags
    end

    local category = info.category
    if type(category) == "number" and not IsSecret(category) then
        copy.category = category
    end

    if copy.spellID == nil
        and copy.overrideSpellID == nil
        and copy.overrideTooltipSpellID == nil
        and #copy.linkedSpellIDs == 0
    then
        return nil
    end

    return copy
end

local function GetCooldownInfoFromAPI(cooldownID)
    if not C_CooldownViewer or type(C_CooldownViewer.GetCooldownViewerCooldownInfo) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
    if ok and type(info) == "table" then
        return info
    end

    return nil
end

local function GetCooldownInfoFromProvider(cooldownID)
    local provider = _G.CooldownViewerDataProvider
    if not provider and _G.CooldownViewerSettings and type(_G.CooldownViewerSettings.GetDataProvider) == "function" then
        provider = _G.CooldownViewerSettings:GetDataProvider()
    end
    if not provider or type(provider.GetCooldownInfoForID) ~= "function" then
        return nil
    end

    local ok, info = pcall(provider.GetCooldownInfoForID, provider, cooldownID)
    if ok and type(info) == "table" then
        return info
    end

    return nil
end

local function HasFlag(flags, flag)
    if IsSecret(flags) or type(flags) ~= "number" or type(flag) ~= "number" then
        return false
    end

    if _G.FlagsUtil and type(_G.FlagsUtil.IsSet) == "function" then
        return _G.FlagsUtil.IsSet(flags, flag)
    end

    if bitband then
        return bitband(flags, flag) == flag
    end

    return false
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InvalidateCooldownCatalog()
    if wipe then
        wipe(cooldownInfoCache)
        wipe(categorySetCache)
        return
    end

    for key in pairs(cooldownInfoCache) do
        cooldownInfoCache[key] = nil
    end
    for key in pairs(categorySetCache) do
        categorySetCache[key] = nil
    end
end


function CDM:GetCooldownCatalogInfo(cooldownID)
    if type(cooldownID) ~= "number" or cooldownID <= 0 then
        return nil
    end

    local cached = cooldownInfoCache[cooldownID]
    if type(cached) == "table" then
        return cached
    end
    if cached == false then
        cached = nil
    end

    local info = GetCooldownInfoFromProvider(cooldownID) or GetCooldownInfoFromAPI(cooldownID)
    local copied = CopyCooldownInfo(info, cooldownID)
    if copied then
        cooldownInfoCache[cooldownID] = copied
        return copied
    end
    if cached then
        return cached
    end

    if cooldownInfoCache[cooldownID] == nil then
        cooldownInfoCache[cooldownID] = false
    end

    return nil
end


function CDM:GetCooldownInfo(cooldownID)
    return self:GetCooldownCatalogInfo(cooldownID)
end


function CDM:GetCooldownCategorySet(category, includeUnlearned)
    local cacheKey = tostring(category) .. ":" .. (includeUnlearned and "1" or "0")
    local cached = categorySetCache[cacheKey]
    if type(cached) == "table" then
        return cached
    end

    if not C_CooldownViewer or type(C_CooldownViewer.GetCooldownViewerCategorySet) ~= "function" then
        categorySetCache[cacheKey] = categorySetCache[cacheKey] or {}
        return categorySetCache[cacheKey]
    end

    local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, includeUnlearned and true or false)
    if ok and type(cooldownIDs) == "table" then
        local copied = CopyNumericArray(cooldownIDs)
        if #copied > 0 then
            categorySetCache[cacheKey] = copied
            return copied
        end
    end

    if type(categorySetCache[cacheKey]) ~= "table" then
        categorySetCache[cacheKey] = {}
    end
    return categorySetCache[cacheKey]
end


function CDM:GetTrackedAuraCategoryList()
    return {
        CATEGORY.TRACKED_BUFF,
        CATEGORY.TRACKED_BAR,
        CATEGORY.HIDDEN_AURA,
    }
end


function CDM:CanUseAuraForCooldown(info)
    if type(info) ~= "table" then
        return false
    end

    if info.hasAura == true then
        return true
    end

    if type(info.selfAura) == "boolean" then
        return true
    end

    local associatedSpellIDs = self:GetAssociatedSpellIDs(info)
    if #associatedSpellIDs > 0 then
        return true
    end

    return not HasFlag(info.flags, HIDE_AURA_FLAG)
end


function CDM:GetCooldownChargeSpellID(info)
    if type(info) ~= "table" then
        return nil
    end

    local overrideSpellID = info.overrideSpellID
    if type(overrideSpellID) == "number" and not IsSecret(overrideSpellID) and overrideSpellID > 0 then
        return overrideSpellID
    end

    local spellID = info.spellID
    if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 then
        return spellID
    end

    return nil
end


function CDM:GetAssociatedSpellIDs(info)
    local ordered = {}
    local seen = {}
    if type(info) ~= "table" then
        return ordered
    end

    local function AddSpellID(spellID)
        if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end

    AddSpellID(info.overrideTooltipSpellID)
    AddSpellID(info.overrideSpellID)
    AddSpellID(info.spellID)

    if type(info.linkedSpellIDs) == "table" then
        for i = 1, #info.linkedSpellIDs do
            AddSpellID(info.linkedSpellIDs[i])
        end
    end

    return ordered
end


function CDM:WarmCooldownCatalog(includeUnlearned)
    local categoryList = self:GetTrackedAuraCategoryList()
    for i = 1, #categoryList do
        local cooldownIDs = self:GetCooldownCategorySet(categoryList[i], includeUnlearned and true or false)
        for n = 1, #cooldownIDs do
            self:GetCooldownCatalogInfo(cooldownIDs[n])
        end
    end
end
