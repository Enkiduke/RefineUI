----------------------------------------------------------------------------------------
-- UnitFrames Party: Core
-- Description: Data registries, shared utilities, and frame iteration for Compact
--              Party/Raid frame handling.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Colors = RefineUI.Colors

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local type = type
local tostring = tostring
local floor = math.floor
local abs = math.abs
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PARTY_FRAME_STATE_REGISTRY = "UnitFramesPartyState"
local PARTY_AURA_STATE_REGISTRY  = "UnitFramesPartyAuraState"

local GAP     = 18
local PET_GAP = 8

----------------------------------------------------------------------------------------
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local PartyFrameData = RefineUI:CreateDataRegistry(PARTY_FRAME_STATE_REGISTRY, "k")
local PartyAuraData  = RefineUI:CreateDataRegistry(PARTY_AURA_STATE_REGISTRY, "k")

local function GetPartyData(frame)
    if not frame then return {} end
    local data = PartyFrameData[frame]
    if not data then
        data = {}
        PartyFrameData[frame] = data
    end
    return data
end

local function GetPartyAuraData(auraFrame)
    if not auraFrame then return {} end
    local data = PartyAuraData[auraFrame]
    if not data then
        data = {}
        PartyAuraData[auraFrame] = data
    end
    return data
end

----------------------------------------------------------------------------------------
-- Hook Key Helpers
----------------------------------------------------------------------------------------
local function GetPartyHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(owner)
end

local function BuildPartyHookKey(owner, method)
    return "UnitFramesParty:" .. GetPartyHookOwnerId(owner) .. ":" .. method
end

----------------------------------------------------------------------------------------
-- Secret Value Helpers
----------------------------------------------------------------------------------------
local function IsUnreadableNumber(value)
    return type(value) == "number" and issecretvalue and issecretvalue(value)
end

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

----------------------------------------------------------------------------------------
-- Safe Frame Level / Strata
----------------------------------------------------------------------------------------
local function GetSafeFrameLevel(frame, fallback)
    local fallbackValue = type(fallback) == "number" and fallback or 0
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return fallbackValue
    end

    local ok, level = pcall(frame.GetFrameLevel, frame)
    if not ok or IsUnreadableNumber(level) then
        return fallbackValue
    end

    if type(level) ~= "number" then
        return fallbackValue
    end

    return floor(level + 0.5)
end

local function GetSafeFrameStrata(frame, fallback)
    local fallbackValue = type(fallback) == "string" and fallback or "MEDIUM"
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return fallbackValue
    end

    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if not ok or IsSecretValue(strata) or type(strata) ~= "string" or strata == "" then
        return fallbackValue
    end

    return strata
end

local function TrySetFrameLevel(frame, level)
    if not frame or type(frame.SetFrameLevel) ~= "function" then
        return
    end
    if type(level) ~= "number" or IsUnreadableNumber(level) then
        return
    end

    pcall(frame.SetFrameLevel, frame, floor(level + 0.5))
end

local function TrySetFrameStrata(frame, strata)
    if not frame or type(frame.SetFrameStrata) ~= "function" then
        return
    end
    if IsSecretValue(strata) or type(strata) ~= "string" or strata == "" then
        return
    end

    pcall(frame.SetFrameStrata, frame, strata)
end

----------------------------------------------------------------------------------------
-- Dispel Type Validation
----------------------------------------------------------------------------------------
local function GetSafeDispelTypeKey(dispelType)
    if type(dispelType) ~= "string" or IsSecretValue(dispelType) then
        return nil
    end

    if dispelType == "Magic"
        or dispelType == "Curse"
        or dispelType == "Disease"
        or dispelType == "Poison"
        or dispelType == "Bleed"
        or dispelType == "None" then
        return dispelType
    end

    return nil
end

----------------------------------------------------------------------------------------
-- Edit Mode Check
----------------------------------------------------------------------------------------
local function IsEditModeActiveNow()
    return EditModeManagerFrame
        and type(EditModeManagerFrame.IsEditModeActive) == "function"
        and EditModeManagerFrame:IsEditModeActive()
end

----------------------------------------------------------------------------------------
-- Compact Frame Detection
----------------------------------------------------------------------------------------
local function IsPartyRaidCompactFrame(frame)
    if not frame then return false end

    local groupType = frame.groupType
    if not groupType then return false end

    local enum = _G.CompactRaidGroupTypeEnum
    if type(enum) == "table" then
        return groupType == enum.Party or groupType == enum.Raid
    end

    return true
end

----------------------------------------------------------------------------------------
-- Pet Unit Helpers
----------------------------------------------------------------------------------------
local function IsCompactPetUnitToken(unit)
    return type(unit) == "string" and unit:find("pet", 1, true) ~= nil
end

local function GetCompactPetOwnerUnit(frame)
    if not frame then return nil end

    local unit = frame.displayedUnit or frame.unit
    if type(unit) ~= "string" then return nil end
    if unit == "pet" then return "player" end

    local prefix, id = unit:match("^(.-)pet(%d+)$")
    if prefix and id and prefix ~= "" then
        return prefix .. id
    end

    return nil
end

local function GetCompactPetOwnerClassColor(frame)
    local ownerUnit = GetCompactPetOwnerUnit(frame)
    if not ownerUnit then return nil end

    local _, class = UnitClass(ownerUnit)
    if not class then return nil end
    return Colors and Colors.Class and Colors.Class[class]
end

----------------------------------------------------------------------------------------
-- Frame Spacing
----------------------------------------------------------------------------------------
local function GetCompactFrameVerticalGap(frame)
    local unit = frame and (frame.displayedUnit or frame.unit)
    if IsCompactPetUnitToken(unit) then
        return PET_GAP
    end
    return GAP
end

local function HookSpacing(frame)
    RefineUI:HookOnce(BuildPartyHookKey(frame, "SetPoint:Spacing"), frame, "SetPoint", function(self, point, relTo, relPoint, x, y)
        local d = GetPartyData(self)
        if d.changing or InCombatLockdown() or IsEditModeActiveNow() then return end
        
        if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
             local desiredGap = GetCompactFrameVerticalGap(self)
             if IsUnreadableNumber(x) or IsUnreadableNumber(y) then return end
             local currentX = type(x) == "number" and x or 0
             local currentY = type(y) == "number" and y or 0
             if currentY ~= -desiredGap and abs(currentY) <= GAP then
                 d.changing = true
                 self:SetPoint(point, relTo, relPoint, currentX, -desiredGap)
                 d.changing = false
             end
        end
    end)
end

local function ForceRestoreSpacing()
    if InCombatLockdown() or IsEditModeActiveNow() then return end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember"..i]
        if frame and frame:IsShown() then
            local data = GetPartyData(frame)
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         data.changing = true
                         frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         data.changing = false
                     end
                 end
            end
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and frame:IsShown() then
            local data = GetPartyData(frame)
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         data.changing = true
                         frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         data.changing = false
                     end
                 end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Frame Iteration
----------------------------------------------------------------------------------------
local function ForEachCompactPartyFrame(includeHidden, fn)
    if type(fn) ~= "function" then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember"..i]
        if frame and (includeHidden or frame:IsShown()) then
            fn(frame)
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and (includeHidden or frame:IsShown()) then
            fn(frame)
        end
    end
end

local function ForEachCompactPartyRaidFrame(includeHidden, includePets, fn)
    if type(fn) ~= "function" then return end

    local seen = {}
    local function TryHandle(frame)
        if not frame or seen[frame] then return end
        seen[frame] = true
        if not IsPartyRaidCompactFrame(frame) then return end
        if includeHidden or frame:IsShown() then
            fn(frame)
        end
    end

    for i = 1, 5 do
        TryHandle(_G["CompactPartyFrameMember" .. i])
    end

    if includePets then
        for i = 1, 5 do
            TryHandle(_G["CompactPartyFramePet" .. i])
        end
    end

    for i = 1, 40 do
        TryHandle(_G["CompactRaidFrame" .. i])
    end

    local raidContainer = _G.CompactRaidFrameContainer
    local groupFrames = raidContainer and raidContainer.groupFrames
    if type(groupFrames) == "table" then
        for _, groupFrame in ipairs(groupFrames) do
            local memberUnitFrames = groupFrame and groupFrame.memberUnitFrames
            if type(memberUnitFrames) == "table" then
                for _, unitFrame in ipairs(memberUnitFrames) do
                    TryHandle(unitFrame)
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Shared Internal Export Table
----------------------------------------------------------------------------------------
local P = {}
UF._party = P

P.GetData               = GetPartyData
P.GetAuraData            = GetPartyAuraData
P.BuildHookKey           = BuildPartyHookKey

P.IsUnreadableNumber     = IsUnreadableNumber
P.IsSecretValue          = IsSecretValue
P.GetSafeFrameLevel      = GetSafeFrameLevel
P.GetSafeFrameStrata     = GetSafeFrameStrata
P.TrySetFrameLevel       = TrySetFrameLevel
P.TrySetFrameStrata      = TrySetFrameStrata
P.GetSafeDispelTypeKey   = GetSafeDispelTypeKey

P.IsEditModeActive       = IsEditModeActiveNow
P.IsCompactFrame         = IsPartyRaidCompactFrame
P.IsPetUnit              = IsCompactPetUnitToken
P.GetPetOwnerClassColor  = GetCompactPetOwnerClassColor

P.ForEachFrame           = ForEachCompactPartyFrame
P.ForEachRaidFrame       = ForEachCompactPartyRaidFrame

P.HookSpacing            = HookSpacing
P.ForceRestoreSpacing    = ForceRestoreSpacing

P.TEXTURE_COMPACT_HEALTH = RefineUI.Media.Textures.Smooth
