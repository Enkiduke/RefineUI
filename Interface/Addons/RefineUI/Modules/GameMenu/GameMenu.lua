----------------------------------------------------------------------------------------
-- RefineUI GameMenu
-- Description: Blizzard Game Menu integration and module manager window.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GameMenu = RefineUI:RegisterModule("GameMenu")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local HideUIPanel = HideUIPanel
local ShowUIPanel = ShowUIPanel
local InCombatLockdown = InCombatLockdown
local PlaySound = PlaySound
local ReloadUI = ReloadUI
local SOUNDKIT = SOUNDKIT
local NineSliceUtil = _G.NineSliceUtil

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local FRAME_NAME = "RefineUI_GameMenuModuleManager"
local ROW_TEMPLATE = "RefineUIGameMenuModuleRowTemplate"
local ROW_HEIGHT = 28
local PANEL_WIDTH = 560
local PANEL_HEIGHT = 620
local PANEL_TEMPLATE_CANDIDATES = {
    "ButtonFrameTemplateNoPortrait",
    "ButtonFrameTemplate",
}
local GAME_MENU_BUTTON_TEXT = "|cffffd200Refine|r|cffffffffUI|r"
local GAME_MENU_BUTTON_TEXT_DISABLED = "RefineUI"

local EVENT_KEY = {
    PLAYER_REGEN_DISABLED = "GameMenu:PLAYER_REGEN_DISABLED",
    PLAYER_REGEN_ENABLED = "GameMenu:PLAYER_REGEN_ENABLED",
}

local HOOK_KEY = {
    GAME_MENU_INIT_BUTTONS = "GameMenu:GameMenuFrame:InitButtons",
}

local MODULE_ROWS = {
    { moduleName = "AFK", label = "AFK" },
    { moduleName = "ActionBars", label = "ActionBars" },
    { moduleName = "Auras", label = "Auras" },
    { moduleName = "BuffReminder", label = "BuffReminder" },
    { moduleName = "CDM", label = "CDM" },
    { moduleName = "EncounterAchievements", label = "EncounterAchievements" },
    { moduleName = "EncounterTimeline", label = "EncounterTimeline" },
    { moduleName = "EntranceDifficulty", label = "EntranceDifficulty" },
    { moduleName = "Chat", label = "Chat" },
    { moduleName = "Maps", label = "Maps" },
    { moduleName = "UnitFrames", label = "UnitFrames" },
    { moduleName = "Nameplates", label = "Nameplates" },
    { moduleName = "MicroMenu", label = "MicroMenu" },
    { moduleName = "Blizzard", label = "Blizzard" },
    { moduleName = "Combat", label = "Combat" },
    { moduleName = "ErrorFilter", label = "ErrorFilter" },
    { moduleName = "ExperienceBar", label = "ExperienceBar" },
    { moduleName = "FadeIn", label = "FadeIn" },
    { moduleName = "GameTime", label = "GameTime" },
    { moduleName = "Dismount", label = "Dismount" },
    { moduleName = "TalkingHead", label = "TalkingHead" },
    { moduleName = "AutoPotion", label = "AutoPotion" },
    { moduleName = "AutoItemBar", label = "AutoItemBar" },
    { moduleName = "AutoOpenBar", label = "AutoOpenBar" },
    { moduleName = "ClickCasting", label = "ClickCasting" },
    { moduleName = "Tooltip", label = "Tooltip" },
    { moduleName = "AutoZoneTrack", label = "AutoZoneTrack" },
    { moduleName = "Quests", label = "Quests" },
    { moduleName = "FasterLoot", label = "FasterLoot" },
    { moduleName = "AutoConfirm", label = "AutoConfirm" },
    { moduleName = "AutoRepair", label = "AutoRepair" },
    { moduleName = "LootRules", label = "LootRules" },
    { moduleName = "Borders", label = "Borders" },
    { moduleName = "Bags", label = "Bags" },
    { moduleName = "Skins", label = "Skins" },
    { moduleName = "RadBar", label = "RadBar" },
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function AddToUISpecialFrames(frameName)
    local specialFrames = _G.UISpecialFrames
    if type(specialFrames) ~= "table" or type(frameName) ~= "string" or frameName == "" then
        return
    end

    for index = 1, #specialFrames do
        if specialFrames[index] == frameName then
            return
        end
    end

    specialFrames[#specialFrames + 1] = frameName
end

local function RegisterStandalonePanelWindow(frameName)
    local panelWindows = _G.UIPanelWindows
    if type(panelWindows) ~= "table" or type(frameName) ~= "string" or frameName == "" then
        return
    end

    if type(panelWindows[frameName]) ~= "table" then
        panelWindows[frameName] = {
            area = "center",
            pushable = 0,
            whileDead = 1,
        }
    end
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

local function SetFrameTitle(frame, titleText)
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

local function CreatePanelFrame()
    for index = 1, #PANEL_TEMPLATE_CANDIDATES do
        local template = PANEL_TEMPLATE_CANDIDATES[index]
        local ok, frame = pcall(CreateFrame, "Frame", FRAME_NAME, _G.UIParent, template)
        if ok and frame then
            return frame
        end
    end

    return CreateFrame("Frame", FRAME_NAME, _G.UIParent)
end

local function SetPanelShown(frame, shown)
    if not frame then
        return false
    end

    if shown then
        if type(ShowUIPanel) == "function" then
            return ShowUIPanel(frame, nil, _G.G_GameMenuFrameContextKey)
        end
        frame:Show()
        return true
    end

    if type(HideUIPanel) == "function" then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
    return true
end

local function FindAddOnsButton(frame)
    local buttonPool = frame and frame.buttonPool
    if not buttonPool or type(buttonPool.EnumerateActive) ~= "function" then
        return nil
    end

    for button in buttonPool:EnumerateActive() do
        if button ~= nil and button:GetText() == _G.ADDONS then
            return button
        end
    end

    return nil
end

local function ReindexButtons(frame, customButton, anchorButton)
    local targetIndex = anchorButton and anchorButton.layoutIndex
    local buttonPool = frame and frame.buttonPool
    if type(targetIndex) ~= "number" or not buttonPool or type(buttonPool.EnumerateActive) ~= "function" then
        return
    end

    for button in buttonPool:EnumerateActive() do
        if button ~= customButton and type(button.layoutIndex) == "number" and button.layoutIndex >= targetIndex then
            button.layoutIndex = button.layoutIndex + 1
        end
    end

    customButton.layoutIndex = targetIndex
    customButton.topPadding = anchorButton.topPadding
    anchorButton.topPadding = nil
    if frame.MarkDirty then
        frame:MarkDirty()
    end
end

local function UpdateButtonText(button, enabled)
    if not button then
        return
    end

    if enabled then
        button:SetText(GAME_MENU_BUTTON_TEXT)
    else
        button:SetText(GAME_MENU_BUTTON_TEXT_DISABLED)
    end
end

local function UpdateRowVisual(row, enabled)
    local title = row and (row.RefineTitle or row.Title)
    if not title then
        return
    end

    if enabled then
        title:SetTextColor(1, 1, 1)
    else
        title:SetTextColor(0.62, 0.62, 0.62)
    end
end

local function UpdateModuleRowState(row, enabled)
    if not row then
        return
    end

    if row.Checkbox then
        row.Checkbox:SetChecked(enabled == true)
    end

    UpdateRowVisual(row, enabled == true)
end

local function UpdateReloadControls(frame)
    if not frame then
        return
    end

    local shown = frame.reloadRequired == true

    if frame.ReloadNotice then
        frame.ReloadNotice:SetShown(shown)
    end

    if frame.ReloadButton then
        frame.ReloadButton:SetShown(shown)
    end
end

local function PlayCheckboxSound(enabled)
    if not PlaySound or not SOUNDKIT then
        return
    end

    local soundKit = enabled and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    if soundKit then
        PlaySound(soundKit)
    end
end

local function EnsureRowTitle(row)
    if not row then
        return nil
    end

    if row.RefineTitle then
        return row.RefineTitle
    end

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetJustifyH("LEFT")
    title:SetPoint("LEFT", row, "LEFT", 18, 0)
    if row.Checkbox then
        title:SetPoint("RIGHT", row.Checkbox, "LEFT", -10, 0)
    else
        title:SetPoint("RIGHT", row, "RIGHT", -46, 0)
    end
    title:Show()

    if row.Title and row.Title.Hide then
        row.Title:Hide()
    end

    row.RefineTitle = title
    return title
end

----------------------------------------------------------------------------------------
-- Module State
----------------------------------------------------------------------------------------
function GameMenu:GetDisplayedModuleEnabled(moduleName)
    local pendingState = self.pendingModuleState
    local value
    if type(pendingState) == "table" then
        value = pendingState[moduleName]
    end
    if type(value) == "boolean" then
        return value
    end

    return RefineUI:IsModuleStartupEnabled(moduleName)
end

----------------------------------------------------------------------------------------
-- Panel UI
----------------------------------------------------------------------------------------
function GameMenu:ResetModuleRow(row)
    if not row then
        return
    end

    row.moduleName = nil
    row:EnableMouse(false)
    row:SetScript("OnMouseUp", nil)
    if row.Checkbox then
        row.Checkbox:EnableMouse(false)
        UpdateModuleRowState(row, false)
        row.Checkbox:SetScript("OnClick", nil)
    end
    local title = row.RefineTitle or row.Title
    if title then
        title:SetText("")
        title:SetTextColor(1, 1, 1)
    end
end

function GameMenu:ToggleModuleRow(row)
    if not row then
        return
    end

    local moduleName = row.moduleName
    if type(moduleName) ~= "string" or moduleName == "" then
        return
    end

    if InCombatLockdown() then
        UpdateModuleRowState(row, self:GetDisplayedModuleEnabled(moduleName))
        return
    end

    local nextEnabled = not self:GetDisplayedModuleEnabled(moduleName)
    self.pendingModuleState = self.pendingModuleState or {}
    self.pendingModuleState[moduleName] = nextEnabled
    RefineUI:SetSavedModuleEnabled(moduleName, nextEnabled)
    UpdateModuleRowState(row, nextEnabled)
    PlayCheckboxSound(nextEnabled)

    local frame = self.moduleFrame
    if frame then
        frame.reloadRequired = true
        UpdateReloadControls(frame)
    end
end

function GameMenu:InitializeModuleRow(row, elementData)
    if not row or type(elementData) ~= "table" or not row.Checkbox then
        return
    end

    local title = EnsureRowTitle(row)
    if not title then
        return
    end

    row.moduleName = elementData.moduleName
    title:SetText(elementData.label or elementData.moduleName or "")
    title:Show()

    local enabled = self:GetDisplayedModuleEnabled(elementData.moduleName)
    UpdateModuleRowState(row, enabled)

    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, buttonName)
        if buttonName ~= "LeftButton" then
            return
        end

        self:ToggleModuleRow(row)
    end)

    row.Checkbox:EnableMouse(false)
    row.Checkbox:SetScript("OnClick", nil)
end

function GameMenu:EnsureModuleListView(frame)
    if not frame or frame.moduleListViewInitialized then
        return frame and frame.moduleListViewInitialized == true
    end

    if type(_G.ScrollUtil) ~= "table" or type(_G.ScrollUtil.InitScrollBoxListWithScrollBar) ~= "function" then
        return false
    end
    if type(_G.CreateScrollBoxListLinearView) ~= "function" then
        return false
    end

    local view = _G.CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer(ROW_TEMPLATE, function(row, elementData)
        self:InitializeModuleRow(row, elementData)
    end)
    view:SetElementResetter(function(row)
        self:ResetModuleRow(row)
    end)
    view:SetPadding(0, 0, 0, 0, 0)

    local ok = pcall(_G.ScrollUtil.InitScrollBoxListWithScrollBar, frame.ScrollBox, frame.ScrollBar, view)
    if not ok then
        return false
    end

    frame.moduleListView = view
    frame.moduleListViewInitialized = true
    return true
end

function GameMenu:PopulateModuleRows(frame)
    if not frame or type(_G.CreateDataProvider) ~= "function" then
        return
    end

    local dataProvider = _G.CreateDataProvider()
    for index = 1, #MODULE_ROWS do
        dataProvider:Insert(MODULE_ROWS[index])
    end

    frame.ScrollBox:SetDataProvider(dataProvider)
end

function GameMenu:RefreshModulePanel()
    local frame = self.moduleFrame
    if not frame then
        return
    end

    UpdateReloadControls(frame)

    if not self:EnsureModuleListView(frame) then
        frame.EmptyText:SetShown(true)
        frame.ScrollBox:Hide()
        frame.ScrollBar:Hide()
        return
    end

    frame.EmptyText:Hide()
    frame.ScrollBox:Show()
    frame.ScrollBar:Show()
    self:PopulateModuleRows(frame)
end

function GameMenu:CreateModulePanel()
    if self.moduleFrame then
        return self.moduleFrame
    end

    local frame = CreatePanelFrame()
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    ApplyNoPortraitLayout(frame)
    SetFrameTitle(frame, "RefineUI Modules")
    AddToUISpecialFrames(FRAME_NAME)
    RegisterStandalonePanelWindow(FRAME_NAME)

    local inset = frame.Inset or frame

    local background = inset:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("character-panel-background")
    background:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    background:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    background:SetAlpha(0.95)
    frame.Background = background

    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)
    scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, 36)
    frame.ScrollBox = scrollBox

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 2)
    if scrollBar.SetHideIfUnscrollable then
        scrollBar:SetHideIfUnscrollable(true)
    end
    if scrollBar.SetInterpolateScroll then
        scrollBar:SetInterpolateScroll(true)
    end
    frame.ScrollBar = scrollBar

    local reloadNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reloadNotice:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 18, 12)
    reloadNotice:SetText(_G.REQUIRES_RELOAD or "Requires Reload")
    reloadNotice:Hide()
    frame.ReloadNotice = reloadNotice

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reloadButton:SetSize(110, 22)
    reloadButton:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -18, 8)
    reloadButton:SetText(_G.RELOADUI or "Reload")
    reloadButton:SetScript("OnClick", function()
        if not InCombatLockdown() and type(ReloadUI) == "function" then
            ReloadUI()
        end
    end)
    reloadButton:Hide()
    frame.ReloadButton = reloadButton

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 18, -18)
    emptyText:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", -18, 18)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetJustifyV("MIDDLE")
    emptyText:SetText("Module list is unavailable.")
    emptyText:Hide()
    frame.EmptyText = emptyText

    frame:SetScript("OnShow", function()
        GameMenu:RefreshModulePanel()
    end)

    self.moduleFrame = frame
    return frame
end

function GameMenu:OpenModulePanel()
    if InCombatLockdown() then
        return false
    end

    local frame = self:CreateModulePanel()
    if not frame then
        return false
    end

    self:RefreshModulePanel()
    return SetPanelShown(frame, true)
end

----------------------------------------------------------------------------------------
-- Game Menu Integration
----------------------------------------------------------------------------------------
function GameMenu:InjectGameMenuButton(frame)
    if not frame or type(frame.AddButton) ~= "function" then
        return
    end

    local enabled = not InCombatLockdown()
    local button = frame:AddButton("RefineUI", function()
        if InCombatLockdown() then
            return
        end

        if _G.GameMenuFrame then
            HideUIPanel(_G.GameMenuFrame)
        end

        GameMenu:OpenModulePanel()
    end, not enabled)

    UpdateButtonText(button, enabled)

    local addOnsButton = FindAddOnsButton(frame)
    if addOnsButton then
        ReindexButtons(frame, button, addOnsButton)
    end
end

function GameMenu:RefreshGameMenuButtonState()
    local frame = _G.GameMenuFrame
    if frame and frame:IsShown() and frame.InitButtons then
        frame:InitButtons()
    end
end

function GameMenu:InstallGameMenuHook()
    if not _G.GameMenuFrame then
        return
    end

    RefineUI:HookOnce(HOOK_KEY.GAME_MENU_INIT_BUTTONS, _G.GameMenuFrame, "InitButtons", function(frame)
        GameMenu:InjectGameMenuButton(frame)
    end)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function GameMenu:OnEnable()
    self:InstallGameMenuHook()
    self:CreateModulePanel()

    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        if self.moduleFrame and self.moduleFrame:IsShown() then
            SetPanelShown(self.moduleFrame, false)
        end
        self:RefreshGameMenuButtonState()
    end, EVENT_KEY.PLAYER_REGEN_DISABLED)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        self:RefreshGameMenuButtonState()
    end, EVENT_KEY.PLAYER_REGEN_ENABLED)
end
