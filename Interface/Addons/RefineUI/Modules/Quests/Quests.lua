----------------------------------------------------------------------------------------
-- Quests for RefineUI
-- Description: Skins quest tracker/map and provides quest settings menu
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Quests = RefineUI:RegisterModule("Quests", "Quests")
local UI = RefineUI

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local gsub = string.gsub

local ObjectiveTrackerFrame = _G.ObjectiveTrackerFrame
local QuestObjectiveTracker = _G.QuestObjectiveTracker
local QuestMapFrame = _G.QuestMapFrame

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local R, G, B = unpack(RefineUI.MyClassColor)
local GOLD_TEXT_COLOR = { 1, 0.82, 0 }
local WHITE_TEXT_COLOR = { 1, 1, 1 }
local PROGRESS_BAR_FLARES = { "Flare1", "Flare2", "SmallFlare1", "SmallFlare2", "FullBarFlare1", "FullBarFlare2" }

local QUEST_PROGRESS_HOOK = {
    PANEL_ON_SHOW = "Quests:QuestFrameProgressPanel_OnShow",
    PANEL_SCRIPT_ON_SHOW = "Quests:QuestFrameProgressPanel:OnShow",
    ITEMS_UPDATE = "Quests:QuestFrameProgressItems_Update",
}
local QUEST_GREETING_HOOK = {
    PANEL_ON_SHOW = "Quests:QuestFrameGreetingPanel_OnShow",
    PANEL_SCRIPT_ON_SHOW = "Quests:QuestFrameGreetingPanel:OnShow",
}
local QUEST_PROGRESS_EVENT = {
    ADDON_LOADED = "Quests:QuestProgress:ADDON_LOADED",
}

local function SetTextColorIfPossible(fontString, color)
    if fontString and fontString.SetTextColor then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function ReplaceQuestInlineColors(text)
    if type(text) ~= "string" or text == "" then
        return text
    end

    text = gsub(text, "|c[fF][fF]000000", "|cffffd200")
    text = gsub(text, "|c[fF][fF]042c54", "|cff1c86ee")

    return text
end

local function BuildQuestHookKey(owner, method, suffix)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    if suffix and suffix ~= "" then
        return "Quests:" .. ownerId .. ":" .. method .. ":" .. suffix
    end
    return "Quests:" .. ownerId .. ":" .. method
end

local Headers = {
    _G.CampaignQuestObjectiveTracker.Header,
    _G.QuestObjectiveTracker.Header,
    _G.MonthlyActivitiesObjectiveTracker.Header,
    _G.BonusObjectiveTracker.Header,
    _G.WorldQuestObjectiveTracker.Header,
    _G.AdventureObjectiveTracker.Header,
    _G.ScenarioObjectiveTracker.Header,
    _G.AchievementObjectiveTracker.Header,
    _G.ProfessionsRecipeTracker.Header,
}

local Trackers = {
    _G.ScenarioObjectiveTracker,
    _G.BonusObjectiveTracker,
    _G.UIWidgetObjectiveTracker,
    _G.CampaignQuestObjectiveTracker,
    _G.QuestObjectiveTracker,
    _G.AdventureObjectiveTracker,
    _G.AchievementObjectiveTracker,
    _G.MonthlyActivitiesObjectiveTracker,
    _G.ProfessionsRecipeTracker,
    _G.WorldQuestObjectiveTracker,
}

local function StyleObjectiveFontString(fontString)
    if not fontString or not fontString.SetFont then
        return
    end

    local font, size, flags = fontString:GetFont()
    if not size then
        size = 13
    end

    if font ~= Media.Fonts.Default or flags ~= "OUTLINE" then
        fontString:SetFont(Media.Fonts.Default, size, "OUTLINE")
    end
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
end

local function StyleQuestMapFontString(fontString)
    if not fontString or not fontString.SetFont then
        return
    end

    local name = fontString.GetName and fontString:GetName() or ""
    local font, originalSize, flags = fontString:GetFont()
    local size = originalSize
    if not size then
        size = 12
    end

    if name and name ~= "" then
        if name:find("Title", 1, true) and size < 16 then
            size = 16
        elseif name:find("Header", 1, true) and size < 14 then
            size = 14
        elseif size > 16 then
            size = 16
        elseif size < 12 then
            size = 12
        end
    end

    if font ~= Media.Fonts.Default or size ~= originalSize or flags ~= "OUTLINE" then
        fontString:SetFont(Media.Fonts.Default, size, "OUTLINE")
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    end
end

local function ForEachChildFrameFontString(frame, callback, seen)
    if not frame or not callback then
        return
    end

    seen = seen or {}
    if seen[frame] then
        return
    end
    seen[frame] = true

    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            callback(region)
        end
    end

    local children = { frame:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child then
            ForEachChildFrameFontString(child, callback, seen)
        end
    end
end

----------------------------------------------------------------------------------------
--	Hide Default Header Backgrounds
----------------------------------------------------------------------------------------
function Quests:HideDefaultBackgrounds()
    for _, Frames in pairs({
        _G.QuestObjectiveTracker.Header.Background,
        _G.CampaignQuestObjectiveTracker.Header.Background,
        _G.MonthlyActivitiesObjectiveTracker.Header.Background,
        _G.BonusObjectiveTracker.Header.Background,
        _G.WorldQuestObjectiveTracker.Header.Background,
        _G.AdventureObjectiveTracker.Header.Background,
        _G.ScenarioObjectiveTracker.Header.Background,
        _G.AchievementObjectiveTracker.Header.Background,
        _G.ProfessionsRecipeTracker.Header.Background,
    }) do
        if (Frames) then
            Frames:SetParent(UI.HiddenFrame)
        end
    end
end

----------------------------------------------------------------------------------------
--	Skin Header with Class-Colored Bar
----------------------------------------------------------------------------------------
function Quests:SkinHeader(Frame)
    local HeaderBar = CreateFrame("StatusBar", nil, Frame)
    Frame.RefineUIHeaderBar = HeaderBar
    RefineUI.Size(HeaderBar, 232, 6)
    RefineUI.Point(HeaderBar, "TOP", Frame, -16, -18)
    HeaderBar:SetFrameLevel(Frame:GetFrameLevel() - 1)
    HeaderBar:SetFrameStrata("BACKGROUND")
    HeaderBar:SetStatusBarTexture(Media.Textures.Statusbar)
    HeaderBar:SetStatusBarColor(R, G, B)
    RefineUI.SetTemplate(HeaderBar)
    RefineUI.CreateBorder(HeaderBar)
end

function Quests:SkinHeaders()
    if (self.HeadersSkinned) then 
        return 
    end

    for _, Header in ipairs(Headers) do
        if (Header) then
            self:SkinHeader(Header)
        end
    end

    self.HeadersSkinned = true
end

----------------------------------------------------------------------------------------
--	Skin Progress Bar
----------------------------------------------------------------------------------------
function Quests:SkinProgressBar(tracker, key)
    local progressBar = tracker.usedProgressBars[key]
    local bar = progressBar and progressBar.Bar
    local label = bar and bar.Label
    local icon = bar and bar.Icon

    if not progressBar.styled then
        if bar.BarFrame then bar.BarFrame:Hide() end
        if bar.BarFrame2 then bar.BarFrame2:Hide() end
        if bar.BarFrame3 then bar.BarFrame3:Hide() end
        if bar.BarGlow then bar.BarGlow:Hide() end
        if bar.Sheen then bar.Sheen:Hide() end
        if bar.IconBG then bar.IconBG:SetAlpha(0) end
        if bar.BorderLeft then bar.BorderLeft:SetAlpha(0) end
        if bar.BorderRight then bar.BorderRight:SetAlpha(0) end
        if bar.BorderMid then bar.BorderMid:SetAlpha(0) end
        -- Hide the flares instead of replacing PlayFlareAnim: Blizzard calls it
        -- mid-layout, and an addon function there taints the tracker update.
        for _, key in ipairs(PROGRESS_BAR_FLARES) do
            if progressBar[key] then progressBar[key]:SetAlpha(0) end
        end

        RefineUI.Size(bar, 200, 16)
        bar:SetStatusBarTexture(Media.Textures.Statusbar)
        RefineUI.SetTemplate(bar)

        label:ClearAllPoints()
        RefineUI.Point(label, "CENTER", bar, "CENTER", 0, -1)
        RefineUI.Font(label, 12, nil, "THINOUTLINE")
        label:SetShadowOffset(1, -1)
        label:SetDrawLayer("OVERLAY")

        if icon then
            RefineUI.Point(icon, "RIGHT", bar, "RIGHT", 26, 0)
            RefineUI.Size(icon, 20, 20)
            icon:SetMask("")

            local border = CreateFrame("Frame", "$parentBorder", bar, "BackdropTemplate")
            border:SetAllPoints(icon)
            RefineUI.SetTemplate(border)
            border:SetBackdropColor(0, 0, 0, 0)
            bar.newIconBg = border

            RefineUI:HookOnce(BuildQuestHookKey(bar.AnimIn, "Play"), bar.AnimIn, "Play", function()
                bar.AnimIn:Stop()
            end)
        end

        progressBar.styled = true
    end

    if bar.newIconBg then bar.newIconBg:SetShown(icon:IsShown()) end
end

----------------------------------------------------------------------------------------
--	Skin Timer Bar
----------------------------------------------------------------------------------------
function Quests:SkinTimerBar(tracker, key)
    local timerBar = tracker.usedTimerBars[key]
    local bar = timerBar and timerBar.Bar

    if not timerBar.styled then
        if bar.BorderLeft then bar.BorderLeft:SetAlpha(0) end
        if bar.BorderRight then bar.BorderRight:SetAlpha(0) end
        if bar.BorderMid then bar.BorderMid:SetAlpha(0) end

        bar:SetStatusBarTexture(Media.Textures.Statusbar)
        RefineUI.SetTemplate(bar)
        timerBar.styled = true
    end
end

----------------------------------------------------------------------------------------
--	Hook Trackers for Skinning
----------------------------------------------------------------------------------------
function Quests:HookTrackers()
    for i = 1, #Trackers do
        local tracker = Trackers[i]
        if tracker then
            RefineUI:HookOnce(BuildQuestHookKey(tracker, "GetProgressBar", i), tracker, "GetProgressBar", function(t, k) self:SkinProgressBar(t, k) end)
            RefineUI:HookOnce(BuildQuestHookKey(tracker, "GetTimerBar", i), tracker, "GetTimerBar", function(t, k) self:SkinTimerBar(t, k) end)
            RefineUI:HookOnce(BuildQuestHookKey(tracker, "EndLayout", i), tracker, "EndLayout", function()
                self:StyleObjectiveFrame(tracker)
            end)
        end
    end
end

function Quests:ApplyObjectiveTrackerFonts()
    for size = 12, 22 do
        StyleObjectiveFontString(_G["ObjectiveTrackerFont" .. size])
    end
    StyleObjectiveFontString(_G.ObjectiveTrackerLineFont)
    StyleObjectiveFontString(_G.ObjectiveTrackerHeaderFont)
end

function Quests:StyleObjectiveFrame(frame)
    ForEachChildFrameFontString(frame, function(fontString)
        if fontString.__refineui_objective_fontobject_hooked then return end
        local fontObject = fontString:GetFontObject()
        if fontObject == _G.ObjectiveTrackerLineFont or fontObject == _G.ObjectiveTrackerHeaderFont then return end
        StyleObjectiveFontString(fontString)

        if fontString.SetFontObject then
            fontString.__refineui_objective_fontobject_hooked = true
            RefineUI:HookOnce(BuildQuestHookKey(fontString, "SetFontObject", "ObjectiveText"), fontString, "SetFontObject", function(self)
                StyleObjectiveFontString(self)
            end)
        end
    end)
end

function Quests:ApplyQuestProgressColors()
    local progressTitle = _G.QuestProgressTitleText or _G.QuestProgressTitle
    SetTextColorIfPossible(progressTitle, GOLD_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestProgressText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestProgressRequiredItemsText, GOLD_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestProgressRequiredMoneyText, GOLD_TEXT_COLOR)
end

function Quests:ApplyQuestGreetingColors()
    SetTextColorIfPossible(_G.GreetingText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.CurrentQuestsText, GOLD_TEXT_COLOR)
    SetTextColorIfPossible(_G.AvailableQuestsText, GOLD_TEXT_COLOR)

    local greetingPanel = _G.QuestFrameGreetingPanel
    if not greetingPanel or not greetingPanel.titleButtonPool then
        return
    end

    for button in greetingPanel.titleButtonPool:EnumerateActive() do
        local fontString = button.GetFontString and button:GetFontString()
        if fontString then
            SetTextColorIfPossible(fontString, WHITE_TEXT_COLOR)
            local text = fontString:GetText()
            if text and text ~= "" then
                local replaced = ReplaceQuestInlineColors(text)
                if replaced ~= text then
                    fontString:SetText(replaced)
                end
            end
        end
    end
end

function Quests:InstallQuestProgressHooks()
    if self.questProgressHooksInstalled then
        return true
    end

    local installedAny = false

    local okOnShow = RefineUI:HookOnce(QUEST_PROGRESS_HOOK.PANEL_ON_SHOW, "QuestFrameProgressPanel_OnShow", function()
        self:ApplyQuestProgressColors()
    end)
    if okOnShow then
        installedAny = true
    end

    local panel = _G.QuestFrameProgressPanel
    if panel and panel.HookScript then
        local okPanel = RefineUI:HookScriptOnce(QUEST_PROGRESS_HOOK.PANEL_SCRIPT_ON_SHOW, panel, "OnShow", function()
            self:ApplyQuestProgressColors()
        end)
        if okPanel then
            installedAny = true
        end
    end

    local okItemsUpdate = RefineUI:HookOnce(QUEST_PROGRESS_HOOK.ITEMS_UPDATE, "QuestFrameProgressItems_Update", function()
        self:ApplyQuestProgressColors()
    end)
    if okItemsUpdate then
        installedAny = true
    end

    if installedAny then
        self.questProgressHooksInstalled = true
    end

    return installedAny
end

function Quests:InstallQuestGreetingHooks()
    if self.questGreetingHooksInstalled then
        return true
    end

    local installedAny = false

    local okOnShow = RefineUI:HookOnce(QUEST_GREETING_HOOK.PANEL_ON_SHOW, "QuestFrameGreetingPanel_OnShow", function()
        self:ApplyQuestGreetingColors()
    end)
    if okOnShow then
        installedAny = true
    end

    local panel = _G.QuestFrameGreetingPanel
    if panel and panel.HookScript then
        local okPanel = RefineUI:HookScriptOnce(QUEST_GREETING_HOOK.PANEL_SCRIPT_ON_SHOW, panel, "OnShow", function()
            self:ApplyQuestGreetingColors()
        end)
        if okPanel then
            installedAny = true
        end
    end

    if installedAny then
        self.questGreetingHooksInstalled = true
    end

    return installedAny
end

function Quests:ApplyQuestMapFonts()
    local roots = {
        _G.QuestInfoFrame,
        _G.QuestInfoRewardsFrame,
        _G.MapQuestInfoRewardsFrame,
        QuestMapFrame and QuestMapFrame.DetailsFrame,
    }
    local seen = {}
    for _, root in pairs(roots) do
        if root then
            ForEachChildFrameFontString(root, function(fontString)
                StyleQuestMapFontString(fontString)

                if not fontString.__refineui_questmap_fontobject_hooked and fontString.SetFontObject then
                    fontString.__refineui_questmap_fontobject_hooked = true
                    RefineUI:HookOnce(BuildQuestHookKey(fontString, "SetFontObject", "QuestMap"), fontString, "SetFontObject", function(self)
                        StyleQuestMapFontString(self)
                    end)
                end
            end, seen)
        end
    end

    SetTextColorIfPossible(_G.QuestInfoTitleHeader, GOLD_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoDescriptionHeader, GOLD_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoObjectivesHeader, GOLD_TEXT_COLOR)
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.Header then
        SetTextColorIfPossible(_G.QuestInfoRewardsFrame.Header, GOLD_TEXT_COLOR)
    end

    SetTextColorIfPossible(_G.QuestInfoDescriptionText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoObjectivesText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoGroupSize, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoRewardText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoTimerText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoSpellObjectiveLearnLabel, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestInfoQuestType, WHITE_TEXT_COLOR)
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.ItemChooseText then
        SetTextColorIfPossible(_G.QuestInfoRewardsFrame.ItemChooseText, WHITE_TEXT_COLOR)
    end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.ItemReceiveText then
        SetTextColorIfPossible(_G.QuestInfoRewardsFrame.ItemReceiveText, WHITE_TEXT_COLOR)
    end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.PlayerTitleText then
        SetTextColorIfPossible(_G.QuestInfoRewardsFrame.PlayerTitleText, WHITE_TEXT_COLOR)
    end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.QuestSessionBonusReward then
        SetTextColorIfPossible(_G.QuestInfoRewardsFrame.QuestSessionBonusReward, WHITE_TEXT_COLOR)
    end
    if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.ItemChooseText then
        SetTextColorIfPossible(_G.MapQuestInfoRewardsFrame.ItemChooseText, WHITE_TEXT_COLOR)
    end
    if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.ItemReceiveText then
        SetTextColorIfPossible(_G.MapQuestInfoRewardsFrame.ItemReceiveText, WHITE_TEXT_COLOR)
    end
    if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.PlayerTitleText then
        SetTextColorIfPossible(_G.MapQuestInfoRewardsFrame.PlayerTitleText, WHITE_TEXT_COLOR)
    end
    if _G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.QuestSessionBonusReward then
        SetTextColorIfPossible(_G.MapQuestInfoRewardsFrame.QuestSessionBonusReward, WHITE_TEXT_COLOR)
    end
    local questXPFrame = _G.QuestInfoXPFrame or (_G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.XPFrame)
    if questXPFrame and questXPFrame.ReceiveText then
        SetTextColorIfPossible(questXPFrame.ReceiveText, GOLD_TEXT_COLOR)
    end
    local mapQuestXPFrame = _G.MapQuestInfoXPFrame or (_G.MapQuestInfoRewardsFrame and _G.MapQuestInfoRewardsFrame.XPFrame)
    if mapQuestXPFrame and mapQuestXPFrame.ReceiveText then
        SetTextColorIfPossible(mapQuestXPFrame.ReceiveText, GOLD_TEXT_COLOR)
    end
    self:ApplyQuestProgressColors()
    self:ApplyQuestGreetingColors()
    SetTextColorIfPossible(_G.QuestDetailDescriptionText, WHITE_TEXT_COLOR)
    SetTextColorIfPossible(_G.QuestDetailObjectivesText, WHITE_TEXT_COLOR)

    if _G.QuestInfoSealFrame and _G.QuestInfoSealFrame.Text and _G.QuestInfoSealFrame.Text.GetText and _G.QuestInfoSealFrame.Text.SetText then
        local sealText = _G.QuestInfoSealFrame.Text:GetText()
        if sealText and sealText ~= "" then
            local replacedSealText = ReplaceQuestInlineColors(sealText)
            if replacedSealText ~= sealText then
                _G.QuestInfoSealFrame.Text:SetText(replacedSealText)
            end
        end
    end

    for i = 1, 20 do
        local text = _G["QuestInfoObjective" .. i]
        if text then
            StyleQuestMapFontString(text)
            local line = text:GetText() or ""
            local cur, goal = line:match("(%d+)%s*/%s*(%d+)")
            local isComplete = false

            if cur and goal then
                isComplete = tonumber(cur) and tonumber(goal) and tonumber(cur) >= tonumber(goal)
            elseif line:find("completed", 1, true) then
                isComplete = true
            end

            if isComplete then
                text:SetTextColor(0.60, 1.00, 0.60)
            else
                text:SetTextColor(1, 1, 1)
            end
        end
    end
end



----------------------------------------------------------------------------------------
--	Settings Button & Menu
----------------------------------------------------------------------------------------
local MenuUtil = MenuUtil

function Quests:InitializeZoneGrouping()
    local tracker = QuestObjectiveTracker
    local originalEnum = tracker.EnumQuestWatchData
    local originalAddBlock = tracker.AddBlock
    local originalHeaderHeight = tracker.headerHeight
    local originalHeaderFrameHeight = tracker.Header:GetHeight()
    local originalHeaderOffsetY = tracker.fromHeaderOffsetY
    local zoneHeaders = {}
    local collapsedZones = {}
    local activeZone
    local previousZone

    self.ApplyZoneHeaderMode = function()
        if Config.Quests.GroupTrackedQuestsByZone then
            if tracker:IsCollapsed() then
                tracker:SetCollapsed(false)
            end
            tracker.headerHeight = 0
            tracker.fromHeaderOffsetY = 0
            tracker.Header:SetHeight(0)
            tracker.Header:Hide()
        else
            tracker.headerHeight = originalHeaderHeight
            tracker.fromHeaderOffsetY = originalHeaderOffsetY
            tracker.Header:SetHeight(originalHeaderFrameHeight)
            tracker.Header:Show()
        end
    end

    local function GetZoneHeader(module, zone)
        local header = zoneHeaders[zone]
        if not header then
            header = CreateFrame("Frame", nil, module.ContentsFrame, "ObjectiveTrackerModuleHeaderTemplate")
            header:Hide()
            header.id = "RefineUIZone:" .. zone
            header.height = 26
            header.offsetX = 0
            header:SetHeight(26)
            header.Text:SetText(zone)
            header.MinimizeButton:SetScript("OnClick", function()
                collapsedZones[zone] = not collapsedZones[zone]
                header:SetCollapsed(collapsedZones[zone])
                tracker:MarkDirty()
            end)
            if Config.Quests.HeaderSkinning then
                header.Background:Hide()
                self:SkinHeader(header)
            end
            zoneHeaders[zone] = header
        end
        return header
    end

    RefineUI:HookOnce("Quests:ZoneGrouping:BeginLayout", tracker, "BeginLayout", function()
        for _, header in pairs(zoneHeaders) do
            header:Hide()
        end
        activeZone = nil
        previousZone = nil
    end)

    tracker.EnumQuestWatchData = function(module, callback)
        if not Config.Quests.GroupTrackedQuestsByZone then
            return originalEnum(module, callback)
        end

        local groups = {}
        local zoneOrder = {}
        local zoneNames = {}
        local infos = module:BuildQuestWatchInfos()
        for index = 1, #infos do
            local quest = infos[index].quest
            local headerIndex = C_QuestLog.GetHeaderIndexForQuest(quest:GetID())
            local zone = headerIndex and zoneNames[headerIndex]
            if headerIndex and not zone then
                zone = C_QuestLog.GetTitleForLogIndex(headerIndex)
                zoneNames[headerIndex] = zone
            end
            zone = zone or _G.MISCELLANEOUS or "Other"
            local group = groups[zone]
            if not group then
                group = {}
                groups[zone] = group
                zoneOrder[#zoneOrder + 1] = zone
            end
            group[#group + 1] = quest
        end

        for index = 1, #zoneOrder do
            local zone = zoneOrder[index]
            local group = groups[zone]
            if collapsedZones[zone] then
                local header = GetZoneHeader(module, zone)
                if not originalAddBlock(module, header) then
                    return
                end
                header:Show()
            else
                for questIndex = 1, #group do
                    activeZone = zone
                    if not callback(module, group[questIndex]) then
                        activeZone = nil
                        return
                    end
                end
            end
        end
        activeZone = nil
    end

    tracker.AddBlock = function(module, block)
        if not Config.Quests.GroupTrackedQuestsByZone or not activeZone or activeZone == previousZone
            or block.cached or module:IsCollapsed() then
            return originalAddBlock(module, block)
        end

        if module:HasSkippedBlocks() then
            return false
        end

        local header = GetZoneHeader(module, activeZone)
        -- Reserve the header and first quest together; native LayoutBlock still
        -- owns caching, line cleanup, and the quest's final placement.
        local blockHeight = block.height
        block.height = blockHeight + header.height - module.fromBlockOffsetY
        local fits = module:CanFitBlock(block)
        block.height = blockHeight
        if not fits then
            module.hasTriedBlocks = true
            module.hasSkippedBlocks = true
            return false
        end

        if not originalAddBlock(module, header) then
            return false
        end
        header:Show()
        previousZone = activeZone
        return originalAddBlock(module, block)
    end

    self.ApplyZoneHeaderMode()
end

function Quests:UpdateObjectiveHeaderCount()
    local _, accepted = C_QuestLog.GetNumQuestLogEntries()
    local tracked = C_QuestLog.GetNumQuestWatches()
    local text = tracked > 0 and (tracked .. "/" .. accepted) or tostring(accepted)
    if self.ObjectiveHeaderCount:GetText() ~= text then
        self.ObjectiveHeaderCount:SetText(text)
    end
end

function Quests:CreateSettingsButton()

    local header = ObjectiveTrackerFrame.Header
    local button = RefineUI.CreateSettingsButton(header, "RefineUI_QuestsSettingsButton", 14)
    
    if ObjectiveTrackerFrame.Header.MinimizeButton then
        button:SetPoint("RIGHT", ObjectiveTrackerFrame.Header.MinimizeButton, "LEFT", -4, 0)
    else
        button:SetPoint("TOPRIGHT", ObjectiveTrackerFrame.Header, "TOPRIGHT", -20, -5)
    end

    -- Header.Text is an AutoScalingFontString: its Lua SetText stores scaling
    -- state, and headerText is read by ObjectiveTrackerManager:Init. Either
    -- taints the tracker's module setup, so set the text with the widget method.
    local function SetTrackerHeaderText()
        GetFontStringMetatable().__index.SetText(header.Text, "Objectives")
    end
    SetTrackerHeaderText()
    RefineUI:HookOnce("Quests:TrackerHeaderText", ObjectiveTrackerFrame, "Init", SetTrackerHeaderText)
    local count = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
    count:SetWidth(48)
    count:SetJustifyH("RIGHT")
    count:SetPoint("RIGHT", button, "LEFT", -8, 0)
    header.Text:ClearAllPoints()
    header.Text:SetPoint("LEFT", header, "LEFT", 7, 0)
    header.Text:SetPoint("RIGHT", count, "LEFT", -8, 0)
    self.ObjectiveHeaderCount = count
    self:UpdateObjectiveHeaderCount()
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quest Options", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    button:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() then return end
        
        MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
            rootDescription:CreateTitle("Quest Options")
            
            rootDescription:CreateCheckbox("Auto Accept", function() return Config.Quests.AutoAccept end, function()
                Config.Quests.AutoAccept = not Config.Quests.AutoAccept
                RefineUI:Print("Auto Accept: " .. (Config.Quests.AutoAccept and "Enabled" or "Disabled"))
            end)

            rootDescription:CreateCheckbox("Auto Complete", function() return Config.Quests.AutoComplete end, function()
                Config.Quests.AutoComplete = not Config.Quests.AutoComplete
                RefineUI:Print("Auto Complete: " .. (Config.Quests.AutoComplete and "Enabled" or "Disabled"))
            end)

            rootDescription:CreateDivider()

            rootDescription:CreateCheckbox("Auto Zone Track", function() return Config.Quests.AutoZoneTrack end, function()
                Config.Quests.AutoZoneTrack = not Config.Quests.AutoZoneTrack
                RefineUI:Print("Auto Zone Track: " .. (Config.Quests.AutoZoneTrack and "Enabled" or "Disabled"))
                local module = RefineUI:GetModule("AutoZoneTrack")
                if module and module.UpdateTrigger then module:UpdateTrigger() end
            end)

            rootDescription:CreateCheckbox("Group Tracked Quests by Zone", function() return Config.Quests.GroupTrackedQuestsByZone end, function()
                Config.Quests.GroupTrackedQuestsByZone = not Config.Quests.GroupTrackedQuestsByZone
                -- Installing or removing the grouping mid-session would dirty the
                -- tracker from addon code, so it applies on the next reload.
                RefineUI:Print("Group Tracked Quests by Zone: "
                    .. (Config.Quests.GroupTrackedQuestsByZone and "Enabled" or "Disabled") .. " (reload UI to apply)")
            end)

            rootDescription:CreateDivider()

            local collapseMenu = rootDescription:CreateButton("Auto Collapse Mode")
            
            collapseMenu:CreateRadio("Never", function() return Config.Quests.AutoCollapseMode == "NEVER" end, function()
                Config.Quests.AutoCollapseMode = "NEVER"
                RefineUI:Print("Auto Collapse Mode: Never")
                local module = RefineUI:GetModule("AutoCollapse")
                if module and module.UpdateState then module:UpdateState() end
            end)
            
            collapseMenu:CreateRadio("In Combat", function() return Config.Quests.AutoCollapseMode == "COMBAT" end, function()
                Config.Quests.AutoCollapseMode = "COMBAT"
                RefineUI:Print("Auto Collapse Mode: In Combat")
                local module = RefineUI:GetModule("AutoCollapse")
                if module and module.UpdateState then module:UpdateState() end
            end)
            
            collapseMenu:CreateRadio("In Instance", function() return Config.Quests.AutoCollapseMode == "INSTANCE" end, function()
                Config.Quests.AutoCollapseMode = "INSTANCE"
                RefineUI:Print("Auto Collapse Mode: In Instance")
                local module = RefineUI:GetModule("AutoCollapse")
                if module and module.UpdateState then module:UpdateState() end
            end)
            
            collapseMenu:CreateRadio("On Load", function() return Config.Quests.AutoCollapseMode == "RELOAD" end, function()
                Config.Quests.AutoCollapseMode = "RELOAD"
                RefineUI:Print("Auto Collapse Mode: On Load")
                local module = RefineUI:GetModule("AutoCollapse")
                if module and module.UpdateState then module:UpdateState() end
            end)
            local legacy = RefineUI:GetModule("LegacyCompletionist")
            if legacy and legacy.AddSettings then
                rootDescription:CreateDivider()
                legacy:AddSettings(rootDescription)
            end
        end)
    end)
    
    self.SettingsButton = button
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function Quests:OnInitialize()
    if (not Config.Quests.Enable) then
        return
    end
    
    R, G, B = unpack(RefineUI.MyClassColor)

    if Config.Quests.HeaderSkinning then
        self:HideDefaultBackgrounds()
        self:SkinHeaders()
    end
    
    self:ApplyObjectiveTrackerFonts()
    RefineUI:HookOnce("Quests:TrackerTextSize", ObjectiveTrackerManager, "SetTextSize", function()
        self:ApplyObjectiveTrackerFonts()
    end)
    self:HookTrackers()
    -- Zone grouping replaces QuestObjectiveTracker methods and layout fields,
    -- which taints tracker updates; only install it when the user opts in.
    if Config.Quests.GroupTrackedQuestsByZone then
        self:InitializeZoneGrouping()
    end
    if self.InitializeInstanceTrackerHeader then
        self:InitializeInstanceTrackerHeader()
    end
    self:ApplyQuestMapFonts()
    if QuestMapFrame then
        RefineUI:HookScriptOnce("Quests:QuestMapFrame:OnShow", QuestMapFrame, "OnShow", function()
            self:ApplyQuestMapFonts()
        end)
        if QuestMapFrame.DetailsFrame then
            RefineUI:HookScriptOnce("Quests:QuestMapDetailsFrame:OnShow", QuestMapFrame.DetailsFrame, "OnShow", function()
                self:ApplyQuestMapFonts()
            end)
        end
    end
    RefineUI:HookOnce("Quests:QuestMapFrame_ShowQuestDetails", "QuestMapFrame_ShowQuestDetails", function()
        self:ApplyQuestMapFonts()
    end)

    self:CreateSettingsButton()
    self:StyleObjectiveFrame(ObjectiveTrackerFrame)
    RefineUI:OnEvents({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED" }, function()
        self:UpdateObjectiveHeaderCount()
    end, "Quests:HeaderCount")
    if self.RegisterObjectiveTrackerEditModeSettings then
        self:RegisterObjectiveTrackerEditModeSettings()
    end
    if self.ApplyObjectiveTrackerScale then
        self:ApplyObjectiveTrackerScale()
    end

    RefineUI:HookOnce("Quests:QuestInfo_Display", "QuestInfo_Display", function()
        self:ApplyQuestMapFonts()
    end)
    self:InstallQuestGreetingHooks()
    self:InstallQuestProgressHooks()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_UIPanels_Game" then
            self:InstallQuestGreetingHooks()
            self:InstallQuestProgressHooks()
            self:ApplyQuestGreetingColors()
            self:ApplyQuestProgressColors()
        end
    end, QUEST_PROGRESS_EVENT.ADDON_LOADED)
end
