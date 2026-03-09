local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
-- Legacy Automation AutoRepair shim
-- Canonical owner lives at Modules/Loot/AutoRepair.lua.
----------------------------------------------------------------------------------------
local AutoRepair = RefineUI:GetModule("AutoRepair")
if not AutoRepair then
    return
end
