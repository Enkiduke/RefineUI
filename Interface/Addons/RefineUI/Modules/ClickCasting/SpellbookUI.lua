----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Spellbook UI
-- Description: Spellbook tab and drag/drop panel for tracked click-cast entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local ClearCursor = ClearCursor
local CreateFrame = CreateFrame
local GetCursorInfo = GetCursorInfo
local GetMacroInfo = GetMacroInfo
local InCombatLockdown = InCombatLockdown
local NineSliceUtil = _G.NineSliceUtil
local type = type
local tostring = tostring
local tonumber = tonumber
local sort = table.sort
local format = string.format
local max = math.max
local min = math.min
local floor = math.floor

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PANEL_WIDTH = 430
local PANEL_HEIGHT = 460
local ROW_HEIGHT = 36
local ROW_SPACING = 2
local MAX_VISIBLE_ROWS = 12
local LIST_SCROLLBAR_WIDTH = 20
local PANEL_SPELLBOOK_OVERLAP = 20
local PANEL_CONTENT_LEFT_PADDING = PANEL_SPELLBOOK_OVERLAP
local PANEL_ANCHOR_X = -PANEL_SPELLBOOK_OVERLAP
local PANEL_ANCHOR_Y = -6
local PANEL_BEHIND_LEVEL_OFFSET = 20
local TAB_Y_OFFSET = -125
local TAB_TEXTURE = "Interface\\AddOns\\RefineUI\\Media\\Logo\\Logo"
local MODERN_PANEL_TITLE = "RefineUI Mouseover Casting"
local PANEL_TEMPLATE_CANDIDATES = {
    "DefaultPanelTemplate",
    "ButtonFrameTemplateNoPortrait",
    "ButtonFrameTemplate",
    "PortraitFrameFlatTemplate",
    "BasicFrameTemplateWithInset",
}

local STATE_TEXT = {
    active = "Active",
    unknown = "Unknown",
    unbound = "Unbound",
    otherspec = "Other Spec",
    missing = "Missing",
    conflicted = "Conflicted",
    suspended = "Suspended",
}

local STATE_COLOR = {
    active = { 0.25, 0.95, 0.35 },
    unknown = { 0.72, 0.72, 0.72 },
    unbound = { 0.95, 0.78, 0.25 },
    otherspec = { 0.45, 0.72, 1.00 },
    missing = { 0.95, 0.42, 0.42 },
    conflicted = { 1.00, 0.40, 0.85 },
    suspended = { 0.90, 0.50, 0.20 },
}

local STATE_BG_COLOR = {
    active = { 0.08, 0.20, 0.10, 0.42 },
    unknown = { 0.14, 0.14, 0.14, 0.42 },
    unbound = { 0.20, 0.17, 0.08, 0.42 },
    otherspec = { 0.08, 0.14, 0.22, 0.42 },
    missing = { 0.20, 0.10, 0.10, 0.42 },
    conflicted = { 0.20, 0.10, 0.18, 0.42 },
    suspended = { 0.20, 0.13, 0.08, 0.42 },
}

local ROW_STATE_SORT_ORDER = {
    active = 1,
    unbound = 2,
    missing = 3,
    unknown = 4,
    otherspec = 5,
    conflicted = 6,
    suspended = 7,
}

local ROW_BORDER_EDGE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"
local GetVisibleRowCount
local NAME_GREY_STATES = {
    missing = true,
    unbound = true,
    otherspec = true,
    unknown = true,
}

local DEFAULT_NAME_COLOR = {
    1.0,
    0.82,
    0.0,
}

local GREY_NAME_COLOR = {
    0.62,
    0.62,
    0.62,
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function CreatePanelFrame()
    for index = 1, #PANEL_TEMPLATE_CANDIDATES do
        local template = PANEL_TEMPLATE_CANDIDATES[index]
        local ok, frame = pcall(CreateFrame, "Frame", "RefineUI_ClickCastingPanel", UIParent, template)
        if ok and frame then
            return frame, template
        end
    end

    return CreateFrame("Frame", "RefineUI_ClickCastingPanel", UIParent), nil
end

local function ApplyNoPortraitLayout(frame)
    if not frame then
        return
    end

    if frame.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName and _G.ButtonFrameTemplateNoPortrait then
        pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, "ButtonFrameTemplateNoPortrait")
    end

    if _G.ButtonFrameTemplate_HidePortrait then
        pcall(_G.ButtonFrameTemplate_HidePortrait, frame)
    elseif frame.PortraitContainer then
        frame.PortraitContainer:Hide()
    end
end

function ClickCasting:IsSpellbookUISuppressed()
    if self.IsCliqueLoaded and self:IsCliqueLoaded() then
        return true
    end
    return false
end

function ClickCasting:UpdateSpellbookUIVisibility()
    local suppressUI = self:IsSpellbookUISuppressed()
    local panel = self.spellbookPanel
    local tab = self.spellbookTab

    if suppressUI then
        if panel and panel:IsShown() then
            panel:Hide()
        end
        self:SetPanelShown(false)
        if tab then
            tab:Hide()
        end
        return
    end

    if tab then
        tab:Show()
        self:AnchorSpellbookTab()
    end
end

function ClickCasting:ApplyPanelBehindAnchorFrame(anchorFrame)
    local panel = self.spellbookPanel
    if not panel or not anchorFrame then
        return
    end

    panel:SetFrameStrata(anchorFrame:GetFrameStrata() or "MEDIUM")
    panel:SetFrameLevel(max(0, (anchorFrame:GetFrameLevel() or 1) - PANEL_BEHIND_LEVEL_OFFSET))
end

local function SetPanelTitle(frame, titleText)
    if not frame then
        return
    end

    if frame.SetTitle then
        frame:SetTitle(titleText)
        return
    end

    if frame.TitleText then
        frame.TitleText:SetText(titleText)
        return
    end

    if frame.NineSlice and frame.NineSlice.Text then
        frame.NineSlice.Text:SetText(titleText)
    end
end

local function GetSpellDisplay(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info then
        return info.name or format("Spell %s", tostring(spellID)), info.iconID
    end
    return format("Spell %s", tostring(spellID)), 134400
end

local function GetMacroDisplay(macroIndex, fallbackName, fallbackIcon)
    local name, iconFileID = GetMacroInfo(tonumber(macroIndex) or 0)
    return name or fallbackName or format("Macro %s", tostring(macroIndex)), tonumber(iconFileID) or fallbackIcon or 134400
end

local function JoinKeys(keys)
    if type(keys) ~= "table" or #keys == 0 then
        return "No bound keys"
    end
    return table.concat(keys, ", ")
end

function ClickCasting:GetEntryDisplay(entry, entryCache)
    if entry.kind == "spell" then
        local spellID = tonumber(entry.spellID) or tonumber(entry.baseSpellID)
        local name, icon = GetSpellDisplay(spellID)
        return name, icon
    end

    local macroIndex = entryCache and tonumber(entryCache.actionID) or tonumber(entry.macroIndex)
    local macroName = entryCache and entryCache.displayName or entry.macroName
    local iconFileID = entryCache and tonumber(entryCache.iconFileID) or tonumber(entry.iconFileID)
    return GetMacroDisplay(macroIndex, macroName, iconFileID)
end

----------------------------------------------------------------------------------------
-- Row Pool
----------------------------------------------------------------------------------------
function ClickCasting:CreatePanelRow(parent, index)
    local row
    if _G.BackdropTemplateMixin then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    else
        row = CreateFrame("Button", nil, parent)
    end

    local rowStep = ROW_HEIGHT + ROW_SPACING
    local topOffset = -((index - 1) * rowStep) - 6
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, topOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, topOffset)
    row:EnableMouse(true)

    if row.SetBackdrop then
        row:SetBackdrop({
            edgeFile = ROW_BORDER_EDGE_FILE,
            edgeSize = 10,
            insets = {
                left = 2,
                right = 2,
                top = 2,
                bottom = 2,
            },
        })
        row:SetBackdropBorderColor(0.38, 0.38, 0.38, 0.90)
    end

    row.Background = row:CreateTexture(nil, "BACKGROUND")
    row.Background:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.Background:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    row.Background:SetColorTexture(0.08, 0.08, 0.08, 0.40)

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(22, 22)
    row.Icon:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 8, 8)
    row.Name:SetWidth(150)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Status:SetPoint("LEFT", row.Icon, "RIGHT", 8, -7)
    row.Status:SetWidth(110)
    row.Status:SetJustifyH("LEFT")

    row.Keys = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Keys:SetPoint("LEFT", row.Name, "RIGHT", 10, 0)
    row.Keys:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    row.Keys:SetJustifyH("LEFT")
    row.Keys:SetWordWrap(false)

    row.RemoveButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.RemoveButton:SetSize(20, 20)
    row.RemoveButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.RemoveButton:SetScript("OnClick", function(buttonSelf)
        local parentRow = buttonSelf:GetParent()
        if not parentRow or not parentRow.entryID then
            return
        end
        ClickCasting:RemoveTrackedEntry(parentRow.entryID)
        ClickCasting:RefreshSpellbookPanel()
    end)

    row:SetScript("OnReceiveDrag", function()
        ClickCasting:HandlePanelDrop()
    end)
    row:SetScript("OnMouseUp", function()
        if GetCursorInfo() then
            ClickCasting:HandlePanelDrop()
        end
    end)

    row:Hide()
    return row
end

function ClickCasting:EnsurePanelRows()
    if not self.spellbookPanel or not self.spellbookPanel.ListContainer then
        return
    end
    local visibleRows = GetVisibleRowCount(self.spellbookPanel)
    self.panelRows = self.panelRows or {}
    for index = 1, visibleRows do
        if not self.panelRows[index] then
            self.panelRows[index] = self:CreatePanelRow(self.spellbookPanel.ListContainer, index)
        end
    end
    for index = visibleRows + 1, #self.panelRows do
        local row = self.panelRows[index]
        if row then
            row.entryID = nil
            row:Hide()
        end
    end
end

local function ClampListOffset(offset, maxOffset)
    local value = tonumber(offset) or 0
    local cap = tonumber(maxOffset) or 0
    if cap < 0 then
        cap = 0
    end
    return max(0, min(floor(value + 0.5), cap))
end

GetVisibleRowCount = function(panel)
    if not panel or not panel.ListContainer then
        return MAX_VISIBLE_ROWS
    end

    local listHeight = panel.ListContainer:GetHeight() or 0
    local rowStep = ROW_HEIGHT + ROW_SPACING
    local usableHeight = max(ROW_HEIGHT, listHeight - 12)
    local rows = floor((usableHeight + ROW_SPACING) / rowStep)
    rows = max(1, min(rows, MAX_VISIBLE_ROWS))
    panel._visibleRows = rows
    return rows
end

----------------------------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------------------------
function ClickCasting:HandlePanelDrop()
    local cursorType, cursorInfo1, cursorInfo2, cursorInfo3 = GetCursorInfo()
    local handled = false

    if cursorType == "spell" then
        local spellID = tonumber(cursorInfo3)
        if (not spellID or spellID <= 0) and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
            local slotIndex = tonumber(cursorInfo1)
            local spellBank = cursorInfo2
            if slotIndex and spellBank ~= nil then
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                if itemInfo then
                    spellID = tonumber(itemInfo.actionID) or tonumber(itemInfo.spellID)
                end
            end
        end
        if spellID and spellID > 0 then
            self:AddTrackedSpell(spellID)
            handled = true
        end
    elseif cursorType == "macro" then
        local macroIndex = tonumber(cursorInfo1)
        if macroIndex and macroIndex > 0 then
            self:AddTrackedMacro(macroIndex)
            handled = true
        end
    end

    if handled then
        ClearCursor()
        self:RefreshSpellbookPanel()
    end
end

function ClickCasting:EnsureSpellbookPanel()
    if self.spellbookPanel then
        return self.spellbookPanel
    end

    local panel, template = CreatePanelFrame()
    self.spellbookPanel = panel
    panel._isBuilding = true
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetMovable(false)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    panel:SetFrameStrata("DIALOG")

    if template ~= "DefaultPanelTemplate" then
        ApplyNoPortraitLayout(panel)
    end
    SetPanelTitle(panel, MODERN_PANEL_TITLE)

    panel.Subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.Subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 14 + PANEL_CONTENT_LEFT_PADDING, -34)
    panel.Subtitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -34)
    panel.Subtitle:SetJustifyH("LEFT")
    panel.Subtitle:SetText("Drag spells or macros here to enable frame-scoped key mouseover casting.")

    panel.WarningText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.WarningText:SetPoint("TOPLEFT", panel.Subtitle, "BOTTOMLEFT", 0, -8)
    panel.WarningText:SetPoint("TOPRIGHT", panel.Subtitle, "BOTTOMRIGHT", 0, -8)
    panel.WarningText:SetJustifyH("LEFT")
    panel.WarningText:SetTextColor(1.0, 0.45, 0.2)
    panel.WarningText:Hide()

    panel.ListContainer = CreateFrame("Frame", nil, panel)
    panel.ListContainer:SetPoint("TOPLEFT", panel.WarningText, "BOTTOMLEFT", 0, -8)
    panel.ListContainer:SetPoint("TOPRIGHT", panel.WarningText, "BOTTOMRIGHT", -(LIST_SCROLLBAR_WIDTH + 6), -8)
    panel.ListContainer:EnableMouseWheel(true)
    panel.ListContainer:SetScript("OnMouseWheel", function(_, delta)
        local bar = panel.ScrollBar
        if not bar or not bar:IsShown() then
            return
        end
        local minValue, maxValue = bar:GetMinMaxValues()
        local direction = (delta > 0) and -1 or 1
        local nextValue = ClampListOffset(bar:GetValue() + direction, maxValue)
        if nextValue < (minValue or 0) then
            nextValue = minValue or 0
        end
        bar:SetValue(nextValue)
    end)

    panel.ScrollBar = CreateFrame("Slider", nil, panel, "UIPanelScrollBarTemplate")
    panel.ScrollBar:SetScript("OnValueChanged", function(_, value)
        if panel._suppressScrollCallbacks or panel._isBuilding then
            return
        end
        ClickCasting.panelListOffset = ClampListOffset(value, panel._maxScrollOffset or 0)
        ClickCasting:RefreshSpellbookPanel()
    end)
    panel.ScrollBar:SetPoint("TOPLEFT", panel.ListContainer, "TOPRIGHT", 2, -14)
    panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.ListContainer, "BOTTOMRIGHT", 2, 14)
    panel._suppressScrollCallbacks = true
    panel.ScrollBar:SetMinMaxValues(0, 0)
    panel.ScrollBar:SetValueStep(1)
    panel.ScrollBar:SetObeyStepOnDrag(true)
    panel.ScrollBar:SetValue(0)
    panel._suppressScrollCallbacks = false
    panel.ScrollBar:Hide()

    panel.EmptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.EmptyText:SetPoint("TOPLEFT", panel.ListContainer, "TOPLEFT", 6, -14)
    panel.EmptyText:SetPoint("TOPRIGHT", panel.ListContainer, "TOPRIGHT", -6, -14)
    panel.EmptyText:SetJustifyH("LEFT")
    panel.EmptyText:SetText("No tracked entries. Drag from the spellbook or macro window.")

    panel.Footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.Footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14 + PANEL_CONTENT_LEFT_PADDING, 14)
    panel.Footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)
    panel.Footer:SetJustifyH("LEFT")
    panel.Footer:SetText("Only Party, Raid, Target, Focus, and Boss frames are eligible.")

    panel.ListContainer:SetPoint("BOTTOMLEFT", panel.Footer, "TOPLEFT", 0, 8)
    panel.ListContainer:SetPoint("BOTTOMRIGHT", panel.Footer, "TOPRIGHT", 0, 8)

    panel:SetScript("OnReceiveDrag", function()
        ClickCasting:HandlePanelDrop()
    end)
    panel:SetScript("OnMouseUp", function()
        if GetCursorInfo() then
            ClickCasting:HandlePanelDrop()
        end
    end)
    panel:SetScript("OnShow", function()
        ClickCasting:SetPanelShown(true)
        ClickCasting:AnchorSpellbookTab()
        ClickCasting:RefreshSpellbookPanel()
    end)
    panel:SetScript("OnHide", function()
        ClickCasting:SetPanelShown(false)
        ClickCasting:AnchorSpellbookTab()
    end)

    panel._isBuilding = false
    self:EnsurePanelRows()
    return panel
end

function ClickCasting:RefreshSpellbookPanel()
    if self:IsSpellbookUISuppressed() then
        self:UpdateSpellbookUIVisibility()
        return
    end

    local panel = self:EnsureSpellbookPanel()
    if not panel or not panel:IsShown() then
        return
    end
    local visibleRows = GetVisibleRowCount(panel)

    local specCache = self:GetCurrentSpecBindingCache()
    local byEntryId = (specCache and specCache.byEntryId) or {}
    local entries = self:GetTrackedEntries()
    local ordered = {}

    for index = 1, #entries do
        ordered[#ordered + 1] = entries[index]
    end
    local function GetEntrySortState(entry)
        if suspendReason then
            return "suspended"
        end
        local entryCache = byEntryId[entry.id]
        if entryCache and type(entryCache.state) == "string" and entryCache.state ~= "" then
            return entryCache.state
        end
        return "missing"
    end
    sort(ordered, function(a, b)
        local aState = GetEntrySortState(a)
        local bState = GetEntrySortState(b)
        local aPriority = ROW_STATE_SORT_ORDER[aState] or 99
        local bPriority = ROW_STATE_SORT_ORDER[bState] or 99
        if aPriority ~= bPriority then
            return aPriority < bPriority
        end

        local aTime = tonumber(a.addedAt) or 0
        local bTime = tonumber(b.addedAt) or 0
        if aTime == bTime then
            return tostring(a.id or "") > tostring(b.id or "")
        end
        return aTime > bTime
    end)

    local totalEntries = #ordered
    local maxScrollOffset = max(0, totalEntries - visibleRows)
    local listOffset = ClampListOffset(self.panelListOffset, maxScrollOffset)
    self.panelListOffset = listOffset
    panel._maxScrollOffset = maxScrollOffset

    if panel.ScrollBar then
        panel._suppressScrollCallbacks = true
        panel.ScrollBar:SetMinMaxValues(0, maxScrollOffset)
        panel.ScrollBar:SetValue(listOffset)
        panel._suppressScrollCallbacks = false

        if maxScrollOffset > 0 then
            panel.ScrollBar:Show()
        else
            panel.ScrollBar:Hide()
        end
    end

    local suspendReason = self:GetSuspendReasonText()
    if suspendReason then
        panel.WarningText:SetText("Module suspended: " .. suspendReason)
        panel.WarningText:Show()
    else
        panel.WarningText:Hide()
    end

    self:EnsurePanelRows()
    local visibleCount = 0
    for index = 1, visibleRows do
        local row = self.panelRows[index]
        local entry = ordered[index + listOffset]
        if row and entry then
            local entryCache = byEntryId[entry.id] or {}
            local state = suspendReason and "suspended" or (entryCache.state or "missing")
            local statusText = (state ~= "suspended" and entryCache.statusText) or (STATE_TEXT[state] or STATE_TEXT.missing)
            local statusColor = STATE_COLOR[state] or STATE_COLOR.missing
            local displayName, iconFileID = self:GetEntryDisplay(entry, entryCache)

            row.entryID = entry.id
            row.Icon:SetTexture(iconFileID or 134400)
            row.Name:SetText(displayName)
            if NAME_GREY_STATES[state] then
                row.Name:SetTextColor(GREY_NAME_COLOR[1], GREY_NAME_COLOR[2], GREY_NAME_COLOR[3])
            else
                row.Name:SetTextColor(DEFAULT_NAME_COLOR[1], DEFAULT_NAME_COLOR[2], DEFAULT_NAME_COLOR[3])
            end
            row.Status:SetText(statusText)
            row.Status:SetTextColor(statusColor[1], statusColor[2], statusColor[3])
            row.Keys:SetText(JoinKeys(entryCache.keys))
            local bgColor = STATE_BG_COLOR[state] or STATE_BG_COLOR.missing
            row.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
            if state == "active" then
                row.Name:SetAlpha(1)
                row.Icon:SetDesaturation(0)
            else
                row.Name:SetAlpha(0.75)
                row.Icon:SetDesaturation(1)
            end

            row:Show()
            visibleCount = visibleCount + 1
        elseif row then
            row.entryID = nil
            row:Hide()
        end
    end

    panel.EmptyText:SetShown(#ordered == 0)
    if #ordered > visibleRows then
        panel.Footer:SetText(format("Showing %d-%d of %d entries. Use mouse wheel or scrollbar.", listOffset + 1, min(listOffset + visibleRows, #ordered), #ordered))
    else
        panel.Footer:SetText("Only Party, Raid, Target, Focus, and Boss frames are eligible.")
    end

    if visibleCount == 0 and #ordered > 0 then
        panel.EmptyText:SetShown(false)
    end
end

function ClickCasting:ToggleSpellbookPanel()
    if self:IsSpellbookUISuppressed() then
        self:UpdateSpellbookUIVisibility()
        return
    end

    local panel = self:EnsureSpellbookPanel()
    if not panel then
        return
    end

    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        self:RefreshSpellbookPanel()
    end
end

----------------------------------------------------------------------------------------
-- Spellbook Tab
----------------------------------------------------------------------------------------
function ClickCasting:AnchorSpellbookTab()
    if not self.spellbookTab then
        return
    end

    local tab = self.spellbookTab
    local panel = self.spellbookPanel
    if self:IsSpellbookUISuppressed() then
        self.panelAnchorFrame = nil
        tab:Hide()
        if panel and panel:IsShown() then
            panel:Hide()
        end
        return
    end

    tab:Show()

    local attachToPanel = panel and panel:IsShown()
    if attachToPanel then
        if self.panelAnchorFrame then
            self:ApplyPanelBehindAnchorFrame(self.panelAnchorFrame)
        end
        tab:SetParent(panel)
        tab:ClearAllPoints()
        tab:SetPoint("LEFT", panel, "TOPRIGHT", 0, TAB_Y_OFFSET)
        if self.panelAnchorFrame then
            tab:SetFrameStrata(self.panelAnchorFrame:GetFrameStrata() or "MEDIUM")
            tab:SetFrameLevel((self.panelAnchorFrame:GetFrameLevel() or 1) + 5)
        else
            tab:SetFrameLevel((panel:GetFrameLevel() or 1) + 5)
        end
        return
    end

    if _G.PlayerSpellsFrame then
        tab:SetParent(_G.PlayerSpellsFrame)
        tab:ClearAllPoints()
        tab:SetPoint("LEFT", _G.PlayerSpellsFrame, "TOPRIGHT", 0, TAB_Y_OFFSET)
        if panel then
            panel:SetParent(UIParent)
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", _G.PlayerSpellsFrame, "TOPRIGHT", PANEL_ANCHOR_X, PANEL_ANCHOR_Y)
            self.panelAnchorFrame = _G.PlayerSpellsFrame
            self:ApplyPanelBehindAnchorFrame(_G.PlayerSpellsFrame)
        end
        return
    end

    if _G.SpellBookFrame then
        tab:SetParent(_G.SpellBookFrame)
        tab:ClearAllPoints()
        local numTabs = _G.GetNumSpellTabs and _G.GetNumSpellTabs() or 0
        local lastTab = _G["SpellBookSkillLineTab" .. tostring(numTabs)]
        if lastTab then
            tab:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -17)
        else
            tab:SetPoint("LEFT", _G.SpellBookFrame, "TOPRIGHT", 0, TAB_Y_OFFSET)
        end
        if panel then
            panel:SetParent(UIParent)
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", _G.SpellBookFrame, "TOPRIGHT", PANEL_ANCHOR_X, PANEL_ANCHOR_Y)
            self.panelAnchorFrame = _G.SpellBookFrame
            self:ApplyPanelBehindAnchorFrame(_G.SpellBookFrame)
        end
        return
    end

    self.panelAnchorFrame = nil
end

function ClickCasting:EnsureSpellbookTab()
    if self.spellbookTab then
        return self.spellbookTab
    end

    local tab = CreateFrame("Button", "RefineUIClickCastingSpellbookTab", UIParent)
    tab:SetSize(32, 32)
    tab:SetNormalTexture(TAB_TEXTURE)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    tab.Background = tab:CreateTexture(nil, "BACKGROUND")
    tab.Background:SetPoint("TOPLEFT", -3, 11)
    tab.Background:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")

    tab:SetScript("OnClick", function()
        ClickCasting:ToggleSpellbookPanel()
    end)
    tab:SetScript("OnEnter", function(selfTab)
        GameTooltip:SetOwner(selfTab, "ANCHOR_RIGHT")
        GameTooltip:SetText("RefineUI Mouseover Casting")
        GameTooltip:AddLine("Open tracked mouseover-cast entries.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.spellbookTab = tab
    return tab
end

function ClickCasting:AttachSpellbookTabIfReady()
    if self:IsSpellbookUISuppressed() then
        self:UpdateSpellbookUIVisibility()
        return true
    end

    if not (_G.PlayerSpellsFrame or _G.SpellBookFrame) then
        return false
    end

    self:EnsureSpellbookTab()
    self:EnsureSpellbookPanel()
    self:AnchorSpellbookTab()

    if _G.PlayerSpellsFrame then
        local hookKey = "ClickCasting:PlayerSpellsFrame:OnShow"
        RefineUI:HookScriptOnce(hookKey, _G.PlayerSpellsFrame, "OnShow", function()
            ClickCasting:AnchorSpellbookTab()
        end)
        local hideHookKey = "ClickCasting:PlayerSpellsFrame:OnHide"
        RefineUI:HookScriptOnce(hideHookKey, _G.PlayerSpellsFrame, "OnHide", function()
            if ClickCasting.spellbookPanel then
                ClickCasting.spellbookPanel:Hide()
            end
        end)
    elseif _G.SpellBookFrame then
        local hookKey = "ClickCasting:SpellBookFrame:OnShow"
        RefineUI:HookScriptOnce(hookKey, _G.SpellBookFrame, "OnShow", function()
            ClickCasting:AnchorSpellbookTab()
        end)
        local hideHookKey = "ClickCasting:SpellBookFrame:OnHide"
        RefineUI:HookScriptOnce(hideHookKey, _G.SpellBookFrame, "OnHide", function()
            if ClickCasting.spellbookPanel then
                ClickCasting.spellbookPanel:Hide()
            end
        end)
    end

    if self:IsPanelShown() and not InCombatLockdown() and self.spellbookPanel then
        self.spellbookPanel:Show()
        self:RefreshSpellbookPanel()
    end

    self:UpdateSpellbookUIVisibility()
    return true
end

function ClickCasting:HandleSpellbookAddonLoaded(addonName)
    if addonName == "Blizzard_PlayerSpells" or addonName == "Blizzard_MacroUI" or addonName == "Clique" then
        self:AttachSpellbookTabIfReady()
    end
end

function ClickCasting:InitializeSpellbookUI()
    if not self:IsSpellbookUISuppressed() then
        self:EnsureSpellbookPanel()
    end
    self:AttachSpellbookTabIfReady()
end
