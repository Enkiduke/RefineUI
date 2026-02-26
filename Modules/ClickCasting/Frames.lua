----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Frames
-- Description: Discovers and registers supported Blizzard unit frames.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local InCombatLockdown = InCombatLockdown
local type = type
local tostring = tostring

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local STATIC_FRAME_UNITS = {
    TargetFrame = "target",
    FocusFrame = "focus",
    Boss1TargetFrame = "boss1",
    Boss2TargetFrame = "boss2",
    Boss3TargetFrame = "boss3",
    Boss4TargetFrame = "boss4",
    Boss5TargetFrame = "boss5",
}

local COMPACT_SETUP_HOOK_KEY = "ClickCasting:CompactUnitFrame:SetUp"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function NormalizeUnitToken(rawUnit)
    if type(rawUnit) ~= "string" then
        return nil
    end
    return rawUnit:lower()
end

function ClickCasting:IsSupportedUnitToken(unit)
    local token = NormalizeUnitToken(unit)
    if not token then
        return false
    end

    if token == "target" or token == "focus" then
        return true
    end

    if token:match("^party%d+$") or token:match("^raid%d+$") then
        return true
    end

    if token:match("^boss%d+$") then
        return true
    end

    return false
end

local function ResolveFrameUnit(frame, fallbackUnit)
    if not frame then
        return nil
    end

    local unit = frame.unit
    if type(unit) == "string" and unit ~= "" then
        return unit
    end

    if frame.GetAttribute then
        local ok, attrUnit = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(attrUnit) == "string" and attrUnit ~= "" then
            return attrUnit
        end
    end

    return fallbackUnit
end

local function IsFrameNameplate(frame)
    local frameName = frame and frame.GetName and frame:GetName()
    if type(frameName) ~= "string" then
        return false
    end
    return frameName:match("^NamePlate") ~= nil
end

----------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------
function ClickCasting:TryRegisterSupportedFrame(frame, fallbackUnit)
    if not frame then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end
    if IsFrameNameplate(frame) then
        return false
    end

    local unit = ResolveFrameUnit(frame, fallbackUnit)
    if not self:IsSupportedUnitToken(unit) then
        return false
    end

    if InCombatLockdown() then
        self.frameRegistrationQueue[frame] = true
        self.pendingFrameRegistration = true
        return false
    end

    return self:RegisterSecureFrame(frame)
end

function ClickCasting:DiscoverStaticFrames()
    for frameName, unit in pairs(STATIC_FRAME_UNITS) do
        local frame = _G[frameName]
        if frame then
            self:TryRegisterSupportedFrame(frame, unit)
        end
    end
end

function ClickCasting:DiscoverCompactFrames()
    for index = 1, 5 do
        local partyFrame = _G["CompactPartyFrameMember" .. tostring(index)]
        if partyFrame then
            self:TryRegisterSupportedFrame(partyFrame, "party" .. tostring(index))
        end
    end

    for index = 1, 40 do
        local raidFrame = _G["CompactRaidFrame" .. tostring(index)]
        if raidFrame then
            self:TryRegisterSupportedFrame(raidFrame, "raid" .. tostring(index))
        end
    end
end

function ClickCasting:DiscoverSupportedFrames()
    self:DiscoverStaticFrames()
    self:DiscoverCompactFrames()
    self:FlushPendingFrameRegistrations()
end

----------------------------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------------------------
function ClickCasting:InitializeFrameDiscovery()
    local ok = RefineUI:HookOnce(COMPACT_SETUP_HOOK_KEY, "CompactUnitFrame_SetUpFrame", function(frame)
        if not frame or (frame.IsForbidden and frame:IsForbidden()) then
            return
        end
        if IsFrameNameplate(frame) then
            return
        end
        local unit = ResolveFrameUnit(frame)
        if not unit then
            return
        end
        if unit:match("^partypet%d+$") or unit:match("^raidpet%d+$") then
            return
        end
        if ClickCasting:IsSupportedUnitToken(unit) then
            ClickCasting:TryRegisterSupportedFrame(frame, unit)
        end
    end)

    if not ok then
        self:Print("Unable to hook CompactUnitFrame_SetUpFrame; compact frame auto-registration may be limited.")
    end
end

function ClickCasting:HandleAddonLoaded(addonName)
    if addonName == "Blizzard_CompactRaidFrames" or addonName == "Blizzard_UnitFrame" then
        self:DiscoverSupportedFrames()
    end

    if self.HandleSpellbookAddonLoaded then
        self:HandleSpellbookAddonLoaded(addonName)
    end
end
