----------------------------------------------------------------------------------------
-- UnitFrames Party: Core
-- Description: Data registries, shared utilities, and frame iteration for Compact
--              Party/Raid frame handling.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config
local UF = UnitFrames
local Private = UnitFrames:GetPrivate()

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
local pairs = pairs
local type = type
local tostring = tostring
local abs = math.abs
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local wipe = wipe

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PARTY_FRAME_STATE_REGISTRY = "UnitFramesPartyState"

local GAP     = 18
local PET_GAP = 8

local seenCompactFramesScratch = {}

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
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local PartyFrameData = RefineUI:CreateDataRegistry(PARTY_FRAME_STATE_REGISTRY, "k")

local function GetPartyData(frame)
    if not frame then return {} end
    local data = PartyFrameData[frame]
    if not data then
        data = {}
        PartyFrameData[frame] = data
    end
    return data
end

local function BuildPartyHookKey(owner, method)
    return UnitFrames:BuildHookKey(owner, "Party:" .. tostring(method))
end

----------------------------------------------------------------------------------------
-- Secret Value Helpers
----------------------------------------------------------------------------------------
local function IsUnreadableNumber(value)
    return type(value) == "number" and issecretvalue and issecretvalue(value)
end

----------------------------------------------------------------------------------------
-- Forbidden Object / Safe Shown Helpers
----------------------------------------------------------------------------------------
local function IsForbiddenObject(object)
    if not object then
        return false
    end
    if type(object) ~= "table" and type(object) ~= "userdata" then
        return false
    end
    if issecretvalue and issecretvalue(object) then
        return true
    end
    if canaccessvalue then
        local okAccess, accessible = pcall(canaccessvalue, object)
        if not okAccess or not accessible then
            return true
        end
    end
    local isForbidden = object.IsForbidden
    if type(isForbidden) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(isForbidden, object)
    return not ok or forbidden == true
end

local function IsFrameShownSafe(frame)
    if not frame or IsForbiddenObject(frame) then
        return false
    end
    local isShown = frame.IsShown
    if type(isShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(isShown, frame)
    return ok and shown == true
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
    if not frame or IsForbiddenObject(frame) then return false end

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
        if UnitFrames:GetState(self, "PartySpacingChange", false) or InCombatLockdown() or IsEditModeActiveNow() then return end
        
        if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
             local desiredGap = GetCompactFrameVerticalGap(self)
             if IsUnreadableNumber(x) or IsUnreadableNumber(y) then return end
             local currentX = type(x) == "number" and x or 0
             local currentY = type(y) == "number" and y or 0
             if currentY ~= -desiredGap and abs(currentY) <= GAP then
                 UnitFrames:WithStateGuard(self, "PartySpacingChange", function()
                     self:SetPoint(point, relTo, relPoint, currentX, -desiredGap)
                 end)
             end
        end
    end)
end

local function ForceRestoreSpacing()
    if InCombatLockdown() or IsEditModeActiveNow() then return end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember"..i]
        if frame and not IsForbiddenObject(frame) and IsFrameShownSafe(frame) then
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         UnitFrames:WithStateGuard(frame, "PartySpacingChange", function()
                             frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         end)
                     end
                 end
            end
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and not IsForbiddenObject(frame) and IsFrameShownSafe(frame) then
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         UnitFrames:WithStateGuard(frame, "PartySpacingChange", function()
                             frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         end)
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
        if frame and not IsForbiddenObject(frame) and (includeHidden or IsFrameShownSafe(frame)) then
            fn(frame)
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and not IsForbiddenObject(frame) and (includeHidden or IsFrameShownSafe(frame)) then
            fn(frame)
        end
    end
end

local function ForEachCompactPartyRaidFrame(includeHidden, includePets, fn)
    if type(fn) ~= "function" then return end

    local seen = WipeTable(seenCompactFramesScratch)
    local function TryHandle(frame)
        if not frame or seen[frame] then return end
        seen[frame] = true
        if not IsPartyRaidCompactFrame(frame) then return end
        if includeHidden or IsFrameShownSafe(frame) then
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

    WipeTable(seen)
end

----------------------------------------------------------------------------------------
-- Shared Internal Export Table
----------------------------------------------------------------------------------------
Private.Party = Private.Party or {}
local P = Private.Party

P.GetData               = GetPartyData
P.BuildHookKey           = BuildPartyHookKey

P.IsUnreadableNumber     = IsUnreadableNumber
P.IsForbiddenObject      = IsForbiddenObject
P.IsFrameShown           = IsFrameShownSafe

P.IsEditModeActive       = IsEditModeActiveNow
P.IsCompactFrame         = IsPartyRaidCompactFrame
P.IsPetUnit              = IsCompactPetUnitToken
P.GetPetOwnerClassColor  = GetCompactPetOwnerClassColor

P.ForEachFrame           = ForEachCompactPartyFrame
P.ForEachRaidFrame       = ForEachCompactPartyRaidFrame

P.HookSpacing            = HookSpacing
P.ForceRestoreSpacing    = ForceRestoreSpacing

P.TEXTURE_COMPACT_HEALTH = RefineUI.Media.Textures.Smooth
