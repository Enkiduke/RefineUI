----------------------------------------------------------------------------------------
-- UnitFrames Component: Portraits
-- Description: Portrait creation and updates for UnitFrames.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local select = select
local unpack = unpack
local pairs = pairs
local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local SetPortraitTexture = SetPortraitTexture
local math = math

local TEXTURE_PATH = "Interface\\AddOns\\RefineUI\\Media\\Textures\\"

----------------------------------------------------------------------------------------
-- Radial Statusbar Functions
----------------------------------------------------------------------------------------
local cos, sin, pi2, halfpi = math.cos, math.sin, math.rad(360), math.rad(90)

local function TransformTexture(tx, x, y, angle, aspect)
    local c, s = cos(angle), sin(angle)
    local y2, oy = y / aspect, 0.5 / aspect
    local ulx, uly = 0.5 + (x - 0.5) * c - (y2 - oy) * s, (oy + (y2 - oy) * c + (x - 0.5) * s) * aspect
    local llx, lly = 0.5 + (x - 0.5) * c - (y2 + oy) * s, (oy + (y2 + oy) * c + (x - 0.5) * s) * aspect
    local urx, ury = 0.5 + (x + 0.5) * c - (y2 - oy) * s, (oy + (y2 - oy) * c + (x + 0.5) * s) * aspect
    local lrx, lry = 0.5 + (x + 0.5) * c - (y2 + oy) * s, (oy + (y2 + oy) * c + (x + 0.5) * s) * aspect
    tx:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function OnPlayUpdate(self)
    self:SetScript("OnUpdate", nil)
    self:Pause()
end

local function OnPlay(self)
    self:SetScript("OnUpdate", OnPlayUpdate)
end

local function SetRadialStatusBarValue(self, value)
    value = math.max(0, math.min(1, value))
    if self._reverse then
        value = 1 - value
    end

    local q = self._clockwise and (1 - value) or value
    local quadrant = q >= 0.75 and 1 or q >= 0.5 and 2 or q >= 0.25 and 3 or 4

    if self._quadrant ~= quadrant then
        self._quadrant = quadrant
        for i = 1, 4 do
            self._textures[i]:SetShown(self._clockwise and i < quadrant or (not self._clockwise and i > quadrant))
        end
        self._scrollframe:SetAllPoints(self._textures[quadrant])
    end

    local rads = value * pi2
    if not self._clockwise then
        rads = -rads + halfpi
    end
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
    SetTexture = CreateTextureFunction("SetTexture"),
    SetBlendMode = CreateTextureFunction("SetBlendMode"),
    SetVertexColor = CreateTextureFunction("SetVertexColor"),
}

local function CreateRadialStatusBar(parent)
    local bar = CreateFrame("Frame", nil, parent)

    local scrollFrame = CreateFrame("ScrollFrame", nil, bar)
    scrollFrame:SetPoint("BOTTOMLEFT", bar, "CENTER")
    scrollFrame:SetPoint("TOPRIGHT")
    bar._scrollframe = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetAllPoints(scrollFrame)

    local wedge = scrollChild:CreateTexture()
    wedge:SetPoint("BOTTOMRIGHT", bar, "CENTER")
    bar._wedge = wedge

    local textures = {
        bar:CreateTexture(),
        bar:CreateTexture(),
        bar:CreateTexture(),
        bar:CreateTexture(),
    }

    textures[1]:SetPoint("BOTTOMLEFT", bar, "CENTER")
    textures[1]:SetPoint("TOPRIGHT")
    textures[1]:SetTexCoord(0.5, 1, 0, 0.5)

    textures[2]:SetPoint("TOPLEFT", bar, "CENTER")
    textures[2]:SetPoint("BOTTOMRIGHT")
    textures[2]:SetTexCoord(0.5, 1, 0.5, 1)

    textures[3]:SetPoint("TOPRIGHT", bar, "CENTER")
    textures[3]:SetPoint("BOTTOMLEFT")
    textures[3]:SetTexCoord(0, 0.5, 0.5, 1)

    textures[4]:SetPoint("BOTTOMRIGHT", bar, "CENTER")
    textures[4]:SetPoint("TOPLEFT")
    textures[4]:SetTexCoord(0, 0.5, 0, 0.5)

    bar._textures = textures
    bar._quadrant = nil
    bar._clockwise = true
    bar._reverse = false
    bar._aspect = 1
    bar:HookScript("OnSizeChanged", OnSizeChanged)

    for method, func in pairs(TextureFunctions) do
        bar[method] = func
    end
    bar.SetRadialStatusBarValue = SetRadialStatusBarValue

    local group = wedge:CreateAnimationGroup()
    local rotation = group:CreateAnimation("Rotation")
    bar._rotation = rotation
    rotation:SetDuration(0)
    rotation:SetEndDelay(1)
    rotation:SetOrigin("BOTTOMRIGHT", 0, 0)
    group:SetScript("OnPlay", OnPlay)
    group:Play()

    return bar
end

----------------------------------------------------------------------------------------
-- Portrait Data
----------------------------------------------------------------------------------------
local function GetPortraitData(frame)
    local data = UnitFrames:GetFrameData(frame)
    data.Portrait = data.Portrait or {}
    return data.Portrait
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function UnitFrames:UpdatePortrait(frame)
    if not frame or not frame.unit then
        return
    end

    local portraitData = GetPortraitData(frame)
    local portrait = portraitData.Texture
    if not portrait then
        return
    end

    local unit = frame.unit
    local guid = UnitGUID(unit)
    local isAvailable = UnitIsConnected(unit) and UnitIsVisible(unit)

    local castName, _, castTexture = UnitCastingInfo(unit)
    if not castName then
        castName, _, castTexture = UnitChannelInfo(unit)
    end

    if castName and castTexture then
        portrait:SetTexture(castTexture)
        portrait.currentState = "cast"
        if portraitData.RadialBar then
            portraitData.RadialBar:Hide()
        end
    else
        SetPortraitTexture(portrait, unit)
        portrait.currentState = "portrait"
        if portraitData.RadialBar then
            portraitData.RadialBar:Hide()
        end
    end

    portrait:Show()
    portrait.guid = guid
    portrait.state = isAvailable
end

function UnitFrames:CreatePortrait(parentFrame)
    if not Config.UnitFrames.Portraits.Enable then
        return nil
    end

    local portraitData = GetPortraitData(parentFrame)
    if portraitData.Frame then
        return portraitData.Frame
    end

    local unit = parentFrame.unit
    local cfg = Config.UnitFrames.Portraits
    local anchorFrame = parentFrame.RefineStyle or parentFrame

    local portraitFrame = CreateFrame("Frame", nil, parentFrame)
    RefineUI.AddAPI(portraitFrame)
    portraitFrame:Size(cfg.Size, cfg.Size)
    portraitFrame:SetFrameLevel(anchorFrame:GetFrameLevel() + 15)
    portraitFrame:SetFrameStrata("HIGH")

    if unit == "player" or unit == "focus" or unit == "pet" then
        portraitFrame:Point("CENTER", anchorFrame, "LEFT", 0, 0)
    else
        portraitFrame:Point("CENTER", anchorFrame, "RIGHT", 0, 0)
    end

    local backgroundTexture = portraitFrame:CreateTexture(nil, "BACKGROUND")
    backgroundTexture:SetAllPoints(portraitFrame)
    backgroundTexture:SetTexture(TEXTURE_PATH .. "PortraitBG.blp")
    backgroundTexture:SetVertexColor(unpack(Config.General.BorderColor))
    backgroundTexture:SetDrawLayer("BACKGROUND", 1)

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    RefineUI.AddAPI(portrait)
    portrait:Size(cfg.InnerSize, cfg.InnerSize)
    portrait:Point("CENTER", portraitFrame, "CENTER")
    portrait:SetDrawLayer("ARTWORK", 2)

    local mask = portraitFrame:CreateMaskTexture()
    mask:SetTexture(TEXTURE_PATH .. "PortraitMask.blp")
    mask:SetAllPoints(portraitFrame)
    portrait:AddMaskTexture(mask)

    local borderTexture = portraitFrame:CreateTexture(nil, "OVERLAY")
    borderTexture:SetAllPoints(portraitFrame)
    borderTexture:SetTexture(TEXTURE_PATH .. "PortraitBorder.blp")
    borderTexture:SetVertexColor(unpack(Config.General.BorderColor))
    borderTexture:SetDrawLayer("OVERLAY", 3)

    local radialBar = CreateRadialStatusBar(portraitFrame)
    radialBar:SetAllPoints(portraitFrame)
    radialBar:SetTexture(TEXTURE_PATH .. "PortraitStatus.blp")
    radialBar:SetVertexColor(1, 0.82, 0, 0.8)
    radialBar:SetFrameLevel(portraitFrame:GetFrameLevel() + 1)
    radialBar:Hide()

    portrait.RadialBar = radialBar
    portrait.BorderTexture = borderTexture
    portrait.currentState = "portrait"

    portraitData.Frame = portraitFrame
    portraitData.Texture = portrait
    portraitData.BorderTexture = borderTexture
    portraitData.RadialBar = radialBar

    portraitFrame:SetScript("OnEvent", function(_, event, eventUnit)
        local frameUnit = parentFrame.unit
        if event == "PLAYER_TARGET_CHANGED" then
            if frameUnit == "target" or frameUnit == "targettarget" then
                UnitFrames:UpdatePortrait(parentFrame)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if frameUnit == "focus" then
                UnitFrames:UpdatePortrait(parentFrame)
            end
        elseif eventUnit == frameUnit or event == "PLAYER_ENTERING_WORLD" then
            UnitFrames:UpdatePortrait(parentFrame)
        end
    end)

    portraitFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    portraitFrame:RegisterEvent("UNIT_MODEL_CHANGED")
    portraitFrame:RegisterEvent("UNIT_CONNECTION")
    portraitFrame:RegisterEvent("UNIT_SPELLCAST_START")
    portraitFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
    portraitFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    portraitFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    portraitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if unit == "target" or unit == "targettarget" then
        portraitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        portraitFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end

    portraitFrame:SetScript("OnShow", function()
        UnitFrames:UpdatePortrait(parentFrame)
    end)

    if parentFrame:IsVisible() then
        UnitFrames:UpdatePortrait(parentFrame)
    end

    return portraitFrame
end
