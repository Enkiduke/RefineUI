-- Decorate native expansion cards; Blizzard retains list, artwork and navigation.
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")
local Data = RefineUI.InstanceCompletion
local function Enabled(key) return Module:IsGuideOptionEnabled(key) end
local function ShowCategory(summary, key)
    local count = summary.instance[key]
    if not Enabled(key) or not count or count.total == 0 then return false end
    local ready = key == "achievements" and summary.achievementsReady
        or key ~= "achievements" and summary.lootReady
    return Enabled("ShowCompletedCategories") or not ready
        or count.unknown > 0 or count.earned < count.total
end
local BADGES = {
    { key = "achievements", label = "Achievements", icon = 236507 },
    { key = "appearances", label = "Appearances", icon = 133743 },
    { key = "pets", label = "Pets", icon = 132599 },
    { key = "mounts", label = "Mounts", icon = 132261 },
    { key = "toys", label = "Toys", icon = 134859 },
}
function Module:IsExpansionCompletionVisible()
    local journal = _G.EncounterJournal
    local list = journal and journal.instanceSelect
    return journal and journal:IsShown() and list and list:IsShown()
        and list.ScrollBox and list.ScrollBox:IsShown() and self:IsSupportedContentTab(journal.selectedTab) and Enabled("Cards")
end

function Module:ShowExpansionCompletionTooltip(button, owner, kind)
    local summary = button.RefineExpansionSummary
    if not Enabled("Cards") or not GameTooltip or not summary or summary.instanceID ~= button.instanceID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.tooltipTitle or "Instance completion", 1, 0.82, 0)
    GameTooltip:AddLine("All difficulties - unique rewards", 0.75, 0.75, 0.75)
    GameTooltip:AddLine("Percentage uses the selected collection types.", 0.65, 0.65, 0.65)
    if not summary.lootReady or not summary.achievementsReady then
        GameTooltip:AddLine(summary.unavailable and "Collection data is currently unavailable." or "Loading collection progress...", 0.75, 0.75, 0.75)
        GameTooltip:Show()
        return
    end
    for _, badge in ipairs(BADGES) do
        if ShowCategory(summary, badge.key) and (not kind or kind == badge.key) then
            local count = summary.instance[badge.key]
            local ready = badge.key == "achievements" and summary.achievementsReady or badge.key ~= "achievements" and summary.lootReady
            local text, r, g, b = self:FormatCompletionCount(count, ready)
            GameTooltip:AddLine(badge.label .. "  " .. text, r, g, b)
            if kind then
                for index = 1, math.min(10, #count.missing) do
                    local reward = count.missing[index]
                    GameTooltip:AddLine(reward.name or reward.link or "Retrieving name...", 0.85, 0.85, 0.85, true)
                end
                if #count.missing > 10 then GameTooltip:AddLine("+" .. (#count.missing - 10) .. " more missing", 0.65, 0.65, 0.65) end
            end
        end
    end
    if summary.unavailable then
        GameTooltip:AddLine("Some collection data is unavailable. Completion is not yet known.", 0.85, 0.72, 0.45, true)
    end
    GameTooltip:Show()
end

function Module:RenderExpansionCompletion(button, summary)
    if not button.RefineExpansionCompletion or summary.instanceID ~= button.instanceID then return end
    button.RefineExpansionSummary = summary
    local overlay = button.RefineExpansionCompletion
    local loading = button.RefineCompletionLoading
    if not Enabled("Cards") then
        overlay.Reveal:Stop(); overlay:Hide(); loading.Sheen:Stop(); loading:Hide()
        return
    end
    if not summary.lootReady or not summary.achievementsReady then
        overlay.Reveal:Stop()
        overlay:Hide()
        overlay.ready = nil
        loading:Show()
        if not loading.Sheen:IsPlaying() then loading.Sheen:Play() end
        return
    end
    loading.Sheen:Stop()
    loading:Hide()
    local available = 0
    for _, badge in ipairs(BADGES) do
        if ShowCategory(summary, badge.key) then available = available + 1 end
    end
    if available == 0 then overlay:Hide(); return end
    overlay:Show()
    -- Leave a separate bottom row for the bar and percentage below the badges.
    overlay:SetHeight(available <= 3 and 31 or 47)
    local firstRow = available <= 3 and available or math.ceil(available / 2)
    local index = 0
    for _, badge in ipairs(BADGES) do
        local widget = overlay.badges[badge.key]
        if not ShowCategory(summary, badge.key) then
            widget:Hide()
        else
        index = index + 1
        local top = index <= firstRow
        local columns = top and firstRow or available - firstRow
        local column = top and index - 1 or index - firstRow - 1
        local width = (button:GetWidth() - 18) / columns
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", 3 + column * width, top and -3 or -19)
        widget:SetSize(width, 13)
        widget:Show()
        local ready = badge.key == "achievements" and summary.achievementsReady or badge.key ~= "achievements" and summary.lootReady
        local text, r, g, b = self:FormatCompletionCount(summary.instance[badge.key], ready)
        widget.Text:SetText(summary.unavailable and not ready and "--" or text)
        widget.Text:SetTextColor(r, g, b)
        end
    end
    local earned, total, known = 0, 0, true
    for _, badge in ipairs(BADGES) do
        if self.guideCollectionTypes and self.guideCollectionTypes[badge.key] then
            local count = summary.instance[badge.key]
            earned, total = earned + count.earned, total + count.total
            if count.unknown > 0 then known = false end
        end
    end
    local rate = known and total > 0 and earned / total or nil
    overlay.Bar:SetValue(rate or 0)
    if rate then
        local r, g, b = self:GetCompletionColor(rate)
        overlay.Bar:SetStatusBarColor(r, g, b)
        overlay.Percent:SetText(string.format("%.0f%%", rate * 100))
        overlay.Percent:SetTextColor(r, g, b)
    else
        overlay.Percent:SetText("--")
        overlay.Percent:SetTextColor(0.68, 0.68, 0.68)
    end
    if not overlay.ready then
        overlay.ready = true
        overlay.Reveal:Play()
    end
end

function Module:DecorateExpansionCompletion(button)
    if not button or not button.instanceID then return end
    local overlay = button.RefineExpansionCompletion
    if not overlay then
        overlay = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.RefineExpansionCompletion = overlay
        overlay:SetPoint("BOTTOMLEFT", 6, 5)
        overlay:SetPoint("BOTTOMRIGHT", -6, 5)
        overlay:SetHeight(47)
        overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        overlay:SetBackdropColor(0.06, 0.045, 0.025, 0.78)
        overlay.Reveal = overlay:CreateAnimationGroup()
        local reveal = overlay.Reveal:CreateAnimation("Alpha")
        reveal:SetFromAlpha(0); reveal:SetToAlpha(1); reveal:SetDuration(0.25)
        -- A narrow gold sheen over the artwork, with no placeholder panel/text.
        -- Native animation groups do the motion; there is no Lua OnUpdate work.
        local loading = CreateFrame("Frame", nil, button)
        button.RefineCompletionLoading = loading
        loading:SetPoint("BOTTOMLEFT", 10, 8)
        loading:SetPoint("BOTTOMRIGHT", -10, 8)
        loading:SetHeight(2)
        local track = loading:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(); track:SetColorTexture(0.8, 0.68, 0.42, 0.12)
        local glow = loading:CreateTexture(nil, "ARTWORK")
        glow:SetSize(32, 2); glow:SetPoint("LEFT")
        glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        glow:SetGradient("HORIZONTAL", CreateColor(0.9, 0.78, 0.5, 0), CreateColor(0.9, 0.78, 0.5, 0.6))
        loading.Sheen = glow:CreateAnimationGroup()
        loading.Sheen:SetLooping("REPEAT")
        local move = loading.Sheen:CreateAnimation("Translation")
        move:SetOffset(math.max(0, button:GetWidth() - 52), 0)
        move:SetDuration(1.6)
        local fadeIn = loading.Sheen:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.35)
        local fadeOut = loading.Sheen:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.45); fadeOut:SetStartDelay(1.15)
        loading:Hide()
        overlay:Hide()
        overlay.badges = {}
        -- Keep a two-line native title above the overlay, including long raid names.
        if button.name then button.name:SetMaxLines(2); button.name:SetHeight(32) end
        for index, descriptor in ipairs(BADGES) do
            local badge = CreateFrame("Button", nil, overlay)
            local columns, column, y = index <= 2 and 2 or 3, index <= 2 and index - 1 or index - 3, index <= 2 and -3 or -19
            local width = (button:GetWidth() - 18) / columns
            badge:SetPoint("TOPLEFT", 3 + column * width, y)
            badge:SetSize(width, 13)
            badge.Icon = badge:CreateTexture(nil, "ARTWORK")
            badge.Icon:SetSize(11, 11); badge.Icon:SetPoint("LEFT")
            badge.Icon:SetTexture(descriptor.icon)
            badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            badge.Text:SetPoint("LEFT", badge.Icon, "RIGHT", 2, 0)
            badge.Text:SetPoint("RIGHT", -2, 0); badge.Text:SetJustifyH("LEFT")
            badge:SetScript("OnClick", function(_, mouseButton) button:Click(mouseButton) end)
            badge:SetScript("OnEnter", function(owner) self:ShowExpansionCompletionTooltip(button, owner, descriptor.key) end)
            badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            overlay.badges[descriptor.key] = badge
        end
        overlay.Bar = CreateFrame("StatusBar", nil, overlay)
        overlay.Bar:SetPoint("BOTTOMLEFT", 3, 6); overlay.Bar:SetPoint("BOTTOMRIGHT", -43, 6)
        overlay.Bar:SetHeight(3); overlay.Bar:SetMinMaxValues(0, 1)
        overlay.Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local barTrack = overlay.Bar:CreateTexture(nil, "BACKGROUND")
        barTrack:SetAllPoints()
        barTrack:SetColorTexture(0.8, 0.68, 0.42, 0.18)
        overlay.Percent = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        overlay.Percent:SetPoint("BOTTOMRIGHT", -3, 2)
        overlay.Percent:SetSize(34, 11)
        overlay.Percent:SetJustifyH("RIGHT")
        button:HookScript("OnEnter", function() self:ShowExpansionCompletionTooltip(button, button) end)
        button:HookScript("OnHide", function()
            loading.Sheen:Stop(); loading:Hide()
            overlay.Reveal:Stop(); overlay:Hide(); overlay.ready = nil
            Data:ReleaseSummary(button)
            button.RefineExpansionInstanceID = nil
            button.RefineExpansionSummary = nil
        end)
        button:HookScript("OnShow", function() self:DecorateExpansionCompletion(button) end)
    end
    if not self:IsExpansionCompletionVisible() then
        button.RefineCompletionLoading.Sheen:Stop(); button.RefineCompletionLoading:Hide()
        overlay.Reveal:Stop(); overlay:Hide(); overlay.ready = nil
        return
    end
    if button.RefineExpansionInstanceID == button.instanceID then return end
    Data:ReleaseSummary(button)
    overlay.Reveal:Stop()
    overlay.ready = nil
    button.RefineExpansionInstanceID = button.instanceID
    local initial = true
    Data:RequestSummary(button.instanceID, button, function(summary)
        -- Cached data is available synchronously: show it immediately. Only a
        -- genuine loading-to-ready transition should play the reveal animation.
        if initial and summary.lootReady and summary.achievementsReady then overlay.ready = true end
        if button:IsShown() and self:IsExpansionCompletionVisible() then self:RenderExpansionCompletion(button, summary) end
    end)
    initial = false
end

local function KeepSummaryWarm(summary)
    Module:OnGuideSummaryUpdated(summary)
end

function Module:ReleaseExpansionCompletionRequests()
    if self._expansionCompletionOwner then Data:ReleaseSummary(self._expansionCompletionOwner) end
    self._expansionCompletionScope = nil
    self._guideSummarySortState = {}
end

function Module:RequestExpansionCompletion()
    local cardsVisible = self:IsExpansionCompletionVisible()
    local needsSummaries = self:GuideListNeedsSummaries()
    if not self:IsGuideInstanceListVisible() or (not cardsVisible and not needsSummaries) then
        self:ReleaseExpansionCompletionRequests()
        return
    end
    local journal = _G.EncounterJournal
    local tier = EJ_GetCurrentTier()
    local isRaid = journal.selectedTab == journal.raidsTab:GetID()
    local all = self.guideAllExpansions
    local scope = tostring(tier) .. ":" .. tostring(isRaid) .. ":" .. tostring(all)
        .. ":" .. tostring(needsSummaries) .. ":" .. tostring(cardsVisible)
    if self._expansionCompletionScope == scope then return end
    self:ReleaseExpansionCompletionRequests()
    self._expansionCompletionOwner = self._expansionCompletionOwner or {}
    self._expansionCompletionScope = scope
    if not next(self.guideCollectionTypes) then return end
    -- In All/Journal order with no active filter, visible cards subscribe on
    -- demand. Sorting or filtering needs summaries for the full displayed list.
    if all and not needsSummaries then return end
    local rows = self:GetGuideBaseRows()
    if not rows then return end
    for _, row in ipairs(rows) do
        Data:RequestSummary(row.instanceID, self._expansionCompletionOwner, KeepSummaryWarm)
    end
end

function Module:InstallExpansionCompletionUI()
    if self._expansionCompletionInstalled then return end
    local journal = _G.EncounterJournal
    local scrollBox = journal and journal.instanceSelect and journal.instanceSelect.ScrollBox
    if not scrollBox or not ScrollUtil or not ScrollUtil.AddInitializedFrameCallback then return end
    self._expansionCompletionInstalled = true
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, button) self:DecorateExpansionCompletion(button) end, self)
    local function Refresh()
        if scrollBox.GetFrames then
            for _, button in ipairs(scrollBox:GetFrames()) do self:DecorateExpansionCompletion(button) end
        end
        self:RequestExpansionCompletion()
    end
    scrollBox:HookScript("OnShow", Refresh)
    scrollBox:HookScript("OnHide", function() self:ReleaseExpansionCompletionRequests() end)
    -- Frame initialization can precede the tab/visibility update.
    RefineUI:HookOnce(self:BuildKey("ExpansionCompletion", "List"), "EncounterJournal_ListInstances", Refresh)
    Refresh()
end
