----------------------------------------------------------------------------------------
-- UnitFrames Party: Aura Borders
-- Description: Aura border creation, cooldown swipe, debuff/buff/dispel color
--              resolution, and top-level aura styling orchestration.
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
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local strlower = string.lower
local strfind = string.find
local floor = math.floor
local tinsert = table.insert
local wipe = wipe

local GetPartyData        = P.GetData
local GetPartyAuraData    = P.GetAuraData
local BuildPartyHookKey   = P.BuildHookKey
local IsUnreadableNumber  = P.IsUnreadableNumber
local IsSecretValue       = P.IsSecretValue
local GetSafeFrameLevel   = P.GetSafeFrameLevel
local GetSafeFrameStrata  = P.GetSafeFrameStrata
local TrySetFrameLevel    = P.TrySetFrameLevel
local TrySetFrameStrata   = P.TrySetFrameStrata
local GetSafeDispelTypeKey = P.GetSafeDispelTypeKey
local IsPartyRaidCompactFrame = P.IsCompactFrame
local GetAuraScratch      = P.GetAuraScratch

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPACT_AURA_BORDER_INSET_X     = 5
local COMPACT_AURA_BORDER_INSET_Y     = 5
local DEFAULT_COMPACT_AURA_COOLDOWN_X = 2
local DEFAULT_COMPACT_AURA_COOLDOWN_Y = 2

local CompactDispelColorProbeTexture
local bestFrameColorScratch = {}

local function WipeTable(tbl)
    if wipe then
        wipe(tbl)
        return tbl
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function ResetBestFrameColorState()
    local state = WipeTable(bestFrameColorScratch)
    state.priority = -1
    return state
end

----------------------------------------------------------------------------------------
-- Cooldown Swipe Helpers
----------------------------------------------------------------------------------------
local function GetRefineCooldownSwipeTexture()
    local textures = RefineUI and RefineUI.Media and RefineUI.Media.Textures
    if type(textures) ~= "table" then return nil end
    if type(textures.CooldownSwipeSmall) == "string" and textures.CooldownSwipeSmall ~= "" then
        return textures.CooldownSwipeSmall
    end
    if type(textures.CooldownSwipe) == "string" and textures.CooldownSwipe ~= "" then
        return textures.CooldownSwipe
    end
    return nil
end

local function GetCompactAuraCooldownSwipeOffsets()
    local x = DEFAULT_COMPACT_AURA_COOLDOWN_X
    local y = DEFAULT_COMPACT_AURA_COOLDOWN_Y
    return -x, y, x, -y
end

local function ApplyCompactAuraCooldownSwipe(auraFrame)
    if not auraFrame then return end

    local cooldown = auraFrame.cooldown or auraFrame.Cooldown
    if not cooldown then return end

    local data = GetPartyAuraData(auraFrame)
    local desiredStrata = GetSafeFrameStrata(auraFrame, "LOW")
    local desiredLevel = GetSafeFrameLevel(auraFrame, 0) + 20
    if data.borderHost and data.borderHost.GetFrameLevel then
        local borderLevel = GetSafeFrameLevel(data.borderHost, 0)
        if (borderLevel + 2) > desiredLevel then
            desiredLevel = borderLevel + 2
        end
    end

    local layerToken = tostring(desiredStrata) .. ":" .. tostring(desiredLevel)
    if data.cooldownLayerToken ~= layerToken then
        if cooldown.GetFrameStrata and cooldown.SetFrameStrata then
            local currentStrata = GetSafeFrameStrata(cooldown, "")
            if currentStrata ~= desiredStrata then
                TrySetFrameStrata(cooldown, desiredStrata)
            end
        end
        if cooldown.SetFrameLevel and cooldown.GetFrameLevel then
            local currentLevel = GetSafeFrameLevel(cooldown, -1)
            if currentLevel < desiredLevel then
                TrySetFrameLevel(cooldown, desiredLevel)
            end
        end
        data.cooldownLayerToken = layerToken
    end

    local swipeTexture = GetRefineCooldownSwipeTexture()
    local swipeToken = tostring(swipeTexture) .. ":compact"

    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(false)
    end
    if cooldown.SetDrawBling then
        cooldown:SetDrawBling(false)
    end
    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(true)
    end
    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, .7)
    end
    local topLeftX, topLeftY, bottomRightX, bottomRightY = GetCompactAuraCooldownSwipeOffsets()
    if (data.cooldownAnchorTopLeftX ~= topLeftX
        or data.cooldownAnchorTopLeftY ~= topLeftY
        or data.cooldownAnchorBottomRightX ~= bottomRightX
        or data.cooldownAnchorBottomRightY ~= bottomRightY)
        and cooldown.ClearAllPoints and cooldown.SetPoint then
        cooldown:ClearAllPoints()
        cooldown:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", topLeftX, topLeftY)
        cooldown:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", bottomRightX, bottomRightY)
        data.cooldownAnchorTopLeftX = topLeftX
        data.cooldownAnchorTopLeftY = topLeftY
        data.cooldownAnchorBottomRightX = bottomRightX
        data.cooldownAnchorBottomRightY = bottomRightY
    end

    if data.cooldownSwipeToken ~= swipeToken and swipeTexture and cooldown.SetSwipeTexture then
        cooldown:SetSwipeTexture(swipeTexture)
    end

    data.cooldownSwipeToken = swipeToken
end

----------------------------------------------------------------------------------------
-- Border Creation
----------------------------------------------------------------------------------------
local function EnsureCompactAuraBorder(auraFrame)
    if not auraFrame or auraFrame:IsForbidden() then return nil end

    local data = GetPartyAuraData(auraFrame)
    local borderHost = data.borderHost

    if not borderHost then
        local ok, createdHost = pcall(CreateFrame, "Frame", nil, auraFrame)
        if not ok or not createdHost then
            data.pendingCreate = true
            return nil
        end
        borderHost = createdHost
        data.borderHost = borderHost
        if borderHost.EnableMouse then
            pcall(borderHost.EnableMouse, borderHost, false)
        end
    end

    if data.borderHostAnchorOwner ~= auraFrame and borderHost.ClearAllPoints and borderHost.SetPoint then
        pcall(borderHost.ClearAllPoints, borderHost)
        pcall(borderHost.SetPoint, borderHost, "TOPLEFT", auraFrame, "TOPLEFT", 0, 0)
        pcall(borderHost.SetPoint, borderHost, "BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 0, 0)
        data.borderHostAnchorOwner = auraFrame
    end
    TrySetFrameStrata(borderHost, GetSafeFrameStrata(auraFrame, "LOW"))
    TrySetFrameLevel(borderHost, GetSafeFrameLevel(auraFrame, 0) + 5)

    if not data.border then
        local ok, createdBorder = pcall(RefineUI.CreateBorder, borderHost, COMPACT_AURA_BORDER_INSET_X, COMPACT_AURA_BORDER_INSET_Y, 8)
        if not ok or not createdBorder then
            data.pendingCreate = true
            return nil
        end
        data.border = createdBorder
    end

    local border = data.border
    if not border then
        data.pendingCreate = true
        return nil
    end

    if borderHost and borderHost.GetFrameLevel then
        local hostLevel = GetSafeFrameLevel(auraFrame, 0) + 5
        if GetSafeFrameLevel(borderHost, hostLevel) ~= hostLevel then
            TrySetFrameLevel(borderHost, hostLevel)
        end
    end

    local blizzardBorder = auraFrame.border or auraFrame.DebuffBorder
    if blizzardBorder then
        if blizzardBorder.SetAlpha then
            pcall(blizzardBorder.SetAlpha, blizzardBorder, 0)
        end
        if not data.blizzardBorderHooksInstalled then
            if blizzardBorder.SetAlpha then
                RefineUI:HookOnce(BuildPartyHookKey(blizzardBorder, "SetAlpha:Hide"), blizzardBorder, "SetAlpha", function(self, alpha)
                    if not IsUnreadableNumber(alpha) and alpha ~= 0 then
                        self:SetAlpha(0)
                    end
                end)
            end
            if blizzardBorder.Show then
                RefineUI:HookOnce(BuildPartyHookKey(blizzardBorder, "Show:Hide"), blizzardBorder, "Show", function(self)
                    self:SetAlpha(0)
                    self:Hide()
                end)
            end
            data.blizzardBorderHooksInstalled = true
        end
    end

    data.pendingCreate = nil
    return border
end

local function ApplyCompactAuraBorderColor(auraFrame, r, g, b, a)
    local border = EnsureCompactAuraBorder(auraFrame)
    if not border then return false end
    local data = GetPartyAuraData(auraFrame)
    if data.borderHost and data.borderHost.Show then
        data.borderHost:Show()
    end
    if border.Show then
        border:Show()
    end

    local colorR = r or 1
    local colorG = g or 1
    local colorB = b or 1
    local colorA = a or 1
    border:SetBackdropBorderColor(colorR, colorG, colorB, colorA)
    return true
end

local function HideCompactAuraBorder(auraFrame)
    if not auraFrame then return end
    local data = GetPartyAuraData(auraFrame)
    if data.border and data.border.Hide then
        data.border:Hide()
    end
    if data.borderHost and data.borderHost.Hide then
        data.borderHost:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Buff Aura Data Tracking
----------------------------------------------------------------------------------------
local function TrackCompactBuffAuraData(auraFrame, aura)
    if not auraFrame then
        return
    end

    local data = GetPartyAuraData(auraFrame)
    if type(aura) ~= "table" then
        data.auraSpellID = nil
        data.auraDuration = nil
        data.auraExpirationTime = nil
        data.auraInstanceID = nil
        data.classBuffEntryKey = nil
        return
    end

    local spellID = aura.spellId or aura.spellID
    if type(spellID) ~= "number" then
        spellID = nil
    end

    data.auraSpellID = spellID
    data.auraDuration = aura.duration
    data.auraExpirationTime = aura.expirationTime
    data.auraInstanceID = aura.auraInstanceID

    local entry = spellID and P.GetTrackedClassBuffEntryBySpellID(spellID)
    data.classBuffEntryKey = entry and entry.key or nil
end

local function GetTrackedClassBuffEntryForAuraFrame(auraFrame)
    local data = auraFrame and GetPartyAuraData(auraFrame)
    local entryKey = data and data.classBuffEntryKey
    if type(entryKey) ~= "string" then
        return nil
    end

    local entries = P.GetPlayerClassBuffEntries()
    for i = 1, #entries do
        local entry = entries[i]
        if entry and entry.key == entryKey then
            return entry
        end
    end

    return nil
end

----------------------------------------------------------------------------------------
-- Buff/Debuff Border Color
----------------------------------------------------------------------------------------
local function ApplyCompactBuffBorderColor(auraFrame)
    ApplyCompactAuraCooldownSwipe(auraFrame)

    local entry = GetTrackedClassBuffEntryForAuraFrame(auraFrame)
    if entry then
        local r, g, b, a = P.GetTrackedClassBuffColor(entry.key)
        return ApplyCompactAuraBorderColor(auraFrame, r, g, b, a)
    end

    local r, g, b = P.GetConfiguredBuffBorderColorRGB()
    return ApplyCompactAuraBorderColor(auraFrame, r, g, b, 1)
end

local function GetDebuffColorFromTable(color)
    if type(color) == "table"
        and type(color.r) == "number"
        and type(color.g) == "number"
        and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return nil
end

local function GetDirectDebuffTypeColorRGB(dispelType)
    local debuffTypeColor = _G.DebuffTypeColor
    local safeDispelType = GetSafeDispelTypeKey(dispelType)

    if type(debuffTypeColor) == "table" then
        local r, g, b = nil, nil, nil
        if safeDispelType == "Magic" then
            r, g, b = GetDebuffColorFromTable(debuffTypeColor.Magic)
        elseif safeDispelType == "Curse" then
            r, g, b = GetDebuffColorFromTable(debuffTypeColor.Curse)
        elseif safeDispelType == "Disease" then
            r, g, b = GetDebuffColorFromTable(debuffTypeColor.Disease)
        elseif safeDispelType == "Poison" then
            r, g, b = GetDebuffColorFromTable(debuffTypeColor.Poison)
        elseif safeDispelType == "Bleed" then
            r, g, b = GetDebuffColorFromTable(debuffTypeColor.Bleed)
        end
        if r then
            return r, g, b
        end
    end

    if safeDispelType == "Magic" then
        return 0.20, 0.60, 1.00
    elseif safeDispelType == "Curse" then
        return 0.60, 0.00, 1.00
    elseif safeDispelType == "Disease" then
        return 0.60, 0.40, 0.00
    elseif safeDispelType == "Poison" then
        return 0.00, 0.60, 0.00
    elseif safeDispelType == "Bleed" then
        return 0.70, 0.10, 0.10
    end

    return 0.80, 0.13, 0.13
end

local function GetDispelTypeFromAtlasName(atlasName)
    if type(atlasName) ~= "string" or IsSecretValue(atlasName) then return nil end
    local lowerAtlas = strlower(atlasName)
    if strfind(lowerAtlas, "magic", 1, true) then
        return "Magic"
    elseif strfind(lowerAtlas, "curse", 1, true) then
        return "Curse"
    elseif strfind(lowerAtlas, "disease", 1, true) then
        return "Disease"
    elseif strfind(lowerAtlas, "poison", 1, true) then
        return "Poison"
    elseif strfind(lowerAtlas, "bleed", 1, true) then
        return "Bleed"
    end
    return nil
end

local function ApplyCompactDebuffBorderColor(auraFrame, aura)
    ApplyCompactAuraCooldownSwipe(auraFrame)
    local dispelType = aura and aura.dispelName
    if not dispelType and auraFrame and auraFrame.icon and auraFrame.icon.GetAtlas then
        dispelType = GetDispelTypeFromAtlasName(auraFrame.icon:GetAtlas())
    end

    local r, g, b = GetDirectDebuffTypeColorRGB(dispelType)
    return ApplyCompactAuraBorderColor(auraFrame, r, g, b, 1)
end

----------------------------------------------------------------------------------------
-- Dispel Color Resolution
----------------------------------------------------------------------------------------
local function EnsureCompactDispelColorProbeTexture()
    if CompactDispelColorProbeTexture then
        return CompactDispelColorProbeTexture
    end

    local ok, probeFrame = pcall(CreateFrame, "Frame", nil, UIParent)
    if not ok or not probeFrame then
        return nil
    end
    probeFrame:Hide()
    probeFrame:SetSize(1, 1)

    local probe = probeFrame:CreateTexture(nil, "BACKGROUND")
    probe:SetAllPoints(probeFrame)
    probe:Hide()
    CompactDispelColorProbeTexture = probe
    return CompactDispelColorProbeTexture
end

local function ResolveBlizzardDispelColorFromAura(aura)
    if not aura then
        return nil, nil, nil
    end

    local auraUtil = _G.AuraUtil
    if type(auraUtil) ~= "table" or type(auraUtil.SetAuraBorderColor) ~= "function" then
        return nil, nil, nil
    end

    local probe = EnsureCompactDispelColorProbeTexture()
    if not probe then
        return nil, nil, nil
    end

    local ok = pcall(auraUtil.SetAuraBorderColor, probe, aura.dispelName)
    if not ok then
        return nil, nil, nil
    end

    if probe.GetVertexColor then
        local r, g, b = probe:GetVertexColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    return nil, nil, nil
end

local function ExtractRGBFromColorObject(color)
    if type(color) ~= "table" then
        return nil, nil, nil
    end

    if type(color.GetRGB) == "function" then
        local r, g, b = color:GetRGB()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    if type(color.GetRGBA) == "function" then
        local r, g, b = color:GetRGBA()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b
    end

    return nil, nil, nil
end

local function ResolveBlizzardDispelColorFromAuraInstance(frame, aura)
    local auraAPI = _G.C_UnitAuras
    local getColor = auraAPI and auraAPI.GetAuraDispelTypeColor
    if type(getColor) ~= "function" then
        return nil, nil, nil
    end
    if not frame or not aura then
        return nil, nil, nil
    end

    local unit = frame.displayedUnit or frame.unit
    if type(unit) ~= "string" then
        return nil, nil, nil
    end

    local auraInstanceID = aura.auraInstanceID
    if auraInstanceID == nil then
        return nil, nil, nil
    end

    local curve = RefineUI and RefineUI.DispelColorCurve or nil
    local ok, colorInfo = pcall(getColor, unit, auraInstanceID, curve)
    if not ok or colorInfo == nil then
        return nil, nil, nil
    end

    return ExtractRGBFromColorObject(colorInfo)
end

----------------------------------------------------------------------------------------
-- Dispel Border Tracking
----------------------------------------------------------------------------------------
local function TrackCompactUnitAuraBorderColor(frame, r, g, b)
    if not frame then
        return
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return
    end

    local data = GetPartyData(frame)
    data.auraBorderR = r
    data.auraBorderG = g
    data.auraBorderB = b
end

local function TrackCompactDispelBorderColor(frame, aura)
    if not frame or frame:IsForbidden() then
        return
    end

    local r, g, b
    if aura and aura.dispelName then
        r, g, b = GetDirectDebuffTypeColorRGB(aura.dispelName)
    end

    if not r then
        local dispelFrames = frame.dispelDebuffFrames
        if type(dispelFrames) == "table" then
            for _, dispelFrame in ipairs(dispelFrames) do
                if dispelFrame and dispelFrame.icon and dispelFrame.icon.GetAtlas then
                    local dispelType = GetDispelTypeFromAtlasName(dispelFrame.icon:GetAtlas())
                    if dispelType then
                        r, g, b = GetDirectDebuffTypeColorRGB(dispelType)
                        break
                    end
                end
            end
        end
    end

    if not r then
        return
    end

    TrackCompactUnitAuraBorderColor(frame, r, g, b)
end

----------------------------------------------------------------------------------------
-- Dispel Indicator Detection
----------------------------------------------------------------------------------------
local function HasShownCompactDispelDebuff(frame)
    if type(frame.dispelDebuffFrames) ~= "table" then
        return false
    end

    for _, dispelFrame in ipairs(frame.dispelDebuffFrames) do
        if dispelFrame and dispelFrame:IsShown() then
            return true
        end
    end

    return false
end

local function HasShownCompactDispelIndicator(frame)
    if HasShownCompactDispelDebuff(frame) then
        return true
    end

    return frame and frame.DispelOverlay and frame.DispelOverlay.IsShown and frame.DispelOverlay:IsShown() or false
end

local function GetCompactDispelIndicatorType(frame)
    if not frame then
        return nil
    end

    if _G.CompactUnitFrame_GetOptionDispelIndicatorType then
        local ok, indicatorType = pcall(_G.CompactUnitFrame_GetOptionDispelIndicatorType, frame)
        if ok and type(indicatorType) == "number" and not IsUnreadableNumber(indicatorType) then
            return indicatorType
        end
    end

    local indicatorType = frame.optionTable and frame.optionTable.raidFramesDispelIndicatorType
    if type(indicatorType) == "number" and not IsUnreadableNumber(indicatorType) then
        return indicatorType
    end

    return nil
end

local function ShouldUseCompactDispelBorderColor(frame)
    local indicatorType = GetCompactDispelIndicatorType(frame)
    local enum = _G.Enum and _G.Enum.RaidDispelDisplayType

    if type(indicatorType) == "number" and type(enum) == "table" then
        if indicatorType == enum.Disabled then
            return false
        end
        if indicatorType == enum.DispellableByMe or indicatorType == enum.DisplayAll then
            return HasShownCompactDispelIndicator(frame)
        end
    end

    return HasShownCompactDispelIndicator(frame)
end

----------------------------------------------------------------------------------------
-- Frame Border Color Update
----------------------------------------------------------------------------------------
local function GetConfiguredCompactPartyBorderColorRGBA()
    local color = Config and Config.General and Config.General.BorderColor
    if type(color) == "table" then
        return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    end
    return 1, 1, 1, 1
end

local function UpdateCompactPartyDispelBorderColor(frame)
    if not frame or frame:IsForbidden() then
        return
    end

    local data = GetPartyData(frame)
    local border = data.healthBarBorder
    if not border then
        return
    end

    local colorR, colorG, colorB, colorA

    if ShouldUseCompactDispelBorderColor(frame) then
        if type(data.auraBorderR) == "number" then
            colorR = data.auraBorderR
            colorG = data.auraBorderG or data.auraBorderR
            colorB = data.auraBorderB or data.auraBorderR
            colorA = 1
        else
            local dispelFrames = frame.dispelDebuffFrames
            if type(dispelFrames) == "table" then
                for _, dispelFrame in ipairs(dispelFrames) do
                    if dispelFrame and dispelFrame:IsShown() and dispelFrame.icon and dispelFrame.icon.GetAtlas then
                        local dispelType = GetDispelTypeFromAtlasName(dispelFrame.icon:GetAtlas())
                        if dispelType then
                            colorR, colorG, colorB = GetDirectDebuffTypeColorRGB(dispelType)
                            colorA = 1
                            break
                        end
                    end
                end
            end

            if not colorR and frame.DispelOverlay and frame.DispelOverlay.IsShown and frame.DispelOverlay:IsShown() and frame.DispelOverlay.GetDispelType then
                local dispelType = GetSafeDispelTypeKey(frame.DispelOverlay:GetDispelType())
                if dispelType then
                    colorR, colorG, colorB = GetDirectDebuffTypeColorRGB(dispelType)
                    colorA = 1
                end
            end
        end
    end

    data.auraBorderR = nil
    data.auraBorderG = nil
    data.auraBorderB = nil

    if not colorR and type(data.classBuffBorderR) == "number"
        and type(data.classBuffBorderG) == "number"
        and type(data.classBuffBorderB) == "number" then
        colorR = data.classBuffBorderR
        colorG = data.classBuffBorderG
        colorB = data.classBuffBorderB
        colorA = 1
    end

    if not colorR then
        colorR, colorG, colorB, colorA = GetConfiguredCompactPartyBorderColorRGBA()
    end

    border:SetBackdropBorderColor(colorR, colorG, colorB, colorA)
end

local function EvaluateFrameColorCandidate(buffFrame, settings, entryKey, bestState)
    if not buffFrame or not settings or settings.FrameColor ~= true then
        return
    end

    local priority = (settings.Important == true) and 2 or 1
    local remaining = P.GetAuraRemainingSecondsFromData(GetPartyAuraData(buffFrame))

    local shouldReplace = false
    if priority > bestState.priority then
        shouldReplace = true
    elseif priority == bestState.priority then
        if remaining and bestState.remaining then
            shouldReplace = remaining < bestState.remaining
        elseif remaining and not bestState.remaining then
            shouldReplace = true
        end
    end

    if shouldReplace then
        local r, g, b = P.GetTrackedClassBuffColor(entryKey)
        bestState.priority = priority
        bestState.remaining = remaining
        bestState.r = r
        bestState.g = g
        bestState.b = b
    end
end

----------------------------------------------------------------------------------------
-- Top-Level Aura Styling Orchestrator
----------------------------------------------------------------------------------------
local function ApplyCompactAuraStylingForFrame(frame)
    if not frame or frame:IsForbidden() then return end
    if not IsPartyRaidCompactFrame(frame) then return end

    local frameData = GetPartyData(frame)
    frameData.classBuffBorderR = nil
    frameData.classBuffBorderG = nil
    frameData.classBuffBorderB = nil

    local auraScratch = GetAuraScratch and GetAuraScratch(frame) or frameData.AuraScratch or {}
    auraScratch.importantBuffFrames = auraScratch.importantBuffFrames or {}
    local importantBuffFrames = WipeTable(auraScratch.importantBuffFrames)
    local bestFrameColor = ResetBestFrameColorState()

    local EnsureCompactAuraSpacing = P.EnsureCompactAuraSpacing
    local BUFF   = P.COMPACT_AURA_CONTAINER_BUFF
    local DEBUFF = P.COMPACT_AURA_CONTAINER_DEBUFF
    local DISPEL = P.COMPACT_AURA_CONTAINER_DISPEL

    if type(frame.buffFrames) == "table" then
        for index, buffFrame in ipairs(frame.buffFrames) do
            if buffFrame then
                EnsureCompactAuraSpacing(frame, buffFrame, BUFF, index)
                if not GetPartyAuraData(buffFrame).border then
                    EnsureCompactAuraBorder(buffFrame)
                end
            end
            if buffFrame and buffFrame:IsShown() then
                ApplyCompactBuffBorderColor(buffFrame)

                local entry = GetTrackedClassBuffEntryForAuraFrame(buffFrame)
                if entry then
                    local settings = P.GetTrackedClassBuffSettings(entry.key)
                    if settings and settings.Important == true then
                        tinsert(importantBuffFrames, buffFrame)
                    end
                    EvaluateFrameColorCandidate(buffFrame, settings, entry.key, bestFrameColor)
                end
            end
        end
    end

    P.ApplyCompactImportantBuffLayout(frame, importantBuffFrames)

    if frame.CenterDefensiveBuff then
        if not GetPartyAuraData(frame.CenterDefensiveBuff).border then
            EnsureCompactAuraBorder(frame.CenterDefensiveBuff)
        end
        if frame.CenterDefensiveBuff:IsShown() then
            ApplyCompactBuffBorderColor(frame.CenterDefensiveBuff)

            local entry = GetTrackedClassBuffEntryForAuraFrame(frame.CenterDefensiveBuff)
            if entry then
                local settings = P.GetTrackedClassBuffSettings(entry.key)
                EvaluateFrameColorCandidate(frame.CenterDefensiveBuff, settings, entry.key, bestFrameColor)
            end
        end
    end

    if type(frame.debuffFrames) == "table" then
        for index, debuffFrame in ipairs(frame.debuffFrames) do
            if debuffFrame then
                EnsureCompactAuraSpacing(frame, debuffFrame, DEBUFF, index)
                if not GetPartyAuraData(debuffFrame).border then
                    EnsureCompactAuraBorder(debuffFrame)
                end
            end
            if debuffFrame and debuffFrame:IsShown() then
                ApplyCompactDebuffBorderColor(debuffFrame)
            end
        end
    end

    if type(frame.dispelDebuffFrames) == "table" then
        for index, dispelFrame in ipairs(frame.dispelDebuffFrames) do
            if dispelFrame then
                EnsureCompactAuraSpacing(frame, dispelFrame, DISPEL, index)
                HideCompactAuraBorder(dispelFrame)
            end
        end
    end

    if type(bestFrameColor.r) == "number" then
        frameData.classBuffBorderR = bestFrameColor.r
        frameData.classBuffBorderG = bestFrameColor.g or bestFrameColor.r
        frameData.classBuffBorderB = bestFrameColor.b or bestFrameColor.r
    end

    UpdateCompactPartyDispelBorderColor(frame)
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.EnsureCompactAuraBorder               = EnsureCompactAuraBorder
P.ApplyCompactAuraBorderColor           = ApplyCompactAuraBorderColor
P.HideCompactAuraBorder                 = HideCompactAuraBorder
P.TrackCompactBuffAuraData              = TrackCompactBuffAuraData
P.ApplyCompactBuffBorderColor           = ApplyCompactBuffBorderColor
P.ApplyCompactDebuffBorderColor         = ApplyCompactDebuffBorderColor
P.TrackCompactDispelBorderColor         = TrackCompactDispelBorderColor
P.UpdateCompactPartyDispelBorderColor   = UpdateCompactPartyDispelBorderColor
P.ApplyCompactAuraStylingForFrame       = ApplyCompactAuraStylingForFrame
