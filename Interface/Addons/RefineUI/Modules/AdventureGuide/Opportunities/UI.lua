-- The Adventure Guide tab is the engine's only UI consumer.
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideOpportunities")
local Runtime = RefineUI.Opportunities
local categoryLabels = { collectibles = "Collectibles", mount = "Mounts", pet = "Pets", toy = "Toys", appearance = "Appearances", decor = "Decor", achievements = "Achievements" }

local function Text(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
end

function Module:RequirementText(req, current)
    local kind, id, target = req[1], req[2], req[3]
    local name = Runtime.labels and Runtime.labels[kind .. ":" .. id]
    if kind == "gold" then
        return "Gold: " .. GetCoinTextureString(current or 0) .. " / " .. GetCoinTextureString(target)
    elseif kind == "currency" or kind == "reputation" or kind == "renown" then
        return (name or (kind == "currency" and "Currency" or "Reputation")) .. ": " .. tostring(current or "?") .. " / " .. target
    elseif kind == "level" then return "Level " .. target
    elseif kind == "faction" then return target == 1 and "Horde" or "Alliance"
    elseif kind == "class" then return "Class requirement"
    elseif kind == "race" then return "Race requirement"
    elseif kind == "quest" then return current == false and "Complete prerequisite quest (click to inspect)" or "Prerequisite quest completed"
    elseif kind == "achievement" then return "Prerequisite achievement completed" end
    if kind == "questReward" then return "Reward quest is incomplete" end
    if kind == "achievementReward" then return "Reward achievement is incomplete with readable criteria" end
    if kind == "capture" then return "Species is wild and obtainable" end
    return "Requirement unverified"
end

function Module:Tooltip(owner, row)
    if not row or not Runtime.engine then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.title, 1, 1, 1, 1, true)
    if row.collectionRow then
        GameTooltip:AddLine(row.collectionGroup and string.format("%d / %d appearances collected", row.collectedCount, row.totalCount)
            or row.owned == true and "Collected" or row.owned == false and "Not collected" or "Ownership unknown",
            row.owned == true and .45 or 1, row.owned == true and 1 or .75, .55)
        GameTooltip:AddLine(row.sourceLabel or "Source unknown", .75, .8, .9, true)
        if row.unavailable then GameTooltip:AddLine("Blizzard marks this collectible unavailable to this character.", 1, .55, .35, true) end
        if row.recommendation then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Recommended route: " .. row.recommendation.label, 1, .82, 0, true)
            GameTooltip:AddLine(row.recommendation.detail or "Open the recommendation for details.", .7, .8, 1, true)
        elseif row.owned == false then
            GameTooltip:AddLine("No acquisition route has enough evidence for a recommendation.", .7, .8, 1, true)
        end
        GameTooltip:AddLine(" ")
        local journal = row.collectionKind == "mount" and "Mount Journal" or row.collectionKind == "pet" and "Pet Journal"
            or row.collectionKind == "toy" and "Toy Box" or row.collectionKind == "appearance" and "Appearances"
            or row.collectionKind == "achievements" and "Achievements" or nil
        local action = journal and ("Click to open " .. journal .. " • Right-click for options")
            or row.recommendation and "Click to open the recommended route • Right-click for options" or "Right-click for options"
        GameTooltip:AddLine(InCombatLockdown() and "Navigation is available after combat." or action, .7, .85, 1, true)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(row.label, 1, 0.82, 0)
    if row.achievementID then
        GameTooltip:AddLine(row.detail, 1, 1, 1, true)
        if type(row.quantity) == "number" and type(row.required) == "number" and row.required > 0 then
            GameTooltip:AddLine(string.format("Remaining criterion progress: %s / %s", row.quantity, row.required), 1, 1, 1, true)
        end
        GameTooltip:AddLine("Blizzard reports one unfinished criterion. This is not an estimate of time or difficulty.", .7, .75, .8, true)
        GameTooltip:AddLine("Click to compare with the native achievement. Refresh rechecks the full count.", .7, .75, .8, true)
    else
        for _, detail in ipairs(Runtime.engine:GetDetails(row)) do
            local mark = detail.passed == true and "✓ " or detail.passed == false and "• " or "? "
            GameTooltip:AddLine(mark .. self:RequirementText(detail.requirement, detail.current),
                detail.passed and .65 or 1, detail.passed and .9 or .75, .65, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(row.detail or "Vendor purchase • Costs apply to this reward individually.", .7, .75, .8, true)
        if row.tier ~= 1 and (not row.acquisition or row.acquisition == "vendor") then
            GameTooltip:AddLine("Known requirements checked. Confirm price and availability at the vendor.", .7, .75, .8, true)
        end
        local source = Runtime.engine.data.sources[row.sourceIndex]
        if source[4] ~= 0 or source[5] ~= 0 then GameTooltip:AddLine(string.format("Location: %.1f, %.1f", source[4] * 100, source[5] * 100), .7, .75, .8) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(InCombatLockdown() and "Navigation is available after combat." or "Click to open • Right-click for options", .7, .85, 1)
    GameTooltip:Show()
end

function Module:Open(row)
    if not row or InCombatLockdown() then return end
    if row.collectionKind == "decor" then
        if row.recommendation then self:Open(row.recommendation) end
        return
    end
    if row.collectionKind == "mount" or row.collectionKind == "pet" or row.collectionKind == "toy" or row.collectionKind == "appearance" then
        if CollectionsJournal_LoadUI then CollectionsJournal_LoadUI() elseif C_AddOns then C_AddOns.LoadAddOn("Blizzard_Collections") end
        if CollectionsJournal then
            ShowUIPanel(CollectionsJournal)
            local tab = row.collectionKind == "mount" and 1 or row.collectionKind == "pet" and 2
                or row.collectionKind == "toy" and 3 or 5
            if CollectionsJournal_SetTab then CollectionsJournal_SetTab(CollectionsJournal, tab) end
        end
        return
    end
    if row.nextQuestID and QuestMapFrame_OpenToQuestDetails then QuestMapFrame_OpenToQuestDetails(row.nextQuestID);return end
    if row.achievementID or row.rewardAchievementID then
        C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        if AchievementFrame_LoadUI then AchievementFrame_LoadUI() end
        if AchievementFrame_SelectAchievement then
            ShowUIPanel(AchievementFrame)
            AchievementFrame_SelectAchievement(row.achievementID or row.rewardAchievementID)
        end
    elseif row.sourceIndex and Runtime.engine then
        local source = Runtime.engine.data.sources[row.sourceIndex]
        if source[1] == "questReward" and QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(source[2]); return
        end
        if not source[3] or source[3] <= 0 then return end
        ShowUIPanel(WorldMapFrame); WorldMapFrame:SetMapID(source[3])
        -- This is explicit navigation, never an automatically injected marker.
        if (source[4] ~= 0 or source[5] ~= 0) and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(source[3]) and UiMapPoint then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(source[3], source[4], source[5]))
        end
    end
end

function Module:Menu(owner, row)
    if not row or not MenuUtil then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local prefs = Runtime:Preferences()
        root:CreateTitle(row.title)
        local focusID = row.recommendation and row.recommendation.id or row.id
        if not row.collectionRow or row.recommendation then
            root:CreateButton(prefs.focus[focusID] and "Remove focus" or "Focus this opportunity", function()
                prefs.focus[focusID] = not prefs.focus[focusID] or nil; self:Render()
            end)
        end
        root:CreateButton("Hide this opportunity", function()
            prefs.hidden[row.id] = true; self:Render()
        end)
    end)
end

function Module:UpdateStatus()
    local page = self.page
    if not page or not Runtime.visible then return end
    local category = self.category or "collectibles"
    if self.view == "collection" then
        local kind = self.category or "mount"
        local state = Runtime.GetCollectionStatus and Runtime:GetCollectionStatus(kind)
        local progress = Runtime.collectionProgress
        local label = categoryLabels[kind] or "Collection"
        page.status:SetText(progress and progress.kind == kind and string.format("Reading %s: %d / %d", label, progress.checked, progress.total)
            or state and state.status == "ready" and (kind == "mount" and "Verified against Blizzard's Mount Journal"
                or kind == "appearance" and "Verified against Blizzard's appearance category totals"
                or kind == "achievements" and "Verified against Blizzard's achievement catalog"
                or "ATT identities validated against Blizzard collection APIs")
            or state and state.status == "unavailable" and (state.error or label .. " unavailable")
            or "Preparing " .. label .. "…")
        return
    end
    local progress = Runtime.scanProgress
    local checking = progress and string.format("Checking achievements: %d / %d • Previous results remain visible", progress.checked, progress.total)
        or "Preparing achievement scan…"
    page.status:SetText(Runtime.error or (InCombatLockdown() and "Paused during combat")
        or ((Runtime.discoveryRequested or Runtime.discovering) and checking)
        or Runtime.discoveryUnavailable and "Achievement progress unavailable • Try Refresh"
        or Runtime.achievementDirty and "Progress changed • Refresh to verify the achievement snapshot"
        or category == "achievements" and "Verified snapshot • Ranked by criteria completion, not estimated effort • Click to inspect"
        or "Known requirements checked • Confirm remote vendor availability")
end

local COLLECTION_ICON = 40
local COLLECTION_GAP = 6
local COLLECTION_STEP = COLLECTION_ICON + COLLECTION_GAP
local COLLECTION_HEADER = 22
local COLLECTION_GROUP_GAP = 10

function Module:HideCollectionGrid()
    local page = self.page
    for _, cell in ipairs(page.collectionCells or {}) do cell.record = nil; cell:Hide() end
    for _, header in ipairs(page.collectionHeaders or {}) do header:Hide() end
    self.collectionLayout = nil
end

function Module:RenderCollectionIcons()
    local page, layout = self.page, self.collectionLayout
    if not page or self.view ~= "collection" or not layout then return end
    for _, cell in ipairs(page.collectionCells) do cell.record = nil; cell:Hide() end
    local scrollTop = page.scroll.GetVerticalScroll and page.scroll:GetVerticalScroll() or 0
    if type(scrollTop) ~= "number" then scrollTop = 0 end
    local viewport = page.scroll.GetHeight and page.scroll:GetHeight() or 400
    if type(viewport) ~= "number" or viewport <= 0 then viewport = 400 end
    local visibleTop, visibleBottom = math.max(0, scrollTop - COLLECTION_STEP), scrollTop + viewport + COLLECTION_STEP
    local used = 0
    for _, group in ipairs(layout.groups) do
        local groupBottom = group.gridTop + group.rows * COLLECTION_STEP
        if groupBottom >= visibleTop and group.gridTop <= visibleBottom then
            local firstRow = math.max(0, math.floor((visibleTop - group.gridTop) / COLLECTION_STEP))
            local lastRow = math.min(group.rows - 1, math.floor((visibleBottom - group.gridTop) / COLLECTION_STEP))
            for gridRow = firstRow, lastRow do
                for column = 0, layout.columns - 1 do
                    local index = gridRow * layout.columns + column + 1
                    local source = group.items[index]
                    if source then
                        used = used + 1
                        local cell = page.collectionCells[used]
                        if not cell then break end
                        local row = Runtime:DecorateCollectionRow(source)
                        cell.record = row
                        cell:ClearAllPoints()
                        cell:SetPoint("TOPLEFT", page.content, "TOPLEFT", 2 + column * COLLECTION_STEP,
                            -(group.gridTop + gridRow * COLLECTION_STEP))
                        cell.icon:SetTexture(row.icon or 134400)
                        cell.icon:SetDesaturated(row.owned ~= true)
                        cell.icon:SetAlpha(row.owned == true and 1 or row.owned == false and .72 or .82)
                        if row.recommendation then cell:SetBackdropBorderColor(1, .72, .05, 1)
                        elseif row.owned == true then cell:SetBackdropBorderColor(.25, .72, .3, .9)
                        elseif row.owned == nil then cell:SetBackdropBorderColor(.8, .65, .25, .9)
                        else cell:SetBackdropBorderColor(.3, .32, .38, .85) end
                        cell.marker:SetShown(row.recommendation ~= nil)
                        cell.progress:SetText(row.collectionGroup and string.format("%d/%d", row.collectedCount, row.totalCount) or "")
                        cell:Show()
                    end
                end
            end
        end
    end
end

function Module:LayoutCollectionGrid(groups)
    local page = self.page
    local width = page.content.GetWidth and page.content:GetWidth() or 690
    if type(width) ~= "number" or width < 300 then width = 690 end
    local columns = math.max(6, math.floor((width - 4) / COLLECTION_STEP))
    local y = 0
    for index, group in ipairs(groups) do
        local header = page.collectionHeaders[index]
        if not header then
            header = CreateFrame("Frame", nil, page.content)
            page.collectionHeaders[index] = header
            header.text = Text(header, "GameFontNormal")
            header.text:SetPoint("LEFT", 2, 0)
            header.line = header:CreateTexture(nil, "ARTWORK")
            header.line:SetHeight(1); header.line:SetPoint("LEFT", header.text, "RIGHT", 8, 0)
            header.line:SetPoint("RIGHT", header, "RIGHT", -2, 0); header.line:SetColorTexture(1, .82, 0, .35)
        end
        header:ClearAllPoints(); header:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -y)
        header:SetPoint("TOPRIGHT", page.content, "TOPRIGHT", 0, -y); header:SetHeight(COLLECTION_HEADER)
        header.text:SetText(string.format("%s (%d)", group.label, #group.items)); header:Show()
        group.gridTop = y + COLLECTION_HEADER
        group.rows = math.ceil(#group.items / columns)
        y = group.gridTop + group.rows * COLLECTION_STEP + COLLECTION_GROUP_GAP
    end
    for index = #groups + 1, #page.collectionHeaders do page.collectionHeaders[index]:Hide() end
    self.collectionLayout = { groups = groups, columns = columns, height = math.max(1, y) }
    page.content:SetHeight(self.collectionLayout.height)
    self:RenderCollectionIcons()
end

function Module:Render()
    local page = self.page
    if not page or not Runtime.visible then return end
    local collectionView = self.view == "collection"
    local limit = self.expanded and 20 or 3
    local category = self.category or "collectibles"
    local rows, groups, total, counts, collectionStatus, coverage
    if collectionView then
        if category ~= "mount" and category ~= "pet" and category ~= "toy" and category ~= "appearance"
            and category ~= "decor" and category ~= "achievements" then category = "mount"; self.category = category end
        if Runtime.RequestCollection then Runtime:RequestCollection(category) end
        groups, total, counts, collectionStatus = Runtime:GetCollectionView(category, self.collectionFilter or "missing")
        rows = {}
    else
        rows, total, counts = Runtime:GetPage(self.offset or 0, limit, category)
    end
    if not collectionView and #rows == 0 and (self.offset or 0) > 0 then
        self.offset = 0
        rows, total, counts = Runtime:GetPage(0, limit, category)
    end
    self:UpdateStatus()
    page.recommended:SetEnabled(collectionView); page.collection:SetEnabled(not collectionView)
    for _, button in pairs(page.collectionFilters) do button:SetShown(collectionView) end
    page.collectionFilters.all:SetEnabled((self.collectionFilter or "missing") ~= "all")
    page.collectionFilters.missing:SetEnabled((self.collectionFilter or "missing") ~= "missing")
    page.collectionFilters.owned:SetEnabled((self.collectionFilter or "missing") ~= "owned")
    local collectionOrder = {mount=1,pet=2,toy=3,appearance=4,decor=5,achievements=6}
    for key, button in pairs(page.categories or {}) do
        local collectionIndex = collectionOrder[key]
        button:SetShown(not collectionView or collectionIndex ~= nil)
        button:ClearAllPoints()
        if collectionView and collectionIndex then
            button:SetSize(110,24); button:SetPoint("TOPLEFT",24+(collectionIndex-1)*115,-70)
        else
            local index = button.categoryIndex
            button:SetSize(150,24); button:SetPoint("TOPLEFT",24+((index-1)%4)*155,-70-math.floor((index-1)/4)*30)
        end
    end
    if collectionView then
        page.coverageInfo = nil
        local coverageText = collectionStatus == "ready" and counts and string.format(
            "Owned: %d • Missing: %d • Unknown: %d • Unavailable here: %d",
            counts.owned or 0, counts.missing or 0, counts.unknown or 0, counts.unavailable or 0) or ""
        if counts and (counts.rejected or 0) > 0 then coverageText = coverageText .. string.format(" • Unrecognized candidates: %d", counts.rejected) end
        page.coverage:SetText(coverageText)
        local label = categoryLabels[category] or "Collection"
        page.summary:SetText(collectionStatus == "ready" and counts and string.format("%s collection: %d / %d collected • %d %s icons",
            label, counts.owned or 0, counts.total or 0, total, self.collectionFilter or "missing") or "Reading collection…")
        for _, key in ipairs({"mount","pet","toy","appearance","decor","achievements"}) do
            local state = Runtime.GetCollectionStatus and Runtime:GetCollectionStatus(key)
            local count = state and state.counts and state.counts.total or 0
            page.categories[key]:SetText(categoryLabels[key] .. " (" .. count .. ")")
            page.categories[key]:SetEnabled(key ~= category)
        end
    else
    coverage = category ~= "achievements" and Runtime.engine and Runtime.engine.GetCoverage and Runtime.engine:GetCoverage(category)
    page.coverage:SetText(coverage and string.format("Evaluable: %d • Owned: %d • Blocked: %d • Unknown: %d • Pending: %d • Hover for coverage",
        coverage.supported, coverage.owned, coverage.blocked, coverage.unknown, coverage.pending)
        or "Blizzard achievement criteria • One unfinished criterion does not establish low effort")
    page.coverageInfo = coverage
    page.summary:SetText(category == "achievements"
        and string.format("%d matches with one criterion left • Showing %d • Not necessarily quick wins", total, #rows)
        or string.format("%d matching collectibles • Showing %d • Purchases, rewards and source leads", total, #rows))
    for key, button in pairs(page.categories or {}) do
        button:SetText(categoryLabels[key] .. " (" .. (counts[key] or 0) .. ")")
        button:SetEnabled(key ~= category)
    end
    end
    if collectionView then
        for _, button in ipairs(page.rows) do button.record = nil; button.signature = nil; button:Hide() end
        if collectionStatus == "ready" then self:LayoutCollectionGrid(groups) else self:HideCollectionGrid(); page.content:SetHeight(1) end
    else
    self:HideCollectionGrid()
    for i = 1, 20 do
        local button, row = page.rows[i], rows[i]
        if row then
            button.record = row
            local detail = row.detail or row.label
            if row.acquisition and row.acquisition ~= "vendor" then detail = row.label .. " • " .. (row.detail or "") end
            if row.gaps and #row.gaps > 0 then
                detail = row.label .. " • " .. self:RequirementText(row.gaps[1].requirement,row.gaps[1].current)
                if #row.gaps > 1 then detail=detail.." • +"..(#row.gaps-1).." more (hover)" end
            end
            if not row.gaps and row.deficit and row.blocker then detail = row.label .. " • " .. self:RequirementText(row.blocker, row.blocker[3] - row.deficit) end
            if row.mapID and row.mapID == Runtime.mapID then detail = detail .. " • In this zone" end
            if row.category then detail = (categoryLabels[row.category] or row.category) .. " • " .. detail end
            local signature = row.id .. "\n" .. row.title .. "\n" .. detail .. "\n" .. tostring(row.icon)
            if button.signature ~= signature then
                button.signature = signature
                button.icon:SetTexture(row.icon or 134400); button.title:SetText(row.title)
                button.detail:SetText(detail); button:Show()
            end
        elseif button.record then button.record = nil; button.signature = nil; button:Hide() end
    end
    page.content:SetHeight(math.max(1, #rows * 64))
    end
    page.empty:SetShown(collectionView and total == 0 or not collectionView and #rows == 0)
    page.empty:SetText(collectionView and (collectionStatus == "unavailable" and "This collection catalog is unavailable. Try Refresh after entering the world."
            or collectionStatus ~= "ready" and "Reading your collection…"
            or "No collectibles match this ownership filter and search.") or Runtime.worker and "Checking your progress…"
        or category == "achievements" and "No matching achievements with one criterion left.\nCheck search and hidden entries."
        or coverage and coverage.supported == 0 and "No acquisition routes can be evaluated for this category yet.\nCatalog records are retained; this is a coverage gap."
        or coverage and coverage.unknown > 0 and "Some ownership or requirements could not be verified.\nUnknown entries are excluded from recommendations."
        or "No matches among supported acquisition routes.\nCheck coverage, search and hidden entries; this is not the entire collection.")
    page.more:SetShown(not collectionView)
    page.more:SetText(self.expanded and "Show top 3" or ("Browse matches (" .. total .. ")"))
    page.previous:SetShown(not collectionView and self.expanded == true); page.next:SetShown(not collectionView and self.expanded == true)
    page.previous:SetEnabled((self.offset or 0) > 0)
    page.next:SetEnabled((self.offset or 0) + limit < total)
end

function Module:CreatePage(journal)
    local page = CreateFrame("Frame", "RefineUIOpportunitiesPage", journal)
    self.page = page
    page:SetPoint("TOPLEFT", 8, -32); page:SetPoint("BOTTOMRIGHT", -8, 6); page:Hide()
    local bg = page:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.035, .045, .06, 1)
    page.title = Text(page, "GameFontNormalLarge"); page.title:SetPoint("TOPLEFT", 24, -16); page.title:SetText("Opportunities")
    page.subtitle = Text(page); page.subtitle:SetPoint("TOPLEFT", 24, -45); page.subtitle:SetText("Collectible opportunities and achievement progress")
    page.recommended = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.recommended:SetSize(110, 24); page.recommended:SetPoint("TOPLEFT", 160, -12); page.recommended:SetText("Recommended")
    page.collection = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.collection:SetSize(95, 24); page.collection:SetPoint("TOPLEFT", 275, -12); page.collection:SetText("Collection")
    local function SetView(view)
        self.view, self.offset, self.expanded = view, 0, false
        self.category = view == "collection" and "mount" or (self.recommendationCategory or "collectibles")
        local prefs = Runtime:Preferences()
        self.updatingSearch = true; page.search:SetText(view == "collection" and (prefs.collectionSearch or "") or (prefs.search or "")); self.updatingSearch = nil
        page.scroll:SetVerticalScroll(0); self:Render()
    end
    page.recommended:SetScript("OnClick", function() SetView("recommended") end)
    page.collection:SetScript("OnClick", function() SetView("collection") end)
    page.summary = Text(page, "GameFontHighlightSmall"); page.summary:SetPoint("TOPLEFT", 24, -135)
    page.coverage = Text(page, "GameFontDisableSmall"); page.coverage:SetPoint("TOPLEFT", 24, -151)
    page.coverageHover = CreateFrame("Frame",nil,page)
    page.coverageHover:SetPoint("TOPLEFT",24,-149);page.coverageHover:SetPoint("TOPRIGHT",-24,-149);page.coverageHover:SetHeight(20)
    page.coverageHover:EnableMouse(true)
    page.coverageHover:SetScript("OnEnter",function(owner)
        local c=page.coverageInfo;if not c then return end
        GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
        GameTooltip:SetText("Recommendation coverage",1,1,1,1,true)
        GameTooltip:AddLine(string.format("ATT catalog: %d • Evaluable records: %d",c.catalog,c.supported),1,1,1,true)
        GameTooltip:AddLine(string.format("Matches before search/hiding: %d • Owned: %d • Blocked: %d • Unknown: %d • Pending: %d",
            c.match,c.owned,c.blocked,c.unknown,c.pending),1,1,1,true)
        GameTooltip:AddLine("Blocked: a checked requirement failed or the reward quest is completed. Unknown: ownership or requirements could not be verified.",.7,.8,1,true)
        GameTooltip:AddLine("Catalog records outside evaluable coverage are not checked. Historical and never-implemented records are included in catalog totals.",.7,.8,1,true)
        GameTooltip:Show()
    end)
    page.coverageHover:SetScript("OnLeave",function() GameTooltip:Hide() end)
    page.categories = {}
    for index, entry in ipairs({{"collectibles","Collectibles"},{"mount","Mounts"},{"pet","Pets"},{"toy","Toys"},
        {"appearance","Appearances"},{"decor","Decor"},{"achievements","Achievements"}}) do
        local key = entry[1]
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        page.categories[key] = button
        button.categoryIndex = index
        button:SetSize(150, 24); button:SetPoint("TOPLEFT", 24 + ((index-1)%4)*155, -70 - math.floor((index-1)/4)*30); button:SetText(entry[2])
        button:SetScript("OnClick", function()
            self.category = key
            if self.view ~= "collection" then self.recommendationCategory = key end
            self.expanded = false; self.offset = 0
            page.scroll:SetVerticalScroll(0); self:Render()
        end)
    end
    page.collectionFilters = {}
    for index, entry in ipairs({{"all","All"},{"missing","Missing"},{"owned","Owned"}}) do
        local key = entry[1]
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        page.collectionFilters[key] = button
        button:SetSize(95, 24); button:SetPoint("TOPLEFT", 24 + (index-1)*100, -100); button:SetText(entry[2]); button:Hide()
        button:SetScript("OnClick", function()
            self.collectionFilter, self.offset = key, 0; Runtime:Preferences().collectionFilter = key
            page.scroll:SetVerticalScroll(0); self:Render()
        end)
    end
    page.status = Text(page, "GameFontDisableSmall"); page.status:SetPoint("BOTTOMLEFT", 24, 13)
    page.status:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 13); page.status:SetJustifyH("LEFT")
    local function Button(label, width, x, callback)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(width, 24); b:SetPoint("TOPRIGHT", x, -12); b:SetText(label); b:SetScript("OnClick", callback)
        return b
    end
    Button("Refresh", 75, -20, function() Runtime:Refresh() end)
    Button("Restore hidden", 110, -100, function() Runtime:Preferences().hidden = {}; self:Render() end)
    Button("Diagnose", 85, -215, function() self:ShowDiagnosticReport() end)
    page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
    page.search:SetSize(170, 20); page.search:SetPoint("TOPRIGHT", -22, -45); page.search:SetAutoFocus(false)
    page.search:HookScript("OnTextChanged", function(box)
        if self.updatingSearch then return end
        if self.view == "collection" then Runtime:Preferences().collectionSearch = box:GetText()
        else Runtime:Preferences().search = box:GetText() end
        self.offset = 0; page.scroll:SetVerticalScroll(0); self:Render()
    end)
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 24, -175); page.scroll:SetPoint("BOTTOMRIGHT", -40, 65)
    page.content = CreateFrame("Frame", nil, page.scroll); page.content:SetSize(690, 1); page.scroll:SetScrollChild(page.content)
    page.scroll:SetScript("OnSizeChanged", function(_, width)
        page.content:SetWidth(width)
        if self.view == "collection" and self.collectionLayout then self:LayoutCollectionGrid(self.collectionLayout.groups) end
    end)
    page.scroll:HookScript("OnVerticalScroll", function() self:RenderCollectionIcons() end)
    page.rows = {}
    for i = 1, 20 do
        local row = CreateFrame("Button", nil, page.content)
        page.rows[i] = row
        row:SetPoint("TOPLEFT", 0, -(i-1)*64); row:SetPoint("TOPRIGHT", page.content, "TOPRIGHT", 0, -(i-1)*64); row:SetHeight(60)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:Hide()
        row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(36,36); row.icon:SetPoint("LEFT",8,0)
        row.title = Text(row); row.title:SetPoint("TOPLEFT",54,-10); row.title:SetPoint("TOPRIGHT",-12,-10); row.title:SetJustifyH("LEFT")
        row.detail = Text(row,"GameFontHighlightSmall"); row.detail:SetPoint("TOPLEFT",54,-33); row.detail:SetPoint("TOPRIGHT",-12,-33); row.detail:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(owner, button)
            if button == "RightButton" then self:Menu(owner, owner.record) else self:Open(owner.record) end
        end)
        row:SetScript("OnEnter", function(owner) self:Tooltip(owner, owner.record) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    page.collectionHeaders = {}
    page.collectionCells = {}
    -- Fixed pool: enough for the Adventure Guide viewport plus one overscan row.
    -- Collection size only changes scroll-child height; it never creates one frame per collectible.
    for i = 1, 180 do
        local cell = CreateFrame("Button", nil, page.content, "BackdropTemplate")
        page.collectionCells[i] = cell
        cell:SetSize(COLLECTION_ICON, COLLECTION_ICON)
        cell:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
        cell:SetBackdropColor(.035, .04, .05, .9); cell:Hide(); cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.icon = cell:CreateTexture(nil, "ARTWORK"); cell.icon:SetPoint("TOPLEFT", 2, -2); cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        cell.marker = cell:CreateTexture(nil, "OVERLAY"); cell.marker:SetSize(8, 8); cell.marker:SetPoint("TOPRIGHT", -1, -1)
        cell.marker:SetColorTexture(1, .72, .05, 1); cell.marker:Hide()
        cell.progress = Text(cell, "GameFontNormalSmall"); cell.progress:SetPoint("BOTTOM", 0, 2)
        cell.progress:SetTextColor(1, 1, 1, 1)
        cell:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
        cell:SetScript("OnClick", function(owner, button)
            if button == "RightButton" then self:Menu(owner, owner.record) else self:Open(owner.record) end
        end)
        cell:SetScript("OnEnter", function(owner) self:Tooltip(owner, owner.record) end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    page.empty = Text(page); page.empty:SetPoint("TOP",0,-195); page.empty:SetWidth(550)
    page.more = CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); page.more:SetSize(195,24); page.more:SetPoint("BOTTOMLEFT",24,35)
    page.more:SetScript("OnClick",function() self.expanded = not self.expanded; self.offset = 0; page.scroll:SetVerticalScroll(0); self:Render() end)
    page.previous = CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); page.previous:SetSize(90,24); page.previous:SetPoint("BOTTOMRIGHT",-122,35); page.previous:SetText("Previous")
    page.next = CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); page.next:SetSize(90,24); page.next:SetPoint("BOTTOMRIGHT",-24,35); page.next:SetText("Next")
    page.previous:SetScript("OnClick",function() self.offset = math.max(0,(self.offset or 0)-20); page.scroll:SetVerticalScroll(0); self:Render() end)
    page.next:SetScript("OnClick",function() self.offset = (self.offset or 0)+20; page.scroll:SetVerticalScroll(0); self:Render() end)
    page:SetScript("OnShow", function()
        page.content:SetWidth(page.scroll:GetWidth())
        local prefs = Runtime:Preferences()
        self.view = self.view or "recommended"; self.collectionFilter = self.collectionFilter or prefs.collectionFilter or "missing"
        self.updatingSearch = true; page.search:SetText(self.view == "collection" and (prefs.collectionSearch or "") or (prefs.search or "")); self.updatingSearch = nil
        Runtime:SetVisible(true)
    end)
    page:SetScript("OnHide", function() Runtime:SetVisible(false); GameTooltip:Hide() end)
    return page
end

function Module:LayoutTabs()
    local journal = EncounterJournal
    if not self.tab or self.layingOut then return end
    self.layingOut = true
    local planner = RefineUI:GetModule("AdventureGuidePlanner")
    if planner and planner.weeklyHubTab then
        planner:LayoutWeeklyHubTabs()
    else
        journal.maxTabWidth = (journal:GetWidth() - 22 - 3 * (#journal.Tabs - 1)) / #journal.Tabs
        local x = 11
        for _, tab in ipairs(journal.Tabs) do
            PanelTemplates_TabResize(tab, 0, nil, nil, journal.maxTabWidth)
            tab:ClearAllPoints(); tab:SetPoint("TOPLEFT", journal, "BOTTOMLEFT", x, 2)
            x = x + tab:GetWidth() + 3
        end
    end
    self.layingOut = nil
end

function Module:Install()
    local journal = EncounterJournal
    if self.tab or not journal or not journal.Tabs or not journal.Tabs[1] then return end
    local tab = CreateFrame("Button", "RefineUIOpportunitiesTab", journal, "BottomEncounterTierTabTemplate")
    self.tab = tab
    local id
    for index, button in ipairs(journal.Tabs) do if button == tab then id = index; break end end
    if not id then id = #journal.Tabs + 1; journal.Tabs[id] = tab end
    tab:SetID(id); tab:SetText("Opportunities"); PanelTemplates_SetNumTabs(journal, #journal.Tabs)
    local page = self:CreatePage(journal)
    tab:SetScript("OnClick", function() EJ_ContentTab_Select(tab:GetID()) end)
    hooksecurefunc("EJ_ContentTab_Select", function(selected)
        local active = selected == tab:GetID()
        if active then
            EJ_HideNonInstancePanels()
            journal.instanceSelect:Hide(); journal.encounter:Hide(); journal.navBar:Hide(); journal.searchBox:Hide()
            if EncounterJournal_HideGreatVaultButton then EncounterJournal_HideGreatVaultButton() end
            journal:SetTitle(ADVENTURE_JOURNAL)
        end
        page:SetShown(active); self:LayoutTabs()
    end)
    hooksecurefunc("PanelTemplates_AnchorTabs", function(frame) if frame == journal then self:LayoutTabs() end end)
    journal:HookScript("OnSizeChanged", function() self:LayoutTabs() end)
    self:LayoutTabs()
end
