----------------------------------------------------------------------------------------
-- UnitFrames Party: Frame Style
-- Description: Health bar texture, name/role/leader icons, custom health text,
--              pet frame colors, and the main StyleCompactPartyFrame entry point.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config
local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Colors = RefineUI.Colors

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitHealthPercent = UnitHealthPercent
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local InCombatLockdown = InCombatLockdown
local type = type
local tostring = tostring
local tonumber = tonumber

local GetPartyData       = P.GetData
local BuildPartyHookKey  = P.BuildHookKey
local IsUnreadableNumber = P.IsUnreadableNumber
local IsEditModeActiveNow    = P.IsEditModeActive
local IsPartyRaidCompactFrame = P.IsCompactFrame
local IsCompactPetUnitToken   = P.IsPetUnit
local GetCompactPetOwnerClassColor = P.GetPetOwnerClassColor

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TEXTURE_LEADER        = [[Interface\AddOns\RefineUI\Media\Textures\LEADER.blp]]
local TEXTURE_ROLE_TANK     = [[Interface\AddOns\RefineUI\Media\Textures\TANK.blp]]
local TEXTURE_ROLE_HEALER   = [[Interface\AddOns\RefineUI\Media\Textures\HEALER.blp]]
local TEXTURE_ROLE_DAMAGER  = [[Interface\AddOns\RefineUI\Media\Textures\DAMAGER.blp]]
local TEXTURE_COMPACT_HEALTH = P.TEXTURE_COMPACT_HEALTH
local TEXTURE_RAID_TARGET_ICONS = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]
local PARTY_RAID_ICON_SIZE = 24

local function QueuePartyDeferred(frame, suffix, delay, fn)
    if not frame or frame:IsForbidden() or type(fn) ~= "function" then
        return
    end

    RefineUI:After(BuildPartyHookKey(frame, "Deferred:" .. suffix), delay, function()
        if frame and not frame:IsForbidden() then
            fn(frame)
        end
    end)
end

----------------------------------------------------------------------------------------
-- Health Bar Texture
----------------------------------------------------------------------------------------
local function ApplyCompactHealthTexture(frame)
    if not frame or frame:IsForbidden() or not frame.healthBar then return end

    local healthBar = frame.healthBar
    healthBar:SetStatusBarTexture(TEXTURE_COMPACT_HEALTH)

    RefineUI:HookOnce(BuildPartyHookKey(healthBar, "SetStatusBarTexture:HealthTexture"), healthBar, "SetStatusBarTexture", function(self, texture)
        if texture ~= TEXTURE_COMPACT_HEALTH then
            self:SetStatusBarTexture(TEXTURE_COMPACT_HEALTH)
        end
    end)
end

----------------------------------------------------------------------------------------
-- Border Layout
----------------------------------------------------------------------------------------
local function UpdateCompactPartyBorderLayout(frame)
    if not frame or frame:IsForbidden() or not frame.healthBar then return end
    if IsEditModeActiveNow() then return end

    local data = GetPartyData(frame)
    local borderHost = data.healthBarBorderHost
    if not borderHost or (borderHost.IsForbidden and borderHost:IsForbidden()) then return end

    local powerBarShown = frame.powerBar and frame.powerBar:IsShown()
    local powerBarUsedHeight = 0
    local rawPowerBarUsedHeight = frame.powerBarUsedHeight
    if not IsUnreadableNumber(rawPowerBarUsedHeight) then
        powerBarUsedHeight = tonumber(rawPowerBarUsedHeight) or 0
    end
    local expandForPowerBar = powerBarShown or powerBarUsedHeight > 0

    if data.healthBarBorderExpanded == expandForPowerBar then
        return
    end

    borderHost:ClearAllPoints()
    borderHost:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
    -- Keep border size anchored to the stable frame container so temporary max-health loss
    -- (which shrinks healthBar) does not collapse the border width.
    borderHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

    data.healthBarBorderExpanded = expandForPowerBar
end

----------------------------------------------------------------------------------------
-- Custom Health Percent Text
----------------------------------------------------------------------------------------
local function UpdateCustomPartyHP(self)
    local frame = self.frame
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        QueuePartyDeferred(frame, "UpdateCustomPartyHP", 0.1, function(deferredFrame)
            if not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UpdateCustomPartyHP({ frame = deferredFrame })
            end
        end)
        return
    end
    
    local data = GetPartyData(frame)
    local percentText = data.CustomPercentText
    if not percentText then return end
    
    if not UnitIsConnected(unit) then
        RefineUI:SetFontStringValue(percentText, "OFFLINE", { emptyText = "" })
        percentText:SetTextColor(0.5, 0.5, 0.5)
    elseif UnitIsDeadOrGhost(unit) then
        RefineUI:SetFontStringValue(percentText, "DEAD", { emptyText = "" })
        percentText:SetTextColor(0.5, 0.5, 0.5)
    else
        local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
        RefineUI:SetFontStringValue(percentText, percent, { emptyText = "" })
        percentText:SetTextColor(1, 1, 1)
    end
    percentText:Show()
end

local function CreateCustomPartyText(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    local data = GetPartyData(frame)
    if not data.customTextCreated then 
        if frame.statusText then
            frame.statusText:SetAlpha(0)
        end
        
        local text = frame.healthBar:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(text, 20, nil, "OUTLINE", false)
        text:SetTextColor(1, 1, 1)
        text:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
        data.CustomPercentText = text
        
        local function OnPartyEvent()
            UpdateCustomPartyHP({ frame = frame })
        end
        
        local frameName = frame.GetName and frame:GetName()
        local key = "Party_"..(frameName or tostring(frame))
        RefineUI:OnUnitEvents(frame.unit, { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }, OnPartyEvent, key)
        
        data.customTextCreated = true
    end
    
    UpdateCustomPartyHP({frame=frame})
end

----------------------------------------------------------------------------------------
-- Leader Icon
----------------------------------------------------------------------------------------
local function UpdateCompactPartyLeader(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    if IsCompactPetUnitToken(frame and (frame.unit or frame.displayedUnit)) then return end

    local data = GetPartyData(frame)
    local unit = frame.unit or frame.displayedUnit
    local isLeader = unit and UnitIsGroupLeader(unit)
    
    if not data.leaderIcon and frame.healthBar then
        local icon = frame.healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetTexture(TEXTURE_LEADER)
        icon:SetSize(16, 16)
        icon:SetPoint("BOTTOMRIGHT", frame.healthBar, "TOPRIGHT", 0, 2)
        icon:Hide()
        data.leaderIcon = icon
    end
    
    local leaderIcon = data.leaderIcon
    if not leaderIcon then return end
    
    if isLeader then
        leaderIcon:Show()
        leaderIcon:ClearAllPoints()
        leaderIcon:SetPoint("BOTTOMRIGHT", frame.healthBar, "TOPRIGHT", 0, 2)
        
        if unit then
            local _, class = UnitClass(unit)
            local color = Colors.Class[class] 
            if color then
                leaderIcon:SetVertexColor(color.r, color.g, color.b)
            else
                leaderIcon:SetVertexColor(1, 1, 1)
            end
        end
    else
        leaderIcon:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Pet Frame Colors
----------------------------------------------------------------------------------------
local function UpdateCompactPetFrameColors(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    if not frame or frame:IsForbidden() or not IsCompactPetUnitToken(frame.displayedUnit or frame.unit) then return end

    local color = GetCompactPetOwnerClassColor(frame)
    if not color then return end

    if frame.name then
        frame.name:SetVertexColor(color.r, color.g, color.b, 1, "RefineUI_Hook")
    end

    if frame.healthBar then
        frame.healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
    end
end

----------------------------------------------------------------------------------------
-- Name Color
----------------------------------------------------------------------------------------
local function UpdateCompactPartyNameColor(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    if not frame or frame:IsForbidden() or not frame.name then return end
    
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        QueuePartyDeferred(frame, "UpdateCompactPartyNameColor", 0.1, function(deferredFrame)
            if not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UpdateCompactPartyNameColor(deferredFrame)
            end
        end)
        return
    end
    
    local unit = frame.displayedUnit or frame.unit
    if not unit then return end

    if IsCompactPetUnitToken(unit) then
        UpdateCompactPetFrameColors(frame)
        return
    end
    
    if UnitIsPlayer(unit) or (C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon()) then
        local _, class = UnitClass(unit)
        if class then
            local r, g, b
            local color = Colors.Class[class]
            if color then
                r, g, b = color.r, color.g, color.b
            end
            
            if r then
                frame.name:SetVertexColor(r, g, b, 1, "RefineUI_Hook")
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Raid Target Marker
----------------------------------------------------------------------------------------
local function EnsureCompactRaidTargetMark(frame)
    if not frame or frame:IsForbidden() then
        return nil
    end

    local data = GetPartyData(frame)
    if not data then
        return nil
    end

    if not data.RaidTargetMark then
        local markHost = CreateFrame("Frame", nil, frame)
        markHost:SetFrameStrata(frame:GetFrameStrata())
        markHost:SetFrameLevel(frame:GetFrameLevel() + 20)
        markHost:EnableMouse(false)

        local mark = markHost:CreateTexture(nil, "OVERLAY", nil, 0)
        mark:SetTexture(TEXTURE_RAID_TARGET_ICONS)
        mark:Hide()
        mark:SetAllPoints(markHost)
        data.RaidTargetMarkHost = markHost
        data.RaidTargetMark = mark
    end

    return data.RaidTargetMark
end

local function ApplyCompactRaidTargetMarkAnchor(frame, mark)
    if not frame or not mark then
        return
    end

    local data = GetPartyData(frame)
    local markHost = data and data.RaidTargetMarkHost
    if not markHost then
        return
    end

    markHost:SetFrameStrata(frame:GetFrameStrata())
    markHost:SetFrameLevel(frame:GetFrameLevel() + 20)
    markHost:ClearAllPoints()
    markHost:SetPoint("CENTER", frame, "LEFT", 0, 0)
    markHost:SetSize(PARTY_RAID_ICON_SIZE, PARTY_RAID_ICON_SIZE)
end

local function UpdateCompactRaidTargetMark(frame)
    if not IsPartyRaidCompactFrame(frame) then
        return
    end

    local mark = EnsureCompactRaidTargetMark(frame)
    if not mark then
        return
    end

    ApplyCompactRaidTargetMarkAnchor(frame, mark)

    local unit = frame.displayedUnit or frame.unit
    if not unit or IsCompactPetUnitToken(unit) then
        mark:Hide()
        return
    end

    local ok, raidTargetIndex = pcall(GetRaidTargetIndex, unit)
    if not ok or not raidTargetIndex then
        mark:Hide()
        return
    end

    if type(SetRaidTargetIconTexture) == "function" then
        local applied = pcall(SetRaidTargetIconTexture, mark, raidTargetIndex)
        if not applied then
            mark:Hide()
            return
        end
    else
        mark:Hide()
        return
    end

    mark:Show()
end

----------------------------------------------------------------------------------------
-- Main Style Entry Point
----------------------------------------------------------------------------------------
function UF.StyleCompactPartyFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not IsPartyRaidCompactFrame(frame) then return end
    
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        QueuePartyDeferred(frame, "StyleCompactPartyFrame", 0.1, function(deferredFrame)
            if not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UF.StyleCompactPartyFrame(deferredFrame)
            end
        end)
        return
    end
    
    local data = GetPartyData(frame)
    local unit = frame.displayedUnit or frame.unit
    local isPetFrame = IsCompactPetUnitToken(unit)
    ApplyCompactHealthTexture(frame)
    
    if not InCombatLockdown() then
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(0, 0, -18, 0)
        end
    end

    P.HookSpacing(frame)
    
    if frame.name then
        local function AnchorName(self)
            local d = GetPartyData(frame)
            if d.namePositioning then return end
            d.namePositioning = true
            self:ClearAllPoints()
            if isPetFrame and frame.healthBar then
                self:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
            else
                self:SetPoint("BOTTOM", frame.healthBar, "TOP", 0, 4)
            end
            d.namePositioning = false
        end

        AnchorName(frame.name)
        RefineUI:HookOnce(BuildPartyHookKey(frame.name, "SetPoint:Anchor"), frame.name, "SetPoint", AnchorName)

        if isPetFrame then
            RefineUI.Font(frame.name, 10, nil, "OUTLINE", true)
            if frame.name.SetJustifyH then
                frame.name:SetJustifyH("CENTER")
            end
            if frame.name.SetHeight then
                frame.name:SetHeight(12)
            end
        else
            RefineUI.Font(frame.name, 12, nil, "OUTLINE", true)
        end
        
        RefineUI:HookOnce(BuildPartyHookKey(frame.name, "SetVertexColor"), frame.name, "SetVertexColor", function(self, r, g, b, a, flag)
            if flag ~= "RefineUI_Hook" then
                UpdateCompactPartyNameColor(frame)
            end
        end)
        UpdateCompactPartyNameColor(frame)
    end

    if frame.healthBar then
         local data = GetPartyData(frame)

         if not data.healthBarBorder then
             local inset = 6
             local edgeSize = RefineUI:Scale(12)

             -- Parent the border host to the frame, not healthBar, so Blizzard health-loss
             -- anchor adjustments on healthBar do not shrink the border host.
             local borderHost = CreateFrame("Frame", nil, frame)
             borderHost:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
             borderHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
             borderHost:SetFrameStrata(frame.healthBar:GetFrameStrata())
             borderHost:SetFrameLevel(frame.healthBar:GetFrameLevel() + 4)
             if borderHost.EnableMouse then
                 borderHost:EnableMouse(false)
             end

             local border = RefineUI.CreateBorder(borderHost, inset, inset, edgeSize)
             data.healthBarBorderHost = borderHost
             data.healthBarBorder = border
         end

         UpdateCompactPartyBorderLayout(frame)

         if frame.powerBar and not data.powerBarBorderHooksInstalled then
             RefineUI:HookScriptOnce(BuildPartyHookKey(frame.powerBar, "OnShow:BorderLayout"), frame.powerBar, "OnShow", function()
                 UpdateCompactPartyBorderLayout(frame)
             end)
             RefineUI:HookScriptOnce(BuildPartyHookKey(frame.powerBar, "OnHide:BorderLayout"), frame.powerBar, "OnHide", function()
                 UpdateCompactPartyBorderLayout(frame)
             end)
              data.powerBarBorderHooksInstalled = true
         end

         P.UpdateCompactPartyDispelBorderColor(frame)

         if isPetFrame then
             UpdateCompactPetFrameColors(frame)
         end
    end
    
    if not isPetFrame then
        CreateCustomPartyText(frame)
    elseif frame.statusText then
        frame.statusText:SetAlpha(0)
    end

    P.ApplyCompactAuraStylingForFrame(frame)
    UpdateCompactRaidTargetMark(frame)

    UpdateCompactPartyNameColor(frame)
    if not isPetFrame then
        UpdateCompactPartyLeader(frame)
    end
    
    if Config.UnitFrames.DisableTooltips then
        RefineUI:HookScriptOnce(BuildPartyHookKey(frame, "OnEnter:Tooltip"), frame, "OnEnter", function(self)
            if not IsShiftKeyDown() then
                GameTooltip:Hide()
            end
        end)
    end
end

----------------------------------------------------------------------------------------
-- Role Icons
----------------------------------------------------------------------------------------
function UF.UpdateRoleIcon(frame)
    if not frame or not frame.roleIcon then return end
    if not IsPartyRaidCompactFrame(frame) then return end
    if IsCompactPetUnitToken(frame.displayedUnit or frame.unit) then
        local data = GetPartyData(frame)
        if data.roleIcon then data.roleIcon:Hide() end
        return
    end
    
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then return end
    
    local data = GetPartyData(frame)
    local role = UnitGroupRolesAssigned(frame.unit or frame.displayedUnit)
    
    if frame.optionTable and not frame.optionTable.displayRoleIcon then
        if data.roleIcon then data.roleIcon:Hide() end
        return
    end

    if ( role == "TANK" or role == "HEALER" or role == "DAMAGER" ) then
        frame.roleIcon:SetAlpha(0)
        
        if not data.roleIcon and frame.healthBar then
            local icon = frame.healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
            icon:SetSize(16, 16)
            data.roleIcon = icon
        end
        
        local roleIcon = data.roleIcon
        if not roleIcon then return end
        
        local texture
        if role == "TANK" then texture = TEXTURE_ROLE_TANK
        elseif role == "HEALER" then texture = TEXTURE_ROLE_HEALER
        else texture = TEXTURE_ROLE_DAMAGER end
        
        roleIcon:SetTexture(texture)
        roleIcon:SetTexCoord(0, 1, 0, 1)
        roleIcon:ClearAllPoints()
        roleIcon:SetPoint("BOTTOMLEFT", frame.healthBar, "TOPLEFT", 0, 2)
        roleIcon:Show()
        
        local unit = frame.unit or frame.displayedUnit
        if unit then
            local _, class = UnitClass(unit)
            local color = Colors.Class[class] 
            if color then
                roleIcon:SetVertexColor(color.r, color.g, color.b)
            else
                 roleIcon:SetVertexColor(1, 1, 1)
            end
        end
    else
        if data.roleIcon then data.roleIcon:Hide() end
    end
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.UpdateCompactPartyNameColor  = UpdateCompactPartyNameColor
P.UpdateCompactPetFrameColors  = UpdateCompactPetFrameColors
UF.UpdateCompactPartyRaidTargetMark = UpdateCompactRaidTargetMark
