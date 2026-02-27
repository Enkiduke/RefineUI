----------------------------------------------------------------------------------------
-- Skins Component: Item Text Frame
-- Description: Forces item text page body/title tags to white.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:ItemTextFrame"
local ITEM_TEXT_TAGS = { "P", "H1", "H2", "H3" }

local EVENT_KEY = {
    ADDON_LOADED = COMPONENT_KEY .. ":ADDON_LOADED",
}

----------------------------------------------------------------------------------------
-- Local State
----------------------------------------------------------------------------------------
local setupComplete = false
local hooksInstalled = false
local whiteTagLookup = {
    P = true,
    H1 = true,
    H2 = true,
    H3 = true,
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function ForceItemTextWhite()
    local pageText = _G.ItemTextPageText
    if not pageText then
        return
    end

    if pageText.IsForbidden and pageText:IsForbidden() then
        return
    end

    if type(pageText.SetTextColor) ~= "function" then
        return
    end

    if not pageText.__refineui_set_text_color_wrapped then
        local originalSetTextColor = pageText.SetTextColor
        if type(originalSetTextColor) == "function" then
            pageText.__refineui_set_text_color_wrapped = true
            pageText.SetTextColor = function(self, tag, r, g, b, a)
                if whiteTagLookup[tag] then
                    return originalSetTextColor(self, tag, 1, 1, 1, a)
                end
                return originalSetTextColor(self, tag, r, g, b, a)
            end
        end
    end

    for i = 1, #ITEM_TEXT_TAGS do
        pageText:SetTextColor(ITEM_TEXT_TAGS[i], 1, 1, 1)
    end
end

local function InstallHooks()
    local frame = _G.ItemTextFrame
    if not frame then
        return false
    end

    if hooksInstalled then
        ForceItemTextWhite()
        return true
    end

    hooksInstalled = true

    if type(_G.ItemTextFrame_OnEvent) == "function" then
        hooksecurefunc("ItemTextFrame_OnEvent", function()
            ForceItemTextWhite()
        end)
    end

    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            ForceItemTextWhite()
        end)
    end

    ForceItemTextWhite()
    return true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupItemTextFrameSkin()
    if setupComplete then
        return
    end
    setupComplete = true

    InstallHooks()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_UIPanels_Game" then
            InstallHooks()
        end
    end, EVENT_KEY.ADDON_LOADED)
end
