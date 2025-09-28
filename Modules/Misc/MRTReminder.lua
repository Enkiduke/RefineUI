local R, C, L = unpack(RefineUI)
-- Hot-path upvalues
local _G = _G
local GetTime, UnitName, GetSpellInfo, IsInInstance, InCombatLockdown =
	GetTime, UnitName, GetSpellInfo, IsInInstance, InCombatLockdown
local insert, remove, wipe, ipairs, type, select = table.insert, table.remove, wipe, ipairs, type, select

local MRTReminder = {
	data = {},
	parsedData = {},
	_nextIdx = 1,
	_noteParseDeferred = false,
}
R.MRTReminder = MRTReminder

if not C.mrtreminder.enable or not C_AddOns.IsAddOnLoaded("BigWigs") then
    return
end

local BigWigsLoader = rawget(_G, "BigWigsLoader")

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function MRTReminder:RegisterEvent(event, handlerName)
    eventFrame:RegisterEvent(event)
    eventHandlers[event] = handlerName
end

function MRTReminder:UnregisterEvent(event)
    eventFrame:UnregisterEvent(event)
    eventHandlers[event] = nil
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local methodName = eventHandlers[event]
    local method = methodName and MRTReminder[methodName]
    if method then method(MRTReminder, event, ...) end
end)

local timerFrame = CreateFrame("Frame")
local timers = {}

function MRTReminder:ScheduleTimer(func, delay, ...)
    local args = select("#", ...) > 0 and { ... } or nil
    local t = {
        func = func,
        args = args,
        expires = GetTime() + delay
    }
    insert(timers, t)
    if not timerFrame._armed then
        timerFrame._armed = true
        timerFrame:SetScript("OnUpdate", MRTReminder._TimerOnUpdate)
    end
    return t
end

local spellCache = {}

local function getCachedSpellInfo(spellID)
    if not spellCache[spellID] then
        spellCache[spellID] = {GetSpellInfo(spellID)}
    end
    return unpack(spellCache[spellID])
end

function MRTReminder:IsNoteEnabledAndShowing()

    local inInstance, instanceType = IsInInstance()
    if not (inInstance and instanceType == "raid") then
        return false
    end

    return true
end

function MRTReminder:CancelTimer(timer)
    for i, t in ipairs(timers) do
        if t == timer then
            remove(timers, i)
            break
        end
    end
    if #timers == 0 then
        timerFrame:SetScript("OnUpdate", nil)
        timerFrame._armed = false
    end
end

function MRTReminder:CancelAllTimers()
    if #timers > 0 then wipe(timers) end
    timerFrame:SetScript("OnUpdate", nil)
    timerFrame._armed = false
end

function MRTReminder:_TimerOnUpdate()
    local now = GetTime()
    for i = #timers, 1, -1 do
        local timer = timers[i]
        if now >= timer.expires then
            remove(timers, i)
            if type(timer.func) == "function" then
                if timer.args then timer.func(unpack(timer.args)) else timer.func() end
            elseif type(timer.func) == "string" and type(MRTReminder[timer.func]) == "function" then
                if timer.args then MRTReminder[timer.func](MRTReminder, unpack(timer.args)) else MRTReminder[timer.func](MRTReminder) end
            end
        end
    end
    if #timers == 0 then
        timerFrame:SetScript("OnUpdate", nil)
        timerFrame._armed = false
    end
end

function MRTReminder:OnInitialize()
    if not C.mrtreminder.enable then 
        return 
    end

    self.data = {}
    self.parsedData = {}

    self:RegisterEvent("CHAT_MSG_ADDON", "OnMRTUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPEW")
    self:RegisterEvent("ENCOUNTER_START", "OnBossPulled")
    self:RegisterEvent("ENCOUNTER_END", "OnBossFightEnd")

    self:_RegisterBigWigs()
    self.playerName = UnitName("player")
end


function MRTReminder:OnMRTUpdate(event, prefix, message, channel, sender)
    if prefix == "EXRTADD" and message:sub(1, 9) == "multiline" then
        if not self._noteParseDeferred then
            self._noteParseDeferred = true
            self:ScheduleTimer(function()
                self._noteParseDeferred = false
                self:ParseNote()
            end, 0.05)
        end
    end
end

function MRTReminder:_RegisterBigWigs()
    if BigWigsLoader then
        BigWigsLoader.RegisterMessage(self, "BigWigs_StartBar", "OnBigWigsStartBar")
        BigWigsLoader.RegisterMessage(self, "BigWigs_StopBar", "OnBigWigsStopBar")
    end
end

function MRTReminder:OnBigWigsStartBar(event, module, spellId, text, duration, icon)
end

function MRTReminder:OnBigWigsStopBar(event, module, text)
end

function MRTReminder:StartBigWigsBar(time, spellID, playerName)
    if not BigWigsLoader then
        return
    end
    local spellName, _, spellTexture = getCachedSpellInfo(spellID)
    if not spellName then
        return
    end
    local text = playerName .. ": " .. spellName
    BigWigsLoader.SendMessage(self, "BigWigs_StartBar", nil, spellID, text, time, spellTexture)
end

function MRTReminder:StopBigWigsBar(spellID, playerName)
    if not BigWigsLoader then
        return
    end
    local spellName = getCachedSpellInfo(spellID)
    local text = playerName .. ": " .. spellName
    BigWigsLoader.SendMessage(self, "BigWigs_StopBar", nil, text)
end

function MRTReminder:ParseNote()
    if not self:IsNoteEnabledAndShowing() then
        return
    end

	local vmrt = rawget(_G, 'VMRT')
	local noteText = vmrt and vmrt.Note and vmrt.Note.Text1
	local playerName = self.playerName or UnitName("player")

    if not noteText or noteText == "" then
        return
    end

	if not self.data then self.data = {} else wipe(self.data) end
	if not self.parsedData then self.parsedData = {} else wipe(self.parsedData) end

    for line in noteText:gmatch("[^\r\n]+") do
        local timeInfo, spellInfo, playerInfo = line:match("{time:([^}]*)}{spell:(%d+)}[^-]+-(.+)")
        if timeInfo and spellInfo and playerInfo then
            local time = self:ParseTime(timeInfo)

            for entryPlayerName, playerSpellID in playerInfo:gmatch("(%S+)%s+{spell:(%d+)}") do
                if entryPlayerName == playerName then
                    local newEntry = {
                        time = time,
                        player = {
                            name = entryPlayerName,
                            spellID = tonumber(playerSpellID)
                        }
                    }
					insert(self.data, newEntry)
					insert(self.parsedData, newEntry)
                end
            end
        end
    end
	-- Sort once & reset pointer
	self:SortData()
	self._nextIdx = 1
end

function MRTReminder:ParseTime(timeInfo)
    local minutes, seconds = timeInfo:match("(%d+):(%d+)")
    return (tonumber(minutes) * 60) + tonumber(seconds)
end

function MRTReminder:SortData()
    table.sort(self.data, function(a, b) return a.time < b.time end)
    table.sort(self.parsedData, function(a, b) return a.time < b.time end)
end

-- function MRTReminder:OnMRTUpdate(event, prefix, message, channel, sender)
--     if prefix == "EXRTADD" and message:sub(1, 9) == "multiline" then
--         self.noteText = VMRT.Note.Text1
--     end
-- end

function MRTReminder:StartFightTimer()
    if not self.parsedData or #self.parsedData == 0 then
        return
    end

    self.fightStartTime = GetTime()
    self._nextIdx = 1
    self:ScheduleTimer("CheckTimedReminders", 0.05)
end

function MRTReminder:CheckTimedReminders()
    if not self:IsNoteEnabledAndShowing() then
        return
    end

    if not self.parsedData or #self.parsedData == 0 then
        return
    end

    local t = GetTime() - self.fightStartTime
    local idx = self._nextIdx
    local n = #self.parsedData
    local auto = C.mrtreminder.autoShow or 3
    local nextWake = nil

    while idx <= n do
        local item = self.parsedData[idx]
        local dt = item.time - t
        if item.reminded then
            idx = idx + 1
        elseif dt <= auto and dt > 0 then
            self:StartBigWigsBar(dt, item.player.spellID, item.player.name)
            self:ShowReminder(item)
            item.reminded = true
            idx = idx + 1
        elseif dt <= 0 then
            item.reminded = true
            idx = idx + 1
        else
            nextWake = dt - auto
            break
        end
    end

    self._nextIdx = idx
    if idx <= n then
        self:ScheduleTimer("CheckTimedReminders", math.max(0.05, nextWake or 0.1))
    end
end

function MRTReminder:OnBossPulled()
    if not self:IsNoteEnabledAndShowing() then
        return
    end

    self:ParseNote()
    
    if self.parsedData and #self.parsedData > 0 then
        self:StartFightTimer()
    end
end

function MRTReminder:OnBossFightEnd()
    local inInst, instType = IsInInstance()
    if inInst and instType == "raid" then
        self:CancelAllTimers()

        if self.parsedData then
            for _, data in ipairs(self.parsedData) do
                if not data.reminded then
                    self:StopBigWigsBar(data.player.spellID, data.player.name)
                end
            end
        end

        if self.parsedData then
            for _, data in ipairs(self.parsedData) do
                data.reminded = false
            end
        end
    end
end

function MRTReminder:ShowReminder(data)
    local spellName = getCachedSpellInfo(data.player.spellID)

    if C.mrtreminder.sound then
        PlaySoundFile(C.mrtreminder.sound, "Master")
        self:ScheduleTimer(function()
            if C.mrtreminder.speech then
                if C_VoiceChat and C_VoiceChat.SpeakText then
                    C_VoiceChat.SpeakText(1, spellName, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
                elseif TextToSpeech_Speak then
                    pcall(function() TextToSpeech_Speak(spellName, Enum.VoiceTtsDestination.LocalPlayback) end)
                end
            end
        end, 1)
    elseif C.mrtreminder.speech then
        if C_VoiceChat and C_VoiceChat.SpeakText then
            C_VoiceChat.SpeakText(1, spellName, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
        elseif TextToSpeech_Speak then
            pcall(function() TextToSpeech_Speak(spellName, Enum.VoiceTtsDestination.LocalPlayback) end)
        end
    end
end

function MRTReminder:OnPEW()
	-- refresh cached player name defensively (rarely changes)
	self.playerName = UnitName("player")
end

MRTReminder:OnInitialize()

