----------------------------------------------------------------------------------------
-- LootRules Component: UI
-- Description: Manager window construction, layout, and interaction bindings.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local LootRules = RefineUI:GetModule("LootRules")
if not LootRules then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = UIParent
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT

local tinsert = table.insert
local pairs = pairs
local type = type
local max = math.max

local STAGE_LOOT = LootRules.STAGE_LOOT or "LOOT"
local STAGE_SELL = LootRules.STAGE_SELL or "SELL"

local STAGE_LABEL = LootRules.STAGE_LABELS or {
    [STAGE_LOOT] = "Loot",
    [STAGE_SELL] = "Sell",
}

local STAGE_COLOR = {
    [STAGE_LOOT] = { 0.52, 0.8, 1.0 },
    [STAGE_SELL] = { 0.58, 0.95, 0.62 },
}

local RULE_ROW_HEIGHT = 36
local RULE_ROW_SPACING = 1
local STAGE_HEADER_HEIGHT = 26
local STAGE_HEADER_SPACING = 8
local STAGE_COLUMNS_HEIGHT = 16
local GROUP_HEADER_HEIGHT = 20
local GROUP_HEADER_SPACING = 4
local GROUP_SECTION_SPACING = 10
local MAX_GROUP_HEADERS = 2
local MAX_VISIBLE_ROWS = 24
local NAME_COLUMN_WIDTH = 260
local TOGGLE_COLUMN_WIDTH = 58
local OPTIONS_COLUMN_WIDTH = NAME_COLUMN_WIDTH
local ROW_LEFT_MARGIN = 8
local ROW_GAP_NAME_TO_OPTIONS = 12
local ROW_GAP_OPTIONS_TO_TOGGLE = 12
local ROW_RIGHT_TOGGLE_MARGIN = 4
local ROW_TARGET_WIDTH = ROW_LEFT_MARGIN
    + NAME_COLUMN_WIDTH
    + ROW_GAP_NAME_TO_OPTIONS
    + OPTIONS_COLUMN_WIDTH
    + ROW_GAP_OPTIONS_TO_TOGGLE
    + TOGGLE_COLUMN_WIDTH
    + ROW_RIGHT_TOGGLE_MARGIN
local WINDOW_RULE_INSETS = 16
local WINDOW_SCROLL_OVERHEAD_MODERN = 48
local WINDOW_SCROLL_OVERHEAD_CLASSIC = 62
local WINDOW_FIXED_WIDTH_MODERN = ROW_TARGET_WIDTH + WINDOW_RULE_INSETS + WINDOW_SCROLL_OVERHEAD_MODERN
local WINDOW_FIXED_WIDTH_CLASSIC = ROW_TARGET_WIDTH + WINDOW_RULE_INSETS + WINDOW_SCROLL_OVERHEAD_CLASSIC

local ENABLED_BG = { 0.09, 0.19, 0.13, 0.78 }
local DISABLED_BG = { 0.22, 0.1, 0.11, 0.72 }
local ENABLED_TEXT = { 0.58, 0.95, 0.62 }
local DISABLED_TEXT = { 0.96, 0.6, 0.6 }
local ENABLED_BORDER = { 0.34, 0.56, 0.38, 0.65 }
local DISABLED_BORDER = { 0.6, 0.34, 0.34, 0.55 }
local HIGHLIGHT_BORDER = { 1, 0.82, 0.2, 0.95 }

local WINDOW_MIN_HEIGHT = 260
local WINDOW_DEFAULT_HEIGHT = 420
local WINDOW_CHROME_HEIGHT = 92
local WINDOW_MAX_SCREEN_MARGIN = 120
local WINDOW_ANCHOR_GAP = 8

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local managerFrames = {}

local RefreshManagerUI
local HandleListMouseWheel

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetWindowFixedWidth(hasModernScroll)
    if hasModernScroll then
        return WINDOW_FIXED_WIDTH_MODERN
    end
    return WINDOW_FIXED_WIDTH_CLASSIC
end

local function ClampWindowHeight(height)
    local target = height or WINDOW_DEFAULT_HEIGHT
    if target < WINDOW_MIN_HEIGHT then
        target = WINDOW_MIN_HEIGHT
    end
    local maxHeight = (UIParent and UIParent.GetHeight and UIParent:GetHeight() or 1080) - WINDOW_MAX_SCREEN_MARGIN
    if maxHeight < WINDOW_MIN_HEIGHT then
        maxHeight = WINDOW_MIN_HEIGHT
    end
    if target > maxHeight then
        target = maxHeight
    end
    return target
end

local function FitWindowToContent(window, contentHeight)
    if not window then
        return
    end
    local fixedWidth = window._fixedWidth or WINDOW_FIXED_WIDTH_MODERN
    local targetHeight = ClampWindowHeight((contentHeight or 0) + WINDOW_CHROME_HEIGHT)
    window:SetSize(fixedWidth, targetHeight)
end

local function NormalizeStage(stage)
    if stage == STAGE_SELL then
        return STAGE_SELL
    end
    return STAGE_LOOT
end

local function IsSellFilterRuleID(ruleID)
    if type(ruleID) ~= "string" then
        return false
    end
    return ruleID:find("^sell_filter_") ~= nil
end

local function IsLootFilterRuleID(ruleID)
    if type(ruleID) ~= "string" then
        return false
    end
    return ruleID:find("^loot_filter_") ~= nil
end

local function BuildStageDisplayGroups(stage, entries)
    local groups = {}

    if stage == STAGE_SELL or stage == STAGE_LOOT then
        local rulesGroup = {
            title = "Rules",
            description = "Run first and override filters.",
            entries = {},
        }
        local filterDescription = "AND: all enabled filters must match."
        if stage == STAGE_LOOT then
            filterDescription = "AND: all enabled filters must match to skip."
        end
        local filtersGroup = {
            title = "Filters",
            description = filterDescription,
            entries = {},
        }

        for stagePos = 1, #entries do
            local entry = entries[stagePos]
            local wrapped = {
                entry = entry,
                stagePos = stagePos,
            }

            local ruleID = entry and entry.rule and entry.rule.id
            local isFilter = (stage == STAGE_SELL and IsSellFilterRuleID(ruleID))
                or (stage == STAGE_LOOT and IsLootFilterRuleID(ruleID))
            if isFilter then
                tinsert(filtersGroup.entries, wrapped)
            else
                tinsert(rulesGroup.entries, wrapped)
            end
        end

        groups[1] = rulesGroup
        groups[2] = filtersGroup
        return groups
    end

    local singleGroup = {
        entries = {},
    }
    for stagePos = 1, #entries do
        singleGroup.entries[#singleGroup.entries + 1] = {
            entry = entries[stagePos],
            stagePos = stagePos,
        }
    end
    groups[1] = singleGroup

    return groups
end

local function GetManagerFrameName(stage)
    if stage == STAGE_SELL then
        return "RefineUI_SellRulesWindow"
    end
    return "RefineUI_LootRulesWindow"
end

local function UpdateRowVisual(row, enabled, isDropTarget)
    if not row or not row.bg or not row.title then return end

    local bg = enabled and ENABLED_BG or DISABLED_BG
    local text = enabled and ENABLED_TEXT or DISABLED_TEXT
    local border = enabled and ENABLED_BORDER or DISABLED_BORDER
    local sepAlpha = enabled and 0.4 or 0.3

    if isDropTarget then
        row.bg:SetColorTexture(0.95, 0.8, 0.15, 0.78)
        row.title:SetTextColor(1, 0.95, 0.75)
        row.summary:SetTextColor(1, 0.92, 0.72)
        if row.SepName and row._hasOptions then
            row.SepName:SetColorTexture(1, 0.9, 0.45, 0.7)
            row.SepName:Show()
        elseif row.SepName then
            row.SepName:Hide()
        end
        if row.SepToggle then
            row.SepToggle:SetColorTexture(1, 0.9, 0.45, 0.7)
        end
        row.border:SetBackdropBorderColor(HIGHLIGHT_BORDER[1], HIGHLIGHT_BORDER[2], HIGHLIGHT_BORDER[3], HIGHLIGHT_BORDER[4])
        return
    end

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    row.title:SetTextColor(text[1], text[2], text[3], 1)
    row.summary:SetTextColor(text[1], text[2], text[3], 0.82)
    if row.SepName and row._hasOptions then
        row.SepName:SetColorTexture(border[1], border[2], border[3], sepAlpha)
        row.SepName:Show()
    elseif row.SepName then
        row.SepName:Hide()
    end
    if row.SepToggle then
        row.SepToggle:SetColorTexture(border[1], border[2], border[3], sepAlpha)
    end
    row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function CreateRuleRow(window, parent)
    local row = CreateFrame("Button", nil, parent)
    row._window = window
    row:SetHeight(RULE_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetAllPoints()
    row.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    row.NameColumn = CreateFrame("Frame", nil, row)
    row.NameColumn:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_LEFT_MARGIN, -2)
    row.NameColumn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ROW_LEFT_MARGIN, 2)
    row.NameColumn:SetWidth(NAME_COLUMN_WIDTH)

    row.ToggleColumn = CreateFrame("Frame", nil, row)
    row.ToggleColumn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
    row.ToggleColumn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)
    row.ToggleColumn:SetWidth(TOGGLE_COLUMN_WIDTH)

    row.SepName = row:CreateTexture(nil, "BORDER")
    row.SepName:SetWidth(1)
    row.SepName:SetPoint("TOPLEFT", row.NameColumn, "TOPRIGHT", 6, -4)
    row.SepName:SetPoint("BOTTOMLEFT", row.NameColumn, "BOTTOMRIGHT", 6, 4)

    row.SepToggle = row:CreateTexture(nil, "BORDER")
    row.SepToggle:SetWidth(1)
    row.SepToggle:SetPoint("TOPRIGHT", row.ToggleColumn, "TOPLEFT", -6, -4)
    row.SepToggle:SetPoint("BOTTOMRIGHT", row.ToggleColumn, "BOTTOMLEFT", -6, 4)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetParent(row.NameColumn)
    row.title:SetPoint("TOPLEFT", row.NameColumn, "TOPLEFT", 0, 0)
    row.title:SetPoint("TOPRIGHT", row.NameColumn, "TOPRIGHT", 0, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetJustifyV("TOP")
    if row.title.SetMaxLines then
        row.title:SetMaxLines(1)
    end

    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.summary:SetParent(row.NameColumn)
    row.summary:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.summary:SetPoint("BOTTOMRIGHT", row.NameColumn, "BOTTOMRIGHT", 0, 0)
    row.summary:SetJustifyH("LEFT")
    row.summary:SetJustifyV("TOP")
    if row.summary.SetWordWrap then
        row.summary:SetWordWrap(false)
    end
    if row.summary.SetMaxLines then
        row.summary:SetMaxLines(1)
    end

    row.check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
    row.check:SetParent(row.ToggleColumn)
    row.check:SetPoint("CENTER", row.ToggleColumn, "CENTER", 0, -1)
    row.check:SetSize(30, 30)
    if row.check.Text then
        row.check.Text:Hide()
    end
    row.check._ownerRow = row

    row.OptionsHost = CreateFrame("Frame", nil, row)
    row.OptionsHost:SetPoint("TOPRIGHT", row.ToggleColumn, "TOPLEFT", -12, -2)
    row.OptionsHost:SetPoint("BOTTOMRIGHT", row.ToggleColumn, "BOTTOMLEFT", -12, 2)
    row.OptionsHost:SetWidth(OPTIONS_COLUMN_WIDTH)
    row.OptionsHost:SetHeight(44)
    row.OptionsHost:SetClipsChildren(true)
    row._optionColumnWidth = OPTIONS_COLUMN_WIDTH

    row.check:SetScript("OnClick", function(self)
        local owner = self._ownerRow
        if not owner or not owner.ruleRef then return end

        owner.ruleRef.enabled = self:GetChecked() and true or false
        if LootRules.SortStageRulesEnabledFirst then
            LootRules:SortStageRulesEnabledFirst(owner.stage)
        end
        if PlaySound and SOUNDKIT then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        RefreshManagerUI(owner._window)
    end)

    return row
end

local function CreateStageHeader(parent)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(STAGE_HEADER_HEIGHT)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.09, 0.12, 0.17, 0.86)
    header:SetBackdropBorderColor(0.3, 0.39, 0.52, 0.65)

    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.label:SetJustifyH("LEFT")

    header.meta = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.meta:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    header.meta:SetJustifyH("RIGHT")
    header.meta:SetTextColor(0.82, 0.82, 0.82)

    return header
end

local function CreateRuleGroupHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(GROUP_HEADER_HEIGHT)

    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.label:SetPoint("LEFT", header, "LEFT", ROW_LEFT_MARGIN, 0)
    header.label:SetJustifyH("LEFT")

    header.detail = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.detail:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    header.detail:SetJustifyH("RIGHT")

    header.line = header:CreateTexture(nil, "BORDER")
    header.line:SetHeight(1)
    header.line:SetPoint("LEFT", header, "LEFT", ROW_LEFT_MARGIN + 118, 0)
    header.line:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    header.line:SetColorTexture(0.36, 0.44, 0.6, 0.55)

    return header
end

local function CreateStageSection(parent)
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if RefineUI.SetTemplate then
        RefineUI.SetTemplate(section, "Transparent")
    else
        section:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        section:SetBackdropColor(0.07, 0.1, 0.14, 0.72)
        section:SetBackdropBorderColor(0.28, 0.36, 0.5, 0.7)
    end

    section.Inner = section:CreateTexture(nil, "ARTWORK")
    section.Inner:SetPoint("TOPLEFT", section, "TOPLEFT", 2, -2)
    section.Inner:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -2, 2)
    section.Inner:SetColorTexture(0.05, 0.08, 0.12, 0.22)

    section.Columns = CreateFrame("Frame", nil, section, "BackdropTemplate")
    section.Columns:SetHeight(STAGE_COLUMNS_HEIGHT)
    section.Columns:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    section.Columns:SetBackdropColor(0.09, 0.12, 0.16, 0.72)
    section.Columns:SetBackdropBorderColor(0.3, 0.37, 0.5, 0.55)

    section.Columns.Rule = section.Columns:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    section.Columns.Rule:SetPoint("LEFT", section.Columns, "LEFT", ROW_LEFT_MARGIN, 0)
    section.Columns.Rule:SetText("Rule")

    section.Columns.Options = section.Columns:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    section.Columns.Options:SetPoint("LEFT", section.Columns, "LEFT", ROW_LEFT_MARGIN + NAME_COLUMN_WIDTH + ROW_GAP_NAME_TO_OPTIONS, 0)
    section.Columns.Options:SetText("Options")

    section.Columns.Toggle = section.Columns:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    section.Columns.Toggle:SetPoint("RIGHT", section.Columns, "RIGHT", -8, 0)
    section.Columns.Toggle:SetText("Enable")

    return section
end

local function EnsureRowPool(window, needed)
    if not window or not window.Rows then return end
    if not needed or needed < 1 then needed = 1 end

    while #window.Rows < needed do
        window.Rows[#window.Rows + 1] = CreateRuleRow(window, window.Content)
    end
end

HandleListMouseWheel = function(window, delta)
    if not window or not window.Scroll then
        return
    end

    local step = (RULE_ROW_HEIGHT + RULE_ROW_SPACING) * 2
    local scroll = window.Scroll

    if scroll.ScrollToOffset and scroll.GetDerivedScrollOffset then
        local current = scroll:GetDerivedScrollOffset() or 0
        local nextOffset = current - (delta * step)
        if nextOffset < 0 then
            nextOffset = 0
        end
        scroll:ScrollToOffset(nextOffset)
        if scroll.FullUpdate then
            local updateNow = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true
            scroll:FullUpdate(updateNow)
        end
        return
    end

    if scroll.GetVerticalScroll and scroll.GetVerticalScrollRange and scroll.SetVerticalScroll then
        local current = scroll:GetVerticalScroll() or 0
        local maxOffset = scroll:GetVerticalScrollRange() or 0
        local nextOffset = current - (delta * step)
        if nextOffset < 0 then
            nextOffset = 0
        elseif nextOffset > maxOffset then
            nextOffset = maxOffset
        end
        scroll:SetVerticalScroll(nextOffset)
    end
end

local function RefreshSingleWindow(window)
    if not window then
        return
    end

    local stage = NormalizeStage(window.Stage)
    local entries = LootRules:GetRulesForStage(stage)
    local groups = BuildStageDisplayGroups(stage, entries)
    local section = window.StageSection
    local header = window.StageHeader
    local color = STAGE_COLOR[stage] or { 0.82, 0.82, 0.82 }
    local hasGroupHeaders = #groups > 1

    local totalRows = 0
    for groupIndex = 1, #groups do
        totalRows = totalRows + #groups[groupIndex].entries
    end

    EnsureRowPool(window, totalRows)

    local rowsHeight = 0
    for groupIndex = 1, #groups do
        local group = groups[groupIndex]
        if hasGroupHeaders then
            rowsHeight = rowsHeight + GROUP_HEADER_HEIGHT + GROUP_HEADER_SPACING
        end

        if #group.entries > 0 then
            for i = 1, #group.entries do
                local displayEntry = group.entries[i]
                local estimateRule = displayEntry and displayEntry.entry and displayEntry.entry.rule
                local estimateHeight = RULE_ROW_HEIGHT
                if LootRules.GetInlineRuleEstimatedHeight then
                    estimateHeight = LootRules:GetInlineRuleEstimatedHeight(estimateRule, window.Content:GetWidth() or 1) or RULE_ROW_HEIGHT
                end
                rowsHeight = rowsHeight + estimateHeight
                if i < #group.entries then
                    rowsHeight = rowsHeight + RULE_ROW_SPACING
                end
            end
        end

        if hasGroupHeaders and groupIndex < #groups then
            rowsHeight = rowsHeight + GROUP_SECTION_SPACING
        end
    end

    local sectionHeight = 8 + STAGE_HEADER_HEIGHT + STAGE_HEADER_SPACING + STAGE_COLUMNS_HEIGHT + 6 + rowsHeight + 10
    if sectionHeight < 44 then
        sectionHeight = 44
    end

    section:Show()
    section:ClearAllPoints()
    section:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 2, 0)
    section:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", -2, 0)
    section:SetHeight(sectionHeight)
    section:SetBackdropBorderColor(color[1], color[2], color[3], 0.62)
    if section.Inner then
        section.Inner:SetColorTexture(color[1] * 0.08, color[2] * 0.08, color[3] * 0.08, 0.22)
    end

    header:Show()
    header:SetParent(section)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", section, "TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", section, "TOPRIGHT", -6, -6)
    header.label:SetText("Advanced " .. (STAGE_LABEL[stage] or stage) .. " Rules")
    header.label:SetTextColor(color[1], color[2], color[3], 1)
    if hasGroupHeaders and groups[1] and groups[2] then
        header.meta:SetText(("%d rule(s), %d filter(s)"):format(#groups[1].entries, #groups[2].entries))
    else
        header.meta:SetText(("%d rule(s)"):format(#entries))
    end

    if section.Columns then
        section.Columns:SetParent(section)
        section.Columns:Show()
        section.Columns:ClearAllPoints()
        section.Columns:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        section.Columns:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
        if hasGroupHeaders then
            section.Columns.Rule:SetText("Rule / Filter")
        else
            section.Columns.Rule:SetText("Rule")
        end
        section.Columns.Rule:SetTextColor(0.78, 0.82, 0.9, 1)
        section.Columns.Options:SetTextColor(0.78, 0.82, 0.9, 1)
        section.Columns.Toggle:SetTextColor(0.78, 0.82, 0.9, 1)
    end

    if window.GroupHeaders then
        for i = 1, #window.GroupHeaders do
            local groupHeader = window.GroupHeaders[i]
            groupHeader:SetParent(section)
            groupHeader:Hide()
        end
    end

    local yOffset = STAGE_HEADER_HEIGHT + STAGE_HEADER_SPACING + STAGE_COLUMNS_HEIGHT + 12
    local rowIndex = 1
    local groupHeaderIndex = 1

    for groupIndex = 1, #groups do
        local group = groups[groupIndex]
        if hasGroupHeaders and window.GroupHeaders then
            local groupHeader = window.GroupHeaders[groupHeaderIndex]
            if groupHeader then
                groupHeader:Show()
                groupHeader:ClearAllPoints()
                groupHeader:SetPoint("TOPLEFT", section, "TOPLEFT", 6, -yOffset)
                groupHeader:SetPoint("TOPRIGHT", section, "TOPRIGHT", -6, -yOffset)
                groupHeader.label:SetText(("%s (%d)"):format(group.title or "Rules", #group.entries))
                groupHeader.label:SetTextColor(color[1], color[2], color[3], 0.95)
                groupHeader.detail:SetText(group.description or "")
                groupHeader.detail:SetTextColor(0.78, 0.82, 0.9, 0.95)
                if groupHeader.line then
                    groupHeader.line:SetColorTexture(color[1] * 0.45, color[2] * 0.45, color[3] * 0.45, 0.6)
                end
            end
            yOffset = yOffset + GROUP_HEADER_HEIGHT + GROUP_HEADER_SPACING
            groupHeaderIndex = groupHeaderIndex + 1
        end

        for groupPos = 1, #group.entries do
            local displayEntry = group.entries[groupPos]
            local stageEntry = displayEntry and displayEntry.entry
            local stagePos = displayEntry and displayEntry.stagePos or groupPos
            local rule = stageEntry and stageEntry.rule
            local row = window.Rows[rowIndex]

            if row and rule then
                local rowHeight = RULE_ROW_HEIGHT
                if LootRules.GetInlineRuleEstimatedHeight then
                    rowHeight = LootRules:GetInlineRuleEstimatedHeight(rule, window.Content:GetWidth() or 1) or RULE_ROW_HEIGHT
                end

                row.ruleRef = rule
                row.stage = stage
                row.stagePos = stagePos
                if row:GetParent() ~= section then
                    row:SetParent(section)
                end
                row:SetFrameLevel((section:GetFrameLevel() or 1) + 2)
                row:Show()
                row:ClearAllPoints()
                row:SetHeight(rowHeight)
                row:SetPoint("TOPLEFT", section, "TOPLEFT", 6, -yOffset)
                row:SetPoint("TOPRIGHT", section, "TOPRIGHT", -6, -yOffset)
                yOffset = yOffset + rowHeight + RULE_ROW_SPACING

                row.title:SetText(rule.title or rule.id or "Rule")
                row.summary:SetText(rule.summary or "")
                row.check:SetChecked(rule.enabled and true or false)
                row:SetAlpha(1)

                local optionColumnWidth = row.OptionsHost and row.OptionsHost:GetWidth() or 0
                if optionColumnWidth < 100 then
                    optionColumnWidth = OPTIONS_COLUMN_WIDTH
                end
                if optionColumnWidth < 160 then
                    optionColumnWidth = 160
                end
                row._optionColumnWidth = optionColumnWidth

                if LootRules.BuildInlineRuleOptions then
                    local actualHeight = LootRules:BuildInlineRuleOptions(row, rule, window) or rowHeight
                    row._hasOptions = row.OptionsHost and row.OptionsHost:IsShown() or false
                    if actualHeight > rowHeight then
                        row:SetHeight(actualHeight)
                        yOffset = yOffset + (actualHeight - rowHeight)
                    end
                else
                    row._hasOptions = false
                end

                UpdateRowVisual(row, rule.enabled and true or false, false)
            end

            rowIndex = rowIndex + 1
        end

        if hasGroupHeaders and groupIndex < #groups then
            yOffset = yOffset + GROUP_SECTION_SPACING
        end
    end

    for i = rowIndex, #window.Rows do
        local row = window.Rows[i]
        row.ruleRef = nil
        row.stage = nil
        row.stagePos = nil
        row._hasOptions = nil
        if row:GetParent() ~= window.Content then
            row:SetParent(window.Content)
        end
        if LootRules.ReleaseInlineRuleOptions then
            LootRules:ReleaseInlineRuleOptions(row)
        end
        row:Hide()
    end

    local contentHeight = yOffset + 10
    if contentHeight < 1 then
        contentHeight = 1
    end
    if contentHeight ~= sectionHeight then
        section:SetHeight(contentHeight)
    end
    window.Content:SetHeight(max(1, contentHeight))
    FitWindowToContent(window, contentHeight)
end

RefreshManagerUI = function(targetWindow)
    if targetWindow then
        RefreshSingleWindow(targetWindow)
        return
    end

    for _, frame in pairs(managerFrames) do
        if frame then
            RefreshSingleWindow(frame)
        end
    end
end

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function LootRules:RefreshManagerWindow()
    RefreshManagerUI()
end

local function CreateManagerUI(stage)
    stage = NormalizeStage(stage)
    if managerFrames[stage] then
        return managerFrames[stage]
    end

    local hasModernScroll = (type(ScrollUtil) == "table")
        and (type(ScrollUtil.InitScrollBoxWithScrollBar) == "function")
        and (type(CreateScrollBoxLinearView) == "function")

    local fixedWidth = GetWindowFixedWidth(hasModernScroll)
    local frameName = GetManagerFrameName(stage)
    local window = CreateFrame("Frame", frameName, UIParent)
    window.Stage = stage
    window._fixedWidth = fixedWidth
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(220)
    window:SetSize(fixedWidth, WINDOW_DEFAULT_HEIGHT)
    window:SetClampedToScreen(true)
    window:Hide()
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetResizable(false)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.SetResizeBounds then
        window:SetResizeBounds(fixedWidth, WINDOW_MIN_HEIGHT, fixedWidth, 1200)
    elseif window.SetMinResize then
        window:SetMinResize(fixedWidth, WINDOW_MIN_HEIGHT)
    end

    local border = CreateFrame("Frame", nil, window, "DialogBorderTranslucentTemplate")
    border.ignoreInLayout = true
    window.Border = border

    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT")
    closeButton.ignoreInLayout = true
    closeButton:SetScript("OnClick", function()
        window:Hide()
    end)
    window.Close = closeButton

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Advanced " .. (STAGE_LABEL[stage] or stage) .. " Rules")
    window.Title = title

    local listContainer = CreateFrame("Frame", nil, window)
    listContainer:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -36)
    listContainer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 44)
    window.ListContainer = listContainer

    local scroll
    local content
    local scrollBar
    local scrollView
    local contentWidthPadding = 2
    if hasModernScroll then
        scroll = CreateFrame("Frame", nil, listContainer, "WowScrollBox")
        scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 4, -6)
        scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -18, 6)
        scroll:SetInterpolateScroll(true)
        scroll:EnableMouseWheel(true)

        scrollBar = CreateFrame("EventFrame", nil, listContainer, "MinimalScrollBar")
        scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
        scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
        scrollBar:SetHideIfUnscrollable(true)
        scrollBar:SetInterpolateScroll(true)

        scrollView = CreateScrollBoxLinearView()
        scrollView:SetPanExtent(14)
    else
        scroll = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 5, -5)
        scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -27, 5)
        scroll:EnableMouseWheel(true)
        contentWidthPadding = 6
    end

    window.Scroll = scroll
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    window.Content = content
    window._contentWidthPadding = contentWidthPadding

    if hasModernScroll then
        content.scrollable = true
        content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        content:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
        ScrollUtil.InitScrollBoxWithScrollBar(scroll, scrollBar, scrollView)
        if scroll.SetScrollTarget then
            scroll:SetScrollTarget(content)
        end
        window.ScrollBar = scrollBar
        window.ScrollView = scrollView
    else
        scroll:SetScrollChild(content)
    end

    window.StageSection = CreateStageSection(content)
    window.StageHeader = CreateStageHeader(window.StageSection)
    window.GroupHeaders = {}
    for i = 1, MAX_GROUP_HEADERS do
        window.GroupHeaders[i] = CreateRuleGroupHeader(window.StageSection)
        window.GroupHeaders[i]:Hide()
    end

    local rows = {}
    for i = 1, MAX_VISIBLE_ROWS do
        rows[i] = CreateRuleRow(window, content)
    end
    window.Rows = rows

    local resizeHandle = CreateFrame("Button", nil, window)
    resizeHandle:Hide()
    window.ResizeHandle = resizeHandle

    local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    resetButton:SetSize(132, 22)
    resetButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 14)
    resetButton:SetText("Reset to Defaults")
    resetButton:SetScript("OnClick", function()
        if LootRules.ResetStageRulesToDefaults then
            LootRules:ResetStageRulesToDefaults(window.Stage)
        end
        RefreshManagerUI(window)
        if PlaySound and SOUNDKIT then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    window.ResetButton = resetButton

    scroll:SetScript("OnSizeChanged", function(scrollSelf, width)
        local contentWidth = (width or scrollSelf:GetWidth() or 1) - (window._contentWidthPadding or 6)
        if contentWidth < 1 then
            contentWidth = 1
        end
        content:SetWidth(contentWidth)
    end)

    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(_, delta)
        HandleListMouseWheel(window, delta)
    end)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        HandleListMouseWheel(window, delta)
    end)
    if not hasModernScroll then
        scroll:SetScript("OnMouseWheel", function(_, delta)
            HandleListMouseWheel(window, delta)
        end)
    end

    window:HookScript("OnSizeChanged", function(self, width, height)
        if self._enforcingSize then
            return
        end

        local targetW = self._fixedWidth or fixedWidth
        local targetH = height
        targetH = ClampWindowHeight(targetH)

        if targetW ~= width or targetH ~= height then
            self._enforcingSize = true
            self:SetSize(targetW, targetH)
            self._enforcingSize = nil
        end
    end)

    window:HookScript("OnShow", function(self)
        local w, h = self:GetSize()
        local targetW = self._fixedWidth or fixedWidth
        local targetH = ClampWindowHeight(h)
        if not w or not h or w ~= targetW or h ~= targetH then
            self:SetSize(targetW, targetH)
        end
    end)

    tinsert(UISpecialFrames, frameName)
    managerFrames[stage] = window
    return window
end

local function ResolveBagAnchorFrame(anchor)
    local frame = anchor
    for _ = 1, 4 do
        if not frame then
            break
        end
        local name = frame.GetName and frame:GetName()
        if name == "RefineUI_Bags" or name == "ContainerFrameCombinedBags" or name == "ContainerFrame1" then
            return frame
        end
        frame = frame.GetParent and frame:GetParent() or nil
    end

    local refineBags = _G and _G["RefineUI_Bags"]
    if refineBags and refineBags.IsShown and refineBags:IsShown() then
        return refineBags
    end

    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        return ContainerFrameCombinedBags
    end

    if ContainerFrame1 and ContainerFrame1:IsShown() then
        return ContainerFrame1
    end

    return nil
end

local function ToggleStageWindow(stage, anchor)
    stage = NormalizeStage(stage)
    local frame = CreateManagerUI(stage)
    if frame:IsShown() then
        frame:Hide()
        return
    end

    RefreshManagerUI(frame)
    FitWindowToContent(frame, frame.Content and frame.Content:GetHeight() or 0)
    frame:ClearAllPoints()

    local otherStage = (stage == STAGE_LOOT) and STAGE_SELL or STAGE_LOOT
    local otherWindow = managerFrames[otherStage]
    if otherWindow and otherWindow:IsShown() then
        frame:SetPoint("BOTTOMRIGHT", otherWindow, "TOPRIGHT", 0, WINDOW_ANCHOR_GAP)
    else
        local bagAnchor = ResolveBagAnchorFrame(anchor)
        if bagAnchor then
            frame:SetPoint("BOTTOMRIGHT", bagAnchor, "BOTTOMLEFT", -WINDOW_ANCHOR_GAP, 0)
        else
            frame:SetPoint("CENTER")
        end
    end

    frame:Show()
end

function LootRules:ToggleLootManager(anchor)
    ToggleStageWindow(STAGE_LOOT, anchor)
end

function LootRules:ToggleSellManager(anchor)
    ToggleStageWindow(STAGE_SELL, anchor)
end

function LootRules:ToggleManager(anchor)
    self:ToggleLootManager(anchor)
end

local function SetupSlashCommands()
    SLASH_LOOTRULES1 = "/lootrules"
    SLASH_LOOTRULES2 = "/lrules"
    SlashCmdList["LOOTRULES"] = function()
        LootRules:ToggleLootManager()
    end

    SLASH_SELLRULES1 = "/sellrules"
    SLASH_SELLRULES2 = "/srules"
    SlashCmdList["SELLRULES"] = function()
        LootRules:ToggleSellManager()
    end
end

function LootRules:OnEnable()
    if not RefineUI.Config.Loot.Enable then
        return
    end

    self:GetConfig()
    if self.EnableExecutors then
        self:EnableExecutors()
    end
    SetupSlashCommands()
end

