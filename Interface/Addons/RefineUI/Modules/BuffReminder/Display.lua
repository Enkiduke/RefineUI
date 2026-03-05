----------------------------------------------------------------------------------------
-- BuffReminder Component: Display
-- Description: Visual rendering and UI frame management
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:GetModule("BuffReminder")
if not BuffReminder then return end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues (Cache only what you actually use)
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local PlaySound = PlaySound
local SOUNDKIT = _G.SOUNDKIT
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local type = type
local math_max = math.max

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function CreateFlashAnimation(frame)
    local group = frame:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local out = group:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0.2)
    out:SetDuration(0.55)
    out:SetSmoothing("IN_OUT")
    local inn = group:CreateAnimation("Alpha")
    inn:SetFromAlpha(0.2)
    inn:SetToAlpha(1)
    inn:SetDuration(0.55)
    inn:SetSmoothing("IN_OUT")
    inn:SetOrder(2)
    return group
end

local function StopFlash(frame)
    if frame.flashAnim and frame.flashAnim:IsPlaying() then
        frame.flashAnim:Stop()
    end
    frame:SetAlpha(1)
end

local function ResolveColorTriplet(color, fallbackR, fallbackG, fallbackB)
    if type(color) ~= "table" then
        return fallbackR, fallbackG, fallbackB
    end
    if color.r and color.g and color.b then
        return color.r, color.g, color.b
    end
    return color[1] or fallbackR, color[2] or fallbackG, color[3] or fallbackB
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    return ResolveColorTriplet(color, 0.6, 0.6, 0.6)
end

local function GetProviderClassColor(classToken)
    local classColor
    if classToken and RefineUI.Colors and RefineUI.Colors.Class then
        classColor = RefineUI.Colors.Class[classToken]
    end
    if not classColor and classToken and RAID_CLASS_COLORS then
        classColor = RAID_CLASS_COLORS[classToken]
    end
    if classColor then
        return ResolveColorTriplet(classColor)
    end
    return nil
end

local function ApplyIconColorState(frame, useClassColor, classToken)
    if not frame then
        return
    end

    local r, g, b = GetDefaultBorderColor()
    local useGlow = false
    if useClassColor then
        local classR, classG, classB = GetProviderClassColor(classToken)
        if classR and classG and classB then
            r, g, b = classR, classG, classB
            useGlow = true
        end
    end

    if frame.border and frame.border.SetBackdropBorderColor then
        frame.border:SetBackdropBorderColor(r, g, b, 1)
    end

    if useGlow then
        if not frame.glow then
            RefineUI.CreateGlow(frame, 8)
        end
        if frame.glow and frame.glow.SetBackdropBorderColor then
            frame.glow:SetBackdropBorderColor(r, g, b, 0.95)
            frame.glow:Show()
        end
    elseif frame.glow then
        frame.glow:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Public Methods / Component Access
----------------------------------------------------------------------------------------
function BuffReminder:ResolveAnchorPosition()
    local pos = RefineUI.Positions and RefineUI.Positions[self.FRAME_NAME]
    if type(pos) ~= "table" then
        return "CENTER", UIParent, "CENTER", 0, 0
    end
    local point = pos[1] or "CENTER"
    local relativeTo = pos[2]
    local relativePoint = pos[3] or point
    local x = pos[4] or 0
    local y = pos[5] or 0
    if type(relativeTo) == "string" then
        relativeTo = _G[relativeTo]
    end
    return point, relativeTo or UIParent, relativePoint, x, y
end

function BuffReminder:GetPreviewEntry()
    local runtime = self:BuildRuntimeState()
    for c = 1, #self.CATEGORY_ORDER do
        local category = self.CATEGORY_ORDER[c]
        local entries = self:GetConfigurableEntries(category)
        for i = 1, #entries do
            local entry = entries[i]
            if self:IsEntryEnabled(entry.key, category) then
                return { category = category, entry = entry, runtime = runtime }
            end
        end
    end
    return { category = "self", entry = { key = "preview", iconOverride = self.QUESTION_MARK_ICON }, runtime = runtime }
end

function BuffReminder:EnsureRootFrame()
    if self.rootFrame then
        return self.rootFrame
    end

    local frame = CreateFrame("Frame", self.FRAME_NAME, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(25)
    frame:EnableMouse(false)

    local point, relativeTo, relativePoint, x, y = self:ResolveAnchorPosition()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    frame:SetSize(RefineUI:Scale(44), RefineUI:Scale(44))
    frame:Hide()

    frame:SetScript("OnEnter", function(selfFrame)
        if not BuffReminder:IsEditModeActive() then return end
        GameTooltip:SetOwner(selfFrame, "ANCHOR_TOP")
        GameTooltip:SetText("Buff Reminder", 1, 1, 1)
        GameTooltip:AddLine("Open settings from the Edit Mode dialog.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.rootFrame = frame
    self.iconFrames = self.iconFrames or {}
    self.hadVisibleIcons = false
    return frame
end

function BuffReminder:EnsureIconFrame(index)
    self.iconFrames = self.iconFrames or {}
    local frame = self.iconFrames[index]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, self.rootFrame)
    frame:SetFrameLevel(self.rootFrame:GetFrameLevel() + 1)
    RefineUI.SetTemplate(frame, "Default")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.flashAnim = CreateFlashAnimation(frame)
    frame:Hide()

    self.iconFrames[index] = frame
    return frame
end

function BuffReminder:RenderEntries(entries)
    local cfg = self:GetConfig()
    local iconSize = RefineUI:Scale(cfg.Size or 44)
    local spacing = RefineUI:Scale(cfg.Spacing or 6)
    local flashEnabled = cfg.Flash ~= false
    local soundEnabled = cfg.Sound == true
    local classColorEnabled = cfg.ClassColor == true
    local count = #entries

    if count == 0 and self:IsEditModeActive() then
        local preview = self:GetPreviewEntry()
        entries = { preview }
        count = 1
        flashEnabled = false
        soundEnabled = false
    end

    if count == 0 then
        if self.iconFrames then
            for i = 1, #self.iconFrames do
                self.iconFrames[i]:Hide()
                StopFlash(self.iconFrames[i])
                if self.iconFrames[i].glow then
                    self.iconFrames[i].glow:Hide()
                end
            end
        end
        if self.rootFrame then
            self.rootFrame:Hide()
        end
        self.hadVisibleIcons = false
        return
    end

    local rootFrame = self:EnsureRootFrame()
    local xOffset = 0
    local lastCategory = nil
    for i = 1, count do
        local payload = entries[i]
        local frame = self:EnsureIconFrame(i)
        if i > 1 and payload.category ~= lastCategory then
            xOffset = xOffset + spacing
        end
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", rootFrame, "LEFT", xOffset, 0)
        frame:SetSize(iconSize, iconSize)
        frame.icon:SetTexture(self:GetEntryTexture(payload.entry, payload.runtime))
        local providerClass = payload.entry and payload.entry.class
        if not providerClass and payload.entry and payload.entry.key == "preview" then
            providerClass = RefineUI.MyClass
        end
        ApplyIconColorState(frame, classColorEnabled, providerClass)
        frame:Show()
        if flashEnabled then
            if frame.flashAnim and not frame.flashAnim:IsPlaying() then
                frame.flashAnim:Play()
            end
        else
            StopFlash(frame)
        end
        xOffset = xOffset + iconSize + spacing
        lastCategory = payload.category
    end

    for i = count + 1, #(self.iconFrames or {}) do
        self.iconFrames[i]:Hide()
        StopFlash(self.iconFrames[i])
        if self.iconFrames[i].glow then
            self.iconFrames[i].glow:Hide()
        end
    end

    rootFrame:SetSize(math_max(iconSize, xOffset - spacing), iconSize)
    rootFrame:Show()

    if soundEnabled and not self.hadVisibleIcons and PlaySound then
        local soundKit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)
        if soundKit then
            PlaySound(soundKit, "Master")
        end
    end

    self.hadVisibleIcons = true
end
