----------------------------------------------------------------------------------------
-- Native Adventure Guide boss-list completion badges.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")
if not Module then return end

local BADGES = {
    { key = "achievements", label = "Achievements", icon = 236507 },
    { key = "appearances", label = "Appearances", icon = 133743 },
    { key = "pets", label = "Pets", icon = 132599 },
    { key = "mounts", label = "Mounts", icon = 132261 },
    { key = "toys", label = "Toys", icon = 134859 },
}
local EMPTY_COUNT = { earned = 0, total = 0, unknown = 0 }
local PROGRESS_RED = { 0.9, 0.27, 0.24 }
local PROGRESS_AMBER = { 0.96, 0.69, 0.24 }
local PROGRESS_GREEN = { 0.39, 0.87, 0.46 }

local function GetInfoFrame()
    local journal = _G.EncounterJournal
    return journal and journal.encounter and journal.encounter.info
end

local function IsReady(summary, key)
    if not summary then return false end
    if key == "achievements" then return summary.achievementsReady end
    return summary.lootReady
end

function Module:GetCompletionColor(rate)
    rate = math.max(0, math.min(rate or 0, 1))
    local from, to, blend
    if rate <= 0.5 then
        from, to, blend = PROGRESS_RED, PROGRESS_AMBER, rate * 2
    else
        from, to, blend = PROGRESS_AMBER, PROGRESS_GREEN, (rate - 0.5) * 2
    end
    return from[1] + (to[1] - from[1]) * blend,
        from[2] + (to[2] - from[2]) * blend,
        from[3] + (to[3] - from[3]) * blend
end

function Module:FormatCompletionCount(count, ready)
    if not ready then return "...", 0.65, 0.65, 0.65 end
    count = count or EMPTY_COUNT
    if count.unknown > 0 then
        return string.format("%d+/%d", count.earned, count.total), 0.85, 0.72, 0.45
    end
    local rate = count.total > 0 and count.earned / count.total or 0
    local r, g, b = self:GetCompletionColor(rate)
    return string.format("%d/%d", count.earned, count.total), r, g, b
end

function Module:GetCompletionRate(summary)
    if not summary or not summary.achievementsReady or not summary.lootReady then return nil end
    local earned, total = 0, 0
    for _, key in ipairs(self.COMPLETION_KEYS) do
        local count = summary.instance[key]
        if count.unknown > 0 then return nil end
        earned, total = earned + count.earned, total + count.total
    end
    if total == 0 then return nil, earned, total end
    return earned / total, earned, total
end

function Module:ShowCompletionTooltip(owner, bossID, kind)
    local tooltip = _G.GameTooltip
    local summary = self._completionSummary
    if not tooltip then return end
    if not summary or summary.instanceID ~= self:GetCurrentJournalInstanceID()
        or summary.difficultyID ~= EJ_GetDifficulty() then
        tooltip:Hide()
        return
    end
    local counts = bossID and summary.bosses[bossID] or summary.instance
    local title = "Missing rewards"
    for _, badge in ipairs(BADGES) do
        if badge.key == kind then title = badge.label end
    end
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    tooltip:SetText(title, 1, 0.82, 0)
    local hasContent = false
    for _, badge in ipairs(BADGES) do
        if not kind or kind == badge.key then
            local count = counts and counts[badge.key] or EMPTY_COUNT
            local missing = count.missing or {}
            local ready = IsReady(summary, badge.key)
            if #missing > 0 or count.unknown > 0 or not ready then
                if not kind then tooltip:AddLine(badge.label, 1, 0.82, 0) end
                -- Bound tooltip height; the counter still reports the full total.
                local limit = kind and 15 or 5
                for index = 1, math.min(#missing, limit) do
                    local reward = missing[index]
                    local name = reward.name
                    if not name and reward.link then name = reward.link:match("%[(.-)%]") end
                    name = name or (reward.achievementID and "Achievement " .. reward.achievementID)
                        or (reward.itemID and "Item " .. reward.itemID) or "Retrieving name..."
                    local icon = reward.icon or badge.icon
                    tooltip:AddLine("|T" .. icon .. ":14|t " .. name, 0.9, 0.85, 0.75, true)
                end
                if #missing > limit then
                    tooltip:AddLine(string.format("+%d more missing", #missing - limit), 0.65, 0.65, 0.65)
                end
                if count.unknown > 0 then
                    tooltip:AddLine(string.format("%d unknown", count.unknown), 0.65, 0.65, 0.65)
                end
                if not ready then tooltip:AddLine("Loading...", 0.65, 0.65, 0.65) end
                hasContent = true
            end
        end
    end
    if not hasContent then tooltip:AddLine("Nothing missing", 0.45, 0.9, 0.55) end
    tooltip:Show()
end

function Module:DecorateCompletionBoss(button)
    if not button or not button.encounterID then return end
    if not button.RefineCompletionBadges then
        local badges = {}
        button.RefineCompletionBadges = badges
        -- Keep the native 55px row and its artwork unchanged.
        if button.text then
            button.text:ClearAllPoints()
            button.text:SetPoint("TOPLEFT", button, "TOPLEFT", 105, -5)
            button.text:SetSize(200, 27)
            button.text:SetJustifyV("TOP")
        end
        for _, descriptor in ipairs(BADGES) do
            local badge = CreateFrame("Button", nil, button)
            badge:SetSize(40, 14)
            badge:EnableMouse(true)
            badge:SetScript("OnClick", function(_, mouseButton) button:Click(mouseButton) end)
            badge.Icon = badge:CreateTexture(nil, "ARTWORK")
            badge.Icon:SetSize(11, 11)
            badge.Icon:SetPoint("LEFT")
            badge.Icon:SetTexture(descriptor.icon)
            badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            badge.Text:SetPoint("LEFT", badge.Icon, "RIGHT", 2, 0)
            badge.Text:SetPoint("RIGHT", badge, "RIGHT", -1, 0)
            badge.Text:SetJustifyH("LEFT")
            badge:SetScript("OnEnter", function(frame)
                self:ShowCompletionTooltip(frame, button.encounterID, descriptor.key)
            end)
            badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            badges[descriptor.key] = badge
        end
    end
    local summary = self._completionSummary
    if summary and (summary.instanceID ~= self:GetCurrentJournalInstanceID()
        or summary.difficultyID ~= EJ_GetDifficulty()) then summary = nil end
    local counts = summary and summary.bosses[button.encounterID]
    local offset = 0
    local availableWidth = math.max(1, button:GetWidth() - 115)
    local visibleCount = 0
    for _, descriptor in ipairs(BADGES) do
        local count = counts and counts[descriptor.key]
        if count and count.total > 0 then visibleCount = visibleCount + 1 end
    end
    local badgeWidth = math.min(60, availableWidth / math.max(1, visibleCount))
    for _, descriptor in ipairs(BADGES) do
        local badge = button.RefineCompletionBadges[descriptor.key]
        local text, r, g, b = self:FormatCompletionCount(counts and counts[descriptor.key], IsReady(summary, descriptor.key))
        local count = counts and counts[descriptor.key]
        local shown = count and count.total > 0
        badge:SetShown(shown == true)
        if shown then
            badge:ClearAllPoints()
            badge:SetPoint("TOPLEFT", button, "TOPLEFT", 105 + offset, -34)
            badge:SetSize(badgeWidth - 2, 14)
            badge.Text:SetText(text)
            badge.Text:SetTextColor(r, g, b)
            offset = offset + badgeWidth
        end
    end
end

function Module:InstallCompletionUI()
    if self._completionUIInstalled then return end
    local info = GetInfoFrame()
    local scrollBox = info and info.BossesScrollBox
    local view = scrollBox and scrollBox.GetView and scrollBox:GetView()
    if not view or not ScrollUtil or not ScrollUtil.AddInitializedFrameCallback then return end

    -- Leave native row extent, spacing and artwork sizing alone.
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, button)
        self:DecorateCompletionBoss(button)
    end, self)

    local header = CreateFrame("Frame", nil, info, "BackdropTemplate")
    header:SetSize(318, 28)
    local oldHeight = scrollBox:GetHeight()
    scrollBox:SetHeight(math.max(150, oldHeight - 64))
    -- Reserve 24px below the original list top for the instance portrait,
    -- then 28px for the summary and 12px above the first boss artwork.
    header:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", 0, 12)
    header:SetPoint("BOTTOMRIGHT", scrollBox, "TOPRIGHT", -20, 12)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    header:SetBackdropColor(0.65, 0.49, 0.28, 0.12)
    header:SetBackdropBorderColor(0.38, 0.25, 0.12, 0.45)
    local shadow = header:CreateTexture(nil, "BACKGROUND", nil, -1)
    shadow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, 0)
    shadow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 2, 0)
    shadow:SetHeight(2)
    shadow:SetColorTexture(0.16, 0.09, 0.03, 0.18)
    header:EnableMouse(true)
    header.Title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.Title:SetPoint("TOPLEFT", 7, -4)
    header.Title:SetPoint("TOPRIGHT", -7, -4)
    header.Title:SetHeight(14)
    header.Title:SetWordWrap(false)
    header.Title:SetMaxLines(1)
    header.Title:SetShadowOffset(1, -1)
    header.Title:SetShadowColor(0.9, 0.75, 0.5, 0.35)
    header.Title:SetTextColor(1, 0.82, 0)
    header.Title:SetJustifyH("LEFT")
    header.Title:SetText("Instance completion")
    header.Bar = CreateFrame("StatusBar", nil, header)
    header.Bar:SetPoint("BOTTOMLEFT", 7, 4)
    header.Bar:SetPoint("BOTTOMRIGHT", -7, 4)
    header.Bar:SetHeight(3)
    header.Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    header.Bar:SetStatusBarColor(0.36, 0.46, 0.22)
    header.Bar:SetMinMaxValues(0, 1)
    local background = header.Bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.32, 0.22, 0.1, 0.18)
    header:SetScript("OnEnter", function(frame) self:ShowCompletionTooltip(frame) end)
    header:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    scrollBox:HookScript("OnShow", function() header:Show(); self:ScheduleCompletionRefresh() end)
    scrollBox:HookScript("OnHide", function() header:Hide() end)
    header:SetShown(scrollBox:IsShown())
    self.completionHeader = header
    self._completionUIInstalled = true
    self:RegisterCompletionEvents()
    self:RenderCompletionProgress()
end

function Module:RenderCompletionProgress()
    if not self._completionUIInstalled then return end
    local info = GetInfoFrame()
    local scrollBox = info and info.BossesScrollBox
    if not scrollBox then return end
    local summary = self._completionSummary
    if summary and (summary.instanceID ~= self:GetCurrentJournalInstanceID()
        or summary.difficultyID ~= EJ_GetDifficulty()) then summary = nil end
    local header = self.completionHeader
    if header then
        local rate, earned, total = self:GetCompletionRate(summary)
        header.Bar:SetValue(rate or 0)
        if rate then
            header.Title:SetText(string.format("Completion  %.0f%%  |  %d/%d", rate * 100, earned, total))
        else
            header.Title:SetText("Instance completion  --")
        end
        if not rate then
            header.Title:SetText(total == 0 and "No tracked rewards" or "Completion  �  loading / unknown")
        end
    end
    if scrollBox.GetFrames then
        for _, button in ipairs(scrollBox:GetFrames()) do self:DecorateCompletionBoss(button) end
    end
end
