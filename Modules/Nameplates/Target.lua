----------------------------------------------------------------------------------------
-- Target Effects for RefineUI Nameplates
-- Description: Handles Target Glow, Arrows, and Border Color
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local C = RefineUI.Config
local M = RefineUI.Media.Textures

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local unpack = unpack
local tonumber = tonumber
local UnitExists = UnitExists
local CreateFrame = CreateFrame
local NameplatesUtil = RefineUI.NameplatesUtil
local IsTargetNameplateUnitFrame = NameplatesUtil.IsTargetNameplateUnitFrame

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ClampAlpha(value, fallback)
    local alpha = tonumber(value)
    if not alpha then
        alpha = fallback
    end
    if alpha < 0 then
        return 0
    end
    if alpha > 1 then
        return 1
    end
    return alpha
end


----------------------------------------------------------------------------------------
-- Arrows
----------------------------------------------------------------------------------------
function RefineUI:CreateTargetArrows(frame)
    if not C.Nameplates.TargetIndicator then return end
    
    local data = RefineUI.NameplateData[frame]
    if not data then 
        data = {}
        RefineUI.NameplateData[frame] = data
    end

    if data.TargetArrows then return end
    
    local indicator = CreateFrame("Frame", nil, frame)
    RefineUI.SetInside(indicator, frame, 0, 0)
    indicator:SetFrameLevel(frame:GetFrameLevel() + 4)
    indicator:Hide()

    local arrowSize = RefineUI:Scale(24)
    local left = indicator:CreateTexture(nil, "OVERLAY")
    RefineUI.Size(left, arrowSize, arrowSize)
    left:SetTexture(M.TargetArrowLeft) -- Pointing Right (at plate)
    left:SetVertexColor(unpack(C.Nameplates.TargetBorderColor))

    local right = indicator:CreateTexture(nil, "OVERLAY")
    RefineUI.Size(right, arrowSize, arrowSize)
    right:SetTexture(M.TargetArrowRight) -- Pointing Left (at plate)
    right:SetVertexColor(unpack(C.Nameplates.TargetBorderColor))

    indicator.Left = left
    indicator.Right = right
    data.TargetArrows = indicator
end

----------------------------------------------------------------------------------------
-- Update Logic
----------------------------------------------------------------------------------------
function RefineUI:UpdateTarget(frame)
    if not frame or not frame.unit then return end
    
    local data = RefineUI.NameplateData[frame]
    if not data then
        data = {}
        RefineUI.NameplateData[frame] = data
    end
    
    local isTarget = IsTargetNameplateUnitFrame(frame)
    data.isTarget = isTarget
    
    -- 1. Border Colors (Centralized)
    if RefineUI.UpdateBorderColors then
        RefineUI:UpdateBorderColors(frame)
    end

    
    -- 3. Arrows
    if data and data.TargetArrows then
        if C.Nameplates and C.Nameplates.TargetIndicator == false then
            data.TargetArrows:Hide()
        elseif isTarget then
            data.TargetArrows:Show()
            
            -- Dynamic Positioning based on enabled elements
            local left = data.TargetArrows.Left
            local right = data.TargetArrows.Right
            
            local anchor
            if data.RefineHidden then
                anchor = data.RefineName or frame.Name
                left:Show()
            else
                anchor = frame.healthBar or frame.Name
                left:Hide()
            end
            
            if anchor then
                left:ClearAllPoints()
                RefineUI.Point(left, "RIGHT", anchor, "LEFT", -4, 0)
                
                right:ClearAllPoints()
                RefineUI.Point(right, "LEFT", anchor, "RIGHT", 4, 0)
            end
        else
            data.TargetArrows:Hide()
        end
    end
    
    -- 4. Alpha (Opacity)
    local nonTargetAlpha = ClampAlpha(C.Nameplates and C.Nameplates.Alpha, 0.6)
    local noTargetAlpha = ClampAlpha(C.Nameplates and C.Nameplates.NoTargetAlpha, 1)

    if UnitExists("target") then
        if isTarget then
            frame:SetAlpha(1)
        elseif data and data.RefineHidden then
            -- Name-only plates should remain fully readable.
            frame:SetAlpha(1)
        else
            frame:SetAlpha(nonTargetAlpha)
        end
    else
        frame:SetAlpha(noTargetAlpha)
    end
end
