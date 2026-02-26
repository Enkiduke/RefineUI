----------------------------------------------------------------------------------------
-- Quests for RefineUI
-- Description: Skins quest tracker/map and provides quest settings menu
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Quests = RefineUI:RegisterModule("Quests")
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
local select = select
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetScreenHeight = GetScreenHeight
local C_Timer = C_Timer

local ObjectiveTrackerFrame = _G.ObjectiveTrackerFrame
local QuestMapFrame = _G.QuestMapFrame
local UIParent = _G.UIParent

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local R, G, B = unpack(RefineUI.MyClassColor)

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

    local _, size = fontString:GetFont()
    if not size then
        size = 13
    end

    fontString:SetFont(Media.Fonts.Default, size, "OUTLINE")
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
end

local function StyleQuestMapFontString(fontString)
    if not fontString or not fontString.SetFont then
        return
    end

    local name = fontString.GetName and fontString:GetName() or ""
    local _, size = fontString:GetFont()
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

    fontString:SetFont(Media.Fonts.Default, size, "OUTLINE")
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
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

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            callback(region)
        end
    end

    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
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
        _G.ObjectiveTrackerFrame.Header,
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
        if progressBar.PlayFlareAnim then progressBar.PlayFlareAnim = function() end end

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
            RefineUI:HookOnce(BuildQuestHookKey(tracker, "Update", i), tracker, "Update", function()
                self:ApplyObjectiveTrackerFonts()
            end)
            RefineUI:HookOnce(BuildQuestHookKey(tracker, "AddBlock", i), tracker, "AddBlock", function()
                self:ApplyObjectiveTrackerFonts()
            end)

            RefineUI:HookOnce(BuildQuestHookKey(tracker, "OnBlockHeaderLeave", i), tracker, "OnBlockHeaderLeave", function(_, block)
                if block.HeaderText and block.HeaderText.col then
                    block.HeaderText:SetTextColor(block.HeaderText.col.r, block.HeaderText.col.g, block.HeaderText.col.b)
                end
            end)
        end
    end
end

function Quests:ApplyObjectiveTrackerFonts()
    if not ObjectiveTrackerFrame then
        return
    end

    ForEachChildFrameFontString(ObjectiveTrackerFrame, function(fontString)
        StyleObjectiveFontString(fontString)

        if not fontString.__refineui_objective_fontobject_hooked and fontString.SetFontObject then
            fontString.__refineui_objective_fontobject_hooked = true
            RefineUI:HookOnce(BuildQuestHookKey(fontString, "SetFontObject", "ObjectiveText"), fontString, "SetFontObject", function(self)
                StyleObjectiveFontString(self)
            end)
        end
    end)
end

function Quests:ApplyQuestMapFonts()
    local roots = {
        _G.QuestInfoFrame,
        _G.QuestInfoRewardsFrame,
        _G.MapQuestInfoRewardsFrame,
        QuestMapFrame and QuestMapFrame.DetailsFrame,
        QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.RewardsFrameContainer,
        QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.RewardsFrameContainer and QuestMapFrame.DetailsFrame.RewardsFrameContainer.RewardsFrame,
    }

    for i = 1, #roots do
        local root = roots[i]
        if root then
            ForEachChildFrameFontString(root, function(fontString)
                StyleQuestMapFontString(fontString)

                if not fontString.__refineui_questmap_fontobject_hooked and fontString.SetFontObject then
                    fontString.__refineui_questmap_fontobject_hooked = true
                    RefineUI:HookOnce(BuildQuestHookKey(fontString, "SetFontObject", "QuestMap"), fontString, "SetFontObject", function(self)
                        StyleQuestMapFontString(self)
                    end)
                end
            end)
        end
    end

    if _G.QuestInfoTitleHeader then _G.QuestInfoTitleHeader:SetTextColor(1, 0.82, 0) end
    if _G.QuestInfoDescriptionHeader then _G.QuestInfoDescriptionHeader:SetTextColor(1, 0.82, 0) end
    if _G.QuestInfoObjectivesHeader then _G.QuestInfoObjectivesHeader:SetTextColor(1, 0.82, 0) end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.Header then
        _G.QuestInfoRewardsFrame.Header:SetTextColor(1, 0.82, 0)
    end

    if _G.QuestInfoDescriptionText then _G.QuestInfoDescriptionText:SetTextColor(1, 1, 1) end
    if _G.QuestInfoObjectivesText then _G.QuestInfoObjectivesText:SetTextColor(1, 1, 1) end
    if _G.QuestInfoGroupSize then _G.QuestInfoGroupSize:SetTextColor(1, 1, 1) end
    if _G.QuestInfoRewardText then _G.QuestInfoRewardText:SetTextColor(1, 1, 1) end
    if _G.QuestInfoRewardsFrame and _G.QuestInfoRewardsFrame.ItemReceiveText then
        _G.QuestInfoRewardsFrame.ItemReceiveText:SetTextColor(1, 1, 1)
    end
    if _G.QuestDetailDescriptionText then _G.QuestDetailDescriptionText:SetTextColor(1, 1, 1) end
    if _G.QuestDetailObjectivesText then _G.QuestDetailObjectivesText:SetTextColor(1, 1, 1) end

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

function Quests:CreateSettingsButton()

    local button = RefineUI.CreateSettingsButton(ObjectiveTrackerFrame.Header, "RefineUI_QuestsSettingsButton", 16, "Interface\\AddOns\\RefineUI\\Media\\Textures\\Settings.blp")
    
    if ObjectiveTrackerFrame.Header.MinimizeButton then
        button:SetPoint("RIGHT", ObjectiveTrackerFrame.Header.MinimizeButton, "LEFT", 0, 0)
    else
        button:SetPoint("TOPRIGHT", ObjectiveTrackerFrame.Header, "TOPRIGHT", -20, -5)
    end
    
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
    
    self:HookTrackers()
    self:ApplyObjectiveTrackerFonts()
    RefineUI:HookOnce("Quests:ObjectiveTracker_Update", "ObjectiveTracker_Update", function()
        self:ApplyObjectiveTrackerFonts()
    end)
    C_Timer.After(0.1, function()
        self:ApplyObjectiveTrackerFonts()
    end)
    C_Timer.After(0.5, function()
        self:ApplyObjectiveTrackerFonts()
    end)
    self:ApplyQuestMapFonts()
    C_Timer.After(0.1, function()
        self:ApplyQuestMapFonts()
    end)
    C_Timer.After(0.5, function()
        self:ApplyQuestMapFonts()
    end)
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

    if not InCombatLockdown() then
        ObjectiveTrackerFrame:SetParent(UIParent)
        ObjectiveTrackerFrame:SetAlpha(1)
        ObjectiveTrackerFrame:Show()
        ObjectiveTrackerFrame:SetScale(1.2)
    end
    
    RefineUI:HookOnce("Quests:QuestInfo_Display", "QuestInfo_Display", function()
        self:ApplyQuestMapFonts()
    end)
end
