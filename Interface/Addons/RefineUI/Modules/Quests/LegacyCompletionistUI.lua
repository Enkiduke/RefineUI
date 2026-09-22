local _, RefineUI = ...
local Module = RefineUI:GetModule("LegacyCompletionist")
local GROUP_PAGE_SIZE = 6
local LINE_TEMPLATE = "RefineUICompletionistLineTemplate"
local FALLBACK_ICON = 134400

local function Icon(texture, size)
    return string.format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t", texture or FALLBACK_ICON, size, size)
end

function Module:AddSettings(root)
    local menu = root:CreateButton("Legacy Completionist Mode")
    local function Option(label, key, rescan)
        menu:CreateCheckbox(label, function() return self:GetSettings()[key] ~= false end, function()
            local cfg = self:GetSettings()
            cfg[key] = cfg[key] == false
            self.groupOffsets, self.firstGroup = {}, 1
            if key == "Enable" then self:UpdateContext()
            elseif rescan then self:Schedule(true)
            else self:BuildView() end
        end)
    end
    Option("Enable in legacy dungeons / raids", "Enable")
    Option("Hide collected / completed", "HideCollected")
    menu:CreateCheckbox("Auto Collapse (one section at a time)", function()
        return self:GetSettings().AutoCollapse ~= false
    end, function()
        self:GetSettings().AutoCollapse = self:GetSettings().AutoCollapse == false
        self.autoCollapseInitialized, self.activeGroup = nil, nil
        self:BuildView()
        self:Reflow()
    end)
    menu:CreateDivider()
    for _, key in ipairs(self.KINDS) do Option(self.LABELS[key], key, key == "achievements") end
    menu:CreateDivider()
    menu:CreateButton("Refresh instance data", function()
        self.dataRetries = 0
        self.achievementEntries = nil
        self:Schedule(true)
    end)
end

function Module:BuildView()
    if not self.context then return end
    local cfg, rows, counts = self:GetSettings(), {}, {}
    for _, kind in ipairs(self.KINDS) do counts[kind] = { total = 0, earned = 0, unknown = 0 } end
    local groups = { { id = 0, name = "Instance", entries = {}, rows = {} } }
    local byBoss = { [0] = groups[1] }
    for _, boss in ipairs(self.bosses or {}) do
        local group = { id = boss.id, name = boss.name, icon = boss.icon, entries = {}, rows = {},
            defeated = boss.encounterID and self.defeated[boss.encounterID] }
        groups[#groups + 1], byBoss[boss.id] = group, group
    end
    local function Add(entry)
        if cfg[entry.kind] == false then return end
        local count = counts[entry.kind]
        count.total = count.total + 1
        if entry.owned == true then count.earned = count.earned + 1
        elseif entry.owned == nil then count.unknown = count.unknown + 1 end
        if cfg.HideCollected ~= false and entry.owned == true then return end
        local assigned = false
        for bossID in pairs(entry.bosses) do
            local group = byBoss[bossID]
            if group then group.entries[#group.entries + 1] = entry; assigned = true end
        end
        if not assigned then groups[1].entries[#groups[1].entries + 1] = entry end
    end
    for _, entry in ipairs(self.entries or {}) do Add(entry) end
    if cfg.achievements ~= false then
        for _, entry in ipairs(self:GetAchievementEntries()) do Add(entry) end
    end
    local visibleGroups = {}
    local displayRows = {}
    for _, group in ipairs(groups) do
        for _, entry in ipairs(group.entries) do
            local row = displayRows[entry]
            if not row then
                local item = entry.item
                local name = entry.name or item.name or item.link or ("Item " .. item.itemID)
                local texture = entry.icon or (item and item.icon)
                local suffix = entry.owned == nil and " |cffaaaaaa?|r" or entry.owned == true and " |cff80ff80+|r" or ""
                row = { text = Icon(texture, 16) .. " " .. name .. suffix, entry = entry }
                displayRows[entry] = row
            end
            group.rows[#group.rows + 1], rows[#rows + 1] = row, row
        end
        if #group.rows > 0 or group.defeated then visibleGroups[#visibleGroups + 1] = group end
    end
    self.rows, self.counts, self.groups = rows, counts, visibleGroups
    self.firstGroup = math.min(self.firstGroup or 1, math.max(1, #visibleGroups))
    self.groupOffsets, self.collapsedGroups = self.groupOffsets or {}, self.collapsedGroups or {}
    self:ApplyAutoCollapse()
    self:UpdateHeader()
    -- Data refreshes use the native coalesced dirty layout. Force a full reflow
    -- only for explicit collapse/expand operations.
    if self.frame then self.frame:MarkDirty() end
end

function Module:Reflow()
    if not self.frame then return end
    self.frame:MarkDirty()
    -- A full layout also reanchors modules that were clean before our height changed.
    local container = self.frame.parentContainer
    if container then container:Update() end
end

function Module:ApplyAutoCollapse()
    if self:GetSettings().AutoCollapse == false then self.advanceAfterBoss = nil; return end
    -- Achievement discovery can finish before boss loot/ownership. Do not latch
    -- the first achievement-bearing boss while earlier bosses are still loading.
    local initialDataReady = self.snapshot and not self.scan and not self.ownershipTicker
        and not self.snapshot.unknownData
        and (self:GetSettings().achievements == false or self.achievementRows ~= nil)
    if not self.autoCollapseInitialized and not initialDataReady then
        self.activeGroup = nil
        for _, group in ipairs(self.groups) do self.collapsedGroups[group.id] = true end
        return
    end
    local byID = {}
    for _, group in ipairs(self.groups) do
        byID[group.id] = group
    end
    local activeExists = self.activeGroup and byID[self.activeGroup]
    if not self.autoCollapseInitialized or self.advanceAfterBoss or (self.activeGroup and not activeExists) then
        local nextID, after = nil, self.advanceAfterBoss == nil
        for _, boss in ipairs(self.bosses or {}) do
            if boss.id == self.advanceAfterBoss then
                after = true
            elseif after then
                local group = byID[boss.id]
                if group and not group.defeated and #group.rows > 0 then nextID = group.id end
            end
            if nextID then break end
        end
        if not nextID then
            for _, group in ipairs(self.groups) do
                if not group.defeated and #group.rows > 0 then nextID = group.id; break end
            end
        end
        self.activeGroup = nextID
        self.autoCollapseInitialized = #self.groups > 0
        self.advanceAfterBoss, self.firstGroup = nil, 1
    end
    for _, group in ipairs(self.groups) do self.collapsedGroups[group.id] = group.id ~= self.activeGroup end
end

function Module:ExpandGroup(id)
    -- An explicit user choice takes precedence even during initial loading.
    self.autoCollapseInitialized = true
    self.activeGroup = id
    self.collapsedGroups[id] = false
    if self:GetSettings().AutoCollapse ~= false then self:ApplyAutoCollapse() end
end

function Module:GetTotals()
    local earned, total, unknown = 0, 0, 0
    for _, count in pairs(self.counts or {}) do
        earned, total, unknown = earned + count.earned, total + count.total, unknown + count.unknown
    end
    local partial = not self.snapshot or self.snapshot.unknownData or unknown > 0 or self.status
        or self.ownershipTicker or (self:GetSettings().achievements ~= false and not self.achievementRows)
    return earned, total, not not partial
end

function Module:UpdateHeader()
    if not self.context or not self.frame then return end
    local title = self.context.name
    title = title .. " |cffaaaaaa(" .. self:GetDifficultyLabel(self.context.difficulty) .. ")|r"
    if self.frame.legacyTitle ~= title then
        self.frame.legacyTitle = title
        self.frame:SetHeader(title)
    end
    local earned, total, partial = self:GetTotals()
    local totalText = string.format("%d/%d%s", earned, total, partial and "*" or "")
    if self.frame.legacyTotal ~= totalText then
        self.frame.legacyTotal = totalText
        self.frame.Header.Total:SetText(totalText)
    end
end

function Module:ShowEntryTooltip(owner, entry)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if entry.item and entry.item.link then GameTooltip:SetHyperlink(entry.item.link)
    elseif entry.kind == "achievements" and GetAchievementLink then
        local link = GetAchievementLink(entry.id)
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(entry.name) end
    end
    if entry.kind == "achievements" then
        GameTooltip:AddLine("Related achievement - verify difficulty and requirements.", 1, 0.82, 0, true)
    end
    if entry.owned == nil then GameTooltip:AddLine("Collection status unavailable.", 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end

function Module:OpenEntry(entry)
    if not entry or InCombatLockdown() then return end
    if entry.kind == "achievements" and C_AddOns then
        C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        if AchievementFrame_SelectAchievement then
            ShowUIPanel(AchievementFrame)
            AchievementFrame_SelectAchievement(entry.id)
        end
    elseif entry.item and entry.item.link and IsModifiedClick and IsModifiedClick() then
        HandleModifiedItemClick(entry.item.link)
    end
end

local function LineEnter(line)
    if line.legacyEntry then Module:ShowEntryTooltip(line, line.legacyEntry) end
end
local function LineLeave() GameTooltip:Hide() end
local function LineClick(line, button)
    if line.legacyClick then line.legacyClick(button) else Module:OpenEntry(line.legacyEntry) end
end
local function FreeLine(line)
    line.legacyEntry, line.legacyClick = nil, nil
end

-- A private template allows handlers to be installed once per pooled line.
function Module:BindLine(line, entry, onClick)
    line.legacyEntry, line.legacyClick = entry, onClick
    if line.legacyBound then return end
    line.legacyBound = true
    line:EnableMouse(true)
    line:SetScript("OnEnter", LineEnter)
    line:SetScript("OnLeave", LineLeave)
    line:SetScript("OnMouseUp", LineClick)
    line.OnFree = FreeLine
end

function Module:Layout(frame)
    if not self.context or not self.counts then return end
    self:UpdateHeader()
    if frame:IsCollapsed() then
        -- Native LayoutBlock records module contents, but does not add a block
        -- when collapsed. Do not measure hidden expanded rows or reserve overflow.
        local block = frame:GetBlock("collapsed")
        block.legacyGroup = nil
        block:SetHeader("")
        block.height = 0
        frame:LayoutBlock(block)
        return
    end
    if #self.groups == 0 then
        local block = frame:GetBlock("empty")
        block.legacyGroup = nil
        block:SetHeader(self.status or ((not self.snapshot or self.ownershipTicker) and "Loading..." or "All tracked entries collected"))
        frame:LayoutBlock(block)
        return
    end
    for index = self.firstGroup, #self.groups do
        local group = self.groups[index]
        local block = frame:GetBlock("group:" .. group.id)
        block.legacyGroup = group
        local collapsed = self.collapsedGroups[group.id]
        block:SetHeader((group.defeated and "|cff80ff80" or "") .. group.name
            .. (group.defeated and "|r" or "") .. (collapsed and " |cffaaaaaa+|r" or " |cffaaaaaa-|r"))
        if not block.CategoryIcon then
            block.CategoryPuck = block:CreateTexture(nil, "BACKGROUND")
            block.CategoryPuck:SetAtlas("UI-QuestPoi-QuestNumber")
            block.CategoryPuck:SetSize(26, 26)
            block.CategoryPuck:SetPoint("RIGHT", block.HeaderText, "LEFT", -2, 0)
            block.CategoryIcon = block:CreateTexture(nil, "ARTWORK")
            block.CategoryIcon:SetSize(16, 16)
            block.CategoryIcon:SetPoint("CENTER", block.CategoryPuck, "CENTER")
            block.CategoryMask = block:CreateMaskTexture()
            block.CategoryMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            block.CategoryMask:SetAllPoints(block.CategoryIcon)
            block.CategoryIcon:AddMaskTexture(block.CategoryMask)
        end
        if group.defeated then
            block.CategoryIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            block.CategoryIcon:SetTexCoord(0, 1, 0, 1)
        else
            block.CategoryIcon:SetTexture(group.icon or "Interface\\Icons\\INV_Misc_Map_01")
            block.CategoryIcon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)
        end
        block.CategoryPuck:Show()
        block.CategoryIcon:Show()
        if not frame:CanFitBlock(block) then return end
        if not collapsed then
            local first = self.groupOffsets[group.id] or 1
            if first > #group.rows then first = 1 end
            local last = first - 1
            for rowIndex = first, math.min(#group.rows, first + GROUP_PAGE_SIZE - 1) do
                local row = group.rows[rowIndex]
                local previousHeight, previousRegion = block.height, block.lastRegion
                local line = block:AddObjective("entry:" .. rowIndex, row.text, LINE_TEMPLATE, false, OBJECTIVE_DASH_STYLE_SHOW)
                -- Reserve a compact 'more' row when this group continues.
                local reserve = (rowIndex < #group.rows or first > 1) and 22 or 0
                block.height = block.height + reserve
                local fits = frame:CanFitBlock(block)
                block.height = block.height - reserve
                if not fits then
                    line.used = nil
                    block.height, block.lastRegion = previousHeight, previousRegion
                    break
                end
                self:BindLine(line, row.entry)
                last = rowIndex
            end
            if last < #group.rows or first > 1 then
                local text = last < #group.rows and string.format("|cffaaaaaa+ %d more|r", #group.rows - last) or "|cffaaaaaaBack to first items|r"
                local previousHeight, previousRegion = block.height, block.lastRegion
                local line = block:AddObjective("more", text, LINE_TEMPLATE, false, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE)
                if frame:CanFitBlock(block) then
                    self:BindLine(line, nil, function(button)
                        if button == "RightButton" or last >= #group.rows then self.groupOffsets[group.id] = 1
                        else self.groupOffsets[group.id] = math.max(first + 1, last + 1) end
                        self.firstGroup = index
                        frame:MarkDirty()
                    end)
                else
                    line.used = nil
                    block.height, block.lastRegion = previousHeight, previousRegion
                end
            end
        end
        if not frame:LayoutBlock(block) then return end
    end
end

function Module:ShowNavigation(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(self.context.name)
        root:CreateButton("Show all bosses", function()
            self.firstGroup, self.groupOffsets = 1, {}
            self.frame:MarkDirty()
        end)
        for index, group in ipairs(self.groups or {}) do
            local target, id = index, group.id
            root:CreateButton(group.name, function()
                self.firstGroup = target
                self.groupOffsets[id] = nil
                self:ExpandGroup(id)
                self:Reflow()
            end)
        end
        self:AddSettings(root)
    end)
end

function Module:EnsureFrame()
    if InCombatLockdown() then return end
    if not (ObjectiveTrackerManager and ObjectiveTrackerModuleMixin and ObjectiveTrackerFrame) then return end
    if not self.frame then
        local frame = CreateFrame("Frame", "RefineUI_LegacyCompletionistTracker", UIParent, "ObjectiveTrackerModuleTemplate")
        self.frame = frame
        frame.blockTemplate = "RefineUICompletionistBlockTemplate"
        frame.uiOrder, frame.headerHeight, frame.lineSpacing = 0, 25, 3
        frame.Header:SetHeight(26)
        local total = frame.Header:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
        frame.Header.Total = total
        total:SetPoint("RIGHT", frame.Header.MinimizeButton, "LEFT", -7, 0)
        total:SetJustifyH("RIGHT")
        -- The template's AutoScalingFontString shrinks long instance titles.
        -- Use an ordinary font string with the native anchor/font instead, so
        -- overflow truncates without changing the tracker header's typography.
        local originalText = frame.Header.Text
        local point, relativeTo, relativePoint, x, y = originalText:GetPoint(1)
        originalText:Hide()
        local title = frame.Header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
        title:SetPoint(point, relativeTo, relativePoint, x, y)
        title:SetPoint("RIGHT", total, "LEFT", -7, 0)
        title:SetJustifyH("LEFT")
        title:SetMaxLines(1)
        title:SetWordWrap(false)
        title:SetNonSpaceWrap(false)
        frame.Header.Text = title
        frame.LayoutContents = function(f) self:Layout(f) end
        frame.OnFreeBlock = function(_, block)
            block.legacyGroup = nil
            if block.CategoryIcon then block.CategoryIcon:Hide() end
            if block.CategoryPuck then block.CategoryPuck:Hide() end
        end
        hooksecurefunc(frame, "SetCollapsed", function() self:Reflow() end)
        frame.OnBlockHeaderClick = function(_, block)
            if block.legacyGroup then
                local id = block.legacyGroup.id
                if self.collapsedGroups[id] then self:ExpandGroup(id)
                else
                    self.collapsedGroups[id] = true
                    if self.activeGroup == id then self.activeGroup = nil end
                end
                self:Reflow()
            end
        end
        frame.OnBlockHeaderEnter = function(_, block)
            local group = block.legacyGroup
            if not group then return end
            GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
            GameTooltip:SetText(group.name)
            if group.defeated then GameTooltip:AddLine("Defeated", 0.5, 1, 0.5) end
            GameTooltip:AddLine("Click to collapse or expand.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
        frame.OnBlockHeaderLeave = function() GameTooltip:Hide() end
        frame.Header:EnableMouse(true)
        frame.Header:SetScript("OnMouseUp", function(header, button)
            if button == "RightButton" and self.context then self:ShowNavigation(header) end
        end)
        frame.Header:SetScript("OnEnter", function(header)
            if not self.context then return end
            GameTooltip:SetOwner(header, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.context.name .. " - " .. (self.context.difficultyName or ""))
            GameTooltip:AddLine("Collected / total tracked items and achievements. Shared rewards count once.", 1, 1, 1, true)
            GameTooltip:AddLine("Related achievements may require another difficulty. Recipes, hidden drops and token unlocks are excluded.", 1, 0.82, 0, true)
            local _, _, partial = self:GetTotals()
            if partial then GameTooltip:AddLine("* Some data or collection states are unavailable or still loading.", 0.7, 0.7, 0.7, true) end
            if self.status then GameTooltip:AddLine(self.status, 0.7, 0.7, 0.7, true) end
            GameTooltip:AddLine("Right-click to jump to a boss.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        frame.Header:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local quests = RefineUI:GetModule("Quests")
        if RefineUI.Config.Quests.HeaderSkinning and quests then
            frame.Header.Background:Hide()
            quests:SkinHeader(frame.Header)
        end
    end
    self:UpdateHeader()
    if not ObjectiveTrackerFrame:HasModule(self.frame) then
        ObjectiveTrackerManager:SetModuleContainer(self.frame, ObjectiveTrackerFrame)
    end
    if _G.EncounterJournal and not self.journalHooked then
        self.journalHooked = true
        _G.EncounterJournal:HookScript("OnHide", function()
            if self.context and self.rescan then self:Schedule(true) end
            if self.context and self.completionDirty then self:Schedule(nil, true) end
        end)
    end
end
