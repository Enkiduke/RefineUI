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
local Auras = RefineUI:GetModule("Auras")

----------------------------------------------------------------------------------------
-- Global / Local Imports
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local IsResting = IsResting
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHealth = UnitHealth
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsPlayer = UnitIsPlayer
local UnitReaction = UnitReaction
local UnitIsUnit = UnitIsUnit
local UnitCanAttack = UnitCanAttack
local UnitIsOtherPlayersPet = UnitIsOtherPlayersPet
local UnitHealthPercent = UnitHealthPercent
local UnitPowerPercent = UnitPowerPercent
local ipairs = ipairs
local unpack = unpack
local pairs = pairs
local type = type
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------
local MyClassColor = RefineUI.MyClassColor

function UnitFrames.GetUnitHealthColor(unit)
    if not unit or not UnitExists(unit) then
        return unpack(Config.UnitFrames.Bars.HealthColor)
    end

    if UnitIsDeadOrGhost(unit) then
        return 0.5, 0.5, 0.5
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
local PLAYER_FRAME_EVENT_UNITS = { "player", "vehicle" }

local function GetCustomTextData(frame)
    local data = UnitFrames:GetFrameData(frame)
    data.CustomText = data.CustomText or {}
    return data.CustomText
end

local function ShouldHidePlayerHealthText()
    return IsResting() and not (PlayerFrame and PlayerFrame.inCombat)
end

function UnitFrames:UpdatePlayerRestPresentation(frame)
    if frame ~= PlayerFrame then
        return
    end

    local textData = GetCustomTextData(frame)
    local percentText = textData.HealthPercentText
    local currentText = textData.HealthCurrentText
    local hideHealthText = ShouldHidePlayerHealthText()
    local isHovered = self:GetState(frame, "HealthTextHovered", false)

    if percentText and currentText then
        if hideHealthText then
            percentText:SetAlpha(0)
            currentText:SetAlpha(0)
        elseif isHovered then
            percentText:SetAlpha(0)
            currentText:SetAlpha(1)
        else
            percentText:SetAlpha(1)
            currentText:SetAlpha(0)
        end
    end

    local content = frame.PlayerFrameContent
    local contentContext = content and content.PlayerFrameContentContextual
    local playerRestLoop = contentContext and contentContext.PlayerRestLoop
    if not playerRestLoop then
        return
    end

    if hideHealthText then
        playerRestLoop:Show()
        if playerRestLoop.PlayerRestLoopAnim then
            playerRestLoop.PlayerRestLoopAnim:Play()
        end
    else
        playerRestLoop:Hide()
        if playerRestLoop.PlayerRestLoopAnim then
            playerRestLoop.PlayerRestLoopAnim:Stop()
        end
    end
end

local function UpdateCustomHPText(frame, unit)
    local textData = GetCustomTextData(frame)
    local percentText = textData.HealthPercentText
    local currentText = textData.HealthCurrentText
    if not percentText or not currentText then
        return
    end

    if not UnitIsConnected(unit) then
        RefineUI:SetFontStringValue(percentText, "OFFLINE")
        RefineUI:SetFontStringValue(currentText, "OFFLINE")
        percentText:SetTextColor(0.5, 0.5, 0.5)
        currentText:SetTextColor(0.5, 0.5, 0.5)
    elseif UnitIsDeadOrGhost(unit) then
        RefineUI:SetFontStringValue(percentText, "DEAD")
        RefineUI:SetFontStringValue(currentText, "DEAD")
        percentText:SetTextColor(0.5, 0.5, 0.5)
        currentText:SetTextColor(0.5, 0.5, 0.5)
    else
        local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
        local hp = UnitHealth(unit)
        RefineUI:SetFontStringValue(percentText, percent)
        RefineUI:SetFontStringValue(currentText, hp)
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
    RefineUI:SetFontStringValue(manaText, percent)
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

    -- PlayerFrame shows "vehicle" while driving; unit swaps and target/focus changes
    -- refresh through StyleFrame -> RefreshCustomText.
    local eventUnits = frame == PlayerFrame and PLAYER_FRAME_EVENT_UNITS or { unit }

    if not UnitFrames:GetState(hpContainer, "CustomTextEventsRegistered", false) then
        local function OnHealthEvent()
            UpdateCustomHPText(frame, frame.unit or "player")
            if frame == PlayerFrame then
                UnitFrames:UpdatePlayerRestPresentation(frame)
            end
        end

        UpdateCustomHPText(frame, unit)
        for _, eventUnit in ipairs(eventUnits) do
            RefineUI:OnUnitEvents(eventUnit, { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }, OnHealthEvent, "RefineUF_HP_" .. eventUnit)
        end

        UnitFrames:SetState(hpContainer, "CustomTextEventsRegistered", true)
    end

    if manaBar and not UnitFrames:GetState(manaBar, "CustomTextEventsRegistered", false) then
        textData.ManaBar = manaBar

        local function OnPowerEvent()
            UpdateCustomManaText(frame, manaBar, frame.unit or "player")
        end

        UpdateCustomManaText(frame, manaBar, unit)
        for _, eventUnit in ipairs(eventUnits) do
            RefineUI:OnUnitEvents(eventUnit, { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }, OnPowerEvent, "RefineUF_PP_" .. eventUnit)
        end

        UnitFrames:SetState(manaBar, "CustomTextEventsRegistered", true)
    end

    if not UnitFrames:GetState(frame, "RefineHoverHooked", false) then
        local function OnEnter()
            UnitFrames:SetState(frame, "HealthTextHovered", true)
            if frame == PlayerFrame then
                UnitFrames:UpdatePlayerRestPresentation(frame)
            else
                textData.HealthPercentText:SetAlpha(0)
                textData.HealthCurrentText:SetAlpha(1)
            end
            if textData.ManaPercentText then
                textData.ManaPercentText:SetAlpha(1)
            end
        end

        local function OnLeave()
            UnitFrames:SetState(frame, "HealthTextHovered", false)
            if frame == PlayerFrame then
                UnitFrames:UpdatePlayerRestPresentation(frame)
            else
                textData.HealthPercentText:SetAlpha(1)
                textData.HealthCurrentText:SetAlpha(0)
            end
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

    if frame == PlayerFrame then
        UnitFrames:UpdatePlayerRestPresentation(frame)
    end
end

function UnitFrames.RefreshCustomText(frame)
    local textData = UnitFrames:GetFrameData(frame).CustomText
    if not textData then
        return
    end

    local unit = frame.unit or "player"
    UpdateCustomHPText(frame, unit)
    if textData.ManaBar then
        UpdateCustomManaText(frame, textData.ManaBar, unit)
    end
end

----------------------------------------------------------------------------------------
-- Auras
----------------------------------------------------------------------------------------
-- 12.1 draws Target/Focus auras in a secure AuraContainer whose buttons addons cannot
-- style, so RefineUI switches that container off and draws its own CustomAuraContainer.
local AURA_LEVEL_OFFSET = 10
local AURA_COOLDOWN_OFFSET_X = 1.0
local AURA_COOLDOWN_OFFSET_Y = 1.5
local AURA_COOLDOWN_LEVEL_OFFSET = 50

local AuraFilters = AuraUtil.AuraFilters
local NOT_PLAYER = AuraUtil.AuraFilterNegationPrefix .. AuraFilters.Player

-- Player-cast auras use the large size, as in Blizzard's TargetFrameAuraContainer.
local AURA_GROUPS = {
    { key = "playerBuffs", filter = AuraUtil.CreateFilterString(AuraFilters.Helpful, AuraFilters.Player), large = true, harmful = false },
    { key = "buffs", filter = AuraUtil.CreateFilterString(AuraFilters.Helpful, NOT_PLAYER), harmful = false },
    { key = "playerDebuffs", filter = AuraUtil.CreateFilterString(AuraFilters.Harmful, AuraFilters.Player, AuraFilters.IncludeNameplateOnly), large = true, harmful = true },
    { key = "debuffs", filter = AuraUtil.CreateFilterString(AuraFilters.Harmful, NOT_PLAYER, AuraFilters.IncludeNameplateOnly), harmful = true },
}

local DISPEL_BORDER_OPTIONS = {
    showWhenHarmful = true,
    showWithoutDispelType = true,
    style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
}

-- Blizzard hides other players' debuffs on hostile NPCs.
local HOSTILE_NPC_DEBUFF_FILTERS = { isFromPlayerOrPlayerPet = false }

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

local function GetAuraSize(cfg, group)
    return group.large and cfg.LargeSize or cfg.Size
end

local function GetBuffBorderColor(cfg, group)
    return group.large and cfg.LargeBuffBorderColor or cfg.SmallBuffBorderColor
end

-- Aura buttons are restricted after creation, so all styling happens here.
local function InitializeAuraButton(frame, group, button)
    local cfg = UnitFrames.GetTargetFocusAuraConfig(frame)
    local size = GetAuraSize(cfg, group)
    button:SetSize(size, size)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", -AURA_COOLDOWN_OFFSET_X, AURA_COOLDOWN_OFFSET_Y)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", AURA_COOLDOWN_OFFSET_X, -AURA_COOLDOWN_OFFSET_Y)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)
    cooldown:SetSwipeTexture(Media.Textures.CooldownSwipeSmall)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetFrameLevel(button:GetFrameLevel() + AURA_COOLDOWN_LEVEL_OFFSET)
    button:SetDurationCooldown(cooldown)

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    button:SetApplicationCount(count)

    Auras.CreateManagedBorder(button)
    Auras.UpdateManagedBorder(button, size)

    if group.harmful then
        -- Blizzard colors the border by dispel type; the pieces become secret after this.
        local pieces = button.RefineManagedBorder.Pieces
        for index = 1, #pieces do
            button:AddDispelTypeTexture(pieces[index], DISPEL_BORDER_OPTIONS)
        end
    else
        Auras.SetManagedBorderColor(button, GetBuffBorderColor(cfg, group))
    end
end

-- Existing buttons are only accessible while auras are not secret. Debuff border
-- pieces are secret, so only the debuff button size follows.
local function RestyleAuraButtons(container, cfg)
    for _, group in ipairs(AURA_GROUPS) do
        local size = GetAuraSize(cfg, group)
        for index = 1, container:GetAuraGroupFrameCount(group.key) do
            local button = container:GetAuraGroupFrame(group.key, index)
            button:SetSize(size, size)
            if not group.harmful then
                Auras.UpdateManagedBorder(button, size)
                Auras.SetManagedBorderColor(button, GetBuffBorderColor(cfg, group))
            end
        end
    end
end

local function EnsureAuraState(frame)
    local data = UnitFrames:GetFrameData(frame)
    local state = data.TargetFocusAuras
    if state then
        return state
    end

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetFrameLevel(frame:GetFrameLevel() + AURA_LEVEL_OFFSET)
    container:SetUnit(frame.unit)
    for _, group in ipairs(AURA_GROUPS) do
        container:AddAuraGroup(group.key, group.filter, {
            initializeFrame = function(button)
                InitializeAuraButton(frame, group, button)
            end,
        })
    end

    state = { container = container }
    data.TargetFocusAuras = state
    return state
end

local function ApplyAuraLayout(frame, container, cfg, isFriend, growUp, hasToT, maxBuffs, maxDebuffs)
    local _, _, hpContainer = UnitFrames:GetFrameContainers(frame)
    local anchorPoint = growUp and "BOTTOMLEFT" or "TOPLEFT"

    container:ClearAllPoints()
    container:SetPoint(anchorPoint, hpContainer, growUp and "TOPLEFT" or "BOTTOMLEFT", cfg.OffsetX, growUp and cfg.OffsetY or -cfg.OffsetY)
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, growUp and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(hasToT and cfg.WrapWidthWithToT or cfg.WrapWidth)

    local onlyPlayerDebuffs = not isFriend and cfg.OnlyPlayerDebuffsOnEnemies
    for index, group in ipairs(AURA_GROUPS) do
        -- Friendly units lead with buffs, hostile units with debuffs. The other category
        -- starts a new line; flow layout skips empty groups, so both of its groups force it.
        local leads = group.harmful ~= isFriend
        local maxFrameCount = group.harmful and maxDebuffs or maxBuffs
        if onlyPlayerDebuffs and group.key == "debuffs" then
            maxFrameCount = 0
        end

        local size = GetAuraSize(cfg, group)
        container:SetAuraGroupMaxFrameCount(group.key, maxFrameCount)
        container:SetAuraGroupLayout(group.key, {
            elementSpacing = cfg.HorizontalSpacing,
            lineSpacing = cfg.VerticalSpacing,
            groupLineSpacing = cfg.GroupGap,
            forceNewLine = not leads,
            elementWidth = size,
            elementHeight = size,
            layoutIndex = leads and index or index + #AURA_GROUPS,
        })
    end
end

-- Runs after Blizzard's ConfigureAuraContainer (unit, friendliness, ToT, size changes).
function UnitFrames.UpdateUnitAuras(frame)
    local cfg = UnitFrames.GetTargetFocusAuraConfig(frame)
    local enabled = cfg.Enable ~= false
    local state = UnitFrames:GetFrameData(frame).TargetFocusAuras
    if not enabled and not state then
        return
    end
    state = state or EnsureAuraState(frame)

    local container = state.container
    if state.enabled ~= enabled then
        state.enabled = enabled
        frame:GetAuraContainer():SetEnabled(not enabled)
        container:SetShown(enabled)
    end
    if not enabled then
        return
    end

    local unit = frame.unit
    local isFriend = not UnitCanAttack("player", unit)
    local growUp = frame.buffsOnTop == true
    local hasToT = frame:IsTargetOfTargetShown()
    local maxBuffs = C_GameRules.IsGameRuleActive(Enum.GameRule.TargetFrameBuffsDisabled) and 0 or (frame.maxBuffs or MAX_TARGET_BUFFS)
    local maxDebuffs = frame.maxDebuffs or MAX_TARGET_DEBUFFS

    local hostileNPC = not isFriend and not UnitIsPlayer(unit) and not UnitIsOtherPlayersPet(unit)
    if state.hostileNPC ~= hostileNPC then
        state.hostileNPC = hostileNPC
        container:SetAuraGroupCandidateFilters("debuffs", hostileNPC and HOSTILE_NPC_DEBUFF_FILTERS or nil)
    end

    if state.layoutDirty ~= false
        or state.isFriend ~= isFriend
        or state.growUp ~= growUp
        or state.hasToT ~= hasToT
        or state.maxBuffs ~= maxBuffs
        or state.maxDebuffs ~= maxDebuffs then
        state.layoutDirty = false
        state.isFriend = isFriend
        state.growUp = growUp
        state.hasToT = hasToT
        state.maxBuffs = maxBuffs
        state.maxDebuffs = maxDebuffs
        ApplyAuraLayout(frame, container, cfg, isFriend, growUp, hasToT, maxBuffs, maxDebuffs)
    end

    if state.restylePending and not C_Secrets.ShouldAurasBeSecret() then
        state.restylePending = nil
        RestyleAuraButtons(container, cfg)
    end
end

-- Runs after Blizzard's UpdateAuras, which rebuilds auras for a new unit.
function UnitFrames.RefreshUnitAuras(frame)
    local state = UnitFrames:GetFrameData(frame).TargetFocusAuras
    if state and state.enabled then
        state.container:UpdateAllAuras()
    end
end

-- Settings changes from the Edit Mode aura layout window.
function UnitFrames.RefreshTargetFocusAuraLayout(frame)
    local state = UnitFrames:GetFrameData(frame).TargetFocusAuras
    if state then
        state.layoutDirty = true
        state.restylePending = true
    end
    UnitFrames.UpdateUnitAuras(frame)
end
