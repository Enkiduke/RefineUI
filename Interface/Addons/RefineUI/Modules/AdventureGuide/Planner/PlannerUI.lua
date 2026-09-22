local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuidePlanner")
local Planner = RefineUI.AdventurePlanner
local INK, MUTED = { 0.93, 0.88, 0.76 }, { 0.64, 0.69, 0.73 }
local GOLD = { 0.83, 0.66, 0.36 }

-- Static radial geometry: no animation timer, cooldown numbers or external art
-- dependency. Partial segments preserve exact progress between tick boundaries.
function Module:UpdatePlannerRing(row, fraction)
    if not row.ring then return end
    row.ring:SetShown(fraction ~= nil)
    if fraction == nil then return end
    fraction = math.max(0, math.min(1, fraction))
    local radius = row.ringRadius or 17
    if row.ring.SetSize then row.ring:SetSize(radius * 2 + 4, radius * 2 + 4) end
    for index, segment in ipairs(row.ring.segments) do
        local start = (index - 1) / 32
        local finish = index / 32
        if segment.track then
            segment.track:SetStartPoint("CENTER", radius * math.sin(start * math.pi * 2), radius * math.cos(start * math.pi * 2))
            segment.track:SetEndPoint("CENTER", radius * math.sin(finish * math.pi * 2), radius * math.cos(finish * math.pi * 2))
        end
        local filled = math.max(0, math.min(1, (fraction - start) * 32))
        segment.fill:SetShown(filled > 0)
        if filled > 0 then
            local a, b = start * math.pi * 2, (start + filled / 32) * math.pi * 2
            segment.fill:SetStartPoint("CENTER", radius * math.sin(a), radius * math.cos(a))
            segment.fill:SetEndPoint("CENTER", radius * math.sin(b), radius * math.cos(b))
            segment.fill:SetColorTexture(fraction >= 1 and 0.38 or 0.25, fraction >= 1 and 0.79 or 0.67, fraction >= 1 and 0.48 or 0.91, 1)
        end
    end
end
local stateText = { loading = "Checking progress…", unknown = "Progress unavailable", locked = "Not unlocked",
    ready = "Reward ready", claimable = "Reward ready", complete = "Completed" }
local stateIcon = { ready = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t ",
    claimable = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t " }

local function Text(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    text:SetJustifyH("LEFT"); text:SetTextColor(unpack(INK)); text:SetMaxLines(1)
    return text
end
local function TimeLeft(at)
    if not at then return "Unavailable" end
    local seconds = math.max(0, at - Planner:Now())
    if seconds < 60 then return "<1m" end
    local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60
    if days > 0 then return days .. "d " .. hours .. "h" end
    return hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m")
end

local function CompactNumber(value)
    if type(value) ~= "number" then return tostring(value or "") end
    if value >= 1000000 then return string.format(value >= 10000000 and "%.0fm" or "%.1fm", value / 1000000) end
    if value >= 1000 then return string.format(value >= 10000 and "%.0fk" or "%.1fk", value / 1000) end
    return tostring(value)
end

local function ResourceAmount(r)
    if r.state == "unknown" or r.state == "loading" then return "?" end
    local amount = r.charges
    if amount == nil then amount = r.quantity end
    if amount == nil then amount = r.held end
    if amount == nil then amount = r.weeklyEarned end
    if amount == nil then amount = r.seasonEarned end
    return (r.verification == "snapshot" and "~" or "") .. (amount == nil and "?" or CompactNumber(amount))
end

function Module:UpdatePlannerHeader()
    local page = self.weeklyHub
    if not page then return end
    page.reset:SetText("Daily " .. TimeLeft(Planner:ResetTime("daily")) .. "  •  Weekly " .. TimeLeft(Planner:ResetTime("weekly")))
    page.character:SetText((UnitName("player") or "") .. "  •  Level " .. UnitLevel("player"))
end

-- Text-only clock updates never trigger provider reads or refresh snapshot age.
function Module:UpdatePlannerCountdowns()
    for _, row in ipairs(self.weeklyHub and self.weeklyHub.visibleRows or {}) do
        local r = row.record
        if r and r.kind == "Resource" then
            -- The strip keeps its short amount; age and caps live in the tooltip.
        elseif r and r.verification == "snapshot" then
            local minutes = math.max(0, math.floor((Planner:Now() - (r.observedAt or Planner:Now())) / 60))
            row.detail:SetText((row.baseDetail or "Last seen") .. " • " .. minutes .. "m ago")
        elseif r and r.expiresAt and r.state ~= "unknown" then
            row.detail:SetText((row.baseDetail or "") .. " • " .. (r.expirationMeaning or "Expires") .. " in " .. TimeLeft(r.expiresAt))
        end
    end
end

function Module:PlannerTooltip(owner, r)
    if not r then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.title, 1, 0.82, 0, 1, true)
    local shown = {}
    local function Add(line, red, green, blue)
        if type(line) ~= "string" or line == "" or shown[line] then return end
        shown[line] = true
        GameTooltip:AddLine(line, red or 1, green or 1, blue or 1, true)
    end
    if r.contentEra == "legacy" then
        Add("Legacy • " .. (r.expansionName or "Earlier expansion"), 0.75, 0.75, 0.75)
    end
    if r.kind == "Activity" or r.kind == "Discovery" then
        local cadence = r.oneTime and "One-time" or r.cadence == "daily" and "Daily"
            or r.cadence == "weekly" and "Weekly" or nil
        if cadence then Add(cadence .. (r.scope == "account" and " • Warband" or ""), 0.75, 0.75, 0.75) end
    elseif r.scope == "account" then Add("Warband", 0.75, 0.75, 0.75) end
    Add(r.detail)
    local genericReward = { ["Quest reward"] = true, ["Daily quest reward"] = true,
        ["Weekly quest reward"] = true }
    if (r.kind == "Activity" or r.kind == "Progress" or r.kind == "Resource")
        and r.rewardReason and not genericReward[r.rewardReason]
        and not (r.detail and r.detail:find(r.rewardReason, 1, true)) then
        Add(r.rewardReason, 0.9, 0.82, 0.65)
    end
    for _, objective in ipairs(r.objectives or {}) do
        if not (r.detail and r.detail:find(objective, 1, true)) then Add(objective) end
    end
    for index, milestone in ipairs(r.milestones or {}) do
        local detail = string.format("Option %d: %d / %d%s", index, milestone.current, milestone.target, milestone.reached and " • Unlocked" or "")
        if milestone.itemLevel then detail = detail .. " • Item level " .. milestone.itemLevel end
        Add(detail, 1, 0.82, 0)
    end
    for _, boss in ipairs(r.bosses or {}) do
        Add((boss.complete and "|A:common-icon-checkmark:12:12|a " or "") .. boss.title,
            boss.complete and 0.55 or 1, boss.complete and 0.55 or 1, boss.complete and 0.55 or 1)
    end
    if r.verification == "snapshot" then
        Add("Last seen " .. math.max(0, math.floor((Planner:Now() - (r.observedAt or Planner:Now())) / 60)) .. "m ago", 0.8, 0.8, 0.8)
    end
    if r.expiresAt then Add((r.expirationMeaning or "Expires") .. " in " .. TimeLeft(r.expiresAt), 1, 0.72, 0.3)
    elseif r.resetKey and not r.oneTime and (r.kind == "Activity" or r.kind == "Progress") then
        Add("Reset in " .. TimeLeft(r.resetKey), 0.75, 0.75, 0.75)
    end
    if r.nextRechargeAt then Add("Next charge in " .. TimeLeft(r.nextRechargeAt), 1, 0.82, 0) end
    if (r.state == "unknown" or r.state == "loading") and not r.detail then Add(stateText[r.state], 0.75, 0.75, 0.75) end
    if r.destination then
        Add(InCombatLockdown() and "Open after combat" or ("Click: " .. r.destination.label), 0.7, 0.85, 1)
    end
    Add("Right-click: options", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

local function SafePlannerNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function SafePlannerPosition(position)
    if issecretvalue and issecretvalue(position) then return false end
    if type(position) ~= "table" then return false end
    if canaccesstable and not canaccesstable(position) then return false end
    return SafePlannerNumber(position.x) and SafePlannerNumber(position.y)
        and position.x >= 0 and position.x <= 1 and position.y >= 0 and position.y <= 1
end

local function CanPlannerPin(mapID)
    if not (C_Map and type(C_Map.CanSetUserWaypointOnMap) == "function") then return false end
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
    return ok and not (issecretvalue and issecretvalue(can)) and can == true
end

-- An exact sub-map point can be translated to a parent map when the sub-map
-- itself does not accept user waypoints. Never pin the parent at a guessed spot.
local function ResolvePlannerPin(mapID, position)
    if CanPlannerPin(mapID) then return mapID, position end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos
        and C_Map.GetMapInfo and CreateVector2D) then return end
    local okVector, vector = pcall(CreateVector2D, position.x, position.y)
    if not okVector or not vector then return end
    local okWorld, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, vector)
    if not okWorld or not SafePlannerNumber(continent) or not world then return end
    local current = mapID
    for _ = 1, 8 do
        local okInfo, info = pcall(C_Map.GetMapInfo, current)
        if not okInfo or not info or (issecretvalue and issecretvalue(info))
            or (canaccesstable and not canaccesstable(info)) then break end
        local okParent, parent = pcall(function() return info.parentMapID end)
        if not okParent then break end
        if not SafePlannerNumber(parent) or parent <= 0 or parent == current then break end
        current = parent
        if CanPlannerPin(current) then
            local okMap, resolvedMap, resolved = pcall(C_Map.GetMapPosFromWorldPos, continent, world, current)
            if okMap and SafePlannerNumber(resolvedMap) and resolvedMap == current
                and resolved and not (issecretvalue and issecretvalue(resolved)) then
                local okXY, x, y = pcall(function()
                    if resolved.GetXY then return resolved:GetXY() end
                    return resolved.x, resolved.y
                end)
                if not okXY then x, y = nil, nil end
                local projected = { x = x, y = y }
                if SafePlannerPosition(projected) then return current, projected end
            end
        end
    end
end

function Module:SetPlannerWaypoint(mapID, position)
    if not SafePlannerNumber(mapID) or mapID <= 0 or mapID % 1 ~= 0
        or not SafePlannerPosition(position) or not (UiMapPoint and UiMapPoint.CreateFromCoordinates)
        or not (C_Map and C_Map.SetUserWaypoint) then return false end
    local targetMap, target = ResolvePlannerPin(mapID, position)
    if not targetMap then return false end
    local okPoint, point = pcall(UiMapPoint.CreateFromCoordinates, targetMap, target.x, target.y)
    if not okPoint or not point then return false end
    local okSet, wasSet = pcall(C_Map.SetUserWaypoint, point)
    if not okSet or (issecretvalue and issecretvalue(wasSet)) or wasSet ~= true then return false end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true, targetMap
end

function Module:TrackPlannerQuest(questID)
    if not SafePlannerNumber(questID) or questID <= 0 or not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return false end
    local onQuest, active = false, false
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, value = pcall(C_QuestLog.IsOnQuest, questID)
        onQuest = ok and not (issecretvalue and issecretvalue(value)) and value == true
    end
    if C_TaskQuest and C_TaskQuest.IsActive then
        local ok, value = pcall(C_TaskQuest.IsActive, questID)
        active = ok and not (issecretvalue and issecretvalue(value)) and value == true
    end
    if not onQuest and not active then return false end
    if onQuest and C_QuestLog and C_QuestLog.AddQuestWatch then
        pcall(C_QuestLog.AddQuestWatch, questID)
    end
    return pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
end

local function PlannerQuestWaypoint(questID)
    if not SafePlannerNumber(questID) or not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return end
    local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
    local position = { x = x, y = y }
    if ok and SafePlannerNumber(mapID) and SafePlannerPosition(position) then return mapID, position end
end

function Module:OpenPlannerDestination(r, owner)
    local d = r and r.destination
    if not d then return end
    if InCombatLockdown() then
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Planner: open this destination after combat.", 1, 0.7, 0.2) end
        return
    end
    if d.type == "vault" then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
        if WeeklyRewards_ShowUI then WeeklyRewards_ShowUI() end
    elseif d.type == "quest" then
        ShowQuestLog(); QuestMapFrame_OpenToQuestDetails(d.id)
        if not self:TrackPlannerQuest(d.id) then
            local mapID, position = PlannerQuestWaypoint(d.id)
            if mapID and self:SetPlannerWaypoint(mapID, position) then
                ShowUIPanel(WorldMapFrame); WorldMapFrame:SetMapID(mapID)
            end
        end
    elseif d.type == "map" then
        ShowUIPanel(WorldMapFrame); WorldMapFrame:SetMapID(d.id)
        if not (r.questID and self:TrackPlannerQuest(r.questID)) then
            local mapID, position = d.id, d.position or r.position
            if not position and r.questID then mapID, position = PlannerQuestWaypoint(r.questID) end
            if position then
                local pinned, pinnedMap = self:SetPlannerWaypoint(mapID, position)
                if pinned and pinnedMap ~= d.id then WorldMapFrame:SetMapID(pinnedMap) end
                if not pinned and UIErrorsFrame then
                    UIErrorsFrame:AddMessage("Planner: this location cannot be tracked on the map.", 1, 0.7, 0.2)
                end
            end
        end
    elseif d.type == "instance" then
        EncounterJournal_OpenJournal(d.difficulty, d.id)
    elseif d.type == "journeys" then
        EJ_ContentTab_Select(EncounterJournal.JourneysTab:GetID())
    elseif d.type == "currency" then
        GameTooltip:SetOwner(owner or self.weeklyHub, "ANCHOR_RIGHT")
        GameTooltip:SetCurrencyByID(d.id); GameTooltip:Show()
    end
end

function Module:PlannerRowMenu(owner, r)
    if not r or not MenuUtil then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(r.title)
        root:CreateButton(r.focused and "Remove Focus" or "Focus this goal", function() Planner:SetPreference("focus", r.id, not r.focused) end)
        root:CreateButton(r.pinned and "Unpin" or "Pin", function() Planner:SetPreference("pins", r.id, not r.pinned) end)
        if r.kind == "Discovery" and r.resetKey then
            root:CreateButton("Not offered this week", function()
                Planner:SetPreference("dismissedLeads", r.id, r.resetKey)
            end)
        end
        root:CreateButton("Hide this activity", function() Planner:SetPreference("hidden", r.id, true) end)
        root:CreateButton("Hide category: " .. r.category, function() Planner:SetPreference("categories", r.category, true) end)
        root:CreateButton("Move to top of section", function()
            local order, first = Planner:Database().preferences.order or {}, 0
            for _, value in pairs(order) do first = math.min(first, value) end
            Planner:SetPreference("order", r.id, first - 1)
        end)
    end)
end

function Module:PlannerSettingsMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Adventure Planner")
        local db = Planner:Database()
        db.preferences.filters = db.preferences.filters or {}
        local filters = db.preferences.filters
        local quick = root:CreateButton("Quick filters")
        for _, option in ipairs({ { "All tracked", false }, { "Actionable", "actionable" }, { "Pinned", "pinned" }, { "Rewards ready", "ready" }, { "Expiring soon", "expiring" } }) do
            local label, mode = option[1], option[2]
            quick:CreateRadio(label, function() return (filters.mode or false) == mode end,
                function() Planner:SetPreference("filters", "mode", mode) end)
        end
        root:CreateCheckbox("Hide unavailable", function() return filters.hideUnavailable end,
            function() Planner:SetPreference("filters", "hideUnavailable", not filters.hideUnavailable) end)
        root:CreateCheckbox("Show resources", function() return not filters.hideResources end,
            function() Planner:SetPreference("filters", "hideResources", not filters.hideResources) end)
        root:CreateButton("Reset activity order", function() db.preferences.order = {}; Planner:Schedule() end)
        root:CreateButton("Clear filters", function()
            db.preferences.filters = {}; db.preferences.hidden = {}; db.preferences.categories = {}
            if self.weeklyHub.search then self.weeklyHub.search:SetText("") end
            Planner:Schedule()
        end)
        local categories, activities = root:CreateButton("Visible categories"), root:CreateButton("Visible activities")
        local known, rows = {}, {}
        for _, records in pairs(Planner.cache) do
            for _, r in ipairs(records) do
                if not known[r.id] then known[r.id] = true; rows[#rows + 1] = r end
            end
        end
        table.sort(rows, function(a, b) return a.title < b.title end)
        local categorySeen = {}
        for _, r in ipairs(rows) do
            local id, category = r.id, r.category
            activities:CreateCheckbox(r.title, function() return not db.preferences.hidden[id] end,
                function() Planner:SetPreference("hidden", id, not db.preferences.hidden[id]) end)
            if category and not categorySeen[category] then
                categorySeen[category] = true
                categories:CreateCheckbox(category, function() return not db.preferences.categories[category] end,
                    function() Planner:SetPreference("categories", category, not db.preferences.categories[category]) end)
            end
        end
        root:CreateButton("Restore hidden activities", function() Planner:RestoreHidden() end)
        root:CreateButton(Planner.completedExpanded and "Collapse completed" or "Show completed", function()
            Planner.completedExpanded = not Planner.completedExpanded; Planner:Schedule()
        end)
        local currencies = root:CreateButton("Pin a currency")
        for index = 1, Planner:Call(C_CurrencyInfo, "GetCurrencyListSize") or 0 do
            local info = Planner:Call(C_CurrencyInfo, "GetCurrencyListInfo", index)
            local link = info and not info.isHeader and Planner:Call(C_CurrencyInfo, "GetCurrencyListLink", index)
            local id = link and Planner:Call(C_CurrencyInfo, "GetCurrencyIDFromLink", link)
            if id then
                local key = "currency:" .. id
                currencies:CreateCheckbox(info.name, function() return db and db.preferences.pins[key] end, function()
                    Planner:SetPreference("pins", key, not db.preferences.pins[key]); Planner:Invalidate("resources")
                end)
            end
        end
    end)
end

function Module:ClearPlannerHighlight()
    local page = self.weeklyHub
    if not page then return end
    if page.highlightTimer then page.highlightTimer:Cancel(); page.highlightTimer = nil end
    if page.highlightRow then page.highlightRow:UnlockHighlight(); page.highlightRow = nil end
end

function Module:ScrollPlannerBy(delta)
    local page = self.weeklyHub
    if not page then return end
    local limit = math.max(0, page.content:GetHeight() - page.scroll:GetHeight())
    page.scroll:SetVerticalScroll(math.max(0, math.min(limit, page.scroll:GetVerticalScroll() - delta * 46)))
end

function Module:ScrollPlannerTo(id)
    Planner.weeklyQuestsExpanded = true
    Planner.moreExpanded = true
    if not Planner.expandedActivities then
        Planner.expandedActivities = true
        if Planner.view then self:RenderPlanner(Planner.view) end
    end
    local page = self.weeklyHub
    local row = page.rowByKey["activity:" .. id] or page.rowByKey["progress:" .. id]
        or page.rowByKey["vault:" .. id] or page.rowByKey["discovery:" .. id]
    if not row or not row:IsShown() then return end
    page.scroll:SetVerticalScroll(math.min(row.y, math.max(0, page.content:GetHeight() - page.scroll:GetHeight())))
    self:ClearPlannerHighlight()
    row:LockHighlight(); page.highlightRow = row
    local timer
    timer = C_Timer.NewTimer(2, function()
        if page.highlightTimer == timer then self:ClearPlannerHighlight() end
    end)
    page.highlightTimer = timer
end

local function Entries(view)
    if Planner.expandedActivities == nil then Planner.expandedActivities = false end
    if Planner.moreExpanded == nil then Planner.moreExpanded = false end
    if Planner.weeklyQuestsExpanded == nil then Planner.weeklyQuestsExpanded = true end
    local entries = {}
    local function Add(key, kind, title, detail, record, action)
        entries[#entries + 1] = { key = key, kind = kind, title = title, detail = detail, record = record, action = action }
    end
    local vaultTracks, otherProgress = {}, {}
    for _, r in ipairs(view.progress or {}) do
        if r.id and r.id:match("^vault:track:") and r.milestones then
            vaultTracks[#vaultTracks + 1] = r
        elseif not (r.id and r.id:match("^vault:next:")) then
            -- vault:next records are recommendation goals derived from the track;
            -- rendering them beside the track would repeat the same progress.
            otherProgress[#otherProgress + 1] = r
        end
    end
    if #vaultTracks > 0 then
        Add("heading:vault", "heading", "GREAT VAULT", "Click a track to open")
        for _, r in ipairs(vaultTracks) do
            Add("vault:" .. r.id, "vault", r.title, r.detail, r)
        end
    end
    if #(view.resources or {}) > 0 then
        for _, r in ipairs(view.resources) do
            Add("resource:" .. r.id, "resource", r.title,
                r.verification == "snapshot" and (r.detail or "Last seen") or stateText[r.state] or r.detail, r)
        end
    end
    Add("heading:next", "heading", "NEXT UP", "Top priority")
    for index, r in ipairs(view.nextUp) do
        local reason = r.recommendationReason or "Next step"
        Add("next:" .. r.id, index == 1 and "hero" or "next", r.actionTitle or r.title,
            reason, r)
    end
    if #view.nextUp == 0 then Add("empty:next", "empty", view.emptyMessage or "No clear next step right now",
        view.emptyDetail or (view.caughtUp and "Tracked priorities are complete."
            or "Check your weekly plan and filters.")) end
    local leads = view.discoveries or {}
    if #leads > 0 then
        local leadLimit = #view.nextUp > 0 and 2 or 3
        Add("heading:discoveries", "link", "WORTH STARTING",
            #leads .. " idea" .. (#leads == 1 and "" or "s") .. " • " ..
            (Planner.discoveriesExpanded and "Show less" or "Show all"), nil,
            function() Planner.discoveriesExpanded = not Planner.discoveriesExpanded; Planner:Schedule() end)
        for index, r in ipairs(leads) do
            if Planner.discoveriesExpanded or index <= leadLimit or r.pinned then
                Add("discovery:" .. r.id, "discovery", r.title, r.detail, r)
            end
        end
    end
    local recommended = {}
    for _, r in ipairs(view.nextUp) do recommended[r.id] = true end
    Add("heading:weekly", "link", "WEEKLY PLAN",
            (view.counts.daily + view.counts.weekly) .. " tracked • " .. (Planner.expandedActivities and "Show less" or "Show all"), nil,
            function() Planner.expandedActivities = not Planner.expandedActivities; Planner:Schedule() end)
    local any, shown, omitted = false, 0, 0
    local function AddCore(rows, label, key)
        local headingAdded = false
        for _, r in ipairs(rows or {}) do
            if not recommended[r.id] then
                any = true
                if Planner.expandedActivities or r.pinned or shown < 5 then
                    if label and not headingAdded then Add("heading:" .. key, "heading", label, ""); headingAdded = true end
                    local detail = stateText[r.state] or r.detail or ""
                    Add("activity:" .. r.id, "activity", r.title, detail, r)
                    shown = shown + 1
                else omitted = omitted + 1 end
            end
        end
    end
    AddCore(view.today, "NOW", "today")
    AddCore(view.thisWeek, shown > 0 and "THIS WEEK" or nil, "thisWeek")
    if omitted > 0 then
        Add("weekly:overflow", "link", "+" .. omitted .. " more weekly activit" .. (omitted == 1 and "y" or "ies"),
            "Show the complete weekly list", nil, function() Planner.expandedActivities = true; Planner:Schedule() end)
    end
    if #otherProgress > 0 then
        Add("heading:progress", "heading", "PROGRESS", "Live milestones")
        for _, r in ipairs(otherProgress) do
            local detail = stateText[r.state] or r.detail or ""
            Add("progress:" .. r.id, "progress", r.title, detail, r)
        end
    end
    if not any then Add("empty:weekly", "empty", #view.nextUp > 0 and "No additional weekly activities." or "No tracked activities displayed.", "") end

    local moreCount = #(view.optional or {}) + #(view.legacy or {}) + #(view.context or {})
        + #(view.snapshots or {})
    if moreCount > 0 then
        Add("heading:more", "link", "MORE", moreCount .. " optional, nearby or informational • " .. (Planner.moreExpanded and "Hide" or "Show"), nil,
            function() Planner.moreExpanded = not Planner.moreExpanded; Planner:Schedule() end)
    end
    if Planner.moreExpanded then
        for _, projection in ipairs({ { "optional", "OPTIONAL", "activity" }, { "legacy", "LEGACY", "activity" },
            { "context", "NEARBY", "context" }, { "snapshots", "LAST OBSERVED", "snapshot" } }) do
            local rows = view[projection[1]] or {}
            if #rows > 0 then Add("heading:" .. projection[1], "heading", projection[2], "") end
            for _, r in ipairs(rows) do
                local detail = r.verification == "snapshot" and (r.detail or "Last seen") or stateText[r.state] or r.detail or ""
                Add(projection[3] .. ":" .. r.id, projection[3], r.title, detail, r)
            end
        end
    end
    Add("heading:completed", "link", "✓ " .. view.counts.completed .. " completed",
        (view.counts.pinnedCompleted > 0 and (view.counts.pinnedCompleted .. " pinned above • ") or "") .. (Planner.completedExpanded and "Hide" or "Show"), nil,
        function() Planner.completedExpanded = not Planner.completedExpanded; Planner:Schedule() end)
    if Planner.completedExpanded then
        for _, r in ipairs(view.completed) do Add("completed:" .. r.id, "activity", r.title, "Completed this reset", r) end
    end
    -- Pack the overview into native-size columns. Expanded activity details
    -- retain full-width rows and the same record identities.
    local column, previous = 0, nil
    local resourceColumns = math.max(1, #(view.resources or {}))
    for _, entry in ipairs(entries) do
        local columns = entry.kind == "vault" and 3 or entry.kind == "resource" and resourceColumns
            or (entry.kind == "progress" and entry.record and entry.record.milestones and 3)
        local group = columns and entry.kind or nil
        if columns then
            if previous ~= group then column = 0 end
            entry.column, entry.columns = column, columns
            column = (column + 1) % columns
            previous = group
        else previous, column = nil, 0 end
    end
    return entries
end

function Module:CreatePlannerRow(page)
    local row = CreateFrame("Button", nil, page.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.surface = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    row.surface:SetPoint("TOPLEFT", 0, -2); row.surface:SetPoint("BOTTOMRIGHT", 0, 2)
    row.surface:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    row.surface:SetVertexColor(0.10, 0.14, 0.18, 0.92)
    row.section = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.section:SetAllPoints(); row.section:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.section:SetVertexColor(0.26, 0.29, 0.33, 0.24)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(24, 24); row.icon:SetPoint("TOPLEFT", 12, -10)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.ring = CreateFrame("Frame", nil, row)
    row.ring:SetSize(38, 38); row.ring:SetPoint("CENTER", row.icon, "CENTER")
    row.ring:EnableMouse(false); row.ring.segments = {}
    for index = 1, 32 do
        local a, b = (index - 1) / 32 * math.pi * 2, index / 32 * math.pi * 2
        local track = row.ring:CreateLine(nil, "BACKGROUND")
        track:SetThickness(3); track:SetColorTexture(0.28, 0.30, 0.32, 0.85)
        track:SetStartPoint("CENTER", 17 * math.sin(a), 17 * math.cos(a))
        track:SetEndPoint("CENTER", 17 * math.sin(b), 17 * math.cos(b))
        local fill = row.ring:CreateLine(nil, "ARTWORK"); fill:SetThickness(3)
        row.ring.segments[index] = { track = track, fill = fill }
    end
    row.title = Text(row); row.title:SetPoint("TOPLEFT", 38, -6); row.title:SetPoint("TOPRIGHT", -91, -6)
    row.detail = Text(row, "GameFontHighlightSmall"); row.detail:SetTextColor(unpack(MUTED))
    row.detail:SetPoint("TOPLEFT", 38, -24); row.detail:SetPoint("TOPRIGHT", -91, -24)
    row.divider = row:CreateTexture(nil, "BACKGROUND"); row.divider:SetColorTexture(0.4, 0.28, 0.12, 0.24)
    row.divider:SetHeight(1); row.divider:SetPoint("BOTTOMLEFT"); row.divider:SetPoint("BOTTOMRIGHT")
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetVertexColor(0.35, 0.49, 0.20, 0.9)
    row.bar:SetHeight(3)
    row.open = CreateFrame("Button", nil, row)
    row.open:SetSize(24, 24); row.open:SetPoint("RIGHT", -8, 0)
    row.open.icon = row.open:CreateTexture(nil, "ARTWORK")
    row.open.icon:SetAllPoints()
    row.open.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    row.open:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.open:SetScript("OnClick", function(owner) self:OpenPlannerDestination(row.record, owner) end)
    row.open:SetScript("OnEnter", function(owner) self:PlannerTooltip(owner, row.record) end)
    row.open:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(owner, button)
        if button == "RightButton" and owner.record then self:PlannerRowMenu(owner, owner.record)
        elseif owner.action then owner.action()
        else self:OpenPlannerDestination(owner.record, owner) end
    end)
    row:SetScript("OnEnter", function(owner) self:PlannerTooltip(owner, owner.record) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function Module:RenderPlanner(view)
    local page = self.weeklyHub
    if not page then return end
    self:UpdatePlannerHeader()
    if page.options then
        local prefs = Planner:Database().preferences
        local active = false
        for _, value in pairs(prefs.filters or {}) do if value and value ~= "" then active = true end end
        if next(prefs.hidden or {}) or next(prefs.categories or {}) then active = true end
        page.options:SetText(active and "Filtered • Edit" or "Customize")
    end
    local expiring = 0
    for _, r in ipairs(view.opportunities or {}) do if r.priorityTier == 2 then expiring = expiring + 1 end end
    page.summary:SetText(string.format("%d reward%s ready  •  %d tracked%s", view.counts.ready,
        view.counts.ready == 1 and "" or "s", view.counts.daily + view.counts.weekly,
        expiring > 0 and ("  •  " .. expiring .. " expiring soon") or ""))
    local offset, anchors = page.scroll:GetVerticalScroll(), {}
    for _, row in ipairs(page.visibleRows or {}) do
        if row.y + row:GetHeight() > offset then anchors[#anchors + 1] = { key = row.key, delta = row.y - offset } end
        row:Hide()
    end
    page.visibleRows = {}
    local used = {}
    local y, entries = 0, Entries(view)
    for _, entry in ipairs(entries) do
        local row = page.rowByKey[entry.key]
        if not row then
            row = page.spareRows and table.remove(page.spareRows) or self:CreatePlannerRow(page)
            page.rowByKey[entry.key] = row
        end
        row.key, row.y, row.record, row.action = entry.key, y, entry.record, entry.action
        used[entry.key] = true
        local r = entry.record
        local heading = entry.kind == "heading" or entry.kind == "link"
        local grid = entry.columns ~= nil
        local vault, resource = entry.kind == "vault", entry.kind == "resource"
        local height = heading and 23 or entry.kind == "empty" and 22 or entry.kind == "hero" and 62
            or vault and 82 or resource and 28 or grid and 56 or entry.kind == "next" and 36 or 32
        if grid and entry.column > 0 then y = page.visibleRows[#page.visibleRows].y end
        row:SetHeight(height); row:ClearAllPoints()
        row.y = y
        local columns = entry.columns or 3
        local gap = resource and (columns > page.content:GetWidth() / 28 and 0 or 2) or 8
        local width = (page.content:GetWidth() - gap * (columns - 1)) / columns
        if grid then
            row:SetPoint("TOPLEFT", page.content, "TOPLEFT", entry.column * (width + gap), -y)
            row:SetWidth(width)
        else
            row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -y); row:SetPoint("TOPRIGHT", page.content, "TOPRIGHT", 0, -y)
        end
        row.icon:SetShown(r ~= nil); if r then row.icon:SetTexture(r.icon or 134400) end
        row.icon:ClearAllPoints()
        local hero = entry.kind == "hero"
        local resourceIconSize = math.max(1, math.min(width - 2, width < 44 and 14 or 18))
        if vault then row.icon:SetPoint("TOP", 0, -8)
        elseif resource then
            if width < 34 then row.icon:SetPoint("CENTER", 0, 0)
            else row.icon:SetPoint("LEFT", 2, 0) end
        else row.icon:SetPoint("TOPLEFT", hero and 14 or grid and 12 or 14, hero and -12 or grid and -10 or -7) end
        row.icon:SetSize(hero and 38 or vault and 34 or resource and resourceIconSize or grid and 24 or 20,
            hero and 38 or vault and 34 or resource and resourceIconSize or grid and 24 or 20)
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", heading and 8 or hero and 62 or 44, hero and -10 or -6)
        row.title:SetPoint("TOPRIGHT", heading and -170 or grid and -5 or -44, hero and -10 or -6)
        row.title:SetText((r and stateIcon[r.state] or "") .. (r and r.pinned and "|A:Waypoint-MapPin-Tracked:12:12|a " or "") ..
            (r and r.contentEra == "legacy" and "[Legacy] " or "") .. (r and r.state == "complete" and "✓ " or "") .. entry.title)
        row.title:SetTextColor(unpack(heading and GOLD or r and r.state == "complete" and MUTED or INK))
        row.title:SetShown(not resource)
        row.title:SetJustifyH(vault and "CENTER" or "LEFT")
        if vault then
            row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", 5, -50); row.title:SetPoint("TOPRIGHT", -5, -50)
        end
        if row.surface then
            row.surface:SetShown(r ~= nil and not resource)
            row.surface:SetVertexColor(hero and 0.18 or 0.10, hero and 0.15 or 0.14,
                hero and 0.08 or vault and 0.13 or resource and 0.15 or 0.18,
                hero and 0.96 or resource and 0.72 or 0.92)
            row.section:SetShown(heading)
        end
        if row.title.SetMaxLines then row.title:SetMaxLines(vault and 1 or grid and 2 or 1) end
        row.detail:ClearAllPoints()
        if heading then row.detail:SetPoint("TOPRIGHT", -5, -8); row.detail:SetWidth(240); row.detail:SetJustifyH("RIGHT")
        else row.detail:SetPoint("TOPLEFT", hero and 62 or 44, hero and -35 or grid and -26 or -20);
            row.detail:SetPoint("TOPRIGHT", grid and -5 or -44, hero and -35 or grid and -26 or -20); row.detail:SetJustifyH("LEFT") end
        local detail = entry.detail or ""
        if r and not vault and r.verification ~= "snapshot" and r.state ~= "unknown" and r.state ~= "loading" and r.milestones and #r.milestones > 0 then
            local slots = {}
            for _, slot in ipairs(r.milestones) do
                slots[#slots + 1] = (slot.reached and "|cff65cc85" or "|cff9ba8b3") .. slot.current .. "/" .. slot.target .. "|r"
            end
            detail = table.concat(slots, "   •   ")
        end
        if vault and r.verification ~= "snapshot" and r.state ~= "unknown" and r.state ~= "loading" then
            detail = r.target and r.target > 0 and (r.current .. "/" .. r.target .. " choices") or detail
        end
        if resource then detail = ResourceAmount(r) end
        if grid and entry.kind == "next" then
            detail = (r.category == "Great Vault" and "Next Vault slot • " or "") .. r.recommendationReason
        end
        if vault then
            row.detail:ClearAllPoints(); row.detail:SetPoint("TOPLEFT", 5, -67); row.detail:SetPoint("TOPRIGHT", -5, -67)
            row.detail:SetJustifyH("CENTER")
        elseif resource then
            row.detail:ClearAllPoints(); row.detail:SetPoint("LEFT", resourceIconSize + 5, 0); row.detail:SetPoint("RIGHT", -1, 0)
            row.detail:SetJustifyH("LEFT")
        elseif grid then
            row.detail:ClearAllPoints(); row.detail:SetPoint("TOPLEFT", 6, -43); row.detail:SetPoint("TOPRIGHT", -5, -43)
        end
        row.baseDetail = detail
        row.detail:SetText(detail)
        row.detail:SetShown(not resource or width >= resourceIconSize + 7 + #detail * 6)
        if r and not grid and not hero then
            row.title:ClearAllPoints(); row.title:SetPoint("LEFT", 40, 0); row.title:SetWidth(page.content:GetWidth() * 0.48 - 40)
            row.detail:ClearAllPoints(); row.detail:SetPoint("LEFT", row, "LEFT", page.content:GetWidth() * 0.48, 0)
            row.detail:SetPoint("RIGHT", -42, 0)
        end
        if row.bar then
            local current, target = r and r.current, r and r.target
            if r and r.kind == "Resource" then current, target = r.weeklyEarned or r.seasonEarned or r.charges, r.weeklyCap or r.seasonCap or r.maxCharges end
            if vault and r and r.milestones and #r.milestones > 0 then
                local final = r.milestones[#r.milestones]
                current, target = final.current, final.target
            end
            local valid = r and r.state ~= "unknown" and type(current) == "number" and type(target) == "number" and target > 0
            row.ringRadius = vault and 23 or 17
            self:UpdatePlannerRing(row, valid and (vault or (entry.kind == "progress" and r.milestones)) and current / target or nil)
            row.bar:SetShown(valid and not grid or false)
            if valid then
                row.bar:ClearAllPoints(); row.bar:SetPoint("BOTTOMLEFT", 6, 3)
                row.bar:SetWidth(math.max(1, ((grid and width or page.content:GetWidth()) - 12) * math.min(1, math.max(0, current / target))))
            end
        end
        row.divider:SetShown(heading)
        row.open:SetShown(not grid and r and r.destination ~= nil or false)
        if r and r.destination and row.open.icon then
            local destination = r.destination.type
            if (destination == "map" or destination == "quest") and row.open.icon.SetAtlas
                and C_Texture and C_Texture.GetAtlasInfo("Waypoint-MapPin-Tracked") then
                row.open.icon:SetAtlas("Waypoint-MapPin-Tracked")
            else row.open.icon:SetTexture(r.icon or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up") end
        end
        row:EnableMouse(r ~= nil or entry.action ~= nil)
        row:Show(); page.visibleRows[#page.visibleRows + 1] = row
        y = y + height
    end
    self:UpdatePlannerCountdowns()
    page.content:SetHeight(math.max(1, y))
    for _, anchor in ipairs(anchors) do
        local row = page.rowByKey[anchor.key]
        if row and row:IsShown() then offset = row.y - anchor.delta; break end
    end
    page.scroll:SetVerticalScroll(math.max(0, math.min(offset, math.max(0, y - page.scroll:GetHeight()))))
    -- Drop stale identities after restoring the scroll anchor. Reuse a bounded
    -- pool rather than retaining a frame for every quest ever seen this session.
    page.spareRows = page.spareRows or {}
    for key, row in pairs(page.rowByKey) do
        if not used[key] then
            if page.highlightRow == row then self:ClearPlannerHighlight() end
            row:Hide(); row:UnlockHighlight()
            row.record, row.action, row.key = nil, nil, nil
            page.spareRows[#page.spareRows + 1] = row
            page.rowByKey[key] = nil
        end
    end
end

function Module:CreatePlannerPage(journal)
    local page = CreateFrame("Frame", "RefineUIAdventurePlanner", journal)
    self.weeklyHub = page; page.rowByKey = {}
    page:SetPoint("TOPLEFT", 8, -32); page:SetPoint("BOTTOMRIGHT", -8, 6); page:Hide()
    local bg = page:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(0.035, 0.045, 0.06, 1)
    local art = page:CreateTexture(nil, "BACKGROUND", nil, 1); art:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo("thewarwithin-landingpage-background") then
        art:SetAtlas("thewarwithin-landingpage-background")
        art:SetVertexColor(0.38, 0.43, 0.50, 0.6)
    end
    local header = page:CreateTexture(nil, "BACKGROUND", nil, 2)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(65)
    header:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    header:SetVertexColor(0.06, 0.08, 0.11, 0.88)
    page.title = Text(page, "GameFontNormalLarge"); page.title:SetPoint("TOPLEFT", 24, -12); page.title:SetText("Weekly Planner")
    page.reset = Text(page, "GameFontHighlightSmall"); page.reset:SetPoint("TOPRIGHT", -22, -17)
    page.character = Text(page, "GameFontHighlightSmall"); page.character:SetPoint("LEFT", page.title, "RIGHT", 18, 0)
    page.summary = Text(page); page.summary:SetPoint("TOPLEFT", 24, -41)
    page.options = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.options:SetSize(85, 22); page.options:SetPoint("TOPRIGHT", -22, -37); page.options:SetText("Customize")
    page.options:SetScript("OnClick", function(owner) self:PlannerSettingsMenu(owner) end)
    page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
    page.search:SetSize(160, 20); page.search:SetPoint("RIGHT", page.options, "LEFT", -10, 0)
    page.search:SetAutoFocus(false)
    page.summary:SetPoint("RIGHT", page.search, "LEFT", -12, 0)
    page.search:HookScript("OnTextChanged", function(box)
        Planner:SetPreference("filters", "search", box:GetText())
    end)
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 20, -69); page.scroll:SetPoint("BOTTOMRIGHT", -39, 13)
    page.content = CreateFrame("Frame", nil, page.scroll); page.content:SetSize(720, 1); page.scroll:SetScrollChild(page.content)
    page.scroll:EnableMouseWheel(true)
    page.scroll:SetScript("OnMouseWheel", function(_, delta) self:ScrollPlannerBy(delta) end)
    page.scroll:SetScript("OnSizeChanged", function(_, width) page.content:SetWidth(width) end)
    page:SetScript("OnShow", function()
        local filters = Planner:Database().preferences.filters or {}
        page.search:SetText(filters.search or "")
        Planner:Show()
    end)
    page:SetScript("OnHide", function()
        Planner:Hide(); GameTooltip:Hide()
        self:ClearPlannerHighlight()
        for _, row in pairs(page.rowByKey) do row:UnlockHighlight() end
    end)
    return page
end
