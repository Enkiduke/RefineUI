local R, C, L = unpack(RefineUI)

-- Suppress Guild Achievement toasts reliably without impacting personal achievements
-- Prefer removing/ignoring the GuildAchievementAlertSystem instead of muting sounds or
-- unregistering broad events that affect other systems.

local _ruiGuildAchieveInitialized = false
local _ruiGuildAchieveTicker      = nil
local _ruiOriginalGasAddAlert     = nil

local function RemoveGuildAchievementSubsystem()
	local af  = rawget(_G, "AlertFrame")
	local gas = rawget(_G, "GuildAchievementAlertSystem")
	if not af or not gas or not af.alertFrameSubSystems then return false end

	local removed = false
	for i = #af.alertFrameSubSystems, 1, -1 do
		if af.alertFrameSubSystems[i] == gas then
			table.remove(af.alertFrameSubSystems, i)
			removed = true
		end
	end
	if removed and af.UpdateAnchors then af:UpdateAnchors() end
	return removed
end

local function SuppressGuildAchievementAlerts()
	if _ruiGuildAchieveInitialized then return end
	_ruiGuildAchieveInitialized = true

	-- 1) Proactively remove the subsystem if already present
	local removed = RemoveGuildAchievementSubsystem()

	-- 2) Prevent it from being re-added later
	if AlertFrame and AlertFrame.AddAlertFrameSubSystem and not AlertFrame.__ruiGuildAchieveHooked then
		AlertFrame.__ruiGuildAchieveHooked = true
		hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, subsystem)
			local gas = rawget(_G, "GuildAchievementAlertSystem")
			if subsystem == gas then
				RemoveGuildAchievementSubsystem()
			end
		end)
	end

	-- 3) Fallback: if subsystem API changes across clients, disable via the specific event
	--    (no impact to personal achievements).
	if AlertFrame and AlertFrame.UnregisterEvent then
		AlertFrame:UnregisterEvent("GUILD_ACHIEVEMENT_EARNED")
	end

	-- 4) Ultimate fallback: if the subsystem exists but cannot be removed (unlikely),
	-- replace its AddAlert with a no-op to prevent any guild achievement toasts or sounds.
	local gas = rawget(_G, "GuildAchievementAlertSystem")
	if gas and gas.AddAlert and not gas.__ruiSuppressed then
		gas.__ruiSuppressed   = true
		_ruiOriginalGasAddAlert = gas.AddAlert
		gas.AddAlert = function() end
	end
end

-- Robust, low-cost initialization:
-- 1) Try at PLAYER_LOGIN; 2) If not ready, tick a few times until AlertFrame/GAS exist.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
	if AlertFrame and rawget(_G, "GuildAchievementAlertSystem") then
		SuppressGuildAchievementAlerts()
		self:UnregisterEvent("PLAYER_LOGIN")
		return
	end
	-- bounded retry: ~2s total worst-case (10 * 0.2s)
	local tries = 0
	_ruiGuildAchieveTicker = C_Timer.NewTicker(0.2, function(t)
		if AlertFrame and rawget(_G, "GuildAchievementAlertSystem") then
			SuppressGuildAchievementAlerts()
			t:Cancel()
			_ruiGuildAchieveTicker = nil
			initFrame:UnregisterEvent("PLAYER_LOGIN")
		else
			tries = tries + 1
			if tries >= 10 then
				t:Cancel()
				_ruiGuildAchieveTicker = nil
				initFrame:UnregisterEvent("PLAYER_LOGIN")
			end
		end
	end)
end)