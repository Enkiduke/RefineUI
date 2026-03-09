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
local type = type
local pairs = pairs
local unpack = unpack

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local Private = UnitFrames:GetPrivate()
local C = Private.Constants

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

local function ApplyRaidTargetIconAnchor(frame, contentContext)
    if not UnitFrames:IsTargetFocusOrBossFrame(frame) or not contentContext then
        return
    end

    local raidTargetIcon = contentContext.RaidTargetIcon
    if not raidTargetIcon or not raidTargetIcon.SetPoint or not raidTargetIcon.ClearAllPoints then
        return
    end

    local function AnchorRaidIcon(selfIcon)
        UnitFrames:WithStateGuard(selfIcon, "RaidTargetAnchor", function()
            selfIcon:ClearAllPoints()
            selfIcon:SetPoint("RIGHT", frame, "LEFT", 0, 0)
        end)
    end

    RefineUI:HookOnce(UnitFrames:BuildHookKey(raidTargetIcon, "SetPoint:RaidTargetAnchor"), raidTargetIcon, "SetPoint", AnchorRaidIcon)
    AnchorRaidIcon(raidTargetIcon)
end

local function ApplySelectionHighlight(frame, bar)
    if not frame.Selection or not frame.Selection.TopLeftCorner or not bar then
        return
    end

    local xOffsetLeft = 0
    local xOffsetRight = 0
    local yOffsetBottom = 0
    local yOffsetTop = 6

    local function AnchorSelectionRegions()
        if InCombatLockdown() then
            return
        end

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

    AnchorSelectionRegions()

    local secureHooked = {
        frame.Selection.TopLeftCorner,
        frame.Selection.TopRightCorner,
        frame.Selection.BottomLeftCorner,
        frame.Selection.BottomRightCorner,
        frame.Selection.MouseOverHighlight,
    }

    for _, region in pairs(secureHooked) do
        RefineUI:HookOnce(UnitFrames:BuildHookKey(region, "SetPoint:Selection"), region, "SetPoint", function(selfRegion)
            if InCombatLockdown() then
                return
            end

            UnitFrames:WithStateGuard(selfRegion, "SelectionAnchor", function()
                selfRegion:ClearAllPoints()
                if selfRegion == frame.Selection.TopLeftCorner then
                    selfRegion:SetPoint("TOPLEFT", bar, "TOPLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(15) + yOffsetTop)
                elseif selfRegion == frame.Selection.TopRightCorner then
                    selfRegion:SetPoint("TOPRIGHT", bar, "TOPRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(15) + yOffsetTop)
                elseif selfRegion == frame.Selection.BottomLeftCorner then
                    selfRegion:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", RefineUI:Scale(-16) + xOffsetLeft, RefineUI:Scale(-25) + yOffsetBottom)
                elseif selfRegion == frame.Selection.BottomRightCorner then
                    selfRegion:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", RefineUI:Scale(15) + xOffsetRight, RefineUI:Scale(-25) + yOffsetBottom)
                elseif selfRegion == frame.Selection.MouseOverHighlight then
                    selfRegion:SetPoint("TOPLEFT", frame.Selection.TopLeftCorner, "TOPLEFT", RefineUI:Scale(8), RefineUI:Scale(-8))
                    selfRegion:SetPoint("BOTTOMRIGHT", frame.Selection.BottomRightCorner, "BOTTOMRIGHT", RefineUI:Scale(-8), RefineUI:Scale(8))
                end
            end)
        end)
    end
end

----------------------------------------------------------------------------------------
-- Dynamic Styling
----------------------------------------------------------------------------------------
function UnitFrames:ApplyDynamicStyle(frame)
    if not frame then
        return
    end

    if frame == PetFrame then
        self:ApplyPetFrameDynamicStyle(frame)
        return
    end

    local unit = frame.unit or "player"
    local _, contentMain, hpContainer, manaBar = self:GetFrameContainers(frame)
    if not hpContainer or not manaBar then
        return
    end

    if hpContainer.HealthBar then
        hpContainer.HealthBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
        hpContainer.HealthBar:SetStatusBarDesaturated(true)
        local hr, hg, hb = self.GetUnitHealthColor(unit)
        hpContainer.HealthBar:SetStatusBarColor(hr, hg, hb)
    end

    manaBar:SetStatusBarTexture(C.TEXTURE_POWER_BAR)
    manaBar:SetStatusBarDesaturated(true)
    local pr, pg, pb = self.GetUnitPowerColor(unit)
    manaBar:SetStatusBarColor(pr, pg, pb)

    if contentMain and frame ~= PlayerFrame and contentMain.Name then
        local nr, ng, nb = self.GetUnitHealthColor(unit)
        contentMain.Name:SetTextColor(nr, ng, nb)
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

    if InCombatLockdown() then
        self:QueueStaticStyle(frame)
        self:ApplyDynamicStyle(frame)
        return
    end

    Private.PendingStaticStyleFrames[frame] = nil
    local data = self:GetFrameData(frame)
    local unit = frame.unit or "player"
    local isBossFrame = frame.isBossFrame or self:IsBossUnit(unit)

    if Config.UnitFrames.Scale and frame:GetScale() ~= Config.UnitFrames.Scale then
        frame:SetScale(Config.UnitFrames.Scale)
    end

    local cfg = Config.UnitFrames.Fonts
    local frameContainer = frame.PlayerFrameContainer or frame.TargetFrameContainer
    local content, contentMain, hpContainer, manaBar = self:GetFrameContainers(frame)
    if not hpContainer or not manaBar then
        return
    end

    local contentContext = content and (content.PlayerFrameContentContextual or content.TargetFrameContentContextual)
    local hiddenFrame = RefineUI.HiddenFrame

    if isBossFrame then
        ApplyBossBarLayout(frameContainer, hpContainer, manaBar)
    end

    if hpContainer.HealthBar then
        hpContainer.HealthBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
        hpContainer.HealthBar:SetStatusBarDesaturated(true)
    end
    manaBar:SetStatusBarTexture(C.TEXTURE_POWER_BAR)
    manaBar:SetStatusBarDesaturated(true)

    local hr, hg, hb = self.GetUnitHealthColor(unit)
    hpContainer.HealthBar:SetStatusBarColor(hr, hg, hb)
    RefineUI:HookOnce(self:BuildHookKey(hpContainer.HealthBar, "SetStatusBarColor:Health"), hpContainer.HealthBar, "SetStatusBarColor", function(selfBar, r1, g1, b1)
        local r2, g2, b2 = UnitFrames.GetUnitHealthColor(unit)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then
            selfBar:SetStatusBarColor(r2, g2, b2)
        end
    end)

    local pr, pg, pb = self.GetUnitPowerColor(unit)
    manaBar:SetStatusBarColor(pr, pg, pb)
    RefineUI:HookOnce(self:BuildHookKey(manaBar, "SetStatusBarColor:Power"), manaBar, "SetStatusBarColor", function(selfBar, r1, g1, b1)
        local r2, g2, b2 = UnitFrames.GetUnitPowerColor(unit)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then
            selfBar:SetStatusBarColor(r2, g2, b2)
        end
    end)
    RefineUI:HookOnce(self:BuildHookKey(manaBar, "SetStatusBarTexture:Power"), manaBar, "SetStatusBarTexture", function(selfBar, texture)
        if texture ~= C.TEXTURE_POWER_BAR then
            selfBar:SetStatusBarTexture(C.TEXTURE_POWER_BAR)
            selfBar:SetStatusBarDesaturated(true)
        end
    end)
    RefineUI:HookOnce(self:BuildHookKey(hpContainer.HealthBar, "SetStatusBarTexture:Health"), hpContainer.HealthBar, "SetStatusBarTexture", function(selfBar, texture)
        if texture ~= C.TEXTURE_HEALTH_BAR then
            selfBar:SetStatusBarTexture(C.TEXTURE_HEALTH_BAR)
            selfBar:SetStatusBarDesaturated(true)
        end
    end)

    if data.RefineStyle then
        data.RefineStyle:SetAlpha(0)
        data.RefineStyle:Hide()
    end

    if frame == PlayerFrame then
        if not InCombatLockdown() then
            frameContainer:SetParent(hiddenFrame)
        end
    else
        frameContainer:SetAlpha(0)
        frameContainer:Hide()
    end

    if contentMain and contentMain.StatusTexture then
        self:EnforceHiddenRegion(contentMain.StatusTexture, hiddenFrame)
    end
    if contentContext and contentContext.PlayerPortraitCornerIcon then
        self:EnforceHiddenRegion(contentContext.PlayerPortraitCornerIcon, hiddenFrame)
    end
    if contentMain and contentMain.ReputationColor then
        self:EnforceHiddenRegion(contentMain.ReputationColor, hiddenFrame)
    end
    if contentMain and contentMain.HitIndicator then
        self:EnforceHiddenRegion(contentMain.HitIndicator, hiddenFrame)
    end

    if contentContext then
        for _, icon in pairs({ contentContext.LeaderIcon, contentContext.GuideIcon }) do
            if icon then
                self:EnforceHiddenRegion(icon, nil)
            end
        end
    end

    ApplyRaidTargetIconAnchor(frame, contentContext)

    if contentContext then
        self:EnforceHiddenRegion(contentContext.AttackIcon, hiddenFrame)
        if frame == TargetFrame or frame == FocusFrame then
            self:EnforceHiddenRegion(contentContext.QuestIcon, hiddenFrame)
        end
    end

    if contentContext then
        self:EnforceHiddenRegion(contentContext.PrestigeBadge, hiddenFrame)
        self:EnforceHiddenRegion(contentContext.PrestigePortrait, hiddenFrame)

        if frame == TargetFrame or frame == FocusFrame then
            self:EnforceHiddenRegion(contentContext.HighLevelTexture, hiddenFrame)
        end
    end

    self:EnsureTooltipHooks(frame)

    if not data.RefineUF then
        data.RefineUF = CreateFrame("Frame", nil, frame)
        data.RefineUF:SetFrameStrata("HIGH")
        data.RefineUF:SetAllPoints(frame)

        data.RefineUF.Texture = data.RefineUF:CreateTexture(nil, "OVERLAY")
        RefineUI:SetPixelSize(data.RefineUF.Texture, Config.UnitFrames.Layout.Width, 46)

        data.RefineUF.Background = frame:CreateTexture(nil, "BACKGROUND")
        data.RefineUF.Background:SetTexture(C.TEXTURE_BACKGROUND)
        data.RefineUF.Background:SetVertexColor(0.5, 0.5, 0.5, 1)
    end

    local refineUF = data.RefineUF
    local showMana = manaBar:IsShown()
    local bgYOffset = 0

    if not showMana then
        refineUF.Texture:SetTexture(C.TEXTURE_FRAME_SMALL)
        RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 46)
        bgYOffset = RefineUI:Scale(11)
    else
        refineUF.Texture:SetTexture(C.TEXTURE_FRAME)
        RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 46)
    end

    if Config.General.BorderColor then
        refineUF.Texture:SetVertexColor(unpack(Config.General.BorderColor))
    end

    RefineUI:SetPixelSize(refineUF.Texture, Config.UnitFrames.Layout.Width, 45)

    if frame == PlayerFrame then
        refineUF.Texture:ClearAllPoints()
        refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(66), RefineUI:Scale(-38))
        if hpContainer.HealthBarMask then
            hpContainer.HealthBarMask:SetTexture(C.MASK_HEALTH)
            hpContainer.HealthBarMask:ClearAllPoints()
            hpContainer.HealthBarMask:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(9))
            hpContainer.HealthBarMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(34))
            if hpContainer.HealthBar:GetStatusBarTexture() then
                hpContainer.HealthBar:GetStatusBarTexture():AddMaskTexture(hpContainer.HealthBarMask)
            end
        end

        if manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetTexture(C.MASK_MANA)
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
        refineUF.Texture:ClearAllPoints()
        if isBossFrame then
            refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-26))
        else
            refineUF.Texture:SetPoint("TOPLEFT", RefineUI:Scale(2), RefineUI:Scale(-38))
        end

        if hpContainer.HealthBarMask then
            hpContainer.HealthBarMask:SetTexture(C.MASK_HEALTH)
            hpContainer.HealthBarMask:SetSize(RefineUI:Scale(193), RefineUI:Scale(30))
            hpContainer.HealthBarMask:ClearAllPoints()
            hpContainer.HealthBarMask:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", RefineUI:Scale(-35), RefineUI:Scale(5))
            if hpContainer.HealthBar:GetStatusBarTexture() then
                hpContainer.HealthBar:GetStatusBarTexture():AddMaskTexture(hpContainer.HealthBarMask)
            end
        end

        if manaBar.ManaBarMask then
            manaBar.ManaBarMask:SetTexture(C.MASK_MANA)
            manaBar.ManaBarMask:SetSize(RefineUI:Scale(190), RefineUI:Scale(28))
            manaBar.ManaBarMask:ClearAllPoints()
            manaBar.ManaBarMask:SetPoint("TOPLEFT", manaBar, "TOPLEFT", RefineUI:Scale(-33), RefineUI:Scale(8))
            if manaBar:GetStatusBarTexture() then
                manaBar:GetStatusBarTexture():AddMaskTexture(manaBar.ManaBarMask)
            end
        end
    end

    refineUF.Background:ClearAllPoints()
    refineUF.Background:SetPoint("TOPLEFT", hpContainer.HealthBar, "TOPLEFT", 0, 0)
    refineUF.Background:SetPoint("BOTTOMRIGHT", manaBar, "BOTTOMRIGHT", (frame == PlayerFrame and 0 or RefineUI:Scale(-10)), bgYOffset)

    if not data.BgMask then
        data.BgMask = refineUF:CreateMaskTexture()
        data.BgMask:SetAllPoints(refineUF.Background)
        data.BgMask:SetTexture(C.MASK_FRAME, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        refineUF.Background:AddMaskTexture(data.BgMask)
    end

    if frame == PlayerFrame then
        self:EnsurePlayerSecondaryManaOverlay(frame, manaBar)
    end

    if self.CreateCustomText and not data.customTextCreated then
        self.CreateCustomText(frame)
        data.customTextCreated = true
    end

    local level = contentMain.LevelText
    if frame == PlayerFrame and not level then
        level = _G.PlayerLevelText
    end

    if level then
        if frame == PlayerFrame then
            if not InCombatLockdown() then
                level:SetParent(hiddenFrame)
            end
            level:Hide()
            RefineUI:HookOnce(self:BuildHookKey(level, "Show:Hidden"), level, "Show", function(selfLevel)
                selfLevel:Hide()
            end)
            if not InCombatLockdown() then
                RefineUI:HookOnce(self:BuildHookKey(level, "SetParent:Hidden"), level, "SetParent", function(selfLevel, parent)
                    if parent ~= hiddenFrame then
                        selfLevel:SetParent(hiddenFrame)
                    end
                end)
            end
        else
            self:EnforceHiddenRegion(level, hiddenFrame)
        end
    end

    local name = contentMain.Name or (frame == PlayerFrame and frame.name)
    if name then
        if frame == PlayerFrame then
            self:EnforceHiddenRegion(name, hiddenFrame)
            RefineUI:HookOnce(self:BuildHookKey(name, "SetText:Hidden"), name, "SetText", function(selfName)
                selfName:SetAlpha(0)
            end)
        else
            local r, g, b = self.GetUnitHealthColor(unit)
            name:SetTextColor(r, g, b)
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

            RefineUI:HookOnce(self:BuildHookKey(name, "SetWidth:Styled"), name, "SetWidth", function(selfName, width)
                if cfg.NameWidth and width ~= cfg.NameWidth then
                    selfName:SetWidth(cfg.NameWidth)
                end
            end)
            RefineUI:HookOnce(self:BuildHookKey(name, "SetWordWrap:Styled"), name, "SetWordWrap", function(selfName, wrap)
                if wrap ~= false then
                    selfName:SetWordWrap(false)
                end
            end)
            RefineUI:HookOnce(self:BuildHookKey(name, "SetPoint:Styled"), name, "SetPoint", function(selfName)
                UnitFrames:WithStateGuard(selfName, "NameAnchor", function()
                    selfName:ClearAllPoints()
                    selfName:SetPoint("BOTTOM", hpContainer, "TOP", 0, 0)
                end)
            end)
            RefineUI:HookOnce(self:BuildHookKey(name, "SetTextColor:Styled"), name, "SetTextColor", function(selfName, r1, g1, b1)
                local r2, g2, b2 = UnitFrames.GetUnitHealthColor(unit)
                if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then
                    selfName:SetTextColor(r2, g2, b2)
                end
            end)
        end
    end

    ApplySelectionHighlight(frame, hpContainer.HealthBar)

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
    if castBar and self.StyleCastBar then
        self:StyleCastBar(castBar, frame)
    end

    if frame == PlayerFrame then
        if self.CreateClassResources then
            self:CreateClassResources(frame)
        end

        local managed = _G.PlayerFrameBottomManagedFramesContainer
        if managed then
            if not InCombatLockdown() then
                managed:SetParent(hiddenFrame)
            end
            managed:SetAlpha(0)
            managed:Hide()
        end
    end

    if (frame == TargetFrame or frame == FocusFrame) and self.UpdateUnitAuras then
        self.UpdateUnitAuras(frame)
        RefineUI:HookOnce(self:BuildHookKey(frame, "UpdateAuras:Styled"), frame, "UpdateAuras", UnitFrames.UpdateUnitAuras)
    end
end
