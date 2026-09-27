local _, RefineUI = ...
local Window = RefineUI:GetModule("AchievementWindow")
local UNSPECIFIED = -1
local ExpansionData = RefineUI.AchievementExpansionData
local DecorData = RefineUI.AchievementDecorData

function Window:GetAlmostExpansion(id)
    return ExpansionData[id] or UNSPECIFIED
end

function Window:GetAlmostExpansionName(expansion)
    return _G["EXPANSION_NAME" .. expansion] or "Unspecified"
end

function Window:GetAlmostExpansionLogo(expansion)
    self.almostExpansionLogos = self.almostExpansionLogos or {}
    if self.almostExpansionLogos[expansion] == nil then
        local info = expansion >= 0 and GetExpansionDisplayInfo and GetExpansionDisplayInfo(expansion)
        self.almostExpansionLogos[expansion] = info and info.logo and info.logo > 0 and info.logo or false
    end
    return self.almostExpansionLogos[expansion]
end

function Window:GetAlmostReward(id, text)
    local item = C_AchievementInfo and C_AchievementInfo.GetRewardItemID
        and C_AchievementInfo.GetRewardItemID(id)
    if item == 0 then item = nil end
    return item, item ~= nil or DecorData[id] ~= nil
        or (type(text) == "string" and text:find("%S") ~= nil)
end

function Window:GetAlmostDecorRewards(id, itemID)
    local entries = {}
    local decorType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor
    if not C_HousingCatalog or not decorType then return entries end
    local ids = DecorData[id]
    if ids and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        for _, decorID in ipairs(ids) do
            local entry = C_HousingCatalog.GetCatalogEntryInfoByRecordID(decorType, decorID, false)
            if entry then entries[#entries + 1] = entry end
        end
    end
    if #entries == 0 and itemID and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local entry = C_HousingCatalog.GetCatalogEntryInfoByItem(itemID, false)
        if entry and entry.entryID and entry.entryID.entryType == decorType then entries[1] = entry end
    end
    return entries
end

function Window:ShowAlmostRewardTooltip(owner, row)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local entries = self:GetAlmostDecorRewards(row.id, row.rewardItem)
    if #entries > 0 then
        for index, entry in ipairs(entries) do
            if index == 1 then GameTooltip:SetText(entry.name or "Housing Decor")
            else GameTooltip:AddLine(" "); GameTooltip:AddLine(entry.name or "Housing Decor", 1, 0.82, 0) end
            GameTooltip:AddLine(HOUSING_DECOR or "Housing Decor", 0.2, 1, 0.2)
            if entry.sourceText and entry.sourceText ~= "" then GameTooltip:AddLine(entry.sourceText, 1, 1, 1, true) end
        end
    elseif row.rewardItem then GameTooltip:SetItemByID(row.rewardItem)
    else
        GameTooltip:SetText(REWARD or "Reward")
        GameTooltip:AddLine(row.reward or "", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Keep progress independent of the native Completed/Incomplete filter. This
-- view always uses account completion and the progress reported by Blizzard.
function Window:InvalidateAlmostCompleted(event, achievementID)
    self:InvalidateAlmostSavedCache(event, achievementID)
    self.almostDirty = true
    if event == "RECEIVED_ACHIEVEMENT_LIST" or event == "ACHIEVEMENT_EARNED" then
        -- A newly unlocked chain step can change category membership.
        self.almostCatalogDirty = true
    end
    if event == "ACHIEVEMENT_EARNED" and achievementID then
        self.almostEarned = self.almostEarned or {}
        self.almostEarned[achievementID] = true
        self:RenderAlmostCompleted()
    end
    self:QueueAlmostRefresh()
end

function Window:QueueAlmostRefresh()
    if not self.almostPanel or not self.almostPanel:IsShown() or self.almostRefreshQueued then return end
    self.almostRefreshQueued = true
    local delay = math.max(0.3, (self.almostRefreshAt or 0) - GetTime())
    C_Timer.After(delay, function()
        self.almostRefreshQueued = nil
        if self.almostPanel:IsShown() then self:ScanAlmostCompleted() end
    end)
end

function Window:PauseAlmostCompleted()
    if self.almostTicker then self.almostTicker:Cancel(); self.almostTicker = nil end
end

function Window:ScanAlmostCompleted()
    self:RestoreAlmostCache()
    if self.almostTicker then return end
    -- Keep the cursor and partial results across panel closes.
    if self.almostStep then
        self.almostTicker = C_Timer.NewTicker(0.02, self.almostStep)
        return
    end
    if self.almostRows and not self.almostDirty then self:RenderAlmostCompleted(); return end
    if self.almostRows and GetTime() < (self.almostRefreshAt or 0) then
        self:RenderAlmostCompleted()
        self:QueueAlmostRefresh()
        return
    end
    self.almostDirty = false
    self.almostRefreshAt = GetTime() + 30
    if self.almostRows then self:RenderAlmostCompleted()
    else self.almostPanel.status:SetText("Finding almost completed achievements...") end
    local cached = not self.almostCatalogDirty and self.almostCatalog
    self.almostCatalogDirty = false
    local categories, rows, seen, catalog = cached and {} or GetCategoryList(), {}, {}, {}
    local tree = RefineUI.InstanceAchievements
    local categoryIndex, index, count, pending = 1, 1
    -- Criteria count against the budget, so large metas cannot stall a frame.
    self.almostStep = function(ticker)
        for _ = 1, 40 do
            if pending then
                if pending.cursor <= pending.count then
                    local _, _, done, quantity, required = GetAchievementCriteriaInfo(pending.id, pending.cursor)
                    local progress = done and 1 or 0
                    if not done and type(quantity) == "number" and type(required) == "number" and required > 0 then
                        progress = math.max(0, math.min(1, quantity / required))
                    end
                    pending.progress = pending.progress + progress
                    pending.cursor = pending.cursor + 1
                else
                    pending.percent = math.floor(pending.progress / pending.count * 100000000 + 0.5) / 1000000
                    pending.cursor, pending.count, pending.progress = nil, nil, nil
                    if pending.percent > 0 and not (self.almostEarned and self.almostEarned[pending.id]) then
                        rows[#rows + 1] = pending
                    end
                    pending = nil
                end
            else
                local category = cached and cached[index] and cached[index].category or categories[categoryIndex]
                if not category then
                    ticker:Cancel()
                    self.almostTicker = nil
                    self.almostStep = nil
                    self.almostCatalog = catalog
                    table.sort(rows, function(a, b)
                        if a.percent ~= b.percent then return a.percent > b.percent end
                        if a.name ~= b.name then return a.name < b.name end
                        return a.id < b.id
                    end)
                    self.almostRows = rows
                    self:SaveAlmostCache()
                    self:RenderAlmostCompleted()
                    -- Events arriving mid-pass are coalesced, not recursive scans.
                    self.almostRefreshAt = GetTime() + 30
                    if self.almostDirty then self:QueueAlmostRefresh() end
                    return
                end
                count = count or (cached and #cached or GetCategoryNumAchievements(category))
                if index > count then
                    categoryIndex, index, count = categoryIndex + 1, 1, nil
                else
                    local id, name, _, completed, _, _, _, description, _, icon, reward, guild, _, _, statistic
                    if cached then
                        id, name, _, completed, _, _, _, description, _, icon, reward, guild, _, _, statistic = GetAchievementInfo(cached[index].id)
                    else
                        id, name, _, completed, _, _, _, description, _, icon, reward, guild, _, _, statistic = GetAchievementInfo(category, index)
                    end
                    index = index + 1
                    local top = tree:GetRootCategoryID(category)
                    -- Legacy and Feats of Strength often cannot be pursued.
                    if id and not seen[id] and not completed and not guild and not statistic and top ~= 15234 and top ~= 81 then
                        seen[id] = true
                        -- Include zero-progress and zero-criteria candidates: they
                        -- may gain progress later and must not disappear from updates.
                        catalog[#catalog + 1] = {id = id, category = category}
                        local criteria = GetAchievementNumCriteria(id) or 0
                        if criteria > 0 then
                            local rewardItem, hasReward = self:GetAlmostReward(id, reward)
                            pending = { id = id, name = name or "",
                                description = description, icon = icon, reward = reward,
                                rewardItem = rewardItem, hasReward = hasReward, expansion = self:GetAlmostExpansion(id),
                                category = top, count = criteria, cursor = 1, progress = 0 }
                        end
                    end
                end
            end
        end
    end
    self.almostTicker = C_Timer.NewTicker(0.02, self.almostStep)
end

function Window:GetAlmostMatches()
    local matches = {}
    for _, row in ipairs(self.almostRows or {}) do
        if not (self.almostEarned and self.almostEarned[row.id]) and row.percent >= (self.almostThreshold or 80)
            and (not self.almostCategory or row.category == self.almostCategory)
            and (self.almostExpansion == nil or row.expansion == self.almostExpansion)
            and (not self.almostReward or row.hasReward) then
            matches[#matches + 1] = row
        end
    end
    return matches
end

function Window:RenderAlmostCompleted()
    local panel = self.almostPanel
    if not panel or not panel:IsShown() then return end
    local rows = self:GetAlmostMatches()
    panel.status:SetText(#rows == 0 and "No matches. Try lowering the progress filter." or (#rows .. " achievements • Highest progress first"))
    panel.ScrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
end

-- A loaded reward item only changes card icons, so re-init the visible cards
-- instead of rebuilding the whole list.
function Window:RefreshAlmostCards()
    local panel = self.almostPanel
    if not panel or not panel:IsShown() then return end
    panel.ScrollBox:ForEachFrame(function(container, row)
        if container.card then self:UpdateAlmostCard(container.card, row) end
    end)
end

function Window:UpdateAlmostCard(button, row)
    button.row = row
    button.Icon.texture:SetTexture(row.icon)
    button.Label:SetText(row.name)
    local logo = self:GetAlmostExpansionLogo(row.expansion)
    button.expansion:SetShown(row.expansion ~= UNSPECIFIED)
    button.expansion.icon:SetTexture(logo or "Interface\\Icons\\INV_Misc_Map_01")
    button.expansion.icon:SetSize(logo and 76 or 20, 20)
    button.percent:SetText(string.format("%.1f%%", math.floor(row.percent * 10) / 10))
    local progress = math.max(0, math.min(1, row.percent / 100))
    button.percent:SetTextColor(math.min(1, 2 * (1 - progress)), math.min(1, 2 * progress), 0)
    button.reward:SetShown(row.hasReward)
    if row.hasReward then
        local decor = self:GetAlmostDecorRewards(row.id, row.rewardItem)[1]
        -- Catalog iconTexture/iconAtlas are model thumbnails, not item icons.
        local itemID = decor and decor.itemID or row.rewardItem
        if itemID == 0 then itemID = row.rewardItem end
        local icon = itemID and C_Item and C_Item.GetItemIconByID(itemID)
        button.reward.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Gift_01")
        if itemID and not icon and C_Item and C_Item.RequestLoadItemDataByID then
            self.almostPendingItems = self.almostPendingItems or {}
            if not self.almostPendingItems[itemID] then
                self.almostPendingItems[itemID] = true
                C_Item.RequestLoadItemDataByID(itemID)
            end
        end
    end
    local flags = select(9, GetAchievementInfo(row.id)) or 0
    button.accountWide = bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) ~= 0
    button:Saturate()
end

function Window:CreateAlmostCard(container)
    -- The native compact card base supplies parchment, border, title strip,
    -- framed icon and points shield. SummaryAchievementTemplate also registers
    -- itself in Blizzard's recent-achievement pool, so use its base directly.
    local button = CreateFrame("Button", nil, container, "ComparisonPlayerTemplate")
    button:SetAllPoints()
    container.card = button
    button:SetHeight(50)
    button:SetHighlightTexture("Interface\\AchievementFrame\\UI-Achievement-AchievementBackground", "ADD")
    button:GetHighlightTexture():SetAlpha(0.15)
    button.isSummary = true
    button.DateCompleted:Hide()
    button.Shield:Hide()
    local function SelectRow()
        if button.row then AchievementFrame_SelectAchievement(button.row.id) end
    end
    local function HideTooltip() GameTooltip:Hide() end
    button.percent = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.percent:SetShadowColor(0, 0, 0, 1)
    button.percent:SetShadowOffset(1, -1)
    button.percent:SetPoint("RIGHT", -10, 0)
    button.percent:SetWidth(76)
    button.percent:SetJustifyH("RIGHT")
    button.reward = CreateFrame("Button", nil, button)
    button.reward:SetSize(28, 28)
    button.reward:SetPoint("RIGHT", button.percent, "LEFT", -8, 0)
    button.reward.icon = button.reward:CreateTexture(nil, "ARTWORK")
    button.reward.icon:SetAllPoints()
    button.reward:SetScript("OnEnter", function(owner)
        local row = button.row
        if not row then return end
        self:ShowAlmostRewardTooltip(owner, row)
    end)
    button.reward:SetScript("OnLeave", HideTooltip)
    button.reward:SetScript("OnClick", SelectRow)
    button.Label:ClearAllPoints()
    button.Label:SetPoint("TOPLEFT", 54, -4)
    button.Label:SetPoint("TOPRIGHT", -132, -4)
    button.Label:SetHeight(20)
    button.Label:SetJustifyH("CENTER")
    button.Description:Hide()
    button.expansion = CreateFrame("Button", nil, button)
    button.expansion:SetPoint("TOPLEFT", 54, -25)
    button.expansion:SetPoint("TOPRIGHT", -132, -25)
    button.expansion:SetHeight(20)
    button.expansion.icon = button.expansion:CreateTexture(nil, "ARTWORK")
    button.expansion.icon:SetPoint("CENTER")
    button.expansion:SetScript("OnEnter", function(owner)
        if not button.row then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(self:GetAlmostExpansionName(button.row.expansion))
        GameTooltip:Show()
    end)
    button.expansion:SetScript("OnLeave", HideTooltip)
    button.expansion:SetScript("OnClick", SelectRow)
    button:SetScript("OnClick", SelectRow)
    button:SetScript("OnEnter", function()
        local row = button.row
        if not row then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.name)
        GameTooltip:AddLine(row.description or "", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("%.1f%% • %s", math.floor(row.percent * 10) / 10,
            self:GetAlmostExpansionName(row.expansion)), 1, 0.82, 0)
        if row.reward and row.reward ~= "" then GameTooltip:AddLine(row.reward, 0.2, 1, 0.2, true) end
        GameTooltip:AddLine("Click to view achievement", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", HideTooltip)
    return button
end

function Window:CreateAlmostPanel()
    local panel = CreateFrame("Frame", nil, AchievementFrame)
    panel:SetAllPoints(AchievementFrameSummary)
    panel:Hide()
    self.almostPanel = panel
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture("Interface\\AchievementFrame\\UI-Achievement-AchievementBackground")
    background:SetTexCoord(0, 1, 0, 0.5)
    CreateFrame("Frame", nil, panel, "AchivementGoldBorderBackdrop"):SetAllPoints()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("Almost Completed")
    local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPRIGHT", -18, -10)
    dropdown:SetWidth(135)
    dropdown:SetDefaultText(FILTER or "Filter")
    -- Category and expansion lists are static for the session; build them on
    -- the first menu open instead of walking the expansion data on every open.
    local categories, expansions
    dropdown:SetupMenu(function(_, root)
        if not categories then
            categories = {}
            local tree = RefineUI.InstanceAchievements
            for _, id in ipairs(tree:GetAllCategoryIDs()) do
                local node = tree:GetCategoryNode(id)
                if node.parentID == -1 and id ~= 81 and id ~= 15234 then categories[#categories + 1] = {id = id, name = node.title} end
            end
            table.sort(categories, function(a, b) return a.name < b.name end)
            local found = {}
            for _, expansion in pairs(ExpansionData) do found[expansion] = true end
            expansions = {}
            for expansion in pairs(found) do expansions[#expansions + 1] = expansion end
            table.sort(expansions, function(a, b) return a > b end)
            expansions[#expansions + 1] = UNSPECIFIED
        end
        local function Refresh()
            self:RenderAlmostCompleted()
            panel.ScrollBox:ScrollToBegin()
        end
        root:CreateTitle("Minimum progress")
        for _, value in ipairs({50, 70, 80, 90, 95}) do
            root:CreateRadio(value .. "%", function() return (self.almostThreshold or 80) == value end,
                function() self.almostThreshold = value; Refresh() end):SetSelectionIgnored()
        end
        local categoryMenu = root:CreateButton("Category")
        categoryMenu:CreateRadio(ALL or "All", function() return not self.almostCategory end,
            function() self.almostCategory = nil; Refresh() end):SetSelectionIgnored()
        for _, category in ipairs(categories) do
            categoryMenu:CreateRadio(category.name, function() return self.almostCategory == category.id end,
                function() self.almostCategory = category.id; Refresh() end):SetSelectionIgnored()
        end
        local expansionMenu = root:CreateButton("Expansion")
        expansionMenu:CreateRadio(ALL or "All", function() return self.almostExpansion == nil end,
            function() self.almostExpansion = nil; Refresh() end):SetSelectionIgnored()
        for _, expansion in ipairs(expansions) do
            expansionMenu:CreateRadio(self:GetAlmostExpansionName(expansion), function() return self.almostExpansion == expansion end,
                function() self.almostExpansion = expansion; Refresh() end):SetSelectionIgnored()
        end
        root:CreateDivider()
        root:CreateCheckbox("Has reward", function() return self.almostReward end,
            function() self.almostReward = not self.almostReward; Refresh() end):SetSelectionIgnored()
        root:CreateButton("Reset filters", function()
            self.almostThreshold, self.almostCategory, self.almostExpansion, self.almostReward = nil, nil, nil, nil
            Refresh()
        end)
    end)
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 18, -48)
    panel.ScrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    panel.ScrollBox:SetPoint("TOPLEFT", 16, -70)
    panel.ScrollBox:SetPoint("BOTTOMRIGHT", -28, 14)
    panel.ScrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    panel.ScrollBar:SetPoint("TOPLEFT", panel.ScrollBox, "TOPRIGHT", 6, -2)
    panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.ScrollBox, "BOTTOMRIGHT", 6, 2)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(50)
    view:SetPadding(2, 2, 2, 2, 4)
    view:SetElementInitializer("Frame", function(container, row)
        self:UpdateAlmostCard(container.card or self:CreateAlmostCard(container), row)
    end)
    view:SetElementResetter(function(container)
        local button = container.card
        if not button then return end
        button.row = nil
        if GameTooltip:GetOwner() == button or GameTooltip:GetOwner() == button.reward
            or GameTooltip:GetOwner() == button.expansion then GameTooltip:Hide() end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(panel.ScrollBox, panel.ScrollBar, view)
    panel:SetScript("OnHide", function()
        self:PauseAlmostCompleted()
        GameTooltip:Hide()
    end)
    panel:SetScript("OnShow", function() self:ScanAlmostCompleted() end)
    hooksecurefunc("AchievementFrame_ShowSubFrame", function(frame)
        if frame ~= panel then panel:Hide() end
    end)
end

function Window:ShowAlmostCompleted()
    if not self:IsPersonalView() then return end
    -- Select the real Summary record; the extra category row never reaches
    -- Blizzard's category selection or achievement APIs.
    for _, category in ipairs(ACHIEVEMENT_FUNCTIONS.categories) do
        if category.id == "summary" then AchievementFrameCategories_SelectElementData(category); break end
    end
    if not self.almostPanel then self:CreateAlmostPanel() end
    AchievementFrame_ShowSubFrame(self.almostPanel)
    self.almostPanel:Show()
    AchievementFrameCategories_UpdateDataProvider()
end
