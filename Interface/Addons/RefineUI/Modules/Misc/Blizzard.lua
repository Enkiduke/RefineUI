local AddOnName, RefineUI = ...

-- Call Modules
local Blizzard = RefineUI:RegisterModule("Blizzard")

-- WoW Globals
local NewPlayerExperience = _G.NewPlayerExperience
-- Note: HelpTip might be loaded later, so we check at runtime or use global reference

local function DismissActiveHelpTips()
    local HelpTip = _G.HelpTip
    if not (HelpTip and HelpTip.framePool) then
        return
    end

    for frame in HelpTip.framePool:EnumerateActive() do
        if frame.Acknowledge then
            frame:Acknowledge()
        elseif frame.Hide then
            frame:Hide()
        end
    end
end

function Blizzard:DisableTips()
    local HelpTip = _G.HelpTip

    if (HelpTip and HelpTip.framePool) then
        DismissActiveHelpTips()

        if type(HelpTip.Show) == "function" and not self._helpTipShowHooked then
            RefineUI:HookOnce("Blizzard:HelpTip:Show", HelpTip, "Show", function()
                DismissActiveHelpTips()
            end)
            self._helpTipShowHooked = true
        end
    end

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
