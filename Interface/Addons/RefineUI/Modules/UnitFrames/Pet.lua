----------------------------------------------------------------------------------------
-- UnitFrames Component: Pet
-- Description: Pet-only styling, secondary mana overlay, and edit mode helpers.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHealthPercent = UnitHealthPercent
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue
local abs = math.abs
local ipairs = ipairs
local type = type
local unpack = unpack

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = UnitFrames:GetPrivate()
local C = Private.Constants

----------------------------------------------------------------------------------------
-- Secondary Mana Overlay
----------------------------------------------------------------------------------------
local function IsPlayerSecondaryPowerSwapActive(frame)
    if frame ~= PlayerFrame then
        return false
    end

    if frame.unit ~= "player" or frame.state == "vehicle" then
        return false
    end

    return UnitFrames.IsPlayerSecondaryPowerSwapActive and UnitFrames.IsPlayerSecondaryPowerSwapActive() or false
end

function UnitFrames:UpdatePlayerSecondaryManaOverlay(frame)
    if frame ~= PlayerFrame then
        return
    end

    local data = self:GetFrameData(frame)
    local overlayData = data and data.PlayerManaOverlay
    local overlay = overlayData and overlayData.Bar
    local sourceBar = overlayData and overlayData.SourceBar
    if not overlay or not sourceBar then
        return
    end

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

    local currentMana = UnitPower("player", C.POWER_TYPE_MANA)
    local maxMana = UnitPowerMax("player", C.POWER_TYPE_MANA)
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
        if safeMin < 0 then
            safeMin = 0
        end
        if safeMin > safeMax then
            safeMin = safeMax
        end

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

function UnitFrames:EnsurePlayerSecondaryManaOverlay(frame, manaBar)
    if frame ~= PlayerFrame or not manaBar then
        return
    end

    local data = self:GetFrameData(frame)
    if not data then
        return
    end

    if not data.PlayerManaOverlay then
        local overlay = CreateFrame("StatusBar", nil, manaBar)
        overlay:SetStatusBarTexture(C.TEXTURE_SECONDARY_MANA_OVERLAY)
        overlay:SetStatusBarDesaturated(true)
        overlay:Hide()

        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(overlay)
        bg:SetColorTexture(0.03, 0.03, 0.03, 1)

        data.PlayerManaOverlay = {
            Bar = overlay,
            Background = bg,
            SourceBar = manaBar,
            LastSafeMin = 0,
            LastSafeMax = 1,
        }
    else
        data.PlayerManaOverlay.SourceBar = manaBar
    end

    local overlayData = data.PlayerManaOverlay
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

            UnitFrames:UpdatePlayerSecondaryManaOverlay(frame)
        end)
        overlayData.eventsRegistered = true
    end

    self:UpdatePlayerSecondaryManaOverlay(frame)
end

----------------------------------------------------------------------------------------
-- Pet Helpers
----------------------------------------------------------------------------------------
local function GetPetPercentValue()
    if UnitHealthPercent and RefineUI.GetPercentCurve then
        return UnitHealthPercent("pet", true, RefineUI.GetPercentCurve())
    end
    return 0
end

function UnitFrames:UpdatePetFrameHealthText(frame)
    if not frame then
        return
    end

    local data = self:GetFrameData(frame)
    local petData = data and data.RefinePet
    local percentText = petData and petData.PercentText
    if not percentText then
        return
    end

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

local function ApplyPetFrameHitRect(frame)
    if not frame or not frame.SetHitRectInsets then
        return
    end

    local leftInset = C.PET_FRAME_WIDTH + C.PET_HEALTH_X - C.PET_HEALTH_WIDTH
    local rightInset = -C.PET_HEALTH_X
    local topInset = -C.PET_HEALTH_Y
    local bottomInset = C.PET_FRAME_HEIGHT - topInset - C.PET_HEALTH_HEIGHT

    if leftInset < 0 then
        leftInset = 0
    end
    if rightInset < 0 then
        rightInset = 0
    end
    if topInset < 0 then
        topInset = 0
    end
    if bottomInset < 0 then
        bottomInset = 0
    end

    frame:SetHitRectInsets(leftInset, rightInset, topInset, bottomInset)
end

local function GetPetEditModeSystemFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.registeredSystemFrames then
        return nil
    end

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
    if not frame or not frame.Selection then
        return
    end

    local selection = frame.Selection
    local anchor = PetFrameHealthBar or frame

    local function AnchorSelection(sel)
        if not sel or not sel.ClearAllPoints or not sel.SetPoint then
            return
        end
        if InCombatLockdown() then
            return
        end

        UnitFrames:WithStateGuard(sel, "PetSelectionAnchor", function()
            sel:ClearAllPoints()
            if anchor == PetFrameHealthBar then
                sel:SetPoint("TOPLEFT", anchor, "TOPLEFT", RefineUI:Scale(-2), RefineUI:Scale(2))
                sel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", RefineUI:Scale(2), RefineUI:Scale(-2))
            else
                sel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                sel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            end
        end)
    end

    AnchorSelection(selection)

    RefineUI:HookOnce(UnitFrames:BuildHookKey(selection, "SetPoint:PetSelection"), selection, "SetPoint", function(selfSelection)
        if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
            AnchorSelection(selfSelection)
        end
    end)
    RefineUI:HookOnce(UnitFrames:BuildHookKey(selection, "SetAllPoints:PetSelection"), selection, "SetAllPoints", function(selfSelection)
        if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
            AnchorSelection(selfSelection)
        end
    end)
end

local function HidePetAuras(frame)
    if not frame then
        return
    end

    if frame.AuraFrameContainer then
        UnitFrames:EnforceHiddenRegion(frame.AuraFrameContainer, RefineUI.HiddenFrame)
    end

    if frame.AuraFramePool and frame.AuraFramePool.ReleaseAll then
        frame.AuraFramePool:ReleaseAll()
    end

    if PartyMemberBuffTooltip and PartyMemberBuffTooltip.Hide then
        PartyMemberBuffTooltip:Hide()
    end
end

local function SyncPetEditModeMoverSize()
    if InCombatLockdown() then
        return
    end
    if not EditModeManagerFrame or not EditModeManagerFrame.IsEditModeActive or not EditModeManagerFrame:IsEditModeActive() then
        return
    end

    local mover = GetPetEditModeSystemFrame()
    if not mover or not mover.SetSize then
        return
    end

    local targetWidth = RefineUI:Scale(C.PET_FRAME_WIDTH)
    local targetHeight = RefineUI:Scale(C.PET_FRAME_HEIGHT)

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

----------------------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------------------
function UnitFrames:ApplyPetFrameDynamicStyle(frame)
    if not frame or not PetFrameHealthBar then
        return
    end

    PetFrameHealthBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
    PetFrameHealthBar:SetStatusBarDesaturated(true)

    local hr, hg, hb = self.GetUnitHealthColor("pet")
    PetFrameHealthBar:SetStatusBarColor(hr, hg, hb)

    self:UpdatePetFrameHealthText(frame)
end

function UnitFrames:StylePetFrame(frame)
    if not frame then
        return
    end

    if InCombatLockdown() then
        self:QueueStaticStyle(frame)
        self:ApplyPetFrameDynamicStyle(frame)
        return
    end

    Private.PendingStaticStyleFrames[frame] = nil
    local data = self:GetFrameData(frame)
    local hiddenFrame = RefineUI.HiddenFrame

    RefineUI:SetPixelSize(frame, C.PET_FRAME_WIDTH, C.PET_FRAME_HEIGHT)

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
    border:SetTexture(C.TEXTURE_FRAME_PET)
    border:ClearAllPoints()
    if PetFrameHealthBar then
        border:SetPoint("CENTER", PetFrameHealthBar, "CENTER", 0, -14)
    else
        border:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    RefineUI:SetPixelSize(border, C.PET_BORDER_WIDTH, C.PET_BORDER_HEIGHT)
    border:SetAlpha(1)
    border:Show()

    if Config.General.BorderColor then
        border:SetVertexColor(unpack(Config.General.BorderColor))
    end

    if PetFrameHealthBar then
        PetFrameHealthBar:ClearAllPoints()
        PetFrameHealthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", RefineUI:Scale(C.PET_HEALTH_X), RefineUI:Scale(C.PET_HEALTH_Y))
        RefineUI:SetPixelSize(PetFrameHealthBar, C.PET_HEALTH_WIDTH, C.PET_HEALTH_HEIGHT)
        PetFrameHealthBar:SetAlpha(1)
        PetFrameHealthBar:Show()
    end

    ApplyPetFrameHitRect(frame)
    ApplyPetSelectionBounds(frame)
    SyncPetEditModeMoverSize()

    RefineUI.Font(petData.PercentText, Config.UnitFrames.Fonts.HPSize)
    petData.PercentText:ClearAllPoints()
    if PetFrameHealthBar then
        petData.PercentText:SetPoint("CENTER", PetFrameHealthBar, "CENTER", 0, 0)
    else
        petData.PercentText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    petData.PercentText:SetJustifyH("CENTER")
    petData.PercentText:SetJustifyV("MIDDLE")

    for _, region in ipairs({
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
        self:EnforceHiddenRegion(region, hiddenFrame)
    end

    HidePetAuras(frame)

    if PetFrameHealthBar then
        RefineUI:HookOnce(self:BuildHookKey(PetFrameHealthBar, "SetStatusBarColor:Pet"), PetFrameHealthBar, "SetStatusBarColor", function(selfBar, r1, g1, b1)
            local r2, g2, b2 = UnitFrames.GetUnitHealthColor("pet")
            if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then
                selfBar:SetStatusBarColor(r2, g2, b2)
            end
        end)
        RefineUI:HookOnce(self:BuildHookKey(PetFrameHealthBar, "SetStatusBarTexture:Pet"), PetFrameHealthBar, "SetStatusBarTexture", function(selfBar, texture)
            if texture ~= C.TEXTURE_HEALTH_BAR then
                selfBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
                selfBar:SetStatusBarDesaturated(true)
            end
        end)
        RefineUI:HookScriptOnce(self:BuildHookKey(PetFrameHealthBar, "OnValueChanged:Pet"), PetFrameHealthBar, "OnValueChanged", function()
            UnitFrames:UpdatePetFrameHealthText(frame)
        end)
    end

    RefineUI:HookOnce(self:BuildHookKey(frame, "UpdateAuras:HidePet"), frame, "UpdateAuras", function(selfFrame)
        HidePetAuras(selfFrame)
    end)
    RefineUI:HookScriptOnce(self:BuildHookKey(frame, "OnEnter:HidePetTooltip"), frame, "OnEnter", function()
        if PartyMemberBuffTooltip and PartyMemberBuffTooltip.Hide then
            PartyMemberBuffTooltip:Hide()
        end
    end)

    self:ApplyPetFrameDynamicStyle(frame)
end
