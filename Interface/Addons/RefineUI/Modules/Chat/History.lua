----------------------------------------------------------------------------------------
-- History for RefineUI
-- Description: Saves chat history across sessions.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local table = table
local time = time
local type = type
local tostring = tostring
local issecretvalue = _G.issecretvalue

local function BuildChatHistoryHookKey(owner, method)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    return "ChatHistory:" .. ownerId .. ":" .. method
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

function Chat:SetupHistory()
    if not self.db.History then return end

    _G.RefineUIChatHistoryDB = _G.RefineUIChatHistoryDB or {}
    local DB = _G.RefineUIChatHistoryDB
    local CF, cfid, hook = {}, {}, {}
    local PLAYER_TEXT = RefineUI.Media.Logo and string.format("|T%s:14:14:0:0|t ", RefineUI.Media.Logo) or "|TInterface\\GossipFrame\\WorkOrderGossipIcon.blp:0:0:1:-2:0:0:0:0:0:0:0:0:0|t "
    local restoredOnce = false
    
    -- Populate initial ChatFrames (since FCF_SetWindowName hook misses frames created before load)
    for i = 1, _G.NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame"..i]
        if frame then
            CF[frame] = i
            cfid[i] = frame
        end
    end

    local function GetSeparator(ts)
        local LOGO = RefineUI.Media.Logo and string.format("|T%s:14:14:0:0|t ", RefineUI.Media.Logo) or PLAYER_TEXT
        if ts then
            return string.format("%s|cFFFFD200Chat History:|r |cFFFFFFFFLast message received %s|r", LOGO, date("%x at %X", ts))
        else
            return string.format("%s|cFFFFD200Chat History|r", LOGO)
        end
    end

    local function prnt(frame, message)
        if not frame.historyBuffer then return end
        
        -- Check if message is already a separator to avoid double printing if something slips through
        local historyMessage = message
        if not message:find("Chat History", 1, true) and not message:find(PLAYER_TEXT, 1, true) then
            historyMessage = PLAYER_TEXT .. message
        end
        
        frame.historyBuffer:PushFront({ 
            message = historyMessage, 
            r = 1, g = 1, b = 1, 
            extraData = { [1] = "temp", n = 1 }, 
            timestamp = GetTime() 
        })
        if frame:GetScrollOffset() ~= 0 then
            frame:ScrollUp()
        end
        frame:MarkDisplayDirty()
    end

    local function IsInitialWorldEntry(isInitialLogin, isReloadingUI)
        if isInitialLogin == nil and isReloadingUI == nil then
            return true
        end
        return isInitialLogin or isReloadingUI
    end

    local function GetOrderedElements(buffer)
        if not buffer or type(buffer.elements) ~= "table" then
            return {}
        end

        local indexed = {}
        for k, v in pairs(buffer.elements) do
            if type(k) == "number" and type(v) == "table" then
                indexed[#indexed + 1] = { k, v }
            end
        end

        table.sort(indexed, function(a, b)
            return a[1] < b[1]
        end)

        local ordered = {}
        for i = 1, #indexed do
            ordered[i] = indexed[i][2]
        end
        return ordered
    end

    local function CopySavableValue(value, seen)
        if issecretvalue and issecretvalue(value) then
            return nil
        end

        local valueType = type(value)
        if valueType == "nil" or valueType == "number" or valueType == "string" or valueType == "boolean" then
            return value
        end
        if valueType ~= "table" then
            return nil
        end

        seen = seen or {}
        if seen[value] then
            return seen[value]
        end

        local copy = {}
        seen[value] = copy
        for k, v in pairs(value) do
            local ck = CopySavableValue(k, seen)
            local cv = CopySavableValue(v, seen)
            if ck ~= nil and cv ~= nil then
                copy[ck] = cv
            end
        end
        return copy
    end

    local function PrepareSaveElement(element)
        if type(element) ~= "table" then return nil end
        if issecretvalue and issecretvalue(element.message) then return nil end

        local copy = CopySavableValue(element)
        if type(copy) ~= "table" or type(copy.message) ~= "string" then
            return nil
        end

        if copy.message:find("Chat History", 1, true) then
            return nil
        end
        if not copy.message:find(PLAYER_TEXT, 1, true) then
            copy.message = PLAYER_TEXT .. copy.message
        end

        return copy
    end

    local function SaveFrameHistory(frame, key)
        if not key or frame == _G.COMBATLOG or not frame or not frame.historyBuffer then
            return
        end

        local ordered = GetOrderedElements(frame.historyBuffer)
        local saveElements = {}
        for i = 1, #ordered do
            local prepared = PrepareSaveElement(ordered[i])
            if prepared then
                saveElements[#saveElements + 1] = prepared
            end
        end

        local max = frame.historyBuffer.maxElements
        if type(max) == "table" and max.value then max = max.value end
        if type(max) == "number" and max > 0 and #saveElements > max then
            local overflow = #saveElements - max
            for i = 1, max do
                saveElements[i] = saveElements[i + overflow]
            end
            for i = #saveElements, max + 1, -1 do
                saveElements[i] = nil
            end
        end

        DB[key] = {
            entries = saveElements,
            timestamp = time(),
        }
    end


    local function HookBuffer(frame)
        if frame == _G.COMBATLOG or not frame.historyBuffer then return end
        if hook[frame] then return end
        hook[frame] = true
        
        RefineUI:Hook(BuildChatHistoryHookKey(frame.historyBuffer, "PushFront"), frame.historyBuffer, "PushFront", function(buffer)
            local elements = buffer.elements
            local max = buffer.maxElements
            if type(max) == "table" and max.value then max = max.value end
            max = max or #elements or 0
            
            -- RefineUI: Removed manual clamping due to CircularBuffer changes in WoW 11.0+
            -- relying on default PushFront behavior to handle overflow.
        end)

        -- Polyfill ReplaceElements (missing in standard CircularBuffer)
        if not frame.historyBuffer.ReplaceElements then
            function frame.historyBuffer:ReplaceElements(newElements)
                self:Clear()
                -- Restore in reverse order so PushFront reconstructs the correct sequence
                for i = #newElements, 1, -1 do
                    self:PushFront(newElements[i])
                end
            end
        end
    end

    -- Update timestamps so elements don't fade instantly after computer restart
    local function UpdateTimestamps(frame)
        local nameorid = CF[frame] > NUM_CHAT_WINDOWS and frame.name or CF[frame]
        local timestamp = GetTime()
        local data = DB[nameorid]
        
        if data then
            -- Handle both old (array) and new ({entries, timestamp}) structures
            local entries = data.entries or data
            if type(entries) == "table" then
                for i = 1, #entries do
                    entries[i].timestamp = timestamp
                end
            end
            data.timestamp = timestamp -- Update the container timestamp as well
        end
    end

    local function SaveHistory()
        for frame, id in pairs(CF) do
            local key = id > NUM_CHAT_WINDOWS and frame.name or id
            SaveFrameHistory(frame, key)
        end
    end

    -- Initialization
    RefineUI:HookOnce("ChatHistory:FCF_SetWindowName", "FCF_SetWindowName", function(frame)
        local id = frame:GetID()
        CF[frame] = id
        cfid[id] = frame
    end)

    RefineUI:HookOnce("ChatHistory:FCFManager_RegisterDedicatedFrame", "FCFManager_RegisterDedicatedFrame", function(frame)
        if CF[frame] and CF[frame] > NUM_CHAT_WINDOWS then
            HookBuffer(frame)
            local saved = DB[frame.name]
            if saved then
                UpdateTimestamps(frame)
                -- Handle new vs old DB structure
                local entries = saved.entries or saved
                if type(entries) == "table" then
                     frame.historyBuffer:ReplaceElements(entries)
                end
                
                local ts = saved.timestamp
                prnt(frame, GetSeparator(ts))
            end
        end
    end)

    RefineUI:HookOnce("ChatHistory:FCFManager_UnregisterDedicatedFrame", "FCFManager_UnregisterDedicatedFrame", function(frame)
        if CF[frame] and CF[frame] > NUM_CHAT_WINDOWS and frame.historyBuffer then
            local key = frame.name or CF[frame] or (frame.GetID and frame:GetID())
            SaveFrameHistory(frame, key)
        end
    end)

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUI)
        if restoredOnce then return end
        if not IsInitialWorldEntry(isInitialLogin, isReloadingUI) then return end
        restoredOnce = true

        for id = 1, NUM_CHAT_WINDOWS do
            local frame = cfid[id]
            if frame and frame ~= _G.COMBATLOG then
                HookBuffer(frame)
                UpdateTimestamps(frame)
                
                local saved = DB[id]
                if saved then
                    local entries = saved.entries or saved
                    if type(entries) == "table" and #entries > 0 then
                        frame.historyBuffer:ReplaceElements(entries)
                        
                        local elements = frame.historyBuffer.elements
                        local max = frame.historyBuffer.maxElements
                        if type(max) == "table" and max.value then max = max.value end
                        max = max or #elements or 0
                    end
                    
                    local ts = saved.timestamp
                    prnt(frame, GetSeparator(ts))
                end
            end
        end
    end, "ChatHistory:Restore")

    RefineUI:RegisterEventCallback("PLAYER_LEAVING_WORLD", SaveHistory, "ChatHistory:Save")
    RefineUI:RegisterEventCallback("PLAYER_LOGOUT", SaveHistory, "ChatHistory:LogoutSave")
end
