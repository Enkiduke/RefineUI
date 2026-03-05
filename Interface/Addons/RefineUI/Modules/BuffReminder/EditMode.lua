----------------------------------------------------------------------------------------
-- BuffReminder Component: EditMode
-- Description: Integration with Edit Mode and configuration UI
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:GetModule("BuffReminder")
if not BuffReminder then return end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues (Cache only what you actually use)
----------------------------------------------------------------------------------------
local _G = _G
local floor = math.floor
local tonumber = tonumber
local tostring = tostring

local buffOptionsFrame
local editModeRegistered = false
local editModeCallbacksRegistered = false
local editModeSettingsRegistered = false
local editModeSettingsAttached = false
local editModeDialogHooked = false
local editModeSettings

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CATEGORY_ROW_HEIGHT = 30
local ENTRY_ROW_HEIGHT = 24
local ROW_SPACING = 3
local OPTION_LABELS = {
    Enable = "Enable",
    InstanceOnly = "Instance",
}
local OPTION_ORDER = { "Enable", "InstanceOnly" }
local OPTION_COLUMN_WIDTH = 74
local OPTION_GROUP_WIDTH = #OPTION_ORDER * OPTION_COLUMN_WIDTH

local CATEGORY_STYLES = {
    raid = {
        bg = { 0.18, 0.14, 0.08, 0.82 },
        border = { 0.82, 0.66, 0.28, 0.8 },
        text = { 1.0, 0.9, 0.62 },
    },
    targeted = {
        bg = { 0.09, 0.15, 0.2, 0.82 },
        border = { 0.3, 0.52, 0.74, 0.8 },
        text = { 0.72, 0.88, 1.0 },
    },
    self = {
        bg = { 0.09, 0.18, 0.12, 0.82 },
        border = { 0.3, 0.64, 0.42, 0.8 },
        text = { 0.74, 0.95, 0.78 },
    },
}

local FALLBACK_STYLE = {
    bg = { 0.12, 0.14, 0.18, 0.78 },
    border = { 0.34, 0.38, 0.48, 0.76 },
    text = { 0.82, 0.86, 0.92 },
}

----------------------------------------------------------------------------------------
-- Public / Module Methods
----------------------------------------------------------------------------------------
function BuffReminder:IsEditModeActive()
    return RefineUI.LibEditMode
        and type(RefineUI.LibEditMode.IsInEditMode) == "function"
        and RefineUI.LibEditMode:IsInEditMode()
end

function BuffReminder:GetEditModeDialog()
    local lib = RefineUI.LibEditMode
    return lib and lib.internal and lib.internal.dialog or nil
end

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSettingsDialogForBuffReminder(selection)
    local dialog = BuffReminder:GetEditModeDialog()
    local activeSelection = selection or (dialog and dialog.selection)
    local rootFrame = BuffReminder.rootFrame
    return activeSelection and rootFrame and activeSelection.parent == rootFrame
end

local function RegisterEditModeSettings()
    if editModeSettingsRegistered or not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    local settingType = RefineUI.LibEditMode.SettingType
    local settings = {}

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Icon Size",
        default = 44,
        minValue = 20,
        maxValue = 72,
        valueStep = 1,
        get = function()
            return tonumber(BuffReminder:GetConfig().Size) or 44
        end,
        set = function(_, value)
            local size = floor((tonumber(value) or 44) + 0.5)
            if size < 20 then
                size = 20
            elseif size > 72 then
                size = 72
            end
            BuffReminder:GetConfig().Size = size
            BuffReminder:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Icon Spacing",
        default = 6,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            return tonumber(BuffReminder:GetConfig().Spacing) or 6
        end,
        set = function(_, value)
            local spacing = floor((tonumber(value) or 6) + 0.5)
            if spacing < 0 then
                spacing = 0
            elseif spacing > 20 then
                spacing = 20
            end
            BuffReminder:GetConfig().Spacing = spacing
            BuffReminder:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Icon Flash",
        default = true,
        get = function()
            return BuffReminder:GetConfig().Flash ~= false
        end,
        set = function(_, value)
            BuffReminder:GetConfig().Flash = value and true or false
            BuffReminder:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Alert Sound",
        default = false,
        get = function()
            return BuffReminder:GetConfig().Sound == true
        end,
        set = function(_, value)
            BuffReminder:GetConfig().Sound = value and true or false
            BuffReminder:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Class Color",
        default = true,
        get = function()
            return BuffReminder:GetConfig().ClassColor == true
        end,
        set = function(_, value)
            BuffReminder:GetConfig().ClassColor = value and true or false
            BuffReminder:RequestRefresh()
        end,
    }

    editModeSettings = settings
    editModeSettingsRegistered = true
end

local function GetCategoryStyle(category)
    return CATEGORY_STYLES[category] or FALLBACK_STYLE
end

local function ApplyManagerFrameLevels(window)
    if not window then
        return
    end

    local baseLevel = window:GetFrameLevel() or 220
    if window.Border then
        window.Border:SetFrameLevel(baseLevel)
    end
    if window.ListContainer then
        window.ListContainer:SetFrameLevel(baseLevel + 5)
    end
    if window.scroll then
        window.scroll:SetFrameLevel(baseLevel + 6)
    end
    if window.content then
        window.content:SetFrameLevel(baseLevel + 7)
    end
end

local function HandleOptionsMouseWheel(window, delta)
    if not window or not window.scroll then
        return
    end

    local scroll = window.scroll
    if not scroll.GetVerticalScroll or not scroll.GetVerticalScrollRange or not scroll.SetVerticalScroll then
        return
    end

    local step = (ENTRY_ROW_HEIGHT + ROW_SPACING) * 2
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

local function EnsureRowOptionCheck(row, index, settingKey, isCategory)
    row.optionChecks = row.optionChecks or {}
    local check = row.optionChecks[index]
    if check then
        return check
    end

    check = CreateFrame("CheckButton", nil, row.optionGroup, "UICheckButtonTemplate")
    check:SetSize(18, 18)
    check.settingKey = settingKey
    check.isCategorySetting = isCategory
    check.ownerRow = row
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    check.label:SetText(OPTION_LABELS[settingKey] or settingKey)
    check.label:SetJustifyH("LEFT")

    check:SetScript("OnClick", function(self)
        local owner = self.ownerRow
        if not owner or not owner.categoryKey or not self.settingKey then
            return
        end

        local checked = self:GetChecked() and true or false
        if self.isCategorySetting then
            local categorySettings = BuffReminder:GetCategorySettings(owner.categoryKey)
            categorySettings[self.settingKey] = checked
            BuffReminder:ApplyCategorySettingToEntries(owner.categoryKey, self.settingKey, checked)
        elseif owner.entryKey then
            local entrySettings = BuffReminder:GetEntrySettings(owner.entryKey, owner.categoryKey)
            entrySettings[self.settingKey] = checked
        end

        BuffReminder:RequestRefresh()
    end)

    row.optionChecks[index] = check
    return check
end

local function EnsureCategoryRow(window, index)
    local row = window.categoryRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, window.content, "BackdropTemplate")
    row:SetHeight(CATEGORY_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetAtlas("Options_List_Hover")
    row.highlight:SetAlpha(0.2)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)

    row.expand = CreateFrame("Button", nil, row)
    row.expand:SetSize(18, 18)
    row.expand:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.expand.text = row.expand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.expand.text:SetPoint("CENTER")
    row.expand.text:SetText("-")
    row.expand:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if not owner or not owner.categoryKey then
            return
        end
        local settings = BuffReminder:GetCategorySettings(owner.categoryKey)
        settings.Expanded = settings.Expanded ~= true
        BuffReminder:RefreshBuffOptionsWindow(true)
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.expand, "RIGHT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconStrip = CreateFrame("Frame", nil, row)
    row.iconStrip:SetSize(120, 16)
    row.iconStrip:SetPoint("RIGHT", row, "RIGHT", -(OPTION_GROUP_WIDTH + 14), 0)
    row.iconStrip.icons = {}
    row.iconStrip:Hide()

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", row.iconStrip, "LEFT", -6, 5)
    row.label:SetJustifyH("LEFT")

    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.summary:SetPoint("LEFT", row.label, "LEFT", 0, -12)
    row.summary:SetPoint("RIGHT", row.iconStrip, "LEFT", -6, -12)
    row.summary:SetJustifyH("LEFT")

    row.optionGroup = CreateFrame("Frame", nil, row)
    row.optionGroup:SetSize(OPTION_GROUP_WIDTH, 20)
    row.optionGroup:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    for i = 1, #OPTION_ORDER do
        local settingKey = OPTION_ORDER[i]
        local check = EnsureRowOptionCheck(row, i, settingKey, true)
        check:ClearAllPoints()
        check:SetPoint("LEFT", row.optionGroup, "LEFT", (i - 1) * OPTION_COLUMN_WIDTH, 0)
    end

    row:SetScript("OnClick", function(self)
        if self.expand and self.expand:IsMouseOver() then
            return
        end
        if self.optionChecks then
            for i = 1, #self.optionChecks do
                if self.optionChecks[i]:IsMouseOver() then
                    return
                end
            end
        end
        if self.expand then
            self.expand:Click()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.categoryKey then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(BuffReminder.CATEGORY_LABELS[self.categoryKey] or self.categoryKey, 1, 1, 1)
        local settings = BuffReminder:GetCategorySettings(self.categoryKey)
        GameTooltip:AddLine(settings.Enable and "Enabled" or "Disabled", 0.82, 0.82, 0.82)
        if settings.InstanceOnly then
            GameTooltip:AddLine("Instance only", 0.72, 0.86, 0.95)
        end
        if self.categoryEntryCount and self.categoryEntryCount > 0 then
            GameTooltip:AddLine(tostring(self.categoryEntryCount) .. " tracked entries", 0.72, 0.72, 0.72)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    window.categoryRows[index] = row
    return row
end

local function EnsureEntryRow(window, index)
    local row = window.entryRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, window.content, "BackdropTemplate")
    row:SetHeight(ENTRY_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetAtlas("Options_List_Hover")
    row.highlight:SetAlpha(0.14)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -(OPTION_GROUP_WIDTH + 8), 0)
    row.label:SetJustifyH("LEFT")

    row.optionGroup = CreateFrame("Frame", nil, row)
    row.optionGroup:SetSize(OPTION_GROUP_WIDTH, 20)
    row.optionGroup:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    for i = 1, #OPTION_ORDER do
        local settingKey = OPTION_ORDER[i]
        local check = EnsureRowOptionCheck(row, i, settingKey, false)
        check:ClearAllPoints()
        check:SetPoint("LEFT", row.optionGroup, "LEFT", (i - 1) * OPTION_COLUMN_WIDTH, 0)
    end

    row:SetScript("OnClick", function(self)
        if self.optionChecks then
            for i = 1, #self.optionChecks do
                if self.optionChecks[i]:IsMouseOver() then
                    return
                end
            end
            if self.optionChecks[1] then
                self.optionChecks[1]:Click()
            end
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entryData then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entryData.name or "Tracked Aura", 1, 1, 1)
        if self.categoryKey then
            GameTooltip:AddLine("Category: " .. (BuffReminder.CATEGORY_LABELS[self.categoryKey] or self.categoryKey), 0.75, 0.82, 0.95)
        end
        local primarySpellID = BuffReminder:GetPrimarySpellID(self.entryData.spellID)
        if primarySpellID then
            GameTooltip:AddLine("Spell ID: " .. tostring(primarySpellID), 0.72, 0.72, 0.72)
        end
        local settings = BuffReminder:GetEntrySettings(self.entryKey, self.categoryKey)
        if settings then
            GameTooltip:AddLine(settings.Enable and "Enabled" or "Disabled", 0.82, 0.82, 0.82)
            if settings.InstanceOnly then
                GameTooltip:AddLine("Instance only", 0.72, 0.86, 0.95)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    window.entryRows[index] = row
    return row
end

local function ApplyCategoryRowStyle(row, category, enabled)
    local style = GetCategoryStyle(category)
    local bg = style.bg
    local border = style.border
    local text = style.text
    local alphaScale = enabled and 1 or 0.45

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] * alphaScale)
    row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4] * alphaScale)
    row.accent:SetColorTexture(text[1], text[2], text[3], 0.95 * alphaScale)
    row.label:SetTextColor(text[1], text[2], text[3], enabled and 1 or 0.85)
    row.summary:SetTextColor(text[1], text[2], text[3], enabled and 0.82 or 0.65)
    row.icon:SetDesaturated(not enabled)
    row.icon:SetVertexColor(1, 1, 1, enabled and 1 or 0.72)
    if row.expand and row.expand.text then
        row.expand.text:SetTextColor(text[1], text[2], text[3], enabled and 1 or 0.72)
    end
    if row.optionChecks then
        for i = 1, #row.optionChecks do
            if row.optionChecks[i].label then
                row.optionChecks[i].label:SetTextColor(text[1], text[2], text[3], enabled and 0.92 or 0.62)
            end
            row.optionChecks[i]:SetEnabled(true)
        end
    end
end

local function ApplyEntryRowStyle(row, category, categoryEnabled, enabled)
    local style = GetCategoryStyle(category)
    local bg = style.bg
    local border = style.border
    local text = style.text
    local alphaScale = categoryEnabled and 1 or 0.55

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.46 * alphaScale)
    row.border:SetBackdropBorderColor(border[1], border[2], border[3], 0.52 * alphaScale)
    row.accent:SetColorTexture(text[1], text[2], text[3], 0.78 * alphaScale)
    row.label:SetTextColor(text[1], text[2], text[3], enabled and (0.96 * alphaScale) or (0.66 * alphaScale))
    row.icon:SetDesaturated(not enabled or not categoryEnabled)
    row.icon:SetVertexColor(1, 1, 1, (enabled and categoryEnabled) and 1 or 0.62)
    if row.optionChecks then
        for i = 1, #row.optionChecks do
            if row.optionChecks[i].label then
                row.optionChecks[i].label:SetTextColor(text[1], text[2], text[3], (categoryEnabled and enabled) and 0.88 or 0.56)
            end
            row.optionChecks[i]:SetEnabled(true)
        end
    end
end

local function GetCategoryIcon(category, runtime)
    local entries = BuffReminder:GetConfigurableEntries(category)
    local firstEntry = entries[1]
    if firstEntry then
        return BuffReminder:GetEntryTexture(firstEntry, runtime)
    end
    return BuffReminder.QUESTION_MARK_ICON
end

local function UpdateCategoryPreviewIcons(row, entries, runtime, enabled)
    if not row or not row.iconStrip then
        return
    end

    if not entries or #entries == 0 then
        row.iconStrip:Hide()
        for i = 1, #row.iconStrip.icons do
            row.iconStrip.icons[i]:Hide()
        end
        return
    end

    local maxIcons = 6
    local shown = #entries
    if shown > maxIcons then
        shown = maxIcons
    end

    row.iconStrip:Show()
    for i = 1, shown do
        local icon = row.iconStrip.icons[i]
        if not icon then
            icon = row.iconStrip:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.iconStrip.icons[i] = icon
        end
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", row.iconStrip, "RIGHT", -((i - 1) * 15), 0)
        icon:SetTexture(BuffReminder:GetEntryTexture(entries[i], runtime))
        icon:SetDesaturated(not enabled)
        icon:SetVertexColor(1, 1, 1, enabled and 1 or 0.68)
        icon:Show()
    end

    for i = shown + 1, #row.iconStrip.icons do
        row.iconStrip.icons[i]:Hide()
    end
end

local function EnsureBuffOptionsWindow()
    if buffOptionsFrame then
        return buffOptionsFrame
    end

    buffOptionsFrame = CreateFrame("Frame", "RefineUI_BuffReminderOptions", UIParent, "ResizeLayoutFrame")
    buffOptionsFrame:SetFrameStrata("DIALOG")
    buffOptionsFrame:SetFrameLevel(220)
    buffOptionsFrame:SetSize(560, 380)
    buffOptionsFrame:EnableMouse(true)
    buffOptionsFrame:Hide()

    buffOptionsFrame.Border = CreateFrame("Frame", nil, buffOptionsFrame, "DialogBorderTranslucentTemplate")
    buffOptionsFrame.Border.ignoreInLayout = true
    buffOptionsFrame.Border:EnableMouse(false)

    buffOptionsFrame.close = CreateFrame("Button", nil, buffOptionsFrame, "UIPanelCloseButton")
    buffOptionsFrame.close:SetPoint("TOPRIGHT")
    buffOptionsFrame.close.ignoreInLayout = true
    buffOptionsFrame.close:SetScript("OnClick", function()
        BuffReminder:HideOptionsWindows()
    end)

    buffOptionsFrame.title = buffOptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    buffOptionsFrame.title:SetPoint("TOP", 0, -14)
    buffOptionsFrame.title:SetText("Buff Reminder")
    buffOptionsFrame.title:SetTextColor(1, 0.82, 0)

    buffOptionsFrame.subtitle = buffOptionsFrame:CreateFontString(nil, "OVERLAY")
    buffOptionsFrame.subtitle:SetFontObject("GameFontHighlightSmall")
    buffOptionsFrame.subtitle:SetPoint("TOPLEFT", 14, -36)
    buffOptionsFrame.subtitle:SetPoint("TOPRIGHT", -36, -36)
    buffOptionsFrame.subtitle:SetJustifyH("LEFT")
    buffOptionsFrame.subtitle:SetText("Configure category and per-buff settings. Category changes apply to all visible buffs.")

    buffOptionsFrame.divider = buffOptionsFrame:CreateTexture(nil, "ARTWORK")
    buffOptionsFrame.divider:SetTexture([[Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider]])
    buffOptionsFrame.divider:SetSize(330, 16)
    buffOptionsFrame.divider:SetPoint("TOP", buffOptionsFrame.subtitle, "BOTTOM", 0, -2)

    buffOptionsFrame.ListContainer = CreateFrame("Frame", nil, buffOptionsFrame, "InsetFrameTemplate")
    buffOptionsFrame.ListContainer:SetPoint("TOPLEFT", buffOptionsFrame, "TOPLEFT", 12, -66)
    buffOptionsFrame.ListContainer:SetPoint("BOTTOMRIGHT", buffOptionsFrame, "BOTTOMRIGHT", -12, 12)

    buffOptionsFrame.scroll = CreateFrame("ScrollFrame", nil, buffOptionsFrame, "UIPanelScrollFrameTemplate")
    buffOptionsFrame.scroll:SetPoint("TOPLEFT", buffOptionsFrame.ListContainer, "TOPLEFT", 5, -5)
    buffOptionsFrame.scroll:SetPoint("BOTTOMRIGHT", buffOptionsFrame.ListContainer, "BOTTOMRIGHT", -27, 5)
    buffOptionsFrame.scroll:EnableMouseWheel(true)

    buffOptionsFrame.content = CreateFrame("Frame", nil, buffOptionsFrame.scroll)
    buffOptionsFrame.content:SetPoint("TOPLEFT", buffOptionsFrame.scroll, "TOPLEFT", 0, 0)
    buffOptionsFrame.content:SetSize(240, 1)
    buffOptionsFrame.scroll:SetScrollChild(buffOptionsFrame.content)
    buffOptionsFrame.categoryRows = {}
    buffOptionsFrame.entryRows = {}

    buffOptionsFrame.ListContainer:EnableMouseWheel(true)
    buffOptionsFrame.ListContainer:SetScript("OnMouseWheel", function(_, delta)
        HandleOptionsMouseWheel(buffOptionsFrame, delta)
    end)
    buffOptionsFrame.content:EnableMouseWheel(true)
    buffOptionsFrame.content:SetScript("OnMouseWheel", function(_, delta)
        HandleOptionsMouseWheel(buffOptionsFrame, delta)
    end)
    buffOptionsFrame.scroll:SetScript("OnMouseWheel", function(_, delta)
        HandleOptionsMouseWheel(buffOptionsFrame, delta)
    end)

    BuffReminder.buffOptionsFrame = buffOptionsFrame
    ApplyManagerFrameLevels(buffOptionsFrame)
    return buffOptionsFrame
end

----------------------------------------------------------------------------------------
-- Refresh Commands
----------------------------------------------------------------------------------------
function BuffReminder:RefreshBuffOptionsWindow(force)
    local window = buffOptionsFrame
    if not window then
        if not force then
            return
        end
        window = EnsureBuffOptionsWindow()
    end
    if not force and not window:IsShown() then
        return
    end

    local runtime = self:BuildRuntimeState()
    self:BuildValidUnitCache()

    local contentWidth = (window:GetWidth() or 560) - 52
    if contentWidth < 500 then
        contentWidth = 500
    end
    window.content:SetWidth(contentWidth)

    for i = 1, #window.categoryRows do window.categoryRows[i]:Hide() end
    for i = 1, #window.entryRows do window.entryRows[i]:Hide() end

    local y = -8
    local categoryIndex = 0
    local entryIndex = 0

    for c = 1, #self.CATEGORY_ORDER do
        local category = self.CATEGORY_ORDER[c]
        local entries = self:GetConfigurableEntries(category)
        local categorySettings = self:GetCategorySettings(category)
        local categoryEnabled = categorySettings.Enable ~= false
        local expanded = categorySettings.Expanded ~= false

        categoryIndex = categoryIndex + 1
        local categoryRow = EnsureCategoryRow(window, categoryIndex)
        categoryRow:ClearAllPoints()
        categoryRow:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, y)
        categoryRow:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, y)
        categoryRow.categoryKey = category
        categoryRow.icon:SetTexture(GetCategoryIcon(category, runtime))
        categoryRow.expand.text:SetText(expanded and "-" or "+")

        categoryRow.categoryEntryCount = #entries
        categoryRow.label:SetText(string.format("%s (%d)", self.CATEGORY_LABELS[category] or category, categoryRow.categoryEntryCount))
        categoryRow.summary:SetText("")

        for i = 1, #OPTION_ORDER do
            local settingKey = OPTION_ORDER[i]
            local check = categoryRow.optionChecks and categoryRow.optionChecks[i]
            if check then
                if settingKey == "Enable" then
                    check:SetChecked(categoryEnabled)
                else
                    check:SetChecked(categorySettings[settingKey] == true)
                end
            end
        end
        ApplyCategoryRowStyle(categoryRow, category, categoryEnabled)
        if category == "raid" then
            UpdateCategoryPreviewIcons(categoryRow, entries, runtime, categoryEnabled)
        else
            UpdateCategoryPreviewIcons(categoryRow, nil, runtime, categoryEnabled)
        end
        categoryRow:Show()
        y = y - (CATEGORY_ROW_HEIGHT + ROW_SPACING)

        if expanded then
            for i = 1, #entries do
                local entry = entries[i]
                local entrySettings = self:GetEntrySettings(entry.key, category)
                entryIndex = entryIndex + 1
                local row = EnsureEntryRow(window, entryIndex)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, y)
                row.entryKey = entry.key
                row.entryData = entry
                row.categoryKey = category
                row.icon:SetTexture(self:GetEntryTexture(entry, runtime))
                row.label:SetText(entry.name)
                for optionIndex = 1, #OPTION_ORDER do
                    local settingKey = OPTION_ORDER[optionIndex]
                    local check = row.optionChecks and row.optionChecks[optionIndex]
                    if check then
                        check:SetChecked(entrySettings[settingKey] == true)
                    end
                end
                ApplyEntryRowStyle(row, category, categoryEnabled, entrySettings.Enable ~= false)
                row:Show()
                y = y - (ENTRY_ROW_HEIGHT + ROW_SPACING)
            end
        end

        y = y - 6
    end

    window.content:SetHeight((-y) + 10)
    if window.scroll and window.scroll.UpdateScrollChildRect then
        window.scroll:UpdateScrollChildRect()
    end
end

function BuffReminder:HideOptionsWindows()
    if buffOptionsFrame then
        buffOptionsFrame:Hide()
    end
end

function BuffReminder:RefreshOptionsWindowsVisibility(selection)
    local dialog = self:GetEditModeDialog()
    if not self:IsEditModeActive() or not dialog or not dialog:IsShown() or not IsSettingsDialogForBuffReminder(selection) then
        self:HideOptionsWindows()
        return
    end
    local managerFrame = _G.EditModeManagerFrame
    if managerFrame and managerFrame:IsShown() then
        dialog:ClearAllPoints()
        dialog:SetPoint("TOPLEFT", managerFrame, "TOPRIGHT", 8, 0)
    end

    local window = EnsureBuffOptionsWindow()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 10)
    local dialogWidth = dialog:GetWidth() or 0
    local dialogHeight = dialog:GetHeight() or 0
    if dialogWidth < 560 then
        dialogWidth = 560
    end
    if dialogHeight < 320 then
        dialogHeight = 320
    end
    window:ClearAllPoints()
    window:SetWidth(dialogWidth)
    window:SetHeight(dialogHeight)
    window:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -8)
    ApplyManagerFrameLevels(window)
    self:RefreshBuffOptionsWindow(true)
    window:Show()
end

local function HookEditModeDialog()
    if editModeDialogHooked then
        return
    end
    local dialog = BuffReminder:GetEditModeDialog()
    if not dialog then
        return
    end

    hooksecurefunc(dialog, "Update", function(_, selection)
        BuffReminder:RefreshOptionsWindowsVisibility(selection)
    end)
    dialog:HookScript("OnShow", function()
        BuffReminder:RefreshOptionsWindowsVisibility()
    end)
    dialog:HookScript("OnHide", function()
        BuffReminder:HideOptionsWindows()
    end)

    editModeDialogHooked = true
end

local function ApplyStoredPosition(point, x, y)
    if not RefineUI.Positions then
        RefineUI.Positions = {}
    end
    RefineUI.Positions[BuffReminder.FRAME_NAME] = { point, "UIParent", point, x, y }
end

function BuffReminder:RegisterEditModeFrame()
    local rootFrame = self.rootFrame
    if editModeRegistered or not rootFrame or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    local pos = RefineUI.Positions and RefineUI.Positions[self.FRAME_NAME]
    local default = {
        point = (pos and pos[1]) or "CENTER",
        x = (pos and pos[4]) or 0,
        y = (pos and pos[5]) or 0,
    }

    RefineUI.LibEditMode:AddFrame(rootFrame, function(frame, _, point, x, y)
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, point, x, y)
        ApplyStoredPosition(point, x, y)
    end, default, "Buff Reminder")
    editModeRegistered = true

    RegisterEditModeSettings()
    if editModeSettings and not editModeSettingsAttached and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(rootFrame, editModeSettings)
        editModeSettingsAttached = true
    end

    HookEditModeDialog()
end

function BuffReminder:RegisterEditModeCallbacks()
    if editModeCallbacksRegistered or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.RegisterCallback) ~= "function" then
        return
    end

    RefineUI.LibEditMode:RegisterCallback("enter", function()
        BuffReminder:Refresh()
        BuffReminder:RefreshOptionsWindowsVisibility()
    end)
    RefineUI.LibEditMode:RegisterCallback("exit", function()
        BuffReminder:HideOptionsWindows()
        BuffReminder:Refresh()
    end)

    editModeCallbacksRegistered = true
end
