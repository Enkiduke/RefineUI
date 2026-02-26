----------------------------------------------------------------------------------------
-- RefineUI UnitFrames Party
-- Description: Handling for CompactPartyFrame (Pixel Perfect skinning).
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

-- Imports
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitExists = UnitExists
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitHealthPercent = UnitHealthPercent
local InCombatLockdown = InCombatLockdown
local type = type
local tostring = tostring
local abs = math.abs
local issecretvalue = _G.issecretvalue

-- External Data Registry (prevents taint on secure CompactUnitFrames)
local PARTY_FRAME_STATE_REGISTRY = "UnitFramesPartyState"
local PartyFrameData = RefineUI:CreateDataRegistry(PARTY_FRAME_STATE_REGISTRY, "k")

local function GetPartyData(frame)
    if not frame then return {} end
    local data = PartyFrameData[frame]
    if not data then
        data = {}
        PartyFrameData[frame] = data
    end
    return data
end

local function GetPartyHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(owner)
end

local function BuildPartyHookKey(owner, method)
    return "UnitFramesParty:" .. GetPartyHookOwnerId(owner) .. ":" .. method
end

local function IsUnreadableNumber(value)
    return type(value) == "number" and issecretvalue and issecretvalue(value)
end

local function IsEditModeActiveNow()
    return EditModeManagerFrame
        and type(EditModeManagerFrame.IsEditModeActive) == "function"
        and EditModeManagerFrame:IsEditModeActive()
end

local function IsPartyRaidCompactFrame(frame)
    if not frame then return false end

    local groupType = frame.groupType
    if not groupType then return false end

    local enum = _G.CompactRaidGroupTypeEnum
    if type(enum) == "table" then
        return groupType == enum.Party or groupType == enum.Raid
    end

    return true
end

local function IsCompactPetUnitToken(unit)
    return type(unit) == "string" and unit:find("pet", 1, true) ~= nil
end

local function GetCompactPetOwnerUnit(frame)
    if not frame then return nil end

    local unit = frame.displayedUnit or frame.unit
    if type(unit) ~= "string" then return nil end
    if unit == "pet" then return "player" end

    local prefix, id = unit:match("^(.-)pet(%d+)$")
    if prefix and id and prefix ~= "" then
        return prefix .. id
    end

    return nil
end

local function GetCompactPetOwnerClassColor(frame)
    local ownerUnit = GetCompactPetOwnerUnit(frame)
    if not ownerUnit then return nil end

    local _, class = UnitClass(ownerUnit)
    if not class then return nil end
    return RefineUI.Colors and RefineUI.Colors.Class and RefineUI.Colors.Class[class]
end

local TEXTURE_LEADER        = [[Interface\AddOns\RefineUI\Media\Textures\LEADER.blp]]
local TEXTURE_ROLE_TANK     = [[Interface\AddOns\RefineUI\Media\Textures\TANK.blp]]
local TEXTURE_ROLE_HEALER   = [[Interface\AddOns\RefineUI\Media\Textures\HEALER.blp]]
local TEXTURE_ROLE_DAMAGER  = [[Interface\AddOns\RefineUI\Media\Textures\DAMAGER.blp]]
local TEXTURE_COMPACT_HEALTH = RefineUI.Media.Textures.Smooth

----------------------------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------------------------

local GAP = 18
local PET_GAP = 8

local function GetCompactFrameVerticalGap(frame)
    local unit = frame and (frame.displayedUnit or frame.unit)
    if IsCompactPetUnitToken(unit) then
        return PET_GAP
    end
    return GAP
end

local function HookSpacing(frame)
    RefineUI:HookOnce(BuildPartyHookKey(frame, "SetPoint:Spacing"), frame, "SetPoint", function(self, point, relTo, relPoint, x, y)
        local d = GetPartyData(self)
        if d.changing or InCombatLockdown() or IsEditModeActiveNow() then return end
        
        -- Detect vertical stacking (TOP anchored to BOTTOM)
        if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
             local desiredGap = GetCompactFrameVerticalGap(self)
             if IsUnreadableNumber(x) or IsUnreadableNumber(y) then return end
             local currentX = type(x) == "number" and x or 0
             local currentY = type(y) == "number" and y or 0
             if currentY ~= -desiredGap and abs(currentY) <= GAP then
                 d.changing = true
                 self:SetPoint(point, relTo, relPoint, currentX, -desiredGap)
                 d.changing = false
             end
        end
    end)
end

local function ForceRestoreSpacing()
    if InCombatLockdown() or IsEditModeActiveNow() then return end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember"..i]
        if frame and frame:IsShown() then
            local data = GetPartyData(frame)
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         data.changing = true
                         frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         data.changing = false
                     end
                 end
            end
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and frame:IsShown() then
            local data = GetPartyData(frame)
            local point, relTo, relPoint, x, y = frame:GetPoint()
            if (point == "TOP" or point == "TOPLEFT") and (relPoint == "BOTTOM" or relPoint == "BOTTOMLEFT") then
                 local desiredGap = GetCompactFrameVerticalGap(frame)
                 if not (IsUnreadableNumber(x) or IsUnreadableNumber(y)) then
                     if type(y) == "number" and y ~= -desiredGap and abs(y) <= GAP then
                         data.changing = true
                         frame:SetPoint(point, relTo, relPoint, x, -desiredGap)
                         data.changing = false
                     end
                 end
            end
        end
    end
end

local function ForEachCompactPartyFrame(includeHidden, fn)
    if type(fn) ~= "function" then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember"..i]
        if frame and (includeHidden or frame:IsShown()) then
            fn(frame)
        end
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFramePet"..i]
        if frame and (includeHidden or frame:IsShown()) then
            fn(frame)
        end
    end
end

local function UpdateCustomPartyHP(self)
    local frame = self.frame
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    
    -- SAFETY GATE: Defer during Edit Mode (only check IsEditModeActive, not editModeStatus which persists)
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        C_Timer.After(0.1, function()
            if frame and not frame:IsForbidden() and not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UpdateCustomPartyHP({frame = frame})
            end
        end)
        return
    end
    
    -- Get text from external data
    local data = GetPartyData(frame)
    local percentText = data.CustomPercentText
    if not percentText then return end
    
    if not UnitIsConnected(unit) then
        percentText:SetText("OFFLINE")
        percentText:SetTextColor(0.5, 0.5, 0.5)
    elseif UnitIsDeadOrGhost(unit) then
        percentText:SetText("DEAD")
        percentText:SetTextColor(0.5, 0.5, 0.5)
    else
        local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
        percentText:SetText(percent)
        percentText:SetTextColor(1, 1, 1)
    end
    percentText:Show()
end

local function UpdateCompactPartyLeader(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    if IsCompactPetUnitToken(frame and (frame.unit or frame.displayedUnit)) then return end

    local data = GetPartyData(frame)
    local unit = frame.unit or frame.displayedUnit
    local isLeader = unit and UnitIsGroupLeader(unit)
    
    -- Create leader icon in external data if needed
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
            local color = RefineUI.Colors.Class[class] 
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

local function UpdateCompactPartyNameColor(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    if not frame or frame:IsForbidden() or not frame.name then return end
    
    -- SAFETY GATE: Defer during Edit Mode (only check IsEditModeActive, not editModeStatus which persists)
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        C_Timer.After(0.1, function()
            if frame and not frame:IsForbidden() and not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UpdateCompactPartyNameColor(frame)
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
            local color = RefineUI.Colors.Class[class]
            if color then
                r, g, b = color.r, color.g, color.b
            end
            
            if r then
                frame.name:SetVertexColor(r, g, b, 1, "RefineUI_Hook")
            end
        end
    end
end

local function CreateCustomPartyText(frame)
    if not IsPartyRaidCompactFrame(frame) then return end
    local data = GetPartyData(frame)
    if not data.customTextCreated then 
        if frame.statusText then
            frame.statusText:SetAlpha(0)
        end
        
        -- Create Custom Percent Text (stored ONLY in external data)
        local text = frame.healthBar:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(text, 20, nil, "OUTLINE", false)
        text:SetTextColor(1, 1, 1)
        text:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
        data.CustomPercentText = text
        
        -- Event Handling
        local function OnPartyEvent(event, u)
            if u == frame.unit then UpdateCustomPartyHP({frame = frame}) end
        end
        
        local frameName = frame.GetName and frame:GetName()
        local key = "Party_"..(frameName or tostring(frame))
        RefineUI:RegisterEventCallback("UNIT_HEALTH", OnPartyEvent, key.."_HP")
        RefineUI:RegisterEventCallback("UNIT_MAXHEALTH", OnPartyEvent, key.."_MHP")
        RefineUI:RegisterEventCallback("UNIT_CONNECTION", OnPartyEvent, key.."_CON")
        
        data.customTextCreated = true
    end
    
    UpdateCustomPartyHP({frame=frame})
end

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
    if expandForPowerBar then
        -- Match Blizzard's compact frame extents when the power bar is shown.
        borderHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    else
        borderHost:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
    end

    data.healthBarBorderExpanded = expandForPowerBar
end

function UF.StyleCompactPartyFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not IsPartyRaidCompactFrame(frame) then return end
    
    -- SAFETY GATE: Defer during Edit Mode to prevent taint
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then
        C_Timer.After(0.1, function()
            if frame and not frame:IsForbidden() and not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then
                UF.StyleCompactPartyFrame(frame)
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

    HookSpacing(frame)
    
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
             -- Create border via an isolated overlay frame (no BackdropTemplate usage)
             -- to avoid secret-value arithmetic in Blizzard Backdrop.lua.
             local inset = 6
             local edgeSize = RefineUI:Scale(12)

             local borderHost = CreateFrame("Frame", nil, frame.healthBar)
             borderHost:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
             borderHost:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
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

         -- Update border color from external data
         local border = data.healthBarBorder
         if Config.General.BorderColor and border then
              border:SetBackdropBorderColor(unpack(Config.General.BorderColor))
         end

         if isPetFrame then
             UpdateCompactPetFrameColors(frame)
         end
    end
    
    if not isPetFrame then
        CreateCustomPartyText(frame)
    elseif frame.statusText then
        frame.statusText:SetAlpha(0)
    end

    UpdateCompactPartyNameColor(frame)
    if not isPetFrame then
        UpdateCompactPartyLeader(frame)
    end
    
    -- Disable Tooltips (Shift Overlay)
    if Config.UnitFrames.DisableTooltips then
        RefineUI:HookScriptOnce(BuildPartyHookKey(frame, "OnEnter:Tooltip"), frame, "OnEnter", function(self)
            if not IsShiftKeyDown() then
                GameTooltip:Hide()
            end
        end)
    end
end

-- Role Icons (Hooked via CompactUnitFrame_UpdateRoleIcon)
function UF.UpdateRoleIcon(frame)
    if not frame or not frame.roleIcon then return end
    if not IsPartyRaidCompactFrame(frame) then return end
    if IsCompactPetUnitToken(frame.displayedUnit or frame.unit) then
        local data = GetPartyData(frame)
        if data.roleIcon then data.roleIcon:Hide() end
        return
    end
    
    -- SAFETY GATE: Skip during Edit Mode (only check IsEditModeActive, not editModeStatus which persists)
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()
    if isEditMode then return end
    
    local data = GetPartyData(frame)
    local role = UnitGroupRolesAssigned(frame.unit or frame.displayedUnit)
    
    -- Check display option
    if frame.optionTable and not frame.optionTable.displayRoleIcon then
        if data.roleIcon then data.roleIcon:Hide() end
        return
    end

    if ( role == "TANK" or role == "HEALER" or role == "DAMAGER" ) then
        -- BANISH BLIZZARD ICON NON-DESTRUCTIVELY
        frame.roleIcon:SetAlpha(0)
        
        -- CREATE/GET CUSTOM ICON (stored in external data)
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
            local color = RefineUI.Colors.Class[class] 
            if color then
                roleIcon:SetVertexColor(color.r, color.g, color.b)
            else
                 roleIcon:SetVertexColor(1, 1, 1)
            end
        end
    else
        -- Hide ours if no role
        if data.roleIcon then data.roleIcon:Hide() end
    end
end

-- Initialization of Hooks
function UF.InitPartyHooks()
    if UF._partyHooksRegistered then return end

    local function RegisterCompactPartyHooks()
        local registered = false

        if _G.CompactUnitFrame_Update then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_Update", "CompactUnitFrame_Update", UF.StyleCompactPartyFrame)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateAll then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateAll:Style", "CompactUnitFrame_UpdateAll", UF.StyleCompactPartyFrame)
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateAll", "CompactUnitFrame_UpdateAll", UpdateCompactPartyNameColor)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateName then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateName", UpdateCompactPartyNameColor)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateHealthColor then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateHealthColor", UpdateCompactPetFrameColors)
            registered = true
        end
        if _G.CompactUnitFrame_UpdateRoleIcon then
            RefineUI:HookOnce("UnitFramesParty:CompactUnitFrame_UpdateRoleIcon", "CompactUnitFrame_UpdateRoleIcon", UF.UpdateRoleIcon)
            registered = true
        end

        return registered
    end

    if RegisterCompactPartyHooks() then
        UF._partyHooksRegistered = true
    end
    
    if CompactPartyFrameTitle then
        CompactPartyFrameTitle:SetAlpha(0)
    end
    
    -- Hide the Raid Frame Manager pop-out tool
    local manager = _G.CompactRaidFrameManager
    if manager then
        manager:SetAlpha(0)
        manager:EnableMouse(false)
        if manager.displayFrame then
            manager.displayFrame:SetAlpha(0)
            manager.displayFrame:EnableMouse(false)
        end
    end
    
    -- Events for persistence
    local function OnPartyEvent(event, addon)
         if event == "ADDON_LOADED" and addon == "Blizzard_CompactRaidFrames" then
              if RegisterCompactPartyHooks() then
                  UF._partyHooksRegistered = true
              end
              
              -- Race Condition Fix: Retroactively apply to existing frames
              ForEachCompactPartyFrame(true, function(frame)
                  UF.StyleCompactPartyFrame(frame)
                  UF.UpdateRoleIcon(frame)
              end)
         elseif event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
            ForEachCompactPartyFrame(false, function(frame)
                UF.StyleCompactPartyFrame(frame)
                UF.UpdateRoleIcon(frame)
            end)
            -- Force restore if we are OOC (handles cases where updates happened in combat)
            ForceRestoreSpacing() 
            
         elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            ForEachCompactPartyFrame(true, function(frame)
                UF.StyleCompactPartyFrame(frame)
                UF.UpdateRoleIcon(frame)
            end)
            ForceRestoreSpacing()
            if event == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(0.1, ForceRestoreSpacing)
            end
         end
    end
    
    RefineUI:OnEvents({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET"}, OnPartyEvent, "RefinePartyHooks")
end
