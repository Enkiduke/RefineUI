----------------------------------------------------------------------------------------
-- RefineUI Lifecycle
-- Description: Deterministic startup callback registry (replaces OnEnable chaining).
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local pairs, type, tostring = pairs, type, tostring
local sort = table.sort
local xpcall = xpcall
local geterrorhandler = geterrorhandler

RefineUI.StartupCallbacks = RefineUI.StartupCallbacks or {}
RefineUI.StartupCallbackOrder = RefineUI.StartupCallbackOrder or 0

local function RunStartupCallback(key, fn)
    local handler = geterrorhandler and geterrorhandler() or function(err) return tostring(err) end
    local ok, err = xpcall(fn, handler)
    if not ok then
        print("|cffff0000Refine|rUI Startup Error [" .. tostring(key) .. "]:", tostring(err))
    end
end

function RefineUI:RegisterStartupCallback(key, fn, priority)
    if type(fn) ~= "function" then return end

    if type(key) ~= "string" or key == "" then
        key = tostring(fn)
    end

    local existing = self.StartupCallbacks[key]
    if not existing then
        self.StartupCallbackOrder = self.StartupCallbackOrder + 1
    end

    self.StartupCallbacks[key] = {
        key = key,
        fn = fn,
        priority = priority or 50,
        order = existing and existing.order or self.StartupCallbackOrder,
    }

    -- Late registrations should still run on live sessions.
    if self._startupRan then
        RunStartupCallback(key, fn)
    end

    return key
end

function RefineUI:RunStartupCallbacks()
    if self._startupRunning or self._startupRan then return end
    self._startupRunning = true

    local queue = {}
    for _, callback in pairs(self.StartupCallbacks) do
        queue[#queue + 1] = callback
    end

    sort(queue, function(a, b)
        if a.priority == b.priority then
            return a.order < b.order
        end
        return a.priority < b.priority
    end)

    for i = 1, #queue do
        local callback = queue[i]
        RunStartupCallback(callback.key, callback.fn)
    end

    self._startupRunning = false
    self._startupRan = true
end

-- Compatibility shim for callers still invoking RefineUI:OnEnable().
function RefineUI:OnEnable()
    self:RunStartupCallbacks()
end
