local AddOnName, RefineUI = ...

-- Call Modules
local Blizzard = RefineUI:RegisterModule("Blizzard")

-- HelpTip:AreHelpTipsEnabled() honors this unregistered CVar. Hiding HelpTips from addon code
-- instead runs their close callbacks (micro-button alerts) tainted.
function Blizzard:OnEnable()
    C_CVar.RegisterCVar("hideHelptips", "1")
    C_CVar.SetCVar("hideHelptips", "1")
end
