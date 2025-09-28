local R, C, L = unpack(RefineUI)
local oGlow = rawget(_G, "oGlow")

-- local Mult = R.mult
-- if R.screenHeight > 1200 then
-- 	Mult = R.Scale(1)
-- end

local colorTable = setmetatable(
	{},
	{
		__index = function(self, val)
			local r, g, b = C_Item.GetItemQualityColor(val)
			rawset(self, val, { r, g, b })
			return self[val]
		end
	}
)

local createBorder = function(self)
	if not self or type(self) ~= "table" or not self.GetName then
		return nil
	end
	-- print("oGlow Border: createBorder called for:", self:GetName())
	local border = self.oGlowBorder
	if not border then
		if self.border then
			-- print("oGlow Border: Found existing self.border on", self:GetName())
			self.oGlowBorder = self.border
		else
			-- print("oGlow Border: No existing border, calling SetTemplate('Icon') on", self:GetName())
			self:SetTemplate("Icon")
			if self.border then
				-- print("oGlow Border: SetTemplate created self.border on", self:GetName())
				self.oGlowBorder = self.border
			else
				-- print("oGlow Border: SetTemplate FAILED to create self.border on", self:GetName(), ". Returning nil.")
				return nil
			end
		end
	end

	if self.oGlowBorder then
		-- print("oGlow Border: Ensuring border is shown for", self:GetName())
		self.oGlowBorder:SetFrameStrata("HIGH")
		self.oGlowBorder:SetFrameLevel(self:GetFrameLevel() + 5)
		self.oGlowBorder:SetAlpha(1)
		self.oGlowBorder:Show()
	else
		-- This case shouldn't happen if the logic above is correct, but just in case
		-- print("oGlow Border: ERROR - self.oGlowBorder is nil after checks for", self:GetName())
	end

	return self.oGlowBorder
end

local borderDisplay = function(frame, color)
	if not frame or type(frame) ~= "table" or not frame.GetName then
		return false
	end
	-- print("oGlow Border: borderDisplay called for:", frame:GetName(), "with color:", tostring(color))
	if color then
		local border = createBorder(frame)
		if not border then
			-- print("oGlow Border: createBorder returned nil for", frame:GetName(), ". Aborting display.")
			return false
		end

		local rgb = colorTable[color]

		if rgb then
			-- print("oGlow Border: Setting border color for", frame:GetName(), "to", rgb[1], rgb[2], rgb[3])
			border:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 1)
			return true
		else
			-- print("oGlow Border: No RGB found for color", tostring(color), "on", frame:GetName())
			-- return false
		end
	elseif frame.oGlowBorder then
		-- print("oGlow Border: Hiding existing border for", frame:GetName())
		frame.oGlowBorder:Hide()
		return false
	else
		-- print("oGlow Border: No color and no existing border for", frame:GetName())
		-- return false
	end
end

function oGlow:RegisterColor(name, r, g, b)
	if rawget(colorTable, name) then
		return nil, string.format("Color [%s] is already registered.", name)
	else
		rawset(colorTable, name, { r, g, b })
	end

	return true
end

oGlow:RegisterDisplay("Border", borderDisplay)
