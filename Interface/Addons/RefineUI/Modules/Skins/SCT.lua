----------------------------------------------------------------------------------------
-- Skins Component: SCT
-- Description: SCT scale defaults are seeded during install.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupSCT()
    -- Seeded during full install/reapply-default flows. Do not force the user's
    -- SCT scale back on normal login.
end
