-- Acquisition evaluation only. No frames, global APIs, or SavedVariables.
local _, RefineUI = ...
local Engine = {}
Engine.__index = Engine
RefineUI.OpportunityEngine = Engine

function Engine.New(data, adapter)
    return setmetatable({ data = data, adapter = adapter, results = {}, dependencies = {}, ownership = {},
        pending = {}, queued = {}, head = 1, revisions = {}, achievements = {}, evaluation = {}, revision = 0 }, Engine)
end

function Engine:Queue(id)
    if not self.data.offers[id] then return end
    self.results[id] = nil
    self.evaluation[id] = nil
    self.revisions[id] = (self.revisions[id] or 0) + 1
    if not self.queued[id] then self.queued[id] = true; self.pending[#self.pending + 1] = id end
end

function Engine:Invalidate(kind, id)
    self.cacheRevision = (self.cacheRevision or 0) + 1
    local index = self.data.index[kind]
    if kind == "item" then
        for _, offerID in ipairs(index and index[id] or {}) do
            self.ownership[self.data.offers[offerID][1]] = nil
        end
    elseif kind == "reward" then
        if id then self.ownership[id] = nil else self.ownership = {} end
    else
        local prefix = kind .. ":"
        for key in pairs(self.dependencies) do
            if key:sub(1, #prefix) == prefix and (id == nil or key:match("^[^:]+:([^:]+):") == tostring(id)) then
                self.dependencies[key] = nil
            end
        end
    end
    if index then
        if id ~= nil then for _, offer in ipairs(index[id] or {}) do self:Queue(offer) end
        else for _, offers in pairs(index) do for _, offer in ipairs(offers) do self:Queue(offer) end end end
    end
    self.revision = self.revision + 1
end

function Engine:Reset()
    self.cacheRevision = (self.cacheRevision or 0) + 1
    self.dependencies, self.ownership, self.results = {}, {}, {}
    for id in ipairs(self.data.offers) do self:Queue(id) end
    self.revision = self.revision + 1
end

function Engine:Dependency(req)
    local key = req[1] .. ":" .. req[2] .. ":" .. req[4]
    local cached = self.dependencies[key]
    if not cached then
        local revision = self.cacheRevision
        self.adapter.readFailure = nil
        local value, reason, unit = self.adapter:Dependency(req)
        if revision ~= self.cacheRevision then return nil end
        cached = { value = value, reason = reason or (value == nil and self.adapter.readFailure), unit = unit }; self.dependencies[key] = cached
    end
    return cached.value
end

local function Contains(values, value)
    for _, candidate in ipairs(values) do if candidate == value then return true end end
    return false
end

function Engine.Check(req, value)
    if value == nil then return nil end
    local kind, target = req[1], req[3]
    if kind == "class" or kind == "race" then return Contains(target, value) end
    if kind == "faction" then return target == value end
    if kind == "quest" or kind == "achievement" then return value == true end
    if type(value) ~= "number" then return nil end
    return value >= target, math.max(0, target - value)
end

function Engine:IsNear(req, remaining)
    if not remaining or remaining <= 0 then return false end
    local cached=self.dependencies[req[1]..":"..req[2]..":"..req[4]]
    if req[1]=="reputation" and cached and cached.unit=="rank" then return remaining<=1 end
    return req[1] == "reputation" and remaining <= 1000
        or req[1] == "renown" and remaining <= 1
        or req[1] == "currency" and remaining <= req[3] * 0.1
end

function Engine:Evaluate(id)
    local row = self.data.offers[id]
    local source = self.data.sources[row[2]]
    if source[1] == "questReward" or source[1] == "capture" then
        local eligible = self:Dependency({source[1],source[2],1,"character"})
        if eligible == nil then return nil, "unknown" end
        if eligible == 0 then return nil, "blocked" end
    end
    local reward = self.ownership[row[1]]
    if not reward then
        local revision = self.cacheRevision
        self.adapter.readFailure = nil
        reward = self.adapter:Ownership(self.data.rewards[row[1]]) or {}
        if reward.owned == nil then reward.reason = reward.reason or self.adapter.readFailure or "Ownership unavailable" end
        if revision ~= self.cacheRevision then return nil end
        self.ownership[row[1]] = reward
    end
    if reward.owned == true then return nil, "owned" end
    if source[1] == "achievementReward" then
        local eligible=self:Dependency({"achievementReward",source[2],1,"character"})
        if eligible == nil then return nil,"unknown" elseif eligible == 0 then return nil,"blocked" end
    end
    if reward.eligible == false then return nil, "blocked" end
    local unknown, missing, blocker, deficit = reward.owned == nil, 0
    local actionable, gaps = true, {}
    if reward.eligibilityRequired and reward.eligible == nil then unknown = true end
    for _, req in ipairs(self.data.requirements[row[3]]) do
        local passed, remaining = Engine.Check(req, self:Dependency(req))
        if passed == nil then unknown = true
        elseif not passed then
            missing = missing + 1; blocker, deficit = req, remaining
            gaps[#gaps+1]={requirement=req,current=self:Dependency(req),remaining=remaining}
            if req[1] ~= "currency" and req[1] ~= "gold" and req[1] ~= "reputation" and req[1] ~= "renown" and req[1] ~= "quest" then actionable=false end
        end
    end
    if not actionable then return nil,"blocked" end
    if unknown then return nil, "unknown" end
    local tier = missing == 0 and 2 or missing == 1 and self:IsNear(blocker, deficit) and 3 or nil
    if missing > 0 and not tier then tier=6 end
    local definition = self.data.rewards[row[1]]
    local live = source[1] == "vendor" and missing == 0 and self.adapter:MerchantReady(definition[3], source[2])
    local label, detail, achievementID, actionPriority
    if source[1] ~= "vendor" then
        tier = 5
        if source[1] == "questReward" then
            local state = self:Dependency({"questReward",source[2],1,"character"})
            label = state == 2 and "Quest ready for turn-in" or state == 1 and "Quest in progress" or "Quest to pursue"
            actionPriority = state == 2 and 1 or state == 1 and 2 or 3
            detail = state == 3 and "Known prerequisites met • Confirm quest availability and reward choice at the quest giver"
                or "Quest reward • Reward choice and remaining objectives must be checked"
        elseif source[1] == "achievementReward" then
            label, achievementID = "Achievement to pursue", source[2]
            local progress=self.adapter.rewardProgress and self.adapter.rewardProgress[source[2]]
            detail = progress and string.format("%d/%d criteria complete • %d remaining",progress.completed,progress.total,progress.missing)
                or "Open the achievement to inspect its requirements"
            actionPriority=progress and (4 + progress.missing / progress.total) or 5
        elseif source[1] == "capture" then
            label = "Wild pet capture"
            detail = "Known habitat • Spawn, weather and battle availability unverified"
        else
            label = "NPC loot source"
            detail = "Drop attempt • Spawn, access and loot eligibility unverified; reward is not guaranteed"
        end
    end
    local nextQuestID
    if missing > 0 then
        tier= tier==3 and 3 or 6;label="Next steps"
        detail=tostring(missing).." known requirement(s) remaining • Not ready yet"
        for _,gap in ipairs(gaps) do if gap.requirement[1]=="quest" then nextQuestID=gap.requirement[2];break end end
        if missing==1 and deficit and type(blocker[3])=="number" and blocker[3]>0 then actionPriority=deficit/blocker[3] end
    end
    return { id = definition[1] .. ":" .. (reward.appearanceID or definition[2]), offerID = id, rewardIndex = row[1],
        category = (definition[1] == "mountSpell" or definition[1] == "mount") and "mount" or definition[1],
        sourceIndex = row[2], title = reward.name or ("Item " .. definition[3]), icon = reward.icon,
        tier = live and 1 or tier, label = label or (live and "Ready to buy" or tier == 2 and "Requirements met" or "Near unlock"),
        detail = detail, rewardAchievementID = achievementID, acquisition = source[1],
        actionPriority = actionPriority,
        gaps = gaps, nextQuestID = nextQuestID,
        blocker = blocker, deficit = deficit, mapID = source[3], itemID = definition[3] }, "match"
end

function Engine:WorkOne()
    local id = self.pending[self.head]
    if not id then self.pending, self.head = {}, 1; return false end
    self.head = self.head + 1; self.queued[id] = nil
    local revision = self.revisions[id]
    local cacheRevision = self.cacheRevision
    local result, state = self:Evaluate(id)
    if revision == self.revisions[id] and cacheRevision == self.cacheRevision then self.results[id] = result; self.evaluation[id] = state
    elseif not self.queued[id] then self:Queue(id) end
    self.revision = self.revision + 1
    return true
end

local function Better(a, b, preferences, mapID)
    local af, bf = preferences.focus[a.id] == true, preferences.focus[b.id] == true
    if af ~= bf then return af end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if (a.actionPriority or 4) ~= (b.actionPriority or 4) then return (a.actionPriority or 4) < (b.actionPriority or 4) end
    local an, bn = mapID ~= nil and a.mapID == mapID, mapID ~= nil and b.mapID == mapID
    if an ~= bn then return an end
    if a.tier == 4 and b.tier == 4 then
        local ap = (a.criteriaCompleted or 0) / math.max(1, a.criteriaTotal or 1)
        local bp = (b.criteriaCompleted or 0) / math.max(1, b.criteriaTotal or 1)
        if ap ~= bp then return ap > bp end
    end
    if a.id ~= b.id then return a.id < b.id end
    return (a.offerID or 0) < (b.offerID or 0)
end

-- A canonical-key index joins collection entries to their best evaluated route.
-- It is rebuilt once per published engine revision, never once per collection row.
function Engine:GetRecommendationIndex(preferences, mapID)
    if self.recommendationIndexRevision == self.revision and self.recommendationIndexMapID == mapID then
        return self.recommendationIndex
    end
    local index = {}
    preferences = preferences or {}; preferences.focus = preferences.focus or {}
    for _, row in pairs(self.results) do
        local definition = row.rewardIndex and self.data.rewards[row.rewardIndex]
        if definition then
            -- Evaluated appearance rows are normalized to a visual ID in row.id;
            -- other collectible IDs already use the same canonical key.
            local key = row.id
            if not index[key] or Better(row, index[key], preferences, mapID) then index[key] = row end
        end
    end
    self.recommendationIndex, self.recommendationIndexRevision, self.recommendationIndexMapID = index, self.revision, mapID
    return index
end

-- Only numeric/cached comparisons here. Filters are applied before limiting results.
function Engine:GetPage(preferences, mapID, offset, limit, category)
    preferences = preferences or {}; preferences.focus = preferences.focus or {}; preferences.hidden = preferences.hidden or {}
    local best, list, counts = {}, {}, { ready = 0, met = 0, near = 0, achievements = 0, collectibles = 0, mount = 0, pet = 0, toy = 0, appearance = 0, decor = 0 }
    for _, row in pairs(self.results) do
        if not best[row.id] or Better(row, best[row.id], preferences, mapID) then best[row.id] = row end
    end
    for id, row in pairs(self.achievements) do best["achievement:" .. id] = row end
    for id, row in pairs(best) do
        local search = preferences.search
        if not preferences.hidden[id] and (not search or search == "" or (row.title or ""):lower():find(search:lower(), 1, true)) then
            if not category or category == "collectibles" and row.tier ~= 4
                or category == "achievements" and row.tier == 4 or category == row.category then
                list[#list + 1] = row
            end
            local key = ({ "ready", "met", "near", "achievements", "attempts", "nextSteps" })[row.tier]
            counts[key] = counts[key] or 0
            counts[key] = counts[key] + 1
            if row.tier ~= 4 then
                counts.collectibles = counts.collectibles + 1
                if row.category then counts[row.category] = (counts[row.category] or 0) + 1 end
            end
        end
    end
    if (offset or 0) == 0 and (limit or 3) == 3 then
        -- Keep the dashboard bounded; the expanded view alone needs a full sort.
        local top = {}
        for _, row in ipairs(list) do
            local position = #top + 1
            for i, previous in ipairs(top) do if Better(row, previous, preferences, mapID) then position = i; break end end
            if position <= 3 then table.insert(top, position, row); top[4] = nil end
        end
        return top, #list, counts
    end
    table.sort(list, function(a,b) return Better(a,b,preferences,mapID) end)
    local rows = {}
    for i = (offset or 0) + 1, math.min(#list, (offset or 0) + (limit or 3)) do rows[#rows + 1] = list[i] end
    return rows, #list, counts
end

function Engine:GetDetails(row)
    if not row.offerID then return {} end
    local offer = self.data.offers[row.offerID]
    local details = {}
    for _, req in ipairs(self.data.requirements[offer[3]]) do
        local key = req[1] .. ":" .. req[2] .. ":" .. req[4]
        local cached = self.dependencies[key]
        local passed, remaining = Engine.Check(req, cached and cached.value)
        details[#details + 1] = { requirement = req, passed = passed, remaining = remaining,
            current = cached and cached.value }
    end
    return details
end

-- Coverage describes only imported rewards, independent of search/hide filters.
function Engine:GetCoverage(category)
    local summary = { supported = 0, unknown = 0, pending = 0, owned = 0, blocked = 0, match = 0 }
    local states, priority = {}, { owned = 1, blocked = 2, pending = 3, unknown = 4, match = 5 }
    for id, offer in ipairs(self.data.offers) do
        local state = self.evaluation[id] or "pending"
        local previous = states[offer[1]]
        if not previous or priority[state] > priority[previous] then states[offer[1]] = state end
    end
    for id, reward in ipairs(self.data.rewards) do
        local kind = reward[1] == "mountSpell" and "mount" or reward[1]
        if category == "collectibles" or category == kind then
            summary.supported = summary.supported + 1
            local state = states[id] or "pending"
            summary[state] = summary[state] + 1
        end
    end
    summary.catalog = 0
    for kind, count in pairs(self.data.catalogCounts or {}) do
        local mapped = kind == "mountSpell" and "mount" or kind
        if category == "collectibles" or category == mapped then summary.catalog = summary.catalog + count end
    end
    if not self.data.catalogCounts then summary.catalog = summary.supported end
    return summary
end
