----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
local NP = R.NP or {}
R.NP = NP

-- Upvalue globals for efficiency
local CreateFrame, hooksecurefunc, UIParent = CreateFrame, hooksecurefunc, UIParent
local UnitIsFriend, UnitIsPlayer, UnitClass, UnitCanAttack, UnitIsUnit = UnitIsFriend, UnitIsPlayer, UnitClass,
    UnitCanAttack, UnitIsUnit
local GetTime, select, unpack = GetTime, select, unpack
local C_NamePlate = C_NamePlate
local GetNamePlateForUnit, GetNamePlates = C_NamePlate.GetNamePlateForUnit, C_NamePlate.GetNamePlates

-- Upvalue commonly used textures from settings to avoid repeated table lookups
local TEX_HEALTH = C.media.healthBar
local TEX_HEALTH_BG = C.media.healthBackground
local TEX_HEALTH_MASK = C.media.nameplateHealthMask
local TEX_CASTBAR = C.media.castbarTexture
local TEX_NP_GLOW = C.media.nameplateGlow
local TEX_TGT_R = C.media.targetIndicatorRight
local TEX_TGT_L = C.media.targetIndicatorLeft
local TEX_PORTRAIT_BORDER = C.media.portraitBorder
local TEX_PORTRAIT_MASK = C.media.portraitMask
local TEX_PORTRAIT_BG = C.media.portraitBackground
local TEX_PORTRAIT_GLOW = C.media.portraitGlow

-- No local helpers; use shared NP.CreateBorderFrame to avoid duplication

-- Dynamically position CC and Cast bars so CC sits above Cast when both are visible (both remain below Health)
function NP.UpdateBarsLayout(parent)
    if not parent then return end
    local health = parent.Health
    local cast = parent.Castbar
    local cc = parent.CrowdControl
    if not health then return end

    local gap = 2

    -- Clear anchors we control
    if cc then cc:ClearAllPoints() end
    if cast then cast:ClearAllPoints() end

    local ccShown = cc and cc:IsShown()
    local castShown = cast and cast:IsShown()

    if ccShown then
        -- CC bar directly under health
        cc:SetPoint("TOP", health, "BOTTOM", 0, gap)
        -- Overlap cast at the same anchor so CC visually covers it (CC has higher frame level)
        if cast then
            cast:SetPoint("TOP", health, "BOTTOM", 0, gap)
            -- Hide cast text/time to avoid showing through under the CC bar
            if cast.Text and cast.Text:IsShown() then cast.Text:Hide() end
            if cast.Time and cast.Time:IsShown() then cast.Time:Hide() end
        end
    else
        -- No CC: cast sits right under health (original layout)
        if cast then
            cast:SetPoint("TOP", health, "BOTTOM", 0, gap)
            -- Ensure cast text/time are visible again when CC isn't showing
            -- But don't force-show them if they were intentionally hidden (e.g., during interrupt hold)
            if cast.Text and not cast.Text:IsShown() and not cast._textHiddenByInterrupt then cast.Text:Show() end
            if cast.Time and not cast.Time:IsShown() and not cast._timeHiddenByInterrupt then cast.Time:Show() end
        end
        -- Keep CC anchored to health when hidden for consistency
        if cc then cc:SetPoint("TOP", health, "BOTTOM", 0, gap) end
    end
end

----------------------------------------------------------------------------------------
-- Nameplate Configuration
----------------------------------------------------------------------------------------


-- Nameplate configuration function
function NP.ConfigureNameplate(self, unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    self:SetPoint("CENTER", nameplate, "CENTER")
    self:SetSize(C.nameplate.width, C.nameplate.height)

    -- Target updates are centralized; no per-plate target event registration here

    -- Disable movement via /moveui
    self.disableMovement = true

    -- Hide Blizzard Power Bar (hook once)
    local NamePlateDriverFrame = rawget(_G, 'NamePlateDriverFrame')
    if NamePlateDriverFrame and not NP._classBarHooked then
        hooksecurefunc(NamePlateDriverFrame, "SetupClassNameplateBars", function(frame)
            if frame and not frame:IsForbidden() and frame.classNamePlatePowerBar then
                frame.classNamePlatePowerBar:Hide()
                frame.classNamePlatePowerBar:UnregisterAllEvents()
            end
        end)
        NP._classBarHooked = true
    end

    -- Ensure no stale target visuals persist when the plate hides
    if not self._clearOnHideHooked then
        self:HookScript("OnHide", function(frame)
            if NP and NP.ClearTargetVisuals then
                NP.ClearTargetVisuals(frame)
            end
        end)
        self._clearOnHideHooked = true
    end

    -- Sync target visuals on show to avoid stale reuse
    if not self._syncOnShowHooked then
        self:HookScript("OnShow", function(frame)
            if NP and NP.UpdateTarget then
                NP.UpdateTarget(frame)
            end
        end)
        self._syncOnShowHooked = true
    end
end

----------------------------------------------------------------------------------------
-- Health Bar
----------------------------------------------------------------------------------------
function NP.CreateHealthBar(self)
    self.Health = CreateFrame("StatusBar", nil, self)
    self.Health:SetAllPoints(self)
    -- Ensure health sits above other plate elements; frame level relative to the parent plate
    local parentLevel = self:GetFrameLevel() or 0
    self.Health:SetFrameLevel(parentLevel + 3)
    self.Health:SetFrameStrata("MEDIUM")
    self.Health:SetStatusBarTexture(TEX_HEALTH)
    self.Health.colorTapping = true
    self.Health.colorDisconnected = true
    self.Health.colorClass = true
    self.Health.colorReaction = true
    self.Health.colorHealth = true
    self.Health.Smooth = true
    NP.CreateBorderFrame(self.Health)

    self.Health.bg = self.Health:CreateTexture(nil, "BORDER")
    self.Health.bg:SetTexture(TEX_HEALTH_BG)
    -- Slightly inset so square corners don't show beyond the masked foreground/bar border
    self.Health.bg:ClearAllPoints()
    self.Health.bg:SetPoint("TOPLEFT", self.Health, "TOPLEFT", 1, -1)
    self.Health.bg:SetPoint("BOTTOMRIGHT", self.Health, "BOTTOMRIGHT", -1, 1)
    -- avoid injecting custom fields on Texture to satisfy linter; use a local factor when needed

    self.Health.mask = self.Health:CreateMaskTexture()
    self.Health.mask:SetTexture(TEX_HEALTH_MASK)
    self.Health.mask:SetPoint("TOPLEFT", self.Health, "TOPLEFT", 0, 0)
    self.Health.mask:SetPoint("BOTTOMRIGHT", self.Health, "BOTTOMRIGHT", 0, 0)
    self.Health:GetStatusBarTexture():AddMaskTexture(self.Health.mask)
    -- Keep a single mask on the foreground status bar only; background remains unmasked for fewer draw calls

    -- Health Text
    self.Health.value = self.Health:CreateFontString(nil, "OVERLAY")
    self.Health.value:SetFont(unpack(C.font.nameplates.health))
    self.Health.value:SetShadowOffset(1, -1)
    self.Health.value:SetPoint("CENTER", self.Health, "CENTER", 0, -1)
    self:Tag(self.Health.value, "[NameplateHealth]")

    -- Threat updates are centralized by a single dispatcher for performance

    self.Health.PostUpdate = NP.HealthPostUpdate

    -- Absorb
    local absorb = self.Health:CreateTexture(nil, "ARTWORK")
    absorb:SetTexture(C.media.texture)
    absorb:SetVertexColor(1, 1, 1, .5)
    self.HealthPrediction = {
        absorbBar = absorb
    }
end

----------------------------------------------------------------------------------------
-- Power Bar
----------------------------------------------------------------------------------------
function NP.CreatePowerBar(self)
    -- Always create; visibility is controlled in the callback based on whether this plate represents the player
    self.Power = CreateFrame("StatusBar", nil, self)
    self.Power:SetStatusBarTexture(C.media.texture)
    self.Power:SetPoint("TOPLEFT", self.Health, "BOTTOMLEFT", 0, -6)
    self.Power:SetPoint("BOTTOMRIGHT", self.Health, "BOTTOMRIGHT", 0, -6 - (C.nameplate.height / 2))
    self.Power.frequentUpdates = true
    self.Power.colorPower = true
    self.Power.PostUpdate = R.PreUpdatePower
    NP.CreateBorderFrame(self.Power)

    self.Power.bg = self.Power:CreateTexture(nil, "BORDER")
    self.Power.bg:SetAllPoints()
    self.Power.bg:SetTexture(C.media.texture)

    -- Start disabled for non-player plates; callback will enable for the personal nameplate
    if self.DisableElement then self:DisableElement("Power") end
    -- Hidden by default; shown only for player's personal nameplate
    self.Power:Hide()
end

----------------------------------------------------------------------------------------
-- Name Text
----------------------------------------------------------------------------------------
function NP.CreateNameText(self)
    self.Name = self:CreateFontString(nil, "OVERLAY")
    self.Name:SetFont(unpack(C.font.nameplates.name))
    self.Name:SetShadowOffset(1, -1)
    self.Name:SetPoint("BOTTOMLEFT", self, "TOPLEFT", -4 * R.noscalemult, -2 * R.noscalemult)
    self.Name:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 4 * R.noscalemult, -2 * R.noscalemult)
    self.Name:SetWordWrap(false)
    self.Name:SetJustifyH("CENTER")
    self:Tag(self.Name, "[NameplateNameColor][NameLongAbbrev]")


    self.Title = self:CreateFontString(nil, "OVERLAY")
    self.Title:SetFont(unpack(C.font.nameplates.title))
    self.Title:SetShadowOffset(1, -1)
    self.Title:SetPoint("TOP", self.Name, "BOTTOM", 0, 0)
    self.Title:SetWordWrap(false)
    self.Title:SetJustifyH("CENTER")                 -- Center the text horizontally
    self.Title:SetTextColor(0.8, 0.8, 0.8)           -- Set text color to slightly off white
    self:Tag(self.Title, "[NPCTitle]")
    self.Title:SetWidth(self.Title:GetStringWidth()) -- Set width to the text width
end

-- Lazy-create the portrait radial status bar only when needed
function NP.EnsurePortraitRadial(self)
    if self.PortraitRadialStatusbar or not self.PortraitFrame then return end
    local radialStatusBar = R.CreateRadialStatusBar(self.PortraitFrame)
    radialStatusBar:SetAllPoints(self.PortraitFrame)
    radialStatusBar:SetTexture(TEX_PORTRAIT_BORDER)
    radialStatusBar:SetVertexColor(0, 0.8, 0.8, 0.75)
    radialStatusBar:SetFrameStrata("HIGH")
    self.PortraitRadialStatusbar = radialStatusBar
    -- Keep hidden by default; DynamicPortrait module will show/hide based on quest state
    radialStatusBar:Hide()
end

function NP.CreatePortraitAndQuestIcon(self)
    -- Create a frame to attach the portrait to
    local PortraitFrame = CreateFrame("Frame", nil, self)
    PortraitFrame:SetSize(20, 20)
    PortraitFrame:SetPoint("RIGHT", self.Health, "LEFT", 5, 0)
    PortraitFrame:SetFrameLevel(self.Health:GetFrameLevel() + 2)     -- Ensure this is higher than the background

    -- Create a circular border texture for the portrait
    local BorderTexture = PortraitFrame:CreateTexture(nil, 'OVERLAY')
    BorderTexture:SetAllPoints(PortraitFrame)
    BorderTexture:SetTexture(TEX_PORTRAIT_BORDER)
    BorderTexture:SetVertexColor(.6, .6, .6, 1)
    BorderTexture:SetDrawLayer("OVERLAY", 3)

    -- local r, g, b = unpack(R.oUF_colors.interruptible)
    -- BorderTexture:SetVertexColor(r, g, b)

    -- -- 2D Portrait
    -- local Portrait = PortraitFrame:CreateTexture(nil, 'OVERLAY')
    -- Portrait:SetSize(16, 16)
    -- Portrait:SetPoint('CENTER', PortraitFrame, 'CENTER')
    -- Portrait:SetDrawLayer("OVERLAY", 2)


    local portrait = PortraitFrame:CreateTexture(nil, 'ARTWORK')
    portrait:SetSize(16, 16)                                 -- Change this to match the inner size of the frame
    portrait:SetPoint('CENTER', PortraitFrame, 'CENTER')     -- Center it in the frame
    portrait:SetDrawLayer("OVERLAY", 2)

    -- Create and apply a circular mask
    local mask = PortraitFrame:CreateMaskTexture()
    mask:SetTexture(TEX_PORTRAIT_MASK)
    mask:SetAllPoints(portrait)     -- align mask to the portrait texture
    portrait:AddMaskTexture(mask)

    -- Background texture for the portrait
    local BackgroundTexture = PortraitFrame:CreateTexture(nil, 'BACKGROUND')     -- Use BACKGROUND layer
    BackgroundTexture:SetAllPoints(BorderTexture)                                -- Center it over the health bar
    BackgroundTexture:SetTexture(TEX_PORTRAIT_BG)
    BackgroundTexture:SetVertexColor(unpack(C.media.borderColor))                -- Set a color with some transparency
    BackgroundTexture:SetDrawLayer("OVERLAY", 1)                                 -- Ensure it is behind the border and portrait

    -- Background texture for the portrait
    local PortraitGlow = PortraitFrame:CreateTexture(nil, 'BACKGROUND')     -- Use BACKGROUND layer
    PortraitGlow:SetAllPoints(BorderTexture)                                -- Center it over the health bar
    PortraitGlow:SetTexture(TEX_PORTRAIT_GLOW)
    PortraitGlow:SetVertexColor(1, 1, 1, .6)                                -- Set a color with some transparency
    PortraitGlow:SetDrawLayer("OVERLAY", 1)
    PortraitGlow:Hide()

    -- Radial status bar is now lazy-created when needed via NP.EnsurePortraitRadial(self)

    -- -- Create the text element for quest completion
    -- local QuestText = PortraitFrame:CreateFontString(nil, "OVERLAY")
    -- QuestText:SetPoint("CENTER", portrait, "CENTER", 0, -4)
    -- QuestText:SetJustifyH("CENTER")
    -- QuestText:SetFont(C.font.nameplates_font, 5, C.font.nameplates_font_style)
    -- QuestText:SetShadowOffset(C.font.nameplates_font_shadow and 1 or 0, C.font.nameplates_font_shadow and -1 or 0)

    self.CombinedPortrait = portrait
    -- self.CombinedPortrait.Text = QuestText
    self.PortraitBorder = BorderTexture
    self.PortraitFrame = PortraitFrame
    self.PortraitGlow = PortraitGlow

        -- Initialize portrait texture if unit is already available
        if self.unit then
            SetPortraitTexture(portrait, self.unit)
        end
        portrait:Show()

        self:HookScript("OnShow", function(self)
            -- Create radial only for hostile units and when quests feature is enabled
            if C and C.nameplate and C.nameplate.quests and UnitCanAttack("player", self.unit or "") then
                if NP and NP.EnsurePortraitRadial then
                    NP.EnsurePortraitRadial(self)
                end
            end
            -- Update portrait texture for hostile units only
            if self.CombinedPortrait and self.unit and not UnitIsFriend("player", self.unit or "") then
                SetPortraitTexture(self.CombinedPortrait, self.unit)
            end
        end)
end

-- Enable the oUF DynamicPortrait element when created lazily
function NP.EnableDynamicPortrait(self)
    if not self or not self.CombinedPortrait then return end
    if self.EnableElement and not self:IsElementEnabled('CombinedPortrait') then
        self:EnableElement('CombinedPortrait')
    end
    if self.CombinedPortrait.ForceUpdate then
        self.CombinedPortrait:ForceUpdate()
    end
end

----------------------------------------------------------------------------------------
-- Target Glow
----------------------------------------------------------------------------------------
function NP.CreateTargetGlow(self)
    local level = 0
    NP.CreateGlowFrame(self,
        { edgeFile = TEX_NP_GLOW, edgeSize = 6, offset = 3, color = { 0.9, 0.9, 0.9, 1 }, frameLevel = level })
end

----------------------------------------------------------------------------------------
-- Cast Bar
----------------------------------------------------------------------------------------
function NP.CreateCastBar(self)
    self.Castbar = CreateFrame("StatusBar", nil, self)
    -- Place castbar beneath the health bar; frame level relative to the parent plate
    local parentLevel = self:GetFrameLevel() or 0
    -- One level above parent but below health (health is parentLevel + 3); below CC (which is +2)
    self.Castbar:SetFrameLevel(parentLevel + 1)
    self.Castbar:SetFrameStrata("MEDIUM")
    self.Castbar:SetStatusBarTexture(TEX_CASTBAR)
    self.Castbar:SetStatusBarColor(1, 0.8, 0)
    self.Castbar:SetPoint("TOP", self.Health, "BOTTOM", 0, 2)
    self.Castbar:SetSize(C.nameplate.width, C.nameplate.height + 2)
    NP.CreateBorderFrame(self.Castbar)
    -- Ensure castbar border sits above the castbar but below the health border
    if self.Castbar.border then
        -- health border is health:GetFrameLevel() + 1, so set castbar border lower than that
        local castBorderLevel = math.max(0, self.Castbar:GetFrameLevel() + 1)
        self.Castbar.border:SetFrameLevel(castBorderLevel)
    end


    self.Castbar.bg = self.Castbar:CreateTexture(nil, "BORDER")
    self.Castbar.bg:SetAllPoints()
    self.Castbar.bg:SetTexture(C.media.texture)
    self.Castbar.bg:SetColorTexture(1, 0.8, 0)
    -- avoid injecting custom fields on Texture to satisfy linter; use local factors when needed

    -- Hold interrupted/failed casts briefly using oUF's built-in property
    -- (keeps the bar visible for a short period after interruption)
    self.Castbar.timeToHold = 1

    self.Castbar.PostCastStart = NP.PostCastStart
    self.Castbar.PostCastStop = NP.PostCastStop
    self.Castbar.PostCastInterruptible = NP.PostCastStart
    -- Show an "Interrupted" overlay for a brief moment, then restore layout on hide
    -- oUF only recognizes PostCastFail (not PostCastInterrupted/PostCastFailed)
    self.Castbar.PostCastFail = NP.PostCastFail
    -- Channels
    self.Castbar.PostChannelStart = NP.PostCastStart
    self.Castbar.PostChannelStop = NP.PostCastStop

    -- Cast Name Text
    self.Castbar.Text = self.Castbar:CreateFontString(nil, "OVERLAY")
    self.Castbar.Text:SetPoint("BOTTOMLEFT", self.Castbar, "BOTTOMLEFT", 2, 1)
    self.Castbar.Text:SetFont(unpack(C.font.nameplates.spell))
    self.Castbar.Text:SetShadowOffset(1, -1)
    self.Castbar.Text:SetJustifyH("LEFT")
    -- Remember original layout to restore after an interrupted/failed hold
    -- Avoid calling FontString:GetPoint() in restricted regions; we know the anchor we just set
    self.Castbar._origTextPoint = { "BOTTOMLEFT", self.Castbar, "BOTTOMLEFT", 2, 1 }
    self.Castbar._origTextJustify = "LEFT"

    -- Castbar icon/cooldown omitted for a cleaner plate


    -- Cast Time Text
    self.Castbar.Time = self.Castbar:CreateFontString(nil, "OVERLAY")
    self.Castbar.Time:SetPoint("BOTTOMRIGHT", self.Castbar, "BOTTOMRIGHT", 0, 1)
    self.Castbar.Time:SetJustifyH("RIGHT")
    self.Castbar.Time:SetFont(unpack(C.font.nameplates.spelltime))
    self.Castbar.Time:SetShadowOffset(1, -1)

    self.Castbar.CustomTimeText = function(self, duration)
        self.Time:SetText(duration > 600 and "∞" or
            ("%.1f"):format(self.channeling and duration or self.max - duration))
    end

    -- Safety net: always restore portrait border when the castbar hides for any reason
    if not self.Castbar._restoreHooked then
        self.Castbar:HookScript("OnHide", function(cb)
            if NP and NP.RestorePortraitBorder then
                NP.RestorePortraitBorder(cb:GetParent())
            end
            if NP and NP.RestoreCastbarLayout then
                NP.RestoreCastbarLayout(cb)
            end
            if NP and NP.UpdateBarsLayout then
                NP.UpdateBarsLayout(cb:GetParent())
            end
        end)
        self.Castbar:HookScript("OnShow", function(cb)
            local parent = cb:GetParent()
            -- Belt-and-suspenders: ensure CC bar is hidden whenever a castbar becomes visible
            if parent and parent.CrowdControl and parent.CrowdControl:IsShown() then
                parent.CrowdControl:Hide()
            end
            if NP and NP.UpdateBarsLayout then
                NP.UpdateBarsLayout(parent)
            end
        end)
        self.Castbar._restoreHooked = true
    end
end

----------------------------------------------------------------------------------------
-- Crowd Control Bar (looks like Castbar, fills up instead of down)
----------------------------------------------------------------------------------------
function NP.CreateCrowdControlBar(self)
    -- oUF element will manage updates; here we just create and style the frame
    local bar = CreateFrame("StatusBar", nil, self)
    bar:SetStatusBarTexture(TEX_CASTBAR)
    bar:SetStatusBarColor(0.2, 0.6, 1)
    local parentLevel = self:GetFrameLevel() or 0
    -- Draw above the castbar but still below the health bar
    bar:SetFrameLevel(parentLevel + 2)
    bar:SetFrameStrata("MEDIUM")
    bar:SetPoint("TOP", self.Health, "BOTTOM", 0, 2)
    bar:SetSize(C.nameplate.width, C.nameplate.height + 2)
    NP.CreateBorderFrame(bar)
    if bar.border then
        bar.border:SetFrameLevel(math.max(0, bar:GetFrameLevel() + 1))
    end
    bar.bg = bar:CreateTexture(nil, "BORDER")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(C.media.texture)
    -- Darker tint of the foreground color to better match castbar background
    bar.bg:SetColorTexture(0.08, 0.24, 0.4)

    bar.Text = bar:CreateFontString(nil, "OVERLAY")
    bar.Text:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, 1)
    bar.Text:SetFont(unpack(C.font.nameplates.spell))
    bar.Text:SetShadowOffset(1, -1)
    bar.Text:SetJustifyH("LEFT")

    bar.Time = bar:CreateFontString(nil, "OVERLAY")
    bar.Time:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 1)
    bar.Time:SetFont(unpack(C.font.nameplates.spelltime))
    bar.Time:SetShadowOffset(1, -1)
    bar.Time:SetJustifyH("RIGHT")

    self.CrowdControl = bar
    bar:Hide()

    if not self._ccOnShowHooked then
        self:HookScript("OnShow", function(frame)
            if frame.CrowdControl and frame.CrowdControl.ForceUpdate then
                frame.CrowdControl:ForceUpdate()
            end
            if NP and NP.UpdateBarsLayout then NP.UpdateBarsLayout(frame) end
        end)
        self._ccOnShowHooked = true
    end

    -- Reposition on CC bar visibility changes
    if not bar._layoutHooks then
        bar:HookScript("OnShow", function(b)
            if NP and NP.UpdateBarsLayout then NP.UpdateBarsLayout(b:GetParent()) end
        end)
        bar:HookScript("OnHide", function(b)
            if NP and NP.UpdateBarsLayout then NP.UpdateBarsLayout(b:GetParent()) end
        end)
        bar._layoutHooks = true
    end
end

----------------------------------------------------------------------------------------
-- Auras
----------------------------------------------------------------------------------------
function NP.CreateAuras(self)
    self.Auras = CreateFrame("Frame", nil, self)
    self.Auras:SetPoint("BOTTOMRIGHT", self.Health, "TOPRIGHT", 0, C.font.nameplates.name[2] + 2)
    self.Auras.initialAnchor = "BOTTOMRIGHT"
    self.Auras["growth-y"] = "UP"
    self.Auras["growth-x"] = "LEFT"
    self.Auras.numDebuffs = C.nameplate.trackDebuffs and 6 or 0
    self.Auras.numBuffs = C.nameplate.trackBuffs and 4 or 0
    self.Auras:SetSize(20 + C.nameplate.width, C.nameplate.aurasSize)
    self.Auras.spacing = 5
    self.Auras.size = C.nameplate.aurasSize - 3
    self.Auras.disableMouse = true

    -- Cooldown swipe toggle (default ON for no regression). When false, draw text-only timers.
    local swipeEnabled = not (C and C.nameplate and C.nameplate.cooldownSwipe == false)
    self.Auras.disableCooldown = not swipeEnabled

    self.Auras.FilterAura = NP.AurasCustomFilter
    self.Auras.PostCreateButton = NP.AurasPostCreateIcon
    self.Auras.PostUpdateButton = NP.AurasPostUpdateIcon
end

----------------------------------------------------------------------------------------
-- Target Indicator
----------------------------------------------------------------------------------------
function NP.CreateTargetIndicator(self)
    self.RTargetIndicator = self:CreateTexture(nil, "OVERLAY", nil, 7)
    self.RTargetIndicator:SetTexture(TEX_TGT_R)
    self.RTargetIndicator:SetSize(C.nameplate.height + 2, C.nameplate.height + 2)
    self.RTargetIndicator:Hide()

    self.LTargetIndicator = self:CreateTexture(nil, "OVERLAY", nil, 7)
    self.LTargetIndicator:SetTexture(TEX_TGT_L)
    self.LTargetIndicator:SetSize(C.nameplate.height + 2, C.nameplate.height + 2)
    self.LTargetIndicator:Hide()
end

----------------------------------------------------------------------------------------
-- Raid Icons
----------------------------------------------------------------------------------------
function NP.CreateRaidIcon(self, unit)
    self.RaidTargetIndicator = self:CreateTexture(nil, "OVERLAY", nil, 7)
    self.RaidTargetIndicator:SetSize((C.nameplate.height * 2), (C.nameplate.height * 2))
    self.RaidTargetIndicator:SetPoint("BOTTOM", self.Name, "TOP", 0, 0)
end

----------------------------------------------------------------------------------------
-- Class Icon
----------------------------------------------------------------------------------------
function NP.CreateQuestIcon(self) end

return NP
