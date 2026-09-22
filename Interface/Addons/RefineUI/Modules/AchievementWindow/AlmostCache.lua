local _, RefineUI = ...
local Window = RefineUI:GetModule("AchievementWindow")
local SCHEMA = 1

local function CacheKey()
    local version, build, _, interface = GetBuildInfo()
    return table.concat({version, build, interface, GetLocale()}, ":")
end

local function ValidNumber(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function ValidCache(cache)
    if type(cache) ~= "table" or cache.schema ~= SCHEMA or cache.key ~= CacheKey()
        or type(cache.catalog) ~= "table" or type(cache.rows) ~= "table"
        or #cache.catalog > 30000 or #cache.rows > 30000 then return false end
    for _, entry in ipairs(cache.catalog) do
        if type(entry) ~= "table" or not ValidNumber(entry.id) or not ValidNumber(entry.category) then return false end
    end
    for _, row in ipairs(cache.rows) do
        if type(row) ~= "table" or not ValidNumber(row.id) or not ValidNumber(row.category)
            or not ValidNumber(row.percent) or row.percent > 100 or type(row.name) ~= "string"
            or type(row.expansion) ~= "number" then return false end
    end
    return true
end

function Window:RestoreAlmostCache()
    if self.almostCacheRestored then return end
    self.almostCacheRestored = true
    local cache = RefineUIAchievementCache
    if not ValidCache(cache) then
        RefineUIAchievementCache = nil
        return
    end
    self.almostRows, self.almostCatalog = cache.rows, cache.catalog
    self.almostCatalogDirty = self.almostCatalogDirty or cache.catalogDirty
    -- Progress can change while logged out or on another character. Publish the
    -- saved snapshot immediately, then refresh only when the panel is opened.
    self.almostDirty = true
    self:RenderAlmostCompleted()
end

function Window:SaveAlmostCache()
    -- Publish only completed scans; a reload during a paused/in-progress scan
    -- leaves the last usable snapshot intact. SavedVariables serializes on exit.
    RefineUIAchievementCache = {
        schema = SCHEMA, key = CacheKey(), rows = self.almostRows,
        catalog = self.almostCatalog, catalogDirty = self.almostCatalogDirty or false,
    }
end

function Window:InvalidateAlmostSavedCache(event, achievementID)
    local cache = RefineUIAchievementCache
    if type(cache) ~= "table" then return end
    if event == "ACHIEVEMENT_EARNED" or event == "RECEIVED_ACHIEVEMENT_LIST" then
        cache.catalogDirty = true
    end
    if event == "ACHIEVEMENT_EARNED" and type(cache.rows) == "table" then
        for index = #cache.rows, 1, -1 do
            local row = cache.rows[index]
            if type(row) == "table" and row.id == achievementID then table.remove(cache.rows, index) end
        end
    end
end
