-- Current-character saved instances, independent of collection scans.
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")

function Module:ReadGuideLockouts()
    local byMap = {}
    for index = 1, GetNumSavedInstances() do
        local name, _, reset, difficultyID, locked, extended, _, _, _, difficulty, total, killed, _, mapID = GetSavedInstanceInfo(index)
        if mapID and (locked or extended) and (reset > 0 or extended) then
            local entry = {
                name = name, difficultyID = difficultyID, difficulty = difficulty or tostring(difficultyID),
                expires = GetTime() + math.max(0, reset), extended = extended,
                total = total or 0, killed = killed or 0, bosses = {},
            }
            for boss = 1, entry.total do
                local bossName, _, defeated = GetSavedInstanceEncounterInfo(index, boss)
                if bossName then entry.bosses[#entry.bosses + 1] = { name = bossName, defeated = defeated } end
            end
            byMap[mapID] = byMap[mapID] or {}
            table.insert(byMap[mapID], entry)
        end
    end
    for _, entries in pairs(byMap) do
        table.sort(entries, function(a, b)
            if a.difficultyID ~= b.difficultyID then return a.difficultyID < b.difficultyID end
            return a.name < b.name
        end)
    end
    self.guideLockouts = byMap
end

function Module:GetGuideCardLockouts(button)
    if not button.instanceID then return {} end
    local mapID = button.RefineLockoutMapID
    if button.RefineLockoutInstanceID ~= button.instanceID then
        -- Return 8 is the journal link; return 10 is the game map ID
        -- used by GetSavedInstanceInfo (not the journal instance ID).
        mapID = select(10, EJ_GetInstanceInfo(button.instanceID))
        button.RefineLockoutInstanceID, button.RefineLockoutMapID = button.instanceID, mapID
    end
    local active = {}
    for _, entry in ipairs(self.guideLockouts and self.guideLockouts[mapID] or {}) do
        if entry.extended or entry.expires > GetTime() then active[#active + 1] = entry end
    end
    return active
end

function Module:ShowGuideLockoutTooltip(button, owner)
    local entries = self:GetGuideCardLockouts(button)
    if owner.lockoutIndex then
        local entry = entries[owner.lockoutIndex]
        entries = entry and { entry } or {}
    end
    if #entries == 0 or not self:IsGuideOptionEnabled("Lockouts") then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("|A:worldquest-Capstone-questmarker-epic-Locked:20:20|a "
        .. (button.tooltipTitle or entries[1].name), 1, 0.82, 0)
    for index, entry in ipairs(entries) do
        if index > 1 then GameTooltip:AddLine(" ") end
        local complete = entry.total > 0 and entry.killed >= entry.total
        local progress = entry.killed .. "/" .. entry.total .. " defeated"
        if complete then progress = "|A:worldquest-tracker-checkmark:14:14|a " .. progress end
        GameTooltip:AddDoubleLine(entry.difficulty, progress,
            0.9, 0.78, 1, complete and 0.4 or 1, complete and 0.95 or 0.82, complete and 0.45 or 0.3)
        GameTooltip:AddLine(" ")
        for _, boss in ipairs(entry.bosses) do
            local status = boss.defeated and ("|A:worldquest-tracker-checkmark:12:12|a " .. BOSS_DEAD) or BOSS_ALIVE
            GameTooltip:AddDoubleLine(boss.name, status,
                boss.defeated and 0.72 or 1, boss.defeated and 0.78 or 0.95, boss.defeated and 0.72 or 0.82,
                boss.defeated and 0.4 or 1, boss.defeated and 0.9 or 0.82, boss.defeated and 0.45 or 0.3)
        end
        GameTooltip:AddLine(" ")
        local remaining = math.max(0, entry.expires - GetTime())
        if remaining > 0 then
            GameTooltip:AddDoubleLine("Resets in", SecondsToTime(remaining), 0.65, 0.75, 0.85, 0.8, 0.9, 1)
        end
        if entry.extended then GameTooltip:AddLine("Lockout extended", 1, 0.65, 0.25) end
    end
    GameTooltip:AddLine("This character", 0.55, 0.6, 0.65)
    GameTooltip:Show()
end

function Module:DecorateGuideLockout(button)
    local entries = self:GetGuideCardLockouts(button)
    local badges = button.RefineGuideLockouts or {}
    button.RefineGuideLockouts = badges
    if not self:IsGuideOptionEnabled("Lockouts") or #entries == 0 then
        for _, badge in ipairs(badges) do
            if GameTooltip:IsOwned(badge) then GameTooltip:Hide() end
            badge:Hide()
        end
        return
    end
    local columns = math.max(1, math.floor(button:GetWidth() / 42))
    for index, entry in ipairs(entries) do
        local badge = badges[index]
        if not badge then
        badge = CreateFrame("Button", nil, button)
        badges[index] = badge
        badge.lockoutIndex = index
        badge:SetSize(40, 40)
        -- Anchor the artwork itself flush with the card corner.
        badge.Banner = badge:CreateTexture(nil, "BACKGROUND")
        badge.Banner:SetPoint("TOPRIGHT", 0, 0)
        badge.Banner:SetSize(40, 40)
        badge.Banner:SetAtlas("worldquest-Capstone-questmarker-epic-Locked")
        badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        badge.Text:SetPoint("CENTER", badge.Banner, "CENTER", 0, -3)
        badge.CompletedBanner = badge:CreateTexture(nil, "BACKGROUND")
        badge.CompletedBanner:SetAtlas("worldquest-Capstone-Banner")
        badge.CompletedBanner:SetPoint("TOP", badge.Banner, "TOP", 0, 0)
        badge.CompletedBanner:SetSize(28, 40)
        badge.CompletedMarker = badge:CreateTexture(nil, "ARTWORK")
        badge.CompletedMarker:SetAtlas("worldquest-questmarker-epic")
        badge.CompletedMarker:SetPoint("CENTER", badge.Banner, "CENTER", 0, 0)
        badge.CompletedMarker:SetSize(32, 32)
        badge.Check = badge:CreateTexture(nil, "OVERLAY")
        badge.Check:SetAtlas("worldquest-tracker-checkmark")
        badge.Check:SetPoint("CENTER", badge.CompletedMarker, "CENTER", 0, 0)
        badge.Check:SetSize(22, 22)
        badge:SetScript("OnClick", function(_, mouseButton) button:Click(mouseButton) end)
        badge:SetScript("OnEnter", function(owner) self:ShowGuideLockoutTooltip(button, owner) end)
        badge:SetScript("OnLeave", function() if GameTooltip:IsOwned(badge) then GameTooltip:Hide() end end)
        badge:SetScript("OnHide", function() if GameTooltip:IsOwned(badge) then GameTooltip:Hide() end end)
        end
        badge:ClearAllPoints()
        badge:SetPoint("TOPRIGHT", -((index - 1) % columns) * 42, -math.floor((index - 1) / columns) * 42)
        local complete = entry.total > 0 and entry.killed >= entry.total
        badge.Text:SetText(entry.killed .. "/" .. entry.total)
        badge.Text:SetShown(not complete)
        badge.Banner:SetShown(not complete)
        badge.CompletedBanner:SetShown(complete)
        badge.CompletedMarker:SetShown(complete)
        badge.Check:SetShown(complete)
        badge:Show()
        if GameTooltip:IsOwned(badge) then self:ShowGuideLockoutTooltip(button, badge) end
    end
    for index = #entries + 1, #badges do
        local badge = badges[index]
        if GameTooltip:IsOwned(badge) then GameTooltip:Hide() end
        badge:Hide()
    end
end

function Module:RefreshGuideLockoutCards()
    local journal = _G.EncounterJournal
    local scroll = journal and journal.instanceSelect and journal.instanceSelect.ScrollBox
    if scroll and scroll.GetFrames then
        for _, button in ipairs(scroll:GetFrames()) do self:DecorateGuideLockout(button) end
    end
end

function Module:InstallGuideLockouts()
    if self.guideLockoutsInstalled then return end
    local scroll = EncounterJournal.instanceSelect.ScrollBox
    if not ScrollUtil or not ScrollUtil.AddInitializedFrameCallback then return end
    self.guideLockoutsInstalled = true
    local function Refresh()
        self:ReadGuideLockouts()
        self:RefreshGuideLockoutCards()
    end
    ScrollUtil.AddInitializedFrameCallback(scroll, function(_, button) self:DecorateGuideLockout(button) end, self)
    RefineUI:HookOnce(self:BuildKey("Lockouts", "List"), "EncounterJournal_ListInstances", function() self:RefreshGuideLockoutCards() end)
    scroll:HookScript("OnShow", function() Refresh(); RequestRaidInfo() end)
    RefineUI:RegisterEventCallback("UPDATE_INSTANCE_INFO", Refresh, self:BuildKey("Lockouts", "Update"))
    RefineUI:RegisterEventCallback("BOSS_KILL", function() RequestRaidInfo() end, self:BuildKey("Lockouts", "Boss"))
    Refresh()
    RequestRaidInfo()
end
