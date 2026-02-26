----------------------------------------------------------------------------------------
-- UnitFrames Module
-- Description: Player, Target, Focus, Pet, and Boss frame skinning.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:RegisterModule("UnitFrames")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

-- External Data Registry
local UNITFRAME_STATE_REGISTRY = "UnitFramesState"
RefineUI.UnitFrameData = RefineUI.UnitFrameData or RefineUI:CreateDataRegistry(UNITFRAME_STATE_REGISTRY, "k")

-- Global Imports
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitExists = UnitExists
local UnitHealthPercent = UnitHealthPercent
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local InCombatLockdown = InCombatLockdown
local unpack = unpack
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local CreateFrame = CreateFrame
local abs = math.abs
local issecretvalue = _G.issecretvalue

-- Constants
local M = RefineUI.Media.Textures
local TEXTURE_FRAME       = M.Frame
local TEXTURE_FRAME_SMALL = M.FrameSmall
local TEXTURE_FRAME_PET   = M.PetFrame or [[Interface\AddOns\RefineUI\Media\Textures\PortraitOff-Pet.blp]]
local TEXTURE_BACKGROUND  = M.HealthBackground
local MASK_FRAME          = M.FrameMask
local MASK_HEALTH         = M.MaskHealth
local MASK_MANA           = M.MaskMana
local TEXTURE_HEALTH_BAR  = M.HealthBar
local TEXTURE_POWER_BAR   = M.PowerBar
local TEXTURE_SECONDARY_MANA_OVERLAY = M.Smooth or [[Interface\Buttons\WHITE8x8]]
local POWER_TYPE_MANA     = Enum.PowerType.Mana
local MAX_BOSS_FRAMES     = 5
local BOSS_HEALTH_WIDTH   = 126
local BOSS_HEALTH_HEIGHT  = 20
local BOSS_MANA_WIDTH     = 134
local BOSS_MANA_HEIGHT    = 10
local PET_FRAME_WIDTH     = 120
local PET_FRAME_HEIGHT    = 49
local PET_BORDER_WIDTH    = 256
local PET_BORDER_HEIGHT   = 64
local PET_HEALTH_WIDTH    = 60
local PET_HEALTH_HEIGHT   = 24
local PET_HEALTH_X        = -19
local PET_HEALTH_Y        = -10
local PendingStaticStyleFrames = setmetatable({}, { __mode = "k" })
local StyleUnitFrame
local StylePetFrame
local ApplyPetFrameDynamicStyle

----------------------------------------------------------------------------------------
-- Core Logic
----------------------------------------------------------------------------------------
local function GetFrameContainers(frame)
    return UF.GetFrameContainers(frame)
end

local function GetUnitFrameData(frame)
    if not frame then return nil end
    local data = RefineUI.UnitFrameData[frame]
    if not data then
        data = {}
        RefineUI.UnitFrameData[frame] = data
    end
    return data
end

local function GetHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(owner)
end

local function BuildUnitFrameHookKey(owner, method)
    return "UnitFrames:" .. GetHookOwnerId(owner) .. ":" .. method
end

local function IsBossUnit(unit)
    return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

local function GetBossFrameForUnit(unit)
    if not IsBossUnit(unit) then return nil end
    local unitIndex = unit:match("^boss(%d+)$")
    if not unitIndex then return nil end
    return _G["Boss" .. unitIndex .. "TargetFrame"]
end

local function AddBossFrames(frameList)
    local function TryAdd(frame)
        if not frame then return end
        for _, existing in ipairs(frameList) do
            if existing == frame then
                return
            end
        end
        frameList[#frameList + 1] = frame
    end

    if BossTargetFrameContainer and BossTargetFrameContainer.BossTargetFrames then
        for _, bossFrame in ipairs(BossTargetFrameContainer.BossTargetFrames) do
            TryAdd(bossFrame)
        end
        return
    end

    for index = 1, MAX_BOSS_FRAMES do
        local bossFrame = _G["Boss" .. index .. "TargetFrame"]
        TryAdd(bossFrame)
    end
end

local function ApplyBossBarLayout(frameContainer, hpContainer, manaBar)
    if InCombatLockdown() then return end
    if not frameContainer or not hpContainer or not manaBar then return end

    hpContainer:ClearAllPoints()
    hpContainer:SetPoint("BOTTOMRIGHT", frameContainer, "LEFT", RefineUI:Scale(148), RefineUI:Scale(2))
    RefineUI:SetPixelSize(hpContainer, BOSS_HEALTH_WIDTH, BOSS_HEALTH_HEIGHT)

    if hpContainer.HealthBar then
        hpContainer.HealthBar:ClearAllPoints()
        hpContainer.HealthBar:SetPoint("TOPLEFT", hpContainer, "TOPLEFT", 0, 0)
        RefineUI:SetPixelSize(hpContainer.HealthBar, BOSS_HEALTH_WIDTH, BOSS_HEALTH_HEIGHT)
    end

    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPRIGHT", hpContainer, "BOTTOMRIGHT", RefineUI:Scale(8), RefineUI:Scale(-1))
    RefineUI:SetPixelSize(manaBar, BOSS_MANA_WIDTH, BOSS_MANA_HEIGHT)
end

local function QueueStaticStyle(frame)
    if not frame then return end
    PendingStaticStyleFrames[frame] = true
end

----------------------------------------------------------------------------------------
-- Player Secondary Mana Overlay
----------------------------------------------------------------------------------------
local function IsPlayerSecondaryPowerSwapActive(frame)
    if frame ~= PlayerFrame then
        return false
    end

    if frame.unit ~= "player" or frame.state == "vehicle" then
        return false
    end

    return UF.IsPlayerSecondaryPowerSwapActive and UF.IsPlayerSecondaryPowerSwapActive() or false
end

local function UpdatePlayerSecondaryManaOverlay(frame)
    if frame ~= PlayerFrame then return end

    local data = GetUnitFrameData(frame)
    local overlayData = data and data.RefinePlayerManaOverlay
    local overlay = overlayData and overlayData.Bar
    local sourceBar = overlayData and overlayData.SourceBar
    if not overlay or not sourceBar then return end

    overlay:ClearAllPoints()
    overlay:SetAllPoints(sourceBar)
    overlay:SetFrameStrata(sourceBar:GetFrameStrata())
    overlay:SetFrameLevel(sourceBar:GetFrameLevel() + 4)

    if sourceBar.ManaBarMask and not overlayData.MaskApplied then
        local overlayTexture = overlay.GetStatusBarTexture and overlay:GetStatusBarTexture()
        if overlayTexture and overlayTexture.AddMaskTexture then
            overlayTexture:AddMaskTexture(sourceBar.ManaBarMask)
        end
        if overlayData.Background and overlayData.Background.AddMaskTexture then
            overlayData.Background:AddMaskTexture(sourceBar.ManaBarMask)
        end
        overlayData.MaskApplied = true
    end

    if not IsPlayerSecondaryPowerSwapActive(frame) then
        overlay:Hide()
        return
    end

    local currentMana = UnitPower("player", POWER_TYPE_MANA)
    local maxMana = UnitPowerMax("player", POWER_TYPE_MANA)
    local isSecret = issecretvalue and (issecretvalue(currentMana) or issecretvalue(maxMana))
    local allowSecretPassThrough = true

    if isSecret and not allowSecretPassThrough then
        local safeMax = overlayData.LastSafeMax
        local safeMin = overlayData.LastSafeMin

        if type(safeMax) ~= "number" or safeMax <= 0 or (issecretvalue and issecretvalue(safeMax)) then
            safeMax = 1
        end
        if type(safeMin) ~= "number" or (issecretvalue and issecretvalue(safeMin)) then
            safeMin = 0
        end
        if safeMin < 0 then safeMin = 0 end
        if safeMin > safeMax then safeMin = safeMax end

        overlay:SetMinMaxValues(0, safeMax)
        overlay:SetValue(safeMin)
    else
        if not isSecret then
            if type(maxMana) ~= "number" or maxMana <= 0 then
                maxMana = 1
            end
            if type(currentMana) ~= "number" or currentMana < 0 then
                currentMana = 0
            end
            if currentMana > maxMana then
                currentMana = maxMana
            end
            overlayData.LastSafeMin = currentMana
            overlayData.LastSafeMax = maxMana
        end
        overlay:SetMinMaxValues(0, maxMana)
        overlay:SetValue(currentMana)
    end

    local manaColor = RefineUI.Colors and RefineUI.Colors.Power and RefineUI.Colors.Power.MANA
    if manaColor then
        overlay:SetStatusBarColor(manaColor.r, manaColor.g, manaColor.b)
    else
        overlay:SetStatusBarColor(0, 0.55, 1)
    end

    overlay:Show()
end

local function EnsurePlayerSecondaryManaOverlay(frame, manaBar)
    if frame ~= PlayerFrame or not manaBar then return end

    local data = GetUnitFrameData(frame)
    if not data then return end

    if not data.RefinePlayerManaOverlay then
        local overlay = CreateFrame("StatusBar", nil, manaBar)
        overlay:SetStatusBarTexture(TEXTURE_SECONDARY_MANA_OVERLAY)
        overlay:SetStatusBarDesaturated(true)
        overlay:Hide()

        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(overlay)
        bg:SetColorTexture(0.03, 0.03, 0.03, 1)

        data.RefinePlayerManaOverlay = {
            Bar = overlay,
            Background = bg,
            SourceBar = manaBar,
            LastSafeMin = 0,
            LastSafeMax = 1,
        }
    else
        data.RefinePlayerManaOverlay.SourceBar = manaBar
    end

    local overlayData = data.RefinePlayerManaOverlay
    if not overlayData.eventsRegistered then
        local overlay = overlayData.Bar
        overlay:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        overlay:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        overlay:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        overlay:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        overlay:RegisterEvent("PLAYER_ENTERING_WORLD")
        overlay:SetScript("OnEvent", function(_, event, unit, powerType)
            if event == "UNIT_POWER_UPDATE" then
                if unit ~= "player" or powerType ~= "MANA" then
                    return
                end
            elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if unit ~= "player" then
                    return
                end
            end

            UpdatePlayerSecondaryManaOverlay(frame)
        end)
        overlayData.eventsRegistered = true
    end

    UpdatePlayerSecondaryManaOverlay(frame)
end

local function GetPetPercentValue()
    if UnitHealthPercent and RefineUI.GetPercentCurve then
        return UnitHealthPercent("pet", true, RefineUI.GetPercentCurve())
    end
    return 0
end

local function UpdatePetFrameHealthText(frame)
    if not frame then return end

    local data = GetUnitFrameData(frame)
    local petData = data and data.RefinePet
    local percentText = petData and petData.PercentText
    if not percentText then return end

    if not UnitExists("pet") then
        percentText:SetText("")
        return
    end

    if not UnitIsConnected("pet") then
        percentText:SetText("OFFLINE")
        percentText:SetTextColor(0.5, 0.5, 0.5)
        return
    end

    if UnitIsDeadOrGhost("pet") then
        percentText:SetText("DEAD")
        percentText:SetTextColor(0.5, 0.5, 0.5)
        return
    end

    percentText:SetText(GetPetPercentValue())
    percentText:SetTextColor(1, 1, 1)
end

local function EnforceHiddenRegion(region, hiddenFrame)
    if not region then return end

    region:SetAlpha(0)
    region:Hide()

    if hiddenFrame and not InCombatLockdown() and region.SetParent then
        region:SetParent(hiddenFrame)
    end

    RefineUI:HookOnce(BuildUnitFrameHookKey(region, "SetAlpha"), region, "SetAlpha", function(self, alpha)
        if alpha ~= 0 then
            self:SetAlpha(0)
        end
    end)
    RefineUI:HookOnce(BuildUnitFrameHookKey(region, "Show"), region, "Show", function(self)
        self:Hide()
    end)
end

local function ApplyPetFrameHitRect(frame)
    if not frame or not frame.SetHitRectInsets then return end

    -- Keep this purely geometric and static; querying live region coordinates on
    -- PetFrame can trigger Blizzard heal-prediction updates in a tainted context.
    local leftInset = PET_FRAME_WIDTH + PET_HEALTH_X - PET_HEALTH_WIDTH
    local rightInset = -PET_HEALTH_X
    local topInset = -PET_HEALTH_Y
    local bottomInset = PET_FRAME_HEIGHT - topInset - PET_HEALTH_HEIGHT

    if leftInset < 0 then leftInset = 0 end
    if rightInset < 0 then rightInset = 0 end
    if topInset < 0 then topInset = 0 end
    if bottomInset < 0 then bottomInset = 0 end

    frame:SetHitRectInsets(leftInset, rightInset, topInset, bottomInset)
end

local function GetPetEditModeSystemFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.registeredSystemFrames then return nil end

    local unitFrameSystem = Enum.EditModeSystem and Enum.EditModeSystem.UnitFrame
    local petFrameSystem = Enum.EditModeSystem and Enum.EditModeSystem.PetFrame
    local petSystemIndex = (Enum.EditModeUnitFrameSystemIndices and Enum.EditModeUnitFrameSystemIndices.Pet) or 8

    for _, systemFrame in ipairs(EditModeManagerFrame.registeredSystemFrames) do
        if systemFrame == PetFrame then
            return systemFrame
        end

        if petFrameSystem and systemFrame.system == petFrameSystem then
            return systemFrame
        end

        if unitFrameSystem and systemFrame.system == unitFrameSystem then
            if systemFrame.systemIndex == petSystemIndex or systemFrame.unit == "pet" then
                return systemFrame
            end
        end
    end

    return nil
end

local function ApplyPetSelectionBounds(frame)
    if not frame or not frame.Selection then return end
    local selection = frame.Selection
    local anchor = PetFrameHealthBar or frame

    local function AnchorSelection(sel)
        if not sel or not sel.ClearAllPoints or not sel.SetPoint then return end
        if sel.changing or InCombatLockdown() then return end
        sel.changing = true
        sel:ClearAllPoints()
        if anchor == PetFrameHealthBar then
            sel:SetPoint("TOPLEFT", anchor, "TOPLEFT", RefineUI:Scale(-2), RefineUI:Scale(2))
            sel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", RefineUI:Scale(2), RefineUI:Scale(-2))
        else
            sel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            sel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        sel.changing = false
    end

    AnchorSelection(selection)

    RefineUI:HookOnce(BuildUnitFrameHookKey(selection, "SetPoint"), selection, "SetPoint", function(self)
        if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
            AnchorSelection(self)
        end
    end)
    RefineUI:HookOnce(BuildUnitFrameHookKey(selection, "SetAllPoints"), selection, "SetAllPoints", function(self)
        if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
            AnchorSelection(self)
        end
    end)
end

local function HidePetAuras(frame)
    if not frame then return end

    if frame.AuraFrameContainer then
        EnforceHiddenRegion(frame.AuraFrameContainer, RefineUI.HiddenFrame)
    end

    if frame.AuraFramePool and frame.AuraFramePool.ReleaseAll then
        frame.AuraFramePool:ReleaseAll()
    end

    if PartyMemberBuffTooltip and PartyMemberBuffTooltip.Hide then
        PartyMemberBuffTooltip:Hide()
    end
end

local function SyncPetEditModeMoverSize()
    if InCombatLockdown() then return end
    if not EditModeManagerFrame or not EditModeManagerFrame.IsEditModeActive or not EditModeManagerFrame:IsEditModeActive() then
        return
    end

    local mover = GetPetEditModeSystemFrame()
    if not mover or not mover.SetSize then return end

    local targetWidth = RefineUI:Scale(PET_FRAME_WIDTH)
    local targetHeight = RefineUI:Scale(PET_FRAME_HEIGHT)

    local currentWidth = mover.GetWidth and mover:GetWidth() or 0
    local currentHeight = mover.GetHeight and mover:GetHeight() or 0
    if abs(currentWidth - targetWidth) > 0.5 or abs(currentHeight - targetHeight) > 0.5 then
        mover:SetSize(targetWidth, targetHeight)
    end

    if mover.selection and mover.selection.SetAllPoints then
        mover.selection:ClearAllPoints()
        mover.selection:SetAllPoints(mover)
    end
    if mover.Selection and mover.Selection.SetAllPoints then
        mover.Selection:ClearAllPoints()
        mover.Selection:SetAllPoints(mover)
    end
end

ApplyPetFrameDynamicStyle = function(frame)
    if not frame or not PetFrameHealthBar then return end

    PetFrameHealthBar:SetStatusBarTexture(TEXTURE_HEALTH_BAR)
    PetFrameHealthBar:SetStatusBarDesaturated(true)

    local hr, hg, hb = UF.GetUnitHealthColor("pet")
    PetFrameHealthBar:SetStatusBarColor(hr, hg, hb)

    UpdatePetFrameHealthText(frame)
end

StylePetFrame = function(frame)
    if not frame then return end
    if InCombatLockdown() then
        QueueStaticStyle(frame)
        ApplyPetFrameDynamicStyle(frame)
        return
    end

    PendingStaticStyleFrames[frame] = nil
    local data = GetUnitFrameData(frame)
    local hiddenFrame = RefineUI.HiddenFrame

    RefineUI:SetPixelSize(frame, PET_FRAME_WIDTH, PET_FRAME_HEIGHT)

    if not data.RefinePet then
        data.RefinePet = CreateFrame("Frame", nil, frame)
        data.RefinePet:SetAllPoints(frame)
        data.RefinePet:SetFrameStrata("HIGH")

        data.RefinePet.Border = data.RefinePet:CreateTexture(nil, "OVERLAY")
        data.RefinePet.Border:SetDrawLayer("OVERLAY", 2)

        data.RefinePet.PercentText = data.RefinePet:CreateFontString(nil, "OVERLAY")
    end

    local petData = data.RefinePet
    local border = petData.Border
    border:SetTexture(TEXTURE_FRAME_PET)
    border:ClearAllPoints()
    if PetFrameHealthBar then
        border:SetPoint("CENTER", PetFrameHealthBar, "CENTER", 0, -14)
    else
        border:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    RefineUI:SetPixelSize(border, PET_BORDER_WIDTH, PET_BORDER_HEIGHT)
    border:SetAlpha(1)
    border:Show()

    if Config.General.BorderColor then
        border:SetVertexColor(unpack(Config.General.BorderColor))
    end

    if PetFrameHealthBar then
        PetFrameHealthBar:ClearAllPoints()
        PetFrameHealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", RefineUI:Scale(PET_HEALTH_X), RefineUI:Scale(PET_HEALTH_Y))
        RefineUI:SetPixelSize(PetFrameHealthBar, PET_HEALTH_WIDTH, PET_HEALTH_HEIGHT)
        PetFrameHealthBar:SetAlpha(1)
        PetFrameHealthBar:Show()
    end
    ApplyPetFrameHitRect(frame)
    ApplyPetSelectionBounds(frame)
    SyncPetEditModeMoverSize()

    if petData.PercentText then
        RefineUI.Font(petData.PercentText, Config.UnitFrames.Fonts.HPSize)
        petData.PercentText:ClearAllPoints()
        if PetFrameHealthBar then
            petData.PercentText:SetPoint("CENTER", PetFrameHealthBar, "CENTER", 0, 0)
        else
            petData.PercentText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        end
        petData.PercentText:SetJustifyH("CENTER")
        petData.PercentText:SetJustifyV("MIDDLE")
    end

    for _, region in pairs({
        PetPortrait,
        PetFrameTexture,
        PetFrameFlash,
        PetAttackModeTexture,
        PetHitIndicator,
        PetName,
        PetNameBackground,
        PetFrameManaBar,
        PetFrameManaBarMask,
        PetFrameHealthBarMask,
        PetFrameManaBarText,
        PetFrameManaBarTextLeft,
        PetFrameManaBarTextRight,
        PetFrameHealthBarText,
        PetFrameHealthBarTextLeft,
        PetFrameHealthBarTextRight,
        PetFrameOverAbsorbGlow,
    }) do
        EnforceHiddenRegion(region, hiddenFrame)
    end

    HidePetAuras(frame)

    if PetFrameHealthBar then
        RefineUI:HookOnce(BuildUnitFrameHookKey(PetFrameHealthBar, "SetStatusBarColor"), PetFrameHealthBar, "SetStatusBarColor", function(self, r1, g1, b1)
            local r2, g2, b2 = UF.GetUnitHealthColor("pet")
            if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then
                self:SetStatusBarColor(r2, g2, b2)
            end
        end)
        RefineUI:HookOnce(BuildUnitFrameHookKey(PetFrameHealthBar, "SetStatusBarTexture"), PetFrameHealthBar, "SetStatusBarTexture", function(self, tex)
            if tex ~= TEXTURE_HEALTH_BAR then
                self:SetStatusBarTexture(TEXTURE_HEALTH_BAR)
                self:SetStatusBarDesaturated(true)
            end
        end)
        RefineUI:HookScriptOnce(BuildUnitFrameHookKey(PetFrameHealthBar, "OnValueChanged"), PetFrameHealthBar, "OnValueChanged", function()
            UpdatePetFrameHealthText(frame)
        end)
    end

    RefineUI:HookOnce(BuildUnitFrameHookKey(frame, "UpdateAuras:Hide"), frame, "UpdateAuras", function(self)
        HidePetAuras(self)
    end)
    RefineUI:HookScriptOnce(BuildUnitFrameHookKey(frame, "OnEnter:HidePetAurasTooltip"), frame, "OnEnter", function()
        if PartyMemberBuffTooltip and PartyMemberBuffTooltip.Hide then
            PartyMemberBuffTooltip:Hide()
        end
    end)

    ApplyPetFrameDynamicStyle(frame)
end

local function ApplyUnitFrameDynamicStyle(frame)
    if not frame then return end

    if frame == PetFrame then
        ApplyPetFrameDynamicStyle(frame)
        return
    end

    local unit = frame.unit or "player"
    local _, contentMain, hpContainer, manaBar = GetFrameContainers(frame)
    if not hpContainer or not manaBar then return end

    if hpContainer.HealthBar then
        hpContainer.HealthBar:SetStatusBarTexture(TEXTURE_HEALTH_BAR)
        hpContainer.HealthBar:SetStatusBarDesaturated(true)
        local hr, hg, hb = UF.GetUnitHealthColor(unit)
        hpContainer.HealthBar:SetStatusBarColor(hr, hg, hb)
    end

    manaBar:SetStatusBarTexture(TEXTURE_POWER_BAR)
    manaBar:SetStatusBarDesaturated(true)
    local pr, pg, pb = UF.GetUnitPowerColor(unit)
    manaBar:SetStatusBarColor(pr, pg, pb)

    if contentMain and frame ~= PlayerFrame and contentMain.Name then
        local nr, ng, nb = UF.GetUnitHealthColor(unit)
        contentMain.Name:SetTextColor(nr, ng, nb)
    end
end

local function FlushQueuedStaticStyles()
    if InCombatLockdown() then return end
    for frame in pairs(PendingStaticStyleFrames) do
        PendingStaticStyleFrames[frame] = nil
        StyleUnitFrame(frame)
    end
end

StyleUnitFrame = function(frame)
    if not frame then return end
    if frame == PetFrame then
        StylePetFrame(frame)
        return
    end

    if InCombatLockdown() then
        QueueStaticStyle(frame)
        ApplyUnitFrameDynamicStyle(frame)
        return
    end

    PendingStaticStyleFrames[frame] = nil
    local data = GetUnitFrameData(frame)
    local unit = frame.unit or "player"
    local isBossFrame = frame.isBossFrame or IsBossUnit(unit)
    
    -- EditMode Taint Protection: Do not set scale in combat
    if Config.UnitFrames.Scale and not InCombatLockdown() then
        if frame:GetScale() ~= Config.UnitFrames.Scale then
            frame:SetScale(Config.UnitFrames.Scale)
        end
    end
    
    -- 1. Get Blizzard Parts
    local cfg = Config.UnitFrames.Fonts
    local frameContainer = frame.PlayerFrameContainer or frame.TargetFrameContainer
    local content, contentMain, hpContainer, manaBar = GetFrameContainers(frame)
    if not hpContainer or not manaBar then return end
    
    local contentContext = content and (content.PlayerFrameContentContextual or content.TargetFrameContentContextual)
    local hiddenFrame = RefineUI.HiddenFrame

    if isBossFrame then
        ApplyBossBarLayout(frameContainer, hpContainer, manaBar)
    end

    -- Apply Custom Bar Textures
    if hpContainer.HealthBar then 
        hpContainer.HealthBar:SetStatusBarTexture(TEXTURE_HEALTH_BAR)
        hpContainer.HealthBar:SetStatusBarDesaturated(true)
    end
    if manaBar then 
        manaBar:SetStatusBarTexture(TEXTURE_POWER_BAR)
        manaBar:SetStatusBarDesaturated(true)
    end

    -- Apply Colors
    local hr, hg, hb = UF.GetUnitHealthColor(unit)
    hpContainer.HealthBar:SetStatusBarColor(hr, hg, hb)
    
    RefineUI:HookOnce(BuildUnitFrameHookKey(hpContainer.HealthBar, "SetStatusBarColor"), hpContainer.HealthBar, "SetStatusBarColor", function(self, r1, g1, b1)
        local r2, g2, b2 = UF.GetUnitHealthColor(unit)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then 
            self:SetStatusBarColor(r2, g2, b2) 
        end
    end)

    local pr, pg, pb = UF.GetUnitPowerColor(unit)
    manaBar:SetStatusBarColor(pr, pg, pb)

    RefineUI:HookOnce(BuildUnitFrameHookKey(manaBar, "SetStatusBarColor"), manaBar, "SetStatusBarColor", function(self, r1, g1, b1)
        local r2, g2, b2 = UF.GetUnitPowerColor(unit)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then 
            self:SetStatusBarColor(r2, g2, b2) 
        end
    end)
    -- Texture hook for manaBar
    RefineUI:HookOnce(BuildUnitFrameHookKey(manaBar, "SetStatusBarTexture"), manaBar, "SetStatusBarTexture", function(self, tex)
        if tex ~= TEXTURE_POWER_BAR then 
            self:SetStatusBarTexture(TEXTURE_POWER_BAR)
            self:SetStatusBarDesaturated(true)
        end
    end)
    
    RefineUI:HookOnce(BuildUnitFrameHookKey(hpContainer.HealthBar, "SetStatusBarTexture"), hpContainer.HealthBar, "SetStatusBarTexture", function(self, tex)
        if tex ~= TEXTURE_HEALTH_BAR then 
            self:SetStatusBarTexture(TEXTURE_HEALTH_BAR)
            self:SetStatusBarDesaturated(true)
        end
    end)

    -- 2. Kill RefineUI/Blizzard Art
    if data.RefineStyle then data.RefineStyle:SetAlpha(0); data.RefineStyle:Hide() end
    
    if not InCombatLockdown() then
        if frame == PlayerFrame then
            frameContainer:SetParent(hiddenFrame)
        else
            frameContainer:SetAlpha(0)
            frameContainer:Hide()
        end
        
        if contentMain and contentMain.StatusTexture then
            contentMain.StatusTexture:SetParent(hiddenFrame)
            contentMain.StatusTexture:Hide()
        end
        
        if contentContext and contentContext.PlayerPortraitCornerIcon then
            contentContext.PlayerPortraitCornerIcon:SetParent(hiddenFrame)
            contentContext.PlayerPortraitCornerIcon:Hide()
        end

        if contentMain.ReputationColor then
            contentMain.ReputationColor:SetParent(hiddenFrame)
            contentMain.ReputationColor:Hide()
        end

        if contentMain.HitIndicator then
            contentMain.HitIndicator:SetParent(hiddenFrame)
            contentMain.HitIndicator:Hide()
        end
    else
        frameContainer:SetAlpha(0)
        if contentMain and contentMain.StatusTexture then contentMain.StatusTexture:Hide() end
        if contentContext and contentContext.PlayerPortraitCornerIcon then contentContext.PlayerPortraitCornerIcon:Hide() end
        if contentMain and contentMain.ReputationColor then contentMain.ReputationColor:Hide() end
        if contentMain and contentMain.HitIndicator then contentMain.HitIndicator:Hide() end
    end

    -- 2b. Hide Leader/Guide Icons (All Frames)
    if contentContext then
        for _, icon in pairs({contentContext.LeaderIcon, contentContext.GuideIcon}) do
            if icon then
                icon:SetAlpha(0)
                RefineUI:HookOnce(BuildUnitFrameHookKey(icon, "SetAlpha"), icon, "SetAlpha", function(self, alpha)
                    if alpha ~= 0 then self:SetAlpha(0) end
                end)
                RefineUI:HookOnce(BuildUnitFrameHookKey(icon, "Show"), icon, "Show", function(self)
                    self:SetAlpha(0)
                end)
            end
        end
    end

    -- 2c. Disable Tooltips (Shift Overlay)
    if Config.UnitFrames.DisableTooltips then
        frame:SetScript("OnEnter", function(self)
            if IsShiftKeyDown() then
                UnitFrame_OnEnter(self)
            end
        end)
        frame:SetScript("OnLeave", function(self)
            UnitFrame_OnLeave(self)
        end)
    end

    -- 3. Create RefineUF Mode Frame
    if not data.RefineUF then
        data.RefineUF = CreateFrame("Frame", nil, frame)
        data.RefineUF:SetFrameStrata("HIGH")
        data.RefineUF:SetAllPoints(frame)
        
        data.RefineUF.Texture = data.RefineUF:CreateTexture(nil, "OVERLAY")
        RefineUI:SetPixelSize(data.RefineUF.Texture, Config.UnitFrames.Layout.Width, 46)
        
        data.RefineUF.Background = frame:CreateTexture(nil, "BACKGROUND")
        data.RefineUF.Background:SetTexture(TEXTURE_BACKGROUND)
        data.RefineUF.Background:SetVertexColor(0.5, 0.5, 0.5, 1)
    end
    
    local refineUF = data.RefineUF
    -- Use manaBar visibility as proxy for power existence
    local showMana = manaBar and manaBar:IsShown()
    local bgYOffset = 0
    
    if not showMana then
        refineUF.Texture:SetTexture(TEXTURE_FRAME_SMALL)
        RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 46)
        bgYOffset = RefineUI:Scale(11) -- BBF noPortrait.lua:2578
    else
        refineUF.Texture:SetTexture(TEXTURE_FRAME)
        RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 46)
        bgYOffset = 0
    end
    
    if Config.General.BorderColor then
        refineUF.Texture:SetVertexColor(unpack(Config.General.BorderColor))
    end

    -- Texture content is 162x45, starting at 48x2
    RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 45)

    if frame == PlayerFrame then
        refineUF.Texture:ClearAllPoints()
        refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(66), RefineUI:Scale(-38))
        if hpContainer.HealthBarMask then
            hpContainer.HealthBarMask:SetTexture(MASK_HEALTH)
            hpContainer.HealthBarMask:ClearAllPoints()
            hpContainer.HealthBarMask:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(9))
            hpContainer.HealthBarMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(34))
            if hpContainer.HealthBar:GetStatusBarTexture() then
                hpContainer.HealthBar:GetStatusBarTexture():AddMaskTexture(hpContainer.HealthBarMask)
            end
        end
        
        if manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetTexture(MASK_MANA)
            manaBar.ManaBarMask:SetSize(RefineUI:Scale(192), RefineUI:Scale(25))
            manaBar.ManaBarMask:ClearAllPoints()
            manaBar.ManaBarMask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", RefineUI:Scale(-34), RefineUI:Scale(7))
            if manaBar:GetStatusBarTexture() then
                manaBar:GetStatusBarTexture():AddMaskTexture(manaBar.ManaBarMask)
            end
        end
        
        if contentContext and contentContext.RoleIcon then
            contentContext.RoleIcon:SetParent(hiddenFrame)
            contentContext.RoleIcon:Hide()
        end

        if contentContext and contentContext.PlayerRestLoop then
            contentContext.PlayerRestLoop:ClearAllPoints()
            contentContext.PlayerRestLoop:SetPoint("BOTTOM", refineUF.Texture, "TOP", 0, 0)
            contentContext.PlayerRestLoop:SetScale(0.5)
        end
    else
        -- Target/Focus
        refineUF.Texture:ClearAllPoints()
        if isBossFrame then
            -- Boss frames use compact Blizzard internals; nudge border up to align with bars.
            refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-26))
        else
            refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-38))
        end
        
        if hpContainer.HealthBarMask then
            hpContainer.HealthBarMask:SetTexture(MASK_HEALTH)
            hpContainer.HealthBarMask:SetSize(RefineUI:Scale(193), RefineUI:Scale(30))
            hpContainer.HealthBarMask:ClearAllPoints()
            hpContainer.HealthBarMask:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", RefineUI:Scale(-35), RefineUI:Scale(5))
            if hpContainer.HealthBar:GetStatusBarTexture() then
                hpContainer.HealthBar:GetStatusBarTexture():AddMaskTexture(hpContainer.HealthBarMask)
            end
        end
        
        if manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetTexture(MASK_MANA)
            manaBar.ManaBarMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(28))
            manaBar.ManaBarMask:ClearAllPoints()
            manaBar.ManaBarMask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(8))
            if manaBar:GetStatusBarTexture() then
                manaBar:GetStatusBarTexture():AddMaskTexture(manaBar.ManaBarMask)
            end
        end
    end

    -- 5. Background Masking
    refineUF.Background:ClearAllPoints()
    refineUF.Background:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", 0, 0)
    refineUF.Background:SetPoint("BOTTOMRIGHT", manaBar, "BOTTOMRIGHT", (frame == PlayerFrame and 0 or RefineUI:Scale(-10)), bgYOffset)
    
    if not data.BgMask then
        data.BgMask = refineUF:CreateMaskTexture()
        data.BgMask:SetAllPoints(refineUF.Background)
        data.BgMask:SetTexture(MASK_FRAME, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        refineUF.Background:AddMaskTexture(data.BgMask)
    end

    -- 5b. Player Secondary Mana Overlay (Shadow/Balance/Elemental full-swap visual)
    if frame == PlayerFrame then
        EnsurePlayerSecondaryManaOverlay(frame, manaBar)
    end

    -- 6. Custom Text Elements (RefineUI Style)
    if UF.CreateCustomText then
        if not data.customTextCreated then
            UF.CreateCustomText(frame)
            data.customTextCreated = true
        end
    end

    -- 6b. Hide Level Text
    local level = contentMain.LevelText
    if frame == PlayerFrame and not level then
        level = _G.PlayerLevelText
    end

    if level then
        if not InCombatLockdown() then
            level:SetParent(refineUF)
        end
        level:Hide()
        
        if frame == PlayerFrame then
            RefineUI:HookOnce(BuildUnitFrameHookKey(level, "Show"), level, "Show", function(self) self:Hide() end)
            if not InCombatLockdown() then
                level:SetParent(hiddenFrame)
                RefineUI:HookOnce(BuildUnitFrameHookKey(level, "SetParent"), level, "SetParent", function(self, p)
                    if p ~= hiddenFrame then self:SetParent(hiddenFrame) end
                end)
            end
        end
    end

    -- 6c. Name Color / Hide Player Name
    local name = contentMain.Name or (frame == PlayerFrame and frame.name)

    if name then
        if frame == PlayerFrame then
            name:SetAlpha(0)
            if not InCombatLockdown() then
                name:SetParent(hiddenFrame)
            end
            RefineUI:HookOnce(BuildUnitFrameHookKey(name, "SetAlpha"), name, "SetAlpha", function(self, a)
                if a ~= 0 then self:SetAlpha(0) end
            end)
            RefineUI:HookOnce(BuildUnitFrameHookKey(name, "Show"), name, "Show", function(self) self:Hide() end)
            RefineUI:HookOnce(BuildUnitFrameHookKey(name, "SetText"), name, "SetText", function(self) self:SetAlpha(0) end)
            if not InCombatLockdown() then
                RefineUI:HookOnce(BuildUnitFrameHookKey(name, "SetParent"), name, "SetParent", function(self, p)
                    if p ~= hiddenFrame then self:SetParent(hiddenFrame) end
                end)
            end
        else
            -- Color other frames
            local r, g, b = UF.GetUnitHealthColor(unit)
            contentMain.Name:SetTextColor(r, g, b)
            
            -- Re-anchor Name (RefineUI Style)
            contentMain.Name:SetParent(data.RefineUF)
            contentMain.Name:ClearAllPoints()
            contentMain.Name:SetPoint("BOTTOM", hpContainer, "TOP", 0, 0)
            contentMain.Name:SetJustifyH("CENTER")
            contentMain.Name:SetWordWrap(false)
            if cfg.NameWidth then contentMain.Name:SetWidth(cfg.NameWidth) end
            if cfg.NameSize then RefineUI.Font(contentMain.Name, cfg.NameSize) end

            RefineUI:HookOnce(BuildUnitFrameHookKey(contentMain.Name, "SetWidth"), contentMain.Name, "SetWidth", function(self, w)
                if cfg.NameWidth and w ~= cfg.NameWidth then self:SetWidth(cfg.NameWidth) end
            end)
            RefineUI:HookOnce(BuildUnitFrameHookKey(contentMain.Name, "SetWordWrap"), contentMain.Name, "SetWordWrap", function(self, wrap)
                if wrap ~= false then self:SetWordWrap(false) end
            end)
            RefineUI:HookOnce(BuildUnitFrameHookKey(contentMain.Name, "SetPoint"), contentMain.Name, "SetPoint", function(self, point, rel, relPoint, x, y)
                 if self.changing then return end
                 self.changing = true
                 self:ClearAllPoints()
                 self:SetPoint("BOTTOM", hpContainer, "TOP", 0, 0)
                 self.changing = false
            end)
            
            RefineUI:HookOnce(BuildUnitFrameHookKey(contentMain.Name, "SetTextColor"), contentMain.Name, "SetTextColor", function(self, r1, g1, b1)
                local r2, g2, b2 = UF.GetUnitHealthColor(unit)
                if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then 
                    self:SetTextColor(r2, g2, b2) 
                end
            end)
        end
    end

    -- 7. Fix Selection Highlight
    if frame.Selection and frame.Selection.TopLeftCorner then
        local xOffsetLeft = 0
        local xOffsetRight = 0
        local yOffsetBottom = 0
        local yOffsetTop = 6
        
        local bar = hpContainer.HealthBar
        
        if not InCombatLockdown() then
            frame.Selection.TopLeftCorner:ClearAllPoints()
            frame.Selection.TopLeftCorner:SetPoint("TOPLEFT", bar, "TOPLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(15) + yOffsetTop)
            frame.Selection.TopRightCorner:ClearAllPoints()
            frame.Selection.TopRightCorner:SetPoint("TOPRIGHT", bar, "TOPRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(15) + yOffsetTop)
            frame.Selection.BottomLeftCorner:ClearAllPoints()
            frame.Selection.BottomLeftCorner:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(-25) + yOffsetBottom)
            frame.Selection.BottomRightCorner:ClearAllPoints()
            frame.Selection.BottomRightCorner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(-25) + yOffsetBottom)
            
            frame.Selection.MouseOverHighlight:ClearAllPoints()
            frame.Selection.MouseOverHighlight:SetPoint("TOPLEFT", frame.Selection.TopLeftCorner, "TOPLEFT", RefineUI:Scale(8), RefineUI:Scale(-8))
            frame.Selection.MouseOverHighlight:SetPoint("BOTTOMRIGHT", frame.Selection.BottomRightCorner, "BOTTOMRIGHT", RefineUI:Scale(-8), RefineUI:Scale(8))
            
            if frame.Selection.HorizontalLabel then
                frame.Selection.HorizontalLabel:ClearAllPoints()
                frame.Selection.HorizontalLabel:SetPoint("CENTER", frame.Selection.MouseOverHighlight, "CENTER", 0, 0)
            end
        end

        local secureHooked = {
            frame.Selection.TopLeftCorner,
            frame.Selection.TopRightCorner,
            frame.Selection.BottomLeftCorner,
            frame.Selection.BottomRightCorner,
            frame.Selection.MouseOverHighlight
        }
        for _, region in pairs(secureHooked) do
            RefineUI:HookOnce(BuildUnitFrameHookKey(region, "SetPoint"), region, "SetPoint", function(self)
                if self.changing or InCombatLockdown() then return end
                self.changing = true
                self:ClearAllPoints()
                if self == frame.Selection.TopLeftCorner then
                    self:SetPoint("TOPLEFT", bar, "TOPLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(15) + yOffsetTop)
                elseif self == frame.Selection.TopRightCorner then
                    self:SetPoint("TOPRIGHT", bar, "TOPRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(15) + yOffsetTop)
                elseif self == frame.Selection.BottomLeftCorner then
                    self:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(-25) + yOffsetBottom)
                elseif self == frame.Selection.BottomRightCorner then
                    self:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(-25) + yOffsetBottom)
                elseif self == frame.Selection.MouseOverHighlight then
                    self:SetPoint("TOPLEFT", frame.Selection.TopLeftCorner, "TOPLEFT", RefineUI:Scale(8), RefineUI:Scale(-8))
                    self:SetPoint("BOTTOMRIGHT", frame.Selection.BottomRightCorner, "BOTTOMRIGHT", RefineUI:Scale(-8), RefineUI:Scale(8))
                end
                self.changing = false
            end)
        end
    end

    -- 8. Cast Bar Styling
    local castBar
    if frame == PlayerFrame then
        castBar = PlayerCastingBarFrame
    else
        castBar = frame.spellbar
        if not castBar and frame.GetName then
            local frameName = frame:GetName()
            if frameName and frameName ~= "" then
                castBar = _G[frameName .. "SpellBar"]
            end
        end
    end
    if castBar then
        RefineUI.StyleCastBar(castBar, frame)
    end

    -- 9. Class Resources & Resource Hiding
    if frame == PlayerFrame then
        if UF.CreateClassResources then
            UF:CreateClassResources(frame)
        end

        local managed = _G.PlayerFrameBottomManagedFramesContainer
        if managed then
            if not InCombatLockdown() then managed:SetParent(hiddenFrame) end
            managed:SetAlpha(0)
            managed:Hide()
        end
    end

    -- 10. Aura Styling
    if frame == TargetFrame or frame == FocusFrame then
        UF.UpdateUnitAuras(frame)
        RefineUI:HookOnce(BuildUnitFrameHookKey(frame, "UpdateAuras"), frame, "UpdateAuras", UF.UpdateUnitAuras)
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function UnitFrames:OnInitialize()
    -- Create Movers Early (before EditMode module checks for them)
end

function UnitFrames:OnEnable()
    local frames = {}
    if PlayerFrame then frames[#frames + 1] = PlayerFrame end
    if TargetFrame then frames[#frames + 1] = TargetFrame end
    if FocusFrame then frames[#frames + 1] = FocusFrame end
    if PetFrame then frames[#frames + 1] = PetFrame end
    AddBossFrames(frames)
    
    local function ReapplyStyles()
        if InCombatLockdown() then return end
        AddBossFrames(frames)
        for _, f in pairs(frames) do
            if f then
                StyleUnitFrame(f)
            end
        end
        FlushQueuedStaticStyles()
    end
    
    ReapplyStyles()
    
    RefineUI:HookOnce("UnitFrames:PlayerFrame_ToPlayerArt", "PlayerFrame_ToPlayerArt", function() StyleUnitFrame(PlayerFrame) end)
    RefineUI:HookOnce("UnitFrames:PlayerFrame_ToVehicleArt", "PlayerFrame_ToVehicleArt", function() StyleUnitFrame(PlayerFrame) end)
    if PetFrame then
        RefineUI:HookScriptOnce("UnitFrames:PetFrame:OnShow", PetFrame, "OnShow", function(self) StylePetFrame(self) end)
        RefineUI:HookOnce("UnitFrames:PetFrame_Update", "PetFrame_Update", function() StylePetFrame(PetFrame) end)
    end
    
    if TargetFrame and TargetFrame.CheckClassification then
        RefineUI:HookOnce("UnitFrames:TargetFrame:CheckClassification", TargetFrame, "CheckClassification", function() StyleUnitFrame(TargetFrame) end)
    end
    if FocusFrame and FocusFrame.CheckClassification then
        RefineUI:HookOnce("UnitFrames:FocusFrame:CheckClassification", FocusFrame, "CheckClassification", function() StyleUnitFrame(FocusFrame) end)
    end
    for _, bossFrame in ipairs(frames) do
        if bossFrame and bossFrame ~= PlayerFrame and bossFrame ~= TargetFrame and bossFrame ~= FocusFrame and bossFrame.CheckClassification then
            RefineUI:HookOnce(BuildUnitFrameHookKey(bossFrame, "CheckClassification"), bossFrame, "CheckClassification", function(self)
                StyleUnitFrame(self)
            end)
            RefineUI:HookScriptOnce(BuildUnitFrameHookKey(bossFrame, "OnShow"), bossFrame, "OnShow", function(self)
                StyleUnitFrame(self)
            end)
        end
    end

    if EditModeManagerFrame then
        RefineUI:HookOnce("UnitFrames:EditModeManagerFrame:EnterEditMode", EditModeManagerFrame, "EnterEditMode", ReapplyStyles)
        RefineUI:HookOnce("UnitFrames:EditModeManagerFrame:ExitEditMode", EditModeManagerFrame, "ExitEditMode", ReapplyStyles)
    end
    
    local function RefreshFrame(frame)
        if not frame then return end
        ApplyUnitFrameDynamicStyle(frame)
        if InCombatLockdown() then
            QueueStaticStyle(frame)
        else
            StyleUnitFrame(frame)
        end
    end

    -- Dynamic Power Type Handling via Events.lua
    local function OnPowerEvent(event, unit)
        if unit == "player" then RefreshFrame(PlayerFrame)
        elseif unit == "target" then RefreshFrame(TargetFrame)
        elseif unit == "focus" then RefreshFrame(FocusFrame)
        elseif IsBossUnit(unit) then
            RefreshFrame(GetBossFrameForUnit(unit))
        end
    end
    RefineUI:RegisterEventCallback("UNIT_MAXPOWER", OnPowerEvent, "UnitFrames_UpdatePowerType_Max")
    RefineUI:RegisterEventCallback("UNIT_DISPLAYPOWER", OnPowerEvent, "UnitFrames_UpdatePowerType_Display")
    RefineUI:OnEvents({"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION"}, function(_, unit)
        if unit == "pet" then
            ApplyPetFrameDynamicStyle(PetFrame)
        end
    end, "UnitFrames:PetFrame:Health")
    RefineUI:RegisterEventCallback("UNIT_PET", function(_, ownerUnit)
        if ownerUnit == "player" then
            RefreshFrame(PetFrame)
        end
    end, "UnitFrames:PetFrame:UNIT_PET")
    RefineUI:RegisterEventCallback("PET_UI_UPDATE", function()
        RefreshFrame(PetFrame)
    end, "UnitFrames:PetFrame:PET_UI_UPDATE")
    RefineUI:RegisterEventCallback("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
        AddBossFrames(frames)
        for _, frame in pairs(frames) do
            if frame and frame.unit and IsBossUnit(frame.unit) then
                RefreshFrame(frame)
            end
        end
    end, "UnitFrames_BossFrame_Engage")
    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        FlushQueuedStaticStyles()
    end, "UnitFrames:FlushQueuedStaticStyles")
    
    -- Initialize Party Frames
    if UF.InitPartyHooks then
        UF.InitPartyHooks()
    end
end
