local R, C, L = unpack(RefineUI)
if C.automation.autoZoneTrack ~= true then return end

----------------------------------------------------------------------------------------
--	Auto Track Quests by Zone (based on Zoned Quests by zestyquarks)
----------------------------------------------------------------------------------------

-----------------------------------------------------------------------------
--	Blizz API Localization
-----------------------------------------------------------------------------
local C_QuestLog = _G.C_QuestLog
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GameTooltip = _G.GameTooltip
local GetQuestID = _G.GetQuestID
local GetTime = _G.GetTime

-- Quest Log API
local C_QuestLogGetInfo = C_QuestLog.GetInfo
local C_QuestLogIsWorldQuest = C_QuestLog.IsWorldQuest
local C_QuestLogAddQuestWatch = C_QuestLog.AddQuestWatch
local C_QuestLogRemoveQuestWatch = C_QuestLog.RemoveQuestWatch
local C_QuestLogGetNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local C_QuestLogGetQuestWatchType = C_QuestLog.GetQuestWatchType

-- Timer API
local C_TimerNewTimer = C_Timer.NewTimer
local wipe = _G.wipe

-----------------------------------------------------------------------------
--	Constants
-----------------------------------------------------------------------------
local UPDATE_DELAY = 0.5            -- Single delay for all updates
local CHECKBOX_OFFSET_X = -20       -- Checkbox X position offset
local CHECKBOX_OFFSET_Y = -4        -- Checkbox Y position offset
local CACHE_DURATION = 2.0          -- How long to cache quest data

-- Colors following RefineUI conventions
local COLOR_SUCCESS = "|cFFFFD200"  -- Yellow
local COLOR_RESET = "|r"

-----------------------------------------------------------------------------
--	Core Variables and Database
-----------------------------------------------------------------------------
local questDB -- Database reference for quest tracking persistence
local pendingTimer, needsUpdate -- Debounced update system
local questCache = {} -- Cache for quest data to reduce API calls
local lastCacheUpdate = 0 -- Timestamp of last cache update

-----------------------------------------------------------------------------
--	Utility Functions
-----------------------------------------------------------------------------

-- REFACTOR: The caching function now also stores the watched status of each quest.
-- This is a key performance improvement, as it prevents repeated API calls to
-- C_QuestLogGetQuestWatchType() inside the main tracking loop.
local function getCachedQuestData()
	local currentTime = GetTime()
	if currentTime - lastCacheUpdate < CACHE_DURATION then
		return questCache
	end
	
	-- Update cache
	wipe(questCache)
	local numQuests = C_QuestLogGetNumQuestLogEntries()
	
	for i = 1, numQuests do
		local questInfo = C_QuestLogGetInfo(i)
		if questInfo and questInfo.questID then
			-- Also cache the watched status to avoid API calls in the loop
			questInfo.isWatched = C_QuestLogGetQuestWatchType(questInfo.questID) ~= nil
			questCache[questInfo.questID] = questInfo
		end
	end
	
	lastCacheUpdate = currentTime
	return questCache
end

-----------------------------------------------------------------------------
--	Quest Database Hooks
-----------------------------------------------------------------------------
local hooksecurefunc = _G.hooksecurefunc

-- Common hook pattern to reduce duplication
local function createQuestHook(action)
	return function(questID, _, isComplete)
		if questDB and not isComplete then
			action(questID)
		end
	end
end

-- Track when quests are manually watched/unwatched to remember user preferences
hooksecurefunc(C_QuestLog, "AddQuestWatch", createQuestHook(function(questID)
	questDB[questID] = true
end))

hooksecurefunc(C_QuestLog, "RemoveQuestWatch", createQuestHook(function(questID)
	questDB[questID] = nil
end))

hooksecurefunc("CompleteQuest", function()
	local questID = GetQuestID()
	if questDB and questID then
		questDB[questID] = nil
	end
end)

-----------------------------------------------------------------------------
--	UI Components
-----------------------------------------------------------------------------
local autoTrackCheckbox

local function createAutoTrackCheckbox()
	local trackerFrame = _G.ObjectiveTrackerFrame
	if not trackerFrame then return nil end
	
	local checkbox = CreateFrame("CheckButton", "RefineUI_AutoTrackCheckbox", trackerFrame, "ChatConfigCheckButtonTemplate")
	checkbox:SetPoint("TOPRIGHT", trackerFrame, "TOPRIGHT", CHECKBOX_OFFSET_X, CHECKBOX_OFFSET_Y)
	checkbox:SetChecked(C.automation.autoZoneTrack)
	checkbox:SetHitRectInsets(0, 0, 0, 0)

	-- Tooltip handlers
	checkbox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Enable or disable auto tracking of quests based on your current zone.")
		GameTooltip:Show()
	end)

	checkbox:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Click handler
	checkbox:SetScript("OnClick", function(self)
		local isChecked = self:GetChecked()
		C.automation.autoZoneTrack = isChecked
		local statusText = isChecked and "Enabled" or "Disabled"
		print(COLOR_SUCCESS .. "Auto Track Quests by Zone:" .. COLOR_RESET .. " " .. statusText)
		
		-- Trigger an update immediately after changing the setting
		scheduleUpdate()
	end)

	return checkbox
end

-- Simple UI initialization
local function initializeUI()
	if not autoTrackCheckbox then
		autoTrackCheckbox = createAutoTrackCheckbox()
	end
end

-----------------------------------------------------------------------------
--	Core Quest Tracking Logic
-----------------------------------------------------------------------------
local function initializeQuestDB()
	if not questDB then
		-- This assumes ZonedQuestsDB is the intended global saved variable table
		ZonedQuestsDB = ZonedQuestsDB or {}
		questDB = ZonedQuestsDB
	end
end

local function shouldTrackQuest(questInfo, questID)
	-- Early returns for better performance
	if not questInfo or questInfo.isHidden or questInfo.isHeader or C_QuestLogIsWorldQuest(questID) then
		return false
	end
	
	-- Check if quest should be tracked based on zone/map status or user preference
	return questInfo.isOnMap or questDB[questID]
end

local function runQuestTracking()
	-- Early exit conditions
	if not C.automation.autoZoneTrack or InCombatLockdown() then
		return
	end

	initializeQuestDB()

	local cachedQuests = getCachedQuestData()
	
	for questID, questInfo in pairs(cachedQuests) do
		local shouldTrack = shouldTrackQuest(questInfo, questID)
		
		-- REFACTOR (KISS): Simplified logic. We only care if the current state
		-- (isWatched) is different from the desired state (shouldTrack).
		if shouldTrack ~= questInfo.isWatched then
			if shouldTrack then
				C_QuestLogAddQuestWatch(questID)
			else
				C_QuestLogRemoveQuestWatch(questID)
			end
		end
	end
	
	-- REFACTOR (YAGNI): The 'needsUpdate' flag is now the sole indicator of work state.
	-- The `changed` variable was unused and has been removed.
	needsUpdate = false
end

-----------------------------------------------------------------------------
--	Timer and Update Management
-----------------------------------------------------------------------------
local function scheduleUpdate()
	needsUpdate = true
	if pendingTimer then 
		return -- Timer already pending
	end
	
	pendingTimer = C_TimerNewTimer(UPDATE_DELAY, function()
		pendingTimer = nil
		-- No need to check InCombatLockdown here, runQuestTracking already does it
		if needsUpdate then
			runQuestTracking()
		end
	end)
end

-----------------------------------------------------------------------------
--	Event System
-----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

-- Register essential events only
local events = {
	"QUEST_ACCEPTED",
	"AREA_POIS_UPDATED", 
	"PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_ENABLED"
}

for _, event in ipairs(events) do
	eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Initialize UI when entering world
		C_Timer.After(0.5, initializeUI)
	end
	
	-- Schedule quest update for all relevant events
	scheduleUpdate()
end)