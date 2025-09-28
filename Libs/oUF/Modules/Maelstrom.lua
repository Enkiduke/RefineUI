local R, C, L = unpack(RefineUI)
if (R.class ~= 'SHAMAN') then return end

local _, ns = ...
local oUF = ns.oUF
-- local LCG = LibStub("LibCustomGlow-1.0")

-- local ButtonGlow_Start = LCG.ButtonGlow_Start
-- local ButtonGlow_Stop = LCG.ButtonGlow_Stop
-- local PixelGlow_Start = LCG.PixelGlow_Start
-- local PixelGlow_Stop = LCG.PixelGlow_Stop
-- local AutoCastGlow_Start = LCG.AutoCastGlow_Start
-- local AutoCastGlow_Stop = LCG.AutoCastGlow_Stop

local function GetMaelstromStack()
	local spellTable = C_UnitAuras.GetPlayerAuraBySpellID(344179)
	if type(spellTable) ~= "table" then return 0 end
	local count = spellTable.applications
	return (count or 0)
end

local function Update(self, event, unit, powerToken)
    if self.unit ~= unit then return end
    if powerToken and powerToken ~= "MAELSTROM" then return end

	local element = self.Maelstrom

	if(element.PreUpdate) then
		element:PreUpdate(unit)
	end

	if UnitHasVehicleUI("player") then
		element:Hide()
		if self.Debuffs then self.Debuffs:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 2, 5) end
	else
		element:Show()
		if self.Debuffs then self.Debuffs:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 2, 22) end
	end

	local cur = GetMaelstromStack()
	local max = 10 -- Cause we don't use :Factory to spawn frames it return sometimes "3"

	for i = 1, max do
		if(i <= cur) then
			element[i]:SetValue(1)
			element[i]:SetAlpha(1)
		else
			element[i]:SetValue(0)
			element[i]:SetAlpha(0.2)
		end
	end

	-- if cur == max then
	-- 	-- PixelGlow_Start(self.Maelstrom.backdrop.border, {0.65, 0.52, 0.94}, 20, .2, 6, 2, -6, -6, true)
	-- 	AutoCastGlow_Start(self.Maelstrom.backdrop.border, {0.65, 0.52, 0.94}, 10, .25, 2, -5, -5)
	-- else
	-- 	-- PixelGlow_Stop(self.Maelstrom.backdrop.border)
	-- 	AutoCastGlow_Stop(self.Maelstrom.backdrop.border)
	-- end


	if(element.PostUpdate) then
		return element:PostUpdate(cur)
	end
end

local function Path(self, ...)
	return (self.Maelstrom.Override or Update) (self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, "ForceUpdate", element.__owner.unit)
end

local function Visibility(self)
	local element = self.Maelstrom

	if not UnitHasVehicleUI("player") then
		element:Show()
		if self.Debuffs then self.Debuffs:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 2, 22) end
	end
	self:RegisterEvent("UNIT_AURA", Path)
end

local function Enable(self)
	local element = self.Maelstrom
	if(element) then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		element.handler = CreateFrame("Frame", nil, element)
		element.handler:RegisterEvent("PLAYER_TALENT_UPDATE")
		element.handler:RegisterEvent("PLAYER_ENTERING_WORLD")
		element.handler:SetScript("OnEvent", function() Visibility(self) end)

		return true
	end
end

local function Disable(self)
	local element = self.Maelstrom
	if(element) then
		element.handler:UnregisterEvent("PLAYER_TALENT_UPDATE")
		element.handler:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end

oUF:AddElement("Maelstrom", Path, Enable, Disable)
