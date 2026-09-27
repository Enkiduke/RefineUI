----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Frames
-- Description: Registers supported Blizzard unit frames.
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
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SUPPORTED_FRAME_NAMES = {
    "TargetFrame",
    "FocusFrame",
    "Boss1TargetFrame",
    "Boss2TargetFrame",
    "Boss3TargetFrame",
    "Boss4TargetFrame",
    "Boss5TargetFrame",
}

-- Compact party/raid frames that exist before the SetUnit hook is installed.
local COMPACT_FRAME_NAME_FORMATS = {
    "CompactPartyFrameMember%d",
    "CompactPartyFramePet%d",
    "CompactRaidFrame%d",
}
local MAX_COMPACT_FRAME_INDEX = 40

-- Last unit seen per compact frame; SetUnit resets clicks only when it changes.
local compactFrameUnits = {}

----------------------------------------------------------------------------------------
-- Compact Frames
----------------------------------------------------------------------------------------
-- Blizzard names every party/raid member frame (CompactPartyFrameMember1,
-- CompactRaidFrame1, CompactRaidGroup1Member1); other compact frames are skipped.
local function IsCompactGroupFrame(frame)
    if frame:IsForbidden() then
        return false
    end
    local name = frame:GetName()
    return name ~= nil and name:find("^Compact") ~= nil
end

local function OnCompactUnitFrameSetUnit(frame, unit)
    if compactFrameUnits[frame] == unit or not IsCompactGroupFrame(frame) then
        return
    end
    compactFrameUnits[frame] = unit
    ClickCasting:RegisterSecureFrame(frame)
end

----------------------------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------------------------
function ClickCasting:DiscoverSupportedFrames()
    for index = 1, #SUPPORTED_FRAME_NAMES do
        local frame = _G[SUPPORTED_FRAME_NAMES[index]]
        if frame and not self.registeredFrames[frame] then
            self:RegisterSecureFrame(frame)
        end
    end

    for formatIndex = 1, #COMPACT_FRAME_NAME_FORMATS do
        local nameFormat = COMPACT_FRAME_NAME_FORMATS[formatIndex]
        for index = 1, MAX_COMPACT_FRAME_INDEX do
            local frame = _G[nameFormat:format(index)]
            if not frame then
                break
            end
            OnCompactUnitFrameSetUnit(frame, frame:GetAttribute("unit"))
        end
    end

    -- Party and raid frames are created and reassigned units on roster changes;
    -- each unit change re-runs SecureUnitButton_OnLoad, which resets clicks.
    hooksecurefunc("CompactUnitFrame_SetUnit", OnCompactUnitFrameSetUnit)
end
