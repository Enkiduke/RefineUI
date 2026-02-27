local _, RefineUI = ...
local Module = RefineUI:GetModule("CooldownAuraTrackers")

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

local TRACKED_BUFF = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local HIDDEN_AURA = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.HiddenAura) or -2

local ALL_AURA_CATEGORIES = { TRACKED_BUFF, TRACKED_BAR, HIDDEN_AURA }
local LAYOUT_STATUS_SUCCESS = Enum and Enum.CooldownLayoutStatus and Enum.CooldownLayoutStatus.Success
local validAuraIDsCache = {}
local cooldownDisplayNameCache = {}
local cooldownDisplayNameLowerCache = {}

local function BuildBucketSet()
    local set = {}
    for i = 1, #Module.TRACKER_BUCKETS do
        set[Module.TRACKER_BUCKETS[i]] = true
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
    for i = 1, #Module.TRACKER_BUCKETS do
        local bucket = Module.TRACKER_BUCKETS[i]
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
    local settingsFrame = Module:GetCooldownViewerSettingsFrame()
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

function Module:InitializeAssignments()
    local cfg = self:GetConfig()
    cfg.LayoutAssignments = cfg.LayoutAssignments or {}
    self:MarkAssignmentsPruneDirty()
end

function Module:InvalidateValidAuraCooldownIDCache()
    if wipe then
        wipe(validAuraIDsCache)
        return
    end
    for key in pairs(validAuraIDsCache) do
        validAuraIDsCache[key] = nil
    end
end

function Module:InvalidateCooldownDisplayNameCache()
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

function Module:MarkAssignmentsPruneDirty()
    self.assignmentsPruneDirty = true
    self:InvalidateValidAuraCooldownIDCache()
    self:InvalidateCooldownDisplayNameCache()
    if self.MarkAssignedCooldownSnapshotDirty then
        self:MarkAssignedCooldownSnapshotDirty()
    end
end

function Module:GetCurrentClassSpecTag()
    if _G.CooldownViewerUtil and type(_G.CooldownViewerUtil.GetCurrentClassAndSpecTag) == "function" then
        local tag = _G.CooldownViewerUtil.GetCurrentClassAndSpecTag()
        if tag then
            return tag
        end
    end
    return GetFallbackClassSpecTag()
end

function Module:GetActiveLayoutID()
    return GetLayoutIDFromManager()
end

function Module:GetCurrentLayoutKey()
    local layoutID = self:GetActiveLayoutID() or 0
    local classSpecTag = self:GetCurrentClassSpecTag() or 0
    return tostring(layoutID) .. ":" .. tostring(classSpecTag)
end

function Module:GetScopedAssignments(layoutKey)
    local cfg = self:GetConfig()
    local assignments = cfg.LayoutAssignments
    local key = layoutKey or self:GetCurrentLayoutKey()
    return EnsureScopedAssignments(assignments, key), key
end

function Module:GetCurrentAssignments()
    return self:GetScopedAssignments(self:GetCurrentLayoutKey())
end

function Module:GetCooldownViewerDataProvider()
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

function Module:GetAssignedIDSet(assignments)
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

function Module:GetCooldownInfo(cooldownID)
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

function Module:ResolveCooldownSpellID(info)
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

function Module:GetCooldownDisplayName(cooldownID)
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

function Module:GetCooldownDisplayNameLower(cooldownID)
    local cached = cooldownDisplayNameLowerCache[cooldownID]
    if cached ~= nil then
        return cached
    end

    local lowered = strlower(self:GetCooldownDisplayName(cooldownID) or "")
    cooldownDisplayNameLowerCache[cooldownID] = lowered
    return lowered
end

function Module:GetSourceCategoryList()
    if self.GetSourceScope and self:GetSourceScope() == "buffs_exact" then
        return { TRACKED_BUFF, HIDDEN_AURA }
    end
    return ALL_AURA_CATEGORIES
end

function Module:GetValidAuraCooldownIDs(includeUnlearned)
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

function Module:SyncAssignedCooldownsToTrackedBuff(layoutKey)
    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        return false, false
    end

    if not TRACKED_BUFF then
        return false, false
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, false
    end

    local provider, settingsFrame = self:GetCooldownViewerDataProvider()
    if not provider or type(provider.SetCooldownToCategory) ~= "function" then
        return false, false
    end
    if not settingsFrame or not settingsFrame:IsShown() then
        return false, false
    end

    local layoutManager = nil
    if settingsFrame and type(settingsFrame.GetLayoutManager) == "function" then
        layoutManager = settingsFrame:GetLayoutManager()
    elseif type(provider.GetLayoutManager) == "function" then
        layoutManager = provider:GetLayoutManager()
    end

    if self:IsLayoutManagerBusy(layoutManager) then
        return false, false
    end

    local scoped = self:GetScopedAssignments(layoutKey)
    local assignedSet = self:GetAssignedIDSet(scoped)
    local changed = false
    local lockApplied = false

    local function IsSuccessStatus(status)
        if status == nil then
            return true
        end
        if LAYOUT_STATUS_SUCCESS ~= nil then
            return status == LAYOUT_STATUS_SUCCESS
        end
        return status == true or status == 0
    end

    if layoutManager and type(layoutManager.LockNotifications) == "function" then
        local okLock = pcall(layoutManager.LockNotifications, layoutManager)
        lockApplied = okLock and true or false
    end

    for cooldownID in pairs(assignedSet) do
        if IsUsableCooldownID(cooldownID) then
            local info = provider.GetCooldownInfoForID and provider:GetCooldownInfoForID(cooldownID)
            local currentCategory = info and info.category
            if currentCategory ~= TRACKED_BUFF then
                local okSet, status = pcall(provider.SetCooldownToCategory, provider, cooldownID, TRACKED_BUFF)
                if okSet and IsSuccessStatus(status) then
                    changed = true
                end
            end
        end
    end

    if lockApplied and layoutManager and type(layoutManager.UnlockNotifications) == "function" then
        pcall(layoutManager.UnlockNotifications, layoutManager, false)
    end

    if changed then
        if type(provider.MarkDirty) == "function" then
            pcall(provider.MarkDirty, provider)
        end
        if settingsFrame and type(settingsFrame.SaveCurrentLayout) == "function" then
            pcall(settingsFrame.SaveCurrentLayout, settingsFrame)
        end
        if self.MarkReloadRecommendationPending then
            self:MarkReloadRecommendationPending()
        end
    end

    return changed, true
end

function Module:SyncCurrentLayoutToTrackedBuff()
    return self:SyncAssignedCooldownsToTrackedBuff(self:GetCurrentLayoutKey())
end

function Module:HasUnsafeSecretCooldownState()
    return false
end

function Module:IsLayoutManagerBusy(layoutManager)
    local manager = layoutManager
    if not manager then
        local settingsFrame = self:GetCooldownViewerSettingsFrame()
        if settingsFrame and type(settingsFrame.GetLayoutManager) == "function" then
            manager = settingsFrame:GetLayoutManager()
        end
    end

    if not manager then
        return false
    end

    if type(manager.AreNotificationsLocked) == "function" then
        local okLocked, isLocked = pcall(manager.AreNotificationsLocked, manager)
        if okLocked and not (issecretvalue and issecretvalue(isLocked)) and isLocked then
            return true
        end
    end

    if not (issecretvalue and issecretvalue(manager.notificationLockCount))
        and type(manager.notificationLockCount) == "number"
        and manager.notificationLockCount > 0
    then
        return true
    end

    if not (issecretvalue and issecretvalue(manager.notifying)) and manager.notifying == true then
        return true
    end

    return false
end

function Module:ScheduleTrackedBuffSyncRetry()
    -- Settings-flow-only sync path: no background retry loop.
    return false
end

function Module:RequestTrackedBuffSync(layoutKey)
    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        return false
    end

    self.pendingTrackedBuffSync = true
    self.pendingTrackedBuffSyncKey = layoutKey or self:GetCurrentLayoutKey()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and settingsFrame:IsShown() then
        return self:ProcessPendingTrackedBuffSync()
    end
    return false
end

function Module:ProcessPendingTrackedBuffSync()
    if not self.pendingTrackedBuffSync then
        return false
    end

    if self.GetSyncStrategy and self:GetSyncStrategy() == "mirror_only" then
        self.pendingTrackedBuffSync = nil
        self.pendingTrackedBuffSyncKey = nil
        return true
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if not settingsFrame or not settingsFrame:IsShown() then
        return false
    end

    local provider = self:GetCooldownViewerDataProvider()
    if not provider then
        return false
    end

    local changed, attempted = self:SyncAssignedCooldownsToTrackedBuff(self.pendingTrackedBuffSyncKey)
    if not attempted then
        return false
    end

    self.pendingTrackedBuffSync = nil
    self.pendingTrackedBuffSyncKey = nil
    return changed or true
end

function Module:AssignCooldownToBucket(cooldownID, bucketName, destIndex, layoutKey)
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

function Module:UnassignCooldownID(cooldownID, layoutKey)
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

function Module:GetSortedNotTrackedIDs(validIDs, assignments)
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

function Module:GetVisibleBucketCooldownIDs(bucketCooldownIDs, visibleSet)
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

function Module:PruneAssignments(layoutKey, validSet)
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

function Module:PruneCurrentLayoutAssignments()
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

function Module:GetBucketCooldownIDs(bucketName, layoutKey)
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
