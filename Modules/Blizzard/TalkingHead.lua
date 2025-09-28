local R, C, L = unpack(RefineUI)

-----------------------------------------------------------------------------------------
--	Talking Head: hide or reposition safely (handles on-demand loading)
-----------------------------------------------------------------------------------------

local function ConfigureTalkingHead()
	-- Ensure the Blizzard Talking Head UI exists before configuring
	local frame = rawget(_G, "TalkingHeadFrame")
	if not frame then
		return
	end

	-- Prevent the position manager from moving it around
	frame.ignoreFramePositionManager = true

	-- If user wants it hidden, hide on play and bail
	if C.general.hideTalkingHead == true then
		if not frame._refineui_hide_hooked then
			frame._refineui_hide_hooked = true
			hooksecurefunc(frame, "PlayCurrent", function()
				frame:Hide()
			end)
		end
		-- Hide immediately in case it's already visible
		frame:Hide()
		return
	end

	-- Anchor to configured position
	frame:ClearAllPoints()
	frame:SetPoint(unpack(C.position.talkingHead))

	-- Keep it anchored if something else tries to move it
	if not frame._refineui_setpoint_hooked then
		frame._refineui_setpoint_hooked = true
		hooksecurefunc(frame, "SetPoint", function(self)
			self:ClearAllPoints()
			self:SetPoint(unpack(C.position.talkingHead))
		end)
	end
end

-- Try to configure immediately (in case the UI is already loaded)
ConfigureTalkingHead()

-- Also configure on login and when the Blizzard UI loads on demand
local Loader = CreateFrame("Frame")
Loader:RegisterEvent("PLAYER_ENTERING_WORLD")
Loader:RegisterEvent("ADDON_LOADED")
Loader:SetScript("OnEvent", function(self, event, addonName)
	if event == "ADDON_LOADED" and addonName ~= "Blizzard_TalkingHeadUI" then
		return
	end
	ConfigureTalkingHead()
end)