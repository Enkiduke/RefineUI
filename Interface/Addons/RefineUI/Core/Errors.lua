----------------------------------------------------------------------------------------
-- RefineUI Errors
-- Description: Forwards caught errors to the active error handler (BugGrabber or
-- Blizzard) and prints a chat link that opens the error in a copy window.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local geterrorhandler = geterrorhandler
local debugstack = debugstack
local canaccessvalue = canaccessvalue
local tostring, tonumber = tostring, tonumber
local format = string.format
local gsub, match, sub = string.gsub, string.match, string.sub
local date = date
local print = print

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local MAX_ERRORS = 50
local MAX_SUMMARY_LENGTH = 160
local LINK_PATTERN = "^addon:" .. AddOnName .. ":error:(%d+)$"

local errors = {} -- errors[id] = { message, stack, count, time }
local errorIds = {} -- errorIds[message] = id
local linkHandlerRegistered = false

----------------------------------------------------------------------------------------
-- Internal
----------------------------------------------------------------------------------------
local function IsReadable(value)
    return not canaccessvalue or canaccessvalue(value)
end

local function OnSetItemRef(_, link)
    local id = match(link, LINK_PATTERN)
    local entry = id and errors[tonumber(id)]
    if not entry then return end

    RefineUI:ShowCopyWindow("RefineUI Error — Ctrl+C", format("%s %s | %s | x%d\n\n%s\n\n%s",
        AddOnName, tostring(RefineUI.Version), entry.time, entry.count, entry.message, entry.stack))
end

local function RecordError(message, stack)
    local id = errorIds[message]
    if id then
        errors[id].count = errors[id].count + 1
        return
    end

    if #errors >= MAX_ERRORS then return end

    id = #errors + 1
    errors[id] = { message = message, stack = stack, count = 1, time = date("%H:%M:%S") }
    errorIds[message] = id

    if not linkHandlerRegistered then
        linkHandlerRegistered = true
        -- Blizzard routes clicks on |Haddon:...|h links to this EventRegistry event.
        EventRegistry:RegisterCallback("SetItemRef", OnSetItemRef, errors)
    end

    local summary = gsub(match(message, "^[^\n]*"), "^Interface/AddOns/", "")
    if #summary > MAX_SUMMARY_LENGTH then
        summary = sub(summary, 1, MAX_SUMMARY_LENGTH - 3) .. "..."
    end
    summary = gsub(summary, "|", "||")

    print(format("|cffff0000Refine|rUI error: %s |cff71d5ff|Haddon:%s:error:%d|h[Details]|h|r", summary, AddOnName, id))
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
--- xpcall message handler for RefineUI error boundaries.
-- Repeats of the same message only increment its count, so chat gets one line per error.
function RefineUI.ErrorHandler(err)
    local stack = debugstack(2)
    geterrorhandler()(err)

    local message = IsReadable(err) and tostring(err) or "<secret error message>"
    if not IsReadable(stack) then
        stack = "<secret stack>"
    end
    RecordError(message, stack)

    return err
end
