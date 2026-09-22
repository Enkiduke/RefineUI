local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuidePlanner")
local Planner = { providers = {}, cache = {}, dirty = {}, revisions = {}, reads = {} }
RefineUI.AdventurePlanner = Planner
local Evidence = RefineUI.PlannerEvidence
Planner.providerOrder = { "quests", "vault", "instances", "resources", "prey", "delves", "events", "journeys", "professions" }
Planner.retryProviders, Planner.pendingItems = {}, {}
local function Pack(...) return { n = select("#", ...), ... } end

function Planner:Read(namespace, method, ...)
    local fn = namespace and namespace[method]
    if type(fn) ~= "function" then
        if self.readingProvider then self.retryProviders[self.readingProvider] = true end
        return { status = "unavailable" }
    end
    local args = { ... }
    for index = 1, select("#", ...) do
        if not Evidence.Accessible(args[index]) then return { status = "restricted" } end
    end
    local values = Pack(pcall(fn, ...))
    if not values[1] then
        if self.readingProvider then self.retryProviders[self.readingProvider] = true end
        return { status = "unavailable" }
    end
    local result = { status = "known", values = {}, count = values.n - 1 }
    for index = 2, values.n do
        local value = values[index]
        local state = "known"
        if not Evidence.Accessible(value) then value, state = nil, "restricted"
        elseif type(value) == "table" then
            local schema = Evidence.Schemas[method]
            if schema then
                local ok, clean, status = pcall(Evidence.Normalize, value, schema)
                value, state = ok and clean or nil, ok and status or "restricted"
            else value, state = nil, "unavailable" end
        elseif type(value) == "number" and not Evidence.Number(value) then value, state = nil, "unavailable"
        end
        result.values[index - 1] = value
        if state ~= "known" then
            result.status = state
            if self.readingProvider then self.retryProviders[self.readingProvider] = true end
        end
    end
    if result.status == "known" and result.values[1] == nil then result.status = "unknown" end
    return result
end

function Planner:Call(namespace, method, ...)
    local result = self:Read(namespace, method, ...)
    return unpack(result.values or {}, 1, result.count or 0)
end

function Planner:Now() return GetServerTime() end
function Planner:ResetTime(cadence)
    local seconds = self:Call(C_DateAndTime, cadence == "daily" and "GetSecondsUntilDailyReset" or "GetSecondsUntilWeeklyReset")
    if type(seconds) == "number" and seconds > 0 then return self:Now() + seconds end
end

function Planner:Database()
    local guid = UnitGUID("player")
    if not guid or not RefineDB then return end
    RefineDB.AdventurePlanner = RefineDB.AdventurePlanner or { version = 1, characters = {} }
    local root = RefineDB.AdventurePlanner
    root.characters = root.characters or {}
    root.account = root.account or { periods = {} }
    root.account.periods = root.account.periods or {}
    local db = root.characters[guid]
    if not db then
        db = { preferences = { pins = {}, hidden = {}, categories = {} }, periods = {} }
        root.characters[guid] = db
        local old = RefineDB.WeeklyHub and RefineDB.WeeklyHub[guid]
        if old and old.reset and old.reset > self:Now() then
            db.periods.weekly = { reset = old.reset, quests = {} }
            for id, quest in pairs(old.quests or {}) do
                db.periods.weekly.quests[id] = { title = quest.title, completed = quest.completed,
                    scope = "character", observedAt = self:Now(), migrated = true }
            end
        end
    end
    db.preferences = db.preferences or {}
    for _, key in ipairs({ "pins", "hidden", "categories", "focus" }) do db.preferences[key] = db.preferences[key] or {} end
    db.periods = db.periods or {}
    db.snapshots = db.snapshots or { orders = {} }
    db.snapshots.orders = db.snapshots.orders or {}
    if (db.version or 1) < 2 then
        -- Old widget values claimed weekly completion without a validated contract.
        for cadence, period in pairs(db.periods) do
            period.preyHunts = nil
            for id, entry in pairs(period.quests or {}) do
                if entry.scope == "account" and period.reset and period.reset > self:Now() then
                    local shared = root.account.periods[cadence]
                    if not shared or shared.reset <= self:Now() then
                        shared = { reset = period.reset, quests = {} }; root.account.periods[cadence] = shared
                    end
                    local previous = shared.quests[id]
                    if not previous or (entry.completed and not previous.completed)
                        or ((entry.observedAt or 0) > (previous.observedAt or 0) and not previous.completed) then shared.quests[id] = entry end
                    period.quests[id] = nil
                end
            end
        end
        db.version = 2
    end
    root.version = 2
    if self.owner ~= guid then
        if self.instanceTimer then self.instanceTimer:Cancel(); self.instanceTimer = nil end
        self.instanceGeneration = (self.instanceGeneration or 0) + 1
        self.instanceRequest, self.instanceReady, self.instanceTimedOut = nil, nil, nil
        self.owner = guid; self.cache = {}; self.dirty = {}; self.completedExpanded = false
        self.preyObservation, self.preyWidgetIDs, self.delveEntrance = nil, {}, nil
        self.retryProviders, self.pendingItems = {}, {}
        for name in pairs(self.providers) do self.dirty[name] = true; self.revisions[name] = (self.revisions[name] or 0) + 1 end
    end
    return db
end

function Planner:Period(cadence, scope)
    local db = self:Database()
    if not db then return end
    local now, reset = self:Now(), self:ResetTime(cadence)
    local periods = scope == "account" and RefineDB.AdventurePlanner.account.periods or db.periods
    local period = periods[cadence]
    if not reset then return nil end
    if not period or period.reset <= now then
        period = { reset = reset, quests = {} }; periods[cadence] = period
        self.completedExpanded = false
    end
    return period
end

function Planner:Invalidate(name)
    self.dirty[name] = true
    self.revisions[name] = (self.revisions[name] or 0) + 1
    if self.visible then self:Schedule() end
end

function Planner:Schedule()
    if self.timer then return end
    self.timer = C_Timer.NewTimer(0.1, function()
        self.timer = nil
        if self.visible then self:Refresh() end
    end)
end

function Planner:Refresh()
    local db = self:Database()
    if not db then return end
    self:CheckBoundaries()
    self.refreshTasks = {}
    for _, name in ipairs(self.providerOrder) do
        if self.dirty[name] and self.providers[name] then
            self.dirty[name] = nil
            self.reads[name] = (self.reads[name] or 0) + 1
            self.readingProvider = name
            self.retryProviders[name] = nil
            local ok, records = pcall(self.providers[name], self)
            self.readingProvider = nil
            if not ok then
                self.errors = self.errors or {}; self.errors[name] = "Provider read failed"
                self.retryProviders[name] = true
                records = { { id = name .. ":unavailable", provider = name, kind = name == "resources" and "Resource" or "Progress",
                    title = name == "instances" and "Instance lockouts" or name:gsub("^%l", string.upper),
                    state = "unknown", verification = "unknown", bucket = "weekly", category = name,
                    detail = "Progress unavailable", coverageRequired = name == "quests" or name == "vault" } }
            end
            self.cache[name] = records or {}
        end
    end
    local records = {}
    for _, name in ipairs(self.providerOrder) do
        for _, record in ipairs(self.cache[name] or {}) do records[#records + 1] = record end
    end
    self.refreshTasks = nil
    self.view = RefineUI.PlannerModel.Build(records, db.preferences, self:Now(), self:ResetTime("daily"))
    if self.visible and Module.RenderPlanner then Module:RenderPlanner(self.view) end
end

function Planner:CheckBoundaries()
    local now = self:Now()
    local db = self:Database()
    if not db then return end
    for _, scope in ipairs({ "character", "account" }) do
    for _, cadence in ipairs({ "daily", "weekly" }) do
        local periods = scope == "account" and RefineDB.AdventurePlanner.account.periods or db.periods
        local period = periods[cadence]
        if period and period.reset <= now then
            self:Period(cadence, scope)
            self:Invalidate("quests")
            self:Invalidate("prey"); self:Invalidate("delves"); self:Invalidate("events")
            if cadence == "weekly" then self:Invalidate("vault"); self:Invalidate("resources"); self:Invalidate("journeys") end
        end
    end
    end
    for name, records in pairs(self.cache) do
        for _, r in ipairs(records) do
            local boundary = r.validUntil or r.expiresAt
            if r.expiresAt then boundary = math.min(boundary or math.huge, r.expiresAt) end
            if r.nextRechargeAt then boundary = math.min(boundary or math.huge, r.nextRechargeAt) end
            if boundary and boundary <= now and not r.boundaryInvalidated then
                r.boundaryInvalidated = true; self:Invalidate(name)
            end
        end
    end
end

function Planner:SetPreference(kind, key, value)
    local db = self:Database()
    if not db then return end
    db.preferences[kind] = db.preferences[kind] or {}
    db.preferences[kind][key] = value or nil
    if self.visible then self:Schedule() end
end

function Planner:RestoreHidden()
    local db = self:Database()
    if not db then return end
    db.preferences.hidden = {}; db.preferences.categories = {}
    if self.visible then self:Schedule() end
end

function Planner:RequestInstances()
    if self.instanceRequest then return end
    self.instanceRequest = true; self.instanceTimedOut = false; self.instanceReady = false
    local owner, generation = self.owner, (self.instanceGeneration or 0) + 1
    self.instanceGeneration = generation
    self.instanceTimer = C_Timer.NewTimer(5, function()
        if self.instanceGeneration == generation and self.owner == owner and self.instanceRequest then
            self.instanceTimer = nil
            self.instanceRequest = nil; self.instanceTimedOut = true; self:Invalidate("instances")
        end
    end)
    -- Install the timeout first: a synchronous cached response may cancel it.
    RequestRaidInfo()
end

function Planner:Show()
    self:Database(); self.visible = true
    for name in pairs(self.providers) do
        if not self.cache[name] then self.dirty[name] = true end
        for _, record in ipairs(self.cache[name] or {}) do
            if record.state == "unknown" or record.state == "loading" then self.dirty[name] = true; break end
        end
    end
    self:RequestInstances(); self:Invalidate("instances")
    self:Refresh()
    if self.ticker then self.ticker:Cancel() end
    self.ticker = C_Timer.NewTicker(1, function()
        self:CheckBoundaries()
        if Module.UpdatePlannerHeader then Module:UpdatePlannerHeader() end
        if Module.UpdatePlannerCountdowns then Module:UpdatePlannerCountdowns() end
    end)
end

function Planner:Hide()
    self.visible = false
    for _, key in ipairs({ "timer", "ticker", "instanceTimer" }) do
        if self[key] then self[key]:Cancel(); self[key] = nil end
    end
    self.instanceRequest = nil; self.instanceGeneration = (self.instanceGeneration or 0) + 1
end

function Module:RegisterWeeklyHubEvents()
    if Planner.registered then return end
    Planner.registered = true
    local events = {
        QUEST_LOG_UPDATE = "quests", QUEST_ACCEPTED = "quests", QUEST_REMOVED = "quests", QUEST_TURNED_IN = "quests",
        QUEST_DATA_LOAD_RESULT = "quests", WEEKLY_REWARDS_UPDATE = "vault", UPDATE_INSTANCE_INFO = "instances",
        TASK_PROGRESS_UPDATE = "quests", WORLD_QUEST_COMPLETED_BY_SPELL = "quests",
        UPDATE_UI_WIDGET = "widget", UPDATE_ALL_UI_WIDGETS = "widgetSet",
        AREA_POIS_UPDATED = "maps", ZONE_CHANGED_NEW_AREA = "maps",
        CURRENCY_DISPLAY_UPDATE = "resources",
        ITEM_INTERACTION_CHARGE_INFO_UPDATED = "resources",
        BAG_UPDATE_DELAYED = "resources", PLAYERBANKSLOTS_CHANGED = "resources",
        PLAYER_ENTERING_WORLD = "all", PLAYER_LEVEL_UP = "all", PLAYER_REGEN_ENABLED = "retry",
        PLAYER_REGEN_DISABLED = "view", GET_ITEM_INFO_RECEIVED = "item", PLAYER_LOGOUT = "logout",
        UPDATE_FACTION = "journeys", MAJOR_FACTION_RENOWN_LEVEL_CHANGED = "journeys", MAJOR_FACTION_UNLOCKED = "journeys",
        ACTIVE_DELVE_DATA_UPDATE = "delveContext", WALK_IN_DATA_UPDATE = "delveContext",
        PARTY_ELIGIBILITY_FOR_DELVE_TIERS_CHANGED = "delveContext", GROUP_ROSTER_UPDATE = "delveContext",
        TRADE_SKILL_SHOW = "professionContext", TRADE_SKILL_DATA_SOURCE_CHANGED = "professionContext",
        TRADE_SKILL_CLOSE = "professionClosed", ADDON_LOADED = "hooks",
        CRAFTINGORDERS_FULFILL_ORDER_RESPONSE = "orderFulfilled",
        CRAFTINGORDERS_HIDE_CRAFTER = "professionClosed", CRAFTINGORDERS_UPDATE_REWARDS = "orderRewards",
        ADDON_RESTRICTION_STATE_CHANGED = "retry",
    }
    for event, provider in pairs(events) do
        -- Optional systems vary across supported client builds. One unavailable
        -- event must not prevent the remaining lifecycle handlers registering.
        local valid = Planner:Call(C_EventUtils, "IsEventValid", event)
        if valid == false then
            Planner.unavailableEvents = Planner.unavailableEvents or {}
            Planner.unavailableEvents[event] = true
        else
        RefineUI:RegisterEventCallback(event, function(_, ...)
            if provider == "logout" then Planner:Hide(); return end
            if provider == "widget" then
                local update = ...
                if Evidence.Table(update) then
                    local id, set = update.widgetID, update.widgetSetID
                    if Evidence.Number(id) and ((Evidence.Number(set) and set == 1843) or (Planner.preyWidgetIDs and Planner.preyWidgetIDs[id])) then
                        Planner:CapturePrey(); Planner:Invalidate("prey")
                    end
                end
            elseif provider == "widgetSet" then
                Planner:CapturePrey(); Planner:Invalidate("prey")
            elseif provider == "maps" then
                for _, name in ipairs({ "quests", "delves", "events" }) do Planner:Invalidate(name) end
            elseif provider == "delveContext" then
                if Planner.CaptureDelveEntrance then Planner:CaptureDelveEntrance() end
                Planner:Invalidate("delves")
            elseif provider == "item" then
                local id = ...
                if Evidence.Number(id) and Planner.pendingItems[id] then
                    Planner.pendingItems[id] = nil; Planner:Invalidate("vault"); Planner:Invalidate("resources")
                end
            elseif provider == "retry" then
                if Planner.retryProviders.delves and Planner.CaptureDelveEntrance then Planner:CaptureDelveEntrance() end
                for name in pairs(Planner.retryProviders) do Planner:Invalidate(name) end
                if Planner.visible then Planner:Schedule() end
            elseif provider == "hooks" or provider == "professionContext" then
                if Planner.InstallOrderHooks then Planner:InstallOrderHooks() end
                if Planner.InstallDelveHooks then Planner:InstallDelveHooks() end
                for name in pairs(Planner.retryProviders) do Planner:Invalidate(name) end
                if provider == "professionContext" then Planner:Invalidate("professions") end
            elseif provider == "professionClosed" then
                Planner.orderContext = nil; Planner:Invalidate("professions")
            elseif provider == "orderFulfilled" then
                if Planner.ObserveOrderFulfilled then Planner:ObserveOrderFulfilled(...) end
            elseif provider == "orderRewards" then
                -- Reward contents can change; do not retain an old promised reward.
                if Planner.InvalidateOrderReward then Planner:InvalidateOrderReward(...) end
            elseif provider == "all" then
                Planner:Database()
                Planner:ObserveQuests()
                if Planner.CapturePrey then Planner:CapturePrey() end
                if Planner.InstallOrderHooks then Planner:InstallOrderHooks() end
                if Planner.InstallDelveHooks then Planner:InstallDelveHooks() end
                for name in pairs(Planner.providers) do Planner:Invalidate(name) end
            elseif provider == "quests" then
                if event == "QUEST_ACCEPTED" then
                    local questID = ...
                    if Evidence.Number(questID) then for _, cadence in ipairs({ "daily", "weekly" }) do
                        for _, scope in ipairs({ "character", "account" }) do
                        local period = Planner:Period(cadence, scope)
                        if period and period.quests[questID] then
                            period.quests[questID].completed, period.quests[questID].completedAt = nil, nil
                        end
                        end
                    end end
                end
                if event == "QUEST_TURNED_IN" or event == "WORLD_QUEST_COMPLETED_BY_SPELL" then Planner:ObserveTurnIn(...) else Planner:ObserveQuests() end
                Planner:Invalidate("quests"); Planner:Invalidate("prey"); Planner:Invalidate("journeys")
            elseif provider == "instances" then
                Planner.instanceReady = true; Planner.instanceTimedOut = nil; Planner.instanceRequest = nil
                if Planner.instanceTimer then Planner.instanceTimer:Cancel(); Planner.instanceTimer = nil end
                Planner:Invalidate(provider)
            elseif provider == "view" then
                if Planner.visible then Planner:Schedule() end
            else Planner:Invalidate(provider) end
        end, self:BuildKey("Planner", event))
        end
    end
    Planner:ObserveQuests()
    if Planner.InstallOrderHooks then Planner:InstallOrderHooks() end
    if Planner.InstallDelveHooks then Planner:InstallDelveHooks() end
    if Planner.CapturePrey then Planner:CapturePrey() end
end
