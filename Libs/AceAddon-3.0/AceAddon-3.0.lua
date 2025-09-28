-- Minimal AceAddon-3.0 compatibility layer for RefineUI
-- Supports: LibStub("AceAddon-3.0"):NewAddon(name, ...mixins)
-- Mixins are expected to be libraries providing :Embed(target)
-- Lifecycle: Calls :OnInitialize() after PLAYER_LOGIN if present

local MAJOR, MINOR = "AceAddon-3.0", 1

local LibStub = LibStub
assert(LibStub, "LibStub not found")

local AceAddon = LibStub:NewLibrary(MAJOR, MINOR)
if not AceAddon then return end

local addonsByName = {}

local eventFrame = CreateFrame("Frame")
local loggedIn = IsLoggedIn and IsLoggedIn()

local function safeCall(func, ...)
    if type(func) == "function" then
        local ok, err = pcall(func, ...)
        if not ok then
            -- Swallow to avoid breaking load; could print if desired
        end
    end
end

function AceAddon:NewAddon(name, ...)
    assert(type(name) == "string" and name ~= "", "AceAddon:NewAddon(name) - name must be a non-empty string")
    if addonsByName[name] then return addonsByName[name] end

    local addon = {}
    addonsByName[name] = addon

    -- Embed mixins provided by string major names
    for i = 1, select('#', ...) do
        local dep = select(i, ...)
        if type(dep) == "string" then
            local lib = LibStub(dep, true)
            if lib and lib.Embed then
                lib:Embed(addon)
            end
        elseif type(dep) == "table" and dep.Embed then
            dep:Embed(addon)
        end
    end

    -- Schedule OnInitialize after login
    if loggedIn then
        C_Timer.After(0, function() safeCall(addon.OnInitialize, addon) end)
    else
        eventFrame:RegisterEvent("PLAYER_LOGIN")
    end

    return addon
end

function AceAddon:GetAddon(name, silent)
    local addon = addonsByName[name]
    if not addon and not silent then
        error(("Addon '%s' not found"):format(tostring(name)), 2)
    end
    return addon
end

eventFrame:SetScript("OnEvent", function()
    if not loggedIn then
        loggedIn = true
        for _, addon in pairs(addonsByName) do
            safeCall(addon.OnInitialize, addon)
        end
    end
end)


