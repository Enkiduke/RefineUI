----------------------------------------------------------------------------------------
-- EntranceDifficulty Component: UI
-- Description: Minimal text selector, title actions, bordered difficulty buttons.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EntranceDifficulty = RefineUI:GetModule("EntranceDifficulty")
if not EntranceDifficulty then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local HasLFGRestrictions = HasLFGRestrictions
local IsControlKeyDown = IsControlKeyDown
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local StaticPopup_Show = StaticPopup_Show
local UIParent = UIParent
local UnitIsGroupLeader = UnitIsGroupLeader
local floor = math.floor
local format = string.format
local max = math.max
local min = math.min
local tostring = tostring
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CARD_WIDTH_MIN = 200
local CARD_WIDTH_MAX = 760
local CARD_PADDING = 10
local HEADER_HEIGHT = 32
local BUTTON_HEIGHT = 20
local BUTTON_GAP = 8
local BUTTON_SIDE_PADDING = 10
local TEXT_GAP = 6
local FOOTER_HEIGHT = 14
local FADE_DURATION = 0.16
local DISABLED_ALPHA = 0.7

local COLOR = {
    Active = { 1.00, 0.82, 0.00, 1.00 },
    Available = { 0.20, 1.00, 0.20, 1.00 },
    Border = { 0.36, 0.36, 0.36, 0.90 },
    Complete = { 1.00, 0.20, 0.20, 1.00 },
    HoverBorder = { 0.72, 0.72, 0.72, 0.95 },
    Normal = { 0.82, 0.82, 0.82, 1.00 },
    Progress = { 1.00, 1.00, 1.00, 1.00 },
    Title = { 1.00, 0.96, 0.84, 1.00 },
    TitleHover = { 1.00, 0.82, 0.00, 1.00 },
    Unavailable = { 1.00, 0.20, 0.20, 1.00 },
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsAddonLoaded(addonName)
    if type(_G.C_AddOns) == "table" and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
        return _G.C_AddOns.IsAddOnLoaded(addonName) == true
    end

    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(addonName) == true
    end

    return false
end

local function LoadAddon(addonName)
    if IsAddonLoaded(addonName) then
        return true
    end

    if type(_G.C_AddOns) == "table" and type(_G.C_AddOns.LoadAddOn) == "function" then
        local ok, loaded = pcall(_G.C_AddOns.LoadAddOn, addonName)
        return ok and (loaded == true or IsAddonLoaded(addonName))
    end

    local loadAddOn = _G.UIParentLoadAddOn or _G.LoadAddOn
    if type(loadAddOn) == "function" then
        local ok, loaded = pcall(loadAddOn, addonName)
        if ok then
            return loaded == true or IsAddonLoaded(addonName)
        end
    end

    return false
end

local function HideOwnedTooltip(owner)
    if GameTooltip and GameTooltip:GetOwner() == owner then
        GameTooltip:Hide()
    end
end

local function GetFontStringWidth(fontString)
    if not fontString then
        return 0
    end

    if type(fontString.GetUnboundedStringWidth) == "function" then
        return fontString:GetUnboundedStringWidth() or 0
    end

    if type(fontString.GetStringWidth) == "function" then
        return fontString:GetStringWidth() or 0
    end

    return 0
end

local function StyleText(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function" then
        return
    end

    local fontPath, fontSize = fontString:GetFont()
    if type(fontPath) == "string" and fontPath ~= "" and type(fontSize) == "number" and fontSize > 0 then
        fontString:SetFont(fontPath, fontSize, "OUTLINE")
    end

    if type(fontString.SetShadowOffset) == "function" then
        fontString:SetShadowOffset(1, -1)
    end

    if type(fontString.SetShadowColor) == "function" then
        fontString:SetShadowColor(0, 0, 0, 1)
    end
end

local function StyleTitleText(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function" then
        return
    end

    local fontPath, fontSize = fontString:GetFont()
    if type(fontPath) == "string" and fontPath ~= "" and type(fontSize) == "number" and fontSize > 0 then
        fontString:SetFont(fontPath, fontSize + 2, "OUTLINE")
    end

    if type(fontString.SetShadowOffset) == "function" then
        fontString:SetShadowOffset(1, -1)
    end

    if type(fontString.SetShadowColor) == "function" then
        fontString:SetShadowColor(0, 0, 0, 1)
    end
end

local function StyleTooltipText(fontString)
    if not fontString or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function" then
        return
    end

    local fontPath, fontSize = fontString:GetFont()
    if type(fontPath) == "string" and fontPath ~= "" and type(fontSize) == "number" and fontSize > 0 then
        fontString:SetFont(fontPath, fontSize, "OUTLINE")
    end

    if type(fontString.SetShadowOffset) == "function" then
        fontString:SetShadowOffset(1, -1)
    end

    if type(fontString.SetShadowColor) == "function" then
        fontString:SetShadowColor(0, 0, 0, 1)
    end
end

local function StyleTooltipLines(tooltip)
    local tooltipModule = RefineUI:GetModule("Tooltip")
    if tooltipModule and type(tooltipModule.StyleTooltipFrameLines) == "function" then
        tooltipModule:StyleTooltipFrameLines(tooltip)
        return
    end

    if not tooltip or type(tooltip.GetName) ~= "function" or type(tooltip.NumLines) ~= "function" then
        return
    end

    local tooltipName = tooltip:GetName()
    if type(tooltipName) ~= "string" or tooltipName == "" then
        return
    end

    for lineIndex = 1, tooltip:NumLines() do
        StyleTooltipText(_G[tooltipName .. "TextLeft" .. lineIndex])
        StyleTooltipText(_G[tooltipName .. "TextRight" .. lineIndex])
    end
end

local function HasLFGRestriction()
    if type(HasLFGRestrictions) == "function" then
        return HasLFGRestrictions() == true
    end

    if type(_G.UnitPopupSharedUtil) == "table" and type(_G.UnitPopupSharedUtil.HasLFGRestrictions) == "function" then
        return _G.UnitPopupSharedUtil.HasLFGRestrictions() == true
    end

    return false
end

local function CanResetInstances()
    local inInstance = select(1, IsInInstance())
    if inInstance then
        return false
    end

    if IsInGroup() and not UnitIsGroupLeader("player") then
        return false
    end

    if HasLFGRestriction() then
        return false
    end

    return true
end

local function BuildButtonLines(buttons, maxContentWidth)
    local lines = {}
    local currentLine

    for index = 1, #buttons do
        local button = buttons[index]
        local buttonWidth = button.layoutWidth or 70

        if not currentLine then
            currentLine = {
                buttons = {},
                width = 0,
            }
            lines[#lines + 1] = currentLine
        end

        local nextWidth = currentLine.width
        if #currentLine.buttons > 0 then
            nextWidth = nextWidth + BUTTON_GAP
        end

        if #currentLine.buttons > 0 and nextWidth + buttonWidth > maxContentWidth then
            currentLine = {
                buttons = {},
                width = 0,
            }
            lines[#lines + 1] = currentLine
            nextWidth = 0
        end

        currentLine.buttons[#currentLine.buttons + 1] = button
        currentLine.width = nextWidth + buttonWidth
    end

    return lines
end

local function MeasureButtonWidth(button)
    local difficultyWidth = GetFontStringWidth(button.DifficultyText)
    local progressWidth = GetFontStringWidth(button.ProgressText)
    return floor(difficultyWidth + progressWidth + (BUTTON_SIDE_PADDING * 2) + TEXT_GAP)
end

----------------------------------------------------------------------------------------
-- UI Creation
----------------------------------------------------------------------------------------
function EntranceDifficulty:EnsureUI()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", self.FRAME_NAME, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(60)
    frame:SetClampedToScreen(true)
    frame:SetPoint("TOP", UIParent, "TOP", 0, RefineUI:Scale(-50))
    frame:SetSize(RefineUI:Scale(CARD_WIDTH_MIN), RefineUI:Scale(54))
    frame:SetAlpha(0)
    frame:Hide()

    frame.TitleButton = CreateFrame("Button", nil, frame)
    frame.TitleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.TitleButton:SetPoint("TOP", frame, "TOP", 0, -4)
    frame.TitleButton:SetHeight(RefineUI:Scale(20))

    frame.TitleText = frame.TitleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.TitleText:SetPoint("CENTER", frame.TitleButton, "CENTER", 0, 0)
    frame.TitleText:SetJustifyH("CENTER")
    frame.TitleText:SetTextColor(COLOR.Title[1], COLOR.Title[2], COLOR.Title[3], COLOR.Title[4])
    StyleTitleText(frame.TitleText)

    frame.TitleButton:SetScript("OnEnter", function(button)
        EntranceDifficulty:ShowTitleTooltip(button)
    end)
    frame.TitleButton:SetScript("OnLeave", function(button)
        EntranceDifficulty:HideTitleTooltip(button)
        frame.TitleText:SetTextColor(COLOR.Title[1], COLOR.Title[2], COLOR.Title[3], COLOR.Title[4])
    end)
    frame.TitleButton:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if IsControlKeyDown() and CanResetInstances() and type(StaticPopup_Show) == "function" then
                StaticPopup_Show("CONFIRM_RESET_INSTANCES")
            end
            return
        end

        EntranceDifficulty:OpenEncounterJournal()
    end)

    frame.ButtonStrip = CreateFrame("Frame", nil, frame)
    frame.ButtonStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PADDING, -HEADER_HEIGHT)
    frame.ButtonStrip:SetSize(1, 1)

    frame.FooterText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.FooterText:SetPoint("TOP", frame.ButtonStrip, "BOTTOM", 0, -5)
    frame.FooterText:SetJustifyH("CENTER")
    frame.FooterText:SetTextColor(COLOR.Normal[1], COLOR.Normal[2], COLOR.Normal[3], COLOR.Normal[4])
    StyleText(frame.FooterText)

    self.frame = frame
    self.rowButtons = {}
    return frame
end

function EntranceDifficulty:EnsureRowButton(index)
    self.rowButtons = self.rowButtons or {}
    local button = self.rowButtons[index]
    if button then
        return button
    end

    local frame = self:EnsureUI()
    button = CreateFrame("Button", nil, frame.ButtonStrip)
    button:SetHeight(RefineUI:Scale(BUTTON_HEIGHT))
    button:RegisterForClicks("LeftButtonUp")
    button:SetHitRectInsets(-4, -4, -4, -4)

    button.DifficultyText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.DifficultyText:SetJustifyH("LEFT")
    button.DifficultyText:SetTextColor(COLOR.Active[1], COLOR.Active[2], COLOR.Active[3], COLOR.Active[4])
    StyleText(button.DifficultyText)

    button.ProgressText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.ProgressText:SetJustifyH("LEFT")
    button.ProgressText:SetTextColor(COLOR.Progress[1], COLOR.Progress[2], COLOR.Progress[3], COLOR.Progress[4])
    StyleText(button.ProgressText)

    local border = RefineUI.CreateBorder(button, 5, 5)
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(COLOR.Border[1], COLOR.Border[2], COLOR.Border[3], COLOR.Border[4])
    end

    local glow = RefineUI.CreateGlow and RefineUI.CreateGlow(button, 4)
    if glow and glow.SetBackdropBorderColor then
        glow:SetBackdropBorderColor(COLOR.Active[1], COLOR.Active[2], COLOR.Active[3], 0.9)
        glow:Hide()
    end

    button:SetScript("OnClick", function(rowButton)
        local rowData = rowButton.rowData
        local cardState = EntranceDifficulty.cardState
        if type(rowData) ~= "table" or type(cardState) ~= "table" then
            return
        end
        if cardState.canInteract ~= true then
            return
        end

        if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end

        EntranceDifficulty:ApplyDifficulty(rowData.difficultyID, cardState.isRaid == true)
    end)

    button:SetScript("OnEnter", function(rowButton)
        EntranceDifficulty:ShowRowTooltip(rowButton)
        EntranceDifficulty:ApplyRowVisualState(rowButton, rowButton.rowData)
    end)

    button:SetScript("OnLeave", function(rowButton)
        EntranceDifficulty:HideRowTooltip(rowButton)
        EntranceDifficulty:ApplyRowVisualState(rowButton, rowButton.rowData)
    end)

    self.rowButtons[index] = button
    return button
end

----------------------------------------------------------------------------------------
-- UI State
----------------------------------------------------------------------------------------
function EntranceDifficulty:ApplyRowVisualState(button, rowData)
    if not button then
        return
    end

    local isActive = type(rowData) == "table" and rowData.isActive == true
    local canInteract = self.cardState and self.cardState.canInteract == true
    local isHovered = type(button.IsMouseOver) == "function" and button:IsMouseOver()

    if button.border and button.border.SetBackdropBorderColor then
        if isActive then
            button.border:SetBackdropBorderColor(COLOR.Active[1], COLOR.Active[2], COLOR.Active[3], COLOR.Active[4])
        elseif isHovered then
            button.border:SetBackdropBorderColor(COLOR.HoverBorder[1], COLOR.HoverBorder[2], COLOR.HoverBorder[3], COLOR.HoverBorder[4])
        else
            button.border:SetBackdropBorderColor(COLOR.Border[1], COLOR.Border[2], COLOR.Border[3], COLOR.Border[4])
        end
    end

    if button.glow then
        if isActive then
            button.glow:Show()
        else
            button.glow:Hide()
        end
    end

    button:SetAlpha(canInteract and 1 or DISABLED_ALPHA)
end

function EntranceDifficulty:ShowCard()
    local frame = self:EnsureUI()
    RefineUI:CancelTimer(self:BuildKey("HideCard"))
    if frame:IsShown() and frame:GetAlpha() >= 0.99 then
        return
    end

    frame:Show()
    RefineUI:FadeIn(frame, FADE_DURATION, 1)
end

function EntranceDifficulty:HideCard(immediate)
    if not self.frame then
        return
    end

    self.renderedCardSignature = nil
    self.cardState = nil
    HideOwnedTooltip(self.frame.TitleButton)

    for index = 1, #(self.rowButtons or {}) do
        HideOwnedTooltip(self.rowButtons[index])
    end

    RefineUI:CancelTimer(self:BuildKey("HideCard"))
    if immediate then
        self.frame:SetAlpha(0)
        self.frame:Hide()
        return
    end

    if not self.frame:IsShown() then
        self.frame:SetAlpha(0)
        return
    end

    RefineUI:FadeOut(self.frame, FADE_DURATION, 0)
    RefineUI:After(self:BuildKey("HideCard"), FADE_DURATION, function()
        if EntranceDifficulty.frame and EntranceDifficulty.frame:GetAlpha() <= 0.01 then
            EntranceDifficulty.frame:Hide()
        end
    end)
end

function EntranceDifficulty:RefreshCard(cardState)
    local frame = self:EnsureUI()

    if type(cardState) ~= "table" then
        self:HideCard()
        return
    end

    self.cardState = cardState
    if self.renderedCardSignature == cardState.signature then
        self:ShowCard()
        return
    end
    self.renderedCardSignature = cardState.signature

    frame.TitleText:SetText(cardState.displayName or cardState.instanceName or "Dungeon")
    frame.TitleButton:SetWidth(RefineUI:Scale(max(40, floor(GetFontStringWidth(frame.TitleText) + 8))))

    local rows = cardState.rows or {}
    local activeButtons = {}
    for index = 1, #rows do
        local rowData = rows[index]
        local button = self:EnsureRowButton(index)
        button.rowData = rowData
        button.DifficultyText:SetText(rowData.label or tostring(rowData.difficultyID))

        if (rowData.killedCount or 0) >= (rowData.totalCount or 0) and (rowData.totalCount or 0) > 0 then
            button.ProgressText:SetTextColor(COLOR.Complete[1], COLOR.Complete[2], COLOR.Complete[3], COLOR.Complete[4])
        else
            button.ProgressText:SetTextColor(COLOR.Progress[1], COLOR.Progress[2], COLOR.Progress[3], COLOR.Progress[4])
        end
        button.ProgressText:SetText((rowData.killedCount or 0) .. "/" .. (rowData.totalCount or 0))

        local difficultyWidth = GetFontStringWidth(button.DifficultyText)
        local progressWidth = GetFontStringWidth(button.ProgressText)
        local totalTextWidth = difficultyWidth + TEXT_GAP + progressWidth
        local leftOffset = floor((MeasureButtonWidth(button) - totalTextWidth) * 0.5)

        button.layoutWidth = MeasureButtonWidth(button)
        button:SetWidth(RefineUI:Scale(button.layoutWidth))

        button.DifficultyText:ClearAllPoints()
        button.DifficultyText:SetPoint("LEFT", button, "LEFT", RefineUI:Scale(leftOffset), 0)
        button.ProgressText:ClearAllPoints()
        button.ProgressText:SetPoint("LEFT", button.DifficultyText, "RIGHT", RefineUI:Scale(TEXT_GAP), 0)

        self:ApplyRowVisualState(button, rowData)
        button:Show()
        activeButtons[#activeButtons + 1] = button
    end

    for index = (#rows + 1), #self.rowButtons do
        local button = self.rowButtons[index]
        button.rowData = nil
        HideOwnedTooltip(button)
        button:Hide()
    end

    frame.FooterText:SetText(cardState.footerText or "")
    frame.FooterText:SetShown(type(cardState.footerText) == "string" and cardState.footerText ~= "")

    local screenWidth = UIParent:GetWidth() or CARD_WIDTH_MAX
    local maxPanelWidth = min(CARD_WIDTH_MAX, max(CARD_WIDTH_MIN, floor(screenWidth - 48)))
    local maxContentWidth = maxPanelWidth - (CARD_PADDING * 2)
    local lines = BuildButtonLines(activeButtons, maxContentWidth)
    local widestLineWidth = 0
    local lineYOffset = 0

    for lineIndex = 1, #lines do
        widestLineWidth = max(widestLineWidth, lines[lineIndex].width)
    end

    local titleWidth = GetFontStringWidth(frame.TitleText)
    local footerWidth = frame.FooterText:IsShown() and GetFontStringWidth(frame.FooterText) or 0
    local panelWidth = max(CARD_WIDTH_MIN, min(maxPanelWidth, max(widestLineWidth + (CARD_PADDING * 2), titleWidth + (CARD_PADDING * 2), footerWidth + (CARD_PADDING * 2))))
    local buttonStripWidth = panelWidth - (CARD_PADDING * 2)

    frame.ButtonStrip:ClearAllPoints()
    frame.ButtonStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PADDING, -HEADER_HEIGHT)
    frame.ButtonStrip:SetWidth(RefineUI:Scale(buttonStripWidth))

    for lineIndex = 1, #lines do
        local lineInfo = lines[lineIndex]
        local lineXOffset = floor((buttonStripWidth - lineInfo.width) * 0.5)

        for buttonIndex = 1, #lineInfo.buttons do
            local button = lineInfo.buttons[buttonIndex]
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame.ButtonStrip, "TOPLEFT", RefineUI:Scale(lineXOffset), -RefineUI:Scale(lineYOffset))
            lineXOffset = lineXOffset + button.layoutWidth + BUTTON_GAP
        end

        lineYOffset = lineYOffset + BUTTON_HEIGHT + BUTTON_GAP
    end

    local buttonStripHeight = 1
    if #lines > 0 then
        buttonStripHeight = lineYOffset - BUTTON_GAP
    end
    frame.ButtonStrip:SetHeight(RefineUI:Scale(buttonStripHeight))

    local footerHeight = frame.FooterText:IsShown() and FOOTER_HEIGHT or 0
    local panelHeight = HEADER_HEIGHT + buttonStripHeight + footerHeight + CARD_PADDING

    frame:SetWidth(RefineUI:Scale(panelWidth))
    frame:SetHeight(RefineUI:Scale(panelHeight))
    self:ShowCard()
end

----------------------------------------------------------------------------------------
-- Tooltips and Journal
----------------------------------------------------------------------------------------
function EntranceDifficulty:ShowTitleTooltip(button)
    local cardState = self.cardState
    if type(cardState) ~= "table" then
        return
    end

    self.frame.TitleText:SetTextColor(COLOR.TitleHover[1], COLOR.TitleHover[2], COLOR.TitleHover[3], COLOR.TitleHover[4])

    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", button, "BOTTOM", 0, -6)
    GameTooltip:SetText(cardState.displayName or cardState.instanceName or "Dungeon", COLOR.Active[1], COLOR.Active[2], COLOR.Active[3])
    GameTooltip:AddLine("Left Click: Open Encounter Journal", COLOR.Available[1], COLOR.Available[2], COLOR.Available[3], true)

    if CanResetInstances() then
        GameTooltip:AddLine("Ctrl Right Click: Reset instances", COLOR.Available[1], COLOR.Available[2], COLOR.Available[3], true)
    else
        GameTooltip:AddLine("Ctrl Right Click: Reset unavailable", COLOR.Unavailable[1], COLOR.Unavailable[2], COLOR.Unavailable[3], true)
    end

    StyleTooltipLines(GameTooltip)
    GameTooltip:Show()
end

function EntranceDifficulty:HideTitleTooltip(button)
    HideOwnedTooltip(button)
end

function EntranceDifficulty:ShowRowTooltip(button)
    local rowData = button and button.rowData
    if type(rowData) ~= "table" then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", button, "BOTTOM", 0, -8)
    GameTooltip:SetText(rowData.label or "Difficulty", COLOR.Active[1], COLOR.Active[2], COLOR.Active[3])
    GameTooltip:AddLine(format("%d/%d bosses defeated", rowData.killedCount or 0, rowData.totalCount or 0), 1, 1, 1)
    GameTooltip:AddLine(" ")

    local encounters = rowData.encounters or {}
    if #encounters <= 0 then
        GameTooltip:AddLine("No encounter progress data available.", COLOR.Unavailable[1], COLOR.Unavailable[2], COLOR.Unavailable[3], true)
    else
        for index = 1, #encounters do
            local encounter = encounters[index]
            local statusText
            local color

            if encounter.isKilled == true then
                statusText = "Unavailable"
                color = COLOR.Unavailable
            else
                statusText = "Available"
                color = COLOR.Available
            end

            GameTooltip:AddDoubleLine(
                encounter.name or format("Boss %d", index),
                statusText,
                1, 1, 1,
                color[1], color[2], color[3]
            )
        end
    end

    StyleTooltipLines(GameTooltip)
    GameTooltip:Show()
end

function EntranceDifficulty:HideRowTooltip(button)
    HideOwnedTooltip(button)
end

function EntranceDifficulty:OpenEncounterJournal()
    local cardState = self.cardState
    if type(cardState) ~= "table" or type(cardState.journalInstanceID) ~= "number" then
        return
    end

    if type(_G.EncounterJournal_LoadUI) == "function" then
        pcall(_G.EncounterJournal_LoadUI)
    else
        LoadAddon(self.BLIZZARD_ENCOUNTER_JOURNAL)
    end

    if type(_G.EncounterJournal_OpenJournal) == "function" then
        pcall(_G.EncounterJournal_OpenJournal, cardState.activeDifficultyID, cardState.journalInstanceID)
        return
    end

    if type(EJ_SelectInstance) == "function" then
        pcall(EJ_SelectInstance, cardState.journalInstanceID)
    end
end
