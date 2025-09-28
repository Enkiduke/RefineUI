local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
local UF = R.UF

-- Position and size
local parent = UIParent
local Experience = CreateFrame('StatusBar', nil, parent)
Experience:SetPoint('BOTTOM', 0, -50)
Experience:SetSize(200, 20)
Experience:EnableMouse(true) -- for tooltip/fading support

-- Position and size the Rested sub-widget
local Rested = CreateFrame('StatusBar', nil, Experience)
Rested:SetAllPoints(Experience)

-- Text display
local Value = Experience:CreateFontString(nil, 'OVERLAY')
Value:SetAllPoints(Experience)
Value:SetFontObject(GameFontHighlight)
if oUF and oUF.Tags and oUF.Tags.Methods then
    local tagFunc = oUF.Tags.Methods['experience:cur'] and oUF.Tags.Methods['experience:max']
    -- leave tag display to layouts; show plain text as a fallback
end

-- Add a background
local Background = Rested:CreateTexture(nil, 'BACKGROUND')
Background:SetAllPoints(Experience)
Background:SetTexture('Interface\\ChatFrame\\ChatFrameBackground')

-- Register with oUF
UF = UF or {}
UF.ExperienceBar = Experience
Experience.Rested = Rested