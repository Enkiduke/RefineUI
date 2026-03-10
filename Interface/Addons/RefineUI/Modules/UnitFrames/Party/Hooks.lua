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
local InCombatLockdown = InCombatLockdown

local IsPartyRaidCompactFrame     = P.IsCompactFrame
local ForEachCompactPartyRaidFrame = P.ForEachRaidFrame
local ForceRestoreSpacing          = P.ForceRestoreSpacing
local ApplyCompactRaidLayout       = P.ApplyCompactRaidLayout
local SetupSecurePartySpacing      = P.SetupSecurePartySpacing
local ApplySecurePartySpacing      = P.ApplySecurePartySpacing

----------------------------------------------------------------------------------------
-- Refresh Tracked Class Buff Settings
----------------------------------------------------------------------------------------
function UF.RefreshTrackedClassBuffSettings()
    P.EnsureManualOrderIncludesAllEntries()

    if InCombatLockdown() then
        return
    end

    ForEachCompactPartyRaidFrame(true, false, function(frame)
        if _G.CompactUnitFrame_UpdateAuras then
            pcall(_G.CompactUnitFrame_UpdateAuras, frame)
        end
        P.ApplyCompactAuraStylingForFrame(frame)
    end)
end

----------------------------------------------------------------------------------------
-- Hook Registration
----------------------------------------------------------------------------------------
function UF.InitPartyHooks()
    if UnitFrames:GetState(UnitFrames, "PartyHooksRegistered", false) then return end

    P.EnsureManualOrderIncludesAllEntries()
    P.HookTrackedBuffSettingsDialog()
    if SetupSecurePartySpacing then
        SetupSecurePartySpacing()
    end

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
        if _G.CompactUnitFrame_UpdateName then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateName", P.UpdateCompactPartyNameColor)
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
        if _G.CompactUnitFrame_UtilSetDebuff then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UtilSetDebuff", "CompactUnitFrame_UtilSetDebuff", function(frame, debuffFrame, aura)
                if not frame or not debuffFrame then return end
                if not IsPartyRaidCompactFrame(frame) then return end
                P.ApplyCompactDebuffBorderColor(debuffFrame, aura)
            end)
            registered = true
        end
        if _G.CompactUnitFrame_UtilSetBuff then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UtilSetBuff", "CompactUnitFrame_UtilSetBuff", function(buffFrame, aura)
                if not buffFrame then return end
                local frame = buffFrame:GetParent()
                if not IsPartyRaidCompactFrame(frame) then return end
                P.TrackCompactBuffAuraData(buffFrame, aura)
                P.ApplyCompactBuffBorderColor(buffFrame)
            end)
            registered = true
        end
        if _G.CompactUnitFrame_UtilSetDispelDebuff then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UtilSetDispelDebuff", "CompactUnitFrame_UtilSetDispelDebuff", function(frame, dispellDebuffFrame, aura)
                if not frame or not dispellDebuffFrame then return end
                if not IsPartyRaidCompactFrame(frame) then return end
                P.TrackCompactDispelBorderColor(frame, aura)
                P.HideCompactAuraBorder(dispellDebuffFrame)
                P.UpdateCompactPartyDispelBorderColor(frame)
            end)
            registered = true
        end
        if _G.DefaultCompactUnitFrameSetup then
            RefineUI:HookOnce("UnitFramesParty:DefaultCompactUnitFrameSetup:AuraSpacing", "DefaultCompactUnitFrameSetup", function(frame)
                if not IsPartyRaidCompactFrame(frame) then return end
                P.ApplyCompactAuraSpacingForFrame(frame)
                P.ApplyCompactAuraStylingForFrame(frame)
            end)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateAuras then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateAuras:Style", "CompactUnitFrame_UpdateAuras", function(frame)
                if not IsPartyRaidCompactFrame(frame) then return end
                P.ApplyCompactAuraStylingForFrame(frame)
            end)
            registered = true
        end
        if _G.CompactUnitFrame_SetDispelOverlayAura then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_SetDispelOverlayAura:AuraSpacing", "CompactUnitFrame_SetDispelOverlayAura", function(frame, aura)
                if not IsPartyRaidCompactFrame(frame) then return end
                P.TrackCompactDispelBorderColor(frame, aura)
                P.ApplyCompactAuraSpacingForFrame(frame)
                P.UpdateCompactPartyDispelBorderColor(frame)
            end)
            registered = true
        end

        return registered
    end

    if RegisterCompactPartyHooks() then
        UnitFrames:SetState(UnitFrames, "PartyHooksRegistered", true)
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
         P.HookTrackedBuffSettingsDialog()
         if SetupSecurePartySpacing then
             SetupSecurePartySpacing()
         end
         if event == "ADDON_LOADED" and (addon == "Blizzard_CompactRaidFrames" or addon == "Blizzard_UnitFrame") then
              if RegisterCompactPartyHooks() then
                  UnitFrames:SetState(UnitFrames, "PartyHooksRegistered", true)
              end

              ForEachCompactPartyRaidFrame(true, true, function(frame)
                  UF.StyleCompactPartyFrame(frame)
                  UF.UpdateRoleIcon(frame)
              end)
              if ApplySecurePartySpacing then
                  ApplySecurePartySpacing()
              end
              ForceRestoreSpacing()
              ApplyCompactRaidLayout()
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
            if ApplySecurePartySpacing then
                ApplySecurePartySpacing()
            end
            ForceRestoreSpacing()
            ApplyCompactRaidLayout()
            
         elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            ForEachCompactPartyRaidFrame(true, true, function(frame)
                UF.StyleCompactPartyFrame(frame)
                UF.UpdateRoleIcon(frame)
            end)
            if ApplySecurePartySpacing then
                ApplySecurePartySpacing()
            end
            ForceRestoreSpacing()
            ApplyCompactRaidLayout()
            if event == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(0.1, function()
                    if ApplySecurePartySpacing then
                        ApplySecurePartySpacing()
                    end
                end)
                C_Timer.After(0.1, ForceRestoreSpacing)
                C_Timer.After(0.1, ApplyCompactRaidLayout)
            end
         end
    end
    
    RefineUI:OnEvents({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET", "RAID_TARGET_UPDATE"}, OnPartyEvent, "RefinePartyHooks")
end
