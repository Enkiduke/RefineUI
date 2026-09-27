local AddOnName, RefineUI = ...

-- Call Modules
local Blizzard = RefineUI:RegisterModule("Blizzard")

-- WoW Globals
local NewPlayerExperience = _G.NewPlayerExperience

-- HelpTip:AreHelpTipsEnabled() honors this unregistered CVar. Hiding HelpTips from addon code
-- instead runs their close callbacks (micro-button alerts) tainted.
function Blizzard:DisableTips()
    C_CVar.RegisterCVar("hideHelptips", "1")
    C_CVar.SetCVar("hideHelptips", "1")

    if (NewPlayerExperience) then
        if (NewPlayerExperience:GetIsActive()) then
            NewPlayerExperience:Shutdown()
        end

        if (NewPlayerExperience.SetEnabled) then
            NewPlayerExperience:SetEnabled(false)
        end
    end
end

function Blizzard:OnEnable()
    -- Enable is called on PLAYER_LOGIN usually, which is safe for this.
	self:DisableTips()
end
