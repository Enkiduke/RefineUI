----------------------------------------------------------------------------------------
-- Nameplates Component: Style
-- Description: Base nameplate styling and aura icon skinning.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local select = select
local pcall = pcall

local CreateFrame = CreateFrame
local UnitIsPlayer = UnitIsPlayer
local UnitAffectingCombat = UnitAffectingCombat

----------------------------------------------------------------------------------------
-- Aura Skinning
----------------------------------------------------------------------------------------
function Nameplates:SkinNamePlateAura(frame)
    if not frame then
        return
    end

    local function ApplyAuraCooldownSwipe()
        local cooldown = frame.Cooldown or frame.cooldown or frame.CooldownFrame
        if not cooldown then
            return
        end

        local desiredStrata
        if frame.GetFrameStrata then
            local ok, strata = pcall(frame.GetFrameStrata, frame)
            if ok and type(strata) == "string" then
                desiredStrata = strata
            end
        end

        local desiredLevel = 2
        if frame.GetFrameLevel then
            local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
            if ok and type(frameLevel) == "number" then
                desiredLevel = frameLevel + 2
            end
        end

        local border = frame.border or frame.RefineBorder
        if border then
            if border.GetFrameStrata then
                local ok, borderStrata = pcall(border.GetFrameStrata, border)
                if ok and type(borderStrata) == "string" then
                    desiredStrata = borderStrata
                end
            end
            if border.GetFrameLevel then
                local ok, borderLevel = pcall(border.GetFrameLevel, border)
                if ok and type(borderLevel) == "number" then
                    desiredLevel = math.max(desiredLevel, borderLevel + 2)
                end
            end
        end

        if desiredStrata and cooldown.SetFrameStrata then
            pcall(cooldown.SetFrameStrata, cooldown, desiredStrata)
        end
        if cooldown.SetFrameLevel then
            pcall(cooldown.SetFrameLevel, cooldown, desiredLevel)
        end

        if cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(false)
        end
        if cooldown.SetDrawBling then
            cooldown:SetDrawBling(false)
        end
        if cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(true)
        end
        if cooldown.SetSwipeTexture then
            cooldown:SetSwipeTexture(Media.Textures.CooldownSwipeSmall)
        end
        if cooldown.SetSwipeColor then
            cooldown:SetSwipeColor(0, 0, 0, 0.8)
        end

        RefineUI.SetInside(cooldown, frame, -2, -2)
    end

    if self:GetNameplateState(frame, "AuraSkinned", false) then
        ApplyAuraCooldownSwipe()
        return
    end

    if frame.Icon then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region:IsObjectType("MaskTexture") then
                region:SetAlpha(0)
            elseif region:IsObjectType("Texture") and region ~= frame.Icon then
                region:SetAlpha(0)
            end
        end

        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        RefineUI.SetInside(frame.Icon, frame, 1, 1)
    end

    RefineUI.CreateBorder(frame, 6, 6, 12)

    if frame.CountFrame and frame.CountFrame.Count then
        RefineUI.Font(frame.CountFrame.Count, 10, nil, "OUTLINE")
        frame.CountFrame.Count:ClearAllPoints()
        RefineUI.Point(frame.CountFrame.Count, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -1)
    end

    ApplyAuraCooldownSwipe()

    local container = frame:GetParent()
    if container then
        self:SetNameplateState(container, "AuraContainerSkinned", true)
    end

    self:SetNameplateState(frame, "AuraSkinned", true)
end

----------------------------------------------------------------------------------------
-- Nameplate Style Pipeline
----------------------------------------------------------------------------------------
function Nameplates:StyleNameplate(nameplate, unit)
    if not nameplate or nameplate:IsForbidden() then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local private = self:GetPrivate()
    local util = private and private.Util
    if not util then
        return
    end

    unit = util.ResolveUnitToken(unit, unitFrame.unit)
    if not unit then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not health then
        return
    end

    self:ApplyConfiguredNameplateSize(unitFrame, nameplate)

    if not data.SizeReapplyHooked and type(unitFrame.ApplyFrameOptions) == "function" then
        local hookKey = self:BuildHookKey(unitFrame, "ApplyFrameOptions:ConfiguredSize")
        local ok = RefineUI:HookOnce(hookKey, unitFrame, "ApplyFrameOptions", function(frameObj)
            local parent = frameObj.GetParent and frameObj:GetParent() or nil
            if parent and parent.UnitFrame == frameObj then
                Nameplates:ApplyConfiguredNameplateSize(frameObj, parent)
            else
                Nameplates:ApplyConfiguredNameplateSize(frameObj)
            end
        end)
        data.SizeReapplyHooked = ok == true
    end

    data.isPlayer = util.ReadSafeBoolean(UnitIsPlayer(unit)) == true
    data.inCombat = util.ReadSafeBoolean(UnitAffectingCombat(unit)) == true

    if unitFrame.ClassificationFrame then
        unitFrame.ClassificationFrame:SetAlpha(0)
    end

    if not data.EventFrame then
        data.EventFrame = CreateFrame("Frame", nil, unitFrame)
        data.EventFrame:SetScript("OnEvent", function(_, event, eventUnit)
            local parentUnit = unitFrame.unit
            local isSame = util.SafeUnitIsUnit(parentUnit, eventUnit)
            if not isSame then
                return
            end

            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                Nameplates:UpdateHealth(nameplate, parentUnit)
            elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
                if Nameplates.QueuePortraitRefresh then
                    Nameplates:QueuePortraitRefresh(unitFrame, parentUnit, event)
                elseif RefineUI.UpdateDynamicPortrait then
                    RefineUI:UpdateDynamicPortrait(nameplate, parentUnit, event)
                end
            end
        end)
    end

    if not data.RefineBorder then
        local borderOverlay = CreateFrame("Frame", nil, health)
        RefineUI.SetInside(borderOverlay, health, 0, 0)
        RefineUI.CreateBorder(borderOverlay, 6, 6, 12)
        data.RefineBorder = borderOverlay.border
        data.HealthBorderOverlay = borderOverlay
    end

    local barTexture = private and private.Textures and private.Textures.HEALTH_BAR
    if barTexture then
        health:SetStatusBarTexture(barTexture)
        health:SetStatusBarDesaturated(true)

        if not data.HealthBackground then
            data.HealthBackground = health:CreateTexture(nil, "BACKGROUND")
            RefineUI.SetInside(data.HealthBackground, health, 0, 0)
            data.HealthBackground:SetTexture(barTexture)
            data.HealthBackground:SetVertexColor(0.25, 0.25, 0.25, 1)
        end

        RefineUI:HookOnce(self:BuildHookKey(health, "SetStatusBarTexture"), health, "SetStatusBarTexture", function(statusBar, tex)
            if data.SettingTexture then
                return
            end
            if (not util.IsAccessibleValue(tex)) or tex ~= barTexture then
                data.SettingTexture = true
                statusBar:SetStatusBarTexture(barTexture)
                statusBar:SetStatusBarDesaturated(true)
                data.SettingTexture = false
            end
        end)
    end

    if unitFrame.castBar then
        RefineUI:StyleNameplateCastBar(unitFrame.castBar)
    elseif unitFrame.CastBar then
        RefineUI:StyleNameplateCastBar(unitFrame.CastBar)
    end

    if data.EventFrame and util.IsUsableUnitToken(unit) and data.EventFrameUnit ~= unit then
        data.EventFrame:UnregisterAllEvents()
        data.EventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", unit)
        data.EventFrame:RegisterUnitEvent("UNIT_MODEL_CHANGED", unit)
        data.EventFrame:RegisterUnitEvent("UNIT_HEALTH", unit)
        data.EventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
        data.EventFrameUnit = unit
    elseif data.EventFrame and data.EventFrameUnit and not util.IsUsableUnitToken(unit) then
        data.EventFrame:UnregisterAllEvents()
        data.EventFrameUnit = nil
    end

    RefineUI:CreateTargetArrows(unitFrame)

    self:UpdateName(nameplate, unit)
    self:UpdateHealth(nameplate, unit)
end
