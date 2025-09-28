local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	UIWidget position
----------------------------------------------------------------------------------------
local top, below, power = _G["UIWidgetTopCenterContainerFrame"], _G["UIWidgetBelowMinimapContainerFrame"],
	_G["UIWidgetPowerBarContainerFrame"]

-- Top Widget
local topAnchor = CreateFrame("Frame", "UIWidgetTopAnchor", UIParent)
topAnchor:SetSize(200, 30)
topAnchor:SetPoint(unpack(C.position.uiwidgetTop))

top:ClearAllPoints()
top:SetPoint("TOP", topAnchor)

-- Below Widget
local belowAnchor = CreateFrame("Frame", "UIWidgetBelowAnchor", UIParent)
belowAnchor:SetSize(150, 30)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		if not belowAnchor:IsUserPlaced() then
			belowAnchor:ClearAllPoints()
			belowAnchor:SetPoint(unpack(C.position.uiwidgetBelow))
		end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end)

hooksecurefunc(below, "SetPoint", function(self, _, anchor)
	if anchor and anchor ~= belowAnchor then
		self:ClearAllPoints()
		self:SetPoint("TOP", belowAnchor)
	end
end)

-- Power Bar Widget
local powerAnchor = CreateFrame("Frame", "UIWidgetPowerBarAnchor", UIParent)
powerAnchor:SetSize(210, 30)
powerAnchor:SetPoint(unpack(C.position.uiwidgetBelow))

hooksecurefunc(power, "SetPoint", function(self, _, anchor)
	if anchor and anchor ~= powerAnchor then
		self:ClearAllPoints()
		self:SetPoint("TOP", powerAnchor)
	end
end)

-- Mover for all widgets
for _, frame in pairs({ top, below }) do
	local anchor = frame == top and topAnchor or frame == below and belowAnchor
	if anchor then
		anchor:SetMovable(true)
		anchor:SetClampedToScreen(true)
	end
	if frame and frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end
	frame:SetScript("OnMouseDown", function(_, button)
		if IsAltKeyDown() or IsShiftKeyDown() then
			if anchor then
				anchor:ClearAllPoints()
				anchor:StartMoving()
			end
		elseif IsControlKeyDown() and button == "RightButton" then
			if anchor then anchor:ClearAllPoints() end
			if frame == top then
				if anchor then anchor:SetPoint(unpack(C.position.uiwidgetTop)) end
			elseif frame == below then
				if anchor then anchor:SetPoint(unpack(C.position.uiwidgetBelow)) end
            else
				local buffsAnchor = rawget(_G, 'RefineUI_Buffs')
				if buffsAnchor and anchor then anchor:SetPoint("TOPRIGHT", buffsAnchor, "BOTTOMRIGHT", 0, -3) end
			end
			if anchor and anchor.SetUserPlaced then anchor:SetUserPlaced(false) end
		end
	end)
	frame:SetScript("OnMouseUp", function()
		if anchor and anchor.StopMovingOrSizing then anchor:StopMovingOrSizing() end
	end)
end

----------------------------------------------------------------------------------------
--	UIWidget skin
----------------------------------------------------------------------------------------
local atlasColors = {
	["UI-Frame-Bar-Fill-Blue"] = { 0.2, 0.6, 1 },
	["UI-Frame-Bar-Fill-Red"] = { 0.9, 0.2, 0.2 },
	["UI-Frame-Bar-Fill-Yellow"] = { 1, 0.6, 0 },
	["objectivewidget-bar-fill-left"] = { 0.2, 0.6, 1 },
	["objectivewidget-bar-fill-right"] = { 0.9, 0.2, 0.2 }
}

local function SkinStatusBar(widget)
	local bar = widget.Bar

	if widget:IsForbidden() then
		if bar and bar.tooltip then
			bar.tooltip = nil
		end
		return
	end

	local atlas = bar:GetStatusBarTexture()
	if atlasColors[atlas] then
		bar:SetStatusBarTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\Statusbar.blp")
		bar:SetStatusBarColor(unpack(atlasColors[atlas]))
	end

	if widget:GetParent() == power then
		-- Don't skin Cosmic Energy bar
		if widget.widgetID == 3463 then
			bar.styled = true
		end
	end

	if not bar.styled then
		bar.BGLeft:SetAlpha(0)
		bar.BGRight:SetAlpha(0)
		bar.BGCenter:SetAlpha(0)
		bar.BorderLeft:SetAlpha(0)
		bar.BorderRight:SetAlpha(0)
		bar.BorderCenter:SetAlpha(0)
		bar.Spark:SetAlpha(0)
		local parent = widget:GetParent():GetParent()
		if parent.castBar or parent.UnitFrame then -- nameplate
			Mixin(bar, BackdropTemplateMixin)
			bar:SetBackdrop({
				bgFile = C.media.blank,
				insets = { left = 0, right = 0, top = 0, bottom = 0 }
			})
			bar:SetBackdropColor(0.1, 0.1, 0.1, 1)
		else
			bar:CreateBackdrop("Overlay")
		end
		bar.styled = true
	end
end

local function SkinDoubleStatusBar(widget)
	for _, bar in pairs({ widget.LeftBar, widget.RightBar }) do
		local atlas = bar:GetStatusBarTexture()
		if atlasColors[atlas] then
			bar:SetStatusBarTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\Statusbar.blp")
			bar:SetStatusBarColor(unpack(atlasColors[atlas]))
		end
		if not bar.styled then
			bar.BG:SetAlpha(0)
			bar.BorderLeft:SetAlpha(0)
			bar.BorderRight:SetAlpha(0)
			bar.BorderCenter:SetAlpha(0)
			bar.Spark:SetAlpha(0)
			bar.SparkGlow:SetAlpha(0)
			bar:CreateBackdrop("Overlay")
			bar.styled = true
		end
	end
end

local function SkinCaptureBar(widget)
	widget.LeftLine:SetAlpha(0)
	widget.RightLine:SetAlpha(0)
	widget.BarBackground:SetAlpha(0)
	widget.Glow1:SetAlpha(0)
	widget.Glow2:SetAlpha(0)
	widget.Glow3:SetAlpha(0)

	widget.LeftBar:SetTexture(C.media.texture)
	widget.NeutralBar:SetTexture(C.media.texture)
	widget.RightBar:SetTexture(C.media.texture)

	widget.LeftBar:SetVertexColor(0.2, 0.6, 1)
	widget.NeutralBar:SetVertexColor(0.8, 0.8, 0.8)
	widget.RightBar:SetVertexColor(0.9, 0.2, 0.2)
	widget:SetTemplate("Default")
	-- if not widget.backdrop then
	-- 	widget:CreateBackdrop("Default")
	-- 	widget.backdrop:SetPoint("TOPLEFT", widget.LeftBar, -2, 2)
	-- 	widget.backdrop:SetPoint("BOTTOMRIGHT", widget.RightBar, 2, -2)
	-- end
end

local VigorBar = CreateFrame("Frame", "VigorBar", UIParent)
VigorBar:SetTemplate("Default")
VigorBar.border:SetFrameStrata("HIGH")
VigorBar:SetPoint("TOP", powerAnchor, "TOP", 0, -2)
VigorBar:SetSize(350, 20)
VigorBar:Hide()

for i = 1, 6 do
	VigorBar[i] = CreateFrame("StatusBar", "Vigor" .. i, VigorBar)
	VigorBar[i]:SetSize((350 - 5) / 6, 20)

	if i == 1 then
		VigorBar[i]:SetPoint("TOPLEFT", VigorBar, "TOPLEFT", 0, 0)
	else
		VigorBar[i]:SetPoint("TOPLEFT", VigorBar[i - 1], "TOPRIGHT", 1, 0)
	end
	VigorBar[i]:SetStatusBarTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\Statusbar-Half.blp")
	VigorBar[i]:SetMinMaxValues(0, 100)
	VigorBar[i]:SetStatusBarColor(0.2, 0.58, 0.8)

	VigorBar[i].bg = VigorBar[i]:CreateTexture(nil, "BORDER")
	VigorBar[i].bg:SetAllPoints()
	VigorBar[i].bg:SetTexture(C.media.texture)
	VigorBar[i].bg:SetVertexColor(0.2 * 0.2, 0.58 * 0.2, 0.8 * 0.2)

	VigorBar[i]:SetValue(0)
end

local function SkinVigorBar(widget)
	if not widget:IsShown() then return end -- Hide our bar if Blizzard's not shown
	local widgetInfo = C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo(widget.widgetID)
	if not widgetInfo then return end

	VigorBar:Show()
	local total = widgetInfo.numTotalFrames
	for i = 1, total do
		local value = 0
		VigorBar[i]:SetStatusBarColor(0.2, 0.58, 0.8)
		if widgetInfo.numFullFrames >= i then
			value = widgetInfo.fillMax
		elseif widgetInfo.numFullFrames + 1 == i then
			value = widgetInfo.fillValue
			VigorBar[i]:SetStatusBarColor(0.2 * 0.6, 0.58 * 0.6, 0.8 * 0.6)
		else
			value = widgetInfo.fillMin
		end
		VigorBar[i]:SetValue(value)
	end

	if total < 6 and IsPlayerSpell(377922) then total = 6 end -- sometimes it return 5

	if total < 6 then
		for i = total + 1, 6 do
			VigorBar[i]:Hide()
			VigorBar[i]:SetValue(0)
		end

		local spacing = select(4, VigorBar[6]:GetPoint())
		local w = VigorBar:GetWidth()
		local s = 0

		for i = 1, total do
			VigorBar[i]:Show()
			if i ~= total then
				VigorBar[i]:SetWidth(w / total - spacing)
				s = s + (w / total)
			else
				VigorBar[i]:SetWidth(w - s)
			end
		end
	end

	widget:SetAlpha(0)

	if not widget.hook then
		hooksecurefunc(widget, "Hide", function(self)
			VigorBar:Hide()
		end)
		widget.hook = true
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_UI_WIDGET")
frame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	for _, widget in pairs(UIWidgetTopCenterContainerFrame.widgetFrames) do
		if widget.widgetType == _G.Enum.UIWidgetVisualizationType.StatusBar then
			SkinStatusBar(widget)
		elseif widget.widgetType == _G.Enum.UIWidgetVisualizationType.DoubleStatusBar then
			SkinDoubleStatusBar(widget)
		end
	end

	for _, widget in pairs(UIWidgetBelowMinimapContainerFrame.widgetFrames) do
		if widget.widgetType == Enum.UIWidgetVisualizationType.CaptureBar then
			SkinCaptureBar(widget)
		end
	end

	for _, widget in pairs(UIWidgetPowerBarContainerFrame.widgetFrames) do
		if widget.widgetType == Enum.UIWidgetVisualizationType.FillUpFrames then
			SkinVigorBar(widget)
		end
	end
end)

hooksecurefunc(UIWidgetTemplateScenarioHeaderCurrenciesAndBackgroundMixin, "Setup", function(widgetInfo)
	widgetInfo.Frame:SetAlpha(0)
	for frame in widgetInfo.currencyPool:EnumerateActive() do
		frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	end
end)

hooksecurefunc(UIWidgetTemplateStatusBarMixin, "Setup", function(widget)
	SkinStatusBar(widget)
end)
