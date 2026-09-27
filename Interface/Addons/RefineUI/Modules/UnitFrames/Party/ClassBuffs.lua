----------------------------------------------------------------------------------------
-- UnitFrames Party: Class Buffs
-- Description: Tracked group-buff data and settings (Important / Tracked / Untracked,
--              manual order, border color, frame color).
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

local CDM = RefineUI:GetModule("CDM")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local ipairs = ipairs
local tostring = tostring
local tinsert = table.insert
local tremove = table.remove
local tsort = table.sort
local band = bit.band
local IsPlayerSpell = IsPlayerSpell

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local QUESTION_MARK_ICON = 134400

local SECTION = {
    IMPORTANT = "Important",
    TRACKED = "Tracked",
    UNTRACKED = "Untracked",
}

local CLASS_GROUP_BUFFS = {
    EVOKER = {
        { key = "evoker_dream_breath", spellIDs = { 355941 }, knownSpellIDs = { 355936 } },
        { key = "evoker_dream_flight", spellIDs = { 363502 }, knownSpellIDs = { 359816 } },
        { key = "evoker_echo", spellIDs = { 364343 } },
        { key = "evoker_reversion", spellIDs = { 366155 } },
        { key = "evoker_echo_reversion", spellIDs = { 367364 }, knownSpellIDs = { 364343 } },
        { key = "evoker_lifebind", spellIDs = { 373267 }, knownSpellIDs = { 373270, 373267 } },
        { key = "evoker_echo_dream_breath", spellIDs = { 376788 }, knownSpellIDs = { 364343 } },
        { key = "evoker_blistering_scales", spellIDs = { 360827 } },
        { key = "evoker_ebon_might", spellIDs = { 395152 } },
        { key = "evoker_prescience", spellIDs = { 410089 }, knownSpellIDs = { 409311 } },
        { key = "evoker_infernos_blessing", spellIDs = { 410263 }, knownSpellIDs = { 410261 } },
        { key = "evoker_symbiotic_bloom", spellIDs = { 410686 } },
        { key = "evoker_shifting_sands", spellIDs = { 413984 } },
        { key = "evoker_source_of_magic", spellIDs = { 369459, 1289630 } },
        { key = "evoker_time_dilation", spellIDs = { 357170 } },
        { key = "evoker_spatial_paradox", spellIDs = { 406732 } },
    },
    DRUID = {
        { key = "druid_rejuvenation", spellIDs = { 774 } },
        { key = "druid_regrowth", spellIDs = { 8936 } },
        { key = "druid_lifebloom", spellIDs = { 33763 } },
        { key = "druid_wild_growth", spellIDs = { 48438 } },
        { key = "druid_germination", spellIDs = { 155777 } },
        { key = "druid_innervate", spellIDs = { 29166 } },
        { key = "druid_ironbark", spellIDs = { 102342 } },
    },
    PRIEST = {
        { key = "priest_power_word_shield", spellIDs = { 17 } },
        { key = "priest_atonement", spellIDs = { 194384 } },
        { key = "priest_void_shield", spellIDs = { 1253593 } },
        { key = "priest_renew", spellIDs = { 139 } },
        { key = "priest_prayer_of_mending", spellIDs = { 41635 }, knownSpellIDs = { 33076 } },
        { key = "priest_echo_of_light", spellIDs = { 77489 }, knownSpellIDs = { 77485 } },
        { key = "priest_power_infusion", spellIDs = { 10060 } },
        { key = "priest_pain_suppression", spellIDs = { 33206 } },
        { key = "priest_guardian_spirit", spellIDs = { 47788 } },
        { key = "priest_angelic_feather", spellIDs = { 121557, 121536 } },
    },
    MONK = {
        { key = "monk_soothing_mist", spellIDs = { 115175 } },
        { key = "monk_renewing_mist", spellIDs = { 119611 }, knownSpellIDs = { 115151 } },
        { key = "monk_enveloping_mist", spellIDs = { 124682 } },
        { key = "monk_aspect_of_harmony", spellIDs = { 450769 }, knownSpellIDs = { 450508 } },
        { key = "monk_life_cocoon", spellIDs = { 116849 } },
        { key = "monk_tigers_lust", spellIDs = { 116841 } },
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
        { key = "paladin_blessing_of_freedom", spellIDs = { 1044 } },
        { key = "paladin_blessing_of_protection", spellIDs = { 1022 } },
        { key = "paladin_blessing_of_spellwarding", spellIDs = { 204018 } },
        { key = "paladin_blessing_of_sacrifice", spellIDs = { 6940 } },
        { key = "paladin_holy_bulwark", spellIDs = { 432496, 432459, 432607 } },
        { key = "paladin_sacred_weapon", spellIDs = { 432502 } },
    },
    WARRIOR = {
        { key = "warrior_intervene", spellIDs = { 3411 } },
    },
    WARLOCK = {
        { key = "warlock_soulstone", spellIDs = { 20707 } },
    },
    HUNTER = {
        { key = "hunter_roar_of_sacrifice", spellIDs = { 53480 } },
    },
}

----------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------
-- The previous module saved the generic buff color on every entry; treat it as unset
-- so the per-ability defaults apply.
local function IsLegacyDefaultColor(color)
    local legacy = Config.Auras.TimedBuffBorderColor
    return color[1] == legacy[1] and color[2] == legacy[2] and color[3] == legacy[3]
end

local function GetSettings(entry)
    local spellSettings = Config.UnitFrames.ClassBuffs.SpellSettings
    local settings = spellSettings[entry.key]
    if not settings then
        settings = { Untracked = entry.hideByDefault }
        spellSettings[entry.key] = settings
    elseif settings.BorderColor and IsLegacyDefaultColor(settings.BorderColor) then
        settings.BorderColor = nil
    end
    return settings
end

local function GetDefaultBorderColor(entry)
    for _, spellID in ipairs(entry.spellIDs) do
        local color = CDM:GetDefaultAbilityBorderColor(nil, spellID)
        if color then
            return color
        end
    end
    return Config.Auras.TimedBuffBorderColor
end

local function SortEntriesByManualOrder(entries)
    local manualOrder = Config.UnitFrames.ClassBuffs.ManualOrder
    local rank = {}
    for index, key in ipairs(manualOrder) do
        rank[key] = index
    end
    for _, entry in ipairs(entries) do
        if not rank[entry.key] then
            manualOrder[#manualOrder + 1] = entry.key
            rank[entry.key] = #manualOrder
        end
    end
    tsort(entries, function(a, b)
        return rank[a.key] < rank[b.key]
    end)
end

local function IsAnySpellKnown(spellIDs)
    for _, spellID in ipairs(spellIDs) do
        if IsPlayerSpell(spellID) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
-- Class list plus Blizzard's Group Buffs list for the current spec, in manual order.
function UF.GetGroupBuffEntries()
    local entries = {}
    local entryBySpellID = {}

    for _, template in ipairs(CLASS_GROUP_BUFFS[RefineUI.MyClass] or {}) do
        local info = C_Spell.GetSpellInfo(template.spellIDs[1])
        local entry = {
            key = template.key,
            spellIDs = template.spellIDs,
            name = info and info.name or tostring(template.spellIDs[1]),
            icon = info and info.iconID or QUESTION_MARK_ICON,
            hideByDefault = false,
            isKnown = IsAnySpellKnown(template.knownSpellIDs or template.spellIDs),
        }
        entries[#entries + 1] = entry
        for _, spellID in ipairs(template.spellIDs) do
            entryBySpellID[spellID] = entry
        end
    end

    for _, item in ipairs(C_CooldownViewer.GetGroupBuffItems()) do
        local existing = entryBySpellID[item.spellID]
        if existing then
            existing.isKnown = existing.isKnown or item.isKnown
        else
            entries[#entries + 1] = {
                key = "spell:" .. item.spellID,
                spellIDs = { item.spellID },
                name = item.name,
                icon = item.iconID,
                hideByDefault = band(item.flags, Enum.GroupBuffItemFlags.HideByDefault) ~= 0,
                isKnown = item.isKnown,
            }
        end
    end

    SortEntriesByManualOrder(entries)
    return entries
end

function UF.GetGroupBuffSection(entry)
    local settings = GetSettings(entry)
    if settings.Untracked then
        return SECTION.UNTRACKED
    elseif settings.Important then
        return SECTION.IMPORTANT
    end
    return SECTION.TRACKED
end

function UF.GetGroupBuffBorderColor(entry)
    local color = GetSettings(entry).BorderColor or GetDefaultBorderColor(entry)
    return color[1], color[2], color[3], color[4] or 1
end

function UF.SetGroupBuffBorderColor(entry, r, g, b, a)
    GetSettings(entry).BorderColor = { r, g, b, a }
    UF.RefreshGroupBuffs()
end

function UF.ResetGroupBuffBorderColor(entry)
    GetSettings(entry).BorderColor = nil
    UF.RefreshGroupBuffs()
end

function UF.IsGroupBuffFrameColor(entry)
    return GetSettings(entry).FrameColor == true
end

function UF.SetGroupBuffFrameColor(entry, enabled)
    GetSettings(entry).FrameColor = enabled and true or false
    UF.RefreshGroupBuffs()
end

-- Moves an entry into a section, optionally placing it before/after another entry.
function UF.MoveGroupBuff(entry, section, anchorEntry, placeAfter)
    local settings = GetSettings(entry)
    settings.Important = section == SECTION.IMPORTANT
    settings.Untracked = section == SECTION.UNTRACKED

    if anchorEntry and anchorEntry ~= entry then
        local manualOrder = Config.UnitFrames.ClassBuffs.ManualOrder
        for index, key in ipairs(manualOrder) do
            if key == entry.key then
                tremove(manualOrder, index)
                break
            end
        end
        for index, key in ipairs(manualOrder) do
            if key == anchorEntry.key then
                tinsert(manualOrder, placeAfter and index + 1 or index, entry.key)
                break
            end
        end
    end

    UF.RefreshGroupBuffs()
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
UF.GROUP_BUFF_SECTION = SECTION
