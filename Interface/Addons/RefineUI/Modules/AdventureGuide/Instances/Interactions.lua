----------------------------------------------------------------------------------------
-- AdventureGuideInstances Interactions
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AdventureGuideInstances = RefineUI:GetModule("AdventureGuideInstances")
if not AdventureGuideInstances then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local format = string.format
local max = math.max
local tostring = tostring
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_ICON_FILE_ID = 134400
local ACHIEVEMENT_TRACKING = Enum.ContentTrackingType.Achievement
local DEFAULT_ROW_HEIGHT = 49
local RIGHT_COLUMN_WIDTH = 132
local ICON_AND_PADDING_WIDTH = 56
local MIN_NAME_COLUMN_WIDTH = 156

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ShowErrorMessage(message)
    UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
end

local function TryInsertAchievementLink(achievementID)
    local achievementLink = GetAchievementLink(achievementID)
    return achievementLink ~= nil and ChatFrameUtil.InsertLink(achievementLink) == true
end

----------------------------------------------------------------------------------------
-- Achievement UI Availability
----------------------------------------------------------------------------------------
function AdventureGuideInstances:IsAchievementUIReady()
    return type(_G.AchievementFrame_SelectAchievement) == "function"
        and type(_G.AchievementFrame_ToggleAchievementFrame) == "function"
end

function AdventureGuideInstances:EnsureAchievementUILoaded()
    if self:IsAchievementUIReady() then
        return true
    end

    local addonName = self.BLIZZARD_ACHIEVEMENT_ADDON
    if not C_AddOns.IsAddOnLoaded(addonName) then
        C_AddOns.LoadAddOn(addonName)
    end
    -- Loading fires ADDON_LOADED synchronously; this call is a no-op once it has run.
    self:OnAchievementUILoaded()
    return self.achievementUIReady == true
end

function AdventureGuideInstances:OnAchievementUILoaded()
    self.achievementUIReady = self:IsAchievementUIReady()
    if not self.achievementUIReady then
        return
    end
    if self.achievementUIInitialized then
        return
    end
    self.achievementUIInitialized = true

    -- Re-evaluate mappings after the Achievement UI has initialized all category data.
    self:InitializeData()
    self:ScheduleCompletionRefresh()

    self:EnsureAchievementListView()

    if self.customTabActive then
        self:RefreshCustomTabContent()
    end
end

----------------------------------------------------------------------------------------
-- Row Rendering
----------------------------------------------------------------------------------------
function AdventureGuideInstances:InitializeAchievementRow(button, elementData)
    if not button or type(elementData) ~= "table" then
        return
    end

    local row = elementData
    local achievementID = row.achievementID
    if type(achievementID) ~= "number" or achievementID <= 0 then
        return
    end

    local _, achievementName, _, completed, _, _, _, _, _, icon, rewardText = GetAchievementInfo(achievementID)

    button.achievementID = achievementID
    button.achievementRow = row
    button:SetHeight(DEFAULT_ROW_HEIGHT)

    -- Recycled template frames keep these one-time layout and font changes.
    if not button._encounterAchievementsSetup then
        local rowTint = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        rowTint:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
        rowTint:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 1)
        rowTint:Hide()
        button.RowCompletionTint = rowTint

        button.Path:SetMaxLines(1)
        button.Path:SetWordWrap(false)
        button.Path:SetNonSpaceWrap(false)
        button.ResultType:SetWidth(RIGHT_COLUMN_WIDTH)
        button.ResultType:ClearAllPoints()
        button.ResultType:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -8)
        button.ResultType:SetJustifyH("RIGHT")

        button.RewardText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.RewardText:SetPoint("TOPRIGHT", button.ResultType, "BOTTOMRIGHT", 0, -1)
        button.RewardText:SetWidth(RIGHT_COLUMN_WIDTH)
        button.RewardText:SetJustifyH("RIGHT")
        button.RewardText:SetJustifyV("TOP")
        button.RewardText:SetTextColor(1, 0.82, 0)
        button.RewardText:SetMaxLines(1)
        button.RewardText:SetWordWrap(false)

        local nameFont, nameSize, nameFlags = button.Name:GetFont()
        if type(nameFont) == "string" and type(nameSize) == "number" then
            button.Name:SetFont(nameFont, max(9, nameSize - 3), nameFlags)
        end

        local pathFont, pathSize, pathFlags = button.Path:GetFont()
        if type(pathFont) == "string" and type(pathSize) == "number" then
            button.Path:SetFont(pathFont, max(7, pathSize - 3), pathFlags)
        end

        local resultFont, resultSize, resultFlags = button.ResultType:GetFont()
        if type(resultFont) == "string" and type(resultSize) == "number" then
            button.ResultType:SetFont(resultFont, max(9, resultSize - 2), resultFlags)
        end

        local rewardFont, rewardSize, rewardFlags = button.RewardText:GetFont()
        if type(rewardFont) == "string" and type(rewardSize) == "number" then
            button.RewardText:SetFont(rewardFont, max(8, rewardSize - 1), rewardFlags)
        end

        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(rowButton, mouseButton)
            self:OnAchievementRowClick(rowButton, mouseButton)
        end)
        button:SetScript("OnEnter", function(rowButton)
            self:OnAchievementRowEnter(rowButton)
        end)
        button:SetScript("OnLeave", function(rowButton)
            self:OnAchievementRowLeave(rowButton)
        end)

        button._encounterAchievementsSetup = true
    end

    button.Name:SetText(achievementName or row.name or tostring(achievementID))
    button.Icon:SetTexture(icon or row.icon or DEFAULT_ICON_FILE_ID)
    button.Path:SetText(row.categoryPath or "")
    rewardText = (type(rewardText) == "string" and rewardText) or row.rewardText or ""
    button.RewardText:SetText(rewardText)
    button.RewardText:SetShown(rewardText ~= "")

    local listWidth = self.customPanel and self.customPanel.ScrollBox and self.customPanel.ScrollBox:GetWidth() or 320
    local nameColumnWidth = max(MIN_NAME_COLUMN_WIDTH, listWidth - RIGHT_COLUMN_WIDTH - ICON_AND_PADDING_WIDTH)
    button.Name:SetWidth(nameColumnWidth)
    button.Path:SetWidth(nameColumnWidth)

    if completed then
        button.ResultType:SetText(_G.ACHIEVEMENTFRAME_FILTER_COMPLETED or "Completed")
        button.ResultType:SetTextColor(0.5, 0.82, 0.5)
        button.Name:SetTextColor(0.78, 0.96, 0.78)
        button.Path:SetTextColor(0.59, 0.84, 0.59)
        button.RowCompletionTint:SetColorTexture(0.08, 0.36, 0.18, 0.22)
        button.RowCompletionTint:Show()
        button.Icon:SetDesaturated(false)
        button:SetAlpha(0.95)
    else
        -- Shift-click tracking gets visible feedback in the list.
        if C_ContentTracking.IsTracking(ACHIEVEMENT_TRACKING, achievementID) then
            button.ResultType:SetText("Tracking")
            button.ResultType:SetTextColor(1, 0.82, 0)
        else
            button.ResultType:SetText(_G.ACHIEVEMENTFRAME_FILTER_INCOMPLETE or "Incomplete")
            button.ResultType:SetTextColor(0.67, 0.51, 0.34)
        end
        button.Name:SetTextColor(0.95, 0.84, 0.66)
        button.Path:SetTextColor(0.72, 0.57, 0.36)
        button.RowCompletionTint:SetColorTexture(0.46, 0.24, 0.08, 0.20)
        button.RowCompletionTint:Show()
        button.Icon:SetDesaturated(false)
        button:SetAlpha(1)
    end
end

function AdventureGuideInstances:ResetAchievementRow(button)
    if not button then
        return
    end

    button.achievementID = nil
    button.achievementRow = nil
    if button.RewardText then
        button.RewardText:Hide()
        button.RewardText:SetText("")
    end
    if button.RowCompletionTint then
        button.RowCompletionTint:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Interactions
----------------------------------------------------------------------------------------
-- Mirrors Blizzard's AchievementTemplateMixin:ToggleTracking checks and messages.
function AdventureGuideInstances:ToggleAchievementTracking(achievementID)
    if C_ContentTracking.IsTracking(ACHIEVEMENT_TRACKING, achievementID) then
        C_ContentTracking.StopTracking(ACHIEVEMENT_TRACKING, achievementID, Enum.ContentTrackingStopType.Manual)
        return
    end

    local maxTracked = Constants.ContentTrackingConsts.MaxTrackedAchievements
    if #C_ContentTracking.GetTrackedIDs(ACHIEVEMENT_TRACKING) >= maxTracked then
        ShowErrorMessage(format(ACHIEVEMENT_WATCH_TOO_MANY, maxTracked))
        return
    end

    local _, _, _, completed, _, _, _, _, _, _, _, isGuild, wasEarnedByMe = GetAchievementInfo(achievementID)
    if (completed and isGuild) or wasEarnedByMe then
        ShowErrorMessage(ERR_ACHIEVEMENT_WATCH_COMPLETED)
        return
    end

    local trackingError = C_ContentTracking.StartTracking(ACHIEVEMENT_TRACKING, achievementID)
    if trackingError then
        ContentTrackingUtil.DisplayTrackingError(trackingError)
    end
end

function AdventureGuideInstances:OpenAchievementInUI(achievementID)
    if not self:EnsureAchievementUILoaded() then
        return
    end
    if not AchievementFrame:IsShown() then
        ShowUIPanel(AchievementFrame)
    end
    AchievementFrame_SelectSearchItem(achievementID)
end

function AdventureGuideInstances:OnAchievementRowClick(button)
    local achievementID = button.achievementID
    if not achievementID then
        return
    end

    if IsModifiedClick("CHATLINK") and TryInsertAchievementLink(achievementID) then
        return
    end

    if IsModifiedClick("QUESTWATCHTOGGLE") then
        self:ToggleAchievementTracking(achievementID)
        -- Only this row's tracking state changed.
        self:InitializeAchievementRow(button, button.achievementRow)
        return
    end

    self:OpenAchievementInUI(achievementID)
end

function AdventureGuideInstances:OnAchievementRowEnter(button)
    if not button.achievementID then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetAchievementByID(button.achievementID)
    GameTooltip:Show()
end

function AdventureGuideInstances:OnAchievementRowLeave(button)
    if GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
    end
end
