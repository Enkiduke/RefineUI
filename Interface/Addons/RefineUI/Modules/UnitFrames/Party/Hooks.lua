----------------------------------------------------------------------------------------
-- UnitFrames Party: Hooks
-- Description: Global hook registration, event wiring, and the InitPartyHooks
--              lifecycle entry point for Compact Party/Raid frame handling.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local ForEachCompactPartyRaidFrame = P.ForEachRaidFrame
local ForceRestoreSpacing          = P.ForceRestoreSpacing

----------------------------------------------------------------------------------------
-- Hook Registration
----------------------------------------------------------------------------------------
function UF.InitPartyHooks()
    if UnitFrames:GetState(UnitFrames, "PartyHooksRegistered", false) then return end

    local function RegisterCompactPartyHooks()
        local registered = false

        if _G.CompactUnitFrame_Update then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_Update", "CompactUnitFrame_Update", UF.StyleCompactPartyFrame)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateAll then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateAll:Style", "CompactUnitFrame_UpdateAll", UF.StyleCompactPartyFrame)
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateAll", "CompactUnitFrame_UpdateAll", P.UpdateCompactPartyNameColor)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateHealthColor then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateHealthColor", P.UpdateCompactPetFrameColors)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateRoleIcon then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateRoleIcon", "CompactUnitFrame_UpdateRoleIcon", UF.UpdateRoleIcon)
            registered = true
        end

        return registered
    end

    if RegisterCompactPartyHooks() then
        UnitFrames:SetState(UnitFrames, "PartyHooksRegistered", true)
    end
    P.RegisterGroupDebuffEditModeSettings()

    if CompactPartyFrameTitle then
        CompactPartyFrameTitle:SetAlpha(0)
    end
    
    local manager = _G.CompactRaidFrameManager
    if manager then
        manager:SetAlpha(0)
        manager:EnableMouse(false)
        if manager.displayFrame then
            manager.displayFrame:SetAlpha(0)
            manager.displayFrame:EnableMouse(false)
        end
    end
    
    local function OnPartyEvent(event, addon)
         if event == "ADDON_LOADED" and (addon == "Blizzard_CompactRaidFrames" or addon == "Blizzard_UnitFrame") then
              if RegisterCompactPartyHooks() then
                  UnitFrames:SetState(UnitFrames, "PartyHooksRegistered", true)
              end

              ForEachCompactPartyRaidFrame(true, true, function(frame)
                  UF.StyleCompactPartyFrame(frame)
                  UF.UpdateRoleIcon(frame)
              end)
         elseif event == "RAID_TARGET_UPDATE" then
            ForEachCompactPartyRaidFrame(false, true, function(frame)
                if UF.UpdateCompactPartyRaidTargetMark then
                    UF.UpdateCompactPartyRaidTargetMark(frame)
                end
            end)
         elseif event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
            ForEachCompactPartyRaidFrame(false, true, function(frame)
                UF.StyleCompactPartyFrame(frame)
                UF.UpdateRoleIcon(frame)
            end)
            ForceRestoreSpacing() 
            
         elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            UF.RefreshGroupBuffs()
         elseif event == "CVAR_UPDATE" then
            if P.IsGroupDebuffCVar(addon) then
                UF.RefreshGroupDebuffs()
            end
         elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            if event == "PLAYER_ENTERING_WORLD" then
                UF.RefreshGroupBuffs()
            elseif P.groupBuffHiddenListPending then
                P.ApplyGroupBuffHiddenList()
            end
            ForEachCompactPartyRaidFrame(true, true, function(frame)
                UF.StyleCompactPartyFrame(frame)
                UF.UpdateRoleIcon(frame)
            end)
            ForceRestoreSpacing()
            if event == "PLAYER_ENTERING_WORLD" then
                RefineUI:After("UnitFramesParty:ForceRestoreSpacing:PLAYER_ENTERING_WORLD", 0.1, ForceRestoreSpacing)
            end
         end
    end
    
    RefineUI:OnEvents({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET", "RAID_TARGET_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "CVAR_UPDATE"}, OnPartyEvent, "RefinePartyHooks")

    -- Blizzard pushes its own Group Buffs hidden list on Cooldown Manager data changes; ours goes after.
    local function RefreshChangedGroupBuffs()
        UF.RefreshGroupBuffs(true)
    end
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        RefineUI:After("UnitFramesParty:GroupBuffs:Refresh", 0, RefreshChangedGroupBuffs)
    end, UF)
end
