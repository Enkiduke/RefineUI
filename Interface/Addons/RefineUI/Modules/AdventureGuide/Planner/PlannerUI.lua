local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuidePlanner")
local Planner, Model = RefineUI.AdventurePlanner, RefineUI.PlannerModel
local Safe = Planner.Safe

local HEIGHTS = { header = 30, hero = 66, row = 46, empty = 44 }
local RING_FILL = "ui-journeys-renown-radial-fill"
local MODES = { { "All activities", false }, { "Actionable", "actionable" }, { "Pinned", "pinned" },
    { "Rewards ready", "ready" }, { "Expiring soon", "expiring" } }

local function TimeLeft(at)
    if not at then return "" end
    local seconds = math.max(0, at - Planner:Now())
    if seconds < 60 then return "<1m" end
    local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60
    if days > 0 then return days .. "d " .. hours .. "h" end
    return hours > 0 and (hours .. "h " .. minutes .. "m") or (minutes .. "m")
end

local function Clock(at)
    local soon = at - Planner:Now() < 86400
    return CreateAtlasMarkup(soon and "activities-clock-expiringsoon" or "activities-clock-standard", 14, 14) .. " " .. TimeLeft(at)
end

local function CompactNumber(value)
    if type(value) ~= "number" then return "?" end
    if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if value >= 10000 then return string.format("%.0fk", value / 1000) end
    return tostring(value)
end

local function StatusText(r)
    if r.state == "ready" then return GREEN_FONT_COLOR:WrapTextInColorCode(r.kind == "task" and "Ready" or "Complete") end
    if r.expiresAt and r.state ~= "complete" then return Clock(r.expiresAt) end
    if r.current and r.target and r.target > 0 then return r.current .. " / " .. r.target end
    return ""
end

------------------------------------------------------------------------------
-- Destinations
------------------------------------------------------------------------------

local function ValidPosition(position)
    local x, y = position and Safe(position.x), position and Safe(position.y)
    return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function CanPin(mapID)
    return Planner:Call(C_Map, "CanSetUserWaypointOnMap", mapID) == true
end

-- A sub-map point is projected to a waypoint-capable parent only through the
-- client's own world transform; the parent is never pinned at a guessed spot.
local function ResolvePin(mapID, position)
    if CanPin(mapID) then return mapID, position end
    local vector = CreateVector2D(position.x, position.y)
    local continent, world = Planner:Call(C_Map, "GetWorldPosFromMapPos", mapID, vector)
    if not continent or not world then return end
    local current = mapID
    for _ = 1, 8 do
        local info = Planner:Call(C_Map, "GetMapInfo", current)
        local parent = info and Safe(info.parentMapID)
        if not parent or parent <= 0 or parent == current then return end
        current = parent
        if CanPin(current) then
            local resolvedMap, resolved = Planner:Call(C_Map, "GetMapPosFromWorldPos", continent, world, current)
            if resolvedMap == current and resolved then
                local x, y = Planner:Call(resolved, "GetXY", resolved)
                local projected = { x = x, y = y }
                if ValidPosition(projected) then return current, projected end
            end
        end
    end
end

function Module:SetPlannerWaypoint(mapID, position)
    if not mapID or not ValidPosition(position) then return false end
    local targetMap, target = ResolvePin(mapID, position)
    local point = targetMap and UiMapPoint.CreateFromCoordinates(targetMap, target.x, target.y)
    if not point or Planner:Call(C_Map, "SetUserWaypoint", point) == false then return false end
    Planner:Call(C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
    return true, targetMap
end

function Module:TrackPlannerQuest(questID)
    local onQuest = Planner:Call(C_QuestLog, "IsOnQuest", questID) == true
    if not onQuest and Planner:Call(C_TaskQuest, "IsActive", questID) ~= true then return false end
    if onQuest then Planner:Call(C_QuestLog, "AddQuestWatch", questID) end
    Planner:Call(C_SuperTrack, "SetSuperTrackedQuestID", questID)
    return true
end

local function QuestWaypoint(questID)
    local mapID, x, y = Planner:Call(C_QuestLog, "GetNextWaypoint", questID)
    local position = { x = x, y = y }
    if mapID and ValidPosition(position) then return mapID, position end
end

function Module:OpenPlannerDestination(r, owner)
    local d = r and r.destination
    if not d then return end
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("Planner: open this after combat.", 1, 0.7, 0.2)
        return
    end
    if d.type == "vault" then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
        WeeklyRewards_ShowUI()
    elseif d.type == "quest" then
        ShowQuestLog(); QuestMapFrame_OpenToQuestDetails(d.id)
        if not self:TrackPlannerQuest(d.id) then
            local mapID, position = QuestWaypoint(d.id)
            if mapID and self:SetPlannerWaypoint(mapID, position) then ShowUIPanel(WorldMapFrame); WorldMapFrame:SetMapID(mapID) end
        end
    elseif d.type == "map" then
        ShowUIPanel(WorldMapFrame); WorldMapFrame:SetMapID(d.id)
        if not (r.questID and self:TrackPlannerQuest(r.questID)) then
            local mapID, position = d.id, d.position
            if not position and r.questID then mapID, position = QuestWaypoint(r.questID) end
            if position then
                local pinned, pinnedMap = self:SetPlannerWaypoint(mapID, position)
                if pinned and pinnedMap ~= d.id then WorldMapFrame:SetMapID(pinnedMap) end
                if not pinned then UIErrorsFrame:AddMessage("Planner: this location cannot be tracked on the map.", 1, 0.7, 0.2) end
            end
        end
    elseif d.type == "instance" then
        EncounterJournal_OpenJournal(d.difficulty, d.id)
    elseif d.type == "journeys" then
        EJ_ContentTab_Select(EncounterJournal.JourneysTab:GetID())
        EncounterJournal.JourneysFrame:ResetView(nil, d.id)
    elseif d.type == "currency" then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetCurrencyByID(d.id)
        GameTooltip:Show()
    end
end

------------------------------------------------------------------------------
-- Tooltips and menus
------------------------------------------------------------------------------

function Module:PlannerTooltip(owner, r)
    if not r then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if r.itemID then GameTooltip:SetItemByID(r.itemID) else GameTooltip_SetTitle(GameTooltip, r.title) end
    if r.era == "legacy" then GameTooltip_AddDisabledLine(GameTooltip, "Legacy • " .. (r.expansionName or "Earlier expansion")) end
    if r.actionTitle and r.actionTitle ~= r.title then GameTooltip_AddHighlightLine(GameTooltip, r.actionTitle) end
    if r.reason then GameTooltip_AddNormalLine(GameTooltip, r.reason) end
    if r.detail and r.detail ~= r.reason then GameTooltip_AddHighlightLine(GameTooltip, r.detail) end
    if r.description then GameTooltip_AddNormalLine(GameTooltip, r.description) end
    for _, line in ipairs(r.lines or {}) do
        if line ~= r.detail then GameTooltip_AddHighlightLine(GameTooltip, line) end
    end
    for index, slot in ipairs(r.slots or {}) do
        local text = string.format("Choice %d: %d / %d", index, math.min(slot.progress, slot.threshold), slot.threshold)
        if slot.itemLevel then text = text .. " • ilvl " .. slot.itemLevel end
        GameTooltip_AddColoredLine(GameTooltip, text, slot.reached and GREEN_FONT_COLOR or DISABLED_FONT_COLOR)
        if slot.upgrade and slot.upgradeText then
            GameTooltip_AddColoredLine(GameTooltip, "   " .. slot.upgradeText .. " (ilvl " .. slot.upgrade .. ")", NORMAL_FONT_COLOR)
        end
    end
    if r.expiresAt then GameTooltip_AddNormalLine(GameTooltip, (r.expirationMeaning or "Expires") .. " in " .. TimeLeft(r.expiresAt)) end
    if r.destination then
        if InCombatLockdown() then GameTooltip_AddErrorLine(GameTooltip, "Available after combat")
        else GameTooltip_AddInstructionLine(GameTooltip, "Click: " .. r.destination.label) end
    end
    if r.kind ~= "vault" then GameTooltip_AddDisabledLine(GameTooltip, "Right-click: options") end
    GameTooltip:Show()
end

function Module:PlannerRowMenu(owner, r)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(r.title)
        root:CreateButton(r.focused and "Remove Focus" or "Focus (recommend first)", function() Planner:SetPreference("focus", r.id, not r.focused) end)
        root:CreateButton(r.pinned and "Unpin" or "Pin (always show)", function() Planner:SetPreference("pins", r.id, not r.pinned) end)
        if r.kind == "lead" and r.resetKey then
            root:CreateButton("Not offered this week", function() Planner:SetPreference("dismissedLeads", r.id, r.resetKey) end)
        end
        root:CreateButton("Move to top of section", function()
            local first = 0
            for _, value in pairs(Planner:Database().preferences.order) do first = math.min(first, value) end
            Planner:SetPreference("order", r.id, first - 1)
        end)
        root:CreateDivider()
        root:CreateButton("Hide this activity", function() Planner:SetPreference("hidden", r.id, true) end)
        if r.category then
            root:CreateButton("Hide category: " .. r.category, function() Planner:SetPreference("categories", r.category, true) end)
        end
    end)
end

local function HasCustomFilters(prefs)
    for _, value in pairs(prefs.filters) do if value and value ~= "" then return true end end
    return next(prefs.hidden) ~= nil or next(prefs.categories) ~= nil or next(prefs.order) ~= nil
end

function Module:ResetPlannerFilters()
    local prefs = Planner:Database().preferences
    for _, key in ipairs({ "filters", "hidden", "categories", "order" }) do wipe(prefs[key]) end
    self.weeklyHub.search:SetText("")
    Planner:Invalidate()
end

function Module:SetupPlannerFilter(dropdown)
    dropdown:SetupMenu(function(_, root)
        local prefs = Planner:Database().preferences
        local filters = prefs.filters
        root:CreateTitle("Show")
        for _, option in ipairs(MODES) do
            local label, mode = option[1], option[2]
            root:CreateRadio(label, function() return (filters.mode or false) == mode end,
                function() Planner:SetPreference("filters", "mode", mode) end)
        end
        root:CreateDivider()
        root:CreateCheckbox("Hide unavailable", function() return filters.hideUnavailable end,
            function() Planner:SetPreference("filters", "hideUnavailable", not filters.hideUnavailable) end)
        root:CreateCheckbox("Show currencies", function() return not filters.hideResources end,
            function() Planner:SetPreference("filters", "hideResources", not filters.hideResources) end)
        local categories, known = root:CreateButton("Categories"), {}
        for _, records in pairs(Planner.cache) do
            for _, r in ipairs(records) do if r.category and r.kind ~= "vault" then known[r.category] = true end end
        end
        for category in pairs(prefs.categories) do known[category] = true end
        local sorted = {}
        for category in pairs(known) do sorted[#sorted + 1] = category end
        table.sort(sorted)
        for _, category in ipairs(sorted) do
            categories:CreateCheckbox(category, function() return not prefs.categories[category] end,
                function() Planner:SetPreference("categories", category, not prefs.categories[category]) end)
        end
        if next(prefs.hidden) then
            local hidden = root:CreateButton("Hidden activities")
            for id in pairs(prefs.hidden) do
                local title = id
                for _, records in pairs(Planner.cache) do
                    for _, r in ipairs(records) do if r.id == id then title = r.title end end
                end
                hidden:CreateButton("Show " .. title, function() Planner:SetPreference("hidden", id, nil) end)
            end
        end
        local currencies = root:CreateButton("Pin a currency")
        for index = 1, Planner:Call(C_CurrencyInfo, "GetCurrencyListSize") or 0 do
            local info = Planner:Call(C_CurrencyInfo, "GetCurrencyListInfo", index)
            local name = info and not Safe(info.isHeader) and Safe(info.name)
            local link = name and Planner:Call(C_CurrencyInfo, "GetCurrencyListLink", index)
            local id = link and Planner:Call(C_CurrencyInfo, "GetCurrencyIDFromLink", link)
            if id then
                local key = "currency:" .. id
                currencies:CreateCheckbox(name, function() return prefs.pins[key] end,
                    function() Planner:SetPreference("pins", key, not prefs.pins[key]) end)
            end
        end
    end)
    dropdown:SetDefaultCallback(function() self:ResetPlannerFilters() end)
    dropdown:SetIsDefaultCallback(function() return not HasCustomFilters(Planner:Database().preferences) end)
end

------------------------------------------------------------------------------
-- Rings and currencies
------------------------------------------------------------------------------

local function CreateRing(parent)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(104, 96)
    card.Ring = CreateFrame("Frame", nil, card)
    card.Ring:SetSize(58, 58); card.Ring:SetPoint("TOP", 0, -2)
    card.Icon = card.Ring:CreateTexture(nil, "ARTWORK")
    card.Icon:SetSize(40, 40); card.Icon:SetPoint("CENTER")
    local mask = card.Ring:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(card.Icon); card.Icon:AddMaskTexture(mask)
    card.Border = card.Ring:CreateTexture(nil, "OVERLAY")
    card.Border:SetAtlas("ui-journeys-renown-radial-bar"); card.Border:SetAllPoints()
    card.Check = card.Ring:CreateTexture(nil, "OVERLAY", nil, 2)
    card.Check:SetAtlas("activities-icon-checkmark", true); card.Check:SetPoint("BOTTOMRIGHT", 4, -4)
    -- Blizzard's Journeys renown ring: a paused Cooldown swipe with the radial fill atlas.
    card.Swipe = CreateFrame("Cooldown", nil, card.Ring)
    card.Swipe:SetAllPoints(); card.Swipe:SetFrameLevel(card.Ring:GetFrameLevel() + 2)
    card.Swipe:SetReverse(true); card.Swipe:SetHideCountdownNumbers(true); card.Swipe:SetRotation(math.pi)
    card.Swipe:SetDrawEdge(false); card.Swipe:SetDrawBling(false)
    local fill = C_Texture.GetAtlasInfo(RING_FILL)
    if fill then
        card.Swipe:SetSwipeTexture(fill.file or fill.filename)
        card.Swipe:SetTexCoordRange({ x = fill.leftTexCoord, y = fill.topTexCoord }, { x = fill.rightTexCoord, y = fill.bottomTexCoord })
    end
    card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.Name:SetPoint("TOP", card.Ring, "BOTTOM", 0, -3); card.Name:SetWidth(104)
    card.Value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.Value:SetPoint("TOP", card.Name, "BOTTOM", 0, -2); card.Value:SetWidth(104)
    card:SetScript("OnClick", function(owner) Module:OpenPlannerDestination(owner.record, owner) end)
    card:SetScript("OnEnter", function(owner) Module:PlannerTooltip(owner, owner.record) end)
    card:SetScript("OnLeave", GameTooltip_Hide)
    return card
end

local function UpdateRing(card, r)
    card.record = r
    card.Icon:SetTexture(r.icon)
    card.Name:SetText(r.title)
    card.Value:SetText(r.detail)
    local fraction
    if r.state ~= "unknown" and r.target and r.target > 0 then fraction = r.fraction or math.min(1, r.current / r.target) end
    local complete = r.state == "complete"
    card.Check:SetShown(complete)
    card.Icon:SetDesaturated(r.state == "unknown")
    card.Swipe:SetShown(fraction ~= nil)
    if fraction then
        local color = complete and GREEN_FONT_COLOR or NORMAL_FONT_COLOR
        card.Swipe:SetSwipeColor(color:GetRGB())
        -- A fully elapsed cooldown clears itself, so a full ring stops just short.
        CooldownFrame_SetDisplayAsPercentage(card.Swipe, math.min(fraction, 0.999))
    end
    card:Show()
end

local function CreateCurrency(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(70, 18)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(16, 16); button.Icon:SetPoint("LEFT")
    button.Amount = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.Amount:SetPoint("LEFT", button.Icon, "RIGHT", 4, 0); button.Amount:SetJustifyH("LEFT")
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetCurrencyByID(owner.record.currencyID)
        for _, line in ipairs(owner.record.lines) do GameTooltip_AddHighlightLine(GameTooltip, line) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

------------------------------------------------------------------------------
-- List rows
------------------------------------------------------------------------------

local function SetupRow(button)
    button.created = true
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetAllPoints()
    button.Highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.Highlight:SetAllPoints(); button.Highlight:SetAtlas("activities-incomplete")
    button.Highlight:SetAlpha(0.3); button.Highlight:SetBlendMode("ADD")
    button.Collapse = button:CreateTexture(nil, "ARTWORK")
    button.Collapse:SetPoint("LEFT", 8, 2)
    button.Divider = button:CreateTexture(nil, "ARTWORK")
    button.Divider:SetAtlas("ui-journeys-renown-divider", true)
    button.Divider:SetPoint("BOTTOMLEFT", 4, 0); button.Divider:SetPoint("BOTTOMRIGHT", -4, 0)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Pin = button:CreateTexture(nil, "OVERLAY")
    button.Pin:SetAtlas("activities-icon-checkmark-small-yellow", true)
    button.Check = button:CreateTexture(nil, "OVERLAY")
    button.Check:SetAtlas("activities-icon-checkmark", true); button.Check:SetPoint("RIGHT", -12, 0)
    button.Name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    button.Name:SetJustifyH("LEFT"); button.Name:SetWordWrap(false)
    button.Reason = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.Reason:SetJustifyH("LEFT"); button.Reason:SetWordWrap(false)
    button.Detail = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.Detail:SetJustifyH("LEFT"); button.Detail:SetWordWrap(false)
    button.Status = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.Status:SetPoint("RIGHT", -14, 0); button.Status:SetJustifyH("RIGHT")
    button:SetScript("OnClick", function(owner, mouse)
        local data = owner.data
        if data.kind == "header" then
            if data.section then
                local prefs = Planner:Database().preferences
                prefs.collapsed[data.section] = not data.collapsed
                Planner:Invalidate()
            end
        elseif mouse == "RightButton" then Module:PlannerRowMenu(owner, data.record)
        else Module:OpenPlannerDestination(data.record, owner) end
    end)
    button:SetScript("OnEnter", function(owner) if owner.data.record then Module:PlannerTooltip(owner, owner.data.record) end end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

local function InitRow(button, data)
    if not button.created then SetupRow(button) end
    button.data = data
    local r, kind = data.record, data.kind
    local header, hero = kind == "header", kind == "hero"
    button.Background:SetShown(r ~= nil)
    button.Divider:SetShown(header)
    button.Collapse:SetShown(header and data.section ~= nil)
    button.Icon:SetShown(r ~= nil)
    button.Pin:SetShown(r ~= nil and r.pinned)
    button.Check:SetShown(r ~= nil and r.state == "complete")
    button.Reason:SetShown(r ~= nil or kind == "empty")
    button.Detail:SetShown(hero)
    button.Highlight:SetShown(r ~= nil)
    button.Name:ClearAllPoints(); button.Reason:ClearAllPoints(); button.Detail:ClearAllPoints()
    button.Name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    if header then
        button.Name:SetFontObject("GameFontHighlightLarge")
        button.Name:SetPoint("LEFT", data.section and 28 or 10, 2)
        button.Name:SetText(data.title)
        button.Collapse:SetAtlas(data.collapsed and "campaign_headericon_closed" or "campaign_headericon_open", true)
        button.Status:SetText(data.count and (data.collapsed and data.count .. " hidden" or data.count) or "")
        button.Status:SetFontObject("GameFontDisable")
        return
    end
    button.Status:SetFontObject("GameFontHighlightSmall")
    if kind == "empty" then
        button.Name:SetFontObject("GameFontHighlightMedium")
        button.Name:SetPoint("TOPLEFT", 20, -6); button.Name:SetText(data.title)
        button.Reason:SetPoint("TOPLEFT", button.Name, "BOTTOMLEFT", 0, -3); button.Reason:SetText(data.detail or "")
        button.Status:SetText("")
        return
    end
    local complete = r.state == "complete"
    button.Background:SetAtlas(hero and "activities-incomplete-active" or complete and "activities-complete" or "activities-incomplete")
    local size = hero and 40 or 30
    button.Icon:SetSize(size, size); button.Icon:ClearAllPoints(); button.Icon:SetPoint("LEFT", 14, 0)
    button.Icon:SetTexture(r.icon)
    button.Icon:SetDesaturated(complete or r.state == "missing" or r.state == "unknown")
    button.Pin:ClearAllPoints(); button.Pin:SetPoint("TOPLEFT", button.Icon, "TOPLEFT", -6, 6)
    button.Name:SetFontObject(hero and "GameFontHighlightLarge" or "GameFontHighlightMedium")
    local left = 14 + size + 10
    button.Name:SetPoint("TOPLEFT", left, hero and -9 or -6); button.Name:SetPoint("TOPRIGHT", -110, hero and -9 or -6)
    button.Reason:SetPoint("TOPLEFT", button.Name, "BOTTOMLEFT", 0, -3); button.Reason:SetPoint("TOPRIGHT", button.Name, "BOTTOMRIGHT", 0, -3)
    local title = data.recommended and r.actionTitle or r.title
    if r.era == "legacy" then title = "[Legacy] " .. title end
    button.Name:SetText(title)
    button.Name:SetTextColor((complete and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
    local reason = data.recommended and r.reason or r.detail or r.reason or ""
    if r.expiring and data.recommended then reason = "Expires soon • " .. reason end
    if r.focused then reason = "Focused • " .. reason end
    button.Reason:SetText(reason)
    button.Reason:SetFontObject(data.recommended and "GameFontNormal" or "GameFontDisableSmall")
    if hero then
        button.Detail:SetPoint("TOPLEFT", button.Reason, "BOTTOMLEFT", 0, -3); button.Detail:SetPoint("TOPRIGHT", button.Reason, "BOTTOMRIGHT", 0, -3)
        button.Detail:SetText(r.detail ~= r.reason and r.detail or "")
    end
    button.Status:SetText(complete and "" or StatusText(r))
end

------------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------------

local function Entries(view)
    local entries = {}
    local function Add(entry) entries[#entries + 1] = entry end
    Add({ kind = "header", title = "Up Next" })
    for index, r in ipairs(view.recommended) do
        Add({ kind = index == 1 and "hero" or "row", record = r, recommended = true })
    end
    if #view.recommended == 0 then Add({ kind = "empty", title = view.emptyMessage, detail = view.emptyDetail }) end
    for _, section in ipairs(view.sections) do
        Add({ kind = "header", title = section.title, section = section.key, collapsed = section.collapsed, count = #section.rows })
        if not section.collapsed then
            for _, r in ipairs(section.rows) do Add({ kind = "row", record = r }) end
        end
    end
    return entries
end

function Module:UpdatePlannerClock()
    local page = self.weeklyHub
    if not page or not page:IsShown() then return end
    local weekly, daily = Planner:ResetTime("weekly"), Planner:ResetTime("daily")
    page.Clock:SetText(CreateAtlasMarkup("activities-clock-standard", 14, 14) .. " Daily " .. TimeLeft(daily)
        .. "   " .. CreateAtlasMarkup("activities-clock-standard", 14, 14) .. " Weekly " .. TimeLeft(weekly))
    page.ScrollBox:ForEachFrame(function(button)
        local r = button.data and button.data.record
        if r and r.expiresAt and r.state ~= "complete" then button.Status:SetText(StatusText(r)) end
    end)
end

function Module:RenderPlanner(view)
    local page = self.weeklyHub
    if not page then return end
    local counts = view.counts
    page.Summary:SetText(string.format("%d ready  •  %d left this week  •  %d done", counts.ready, counts.remaining, counts.completed))
    for index, r in ipairs(view.rings) do
        page.rings[index] = page.rings[index] or CreateRing(page.Band)
        page.rings[index]:SetPoint("TOPLEFT", (index - 1) * 108, 0)
        UpdateRing(page.rings[index], r)
    end
    for index = #view.rings + 1, #page.rings do page.rings[index]:Hide() end
    local columns = 3
    for index, r in ipairs(view.resources) do
        local button = page.currencies[index] or CreateCurrency(page.Band)
        page.currencies[index] = button
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", -((index - 1) % columns) * 74, -math.floor((index - 1) / columns) * 20 - 6)
        button.record = r
        button.Icon:SetTexture(r.icon)
        button.Amount:SetText(CompactNumber(r.amount))
        button:Show()
    end
    for index = #view.resources + 1, #page.currencies do page.currencies[index]:Hide() end
    page.ScrollBox:SetDataProvider(CreateDataProvider(Entries(view)), ScrollBoxConstants.RetainScrollPosition)
    page.Filter:ValidateResetState()
    self:UpdatePlannerClock()
end

function Module:CreatePlannerPage(journal)
    local page = CreateFrame("Frame", "RefineUIAdventurePlanner", journal)
    self.weeklyHub, page.rings, page.currencies = page, {}, {}
    page:SetPoint("TOPLEFT", journal.inset, "TOPLEFT")
    page:SetPoint("BOTTOMRIGHT", journal.inset, "BOTTOMRIGHT")
    page:Hide()
    page.Border = CreateFrame("Frame", nil, page, "QuestLogBorderFrameTemplate")
    page.Border:SetAllPoints(); page.Border:SetFrameLevel(page:GetFrameLevel() + 10)
    if page.Border.TopDetail then page.Border.TopDetail:Hide() end
    page.Title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge2")
    page.Title:SetPoint("TOPLEFT", 20, -17); page.Title:SetText("Weekly Planner")
    page.Clock = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.Clock:SetPoint("LEFT", page.Title, "RIGHT", 14, -1)
    page.Summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.Summary:SetPoint("TOPLEFT", page.Title, "BOTTOMLEFT", 0, -5)
    page.Filter = CreateFrame("DropdownButton", nil, page, "WowStyle1FilterDropdownTemplate")
    page.Filter:SetPoint("TOPRIGHT", -22, -16)
    self:SetupPlannerFilter(page.Filter)
    page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
    page.search:SetSize(150, 20); page.search:SetPoint("RIGHT", page.Filter, "LEFT", -12, 0)
    page.search:SetAutoFocus(false)
    page.search:HookScript("OnTextChanged", function(box, userInput)
        if userInput then Planner:SetPreference("filters", "search", box:GetText()) end
    end)
    page.Band = CreateFrame("Frame", nil, page)
    page.Band:SetPoint("TOPLEFT", 16, -60); page.Band:SetPoint("TOPRIGHT", -22, -60); page.Band:SetHeight(100)
    page.BandDivider = page:CreateTexture(nil, "ARTWORK")
    page.BandDivider:SetAtlas("ui-journeys-renown-divider", true)
    page.BandDivider:SetPoint("TOPLEFT", page.Band, "BOTTOMLEFT", 0, -2); page.BandDivider:SetPoint("TOPRIGHT", page.Band, "BOTTOMRIGHT", 0, -2)
    page.ScrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    page.ScrollBox:SetPoint("TOPLEFT", page.Band, "BOTTOMLEFT", -6, -14)
    page.ScrollBox:SetPoint("BOTTOMRIGHT", -24, 6)
    page.ScrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    page.ScrollBar:SetPoint("TOPLEFT", page.ScrollBox, "TOPRIGHT", 6, -4)
    page.ScrollBar:SetPoint("BOTTOMLEFT", page.ScrollBox, "BOTTOMRIGHT", 6, 4)
    local view = CreateScrollBoxListLinearView(2, 8, 0, 0, 2)
    view:SetElementExtentCalculator(function(_, data) return HEIGHTS[data.kind] end)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(page.ScrollBox, page.ScrollBar, view)
    page:SetScript("OnShow", function()
        page.search:SetText(Planner:Database().preferences.filters.search or "")
        Planner:Show()
    end)
    page:SetScript("OnHide", function() Planner:Hide(); GameTooltip:Hide() end)
    return page
end

------------------------------------------------------------------------------
-- Adventure Guide tab
------------------------------------------------------------------------------

function Module:SelectWeeklyHub()
    EJ_ContentTab_Select(self.weeklyHubTab:GetID())
end

-- Planner first, then Blizzard's visible tabs in their native order.
function Module:LayoutWeeklyHubTabs()
    local journal, tab = EncounterJournal, self.weeklyHubTab
    if not tab or self.weeklyHubLayingOut then return end
    self.weeklyHubLayingOut = true
    local order = { tab }
    for _, button in ipairs(journal.Tabs) do
        if button ~= tab and button:IsShown() then order[#order + 1] = button end
    end
    journal.maxTabWidth = (journal:GetWidth() - 22 - 3 * (#order - 1)) / #order
    local x = 11
    for _, button in ipairs(order) do
        PanelTemplates_TabResize(button, 0, nil, nil, journal.maxTabWidth)
        button:ClearAllPoints()
        -- Anchor to the journal so native ID-order anchoring cannot form a cycle.
        button:SetPoint("TOPLEFT", journal, "BOTTOMLEFT", x, 2)
        x = x + button:GetWidth() + 3
    end
    self.weeklyHubLayingOut = nil
end

function Module:InstallPlanner()
    local journal = EncounterJournal
    if self.weeklyHub or not journal.Tabs or not journal.Tabs[1] then return end
    local tab = CreateFrame("Button", "RefineUIWeeklyHubTab", journal, "BottomEncounterTierTabTemplate")
    self.weeklyHubTab = tab
    -- Some client versions register template-created tabs during CreateFrame.
    local tabID
    for index, button in ipairs(journal.Tabs) do
        if button == tab then tabID = index; break end
    end
    if not tabID then tabID = #journal.Tabs + 1; journal.Tabs[tabID] = tab end
    tab:SetID(tabID); tab:SetText("Planner")
    PanelTemplates_SetNumTabs(journal, #journal.Tabs)
    -- Custom IDs stay local; never pass them to C_EncounterJournal.SetTab.
    tab:SetScript("OnClick", function() self:SelectWeeklyHub() end)
    local page = self:CreatePlannerPage(journal)
    local function Layout() self:LayoutWeeklyHubTabs() end
    hooksecurefunc("PanelTemplates_AnchorTabs", function(frame) if frame == journal then Layout() end end)
    journal:HookScript("OnSizeChanged", Layout)
    for _, button in ipairs(journal.Tabs) do
        button:HookScript("OnShow", Layout); button:HookScript("OnHide", Layout)
    end
    hooksecurefunc("EJ_ContentTab_Select", function(id)
        Layout()
        local active = id == tab:GetID()
        if active then
            -- The native selector runs no branch for a custom tab. Hiding the
            -- Suggested Content panel re-shows the instance list, so hide it after.
            EJ_HideNonInstancePanels()
            EncounterJournal_HideGreatVaultButton()
            local select = journal.instanceSelect
            select.ScrollBox:Hide(); select.ScrollBar:Hide(); select.ExpansionDropdown:Hide(); select.Title:Hide()
        end
        page:SetShown(active)
    end)
    -- Open on the Planner unless Blizzard navigated to an instance (for
    -- example while inside a dungeon) or a boss link is being followed.
    journal:HookScript("OnShow", function()
        if not journal.encounter:IsShown() then self:SelectWeeklyHub() end
    end)
    Layout()
    if journal:IsShown() and not journal.encounter:IsShown() then self:SelectWeeklyHub() end
end
