local _, RefineUI = ...
local Module = RefineUI:RegisterModule("AdventureGuidePlanner")
local Planner = { providers = {}, cache = {}, dirty = {}, pendingItems = {}, requested = {},
    providerOrder = { "vault", "quests", "prey", "delves", "professions", "resources", "lockouts", "journeys", "events" } }
RefineUI.AdventurePlanner = Planner

local issecretvalue, canaccessvalue, canaccesstable = issecretvalue, canaccessvalue, canaccesstable
local PREFERENCES = { "pins", "hidden", "categories", "focus", "order", "filters", "dismissedLeads", "collapsed" }
local REFRESH_KEY = "AdventureGuidePlanner:Refresh"

function Module:BuildKey(...)
    local key = "AdventureGuidePlanner"
    for index = 1, select("#", ...) do key = key .. ":" .. tostring(select(index, ...)) end
    return key
end

-- Secret, inaccessible and non-finite values never enter Planner state. Fields of
-- returned tables are checked again where they are read.
function Planner.Safe(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    local kind = type(value)
    if kind == "table" and canaccesstable and not canaccesstable(value) then return nil end
    if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then return nil end
    return value
end
local Safe = Planner.Safe

local function Clean(count, value, ...)
    if count <= 0 then return end
    return Safe(value), Clean(count - 1, ...)
end
local function Checked(ok, ...)
    if ok then return Clean(select("#", ...), ...) end
end

-- Optional APIs vary across the supported builds; a missing or failing call
-- is simply no answer.
function Planner:Call(namespace, method, ...)
    local fn = namespace and namespace[method]
    if type(fn) == "function" then return Checked(pcall(fn, ...)) end
end

function Planner:Now() return GetServerTime() end

function Planner:ResetTime(cadence)
    local seconds = self:Call(C_DateAndTime, cadence == "daily" and "GetSecondsUntilDailyReset" or "GetSecondsUntilWeeklyReset")
    if type(seconds) == "number" and seconds > 0 then return self:Now() + seconds end
end

function Planner:Database()
    if self.db then return self.db end
    local guid = UnitGUID("player")
    if not guid or not RefineDB then return end
    local root = RefineDB.AdventurePlanner or {}
    RefineDB.AdventurePlanner = root
    root.characters = root.characters or {}
    root.account = root.account or {}
    root.account.periods = root.account.periods or {}
    local db = root.characters[guid] or {}
    root.characters[guid] = db
    db.preferences = db.preferences or {}
    for _, key in ipairs(PREFERENCES) do db.preferences[key] = db.preferences[key] or {} end
    db.periods = db.periods or {}
    db.snapshots = db.snapshots or {}
    db.snapshots.orders = db.snapshots.orders or {}
    db.version, root.version = 2, 2
    self.owner, self.db = guid, db
    return db
end

function Planner:Period(cadence, scope)
    local db = self:Database()
    if not db then return end
    local periods = scope == "account" and RefineDB.AdventurePlanner.account.periods or db.periods
    local period = periods[cadence]
    if period and period.reset > self:Now() then return period end
    local reset = self:ResetTime(cadence)
    if not reset then return end
    period = { reset = reset, quests = {} }
    periods[cadence] = period
    return period
end

function Planner:Invalidate(...)
    for index = 1, select("#", ...) do self.dirty[select(index, ...)] = true end
    if self.visible then RefineUI:Debounce(REFRESH_KEY, 0.1, function() if self.visible then self:Refresh() end end) end
end

function Planner:InvalidateAll()
    for _, name in ipairs(self.providerOrder) do self.dirty[name] = true end
    self:Invalidate()
end

function Planner:Refresh()
    local db = self:Database()
    if not db then return end
    self.mapTasks = {}
    for _, name in ipairs(self.providerOrder) do
        if self.dirty[name] or not self.cache[name] then
            self.dirty[name] = nil
            self.cache[name] = self.providers[name](self, db)
        end
    end
    self.mapTasks = nil
    local records = {}
    for _, name in ipairs(self.providerOrder) do
        for _, record in ipairs(self.cache[name]) do records[#records + 1] = record end
    end
    self.view = RefineUI.PlannerModel.Build(records, db.preferences, self:Now(), self:ResetTime("daily"))
    if Module.RenderPlanner then Module:RenderPlanner(self.view) end
end

-- The ticker only updates clock text; it re-reads providers once a reset or a
-- displayed expiry passes.
function Planner:Tick()
    local view, now = self.view, self:Now()
    if view and view.nextBoundary and view.nextBoundary <= now then self:InvalidateAll() end
    if Module.UpdatePlannerClock then Module:UpdatePlannerClock() end
end

function Planner:SetPreference(kind, key, value)
    local db = self:Database()
    if not db then return end
    db.preferences[kind][key] = value or nil
    if kind == "pins" and key:match("^currency:") then self.dirty.resources = true end
    self:Invalidate()
end

function Planner:Show()
    if not self:Database() then return end
    self.visible = true
    self:Refresh()
    if self.ticker then self.ticker:Cancel() end
    self.ticker = C_Timer.NewTicker(10, function() self:Tick() end)
end

function Planner:Hide()
    self.visible = false
    RefineUI:CancelDebounce(REFRESH_KEY)
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

-- Hidden bookkeeping is limited to accepted and turned-in quest IDs; full quest
-- log scans only happen while the Planner is visible.
local events = {
    QUEST_ACCEPTED = function(questID) Planner:ObserveQuest(Safe(questID)); Planner:Invalidate("quests", "prey") end,
    QUEST_TURNED_IN = function(questID) Planner:ObserveTurnIn(Safe(questID)); Planner:Invalidate("quests", "prey", "professions", "journeys") end,
    WORLD_QUEST_COMPLETED_BY_SPELL = function(questID) Planner:ObserveTurnIn(Safe(questID)); Planner:Invalidate("quests") end,
    QUEST_REMOVED = "quests", QUEST_LOG_UPDATE = "quests", TASK_PROGRESS_UPDATE = "quests", QUEST_DATA_LOAD_RESULT = "quests",
    WEEKLY_REWARDS_UPDATE = "vault", UPDATE_INSTANCE_INFO = "lockouts",
    CURRENCY_DISPLAY_UPDATE = function() Planner:Invalidate("resources", "delves") end,
    BAG_UPDATE_DELAYED = function() Planner:Invalidate("resources", "professions") end,
    PLAYERBANKSLOTS_CHANGED = "resources", ITEM_INTERACTION_CHARGE_INFO_UPDATED = "resources",
    AREA_POIS_UPDATED = function() Planner:Invalidate("delves", "events", "quests") end,
    ZONE_CHANGED_NEW_AREA = function() Planner:Invalidate("delves", "events") end,
    ACTIVE_DELVE_DATA_UPDATE = "delves", WALK_IN_DATA_UPDATE = "delves",
    UPDATE_FACTION = "journeys", MAJOR_FACTION_RENOWN_LEVEL_CHANGED = "journeys", MAJOR_FACTION_UNLOCKED = "journeys",
    SKILL_LINES_CHANGED = "professions", TRADE_SKILL_CLOSE = "professions",
    CRAFTINGORDERS_FULFILL_ORDER_RESPONSE = function(...) Planner:ObserveOrderFulfilled(...) end,
    CRAFTINGORDERS_UPDATE_REWARDS = function(...) Planner:InvalidateOrderReward(...) end,
    GET_ITEM_INFO_RECEIVED = function(itemID)
        itemID = Safe(itemID)
        if itemID and Planner.pendingItems[itemID] then
            Planner.pendingItems[itemID] = nil
            Planner:Invalidate("vault", "resources", "professions")
        end
    end,
    ADDON_LOADED = function(name)
        name = Safe(name)
        if name == "Blizzard_EncounterJournal" then Module:InstallPlanner()
        elseif name == "Blizzard_Professions" then Planner:InstallOrderHooks() end
    end,
    PLAYER_ENTERING_WORLD = function() Planner:InvalidateAll() end,
    PLAYER_LEVEL_UP = function() Planner:InvalidateAll() end,
    PLAYER_LOGOUT = function() Planner:Hide() end,
}

function Module:OnEnable()
    for event, handler in pairs(events) do
        if Planner:Call(C_EventUtils, "IsEventValid", event) ~= false then
            local fn = type(handler) == "function" and handler or function() Planner:Invalidate(handler) end
            RefineUI:RegisterEventCallback(event, function(_, ...) fn(...) end, self:BuildKey(event))
        end
    end
    Planner:InstallOrderHooks()
    if type(EncounterJournal) == "table" then self:InstallPlanner() end
end
