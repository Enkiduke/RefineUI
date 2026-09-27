----------------------------------------------------------------------------------------
-- EntranceDifficulty Component: UI
-- Description: Quest-tracker header with a centered entrance icon and a horizontal difficulty row.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EntranceDifficulty = RefineUI:GetModule("EntranceDifficulty")
if not EntranceDifficulty then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local IsControlKeyDown = IsControlKeyDown
local PlaySound = PlaySound
local StaticPopup_Show = StaticPopup_Show
local UIParent = UIParent
local ceil = math.ceil
local floor = math.floor
local format = string.format
local max = math.max
local min = math.min

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
-- Header metrics mirror ObjectiveTrackerModuleHeaderTemplate (260x26 frame, centered atlas).
local WIDTH_MIN = 260
local WIDTH_MAX = 640
local SIDE_PADDING = 12
local ICON_SIZE = 28
local ICON_OVERLAP = 8
local HEADER_HEIGHT = 26
local ROW_GAP = 4
local ITEM_HEIGHT = 21 -- Options_List_* atlas height
local ITEM_PADDING = 10
local ITEM_GAP = 4
local LINE_GAP = 2
local FOOTER_GAP = 4
local FADE_DURATION = 0.16

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function SetTrackerColor(region, colorKey)
    local color = OBJECTIVE_TRACKER_COLOR[colorKey]
    region:SetTextColor(color.r, color.g, color.b)
end

local function HideOwnedTooltip(owner)
    if GameTooltip:GetOwner() == owner then
        GameTooltip:Hide()
    end
end

local function CanResetInstances()
    return UnitPopupResetInstancesButtonMixin:IsEnabled()
end

local function UpdateItemState(item)
    local rowData = item.rowData
    local cardState = EntranceDifficulty.cardState
    if not rowData or not cardState then
        return
    end

    -- Same selected/hover pair as the Settings category list.
    local hovered = item.isHovered and cardState.canInteract
    if rowData.isActive then
        item.Selector:SetAtlas("Options_List_Active")
        item.Selector:Show()
    elseif hovered then
        item.Selector:SetAtlas("Options_List_Hover")
        item.Selector:Show()
    else
        item.Selector:Hide()
    end

    if rowData.isActive then
        SetTrackerColor(item.Text, "HeaderHighlight")
    elseif hovered then
        SetTrackerColor(item.Text, "NormalHighlight")
    else
        SetTrackerColor(item.Text, cardState.canInteract and "Normal" or "Complete")
    end
end

-- Wraps the first `count` items into centered lines. Measures only when contentWidth is nil.
local function LayoutItems(frame, items, count, maxWidth, contentWidth, top)
    if count == 0 then
        return 0, 0
    end

    local widest, lineCount = 0, 0
    local first, lineWidth = 1, 0
    for index = 1, count + 1 do
        local width = index <= count and items[index]:GetWidth() or 0
        if index > count or (index > first and lineWidth + ITEM_GAP + width > maxWidth) then
            if contentWidth then
                local x = SIDE_PADDING + floor((contentWidth - lineWidth) * 0.5)
                local y = top + lineCount * (ITEM_HEIGHT + LINE_GAP)
                for lineIndex = first, index - 1 do
                    local item = items[lineIndex]
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
                    x = x + item:GetWidth() + ITEM_GAP
                end
            end

            widest = max(widest, lineWidth)
            lineCount = lineCount + 1
            first, lineWidth = index, width
        elseif index > first then
            lineWidth = lineWidth + ITEM_GAP + width
        else
            lineWidth = width
        end
    end

    return widest, lineCount
end

----------------------------------------------------------------------------------------
-- Scripts
----------------------------------------------------------------------------------------
local function OnHeaderEnter(header)
    SetTrackerColor(header.Text, "HeaderHighlight")
    EntranceDifficulty:ShowHeaderTooltip(header)
end

local function OnHeaderLeave(header)
    SetTrackerColor(header.Text, "Header")
    GameTooltip_Hide()
end

local function OnHeaderClick(_, mouseButton)
    if mouseButton == "RightButton" then
        if IsControlKeyDown() and CanResetInstances() then
            StaticPopup_Show("CONFIRM_RESET_INSTANCES")
        end
        return
    end

    EntranceDifficulty:OpenEncounterJournal()
end

local function OnItemClick(item)
    local cardState = EntranceDifficulty.cardState
    if not cardState or not cardState.canInteract or not item.rowData or item.rowData.isActive then
        return
    end

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    EntranceDifficulty:ApplyDifficulty(item.rowData.difficultyID, cardState.isRaid)
end

local function OnItemEnter(item)
    item.isHovered = true
    UpdateItemState(item)
    EntranceDifficulty:ShowItemTooltip(item)
end

local function OnItemLeave(item)
    item.isHovered = nil
    UpdateItemState(item)
    GameTooltip_Hide()
end

----------------------------------------------------------------------------------------
-- UI Creation
----------------------------------------------------------------------------------------
local function AddAlpha(group, target, duration, startDelay, fromAlpha, toAlpha)
    local animation = group:CreateAnimation("Alpha")
    animation:SetTarget(target)
    animation:SetDuration(duration)
    animation:SetStartDelay(startDelay)
    animation:SetFromAlpha(fromAlpha)
    animation:SetToAlpha(toAlpha)
end

local function CreateHeader(frame)
    local header = CreateFrame("Button", nil, frame)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:SetPoint("TOPLEFT", 0, -(ICON_SIZE - ICON_OVERLAP))
    header:SetPoint("TOPRIGHT", 0, -(ICON_SIZE - ICON_OVERLAP))
    header:SetHeight(HEADER_HEIGHT)
    header:SetScript("OnEnter", OnHeaderEnter)
    header:SetScript("OnLeave", OnHeaderLeave)
    header:SetScript("OnClick", OnHeaderClick)

    header.Background = header:CreateTexture(nil, "BACKGROUND")
    header.Background:SetAtlas("UI-QuestTracker-Secondary-Objective-Header", true)
    header.Background:SetPoint("CENTER")
    header.backgroundWidth = header.Background:GetWidth()

    header.Text = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
    header.Text:SetPoint("CENTER")
    header.Text:SetJustifyH("CENTER")
    header.Text:SetWordWrap(false)
    SetTrackerColor(header.Text, "Header")

    header.Icon = header:CreateTexture(nil, "ARTWORK")
    header.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    header.Icon:SetPoint("BOTTOM", header, "TOP", 0, -ICON_OVERLAP)

    -- ObjectiveTrackerModuleHeaderTemplate AddAnim, kept inside the strip because the title is centered.
    header.Glow = header:CreateTexture(nil, "OVERLAY")
    header.Glow:SetAtlas("UI-QuestTracker-OBJFX-BarGlow", true)
    header.Glow:SetPoint("CENTER", 0, 1)
    header.Glow:SetAlpha(0)

    header.Shine = header:CreateTexture(nil, "ARTWORK")
    header.Shine:SetAtlas("UI-QuestTracker-OBJFX-Shine", true)
    header.Shine:SetPoint("LEFT", 0, 1)
    header.Shine:SetAlpha(0)

    local addAnim = header:CreateAnimationGroup()
    addAnim:SetToFinalAlpha(true)
    AddAlpha(addAnim, header.Background, 0.5, 0, 0, 1)
    AddAlpha(addAnim, header.Glow, 0.2, 0, 0, 1)
    AddAlpha(addAnim, header.Glow, 0.6, 0.2, 1, 0)
    AddAlpha(addAnim, header.Shine, 1, 0.2, 0, 1)
    AddAlpha(addAnim, header.Shine, 1.2, 0.2, 1, 0)
    header.ShineTranslation = addAnim:CreateAnimation("Translation")
    header.ShineTranslation:SetTarget(header.Shine)
    header.ShineTranslation:SetDuration(0.7)
    header.ShineTranslation:SetStartDelay(0.2)
    header.ShineTranslation:SetSmoothing("IN_OUT")
    header.AddAnim = addAnim

    return header
end

function EntranceDifficulty:EnsureUI()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", self.FRAME_NAME, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -50)
    frame:SetSize(WIDTH_MIN, ICON_SIZE)
    frame:SetAlpha(0)
    frame:Hide()

    frame.Header = CreateHeader(frame)

    frame.FooterText = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
    frame.FooterText:SetJustifyH("CENTER")

    self.frame = frame
    self.items = {}
    return frame
end

function EntranceDifficulty:EnsureItem(index)
    local item = self.items[index]
    if item then
        return item
    end

    item = CreateFrame("Button", nil, self.frame)
    item:SetHeight(ITEM_HEIGHT)
    item:SetScript("OnClick", OnItemClick)
    item:SetScript("OnEnter", OnItemEnter)
    item:SetScript("OnLeave", OnItemLeave)

    item.Selector = item:CreateTexture(nil, "BACKGROUND")
    item.Selector:SetAllPoints()
    item.Selector:Hide()

    item.Text = item:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
    item.Text:SetPoint("CENTER")
    item.Text:SetWordWrap(false)

    self.items[index] = item
    return item
end

----------------------------------------------------------------------------------------
-- UI State
----------------------------------------------------------------------------------------
function EntranceDifficulty:ShowCard()
    local frame = self.frame
    RefineUI:CancelTimer(self.HIDE_TIMER_KEY)
    if not self.cardShown then
        self.cardShown = true
        local header = frame.Header
        header.ShineTranslation:SetOffset(header:GetWidth() - header.Shine:GetWidth(), 0)
        frame:Show()
        header.AddAnim:Restart()
    end
    RefineUI:FadeIn(frame, FADE_DURATION, 1)
end

function EntranceDifficulty:HideCard()
    local frame = self.frame
    self.cardState = nil
    if not frame then
        return
    end

    HideOwnedTooltip(frame.Header)
    for index = 1, #self.items do
        HideOwnedTooltip(self.items[index])
    end

    if not self.cardShown then
        return
    end
    self.cardShown = nil

    -- UIFrameFadeOut only changes alpha; ShowCard cancels this timer if the card returns first.
    RefineUI:FadeOut(frame, FADE_DURATION, 0)
    RefineUI:After(self.HIDE_TIMER_KEY, FADE_DURATION, function()
        frame:Hide()
    end)
end

function EntranceDifficulty:RefreshCard(cardState)
    local frame = self:EnsureUI()
    self.cardState = cardState

    local header = frame.Header
    header.Icon:SetAtlas(cardState.atlasName)
    header.Text:SetText(cardState.name)
    local contentWidth = header.Text:GetUnboundedStringWidth()

    local rows = cardState.rows
    local items = self.items
    for index = 1, #rows do
        local rowData = rows[index]
        local item = self:EnsureItem(index)
        item.rowData = rowData

        local text = rowData.label
        if rowData.totalCount > 0 then
            local progress = format("%d/%d", rowData.killedCount, rowData.totalCount)
            if rowData.killedCount >= rowData.totalCount then
                progress = RED_FONT_COLOR:WrapTextInColorCode(progress)
            end
            text = text .. " " .. progress
        end
        item.Text:SetText(text)
        item:SetWidth(ceil(item.Text:GetUnboundedStringWidth()) + (ITEM_PADDING * 2))

        UpdateItemState(item)
        item:Show()
    end

    for index = #rows + 1, #items do
        local item = items[index]
        item.rowData = nil
        item.isHovered = nil
        HideOwnedTooltip(item)
        item:Hide()
    end

    local footerText = cardState.footerText
    local footerWidth = 0
    frame.FooterText:SetShown(footerText ~= nil)
    if footerText then
        frame.FooterText:SetText(footerText)
        SetTrackerColor(frame.FooterText, cardState.canInteract and "Complete" or "Failed")
        footerWidth = frame.FooterText:GetUnboundedStringWidth()
    end

    local maxContentWidth = min(WIDTH_MAX, floor(UIParent:GetWidth() - 48)) - (SIDE_PADDING * 2)
    local itemsTop = ICON_SIZE - ICON_OVERLAP + HEADER_HEIGHT + ROW_GAP
    local widestLine, lineCount = LayoutItems(frame, items, #rows, maxContentWidth)
    contentWidth = min(maxContentWidth, ceil(max(WIDTH_MIN - (SIDE_PADDING * 2), contentWidth, widestLine, footerWidth)))
    LayoutItems(frame, items, #rows, maxContentWidth, contentWidth, itemsTop)

    local height = itemsTop + (lineCount * (ITEM_HEIGHT + LINE_GAP)) - LINE_GAP
    if footerText then
        frame.FooterText:SetWidth(contentWidth)
        frame.FooterText:ClearAllPoints()
        frame.FooterText:SetPoint("TOP", frame, "TOP", 0, -(height + FOOTER_GAP))
        height = height + FOOTER_GAP + frame.FooterText:GetStringHeight()
    end

    local width = contentWidth + (SIDE_PADDING * 2)
    header.Background:SetWidth(header.backgroundWidth + width - WIDTH_MIN)
    frame:SetSize(width, height)
    self:ShowCard()
end

----------------------------------------------------------------------------------------
-- Tooltips and Journal
----------------------------------------------------------------------------------------
function EntranceDifficulty:ShowHeaderTooltip(header)
    local cardState = self.cardState
    if not cardState then
        return
    end

    GameTooltip:SetOwner(header, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, cardState.name)
    GameTooltip_AddInstructionLine(GameTooltip, "Left-click: Open " .. ADVENTURE_JOURNAL)
    if CanResetInstances() then
        GameTooltip_AddInstructionLine(GameTooltip, "Ctrl-Right-click: " .. RESET_INSTANCES)
    else
        GameTooltip_AddDisabledLine(GameTooltip, "Ctrl-Right-click: " .. RESET_INSTANCES)
    end
    GameTooltip:Show()
end

function EntranceDifficulty:ShowItemTooltip(item)
    local rowData = item.rowData
    if not rowData then
        return
    end

    GameTooltip:SetOwner(item, "ANCHOR_BOTTOM")
    GameTooltip_SetTitle(GameTooltip, rowData.label)
    GameTooltip_AddHighlightLine(GameTooltip, format("%d/%d bosses defeated", rowData.killedCount, rowData.totalCount))

    local encounters = rowData.encounters
    if #encounters > 0 then
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        for index = 1, #encounters do
            local encounter = encounters[index]
            if encounter.isKilled then
                GameTooltip_AddColoredDoubleLine(GameTooltip, encounter.name, "Defeated", HIGHLIGHT_FONT_COLOR, RED_FONT_COLOR, false)
            else
                GameTooltip_AddColoredDoubleLine(GameTooltip, encounter.name, "Available", HIGHLIGHT_FONT_COLOR, GREEN_FONT_COLOR, false)
            end
        end
    else
        GameTooltip_AddDisabledLine(GameTooltip, "No encounter progress data available.")
    end
    GameTooltip:Show()
end

function EntranceDifficulty:OpenEncounterJournal()
    local cardState = self.cardState
    if not cardState then
        return
    end

    EncounterJournal_LoadUI()
    EncounterJournal_OpenJournal(cardState.activeDifficultyID, cardState.journalInstanceID)
end
