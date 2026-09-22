----------------------------------------------------------------------------------------
-- Chat message pipeline for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local KEYSTONE_LINK_EVENTS = {
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_SAY",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_YELL",
}

----------------------------------------------------------------------------------------
-- Message Filter
----------------------------------------------------------------------------------------
local function DecorateKeystoneLink(_, _, message, ...)
    if not Chat:IsAccessibleString(message) or Chat:MessageIsProtected(message) or not Chat.DecorateKeystoneLinks then
        return
    end

    local decorated = Chat:DecorateKeystoneLinks(message)
    if decorated ~= message then
        return false, decorated, ...
    end
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:InstallMessagePipeline()
    if self._messagePipelineInstalled then
        return
    end

    if type(ChatFrame_AddMessageEventFilter) ~= "function" then
        return
    end

    for i = 1, #KEYSTONE_LINK_EVENTS do
        ChatFrame_AddMessageEventFilter(KEYSTONE_LINK_EVENTS[i], DecorateKeystoneLink)
    end

    self._messagePipelineInstalled = true
end
