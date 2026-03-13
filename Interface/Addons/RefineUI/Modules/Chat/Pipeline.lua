----------------------------------------------------------------------------------------
-- Chat message pipeline for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local lower = string.lower
local pairs = pairs
local strsub = string.sub
local strlen = string.len
local strupper = string.upper
local type = type
local pcall = pcall

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_ChatInfo = C_ChatInfo
local ChatFrameUtil = ChatFrameUtil
local ChatTypeInfo = ChatTypeInfo
local FCF_GetCurrentChatFrame = FCF_GetCurrentChatFrame
local FCFManager_GetChatTarget = FCFManager_GetChatTarget
local FCFManager_ShouldSuppressMessage = FCFManager_ShouldSuppressMessage
local FlashClientIcon = FlashClientIcon
local GetCVar = GetCVar
local GetCVarBool = GetCVarBool
local GetTime = GetTime
local IsCombatLog = IsCombatLog
local PlaySound = PlaySound
local TextToSpeechFrame_MessageEventHandler = TextToSpeechFrame_MessageEventHandler

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local FRAME_STATE_REGISTRY = "ChatPipeline:FrameState"
local PIPELINE_TEMP_WINDOW_KEY = "ChatPipeline:FCF_OpenTemporaryWindow"
local SIMPLE_TYPES = {
    BN_WHISPER_PLAYER_OFFLINE = true,
    CURRENCY = true,
    FILTERED = true,
    IGNORED = true,
    LOOT = true,
    MONEY = true,
    OPENING = true,
    PET_INFO = true,
    RESTRICTED = true,
    SKILL = true,
    SYSTEM = true,
    TARGETICONS = true,
    TRADESKILLS = true,
}
local GENERAL_TYPES = {
    ACHIEVEMENT = true,
    BN_WHISPER = true,
    BN_WHISPER_INFORM = true,
    CHANNEL = true,
    COMMUNITIES_CHANNEL = true,
    EMOTE = true,
    GUILD = true,
    GUILD_ACHIEVEMENT = true,
    INSTANCE_CHAT = true,
    INSTANCE_CHAT_LEADER = true,
    OFFICER = true,
    PARTY = true,
    PARTY_LEADER = true,
    RAID = true,
    RAID_LEADER = true,
    RAID_WARNING = true,
    SAY = true,
    TEXT_EMOTE = true,
    WHISPER = true,
    WHISPER_INFORM = true,
    YELL = true,
}

local function IsAccessibleString(value)
    if RefineUI.IsAccessibleString then
        return RefineUI:IsAccessibleString(value)
    end
    return type(value) == "string"
end

local function IsSupportedChatType(chatType)
    if SIMPLE_TYPES[chatType] or GENERAL_TYPES[chatType] then
        return true
    end
    return strsub(chatType, 1, 7) == "COMBAT_" or strsub(chatType, 1, 6) == "SPELL_" or strsub(chatType, 1, 10) == "BG_SYSTEM_"
end

local function GetFrameState(frame)
    local state = RefineUI:RegistryGet(FRAME_STATE_REGISTRY, frame)
    if type(state) ~= "table" then
        state = {}
        RefineUI:RegistrySet(FRAME_STATE_REGISTRY, frame, nil, state)
    end
    return state
end

local function EnsureRegionalChannel(chatFrame, eventType, channelID)
    if chatFrame ~= DEFAULT_CHAT_FRAME or eventType ~= "YOU_CHANGED" then
        return false
    end
    if not C_ChatInfo or not C_ChatInfo.IsChannelRegionalForChannelID or not C_ChatInfo.GetChannelShortcutForChannelID then
        return false
    end
    if not C_ChatInfo.IsChannelRegionalForChannelID(channelID) then
        return false
    end
    return chatFrame:AddChannel(C_ChatInfo.GetChannelShortcutForChannelID(channelID)) ~= nil
end

function Chat:ShouldUseMessagePipeline(frame)
    if not frame or type(frame.GetID) ~= "function" then
        return false
    end
    local frameID = frame:GetID()
    if type(IsCombatLog) == "function" and IsCombatLog(frameID) then
        return false
    end
    return true
end

function Chat:CallOriginalAddMessage(frame, ...)
    local state = GetFrameState(frame)
    local original = state.originalAddMessage
    if type(original) == "function" then
        return original(frame, ...)
    end
    return nil
end

function Chat:CallOriginalOnEvent(frame, event, ...)
    local state = GetFrameState(frame)
    local original = state.originalOnEvent
    if type(original) == "function" then
        return original(frame, event, ...)
    end
    return nil
end

function Chat:PipelineAddMessage(frame, body, r, g, b, infoID, accessID, typeID, event, eventArgs, msgFormatter, ...)
    local edited = body
    local state = GetFrameState(frame)
    if self.AddMessageEdits then
        edited = self:AddMessageEdits(frame, body, {
            accessID = accessID,
            event = event,
            fromPipeline = state.isPipelineDispatch == true,
            infoID = infoID,
            typeID = typeID,
        })
    end
    return self:CallOriginalAddMessage(frame, edited, r, g, b, infoID, accessID, typeID, event, eventArgs, msgFormatter, ...)
end

function Chat:EmitPipelineMessage(frame, ...)
    local state = GetFrameState(frame)
    state.isPipelineDispatch = true
    local ok, result = pcall(frame.AddMessage, frame, ...)
    state.isPipelineDispatch = nil
    if ok then
        return result
    end
    error(result)
end

function Chat:ChatFrame_ConfigEventHandler(frame, ...)
    local handler = ChatFrameMixin and ChatFrameMixin.ConfigEventHandler or _G.ChatFrame_ConfigEventHandler
    if type(handler) == "function" then
        return handler(frame, ...)
    end
    return nil
end

function Chat:ChatFrame_SystemEventHandler(frame, ...)
    local handler = ChatFrameMixin and ChatFrameMixin.SystemEventHandler or _G.ChatFrame_SystemEventHandler
    if type(handler) == "function" then
        return handler(frame, ...)
    end
    return nil
end

function Chat:ChatFrame_OnEvent(frame, event, ...)
    if frame.customEventHandler and frame.customEventHandler(frame, event, ...) then
        return
    end

    if self:ChatFrame_ConfigEventHandler(frame, event, ...) then
        return
    end
    if self:ChatFrame_SystemEventHandler(frame, event, ...) then
        return
    end
    if self:ChatFrame_MessageEventHandler(frame, event, ...) then
        return
    end

    self:CallOriginalOnEvent(frame, event, ...)
end

function Chat:ChatFrame_MessageEventHandler(frame, event, ...)
    if type(event) ~= "string" or strsub(event, 1, 8) ~= "CHAT_MSG" then
        return false
    end

    local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17 = ...
    if arg16 then
        return true
    end

    local chatType = strsub(event, 10)
    if not IsSupportedChatType(chatType) then
        return false
    end

    if type(TextToSpeechFrame_MessageEventHandler) == "function" then
        TextToSpeechFrame_MessageEventHandler(frame, event, ...)
    end

    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if not info then
        return false
    end

    if arg6 == "GM" and chatType == "WHISPER" then
        return false
    end

    local shouldDiscard
    shouldDiscard, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14 =
        ChatFrameUtil.ProcessMessageEventFilters(frame, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
    if shouldDiscard then
        return true
    end

    local coloredName = ChatFrameUtil.GetDecoratedSenderName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14)
    local channelLength = IsAccessibleString(arg4) and strlen(arg4) or 0
    local infoType = chatType

    if chatType == "VOICE_TEXT" and type(GetCVarBool) == "function" and not GetCVarBool("speechToText") then
        return true
    end

    if chatType == "COMMUNITIES_CHANNEL" or (strsub(chatType, 1, 7) == "CHANNEL" and chatType ~= "CHANNEL_LIST" and (arg1 ~= "INVITE" or chatType ~= "CHANNEL_NOTICE_USER")) then
        local found = false
        for index, value in pairs(frame.channelList or {}) do
            if channelLength > strlen(value) then
                if ((arg7 and arg7 > 0) and frame.zoneChannelList and frame.zoneChannelList[index] == arg7) or (strupper(value) == strupper(arg9 or "")) then
                    found = true
                    infoType = "CHANNEL" .. arg8
                    info = ChatTypeInfo[infoType]
                    break
                end
            end
        end

        if not found or not info then
            if not EnsureRegionalChannel(frame, arg1, arg7) then
                return true
            end
            infoType = "CHANNEL" .. arg8
            info = ChatTypeInfo[infoType] or info
        end
    end

    local chatGroup = ChatFrameUtil.GetChatCategory(chatType)
    local chatTarget = FCFManager_GetChatTarget(chatGroup, arg2, arg8)

    if FCFManager_ShouldSuppressMessage(frame, chatGroup, chatTarget) then
        return true
    end

    if chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" then
        local senderKey = type(arg2) == "string" and lower(arg2) or nil
        if senderKey and frame.privateMessageList and not frame.privateMessageList[senderKey] then
            return true
        elseif senderKey and frame.excludePrivateMessageList and frame.excludePrivateMessageList[senderKey] and type(GetCVar) == "function" and GetCVar("whisperMode") ~= "popout_and_inline" then
            return true
        end
    end

    if frame.privateMessageList then
        if (chatGroup == "BN_INLINE_TOAST_ALERT" or chatGroup == "BN_WHISPER_PLAYER_OFFLINE") and type(arg2) == "string" and not frame.privateMessageList[lower(arg2)] then
            return true
        end

        if chatGroup == "SYSTEM" and IsAccessibleString(arg1) then
            local matchFound = false
            local loweredMessage = lower(arg1)
            for playerName in pairs(frame.privateMessageList) do
                if loweredMessage == lower(format(ERR_CHAT_PLAYER_NOT_FOUND_S, playerName))
                    or loweredMessage == lower(format(ERR_FRIEND_ONLINE_SS, playerName, playerName))
                    or loweredMessage == lower(format(ERR_FRIEND_OFFLINE_S, playerName)) then
                    matchFound = true
                    break
                end
            end
            if not matchFound then
                return true
            end
        end
    end

    if SIMPLE_TYPES[chatType] or strsub(chatType, 1, 7) == "COMBAT_" or strsub(chatType, 1, 6) == "SPELL_" or strsub(chatType, 1, 10) == "BG_SYSTEM_" then
        self:EmitPipelineMessage(frame, arg1, info.r, info.g, info.b, info.id, nil, nil, event)
    elseif chatType == "ACHIEVEMENT" or chatType == "GUILD_ACHIEVEMENT" then
        local playerLink
        if type(GetPlayerLink) == "function" and IsAccessibleString(arg2) and IsAccessibleString(coloredName) then
            playerLink = GetPlayerLink(arg2, format("[%s]", coloredName))
        end
        local message = playerLink and IsAccessibleString(arg1) and format(arg1, playerLink) or arg1
        self:EmitPipelineMessage(frame, message, info.r, info.g, info.b, info.id, nil, nil, event)
    else
        local accessID = self.GetAccessID and self:GetAccessID(chatGroup, chatTarget) or nil
        local typeID = self.GetAccessID and self:GetAccessID(infoType, chatTarget, arg12 or arg13) or nil
        local body = self:MessageFormatter(frame, info, chatType, chatGroup, chatTarget, coloredName, arg1, arg2, arg3, arg4, arg6, arg7, arg8, arg11, arg12, arg13, arg14, arg17)
        self:EmitPipelineMessage(frame, body or arg1, info.r, info.g, info.b, info.id, accessID, typeID, event)
    end

    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        if ChatFrameUtil and ChatFrameUtil.SetLastTellTarget and IsAccessibleString(arg2) then
            ChatFrameUtil.SetLastTellTarget(arg2, chatType)
        end

        if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.TELL_MESSAGE and type(GetTime) == "function" then
            local state = GetFrameState(frame)
            local nextWhisperAlertAt = state.nextWhisperAlertAt
            if not nextWhisperAlertAt or GetTime() > nextWhisperAlertAt then
                PlaySound(SOUNDKIT.TELL_MESSAGE)
            end
            state.nextWhisperAlertAt = GetTime() + ((ChatFrameConstants and ChatFrameConstants.WhisperSoundAlertCooldown) or 0)
        end

        if type(FlashClientIcon) == "function" then
            FlashClientIcon()
        end
    end

    if ChatFrameUtil and ChatFrameUtil.FlashTabIfNotShown then
        ChatFrameUtil.FlashTabIfNotShown(frame, info, chatType, chatGroup, chatTarget)
    end

    return true
end

function Chat:SetupMessageFrame(frame)
    if not self:ShouldUseMessagePipeline(frame) then
        return
    end

    local state = GetFrameState(frame)
    if state.installed then
        return
    end

    state.originalAddMessage = frame.AddMessage
    state.originalOnEvent = frame:GetScript("OnEvent")
    state.installed = true

    frame.AddMessage = function(messageFrame, ...)
        return Chat:PipelineAddMessage(messageFrame, ...)
    end
    frame:SetScript("OnEvent", function(messageFrame, event, ...)
        return Chat:ChatFrame_OnEvent(messageFrame, event, ...)
    end)
end

local function SetupTemporaryMessageFrame()
    local frame = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
    if frame then
        Chat:SetupMessageFrame(frame)
    end
end

function Chat:InstallMessagePipeline()
    if self._messagePipelineInstalled then
        return
    end
    self._messagePipelineInstalled = true

    RefineUI:CreateDataRegistry(FRAME_STATE_REGISTRY, "k")

    if CHAT_FRAMES then
        for _, frameName in pairs(CHAT_FRAMES) do
            local frame = _G[frameName]
            if frame then
                self:SetupMessageFrame(frame)
            end
        end
    end

    RefineUI:HookOnce(PIPELINE_TEMP_WINDOW_KEY, "FCF_OpenTemporaryWindow", SetupTemporaryMessageFrame)
end
