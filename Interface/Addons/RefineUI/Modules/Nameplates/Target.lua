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
local GetRaidTargetIndex = GetRaidTargetIndex
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
    local isNameOnly = data.RefineHidden == true
    if RefineUI.IsNameOnlyNameplate then
        isNameOnly = RefineUI:IsNameOnlyNameplate(frame, data)
    end
    if RefineUI.UpdateNameplateRaidIconAnchor then
        RefineUI:UpdateNameplateRaidIconAnchor(frame, data, isNameOnly)
    end
    
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
            if isNameOnly then
                anchor = data.RefineName or frame.Name
                left:Show()
            else
                anchor = frame.healthBar or frame.Name
                left:Hide()
            end
            
            if anchor then
                local rightOffset = 4
                if (not isNameOnly) and frame.unit and GetRaidTargetIndex(frame.unit) then
                    rightOffset = rightOffset + 6
                end

                left:ClearAllPoints()
                RefineUI.Point(left, "RIGHT", anchor, "LEFT", -4, 0)
                
                right:ClearAllPoints()
                RefineUI.Point(right, "LEFT", anchor, "RIGHT", rightOffset, 0)
            end
        else
            data.TargetArrows:Hide()
        end
    end
    
    -- 4. Alpha (Opacity)
    local nonTargetAlpha = ClampAlpha(C.Nameplates and C.Nameplates.Alpha, 0.5)
    local noTargetAlpha = ClampAlpha(C.Nameplates and C.Nameplates.NoTargetAlpha, 1)
    local castingAlpha = ClampAlpha(C.Nameplates and C.Nameplates.CastAlpha, 0.75)
    local hasTarget = UnitExists("target")
    local finalAlpha

    if not hasTarget then
        finalAlpha = noTargetAlpha
    elseif isTarget then
        finalAlpha = 1
    else
        finalAlpha = nonTargetAlpha
        if data and data.isCasting == true and castingAlpha > finalAlpha then
            finalAlpha = castingAlpha
        end
    end

    if data.lastAppliedAlpha ~= finalAlpha or frame:GetAlpha() ~= finalAlpha then
        data.lastAppliedAlpha = finalAlpha
        frame:SetAlpha(finalAlpha)
    end
end
