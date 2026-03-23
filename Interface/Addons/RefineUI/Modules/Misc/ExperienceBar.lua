local AddOnName, RefineUI = ...
local LibEditMode = LibStub("LibEditMode")

-- Call Modules
local ExperienceBar = RefineUI:RegisterModule("ExperienceBar")

-- Lib Globals
local _G = _G
local select = select
local unpack = unpack
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
local tostring = tostring
local tonumber = tonumber
local type = type
local sort = table.sort

-- WoW Globals
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local GetXPExhaustion = GetXPExhaustion
local GetRestState = GetRestState
local UnitLevel = UnitLevel
local GetPetExperience = GetPetExperience
local IsXPUserDisabled = IsXPUserDisabled
local UnitHonor = UnitHonor
local UnitHonorMax = UnitHonorMax
local UnitHonorLevel = UnitHonorLevel
local C_Reputation = C_Reputation
local C_MajorFactions = C_MajorFactions
local C_PvP = C_PvP
local C_Texture = C_Texture
local GameTooltip = GameTooltip
local BreakUpLargeNumbers = BreakUpLargeNumbers
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame

-- Locals
local Mult = 2.5
local CurrentType = "experience"
local BAR_WIDTH = 294
local BAR_HEIGHT = 30
local ICON_SIZE = BAR_HEIGHT + 4
local ICON_GAP = 6
local MAJOR_FACTION_ICON_ATLAS_FORMAT = "majorfactions_icons_%s512"
local DEFAULT_IDLE_ALPHA = 0.5
local DEFAULT_BAR_SCALE = 1.0
local MIN_BAR_SCALE = 0.75
local MAX_BAR_SCALE = 1.5
local FRAME_NAME = "RefineUI_ExperienceBar"

local Colors = {
	experience = { 0.6 * Mult, 0, 0.6 * Mult }, -- Purple
	rested = { 0, 0.39, 0.88 }, -- Blue
	honor = { 1, 0.71, 0 }, -- Orange
	renown = { 0.4, 0.2, 0.8 }, -- Covenant Purple
	reputation = { 0, 0.6, 1 }, -- Blue
}

local RENOWN_EVENTS = {
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
	"MAJOR_FACTION_UNLOCKED",
}

local EXPANSION_LEVEL = {
    DRAGONFLIGHT = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.Dragonflight) or 9,
    WAR_WITHIN = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.WarWithin) or 10,
    MIDNIGHT = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.Midnight) or 11,
}

local MAJOR_FACTION_EXPANSIONS = {
    { id = EXPANSION_LEVEL.MIDNIGHT, label = "Midnight" },
    { id = EXPANSION_LEVEL.WAR_WITHIN, label = "The War Within" },
    { id = EXPANSION_LEVEL.DRAGONFLIGHT, label = "Dragonflight" },
}

local function ClampAlpha(value, fallback)
    local alpha = tonumber(value)
    if not alpha then
        alpha = fallback or DEFAULT_IDLE_ALPHA
    end

    if alpha < 0 then
        return 0
    elseif alpha > 1 then
        return 1
    end

    return alpha
end

local function ClampScale(value)
    local scale = tonumber(value)
    if not scale then
        scale = DEFAULT_BAR_SCALE
    end

    if scale < MIN_BAR_SCALE then
        scale = MIN_BAR_SCALE
    elseif scale > MAX_BAR_SCALE then
        scale = MAX_BAR_SCALE
    end

    return floor((scale * 100) + 0.5) / 100
end

function ExperienceBar:GetBarScale()
    return ClampScale(self.db and self.db.Scale)
end

function ExperienceBar:GetScaledMetrics()
    local scale = self:GetBarScale()
    local width = max(1, floor((BAR_WIDTH * scale) + 0.5))
    local height = max(1, floor((BAR_HEIGHT * scale) + 0.5))
    local iconSize = max(1, floor((ICON_SIZE * scale) + 0.5))
    local iconGap = max(0, floor((ICON_GAP * scale) + 0.5))
    local textSize = max(8, floor((16 * scale) + 0.5))
    local textOffsetY = floor((6 * scale) + 0.5)

    return width, height, iconSize, iconGap, textSize, textOffsetY
end

function ExperienceBar:IsMouseoverEnabled()
    return not self.db or self.db.Mouseover ~= false
end

function ExperienceBar:GetIdleAlpha()
    return ClampAlpha(self.db and self.db.Alpha, DEFAULT_IDLE_ALPHA)
end

function ExperienceBar:RefreshEditModeSettingsAvailability()
    if not (LibEditMode and self.Frame and self._editModeSettings) then
        return
    end

    local alphaSetting
    for _, setting in ipairs(self._editModeSettings) do
        if setting.name == "Alpha When Not Moused-Over" then
            alphaSetting = setting
            break
        end
    end

    if alphaSetting then
        alphaSetting.disabled = not self:IsMouseoverEnabled()
    end

    if type(LibEditMode.RefreshFrameSettings) == "function" then
        LibEditMode:RefreshFrameSettings(self.Frame)
    end
end

function ExperienceBar:ApplyAlphaState()
    if not self.Frame then
        return
    end

    if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(self.Frame)
    end

    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        self.Frame:SetAlpha(1)
        return
    end

    if self:IsMouseoverEnabled() then
        if self.Frame:IsMouseOver() then
            self.Frame:SetAlpha(1)
        else
            self.Frame:SetAlpha(self:GetIdleAlpha())
        end
    else
        self.Frame:SetAlpha(1)
    end
end

function ExperienceBar:ApplyScale()
    if not (self.Frame and self.Bar and self.IconFrame and self.Text) then
        return
    end

    local width, height, iconSize, _, textSize, textOffsetY = self:GetScaledMetrics()

    if RefineUI.SetPixelSize then
        RefineUI:SetPixelSize(self.Frame, width, height)
        RefineUI:SetPixelSize(self.IconFrame, iconSize, iconSize)
    else
        self.Frame:SetSize(width, height)
        self.IconFrame:SetSize(iconSize, iconSize)
    end

    self.Text:ClearAllPoints()
    RefineUI.Point(self.Text, "CENTER", self.Bar, "CENTER", 0, textOffsetY)
    RefineUI.Font(self.Text, textSize)

    self:UpdateBarLayout(self.IconFrame:IsShown())
end

function ExperienceBar:RegisterEditModeSettings()
    if not (LibEditMode and self.Frame and type(LibEditMode.AddFrameSettings) == "function") then
        return
    end
    if self._editModeSettingsAttached then
        return
    end

    local settings = {
        {
            kind = LibEditMode.SettingType.Slider,
            name = "Scale",
            default = DEFAULT_BAR_SCALE,
            minValue = MIN_BAR_SCALE,
            maxValue = MAX_BAR_SCALE,
            valueStep = 0.05,
            formatter = function(value)
                return format("%.2f", ClampScale(value))
            end,
            get = function()
                return ExperienceBar:GetBarScale()
            end,
            set = function(_, value)
                ExperienceBar.db.Scale = ClampScale(value)
                ExperienceBar:ApplyScale()
            end,
        },
        {
            kind = LibEditMode.SettingType.Checkbox,
            name = "Mouseover",
            default = false,
            get = function()
                return ExperienceBar:IsMouseoverEnabled()
            end,
            set = function(_, value)
                ExperienceBar.db.Mouseover = value == true
                ExperienceBar:ApplyAlphaState()
                ExperienceBar:RefreshEditModeSettingsAvailability()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = "Alpha When Not Moused-Over",
            default = DEFAULT_IDLE_ALPHA,
            minValue = 0,
            maxValue = 1,
            valueStep = 0.05,
            disabled = not self:IsMouseoverEnabled(),
            get = function()
                return ExperienceBar:GetIdleAlpha()
            end,
            set = function(_, value)
                ExperienceBar.db.Alpha = ClampAlpha(value, DEFAULT_IDLE_ALPHA)
                ExperienceBar:ApplyAlphaState()
            end,
        },
    }

    self._editModeSettings = settings
    LibEditMode:AddFrameSettings(self.Frame, settings)
    self._editModeSettingsAttached = true
    self:RefreshEditModeSettingsAvailability()
end

function ExperienceBar:RegisterEditModeCallbacks()
    if self._editModeCallbacksRegistered or not (LibEditMode and type(LibEditMode.RegisterCallback) == "function") then
        return
    end

    LibEditMode:RegisterCallback("enter", function()
        ExperienceBar:ApplyAlphaState()
    end)

    LibEditMode:RegisterCallback("exit", function()
        ExperienceBar:ApplyAlphaState()
    end)

    self._editModeCallbacksRegistered = true
end

function ExperienceBar:CreateBar()
	local Container = CreateFrame("Frame", FRAME_NAME, _G.UIParent)
    local width, height, iconSize, _, textSize, textOffsetY = self:GetScaledMetrics()
    
    -- Strict API: Size and Point
	if RefineUI.SetPixelSize then
        RefineUI:SetPixelSize(Container, width, height)
    else
        Container:SetSize(width, height)
    end
	
    -- Position Priority: Central Config > DB Saved > Default
    local pos = (RefineUI.Positions and RefineUI.Positions[FRAME_NAME]) or { "TOP", "Minimap", "BOTTOM", 0, -10 }
    
    -- Handle string relativeTo
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    if type(relativeTo) == "string" then
        relativeTo = _G[relativeTo] or _G.UIParent
    end
	RefineUI.Point(Container, point, relativeTo, relativePoint, x, y)

	Container.editModeName = "Experience Bar"
	if LibEditMode then
		LibEditMode:AddFrame(Container, function(frame, layout, point, x, y)
			RefineUI:SetPosition(FRAME_NAME, { point, "UIParent", point, x, y })
		end, { point = point, x = x, y = y })
	end

    Container:EnableMouse(true)
	Container:SetAlpha(1)

	local Bar = CreateFrame("StatusBar", nil, Container)
	RefineUI.Point(Bar, "TOPLEFT", Container, "TOPLEFT", 0, 0)
	RefineUI.Point(Bar, "BOTTOMRIGHT", Container, "BOTTOMRIGHT", 0, 0)
    
	Bar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
	Bar:SetStatusBarColor(unpack(Colors.experience))
    
	-- Strict API: CreateBackdrop/Shadow
	RefineUI.CreateBackdrop(Bar) -- Should default to 'Default' template logic
    
    if Bar.bg and Bar.bg.border then
        Bar.bg.border:SetFrameLevel(Bar:GetFrameLevel() + 1)
    end

	local IconFrame = CreateFrame("Frame", nil, Container)
	if RefineUI.SetPixelSize then
        RefineUI:SetPixelSize(IconFrame, iconSize, iconSize)
    else
        IconFrame:SetSize(iconSize, iconSize)
    end
	RefineUI.Point(IconFrame, "LEFT", Container, "LEFT", 0, 0)
    RefineUI.CreateBackdrop(IconFrame, "Default")
    IconFrame:Hide()

    if IconFrame.bg and IconFrame.bg.border then
        IconFrame.bg.border:SetFrameLevel(IconFrame:GetFrameLevel() + 1)
    end

    local IconTexture = IconFrame:CreateTexture(nil, "ARTWORK")
    IconTexture:SetPoint("TOPLEFT", IconFrame, "TOPLEFT", 2, -2)
    IconTexture:SetPoint("BOTTOMRIGHT", IconFrame, "BOTTOMRIGHT", -2, 2)
    IconTexture:Hide()

	local BarRested = CreateFrame("StatusBar", nil, Bar)
	RefineUI.SetInside(BarRested)
	BarRested:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
	BarRested:SetStatusBarColor(unpack(Colors.rested))
	BarRested:SetFrameLevel(Bar:GetFrameLevel() - 1)
	BarRested:Hide()

	local InvisFrame = CreateFrame("Frame", nil, Bar)
	InvisFrame:SetFrameLevel(Bar:GetFrameLevel() + 10)
	RefineUI.SetInside(InvisFrame)

	local Text = InvisFrame:CreateFontString(nil, "OVERLAY")
	RefineUI.Point(Text, "CENTER", Bar, "CENTER", 0, textOffsetY)
    
    -- Strict API: Font
	RefineUI.Font(Text, textSize) -- Defaults to RefineUI.Media.Fonts.Default
    
    -- Context Menu
    local MenuUtil = MenuUtil
    Container:SetScript("OnEnter", function(frame) ExperienceBar:OnEnter(frame) end)
    Container:SetScript("OnLeave", function(frame) ExperienceBar:OnLeave(frame) end)
    Container:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                rootDescription:CreateTitle("Experience Bar")

                local pLevel = UnitLevel("player")
                local maxLevel = GetMaxLevelForPlayerExpansion()
                local maxPlayerLevel = _G.MAX_PLAYER_LEVEL or 0
                if maxLevel == 0 and maxPlayerLevel > 0 then
                    maxLevel = maxPlayerLevel
                end
                local pIsMaxLevel = pLevel >= maxLevel

                local experienceRadio = rootDescription:CreateRadio("Experience", function()
                    return not pIsMaxLevel and (ExperienceBar.db.SubMaxTrackMode or "EXPERIENCE") == "EXPERIENCE"
                end, function()
                    ExperienceBar.db.SubMaxTrackMode = "EXPERIENCE"
                    RefineUI:Print("Tracking: Experience")
                    ExperienceBar:OnEvent()
                end)
                experienceRadio:SetEnabled(not pIsMaxLevel)

                rootDescription:CreateRadio("Reputation", function()
                    return pIsMaxLevel or ExperienceBar.db.SubMaxTrackMode == "REPUTATION"
                end, function()
                    ExperienceBar.db.SubMaxTrackMode = "REPUTATION"
                    RefineUI:Print("Tracking: Reputation")
                    ExperienceBar:OnEvent()
                end)

                rootDescription:CreateDivider()

                -- Status / Clear Manual
                local currentWatched = C_Reputation.GetWatchedFactionData()
                if not currentWatched then
                    local numFactions = C_Reputation.GetNumFactions()
                    for i = 1, numFactions do
                        local factionData = C_Reputation.GetFactionDataByIndex(i)
                        if factionData and factionData.isWatched then
                            currentWatched = factionData
                            break
                        end
                    end
                end

                -- Auto-Track Settings
                local autoTrackName = "Auto-Track"
                if ExperienceBar.db.AutoTrack == "RECENT" then autoTrackName = autoTrackName .. " (Recent)"
                else autoTrackName = autoTrackName .. " (Closest)"
                end
                
                local autoTrackMenu = rootDescription:CreateButton(autoTrackName)
                autoTrackMenu:SetEnabled(not currentWatched)
                
                autoTrackMenu:CreateRadio("Closest", function() return ExperienceBar.db.AutoTrack == "CLOSEST" end, function()
                    ExperienceBar.db.AutoTrack = "CLOSEST"
                    RefineUI:Print("Auto-Track: Closest")
                    ExperienceBar:OnEvent()
                end)
                
                autoTrackMenu:CreateRadio("Recent", function() return ExperienceBar.db.AutoTrack == "RECENT" end, function()
                    ExperienceBar.db.AutoTrack = "RECENT"
                    RefineUI:Print("Auto-Track: Recent")
                    ExperienceBar:OnEvent()
                end)
                
                rootDescription:CreateDivider()

                if currentWatched then
                    rootDescription:CreateButton("|cffFF0000Stop Tracking|r " .. (currentWatched.name or ""), function()
                        C_Reputation.SetWatchedFactionByID(0) -- Clear watch
                        RefineUI:Print("Manual tracking cleared. Auto-Track resumed.")
                        ExperienceBar:OnEvent()
                    end)
                    rootDescription:CreateDivider()
                end

                local function AddFactionMenu(parent, majorFactionData)
                    if not majorFactionData then
                        return
                    end

                    local factionID = majorFactionData.factionID
                    local name = majorFactionData.name or ("Faction " .. tostring(factionID))
                    local level = majorFactionData.renownLevel or 0
                    local isMaxed = C_MajorFactions.HasMaximumRenown(factionID)
                    local text = format("%s (Lvl %d)", name, level)

                    if not majorFactionData.isUnlocked then
                        text = "|cff808080" .. text .. " (" .. (_G.MAJOR_FACTION_BUTTON_FACTION_LOCKED or "Locked") .. ")|r"
                    elseif isMaxed then
                        text = "|cff808080" .. text .. " (Maxed)|r"
                    end

                    parent:CreateRadio(text, function()
                        local watched = C_Reputation.GetWatchedFactionData()
                        return watched and watched.factionID == factionID
                    end, function()
                        if not majorFactionData.isUnlocked or isMaxed then
                            return
                        end

                        C_Reputation.SetWatchedFactionByID(factionID)
                        RefineUI:Print("Watching: " .. name)
                        ExperienceBar:OnEvent()
                    end)
                end

                for _, expansionInfo in ipairs(MAJOR_FACTION_EXPANSIONS) do
                    local factionIDs = C_MajorFactions.GetMajorFactionIDs(expansionInfo.id)
                    if factionIDs and #factionIDs > 0 then
                        local menu = rootDescription:CreateButton(expansionInfo.label)
                        local majorFactions = {}

                        for _, factionID in ipairs(factionIDs) do
                            if not C_MajorFactions.IsMajorFactionHiddenFromExpansionPage(factionID) then
                                local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
                                if majorFactionData then
                                    majorFactions[#majorFactions + 1] = majorFactionData
                                end
                            end
                        end

                        sort(majorFactions, function(a, b)
                            if a.uiPriority ~= b.uiPriority then
                                return a.uiPriority < b.uiPriority
                            end

                            return a.name < b.name
                        end)

                        for _, majorFactionData in ipairs(majorFactions) do
                            AddFactionMenu(menu, majorFactionData)
                        end
                    end
                end
                
            end)
        end
    end)

	self.Frame = Container
	self.Bar = Bar
	self.BarRested = BarRested
	self.IconFrame = IconFrame
	self.IconTexture = IconTexture
	self.Text = Text

    self:ApplyScale()
    self:RegisterEditModeSettings()
    self:RegisterEditModeCallbacks()
    self:ApplyAlphaState()
end

----------------------------------------------------------------------------------------
-- Helper: Process faction data (DRY - used by both explicit watch and fallback)
----------------------------------------------------------------------------------------
local function ProcessFactionData(factionData)
	if not factionData then return nil end
	
	local name = factionData.name
	local factionID = factionData.factionID
	local reaction = factionData.reaction or 0
	local currentStanding = factionData.currentStanding or 0
	local currentThreshold = factionData.currentReactionThreshold or 0
	local nextThreshold = factionData.nextReactionThreshold
	
	local cur = max(0, currentStanding - currentThreshold)
	local maxVal = (nextThreshold and (nextThreshold - currentThreshold)) or 1
	if maxVal <= 0 then maxVal = 1 end
	if cur > maxVal then cur = maxVal end
	local perc = floor(cur / maxVal * 100 + 0.5)

	-- Check for Major Faction (Renown)
	if C_MajorFactions and C_MajorFactions.GetMajorFactionData and factionID then
        -- If Max Renown, check if Paragon is available first
        local isMaxRenown = C_MajorFactions.HasMaximumRenown(factionID)
        local isParagon = C_Reputation.IsFactionParagon(factionID)
        
        -- If NOT (Max + Paragon), then show Renown normal data
        if not (isMaxRenown and isParagon) then
            local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorFactionData and majorFactionData.renownLevel then
                local rCur = majorFactionData.renownReputationEarned or 0
                local rMax = majorFactionData.renownLevelThreshold or 1
                if rMax <= 0 then rMax = 1 end
                if rCur > rMax then rCur = rMax end
                local rPerc = floor(rCur / rMax * 100 + 0.5)
                return rCur, rMax, rPerc, 0, 0, majorFactionData.renownLevel, "renown", majorFactionData.name or name, factionID
            end
        end
	end

	-- Check for Paragon
	if C_Reputation.IsFactionParagon(factionID) then
		local currentValue, threshold, rewardQuestID, hasRewardPending, tooLowLevelForParagon = C_Reputation.GetFactionParagonInfo(factionID)
		if currentValue and threshold then
			local cur = currentValue % threshold
			local maxVal = threshold
			if maxVal <= 0 then maxVal = 1 end
			local perc = floor(cur / maxVal * 100 + 0.5)
			return cur, maxVal, perc, 0, 0, "Paragon", "reputation", name, factionID
		end
	end

	-- Standard reputation
	local standingText = _G['FACTION_STANDING_LABEL' .. reaction] or tostring(reaction)
	return cur, maxVal, perc, 0, 0, standingText, "reputation", name, factionID
end

-- Fallback: Iterate all factions if GetWatchedFactionData fails (Blizzard Bug #584)
local function GetWatchedFactionData_Fallback()
    local numFactions = C_Reputation.GetNumFactions()
    for i = 1, numFactions do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if data and data.isWatched then
            return data
        end
    end
    return nil
end

local LastGainedFactionID = nil

local function GetMajorFactionIconAtlas(factionID)
    if not (factionID and C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_Texture and C_Texture.GetAtlasInfo) then
        return nil
    end

    local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
    if not (majorFactionData and majorFactionData.textureKit) then
        return nil
    end

    local atlas = format(MAJOR_FACTION_ICON_ATLAS_FORMAT, majorFactionData.textureKit)
    if not C_Texture.GetAtlasInfo(atlas) then
        return nil
    end

    return atlas
end

local function GetMajorFactionDataForExpansion(expansionID)
    if not (C_MajorFactions and C_MajorFactions.GetMajorFactionIDs and C_MajorFactions.GetMajorFactionData) then
        return {}
    end

    local majorFactions = {}
    local factionIDs = C_MajorFactions.GetMajorFactionIDs(expansionID)
    for _, factionID in ipairs(factionIDs or {}) do
        if not C_MajorFactions.IsMajorFactionHiddenFromExpansionPage(factionID) then
            local data = C_MajorFactions.GetMajorFactionData(factionID)
            if data then
                majorFactions[#majorFactions + 1] = data
            end
        end
    end

    sort(majorFactions, function(a, b)
        if a.uiPriority ~= b.uiPriority then
            return a.uiPriority < b.uiPriority
        end

        if a.name and b.name then
            return a.name < b.name
        end

        return (a.factionID or 0) < (b.factionID or 0)
    end)

    return majorFactions
end

local function GetAllKnownMajorFactionData()
    local allMajorFactions = {}
    local seenFactionIDs = {}

    for _, expansionInfo in ipairs(MAJOR_FACTION_EXPANSIONS) do
        for _, majorFactionData in ipairs(GetMajorFactionDataForExpansion(expansionInfo.id)) do
            local factionID = majorFactionData.factionID
            if factionID and not seenFactionIDs[factionID] then
                allMajorFactions[#allMajorFactions + 1] = majorFactionData
                seenFactionIDs[factionID] = true
            end
        end
    end

    return allMajorFactions
end

local function GetClosestFaction()
    local currentExpansionID = GetExpansionLevel()
    local bestCurrentData = nil
    local bestCurrentPerc = -1
    local bestFallbackData = nil
    local bestFallbackPerc = -1

    for _, majorFactionData in ipairs(GetAllKnownMajorFactionData()) do
        local factionID = majorFactionData.factionID
        local isMax = C_MajorFactions.HasMaximumRenown(factionID)
        local isParagon = C_Reputation.IsFactionParagon(factionID)
        
        if not isMax or isParagon then
            local valid = false
            local perc = 0
            
            if isMax and isParagon then
                 local currentValue, threshold = C_Reputation.GetFactionParagonInfo(factionID)
                 if currentValue and threshold and threshold > 0 then
                     perc = (currentValue % threshold) / threshold
                     valid = true
                 end
            elseif majorFactionData.expansionID == currentExpansionID and majorFactionData.isUnlocked then
                 local rCur = majorFactionData.renownReputationEarned or 0
                 local rMax = majorFactionData.renownLevelThreshold or 1
                 if rMax > 0 then
                     perc = rCur / rMax
                     valid = true
                 end
            end
            
            if valid then
                if majorFactionData.expansionID == currentExpansionID then
                    if perc > bestCurrentPerc then
                        bestCurrentPerc = perc
                        bestCurrentData = majorFactionData
                    end
                elseif perc > bestFallbackPerc then
                    bestFallbackPerc = perc
                    bestFallbackData = majorFactionData
                end
            end
        end
    end
    
    return bestCurrentData or bestFallbackData
end

local function GetRecentFaction()
    if not LastGainedFactionID then return nil end
    return C_Reputation.GetFactionDataByID(LastGainedFactionID)
end

function ExperienceBar:UpdateBarLayout(showIcon)
    if not self.Bar or not self.Frame then
        return
    end

    local _, _, iconSize, iconGap = self:GetScaledMetrics()

    self.Bar:ClearAllPoints()
    if showIcon then
        RefineUI.Point(self.Bar, "TOPLEFT", self.Frame, "TOPLEFT", iconSize + iconGap, 0)
        RefineUI.Point(self.Bar, "BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", 0, 0)
    else
        RefineUI.Point(self.Bar, "TOPLEFT", self.Frame, "TOPLEFT", 0, 0)
        RefineUI.Point(self.Bar, "BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", 0, 0)
    end
end

function ExperienceBar:UpdateTrackedFactionIcon(factionID)
    if not (self.IconFrame and self.IconTexture) then
        return
    end

    local atlas = GetMajorFactionIconAtlas(factionID)
    if atlas then
        self.IconTexture:SetAtlas(atlas, true)
        self.IconTexture:Show()
        self.IconFrame:Show()
        self:UpdateBarLayout(true)
        return
    end

    self.IconTexture:SetTexture(nil)
    self.IconTexture:Hide()
    self.IconFrame:Hide()
    self:UpdateBarLayout(false)
end

function ExperienceBar:GetValues()
	local pLevel = UnitLevel('player')
	local maxLevel = GetMaxLevelForPlayerExpansion()
	local maxPlayerLevel = _G.MAX_PLAYER_LEVEL or 0
	if maxLevel == 0 and maxPlayerLevel > 0 then maxLevel = maxPlayerLevel end
	local pIsMaxLevel = pLevel >= maxLevel

    local function GetExperienceValues()
        local cur, maxVal = UnitXP('player'), UnitXPMax('player')
        if maxVal <= 0 then maxVal = 1 end
        local rested = GetXPExhaustion() or 0
        local perc = floor(cur / maxVal * 100 + 0.5)
        local restedPerc = floor(rested / maxVal * 100 + 0.5)
        return cur, maxVal, perc, rested, restedPerc, pLevel, "experience", nil, nil
    end

    local shouldTrackRepAtSubMax = self.db and self.db.SubMaxTrackMode == "REPUTATION"
    if not pIsMaxLevel and not shouldTrackRepAtSubMax then
        return GetExperienceValues()
    end

	-- 1. Check for faction explicitly watched via "Show as Experience Bar"
	local watchedFactionData = C_Reputation.GetWatchedFactionData()
	if not watchedFactionData then
		watchedFactionData = GetWatchedFactionData_Fallback()
	end

    -- AutoTrack applies for max level, or when sub-max rep override is enabled
    if not watchedFactionData and self.db and self.db.AutoTrack and (pIsMaxLevel or shouldTrackRepAtSubMax) then
        if self.db.AutoTrack == "RECENT" then
            watchedFactionData = GetRecentFaction() or GetClosestFaction()
        elseif self.db.AutoTrack == "CLOSEST" then
            watchedFactionData = GetClosestFaction()
        end
    end
	
    if pIsMaxLevel then
	    -- If we found data via AutoTrack or Fallback, we should process it even if isWatched is false
	    if watchedFactionData then
		    local result = {ProcessFactionData(watchedFactionData)}
		    if result[1] then return unpack(result) end
	    end

	    -- 2. Check for Honor (only at max level, if not showing Renown/Rep)
	    local pIsMaxHonorLevel = C_PvP and C_PvP.GetNextHonorLevelForReward and not C_PvP.GetNextHonorLevelForReward(UnitHonorLevel('player'))
	    local shouldShowHonorBar = pIsMaxLevel and IsWatchingHonorAsXP()
	
	    if shouldShowHonorBar and not pIsMaxHonorLevel then
		    local cur = UnitHonor('player')
		    local maxVal = UnitHonorMax('player') or 1
		    if maxVal <= 0 then maxVal = 1 end
		    local level = UnitHonorLevel('player')
		    local perc = floor(cur / maxVal * 100 + 0.5)
		    return cur, maxVal, perc, 0, 0, level, "honor", nil, nil
	    end

	    -- 4. Fallback: At max level, display watched faction data
	    if watchedFactionData then
		    local result = {ProcessFactionData(watchedFactionData)}
		    if result[1] then return unpack(result) end
	    end
    else
        -- Sub-max rep override path: show rep if available, otherwise fall back to XP.
	    if watchedFactionData then
		    local result = {ProcessFactionData(watchedFactionData)}
		    if result[1] then return unpack(result) end
	    end
        return GetExperienceValues()
	end

	return 0, 1, 0, 0, 0, pLevel, "none", nil, nil
end

function ExperienceBar:OnEnter(frame)
	local cur, maxVal, perc, rested, restedPerc, level, barType, name = ExperienceBar:GetValues()
	
	GameTooltip:ClearLines()
	GameTooltip:SetOwner(frame, "ANCHOR_CURSOR", 0, -6)
	
	if barType == "renown" then
		local RENOWN = _G.RENOWN or 'Renown'
		local RENOWN_LEVEL_LABEL = _G.RENOWN_LEVEL_LABEL or 'Level %d'
		GameTooltip:AddLine(format("%s - %s", name or RENOWN, format(RENOWN_LEVEL_LABEL, level or 0)))
		GameTooltip:AddDoubleLine("Current Renown:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
	elseif barType == "reputation" then
		GameTooltip:AddLine(format("%s - %s", name or "Reputation", level or ""))
		GameTooltip:AddDoubleLine("Current Reputation:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
	elseif barType == "honor" then
		GameTooltip:AddLine(HONOR_LEVEL_LABEL:format(level or 0))
		GameTooltip:AddDoubleLine("Current Honor:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
	elseif barType == "experience" then
		GameTooltip:AddLine("|cffffd200Experience|r")
		GameTooltip:AddDoubleLine("Current Experience:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Remaining Experience:", format("%s (%d%%)", BreakUpLargeNumbers(maxVal - cur), floor((maxVal - cur) / maxVal * 100, 2)), 1, 1, 1, 1, 1, 1)
		
		if rested and rested > 0 then
			GameTooltip:AddDoubleLine("Rested Experience:", format("%s (%d%%)", BreakUpLargeNumbers(rested), restedPerc), 0, 0.6, 1, 1, 1, 1)
		end
	end

	GameTooltip:Show()

    if not self:IsMouseoverEnabled() then
        if UIFrameFadeRemoveFrame then
            UIFrameFadeRemoveFrame(frame)
        end
        frame:SetAlpha(1)
        return
    end

	RefineUI:FadeIn(frame, 0.2, 1)
end

function ExperienceBar:OnLeave(frame)
	GameTooltip:Hide()

    if not self:IsMouseoverEnabled() then
        if UIFrameFadeRemoveFrame then
            UIFrameFadeRemoveFrame(frame)
        end
        frame:SetAlpha(1)
        return
    end

	RefineUI:FadeOut(frame, 0.5, self:GetIdleAlpha())
end

function ExperienceBar:OnEvent(event, arg1)
    if event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        local factionName = arg1:match(FACTION_STANDING_INCREASED:gsub("%%s", "(.*)"):gsub("%%d", ".*")) or
                            arg1:match(FACTION_STANDING_DECREASED:gsub("%%s", "(.*)"):gsub("%%d", ".*"))
        if factionName then
             -- We have a name, but need ID. Iterate to find it.
             local numFactions = C_Reputation.GetNumFactions()
             for i=1, numFactions do
                 local data = C_Reputation.GetFactionDataByIndex(i)
                 if data and data.name == factionName then
                     -- Track recent major faction gains across all known renown factions.
                     local majorData = C_MajorFactions.GetMajorFactionData(data.factionID)
                     if majorData then
                        LastGainedFactionID = data.factionID
                        if self.db.AutoTrack == "RECENT" then self:OnEvent() end -- Force update
                     end
                     return
                 end
             end
        end
        return
    end

	local cur, maxVal, perc, rested, restedPerc, level, barType, name, factionID = self:GetValues()
	CurrentType = barType

	self.Bar:SetMinMaxValues(0, maxVal)
	self.Bar:SetValue(cur) -- Removed UI.SmoothBars wrapper as it's not strictly part of Core API yet unless implemented

	-- Update Colors
	local color = Colors[barType] or Colors.experience
	self.Bar:SetStatusBarColor(unpack(color))

	-- Rested Logic
	if barType == "experience" and rested and rested > 0 then
		self.BarRested:SetMinMaxValues(0, maxVal)
		self.BarRested:SetValue(math.min(cur + rested, maxVal))
		self.BarRested:Show()
		self.BarRested:SetStatusBarColor(unpack(Colors.rested))
	else
		self.BarRested:Hide()
	end

    self:UpdateTrackedFactionIcon(factionID)
	
	-- Visibility Checks
	local shouldShow = true
	if barType == "none" then
		shouldShow = false
	elseif UnitHasVehicleUI and UnitHasVehicleUI("player") then
		shouldShow = false
	elseif barType == "experience" and IsXPUserDisabled and IsXPUserDisabled() then
		shouldShow = false
	end

	-- Force Show in Edit Mode
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
		shouldShow = true
		if cur == 0 and maxVal == 1 then
			cur, maxVal, perc = 50, 100, 50
			self.Bar:SetMinMaxValues(0, maxVal)
			self.Bar:SetValue(cur)
		end
	end

	if shouldShow then
		self.Frame:Show()
        self.Bar:Show()
        self:ApplyAlphaState()
	else
		self.Frame:Hide()
	end
end

function ExperienceBar:RegisterEvents()
	local events = {
		"PLAYER_ENTERING_WORLD",
		"PLAYER_XP_UPDATE",
		"PLAYER_LEVEL_UP",
		"UPDATE_EXHAUSTION",
		"PLAYER_UPDATE_RESTING",
		"ENABLE_XP_GAIN",
		"DISABLE_XP_GAIN",
		"HONOR_XP_UPDATE",
		"HONOR_LEVEL_UPDATE",
		"UPDATE_FACTION",
		"ZONE_CHANGED",
		"ZONE_CHANGED_NEW_AREA",
		"UPDATE_EXPANSION_LEVEL",
		"UNIT_ENTERED_VEHICLE",
		"UNIT_EXITED_VEHICLE",
        "CHAT_MSG_COMBAT_FACTION_CHANGE"
	}

	for _, event in next, RENOWN_EVENTS do
		table.insert(events, event)
	end
	
	RefineUI:OnEvents(events, function() self:OnEvent() end, "ExperienceBar:Update")
	
	-- Hook for watching preference changes
	RefineUI:HookOnce("ExperienceBar:SetWatchingHonorAsXP", "SetWatchingHonorAsXP", function() self:OnEvent() end)
	if SetWatchedFactionIndex then
		RefineUI:HookOnce("ExperienceBar:SetWatchedFactionIndex", "SetWatchedFactionIndex", function() self:OnEvent() end)
	end
	if C_Reputation and C_Reputation.SetWatchedFactionByID then
		RefineUI:HookOnce("ExperienceBar:C_Reputation:SetWatchedFactionByID", C_Reputation, "SetWatchedFactionByID", function() self:OnEvent() end)
	end
end

function ExperienceBar:OnEnable()

	-- Check new config data bars structure
	-- Check new config data bars structure
	local config = RefineUI.Config.UnitFrames and RefineUI.Config.UnitFrames.DataBars and RefineUI.Config.UnitFrames.DataBars.ExperienceBar
	if not config then return end

	-- Migration: Handle old boolean config
	if type(config) ~= "table" then
		config = {
			Enable = config,
		}
		RefineUI.Config.UnitFrames.DataBars.ExperienceBar = config
	end

	if not config.Enable then return end
	self.db = config
    if self.db.SubMaxTrackMode ~= "EXPERIENCE" and self.db.SubMaxTrackMode ~= "REPUTATION" then
        self.db.SubMaxTrackMode = "EXPERIENCE"
    end
    self.db.Scale = ClampScale(self.db.Scale)
    if self.db.Mouseover == nil then
        self.db.Mouseover = false
    end
    self.db.Alpha = ClampAlpha(self.db.Alpha, DEFAULT_IDLE_ALPHA)
    if self.db.Position then
        if not RefineUI.Positions[FRAME_NAME] then
            RefineUI:SetPosition(FRAME_NAME, self.db.Position)
        end
        self.db.Position = nil
    end

	self:CreateBar()
	self:RegisterEvents()
	self:OnEvent() -- Initial update

    -- Disable Default XP Bar
    if _G.MainStatusTrackingBarContainer then
        if RefineUI.AddAPI then RefineUI.AddAPI(_G.MainStatusTrackingBarContainer) end
        RefineUI.Kill(_G.MainStatusTrackingBarContainer)
    end
end
