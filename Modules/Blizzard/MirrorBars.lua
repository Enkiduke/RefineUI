local R, C, L = unpack(RefineUI)

-- Upvalues and constants for clarity and micro-optimizations
local UIParent = UIParent
local DEFAULT_COLOR = { 0.8, 0.8, 0.8 }
local TIMER_DEFAULT_Y = -96

----------------------------------------------------------------------------------------
--	Mirror Timers (Underwater Breath, etc.) [from ElvUI]
----------------------------------------------------------------------------------------
local position = (C and C.position and C.position.mirrorTimers) or {
	BREATH = -96;
	EXHAUSTION = -116;
	FEIGNDEATH = -142;
}

local function loadPosition(frame, timer)
	local y = position[timer] or TIMER_DEFAULT_Y
	frame:SetPoint("TOP", UIParent, "TOP", 0, y)
end

local colors = {
	EXHAUSTION = {1, 0.9, 0};
	BREATH = {0.31, 0.45, 0.63};
	DEATH = {1, 0.7, 0};
	FEIGNDEATH = {0.3, 0.7, 0};
}

local function SetupTimer(container, timer)
	local bar = container:GetAvailableTimer(timer)
	if not bar then return end

	if not bar.atlasHolder then
		bar.atlasHolder = CreateFrame("Frame", nil, bar)
		bar.atlasHolder:SetClipsChildren(true)
		bar.atlasHolder:SetInside()

		bar.StatusBar:SetParent(bar.atlasHolder)
		bar.StatusBar:ClearAllPoints()
		bar.StatusBar:SetAllPoints()

		bar.Text:SetFont(C.media.normalFont, C.media.normalFontSize, C.media.normalFontStyle)
		bar.Text:SetShadowOffset(0, 0)
		bar.Text:ClearAllPoints()
		bar.Text:SetParent(bar.StatusBar)
		bar.Text:SetPoint("CENTER", bar.StatusBar, 0, 0)

		bar:SetSize(289, 23)
		bar:StripTextures()
		bar:SetTemplate("Transparent")
		-- bar.backdrop:SetPoint("TOPLEFT", 2, -2)
		-- bar.backdrop:SetPoint("BOTTOMRIGHT", -2, 1)

		bar:ClearAllPoints()
		loadPosition(bar, timer)
	end

	local color = colors[timer] or DEFAULT_COLOR
	bar.StatusBar:SetStatusBarTexture(C.media.texture)
	bar.StatusBar:SetStatusBarColor(color[1], color[2], color[3])
end

local mirrorContainer = _G and _G["MirrorTimerContainer"]
if mirrorContainer then
	hooksecurefunc(mirrorContainer, "SetupTimer", SetupTimer)
end