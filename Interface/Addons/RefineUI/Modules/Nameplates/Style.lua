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
local max = math.max
local setmetatable = setmetatable

local CreateFrame = CreateFrame
local UnitIsPlayer = UnitIsPlayer
local UnitAffectingCombat = UnitAffectingCombat

local Private = Nameplates:GetPrivate()
local Util = Private.Util
local HEALTH_BAR_TEXTURE = Private.Textures.HEALTH_BAR

-- Visual inset last applied to each pooled aura item; nil means not skinned yet.
local auraSkinInset = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------------------------
-- Aura Skinning
----------------------------------------------------------------------------------------
-- Aura items are pooled and reparented on every Blizzard refresh, so strata/level and
-- the settings CooldownFrame_Set/SetAura reset are reapplied each time; anchors,
-- fonts, and swipe art only change with the visual inset.
local function ApplyAuraCooldownSwipe(frame, cooldownInset, restyle)
    local cooldown = frame.Cooldown or frame.cooldown or frame.CooldownFrame
    if not cooldown then
        return
    end

    local border = frame.border
    if border then
        cooldown:SetFrameStrata(border:GetFrameStrata())
        cooldown:SetFrameLevel(max(frame:GetFrameLevel(), border:GetFrameLevel()) + 2)
    else
        cooldown:SetFrameStrata(frame:GetFrameStrata())
        cooldown:SetFrameLevel(frame:GetFrameLevel() + 2)
    end

    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)

    if not restyle then
        return
    end

    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeTexture(Media.Textures.CooldownSwipeSmall)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)

    RefineUI.SetInside(cooldown, frame, cooldownInset, cooldownInset)
end

function Nameplates:SkinNamePlateAura(frame, visualInset)
    local resolvedVisualInset = max(0, visualInset)
    local iconInset = 1 + resolvedVisualInset
    local cooldownInset = resolvedVisualInset - 1
    local borderInset = 6 - resolvedVisualInset

    local appliedInset = auraSkinInset[frame]
    local isSkinned = appliedInset ~= nil
    local restyle = appliedInset ~= resolvedVisualInset

    if not isSkinned and frame.Icon then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region:IsObjectType("MaskTexture") then
                region:SetAlpha(0)
            elseif region:IsObjectType("Texture") and region ~= frame.Icon then
                region:SetAlpha(0)
            end
        end

        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end

    if restyle and frame.Icon then
        RefineUI.SetInside(frame.Icon, frame, iconInset, iconInset)
    end

    RefineUI.CreateBorder(frame, borderInset, borderInset, 14)

    if restyle and frame.CountFrame and frame.CountFrame.Count then
        RefineUI.Font(frame.CountFrame.Count, 10, nil, "OUTLINE")
        frame.CountFrame.Count:ClearAllPoints()
        RefineUI.Point(frame.CountFrame.Count, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -1)
    end

    ApplyAuraCooldownSwipe(frame, cooldownInset, restyle)

    auraSkinInset[frame] = resolvedVisualInset
end

function Nameplates:UpdateNameplatePortraitModelEvents(unitFrame, unit, enabled)
    local data = RefineUI.NameplateData[unitFrame]
    local eventFrame = data and data.EventFrame
    if not eventFrame then
        return
    end

    if enabled ~= true or not Util.IsUsableUnitToken(unit) then
        if data.EventFrameUnit ~= nil then
            eventFrame:UnregisterAllEvents()
            data.EventFrameUnit = nil
        end
        return
    end

    if data.EventFrameUnit ~= unit then
        eventFrame:UnregisterAllEvents()
        eventFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", unit)
        eventFrame:RegisterUnitEvent("UNIT_MODEL_CHANGED", unit)
        data.EventFrameUnit = unit
    end
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

    unit = Util.ResolveUnitToken(unit, unitFrame.unit)
    if not unit then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    local isPredictedNameOnly = self:IsNameOnlyNameplateInternal(unitFrame, data, false)
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not health then
        return
    end

    self:ApplyConfiguredNameplateSize(unitFrame)

    -- Blizzard re-applies frame options on every SetUnit; this per-frame hook is the
    -- single place that restores the configured size afterwards.
    if not data.SizeReapplyHooked then
        local hookKey = self:BuildHookKey(unitFrame, "ApplyFrameOptions:ConfiguredSize")
        data.SizeReapplyHooked = RefineUI:HookOnce(hookKey, unitFrame, "ApplyFrameOptions", function(frameObj)
            Nameplates:ApplyConfiguredNameplateSize(frameObj)
        end) == true
    end

    data.isPlayer = Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true
    data.inCombat = Util.ReadSafeBoolean(UnitAffectingCombat(unit)) == true

    if unitFrame.ClassificationFrame then
        unitFrame.ClassificationFrame:SetAlpha(0)
    end

    -- Blizzard's nameplateInfoDisplay health text duplicates RefineHealth. TextStatusBarMixin
    -- only shows/hides these regions, so a one-time alpha hide persists.
    if health.Text then health.Text:SetAlpha(0) end
    if health.LeftText then health.LeftText:SetAlpha(0) end
    if health.RightText then health.RightText:SetAlpha(0) end

    if not data.EventFrame then
        data.EventFrame = CreateFrame("Frame", nil, unitFrame)
        -- Only UNIT_PORTRAIT_UPDATE/UNIT_MODEL_CHANGED are registered, as unit events.
        data.EventFrame:SetScript("OnEvent", function(_, event)
            Nameplates:QueuePortraitRefresh(unitFrame, unitFrame.unit, event)
        end)
    end

    if not data.RefineBorder then
        local borderOverlay = CreateFrame("Frame", nil, health)
        RefineUI.SetInside(borderOverlay, health, 0, 0)
        RefineUI.CreateBorder(borderOverlay, 6, 6, 12)
        data.RefineBorder = borderOverlay.border
        data.HealthBorderOverlay = borderOverlay
    end

    health:SetStatusBarTexture(HEALTH_BAR_TEXTURE)
    health:SetStatusBarDesaturated(true)
    data.HealthTextureApplied = true

    if not data.HealthBackground then
        data.HealthBackground = health:CreateTexture(nil, "BACKGROUND")
        RefineUI.SetInside(data.HealthBackground, health, 0, 0)
        data.HealthBackground:SetTexture(HEALTH_BAR_TEXTURE)
        data.HealthBackground:SetVertexColor(0.25, 0.25, 0.25, 1)
    end

    if not data.HealthTextureHooked then
        data.HealthTextureHooked = true
        RefineUI:HookOnce(self:BuildHookKey(health, "SetStatusBarTexture"), health, "SetStatusBarTexture", function(statusBar, tex)
            if data.SettingTexture then
                return
            end
            if (not Util.IsAccessibleValue(tex)) or tex ~= HEALTH_BAR_TEXTURE then
                data.SettingTexture = true
                statusBar:SetStatusBarTexture(HEALTH_BAR_TEXTURE)
                statusBar:SetStatusBarDesaturated(true)
                data.SettingTexture = false
            end
        end)
    end

    local castBar = Util.GetNameplateCastBar(unitFrame)
    if castBar then
        RefineUI:StyleNameplateCastBar(castBar)
    end

    self:UpdateNameplatePortraitModelEvents(unitFrame, unit, not isPredictedNameOnly)

    RefineUI:CreateTargetArrows(unitFrame)

    self:UpdateName(nameplate, unit)
    if not isPredictedNameOnly then
        self:UpdateHealth(nameplate, unit)
    end
end
