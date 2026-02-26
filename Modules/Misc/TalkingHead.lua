----------------------------------------------------------------------------------------
-- TalkingHead for RefineUI
-- Description: Hides the Talking Head frame.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Module = RefineUI:RegisterModule("TalkingHead")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G

----------------------------------------------------------------------------------------
-- Core Logic
----------------------------------------------------------------------------------------

local function HookTalkingHead()
    local TalkingHeadFrame = _G.TalkingHeadFrame
    if not TalkingHeadFrame then return end

    if RefineUI.Config.TalkingHead.NoTalkingHead then
        RefineUI:HookOnce("TalkingHead:PlayCurrent:Hide", TalkingHeadFrame, "PlayCurrent", function(self)
            self:Hide()
            if self.Finish then self:Finish() end
        end)
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function Module:OnEnable()
    local config = RefineUI.Config.TalkingHead
    if not (config and config.Enable) then return end

    if _G.TalkingHeadFrame then
        HookTalkingHead()
    else
        local loadKey = "TalkingHead:Load"
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
            if addonName == "Blizzard_TalkingHeadUI" then
                HookTalkingHead()
                RefineUI:OffEvent("ADDON_LOADED", loadKey)
            end
        end, loadKey)
    end
end
