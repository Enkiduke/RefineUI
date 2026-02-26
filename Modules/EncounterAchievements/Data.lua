----------------------------------------------------------------------------------------
-- EncounterAchievements Data
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterAchievements = RefineUI:GetModule("EncounterAchievements")
if not EncounterAchievements then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local next = next
local pairs = pairs
local sort = table.sort
local tostring = tostring
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DUNGEONS_AND_RAIDS_CATEGORY_ID = 168
local DEFAULT_ICON_FILE_ID = 134400
local ASYNC_SCAN_ACHIEVEMENTS_PER_TICK = 50
local ASYNC_SCAN_TICK_INTERVAL_SECONDS = 0.01

local MANUAL_INSTANCE_CATEGORY_OVERRIDES = {
    -- [journalInstanceID] = categoryID
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function NormalizeToken(text)
    if type(text) ~= "string" then
        return ""
    end

    local token = text:lower()
    token = token:gsub("|c%x%x%x%x%x%x%x%x", "")
    token = token:gsub("|r", "")
    token = token:gsub("[%s]+", "")
    token = token:gsub("[%p%c]+", "")
    return token
end

local function ResolveCategoryInfo(categoryID)
    local title, parentID = GetCategoryInfo(categoryID)

    if type(title) == "table" then
        parentID = title.parentID
        title = title.title or title.name
    end

    return title, tonumber(parentID) or -1
end

local function GetAchievementCategoryIDList()
    if type(GetCategoryList) ~= "function" then
        return {}
    end

    local packed = { GetCategoryList() }
    local source
    if #packed == 1 and type(packed[1]) == "table" then
        source = packed[1]
    else
        source = packed
    end

    local categoryIDs = {}
    local seen = {}

    for _, rawCategoryID in pairs(source) do
        local categoryID = tonumber(rawCategoryID)
        if categoryID and categoryID > 0 and not seen[categoryID] then
            seen[categoryID] = true
            categoryIDs[#categoryIDs + 1] = categoryID
        end
    end

    sort(categoryIDs)
    return categoryIDs
end

local function BuildCategoryNode(categoryID, title, parentID)
    return {
        id = categoryID,
        title = title or "",
        parentID = parentID or -1,
        normalizedTitle = NormalizeToken(title),
        children = {},
    }
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function EncounterAchievements:InitializeData()
    self:CancelPendingInstanceRowBuilds()

    self._categoryGraph = nil
    self._allCategoryIDs = nil

    self._categoryPathCache = {}
    self._categoryPathTokenCache = {}
    self._categoryDepthCache = {}

    self._instanceCategoryCache = {}
    self._instanceAchievementCache = {}
    self._instanceRowCache = {}

    self._pendingInstanceRowBuilds = {}
    self._pendingInstanceRowBuildQueue = {}
    self._instanceRowBuildTicker = nil
end

----------------------------------------------------------------------------------------
-- Category Graph
----------------------------------------------------------------------------------------
function EncounterAchievements:BuildCategoryGraph()
    local categoryIDs = GetAchievementCategoryIDList()
    local graph = {}

    for _, rawCategoryID in ipairs(categoryIDs) do
        local categoryID = tonumber(rawCategoryID)
        if categoryID and categoryID > 0 then
            local title, parentID = ResolveCategoryInfo(categoryID)
            graph[categoryID] = BuildCategoryNode(categoryID, title, parentID)
        end
    end

    -- Ensure referenced parents exist in the graph.
    local addedParent = true
    local safety = 0
    while addedParent and safety < 32 do
        addedParent = false
        for _, node in pairs(graph) do
            local parentID = node.parentID
            if parentID and parentID > 0 and not graph[parentID] then
                local title, parentParentID = ResolveCategoryInfo(parentID)
                graph[parentID] = BuildCategoryNode(parentID, title, parentParentID)
                addedParent = true
            end
        end
        safety = safety + 1
    end

    -- Build child lists.
    for _, node in pairs(graph) do
        local parentID = node.parentID
        if parentID and parentID > 0 then
            local parentNode = graph[parentID]
            if parentNode then
                parentNode.children[#parentNode.children + 1] = node.id
            end
        end
    end

    -- Stable ordering for deterministic traversal.
    for _, node in pairs(graph) do
        sort(node.children, function(leftID, rightID)
            local leftNode = graph[leftID]
            local rightNode = graph[rightID]
            local leftTitle = leftNode and leftNode.title or ""
            local rightTitle = rightNode and rightNode.title or ""
            if leftTitle == rightTitle then
                return leftID < rightID
            end
            return leftTitle < rightTitle
        end)
    end

    local allCategoryIDs = {}
    for categoryID in pairs(graph) do
        allCategoryIDs[#allCategoryIDs + 1] = categoryID
    end
    sort(allCategoryIDs)

    self._categoryGraph = graph
    self._allCategoryIDs = allCategoryIDs

    return graph
end

function EncounterAchievements:GetCategoryGraph()
    if type(self._categoryGraph) ~= "table" or not next(self._categoryGraph) then
        return self:BuildCategoryGraph()
    end
    return self._categoryGraph
end

function EncounterAchievements:GetAllCategoryIDs()
    if type(self._allCategoryIDs) ~= "table" or #self._allCategoryIDs == 0 then
        self:BuildCategoryGraph()
    end
    return self._allCategoryIDs or {}
end

function EncounterAchievements:HasCategoryData()
    local graph = self:GetCategoryGraph()
    return type(graph) == "table" and next(graph) ~= nil
end

function EncounterAchievements:GetCategoryNode(categoryID)
    local graph = self:GetCategoryGraph()
    return graph[categoryID]
end

function EncounterAchievements:GetPreferredRootCategoryID()
    local graph = self:GetCategoryGraph()
    if graph[DUNGEONS_AND_RAIDS_CATEGORY_ID] then
        return DUNGEONS_AND_RAIDS_CATEGORY_ID
    end

    local combinedToken = NormalizeToken((DUNGEONS or "") .. (RAIDS or ""))
    if combinedToken ~= "" then
        for categoryID, node in pairs(graph) do
            if node.parentID == -1 and node.normalizedTitle == combinedToken then
                return categoryID
            end
        end
    end

    local dungeonToken = NormalizeToken(DUNGEONS)
    local raidToken = NormalizeToken(RAIDS)
    if dungeonToken ~= "" and raidToken ~= "" then
        for categoryID, node in pairs(graph) do
            if node.parentID == -1
                and node.normalizedTitle ~= ""
                and string.find(node.normalizedTitle, dungeonToken, 1, true)
                and string.find(node.normalizedTitle, raidToken, 1, true) then
                return categoryID
            end
        end
    end

    return nil
end

function EncounterAchievements:GetBranchRootCategoryID(rootCategoryID, isRaid)
    local graph = self:GetCategoryGraph()
    local rootNode = graph[rootCategoryID]
    if not rootNode then
        return nil
    end

    local targetToken = NormalizeToken(isRaid and RAIDS or DUNGEONS)
    if targetToken == "" then
        return nil
    end

    for _, childCategoryID in ipairs(rootNode.children) do
        local childNode = graph[childCategoryID]
        if childNode and childNode.normalizedTitle == targetToken then
            return childCategoryID
        end
    end

    for _, childCategoryID in ipairs(rootNode.children) do
        local childNode = graph[childCategoryID]
        if childNode and childNode.normalizedTitle ~= "" and string.find(childNode.normalizedTitle, targetToken, 1, true) then
            return childCategoryID
        end
    end

    return nil
end

function EncounterAchievements:GetDescendantCategoryIDs(rootCategoryID, includeRoot)
    local graph = self:GetCategoryGraph()
    local rootNode = graph[rootCategoryID]
    if not rootNode then
        return {}
    end

    local descendants = {}

    local function Traverse(categoryID)
        local node = graph[categoryID]
        if not node then
            return
        end
        descendants[#descendants + 1] = categoryID
        for _, childCategoryID in ipairs(node.children) do
            Traverse(childCategoryID)
        end
    end

    if includeRoot then
        Traverse(rootCategoryID)
    else
        for _, childCategoryID in ipairs(rootNode.children) do
            Traverse(childCategoryID)
        end
    end

    return descendants
end

----------------------------------------------------------------------------------------
-- Category Path Helpers
----------------------------------------------------------------------------------------
function EncounterAchievements:GetCategoryDepth(categoryID)
    local cachedDepth = self._categoryDepthCache and self._categoryDepthCache[categoryID]
    if type(cachedDepth) == "number" then
        return cachedDepth
    end

    local graph = self:GetCategoryGraph()
    local depth = 0
    local cursor = categoryID
    local safety = 0

    while cursor and safety < 64 do
        local node = graph[cursor]
        if not node then
            break
        end

        local parentID = node.parentID
        if not parentID or parentID <= 0 then
            break
        end

        depth = depth + 1
        cursor = parentID
        safety = safety + 1
    end

    self._categoryDepthCache[categoryID] = depth
    return depth
end

function EncounterAchievements:GetCategoryPath(categoryID, separator)
    separator = separator or " > "

    local cachedPath = self._categoryPathCache and self._categoryPathCache[categoryID]
    if type(cachedPath) == "string" then
        return cachedPath
    end

    local graph = self:GetCategoryGraph()
    local segments = {}

    local cursor = categoryID
    local safety = 0
    while cursor and safety < 64 do
        local node = graph[cursor]
        if not node then
            break
        end

        segments[#segments + 1] = node.title or ""

        if not node.parentID or node.parentID <= 0 then
            break
        end

        cursor = node.parentID
        safety = safety + 1
    end

    local count = #segments
    for index = 1, math.floor(count / 2) do
        local opposite = count - index + 1
        segments[index], segments[opposite] = segments[opposite], segments[index]
    end

    local path = table.concat(segments, separator)
    self._categoryPathCache[categoryID] = path
    return path
end

function EncounterAchievements:GetCategoryPathToken(categoryID)
    local cachedToken = self._categoryPathTokenCache and self._categoryPathTokenCache[categoryID]
    if type(cachedToken) == "string" then
        return cachedToken
    end

    local pathToken = NormalizeToken(self:GetCategoryPath(categoryID, " "))
    self._categoryPathTokenCache[categoryID] = pathToken
    return pathToken
end

function EncounterAchievements:GetCurrentExpansionToken()
    if type(EJ_GetCurrentTier) ~= "function" or type(EJ_GetTierInfo) ~= "function" then
        return ""
    end

    local tier = EJ_GetCurrentTier()
    if type(tier) ~= "number" then
        return ""
    end

    return NormalizeToken(EJ_GetTierInfo(tier))
end

----------------------------------------------------------------------------------------
-- Instance -> Category Resolution
----------------------------------------------------------------------------------------
function EncounterAchievements:ScoreCategoryMatch(categoryID, instanceToken, expansionToken)
    local node = self:GetCategoryNode(categoryID)
    if not node then
        return nil
    end

    local categoryToken = node.normalizedTitle
    if categoryToken == "" or instanceToken == "" then
        return nil
    end

    local score
    if categoryToken == instanceToken then
        score = 1000
    elseif string.find(categoryToken, instanceToken, 1, true) then
        score = 700
    elseif string.find(instanceToken, categoryToken, 1, true) then
        score = 650
    else
        local pathToken = self:GetCategoryPathToken(categoryID)
        if pathToken ~= "" and string.find(pathToken, instanceToken, 1, true) then
            score = 550
        end
    end

    if not score then
        return nil
    end

    if expansionToken ~= "" then
        local pathToken = self:GetCategoryPathToken(categoryID)
        if pathToken ~= "" and string.find(pathToken, expansionToken, 1, true) then
            score = score + 100
        end
    end

    score = score + self:GetCategoryDepth(categoryID)
    return score
end

function EncounterAchievements:ResolveCategoryForInstance(instanceID, isRaid)
    local graph = self:GetCategoryGraph()
    if not next(graph) then
        return nil
    end

    local manualOverrideCategoryID = MANUAL_INSTANCE_CATEGORY_OVERRIDES[instanceID]
    if manualOverrideCategoryID and graph[manualOverrideCategoryID] then
        return manualOverrideCategoryID
    end

    local instanceName = EJ_GetInstanceInfo(instanceID)
    local instanceToken = NormalizeToken(instanceName)
    if instanceToken == "" then
        return nil
    end

    local expansionToken = self:GetCurrentExpansionToken()
    local rootCategoryID = self:GetPreferredRootCategoryID()

    local candidateCategoryIDs = {}
    if rootCategoryID then
        local branchRootCategoryID = self:GetBranchRootCategoryID(rootCategoryID, isRaid)
        if branchRootCategoryID then
            candidateCategoryIDs = self:GetDescendantCategoryIDs(branchRootCategoryID, true)
        else
            candidateCategoryIDs = self:GetDescendantCategoryIDs(rootCategoryID, true)
        end
    else
        candidateCategoryIDs = self:GetAllCategoryIDs()
    end

    local bestCategoryID
    local bestScore
    for _, categoryID in ipairs(candidateCategoryIDs) do
        local score = self:ScoreCategoryMatch(categoryID, instanceToken, expansionToken)
        if score and (not bestScore or score > bestScore) then
            bestCategoryID = categoryID
            bestScore = score
        end
    end

    if bestCategoryID then
        return bestCategoryID
    end

    -- Fallback: exact title match across all categories.
    for _, categoryID in ipairs(self:GetAllCategoryIDs()) do
        local node = graph[categoryID]
        if node and node.normalizedTitle == instanceToken then
            return categoryID
        end
    end

    -- Fallback: best path token match if no direct title match exists.
    local bestPathMatchCategoryID
    local bestPathMatchDepth
    for _, categoryID in ipairs(self:GetAllCategoryIDs()) do
        local pathToken = self:GetCategoryPathToken(categoryID)
        if pathToken ~= "" and string.find(pathToken, instanceToken, 1, true) then
            local depth = self:GetCategoryDepth(categoryID)
            if not bestPathMatchDepth or depth > bestPathMatchDepth then
                bestPathMatchCategoryID = categoryID
                bestPathMatchDepth = depth
            end
        end
    end

    if bestPathMatchCategoryID then
        return bestPathMatchCategoryID
    end

    return nil
end

function EncounterAchievements:GetResolvedCategoryForInstance(instanceID, isRaid)
    if type(instanceID) ~= "number" or instanceID <= 0 then
        return nil
    end

    local cachedValue = self._instanceCategoryCache[instanceID]
    if cachedValue ~= nil then
        return cachedValue or nil
    end

    local resolvedCategoryID = self:ResolveCategoryForInstance(instanceID, isRaid)
    if resolvedCategoryID then
        self._instanceCategoryCache[instanceID] = resolvedCategoryID
    elseif self:HasCategoryData() then
        self._instanceCategoryCache[instanceID] = false
    end

    return resolvedCategoryID
end

----------------------------------------------------------------------------------------
-- Category -> Achievement Resolution
----------------------------------------------------------------------------------------
function EncounterAchievements:BuildRowsFromAchievementIDs(achievementIDs)
    local rows = {}

    for _, achievementID in ipairs(achievementIDs or {}) do
        local _, name, _, _, _, _, _, description, _, icon, rewardText = GetAchievementInfo(achievementID)
        local achievementCategoryID = GetAchievementCategory(achievementID)

        rows[#rows + 1] = {
            achievementID = achievementID,
            name = name or tostring(achievementID),
            description = description or "",
            icon = icon or DEFAULT_ICON_FILE_ID,
            rewardText = rewardText or "",
            categoryPath = self:GetCategoryPath(achievementCategoryID, " > "),
        }
    end

    return rows
end

function EncounterAchievements:CollectAchievementIDsForCategory(categoryID)
    local achievementIDs = {}
    local seenAchievementIDs = {}

    local categoryIDs = self:GetDescendantCategoryIDs(categoryID, true)
    for _, currentCategoryID in ipairs(categoryIDs) do
        local numAchievements = 0
        if type(GetCategoryNumAchievements) == "function" then
            local total = GetCategoryNumAchievements(currentCategoryID, true)
            if type(total) == "number" and total > 0 then
                numAchievements = total
            end
        end

        for index = 1, numAchievements do
            local achievementID, _, _, _, _, _, _, _, _, _, _, _, _, _, isStatistic = GetAchievementInfo(currentCategoryID, index)
            if type(achievementID) == "number"
                and achievementID > 0
                and not seenAchievementIDs[achievementID]
                and isStatistic ~= true then
                seenAchievementIDs[achievementID] = true
                achievementIDs[#achievementIDs + 1] = achievementID
            end
        end
    end

    return achievementIDs
end

function EncounterAchievements:CollectAchievementIDsByInstanceText(instanceID)
    local instanceName = EJ_GetInstanceInfo(instanceID)
    local instanceToken = NormalizeToken(instanceName)
    if instanceToken == "" then
        return {}
    end

    local seenAchievementIDs = {}
    local achievementIDs = {}

    local scopedCategoryIDs
    local rootCategoryID = self:GetPreferredRootCategoryID()
    if rootCategoryID then
        scopedCategoryIDs = self:GetDescendantCategoryIDs(rootCategoryID, true)
    else
        scopedCategoryIDs = self:GetAllCategoryIDs()
    end

    for _, currentCategoryID in ipairs(scopedCategoryIDs) do
        local total = type(GetCategoryNumAchievements) == "function" and GetCategoryNumAchievements(currentCategoryID, true) or 0
        local numAchievements = (type(total) == "number" and total > 0) and total or 0

        for index = 1, numAchievements do
            local achievementID, name, _, _, _, _, _, description, _, _, _, _, _, _, isStatistic = GetAchievementInfo(currentCategoryID, index)
            if type(achievementID) == "number" and achievementID > 0 and not seenAchievementIDs[achievementID] then
                local nameToken = NormalizeToken(name)
                local descriptionToken = NormalizeToken(description)

                if isStatistic ~= true
                    and ((nameToken ~= "" and string.find(nameToken, instanceToken, 1, true))
                        or (descriptionToken ~= "" and string.find(descriptionToken, instanceToken, 1, true))) then
                    seenAchievementIDs[achievementID] = true
                    achievementIDs[#achievementIDs + 1] = achievementID
                end
            end
        end
    end

    return achievementIDs
end

function EncounterAchievements:BuildInstanceAchievementRows(instanceID, categoryID)
    local cachedEntry = self._instanceAchievementCache[instanceID]
    local achievementIDs = cachedEntry and cachedEntry.achievementIDs or nil
    if type(achievementIDs) ~= "table" or cachedEntry.categoryID ~= categoryID then
        achievementIDs = self:CollectAchievementIDsForCategory(categoryID)
        self._instanceAchievementCache[instanceID] = {
            categoryID = categoryID,
            achievementIDs = achievementIDs,
        }
    end

    return self:BuildRowsFromAchievementIDs(achievementIDs)
end

----------------------------------------------------------------------------------------
-- Async Instance Row Build
----------------------------------------------------------------------------------------
function EncounterAchievements:BuildScopedFallbackCategoryIDs()
    local rootCategoryID = self:GetPreferredRootCategoryID()
    if rootCategoryID then
        return self:GetDescendantCategoryIDs(rootCategoryID, true)
    end
    return self:GetAllCategoryIDs()
end

function EncounterAchievements:BuildAchievementRowData(achievementID, name, description, icon, rewardText, categoryID)
    return {
        achievementID = achievementID,
        name = name or tostring(achievementID),
        description = description or "",
        icon = icon or DEFAULT_ICON_FILE_ID,
        rewardText = rewardText or "",
        categoryPath = self:GetCategoryPath(categoryID, " > "),
    }
end

function EncounterAchievements:GetCachedInstanceAchievementRows(instanceID)
    local cachedRows = self._instanceRowCache and self._instanceRowCache[instanceID]
    if type(cachedRows) == "table" then
        return cachedRows.rows or {}, cachedRows.categoryID, false
    end

    local pendingBuild = self._pendingInstanceRowBuilds and self._pendingInstanceRowBuilds[instanceID]
    return nil, nil, pendingBuild ~= nil
end

function EncounterAchievements:ProcessPendingRowBuildTask(task, budgetPerTick)
    local categoryIDs = task.categoryIDs or {}
    local maxScans = type(budgetPerTick) == "number" and budgetPerTick > 0 and budgetPerTick or ASYNC_SCAN_ACHIEVEMENTS_PER_TICK
    local scans = 0

    while scans < maxScans do
        local categoryID = categoryIDs[task.categoryIndex]
        if not categoryID then
            return true
        end

        if task.numAchievements == nil then
            local total = type(GetCategoryNumAchievements) == "function" and GetCategoryNumAchievements(categoryID, true) or 0
            task.numAchievements = (type(total) == "number" and total > 0) and total or 0
            task.achievementIndex = 1
        end

        if task.achievementIndex > task.numAchievements then
            task.categoryIndex = task.categoryIndex + 1
            task.achievementIndex = 1
            task.numAchievements = nil
        else
            local achievementID, name, _, _, _, _, _, description, _, icon, rewardText, _, _, _, isStatistic = GetAchievementInfo(categoryID, task.achievementIndex)
            task.achievementIndex = task.achievementIndex + 1
            scans = scans + 1

            if type(achievementID) == "number"
                and achievementID > 0
                and isStatistic ~= true
                and not task.seenAchievementIDs[achievementID] then
                local includeAchievement = true

                if task.mode == "fallback" then
                    local nameToken = NormalizeToken(name)
                    local descriptionToken = NormalizeToken(description)
                    includeAchievement = (nameToken ~= "" and string.find(nameToken, task.instanceToken, 1, true))
                        or (descriptionToken ~= "" and string.find(descriptionToken, task.instanceToken, 1, true))
                end

                if includeAchievement then
                    task.seenAchievementIDs[achievementID] = true
                    task.rows[#task.rows + 1] = self:BuildAchievementRowData(
                        achievementID,
                        name,
                        description,
                        icon,
                        rewardText,
                        categoryID
                    )
                end
            end
        end
    end

    return false
end

function EncounterAchievements:FinishPendingRowBuildTask(task)
    local state = {
        rows = task.rows or {},
        categoryID = task.categoryID,
    }

    self._instanceRowCache[task.instanceID] = state
    self._pendingInstanceRowBuilds[task.instanceID] = nil

    for index = #self._pendingInstanceRowBuildQueue, 1, -1 do
        if self._pendingInstanceRowBuildQueue[index] == task then
            table.remove(self._pendingInstanceRowBuildQueue, index)
            break
        end
    end

    local callbacks = task.callbacks or {}
    for _, callback in ipairs(callbacks) do
        if type(callback) == "function" then
            pcall(callback, task.instanceID, state.rows, state.categoryID)
        end
    end
end

function EncounterAchievements:ProcessPendingRowBuildTick()
    local queue = self._pendingInstanceRowBuildQueue
    if type(queue) ~= "table" or #queue == 0 then
        self:CancelPendingInstanceRowBuilds()
        return
    end

    local task = queue[1]
    if type(task) ~= "table" then
        table.remove(queue, 1)
        return
    end

    local isDone = self:ProcessPendingRowBuildTask(task, ASYNC_SCAN_ACHIEVEMENTS_PER_TICK)
    if isDone then
        self:FinishPendingRowBuildTask(task)
    end

    if #queue == 0 then
        self:CancelPendingInstanceRowBuilds()
    end
end

function EncounterAchievements:StartPendingRowBuildWorker()
    if self._instanceRowBuildTicker then
        return
    end

    if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.NewTicker) ~= "function" then
        return
    end

    self._instanceRowBuildTicker = _G.C_Timer.NewTicker(ASYNC_SCAN_TICK_INTERVAL_SECONDS, function()
        self:ProcessPendingRowBuildTick()
    end)
end

function EncounterAchievements:CancelPendingInstanceRowBuilds()
    if self._instanceRowBuildTicker and self._instanceRowBuildTicker.Cancel then
        self._instanceRowBuildTicker:Cancel()
    end

    self._instanceRowBuildTicker = nil
    self._pendingInstanceRowBuilds = {}
    self._pendingInstanceRowBuildQueue = {}
end

function EncounterAchievements:RequestInstanceAchievementRows(instanceID, isRaid, onComplete)
    if type(instanceID) ~= "number" or instanceID <= 0 then
        if type(onComplete) == "function" then
            pcall(onComplete, instanceID, {}, nil)
        end
        return false
    end

    local cachedRows = self._instanceRowCache and self._instanceRowCache[instanceID]
    if type(cachedRows) == "table" then
        if type(onComplete) == "function" then
            pcall(onComplete, instanceID, cachedRows.rows or {}, cachedRows.categoryID)
        end
        return true
    end

    local hasForeignPendingTask = false
    for pendingInstanceID in pairs(self._pendingInstanceRowBuilds) do
        if pendingInstanceID ~= instanceID then
            hasForeignPendingTask = true
            break
        end
    end

    if hasForeignPendingTask then
        self:CancelPendingInstanceRowBuilds()
    end

    local pendingBuild = self._pendingInstanceRowBuilds[instanceID]
    if type(pendingBuild) == "table" then
        if type(onComplete) == "function" then
            pendingBuild.callbacks[#pendingBuild.callbacks + 1] = onComplete
        end
        return false
    end

    if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.NewTicker) ~= "function" then
        local rows, categoryID = self:GetInstanceAchievementRows(instanceID, isRaid)
        if type(onComplete) == "function" then
            pcall(onComplete, instanceID, rows, categoryID)
        end
        return true
    end

    local categoryID = self:GetResolvedCategoryForInstance(instanceID, isRaid)
    local mode
    local categoryIDs
    local instanceToken = ""

    if categoryID then
        mode = "category"
        categoryIDs = self:GetDescendantCategoryIDs(categoryID, true)
    else
        mode = "fallback"
        categoryIDs = self:BuildScopedFallbackCategoryIDs()
        instanceToken = NormalizeToken(EJ_GetInstanceInfo(instanceID))
    end

    if type(categoryIDs) ~= "table" then
        categoryIDs = {}
    end

    if mode == "fallback" and instanceToken == "" then
        self._instanceRowCache[instanceID] = { rows = {}, categoryID = nil }
        if type(onComplete) == "function" then
            pcall(onComplete, instanceID, {}, nil)
        end
        return true
    end

    local task = {
        instanceID = instanceID,
        categoryID = categoryID,
        mode = mode,
        categoryIDs = categoryIDs,
        categoryIndex = 1,
        achievementIndex = 1,
        numAchievements = nil,
        instanceToken = instanceToken,
        seenAchievementIDs = {},
        rows = {},
        callbacks = {},
    }

    if type(onComplete) == "function" then
        task.callbacks[#task.callbacks + 1] = onComplete
    end

    self._pendingInstanceRowBuilds[instanceID] = task
    self._pendingInstanceRowBuildQueue[#self._pendingInstanceRowBuildQueue + 1] = task
    self:StartPendingRowBuildWorker()

    return false
end

function EncounterAchievements:GetInstanceAchievementRows(instanceID, isRaid)
    if type(instanceID) ~= "number" or instanceID <= 0 then
        return {}, nil
    end

    local cachedRows = self._instanceRowCache[instanceID]
    if type(cachedRows) == "table" then
        return cachedRows.rows, cachedRows.categoryID
    end

    local categoryID = self:GetResolvedCategoryForInstance(instanceID, isRaid)
    if not categoryID then
        local fallbackAchievementIDs = self:CollectAchievementIDsByInstanceText(instanceID)
        if #fallbackAchievementIDs > 0 then
            local fallbackRows = self:BuildRowsFromAchievementIDs(fallbackAchievementIDs)
            local fallbackState = { rows = fallbackRows, categoryID = nil }
            self._instanceRowCache[instanceID] = fallbackState
            return fallbackState.rows, fallbackState.categoryID
        end

        if self:HasCategoryData() then
            local emptyState = { rows = {}, categoryID = nil }
            self._instanceRowCache[instanceID] = emptyState
            return emptyState.rows, emptyState.categoryID
        end

        return {}, nil
    end

    local rows = self:BuildInstanceAchievementRows(instanceID, categoryID)
    if #rows == 0 then
        local fallbackAchievementIDs = self:CollectAchievementIDsByInstanceText(instanceID)
        if #fallbackAchievementIDs > 0 then
            rows = self:BuildRowsFromAchievementIDs(fallbackAchievementIDs)
            categoryID = nil
        end
    end

    self._instanceRowCache[instanceID] = {
        rows = rows,
        categoryID = categoryID,
    }

    return rows, categoryID
end
