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
local GameTooltip = GameTooltip
local BreakUpLargeNumbers = BreakUpLargeNumbers

-- Locals
local Mult = 2.5
local CurrentType = "experience"

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

function ExperienceBar:CreateBar()
	local Bar = CreateFrame("StatusBar", "RefineUI_ExperienceBar", _G.UIParent)
    
    -- Strict API: Size and Point
	RefineUI.Size(Bar, 294, 30)
	
    -- Position Priority: Central Config > DB Saved > Default
    local pos = RefineUI.Positions.RefineUI_ExperienceBar or (self.db and self.db.Position) or { "TOP", "UIParent", "TOP", 0, -12 }
    
    -- Handle string relativeTo
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    if type(relativeTo) == "string" then
        relativeTo = _G[relativeTo] or _G.UIParent
    end
	RefineUI.Point(Bar, point, relativeTo, relativePoint, x, y)

	Bar.editModeName = "Experience Bar"
	if LibEditMode then
		LibEditMode:AddFrame(Bar, function(frame, layout, point, x, y)
			if not self.db then return end
			self.db.Position = { point, "UIParent", point, x, y }
		end, { point = point, x = x, y = y })
	end
    
	Bar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
	Bar:SetStatusBarColor(unpack(Colors.experience))
    
	-- Strict API: CreateBackdrop/Shadow
	RefineUI.CreateBackdrop(Bar) -- Should default to 'Default' template logic
    
    if Bar.bg and Bar.bg.border then
        Bar.bg.border:SetFrameLevel(Bar:GetFrameLevel() + 1)
    end
    
	Bar:SetScript("OnEnter", function(self) ExperienceBar:OnEnter(self) end)
	Bar:SetScript("OnLeave", function(self) ExperienceBar:OnLeave(self) end)
	Bar:SetAlpha(0.25)

	local BarRested = CreateFrame("StatusBar", nil, Bar)
	RefineUI.Size(BarRested, 171, 8)
	RefineUI.SetInside(BarRested)
	BarRested:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
	BarRested:SetStatusBarColor(unpack(Colors.rested))
	BarRested:SetFrameLevel(Bar:GetFrameLevel() - 1)
	BarRested:Hide()

	local InvisFrame = CreateFrame("Frame", nil, Bar)
	InvisFrame:SetFrameLevel(Bar:GetFrameLevel() + 10)
	RefineUI.SetInside(InvisFrame)

	local Text = InvisFrame:CreateFontString(nil, "OVERLAY")
	RefineUI.Point(Text, "CENTER", Bar, 0, 6)
    
    -- Strict API: Font
	RefineUI.Font(Text, 16) -- Defaults to RefineUI.Media.Fonts.Default
    
    -- Context Menu
    local MenuUtil = MenuUtil
    Bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                rootDescription:CreateTitle("Experience Bar")

                -- Auto-Track Settings
                local autoTrackName = "Auto-Track"
                if ExperienceBar.db.AutoTrack == "RECENT" then autoTrackName = autoTrackName .. " (Recent)"
                elseif ExperienceBar.db.AutoTrack == "CLOSEST" then autoTrackName = autoTrackName .. " (Closest)"
                else autoTrackName = autoTrackName .. " (None)" 
                end
                
                local autoTrackMenu = rootDescription:CreateButton(autoTrackName)
                
                autoTrackMenu:CreateRadio("Closest (Default)", function() return ExperienceBar.db.AutoTrack == "CLOSEST" end, function()
                    ExperienceBar.db.AutoTrack = "CLOSEST"
                    RefineUI:Print("Auto-Track: Closest")
                    ExperienceBar:OnEvent()
                end)
                
                autoTrackMenu:CreateRadio("Recent", function() return ExperienceBar.db.AutoTrack == "RECENT" end, function()
                    ExperienceBar.db.AutoTrack = "RECENT"
                    RefineUI:Print("Auto-Track: Recent")
                    ExperienceBar:OnEvent()
                end)
                
                autoTrackMenu:CreateRadio("None", function() return ExperienceBar.db.AutoTrack == "NONE" end, function()
                    ExperienceBar.db.AutoTrack = "NONE"
                    RefineUI:Print("Auto-Track: None")
                    ExperienceBar:OnEvent()
                end)
                
                rootDescription:CreateDivider()
                
                -- Icon Mappings
                local TWW_ICONS_PATH = "Interface\\MajorFactions\\TheWarWithinMajorFactionsIcons\\"
                local DF_ICONS_PATH = "Interface\\MajorFactions\\MajorFactionsIcons\\"
                local MN_ICONS_PATH = "Interface\\MajorFactions\\MidnightMajorFactionsIcons\\"
                
                local FactionIcons = {
                    -- Midnight (Placeholders)
                    [9991] = MN_ICONS_PATH .. "majorfactions_icons_amanitribe512",
                    [9992] = MN_ICONS_PATH .. "majorfactions_icons_haratitribe512",
                    [9993] = MN_ICONS_PATH .. "majorfactions_icons_shadowstepcadre512",
                    [9994] = MN_ICONS_PATH .. "majorfactions_icons_silvermooncourt512",
                
                    -- The War Within
                    [2590] = TWW_ICONS_PATH .. "majorfactions_icons_storm512",  -- Council of Dornogal
                    [2594] = TWW_ICONS_PATH .. "majorfactions_icons_candle512", -- Assembly of the Deeps
                    [2570] = TWW_ICONS_PATH .. "majorfactions_icons_flame512",  -- Hallowfall Arathi
                    [2600] = TWW_ICONS_PATH .. "majorfactions_icons_web512",    -- Severed Threads
                    
                    -- Dragonflight
                    [2507] = DF_ICONS_PATH .. "MajorFactions_Icons_Expedition512", -- Dragonscale
                    [2510] = DF_ICONS_PATH .. "MajorFactions_Icons_Centaur512",    -- Maruuk
                    [2511] = DF_ICONS_PATH .. "MajorFactions_Icons_Tuskarr512",    -- Iskaara
                    [2503] = DF_ICONS_PATH .. "MajorFactions_Icons_Valdrakken512", -- Valdrakken
                    [2564] = DF_ICONS_PATH .. "MajorFactions_Icons_Niffen512",     -- Loamm Niffen
                    [2574] = DF_ICONS_PATH .. "MajorFactions_Icons_Dream512",      -- Dream Wardens
                }

                -- Expansion Submenus
                -- Expansion Submenus
                local function AddFactionMenu(parent, factionID, knownName)
                     local data = C_MajorFactions.GetMajorFactionData(factionID)

                     -- Fallback for placeholder/unknown IDs
                     local name = data and data.name or knownName or "Unknown Faction"
                     local level = data and data.renownLevel or 0
                     local text = string.format("%s (Lvl %d)", name, level)
                     
                     -- Prepend Icon if available (Inline Texture)
                     local iconPath = FactionIcons[factionID]
                     if iconPath then
                         text = string.format("|T%s:18:18:0:0|t  %s", iconPath, text)
                     end

                     local isMaxed = data and C_MajorFactions.HasMaximumRenown(factionID)
                     if isMaxed then
                         text = "|cff808080" .. text .. " (Maxed)|r"
                     end

                     parent:CreateRadio(text, function()
                        local watched = C_Reputation.GetWatchedFactionData()
                        return watched and watched.factionID == factionID
                     end, function()
                         if isMaxed then return end -- Disable selection
                         
                         if not data then 
                            RefineUI:Print("Faction ID " .. factionID .. " not found. Please update ExperienceBar.lua with correct ID.")
                            return 
                         end
                         C_Reputation.SetWatchedFactionByID(factionID)
                         RefineUI:Print("Watching: " .. name)
                         ExperienceBar:OnEvent()
                     end)
                end
                
                -- Status / Clear Manual
                local currentWatched = C_Reputation.GetWatchedFactionData()
                if currentWatched then
                    rootDescription:CreateButton("|cffFF0000Stop Tracking|r " .. (currentWatched.name or ""), function()
                        C_Reputation.SetWatchedFactionByID(0) -- Clear watch
                        RefineUI:Print("Manual tracking cleared. Auto-Track resumed.")
                        ExperienceBar:OnEvent()
                    end)
                    rootDescription:CreateDivider()
                end
                
                -- Midnight (12.0)
                local mnMenu = rootDescription:CreateButton("Midnight")
                AddFactionMenu(mnMenu, 9991, "Amani Tribe")
                AddFactionMenu(mnMenu, 9992, "Harati Tribe")
                AddFactionMenu(mnMenu, 9993, "Shadowstep Cadre")
                AddFactionMenu(mnMenu, 9994, "Silvermoon Court")
                
                -- The War Within (11.0)
                local twwMenu = rootDescription:CreateButton("The War Within")
                AddFactionMenu(twwMenu, 2590) -- Council of Dornogal
                AddFactionMenu(twwMenu, 2594) -- The Assembly of the Deeps
                AddFactionMenu(twwMenu, 2570) -- Hallowfall Arathi
                AddFactionMenu(twwMenu, 2600) -- The Severed Threads

                -- Dragonflight
                local dfMenu = rootDescription:CreateButton("Dragonflight")
                AddFactionMenu(dfMenu, 2507) -- Dragonscale Expedition
                AddFactionMenu(dfMenu, 2510) -- Maruuk Centaur
                AddFactionMenu(dfMenu, 2511) -- Iskaara Tuskarr
                AddFactionMenu(dfMenu, 2503) -- Valdrakken Accord
                AddFactionMenu(dfMenu, 2564) -- Loamm Niffen
                AddFactionMenu(dfMenu, 2574) -- Dream Wardens
                
            end)
        end
    end)

	self.Bar = Bar
	self.BarRested = BarRested
	self.Text = Text
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
                return rCur, rMax, rPerc, 0, 0, majorFactionData.renownLevel, "renown", majorFactionData.name or name
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
			return cur, maxVal, perc, 0, 0, "Paragon", "reputation", name
		end
	end

	-- Standard reputation
	local standingText = _G['FACTION_STANDING_LABEL' .. reaction] or tostring(reaction)
	return cur, maxVal, perc, 0, 0, standingText, "reputation", name
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

-- The War Within (10) and Dragonflight (9) Major Factions
-- It's safer to check these explicitly if GetMajorFactionList isn't available
local WAR_WITHIN_FACTIONS = {
    2590, -- Council of Dornogal
    2594, -- The Assembly of the Deeps
    2570, -- Hallowfall Arathi
    2600, -- The Severed Threads
    -- Dragonflight IDs (optional, kept for completeness if user is playing current exp)
    2507, -- Dragonscale Expedition
    2510, -- Maruuk Centaur
    2511, -- Iskaara Tuskarr
    2503, -- Valdrakken Accord
    2564, -- Loamm Niffen
    2574, -- Dream Wardens
}

local function GetClosestFaction()
    local currentExpansionID = GetExpansionLevel()
    local bestData = nil
    local bestPerc = -1

    for _, factionID in ipairs(WAR_WITHIN_FACTIONS) do
        local isMax = C_MajorFactions.HasMaximumRenown(factionID)
        local isParagon = C_Reputation.IsFactionParagon(factionID)
        
        if not isMax or isParagon then
            local data = C_MajorFactions.GetMajorFactionData(factionID)
            local valid = false
            local perc = 0
            
            if isMax and isParagon then
                 local currentValue, threshold = C_Reputation.GetFactionParagonInfo(factionID)
                 if currentValue and threshold and threshold > 0 then
                     perc = (currentValue % threshold) / threshold
                     valid = true
                 end
            elseif data and data.expansionID == currentExpansionID and data.isUnlocked then
                 local rCur = data.renownReputationEarned or 0
                 local rMax = data.renownLevelThreshold or 1
                 if rMax > 0 then
                     perc = rCur / rMax
                     valid = true
                 end
            end
            
            if valid and perc > bestPerc then
                bestPerc = perc
                bestData = data
            end
        end
    end
    
    return bestData
end

local function GetRecentFaction()
    if not LastGainedFactionID then return nil end
    return C_Reputation.GetFactionDataByID(LastGainedFactionID)
end

function ExperienceBar:GetValues()
	local pLevel = UnitLevel('player')
	local maxLevel = GetMaxLevelForPlayerExpansion()
	local maxPlayerLevel = _G.MAX_PLAYER_LEVEL or 0
	if maxLevel == 0 and maxPlayerLevel > 0 then maxLevel = maxPlayerLevel end
	local pIsMaxLevel = pLevel >= maxLevel
	
	-- 1. Check for faction explicitly watched via "Show as Experience Bar"
	local watchedFactionData = C_Reputation.GetWatchedFactionData()
	if not watchedFactionData then 
		watchedFactionData = GetWatchedFactionData_Fallback() 
	end

    -- AutoTrack Override if nothing explicitly watched
    if not watchedFactionData and self.db and self.db.AutoTrack then
        if self.db.AutoTrack == "RECENT" then
            watchedFactionData = GetRecentFaction()
        elseif self.db.AutoTrack == "CLOSEST" then
            watchedFactionData = GetClosestFaction()
        end
    end
	
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
		return cur, maxVal, perc, 0, 0, level, "honor", nil
	end

	-- 3. Default to Experience (if not max level)
	if not pIsMaxLevel then
		local cur, maxVal = UnitXP('player'), UnitXPMax('player')
		if maxVal <= 0 then maxVal = 1 end
		local rested = GetXPExhaustion() or 0
		local perc = floor(cur / maxVal * 100 + 0.5)
		local restedPerc = floor(rested / maxVal * 100 + 0.5)
		return cur, maxVal, perc, rested, restedPerc, pLevel, "experience", nil
	end

	-- 4. Fallback: At max level, display watched faction data
	if pIsMaxLevel and watchedFactionData then
		local result = {ProcessFactionData(watchedFactionData)}
		if result[1] then return unpack(result) end
	end

	return 0, 1, 0, 0, 0, pLevel, "none", nil
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
    
    -- Strict API: Use RefineUI:FadeIn() helper
	RefineUI:FadeIn(frame, 0.2, 1)
end

function ExperienceBar:OnLeave(frame)
	GameTooltip:Hide()
    
    -- Strict API: Use RefineUI:FadeOut() helper
	RefineUI:FadeOut(frame, 0.5, 0.25)
end

function ExperienceBar:OnEvent(event, arg1)
    if event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        local factionName = arg1:match(FACTION_STANDING_INCREASED:gsub("%%s", "(.*)"):gsub("%%d", ".*")) or
                            arg1:match(FACTION_STANDING_DECREASED:gsub("%%s", "(.*)"):gsub("%%d", ".*"))
        if factionName then
             -- We have a name, but need ID. Iterate to find it.
             local numFactions = C_Reputation.GetNumFactions()
             local currentExpansionID = GetExpansionLevel()
             for i=1, numFactions do
                 local data = C_Reputation.GetFactionDataByIndex(i)
                 if data and data.name == factionName then
                     -- Check if Major Faction and Current Exp
                     local majorData = C_MajorFactions.GetMajorFactionData(data.factionID)
                     if majorData and majorData.expansionID == currentExpansionID then
                        LastGainedFactionID = data.factionID
                        if self.db.AutoTrack == "RECENT" then self:OnEvent() end -- Force update
                     end
                     return
                 end
             end
        end
        return
    end

	local cur, maxVal, perc, rested, restedPerc, level, barType, name = self:GetValues()
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
		self.Bar:Show()
	else
		self.Bar:Hide()
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
	if C_Reputation and C_Reputation.SetWatchedFaction then
		RefineUI:HookOnce("ExperienceBar:C_Reputation:SetWatchedFaction", C_Reputation, "SetWatchedFaction", function() self:OnEvent() end)
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
			Position = { "TOP", "UIParent", "TOP", 0, -12 }
		}
		RefineUI.Config.UnitFrames.DataBars.ExperienceBar = config
	end

	if not config.Enable then return end
	self.db = config

	self:CreateBar()
	self:RegisterEvents()
	self:OnEvent() -- Initial update

    -- Disable Default XP Bar
    if _G.MainStatusTrackingBarContainer then
        if RefineUI.AddAPI then RefineUI.AddAPI(_G.MainStatusTrackingBarContainer) end
        RefineUI.Kill(_G.MainStatusTrackingBarContainer)
    end
end
