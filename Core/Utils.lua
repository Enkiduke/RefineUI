local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF


R.SetFontString = function(parent, fontName, fontHeight, fontStyle)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetFont(fontName, fontHeight, fontStyle)
    return fs
end

local day, hour, minute = 86400, 3600, 60
local floor, format = math.floor, string.format

R.FormatTime = function(s)
    if s >= day then
        return format("%dd", floor(s / day + 0.5))
    elseif s >= hour then
        return format("%dh", floor(s / hour + 0.5))
    elseif s >= minute then
        return format("%dm", floor(s / minute + 0.5))
    elseif s >= 5 then
        return tostring(floor(s + 0.5))
    end
    return format("%.1f", s)
end

----------------------------------------------------------------------------------------
--	Number value function
----------------------------------------------------------------------------------------
R.Round = function(number, decimals)
	if not decimals then decimals = 0 end
	if decimals and decimals > 0 then
		local mult = 10 ^ decimals
		return floor(number * mult + 0.5) / mult
	end
	return floor(number + 0.5)
end

R.ShortValue = function(value)
	if value >= 1e11 then
		return ("%.0fB"):format(value / 1e9)
	elseif value >= 1e10 then
		return ("%.1fB"):format(value / 1e9):gsub("%.?0+([km])$", "%1")
	elseif value >= 1e9 then
		return ("%.2fB"):format(value / 1e9):gsub("%.?0+([km])$", "%1")
	elseif value >= 1e8 then
		return ("%.0fM"):format(value / 1e6)
	elseif value >= 1e7 then
		return ("%.1fM"):format(value / 1e6):gsub("%.?0+([km])$", "%1")
	elseif value >= 1e6 then
		return ("%.2fM"):format(value / 1e6):gsub("%.?0+([km])$", "%1")
	elseif value >= 1e5 then
		return ("%.0fK"):format(value / 1e3)
	elseif value >= 1e3 then
		return ("%.1fK"):format(value / 1e3):gsub("%.?0+([km])$", "%1")
	else
		return value
	end
end


----------------------------------------------------------------------------------------
--	Colors
----------------------------------------------------------------------------------------

R.RGBToHex = function(r, g, b)
	r = tonumber(r) <= 1 and tonumber(r) >= 0 and tonumber(r) or 0
	g = tonumber(g) <= tonumber(g) and tonumber(g) >= 0 and tonumber(g) or 0
	b = tonumber(b) <= 1 and tonumber(b) >= 0 and tonumber(b) or 0
	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

R.ColorGradient = function(perc, r1,g1,b1, r2,g2,b2, r3,g3,b3)
    if perc >= 1 then
        return r3, g3, b3
    elseif perc <= 0 then
        return r1, g1, b1
    end

    local segment, relperc = math.modf(perc * 2)
    local rr1, rg1, rb1, rr2, rg2, rb2 = select((segment * 3) + 1, r1,g1,b1, r2,g2,b2, r3,g3,b3)

    return rr1 + (rr2 - rr1) * relperc, rg1 + (rg2 - rg1) * relperc, rb1 + (rb2 - rb1) * relperc
end

----------------------------------------------------------------------------------------
--	Fade in/out functions
----------------------------------------------------------------------------------------
R.FadeIn = function(f)
    UIFrameFadeIn(f, 0.4, f:GetAlpha(), 1)
end

R.FadeOut = function(f)
    UIFrameFadeOut(f, 0.8, f:GetAlpha(), 0)
end