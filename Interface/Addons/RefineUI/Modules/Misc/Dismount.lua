local AddOnName, RefineUI = ...

local Module = RefineUI:RegisterModule("Dismount")

-- Cache globals
local IsMounted = IsMounted
local IsFlying = IsFlying
local Dismount = _G.Dismount
local CancelShapeshiftForm = _G.CancelShapeshiftForm
local InCombatLockdown = InCombatLockdown
local UIErrorsFrame = _G.UIErrorsFrame

-- Constants (Localized via Global Strings)
-- We use these to match the error message text exactly.
local MOUNT_ERRORS = {
    [_G.ERR_NOT_WHILE_MOUNTED] = true,
    [_G.ERR_TAXIPLAYERALREADYMOUNTED] = true,
}

local SHAPESHIFT_ERRORS = {
    [_G.ERR_NOT_WHILE_SHAPESHIFTED] = true,
    [_G.ERR_NO_ITEMS_WHILE_SHAPESHIFTED] = true,
    [_G.ERR_MOUNT_SHAPESHIFTED] = true,
    [_G.SPELL_FAILED_NOT_SHAPESHIFT] = true,
}

-- Skyriding Spells (Surge Forward, Whirling Surge, Aerial Halt)
local SKYRIDING_SPELLS = {
    [372608] = true,
    [361584] = true,
    [403092] = true,
}

function Module:OnEnable()
    -- Skyriding Dismount Logic
    RefineUI:RegisterEventCallback("UNIT_SPELLCAST_SENT", function(_, unit, target, castGUID, spellID)
        if (unit ~= "player") then return end

        if (SKYRIDING_SPELLS[spellID]) then
            if (IsMounted() and not _G.IsFlying()) then
                Dismount()
            end
        end
    end, "Dismount:Skyriding")

    -- Error Handling (Auto-Dismount/Cancel Form on Error)
    RefineUI:RegisterEventCallback("UI_ERROR_MESSAGE", function(_, errorType, message)
        if (MOUNT_ERRORS[message]) then
            Dismount()
            UIErrorsFrame:Clear()
        elseif (SHAPESHIFT_ERRORS[message]) then
            if (InCombatLockdown()) then
                RefineUI:Print("Cannot cancel shapeshift in combat.")
            else
                CancelShapeshiftForm()
                UIErrorsFrame:Clear()
            end
        end
    end, "Dismount:Errors")

    -- Taxi Handling (Dismount/Cancel Form when opening Taxi Map)
    RefineUI:RegisterEventCallback("TAXIMAP_OPENED", function()
        if (IsMounted()) then
            Dismount()
        end
        CancelShapeshiftForm()
    end, "Dismount:Taxi")
end
