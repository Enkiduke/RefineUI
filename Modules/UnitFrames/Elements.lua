----------------------------------------------------------------------------------------
-- RefineUI UnitFrames Elements
-- Description: Shared helper functions and elements for UnitFrames.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

-- Global/Local Imports
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHealth = UnitHealth
local tonumber = tonumber
local issecretvalue = _G.issecretvalue
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitIsUnit = UnitIsUnit
local unpack = unpack
local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent
local type = type
local tostring = tostring

local ELEMENTS_STATE_REGISTRY = "UnitFramesElementsState"

local function GetElementState(owner, key, defaultValue)
    return RefineUI:RegistryGet(ELEMENTS_STATE_REGISTRY, owner, key, defaultValue)
end

local function SetElementState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(ELEMENTS_STATE_REGISTRY, owner, key)
    else
        RefineUI:RegistrySet(ELEMENTS_STATE_REGISTRY, owner, key, value)
    end
end

local function BuildElementHookKey(owner, method)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    return "UnitFramesElements:" .. ownerId .. ":" .. method
end

-- Cache Player Class Color
local _, myClass = UnitClass("player")
local MyClassColor = RefineUI.Colors.Class[myClass]
RefineUI.MyClassColor = MyClassColor -- Share globally for other modules

----------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------
function UF.GetUnitHealthColor(unit)
    if not unit or not UnitExists(unit) then 
        return unpack(Config.UnitFrames.Bars.HealthColor) 
    end
    
    if UnitIsPlayer(unit) and Config.UnitFrames.Bars.UseClassColor then
        if UnitIsUnit(unit, "player") and MyClassColor then
            return MyClassColor.r, MyClassColor.g, MyClassColor.b
        end
        local _, class = UnitClass(unit)
        local color = RefineUI.Colors.Class[class]
        if color then return color.r, color.g, color.b end
    elseif Config.UnitFrames.Bars.UseReactionColor then
        if UnitIsTapDenied(unit) then
            return 0.5, 0.5, 0.5
        end
        local reaction = UnitReaction(unit, "player")
        if reaction then
             local color = RefineUI.Colors.Reaction[reaction]
             if color then return color.r, color.g, color.b end
        end
    end
    
    return unpack(Config.UnitFrames.Bars.HealthColor)
end

function UF.GetUnitPowerColor(unit)
    if not unit or not UnitExists(unit) then 
        return unpack(Config.UnitFrames.Bars.ManaColor) 
    end
    
    if Config.UnitFrames.Bars.UsePowerColor then
        local _, powerToken = UnitPowerType(unit)
        local color = RefineUI.Colors.Power[powerToken]
        if color then return color.r, color.g, color.b end
    end
    
    return unpack(Config.UnitFrames.Bars.ManaColor)
end

----------------------------------------------------------------------------------------
-- Custom Text
----------------------------------------------------------------------------------------
local function UpdateCustomHPText(hpContainer, unit)
    if not UnitIsConnected(unit) then
        hpContainer.CustomPercentText:SetText("OFFLINE")
        hpContainer.CustomCurrentText:SetText("OFFLINE")
        hpContainer.CustomPercentText:SetTextColor(0.5, 0.5, 0.5)
        hpContainer.CustomCurrentText:SetTextColor(0.5, 0.5, 0.5)
    elseif UnitIsDeadOrGhost(unit) then
        hpContainer.CustomPercentText:SetText("DEAD")
        hpContainer.CustomCurrentText:SetText("DEAD")
        hpContainer.CustomPercentText:SetTextColor(0.5, 0.5, 0.5)
        hpContainer.CustomCurrentText:SetTextColor(0.5, 0.5, 0.5)
    else
        local scale = RefineUI.ScaleTo100 or 1.0
        
        -- WoW 12.0+: Use Percent Curve for health
        local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
        hpContainer.CustomPercentText:SetText(percent) -- Pass directly (engine handles secrets)
        
        -- Safe Current Health
        local hp = UnitHealth(unit)
        hpContainer.CustomCurrentText:SetText(hp) -- Pass directly (engine handles secrets)
        
        hpContainer.CustomPercentText:SetTextColor(1, 1, 1)
        hpContainer.CustomCurrentText:SetTextColor(1, 1, 1)
    end
end

local function GetPlayerManaOverlayBar()
    local playerFrame = _G.PlayerFrame
    if not playerFrame or not RefineUI.UnitFrameData then
        return nil
    end

    local data = RefineUI.UnitFrameData[playerFrame]
    local overlayData = data and data.RefinePlayerManaOverlay
    return overlayData and overlayData.Bar or nil
end

local function SyncManaTextParent(manaBar, unit)
    if not manaBar or not manaBar.CustomPercentText then return end

    local desiredParent = manaBar
    if unit == "player" and UF.IsPlayerSecondaryPowerSwapActive and UF.IsPlayerSecondaryPowerSwapActive() then
        local overlayBar = GetPlayerManaOverlayBar()
        if overlayBar then
            desiredParent = overlayBar
        end
    end

    if manaBar.CustomPercentText:GetParent() ~= desiredParent then
        manaBar.CustomPercentText:SetParent(desiredParent)
    end
end

local function UpdateCustomManaText(manaBar, unit)
    SyncManaTextParent(manaBar, unit)

    -- WoW 12.0+: Use Percent Curve for power
    local powerType
    if unit == "player" and UF.IsPlayerSecondaryPowerSwapActive and UF.IsPlayerSecondaryPowerSwapActive() then
        powerType = Enum.PowerType.Mana
    end

    local percent = UnitPowerPercent(unit, powerType, false, RefineUI.GetPercentCurve())
    manaBar.CustomPercentText:SetText(percent) -- Pass directly (engine handles secrets)
end

local function GetFrameContainers(frame)
    -- Helper to find containers safely
    local content = frame.PlayerFrameContent or frame.TargetFrameContent
    if not content then return end
    local contentMain = content.PlayerFrameContentMain or content.TargetFrameContentMain
    if not contentMain then return end
    local hpContainer = contentMain.HealthBarsContainer
    local manaBar = contentMain.ManaBarArea and contentMain.ManaBarArea.ManaBar or contentMain.ManaBar
    return content, contentMain, hpContainer, manaBar
end
UF.GetFrameContainers = GetFrameContainers

function UF.CreateCustomText(frame)
    local _, _, hpContainer, manaBar = GetFrameContainers(frame)
    if not hpContainer then return end
    local unit = frame.unit or "player"
    local uConf = Config.UnitFrames

    -- Hide default texts
    for _, text in pairs({hpContainer.LeftText, hpContainer.RightText, hpContainer.HealthBarText, hpContainer.DeadText}) do
        if text then
            text:SetAlpha(0)
            if not GetElementState(text, "hiddenHook", false) then
                RefineUI:HookOnce(BuildElementHookKey(text, "SetAlpha"), text, "SetAlpha", function(self, alpha)
                    if alpha ~= 0 then self:SetAlpha(0) end
                end)
                SetElementState(text, "hiddenHook", true)
            end
        end
    end

    local cfg = Config.UnitFrames.Fonts
    
    -- Retrieve external data to access RefineUF
    local data = RefineUI.UnitFrameData and RefineUI.UnitFrameData[frame]
    local refineUF = data and data.RefineUF
    
    -- Custom HP Percent
    if not hpContainer.CustomPercentText then
        hpContainer.CustomPercentText = hpContainer:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(hpContainer.CustomPercentText, cfg.HPSize)
        
        local parentTex = refineUF and refineUF.Texture or frame
        hpContainer.CustomPercentText:SetPoint("CENTER", parentTex, "CENTER", 0, 8)
    end

    -- Custom HP Current
    if not hpContainer.CustomCurrentText then
        hpContainer.CustomCurrentText = hpContainer:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(hpContainer.CustomCurrentText, cfg.HPSize)
        
        local parentTex = refineUF and refineUF.Texture or frame
        hpContainer.CustomCurrentText:SetPoint("CENTER", parentTex, "CENTER", 0, 8)
        hpContainer.CustomCurrentText:SetAlpha(0)
    end

    -- Mana Text
    if manaBar then
        for _, text in pairs({manaBar.LeftText, manaBar.RightText, manaBar.ManaBarText}) do
            if text then
                text:SetAlpha(0)
                if not GetElementState(text, "hiddenHook", false) then
                    RefineUI:HookOnce(BuildElementHookKey(text, "SetAlpha"), text, "SetAlpha", function(self, alpha)
                        if alpha ~= 0 then self:SetAlpha(0) end
                    end)
                    SetElementState(text, "hiddenHook", true)
                end
            end
        end

        if not manaBar.CustomPercentText then
            manaBar.CustomPercentText = manaBar:CreateFontString(nil, "OVERLAY")
            RefineUI.Font(manaBar.CustomPercentText, cfg.ManaSize)
            
            local parentTex = refineUF and refineUF.Texture or frame
            manaBar.CustomPercentText:SetPoint("CENTER", parentTex, "CENTER", 2, -6)
            manaBar.CustomPercentText:SetAlpha(0)
        end
    end

    -- Event Handling via Core/Events.lua
    if not GetElementState(hpContainer, "eventsRegistered", false) then
         local function OnHealthEvent(event, u)
             if u == unit then UpdateCustomHPText(hpContainer, unit) end
         end
         
         -- Initial update
         UpdateCustomHPText(hpContainer, unit)
         
         RefineUI:OnEvents({"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION"}, OnHealthEvent, "RefineUF_HP_"..unit)
         
         if frame == TargetFrame then
             RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function() UpdateCustomHPText(hpContainer, frame.unit) end, "RefineUF_TGT_HP")
         elseif frame == FocusFrame then
             RefineUI:RegisterEventCallback("PLAYER_FOCUS_CHANGED", function() UpdateCustomHPText(hpContainer, frame.unit) end, "RefineUF_FOC_HP")
         end

         SetElementState(hpContainer, "eventsRegistered", true)
    end

    if manaBar and not GetElementState(manaBar, "eventsRegistered", false) then
        local function OnPowerEvent(event, u)
             if u == unit then UpdateCustomManaText(manaBar, unit) end
         end
         
          UpdateCustomManaText(manaBar, unit)
          
          RefineUI:OnEvents({"UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER"}, OnPowerEvent, "RefineUF_PP_"..unit)
         
         if frame == TargetFrame then
             RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function() UpdateCustomManaText(manaBar, frame.unit) end, "RefineUF_TGT_MP")
         elseif frame == FocusFrame then
             RefineUI:RegisterEventCallback("PLAYER_FOCUS_CHANGED", function() UpdateCustomManaText(manaBar, frame.unit) end, "RefineUF_FOC_MP")
         end
         
         SetElementState(manaBar, "eventsRegistered", true)
    end

    -- Hover Hooks
    if not GetElementState(frame, "refineHoverHooked", false) then
        local function OnEnter()
            hpContainer.CustomPercentText:SetAlpha(0)
            hpContainer.CustomCurrentText:SetAlpha(1)
            if manaBar then manaBar.CustomPercentText:SetAlpha(1) end
        end
        local function OnLeave()
            hpContainer.CustomPercentText:SetAlpha(1)
            hpContainer.CustomCurrentText:SetAlpha(0)
            if manaBar then manaBar.CustomPercentText:SetAlpha(0) end
        end

        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
        if hpContainer.HealthBar then
             hpContainer.HealthBar:HookScript("OnEnter", OnEnter)
             hpContainer.HealthBar:HookScript("OnLeave", OnLeave)
        end
        if manaBar then
             manaBar:HookScript("OnEnter", OnEnter)
             manaBar:HookScript("OnLeave", OnLeave)
        end
        SetElementState(frame, "refineHoverHooked", true)
    end
end

----------------------------------------------------------------------------------------
-- Auras
----------------------------------------------------------------------------------------
function UF.StyleAuraIcon(button)
    if not button or button:IsForbidden() or GetElementState(button, "refineUIHooked", false) then return end
    
    RefineUI.CreateBorder(button, 2, 2, 8)
    
    if button.Border then
        button.Border:Hide()
        RefineUI:HookOnce(BuildElementHookKey(button.Border, "Show"), button.Border, "Show", function(self) self:Hide() end)
    end
    
    if button.Stealable then
        button.Stealable:Hide()
        RefineUI:HookOnce(BuildElementHookKey(button.Stealable, "Show"), button.Stealable, "Show", function(self) self:Hide() end)
    end

    if not GetElementState(button, "refineUISizeHook", false) then
        RefineUI:HookOnce(BuildElementHookKey(button, "SetSize"), button, "SetSize", function(self, width, height)
            if GetElementState(self, "refineUISizing", false) then return end
            SetElementState(self, "refineUISizing", true)
            
            local auras = Config.UnitFrames.Auras
            local isLarge = width > 20
            local newSize = isLarge and auras.LargeSize or auras.Size
            
            self:SetSize(newSize, newSize)
            SetElementState(self, "refineUISizing", nil)
        end)
        SetElementState(button, "refineUISizeHook", true)
    end

    SetElementState(button, "refineUIHooked", true)
end

function UF.UpdateUnitAuras(frame)
    if not frame or not frame.auraPools then return end
    
    local _, _, hpContainer = GetFrameContainers(frame)
    if not hpContainer then return end

    for button in frame.auraPools:EnumerateActive() do
        UF.StyleAuraIcon(button)
        
        local point, rel, relPoint, x, y = button:GetPoint()
        
        -- Robust check for the "Head" aura (anchored to portrait/frame instead of another aura)
        local isAnchor = false
        if rel and rel:IsObjectType("Texture") then
            if frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual and rel:GetParent() == frame.TargetFrameContent.TargetFrameContentContextual then
                 isAnchor = true
            else
                local atlas = rel:GetAtlas()
                if atlas and (atlas:find("Target") or atlas:find("Portrait")) then
                    isAnchor = true
                end
            end
        end

        if isAnchor then
            button:ClearAllPoints()
            -- FIXED OFFSET: 4 (x), -40 (y). Change these values to move the entire block.
            if Config.UnitFrames.Auras.BuffsOnTop then
                 button:SetPoint("BOTTOMLEFT", hpContainer, "TOPLEFT", 0, 4)
            else
                 button:SetPoint(point, hpContainer, "BOTTOMLEFT", 0, 35)
            end
        elseif rel and rel:IsObjectType("Button") and rel:GetParent() == button:GetParent() then
            -- NEIGHBOR SPACING: Controls the gap between icons.
            local spacing = Config.UnitFrames.Auras.Spacing or 4
            
            -- Preserve direction (horizontal vs vertical wrap)
            -- If x was positive, keep it positive but use new spacing. Same for y.
            local newX = (x == 0) and 0 or (x > 0 and spacing or -spacing)
            local newY = (y == 0) and 0 or (y > 0 and spacing or -spacing)
            
            button:ClearAllPoints()
            button:SetPoint(point, rel, relPoint, newX, newY)
        end

        local size = button:GetWidth()
        local isLarge = size > 20 or size == 0
        local newSize = isLarge and Config.UnitFrames.Auras.LargeSize or Config.UnitFrames.Auras.Size
        button:SetSize(newSize, newSize)
    end
end
