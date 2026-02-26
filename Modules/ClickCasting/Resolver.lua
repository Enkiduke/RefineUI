----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Resolver
-- Description: Resolves tracked entries into per-spec action slots and keys.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local C_ActionBar = C_ActionBar
local C_Macro = C_Macro
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local Enum = Enum
local FindBaseSpellByID = FindBaseSpellByID
local GetActionInfo = GetActionInfo
local GetBindingKey = GetBindingKey
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroInfo = GetMacroInfo
local GetNumMacros = GetNumMacros
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local GetFlyoutInfo = GetFlyoutInfo
local GetFlyoutSlotInfo = GetFlyoutSlotInfo
local IsPlayerSpell = IsPlayerSpell
local IsSpellKnown = IsSpellKnown
local IsSpellKnownOrOverridesKnown = IsSpellKnownOrOverridesKnown
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120
local tostring = tostring
local tonumber = tonumber
local type = type
local pairs = pairs
local ipairs = ipairs
local sort = table.sort

local SPELLBOOK_PLAYER_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local SPELLBOOK_ITEM_TYPE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
local SPELLBOOK_ITEM_TYPE_FUTURE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
local SPELLBOOK_ITEM_TYPE_FLYOUT = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
local UNKNOWN_SPEC_LABEL = "Other Spec"

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ACTION_BAR_BUTTON_GROUPS = {
    { prefix = "ActionButton", size = 12 },
    { prefix = "MultiBarBottomLeftButton", size = 12 },
    { prefix = "MultiBarBottomRightButton", size = 12 },
    { prefix = "MultiBarRightButton", size = 12 },
    { prefix = "MultiBarLeftButton", size = 12 },
    { prefix = "MultiBar5Button", size = 12 },
    { prefix = "MultiBar6Button", size = 12 },
    { prefix = "MultiBar7Button", size = 12 },
}

local ACTION_SLOT_MAX = 180

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function BuildLookupList(set)
    local list = {}
    for value in pairs(set) do
        list[#list + 1] = value
    end
    sort(list)
    return list
end

local function GetBaseSpellID(spellID)
    local idNum = tonumber(spellID)
    if not idNum or idNum <= 0 then
        return nil
    end

    if type(FindBaseSpellByID) == "function" then
        local ok, baseID = pcall(FindBaseSpellByID, idNum)
        if ok and tonumber(baseID) then
            return tonumber(baseID)
        end
    end

    return idNum
end

local function IsSpellKnownForCurrentSpec(spellID, baseSpellID)
    local candidates = {}
    local spellNum = tonumber(spellID)
    local baseNum = tonumber(baseSpellID)
    if spellNum and spellNum > 0 then
        candidates[spellNum] = true
    end
    if baseNum and baseNum > 0 then
        candidates[baseNum] = true
    end

    for candidateSpellID in pairs(candidates) do
        if type(IsSpellKnownOrOverridesKnown) == "function" then
            local ok, known = pcall(IsSpellKnownOrOverridesKnown, candidateSpellID)
            if ok and known then
                return true
            end
        end

        if type(IsPlayerSpell) == "function" then
            local ok, known = pcall(IsPlayerSpell, candidateSpellID)
            if ok and known then
                return true
            end
        end

        if type(IsSpellKnown) == "function" then
            local ok, known = pcall(IsSpellKnown, candidateSpellID)
            if ok and known then
                return true
            end
        end
    end

    return false
end

local function AddSpecLabel(labelSetBySpell, spellID, label)
    local spellNum = tonumber(spellID)
    if not spellNum or spellNum <= 0 then
        return
    end

    local safeLabel = (type(label) == "string" and label ~= "" and label) or UNKNOWN_SPEC_LABEL
    if type(labelSetBySpell[spellNum]) ~= "table" then
        labelSetBySpell[spellNum] = {}
    end
    labelSetBySpell[spellNum][safeLabel] = true
end

local function AddSpellToSpecIndex(specIndex, spellID, isOffSpecLine, offSpecLabel)
    local spellNum = tonumber(spellID)
    if not spellNum or spellNum <= 0 then
        return
    end

    local baseSpellID = GetBaseSpellID(spellNum)
    if isOffSpecLine then
        AddSpecLabel(specIndex.offSpecLabelsBySpell, spellNum, offSpecLabel)
        if baseSpellID and baseSpellID > 0 then
            AddSpecLabel(specIndex.offSpecLabelsBySpell, baseSpellID, offSpecLabel)
        end
    else
        specIndex.currentValidSpellSet[spellNum] = true
        if baseSpellID and baseSpellID > 0 then
            specIndex.currentValidSpellSet[baseSpellID] = true
        end
    end
end

local function GetOtherSpecLabel(specIndex, spellID, baseSpellID)
    if type(specIndex) ~= "table" or type(specIndex.offSpecLabelsBySpell) ~= "table" then
        return nil
    end

    local labelSet = {}
    local spellNum = tonumber(spellID)
    local baseNum = tonumber(baseSpellID)
    local spellLabels = spellNum and specIndex.offSpecLabelsBySpell[spellNum]
    local baseLabels = baseNum and specIndex.offSpecLabelsBySpell[baseNum]

    if type(spellLabels) == "table" then
        for label in pairs(spellLabels) do
            labelSet[label] = true
        end
    end
    if type(baseLabels) == "table" then
        for label in pairs(baseLabels) do
            labelSet[label] = true
        end
    end

    local labels = BuildLookupList(labelSet)
    if #labels == 0 then
        return nil
    end
    if #labels == 1 then
        return labels[1]
    end
    return table.concat(labels, ", ")
end

local function BuildSpecSpellIndex()
    local specIndex = {
        currentValidSpellSet = {},
        offSpecLabelsBySpell = {},
    }

    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemType) then
        return specIndex
    end
    if not SPELLBOOK_PLAYER_BANK or not SPELLBOOK_ITEM_TYPE_SPELL then
        return specIndex
    end

    local skillLineCount = tonumber(C_SpellBook.GetNumSpellBookSkillLines()) or 0
    for skillLineIndex = 1, skillLineCount do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if type(info) == "table" and not info.shouldHide then
            local offSpecID = tonumber(info.offSpecID)
            local isOffSpecLine = offSpecID and offSpecID > 0
            local offSpecLabel = UNKNOWN_SPEC_LABEL

            if isOffSpecLine and type(GetSpecializationInfoByID) == "function" then
                local _, specName = GetSpecializationInfoByID(offSpecID)
                if type(specName) == "string" and specName ~= "" then
                    offSpecLabel = specName
                end
            end

            local itemOffset = tonumber(info.itemIndexOffset) or 0
            local itemCount = tonumber(info.numSpellBookItems) or 0
            for itemIndex = 1, itemCount do
                local spellBookSlot = itemOffset + itemIndex
                local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(spellBookSlot, SPELLBOOK_PLAYER_BANK)
                if itemType == SPELLBOOK_ITEM_TYPE_SPELL or itemType == SPELLBOOK_ITEM_TYPE_FUTURE_SPELL then
                    AddSpellToSpecIndex(specIndex, tonumber(spellID) or tonumber(actionID), isOffSpecLine, offSpecLabel)
                elseif itemType == SPELLBOOK_ITEM_TYPE_FLYOUT and type(GetFlyoutInfo) == "function" and type(GetFlyoutSlotInfo) == "function" then
                    local flyoutID = tonumber(actionID)
                    local _, _, numFlyoutSlots = flyoutID and GetFlyoutInfo(flyoutID)
                    numFlyoutSlots = tonumber(numFlyoutSlots) or 0
                    for flyoutSlot = 1, numFlyoutSlots do
                        local flyoutSpellID, overrideSpellID = GetFlyoutSlotInfo(flyoutID, flyoutSlot)
                        AddSpellToSpecIndex(specIndex, flyoutSpellID, isOffSpecLine, offSpecLabel)
                        AddSpellToSpecIndex(specIndex, overrideSpellID, isOffSpecLine, offSpecLabel)
                    end
                end
            end
        end
    end

    return specIndex
end

local function BuildEntryOrder(entries)
    local ordered = {}
    for i = 1, #entries do
        ordered[i] = entries[i]
    end
    sort(ordered, function(a, b)
        local aTime = tonumber(a and a.addedAt) or 0
        local bTime = tonumber(b and b.addedAt) or 0
        if aTime == bTime then
            return tostring(a.id or "") < tostring(b.id or "")
        end
        return aTime < bTime
    end)
    return ordered
end

----------------------------------------------------------------------------------------
-- Spec
----------------------------------------------------------------------------------------
function ClickCasting:GetActiveSpecKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then
        return "nospec"
    end

    local specID = GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
    if not specID then
        return "nospec"
    end

    return tostring(specID)
end

----------------------------------------------------------------------------------------
-- Slot/Key Index
----------------------------------------------------------------------------------------
function ClickCasting:BuildActionSlotCommandIndex()
    local slotCommands = {}

    for _, group in ipairs(ACTION_BAR_BUTTON_GROUPS) do
        for buttonIndex = 1, group.size do
            local buttonName = group.prefix .. tostring(buttonIndex)
            local button = _G[buttonName]
            if button and type(button.action) == "number" and button.action > 0 then
                local slot = button.action
                local bucket = slotCommands[slot]
                if not bucket then
                    bucket = {
                        commandSet = {},
                    }
                    slotCommands[slot] = bucket
                end

                local commandName = button.bindingAction
                if type(commandName) ~= "string" or commandName == "" then
                    local buttonType = button.buttonType
                    local buttonID = (button.GetID and button:GetID()) or buttonIndex
                    if type(buttonType) == "string" and buttonID then
                        commandName = buttonType .. tostring(buttonID)
                    end
                end

                if type(commandName) == "string" and commandName ~= "" then
                    bucket.commandSet[commandName] = true
                end

                bucket.commandSet["CLICK " .. buttonName .. ":LeftButton"] = true
            end
        end
    end

    return slotCommands
end

local function CollectKeysForCommandSet(commandSet)
    local keySet = {}
    for commandName in pairs(commandSet) do
        local keys = { GetBindingKey(commandName) }
        for i = 1, #keys do
            local key = keys[i]
            if type(key) == "string" and key ~= "" then
                keySet[key] = true
            end
        end
    end
    return keySet
end

local function CollectKeysForSlots(slots, slotCommandIndex)
    local keySet = {}
    for i = 1, #slots do
        local slot = slots[i]
        local bucket = slotCommandIndex[slot]
        if bucket and bucket.commandSet then
            local fromCommandSet = CollectKeysForCommandSet(bucket.commandSet)
            for key in pairs(fromCommandSet) do
                keySet[key] = true
            end
        end
    end
    return BuildLookupList(keySet)
end

----------------------------------------------------------------------------------------
-- Macro Resolution
----------------------------------------------------------------------------------------
local function GetMacroNameAndIcon(index)
    local name, iconFileID = GetMacroInfo(index)
    return name, tonumber(iconFileID)
end

local function IsCharacterMacroIndex(index)
    return index > MAX_ACCOUNT_MACROS
end

function ClickCasting:ResolveTrackedMacroIndex(entry)
    local rawIndex = tonumber(entry and entry.macroIndex)
    local targetName = entry and entry.macroName
    local targetIcon = tonumber(entry and entry.iconFileID)
    local targetCharState = entry and entry.isCharacterMacro == true

    if (type(targetName) ~= "string" or targetName == "") and rawIndex and rawIndex > 0 and C_Macro and type(C_Macro.GetMacroName) == "function" then
        local ok, resolvedName = pcall(C_Macro.GetMacroName, rawIndex)
        if ok and type(resolvedName) == "string" and resolvedName ~= "" then
            targetName = resolvedName
        end
    end

    local function GetMacroRecord(index)
        local name, icon = GetMacroNameAndIcon(index)
        if not name then
            return nil
        end
        return {
            index = index,
            name = name,
            icon = icon,
            isCharacterMacro = IsCharacterMacroIndex(index),
        }
    end

    local function IsExpectedScope(record)
        return record and record.isCharacterMacro == targetCharState
    end

    local _, numCharacter = GetNumMacros()
    local maxIndex = (MAX_ACCOUNT_MACROS or 120) + (tonumber(numCharacter) or 0)

    local function CollectNameCandidates(requireExpectedScope)
        local candidates = {}
        if type(targetName) ~= "string" or targetName == "" then
            return candidates
        end

        for index = 1, maxIndex do
            local record = GetMacroRecord(index)
            if record and record.name == targetName then
                if not requireExpectedScope or IsExpectedScope(record) then
                    candidates[#candidates + 1] = record
                end
            end
        end
        return candidates
    end

    local function FindUniqueMovedCandidate(rawIndexToIgnore)
        local candidates = CollectNameCandidates(true)
        if #candidates ~= 1 then
            candidates = CollectNameCandidates(false)
        end
        if #candidates == 1 and candidates[1].index ~= rawIndexToIgnore then
            return candidates[1]
        end
        return nil
    end

    if rawIndex and rawIndex > 0 then
        local indexRecord = GetMacroRecord(rawIndex)
        if indexRecord then
            if not targetName or targetName == "" or indexRecord.name == targetName then
                return rawIndex, indexRecord.name, indexRecord.isCharacterMacro, indexRecord.icon, "index"
            end

            -- If name changed at this index, prefer a unique moved/reordered match by saved name.
            local movedCandidate = FindUniqueMovedCandidate(rawIndex)
            if movedCandidate then
                return movedCandidate.index, movedCandidate.name, movedCandidate.isCharacterMacro, movedCandidate.icon, "name"
            end

            -- Otherwise treat as an in-place rename/edit of the tracked macro.
            return rawIndex, indexRecord.name, indexRecord.isCharacterMacro, indexRecord.icon, "index-edited"
        end
    end

    local candidates = CollectNameCandidates(true)
    if #candidates == 0 then
        candidates = CollectNameCandidates(false)
    end
    if #candidates == 1 then
        local candidate = candidates[1]
        return candidate.index, candidate.name, candidate.isCharacterMacro, candidate.icon, "name"
    end

    if #candidates > 1 then
        if not targetIcon then
            return nil, nil, nil, nil, "ambiguous"
        end

        local exactIconCandidate
        local exactCount = 0
        for i = 1, #candidates do
            if candidates[i].icon and candidates[i].icon == targetIcon then
                exactIconCandidate = candidates[i]
                exactCount = exactCount + 1
            end
        end
        if exactCount == 1 and exactIconCandidate then
            return exactIconCandidate.index, exactIconCandidate.name, exactIconCandidate.isCharacterMacro, exactIconCandidate.icon, "name-icon"
        end
        return nil, nil, nil, nil, "ambiguous"
    end

    return nil, nil, nil, nil, "missing"
end

local function BuildMacroCandidateIndexSet(macroIndex, macroName, isCharacterMacro)
    local candidateSet = {}
    local indexNum = tonumber(macroIndex)
    if indexNum and indexNum > 0 then
        candidateSet[indexNum] = true
    end

    if type(macroName) == "string" and macroName ~= "" then
        if type(GetMacroIndexByName) == "function" then
            local byNameIndex = tonumber(GetMacroIndexByName(macroName))
            if byNameIndex and byNameIndex > 0 then
                candidateSet[byNameIndex] = true
            end
        end

        local _, numCharacter = GetNumMacros()
        local maxIndex = (MAX_ACCOUNT_MACROS or 120) + (tonumber(numCharacter) or 0)
        for index = 1, maxIndex do
            local name = GetMacroNameAndIcon(index)
            if name and name == macroName then
                if isCharacterMacro == nil or IsCharacterMacroIndex(index) == (isCharacterMacro == true) then
                    candidateSet[index] = true
                end
            end
        end
    end

    return candidateSet
end

local function ResolveMacroSlots(macroIndex, macroName, isCharacterMacro)
    local candidateIndexSet = BuildMacroCandidateIndexSet(macroIndex, macroName, isCharacterMacro)

    local function GetSlotMacroName(slot, actionID)
        if C_ActionBar and type(C_ActionBar.GetActionText) == "function" then
            local ok, actionText = pcall(C_ActionBar.GetActionText, slot)
            if ok and type(actionText) == "string" and actionText ~= "" then
                return actionText
            end
        end

        if type(actionID) == "string" and actionID ~= "" then
            return actionID
        end

        local resolvedName = GetMacroNameAndIcon(actionID)
        if (not resolvedName or resolvedName == "") and C_Macro and type(C_Macro.GetMacroName) == "function" then
            local ok, macroNameFromID = pcall(C_Macro.GetMacroName, tonumber(actionID))
            if ok and type(macroNameFromID) == "string" and macroNameFromID ~= "" then
                resolvedName = macroNameFromID
            end
        end

        if type(resolvedName) == "string" and resolvedName ~= "" then
            return resolvedName
        end

        return nil
    end

    local slots = {}
    for slot = 1, ACTION_SLOT_MAX do
        local actionType, actionID, subType = GetActionInfo(slot)
        if actionType == "macro" then
            local matched = false
            local actionIndex = tonumber(actionID)
            -- For macros with subType "spell", actionID is a spellID; never treat that
            -- numeric ID as a macro index match.
            if actionIndex and candidateIndexSet[actionIndex] and subType ~= "spell" then
                matched = true
            end

            if not matched and type(macroName) == "string" and macroName ~= "" then
                local slotMacroName = GetSlotMacroName(slot, actionID)
                if slotMacroName and slotMacroName == macroName then
                    matched = true
                end
            end

            if matched then
                slots[#slots + 1] = slot
            end
        end
    end
    return slots
end

local function ResolveSpellSlots(spellID, baseSpellID)
    local candidateIDs = {}
    if spellID and spellID > 0 then
        candidateIDs[spellID] = true
    end
    if baseSpellID and baseSpellID > 0 then
        candidateIDs[baseSpellID] = true
    end

    local slotSet = {}
    local function AddSlot(slot)
        local slotNum = tonumber(slot)
        if slotNum and slotNum > 0 then
            slotSet[slotNum] = true
        end
    end

    local function AddSlotsFromSpellID(findSpellID)
        if not findSpellID or findSpellID <= 0 then
            return
        end
        if C_ActionBar and C_ActionBar.FindSpellActionButtons then
            local ok, result = pcall(C_ActionBar.FindSpellActionButtons, findSpellID)
            if ok and type(result) == "table" then
                for i = 1, #result do
                    AddSlot(result[i])
                end
            end
        end
    end

    for findSpellID in pairs(candidateIDs) do
        AddSlotsFromSpellID(findSpellID)
    end

    -- API fallback for edge cases where FindSpellActionButtons misses variant IDs.
    if not next(slotSet) then
        for slot = 1, ACTION_SLOT_MAX do
            local actionType, actionID = GetActionInfo(slot)
            local actionSpellID = tonumber(actionID)
            if actionType == "spell" and actionSpellID and actionSpellID > 0 then
                if candidateIDs[actionSpellID] then
                    slotSet[slot] = true
                else
                    local actionBaseSpellID = GetBaseSpellID(actionSpellID)
                    if actionBaseSpellID and candidateIDs[actionBaseSpellID] then
                        slotSet[slot] = true
                    end
                end
            end
        end
    end

    return BuildLookupList(slotSet)
end

----------------------------------------------------------------------------------------
-- Entry Resolution
----------------------------------------------------------------------------------------
local function ResolveSpellEntry(entry, slotCommandIndex, specSpellIndex)
    local spellID = tonumber(entry.spellID)
    local baseSpellID = tonumber(entry.baseSpellID) or GetBaseSpellID(spellID)
    local spellInfo = nil
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        spellInfo = C_Spell.GetSpellInfo(spellID)
    end
    local displayName = spellInfo and spellInfo.name or nil
    local iconFileID = spellInfo and spellInfo.iconID or nil

    local cache = {
        kind = "spell",
        actionType = "spell",
        actionID = spellID,
        displayName = displayName,
        iconFileID = iconFileID,
        slots = {},
        keys = {},
        allKeys = {},
        state = "missing",
        reason = "spell_missing",
    }

    if not spellID or spellID <= 0 or not baseSpellID then
        return cache
    end

    if not IsSpellKnownForCurrentSpec(spellID, baseSpellID) then
        local currentValidSet = type(specSpellIndex) == "table" and specSpellIndex.currentValidSpellSet or nil
        local knownForCurrentSpec = type(currentValidSet) == "table" and (currentValidSet[spellID] or currentValidSet[baseSpellID])
        if knownForCurrentSpec then
            cache.state = "unknown"
            cache.reason = "spell_valid_current_spec_not_known"
        else
            local otherSpecLabel = GetOtherSpecLabel(specSpellIndex, spellID, baseSpellID)
            if otherSpecLabel then
                cache.state = "otherspec"
                cache.reason = "spell_known_other_spec"
                cache.statusText = otherSpecLabel
            else
                cache.state = "missing"
                cache.reason = "spell_not_known_for_spec"
            end
        end
        return cache
    end

    local slots = ResolveSpellSlots(spellID, baseSpellID)

    cache.slots = slots
    cache.baseSpellID = baseSpellID
    if #slots == 0 then
        cache.state = "missing"
        cache.reason = "spell_not_on_bar"
        return cache
    end

    local keys = CollectKeysForSlots(slots, slotCommandIndex)
    cache.allKeys = keys
    cache.keys = keys
    if #keys == 0 then
        cache.state = "unbound"
        cache.reason = "slot_has_no_binding"
        return cache
    end

    cache.state = "active"
    cache.reason = nil
    return cache
end

local function ResolveMacroEntry(self, entry, slotCommandIndex)
    local cache = {
        kind = "macro",
        actionType = "macro",
        actionID = nil,
        displayName = entry.macroName,
        iconFileID = entry.iconFileID,
        slots = {},
        keys = {},
        allKeys = {},
        state = "missing",
        reason = "macro_missing",
    }

    local resolvedIndex, macroName, isCharacterMacro, iconFileID, resolveReason = self:ResolveTrackedMacroIndex(entry)
    if not resolvedIndex then
        cache.reason = resolveReason or "macro_missing"
        return cache
    end

    cache.actionID = resolvedIndex
    cache.displayName = macroName
    cache.iconFileID = iconFileID
    cache.isCharacterMacro = isCharacterMacro == true

    if tonumber(entry.macroIndex) ~= resolvedIndex or entry.macroName ~= macroName or entry.iconFileID ~= iconFileID then
        self:UpdateTrackedMacroMetadata(entry.id, resolvedIndex, macroName, isCharacterMacro, iconFileID)
    end

    local slots = ResolveMacroSlots(resolvedIndex, macroName, isCharacterMacro)
    cache.slots = slots
    if #slots == 0 then
        cache.state = "missing"
        cache.reason = "macro_not_on_bar"
        return cache
    end

    local keys = CollectKeysForSlots(slots, slotCommandIndex)
    cache.allKeys = keys
    cache.keys = keys
    if #keys == 0 then
        cache.state = "unbound"
        cache.reason = "slot_has_no_binding"
        return cache
    end

    cache.state = "active"
    cache.reason = nil
    return cache
end

function ClickCasting:ResolveEntryForSpec(entry, slotCommandIndex, specSpellIndex)
    if entry.kind == "spell" then
        return ResolveSpellEntry(entry, slotCommandIndex, specSpellIndex)
    end
    if entry.kind == "macro" then
        return ResolveMacroEntry(self, entry, slotCommandIndex)
    end

    return {
        kind = tostring(entry.kind),
        state = "missing",
        reason = "unsupported_kind",
        keys = {},
        allKeys = {},
        slots = {},
    }
end

----------------------------------------------------------------------------------------
-- Build Cache
----------------------------------------------------------------------------------------
function ClickCasting:RebuildActiveSpecBindings()
    local specKey = self:GetActiveSpecKey()
    local entries = self:GetTrackedEntries()
    local orderedEntries = BuildEntryOrder(entries)
    local slotCommandIndex = self:BuildActionSlotCommandIndex()
    local specSpellIndex = BuildSpecSpellIndex()

    local byEntryId = {}
    local byKey = {}
    local assignedKeysByEntry = {}

    for _, entry in ipairs(orderedEntries) do
        local entryCache = self:ResolveEntryForSpec(entry, slotCommandIndex, specSpellIndex)
        byEntryId[entry.id] = entryCache
        assignedKeysByEntry[entry.id] = {}

        if entryCache.state == "active" and type(entryCache.keys) == "table" then
            for _, key in ipairs(entryCache.keys) do
                local previousEntryID = byKey[key]
                if previousEntryID and previousEntryID ~= entry.id then
                    assignedKeysByEntry[previousEntryID][key] = nil
                end
                byKey[key] = entry.id
                assignedKeysByEntry[entry.id][key] = true
            end
        end
    end

    for entryID, entryCache in pairs(byEntryId) do
        if entryCache.state == "active" then
            local winningKeys = BuildLookupList(assignedKeysByEntry[entryID] or {})
            if #winningKeys == 0 then
                entryCache.state = "conflicted"
                entryCache.reason = "shadowed"
                entryCache.keys = {}
            else
                local totalKeys = (entryCache.allKeys and #entryCache.allKeys) or #winningKeys
                entryCache.keys = winningKeys
                if #winningKeys < totalKeys then
                    entryCache.reason = "partial_conflict"
                else
                    entryCache.reason = nil
                end
            end
        end
    end

    self:SetSpecBindings(specKey, {
        byEntryId = byEntryId,
        byKey = byKey,
    })

    local activeKeyActions = {}
    for key, entryID in pairs(byKey) do
        local entryCache = byEntryId[entryID]
        if entryCache and entryCache.state == "active" then
            activeKeyActions[#activeKeyActions + 1] = {
                key = key,
                entryID = entryID,
                actionType = entryCache.actionType,
                actionID = entryCache.actionID,
                actionName = entryCache.displayName,
            }
        end
    end
    sort(activeKeyActions, function(a, b)
        return a.key < b.key
    end)

    self.runtimeActiveSpecKey = specKey
    self.runtimeActiveKeyActions = activeKeyActions
    self.runtimeActiveByEntry = byEntryId
end

function ClickCasting:GetRuntimeActiveKeyActions()
    return self.runtimeActiveKeyActions or {}
end

function ClickCasting:GetCurrentSpecBindingCache()
    local specKey = self:GetActiveSpecKey()
    return self:GetSpecBindings(specKey)
end
