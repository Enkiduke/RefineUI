----------------------------------------------------------------------------------------
--	Combat Targeting for RefineUI
--	This module provides combat-specific targeting features:
--  1. Sticky Targeting - Prevents target deselection during combat
--  2. Disable Right Click Camera Rotation - Prevents camera rotation with right-click in combat
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)
if C.misc.combatTargeting ~= true then return end

local function CreateConfigurableFeature(name, enabledSetting, setup)
    if enabledSetting then
        setup()
    end
end

----------------------------------------------------------------------------------------
--	Sticky Targeting
----------------------------------------------------------------------------------------
CreateConfigurableFeature("StickyTargeting", C.misc.combatTargeting, function()
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        Settings.SetValue("deselectOnClick", event == "PLAYER_REGEN_DISABLED")
    end)
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
end)

----------------------------------------------------------------------------------------
--	Disable Right Click Camera Rotation in Combat
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
--  Unified mouse wrapper (stable, no swapping on combat edges)
----------------------------------------------------------------------------------------
do
    -- Feature gates
    local DISABLE_RCLICK_IN_COMBAT = C.misc.disableRightClickCombat
    local AUTOTARGET_IN_COMBAT     = true  -- always on for this module's section below

    -- Capture originals once
    local origDown = WorldFrame:GetScript("OnMouseDown")
    local origUp   = WorldFrame:GetScript("OnMouseUp")

    -- Utility
    local function CanAttack(unit)
        local isFriendly = UnitIsFriend and UnitIsFriend("player", unit)
        return UnitCanAttack("player", unit) and not UnitIsDeadOrGhost(unit) and not isFriendly
    end

    -- One wrapper for both features. We never replace it again.
    WorldFrame:SetScript("OnMouseDown", function(self, button)
        if origDown then origDown(self, button) end

        -- NOTE: Do NOT alter camera state here; only gate our own actions.
        -- Right-click suppression intent: avoid starting any addon-driven mouselook
        -- while in combat. Native camera turn is handled by the client.
        -- We intentionally do nothing on RMB down.
    end)

    WorldFrame:SetScript("OnMouseUp", function(self, button)
        if origUp then origUp(self, button) end

        -- Left-click auto-target (combat only)
        if button == "LeftButton" and AUTOTARGET_IN_COMBAT and InCombatLockdown() then
            if not (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then
                local MouseIsOverWorld = rawget(_G, "MouseIsOverWorld")
                if MouseIsOverWorld and MouseIsOverWorld() then
                    if UnitExists("mouseover") and CanAttack("mouseover") then
                        TargetUnit("mouseover")
                        -- Do NOT force mouselook here; it fights RMB state.
                        -- If the player is already mouselooking, leave it alone.
                    end
                end
            end
        end

        -- Right-click in combat: never toggle mouselook here.
        -- The old code called MouselookStart() on RMB Up which caused the “unlick”.
        if button == "RightButton" and DISABLE_RCLICK_IN_COMBAT and InCombatLockdown() then
            -- Soft guard only: if we somehow entered mouselook due to other logic, stop it.
            -- This avoids sticky mouselook without fighting native camera turn.
            -- Crucially, we *don’t* start/stop on combat edges.
            if IsMouselooking() and not IsMouseButtonDown("RightButton") then
                MouselookStop()
            end
        end
    end)
end

----------------------------------------------------------------------------------------
--	Auto target on mouse click(TargetOnMouseDown by clanzda)
----------------------------------------------------------------------------------------
-- Auto-target behavior is now handled inside the unified wrapper above.
-- We remove the combat-time script swapping and the forced MouselookStart().