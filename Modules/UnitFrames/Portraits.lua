----------------------------------------------------------------------------------------
-- RefineUI Portraits (Shared)
-- Description: Shared portrait functionality for UnitFrames and Nameplates
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
RefineUI.UnitFrames = RefineUI.UnitFrames or {}

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local select, unpack, pairs = select, unpack, pairs
local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local SetPortraitTexture = SetPortraitTexture
local GetTime = GetTime
local math = math

local TEXTURE_PATH = "Interface\\AddOns\\RefineUI\\Media\\Textures\\"

----------------------------------------------------------------------------------------
-- Radial Statusbar Functions (Quest Progress)
----------------------------------------------------------------------------------------
local cos, sin, pi2, halfpi = math.cos, math.sin, math.rad(360), math.rad(90)

local function TransformTexture(tx, x, y, angle, aspect)
    local c, s = cos(angle), sin(angle)
    local y2, oy = y / aspect, 0.5 / aspect
    local ULx, ULy = 0.5 + (x - 0.5) * c - (y2 - oy) * s, (oy + (y2 - oy) * c + (x - 0.5) * s) * aspect
    local LLx, LLy = 0.5 + (x - 0.5) * c - (y2 + oy) * s, (oy + (y2 + oy) * c + (x - 0.5) * s) * aspect
    local URx, URy = 0.5 + (x + 0.5) * c - (y2 - oy) * s, (oy + (y2 - oy) * c + (x + 0.5) * s) * aspect
    local LRx, LRy = 0.5 + (x + 0.5) * c - (y2 + oy) * s, (oy + (y2 + oy) * c + (x + 0.5) * s) * aspect
    tx:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end

local function OnPlayUpdate(self)
    self:SetScript('OnUpdate', nil)
    self:Pause()
end

local function OnPlay(self)
    self:SetScript('OnUpdate', OnPlayUpdate)
end

local function SetRadialStatusBarValue(self, value)
    value = math.max(0, math.min(1, value))
    if self._reverse then value = 1 - value end
    
    local q = self._clockwise and (1 - value) or value
    local quadrant = q >= 0.75 and 1 or q >= 0.5 and 2 or q >= 0.25 and 3 or 4
    
    if self._quadrant ~= quadrant then
        self._quadrant = quadrant
        for i = 1, 4 do
            self._textures[i]:SetShown(self._clockwise and i < quadrant or not self._clockwise and i > quadrant)
        end
        self._scrollframe:SetAllPoints(self._textures[quadrant])
    end
    
    local rads = value * pi2
    if not self._clockwise then rads = -rads + halfpi end
    TransformTexture(self._wedge, -0.5, -0.5, rads, self._aspect)
    self._rotation:SetRadians(-rads)
end

local function OnSizeChanged(self, width, height)
    self._wedge:SetSize(width, height)
    self._aspect = width / height
end

local function CreateTextureFunction(func)
    return function(self, ...)
        for i = 1, 4 do
            self._textures[i][func](self._textures[i], ...)
        end
        self._wedge[func](self._wedge, ...)
    end
end

local TextureFunctions = {
    SetTexture = CreateTextureFunction('SetTexture'),
    SetBlendMode = CreateTextureFunction('SetBlendMode'),
    SetVertexColor = CreateTextureFunction('SetVertexColor'),
}

local function CreateRadialStatusBar(parent)
    local bar = CreateFrame('Frame', nil, parent)
    
    local scrollframe = CreateFrame('ScrollFrame', nil, bar)
    scrollframe:SetPoint('BOTTOMLEFT', bar, 'CENTER')
    scrollframe:SetPoint('TOPRIGHT')
    bar._scrollframe = scrollframe
    
    local scrollchild = CreateFrame('frame', nil, scrollframe)
    scrollframe:SetScrollChild(scrollchild)
    scrollchild:SetAllPoints(scrollframe)
    
    local wedge = scrollchild:CreateTexture()
    wedge:SetPoint('BOTTOMRIGHT', bar, 'CENTER')
    bar._wedge = wedge
    
    local textures = {
        bar:CreateTexture(),
        bar:CreateTexture(),
        bar:CreateTexture(),
        bar:CreateTexture()
    }
    
    textures[1]:SetPoint('BOTTOMLEFT', bar, 'CENTER')
    textures[1]:SetPoint('TOPRIGHT')
    textures[1]:SetTexCoord(0.5, 1, 0, 0.5)
    
    textures[2]:SetPoint('TOPLEFT', bar, 'CENTER')
    textures[2]:SetPoint('BOTTOMRIGHT')
    textures[2]:SetTexCoord(0.5, 1, 0.5, 1)
    
    textures[3]:SetPoint('TOPRIGHT', bar, 'CENTER')
    textures[3]:SetPoint('BOTTOMLEFT')
    textures[3]:SetTexCoord(0, 0.5, 0.5, 1)
    
    textures[4]:SetPoint('BOTTOMRIGHT', bar, 'CENTER')
    textures[4]:SetPoint('TOPLEFT')
    textures[4]:SetTexCoord(0, 0.5, 0, 0.5)
    
    bar._textures = textures
    bar._quadrant = nil
    bar._clockwise = true
    bar._reverse = false
    bar._aspect = 1
    bar:HookScript('OnSizeChanged', OnSizeChanged)
    
    for method, func in pairs(TextureFunctions) do
        bar[method] = func
    end
    bar.SetRadialStatusBarValue = SetRadialStatusBarValue
    
    local group = wedge:CreateAnimationGroup()
    local rotation = group:CreateAnimation('Rotation')
    bar._rotation = rotation
    rotation:SetDuration(0)
    rotation:SetEndDelay(1)
    rotation:SetOrigin('BOTTOMRIGHT', 0, 0)
    group:SetScript('OnPlay', OnPlay)
    group:Play()
    
    return bar
end

----------------------------------------------------------------------------------------
-- Portrait Update Logic
----------------------------------------------------------------------------------------

function RefineUI.UpdatePortrait(frame)
    if not frame or not frame.unit or not frame.DynamicPortrait then return end
    
    local portrait = frame.DynamicPortrait
    local unit = frame.unit
    local guid = UnitGUID(unit)
    local isAvailable = UnitIsConnected(unit) and UnitIsVisible(unit)
    
    -- Check for spell cast (highest priority)
    local castName, _, castTexture = UnitCastingInfo(unit)
    if not castName then
        castName, _, castTexture = UnitChannelInfo(unit)
    end
    
    if castName and castTexture then
        -- Show cast icon
        portrait:SetTexture(castTexture)
        portrait.currentState = 'cast'
        if portrait.RadialBar then
            portrait.RadialBar:Hide()
        end
    else
        -- Default to normal portrait
        SetPortraitTexture(portrait, unit)
        portrait.currentState = 'portrait'
        if portrait.RadialBar then
            portrait.RadialBar:Hide()
        end
    end
    
    portrait:Show()
    portrait.guid = guid
    portrait.state = isAvailable
end

----------------------------------------------------------------------------------------
-- Portrait Creation
----------------------------------------------------------------------------------------

function RefineUI.CreatePortrait(parentFrame)
    if not Config.UnitFrames.Portraits.Enable then return end
    
    -- Prevent duplicate creation
    if parentFrame.PortraitFrame then return parentFrame.PortraitFrame end
    
    local unit = parentFrame.unit
    local cfg = Config.UnitFrames.Portraits
    local anchorFrame = parentFrame.RefineStyle or parentFrame
    
    -- Create a frame to hold the portrait
    local PortraitFrame = CreateFrame("Frame", nil, parentFrame)
    RefineUI.AddAPI(PortraitFrame)
    PortraitFrame:Size(cfg.Size, cfg.Size)
    PortraitFrame:SetFrameLevel(anchorFrame:GetFrameLevel() + 15)
    PortraitFrame:SetFrameStrata("HIGH")
    
    -- Position based on unit type (Centered on edge)
    if unit == "player" or unit == "focus" or unit == "pet" then
        PortraitFrame:Point("CENTER", anchorFrame, "LEFT", 0, 0)
    elseif unit then
        PortraitFrame:Point("CENTER", anchorFrame, "RIGHT", 0, 0)
    else
        -- Default for non-unit frames
        PortraitFrame:Point("CENTER", anchorFrame, "RIGHT", 0, 0)
    end
    
    -- Background texture
    local BackgroundTexture = PortraitFrame:CreateTexture(nil, 'BACKGROUND')
    BackgroundTexture:SetAllPoints(PortraitFrame)
    BackgroundTexture:SetTexture(TEXTURE_PATH .. "PortraitBG.blp")
    BackgroundTexture:SetVertexColor(unpack(Config.General.BorderColor))
    BackgroundTexture:SetDrawLayer("BACKGROUND", 1)
    
    -- Portrait texture (2D)
    local portrait = PortraitFrame:CreateTexture(nil, 'ARTWORK')
    RefineUI.AddAPI(portrait)
    portrait:Size(cfg.InnerSize, cfg.InnerSize)
    portrait:Point('CENTER', PortraitFrame, 'CENTER')
    portrait:SetDrawLayer("ARTWORK", 2)
    
    -- Circular mask
    local mask = PortraitFrame:CreateMaskTexture()
    mask:SetTexture(TEXTURE_PATH .. "PortraitMask.blp")
    mask:SetAllPoints(PortraitFrame)
    portrait:AddMaskTexture(mask)
    
    -- Border texture
    local BorderTexture = PortraitFrame:CreateTexture(nil, 'OVERLAY')
    BorderTexture:SetAllPoints(PortraitFrame)
    BorderTexture:SetTexture(TEXTURE_PATH .. "PortraitBorder.blp")
    BorderTexture:SetVertexColor(unpack(Config.General.BorderColor))
    BorderTexture:SetDrawLayer("OVERLAY", 3)
    
    -- Create radial status bar for quest progress
    local RadialBar = CreateRadialStatusBar(PortraitFrame)
    RadialBar:SetAllPoints(PortraitFrame)
    RadialBar:SetTexture(TEXTURE_PATH .. "PortraitStatus.blp")
    RadialBar:SetVertexColor(1, 0.82, 0, 0.8) -- Gold for quest progress
    RadialBar:SetFrameLevel(PortraitFrame:GetFrameLevel() + 1)
    RadialBar:Hide()
    
    -- Store references
    portrait.RadialBar = RadialBar
    portrait.BorderTexture = BorderTexture
    portrait.currentState = 'portrait'
    
    parentFrame.DynamicPortrait = portrait
    parentFrame.PortraitFrame = PortraitFrame
    parentFrame.PortraitBorder = BorderTexture
    
    -- Register events for portrait updates if unit is available
    PortraitFrame:SetScript("OnEvent", function(self, event, eventUnit)
        local frameUnit = parentFrame.unit
        -- Unit-less events that apply to specific units
        if event == "PLAYER_TARGET_CHANGED" then
            if frameUnit == "target" or frameUnit == "targettarget" then
                RefineUI.UpdatePortrait(parentFrame)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if frameUnit == "focus" then
                RefineUI.UpdatePortrait(parentFrame)
            end
        elseif eventUnit == frameUnit or event == "PLAYER_ENTERING_WORLD" then
            RefineUI.UpdatePortrait(parentFrame)
        end
    end)
    
    PortraitFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    PortraitFrame:RegisterEvent("UNIT_MODEL_CHANGED")
    PortraitFrame:RegisterEvent("UNIT_CONNECTION")
    PortraitFrame:RegisterEvent("UNIT_SPELLCAST_START")
    PortraitFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    PortraitFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    PortraitFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    PortraitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    -- Register target/focus change events for those unit types
    if unit == "target" or unit == "targettarget" then
        PortraitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        PortraitFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    
    -- Initial update
    PortraitFrame:SetScript("OnShow", function()
        RefineUI.UpdatePortrait(parentFrame)
    end)
    
    if parentFrame:IsVisible() then
        RefineUI.UpdatePortrait(parentFrame)
    end

    return PortraitFrame
end

