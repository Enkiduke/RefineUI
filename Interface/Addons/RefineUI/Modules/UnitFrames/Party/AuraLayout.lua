----------------------------------------------------------------------------------------
-- UnitFrames Party: Aura Layout
-- Description: Grid direction, aura spacing, carrier frames, and important-buff
--              anchor layout for Compact Party/Raid frames.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config
local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local strfind = string.find
local abs = math.abs
local floor = math.floor
local tinsert = table.insert
local tsort = table.sort
local wipe = wipe

local GetPartyData     = P.GetData
local GetPartyAuraData = P.GetAuraData
local BuildPartyHookKey = P.BuildHookKey
local IsUnreadableNumber = P.IsUnreadableNumber
local GetSafeFrameLevel  = P.GetSafeFrameLevel
local GetSafeFrameStrata = P.GetSafeFrameStrata
local IsPartyRaidCompactFrame = P.IsCompactFrame

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPACT_AURA_CONTAINER_BUFF   = "Buffs"
local COMPACT_AURA_CONTAINER_DEBUFF = "Debuffs"
local COMPACT_AURA_CONTAINER_DISPEL = "Dispel"

local DEFAULT_COMPACT_AURA_ICON_SPACING = 2

local COMPACT_GRID_DIRECTION_FALLBACK = {
    TopRightToBottomLeft = { x = -1, y = -1, isVertical = false },
    BottomRightToTopLeft = { x = -1, y = 1, isVertical = false },
    BottomLeftToTopRight = { x = 1, y = 1, isVertical = false },
    RightToLeft = { x = -1, y = 0, isVertical = false },
    LeftToRight = { x = 1, y = 0, isVertical = false },
}

local importantByFrameScratch = {}
local importantLayoutTokenParts = {}

local function WipeTable(tbl)
    if wipe then
        wipe(tbl)
        return tbl
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

----------------------------------------------------------------------------------------
-- Aura Icon Spacing
----------------------------------------------------------------------------------------
local function GetCompactAuraIconSpacing()
    local spacing = DEFAULT_COMPACT_AURA_ICON_SPACING
    local aurasConfig = Config and Config.UnitFrames and Config.UnitFrames.Auras
    if type(aurasConfig) == "table" then
        local configured = aurasConfig.CompactPartyRaidSpacing
        if type(configured) == "number" then
            spacing = configured
        elseif type(aurasConfig.Spacing) == "number" and aurasConfig.Spacing > 0 then
            spacing = aurasConfig.Spacing
        end
    end
    if spacing < 0 then
        spacing = 0
    end
    return spacing
end

----------------------------------------------------------------------------------------
-- Grid Direction
----------------------------------------------------------------------------------------
local function GetCompactGridDirection(directionName)
    local gridLayoutMixin = _G.GridLayoutMixin
    local directions = gridLayoutMixin and gridLayoutMixin.Direction
    if type(directions) == "table" and type(directions[directionName]) == "table" then
        return directions[directionName]
    end
    return COMPACT_GRID_DIRECTION_FALLBACK[directionName]
end

----------------------------------------------------------------------------------------
-- Container Resolution
----------------------------------------------------------------------------------------
local function ResolveCompactAuraContainerInfo(ownerFrame, auraFrame)
    if not ownerFrame or not auraFrame then
        return nil, nil
    end

    if type(ownerFrame.buffFrames) == "table" then
        for index, candidate in ipairs(ownerFrame.buffFrames) do
            if candidate == auraFrame then
                return COMPACT_AURA_CONTAINER_BUFF, index
            end
        end
    end

    if type(ownerFrame.debuffFrames) == "table" then
        for index, candidate in ipairs(ownerFrame.debuffFrames) do
            if candidate == auraFrame then
                return COMPACT_AURA_CONTAINER_DEBUFF, index
            end
        end
    end

    if type(ownerFrame.dispelDebuffFrames) == "table" then
        for index, candidate in ipairs(ownerFrame.dispelDebuffFrames) do
            if candidate == auraFrame then
                return COMPACT_AURA_CONTAINER_DISPEL, index
            end
        end
    end

    return nil, nil
end

----------------------------------------------------------------------------------------
-- Layout Spec Resolution
----------------------------------------------------------------------------------------
local function GetCompactAuraLayoutSpec(ownerFrame, containerType)
    if not ownerFrame or not containerType then
        return nil
    end

    local enum = _G.Enum and _G.Enum.RaidAuraOrganizationType
    local legacyType = enum and enum.Legacy
    local buffsTopDebuffsBottomType = enum and enum.BuffsTopDebuffsBottom
    local buffsRightDebuffsLeftType = enum and enum.BuffsRightDebuffsLeft

    local auraOrganizationType = legacyType
    local editMode = _G.EditModeManagerFrame
    if editMode and type(editMode.GetRaidFrameAuraOrganizationType) == "function" then
        auraOrganizationType = editMode:GetRaidFrameAuraOrganizationType(ownerFrame.groupType) or auraOrganizationType
    end

    if auraOrganizationType == buffsTopDebuffsBottomType then
        if containerType == COMPACT_AURA_CONTAINER_BUFF then
            return { useChainLayout = false, stride = 6, direction = GetCompactGridDirection("TopRightToBottomLeft") }
        elseif containerType == COMPACT_AURA_CONTAINER_DEBUFF then
            return { useChainLayout = true, stride = 3, direction = GetCompactGridDirection("BottomRightToTopLeft") }
        elseif containerType == COMPACT_AURA_CONTAINER_DISPEL then
            return { useChainLayout = false, stride = 3, direction = GetCompactGridDirection("BottomLeftToTopRight") }
        end
    elseif auraOrganizationType == buffsRightDebuffsLeftType then
        if containerType == COMPACT_AURA_CONTAINER_BUFF then
            return { useChainLayout = false, stride = 3, direction = GetCompactGridDirection("BottomRightToTopLeft") }
        elseif containerType == COMPACT_AURA_CONTAINER_DEBUFF then
            return { useChainLayout = true, stride = 3, direction = GetCompactGridDirection("BottomLeftToTopRight") }
        elseif containerType == COMPACT_AURA_CONTAINER_DISPEL then
            return { useChainLayout = false, stride = 3, direction = GetCompactGridDirection("LeftToRight") }
        end
    else
        if containerType == COMPACT_AURA_CONTAINER_BUFF then
            return { useChainLayout = false, stride = 3, direction = GetCompactGridDirection("BottomRightToTopLeft") }
        elseif containerType == COMPACT_AURA_CONTAINER_DEBUFF then
            return { useChainLayout = true, stride = 3, direction = GetCompactGridDirection("BottomLeftToTopRight") }
        elseif containerType == COMPACT_AURA_CONTAINER_DISPEL then
            return { useChainLayout = false, stride = 3, direction = GetCompactGridDirection("RightToLeft") }
        end
    end

    return nil
end

local function GetCompactAuraOrganizationType(ownerFrame)
    if not ownerFrame then
        return nil
    end

    local enum = _G.Enum and _G.Enum.RaidAuraOrganizationType
    local auraOrganizationType = enum and enum.Legacy
    local editMode = _G.EditModeManagerFrame
    if editMode and type(editMode.GetRaidFrameAuraOrganizationType) == "function" then
        auraOrganizationType = editMode:GetRaidFrameAuraOrganizationType(ownerFrame.groupType) or auraOrganizationType
    end
    return auraOrganizationType
end

----------------------------------------------------------------------------------------
-- Important Buff Anchor
----------------------------------------------------------------------------------------
local function GetCompactImportantAnchorPoint(ownerFrame)
    local enum = _G.Enum and _G.Enum.RaidAuraOrganizationType
    local organizationType = GetCompactAuraOrganizationType(ownerFrame)

    if enum and organizationType == enum.Legacy then
        local powerBarUsedHeight = ownerFrame and ownerFrame.powerBarUsedHeight or 0
        if IsUnreadableNumber(powerBarUsedHeight) then
            powerBarUsedHeight = 0
        end
        if type(powerBarUsedHeight) ~= "number" then
            powerBarUsedHeight = 0
        end
        return "BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", -3, 3 + powerBarUsedHeight
    elseif enum and organizationType == enum.BuffsTopDebuffsBottom then
        return "TOPRIGHT", ownerFrame, "TOPRIGHT", -3, -3
    elseif enum and organizationType == enum.BuffsRightDebuffsLeft then
        return "TOPRIGHT", ownerFrame, "TOPRIGHT", -3, -3
    end

    return "TOPRIGHT", ownerFrame, "TOPRIGHT", -3, -3
end

local function EnsureCompactImportantBuffAnchor(ownerFrame)
    if not ownerFrame or ownerFrame:IsForbidden() then
        return nil
    end

    local data = GetPartyData(ownerFrame)
    local anchor = data.importantBuffAnchor
    if not anchor then
        anchor = CreateFrame("Frame", nil, ownerFrame)
        anchor:SetSize(1, 1)
        if anchor.EnableMouse then
            anchor:EnableMouse(false)
        end
        data.importantBuffAnchor = anchor
    end

    local point, relativeTo, relativePoint, x, y = GetCompactImportantAnchorPoint(ownerFrame)
    anchor:ClearAllPoints()
    anchor:SetPoint(point, relativeTo, relativePoint, x, y)
    anchor:SetFrameStrata(GetSafeFrameStrata(ownerFrame, "LOW"))
    anchor:SetFrameLevel(GetSafeFrameLevel(ownerFrame, 0) + 35)
    return anchor
end

local function BuildCompactImportantLayoutToken(frame, importantBuffFrames, stride, spacing, direction)
    local parts = WipeTable(importantLayoutTokenParts)
    parts[1] = tostring(stride)
    parts[2] = ":"
    parts[3] = tostring(spacing)
    parts[4] = ":"
    parts[5] = tostring(direction and direction.x or 0)
    parts[6] = ":"
    parts[7] = tostring(direction and direction.y or 0)

    local nextIndex = 8
    for index = 1, #importantBuffFrames do
        local buffFrame = importantBuffFrames[index]
        local auraData = buffFrame and GetPartyAuraData(buffFrame)
        parts[nextIndex] = "|I:"
        parts[nextIndex + 1] = tostring(index)
        parts[nextIndex + 2] = ":"
        parts[nextIndex + 3] = tostring(auraData and (auraData.auraInstanceID or auraData.auraSpellID) or buffFrame)
        nextIndex = nextIndex + 4
    end

    if type(frame.buffFrames) == "table" then
        for index = 1, #frame.buffFrames do
            local buffFrame = frame.buffFrames[index]
            if buffFrame and buffFrame:IsShown() then
                local auraData = GetPartyAuraData(buffFrame)
                parts[nextIndex] = "|B:"
                parts[nextIndex + 1] = tostring(index)
                parts[nextIndex + 2] = ":"
                parts[nextIndex + 3] = tostring(auraData and (auraData.auraInstanceID or auraData.auraSpellID) or buffFrame)
                parts[nextIndex + 4] = ":"
                parts[nextIndex + 5] = importantByFrameScratch[buffFrame] and "1" or "0"
                nextIndex = nextIndex + 6
            end
        end
    end

    return table.concat(parts, "")
end

----------------------------------------------------------------------------------------
-- Spacing Computation
----------------------------------------------------------------------------------------
local function ResolveCompactAuraChainSpacingOffset(point, relPoint, spacing)
    if type(point) ~= "string" or type(relPoint) ~= "string" then
        return 0, 0
    end

    if strfind(point, "LEFT", 1, true) and strfind(relPoint, "RIGHT", 1, true) then
        return spacing, 0
    elseif strfind(point, "RIGHT", 1, true) and strfind(relPoint, "LEFT", 1, true) then
        return -spacing, 0
    elseif strfind(point, "TOP", 1, true) and strfind(relPoint, "BOTTOM", 1, true) then
        return 0, -spacing
    elseif strfind(point, "BOTTOM", 1, true) and strfind(relPoint, "TOP", 1, true) then
        return 0, spacing
    end

    return 0, 0
end

local function GetCompactAuraSpacingOffset(auraFrame, point, relTo, relPoint, _x, _y)
    if not auraFrame or type(point) ~= "string" then
        return nil, nil
    end

    local spacing = GetCompactAuraIconSpacing()

    local data = GetPartyAuraData(auraFrame)
    local ownerFrame = data.ownerFrame
    if not IsPartyRaidCompactFrame(ownerFrame) then
        return nil, nil
    end

    local containerType = data.containerType
    local containerIndex = data.containerIndex
    if type(containerIndex) ~= "number" or not containerType then
        containerType, containerIndex = ResolveCompactAuraContainerInfo(ownerFrame, auraFrame)
        if not containerType or type(containerIndex) ~= "number" then
            return nil, nil
        end
        data.containerType = containerType
        data.containerIndex = containerIndex
    end

    local layoutSpec = GetCompactAuraLayoutSpec(ownerFrame, containerType)
    local direction = layoutSpec and layoutSpec.direction
    if type(direction) ~= "table" then
        return nil, nil
    end

    local desiredOffsetX = 0
    local desiredOffsetY = 0

    if spacing > 0 then
        if layoutSpec.useChainLayout then
            if containerIndex > 1 then
                local chainSpacingX, chainSpacingY = ResolveCompactAuraChainSpacingOffset(point, relPoint, spacing)
                if chainSpacingX == 0 and chainSpacingY == 0 then
                    local directionX = type(direction.x) == "number" and direction.x or 0
                    local directionY = type(direction.y) == "number" and direction.y or 0
                    if abs(directionX) >= abs(directionY) then
                        chainSpacingX = directionX ~= 0 and spacing * directionX or 0
                    else
                        chainSpacingY = directionY ~= 0 and spacing * directionY or 0
                    end
                end

                desiredOffsetX = chainSpacingX
                desiredOffsetY = chainSpacingY
            end
        else
            local stride = layoutSpec.stride or 1
            local row = floor((containerIndex - 1) / stride) + 1
            local col = ((containerIndex - 1) % stride) + 1
            if direction.isVertical then
                row, col = col, row
            end

            local directionX = type(direction.x) == "number" and direction.x or 0
            local directionY = type(direction.y) == "number" and direction.y or 0
            desiredOffsetX = (col - 1) * spacing * directionX
            desiredOffsetY = (row - 1) * spacing * directionY
        end
    end

    return desiredOffsetX, desiredOffsetY
end

----------------------------------------------------------------------------------------
-- Spacing Carrier Management
----------------------------------------------------------------------------------------
local function EnsureCompactAuraSpacingCarrier(auraFrame)
    local data = GetPartyAuraData(auraFrame)
    if data.spacingCarrier and data.spacingCarrier:GetParent() == (auraFrame:GetParent() or auraFrame) then
        return data.spacingCarrier
    end

    local parent = auraFrame:GetParent() or auraFrame
    local carrier = CreateFrame("Frame", nil, parent)
    carrier:SetSize(1, 1)
    if carrier.EnableMouse then
        carrier:EnableMouse(false)
    end
    data.spacingCarrier = carrier
    return carrier
end

local function GetCompactAuraBaseAnchor(auraFrame)
    local data = GetPartyAuraData(auraFrame)
    if type(data.basePoint) == "string" then
        return data.basePoint, data.baseRelTo, data.baseRelPoint, data.baseX, data.baseY
    end

    local point, relTo, relPoint, x, y = auraFrame:GetPoint()
    if type(point) ~= "string" then
        return nil, nil, nil, nil, nil
    end

    if data.spacingCarrier and relTo == data.spacingCarrier then
        return nil, nil, nil, nil, nil
    end

    data.basePoint = point
    data.baseRelTo = relTo
    data.baseRelPoint = relPoint
    data.baseX = x
    data.baseY = y
    return point, relTo, relPoint, x, y
end

----------------------------------------------------------------------------------------
-- Spacing Application
----------------------------------------------------------------------------------------
local function ApplyCompactAuraSpacingFromAnchor(auraFrame, point, relTo, relPoint, x, y, offsetX, offsetY)
    if not auraFrame or auraFrame:IsForbidden() then
        return
    end

    if type(offsetX) ~= "number" or type(offsetY) ~= "number" then
        return
    end

    local data = GetPartyAuraData(auraFrame)
    if data.spacingAdjusting then
        return
    end

    if offsetX == 0 and offsetY == 0 then
        data.spacingAdjusting = true
        pcall(auraFrame.ClearAllPoints, auraFrame)
        pcall(auraFrame.SetPoint, auraFrame, point, relTo, relPoint, x, y)
        data.spacingAdjusting = false
        return
    end

    local carrier = EnsureCompactAuraSpacingCarrier(auraFrame)
    if not carrier then
        return
    end

    data.spacingAdjusting = true
    if data.spacingCarrierPoint ~= point
        or data.spacingCarrierRelTo ~= relTo
        or data.spacingCarrierRelPoint ~= relPoint
        or data.spacingCarrierX ~= x
        or data.spacingCarrierY ~= y then
        carrier:ClearAllPoints()
        pcall(carrier.SetPoint, carrier, point, relTo, relPoint, x, y)
        data.spacingCarrierPoint = point
        data.spacingCarrierRelTo = relTo
        data.spacingCarrierRelPoint = relPoint
        data.spacingCarrierX = x
        data.spacingCarrierY = y
    end

    local okCarrier = true
    if okCarrier then
        pcall(auraFrame.ClearAllPoints, auraFrame)
        pcall(auraFrame.SetPoint, auraFrame, point, carrier, point, offsetX, offsetY)
    end
    data.spacingAdjusting = false
end

local function ApplyCompactAuraSpacingToCurrentPoint(auraFrame)
    if not auraFrame or auraFrame:IsForbidden() then
        return
    end

    local data = GetPartyAuraData(auraFrame)
    if data.isInImportantAnchor then
        return
    end

    local point, relTo, relPoint, x, y = GetCompactAuraBaseAnchor(auraFrame)
    if type(point) ~= "string" then
        return
    end

    local desiredOffsetX, desiredOffsetY = GetCompactAuraSpacingOffset(auraFrame, point, relTo, relPoint, x, y)
    if desiredOffsetX == nil or desiredOffsetY == nil then
        return
    end

    ApplyCompactAuraSpacingFromAnchor(auraFrame, point, relTo, relPoint, x, y, desiredOffsetX, desiredOffsetY)
end

local function EnsureCompactAuraSpacing(ownerFrame, auraFrame, containerType, containerIndex)
    if not auraFrame or auraFrame:IsForbidden() then
        return
    end

    ownerFrame = ownerFrame or auraFrame:GetParent()
    if not IsPartyRaidCompactFrame(ownerFrame) then
        return
    end

    if not containerType or type(containerIndex) ~= "number" then
        containerType, containerIndex = ResolveCompactAuraContainerInfo(ownerFrame, auraFrame)
    end
    if not containerType or type(containerIndex) ~= "number" then
        return
    end

    local data = GetPartyAuraData(auraFrame)
    data.ownerFrame = ownerFrame
    data.containerType = containerType
    data.containerIndex = containerIndex

    if not data.spacingHookInstalled then
        RefineUI:HookOnce(BuildPartyHookKey(auraFrame, "SetPoint:AuraSpacing"), auraFrame, "SetPoint", function(self, point, relTo, relPoint, x, y)
            local auraData = GetPartyAuraData(self)
            if auraData.spacingAdjusting then
                return
            end
            if auraData.isInImportantAnchor then
                return
            end

            auraData.basePoint = point
            auraData.baseRelTo = relTo
            auraData.baseRelPoint = relPoint
            auraData.baseX = x
            auraData.baseY = y

            local desiredOffsetX, desiredOffsetY = GetCompactAuraSpacingOffset(self, point, relTo, relPoint, x, y)
            if desiredOffsetX == nil or desiredOffsetY == nil then
                return
            end

            ApplyCompactAuraSpacingFromAnchor(self, point, relTo, relPoint, x, y, desiredOffsetX, desiredOffsetY)
        end)
        data.spacingHookInstalled = true
    end

    ApplyCompactAuraSpacingToCurrentPoint(auraFrame)
end

local function ApplyCompactAuraSpacingForFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not IsPartyRaidCompactFrame(frame) then return end

    if type(frame.buffFrames) == "table" then
        for index, buffFrame in ipairs(frame.buffFrames) do
            if buffFrame then
                EnsureCompactAuraSpacing(frame, buffFrame, COMPACT_AURA_CONTAINER_BUFF, index)
            end
        end
    end

    if type(frame.debuffFrames) == "table" then
        for index, debuffFrame in ipairs(frame.debuffFrames) do
            if debuffFrame then
                EnsureCompactAuraSpacing(frame, debuffFrame, COMPACT_AURA_CONTAINER_DEBUFF, index)
            end
        end
    end

    if type(frame.dispelDebuffFrames) == "table" then
        for index, dispelFrame in ipairs(frame.dispelDebuffFrames) do
            if dispelFrame then
                EnsureCompactAuraSpacing(frame, dispelFrame, COMPACT_AURA_CONTAINER_DISPEL, index)
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Important Buff Sort / Layout
----------------------------------------------------------------------------------------
local function CompareImportantBuffFramesByManualOrder(auraFrameA, auraFrameB)
    local dataA = GetPartyAuraData(auraFrameA)
    local dataB = GetPartyAuraData(auraFrameB)
    local rankA = P.GetTrackedClassBuffManualOrderRank(dataA and dataA.classBuffEntryKey)
    local rankB = P.GetTrackedClassBuffManualOrderRank(dataB and dataB.classBuffEntryKey)
    if rankA ~= rankB then
        return rankA < rankB
    end
    local spellA = dataA and dataA.auraSpellID or 0
    local spellB = dataB and dataB.auraSpellID or 0
    return spellA < spellB
end

local function CompareImportantBuffFramesByDuration(auraFrameA, auraFrameB, descending)
    local remainingA = P.GetAuraRemainingSecondsFromData(GetPartyAuraData(auraFrameA))
    local remainingB = P.GetAuraRemainingSecondsFromData(GetPartyAuraData(auraFrameB))

    if remainingA == nil and remainingB == nil then
        return CompareImportantBuffFramesByManualOrder(auraFrameA, auraFrameB)
    elseif remainingA == nil then
        return false
    elseif remainingB == nil then
        return true
    end

    if remainingA == remainingB then
        return CompareImportantBuffFramesByManualOrder(auraFrameA, auraFrameB)
    end

    if descending then
        return remainingA > remainingB
    end
    return remainingA < remainingB
end

local function SortImportantBuffFrames(frames)
    P.EnsureManualOrderIncludesAllEntries()
    local mode = P.GetTrackedClassBuffSortMode()
    local SORT_MODE = P.IMPORTANT_SORT_MODE
    if mode == SORT_MODE.ASCENDING then
        tsort(frames, function(a, b)
            return CompareImportantBuffFramesByDuration(a, b, false)
        end)
    elseif mode == SORT_MODE.DESCENDING then
        tsort(frames, function(a, b)
            return CompareImportantBuffFramesByDuration(a, b, true)
        end)
    else
        tsort(frames, CompareImportantBuffFramesByManualOrder)
    end
end

local function ApplyCompactImportantBuffLayout(frame, importantBuffFrames)
    if not frame or frame:IsForbidden() or type(frame.buffFrames) ~= "table" then
        return
    end

    local frameData = GetPartyData(frame)
    local importantByFrame = WipeTable(importantByFrameScratch)
    for i = 1, #importantBuffFrames do
        local buffFrame = importantBuffFrames[i]
        if buffFrame then
            importantByFrame[buffFrame] = true
        end
    end

    for _, buffFrame in ipairs(frame.buffFrames) do
        local data = GetPartyAuraData(buffFrame)
        data.isInImportantAnchor = importantByFrame[buffFrame] == true
    end

    if #importantBuffFrames == 0 then
        frameData.importantMembershipToken = "none"
        frameData.importantLayoutToken = "none"
        for _, buffFrame in ipairs(frame.buffFrames) do
            if buffFrame and buffFrame:IsShown() then
                ApplyCompactAuraSpacingToCurrentPoint(buffFrame)
            end
        end
        return
    end

    SortImportantBuffFrames(importantBuffFrames)

    local anchor = EnsureCompactImportantBuffAnchor(frame)
    if not anchor then
        return
    end

    local layoutSpec = GetCompactAuraLayoutSpec(frame, COMPACT_AURA_CONTAINER_BUFF)
    local stride = layoutSpec and layoutSpec.stride or 3
    if stride < 1 then
        stride = 3
    end
    local spacing = GetCompactAuraIconSpacing()
    local direction = layoutSpec and layoutSpec.direction

    -- Place important frames onto the important anchor
    for index = 1, #importantBuffFrames do
        local buffFrame = importantBuffFrames[index]
        if buffFrame then
            local iconWidth = buffFrame:GetWidth() or 0
            local iconHeight = buffFrame:GetHeight() or iconWidth
            local col = (index - 1) % stride
            local row = floor((index - 1) / stride)
            local x = -(col * (iconWidth + spacing))
            local y = -(row * (iconHeight + spacing))
            local data = GetPartyAuraData(buffFrame)
            data.spacingAdjusting = true
            buffFrame:ClearAllPoints()
            buffFrame:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", x, y)
            data.spacingAdjusting = false
        end
    end

    -- Re-layout non-important frames at sequential grid positions to close gaps.
    -- Blizzard uses AnchorUtil.GridLayout which positions each buffFrames[N] at
    -- absolute grid slot N. When important frames are extracted, the remaining
    -- frames stay at their original slots, leaving gaps. We must re-lay them
    -- out at sequential positions (0, 1, 2...) using the same grid parameters.

    -- Capture the grid origin from buffFrames[1]'s original base anchor.
    -- This is the anchor point Blizzard set via GridLayout for the first slot.
    local originPoint, originRelTo, originRelPoint, originX, originY
    local firstData = GetPartyAuraData(frame.buffFrames[1])
    if firstData and type(firstData.basePoint) == "string" then
        originPoint = firstData.basePoint
        originRelTo = firstData.baseRelTo
        originRelPoint = firstData.baseRelPoint
        originX = firstData.baseX or 0
        originY = firstData.baseY or 0
    end

    if not originPoint or not originRelTo then
        return
    end

    -- Determine grid step direction from layout spec
    local dirX = direction and type(direction.x) == "number" and direction.x or -1
    local dirY = direction and type(direction.y) == "number" and direction.y or -1

    local seqIndex = 0
    for _, buffFrame in ipairs(frame.buffFrames) do
        local data = GetPartyAuraData(buffFrame)
        if buffFrame and buffFrame:IsShown() and not data.isInImportantAnchor then
            local iconWidth = buffFrame:GetWidth() or 0
            local iconHeight = buffFrame:GetHeight() or iconWidth

            local col = seqIndex % stride
            local row = floor(seqIndex / stride)

            local offsetX = col * iconWidth * dirX
            local offsetY = row * iconHeight * dirY

            -- Update base anchor data so spacing system uses corrected position
            local nextBaseX = originX + offsetX
            local nextBaseY = originY + offsetY
            local nextContainerIndex = seqIndex + 1
            local baseAnchorChanged = data.basePoint ~= originPoint
                or data.baseRelTo ~= originRelTo
                or data.baseRelPoint ~= originRelPoint
                or data.baseX ~= nextBaseX
                or data.baseY ~= nextBaseY
                or data.containerIndex ~= nextContainerIndex

            data.basePoint = originPoint
            data.baseRelTo = originRelTo
            data.baseRelPoint = originRelPoint
            data.baseX = nextBaseX
            data.baseY = nextBaseY
            data.containerIndex = nextContainerIndex

            -- Re-apply spacing from corrected base position.
            data.spacingAdjusting = true
            buffFrame:ClearAllPoints()
            data.spacingAdjusting = false
            ApplyCompactAuraSpacingToCurrentPoint(buffFrame)

            seqIndex = seqIndex + 1
        end
    end
end

local function PrewarmAuraHelpersForFrame(frame)
    if not frame or frame:IsForbidden() or InCombatLockdown() then
        return
    end
    if not IsPartyRaidCompactFrame(frame) then
        return
    end

    EnsureCompactImportantBuffAnchor(frame)
    ApplyCompactAuraSpacingForFrame(frame)

    if type(P.EnsureCompactAuraBorder) == "function" then
        if type(frame.buffFrames) == "table" then
            for index = 1, #frame.buffFrames do
                local buffFrame = frame.buffFrames[index]
                if buffFrame then
                    P.EnsureCompactAuraBorder(buffFrame)
                end
            end
        end

        if type(frame.debuffFrames) == "table" then
            for index = 1, #frame.debuffFrames do
                local debuffFrame = frame.debuffFrames[index]
                if debuffFrame then
                    P.EnsureCompactAuraBorder(debuffFrame)
                end
            end
        end

        if frame.CenterDefensiveBuff then
            P.EnsureCompactAuraBorder(frame.CenterDefensiveBuff)
        end
    end
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.COMPACT_AURA_CONTAINER_BUFF   = COMPACT_AURA_CONTAINER_BUFF
P.COMPACT_AURA_CONTAINER_DEBUFF = COMPACT_AURA_CONTAINER_DEBUFF
P.COMPACT_AURA_CONTAINER_DISPEL = COMPACT_AURA_CONTAINER_DISPEL

P.GetCompactAuraIconSpacing          = GetCompactAuraIconSpacing
P.GetCompactAuraLayoutSpec           = GetCompactAuraLayoutSpec
P.EnsureCompactImportantBuffAnchor   = EnsureCompactImportantBuffAnchor
P.EnsureCompactAuraSpacing           = EnsureCompactAuraSpacing
P.ApplyCompactAuraSpacingForFrame    = ApplyCompactAuraSpacingForFrame
P.ApplyCompactAuraSpacingToCurrentPoint = ApplyCompactAuraSpacingToCurrentPoint
P.ApplyCompactImportantBuffLayout    = ApplyCompactImportantBuffLayout
P.PrewarmAuraHelpersForFrame         = PrewarmAuraHelpersForFrame
