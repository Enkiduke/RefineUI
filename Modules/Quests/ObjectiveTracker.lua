local R, C, L = unpack(RefineUI)

-- ----------------------------------------------------------------------------------------
-- --	Common styling functions
-- ----------------------------------------------------------------------------------------
local function HideBarElements(bar, elements)
	for _, element in ipairs(elements) do
		if bar[element] then
			if element:find("Border") or element == "IconBG" then
				bar[element]:SetAlpha(0)
			else
				bar[element]:Hide()
			end
		end
	end
end

local function SetupBarStyle(bar, size)
	if size then
		bar:SetSize(size.width, size.height)
	end
	bar:SetStatusBarTexture(C.media.texture)
	bar:CreateBackdrop("Transparent")
end

-- ----------------------------------------------------------------------------------------
-- --	Skin quest objective progress bar
-- ----------------------------------------------------------------------------------------
local function HideProgressBarElements(bar)
	local elements = {"BarFrame", "BarFrame2", "BarFrame3", "BarGlow", "Sheen", "IconBG", "BorderLeft", "BorderRight", "BorderMid"}
	HideBarElements(bar, elements)
end

local function SetupProgressBarStyle(bar)
	SetupBarStyle(bar, {width = 200, height = 16})
end

local function SetupProgressBarLabel(label)
	label:ClearAllPoints()
	label:SetPoint("CENTER", 0, -1)
	label:SetFont(unpack(C.font.quest))
	label:SetShadowOffset(1, -1)
	label:SetDrawLayer("OVERLAY")
end

local function SetupProgressBarIcon(bar, icon)
	icon:SetPoint("RIGHT", 26, 0)
	icon:SetSize(20, 20)
	icon:SetMask("")

	local border = CreateFrame("Frame", "$parentBorder", bar)
	border:SetAllPoints(icon)
	border:SetTemplate("Transparent")
	border:SetBackdropColor(0, 0, 0, 0)
	bar.newIconBg = border

	hooksecurefunc(bar.AnimIn, "Play", function()
		bar.AnimIn:Stop()
	end)
end

local function SkinProgressBar(tracker, key)
	local progressBar = tracker.usedProgressBars[key]
	local bar = progressBar and progressBar.Bar
	local label = bar and bar.Label
	local icon = bar and bar.Icon

	if not progressBar.styled then
		HideProgressBarElements(bar)
		if progressBar.PlayFlareAnim then progressBar.PlayFlareAnim = R.dummy end
		
		SetupProgressBarStyle(bar)
		SetupProgressBarLabel(label)
		
		if icon then
			SetupProgressBarIcon(bar, icon)
		end
		
		progressBar.styled = true
	end

	if bar.newIconBg then bar.newIconBg:SetShown(icon:IsShown()) end
end

-- ----------------------------------------------------------------------------------------
-- --	Skin Timer bar
-- ----------------------------------------------------------------------------------------
local function HideTimerBarElements(bar)
	local elements = {"BorderLeft", "BorderRight", "BorderMid"}
	HideBarElements(bar, elements)
end

local function SetupTimerBarStyle(bar)
	SetupBarStyle(bar)
end

local function SkinTimer(tracker, key)
	local timerBar = tracker.usedTimerBars[key]
	local bar = timerBar and timerBar.Bar

	if not timerBar.styled then
		HideTimerBarElements(bar)
		SetupTimerBarStyle(bar)
		timerBar.styled = true
	end
end

-- ----------------------------------------------------------------------------------------
-- --	Skin and hook all trackers
-- ----------------------------------------------------------------------------------------
local function OnBlockHeaderLeave(_, block)
	if block.HeaderText and block.HeaderText.col then
		block.HeaderText:SetTextColor(block.HeaderText.col.r, block.HeaderText.col.g, block.HeaderText.col.b)
	end
end

local function SetupTracker(tracker)
	if not tracker then return end
	
	hooksecurefunc(tracker, "GetProgressBar", SkinProgressBar)
	hooksecurefunc(tracker, "GetTimerBar", SkinTimer)
	hooksecurefunc(tracker, "OnBlockHeaderLeave", OnBlockHeaderLeave)
end

-- Pre-filter valid trackers for performance
local trackers = {
	ScenarioObjectiveTracker,
	BonusObjectiveTracker,
	UIWidgetObjectiveTracker,
	CampaignQuestObjectiveTracker,
	QuestObjectiveTracker,
	AdventureObjectiveTracker,
	AchievementObjectiveTracker,
	MonthlyActivitiesObjectiveTracker,
	ProfessionsRecipeTracker,
	WorldQuestObjectiveTracker,
}

-- Setup all valid trackers
for i = 1, #trackers do
	SetupTracker(trackers[i])
end

