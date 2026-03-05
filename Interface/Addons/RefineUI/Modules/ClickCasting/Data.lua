----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Data
-- Description: SavedVariables schema, migrations, and tracked entry CRUD.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_Macro = C_Macro
local FindBaseSpellByID = FindBaseSpellByID
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroInfo = GetMacroInfo
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local GetTime = GetTime
local time = time
local tostring = tostring
local tonumber = tonumber
local type = type
local tremove = table.remove
local tinsert = table.insert

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CURRENT_SCHEMA_VERSION = 1

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function GetBaseSpellID(spellID)
    local idNum = tonumber(spellID)
    if not idNum or idNum <= 0 then
        return nil
    end

    if type(FindBaseSpellByID) == "function" then
        local ok, result = pcall(FindBaseSpellByID, idNum)
        if ok and tonumber(result) then
            return tonumber(result)
        end
    end

    return idNum
end

local function NormalizeStateTable(tbl)
    if type(tbl) ~= "table" then
        return {}
    end
    return tbl
end

local function BuildEntryID(prefix)
    local stamp = tostring(time() or 0)
    local micro = tostring(math.floor((GetTime() or 0) * 1000))
    return string.format("cc_%s_%s_%s", prefix, stamp, micro)
end

local function GetMacroMetadata(macroIndex)
    local index = tonumber(macroIndex)
    if not index or index <= 0 then
        return nil, nil, nil, nil
    end

    local name, iconFileID = GetMacroInfo(index)
    if name then
        local isCharacterMacro = (index > MAX_ACCOUNT_MACROS)
        return name, iconFileID, isCharacterMacro, index
    end

    if C_Macro and type(C_Macro.GetMacroName) == "function" then
        local ok, macroName = pcall(C_Macro.GetMacroName, index)
        if ok and type(macroName) == "string" and macroName ~= "" then
            if type(GetMacroIndexByName) == "function" then
                local resolvedIndex = tonumber(GetMacroIndexByName(macroName))
                if resolvedIndex and resolvedIndex > 0 then
                    local resolvedName, resolvedIcon = GetMacroInfo(resolvedIndex)
                    if resolvedName then
                        local isCharacterMacro = (resolvedIndex > MAX_ACCOUNT_MACROS)
                        return resolvedName, resolvedIcon, isCharacterMacro, resolvedIndex
                    end
                end
            end
            return macroName, nil, nil, nil
        end
    end

    return nil, nil, nil, nil
end

local function NormalizeTrackedEntry(rawEntry)
    if type(rawEntry) ~= "table" then
        return nil
    end

    local kind = rawEntry.kind
    if kind ~= "spell" and kind ~= "macro" then
        return nil
    end

    local entry = {
        id = tostring(rawEntry.id or BuildEntryID(kind)),
        kind = kind,
        addedAt = tonumber(rawEntry.addedAt) or time(),
    }

    if kind == "spell" then
        local spellID = tonumber(rawEntry.spellID)
        if not spellID or spellID <= 0 then
            return nil
        end
        entry.spellID = spellID
        entry.baseSpellID = tonumber(rawEntry.baseSpellID) or GetBaseSpellID(spellID) or spellID
    else
        local macroIndex = tonumber(rawEntry.macroIndex)
        if not macroIndex or macroIndex <= 0 then
            return nil
        end
        entry.macroIndex = macroIndex
        entry.macroName = rawEntry.macroName
        entry.isCharacterMacro = rawEntry.isCharacterMacro == true
        entry.iconFileID = tonumber(rawEntry.iconFileID) or nil
    end

    return entry
end

----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------
function ClickCasting:GetConfig()
    RefineUI.Config.ClickCasting = NormalizeStateTable(RefineUI.Config.ClickCasting)

    local cfg = RefineUI.Config.ClickCasting
    if cfg.Enable == nil then
        cfg.Enable = true
    end
    if type(cfg.SchemaVersion) ~= "number" then
        cfg.SchemaVersion = CURRENT_SCHEMA_VERSION
    end
    if type(cfg.TrackedEntries) ~= "table" then
        cfg.TrackedEntries = {}
    end
    if type(cfg.SpecBindings) ~= "table" then
        cfg.SpecBindings = {}
    end
    cfg.UI = NormalizeStateTable(cfg.UI)
    if cfg.UI.PanelShown == nil then
        cfg.UI.PanelShown = false
    end

    return cfg
end

function ClickCasting:InitializeData()
    local cfg = self:GetConfig()

    if cfg.SchemaVersion < CURRENT_SCHEMA_VERSION then
        cfg.SchemaVersion = CURRENT_SCHEMA_VERSION
    end

    local normalizedEntries = {}
    for i = 1, #cfg.TrackedEntries do
        local normalizedEntry = NormalizeTrackedEntry(cfg.TrackedEntries[i])
        if normalizedEntry then
            normalizedEntries[#normalizedEntries + 1] = normalizedEntry
        end
    end

    cfg.TrackedEntries = normalizedEntries
    cfg.SpecBindings = NormalizeStateTable(cfg.SpecBindings)
end

----------------------------------------------------------------------------------------
-- Entry Queries
----------------------------------------------------------------------------------------
function ClickCasting:GetTrackedEntries()
    return self:GetConfig().TrackedEntries
end

function ClickCasting:GetTrackedEntryByID(entryID)
    local targetID = tostring(entryID or "")
    if targetID == "" then
        return nil, nil
    end

    local entries = self:GetTrackedEntries()
    for index = 1, #entries do
        local entry = entries[index]
        if entry.id == targetID then
            return entry, index
        end
    end
    return nil, nil
end

----------------------------------------------------------------------------------------
-- Entry Mutations
----------------------------------------------------------------------------------------
function ClickCasting:AddTrackedSpell(spellID)
    local idNum = tonumber(spellID)
    if not idNum or idNum <= 0 then
        return false, "invalid_spell"
    end

    local baseSpellID = GetBaseSpellID(idNum) or idNum
    local entries = self:GetTrackedEntries()

    for i = 1, #entries do
        local entry = entries[i]
        if entry.kind == "spell" and tonumber(entry.baseSpellID) == baseSpellID then
            entry.spellID = idNum
            entry.baseSpellID = baseSpellID
            entry.addedAt = time()
            self:RequestRebuild("track-spell-refresh")
            return true, entry.id
        end
    end

    local newEntry = {
        id = BuildEntryID("spell"),
        kind = "spell",
        spellID = idNum,
        baseSpellID = baseSpellID,
        addedAt = time(),
    }

    tinsert(entries, newEntry)
    self:RequestRebuild("track-spell")
    return true, newEntry.id
end

function ClickCasting:AddTrackedMacro(macroIndex)
    local index = tonumber(macroIndex)
    if not index or index <= 0 then
        return false, "invalid_macro"
    end

    local macroName, iconFileID, isCharacterMacro, resolvedIndex = GetMacroMetadata(index)
    if resolvedIndex and resolvedIndex > 0 then
        index = resolvedIndex
    end
    local entries = self:GetTrackedEntries()

    for i = 1, #entries do
        local entry = entries[i]
        if entry.kind == "macro" and (
            tonumber(entry.macroIndex) == index
            or (
                type(macroName) == "string" and macroName ~= ""
                and type(entry.macroName) == "string" and entry.macroName == macroName
                and entry.isCharacterMacro == (isCharacterMacro == true)
            )
        ) then
            entry.macroIndex = index
            entry.macroName = macroName
            entry.iconFileID = iconFileID
            entry.isCharacterMacro = isCharacterMacro == true
            entry.addedAt = time()
            self:RequestRebuild("track-macro-refresh")
            return true, entry.id
        end
    end

    local newEntry = {
        id = BuildEntryID("macro"),
        kind = "macro",
        macroIndex = index,
        macroName = macroName,
        isCharacterMacro = isCharacterMacro == true,
        iconFileID = iconFileID,
        addedAt = time(),
    }

    tinsert(entries, newEntry)
    self:RequestRebuild("track-macro")
    return true, newEntry.id
end

function ClickCasting:RemoveTrackedEntry(entryID)
    local _, index = self:GetTrackedEntryByID(entryID)
    if not index then
        return false
    end

    local entries = self:GetTrackedEntries()
    tremove(entries, index)
    self:RequestRebuild("remove-entry")
    return true
end

function ClickCasting:UpdateTrackedMacroMetadata(entryID, macroIndex, macroName, isCharacterMacro, iconFileID)
    local entry = self:GetTrackedEntryByID(entryID)
    if not entry or entry.kind ~= "macro" then
        return false
    end

    entry.macroIndex = tonumber(macroIndex) or entry.macroIndex
    entry.macroName = macroName
    entry.isCharacterMacro = isCharacterMacro == true
    entry.iconFileID = tonumber(iconFileID) or entry.iconFileID
    return true
end

----------------------------------------------------------------------------------------
-- Spec Cache
----------------------------------------------------------------------------------------
function ClickCasting:GetSpecBindings(specKey)
    local key = tostring(specKey or "nospec")
    local cfg = self:GetConfig()
    if type(cfg.SpecBindings[key]) ~= "table" then
        cfg.SpecBindings[key] = {
            byEntryId = {},
            byKey = {},
        }
    end
    return cfg.SpecBindings[key]
end

function ClickCasting:SetSpecBindings(specKey, payload)
    local key = tostring(specKey or "nospec")
    local cfg = self:GetConfig()
    cfg.SpecBindings[key] = payload or {
        byEntryId = {},
        byKey = {},
    }
end

function ClickCasting:SetPanelShown(shown)
    local cfg = self:GetConfig()
    cfg.UI.PanelShown = shown and true or false
end

function ClickCasting:IsPanelShown()
    local cfg = self:GetConfig()
    return cfg.UI.PanelShown == true
end
