local R, C, L = unpack(RefineUI)
if not C.reminder.soloBuffsEnable then return end

-- Use managed spells if available, otherwise fall back to default configuration
local tab = R.ReminderSelfBuffs and R.ReminderSelfBuffs[R.class]
if not tab then return end

----------------------------------------------------------------------------------------
-- Upvalues
----------------------------------------------------------------------------------------
local CreateFrame, PlaySoundFile, unpack = CreateFrame, PlaySoundFile, unpack
local select, GetWeaponEnchantInfo = select, GetWeaponEnchantInfo
local AuraUtil, C_Spell = AuraUtil, C_Spell
local ipairs, type = ipairs, type

----------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------
local function UpdateIcon(self, group)
    for _, spellData in ipairs(group.spells) do
        local name, icon, spellID = unpack(spellData)
        if spellID and type(spellID) == "number" then
            icon = C_Spell.GetSpellTexture(spellID) or icon
            if icon then
                self.icon:SetTexture(icon)
                return
            end
        end
    end
    self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
end

local function CheckBuffs(self, group)
    local buffMissing = true

    -- Check weapon enchants first (avoid repeated calls and aura loop if satisfied)
    if group.mainhand or group.offhand then
        local mhHas, _, _, _, ohHas = GetWeaponEnchantInfo()
        if (group.mainhand and mhHas) or (group.offhand and ohHas) then
            buffMissing = false
        end
    end

    -- If still missing, check configured auras on the player
    if buffMissing and group.spells then
        for _, spell in ipairs(group.spells) do
            local name = (unpack(spell))
            if AuraUtil.FindAuraByName(name, "player") then
                buffMissing = false
                break
            end
        end
    end

    if buffMissing then
        -- Only play sound on transition to shown to avoid spam
        if not self:IsShown() then
            if C.reminder.solo_buffs_sound and C.media and C.media.warningSound then
                PlaySoundFile(C.media.warningSound, "Master")
            end
        end
        self:Show()
    else
        self:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Event Handler
----------------------------------------------------------------------------------------
local function OnEvent(self, event, arg1)
    if (event == "UNIT_AURA" or event == "PLAYER_ENTERING_WORLD") and arg1 ~= "player" then return end
    
    local group = tab[self.id]
    if not group or not group.spells then return end

    UpdateIcon(self, group)
    CheckBuffs(self, group)
end

----------------------------------------------------------------------------------------
-- Frame Creation and Setup
----------------------------------------------------------------------------------------
local frames = {}
local primaryFrame

local function CreateReminderFrames()
    -- Clean up existing frames
    if primaryFrame then
        primaryFrame:Hide()
        for i, frame in ipairs(frames) do
            frame:Hide()
            frame:SetParent(nil)
        end
        wipe(frames)
    end

    -- Get current tab (could be updated from edit mode)
    tab = R.ReminderSelfBuffs and R.ReminderSelfBuffs[R.class]
    if not tab or #tab == 0 then return end

    -- Create the primary frame
    primaryFrame = CreateFrame("Frame", "RefineUI_SelfBuffsReminder", UIParent)
    primaryFrame:SetPoint(unpack(C.position.selfBuffs))
    primaryFrame:SetFrameLevel(5)

    -- Calculate total width based on number of buffs and their size
    local spacing = 5
    if R.SelfBuffsReminder and R.SelfBuffsReminder.FrameSettings and R.SelfBuffsReminder.FrameSettings[R.class] then
        spacing = R.SelfBuffsReminder.FrameSettings[R.class].space or 5
    end
    
    local iconSize = C.reminder.soloBuffsSize
    if R.SelfBuffsReminder and R.SelfBuffsReminder.FrameSettings and R.SelfBuffsReminder.FrameSettings[R.class] then
        iconSize = R.SelfBuffsReminder.FrameSettings[R.class].size or C.reminder.soloBuffsSize
    end

    local totalWidth = #tab * iconSize + (#tab - 1) * spacing
    primaryFrame:SetSize(totalWidth, iconSize)

    -- Create individual buff frames
    for i, group in ipairs(tab) do
        local frame = CreateFrame("Frame", "ReminderFrame"..i, primaryFrame)
        frame:SetSize(iconSize, iconSize)
        frame:SetPoint("LEFT", primaryFrame, "LEFT", (i-1) * (iconSize + spacing), 0)
        frame:SetTemplate("Default")
        frame:SetFrameLevel(6)
        frame.id = i

        -- Create and setup icon texture
        frame.icon = frame:CreateTexture(nil, "BACKGROUND")
        frame.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame.icon:SetAllPoints()

        -- Setup flash animation if enabled
        if C.reminder.soloBuffsFlash then
            local frameAG = frame:CreateAnimationGroup()
            local iconAG = frame.icon:CreateAnimationGroup()
            frameAG:SetLooping("REPEAT")
            iconAG:SetLooping("REPEAT")
            
            local frameFadeOut = frameAG:CreateAnimation("Alpha")
            local iconFadeOut = iconAG:CreateAnimation("Alpha")
            frameFadeOut:SetFromAlpha(1)
            frameFadeOut:SetToAlpha(0.1)
            frameFadeOut:SetDuration(0.5)
            frameFadeOut:SetSmoothing("IN_OUT")
            iconFadeOut:SetFromAlpha(1)
            iconFadeOut:SetToAlpha(0.1)
            iconFadeOut:SetDuration(0.5)
            iconFadeOut:SetSmoothing("IN_OUT")
            
            local frameFadeIn = frameAG:CreateAnimation("Alpha")
            local iconFadeIn = iconAG:CreateAnimation("Alpha")
            frameFadeIn:SetFromAlpha(0.1)
            frameFadeIn:SetToAlpha(1)
            frameFadeIn:SetDuration(0.5)
            frameFadeIn:SetSmoothing("IN_OUT")
            frameFadeIn:SetOrder(2)
            iconFadeIn:SetFromAlpha(0.1)
            iconFadeIn:SetToAlpha(1)
            iconFadeIn:SetDuration(0.5)
            iconFadeIn:SetSmoothing("IN_OUT")
            iconFadeIn:SetOrder(2)
            
            frameAG:Play()
            iconAG:Play()
        end

        -- Set up event handling
        frame:Hide()
        frame:SetScript("OnEvent", OnEvent)
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("UNIT_AURA")
        
        table.insert(frames, frame)
    end

    -- Center the primary frame
    primaryFrame:ClearAllPoints()
    primaryFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

-- Create initial frames
CreateReminderFrames()

-- Add refresh function to the global namespace for edit mode
R.SelfBuffsReminder = R.SelfBuffsReminder or {}
R.SelfBuffsReminder.RefreshReminders = function()
    CreateReminderFrames()
end