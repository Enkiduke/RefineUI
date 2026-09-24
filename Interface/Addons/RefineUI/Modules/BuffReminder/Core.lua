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
local C_Secrets = C_Secrets
local C_PaperDollInfo = C_PaperDollInfo
local GetNumGroupMembers = GetNumGroupMembers
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetSpecializationRole = GetSpecializationRole
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
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
local UnitIsUnit = UnitIsUnit
local UnitLevel = UnitLevel
local issecretvalue = _G.issecretvalue
local type = type
local wipe = wipe

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ROGUE_DRAGON_TEMPERED_BLADES = 381801
local HUNTER_UNBREAKABLE_BOND = 1223323
local ROGUE_LETHAL_POISONS = { 315584, 8679, 2823, 381664 }
local ROGUE_NONLETHAL_POISONS = { 5761, 381637, 3408 }

local groupUnits = {}
local groupClasses = {}

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
    if type(spellIDs) ~= "table" then
        return IsPlayerSpell(spellIDs)
    end
    for i = 1, #spellIDs do
        if IsPlayerSpell(spellIDs[i]) then
            return true
        end
    end
    return false
end

local function ContainsSpellID(spellIDs, spellID)
    if type(spellIDs) ~= "table" then
        return spellIDs == spellID
    end
    for i = 1, #spellIDs do
        if spellIDs[i] == spellID then
            return true
        end
    end
    return false
end

local function GetActiveFormSpellID()
    local index = GetShapeshiftForm()
    if not index or index == 0 then return nil end
    local _, active, _, spellID = GetShapeshiftFormInfo(index)
    if (issecretvalue and (issecretvalue(active) or issecretvalue(spellID))) or not active then return nil end
    return spellID
end

local function GetAuraDataBySpellID(unit, spellID)
    local ok, auraData
    if unit == "player" then
        ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    else
        ok, auraData = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    end
    return ok and auraData or nil
end

-- Restricted content (M+, encounters) hides some auras entirely; treat those as present so they never false-alarm.
local function IsAuraUnreadable(spellID)
    local isSecret = C_Secrets.ShouldSpellAuraBeSecret(spellID)
    return (issecretvalue and issecretvalue(isSecret)) or isSecret == true
end

local function UnitHasAura(unit, spellID)
    local auraData = GetAuraDataBySpellID(unit, spellID)
    if auraData then
        return true, auraData
    end
    return IsAuraUnreadable(spellID), nil
end

local function UnitHasAnyAura(unit, spellIDs)
    if type(spellIDs) ~= "table" then
        return UnitHasAura(unit, spellIDs)
    end
    for i = 1, #spellIDs do
        local hasAura, auraData = UnitHasAura(unit, spellIDs[i])
        if hasAura then
            return true, auraData
        end
    end
    return false, nil
end

local function CountPlayerAuras(spellIDs)
    local count = 0
    for i = 1, #spellIDs do
        if GetAuraDataBySpellID("player", spellIDs[i]) then
            count = count + 1
        end
    end
    return count
end

local function GetMissingKnownPoison(spellIDs)
    for i = 1, #spellIDs do
        local spellID = spellIDs[i]
        if IsPlayerSpell(spellID) and not GetAuraDataBySpellID("player", spellID) then
            return spellID
        end
    end
    return nil
end

function BuffReminder:GetCastSpellID(entry, runtime)
    if entry.customCheck == "roguePoisons" then
        local required = IsPlayerSpell(ROGUE_DRAGON_TEMPERED_BLADES) and 2 or 1
        if CountPlayerAuras(ROGUE_LETHAL_POISONS) < required then
            local spellID = GetMissingKnownPoison(ROGUE_LETHAL_POISONS)
            if spellID then return spellID end
        end
        if CountPlayerAuras(ROGUE_NONLETHAL_POISONS) < required then
            return GetMissingKnownPoison(ROGUE_NONLETHAL_POISONS)
        end
        return nil
    end

    local spellIDs = entry.castSpellID or entry.spellID
    if not spellIDs then return nil end
    if type(spellIDs) ~= "table" then
        return IsPlayerSpell(spellIDs) and spellIDs or nil
    end

    local preferred = entry.iconByRole and runtime and entry.iconByRole[runtime.role]
    if preferred and IsPlayerSpell(preferred) then
        return preferred
    end

    for i = 1, #spellIDs do
        if IsPlayerSpell(spellIDs[i]) then
            return spellIDs[i]
        end
    end
    return nil
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

local function BuildGroupCache()
    wipe(groupUnits)
    wipe(groupClasses)

    local groupSize = GetNumGroupMembers()
    if groupSize == 0 then
        groupUnits[1] = "player"
        groupClasses[RefineUI.MyClass] = true
        return
    end

    local inRaid = IsInRaid()
    for i = 1, groupSize do
        local unit = inRaid and ("raid" .. i) or ((i == 1) and "player" or ("party" .. (i - 1)))
        if IsValidGroupMember(unit) then
            local _, class = UnitClass(unit)
            groupUnits[#groupUnits + 1] = unit
            if class then
                groupClasses[class] = true
            end
        end
    end
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

local function IsPlayerRaidBuffBeneficiary(self, entry)
    local beneficiaries = self.BUFF_BENEFICIARIES[entry.key]
    return (not beneficiaries) or beneficiaries[RefineUI.MyClass]
end

local function IsTargetedBuffActiveFromPlayer(entry)
    local auraSpell = entry.buffIdOverride or entry.spellID
    for i = 1, #groupUnits do
        local unit = groupUnits[i]
        if not entry.beneficiaryRole or UnitGroupRolesAssigned(unit) == entry.beneficiaryRole then
            local hasBuff, auraData = UnitHasAnyAura(unit, auraSpell)
            -- No auraData means the aura is unreadable; its source can't be checked, so assume it's ours.
            if hasBuff and (not auraData or IsPlayerAuraFromMe(auraData)) then
                return true
            end
        end
    end
    return false
end

local function EvaluateCustomCheck(entry, runtime)
    if entry.customCheck == "stance" then
        if not IsPlayerSpell(entry.spellID) then return false end
        return GetActiveFormSpellID() ~= entry.spellID
    end
    if entry.customCheck == "roguePoisons" then
        local lethalCount = CountPlayerAuras(ROGUE_LETHAL_POISONS)
        local nonLethalCount = CountPlayerAuras(ROGUE_NONLETHAL_POISONS)
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

local function ShouldShowRaidEntry(self, entry, runtime)
    if entry.skipPvP and (runtime.instanceType == "pvp" or runtime.instanceType == "arena") then
        return false
    end
    if not groupClasses[entry.class] then
        return false
    end

    if not IsPlayerRaidBuffBeneficiary(self, entry) then
        return false
    end

    local auraSpell = entry.spellID
    if entry.instanceBuffIDs and (runtime.instanceType == "party" or runtime.instanceType == "raid") then
        auraSpell = entry.instanceBuffIDs
    end
    -- Paladin auras are stance-bar forms; the form state stays readable when the aura itself is secret.
    if entry.isForm and entry.class == RefineUI.MyClass then
        return not ContainsSpellID(auraSpell, GetActiveFormSpellID())
    end
    local hasOnPlayer = UnitHasAnyAura("player", auraSpell)
    return not hasOnPlayer
end

local function ShouldShowTargetedEntry(self, entry)
    if entry.class ~= RefineUI.MyClass then return false end
    if not KnowsAnySpell(entry.spellID) then return false end
    if GetNumGroupMembers() == 0 and not entry.allowSolo then return false end
    self.watchGroupAuras = true
    return not IsTargetedBuffActiveFromPlayer(entry)
end

local function ShouldShowSelfEntry(entry, runtime)
    if entry.customCheck then
        return EvaluateCustomCheck(entry, runtime)
    end
    if not KnowsAnySpell(entry.spellID) then return false end
    if entry.requireShield and not runtime.offhandHasShield then return false end
    if entry.enchantID then
        if entry.enchantSlot == "offhand" then
            return runtime.offEnchantID ~= entry.enchantID
        end
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
    local inInstance, instanceType = IsInInstance()
    return {
        playerLevel = UnitLevel("player") or 1,
        specID = GetPlayerSpecID(),
        role = GetPlayerRole(),
        mainEnchantID = mainEnchantID,
        offEnchantID = offEnchantID,
        offhandHasShield = RefineUI.MyClass == "SHAMAN" and C_PaperDollInfo.OffhandHasShield(),
        inInstance = inInstance == true,
        instanceType = instanceType,
    }
end

function BuffReminder:CollectMissingEntries()
    if InCombatLockdown() then
        return {}
    end

    local runtime = self:BuildRuntimeState()
    local result = {}

    BuildGroupCache()
    self.watchGroupAuras = false

    for c = 1, #self.CATEGORY_ORDER do
        local category = self.CATEGORY_ORDER[c]
        local entries = self.CATEGORY_BUFFS[category]
        if self:IsCategoryEnabled(category) then
            for i = 1, #entries do
                local entry = entries[i]
                local entrySettings = self:GetEntrySettings(entry.key, category)
                if entrySettings.Enable ~= false and IsScopeAllowed(entrySettings, runtime) and (category == "raid" or PassesCommonChecks(self, entry, runtime)) then
                    local show = false
                    if category == "raid" then
                        show = ShouldShowRaidEntry(self, entry, runtime)
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
    end

    return result
end

function BuffReminder:GetEntryTexture(entry, runtime, castSpellID)
    local texture = entry.iconOverride
    if type(texture) == "table" then
        texture = texture[1]
    end
    if not texture and C_Spell and C_Spell.GetSpellTexture then
        local spellID = castSpellID or entry.castSpellID
        if not spellID and (entry.iconByRole or entry.customCheck == "roguePoisons") then
            spellID = self:GetCastSpellID(entry, runtime)
        end
        spellID = spellID or self:GetPrimarySpellID(entry.spellID)
        local ok, spellTexture = pcall(C_Spell.GetSpellTexture, spellID)
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
