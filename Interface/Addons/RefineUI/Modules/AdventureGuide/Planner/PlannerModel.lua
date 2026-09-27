-- Pure projection: no API reads, persistence or UI work here.
local _, RefineUI = ...
local Model = {}
RefineUI.PlannerModel = Model

local ACTIONABLE = { ready = true, active = true, available = true }
local STATE_ORDER = { ready = 1, active = 2, available = 3, missing = 4, unknown = 5, complete = 6 }
Model.RECOMMENDED, Model.PER_CATEGORY = 5, 2
Model.SECTIONS = {
    { key = "weekly", title = "Weekly Activities" },
    { key = "delves", title = "Delves & Prey" },
    { key = "professions", title = "Professions" },
    { key = "progress", title = "Journeys" },
    { key = "lockouts", title = "Lockouts" },
    { key = "nearby", title = "Nearby" },
    { key = "optional", title = "Legacy & Optional", collapsed = true },
    { key = "completed", title = "Completed", collapsed = true },
}

local function Recommendation(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if (a.weight or 0) ~= (b.weight or 0) then return (a.weight or 0) > (b.weight or 0) end
    return a.id < b.id
end

local function Hidden(r, prefs, search)
    local filters, mode = prefs.filters, prefs.filters.mode
    if prefs.hidden[r.id] or prefs.categories[r.category] then return true end
    if r.kind == "lead" and r.resetKey and prefs.dismissedLeads[r.id] == r.resetKey then return true end
    if r.kind == "resource" then return filters.hideResources end
    if filters.hideUnavailable and (r.state == "unknown" or r.state == "missing") then return true end
    if mode == "pinned" and not r.pinned then return true end
    if mode == "actionable" and not (ACTIONABLE[r.state] and (r.kind == "task" or r.kind == "lead")) then return true end
    if mode == "ready" and r.state ~= "ready" then return true end
    if mode == "expiring" and not r.expiring then return true end
    return search and not (r.title .. " " .. (r.category or "")):lower():find(search, 1, true)
end

function Model.Build(records, prefs, now, dailyReset)
    local view = { recommended = {}, rings = {}, resources = {}, sections = {},
        counts = { ready = 0, remaining = 0, completed = 0 } }
    local search = prefs.filters.search
    search = search and search ~= "" and search:lower() or nil
    local function Boundary(at)
        if at and at > now and (not view.nextBoundary or at < view.nextBoundary) then view.nextBoundary = at end
    end
    Boundary(dailyReset)
    local rows, candidates, seen = {}, {}, {}
    for _, section in ipairs(Model.SECTIONS) do rows[section.key] = {} end
    for _, r in ipairs(records) do
        if not seen[r.id] then
            seen[r.id] = true
            r.pinned, r.focused = prefs.pins[r.id] or false, prefs.focus[r.id] or false
            r.expiring = ACTIONABLE[r.state] and r.expiresAt and dailyReset and r.expiresAt <= dailyReset and not r.optional or nil
            if r.expiring and r.tier and r.tier > 3 then r.tier = 3 end
            -- Focus is an explicit priority override; Pin only keeps a row visible.
            r.rank = r.focused and math.min(r.tier or 6, 2.5) or r.tier or 6
            Boundary(r.expiresAt)
            if r.kind == "vault" or r.id == "prey:weekly" then
                view.rings[#view.rings + 1] = r
            elseif not Hidden(r, prefs, search) then
                if r.kind == "resource" then
                    view.resources[#view.resources + 1] = r
                elseif r.state == "complete" and not r.pinned then
                    view.counts.completed = view.counts.completed + 1
                    rows.completed[#rows.completed + 1] = r
                else
                    if r.kind == "task" and ACTIONABLE[r.state] and not r.optional then
                        view.counts.remaining = view.counts.remaining + 1
                        if r.state == "ready" then view.counts.ready = view.counts.ready + 1 end
                    end
                    if r.recommend and ACTIONABLE[r.state] and (not r.optional or r.focused) then candidates[#candidates + 1] = r end
                    if rows[r.section] then rows[r.section][#rows[r.section] + 1] = r end
                end
            end
        end
    end
    table.sort(candidates, Recommendation)
    local picked, perCategory = {}, {}
    for _, r in ipairs(candidates) do
        if #view.recommended >= Model.RECOMMENDED then break end
        local used = perCategory[r.category] or 0
        if used < Model.PER_CATEGORY or r.rank <= 1 or r.focused then
            view.recommended[#view.recommended + 1] = r
            perCategory[r.category], picked[r.id] = used + 1, true
        end
    end
    if #view.recommended == 0 then
        view.emptyMessage = view.counts.remaining == 0 and "You're caught up for this week" or "Nothing urgent right now"
        view.emptyDetail = view.counts.remaining == 0 and "Check back after the next reset." or "Your remaining activities are listed below."
    end
    local order = prefs.order
    for _, section in ipairs(Model.SECTIONS) do
        local list, visible = rows[section.key], {}
        for _, r in ipairs(list) do if not picked[r.id] then visible[#visible + 1] = r end end
        table.sort(visible, function(a, b)
            local ao, bo = order[a.id] or 0, order[b.id] or 0
            if ao ~= bo then return ao < bo end
            if a.pinned ~= b.pinned then return a.pinned end
            local as, bs = STATE_ORDER[a.state] or 5, STATE_ORDER[b.state] or 5
            if as ~= bs then return as < bs end
            return Recommendation(a, b)
        end)
        if #visible > 0 then
            local collapsed = prefs.collapsed[section.key]
            if collapsed == nil then collapsed = section.collapsed or false end
            view.sections[#view.sections + 1] = { key = section.key, title = section.title, rows = visible, collapsed = collapsed }
        end
    end
    return view
end
