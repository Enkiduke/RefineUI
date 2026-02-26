----------------------------------------------------------------------------------------
-- CDM Component: AssignmentsData
-- Description: Assignment data model, lookup, pruning, and cooldown metadata helpers.
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
local tonumber = tonumber
local tostring = tostring
local strlower = string.lower
local wipe = _G.wipe or table.wipe
local tinsert = table.insert
local tremove = table.remove

local UnitClass = UnitClass
local GetCVarBool = GetCVarBool
local C_CooldownViewer = C_CooldownViewer
local C_SpecializationInfo = C_SpecializationInfo
local C_Spell = C_Spell
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKED_BUFF = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local HIDDEN_AURA = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenAura) or -2

local ALL_AURA_CATEGORIES = { TRACKED_BUFF, TRACKED_BAR, HIDDEN_AURA }
local LAYOUT_STATUS_SUCCESS = Enum and Enum.CooldownLayoutStatus and Enum.CooldownLayoutStatus.Success
local validAuraIDsCache = {}
local cooldownDisplayNameCache = {}
local cooldownDisplayNameLowerCache = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function BuildBucketSet()
    local set = {}
    for i = 1, #CDM.TRACKER_BUCKETS do
        set[CDM.TRACKER_BUCKETS[i]] = true
    end
    return set
end

local TRACKER_BUCKET_SET = BuildBucketSet()

local function IsUsableCooldownID(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return type(value) == "number" and value > 0
end

local function ClampInsertIndex(index, count)
    local value = tonumber(index)
    if not value then
        return count + 1
    end
    if value < 1 then
        return 1
    end
    if value > (count + 1) then
        return count + 1
    end
    return value
end

local function RemoveFromArray(list, targetID)
    local changed = false
    for i = #list, 1, -1 do
        if list[i] == targetID then
            tremove(list, i)
            changed = true
        end
    end
    return changed
end

local function EnsureScopedAssignments(assignments, key)
    assignments[key] = assignments[key] or {}
    local scoped = assignments[key]
    for i = 1, #CDM.TRACKER_BUCKETS do
        local bucket = CDM.TRACKER_BUCKETS[i]
        if type(scoped[bucket]) ~= "table" then
            scoped[bucket] = {}
        end
    end
    return scoped
end

local function ToSet(values)
    local set = {}
    for i = 1, #values do
        set[values[i]] = true
    end
    return set
end

local function GetLayoutIDFromManager()
    local settingsFrame = CDM:GetCooldownViewerSettingsFrame()
    if not settingsFrame or type(settingsFrame.GetLayoutManager) ~= "function" then
        return 0
    end

    local layoutManager = settingsFrame:GetLayoutManager()
    if not layoutManager then
        return 0
    end

    if type(layoutManager.GetActiveLayout) == "function" then
        local accessOnly = Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly
        local layout = layoutManager:GetActiveLayout(accessOnly)
        if layout and type(_G.CooldownManagerLayout_GetID) == "function" then
            local layoutID = _G.CooldownManagerLayout_GetID(layout)
            if type(layoutID) == "number" then
                return layoutID
            end
        end
    end

    if type(layoutManager.GetActiveLayoutID) == "function" then
        local layoutID = layoutManager:GetActiveLayoutID()
        if type(layoutID) == "number" then
            return layoutID
        end
    end

    return 0
end

local function GetFallbackClassSpecTag()
    local classID = select(3, UnitClass("player"))
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
    if classID and specIndex then
        return (classID * 10) + specIndex
    end
    return 0
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InitializeAssignments()
    local cfg = self:GetConfig()
    cfg.LayoutAssignments = cfg.LayoutAssignments or {}
    self:MarkAssignmentsPruneDirty()
end


function CDM:InvalidateValidAuraCooldownIDCache()
    if wipe then
        wipe(validAuraIDsCache)
        return
    end
    for key in pairs(validAuraIDsCache) do
        validAuraIDsCache[key] = nil
    end
end


function CDM:InvalidateCooldownDisplayNameCache()
    if wipe then
        wipe(cooldownDisplayNameCache)
        wipe(cooldownDisplayNameLowerCache)
        return
    end
    for key in pairs(cooldownDisplayNameCache) do
        cooldownDisplayNameCache[key] = nil
    end
    for key in pairs(cooldownDisplayNameLowerCache) do
        cooldownDisplayNameLowerCache[key] = nil
    end
end


function CDM:MarkAssignmentsPruneDirty()
    self.assignmentsPruneDirty = true
    self:InvalidateValidAuraCooldownIDCache()
    self:InvalidateCooldownDisplayNameCache()
    if self.MarkAssignedCooldownSnapshotDirty then
        self:MarkAssignedCooldownSnapshotDirty()
    end
end


function CDM:GetCurrentClassSpecTag()
    if _G.CooldownViewerUtil and type(_G.CooldownViewerUtil.GetCurrentClassAndSpecTag) == "function" then
        local tag = _G.CooldownViewerUtil.GetCurrentClassAndSpecTag()
        if tag then
            return tag
        end
    end
    return GetFallbackClassSpecTag()
end


function CDM:GetActiveLayoutID()
    return GetLayoutIDFromManager()
end


function CDM:GetCurrentLayoutKey()
    local layoutID = self:GetActiveLayoutID() or 0
    local classSpecTag = self:GetCurrentClassSpecTag() or 0
    return tostring(layoutID) .. ":" .. tostring(classSpecTag)
end


function CDM:GetScopedAssignments(layoutKey)
    local cfg = self:GetConfig()
    local assignments = cfg.LayoutAssignments
    local key = layoutKey or self:GetCurrentLayoutKey()
    return EnsureScopedAssignments(assignments, key), key
end


function CDM:GetCurrentAssignments()
    return self:GetScopedAssignments(self:GetCurrentLayoutKey())
end


function CDM:GetCooldownViewerDataProvider()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and type(settingsFrame.GetDataProvider) == "function" then
        local provider = settingsFrame:GetDataProvider()
        if provider then
            return provider, settingsFrame
        end
    end
    local provider = _G.CooldownViewerDataProvider
    if provider then
        return provider, settingsFrame
    end
    return nil, settingsFrame
end


function CDM:GetAssignedIDSet(assignments)
    local assigned = {}
    local scoped = assignments or self:GetCurrentAssignments()
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local ids = scoped[bucket]
        for n = 1, #ids do
            assigned[ids[n]] = true
        end
    end
    return assigned
end


function CDM:GetCooldownInfo(cooldownID)
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and type(settingsFrame.GetDataProvider) == "function" then
        local provider = settingsFrame:GetDataProvider()
        if provider and type(provider.GetCooldownInfoForID) == "function" then
            local info = provider:GetCooldownInfoForID(cooldownID)
            if info then
                return info
            end
        end
    end

    if C_CooldownViewer and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        return C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    end

    return nil
end


function CDM:ResolveCooldownSpellID(info)
    if not info then
        return nil
    end
    if info.overrideTooltipSpellID then
        return info.overrideTooltipSpellID
    end
    if info.overrideSpellID then
        return info.overrideSpellID
    end
    return info.spellID
end


function CDM:GetCooldownDisplayName(cooldownID)
    local cached = cooldownDisplayNameCache[cooldownID]
    if cached ~= nil then
        return cached
    end

    local info = self:GetCooldownInfo(cooldownID)
    local spellID = self:ResolveCooldownSpellID(info)
    local resolvedName = nil
    if spellID and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local name = C_Spell.GetSpellName(spellID)
        if name and (not issecretvalue or not issecretvalue(name)) and name ~= "" then
            resolvedName = name
        end
    end

    if resolvedName == nil then
        resolvedName = tostring(cooldownID)
    end

    cooldownDisplayNameCache[cooldownID] = resolvedName
    return resolvedName
end


function CDM:GetCooldownDisplayNameLower(cooldownID)
    local cached = cooldownDisplayNameLowerCache[cooldownID]
    if cached ~= nil then
        return cached
    end

    local lowered = strlower(self:GetCooldownDisplayName(cooldownID) or "")
    cooldownDisplayNameLowerCache[cooldownID] = lowered
    return lowered
end


function CDM:GetSourceCategoryList()
    if self.GetSourceScope and self:GetSourceScope() == "buffs_exact" then
        return { TRACKED_BUFF, HIDDEN_AURA }
    end
    return ALL_AURA_CATEGORIES
end


function CDM:GetValidAuraCooldownIDs(includeUnlearned)
    local showUnlearned = includeUnlearned
    if showUnlearned == nil then
        showUnlearned = GetCVarBool and GetCVarBool("cooldownViewerShowUnlearned") or false
    end

    local sourceScope = self.GetSourceScope and self:GetSourceScope() or "buffs_exact"
    local cacheKey = tostring(self:GetCurrentLayoutKey()) .. ":" .. tostring(sourceScope) .. ":" .. (showUnlearned and "1" or "0")
    local cachedIDs = validAuraIDsCache[cacheKey]
    if type(cachedIDs) == "table" then
        return cachedIDs
    end

    local orderedIDs = {}
    local seen = {}

    local categoryList = self:GetSourceCategoryList()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    local provider = settingsFrame and settingsFrame.GetDataProvider and settingsFrame:GetDataProvider()
    if provider and type(provider.GetOrderedCooldownIDsForCategory) == "function" then
        for i = 1, #categoryList do
            local category = categoryList[i]
            if category ~= nil then
                local ids = provider:GetOrderedCooldownIDsForCategory(category, showUnlearned)
                if type(ids) == "table" then
                    for n = 1, #ids do
                        local cooldownID = ids[n]
                        if IsUsableCooldownID(cooldownID) and not seen[cooldownID] then
                            seen[cooldownID] = true
                            tinsert(orderedIDs, cooldownID)
                        end
                    end
                end
            end
        end
    elseif C_CooldownViewer and type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function" then
        for i = 1, #categoryList do
            local category = categoryList[i]
            if type(category) == "number" then
                local ids = C_CooldownViewer.GetCooldownViewerCategorySet(category, showUnlearned)
                if type(ids) == "table" then
                    for n = 1, #ids do
                        local cooldownID = ids[n]
                        if IsUsableCooldownID(cooldownID) and not seen[cooldownID] then
                            seen[cooldownID] = true
                            tinsert(orderedIDs, cooldownID)
                        end
                    end
                end
            end
        end
    end

    if #orderedIDs > 0 then
        validAuraIDsCache[cacheKey] = orderedIDs
    end

    return orderedIDs
end


function CDM:AssignCooldownToBucket(cooldownID, bucketName, destIndex, layoutKey)
    if not TRACKER_BUCKET_SET[bucketName] then
        return false
    end

    local scoped = self:GetScopedAssignments(layoutKey)
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        RemoveFromArray(scoped[bucket], cooldownID)
    end

    local targetList = scoped[bucketName]
    local insertIndex = ClampInsertIndex(destIndex, #targetList)
    tinsert(targetList, insertIndex, cooldownID)
    if self.MarkAssignedCooldownSnapshotDirty then
        self:MarkAssignedCooldownSnapshotDirty()
    end
    if self.MarkReloadRecommendationPending then
        self:MarkReloadRecommendationPending()
    end
    self:RequestTrackedBuffSync(layoutKey)
    return true
end


function CDM:UnassignCooldownID(cooldownID, layoutKey)
    local scoped = self:GetScopedAssignments(layoutKey)
    local changed = false
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        changed = RemoveFromArray(scoped[bucket], cooldownID) or changed
    end
    if changed and self.MarkReloadRecommendationPending then
        self:MarkReloadRecommendationPending()
    end
    if changed then
        if self.MarkAssignedCooldownSnapshotDirty then
            self:MarkAssignedCooldownSnapshotDirty()
        end
        self:RequestTrackedBuffSync(layoutKey)
    end
    return changed
end


function CDM:GetSortedNotTrackedIDs(validIDs, assignments)
    local assigned = self:GetAssignedIDSet(assignments)
    local notTracked = {}
    for i = 1, #validIDs do
        local cooldownID = validIDs[i]
        if not assigned[cooldownID] then
            tinsert(notTracked, cooldownID)
        end
    end

    return notTracked
end


function CDM:GetVisibleBucketCooldownIDs(bucketCooldownIDs, visibleSet)
    local visibleCooldownIDs = {}
    local visibleAssignmentIndices = {}
    if type(bucketCooldownIDs) ~= "table" or type(visibleSet) ~= "table" then
        return visibleCooldownIDs, visibleAssignmentIndices
    end

    for assignmentIndex = 1, #bucketCooldownIDs do
        local cooldownID = bucketCooldownIDs[assignmentIndex]
        if visibleSet[cooldownID] then
            tinsert(visibleCooldownIDs, cooldownID)
            tinsert(visibleAssignmentIndices, assignmentIndex)
        end
    end

    return visibleCooldownIDs, visibleAssignmentIndices
end


function CDM:PruneAssignments(layoutKey, validSet)
    local scoped = self:GetScopedAssignments(layoutKey)
    local changed = false
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local list = scoped[bucket]
        for n = #list, 1, -1 do
            local cooldownID = list[n]
            if not validSet[cooldownID] then
                tremove(list, n)
                changed = true
            end
        end
    end
    return changed
end


function CDM:PruneCurrentLayoutAssignments()
    local validIDs = self:GetValidAuraCooldownIDs(true)
    if #validIDs == 0 then
        return false
    end
    local validSet = ToSet(validIDs)
    local changed = self:PruneAssignments(self:GetCurrentLayoutKey(), validSet)
    if changed and self.MarkAssignedCooldownSnapshotDirty then
        self:MarkAssignedCooldownSnapshotDirty()
    end
    self.assignmentsPruneDirty = nil
    return changed
end


function CDM:GetBucketCooldownIDs(bucketName, layoutKey)
    if not TRACKER_BUCKET_SET[bucketName] then
        return {}
    end
    local scoped = self:GetScopedAssignments(layoutKey)
    local ids = {}
    for i = 1, #scoped[bucketName] do
        ids[i] = scoped[bucketName][i]
    end
    return ids
end
