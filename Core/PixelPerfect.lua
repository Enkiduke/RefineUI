----------------------------------------------------------------------------------------
-- RefineUI PixelPerfect
-- Description: Handles resolution-independent scaling and pixel alignment.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local floor = math.floor
local min, max = math.min, math.max
local format = string.format
local tonumber = tonumber
local type = type
local _G = _G

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local UIParent = _G.UIParent
local GetPhysicalScreenSize = _G.GetPhysicalScreenSize
local SetCVar = _G.SetCVar
local GetCVar = _G.GetCVar

----------------------------------------------------------------------------------------
-- Pixel Perfect Math
----------------------------------------------------------------------------------------

-- 1. Get accurate screen dimensions
function RefineUI:UpdateScreenDimensions()
    local w, h = GetPhysicalScreenSize()
    
    -- Robust fallback if GetPhysicalScreenSize returns 0 (can happen early in boot)
    if not h or h <= 0 then
        -- Try getting resolution from CVar as second fallback
        local res = GetCVar("gxWindowedResolution") or GetCVar("gxFullscreenResolution")
        if res then
            w, h = _G.string.match(res, "(%d+)x(%d+)")
            w, h = tonumber(w), tonumber(h)
        end
    end
    
    -- Final fallback to 1080p
    RefineUI.ScreenWidth = (w and w > 0) and w or 1920
    RefineUI.ScreenHeight = (h and h > 0) and h or 1080
end

-- 2. Calculate ideal scale based on height
function RefineUI:CalculateUIScale()
    local screenHeight = RefineUI.ScreenHeight or 1080
    if screenHeight < 1 then screenHeight = 1080 end
    
    local baseScale = 768 / screenHeight
    local uiScale = baseScale

    -- Apply multipliers for very high resolutions to keep UI readable (e.g. 1440p, 4K)
    if screenHeight >= 2400 then -- 4K+
        uiScale = uiScale * 3
    elseif screenHeight >= 1600 then -- 1440p / 1600p
        uiScale = uiScale * 2
    end

    -- Clamp to sane bounds
    uiScale = min(2, max(0.40, uiScale))

    return tonumber(format("%.5f", uiScale))
end

-- 3. Update internal math constants (SAFE - No CVar changes)
function RefineUI:UpdatePixelConstants()
    RefineUI:UpdateScreenDimensions()
    local general = (RefineUI.Config and RefineUI.Config.General) or {}
    
    -- Determine effective scale (Config > CVar > Calculated)
    local effectiveScale = general.Scale
    if not effectiveScale then
        effectiveScale = tonumber(GetCVar("uiScale"))
        if not effectiveScale or effectiveScale <= 0 then
             effectiveScale = RefineUI:CalculateUIScale()
        end
    end

    if not effectiveScale or effectiveScale <= 0 then effectiveScale = 1 end
    
    -- 768 is the magic Blizzard UI height constant
    RefineUI.mult = (768 / RefineUI.ScreenHeight) / effectiveScale
    RefineUI.noscalemult = RefineUI.mult * effectiveScale
    RefineUI.low_resolution = RefineUI.ScreenWidth <= 1440
end

-- 4. Enforce Scale (DANGEROUS - Sets CVars, calls Recompute)
-- Only call this on Login or Config Change. NEVER on Display Change.
function RefineUI:SetUIScale()
    local general = (RefineUI.Config and RefineUI.Config.General) or {}
    if not general.UseUIScale then return end
    
    local idealScale = general.Scale or RefineUI:CalculateUIScale()
    
    if idealScale ~= tonumber(GetCVar("uiScale")) then
        SetCVar("useUiScale", "1")
        SetCVar("uiScale", tostring(idealScale))
    end
    
    -- Apply to UIParent just in case
    if UIParent then
        UIParent:SetScale(idealScale)
    end
    
    RefineUI:UpdatePixelConstants()
end

----------------------------------------------------------------------------------------
-- Scale API
----------------------------------------------------------------------------------------

local function ScaleValue(x)
    local m = RefineUI.mult or 1
    if m == 0 then return 0 end
    if type(x) ~= "number" then return x end
    return m * floor(x / m + 0.5)
end

-- Supports both RefineUI:Scale(x) and RefineUI.Scale(x)
RefineUI.Scale = function(self, x)
	if type(self) == "number" then return ScaleValue(self) end
	return ScaleValue(x)
end

----------------------------------------------------------------------------------------
-- Pixel Perfect Utilities
----------------------------------------------------------------------------------------

function RefineUI:PixelPerfect(x)
	local scale = UIParent:GetEffectiveScale()
	return floor(x / scale + 0.5) * scale
end

function RefineUI:PixelSnap(frame)
	if not frame or not frame.GetPoint then return end
	local numPoints = frame:GetNumPoints()
	if numPoints == 0 then return end

	local scale = frame:GetEffectiveScale() or 1
	local anchors = {}
	for i = 1, numPoints do
		local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
		if point then
			local parentScale = (relativeTo and relativeTo.GetEffectiveScale and relativeTo:GetEffectiveScale()) or scale
			xOfs = xOfs or 0
			yOfs = yOfs or 0
			-- Snap to nearest physical pixel
			xOfs = RefineUI:PixelPerfect((xOfs * scale) / parentScale) / scale
			yOfs = RefineUI:PixelPerfect((yOfs * scale) / parentScale) / scale
			anchors[#anchors + 1] = { point, relativeTo, relativePoint, xOfs, yOfs }
		end
	end

	if #anchors == 0 then return end
	frame:ClearAllPoints()
	for i = 1, #anchors do
		frame:SetPoint(anchors[i][1], anchors[i][2], anchors[i][3], anchors[i][4], anchors[i][5])
	end
end

function RefineUI:SetPixelSize(frame, width, height)
	local scale = frame:GetEffectiveScale()
	width = width and RefineUI:PixelPerfect(width * scale) / scale or frame:GetWidth()
	height = height and RefineUI:PixelPerfect(height * scale) / scale or frame:GetHeight()
	frame:SetSize(width, height)
end

----------------------------------------------------------------------------------------
-- Initialization & Events
----------------------------------------------------------------------------------------

-- Initial setup of constants (Safe)
RefineUI:UpdatePixelConstants()

-- Handle Display Changes (SAFE - Only math, no CVars)
RefineUI:RegisterEventCallback("DISPLAY_SIZE_CHANGED", function()
    RefineUI:UpdatePixelConstants()
end)

RefineUI:RegisterEventCallback("UI_SCALE_CHANGED", function()
     RefineUI:UpdatePixelConstants()
end)

-- Note: RefineUI:SetUIScale() is called in Engine.lua:PLAYER_LOGIN
