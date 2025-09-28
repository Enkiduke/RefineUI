local R, C, L = unpack(RefineUI)
if not C.chat.whisperSound then return end

----------------------------------------------------------------------------------------
-- Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Optional debounce (default OFF)
----------------------------------------------------------------------------------------
-- Example to enable: C.chat.whisperSoundDebounceMs = 200
local DEBOUNCE_MS = (C.chat.whisperSoundDebounceMs and tonumber(C.chat.whisperSoundDebounceMs)) or 0
local lastPlayMs = 0
local function ShouldPlay()
    if DEBOUNCE_MS <= 0 then
        return true
    end
    local nowMs = (GetTime() or 0) * 1000
    if (nowMs - lastPlayMs) >= DEBOUNCE_MS then
        lastPlayMs = nowMs
        return true
    end
    return false
end

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local WHISPER_EVENTS = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_BN_WHISPER"
}

----------------------------------------------------------------------------------------
-- Whisper Sound System
----------------------------------------------------------------------------------------
local function OnWhisperReceived(_, event)
    if C.media.whisperSound and ShouldPlay() then
        PlaySoundFile(C.media.whisperSound, "Master")
    end
end

local WhisperSoundSystem = CreateFrame("Frame")

for _, event in ipairs(WHISPER_EVENTS) do
    WhisperSoundSystem:RegisterEvent(event)
end

WhisperSoundSystem:SetScript("OnEvent", OnWhisperReceived)