local R, C, L = unpack(RefineUI)

if not C.chat.timestamps then return end

----------------------------------------------------------------------------------------
--	Chat Timestamps - Consolidated timestamp module for all chat messages
--  
--  This module provides unified timestamp functionality for ALL chat frames,
--  including the Combat Log (ChatFrame2) which was previously excluded.
--
--  Configuration options (in Config/Settings.lua):
--  - C.chat.timestamps: Enable/disable timestamps (boolean)
--  - C.chat.timestampFormat: Format style (string)
--    Valid values: "HHMM", "HHMMSS", "HHMM_24HR", "HHMMSS_24HR", "HHMM_AMPM", "HHMMSS_AMPM"
--  - C.chat.timestampColor: Enable colored timestamps (boolean)
--
--  Features:
--  - Applies to all chat frames including Combat Log
--  - Handles temporary chat windows
--  - Prevents double-timestamping with comprehensive detection
--  - Automatically disables Blizzard's built-in timestamp system
--  - Configurable format and colors
--  - Test command: /ruitest
--
--  Anti-Double-Timestamp Protection:
--  - Detects [12:34] and [12:34:56] bracketed formats
--  - Detects 12:34 and 12:34:56 plain formats  
--  - Detects colored timestamp variants
--  - Automatically disables showTimestamps CVar
----------------------------------------------------------------------------------------

-- Cache frequently used globals
local _G = _G
local rawget = rawget
local date = date
local time = time
local type = type
local match = string.match
local gsub = string.gsub
local ipairs = ipairs
local format = string.format
local GetTime = GetTime
local C_Timer = C_Timer

-- Timestamp format mappings
local TIMESTAMP_FORMATS = {
    ["HHMM"] = "TIMESTAMP_FORMAT_HHMM",
    ["HHMMSS"] = "TIMESTAMP_FORMAT_HHMMSS", 
    ["HHMM_24HR"] = "TIMESTAMP_FORMAT_HHMM_24HR",
    ["HHMMSS_24HR"] = "TIMESTAMP_FORMAT_HHMMSS_24HR",
    ["HHMM_AMPM"] = "TIMESTAMP_FORMAT_HHMM_AMPM",
    ["HHMMSS_AMPM"] = "TIMESTAMP_FORMAT_HHMMSS_AMPM"
}

-- Color coding for timestamp age (if enabled)
local function GetTimestampColor()
    if not C.chat.timestampColor then
        return "|cffffffff" -- White if coloring disabled
    end
    
    -- Return a subtle gray color for timestamps
    return "|cff888888"
end

-- Custom timestamp formats with color support
local CUSTOM_FORMATS = {
    ["HHMM"] = function() 
        return GetTimestampColor() .. "[" .. date("%I:%M") .. "]|r "
    end,
    ["HHMMSS"] = function() 
        return GetTimestampColor() .. "[" .. date("%I:%M:%S") .. "]|r "
    end,
    ["HHMM_24HR"] = function() 
        return GetTimestampColor() .. "[" .. date("%H:%M") .. "]|r "
    end,
    ["HHMMSS_24HR"] = function() 
        return GetTimestampColor() .. "[" .. date("%H:%M:%S") .. "]|r "
    end,
    ["HHMM_AMPM"] = function() 
        return GetTimestampColor() .. "[" .. date("%I:%M %p") .. "]|r "
    end,
    ["HHMMSS_AMPM"] = function() 
        return GetTimestampColor() .. "[" .. date("%I:%M:%S %p") .. "]|r "
    end
}

-- Store original AddMessage functions
local originalAddMessage = {}

-- Precompiled "already has timestamp" patterns (covers colored and plain)
local P1, P2, P3, P4 = "^%[%d+:%d+", "^|c%x%x%x%x%x%x%x%x%[%d+:%d+", "^%d+:%d+", "^|c%x%x%x%x%x%x%x%x%d+:%d+"
-- Function to check if a message already has a timestamp
local function HasTimestamp(text)
    if not text or type(text) ~= "string" then
        return false
    end
    return (match(text, P1) or match(text, P2) or match(text, P3) or match(text, P4)) and true or false
end

-- Enhanced AddMessage function with timestamp support
local function AddMessageWithTimestamp(frame, text, ...)
    if type(text) == "string" and text ~= "" then
        -- Check if message already has a timestamp to avoid double-timestamping
        if not HasTimestamp(text) then
            local timestampFormat = C.chat.timestampFormat or "HHMM"
            local customFormat = CUSTOM_FORMATS[timestampFormat]
            
            if customFormat then
                text = customFormat() .. text
            end
        end
    end
    
    -- Call original AddMessage
    return originalAddMessage[frame](frame, text, ...)
end

-- Apply timestamp formatting to a specific frame
local function SetupFrameTimestamps(frame)
    if frame and frame.AddMessage and not originalAddMessage[frame] then
        originalAddMessage[frame] = frame.AddMessage
        frame.AddMessage = AddMessageWithTimestamp
    end
end

-- Apply timestamp formatting to all chat frames
local function SetupTimestamps()
    -- Disable Blizzard's built-in timestamp system to prevent double timestamps
    SetCVar("showTimestamps", "none")
    
    -- Set up global timestamp formats (for any remaining Blizzard timestamp usage)
    local formatKey = TIMESTAMP_FORMATS[C.chat.timestampFormat]
    if formatKey then
        local ts = rawget(_G, formatKey)
        if ts ~= nil then
            local customFormat = CUSTOM_FORMATS[C.chat.timestampFormat]
            if customFormat then
                _G[formatKey] = customFormat()
            end
        end
    end
    
    -- Hook AddMessage for all existing chat frames
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        SetupFrameTimestamps(frame)
    end
    
    -- Special handling for Combat Log (ChatFrame2)
    local combatFrame = _G["ChatFrame2"]
    if combatFrame then
        SetupFrameTimestamps(combatFrame)
    end
end

-- Handle temporary chat frames
local function SetupTempChatTimestamps()
    local frame = FCF_GetCurrentChatFrame()
    SetupFrameTimestamps(frame)
end

-- Initialize timestamp system
local TimestampFrame = CreateFrame("Frame")
TimestampFrame:RegisterEvent("ADDON_LOADED")
TimestampFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

TimestampFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "Blizzard_CombatLog" then
            -- Setup timestamps for combat log when it loads
            C_Timer.After(0.1, SetupTimestamps)
        elseif addon == "RefineUI" then
            -- Initial setup
            SetupTimestamps()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure timestamps are applied after full initialization
        C_Timer.After(1, function()
            SetupTimestamps()
            
            -- Hook temporary chat frame creation if not already done
            if not _G.RefineUI_TimestampTempHooked then
                hooksecurefunc("FCF_OpenTemporaryWindow", SetupTempChatTimestamps)
                _G.RefineUI_TimestampTempHooked = true
            end
        end)
        
        -- Unregister this event as we only need it once
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

-- Public function to update timestamp settings (for potential future config UI)
function RefineUI_UpdateTimestampSettings()
    SetupTimestamps()
end

-- Debug function to test timestamps
local function TestTimestamps()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame and frame:IsVisible() then
            frame:AddMessage("RefineUI Timestamp Test " .. i .. " - " .. date("%c"))
        end
    end
end

-- Slash command for testing (can be removed in production)
SLASH_RUITIMESTAMP1 = "/ruitest"
SlashCmdList["RUITIMESTAMP"] = function()
    TestTimestamps()
    print("RefineUI: Timestamp test messages sent to all visible chat frames")
end
