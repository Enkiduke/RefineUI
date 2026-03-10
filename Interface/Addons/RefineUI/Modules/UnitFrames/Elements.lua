----------------------------------------------------------------------------------------
-- UnitFrames Component: Elements
-- Description: Shared colors, custom text elements, and aura styling.
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
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Global / Local Imports
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHealth = UnitHealth
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitIsUnit = UnitIsUnit
local UnitCanAttack = UnitCanAttack
local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent
local ipairs = ipairs
local max = math.max
local unpack = unpack
local pairs = pairs
local type = type
local tonumber = tonumber
local issecretvalue = issecretvalue

----------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------
local MyClassColor = RefineUI.MyClassColor

function UnitFrames.GetUnitHealthColor(unit)
    if not unit or not UnitExists(unit) then
        return unpack(Config.UnitFrames.Bars.HealthColor)
    end

    if UnitIsPlayer(unit) and Config.UnitFrames.Bars.UseClassColor then
        if UnitIsUnit(unit, "player") and MyClassColor then
            return MyClassColor.r, MyClassColor.g, MyClassColor.b
        end

        local _, class = UnitClass(unit)
        local color = RefineUI.Colors.Class[class]
        if color then
            return color.r, color.g, color.b
        end
    elseif Config.UnitFrames.Bars.UseReactionColor then
        if UnitIsTapDenied(unit) then
            return 0.5, 0.5, 0.5
        end

        local reaction = UnitReaction(unit, "player")
        if reaction then
            local color = RefineUI.Colors.Reaction[reaction]
            if color then
                return color.r, color.g, color.b
            end
        end
    end

    return unpack(Config.UnitFrames.Bars.HealthColor)
end

function UnitFrames.GetUnitPowerColor(unit)
    if not unit or not UnitExists(unit) then
        return unpack(Config.UnitFrames.Bars.ManaColor)
    end

    if Config.UnitFrames.Bars.UsePowerColor then
        local _, powerToken = UnitPowerType(unit)
        local color = RefineUI.Colors.Power[powerToken]
        if color then
            return color.r, color.g, color.b
        end
    end

    return unpack(Config.UnitFrames.Bars.ManaColor)
end

----------------------------------------------------------------------------------------
-- Custom Text
----------------------------------------------------------------------------------------
local function GetCustomTextData(frame)
    local data = UnitFrames:GetFrameData(frame)
    data.CustomText = data.CustomText or {}
    return data.CustomText
end

local function UpdateCustomHPText(frame, unit)
    local textData = GetCustomTextData(frame)
    local percentText = textData.HealthPercentText
    local currentText = textData.HealthCurrentText
    if not percentText or not currentText then
        return
    end

    if not UnitIsConnected(unit) then
        RefineUI:SetFontStringValue(percentText, "OFFLINE", { emptyText = "" })
        RefineUI:SetFontStringValue(currentText, "OFFLINE", { emptyText = "" })
        percentText:SetTextColor(0.5, 0.5, 0.5)
        currentText:SetTextColor(0.5, 0.5, 0.5)
    elseif UnitIsDeadOrGhost(unit) then
        RefineUI:SetFontStringValue(percentText, "DEAD", { emptyText = "" })
        RefineUI:SetFontStringValue(currentText, "DEAD", { emptyText = "" })
        percentText:SetTextColor(0.5, 0.5, 0.5)
        currentText:SetTextColor(0.5, 0.5, 0.5)
    else
        local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
        local hp = UnitHealth(unit)
        RefineUI:SetFontStringValue(percentText, percent, { emptyText = "" })
        RefineUI:SetFontStringValue(currentText, hp, { emptyText = "" })
        percentText:SetTextColor(1, 1, 1)
        currentText:SetTextColor(1, 1, 1)
    end
end

local function GetPlayerManaOverlayBar()
    local playerFrame = _G.PlayerFrame
    if not playerFrame then
        return nil
    end

    local data = UnitFrames:GetFrameData(playerFrame)
    local overlayData = data and data.PlayerManaOverlay
    return overlayData and overlayData.Bar or nil
end

local function SyncManaTextParent(frame, manaBar, unit)
    local textData = GetCustomTextData(frame)
    local manaText = textData.ManaPercentText
    if not manaText then
        return
    end

    local desiredParent = manaBar
    if unit == "player" and UnitFrames.IsPlayerSecondaryPowerSwapActive and UnitFrames.IsPlayerSecondaryPowerSwapActive() then
        local overlayBar = GetPlayerManaOverlayBar()
        if overlayBar then
            desiredParent = overlayBar
        end
    end

    if manaText:GetParent() ~= desiredParent then
        manaText:SetParent(desiredParent)
    end
end

local function UpdateCustomManaText(frame, manaBar, unit)
    local textData = GetCustomTextData(frame)
    local manaText = textData.ManaPercentText
    if not manaText then
        return
    end

    SyncManaTextParent(frame, manaBar, unit)

    local powerType
    if unit == "player" and UnitFrames.IsPlayerSecondaryPowerSwapActive and UnitFrames.IsPlayerSecondaryPowerSwapActive() then
        powerType = Enum.PowerType.Mana
    end

    local percent = UnitPowerPercent(unit, powerType, false, RefineUI.GetPercentCurve())
    RefineUI:SetFontStringValue(manaText, percent, { emptyText = "" })
end

function UnitFrames.CreateCustomText(frame)
    local _, _, hpContainer, manaBar = UnitFrames:GetFrameContainers(frame)
    if not hpContainer then
        return
    end

    local unit = frame.unit or "player"
    local cfg = Config.UnitFrames.Fonts
    local frameData = UnitFrames:GetFrameData(frame)
    local textData = GetCustomTextData(frame)
    local refineUF = frameData and frameData.RefineUF
    local parentTex = refineUF and refineUF.Texture or frame

    for _, text in pairs({ hpContainer.LeftText, hpContainer.RightText, hpContainer.HealthBarText, hpContainer.DeadText }) do
        if text then
            text:SetAlpha(0)
            if not UnitFrames:GetState(text, "HiddenHook", false) then
                RefineUI:HookOnce(UnitFrames:BuildHookKey(text, "SetAlpha:CustomText"), text, "SetAlpha", function(selfText, alpha)
                    if alpha ~= 0 then
                        selfText:SetAlpha(0)
                    end
                end)
                UnitFrames:SetState(text, "HiddenHook", true)
            end
        end
    end

    if not textData.HealthPercentText then
        textData.HealthPercentText = hpContainer:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(textData.HealthPercentText, cfg.HPSize)
        textData.HealthPercentText:SetPoint("CENTER", parentTex, "CENTER", 0, 8)
    end

    if not textData.HealthCurrentText then
        textData.HealthCurrentText = hpContainer:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(textData.HealthCurrentText, cfg.HPSize)
        textData.HealthCurrentText:SetPoint("CENTER", parentTex, "CENTER", 0, 8)
        textData.HealthCurrentText:SetAlpha(0)
    end

    if manaBar then
        for _, text in pairs({ manaBar.LeftText, manaBar.RightText, manaBar.ManaBarText }) do
            if text then
                text:SetAlpha(0)
                if not UnitFrames:GetState(text, "HiddenHook", false) then
                    RefineUI:HookOnce(UnitFrames:BuildHookKey(text, "SetAlpha:CustomText"), text, "SetAlpha", function(selfText, alpha)
                        if alpha ~= 0 then
                            selfText:SetAlpha(0)
                        end
                    end)
                    UnitFrames:SetState(text, "HiddenHook", true)
                end
            end
        end

        if not textData.ManaPercentText then
            textData.ManaPercentText = manaBar:CreateFontString(nil, "OVERLAY")
            RefineUI.Font(textData.ManaPercentText, cfg.ManaSize)
            textData.ManaPercentText:SetPoint("CENTER", parentTex, "CENTER", 2, -6)
            textData.ManaPercentText:SetAlpha(0)
        end
    end

    if not UnitFrames:GetState(hpContainer, "CustomTextEventsRegistered", false) then
        local function OnHealthEvent(_, eventUnit)
            if eventUnit == unit then
                UpdateCustomHPText(frame, unit)
            end
        end

        UpdateCustomHPText(frame, unit)
        RefineUI:OnEvents({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }, OnHealthEvent, "RefineUF_HP_" .. unit)

        if frame == TargetFrame then
            RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function()
                UpdateCustomHPText(frame, frame.unit)
            end, "RefineUF_TGT_HP")
        elseif frame == FocusFrame then
            RefineUI:RegisterEventCallback("PLAYER_FOCUS_CHANGED", function()
                UpdateCustomHPText(frame, frame.unit)
            end, "RefineUF_FOC_HP")
        end

        UnitFrames:SetState(hpContainer, "CustomTextEventsRegistered", true)
    end

    if manaBar and not UnitFrames:GetState(manaBar, "CustomTextEventsRegistered", false) then
        local function OnPowerEvent(_, eventUnit)
            if eventUnit == unit then
                UpdateCustomManaText(frame, manaBar, unit)
            end
        end

        UpdateCustomManaText(frame, manaBar, unit)
        RefineUI:OnEvents({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }, OnPowerEvent, "RefineUF_PP_" .. unit)

        if frame == TargetFrame then
            RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function()
                UpdateCustomManaText(frame, manaBar, frame.unit)
            end, "RefineUF_TGT_MP")
        elseif frame == FocusFrame then
            RefineUI:RegisterEventCallback("PLAYER_FOCUS_CHANGED", function()
                UpdateCustomManaText(frame, manaBar, frame.unit)
            end, "RefineUF_FOC_MP")
        end

        UnitFrames:SetState(manaBar, "CustomTextEventsRegistered", true)
    end

    if not UnitFrames:GetState(frame, "RefineHoverHooked", false) then
        local function OnEnter()
            textData.HealthPercentText:SetAlpha(0)
            textData.HealthCurrentText:SetAlpha(1)
            if textData.ManaPercentText then
                textData.ManaPercentText:SetAlpha(1)
            end
        end

        local function OnLeave()
            textData.HealthPercentText:SetAlpha(1)
            textData.HealthCurrentText:SetAlpha(0)
            if textData.ManaPercentText then
                textData.ManaPercentText:SetAlpha(0)
            end
        end

        frame:HookScript("OnEnter", OnEnter)
        frame:HookScript("OnLeave", OnLeave)
        if hpContainer.HealthBar then
            hpContainer.HealthBar:HookScript("OnEnter", OnEnter)
            hpContainer.HealthBar:HookScript("OnLeave", OnLeave)
        end
        if manaBar then
            manaBar:HookScript("OnEnter", OnEnter)
            manaBar:HookScript("OnLeave", OnLeave)
        end

        UnitFrames:SetState(frame, "RefineHoverHooked", true)
    end
end

----------------------------------------------------------------------------------------
-- Auras
----------------------------------------------------------------------------------------
local TARGET_FOCUS_AURA_BORDER_INSET = 4
local TARGET_FOCUS_AURA_BORDER_EDGE = 8
local TARGET_FOCUS_AURA_COOLDOWN_OFFSET_X = 1.5
local TARGET_FOCUS_AURA_COOLDOWN_OFFSET_Y = 1.5
local TARGET_FOCUS_DEBUFF_DISPLAY_INFO = AuraUtil and AuraUtil.GetDebuffDisplayInfoTable and AuraUtil.GetDebuffDisplayInfoTable() or nil

local function GetTargetFocusCooldownSwipeTexture()
    local textures = Media and Media.Textures
    if type(textures) ~= "table" then
        return nil
    end

    if type(textures.CooldownSwipeSmall) == "string" and textures.CooldownSwipeSmall ~= "" then
        return textures.CooldownSwipeSmall
    end

    if type(textures.CooldownSwipe) == "string" and textures.CooldownSwipe ~= "" then
        return textures.CooldownSwipe
    end

    return nil
end

local function IsPlayerOrPetAuraSource(sourceUnit)
    if issecretvalue and issecretvalue(sourceUnit) then
        return false
    end

    return sourceUnit == "player" or sourceUnit == "pet"
end

local function GetTargetFocusAuraBorderColor(button, auraData)
    local color = Config.General and Config.General.BorderColor
    local defaultR = color and color[1] or 0.6
    local defaultG = color and color[2] or 0.6
    local defaultB = color and color[3] or 0.6
    local defaultA = color and (color[4] or 1) or 1

    if not auraData then
        return defaultR, defaultG, defaultB, defaultA
    end

    local isHarmful = auraData.isHarmful
    if issecretvalue and issecretvalue(isHarmful) then
        return defaultR, defaultG, defaultB, defaultA
    end

    if not isHarmful then
        local auraConfig = UnitFrames.GetTargetFocusAuraConfig and UnitFrames.GetTargetFocusAuraConfig(button and button.unit)
        local isLargeBuff = IsPlayerOrPetAuraSource(auraData.sourceUnit)
        local buffColor = isLargeBuff and auraConfig and auraConfig.LargeBuffBorderColor or auraConfig and auraConfig.SmallBuffBorderColor
        if type(buffColor) == "table" and type(buffColor[1]) == "number" and type(buffColor[2]) == "number" and type(buffColor[3]) == "number" then
            return buffColor[1], buffColor[2], buffColor[3], buffColor[4] or defaultA
        end
        return defaultR, defaultG, defaultB, defaultA
    end

    local dispelType = auraData.dispelName
    if issecretvalue and issecretvalue(dispelType) then
        return defaultR, defaultG, defaultB, defaultA
    end

    local info = TARGET_FOCUS_DEBUFF_DISPLAY_INFO and (TARGET_FOCUS_DEBUFF_DISPLAY_INFO[dispelType] or TARGET_FOCUS_DEBUFF_DISPLAY_INFO.None)
    local colorInfo = info and info.color
    if colorInfo and colorInfo.GetRGBA then
        return colorInfo:GetRGBA()
    end

    return defaultR, defaultG, defaultB, defaultA
end

local function EnsureAuraSkin(button)
    local skin = UnitFrames:GetState(button, "AuraSkin", nil)
    if skin then
        return skin
    end

    skin = {}

    local wrapper = CreateFrame("Frame", nil, button)
    wrapper:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    wrapper:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    skin.wrapper = wrapper

    if button.Icon and button.Icon.GetTexture then
        local skinnedIcon = wrapper:CreateTexture(nil, "BACKGROUND")
        skinnedIcon:SetAllPoints(wrapper)
        skinnedIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        skinnedIcon:SetTexture(button.Icon:GetTexture())
        button.Icon:SetAlpha(0)

        RefineUI:HookOnce(UnitFrames:BuildHookKey(button.Icon, "SetTexture:TargetFocusAura"), button.Icon, "SetTexture", function(_, texture)
            skinnedIcon:SetTexture(texture)
        end)

        skin.skinnedIcon = skinnedIcon
    end

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)
    cooldown:SetHideCountdownNumbers(true)

    local swipeTexture = GetTargetFocusCooldownSwipeTexture()
    if swipeTexture and cooldown.SetSwipeTexture then
        cooldown:SetSwipeTexture(swipeTexture)
    end

    skin.cooldown = cooldown

    UnitFrames:SetState(button, "AuraSkin", skin)
    return skin
end

local function UpdateAuraSkin(button, auraData)
    local skin = EnsureAuraSkin(button)
    if not skin or not skin.wrapper then
        return
    end

    local wrapper = skin.wrapper
    wrapper:ClearAllPoints()
    wrapper:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    wrapper:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    if wrapper.SetFrameStrata then
        wrapper:SetFrameStrata(button:GetFrameStrata() or "MEDIUM")
    end
    if wrapper.SetFrameLevel then
        wrapper:SetFrameLevel(button:GetFrameLevel() or 0)
    end

    if skin.skinnedIcon and button.Icon and button.Icon.GetTexture then
        skin.skinnedIcon:SetTexture(button.Icon:GetTexture())
        button.Icon:SetAlpha(0)
    end

    RefineUI.CreateBorder(wrapper, TARGET_FOCUS_AURA_BORDER_INSET, TARGET_FOCUS_AURA_BORDER_INSET, TARGET_FOCUS_AURA_BORDER_EDGE)

    if wrapper.border and wrapper.border.SetFrameStrata then
        wrapper.border:SetFrameStrata(wrapper:GetFrameStrata() or "MEDIUM")
    end
    if wrapper.border and wrapper.border.SetFrameLevel then
        wrapper.border:SetFrameLevel(max(0, (wrapper:GetFrameLevel() or 0) + 1))
    end
    if wrapper.border and wrapper.border.SetBackdropBorderColor then
        wrapper.border:SetBackdropBorderColor(GetTargetFocusAuraBorderColor(button, auraData))
    end

    local cooldown = skin.cooldown
    if not cooldown then
        return
    end

    if cooldown.ClearAllPoints and cooldown.SetPoint then
        cooldown:ClearAllPoints()
        cooldown:SetPoint("TOPLEFT", wrapper, "TOPLEFT", -TARGET_FOCUS_AURA_COOLDOWN_OFFSET_X, TARGET_FOCUS_AURA_COOLDOWN_OFFSET_Y)
        cooldown:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", TARGET_FOCUS_AURA_COOLDOWN_OFFSET_X, -TARGET_FOCUS_AURA_COOLDOWN_OFFSET_Y)
    end
    if cooldown.SetFrameStrata then
        cooldown:SetFrameStrata(button:GetFrameStrata() or "MEDIUM")
    end
    if cooldown.SetFrameLevel then
        cooldown:SetFrameLevel((button:GetFrameLevel() or 0) + 50)
    end

    if button.Cooldown and button.Cooldown ~= cooldown then
        button.Cooldown:Hide()
        RefineUI:HookOnce(UnitFrames:BuildHookKey(button.Cooldown, "Show:TargetFocusAura"), button.Cooldown, "Show", function(selfCooldown)
            selfCooldown:Hide()
        end)
    end

    local auraInstanceID = auraData and auraData.auraInstanceID or button.auraInstanceID
    local auraDurationObj = nil
    local didSetCooldown = false

    if C_UnitAuras and C_UnitAuras.GetAuraDuration and auraInstanceID and button.unit then
        auraDurationObj = C_UnitAuras.GetAuraDuration(button.unit, auraInstanceID)
        if auraDurationObj and type(cooldown.SetCooldownFromDurationObject) == "function" then
            local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, auraDurationObj)
            if ok then
                didSetCooldown = true
            end
        end
    end

    if not didSetCooldown and auraData then
        if type(cooldown.SetCooldownFromExpirationTime) == "function" then
            local ok = pcall(cooldown.SetCooldownFromExpirationTime, cooldown, auraData.expirationTime, auraData.duration, 1)
            if ok then
                didSetCooldown = true
            end
        end
    end

    if didSetCooldown then
        cooldown:Show()
    else
        if cooldown.Clear then
            cooldown:Clear()
        end
        cooldown:Hide()
    end
end

function UnitFrames.StyleAuraIcon(button)
    if not button or button:IsForbidden() or UnitFrames:GetState(button, "AuraStyled", false) then
        return
    end

    EnsureAuraSkin(button)

    if button.Border then
        button.Border:Hide()
        RefineUI:HookOnce(UnitFrames:BuildHookKey(button.Border, "Show:AuraBorder"), button.Border, "Show", function(selfBorder)
            selfBorder:Hide()
        end)
    end

    if button.Stealable then
        button.Stealable:Hide()
        RefineUI:HookOnce(UnitFrames:BuildHookKey(button.Stealable, "Show:Stealable"), button.Stealable, "Show", function(selfStealable)
            selfStealable:Hide()
        end)
    end

    UnitFrames:SetState(button, "AuraStyled", true)
end

function UnitFrames.GetTargetFocusAuraConfig(frameOrUnit)
    local unit = frameOrUnit
    if type(frameOrUnit) == "table" then
        if frameOrUnit == FocusFrame then
            unit = "focus"
        else
            unit = frameOrUnit.unit
        end
    end

    if unit == "focus" then
        return Config.UnitFrames.FocusAuras or Config.UnitFrames.TargetAuras or Config.UnitFrames.Auras
    end

    return Config.UnitFrames.TargetAuras or Config.UnitFrames.Auras
end

local function EnsureTargetFocusAuraHolders(frame)
    local data = UnitFrames:GetFrameData(frame)
    if data.TargetFocusAuraHolders then
        return data.TargetFocusAuraHolders
    end

    local holders = {}
    holders.near = CreateFrame("Frame", nil, frame)
    holders.far = CreateFrame("Frame", nil, frame)

    for _, holder in pairs(holders) do
        holder:SetSize(1, 1)
        holder:Hide()
        holder:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
        holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    end

    data.TargetFocusAuraHolders = holders
    return holders
end

local function HideTargetFocusAuraHolders(frame)
    local data = UnitFrames:GetFrameData(frame)
    local holders = data and data.TargetFocusAuraHolders
    if not holders then
        return
    end

    holders.near:Hide()
    holders.far:Hide()
end

local function NormalizeAuraMetric(value, fallback, minimum)
    if type(value) ~= "number" then
        value = fallback
    end

    if minimum and value < minimum then
        value = minimum
    end

    return value
end

local function GetTargetFocusAuraMetrics(frame)
    local cfg = UnitFrames.GetTargetFocusAuraConfig(frame) or {}
    local hasToT = frame.totFrame and frame.totFrame:IsShown()

    return {
        enabled = cfg.Enable ~= false,
        size = NormalizeAuraMetric(cfg.Size, 14, 8),
        largeSize = NormalizeAuraMetric(cfg.LargeSize, 18, 8),
        spacingX = NormalizeAuraMetric(cfg.HorizontalSpacing, 2, 0),
        spacingY = NormalizeAuraMetric(cfg.VerticalSpacing, 2, 0),
        groupGap = NormalizeAuraMetric(cfg.GroupGap, 4, 0),
        offsetX = NormalizeAuraMetric(cfg.OffsetX, 0),
        offsetY = NormalizeAuraMetric(cfg.OffsetY, 4, 0),
        wrapWidth = NormalizeAuraMetric(hasToT and cfg.WrapWidthWithToT or cfg.WrapWidth, hasToT and 101 or 122, 16),
    }
end

local function GetTargetFocusPlayerDebuffAuraSet(frame)
    if not frame or not frame.unit or not C_UnitAuras or type(C_UnitAuras.GetUnitAuras) ~= "function" then
        return nil
    end

    local cfg = UnitFrames.GetTargetFocusAuraConfig(frame)
    if not cfg or not cfg.OnlyPlayerDebuffsOnEnemies then
        return nil
    end

    if not UnitCanAttack("player", frame.unit) then
        return nil
    end

    local auraDataList = C_UnitAuras.GetUnitAuras(frame.unit, "HARMFUL|PLAYER")
    if type(auraDataList) ~= "table" or #auraDataList == 0 then
        return {}
    end

    local allowedAuraInstanceIDs = {}
    for index = 1, #auraDataList do
        local auraData = auraDataList[index]
        local auraInstanceID = auraData and auraData.auraInstanceID
        if auraInstanceID then
            allowedAuraInstanceIDs[auraInstanceID] = true
        end
    end

    return allowedAuraInstanceIDs
end

local function BuildOrderedTargetFocusAuraLists(frame)
    local buttonByAuraInstanceID = {}
    local buffs = {}
    local debuffs = {}
    local playerDebuffAuraSet = GetTargetFocusPlayerDebuffAuraSet(frame)

    for button in frame.auraPools:EnumerateActive() do
        if button and button.auraInstanceID then
            buttonByAuraInstanceID[button.auraInstanceID] = button
        end
    end

    if frame.activeBuffs and frame.activeBuffs.Iterate then
        frame.activeBuffs:Iterate(function(auraInstanceID, auraData)
            local button = buttonByAuraInstanceID[auraInstanceID]
            if button and auraData then
                buffs[#buffs + 1] = { button = button, auraData = auraData }
            end
        end)
    end

    if frame.activeDebuffs and frame.activeDebuffs.Iterate then
        frame.activeDebuffs:Iterate(function(auraInstanceID, auraData)
            local button = buttonByAuraInstanceID[auraInstanceID]
            if button and auraData then
                if not playerDebuffAuraSet or playerDebuffAuraSet[auraInstanceID] then
                    debuffs[#debuffs + 1] = { button = button, auraData = auraData }
                else
                    button:Hide()
                end
            end
        end)
    end

    return buffs, debuffs
end

local function ApplyTargetFocusAuraButtonLayout(button, holder, growUp, xOffset, yOffset, size)
    local point = growUp and "BOTTOMLEFT" or "TOPLEFT"
    local relativePoint = point
    local relativeY = growUp and yOffset or -yOffset

    button:Show()
    button:ClearAllPoints()
    button:SetPoint(point, holder, relativePoint, xOffset, relativeY)
    button:SetSize(size, size)
end

local function LayoutTargetFocusAuraGroup(holder, orderedAuras, metrics, growUp)
    if not holder then
        return 0, false
    end

    if #orderedAuras == 0 then
        holder:Hide()
        return 0, false
    end

    local currentRowWidth = 0
    local currentRowHeight = 0
    local totalHeight = 0
    local usedWidth = 0
    local xOffset = 0
    local yOffset = 0

    for index = 1, #orderedAuras do
        local entry = orderedAuras[index]
        local button = entry.button
        local auraData = entry.auraData
        local size = (auraData and IsPlayerOrPetAuraSource(auraData.sourceUnit)) and metrics.largeSize or metrics.size
        local projectedWidth = currentRowWidth
        if projectedWidth > 0 then
            projectedWidth = projectedWidth + metrics.spacingX
        end
        projectedWidth = projectedWidth + size

        if currentRowWidth > 0 and projectedWidth > metrics.wrapWidth then
            totalHeight = totalHeight + currentRowHeight + metrics.spacingY
            yOffset = totalHeight
            xOffset = 0
            currentRowWidth = 0
            currentRowHeight = 0
            projectedWidth = size
        end

        if currentRowWidth > 0 then
            xOffset = currentRowWidth + metrics.spacingX
        else
            xOffset = 0
        end

        ApplyTargetFocusAuraButtonLayout(button, holder, growUp, xOffset, yOffset, size)

        currentRowWidth = projectedWidth
        currentRowHeight = max(currentRowHeight, size)
        usedWidth = max(usedWidth, currentRowWidth)
    end

    totalHeight = totalHeight + currentRowHeight
    holder:SetSize(max(usedWidth, 1), max(totalHeight, 1))
    holder:Show()
    return totalHeight, true
end

local function AnchorTargetFocusAuraHolder(holder, anchorFrame, growUp, offsetX, offsetY)
    if growUp then
        holder:ClearAllPoints()
        holder:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", offsetX, offsetY)
    else
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", offsetX, -offsetY)
    end
end

local function AnchorSecondaryTargetFocusAuraHolder(holder, nearHolder, anchorFrame, growUp, offsetX, offsetY, groupGap, hasNearGroup)
    holder:ClearAllPoints()

    if hasNearGroup then
        if growUp then
            holder:SetPoint("BOTTOMLEFT", nearHolder, "TOPLEFT", 0, groupGap)
        else
            holder:SetPoint("TOPLEFT", nearHolder, "BOTTOMLEFT", 0, -groupGap)
        end
    else
        AnchorTargetFocusAuraHolder(holder, anchorFrame, growUp, offsetX, offsetY)
    end
end

local function ApplyTargetFocusAuraLayout(frame)
    local _, _, hpContainer = UnitFrames:GetFrameContainers(frame)
    if not hpContainer then
        return
    end

    local buffs, debuffs = BuildOrderedTargetFocusAuraLists(frame)
    for index = 1, #buffs do
        UpdateAuraSkin(buffs[index].button, buffs[index].auraData)
    end
    for index = 1, #debuffs do
        UpdateAuraSkin(debuffs[index].button, debuffs[index].auraData)
    end

    local metrics = GetTargetFocusAuraMetrics(frame)
    local holders = EnsureTargetFocusAuraHolders(frame)

    if not metrics.enabled then
        HideTargetFocusAuraHolders(frame)
        return
    end

    local isFriend = frame.unit and not UnitCanAttack("player", frame.unit)
    local growUp = frame.buffsOnTop == true
    local nearAuras = isFriend and buffs or debuffs
    local farAuras = isFriend and debuffs or buffs

    AnchorTargetFocusAuraHolder(holders.near, hpContainer, growUp, metrics.offsetX, metrics.offsetY)
    local nearHeight, hasNearGroup = LayoutTargetFocusAuraGroup(holders.near, nearAuras, metrics, growUp)
    if not hasNearGroup then
        nearHeight = 0
    end

    AnchorSecondaryTargetFocusAuraHolder(holders.far, holders.near, hpContainer, growUp, metrics.offsetX, metrics.offsetY, metrics.groupGap, hasNearGroup and nearHeight > 0)
    LayoutTargetFocusAuraGroup(holders.far, farAuras, metrics, growUp)
end

function UnitFrames.RefreshTargetFocusAuraLayout(frame)
    if not frame or not frame.auraPools or (frame ~= TargetFrame and frame ~= FocusFrame) then
        return
    end

    if frame.UpdateAuras then
        pcall(frame.UpdateAuras, frame)
    else
        UnitFrames.UpdateUnitAuras(frame)
    end
end

function UnitFrames.UpdateUnitAuras(frame)
    if not frame or not frame.auraPools then
        return
    end

    for button in frame.auraPools:EnumerateActive() do
        UnitFrames.StyleAuraIcon(button)
    end

    if frame == TargetFrame or frame == FocusFrame then
        ApplyTargetFocusAuraLayout(frame)
    end
end
