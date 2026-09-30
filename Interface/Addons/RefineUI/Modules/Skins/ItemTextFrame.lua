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
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:ItemTextFrame"
local ITEM_TEXT_TAGS = { "P", "H1", "H2", "H3" }

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
-- ItemTextFrame_OnEvent sets the material text colors only on ITEM_TEXT_BEGIN. The XML
-- binds that function at load, so the frame's script is hooked rather than the global.
local function OnItemTextEvent(_, event)
    if event ~= "ITEM_TEXT_BEGIN" then
        return
    end

    local pageText = ItemTextPageText
    for i = 1, #ITEM_TEXT_TAGS do
        pageText:SetTextColor(ITEM_TEXT_TAGS[i], 1, 1, 1)
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupItemTextFrameSkin()
    RefineUI:HookScriptOnce(COMPONENT_KEY .. ":OnEvent", ItemTextFrame, "OnEvent", OnItemTextEvent)
end
