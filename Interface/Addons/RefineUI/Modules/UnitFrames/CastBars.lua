----------------------------------------------------------------------------------------
-- RefineUI UnitFrame CastBars
-- Description: Skins and attaches castbars to unitframes
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local unpack = unpack
local UnitIsUnit = UnitIsUnit
local issecretvalue = issecretvalue
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local InCombatLockdown = InCombatLockdown
local math = math
local GetTime = GetTime
local type = type
local tostring = tostring
local pairs = pairs
local next = next
local setmetatable = setmetatable

-- External Data Registry (prevents taint on secure CastBar frames)
local UNITFRAME_CASTBAR_STATE_REGISTRY = "UnitFrameCastBarsState"
local CastBarData = RefineUI:CreateDataRegistry(UNITFRAME_CASTBAR_STATE_REGISTRY, "k")

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function HasValue(v)
    if IsSecret(v) then
        return true
    end
    return v ~= nil
end

local function GetCastBarData(castbar)
    if not castbar then return {} end
    local data = CastBarData[castbar]
    if not data then
        data = {}
        CastBarData[castbar] = data
    end
    return data
end

local TEXTURE_PATH = "Interface\\AddOns\\RefineUI\\Media\\Textures\\"
local TEX_BAR = TEXTURE_PATH .. "HealthBarTest.blp" -- Reusing the clean texture
local TEX_BACKGROUND = TEXTURE_PATH .. "HealthBackground.blp"
local TEX_PORTRAIT_BORDER = TEXTURE_PATH .. "PortraitBorder.blp"
local TEX_MASK = TEXTURE_PATH .. "PortraitMask.blp"

local function GetHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(owner)
end

local function BuildUnitCastHookKey(owner, method)
    return "UnitFramesCastBars:" .. GetHookOwnerId(owner) .. ":" .. method
end

local function IsBossUnitFrame(frame)
    if not frame then return false end
    if frame.isBossFrame then return true end
    return type(frame.unit) == "string" and frame.unit:match("^boss%d+$") ~= nil
end

local function GetBossCastBarAnchor(frame)
    if not frame then return nil end

    local unitFrameData = RefineUI.UnitFrameData and RefineUI.UnitFrameData[frame]
    local refineUF = unitFrameData and unitFrameData.RefineUF
    if refineUF and refineUF.Texture then
        return refineUF.Texture
    end

    if UF and UF.GetFrameContainers then
        local _, _, hpContainer, manaBar = UF.GetFrameContainers(frame)
        if manaBar then
            return manaBar
        end
        if hpContainer and hpContainer.HealthBar then
            return hpContainer.HealthBar
        end
    end

    return frame
end

local UNITFRAME_CASTBAR_TIMER_JOB_KEY = "UnitFrames:CastBarTimerUpdater"
local UNITFRAME_CASTBAR_TIMER_INTERVAL = 0.05
local ActiveTimerCastBars = setmetatable({}, { __mode = "k" })
local castBarTimerSchedulerInitialized = false
local SetCastBarTimerActive



----------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------

local function UpdateTime(self, elapsed)
    local data = GetCastBarData(self)
    local timer = data.timer
    if not timer then return end

    local function SetTimerText(text)
        RefineUI:SetFontStringValue(timer, text, {
            emptyText = "",
        })
    end

    local function SetTimerNumber(value, durationObj)
        RefineUI:SetFontStringValue(timer, value, {
            format = "%.1f",
            duration = durationObj,
            emptyText = "",
        })
    end

    -- WoW 12.0: Check for secret values to prevent arithmetic crashes
    if IsSecret(self.maxValue) or IsSecret(self.value) then
        if not self.GetTimerDuration then return end

        local durationObj = self:GetTimerDuration()
        if not durationObj and self.unit and self.SetTimerDuration then
            local duration
            local isChanneling = (self.channeling or self.reverseChanneling) and true or false
            if isChanneling and UnitChannelDuration then
                duration = UnitChannelDuration(self.unit)
            end
            if not isChanneling and UnitCastingDuration then
                duration = UnitCastingDuration(self.unit)
            end
            if HasValue(duration) then
                self:SetTimerDuration(duration)
                durationObj = self:GetTimerDuration()
            end
        end
        if not durationObj then return end

        -- Try to use EvaluateRemainingDuration for a proper countdown
        if durationObj.EvaluateRemainingDuration then
             local remaining = durationObj:EvaluateRemainingDuration(RefineUI.GetLinearCurve())
             if IsSecret(remaining) then
                SetTimerNumber(remaining, durationObj)
                return
             end
             if remaining ~= nil then
                SetTimerNumber(remaining, durationObj)
                return
             end
        end
        
        -- Use total duration when remaining evaluation is unavailable.
        local total = durationObj.GetTotalDuration and durationObj:GetTotalDuration() or nil
        if IsSecret(total) then
             SetTimerNumber(total, durationObj)
        elseif total ~= nil then
             SetTimerNumber(total, durationObj)
        else
             SetTimerNumber(nil, durationObj)
        end
        return
    end

    if self.casting then
        SetTimerNumber(math.max(self.maxValue - self.value, 0), nil)
    elseif self.channeling then
        SetTimerNumber(math.max(self.value, 0), nil)
    else
        SetTimerText("")
    end
end

local function IsCastTimerRelevant(castbar)
    if not castbar or not castbar:IsShown() then
        return false
    end
    return castbar.casting or castbar.channeling or castbar.reverseChanneling
end

local function CastBarTimerUpdateJob()
    local hasActive = false

    for castbar in pairs(ActiveTimerCastBars) do
        if castbar and castbar:IsShown() then
            UpdateTime(castbar, UNITFRAME_CASTBAR_TIMER_INTERVAL)
            if IsCastTimerRelevant(castbar) then
                hasActive = true
            else
                ActiveTimerCastBars[castbar] = nil
            end
        else
            ActiveTimerCastBars[castbar] = nil
        end
    end

    if not hasActive and not next(ActiveTimerCastBars) and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(UNITFRAME_CASTBAR_TIMER_JOB_KEY, false, false)
    end
end

local function EnsureCastBarTimerScheduler()
    if castBarTimerSchedulerInitialized then return end
    if not RefineUI.RegisterUpdateJob then return end

    RefineUI:RegisterUpdateJob(
        UNITFRAME_CASTBAR_TIMER_JOB_KEY,
        UNITFRAME_CASTBAR_TIMER_INTERVAL,
        CastBarTimerUpdateJob,
        { enabled = false }
    )

    castBarTimerSchedulerInitialized = true
end

SetCastBarTimerActive = function(castbar, enabled)
    if not castbar then return end

    if enabled then
        ActiveTimerCastBars[castbar] = true
    else
        ActiveTimerCastBars[castbar] = nil
    end

    EnsureCastBarTimerScheduler()

    if castBarTimerSchedulerInitialized and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(UNITFRAME_CASTBAR_TIMER_JOB_KEY, next(ActiveTimerCastBars) ~= nil, false)
    end
end

local function EnsureIconLayering(castbar, data)
    if not castbar or not castbar.Icon then return end

    if not data.iconHost then
        local iconHost = CreateFrame("Frame", nil, castbar)
        iconHost:SetAllPoints(castbar)
        data.iconHost = iconHost
    end

    local iconHost = data.iconHost
    local borderLevel = castbar.border and castbar.border:GetFrameLevel() or castbar:GetFrameLevel()
    local desiredLevel = math.max(0, borderLevel + 1)
    local desiredStrata = castbar:GetFrameStrata()

    if iconHost:GetFrameLevel() ~= desiredLevel then
        iconHost:SetFrameLevel(desiredLevel)
    end
    if iconHost:GetFrameStrata() ~= desiredStrata then
        iconHost:SetFrameStrata(desiredStrata)
    end

    if castbar.Icon:GetParent() ~= iconHost then
        castbar.Icon:SetParent(iconHost)
    end
    castbar.Icon:SetDrawLayer("OVERLAY", 1)

    if data.iconMask and data.iconMask.GetParent and data.iconMask:GetParent() ~= iconHost then
        data.iconMask:SetParent(iconHost)
    end

    if data.iconBorder and data.iconBorder:GetParent() ~= iconHost then
        data.iconBorder:SetParent(iconHost)
    end
    if data.iconBorder then
        data.iconBorder:SetDrawLayer("OVERLAY", 2)
    end
end

local function PostCastStart(self, unit)
    local data = GetCastBarData(self)
    self:SetAlpha(1)
    if self.Spark then self.Spark:SetHeight(self:GetHeight()) end

    -- WoW 12.0: Handle Secret Values using Engine Duration
    if IsSecret(self.maxValue) or IsSecret(self.value) then
        if self.SetTimerDuration and self.unit then
            local duration
            local isChanneling = (self.channeling or self.reverseChanneling) and true or false
            if isChanneling and UnitChannelDuration then
                duration = UnitChannelDuration(self.unit)
            end
            if not isChanneling and UnitCastingDuration then
                duration = UnitCastingDuration(self.unit)
            end
            if HasValue(duration) then
                self:SetTimerDuration(duration)
            end
        end
    end
    
    -- Color
    if self.notInterruptible then
        self:SetStatusBarColor(0.5, 0.5, 0.5) -- Grey for uninterruptible
    else
        local c = Config.UnitFrames.CastBars.Color
        self:SetStatusBarColor(unpack(c))
    end
    
    -- Force Icon Styling on every cast (Blizzard resets it)
    if self.Icon then
        EnsureIconLayering(self, data)

        self.Icon:ClearAllPoints()
        self.Icon:SetSize(self:GetHeight() + 20, self:GetHeight() + 20)
        self.Icon:SetPoint("CENTER", self, "LEFT", -10, 0)
        self.Icon:SetAlpha(1)
        self.Icon:Show()
        
        if data.iconBorder then
            data.iconBorder:Show()
            data.iconBorder:SetSize(self:GetHeight() + 20, self:GetHeight() + 20)
        end
    end
    
    -- Force Text Anchoring
    if self.Text then
        self.Text:ClearAllPoints()
        self.Text:SetPoint("LEFT", self, "LEFT", 8, 1)
        self.Text:SetJustifyH("LEFT")
    end

    if data and data.timer then
        UpdateTime(self, 0)
        SetCastBarTimerActive(self, IsCastTimerRelevant(self))
    end
end

----------------------------------------------------------------------------------------
-- Style Function
----------------------------------------------------------------------------------------

function RefineUI.StyleCastBar(castbar, attachedFrame)
    if not castbar then return end
    
    local data = GetCastBarData(castbar)
    if data.isStyled then return end
    
    local cfg = Config.UnitFrames.CastBars
    
    -- Strip Default Textures
    if castbar.Border then castbar.Border:Hide() end
    if castbar.BorderShield then castbar.BorderShield:Hide() end
    if castbar.TextBorder then
        castbar.TextBorder:SetParent(RefineUI.HiddenFrame)
    end
    if castbar.Background then castbar.Background:SetTexture(nil) end
    
    -- Set StatusBar Texture
    castbar:SetStatusBarTexture(TEX_BAR)
    
    -- Create Backdrop
    RefineUI.CreateBorder(castbar, 6, 6, 12)
    castbar.border:SetFrameLevel(castbar:GetFrameLevel() + 1)
    
    -- Background
    local bg = castbar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(castbar)
    bg:SetTexture(TEX_BACKGROUND)
    bg:SetVertexColor(0.5, 0.5, 0.5, 1)

    -- Icon
    if castbar.Icon then
        EnsureIconLayering(castbar, data)
        
        if not data.iconMask then
            local mask = castbar:CreateMaskTexture()
            mask:SetTexture(TEX_MASK)
            mask:SetAllPoints(castbar.Icon)
            castbar.Icon:AddMaskTexture(mask)
            data.iconMask = mask
        end
        EnsureIconLayering(castbar, data)
        
        -- Create Icon Border (PortraitBorder.blp)
        if not data.iconBorder then
            local iconBorder = (data.iconHost or castbar):CreateTexture(nil, "OVERLAY")
            iconBorder:SetTexture(TEX_PORTRAIT_BORDER)
            iconBorder:SetSize(cfg.Height + 20, cfg.Height + 20)
            iconBorder:SetPoint("CENTER", castbar.Icon, "CENTER", 0, 0)
            iconBorder:SetVertexColor(unpack(Config.General.BorderColor))
            iconBorder:SetDrawLayer("OVERLAY", 2)
            data.iconBorder = iconBorder
        end
        EnsureIconLayering(castbar, data)
    end
    
    -- Text (Spell Name)
    if castbar.Text then
        castbar.Text:ClearAllPoints()
        castbar.Text:SetPoint("LEFT", castbar, "LEFT", 8, 1)
        castbar.Text:SetJustifyH("LEFT")
        RefineUI.Font(castbar.Text, 10)
        castbar.Text:SetShadowOffset(1, -1)
        
        RefineUI:HookOnce(BuildUnitCastHookKey(castbar.Text, "SetPoint"), castbar.Text, "SetPoint", function(self)
            if data.textChanging then return end
            data.textChanging = true
            self:ClearAllPoints()
            self:SetPoint("LEFT", castbar, "LEFT", 8, 0)
            self:SetPoint("RIGHT", castbar, "RIGHT", -35, 0) -- Constrain width to avoid timer overlap
            self:SetWordWrap(false)
            data.textChanging = false
        end)
    end
    
    -- Time
    if cfg.ShowTime then
        local timer = castbar:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(timer, 14)
        timer:SetPoint("RIGHT", castbar, "RIGHT", -4, -1)
        timer:SetShadowOffset(1, -1)
        data.timer = timer

        EnsureCastBarTimerScheduler()
        castbar:HookScript("OnHide", function(self)
            SetCastBarTimerActive(self, false)
        end)
    end
    
    -- Spark
    if castbar.Spark then
        castbar.Spark:SetBlendMode("ADD")
        castbar.Spark:SetWidth(5)
    end
    
    -- Safe Sizing
    local function ApplySize()
         castbar:SetSize(cfg.Width, cfg.Height)
         
         if castbar.Flash then
             castbar.Flash:ClearAllPoints()
             castbar.Flash:SetAllPoints(castbar)
         end
 
         if castbar.InterruptGlow then
             castbar.InterruptGlow:ClearAllPoints()
             castbar.InterruptGlow:SetPoint("LEFT", castbar, "LEFT", -20, 0) -- Slight overflow for glow
             castbar.InterruptGlow:SetPoint("RIGHT", castbar, "RIGHT", 20, 0)
             castbar.InterruptGlow:SetPoint("TOP", castbar, "TOP", 0, 20)
             castbar.InterruptGlow:SetPoint("BOTTOM", castbar, "BOTTOM", 0, -20)
         end

         if attachedFrame and attachedFrame.GetScale then
             -- Only apply scale if the castbar is NOT parented to the scaled frame
             -- (Sub-frames inherit scale automatically)
             if castbar:GetParent() ~= attachedFrame then
                castbar:SetScale(attachedFrame:GetScale())
             else
                castbar:SetScale(.75)
             end
         end
    end
    
    ApplySize()
    
    -- Hook for persistence
    castbar:HookScript("OnShow", ApplySize)
    
    if castbar == PlayerCastingBarFrame then
        -- BBF Trick: EditMode/Blizzard likes to mess with Scale/Size of PlayerBar
        RefineUI:HookOnce(BuildUnitCastHookKey(castbar, "SetScale"), castbar, "SetScale", function()
             if data.isUpdating then return end
             data.isUpdating = true
             C_Timer.After(0, function()
                 ApplySize()
                 data.isUpdating = false
             end)
        end)
    end

    -- Positioning (Disabled for verification)
    -- ... (Keep existing commented out positioning)
    
    -- Events
    castbar:HookScript("OnEvent", PostCastStart)
    castbar:HookScript("OnShow", function(self) PostCastStart(self) end) -- Ensure colors apply on show
    
    -- Target/Focus cast bars are anchored directly to their unit frame bottoms.
    if attachedFrame == TargetFrame or attachedFrame == FocusFrame then
        local yOffset = (attachedFrame == FocusFrame) and 30 or 30

        local function AnchorUnitFrameCastBar(self)
            if data.unitFrameAnchorChanging then return end
            data.unitFrameAnchorChanging = true
            self:ClearAllPoints()
            self:SetPoint("TOP", attachedFrame, "BOTTOM", -36, yOffset)
            data.unitFrameAnchorChanging = false
        end

        AnchorUnitFrameCastBar(castbar)
        castbar:HookScript("OnShow", AnchorUnitFrameCastBar)
        RefineUI:HookOnce(BuildUnitCastHookKey(castbar, "SetPoint:UnitFrameAnchor"), castbar, "SetPoint", AnchorUnitFrameCastBar)
    elseif attachedFrame and IsBossUnitFrame(attachedFrame) then
        local function AnchorBossCastBar(self)
            if data.bossAnchorChanging then return end
            data.bossAnchorChanging = true
            local anchor = GetBossCastBarAnchor(attachedFrame) or attachedFrame
            self:ClearAllPoints()
            self:SetPoint("TOP", anchor, "BOTTOM", 0, 10)
            data.bossAnchorChanging = false
        end

        AnchorBossCastBar(castbar)
        castbar:HookScript("OnShow", AnchorBossCastBar)
        RefineUI:HookOnce(BuildUnitCastHookKey(castbar, "SetPoint:BossAnchor"), castbar, "SetPoint", AnchorBossCastBar)
    end
    
    -- Selection Box Styling (Simplified)
    if castbar.Selection then
        local function UpdateSelection(self)
            if data.selectionChanging or InCombatLockdown() then return end
            local icon = data.iconBorder or castbar.Icon
            if not icon then return end

            data.selectionChanging = true
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
            self:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", 4, -4)
            data.selectionChanging = false
        end

        RefineUI:HookOnce(BuildUnitCastHookKey(castbar.Selection, "SetPoint"), castbar.Selection, "SetPoint", UpdateSelection)
        UpdateSelection(castbar.Selection)
    end

    data.isStyled = true
end
