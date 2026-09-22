local _, RefineUI = ...
local P, E = RefineUI.AdventurePlanner, RefineUI.PlannerEvidence

function P:GetMapTasks(mapID)
    local cache = self.refreshTasks
    if cache and cache[mapID] then return cache[mapID] end
    local tasks = self:Call(C_TaskQuest, "GetQuestsOnMap", mapID) or {}
    if cache then cache[mapID] = tasks end
    return tasks
end

function P:QuestReady(id)
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then return self:Call(C_QuestLog, "ReadyForTurnIn", id) end
    return self:Call(C_QuestLog, "IsComplete", id)
end

local function Record(self, id, provider, title, category)
    return { id = id, provider = provider, title = title, category = category, kind = "Context",
        bucket = "weekly", cadence = "none", source = provider, verification = "live", state = "available",
        ownerKey = self.owner, scope = "character", observedAt = self:Now() }
end

-- Capture raw presentation values, not an inferred weekly completion counter.
-- Its identity/direction/reset contract remains an in-game release gate.
function P:CapturePrey()
    self:Database()
    self.preyWidgetIDs = self.preyWidgetIDs or {}
    local observations = {}
    for _, widget in ipairs(self:Call(C_UIWidgetManager, "GetAllWidgetsBySetID", 1843) or {}) do
        if E.Number(widget.widgetID) then
            self.preyWidgetIDs[widget.widgetID] = true
            local info = self:Call(C_UIWidgetManager, "GetStatusBarWidgetVisualizationInfo", widget.widgetID)
            if info and info.shownState == 1 and info.text and E.Number(info.barValue) and E.Number(info.barMax) then
                observations[#observations + 1] = { widgetID = widget.widgetID, text = info.text,
                    value = info.barValue, maximum = info.barMax }
            end
        end
    end
    if #observations > 0 then
        self.preyObservation = { observedAt = self:Now(), values = observations }
    end
end

P.providers.prey = function(self)
    local records = {}
    local id = self:Call(C_QuestLog, "GetActivePreyQuest")
    if E.Number(id) and id > 0 and self:Call(C_QuestLog, "IsOnQuest", id) == true then
        local r = Record(self, "quest:" .. id, "prey", self:Call(C_QuestLog, "GetTitleForQuestID", id) or "Active Prey hunt", "Prey")
        r.kind, r.questID, r.contentType, r.goalType = "Activity", id, "prey", "quest"
        r.source, r.destination = "C_QuestLog.GetActivePreyQuest", { type = "quest", id = id, label = "Track quest" }
        local ready = self:QuestReady(id)
        r.state = ready == true and "ready" or ready == false and "inProgress" or "unknown"
        r.detail = ready == true and "Ready to turn in" or "Active hunt"
        r.rewardReason = "Finish your active hunt"
        r.recommendable, r.recommendationWeight = r.state ~= "unknown", 64
        r.objectives = {}
        for _, objective in ipairs(self:Call(C_QuestLog, "GetQuestObjectives", id) or {}) do
            if objective.text then r.objectives[#r.objectives + 1] = objective.text end
        end
        records[#records + 1] = r
    end
    if self.preyObservation then
        local r = Record(self, "prey:allowance", "prey", "Hunt table observation", "Prey")
        r.kind = "Snapshot"
        r.verification, r.observedAt = "snapshot", self.preyObservation.observedAt
        r.detail = "Prey table"
        r.objectives = {}
        for _, value in ipairs(self.preyObservation.values) do
            r.objectives[#r.objectives + 1] = value.text .. " • " .. value.value .. " / " .. value.maximum
        end
        r.rewardReason = "Presentation only; does not establish completed hunts or limited rewards."
        records[#records + 1] = r
    end
    return records
end

-- Discover the current map and its ancestors without asserting global coverage.
function P:ContextMaps()
    local maps, seen = {}, {}
    local id = self:Call(C_Map, "GetBestMapForUnit", "player")
    for _ = 1, 12 do
        if not E.Number(id) or id <= 0 or seen[id] then break end
        seen[id], maps[#maps + 1] = true, id
        local info = self:Call(C_Map, "GetMapInfo", id)
        id = info and info.parentMapID
    end
    return maps
end

local function POIs(self, provider, method)
    local records, seen = {}, {}
    for _, mapID in ipairs(self:ContextMaps()) do
        for _, id in ipairs(self:Call(C_AreaPoiInfo, method, mapID) or {}) do
            local info = self:Call(C_AreaPoiInfo, "GetAreaPOIInfo", mapID, id)
            if info and info.name and not seen[id] then
                seen[id] = true
                local r = Record(self, provider .. ":" .. id, provider, info.name, provider == "delves" and "Delves" or "World events")
                r.poiID, r.mapID, r.position = id, mapID, info.position
                r.destination = { type = "map", id = mapID, position = info.position,
                    label = info.position and "Track location" or "Map" }
                r.state = info.isLocked == true and "locked" or "available"
                r.actionable = false
                local unlocked
                if info.isLocked ~= nil then unlocked = not info.isLocked end
                r.facts = { markerVisible = E.Fact(r, "markerVisible", true, "C_AreaPoiInfo.GetAreaPOIInfo"),
                    unlocked = E.Fact(r, "unlocked", unlocked, "C_AreaPoiInfo.GetAreaPOIInfo"),
                    active = E.Fact(r, "active", info.isCurrentEvent, "C_AreaPoiInfo.GetAreaPOIInfo") }
                r.bountiful, r.isCurrentEvent, r.isLocked = info.atlasName == "delves-bountiful", info.isCurrentEvent, info.isLocked
                r.detail = info.isLocked == true and "Locked location" or provider == "delves" and (r.bountiful and "Bountiful Delve" or "Delve entrance")
                    or info.isCurrentEvent == true and "Current event" or "Map event"
                r.source = "C_AreaPoiInfo." .. method
                r.rewardReason = "Visible on a contextual map; discovery is not exhaustive and does not establish reward eligibility."
                local timed, hidden = self:Call(C_AreaPoiInfo, "IsAreaPOITimed", id)
                local seconds = timed == true and hidden == false and self:Call(C_AreaPoiInfo, "GetAreaPOISecondsLeft", id)
                if E.Number(seconds) and seconds > 0 then r.expiresAt = self:Now() + seconds; r.expirationMeaning = "Map marker expires" end
                records[#records + 1] = r
            end
        end
    end
    return records
end

P.providers.events = function(self) return POIs(self, "events", "GetEventsForMap") end

function P:CaptureDelveEntrance()
    local frame = DelvesDifficultyPickerFrame
    local previous = self.delveEntrance
    self.delveEntrance = nil
    if not frame or not frame:IsShown() or not Enum.TieredEntranceType
        or self:Call(C_DelvesUI, "GetTieredEntranceType") ~= Enum.TieredEntranceType.Delve then
        if previous then self:Invalidate("delves") end
        return
    end
    local read = self:Read(C_DelvesUI, "GetDelveEntranceTiers")
    local tiers = read.values and read.values[1]
    if read.status == "restricted" or read.status == "unavailable" then self.retryProviders.delves = true end
    if not tiers then if previous then self:Invalidate("delves") end; return end
    for _, tier in ipairs(tiers) do
        if E.Number(tier.tier) then
            tier.enabled, tier.failureReason = self:Call(C_DelvesUI, "IsDelveEntranceTierEnabled", tier.tier)
        end
    end
    self.delveEntrance = { tiers = tiers, observedAt = self:Now(),
        mapID = self:Call(C_DelvesUI, "GetDelveEntranceMapID"),
        title = self:Call(C_DelvesUI, "GetDelveEntranceTitleString") }
    self:Invalidate("delves")
end

function P:InstallDelveHooks()
    local frame = DelvesDifficultyPickerFrame
    if not frame or self.delveHookFrame == frame or not hooksecurefunc or type(frame.TryShow) ~= "function" then return end
    self.delveHookFrame = frame
    hooksecurefunc(frame, "TryShow", function()
        if not pcall(self.CaptureDelveEntrance, self) then self.retryProviders.delves = true end
    end)
    frame:HookScript("OnHide", function() self.delveEntrance = nil; self:Invalidate("delves") end)
end

P.providers.delves = function(self)
    local records = POIs(self, "delves", "GetDelvesForMap")
    if self.delveEntrance then
        local entrance = self.delveEntrance
        local r = Record(self, "delves:entrance", "delves", entrance.title or "Delve entrance tiers", "Delves")
        r.context, r.observedAt, r.verification = "open-delve-entrance", entrance.observedAt, "observed"
        r.source, r.tiers, r.mapID = "C_DelvesUI.GetDelveEntranceTiers", entrance.tiers, entrance.mapID
        r.detail = "Entrance tiers"
        r.objectives = {}
        for _, tier in ipairs(entrance.tiers) do
            if tier.tier then
                r.objectives[#r.objectives + 1] = "Tier " .. tier.tier .. " • " ..
                    (tier.enabled == true and "Available" or tier.failureReason or tier.lockedReason or
                        (tier.enabled == false and "Unavailable" or "Not shown"))
            end
        end
        records[#records + 1] = r
    end
    if self:Call(C_DelvesUI, "HasActiveDelve") == true then
        local tier = self:Call(C_DelvesUI, "GetActiveDelveTier")
        local eligible = self:Call(C_DelvesUI, "IsEligibleForActiveDelveRewards", "player")
        local r = Record(self, "delves:active", "delves", "Active Delve", "Delves")
        r.context = "active-delve"
        r.detail = "Active Delve rewards: " .. (eligible == true and "Available" or eligible == false and "Unavailable" or "Not shown")
        r.facts = { rewardEligibility = E.Fact(r, "rewardEligibility", eligible, "C_DelvesUI.IsEligibleForActiveDelveRewards") }
        r.tier = tier
        r.rewardReason = "Applies only to the active Delve; does not prove global coffer availability."
        records[#records + 1] = r
    end
    return records
end

P.providers.journeys = function(self)
    local records = {}
    local delveFaction = self:Call(C_DelvesUI, "GetDelvesFactionForSeason")
    local season = self:Call(C_DelvesUI, "GetCurrentDelvesSeasonNumber")
    for _, id in ipairs(self:Call(C_MajorFactions, "GetMajorFactionIDs", LE_EXPANSION_LEVEL_CURRENT) or {}) do
        if self:Call(C_MajorFactions, "IsMajorFactionHiddenFromExpansionPage", id) == false
            and self:Call(C_MajorFactions, "ShouldDisplayMajorFactionAsJourney", id) == true then
            local info = self:Call(C_MajorFactions, "GetMajorFactionData", id)
            if info and info.name then
                local r = Record(self, "journey:" .. id, "journeys", info.name, "Journeys")
                r.kind = "Progress"
                r.goalType, r.factionID, r.importance = "journey", id, "optional"
                r.contentType = id == delveFaction and "delves" or "journey"
                r.season = id == delveFaction and season or nil
                r.source = "C_MajorFactions.GetMajorFactionData"
                r.current, r.target = info.renownReputationEarned, info.renownLevelThreshold
                r.weeklyCapped = self:Call(C_MajorFactions, "IsWeeklyRenownCapped", id)
                local maximum = self:Call(C_MajorFactions, "HasMaximumRenown", id)
                r.state = info.isUnlocked == false and "locked" or info.isUnlocked ~= true and "unknown"
                    or maximum == true and "complete" or maximum == false and "inProgress" or "unknown"
                r.detail = "Renown " .. (info.renownLevel or "?") .. (r.weeklyCapped == true and " • Weekly capped" or "")
                r.destination = { type = "journeys", label = "Journeys" }
                r.rewardReason = "Track progress; an uncapped flag does not quantify remaining weekly progress."
                records[#records + 1] = r
            end
        end
    end
    return records
end

function P:ObserveOrders(page, result, orderType, buckets, more, offset)
    if not E.Number(result) or result ~= Enum.CraftingOrderResult.Ok or not E.Number(orderType)
        or orderType ~= Enum.CraftingOrderType.Npc or not E.Accessible(buckets) or buckets ~= false then return end
    if not E.Table(page.professionInfo) or not E.Number(page.professionInfo.professionID)
        or not E.Accessible(page.orderType) or page.orderType ~= orderType then return end
    local request = page.lastRequest
    if not E.Table(request) or not E.Number(request.profession) or not E.Number(page.professionInfo.profession)
        or request.profession ~= page.professionInfo.profession then return end
    local profession = page.professionInfo.professionID
    local db = self:Database()
    if not db then return end
    for _, order in ipairs(self:Call(C_CraftingOrders, "GetCrafterOrders") or {}) do
        if E.Number(order.orderID) and order.orderType == orderType and E.Number(order.expirationTime) then
            local key = profession .. ":" .. order.orderID
            db.snapshots.orders[key] = { order = order, profession = profession, ownerKey = self.owner,
                observedAt = self:Now(), expiresAt = order.expirationTime, coverage = "partial",
                offset = E.Number(offset) and offset or nil }
            if E.Accessible(more) and type(more) == "boolean" then db.snapshots.orders[key].more = more end
        end
    end
    self:Invalidate("professions")
end

function P:InstallOrderHooks()
    local page = ProfessionsFrame and ProfessionsFrame.OrdersPage
    if not page or self.orderHookPage == page or not hooksecurefunc or type(page.OrderRequestCallback) ~= "function" then return end
    self.orderHookPage = page
    hooksecurefunc(page, "OrderRequestCallback", function(...)
        -- Native callback context can contain inaccessible fields; isolate capture.
        local ok = pcall(self.ObserveOrders, self, ...)
        if not ok then self.retryProviders.professions = true end
    end)
end

function P:ObserveOrderFulfilled(result, orderID)
    if not E.Number(result) or not E.Number(orderID) or result ~= Enum.CraftingOrderResult.Ok then return end
    local db = self:Database()
    for key, entry in pairs(db and db.snapshots.orders or {}) do
        if entry.order.orderID == orderID then db.snapshots.orders[key] = nil end
    end
    self:Invalidate("professions")
end

function P:InvalidateOrderReward(_, orderID)
    if not E.Number(orderID) then return end
    local db = self:Database()
    for _, entry in pairs(db and db.snapshots.orders or {}) do
        if entry.order.orderID == orderID then entry.order.npcOrderRewards = nil end
    end
    self:Invalidate("professions")
end

P.providers.professions = function(self)
    local db, records = self:Database(), {}
    for key, entry in pairs(db and db.snapshots.orders or {}) do
        if entry.expiresAt <= self:Now() then db.snapshots.orders[key] = nil
        elseif entry.ownerKey == self.owner then
            local r = Record(self, "order:" .. key, "professions", "Patron order #" .. entry.order.orderID, "Professions")
            r.kind = "Snapshot"
            r.verification, r.observedAt, r.validUntil = "snapshot", entry.observedAt, entry.expiresAt
            r.expiresAt, r.expirationMeaning = entry.expiresAt, "Last observed order expiry"
            r.order, r.professionSkillLineID, r.coverage = entry.order, entry.profession, "partial"
            r.source = "C_CraftingOrders.GetCrafterOrders / successful NPC response"
            r.detail = "Profession orders"
            r.rewardReason = "Partial search observation. isFulfillable is an order-state flag, not general craftability."
            r.objectives = {}
            for _, reward in ipairs(entry.order.npcOrderRewards or {}) do
                local name = reward.itemLink or (reward.currencyType and ("Currency #" .. reward.currencyType))
                if name then r.objectives[#r.objectives + 1] = "Observed reward: " .. (reward.count or "?") .. " × " .. name end
            end
            records[#records + 1] = r
        end
    end
    return records
end
