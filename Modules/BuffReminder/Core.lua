----------------------------------------------------------------------------------------
-- BuffReminder Component: Core
-- Description: Core logic and aura checking for BuffReminder
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
local _G = _G
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local GetNumGroupMembers = GetNumGroupMembers
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetSpecializationRole = GetSpecializationRole
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local IsPlayerSpell = IsPlayerSpell
local UnitCanAssist = UnitCanAssist
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitLevel = UnitLevel
local issecretvalue = _G.issecretvalue
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ROGUE_DRAGON_TEMPERED_BLADES = 381801
local HUNTER_UNBREAKABLE_BOND = 1223323

BuffReminder.currentValidUnits = BuffReminder.currentValidUnits or {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetSpellList(spellIDs)
    if type(spellIDs) == "table" then
        return spellIDs
    end
    return { spellIDs }
end

----------------------------------------------------------------------------------------
-- Public Methods / Component Access
----------------------------------------------------------------------------------------
function BuffReminder:GetPrimarySpellID(spellIDs)
    if type(spellIDs) == "table" then
        return spellIDs[1]
    end
    return spellIDs
end

----------------------------------------------------------------------------------------
-- Player / Group Info Helpers
----------------------------------------------------------------------------------------
local function GetPlayerSpecID()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationInfo(specIndex)
    end
    return nil
end

local function GetPlayerRole()
    local specIndex = GetSpecialization()
    if specIndex then
        return GetSpecializationRole(specIndex)
    end
    return nil
end

local function KnowsAnySpell(spellIDs)
    local spellList = GetSpellList(spellIDs)
    for i = 1, #spellList do
        if IsPlayerSpell(spellList[i]) then
            return true
        end
    end
    return false
end

local function GetAuraDataBySpellID(unit, spellID)
    if not C_UnitAuras or not spellID then
        return nil
    end
    if C_UnitAuras.GetUnitAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID, BuffReminder.AURA_FILTER)
        if ok then
            return auraData
        end
    end
    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then
            return auraData
        end
    end
    return nil
end

local function UnitHasAnyAura(unit, spellIDs)
    local spellList = GetSpellList(spellIDs)
    for i = 1, #spellList do
        local auraData = GetAuraDataBySpellID(unit, spellList[i])
        if auraData then
            return true, auraData
        end
    end
    return false, nil
end

local function CountPlayerAuras(spellIDs)
    local count = 0
    local spellList = GetSpellList(spellIDs)
    for i = 1, #spellList do
        if GetAuraDataBySpellID("player", spellList[i]) then
            count = count + 1
        end
    end
    return count
end

local function IsValidGroupMember(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and UnitCanAssist("player", unit)
end

----------------------------------------------------------------------------------------
-- Unit Tracking Validations
----------------------------------------------------------------------------------------
function BuffReminder:IsTrackedUnitToken(unit)
    return unit == "player" or unit == "pet" or unit:match("^party%d+$") or unit:match("^raid%d+$")
end

function BuffReminder:IsCategoryEnabled(category)
    local settings = self:GetCategorySettings(category)
    if settings.Enable == false then
        return false
    end
    return true
end

function BuffReminder:IsEntryEnabled(entryKey, category)
    local settings = self:GetEntrySettings(entryKey, category)
    if settings.Enable == false then
        return false
    end
    return true
end

function BuffReminder:BuildValidUnitCache()
    local validUnits = {}
    local groupSize = GetNumGroupMembers()
    local inRaid = IsInRaid()

    if groupSize == 0 then
        local _, class = UnitClass("player")
        validUnits[1] = { unit = "player", class = class, isPlayer = true }
        self.currentValidUnits = validUnits
        return validUnits
    end

    local idx = 1
    for i = 1, groupSize do
        local unit = inRaid and ("raid" .. i) or ((i == 1) and "player" or ("party" .. (i - 1)))
        if IsValidGroupMember(unit) then
            local _, class = UnitClass(unit)
            validUnits[idx] = { unit = unit, class = class, isPlayer = UnitIsPlayer(unit) }
            idx = idx + 1
        end
    end

    self.currentValidUnits = validUnits
    return validUnits
end

local function PassesCommonChecks(self, entry, runtime)
    if entry.class and entry.class ~= RefineUI.MyClass then return false end
    if entry.levelRequired and runtime.playerLevel < entry.levelRequired then return false end
    if entry.requireSpecId and runtime.specID ~= entry.requireSpecId then return false end
    if entry.requiresTalentSpellID and not IsPlayerSpell(entry.requiresTalentSpellID) then return false end
    if entry.excludeTalentSpellID and IsPlayerSpell(entry.excludeTalentSpellID) then return false end
    return true
end

local function IsScopeAllowed(settings, runtime)
    if not settings or not runtime then
        return true
    end
    if settings.InstanceOnly and not runtime.inInstance then
        return false
    end
    return true
end

local function IsPlayerAuraFromMe(auraData)
    if not auraData then return false end
    if auraData.isFromPlayerOrPlayerPet ~= nil then
        return auraData.isFromPlayerOrPlayerPet == true
    end
    local sourceUnit = auraData.sourceUnit
    if not sourceUnit or type(sourceUnit) ~= "string" then return false end
    if issecretvalue and issecretvalue(sourceUnit) then return false end
    return UnitIsUnit(sourceUnit, "player")
end

local function IsRaidBuffAvailable(self, entry)
    if not entry or not entry.class then
        return false
    end
    local validUnits = self.currentValidUnits or {}
    for i = 1, #validUnits do
        if validUnits[i].class == entry.class then
            return true
        end
    end
    return false
end

local function IsPlayerRaidBuffBeneficiary(self, entry)
    local beneficiaries = self.BUFF_BENEFICIARIES[entry.key]
    return (not beneficiaries) or beneficiaries[RefineUI.MyClass]
end

----------------------------------------------------------------------------------------
-- Public / Module Methods
----------------------------------------------------------------------------------------
function BuffReminder:CollectApplicableRaidBuffEntries()
    self:BuildValidUnitCache()
    local list = {}
    for i = 1, #self.RAID_BUFFS do
        local entry = self.RAID_BUFFS[i]
        if IsRaidBuffAvailable(self, entry) then
            list[#list + 1] = entry
        end
    end
    return list
end

local function IsTargetedBuffActiveFromPlayer(self, entry)
    local spellList = GetSpellList(entry.spellID)
    if #spellList == 0 then
        return false
    end

    local validUnits = self.currentValidUnits or {}
    for i = 1, #validUnits do
        local member = validUnits[i]
        if not entry.beneficiaryRole or UnitGroupRolesAssigned(member.unit) == entry.beneficiaryRole then
            local hasBuff, auraData = UnitHasAnyAura(member.unit, spellList)
            if hasBuff and IsPlayerAuraFromMe(auraData) then
                return true
            end
        end
    end
    return false
end

local function EvaluateCustomCheck(entry, runtime)
    if entry.customCheck == "roguePoisons" then
        local lethalCount = CountPlayerAuras({ 315584, 8679, 2823, 381664 })
        local nonLethalCount = CountPlayerAuras({ 5761, 381637, 3408 })
        local required = IsPlayerSpell(ROGUE_DRAGON_TEMPERED_BLADES) and 2 or 1
        return lethalCount < required or nonLethalCount < required
    end
    if entry.customCheck == "missingPet" then
        return not UnitExists("pet")
    end
    if entry.customCheck == "hunterMissingPet" then
        if runtime.specID == 254 and not IsPlayerSpell(HUNTER_UNBREAKABLE_BOND) then
            return false
        end
        return not UnitExists("pet")
    end
    return false
end

local function ShouldShowRaidEntry(self, entry)
    if not IsRaidBuffAvailable(self, entry) then
        return false
    end

    if not IsPlayerRaidBuffBeneficiary(self, entry) then
        return false
    end

    local hasOnPlayer = UnitHasAnyAura("player", entry.spellID)
    return not hasOnPlayer
end

local function ShouldShowTargetedEntry(self, entry)
    if entry.class ~= RefineUI.MyClass then return false end
    if not KnowsAnySpell(entry.spellID) then return false end
    if GetNumGroupMembers() == 0 then return false end
    return not IsTargetedBuffActiveFromPlayer(self, entry)
end

local function ShouldShowSelfEntry(entry, runtime)
    if entry.customCheck then
        return EvaluateCustomCheck(entry, runtime)
    end
    if not KnowsAnySpell(entry.spellID) then return false end
    if entry.enchantID then
        return runtime.mainEnchantID ~= entry.enchantID and runtime.offEnchantID ~= entry.enchantID
    end
    local auraSpell = entry.buffIdOverride or entry.spellID
    local hasAura = UnitHasAnyAura("player", auraSpell)
    return not hasAura
end

local function ShouldShowPetEntry(entry, runtime)
    if entry.customCheck then
        return EvaluateCustomCheck(entry, runtime)
    end
    if not KnowsAnySpell(entry.spellID) then return false end
    return not UnitExists("pet")
end

function BuffReminder:BuildRuntimeState()
    local _, _, _, mainEnchantID, _, _, _, offEnchantID = GetWeaponEnchantInfo()
    local inInstance = IsInInstance()
    return {
        playerLevel = UnitLevel("player") or 1,
        specID = GetPlayerSpecID(),
        role = GetPlayerRole(),
        mainEnchantID = mainEnchantID,
        offEnchantID = offEnchantID,
        inInstance = inInstance == true,
    }
end

function BuffReminder:CollectMissingEntries()
    if InCombatLockdown() then
        return {}
    end

    local runtime = self:BuildRuntimeState()
    local result = {}

    self:BuildValidUnitCache()

    for c = 1, #self.CATEGORY_ORDER do
        local category = self.CATEGORY_ORDER[c]
        local entries = self.CATEGORY_BUFFS[category]
        for i = 1, #entries do
            local entry = entries[i]
            local entrySettings = self:GetEntrySettings(entry.key, category)
            if self:IsEntryEnabled(entry.key, category) and IsScopeAllowed(entrySettings, runtime) and (category == "raid" or PassesCommonChecks(self, entry, runtime)) then
                local show = false
                if category == "raid" then
                    show = ShouldShowRaidEntry(self, entry)
                elseif category == "targeted" then
                    show = ShouldShowTargetedEntry(self, entry)
                elseif category == "self" then
                    if entry.reminderType == "pet" then
                        show = ShouldShowPetEntry(entry, runtime)
                    else
                        show = ShouldShowSelfEntry(entry, runtime)
                    end
                end

                if show then
                    result[#result + 1] = { category = category, entry = entry, runtime = runtime }
                end
            end
        end
    end

    return result
end

function BuffReminder:GetEntryTexture(entry, runtime)
    local texture = entry.iconOverride
    if type(texture) == "table" then
        texture = texture[1]
    end
    if not texture and entry.iconByRole and runtime and runtime.role then
        texture = entry.iconByRole[runtime.role]
    end
    if not texture and C_Spell and C_Spell.GetSpellTexture then
        local ok, spellTexture = pcall(C_Spell.GetSpellTexture, self:GetPrimarySpellID(entry.spellID))
        if ok then
            texture = spellTexture
        end
    end
    return texture or self.QUESTION_MARK_ICON
end

function BuffReminder:GetConfigurableEntries(category)
    local source = self.CATEGORY_BUFFS[category]
    if type(source) ~= "table" then
        return {}
    end
    if category == "raid" then
        local raidEntries = {}
        for i = 1, #source do
            raidEntries[i] = source[i]
        end
        return raidEntries
    end

    local list = {}
    local idx = 1
    local runtime = self:BuildRuntimeState()
    for i = 1, #source do
        local entry = source[i]
        if PassesCommonChecks(self, entry, runtime) and KnowsAnySpell(entry.spellID) then
            list[idx] = entry
            idx = idx + 1
        end
    end
    return list
end
