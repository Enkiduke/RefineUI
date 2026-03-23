----------------------------------------------------------------------------------------
-- Nameplates Component: Targeting
-- Description: Handles Target Glow, Arrows, and Border Color
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end
local Config = RefineUI.Config
local MediaTextures = RefineUI.Media.Textures

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local type = type
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

local function GetTargetIndicatorColor()
    local fallback = { 1, 1, 1, 1 }
    local color = Config and Config.Nameplates and Config.Nameplates.TargetBorderColor
    if type(color) ~= "table" then
        color = fallback
    end

    return color[1] or fallback[1], color[2] or fallback[2], color[3] or fallback[3], color[4] or fallback[4]
end

----------------------------------------------------------------------------------------
-- Arrows
----------------------------------------------------------------------------------------
function RefineUI:CreateTargetArrows(frame)
    if not Config or not Config.Nameplates or not Config.Nameplates.TargetIndicator then return end
    
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
    local colorR, colorG, colorB = GetTargetIndicatorColor()
    local left = indicator:CreateTexture(nil, "OVERLAY")
    RefineUI.Size(left, arrowSize, arrowSize)
    left:SetTexture(MediaTextures.TargetArrowLeft) -- Pointing Right (at plate)
    left:SetVertexColor(colorR, colorG, colorB)

    local right = indicator:CreateTexture(nil, "OVERLAY")
    RefineUI.Size(right, arrowSize, arrowSize)
    right:SetTexture(MediaTextures.TargetArrowRight) -- Pointing Left (at plate)
    right:SetVertexColor(colorR, colorG, colorB)

    indicator.Left = left
    indicator.Right = right
    data.TargetArrows = indicator
end

----------------------------------------------------------------------------------------
-- Update Logic
----------------------------------------------------------------------------------------
function RefineUI:UpdateTarget(frame)
    if not frame or not frame.unit or (frame.IsForbidden and frame:IsForbidden()) then return end
    
    local data = RefineUI.NameplateData[frame]
    if not data then
        data = {}
        RefineUI.NameplateData[frame] = data
    end
    
    local previousTarget = data.isTarget
    local previousNameOnly = data.lastTargetNameOnly
    local isTarget = IsTargetNameplateUnitFrame(frame)
    data.isTarget = isTarget
    local isNameOnly = data.RefineHidden == true
    if RefineUI.IsNameOnlyNameplate then
        isNameOnly = RefineUI:IsNameOnlyNameplate(frame, data)
    end

    -- Raid icon anchoring is already refreshed by visibility and Blizzard raid-target/
    -- anchor hooks. Only reapply here when our name-only mode actually changed.
    if RefineUI.UpdateNameplateRaidIconAnchor and (previousNameOnly ~= isNameOnly or data.RaidIconAnchorMode == nil) then
        RefineUI:UpdateNameplateRaidIconAnchor(frame, data, isNameOnly)
    end
    data.lastTargetNameOnly = isNameOnly
    
    -- 1. Border Colors (Centralized)
    if (not isNameOnly) and RefineUI.UpdateBorderColors and previousTarget ~= isTarget then
        RefineUI:UpdateBorderColors(frame)
    end

    
    -- 3. Arrows
    if data and data.TargetArrows then
        if Config.Nameplates and Config.Nameplates.TargetIndicator == false then
            if data.TargetArrowsShown ~= false then
                data.TargetArrows:Hide()
                data.TargetArrowsShown = false
                data.TargetArrowAnchor = nil
            end
        elseif isTarget then
            if data.TargetArrowsShown ~= true then
                data.TargetArrows:Show()
                data.TargetArrowsShown = true
            end
            
            -- Dynamic Positioning based on enabled elements
            local left = data.TargetArrows.Left
            local right = data.TargetArrows.Right

            local anchor
            local showLeft = false
            if isNameOnly then
                anchor = data.RefineName or frame.Name
                showLeft = true
            else
                anchor = frame.healthBar or frame.Name
            end

            if left and data.TargetArrowLeftShown ~= showLeft then
                left:SetShown(showLeft)
                data.TargetArrowLeftShown = showLeft
            end
            
            if anchor then
                local rightOffset = 4
                if (not isNameOnly) and frame.unit and GetRaidTargetIndex(frame.unit) then
                    rightOffset = rightOffset + 6
                end

                if data.TargetArrowAnchor ~= anchor
                    or data.TargetArrowRightOffset ~= rightOffset
                    or data.TargetArrowNameOnly ~= isNameOnly then
                    left:ClearAllPoints()
                    RefineUI.Point(left, "RIGHT", anchor, "LEFT", -4, 0)
                    
                    right:ClearAllPoints()
                    RefineUI.Point(right, "LEFT", anchor, "RIGHT", rightOffset, 0)

                    data.TargetArrowAnchor = anchor
                    data.TargetArrowRightOffset = rightOffset
                    data.TargetArrowNameOnly = isNameOnly
                end
            end
        else
            if data.TargetArrowsShown ~= false then
                data.TargetArrows:Hide()
                data.TargetArrowsShown = false
                data.TargetArrowAnchor = nil
            end
        end
    end
    
    -- 4. Alpha (Opacity)
    local nonTargetAlpha = ClampAlpha(Config.Nameplates and Config.Nameplates.Alpha, 0.5)
    local noTargetAlpha = ClampAlpha(Config.Nameplates and Config.Nameplates.NoTargetAlpha, 1)
    local castingAlpha = ClampAlpha(Config.Nameplates and Config.Nameplates.CastAlpha, 0.75)
    local hasTarget = UnitExists("target")
    local finalAlpha

    if not hasTarget then
        finalAlpha = noTargetAlpha
    elseif isTarget then
        finalAlpha = 1
    else
        finalAlpha = nonTargetAlpha
        if (not isNameOnly) and data and data.isCasting == true and castingAlpha > finalAlpha then
            finalAlpha = castingAlpha
        end
    end

    if data.lastAppliedAlpha ~= finalAlpha or frame:GetAlpha() ~= finalAlpha then
        data.lastAppliedAlpha = finalAlpha
        frame:SetAlpha(finalAlpha)
    end
end

