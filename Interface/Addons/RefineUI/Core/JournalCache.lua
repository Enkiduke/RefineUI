-- Account-wide, disposable journal data. Bind lazily after SavedVariables load.
local _, RefineUI = ...
local Cache = {}
RefineUI.JournalCache = Cache
local VERSION = 1
local TTL = {
    catalogs = 30 * 86400,
    manifests = 30 * 86400,
    rows = 30 * 86400,
    summaries = 7 * 86400,
    details = 7 * 86400,
}
local MAX_ENTRIES = { manifests = 512, rows = 512, summaries = 512, default = 256 }
local OWNERSHIP_KEYS = { "achievements", "appearances", "pets", "mounts", "toys" }

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        -- Item-load requests belong to the current session, never SavedVariables.
        if key ~= "requested" then result[key] = Copy(child) end
    end
    return result
end

function Cache:Store()
    local build, interface = "unknown", 0
    if GetBuildInfo then _, build, _, interface = GetBuildInfo() end
    local locale = GetLocale and GetLocale() or "enUS"
    local db = _G.RefineUIJournalCache
    -- A build number changes for hotfixes which usually do not change journal
    -- data. The interface number is the useful compatibility boundary; TTLs
    -- cover server-side loot changes between interface releases.
    local legacyBuildChanged = type(db) == "table" and not db.interface
        and db.build and db.build ~= build
    if type(db) ~= "table" or db.version ~= VERSION or db.locale ~= locale or legacyBuildChanged
        or (db.interface and interface ~= 0 and db.interface ~= interface) then
        db = { version = VERSION, build = build, interface = interface, locale = locale,
            buckets = {}, ownership = {} }
        _G.RefineUIJournalCache = db
    else
        db.build, db.interface = build, interface
        db.buckets, db.ownership = db.buckets or {}, db.ownership or {}
    end
    return db
end

function Cache:Bucket(kind)
    local db = self:Store()
    -- Faction affects journal drops and achievement availability; characters of
    -- the same faction share data regardless of class, realm, or UI profile.
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
    local key = kind .. ":" .. faction
    db.buckets[key] = db.buckets[key] or {}
    return db.buckets[key]
end

function Cache:Get(kind, key)
    local bucket = self:Bucket(kind)
    local entry = bucket[key]
    local now = time()
    if not entry then return end
    local ttl = TTL[kind] or TTL.details
    if type(entry.saved) ~= "number" or now < entry.saved or now - entry.saved >= ttl then
        bucket[key] = nil
        return
    end
    entry.used = now
    return Copy(entry.value)
end

function Cache:Put(kind, key, value)
    local bucket, now = self:Bucket(kind), time()
    bucket[key] = { saved = now, used = now, value = Copy(value) }
    local count, oldestKey, oldest = 0, nil, math.huge
    for id, entry in pairs(bucket) do
        count = count + 1
        if id ~= key and entry.used < oldest then oldestKey, oldest = id, entry.used end
    end
    local limit = MAX_ENTRIES[kind] or MAX_ENTRIES.default
    if count > limit and oldestKey then bucket[oldestKey] = nil end
end

function Cache:Remove(kind, key)
    self:Bucket(kind)[key] = nil
end

function Cache:GetOwnershipRevisions()
    local revisions, saved = {}, self:Store().ownership
    for _, kind in ipairs(OWNERSHIP_KEYS) do revisions[kind] = saved[kind] or 0 end
    return revisions
end

function Cache:BumpOwnership(kind)
    local saved = self:Store().ownership
    if kind then
        saved[kind] = (saved[kind] or 0) + 1
    else
        for _, key in ipairs(OWNERSHIP_KEYS) do saved[key] = (saved[key] or 0) + 1 end
    end
end

function Cache:OwnershipMatches(revisions)
    if type(revisions) ~= "table" then return false end
    local current = self:Store().ownership
    for _, kind in ipairs(OWNERSHIP_KEYS) do
        if (revisions[kind] or 0) ~= (current[kind] or 0) then return false end
    end
    return true
end

function Cache:InvalidateOwnership(kind)
    -- Keep summaries and manifests. A revision mismatch makes the next reader
    -- recompute ownership from the compact manifest without touching the journal.
    if kind == true then kind = "achievements" end
    self:BumpOwnership(kind)
    if kind ~= "achievements" then
        -- Detail snapshots predate revision stamps and must be dropped. Their
        -- journal catalogs remain available, so rebuilding them is inexpensive.
        local db = self:Store()
        for key in pairs(db.buckets) do
            if key:match("^details:") then db.buckets[key] = nil end
        end
    end
end
