----------------------------------------------------------------------------------------
-- RefineUI Commands
-- Description: Slash command handling and debug tools.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local print = print
local pairs = pairs
local sort = table.sort
local tonumber = tonumber
local tostring = tostring
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitReaction = UnitReaction
local UnitCanAttack = UnitCanAttack
local UnitIsEnemy = UnitIsEnemy
local UnitFactionGroup = UnitFactionGroup
local UnitClassification = UnitClassification

----------------------------------------------------------------------------------------
-- Debug Tools
----------------------------------------------------------------------------------------

function RefineUI:DebugTarget()
    local unit = "target"
    if not UnitExists(unit) then
        print("|cff00ccffRefineUI:|r No target selected.")
        return
    end

    local name = UnitName(unit) or "Unknown"
    local guid = UnitGUID(unit) or "None"
    local reaction = UnitReaction("player", unit) or "Nil"
    local canAttack = UnitCanAttack("player", unit)
    local isEnemy = UnitIsEnemy("player", unit)
    local faction = UnitFactionGroup(unit) or "Nil"
    local classification = UnitClassification(unit) or "Nil"
    
    -- Extract NPC ID from GUID
    local npcID = "Player/Unknown"
    if guid then
        local _, _, _, _, _, id = strsplit("-", guid)
        npcID = id or "Unknown"
    end

    print("----------------------------------------")
    print("|cff00ccffRefineUI Debug: Target Info|r")
    print("Name: " .. name)
    print("NPC ID: " .. npcID)
    print("GUID: " .. guid)
    print("Reaction: " .. reaction)
    print("Can Attack: " .. (canAttack and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    print("Is Enemy: " .. (isEnemy and "|cff00ff00Yes|r" or "|cffff0000No|r"))
    print("Faction: " .. faction)
    print("Classification: " .. classification)
    print("----------------------------------------")
end

local function sortedTopN(counterMap, limit)
    local list = {}
    if type(counterMap) ~= "table" then
        return list
    end

    for key, value in pairs(counterMap) do
        if type(value) == "number" and value > 0 then
            list[#list + 1] = { key = key, value = value }
        end
    end

    sort(list, function(a, b)
        if a.value == b.value then
            return tostring(a.key) < tostring(b.key)
        end
        return a.value > b.value
    end)

    if #list > limit then
        for i = #list, limit + 1, -1 do
            list[i] = nil
        end
    end
    return list
end

local function dumpObservability(rest)
    local limit = tonumber(rest) or 8
    if limit < 1 then limit = 1 end
    if limit > 20 then limit = 20 end

    local snapshot = RefineUI:GetObservabilitySnapshot()
    local status = snapshot.enabled and "ON" or "OFF"
    RefineUI:Print("Observability: %s", status)

    local eventFired = sortedTopN(snapshot.events and snapshot.events.fired, limit)
    local hookCalls = sortedTopN(snapshot.hooks and snapshot.hooks.calls, limit)

    if #eventFired == 0 and #hookCalls == 0 then
        RefineUI:Print("Observability: no event/hook calls recorded yet.")
        return
    end

    for i = 1, #eventFired do
        local row = eventFired[i]
        RefineUI:Print("Obs Event: %s = %d", row.key, row.value)
    end

    for i = 1, #hookCalls do
        local row = hookCalls[i]
        RefineUI:Print("Obs Hook: %s = %d", row.key, row.value)
    end
end

local function setObservabilityEnabled(enabled)
    local general = RefineUI.Config and RefineUI.Config.General
    if general then
        general.Debug = general.Debug or {}
        general.Debug.Observability = enabled and true or false
    end
    RefineUI:SetObservabilityEnabled(enabled and true or false)
    RefineUI:Print("Observability: %s", enabled and "enabled" or "disabled")
end

local function handleDebugObservability(rest)
    local action, arg = rest:match("^(%S*)%s*(.-)$")
    action = (action or ""):lower()

    if action == "on" then
        setObservabilityEnabled(true)
    elseif action == "off" then
        setObservabilityEnabled(false)
    elseif action == "dump" then
        dumpObservability(arg)
    elseif action == "reset" then
        RefineUI:ResetObservabilityCounters()
        RefineUI:Print("Observability: counters reset.")
    else
        RefineUI:Print("Usage: /refine debug obs on|off|dump|reset")
    end
end

local function handleDebugCommand(msg)
    local group, rest = msg:match("^(%S*)%s*(.-)$")
    group = (group or ""):lower()

    if group == "obs" then
        handleDebugObservability(rest)
        return
    end

    RefineUI:Print("Usage: /refine debug obs on|off|dump|reset")
end

----------------------------------------------------------------------------------------
-- Slash Commands
----------------------------------------------------------------------------------------

function RefineUI:LoadDebugCommands()
    self.ChatCommands = self.ChatCommands or {}
    self.ChatCommands["debugtarget"] = function()
        RefineUI:DebugTarget()
    end
    self.ChatCommands["dt"] = self.ChatCommands["debugtarget"]
    self.ChatCommands["debug"] = function(msg)
        handleDebugCommand(msg or "")
    end
    self:RegisterChatCommand("rdt", self.ChatCommands["debugtarget"])
end
