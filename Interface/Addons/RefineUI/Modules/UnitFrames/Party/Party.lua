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
local type = type
local tostring = tostring
local floor = math.floor
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PARTY_FRAME_STATE_REGISTRY = "UnitFramesPartyState"
local PARTY_AURA_STATE_REGISTRY  = "UnitFramesPartyAuraState"
local MAX_RAID_GROUPS = 8
local DEFAULT_COMPACT_RAID_GROUP_HORIZONTAL_SPACING = 8
local GAP = 18
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

local function BuildPartyHookKey(owner, method)
    return UnitFrames:BuildHookKey(owner, "Party:" .. tostring(method))
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

local function IsCompactPartyMemberFrame(frame)
    if not frame or type(frame.GetName) ~= "function" then
        return false
    end

    local frameName = frame:GetName()
    return type(frameName) == "string" and frameName:match("^CompactPartyFrameMember%d+$") ~= nil
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
-- Compact Raid Layout
----------------------------------------------------------------------------------------
local function GetCompactFrameVerticalGap(frame)
    local unit = frame and (frame.displayedUnit or frame.unit)
    if IsCompactPetUnitToken(unit) then
        return PET_GAP
    end
    return GAP
end

local function HookSpacing(frame)
    if not frame or IsCompactPartyMemberFrame(frame) then
        return
    end

    RefineUI:HookOnce(BuildPartyHookKey(frame, "SetPoint:Spacing"), frame, "SetPoint", function(self, point, relTo, relPoint, x, y)
        if UnitFrames:GetState(self, "PartySpacingChange", false) or InCombatLockdown() or IsEditModeActiveNow() then
            return
        end

        if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
            local desiredGap = GetCompactFrameVerticalGap(self)
            if IsUnreadableNumber(x) or IsUnreadableNumber(y) then
                return
            end

            local currentX = type(x) == "number" and x or 0
            local currentY = type(y) == "number" and y or 0
            if currentY ~= -desiredGap then
                UnitFrames:WithStateGuard(self, "PartySpacingChange", function()
                    self:SetPoint(point, relTo, relPoint, currentX, -desiredGap)
                end)
            end
        end
    end)
end

local function GetConfiguredCompactRaidGroupHorizontalSpacing()
    local unitFramesConfig = Config and Config.UnitFrames
    local configured = unitFramesConfig and unitFramesConfig.CompactRaidGroupHorizontalSpacing
    if type(configured) ~= "number" or configured < 0 then
        configured = DEFAULT_COMPACT_RAID_GROUP_HORIZONTAL_SPACING
    end
    return RefineUI:Scale(configured)
end

local function HideCompactPartyTitle()
    local title = _G.CompactPartyFrameTitle
    if not title then
        return
    end

    if title.SetAlpha then
        title:SetAlpha(0)
    end
    if title.Hide and title.IsShown and title:IsShown() then
        title:Hide()
    end
end

local function ForEachCompactRaidGroup(fn)
    if type(fn) ~= "function" then
        return
    end

    local seen = {}
    local raidContainer = _G.CompactRaidFrameContainer
    local groupFrames = raidContainer and raidContainer.groupFrames

    if type(groupFrames) == "table" then
        for _, groupFrame in ipairs(groupFrames) do
            if groupFrame and not seen[groupFrame] then
                seen[groupFrame] = true
                fn(groupFrame)
            end
        end
    end

    for i = 1, MAX_RAID_GROUPS do
        local groupFrame = _G["CompactRaidGroup" .. i]
        if groupFrame and not seen[groupFrame] then
            seen[groupFrame] = true
            fn(groupFrame)
        end
    end
end

local function CollapseCompactRaidGroupTitle(groupFrame)
    if not groupFrame or (groupFrame.IsForbidden and groupFrame:IsForbidden()) then
        return false
    end

    local title = groupFrame.title
    if not title then
        return false
    end

    local changed = false

    if title.SetHeight and title.GetHeight then
        local currentHeight = title:GetHeight()
        if type(currentHeight) == "number" and currentHeight ~= 0 then
            title:SetHeight(0)
            changed = true
        end
    end

    if title.SetAlpha and title.GetAlpha then
        local currentAlpha = title:GetAlpha()
        if type(currentAlpha) == "number" and currentAlpha ~= 0 then
            title:SetAlpha(0)
            changed = true
        end
    end

    if title.Hide and title.IsShown and title:IsShown() then
        title:Hide()
        changed = true
    end

    return changed
end

local function ApplyCompactRaidGroupSpacing()
    local raidContainer = _G.CompactRaidFrameContainer
    if not raidContainer or type(_G.FlowContainer_SetHorizontalSpacing) ~= "function" then
        return false
    end

    local desiredSpacing = GetConfiguredCompactRaidGroupHorizontalSpacing()
    local currentSpacing = raidContainer.flowHorizontalSpacing
    if type(currentSpacing) == "number" and currentSpacing == desiredSpacing then
        return false
    end

    _G.FlowContainer_SetHorizontalSpacing(raidContainer, desiredSpacing)
    return true
end

local function ApplyCompactRaidLayout()
    HideCompactPartyTitle()

    if InCombatLockdown() or IsEditModeActiveNow() then
        return
    end

    local changed = ApplyCompactRaidGroupSpacing()
    ForEachCompactRaidGroup(function(groupFrame)
        if CollapseCompactRaidGroupTitle(groupFrame) then
            changed = true
        end
    end)

    local raidContainer = _G.CompactRaidFrameContainer
    if changed and raidContainer and type(raidContainer.LayoutFrames) == "function" then
        pcall(raidContainer.LayoutFrames, raidContainer)
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

local function ForceRestoreSpacing()
    if InCombatLockdown() or IsEditModeActiveNow() then
        return
    end

    ForEachCompactPartyRaidFrame(true, true, function(frame)
        local point, relTo, relPoint, x, y = frame:GetPoint()
        if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
            local desiredGap = GetCompactFrameVerticalGap(frame)
            if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                local currentX = type(x) == "number" and x or 0
                local currentY = type(y) == "number" and y or 0
                if currentY ~= -desiredGap then
                    UnitFrames:WithStateGuard(frame, "PartySpacingChange", function()
                        frame:SetPoint(point, relTo, relPoint, currentX, -desiredGap)
                    end)
                end
            end
        end
    end)
end

----------------------------------------------------------------------------------------
-- Shared Internal Export Table
----------------------------------------------------------------------------------------
Private.Party = Private.Party or {}
local P = Private.Party

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
P.IsCompactPartyMemberFrame = IsCompactPartyMemberFrame
P.IsPetUnit              = IsCompactPetUnitToken
P.GetPetOwnerClassColor  = GetCompactPetOwnerClassColor
P.GetCompactFrameVerticalGap = GetCompactFrameVerticalGap

P.ForEachFrame           = ForEachCompactPartyFrame
P.ForEachRaidFrame       = ForEachCompactPartyRaidFrame

P.HookSpacing            = HookSpacing
P.ForceRestoreSpacing    = ForceRestoreSpacing
P.ApplyCompactRaidLayout = ApplyCompactRaidLayout

P.TEXTURE_COMPACT_HEALTH = RefineUI.Media.Textures.Smooth
