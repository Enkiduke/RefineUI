----------------------------------------------------------------------------------------
-- RefineUI MouseoverCasting Spellbook UI
-- Description: Spellbook tab and drag/drop panel for tracked mouseover-cast entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local MouseoverCasting = RefineUI:GetModule("MouseoverCasting")
if not MouseoverCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local ClearCursor = ClearCursor
local CreateDataProvider = CreateDataProvider
local CreateFrame = CreateFrame
local CreateScrollBoxListLinearView = CreateScrollBoxListLinearView
local GameTooltip = GameTooltip
local GetBindingText = GetBindingText
local GetCursorInfo = GetCursorInfo
local GetMacroInfo = GetMacroInfo
local InCombatLockdown = InCombatLockdown
local PlaySound = PlaySound
local ScrollUtil = ScrollUtil
local SOUNDKIT = SOUNDKIT
local concat = table.concat
local format = string.format
local max = math.max
local sort = table.sort
local tonumber = tonumber
local tostring = tostring

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PANEL_SPELLBOOK_OVERLAP = 20
-- Visible width matches Blizzard's ClickBindingFrame, so its row art fits as designed.
local PANEL_WIDTH = 440 + PANEL_SPELLBOOK_OVERLAP
local PANEL_HEIGHT = 460
local PANEL_CONTENT_LEFT = PANEL_SPELLBOOK_OVERLAP + 12
local PANEL_ANCHOR_Y = -6
local PANEL_BEHIND_LEVEL_OFFSET = 20
local ROW_HEIGHT = 46
local TAB_Y_OFFSET = -120
local TAB_ICON_SIZE = 32
local TAB_TEXTURE = "Interface\\AddOns\\RefineUI\\Media\\Textures\\mouseovercast"
local FALLBACK_ICON = 134400
local PANEL_TITLE = "Mouseover Casting"
local HELP_TEXT = "Hover a unit frame and press your keybind to cast on it."
local FOOTER_TEXT = "Works on party, raid, target, focus, and boss frames."

-- Last list row: the drop target for new entries.
local ADD_ROW = { isAddRow = true }
local NO_CACHE = {}

local STATE_SORT_ORDER = {
    active = 1,
    unbound = 2,
    missing = 3,
    conflicted = 4,
    unknown = 5,
    otherspec = 6,
}

-- Why an entry does nothing, shown in place of its keybinds.
local REASON_TEXT = {
    spell_missing = "Not known",
    spell_not_known_for_spec = "Not known",
    spell_valid_current_spec_not_known = "Not learned",
    spell_not_on_bar = "Not on your action bars",
    macro_not_on_bar = "Not on your action bars",
    slot_has_no_binding = "Action bar slot has no keybind",
    shadowed = "Keybind used by another entry",
    macro_missing = "Macro not found",
    missing = "Macro not found",
    ambiguous = "Several macros share this name",
}

-- Known and tracked, but without a usable keybind: shown red. Other reasons are grey.
local KEYBIND_PROBLEM_REASONS = {
    spell_not_on_bar = true,
    macro_not_on_bar = true,
    slot_has_no_binding = true,
    shadowed = true,
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function GetEntryDisplay(entry, entryCache)
    if entry.kind == "spell" then
        local spellID = tonumber(entry.spellID) or tonumber(entry.baseSpellID)
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, info.iconID
        end
        return format("Spell %s", tostring(spellID)), FALLBACK_ICON
    end

    local macroIndex = tonumber(entryCache.actionID) or tonumber(entry.macroIndex)
    local name, iconFileID = GetMacroInfo(macroIndex or 0)
    return name or entryCache.displayName or entry.macroName or format("Macro %s", tostring(macroIndex)),
        tonumber(iconFileID) or tonumber(entryCache.iconFileID) or tonumber(entry.iconFileID) or FALLBACK_ICON
end

local function FormatKeys(keys)
    local texts = {}
    for index = 1, #keys do
        texts[index] = GetBindingText(keys[index])
    end
    return concat(texts, ", ")
end

-- Returns the status line and whether a known entry lacks a usable keybind (shown red).
local function GetStatusText(entryCache, suspended)
    if suspended then
        return DISABLED_FONT_COLOR:WrapTextInColorCode("Paused"), false
    end

    local state = entryCache.state
    if state == "active" then
        return FormatKeys(entryCache.keys), false
    elseif not state then
        -- Resolved on the next rebuild, which waits for combat to end.
        return DISABLED_FONT_COLOR:WrapTextInColorCode("Pending"), false
    elseif state == "otherspec" then
        return DISABLED_FONT_COLOR:WrapTextInColorCode(format("Spec: %s", entryCache.statusText)), false
    end

    local reason = entryCache.reason
    local text = REASON_TEXT[reason] or "Unavailable"
    if KEYBIND_PROBLEM_REASONS[reason] then
        return RED_FONT_COLOR:WrapTextInColorCode(text), true
    end
    return DISABLED_FONT_COLOR:WrapTextInColorCode(text), false
end

-- Active entries first, then newest first.
local function CompareElements(a, b)
    local aOrder = STATE_SORT_ORDER[a.cache.state] or 99
    local bOrder = STATE_SORT_ORDER[b.cache.state] or 99
    if aOrder ~= bOrder then
        return aOrder < bOrder
    end

    local aTime = tonumber(a.entry.addedAt) or 0
    local bTime = tonumber(b.entry.addedAt) or 0
    if aTime == bTime then
        return tostring(a.entry.id) > tostring(b.entry.id)
    end
    return aTime > bTime
end

local function ApplyPanelBehindAnchorFrame(panel, anchorFrame)
    panel:SetFrameStrata(anchorFrame:GetFrameStrata() or "MEDIUM")
    panel:SetFrameLevel(max(0, (anchorFrame:GetFrameLevel() or 1) - PANEL_BEHIND_LEVEL_OFFSET))
end

local function OnDropTargetMouseUp()
    if GetCursorInfo() then
        MouseoverCasting:HandlePanelDrop()
    end
end

local function OnDropTargetReceiveDrag()
    MouseoverCasting:HandlePanelDrop()
end

local function SetDropTargetScripts(frame)
    frame:SetScript("OnReceiveDrag", OnDropTargetReceiveDrag)
    frame:SetScript("OnMouseUp", OnDropTargetMouseUp)
end

----------------------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------------------
-- Rows follow Blizzard's ClickBindingLineTemplate (Blizzard_ClickBindingUI).
local function OnRowEnter(row)
    local entry = row.entry
    if not entry then
        return
    end

    row.DeleteButton:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.kind == "spell" then
        GameTooltip:SetSpellByID(entry.spellID)
    else
        GameTooltip:SetText(row.displayName)
    end
    GameTooltip:Show()
end

local function OnRowLeave(row)
    GameTooltip:Hide()
    if not row.DeleteButton:IsMouseMotionFocus() then
        row.DeleteButton:Hide()
    end
end

local function OnDeleteClick(button)
    local entry = button:GetParent().entry
    if entry then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        GameTooltip:Hide()
        MouseoverCasting:RemoveTrackedEntry(entry.id)
        MouseoverCasting:RefreshSpellbookPanel()
    end
end

local function SetupRow(row)
    row.Background = row:CreateTexture(nil, "BACKGROUND")
    row.Background:SetAtlas("ClickCastList-ButtonBackground", true)
    row.Background:SetPoint("CENTER")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(35, 35)
    row.Icon:SetPoint("LEFT")

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 5, 7)
    row.Name:SetPoint("RIGHT", row, "RIGHT", -30, 7)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetMaxLines(1)

    row.Status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Status:SetPoint("LEFT", row.Icon, "RIGHT", 5, -8)
    row.Status:SetPoint("RIGHT", row, "RIGHT", -8, -8)
    row.Status:SetJustifyH("LEFT")
    row.Status:SetMaxLines(1)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("ClickCastList-ButtonHighlight", true)
    highlight:SetPoint("CENTER")
    highlight:SetBlendMode("ADD")

    -- Bare delete icon, as on Blizzard's housing UI (Blizzard_HousingHouseFinder).
    local deleteButton = CreateFrame("Button", nil, row)
    deleteButton:SetSize(16, 16)
    deleteButton:SetPoint("CENTER", row, "RIGHT", -12, 8)
    deleteButton:SetNormalAtlas("common-icon-delete")
    deleteButton:SetHighlightAtlas("common-icon-delete", "ADD")
    deleteButton:SetScript("OnClick", OnDeleteClick)
    deleteButton:SetScript("OnLeave", deleteButton.Hide)
    row.DeleteButton = deleteButton

    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)
    SetDropTargetScripts(row)
end

local function InitRow(row, data)
    if not row.Icon then
        SetupRow(row)
    end
    row.DeleteButton:Hide()

    if data.isAddRow then
        row.entry = nil
        -- Same empty-slot art as the Radial Bar.
        row.Icon:SetAtlas("cdm-empty")
        row.Icon:SetDesaturated(false)
        row.Icon:SetVertexColor(WHITE_FONT_COLOR:GetRGB())
        row.Name:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("Add a spell or macro"))
        row.Status:SetText(DISABLED_FONT_COLOR:WrapTextInColorCode("Drag it here from your spellbook or macros"))
        return
    end

    local entry, entryCache = data.entry, data.cache
    local isActive = entryCache.state == "active" and not data.suspended
    local displayName, iconFileID = GetEntryDisplay(entry, entryCache)
    local statusText, isProblem = GetStatusText(entryCache, data.suspended)
    row.entry = entry
    row.displayName = displayName
    row.Icon:SetTexture(iconFileID)
    row.Icon:SetDesaturated(not isActive)
    -- Fixable problems tint the desaturated icon red; other specs stay grey.
    row.Icon:SetVertexColor((isProblem and RED_FONT_COLOR or WHITE_FONT_COLOR):GetRGB())
    row.Name:SetText(displayName)
    row.Name:SetTextColor((isActive and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB())
    row.Status:SetText(statusText)
end

----------------------------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------------------------
function MouseoverCasting:HandlePanelDrop()
    local cursorType, cursorInfo1, cursorInfo2, cursorInfo3 = GetCursorInfo()
    local handled = false

    if cursorType == "spell" then
        local spellID = tonumber(cursorInfo3)
        if not spellID or spellID <= 0 then
            local slotIndex = tonumber(cursorInfo1)
            if slotIndex and cursorInfo2 ~= nil then
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, cursorInfo2)
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
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ClearCursor()
        self:RefreshSpellbookPanel()
    end
end

function MouseoverCasting:EnsureSpellbookPanel()
    if self.spellbookPanel then
        return self.spellbookPanel
    end

    local panel = CreateFrame("Frame", "RefineUI_MouseoverCastingPanel", UIParent, "DefaultPanelTemplate")
    self.spellbookPanel = panel
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    panel:SetFrameStrata("DIALOG")
    panel:SetTitle(PANEL_TITLE)

    panel.HelpText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.HelpText:SetPoint("TOPLEFT", PANEL_CONTENT_LEFT, -32)
    panel.HelpText:SetPoint("TOPRIGHT", -14, -32)
    panel.HelpText:SetJustifyH("LEFT")
    panel.HelpText:SetText(HELP_TEXT)

    -- Suspension replaces the footer text, so the list never shifts.
    panel.Footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.Footer:SetPoint("BOTTOMLEFT", PANEL_CONTENT_LEFT, 14)
    panel.Footer:SetPoint("BOTTOMRIGHT", -14, 14)
    panel.Footer:SetJustifyH("LEFT")

    -- List box styled like Blizzard's click binding list; it starts below the help text however it wraps.
    panel.ListBackground = CreateFrame("Frame", nil, panel, "TooltipBackdropTemplate")
    panel.ListBackground:SetPoint("TOPLEFT", panel.HelpText, "BOTTOMLEFT", -6, -10)
    panel.ListBackground:SetPoint("BOTTOMRIGHT", -31, 34)
    panel.ListBackground:SetBackdropColor(BLACK_FONT_COLOR:GetRGB())
    panel.ListBackground:SetBackdropBorderColor(DARKGRAY_COLOR:GetRGB())

    -- Child of the list box so the rows always draw above its backdrop.
    panel.ScrollBox = CreateFrame("Frame", nil, panel.ListBackground, "WowScrollBoxList")
    panel.ScrollBox:SetPoint("TOPLEFT", panel.ListBackground, "TOPLEFT", 5, -5)
    panel.ScrollBox:SetPoint("BOTTOMRIGHT", panel.ListBackground, "BOTTOMRIGHT", -5, 5)
    SetDropTargetScripts(panel.ScrollBox)

    panel.ScrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    panel.ScrollBar:SetPoint("TOPLEFT", panel.ListBackground, "TOPRIGHT", 5, -5)
    panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.ListBackground, "BOTTOMRIGHT", 5, 5)

    local view = CreateScrollBoxListLinearView(7, 7, 7, 7, 4)
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(panel.ScrollBox, panel.ScrollBar, view)

    SetDropTargetScripts(panel)
    panel:SetScript("OnShow", function()
        MouseoverCasting:SetPanelShown(true)
        MouseoverCasting:AnchorSideTab()
        MouseoverCasting:RefreshSpellbookPanel()
    end)
    panel:SetScript("OnHide", function()
        GameTooltip:Hide()
        MouseoverCasting:SetPanelShown(false)
        MouseoverCasting:AnchorSideTab()
    end)

    return panel
end

function MouseoverCasting:RefreshSpellbookPanel()
    local panel = self.spellbookPanel
    if not panel or not panel:IsShown() then
        return
    end

    local byEntryId = self.runtimeActiveByEntry or NO_CACHE
    local suspendReason = self:GetSuspendReasonText()
    local suspended = suspendReason ~= nil
    local entries = self:GetTrackedEntries()
    local elements = {}
    for index = 1, #entries do
        local entry = entries[index]
        elements[index] = {
            entry = entry,
            cache = byEntryId[entry.id] or NO_CACHE,
            suspended = suspended,
        }
    end
    sort(elements, CompareElements)
    elements[#elements + 1] = ADD_ROW

    panel.ScrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    if suspended then
        panel.Footer:SetText(RED_FONT_COLOR:WrapTextInColorCode("Paused: " .. suspendReason))
    else
        panel.Footer:SetText(FOOTER_TEXT)
    end
end

function MouseoverCasting:ToggleSpellbookPanel()
    local panel = self.spellbookPanel
    -- OnShow refreshes the panel.
    panel:SetShown(not panel:IsShown())
end

----------------------------------------------------------------------------------------
-- Spellbook Tab
----------------------------------------------------------------------------------------
function MouseoverCasting:AnchorSideTab()
    local tab = self.sideTab
    if not tab then
        return
    end

    local panel = self.spellbookPanel
    local anchorFrame = _G.PlayerSpellsFrame
    local panelShown = panel:IsShown()
    tab.SelectedTexture:SetShown(panelShown)

    if panelShown then
        ApplyPanelBehindAnchorFrame(panel, anchorFrame)
        tab:SetParent(panel)
        tab:ClearAllPoints()
        -- Same height as on the spellbook; the panel sits PANEL_ANCHOR_Y below its top.
        tab:SetPoint("TOPLEFT", panel, "TOPRIGHT", 0, TAB_Y_OFFSET - PANEL_ANCHOR_Y)
        tab:SetFrameStrata(anchorFrame:GetFrameStrata() or "MEDIUM")
        tab:SetFrameLevel((anchorFrame:GetFrameLevel() or 1) + 5)
        return
    end

    tab:SetParent(anchorFrame)
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 0, TAB_Y_OFFSET)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", -PANEL_SPELLBOOK_OVERLAP, PANEL_ANCHOR_Y)
    ApplyPanelBehindAnchorFrame(panel, anchorFrame)
end

function MouseoverCasting:EnsureSideTab()
    if self.sideTab then
        return self.sideTab
    end

    -- Blizzard's side tab, as on the quest log.
    local tab = CreateFrame("Frame", "RefineUI_MouseoverCastingSideTab", UIParent, "LargeSideTabButtonTemplate")
    tab.tooltipText = PANEL_TITLE
    tab.Icon:SetTexture(TAB_TEXTURE)
    tab.Icon:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
    tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if button == "LeftButton" and upInside then
            MouseoverCasting:ToggleSpellbookPanel()
        end
    end)

    self.sideTab = tab
    return tab
end

function MouseoverCasting:AttachToPlayerSpellsFrame()
    local playerSpellsFrame = _G.PlayerSpellsFrame
    if not playerSpellsFrame then
        return
    end

    self:EnsureSpellbookPanel()
    self:EnsureSideTab()
    self:AnchorSideTab()

    RefineUI:HookScriptOnce("MouseoverCasting:PlayerSpellsFrame:OnShow", playerSpellsFrame, "OnShow", function()
        MouseoverCasting:AnchorSideTab()
    end)
    RefineUI:HookScriptOnce("MouseoverCasting:PlayerSpellsFrame:OnHide", playerSpellsFrame, "OnHide", function()
        MouseoverCasting.spellbookPanel:Hide()
    end)

    if self:IsPanelShown() and not InCombatLockdown() then
        self.spellbookPanel:Show()
    end
end
