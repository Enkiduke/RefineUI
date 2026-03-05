----------------------------------------------------------------------------------------
-- EncounterAchievements Interactions
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterAchievements = RefineUI:GetModule("EncounterAchievements")
if not EncounterAchievements then
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
local DEFAULT_MAX_TRACKED_ACHIEVEMENTS = 10
local DEFAULT_ROW_HEIGHT = 49
local RIGHT_COLUMN_WIDTH = 132
local ICON_AND_PADDING_WIDTH = 56
local MIN_NAME_COLUMN_WIDTH = 156

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
    if type(_G.C_AddOns) == "table" and type(_G.C_AddOns.LoadAddOn) == "function" then
        local ok, loaded = pcall(_G.C_AddOns.LoadAddOn, addonName)
        return ok and loaded == true
    end

    local loadAddOn = _G.UIParentLoadAddOn or _G.LoadAddOn
    if type(loadAddOn) == "function" then
        local ok, loaded = pcall(loadAddOn, addonName)
        if ok then
            if type(loaded) == "boolean" then
                return loaded
            end
            return IsAddonLoaded(addonName)
        end
    end

    return false
end

local function ShowErrorMessage(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    local errorsFrame = _G.UIErrorsFrame
    if errorsFrame and type(errorsFrame.AddMessage) == "function" then
        errorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    end
end

local function TryInsertAchievementLink(achievementID)
    if type(_G.GetAchievementLink) ~= "function" then
        return false
    end

    local achievementLink = _G.GetAchievementLink(achievementID)
    if type(achievementLink) ~= "string" or achievementLink == "" then
        return false
    end

    local handled = false
    if type(_G.ChatFrameUtil) == "table" and type(_G.ChatFrameUtil.InsertLink) == "function" then
        handled = _G.ChatFrameUtil.InsertLink(achievementLink) == true
    end

    if handled and type(_G.AchievementFrame_OnAchievementLinkedInChat) == "function" then
        _G.AchievementFrame_OnAchievementLinkedInChat(achievementID)
    end

    if (not handled)
        and _G.SocialPostFrame
        and type(_G.Social_IsShown) == "function"
        and _G.Social_IsShown()
        and type(_G.Social_InsertLink) == "function" then
        _G.Social_InsertLink(achievementLink)
        handled = true
    end

    return handled
end

----------------------------------------------------------------------------------------
-- Achievement UI Availability
----------------------------------------------------------------------------------------
function EncounterAchievements:IsAchievementUIReady()
    return type(_G.AchievementFrame_SelectAchievement) == "function"
        and type(_G.AchievementFrame_ToggleAchievementFrame) == "function"
end

function EncounterAchievements:EnsureAchievementUILoaded()
    if self:IsAchievementUIReady() then
        self.achievementUIReady = true
        return true
    end

    local addonName = self.BLIZZARD_ACHIEVEMENT_ADDON
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end

    if IsAddonLoaded(addonName) then
        self.achievementUIReady = self:IsAchievementUIReady()
        if self.achievementUIReady then
            self:OnAchievementUILoaded()
        end
        return self.achievementUIReady == true
    end

    local loaded = LoadAddon(addonName)
    self.achievementUIReady = self:IsAchievementUIReady()
    if loaded and self.achievementUIReady then
        self:OnAchievementUILoaded()
    end

    return self.achievementUIReady == true
end

function EncounterAchievements:OnAchievementUILoaded()
    self.achievementUIReady = self:IsAchievementUIReady()
    if not self.achievementUIReady then
        return
    end

    if self.CancelPendingInstanceRowBuilds then
        self:CancelPendingInstanceRowBuilds()
    end

    -- Re-evaluate mappings after the Achievement UI has initialized all category data.
    self._instanceCategoryCache = {}
    self._instanceAchievementCache = {}
    self._instanceRowCache = {}
    self._categoryGraph = nil
    self._allCategoryIDs = nil
    self._categoryPathCache = {}
    self._categoryPathTokenCache = {}
    self._categoryDepthCache = {}

    self:EnsureAchievementListView()

    if self.customTabActive then
        self:RefreshCustomTabContent()
    end
end

----------------------------------------------------------------------------------------
-- Row Rendering
----------------------------------------------------------------------------------------
function EncounterAchievements:InitializeAchievementRow(button, elementData)
    if not button or type(elementData) ~= "table" then
        return
    end

    local row = elementData.row or elementData
    local achievementID = row.achievementID or elementData.achievementID
    if type(achievementID) ~= "number" or achievementID <= 0 then
        return
    end

    local _, achievementName, _, completed, _, _, _, _, _, icon, rewardText = GetAchievementInfo(achievementID)

    button.achievementID = achievementID
    button.achievementRow = row
    button:SetHeight(DEFAULT_ROW_HEIGHT)

    if not button.RowCompletionTint then
        local rowTint = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        rowTint:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
        rowTint:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 1)
        rowTint:Hide()
        button.RowCompletionTint = rowTint
    end

    local name = achievementName or row.name or tostring(achievementID)
    button.Name:SetText(name)
    button.Icon:SetTexture(icon or row.icon or DEFAULT_ICON_FILE_ID)
    button.Path:SetText(row.categoryPath or "")
    rewardText = (type(rewardText) == "string" and rewardText) or row.rewardText or ""

    local listWidth = self.customPanel and self.customPanel.ScrollBox and self.customPanel.ScrollBox:GetWidth() or 320
    local nameColumnWidth = max(MIN_NAME_COLUMN_WIDTH, listWidth - RIGHT_COLUMN_WIDTH - ICON_AND_PADDING_WIDTH)
    button.Name:SetWidth(nameColumnWidth)
    button.Path:SetWidth(nameColumnWidth)
    if button.Path.SetMaxLines then
        button.Path:SetMaxLines(1)
    end
    if button.Path.SetWordWrap then
        button.Path:SetWordWrap(false)
    end
    if button.Path.SetNonSpaceWrap then
        button.Path:SetNonSpaceWrap(false)
    end
    button.ResultType:SetWidth(RIGHT_COLUMN_WIDTH)
    button.ResultType:ClearAllPoints()
    button.ResultType:SetPoint("TOPRIGHT", button, "TOPRIGHT", -10, -8)
    button.ResultType:SetJustifyH("RIGHT")

    if not button.RewardText then
        button.RewardText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.RewardText:SetPoint("TOPRIGHT", button.ResultType, "BOTTOMRIGHT", 0, -1)
        button.RewardText:SetJustifyH("RIGHT")
        button.RewardText:SetJustifyV("TOP")
        button.RewardText:SetTextColor(1, 0.82, 0)
        if button.RewardText.SetMaxLines then
            button.RewardText:SetMaxLines(1)
        end
        if button.RewardText.SetWordWrap then
            button.RewardText:SetWordWrap(false)
        end
    end
    button.RewardText:SetWidth(RIGHT_COLUMN_WIDTH)
    button.RewardText:SetText(rewardText)
    button.RewardText:SetShown(rewardText ~= "")

    if not button._encounterAchievementsFontsAdjusted then
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

        button._encounterAchievementsFontsAdjusted = true
    end

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
        button.ResultType:SetText(_G.ACHIEVEMENTFRAME_FILTER_INCOMPLETE or "Incomplete")
        button.ResultType:SetTextColor(0.67, 0.51, 0.34)
        button.Name:SetTextColor(0.95, 0.84, 0.66)
        button.Path:SetTextColor(0.72, 0.57, 0.36)
        button.RowCompletionTint:SetColorTexture(0.46, 0.24, 0.08, 0.20)
        button.RowCompletionTint:Show()
        button.Icon:SetDesaturated(false)
        button:SetAlpha(1)
    end

    if not button._encounterAchievementsWired then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(rowButton, mouseButton)
            self:OnAchievementRowClick(rowButton, mouseButton)
        end)
        button:SetScript("OnEnter", function(rowButton)
            self:OnAchievementRowEnter(rowButton)
        end)
        button:SetScript("OnLeave", function()
            self:OnAchievementRowLeave()
        end)
        button._encounterAchievementsWired = true
    end
end

function EncounterAchievements:ResetAchievementRow(button)
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
function EncounterAchievements:ToggleAchievementTracking(achievementID)
    if type(achievementID) ~= "number" or achievementID <= 0 then
        return false
    end

    local contentTracking = _G.C_ContentTracking
    local enum = _G.Enum
    local contentType = enum and enum.ContentTrackingType and enum.ContentTrackingType.Achievement
    if type(contentTracking) ~= "table" or not contentType then
        return false
    end

    if type(contentTracking.IsTracking) == "function" and contentTracking.IsTracking(contentType, achievementID) then
        if type(contentTracking.StopTracking) == "function" then
            local stopType = enum.ContentTrackingStopType and enum.ContentTrackingStopType.Manual
            contentTracking.StopTracking(contentType, achievementID, stopType)
            return true
        end
        return false
    end

    if type(contentTracking.GetTrackedIDs) == "function" then
        local trackedIDs = contentTracking.GetTrackedIDs(contentType)
        local trackedCount = type(trackedIDs) == "table" and #trackedIDs or 0
        local maxTracked = DEFAULT_MAX_TRACKED_ACHIEVEMENTS
        if type(_G.Constants) == "table"
            and type(_G.Constants.ContentTrackingConsts) == "table"
            and type(_G.Constants.ContentTrackingConsts.MaxTrackedAchievements) == "number" then
            maxTracked = _G.Constants.ContentTrackingConsts.MaxTrackedAchievements
        end
        if trackedCount >= maxTracked then
            local message = format(_G.ACHIEVEMENT_WATCH_TOO_MANY or "You may only track %d achievements.", maxTracked)
            ShowErrorMessage(message)
            return false
        end
    end

    local _, _, _, completed, _, _, _, _, _, _, _, isGuild, wasEarnedByMe = GetAchievementInfo(achievementID)
    if (completed and isGuild) or wasEarnedByMe then
        ShowErrorMessage(_G.ERR_ACHIEVEMENT_WATCH_COMPLETED or "Completed achievements cannot be tracked.")
        return false
    end

    if type(contentTracking.StartTracking) == "function" then
        local trackingError = contentTracking.StartTracking(contentType, achievementID)
        if trackingError and type(_G.ContentTrackingUtil) == "table" and type(_G.ContentTrackingUtil.DisplayTrackingError) == "function" then
            _G.ContentTrackingUtil.DisplayTrackingError(trackingError)
            return false
        end
        return trackingError == nil
    end

    return false
end

function EncounterAchievements:OpenAchievementInUI(achievementID)
    if type(achievementID) ~= "number" or achievementID <= 0 then
        return false
    end

    if not self:EnsureAchievementUILoaded() then
        return false
    end

    local achievementFrame = _G.AchievementFrame
    if achievementFrame and type(achievementFrame.IsShown) == "function" and not achievementFrame:IsShown() then
        if type(_G.ShowUIPanel) == "function" then
            _G.ShowUIPanel(achievementFrame)
        end
    elseif (not achievementFrame) and type(_G.AchievementFrame_ToggleAchievementFrame) == "function" then
        _G.AchievementFrame_ToggleAchievementFrame(false, false)
    end

    if type(_G.AchievementFrame_SelectSearchItem) == "function" then
        _G.AchievementFrame_SelectSearchItem(achievementID)
        return true
    end

    if type(_G.AchievementFrame_SelectAchievement) == "function" then
        _G.AchievementFrame_SelectAchievement(achievementID, true)
        return true
    end

    return false
end

function EncounterAchievements:OnAchievementRowClick(button)
    local achievementID = button and button.achievementID
    if type(achievementID) ~= "number" or achievementID <= 0 then
        return
    end

    if type(_G.IsModifiedClick) == "function" and _G.IsModifiedClick("CHATLINK") then
        if TryInsertAchievementLink(achievementID) then
            return
        end
    end

    if type(_G.IsModifiedClick) == "function" and _G.IsModifiedClick("QUESTWATCHTOGGLE") then
        self:ToggleAchievementTracking(achievementID)
        self:RefreshCustomTabContent()
        return
    end

    self:OpenAchievementInUI(achievementID)
end

function EncounterAchievements:OnAchievementRowEnter(button)
    if not button or type(button.achievementID) ~= "number" then
        return
    end

    if not _G.GameTooltip then
        return
    end

    _G.GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    if type(_G.GameTooltip.SetAchievementByID) == "function" then
        _G.GameTooltip:SetAchievementByID(button.achievementID)
    else
        local link = type(_G.GetAchievementLink) == "function" and _G.GetAchievementLink(button.achievementID) or nil
        if link and type(_G.GameTooltip.SetHyperlink) == "function" then
            _G.GameTooltip:SetHyperlink(link)
        else
            _G.GameTooltip:SetText(button.Name and button.Name:GetText() or tostring(button.achievementID))
        end
    end

    _G.GameTooltip:Show()
end

function EncounterAchievements:OnAchievementRowLeave()
    if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
        _G.GameTooltip:Hide()
    end
end
