----------------------------------------------------------------------------------------
-- UnitFrames Party: Settings
-- Description: Tracked-buff settings UI panel (drag-and-drop editor, color picker,
--              sort mode) shown in Edit Mode for Party/Raid frame systems.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
local UF = RefineUI.UnitFrames
local P = UF._party
if not P then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local type = type
local tostring = tostring
local wipe = wipe
local tinsert = table.insert
local tsort = table.sort

local QUESTION_MARK_ICON = P.QUESTION_MARK_ICON
local IMPORTANT_SORT_MODE = P.IMPORTANT_SORT_MODE

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local IMPORTANT_DRAG_TEXTURE = [[Interface\AddOns\RefineUI\Media\Textures\drag.blp]]
local ROW_HEIGHT = 26
local ROW_SPACING = 2

local COL_FRAME_RIGHT    = -6
local COL_IMP_RIGHT      = -34
local COL_COLOR_RIGHT    = -62
local COL_NAME_RIGHT     = -88

local SECTION_STYLE = {
    important = {
        bg     = { 0.18, 0.14, 0.08, 0.78 },
        border = { 0.82, 0.66, 0.28, 0.7 },
        accent = { 1.0, 0.9, 0.62 },
        text   = { 1.0, 0.9, 0.62 },
        rowBg  = { 0.14, 0.12, 0.08, 0.45 },
    },
    standard = {
        bg     = { 0.09, 0.14, 0.18, 0.78 },
        border = { 0.3, 0.52, 0.74, 0.7 },
        accent = { 0.72, 0.88, 1.0 },
        text   = { 0.72, 0.88, 1.0 },
        rowBg  = { 0.08, 0.10, 0.14, 0.40 },
    },
}

local trackedBuffSettingsWindow
local trackedBuffSettingsDialogHooked = false
local trackedBuffSettingsRows = {}

----------------------------------------------------------------------------------------
-- Edit Mode System Detection
----------------------------------------------------------------------------------------
local function IsPartyOrRaidEditModeSystem(systemFrame)
    local enum = _G.Enum
    if not systemFrame or type(systemFrame) ~= "table" or type(enum) ~= "table" then
        return false
    end
    if not enum.EditModeSystem or not enum.EditModeUnitFrameSystemIndices then
        return false
    end
    if systemFrame.system ~= enum.EditModeSystem.UnitFrame then
        return false
    end
    local index = systemFrame.systemIndex
    return index == enum.EditModeUnitFrameSystemIndices.Party
        or index == enum.EditModeUnitFrameSystemIndices.Raid
end

----------------------------------------------------------------------------------------
-- Sort Helpers
----------------------------------------------------------------------------------------
local function SortEntriesByManualOrder(entries)
    tsort(entries, function(a, b)
        local rankA = P.GetTrackedClassBuffManualOrderRank(a and a.key)
        local rankB = P.GetTrackedClassBuffManualOrderRank(b and b.key)
        if rankA ~= rankB then
            return rankA < rankB
        end
        return (a and a.name or "") < (b and b.name or "")
    end)
end

local function SortEntriesByName(entries, descending)
    tsort(entries, function(a, b)
        local nameA = a and a.name or ""
        local nameB = b and b.name or ""
        if descending then
            return nameA > nameB
        end
        return nameA < nameB
    end)
end

local function EnsureTrackedBuffOrderContainsEntry(entryKey)
    local cfg = P.GetClassBuffConfig()
    if not cfg or type(entryKey) ~= "string" then
        return
    end

    for i = 1, #cfg.ManualOrder do
        if cfg.ManualOrder[i] == entryKey then
            return
        end
    end
    cfg.ManualOrder[#cfg.ManualOrder + 1] = entryKey
end

----------------------------------------------------------------------------------------
-- Color Picker
----------------------------------------------------------------------------------------
local function OpenTrackedBuffColorPicker(entryKey)
    local settings = P.GetTrackedClassBuffSettings(entryKey)
    if not settings or not ColorPickerFrame or type(ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
        return
    end

    local oldColor = { settings.BorderColor[1], settings.BorderColor[2], settings.BorderColor[3], settings.BorderColor[4] or 1 }
    local function ApplyPickerColor(colorTable)
        settings.BorderColor = P.NormalizeTrackedBuffColorTable(colorTable)
        if trackedBuffSettingsWindow and trackedBuffSettingsWindow:IsShown() then
            trackedBuffSettingsWindow:RefreshRows()
        end
        UF.RefreshTrackedClassBuffSettings()
    end

    local info = {
        hasOpacity = false,
        r = oldColor[1],
        g = oldColor[2],
        b = oldColor[3],
        opacity = oldColor[4],
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplyPickerColor({ r, g, b, 1 })
        end,
        opacityFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ApplyPickerColor({ r, g, b, 1 })
        end,
        cancelFunc = function()
            ApplyPickerColor(oldColor)
        end,
    }

    ColorPickerFrame:SetupColorPickerAndShow(info)
end

----------------------------------------------------------------------------------------
-- Row Management
----------------------------------------------------------------------------------------
local function EnsureTrackedBuffRow(parent, index)
    local row = trackedBuffSettingsRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    row.border:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.4)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetAtlas("Options_List_Hover")
    row.highlight:SetAlpha(0.14)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)

    row.dragHandle = CreateFrame("Frame", nil, row)
    row.dragHandle:SetSize(12, 12)
    row.dragHandle:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.dragHandle.icon = row.dragHandle:CreateTexture(nil, "ARTWORK")
    row.dragHandle.icon:SetAllPoints()
    row.dragHandle.icon:SetTexture(IMPORTANT_DRAG_TEXTURE)
    row.dragHandle.icon:SetVertexColor(0.75, 0.75, 0.75, 0.85)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.dragHandle, "RIGHT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", COL_NAME_RIGHT, 0)
    row.name:SetJustifyH("LEFT")

    row.colorButton = CreateFrame("Button", nil, row)
    row.colorButton:SetSize(16, 16)
    row.colorButton:SetPoint("RIGHT", row, "RIGHT", COL_COLOR_RIGHT, 0)
    row.colorButton:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if owner and owner.entryKey then
            OpenTrackedBuffColorPicker(owner.entryKey)
        end
    end)
    row.colorButton.swatch = row.colorButton:CreateTexture(nil, "ARTWORK")
    row.colorButton.swatch:SetPoint("TOPLEFT", row.colorButton, "TOPLEFT", 1, -1)
    row.colorButton.swatch:SetPoint("BOTTOMRIGHT", row.colorButton, "BOTTOMRIGHT", -1, 1)
    row.colorButton.swatch:SetColorTexture(1, 1, 1, 1)
    RefineUI.CreateBorder(row.colorButton, 1, 1, 6)

    row.importantCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.importantCheck:SetSize(18, 18)
    row.importantCheck:SetPoint("RIGHT", row, "RIGHT", COL_IMP_RIGHT, 0)
    row.importantCheck:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if not owner or not owner.entryKey then
            return
        end
        local settings = P.GetTrackedClassBuffSettings(owner.entryKey)
        settings.Important = self:GetChecked() and true or false
        if settings.Important then
            EnsureTrackedBuffOrderContainsEntry(owner.entryKey)
        end
        P.EnsureManualOrderIncludesAllEntries()
        trackedBuffSettingsWindow:RefreshRows()
        UF.RefreshTrackedClassBuffSettings()
    end)

    row.frameColorCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.frameColorCheck:SetSize(18, 18)
    row.frameColorCheck:SetPoint("RIGHT", row, "RIGHT", COL_FRAME_RIGHT, 0)
    row.frameColorCheck:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if not owner or not owner.entryKey then
            return
        end
        local settings = P.GetTrackedClassBuffSettings(owner.entryKey)
        settings.FrameColor = self:GetChecked() and true or false
        UF.RefreshTrackedClassBuffSettings()
    end)

    row:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        if not trackedBuffSettingsWindow or not trackedBuffSettingsWindow:IsManualSortMode() then
            return
        end
        if self.sectionType ~= "important" or not self.entryKey then
            return
        end
        if self.colorButton:IsMouseOver() or self.importantCheck:IsMouseOver() or self.frameColorCheck:IsMouseOver() then
            return
        end
        trackedBuffSettingsWindow:StartManualDrag(self.entryKey)
    end)

    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and trackedBuffSettingsWindow then
            trackedBuffSettingsWindow:StopManualDrag(true)
        end
    end)

    trackedBuffSettingsRows[index] = row
    return row
end

local function ApplyRowStyle(row, sectionType)
    local style = SECTION_STYLE[sectionType] or SECTION_STYLE.standard
    row.bg:SetColorTexture(style.rowBg[1], style.rowBg[2], style.rowBg[3], style.rowBg[4])
    row.border:SetBackdropBorderColor(style.border[1], style.border[2], style.border[3], 0.35)
    row.accent:SetColorTexture(style.accent[1], style.accent[2], style.accent[3], 0.65)
end

----------------------------------------------------------------------------------------
-- Section Header Construction
----------------------------------------------------------------------------------------
local function EnsureSectionHeader(parent, sectionType)
    local style = SECTION_STYLE[sectionType] or SECTION_STYLE.standard

    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(22)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.bg[4])

    header.border = CreateFrame("Frame", nil, header, "BackdropTemplate")
    header.border:SetAllPoints()
    header.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header.border:SetBackdropBorderColor(style.border[1], style.border[2], style.border[3], style.border[4])

    header.accent = header:CreateTexture(nil, "ARTWORK")
    header.accent:SetWidth(3)
    header.accent:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -1)
    header.accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 1)
    header.accent:SetColorTexture(style.accent[1], style.accent[2], style.accent[3], 0.9)

    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetPoint("LEFT", header, "LEFT", 8, 0)
    header.label:SetTextColor(style.text[1], style.text[2], style.text[3])

    return header
end

----------------------------------------------------------------------------------------
-- Settings Window
----------------------------------------------------------------------------------------
local function EnsureTrackedBuffSettingsWindow()
    if trackedBuffSettingsWindow then
        return trackedBuffSettingsWindow
    end

    local window = CreateFrame("Frame", "RefineUI_PartyClassBuffSettings", UIParent, "BackdropTemplate")
    window:SetSize(380, 360)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(210)
    window:Hide()
    window:EnableMouse(true)

    window.Border = CreateFrame("Frame", nil, window, "DialogBorderTranslucentTemplate")
    window.Border.ignoreInLayout = true

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    window.title:SetPoint("TOP", 0, -14)
    window.title:SetText("Party/Raid Buffs")
    window.title:SetTextColor(1, 0.82, 0)

    window.subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.subtitle:SetPoint("TOPLEFT", 14, -36)
    window.subtitle:SetPoint("TOPRIGHT", -14, -36)
    window.subtitle:SetJustifyH("LEFT")
    window.subtitle:SetText("Configure tracked class healer buffs.")

    local headerBar = CreateFrame("Frame", nil, window)
    headerBar:SetHeight(16)
    headerBar:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -54)
    headerBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, -54)

    window.columnFrame = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.columnFrame:SetPoint("RIGHT", headerBar, "RIGHT", COL_FRAME_RIGHT + 2, 0)
    window.columnFrame:SetText("Frame")
    window.columnFrame:SetTextColor(0.7, 0.7, 0.7)

    window.columnImportant = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.columnImportant:SetPoint("RIGHT", headerBar, "RIGHT", COL_IMP_RIGHT + 2, 0)
    window.columnImportant:SetText("Imp.")
    window.columnImportant:SetTextColor(0.7, 0.7, 0.7)

    window.columnColor = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.columnColor:SetPoint("RIGHT", headerBar, "RIGHT", COL_COLOR_RIGHT + 2, 0)
    window.columnColor:SetText("Color")
    window.columnColor:SetTextColor(0.7, 0.7, 0.7)

    window.listContainer = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    window.listContainer:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -70)
    window.listContainer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 12)

    window.scroll = CreateFrame("ScrollFrame", nil, window.listContainer, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", window.listContainer, "TOPLEFT", 4, -4)
    window.scroll:SetPoint("BOTTOMRIGHT", window.listContainer, "BOTTOMRIGHT", -24, 4)
    window.scroll:EnableMouseWheel(true)

    window.content = CreateFrame("Frame", nil, window.scroll)
    window.content:SetPoint("TOPLEFT", window.scroll, "TOPLEFT", 0, 0)
    window.content:SetSize(320, 1)
    window.scroll:SetScrollChild(window.content)

    local function HandleMouseWheel(_, delta)
        if not window.scroll or not window.scroll.GetVerticalScroll then return end
        local step = (ROW_HEIGHT + ROW_SPACING) * 3
        local current = window.scroll:GetVerticalScroll() or 0
        local maxScroll = window.scroll:GetVerticalScrollRange() or 0
        local next = current - (delta * step)
        if next < 0 then next = 0 end
        if next > maxScroll then next = maxScroll end
        window.scroll:SetVerticalScroll(next)
    end

    window.listContainer:EnableMouseWheel(true)
    window.listContainer:SetScript("OnMouseWheel", HandleMouseWheel)
    window.content:EnableMouseWheel(true)
    window.content:SetScript("OnMouseWheel", HandleMouseWheel)
    window.scroll:SetScript("OnMouseWheel", HandleMouseWheel)

    window.importantHeader = EnsureSectionHeader(window.content, "important")
    window.importantHeader.label:SetText("Important")

    window.orderLabel = window.importantHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.orderLabel:SetText("Order:")
    window.orderLabel:SetTextColor(0.85, 0.78, 0.55)

    window.orderDropdown = CreateFrame("DropdownButton", nil, window.importantHeader, "WowStyle1DropdownTemplate")
    window.orderDropdown:SetSize(100, 20)
    window.orderDropdown:SetPoint("RIGHT", window.importantHeader, "RIGHT", -4, 0)
    window.orderLabel:SetPoint("RIGHT", window.orderDropdown, "LEFT", -4, 0)

    window.standardHeader = EnsureSectionHeader(window.content, "standard")
    window.standardHeader.label:SetText("Standard")

    window.emptyText = window.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.emptyText:SetTextColor(0.6, 0.6, 0.6)
    window.emptyText:SetText("No tracked healer buffs for this class.")

    window.insertLine = window.content:CreateTexture(nil, "OVERLAY")
    window.insertLine:SetHeight(2)
    window.insertLine:SetColorTexture(1, 0.84, 0.28, 0.95)
    window.insertLine:Hide()

    window.dragGhost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window.dragGhost:SetSize(180, ROW_HEIGHT)
    window.dragGhost:SetFrameStrata("DIALOG")
    window.dragGhost:SetFrameLevel(300)
    window.dragGhost:Hide()
    RefineUI.SetTemplate(window.dragGhost, "Transparent")
    window.dragGhost.text = window.dragGhost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.dragGhost.text:SetPoint("LEFT", 10, 0)
    window.dragGhost.text:SetPoint("RIGHT", -10, 0)
    window.dragGhost.text:SetJustifyH("LEFT")

    window.importantRows = {}
    window.rowCount = 0
    window.dragEntryKey = nil
    window.dragInsertIndex = nil

    function window:IsManualSortMode()
        return P.GetTrackedClassBuffSortMode() == IMPORTANT_SORT_MODE.MANUAL
    end

    function window:GetImportantRowsExcludingDragged()
        local rows = {}
        local dragged = self.dragEntryKey
        for i = 1, #self.importantRows do
            local row = self.importantRows[i]
            if row and row:IsShown() and row.entryKey and row.entryKey ~= dragged then
                rows[#rows + 1] = row
            end
        end
        return rows
    end

    function window:UpdateDragInsertTarget()
        if not self.dragEntryKey then
            self.insertLine:Hide()
            return
        end

        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        cursorY = cursorY / scale

        local rows = self:GetImportantRowsExcludingDragged()
        if #rows == 0 then
            self.dragInsertIndex = 1
            self.insertLine:ClearAllPoints()
            self.insertLine:SetPoint("TOPLEFT", self.importantHeader, "BOTTOMLEFT", 0, -2)
            self.insertLine:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -4, -2)
            self.insertLine:Show()
            return
        end

        local insertIndex = #rows + 1
        for i = 1, #rows do
            local top = rows[i]:GetTop() or 0
            local bottom = rows[i]:GetBottom() or top
            local mid = (top + bottom) * 0.5
            if cursorY >= mid then
                insertIndex = i
                break
            end
        end
        self.dragInsertIndex = insertIndex

        self.insertLine:ClearAllPoints()
        if insertIndex <= #rows then
            self.insertLine:SetPoint("TOPLEFT", rows[insertIndex], "TOPLEFT", 0, 1)
            self.insertLine:SetPoint("TOPRIGHT", rows[insertIndex], "TOPRIGHT", 0, 1)
        else
            self.insertLine:SetPoint("TOPLEFT", rows[#rows], "BOTTOMLEFT", 0, -1)
            self.insertLine:SetPoint("TOPRIGHT", rows[#rows], "BOTTOMRIGHT", 0, -1)
        end
        self.insertLine:Show()
    end

    function window:StartManualDrag(entryKey)
        if not self:IsManualSortMode() or type(entryKey) ~= "string" then
            return
        end

        self.dragEntryKey = entryKey
        self.dragInsertIndex = nil
        for i = 1, #self.importantRows do
            local row = self.importantRows[i]
            if row and row.entryKey == entryKey then
                row:SetAlpha(0.35)
                self.dragGhost.text:SetText(row.name:GetText() or "")
                break
            end
        end

        self.dragGhost:Show()
        self:SetScript("OnUpdate", function(win)
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            win.dragGhost:ClearAllPoints()
            win.dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cursorX / scale) + 12, (cursorY / scale) - 8)
            win:UpdateDragInsertTarget()
        end)
    end

    function window:StopManualDrag(applyMove)
        if not self.dragEntryKey then
            return
        end

        local draggedEntry = self.dragEntryKey
        local insertIndex = self.dragInsertIndex

        self.dragEntryKey = nil
        self.dragInsertIndex = nil
        self:SetScript("OnUpdate", nil)
        self.insertLine:Hide()
        self.dragGhost:Hide()

        for i = 1, #self.importantRows do
            local row = self.importantRows[i]
            if row then
                row:SetAlpha(1)
            end
        end

        if not applyMove then
            return
        end

        local order = {}
        for i = 1, #self.importantRows do
            local row = self.importantRows[i]
            if row and row.entryKey and row.entryKey ~= draggedEntry then
                order[#order + 1] = row.entryKey
            end
        end

        if type(insertIndex) ~= "number" then
            insertIndex = #order + 1
        end
        if insertIndex < 1 then
            insertIndex = 1
        elseif insertIndex > (#order + 1) then
            insertIndex = #order + 1
        end
        tinsert(order, insertIndex, draggedEntry)

        local cfg = P.GetClassBuffConfig()
        if cfg then
            local seen = {}
            local merged = {}
            for i = 1, #order do
                local key = order[i]
                if type(key) == "string" and not seen[key] then
                    seen[key] = true
                    merged[#merged + 1] = key
                end
            end
            for i = 1, #cfg.ManualOrder do
                local key = cfg.ManualOrder[i]
                if type(key) == "string" and not seen[key] then
                    seen[key] = true
                    merged[#merged + 1] = key
                end
            end
            cfg.ManualOrder = merged
            P.EnsureManualOrderIncludesAllEntries()
        end

        self:RefreshRows()
        UF.RefreshTrackedClassBuffSettings()
    end

    function window:RefreshRows()
        P.EnsureManualOrderIncludesAllEntries()
        local contentWidth = (self:GetWidth() or 380) - 44
        if contentWidth < 280 then
            contentWidth = 280
        end
        self.content:SetWidth(contentWidth)

        local entries = P.GetPlayerClassBuffEntries()
        local importantEntries = {}
        local standardEntries = {}
        for i = 1, #entries do
            local entry = entries[i]
            local settings = P.GetTrackedClassBuffSettings(entry.key)
            if settings and settings.Important == true then
                importantEntries[#importantEntries + 1] = entry
            else
                standardEntries[#standardEntries + 1] = entry
            end
        end

        local sortMode = P.GetTrackedClassBuffSortMode()
        local sortModeText = "Manual"
        if sortMode == IMPORTANT_SORT_MODE.MANUAL then
            SortEntriesByManualOrder(importantEntries)
        elseif sortMode == IMPORTANT_SORT_MODE.ASCENDING then
            sortModeText = "Ascending"
            SortEntriesByName(importantEntries, false)
        else
            sortModeText = "Descending"
            SortEntriesByName(importantEntries, true)
        end
        SortEntriesByName(standardEntries, false)
        if self.orderDropdown.Text then
            self.orderDropdown.Text:SetText(sortModeText)
        end

        self.orderDropdown:SetupMenu(function(_, rootDescription)
            rootDescription:CreateRadio(
                "Manual",
                function() return P.GetTrackedClassBuffSortMode() == IMPORTANT_SORT_MODE.MANUAL end,
                function()
                    P.SetTrackedClassBuffSortMode(IMPORTANT_SORT_MODE.MANUAL)
                    self:RefreshRows()
                    UF.RefreshTrackedClassBuffSettings()
                end
            )
            rootDescription:CreateRadio(
                "Ascending",
                function() return P.GetTrackedClassBuffSortMode() == IMPORTANT_SORT_MODE.ASCENDING end,
                function()
                    P.SetTrackedClassBuffSortMode(IMPORTANT_SORT_MODE.ASCENDING)
                    self:RefreshRows()
                    UF.RefreshTrackedClassBuffSettings()
                end
            )
            rootDescription:CreateRadio(
                "Descending",
                function() return P.GetTrackedClassBuffSortMode() == IMPORTANT_SORT_MODE.DESCENDING end,
                function()
                    P.SetTrackedClassBuffSortMode(IMPORTANT_SORT_MODE.DESCENDING)
                    self:RefreshRows()
                    UF.RefreshTrackedClassBuffSettings()
                end
            )
        end)

        for i = 1, #trackedBuffSettingsRows do
            trackedBuffSettingsRows[i]:Hide()
        end
        wipe(self.importantRows)

        local y = -4

        self.importantHeader:ClearAllPoints()
        self.importantHeader:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
        self.importantHeader:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, y)
        y = y - 24

        local rowIndex = 0
        local manualMode = self:IsManualSortMode()
        for i = 1, #importantEntries do
            rowIndex = rowIndex + 1
            local row = EnsureTrackedBuffRow(self.content, rowIndex)
            local entry = importantEntries[i]
            local settings = P.GetTrackedClassBuffSettings(entry.key)
            local r, g, b = P.GetTrackedClassBuffColor(entry.key)

            row.sectionType = "important"
            row.entryKey = entry.key
            row.icon:SetTexture(entry.icon or QUESTION_MARK_ICON)
            row.name:SetText(entry.name or ("Spell " .. tostring(entry.primarySpellID)))
            row.colorButton.swatch:SetColorTexture(r, g, b, 1)
            row.importantCheck:SetChecked(settings.Important == true)
            row.frameColorCheck:SetChecked(settings.FrameColor == true)
            row.dragHandle:SetShown(manualMode)
            ApplyRowStyle(row, "important")

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, y)
            row:Show()
            y = y - (ROW_HEIGHT + ROW_SPACING)
            self.importantRows[#self.importantRows + 1] = row
        end

        y = y - 6

        self.standardHeader:ClearAllPoints()
        self.standardHeader:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
        self.standardHeader:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, y)
        y = y - 24

        for i = 1, #standardEntries do
            rowIndex = rowIndex + 1
            local row = EnsureTrackedBuffRow(self.content, rowIndex)
            local entry = standardEntries[i]
            local settings = P.GetTrackedClassBuffSettings(entry.key)
            local r, g, b = P.GetTrackedClassBuffColor(entry.key)

            row.sectionType = "standard"
            row.entryKey = entry.key
            row.icon:SetTexture(entry.icon or QUESTION_MARK_ICON)
            row.name:SetText(entry.name or ("Spell " .. tostring(entry.primarySpellID)))
            row.colorButton.swatch:SetColorTexture(r, g, b, 1)
            row.importantCheck:SetChecked(settings.Important == true)
            row.frameColorCheck:SetChecked(settings.FrameColor == true)
            row.dragHandle:Hide()
            ApplyRowStyle(row, "standard")

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, y)
            row:Show()
            y = y - (ROW_HEIGHT + ROW_SPACING)
        end

        self.emptyText:ClearAllPoints()
        self.emptyText:SetPoint("CENTER", self.content, "CENTER", 0, 0)
        self.emptyText:SetShown(#entries == 0)

        if #entries == 0 then
            self.importantHeader:Hide()
            self.standardHeader:Hide()
        else
            self.importantHeader:Show()
            self.standardHeader:Show()
        end

        self.rowCount = rowIndex
        self.content:SetHeight((-y) + 16)
        if self.scroll and self.scroll.UpdateScrollChildRect then
            self.scroll:UpdateScrollChildRect()
        end
    end

    window:SetScript("OnHide", function(self)
        self:StopManualDrag(false)
    end)

    window:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            window:StopManualDrag(true)
        end
    end)

    trackedBuffSettingsWindow = window
    return trackedBuffSettingsWindow
end

----------------------------------------------------------------------------------------
-- Edit Mode Dialog Integration
----------------------------------------------------------------------------------------
local function RefreshTrackedBuffSettingsWindowVisibility(systemFrame)
    local editMode = _G.EditModeManagerFrame
    local dialog = _G.EditModeSystemSettingsDialog
    local inEditMode = editMode and editMode.IsEditModeActive and editMode:IsEditModeActive()
    local activeSystem = systemFrame or (dialog and dialog.attachedToSystem)

    if not inEditMode or not dialog or not dialog:IsShown() or not IsPartyOrRaidEditModeSystem(activeSystem) then
        if trackedBuffSettingsWindow then
            trackedBuffSettingsWindow:Hide()
        end
        return
    end

    local window = EnsureTrackedBuffSettingsWindow()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 8)
    window:ClearAllPoints()

    local dialogWidth = dialog:GetWidth() or 380
    local dialogHeight = dialog:GetHeight() or 360
    if dialogHeight < 300 then dialogHeight = 300 end

    window:SetWidth(dialogWidth)
    window:SetHeight(dialogHeight)
    window:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -8)
    window:RefreshRows()
    window:Show()
end

local function HookTrackedBuffSettingsDialog()
    if trackedBuffSettingsDialogHooked then
        return
    end

    local dialog = _G.EditModeSystemSettingsDialog
    if not dialog then
        return
    end

    hooksecurefunc(dialog, "UpdateDialog", function(_, systemFrame)
        RefreshTrackedBuffSettingsWindowVisibility(systemFrame)
    end)
    dialog:HookScript("OnShow", function(self)
        RefreshTrackedBuffSettingsWindowVisibility(self.attachedToSystem)
    end)
    dialog:HookScript("OnHide", function()
        if trackedBuffSettingsWindow then
            trackedBuffSettingsWindow:Hide()
        end
    end)

    local editMode = _G.EditModeManagerFrame
    if editMode then
        hooksecurefunc(editMode, "ExitEditMode", function()
            if trackedBuffSettingsWindow then
                trackedBuffSettingsWindow:Hide()
            end
        end)
    end

    trackedBuffSettingsDialogHooked = true
    RefreshTrackedBuffSettingsWindowVisibility(dialog.attachedToSystem)
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.HookTrackedBuffSettingsDialog = HookTrackedBuffSettingsDialog
