local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
-- Local functions
----------------------------------------------------------------------------------------
local function GetZoneColor()
	local pvpType = C_PvP.GetZonePVPInfo()
	if pvpType == "sanctuary" then
		return 0.41, 0.8, 0.94
	elseif pvpType == "arena" then
		return 1.0, 0.1, 0.1
	elseif pvpType == "friendly" then
		return 0.1, 1.0, 0.1
	elseif pvpType == "hostile" then
		return 1.0, 0.1, 0.1
	elseif pvpType == "contested" then
		return 1.0, 0.7, 0.0
	elseif pvpType == "combat" then
		return 1.0, 0.1, 0.1
	else
		return 1.0, 0.9294, 0.7607
	end
end

local function FadeOutWhoClicked(whoClickedText)
	UIFrameFadeOut(whoClickedText, 1, whoClickedText:GetAlpha(), 0)
end

----------------------------------------------------------------------------------------
--	Minimap border
----------------------------------------------------------------------------------------
-- local MinimapAnchor = CreateFrame("Frame", "MinimapAnchor", UIParent)
-- MinimapAnchor:CreatePanel("Default", C.minimap.size, C.minimap.size, unpack(C.position.minimap))

-- Disable Minimap Cluster
MinimapCluster:EnableMouse(false)
MinimapCluster:SetTemplate("Default")

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
	self:UnregisterEvent(event)

    -- Set Minimap size
    MinimapCluster:SetSize(C.minimap.size, C.minimap.size)
    Minimap:SetSize(C.minimap.size, C.minimap.size)
    Minimap:SetAllPoints(MinimapCluster)

    -- Rest of the code...
    MinimapCluster.Selection:SetSize(C.minimap.size, C.minimap.size)

    -- Hook into Minimap's OnSizeChanged
    MinimapCluster:HookScript("OnSizeChanged", function(self, width, height)
        if width ~= C.minimap.size or height ~= C.minimap.size then
            self:SetSize(C.minimap.size, C.minimap.size)
        end
    end)

	-- Instance Difficulty icon
	MinimapCluster.InstanceDifficulty:SetParent(Minimap)
	MinimapCluster.InstanceDifficulty:ClearAllPoints()
	MinimapCluster.InstanceDifficulty:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
	MinimapCluster.InstanceDifficulty.Default.Border:Hide()
	MinimapCluster.InstanceDifficulty.Default.Background:SetSize(36, 36)
	MinimapCluster.InstanceDifficulty.Default.Background:SetVertexColor(0.6, 0.3, 0)

	-- Guild Instance Difficulty icon
	MinimapCluster.InstanceDifficulty.Guild.Border:Hide()
	MinimapCluster.InstanceDifficulty.Guild.Background:SetSize(36, 36)
	MinimapCluster.InstanceDifficulty.Guild.Background:ClearAllPoints()
	MinimapCluster.InstanceDifficulty.Guild.Background:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)

	-- Challenge Mode icon
	MinimapCluster.InstanceDifficulty.ChallengeMode.Border:Hide()
	MinimapCluster.InstanceDifficulty.ChallengeMode.Background:SetSize(36, 36)
	MinimapCluster.InstanceDifficulty.ChallengeMode.Background:SetVertexColor(0.8, 0.8, 0)
	MinimapCluster.InstanceDifficulty.ChallengeMode.Background:ClearAllPoints()
	MinimapCluster.InstanceDifficulty.ChallengeMode.Background:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)

	-- Move QueueStatus icon
	QueueStatusFrame:SetClampedToScreen(true)
	QueueStatusFrame:SetFrameStrata("TOOLTIP")
	QueueStatusButton:ClearAllPoints()
	QueueStatusButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 0)
	QueueStatusButton:SetParent(Minimap)
	QueueStatusButton:SetScale(0.75)

	hooksecurefunc(QueueStatusButton, "SetPoint", function(self, _, anchor)
		if anchor ~= Minimap then
			self:ClearAllPoints()
			self:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 0)
		end
	end)

	hooksecurefunc(QueueStatusButton, "SetScale", function(self, scale)
		if scale ~= 0.75 then
			self:SetScale(0.75)
		end
	end)

	-- Invites icon
	local InviteTexture = GameTimeCalendarInvitesTexture
	InviteTexture:ClearAllPoints()
	InviteTexture:SetParent(Minimap)
	InviteTexture:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -1, -4)
	GameTimeFrame:Hide()

	-- Create button to show invite tooltip and allow open calendar
	local button = CreateFrame("Button", nil, Minimap)
	button:SetAllPoints(InviteTexture)
	if not GameTimeCalendarInvitesTexture:IsShown() then
		button:Hide()
	end

	button:SetScript("OnEnter", function()
		if InCombatLockdown() then return end
		if InviteTexture:IsShown() then
			GameTooltip:SetOwner(button, "ANCHOR_LEFT")
			GameTooltip:AddLine(GAMETIME_TOOLTIP_CALENDAR_INVITES)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(GAMETIME_TOOLTIP_TOGGLE_CALENDAR)
			GameTooltip:Show()
		end
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	button:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		if InviteTexture:IsShown() then
			ToggleCalendar()
		end
	end)

	hooksecurefunc(InviteTexture, "Show", function()
		button:Show()
	end)

	hooksecurefunc(InviteTexture, "Hide", function()
		button:Hide()
	end)

	-- Move Mail icon
	local MailFrame = MinimapCluster.IndicatorFrame.MailFrame
	hooksecurefunc(MailFrame, "SetPoint", function(self, _, anchor)
		if anchor ~= Minimap then
			self:ClearAllPoints()
			self:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -2, 4)
		end
	end)
	-- Use the default mailbox texture; remove legacy path override
	MiniMapMailIcon:SetSize(20, 18)

	-- Move crafting order icon
	local Crafting = MinimapCluster.IndicatorFrame.CraftingOrderFrame
	hooksecurefunc(Crafting, "SetPoint", function(self, _, anchor)
		if anchor ~= Minimap then
			self:ClearAllPoints()
			self:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 4)
		end
	end)
end)

-- Adjusting for patch 9.0.1 Minimap.xml
Minimap:SetFrameStrata("LOW")
Minimap:SetFrameLevel(2)

-- Hide Border
MinimapCompassTexture:Hide()
MinimapCluster.BorderTop:StripTextures()

-- Hide Zoom Buttons
    local zoomInBtn = rawget(Minimap, 'ZoomIn')
    if zoomInBtn and zoomInBtn.Kill then zoomInBtn:Kill() end
    local zoomOutBtn = rawget(Minimap, 'ZoomOut')
    if zoomOutBtn and zoomOutBtn.Kill then zoomOutBtn:Kill() end

-- Set up the addon's frame
if C.minimap.zoomReset then
	local resetZoom = CreateFrame("Frame")
	local resetting = 0
	Minimap:SetZoom(0)
	resetZoom:RegisterEvent("MINIMAP_UPDATE_ZOOM")
	resetZoom:RegisterEvent("PLAYER_ENTERING_WORLD")
	resetZoom:SetScript("OnEvent", function(self, event)
		if Minimap:GetZoom() > 0 then
			if event == "PLAYER_ENTERING_WORLD" then
				Minimap:SetZoom(0)
			elseif resetting == 0 then
				resetting = 1
				C_Timer.After(C.minimap.resetTime, function()
					Minimap:SetZoom(0)
					resetting = 0
				end)
			end
		end
	end)
end

-- Hide Blob Ring
Minimap:SetArchBlobRingScalar(0)
Minimap:SetQuestBlobRingScalar(0)

-- Hide Zone Frame
MinimapCluster.ZoneTextButton:Hide()

-- --  Frames need a position and size set in order to be visible (Size can also be set using multiple anchor points)
-- local zoneTextFrame=CreateFrame("Frame", "MinimapZoneText", Minimap);--    Our frame
-- zoneTextFrame:SetPoint("TOP", Minimap, "TOP", 0, -10)
-- zoneTextFrame:SetSize(1,1);

-- --  FontStrings only need a position set. By default, they size automatically according to the text shown.
-- local zoneTextLabel = zoneTextFrame:CreateFontString("ZoneTextLabel", "OVERLAY")
-- zoneTextLabel:SetFont(C.font.minimap_font, C.font.minimap_font_size, C.font.minimap_font_style)
-- zoneTextLabel:SetPoint("CENTER");

-- Minimap:SetScript("OnEnter", function(self)
--     local zoneText = GetMinimapZoneText()
--     if zoneText then
--         zoneTextLabel:SetText(zoneText)
--         zoneTextFrame:Show()
--     end
-- end)

-- Minimap:SetScript("OnLeave", function(self)
--     zoneTextFrame:Hide()
-- end)

AddonCompartmentFrame:Kill()

-- Garrison icon
ExpansionLandingPageMinimapButton:SetScale(0.0001)
ExpansionLandingPageMinimapButton:SetAlpha(0)


-- Feedback icon
do
    local f = rawget(_G, 'FeedbackUIButton')
    if f then
        f:ClearAllPoints()
        f:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 0)
        f:SetScale(0.8)
    end
end

-- Streaming icon
if StreamingIcon then
	StreamingIcon:ClearAllPoints()
	StreamingIcon:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, -10)
	StreamingIcon:SetScale(0.8)
	StreamingIcon:SetFrameStrata("BACKGROUND")
end

-- GhostFrame
GhostFrame:StripTextures()
GhostFrame:SetTemplate("Overlay")
GhostFrame:StyleButton()
GhostFrame:ClearAllPoints()
GhostFrame:SetPoint(unpack(C.position.ghost))
GhostFrameContentsFrameIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
GhostFrameContentsFrameIcon:SetSize(32, 32)
GhostFrameContentsFrame:SetFrameLevel(GhostFrameContentsFrame:GetFrameLevel() + 2)
GhostFrameContentsFrame:CreateBackdrop("Overlay")
GhostFrameContentsFrame.backdrop:SetPoint("TOPLEFT", GhostFrameContentsFrameIcon, -2, 2)
GhostFrameContentsFrame.backdrop:SetPoint("BOTTOMRIGHT", GhostFrameContentsFrameIcon, 2, -2)

-- Enable mouse scrolling
Minimap:EnableMouseWheel(true)
Minimap:SetScript("OnMouseWheel", function(_, d)
	if d > 0 then
    local zi = _G.Minimap and rawget(_G.Minimap, 'ZoomIn')
        if zi and zi.Click then zi:Click() end
	elseif d < 0 then
    local zo = _G.Minimap and rawget(_G.Minimap, 'ZoomOut')
        if zo and zo.Click then zo:Click() end
	end
end)

-- Hide Game Time
MinimapCluster:RegisterEvent("PLAYER_LOGIN")
MinimapCluster:RegisterEvent("ADDON_LOADED")
MinimapCluster:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_TimeManager" then
		TimeManagerClockButton:Kill()
	elseif addon == "Blizzard_HybridMinimap" then
		HybridMinimap:SetFrameStrata("BACKGROUND")
		HybridMinimap:SetFrameLevel(100)
		HybridMinimap.MapCanvas:SetUseMaskTexture(false)
		HybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
		HybridMinimap.MapCanvas:SetUseMaskTexture(true)
	end
end)

----------------------------------------------------------------------------------------
--	Right click menu
----------------------------------------------------------------------------------------

Minimap:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" then
		MinimapCluster.Tracking.Button:OpenMenu()
		MinimapCluster.Tracking.Button.menu:ClearAllPoints()
		MinimapCluster.Tracking.Button.menu:SetPoint("TOPRIGHT", Minimap, "LEFT", -4, 0)
	elseif button == "LeftButton" then
        local onClick = Minimap and rawget(Minimap, 'OnClick')
        if type(onClick) == 'function' then onClick(self) end
	end
end)

-- Set Square Map Mask
Minimap:SetMaskTexture(C.media.blank)
Minimap:SetArchBlobRingAlpha(0)
Minimap:SetQuestBlobRingAlpha(0)

-- For others mods with a minimap button, set minimap buttons position in square mode
function GetMinimapShape() return "SQUARE" end

-- ----------------------------------------------------------------------------------------
-- --	Hide minimap in combat
-- ----------------------------------------------------------------------------------------
-- if C.minimap.hide_combat == true then
-- 	MinimapAnchor:RegisterEvent("PLAYER_REGEN_ENABLED")
-- 	MinimapAnchor:RegisterEvent("PLAYER_REGEN_DISABLED")
-- 	MinimapAnchor:HookScript("OnEvent", function(self, event)
-- 		if event == "PLAYER_REGEN_ENABLED" then
-- 			self:Show()
-- 		elseif event == "PLAYER_REGEN_DISABLED" then
-- 			if not R.FarmMode then
-- 				self:Hide()
-- 			end
-- 		end
-- 	end)
-- end

----------------------------------------------------------------------------------------
--	Tracking Menu
----------------------------------------------------------------------------------------
MinimapCluster.Tracking.Background:Hide()
MinimapCluster.Tracking.Button:SetAlpha(0)
Minimap:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" then
		MinimapCluster.Tracking.Button:OpenMenu()
		local menu = MinimapCluster.Tracking.Button.menu
		if menu then
			local cursorX, cursorY = GetCursorPosition()
			local scale = UIParent:GetEffectiveScale()
			menu:ClearAllPoints()
			menu:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
		end
    elseif button == "LeftButton" then
        local onClick = Minimap and rawget(Minimap, 'OnClick')
        if type(onClick) == 'function' then onClick(self) end
    end
end)

----------------------------------------------------------------------------------------
-- Show who clicked the minimap
----------------------------------------------------------------------------------------
local whoClickedFrame = CreateFrame("Frame", "RefineUIWhoClickedFrame", Minimap)
whoClickedFrame:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 0)
whoClickedFrame:SetSize(1, 1)

local whoClickedText = whoClickedFrame:CreateFontString(nil, "OVERLAY")
whoClickedText:SetFont(C.media.normalFont, 16, "OUTLINE")
whoClickedText:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 6)

local whoClickedTimer

local function OnMinimapPing(self, event, unit)
	local name = UnitName(unit)
	local _, class = UnitClass(unit)
	whoClickedText:SetFormattedText("(%s)", name)
	whoClickedText:SetTextColor(unpack(R.oUF_colors.class[class]))
	UIFrameFadeRemoveFrame(whoClickedText)
	whoClickedText:SetAlpha(1)
	whoClickedText:Show()
if whoClickedTimer then whoClickedTimer:Cancel() end
    whoClickedTimer = C_Timer.NewTimer(5, function() FadeOutWhoClicked(whoClickedText) end)
end

whoClickedFrame:RegisterEvent("MINIMAP_PING")
whoClickedFrame:SetScript("OnEvent", OnMinimapPing)
whoClickedText:Hide()


----------------------------------------------------------------------------------------
-- Zone Text on Mouseover
----------------------------------------------------------------------------------------
local zoneText = Minimap:CreateFontString(nil, "OVERLAY")
zoneText:SetFont(C.media.normalFont, 16, "OUTLINE")
zoneText:SetPoint("TOP", Minimap, "TOP", 0, -2)
zoneText:Hide()

Minimap:HookScript("OnEnter", function()
	local zoneName = GetZoneText()
	if zoneName and zoneName ~= "" then
		local r, g, b = GetZoneColor()
		zoneText:SetText(zoneName)
		zoneText:SetTextColor(r, g, b)
		zoneText:Show()
	end
end)

Minimap:HookScript("OnLeave", function() zoneText:Hide() end)
