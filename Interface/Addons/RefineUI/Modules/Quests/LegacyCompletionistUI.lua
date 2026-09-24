local _, RefineUI = ...
local Module = RefineUI:GetModule("LegacyCompletionist")
local GROUP_PAGE_SIZE = 6
local LINE_TEMPLATE = "RefineUICompletionistLineTemplate"
local BLOCK_TEMPLATE = "RefineUICompletionistBlockTemplate"
local FALLBACK_ICON = 134400
local PANEL_SPACING = 10
local PANEL_SCREEN_MARGIN = 10

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
            elseif key ~= "HideCollected" and cfg[key] then self:Schedule()
            else self:BuildView(); self:Reflow() end
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
    local previousGroups = self.groups or {}
    for _, kind in ipairs(self.KINDS) do counts[kind] = { total = 0, earned = 0, unknown = 0 } end
    local groups = { { id = 0, name = "Instance", entries = {}, rows = {}, earned = 0, total = 0 } }
    local byBoss, byName = { [0] = groups[1] }, {}
    for _, boss in ipairs(self.bosses or {}) do
        local group = { id = boss.id, name = boss.name, icon = boss.icon, entries = {}, rows = {},
            defeated = self.defeated[boss.id], earned = 0, total = 0 }
        groups[#groups + 1], byBoss[boss.id] = group, group
        byName[boss.name:lower()] = group
    end
    local function Add(entry)
        if cfg[entry.kind] == false then return end
        local count = counts[entry.kind]
        count.total = count.total + 1
        if entry.owned == true then count.earned = count.earned + 1
        elseif entry.owned == nil then count.unknown = count.unknown + 1 end
        local showEntry = cfg.HideCollected == false or entry.owned ~= true
        local assigned = false
        for bossID in pairs(entry.bosses) do
            local group = byBoss[bossID]
            if group then
                group.total = group.total + 1
                if entry.owned == true then group.earned = group.earned + 1 end
                if showEntry then group.entries[#group.entries + 1] = entry end
                assigned = true
            end
        end
        if not assigned then
            local group = groups[1]
            group.total = group.total + 1
            if entry.owned == true then group.earned = group.earned + 1 end
            if showEntry then group.entries[#group.entries + 1] = entry end
        end
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
        group.expandable = #group.rows > 0 and (group.id == 0 or group.earned < group.total)
        if group.id ~= 0 or #group.rows > 0 then visibleGroups[#visibleGroups + 1] = group end
    end
    local layoutChanged = #previousGroups ~= #visibleGroups
    if not layoutChanged then
        for index, group in ipairs(visibleGroups) do
            local previous = previousGroups[index]
            if previous.id ~= group.id or previous.name ~= group.name or previous.icon ~= group.icon
                or previous.defeated ~= group.defeated
                or previous.total ~= group.total or previous.earned ~= group.earned
                or previous.expandable ~= group.expandable or #previous.rows ~= #group.rows then
                layoutChanged = true
                break
            end
            for rowIndex, row in ipairs(group.rows) do
                local previousRow = previous.rows[rowIndex]
                if previousRow.text ~= row.text or previousRow.entry.key ~= row.entry.key
                    or (previousRow.entry.item and previousRow.entry.item.link) ~= (row.entry.item and row.entry.item.link) then
                    layoutChanged = true
                    break
                end
            end
            if layoutChanged then break end
        end
    end
    self.rows, self.counts, self.groups, self.groupsByName = rows, counts, visibleGroups, byName
    self.firstGroup = math.min(self.firstGroup or 1, math.max(1, #visibleGroups))
    self.groupOffsets, self.collapsedGroups = self.groupOffsets or {}, self.collapsedGroups or {}
    local collapseChanged = self:ApplyAutoCollapse()
    local statusChanged = self.viewStatus ~= self.status
    self.viewStatus = self.status
    self:UpdateHeader()
    if layoutChanged or collapseChanged or statusChanged then self:Reflow() end
end

-- The panel is a private tracker module outside Blizzard's container; it never
-- touches Blizzard tracker frames or state.
function Module:Reflow()
    if not self.frame then return end
    RefineUI:Debounce("LegacyCompletionist:Panel", 0, function() self:UpdatePanel() end)
end

function Module:UpdatePanel()
    local frame, tracker = self.frame, ObjectiveTrackerFrame
    if not frame then return end
    if not self.context or not self.counts then frame:Hide(); return end
    frame:SetScale(tracker:GetEffectiveScale() / UIParent:GetEffectiveScale())
    frame:ClearAllPoints()
    local top
    if tracker:IsVisible() and tracker.NineSlice:IsShown() then
        frame:SetPoint("TOP", tracker.NineSlice, "BOTTOM", 0, -PANEL_SPACING)
        top = tracker.NineSlice:GetBottom() - PANEL_SPACING
    else
        frame:SetPoint("TOP", tracker, "TOP")
        top = tracker:GetTop()
    end
    frame:SetPoint("LEFT", tracker, "LEFT")
    -- Legacy content used to take priority inside the tracker; keep it visible
    -- when tracked quests fill the Edit Mode box by allowing the screen below.
    frame:Update(math.max(0, top - PANEL_SCREEN_MARGIN))
end

function Module:ToggleGroup(id)
    if self.collapsedGroups[id] then self:ExpandGroup(id)
    else
        self.collapsedGroups[id] = true
        if self.activeGroup == id then self.activeGroup = nil end
    end
    self:Reflow()
end

function Module:ApplyAutoCollapse()
    if self:GetSettings().AutoCollapse == false then self.advanceAfterBoss = nil; return end
    local changed = false
    -- Achievement discovery can finish before boss loot/ownership. Do not latch
    -- the first achievement-bearing boss while earlier bosses are still loading.
    local initialDataReady = self.snapshot and not self.scan and not self.ownershipTicker
        and not self.snapshot.unknownData
        and (self:GetSettings().achievements == false or self.achievementRows ~= nil)
    if not self.autoCollapseInitialized and not initialDataReady then
        self.activeGroup = nil
        for _, group in ipairs(self.groups) do
            if self.collapsedGroups[group.id] ~= true then changed = true end
            self.collapsedGroups[group.id] = true
        end
        return changed
    end
    local byID = {}
    for _, group in ipairs(self.groups) do
        byID[group.id] = group
    end
    local activeExists = self.activeGroup and byID[self.activeGroup] and byID[self.activeGroup].expandable
    if not self.autoCollapseInitialized or self.advanceAfterBoss or (self.activeGroup and not activeExists) then
        local nextID, after = nil, self.advanceAfterBoss == nil
        for _, boss in ipairs(self.bosses or {}) do
            if boss.id == self.advanceAfterBoss then
                after = true
            elseif after then
                local group = byID[boss.id]
                if group and not group.defeated and group.expandable then nextID = group.id end
            end
            if nextID then break end
        end
        if not nextID then
            for _, group in ipairs(self.groups) do
                if not group.defeated and group.expandable then nextID = group.id; break end
            end
        end
        self.activeGroup = nextID
        self.autoCollapseInitialized = #self.groups > 0
        self.advanceAfterBoss, self.firstGroup = nil, 1
    end
    for _, group in ipairs(self.groups) do
        local collapsed = group.id ~= self.activeGroup
        if self.collapsedGroups[group.id] ~= collapsed then changed = true end
        self.collapsedGroups[group.id] = collapsed
    end
    return changed
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
    local totalText = ""
    if self.snapshot then
        local earned, total, partial = self:GetTotals()
        totalText = string.format("%d/%d%s", earned, total, partial and "*" or "")
    end
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
        if not self:LayoutGroup(frame, index, self.groups[index]) then return end
    end
end

function Module:LayoutGroup(frame, index, group)
    local block = frame:GetBlock("group:" .. group.id)
    block.legacyGroup = group
    local collapsed = self.collapsedGroups[group.id]
    local missing = group.total - group.earned
    local count = group.id ~= 0 and missing > 0 and string.format(" (%d)", missing) or ""
    block:SetHeader((group.id ~= 0 and (group.defeated and "|cff80ff80" or "|cffffd100") or "") .. group.name .. count
        .. (group.id ~= 0 and "|r" or "")
        .. (not group.expandable and "" or (collapsed and " |cffaaaaaa+|r" or " |cffaaaaaa-|r")))
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
    if not frame:CanFitBlock(block) then return false end
    if group.expandable and not collapsed then
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
    return frame:LayoutBlock(block)
end

function Module:ShowNavigation(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(self.context.name)
        root:CreateButton("Show all bosses", function()
            self.firstGroup, self.groupOffsets = 1, {}
            self.frame:MarkDirty()
        end)
        for index, group in ipairs(self.groups or {}) do
            local target, id, expandable = index, group.id, group.expandable
            root:CreateButton(group.name, function()
                self.firstGroup = target
                self.groupOffsets[id] = nil
                if expandable then self:ExpandGroup(id) end
                self:Reflow()
            end)
        end
        self:AddSettings(root)
    end)
end

-- Blizzard's module/block mixins acquire from ObjectiveTrackerManager's shared
-- pools. The panel owns its pools so none of its frames enter Blizzard state.
local function AcquirePanelFrame(module, template)
    local pool = module.legacyPools[template]
    if not pool then
        pool = CreateFramePool("Frame", module.ContentsFrame, template)
        module.legacyPools[template] = pool
    end
    local frame, isNew = pool:Acquire()
    if isNew then frame.template = template end
    return frame, isNew
end

local function GetPanelLine(block, objectiveKey, template)
    template = template or block.parentModule.lineTemplate
    local line = block.usedLines[objectiveKey]
    if line and line.template ~= template then
        block:FreeLine(line)
        line = nil
    end
    if not line then
        line = AcquirePanelFrame(block.parentModule, template)
        line:SetParent(block)
        line:Show()
    end
    block.usedLines[objectiveKey] = line
    line.objectiveKey, line.parentBlock, line.used = objectiveKey, block, true
    return line
end

local function FreePanelLine(block, line)
    block.usedLines[line.objectiveKey] = nil
    block.parentModule.legacyPools[line.template]:Release(line)
    line:Hide()
    if line.OnFree then line:OnFree(block) end
end

local function AcquirePanelBlock(module, template)
    local block, isNew = AcquirePanelFrame(module, template)
    block:SetParent(module.ContentsFrame)
    if isNew then block.GetLine, block.FreeLine = GetPanelLine, FreePanelLine end
    return block, isNew
end

local function FreePanelBlock(module, block)
    module:RemoveBlockFromCache(block, true)
    block:Free()
    module.usedBlocks[block.template][block.id] = nil
    module.legacyPools[block.template]:Release(block)
    module:OnFreeBlock(block)
end

function Module:EnsureFrame()
    if _G.EncounterJournal and not self.journalHooked then
        self.journalHooked = true
        _G.EncounterJournal:HookScript("OnHide", function()
            if self.context and self.rescan then self:Schedule(true) end
            if self.context and self.completionDirty then self:Schedule(nil, true) end
        end)
    end
    if not self.context or not ObjectiveTrackerFrame then return end
    if not self.frame then
        local tracker = ObjectiveTrackerFrame
        local frame = CreateFrame("Frame", "RefineUI_LegacyCompletionistTracker", UIParent, "ObjectiveTrackerModuleTemplate")
        self.frame = frame
        frame:Hide()
        frame:SetFrameStrata(tracker:GetFrameStrata())
        frame.blockTemplate, frame.lineTemplate = BLOCK_TEMPLATE, LINE_TEMPLATE
        frame.headerHeight, frame.lineSpacing = 25, 3
        frame.legacyPools = {}
        frame.AcquireFrame, frame.FreeBlock = AcquirePanelBlock, FreePanelBlock
        -- Stands in for a Blizzard container: follows the tracker's collapse
        -- state and routes module MarkDirty calls to the panel's own layout.
        frame.parentContainer = {
            IsCollapsed = function() return tracker:IsCollapsed() end,
            MarkDirty = function() self:Reflow() end,
        }
        local function Reflow() self:Reflow() end
        RefineUI:HookScriptOnce("LegacyCompletionist:TrackerSize", tracker.NineSlice, "OnSizeChanged", Reflow)
        RefineUI:HookScriptOnce("LegacyCompletionist:TrackerShow", tracker, "OnShow", Reflow)
        RefineUI:HookScriptOnce("LegacyCompletionist:TrackerHide", tracker, "OnHide", Reflow)
        RefineUI:HookOnce("LegacyCompletionist:TrackerCollapsed", tracker, "SetCollapsed", Reflow)
        frame.Header:SetHeight(26)
        local total = frame.Header:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
        frame.Header.Total = total
        total:SetPoint("RIGHT", frame.Header.MinimizeButton, "LEFT", -7, 0)
        total:SetJustifyH("RIGHT")
        frame:SetHeader("Collection")
        frame.LayoutContents = function(f) self:Layout(f) end
        frame.OnFreeBlock = function(_, block)
            block.legacyGroup = nil
            if block.CategoryIcon then block.CategoryIcon:Hide() end
            if block.CategoryPuck then block.CategoryPuck:Hide() end
        end
        frame.OnBlockHeaderClick = function(_, block)
            if block.legacyGroup and block.legacyGroup.expandable then self:ToggleGroup(block.legacyGroup.id) end
        end
        frame.OnBlockHeaderEnter = function(_, block)
            local group = block.legacyGroup
            if not group then return end
            GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
            GameTooltip:SetText(group.name)
            if group.defeated then GameTooltip:AddLine("Defeated", 0.5, 1, 0.5) end
            if group.expandable then GameTooltip:AddLine("Click to collapse or expand.", 0.7, 0.7, 0.7) end
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
    self:Reflow()
end
