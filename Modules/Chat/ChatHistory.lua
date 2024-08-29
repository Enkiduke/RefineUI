local R, C, L = unpack(RefineUI)
if not C.chat.history then return end

----------------------------------------------------------------------------------------
-- Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local ChatFrame_MessageEventHandler = ChatFrame_MessageEventHandler
local ChatEdit_SetLastTellTarget = ChatEdit_SetLastTellTarget
local IsLoggedIn = IsLoggedIn
local UnitGUID = UnitGUID
local date, time, type, unpack = date, time, type, unpack
local tinsert, tremove = table.insert, table.remove

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LOG_MAX = 500
local CHAT_FRAME = ChatFrame1
local PLAYER_FLAG = "CHAT_HISTORY_PLAYER_ENTRY"
local PLAYER_TEXT = "|TInterface\\GossipFrame\\WorkOrderGossipIcon.blp:0:0:1:-2:0:0:0:0:0:0:0:0:0|t "
local ENTRY_FLAG, ENTRY_GUID, ENTRY_EVENT, ENTRY_TIME = 6, 12, 30, 31

----------------------------------------------------------------------------------------
-- Local variables
----------------------------------------------------------------------------------------
local chatHistoryFrame = CreateFrame("Frame", "RefineUIChatHistoryFrame")
RefineUIChatHistoryDB = RefineUIChatHistoryDB or {}

----------------------------------------------------------------------------------------
-- Chat events to monitor
----------------------------------------------------------------------------------------
local EVENTS = {
    "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_SAY", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_YELL", "CHAT_MSG_SYSTEM"
}

----------------------------------------------------------------------------------------
-- Utility functions
----------------------------------------------------------------------------------------
local function PrintChatHistory()
    local temp

    chatHistoryFrame.IsPrinting = true

    for i = #RefineUIChatHistoryDB, 1, -1 do
        temp = RefineUIChatHistoryDB[i]
        ChatFrame_MessageEventHandler(CHAT_FRAME, temp[ENTRY_EVENT], unpack(temp))
    end

    chatHistoryFrame.IsPrinting = false
    chatHistoryFrame.HasPrinted = true

    if temp then
        CHAT_FRAME:AddMessage("---- Last message received " .. date("%x at %X", temp[ENTRY_TIME]) .. " ----")
    end
end

local function SaveChatMessage(event, ...)
    local temp = {...}

    if temp[1] then
        temp[ENTRY_EVENT] = event
        temp[ENTRY_TIME] = time()
        if event == "CHAT_MSG_SYSTEM" then
            temp[1] = tostring(PLAYER_TEXT..temp[1])
        end

        temp[ENTRY_FLAG] = PLAYER_FLAG

        tinsert(RefineUIChatHistoryDB, 1, temp)

        for i = LOG_MAX, #RefineUIChatHistoryDB do
            tremove(RefineUIChatHistoryDB, LOG_MAX)
        end
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
local function InitializeChatHistory()
    RefineUIChatHistoryDB = type(RefineUIChatHistoryDB) == "table" and RefineUIChatHistoryDB or {}
    _G["CHAT_FLAG_" .. PLAYER_FLAG] = PLAYER_TEXT

    local originalChatEdit_SetLastTellTarget = ChatEdit_SetLastTellTarget

    _G.ChatEdit_SetLastTellTarget = function(...)
        if chatHistoryFrame.IsPrinting then
            return
        end
        return originalChatEdit_SetLastTellTarget(...)
    end

    for i = 1, #EVENTS do
        chatHistoryFrame:RegisterEvent(EVENTS[i])
    end

    if IsLoggedIn() then
        OnChatHistoryEvent(chatHistoryFrame, "PLAYER_LOGIN")
    else
        chatHistoryFrame:RegisterEvent("PLAYER_LOGIN")
    end
end

----------------------------------------------------------------------------------------
-- Event handling
----------------------------------------------------------------------------------------
local function OnChatHistoryEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "RefineUI" then
            self:UnregisterEvent(event)
            InitializeChatHistory()
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent(event)
        self.PlayerGUID = UnitGUID("player")
        PrintChatHistory()
    elseif self.HasPrinted then
        SaveChatMessage(event, ...)
    end
end

----------------------------------------------------------------------------------------
-- Chat History Frame initialization
----------------------------------------------------------------------------------------
chatHistoryFrame:RegisterEvent("ADDON_LOADED")
chatHistoryFrame:SetScript("OnEvent", OnChatHistoryEvent)