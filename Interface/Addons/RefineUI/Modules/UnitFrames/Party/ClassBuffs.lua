----------------------------------------------------------------------------------------
-- UnitFrames Party: Class Buffs
-- Description: Class healer-buff tracking data, config accessors, sort/order logic.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
local UF = RefineUI.UnitFrames
local P = UF._party
if not P then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local tostring = tostring
local tonumber = tonumber
local GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local GetTime = GetTime
local issecretvalue = _G.issecretvalue

local IsUnreadableNumber = P.IsUnreadableNumber

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local QUESTION_MARK_ICON = 134400

local IMPORTANT_SORT_MODE = {
    MANUAL = "MANUAL",
    ASCENDING = "ASCENDING",
    DESCENDING = "DESCENDING",
}

local CLASS_HEALER_BUFFS = {
    EVOKER = {
        { key = "evoker_dream_breath", spellIDs = { 355941 } },
        { key = "evoker_dream_flight", spellIDs = { 363502 } },
        { key = "evoker_echo", spellIDs = { 364343 } },
        { key = "evoker_reversion", spellIDs = { 366155 } },
        { key = "evoker_echo_reversion", spellIDs = { 367364 } },
        { key = "evoker_lifebind", spellIDs = { 373267 } },
        { key = "evoker_echo_dream_breath", spellIDs = { 376788 } },
        { key = "evoker_blistering_scales", spellIDs = { 360827 } },
        { key = "evoker_ebon_might", spellIDs = { 395152 } },
        { key = "evoker_prescience", spellIDs = { 410089 } },
        { key = "evoker_infernos_blessing", spellIDs = { 410263 } },
        { key = "evoker_symbiotic_bloom", spellIDs = { 410686 } },
        { key = "evoker_shifting_sands", spellIDs = { 413984 } },
    },
    DRUID = {
        { key = "druid_rejuvenation", spellIDs = { 774 } },
        { key = "druid_regrowth", spellIDs = { 8936 } },
        { key = "druid_lifebloom", spellIDs = { 33763 } },
        { key = "druid_wild_growth", spellIDs = { 48438 } },
        { key = "druid_germination", spellIDs = { 155777 } },
    },
    PRIEST = {
        { key = "priest_power_word_shield", spellIDs = { 17 } },
        { key = "priest_atonement", spellIDs = { 194384 } },
        { key = "priest_void_shield", spellIDs = { 1253593 } },
        { key = "priest_renew", spellIDs = { 139 } },
        { key = "priest_prayer_of_mending", spellIDs = { 41635 } },
        { key = "priest_echo_of_light", spellIDs = { 77489 } },
    },
    MONK = {
        { key = "monk_soothing_mist", spellIDs = { 115175 } },
        { key = "monk_renewing_mist", spellIDs = { 119611 } },
        { key = "monk_enveloping_mist", spellIDs = { 124682 } },
        { key = "monk_aspect_of_harmony", spellIDs = { 450769 } },
    },
    SHAMAN = {
        { key = "shaman_earth_shield", spellIDs = { 974, 383648 } },
        { key = "shaman_riptide", spellIDs = { 61295 } },
    },
    PALADIN = {
        { key = "paladin_beacon_of_light", spellIDs = { 53563 } },
        { key = "paladin_eternal_flame", spellIDs = { 156322 } },
        { key = "paladin_beacon_of_faith", spellIDs = { 156910 } },
        { key = "paladin_beacon_of_the_savior", spellIDs = { 1244893 } },
        { key = "paladin_beacon_of_virtue", spellIDs = { 200025 } },
    },
}

----------------------------------------------------------------------------------------
-- Buff Entry Builder
----------------------------------------------------------------------------------------
local PlayerClassBuffEntries
local PlayerClassBuffLookup

local function ClampColorComponent(value, fallback)
    local n = tonumber(value)
    if type(n) ~= "number" then
        return fallback
    end
    if n < 0 then
        return 0
    elseif n > 1 then
        return 1
    end
    return n
end

local function GetDefaultTrackedBuffColorRGBA()
    local color = Config and Config.Auras and Config.Auras.TimedBuffBorderColor
    if type(color) == "table" then
        return ClampColorComponent(color[1], 0.12), ClampColorComponent(color[2], 0.9), ClampColorComponent(color[3], 0.12), 1
    end
    return 0.12, 0.9, 0.12, 1
end

local function NormalizeTrackedBuffColorTable(color)
    local r, g, b, a = GetDefaultTrackedBuffColorRGBA()
    if type(color) ~= "table" then
        return { r, g, b, a }
    end
    return {
        ClampColorComponent(color[1], r),
        ClampColorComponent(color[2], g),
        ClampColorComponent(color[3], b),
        ClampColorComponent(color[4], a),
    }
end

local function GetSpellNameAndIcon(spellID)
    if type(GetSpellInfo) == "function" then
        local info = GetSpellInfo(spellID)
        if type(info) == "table" then
            local name = info.name or ("Spell " .. tostring(spellID))
            local icon = info.iconID or info.originalIconID or QUESTION_MARK_ICON
            return name, icon
        end
    end
    return "Spell " .. tostring(spellID), QUESTION_MARK_ICON
end

local function BuildPlayerClassBuffEntries()
    if PlayerClassBuffEntries and PlayerClassBuffLookup then
        return PlayerClassBuffEntries, PlayerClassBuffLookup
    end

    local class = RefineUI.MyClass
    local source = CLASS_HEALER_BUFFS[class] or {}
    local entries = {}
    local lookup = {}

    for i = 1, #source do
        local template = source[i]
        local spellIDs = template and template.spellIDs
        if type(spellIDs) == "table" and #spellIDs > 0 then
            local primarySpellID = spellIDs[1]
            local name, icon = GetSpellNameAndIcon(primarySpellID)
            local entry = {
                key = template.key,
                spellIDs = spellIDs,
                primarySpellID = primarySpellID,
                name = name,
                icon = icon,
            }
            entries[#entries + 1] = entry

            for spellIndex = 1, #spellIDs do
                local id = spellIDs[spellIndex]
                if type(id) == "number" then
                    lookup[id] = entry
                end
            end
        end
    end

    PlayerClassBuffEntries = entries
    PlayerClassBuffLookup = lookup
    return PlayerClassBuffEntries, PlayerClassBuffLookup
end

local function GetPlayerClassBuffEntries()
    local entries = BuildPlayerClassBuffEntries()
    return entries
end

local function GetTrackedClassBuffEntryBySpellID(spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    if issecretvalue and issecretvalue(spellID) then
        return nil
    end
    local _, lookup = BuildPlayerClassBuffEntries()
    return lookup[spellID]
end

----------------------------------------------------------------------------------------
-- Config Accessors
----------------------------------------------------------------------------------------
local function GetClassBuffConfig()
    if not Config or type(Config.UnitFrames) ~= "table" then
        return nil
    end

    local cfg = Config.UnitFrames.ClassBuffs
    if type(cfg) ~= "table" then
        cfg = {}
        Config.UnitFrames.ClassBuffs = cfg
    end

    if type(cfg.SpellSettings) ~= "table" then
        cfg.SpellSettings = {}
    end

    if type(cfg.ManualOrder) ~= "table" then
        cfg.ManualOrder = {}
    end

    if cfg.ImportantSort ~= IMPORTANT_SORT_MODE.MANUAL
        and cfg.ImportantSort ~= IMPORTANT_SORT_MODE.ASCENDING
        and cfg.ImportantSort ~= IMPORTANT_SORT_MODE.DESCENDING then
        cfg.ImportantSort = IMPORTANT_SORT_MODE.MANUAL
    end

    return cfg
end

local function EnsureManualOrderIncludesAllEntries()
    local cfg = GetClassBuffConfig()
    if not cfg then return end

    local entries = GetPlayerClassBuffEntries()
    local seen = {}
    local ordered = {}

    for i = 1, #cfg.ManualOrder do
        local key = cfg.ManualOrder[i]
        if type(key) == "string" and not seen[key] then
            seen[key] = true
            ordered[#ordered + 1] = key
        end
    end

    for i = 1, #entries do
        local key = entries[i].key
        if key and not seen[key] then
            seen[key] = true
            ordered[#ordered + 1] = key
        end
    end

    cfg.ManualOrder = ordered
end

local function GetTrackedClassBuffSettings(entryKey)
    local cfg = GetClassBuffConfig()
    if not cfg or type(entryKey) ~= "string" or entryKey == "" then
        return nil
    end

    local settings = cfg.SpellSettings[entryKey]
    if type(settings) ~= "table" then
        settings = {}
        cfg.SpellSettings[entryKey] = settings
    end

    if settings.Important == nil then
        settings.Important = false
    else
        settings.Important = settings.Important and true or false
    end

    if settings.FrameColor == nil then
        settings.FrameColor = false
    else
        settings.FrameColor = settings.FrameColor and true or false
    end

    settings.BorderColor = NormalizeTrackedBuffColorTable(settings.BorderColor)
    return settings
end

local function GetTrackedClassBuffSortMode()
    local cfg = GetClassBuffConfig()
    if not cfg then
        return IMPORTANT_SORT_MODE.MANUAL
    end
    return cfg.ImportantSort
end

local function SetTrackedClassBuffSortMode(mode)
    local cfg = GetClassBuffConfig()
    if not cfg then
        return
    end

    if mode ~= IMPORTANT_SORT_MODE.MANUAL
        and mode ~= IMPORTANT_SORT_MODE.ASCENDING
        and mode ~= IMPORTANT_SORT_MODE.DESCENDING then
        mode = IMPORTANT_SORT_MODE.MANUAL
    end

    cfg.ImportantSort = mode
end

local function GetTrackedClassBuffColor(entryKey)
    local settings = GetTrackedClassBuffSettings(entryKey)
    if not settings then
        return GetDefaultTrackedBuffColorRGBA()
    end
    local color = settings.BorderColor
    return color[1], color[2], color[3], color[4] or 1
end

local function GetTrackedClassBuffManualOrderRank(entryKey)
    local cfg = GetClassBuffConfig()
    if not cfg or type(entryKey) ~= "string" then
        return 9999
    end

    for i = 1, #cfg.ManualOrder do
        if cfg.ManualOrder[i] == entryKey then
            return i
        end
    end

    return 9999
end

local function GetConfiguredBuffBorderColorRGB()
    local r, g, b = GetDefaultTrackedBuffColorRGBA()
    return r, g, b
end

----------------------------------------------------------------------------------------
-- Aura Duration Helper
----------------------------------------------------------------------------------------
local function GetAuraRemainingSecondsFromData(auraData)
    if not auraData then
        return nil
    end

    local expirationTime = auraData.auraExpirationTime
    local duration = auraData.auraDuration
    if IsUnreadableNumber(expirationTime) or IsUnreadableNumber(duration) then
        return nil
    end
    if type(expirationTime) ~= "number" or expirationTime <= 0 then
        return nil
    end

    local now = type(GetTime) == "function" and GetTime() or 0
    local remaining = expirationTime - now
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.QUESTION_MARK_ICON                    = QUESTION_MARK_ICON
P.IMPORTANT_SORT_MODE                   = IMPORTANT_SORT_MODE

P.GetPlayerClassBuffEntries             = GetPlayerClassBuffEntries
P.GetTrackedClassBuffEntryBySpellID     = GetTrackedClassBuffEntryBySpellID
P.GetClassBuffConfig                    = GetClassBuffConfig
P.EnsureManualOrderIncludesAllEntries   = EnsureManualOrderIncludesAllEntries
P.GetTrackedClassBuffSettings           = GetTrackedClassBuffSettings
P.GetTrackedClassBuffSortMode           = GetTrackedClassBuffSortMode
P.SetTrackedClassBuffSortMode           = SetTrackedClassBuffSortMode
P.GetTrackedClassBuffColor              = GetTrackedClassBuffColor
P.GetTrackedClassBuffManualOrderRank    = GetTrackedClassBuffManualOrderRank
P.GetConfiguredBuffBorderColorRGB       = GetConfiguredBuffBorderColorRGB

P.GetDefaultTrackedBuffColorRGBA        = GetDefaultTrackedBuffColorRGBA
P.NormalizeTrackedBuffColorTable        = NormalizeTrackedBuffColorTable
P.ClampColorComponent                   = ClampColorComponent
P.GetAuraRemainingSecondsFromData       = GetAuraRemainingSecondsFromData
