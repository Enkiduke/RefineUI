----------------------------------------------------------------------------------------
-- UnitFrames Component: Style
-- Description: Core styling pipeline for player, target, focus, and boss frames.
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
local InCombatLockdown = InCombatLockdown
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local ipairs = ipairs
local unpack = unpack

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = UnitFrames:GetPrivate()
local C = Private.Constants

local SELECTION_TOP_OFFSET = 6
local SELECTION_REGION_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "MouseOverHighlight" }

----------------------------------------------------------------------------------------
-- Layout Helpers
----------------------------------------------------------------------------------------
local function ApplyBossBarLayout(frameContainer, hpContainer, manaBar)
    if InCombatLockdown() or not frameContainer or not hpContainer or not manaBar then
        return
    end

    hpContainer:ClearAllPoints()
    hpContainer:SetPoint("BOTTOMRIGHT", frameContainer, "LEFT", RefineUI:Scale(148), RefineUI:Scale(2))
    RefineUI:SetPixelSize(hpContainer, C.BOSS_HEALTH_WIDTH, C.BOSS_HEALTH_HEIGHT)

    if hpContainer.HealthBar then
        hpContainer.HealthBar:ClearAllPoints()
        hpContainer.HealthBar:SetPoint("TOPLEFT", hpContainer, "TOPLEFT", 0, 0)
        RefineUI:SetPixelSize(hpContainer.HealthBar, C.BOSS_HEALTH_WIDTH, C.BOSS_HEALTH_HEIGHT)
    end

    manaBar:ClearAllPoints()
    manaBar:SetPoint("TOPRIGHT", hpContainer, "BOTTOMRIGHT", RefineUI:Scale(8), RefineUI:Scale(-1))
    RefineUI:SetPixelSize(manaBar, C.BOSS_MANA_WIDTH, C.BOSS_MANA_HEIGHT)
end

local function ApplyRaidTargetIconAnchor(frame, contentContext, hpContainer)
    if not UnitFrames:IsTargetFocusOrBossFrame(frame) or not contentContext then
        return
    end

    local raidTargetIcon = contentContext.RaidTargetIcon
    if not raidTargetIcon or not raidTargetIcon.SetPoint or not raidTargetIcon.ClearAllPoints then
        return
    end

    local healthBar = hpContainer and hpContainer.HealthBar

    local function AnchorRaidIcon(selfIcon)
        UnitFrames:WithStateGuard(selfIcon, "RaidTargetAnchor", function()
            selfIcon:ClearAllPoints()

            if frame == TargetFrame or frame == FocusFrame then
                if not healthBar then
                    return
                end

                if frame == TargetFrame then
                    selfIcon:SetPoint("LEFT", healthBar, "RIGHT", RefineUI:Scale(4), 0)
                    return
                end

                selfIcon:SetPoint("RIGHT", healthBar, "LEFT", RefineUI:Scale(-4), 0)
                return
            end

            selfIcon:SetPoint("RIGHT", frame, "LEFT", 0, 0)
        end)
    end

    RefineUI:HookOnce(UnitFrames:BuildHookKey(raidTargetIcon, "SetPoint:RaidTargetAnchor"), raidTargetIcon, "SetPoint", AnchorRaidIcon)
    AnchorRaidIcon(raidTargetIcon)
end

local anchoringSelection = false

local function AnchorSelectionRegion(selection, region, bar)
    if anchoringSelection or InCombatLockdown() then
        return
    end

    anchoringSelection = true
    region:ClearAllPoints()
    if region == selection.TopLeftCorner then
        region:SetPoint("TOPLEFT", bar, "TOPLEFT", RefineUI:Scale(-16), RefineUI:Scale(15) + SELECTION_TOP_OFFSET)
    elseif region == selection.TopRightCorner then
        region:SetPoint("TOPRIGHT", bar, "TOPRIGHT", RefineUI:Scale(15), RefineUI:Scale(15) + SELECTION_TOP_OFFSET)
    elseif region == selection.BottomLeftCorner then
        region:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", RefineUI:Scale(-16), RefineUI:Scale(-25))
    elseif region == selection.BottomRightCorner then
        region:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", RefineUI:Scale(15), RefineUI:Scale(-25))
    elseif region == selection.MouseOverHighlight then
        region:SetPoint("TOPLEFT", selection.TopLeftCorner, "TOPLEFT", RefineUI:Scale(8), RefineUI:Scale(-8))
        region:SetPoint("BOTTOMRIGHT", selection.BottomRightCorner, "BOTTOMRIGHT", RefineUI:Scale(-8), RefineUI:Scale(8))
    end
    anchoringSelection = false
end

local function HookSelectionHighlight(frame, bar)
    local selection = frame.Selection
    if not selection or not selection.TopLeftCorner or not bar then
        return
    end

    for _, key in ipairs(SELECTION_REGION_KEYS) do
        local region = selection[key]
        RefineUI:HookOnce(UnitFrames:BuildHookKey(region, "SetPoint:Selection"), region, "SetPoint", function(selfRegion)
            AnchorSelectionRegion(selection, selfRegion, bar)
        end)
    end
end

local function ApplySelectionHighlight(frame, bar)
    local selection = frame.Selection
    if not selection or not selection.TopLeftCorner or not bar then
        return
    end

    for _, key in ipairs(SELECTION_REGION_KEYS) do
        AnchorSelectionRegion(selection, selection[key], bar)
    end

    if selection.HorizontalLabel then
        selection.HorizontalLabel:ClearAllPoints()
        selection.HorizontalLabel:SetPoint("CENTER", selection.MouseOverHighlight, "CENTER", 0, 0)
    end
end

----------------------------------------------------------------------------------------
-- Dynamic Styling
----------------------------------------------------------------------------------------
-- Caches the unit colors so the per-update SetStatusBarColor hooks stay cheap.
-- Blizzard calls this path on unit, faction, and art changes.
function UnitFrames:ApplyDynamicStyle(frame)
    if not frame then
        return
    end

    if frame == PetFrame then
        self:ApplyPetFrameDynamicStyle(frame)
        return
    end

    local _, contentMain, hpContainer, manaBar = self:GetFrameContainers(frame)
    if not hpContainer or not manaBar then
        return
    end

    local data = self:GetFrameData(frame)
    local unit = frame.unit or "player"
    local hr, hg, hb = self.GetUnitHealthColor(unit)
    data.hr, data.hg, data.hb = hr, hg, hb
    data.isDead = UnitIsDeadOrGhost(unit)

    local healthBar = hpContainer.HealthBar
    healthBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
    healthBar:SetStatusBarDesaturated(true)
    healthBar:SetStatusBarColor(hr, hg, hb)

    manaBar:SetStatusBarTexture(C.TEXTURE_POWER_BAR)
    manaBar:SetStatusBarDesaturated(true)
    manaBar:SetStatusBarColor(self.GetUnitPowerColor(unit))

    if frame ~= PlayerFrame and contentMain.Name then
        contentMain.Name:SetTextColor(hr, hg, hb)
    end
end

----------------------------------------------------------------------------------------
-- Bar Shape
----------------------------------------------------------------------------------------
-- Blizzard resets masks and bar art in CheckClassification and PlayerFrame_To*Art,
-- often in combat. Everything here is a region, so it is safe to reapply in combat.
function UnitFrames:ApplyBarShape(frame)
    local refineUF = self:GetFrameData(frame).RefineUF
    if not refineUF then
        return
    end

    local _, _, hpContainer, manaBar = self:GetFrameContainers(frame)
    if not hpContainer or not manaBar then
        return
    end

    local isPlayer = frame == PlayerFrame
    local healthBar = hpContainer.HealthBar
    local showMana = manaBar:IsShown()

    local texture = refineUF.Texture
    texture:SetTexture(showMana and C.TEXTURE_FRAME or C.TEXTURE_FRAME_SMALL)
    RefineUI:SetPixelSize(texture, Config.UnitFrames.Layout.Width, 45)
    texture:ClearAllPoints()
    if isPlayer then
        texture:SetPoint("TOPLEFT", RefineUI:Scale(66), RefineUI:Scale(-38))
    elseif frame.isBossFrame or self:IsBossUnit(frame.unit) then
        texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-26))
    else
        texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-38))
    end

    local healthMask = hpContainer.HealthBarMask
    if healthMask then
        healthMask:SetTexture(C.MASK_HEALTH)
        healthMask:ClearAllPoints()
        if isPlayer then
            healthMask:SetPoint("TOPLEFT", healthBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(9))
            healthMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(34))
        else
            healthMask:SetPoint("TOPLEFT", healthBar, "TOPLEFT", RefineUI:Scale(-35), RefineUI:Scale(5))
            healthMask:SetSize(RefineUI:Scale(193), RefineUI:Scale(30))
        end
        healthBar:GetStatusBarTexture():AddMaskTexture(healthMask)
    end

    local manaMask = manaBar.ManaBarMask
    if manaMask then
        manaMask:SetTexture(C.MASK_MANA)
        manaMask:ClearAllPoints()
        if isPlayer then
            manaMask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", RefineUI:Scale(-34), RefineUI:Scale(7))
            manaMask:SetSize(RefineUI:Scale(192), RefineUI:Scale(25))
        else
            manaMask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(8))
            manaMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(28))
        end
        manaBar:GetStatusBarTexture():AddMaskTexture(manaMask)
    end

    local background = refineUF.Background
    background:ClearAllPoints()
    background:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    background:SetPoint("BOTTOMRIGHT", manaBar, "BOTTOMRIGHT", isPlayer and 0 or RefineUI:Scale(-10), showMana and 0 or RefineUI:Scale(11))
end

----------------------------------------------------------------------------------------
-- One-Time Setup
----------------------------------------------------------------------------------------
local function SetupFrame(frame, data, content, contentMain, hpContainer, manaBar)
    local hiddenFrame = RefineUI.HiddenFrame
    local contentContext = content.PlayerFrameContentContextual or content.TargetFrameContentContextual
    local healthBar = hpContainer.HealthBar
    local isPlayer = frame == PlayerFrame
    local isTargetOrFocus = frame == TargetFrame or frame == FocusFrame

    RefineUI:HookOnce(UnitFrames:BuildHookKey(healthBar, "SetStatusBarColor:Health"), healthBar, "SetStatusBarColor", function(selfBar, r, g, b)
        local hr, hg, hb = data.hr, data.hg, data.hb
        if hr and (r ~= hr or g ~= hg or b ~= hb) then
            selfBar:SetStatusBarColor(hr, hg, hb)
        end
    end)
    RefineUI:HookOnce(UnitFrames:BuildHookKey(manaBar, "SetStatusBarColor:Power"), manaBar, "SetStatusBarColor", function(selfBar, r, g, b)
        local pr, pg, pb = UnitFrames.GetUnitPowerColor(frame.unit or "player")
        if r ~= pr or g ~= pg or b ~= pb then
            selfBar:SetStatusBarColor(pr, pg, pb)
        end
    end)
    RefineUI:HookOnce(UnitFrames:BuildHookKey(manaBar, "SetStatusBarTexture:Power"), manaBar, "SetStatusBarTexture", function(selfBar, texture)
        if texture ~= C.TEXTURE_POWER_BAR then
            selfBar:SetStatusBarTexture(C.TEXTURE_POWER_BAR)
            selfBar:SetStatusBarDesaturated(true)
        end
    end)
    RefineUI:HookOnce(UnitFrames:BuildHookKey(healthBar, "SetStatusBarTexture:Health"), healthBar, "SetStatusBarTexture", function(selfBar, texture)
        if texture ~= C.TEXTURE_HEALTH_BAR then
            selfBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
            selfBar:SetStatusBarDesaturated(true)
        end
    end)

    if isPlayer then
        frame.PlayerFrameContainer:SetParent(hiddenFrame)
    end

    -- StatusTexture keeps its Show hook so Blizzard's per-frame rest/combat pulse stays idle.
    UnitFrames:EnforceHiddenRegion(contentMain.StatusTexture, nil)
    UnitFrames:EnforceHiddenRegion(contentMain.ReputationColor, hiddenFrame)
    UnitFrames:EnforceHiddenRegion(contentMain.HitIndicator, hiddenFrame)

    if contentContext then
        UnitFrames:EnforceHiddenRegion(contentContext.PlayerPortraitCornerIcon, hiddenFrame)
        UnitFrames:EnforceHiddenRegion(contentContext.AttackIcon, hiddenFrame)
        UnitFrames:EnforceHiddenRegion(contentContext.PrestigeBadge, hiddenFrame)
        UnitFrames:EnforceHiddenRegion(contentContext.PrestigePortrait, hiddenFrame)
        UnitFrames:EnforceHiddenRegion(contentContext.LeaderIcon, nil)
        UnitFrames:EnforceHiddenRegion(contentContext.GuideIcon, nil)

        if isPlayer then
            UnitFrames:EnforceHiddenRegion(contentContext.GroupIndicator, hiddenFrame)
            UnitFrames:EnforceHiddenRegion(contentContext.RoleIcon, hiddenFrame)

            if contentContext.PlayerRestLoop then
                contentContext.PlayerRestLoop:ClearAllPoints()
                contentContext.PlayerRestLoop:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
                contentContext.PlayerRestLoop:SetScale(0.5)
            end
        elseif isTargetOrFocus then
            UnitFrames:EnforceHiddenRegion(contentContext.QuestIcon, hiddenFrame)
            UnitFrames:EnforceHiddenRegion(contentContext.HighLevelTexture, hiddenFrame)
        end
    end

    ApplyRaidTargetIconAnchor(frame, contentContext, hpContainer)
    UnitFrames:EnsureTooltipHooks(frame)

    local refineUF = CreateFrame("Frame", nil, frame)
    refineUF:SetFrameStrata("HIGH")
    refineUF:SetAllPoints(frame)

    refineUF.Texture = refineUF:CreateTexture(nil, "OVERLAY")
    if Config.General.BorderColor then
        refineUF.Texture:SetVertexColor(unpack(Config.General.BorderColor))
    end

    refineUF.Background = frame:CreateTexture(nil, "BACKGROUND")
    refineUF.Background:SetTexture(C.TEXTURE_BACKGROUND)
    refineUF.Background:SetVertexColor(0.5, 0.5, 0.5, 1)

    local bgMask = refineUF:CreateMaskTexture()
    bgMask:SetAllPoints(refineUF.Background)
    bgMask:SetTexture(C.MASK_FRAME, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    refineUF.Background:AddMaskTexture(bgMask)

    data.RefineUF = refineUF

    if UnitFrames.CreateCustomText then
        UnitFrames.CreateCustomText(frame)
    end

    local level = contentMain.LevelText
    if isPlayer and not level then
        level = _G.PlayerLevelText
    end
    if level then
        UnitFrames:EnforceHiddenRegion(level, hiddenFrame)
        if isPlayer then
            RefineUI:HookOnce(UnitFrames:BuildHookKey(level, "SetParent:Hidden"), level, "SetParent", function(selfLevel, parent)
                if parent ~= hiddenFrame then
                    selfLevel:SetParent(hiddenFrame)
                end
            end)
        end
    end

    local name = contentMain.Name or (isPlayer and frame.name)
    if name then
        if isPlayer then
            UnitFrames:EnforceHiddenRegion(name, hiddenFrame)
        else
            local cfg = Config.UnitFrames.Fonts
            name:SetParent(refineUF)
            name:ClearAllPoints()
            name:SetPoint("BOTTOM", hpContainer, "TOP", 0, 0)
            name:SetJustifyH("CENTER")
            name:SetWordWrap(false)
            if cfg.NameWidth then
                name:SetWidth(cfg.NameWidth)
            end
            if cfg.NameSize then
                RefineUI.Font(name, cfg.NameSize)
            end

            RefineUI:HookOnce(UnitFrames:BuildHookKey(name, "SetWidth:Styled"), name, "SetWidth", function(selfName, width)
                if cfg.NameWidth and width ~= cfg.NameWidth then
                    selfName:SetWidth(cfg.NameWidth)
                end
            end)
            RefineUI:HookOnce(UnitFrames:BuildHookKey(name, "SetWordWrap:Styled"), name, "SetWordWrap", function(selfName, wrap)
                if wrap ~= false then
                    selfName:SetWordWrap(false)
                end
            end)
            RefineUI:HookOnce(UnitFrames:BuildHookKey(name, "SetPoint:Styled"), name, "SetPoint", function(selfName)
                UnitFrames:WithStateGuard(selfName, "NameAnchor", function()
                    selfName:ClearAllPoints()
                    selfName:SetPoint("BOTTOM", hpContainer, "TOP", 0, 0)
                end)
            end)
            RefineUI:HookOnce(UnitFrames:BuildHookKey(name, "SetTextColor:Styled"), name, "SetTextColor", function(selfName, r, g, b)
                local hr, hg, hb = data.hr, data.hg, data.hb
                if hr and (r ~= hr or g ~= hg or b ~= hb) then
                    selfName:SetTextColor(hr, hg, hb)
                end
            end)
        end
    end

    HookSelectionHighlight(frame, healthBar)

    local castBar
    if isPlayer then
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
    if castBar and UnitFrames.StyleCastBar then
        UnitFrames:StyleCastBar(castBar, frame)
    end

    if isTargetOrFocus and UnitFrames.UpdateUnitAuras then
        RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "ConfigureAuraContainer:Styled"), frame, "ConfigureAuraContainer", UnitFrames.UpdateUnitAuras)
        RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "UpdateAuras:Styled"), frame, "UpdateAuras", UnitFrames.RefreshUnitAuras)
    end
end

----------------------------------------------------------------------------------------
-- Static Layout
----------------------------------------------------------------------------------------
local function ApplyStaticLayout(frame, hpContainer, manaBar)
    local isPlayer = frame == PlayerFrame
    local ownsScaleViaEditMode = isPlayer or frame == TargetFrame or frame == FocusFrame
    if not ownsScaleViaEditMode and Config.UnitFrames.Scale and frame:GetScale() ~= Config.UnitFrames.Scale then
        frame:SetScale(Config.UnitFrames.Scale)
    end

    if not isPlayer then
        local frameContainer = frame.TargetFrameContainer
        if frame.isBossFrame or UnitFrames:IsBossUnit(frame.unit) then
            ApplyBossBarLayout(frameContainer, hpContainer, manaBar)
        end
        frameContainer:SetAlpha(0)
        frameContainer:Hide()
    end

    ApplySelectionHighlight(frame, hpContainer.HealthBar)

    if isPlayer then
        UnitFrames:EnsurePlayerSecondaryManaOverlay(frame, manaBar)

        if UnitFrames.UpdatePlayerRestPresentation then
            UnitFrames:UpdatePlayerRestPresentation(frame)
        end

        if UnitFrames.CreateClassResources then
            UnitFrames:CreateClassResources(frame)
        end

        local managed = _G.PlayerBottomManagedFrameContainer
        if managed then
            managed:SetParent(RefineUI.HiddenFrame)
            managed:SetAlpha(0)
            managed:Hide()
        end
    elseif (frame == TargetFrame or frame == FocusFrame) and UnitFrames.UpdateUnitAuras then
        UnitFrames.UpdateUnitAuras(frame)
    end
end

----------------------------------------------------------------------------------------
-- Style Pipeline
----------------------------------------------------------------------------------------
function UnitFrames:StyleFrame(frame)
    if not frame then
        return
    end

    if frame == PetFrame then
        self:StylePetFrame(frame)
        return
    end

    local content, contentMain, hpContainer, manaBar = self:GetFrameContainers(frame)
    if not hpContainer or not manaBar then
        return
    end

    self:ApplyDynamicStyle(frame)

    if InCombatLockdown() then
        self:ApplyBarShape(frame)
        if self.RefreshCustomText then
            self.RefreshCustomText(frame)
        end
        self:QueueStaticStyle(frame)
        return
    end

    Private.PendingStaticStyleFrames[frame] = nil
    local data = self:GetFrameData(frame)
    if not data.RefineUF then
        SetupFrame(frame, data, content, contentMain, hpContainer, manaBar)
    end

    ApplyStaticLayout(frame, hpContainer, manaBar)
    self:ApplyBarShape(frame)
    if self.RefreshCustomText then
        self.RefreshCustomText(frame)
    end
end
