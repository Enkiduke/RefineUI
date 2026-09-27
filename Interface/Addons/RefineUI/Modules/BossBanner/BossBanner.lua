----------------------------------------------------------------------------------------
-- BossBanner for RefineUI
-- Description: Replaces Blizzard's boss kill/loot banner with a "Boss Defeated" badge.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local BossBanner = RefineUI:RegisterModule("BossBanner", "BossBanner")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local select = select
local tonumber = tonumber
local CreateFrame = CreateFrame
local GetInstanceInfo = GetInstanceInfo
local PlaySound = PlaySound
local EJ_GetCreatureInfo = EJ_GetCreatureInfo
local EJ_GetEncounterInfo = EJ_GetEncounterInfo
local EJ_GetEncounterInfoByIndex = EJ_GetEncounterInfoByIndex
local SetPortraitTextureFromCreatureDisplayID = SetPortraitTextureFromCreatureDisplayID

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BADGE_SIZE = 120
local PORTRAIT_SIZE = 66
local TEXT_WIDTH = 400
local DIVIDER_WIDTH = 220
local HOLD_TIME = 4
local FADE_TIME = 0.6
local SPIN_FAST_TIME = 0.3
local SPIN_SETTLE_TIME = 0.7
local SHEEN_TIME = 0.5
local SLIDE_OFFSET = 8
local TEST_JOURNAL_ENCOUNTER_ID = 198 -- Ragnaros (Firelands)
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

----------------------------------------------------------------------------------------
-- Encounter Lookup
----------------------------------------------------------------------------------------
-- BOSS_KILL reports the dungeon encounter ID; the portrait lives on the journal encounter.
local function FindJournalEncounter(dungeonEncounterID)
    local journalInstanceID = C_EncounterJournal.GetInstanceForGameMap(select(8, GetInstanceInfo()))
    if not journalInstanceID then
        return nil
    end

    local index = 1
    while true do
        local _, _, journalEncounterID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(index, journalInstanceID)
        if not journalEncounterID or encounterID == dungeonEncounterID then
            return journalEncounterID
        end
        index = index + 1
    end
end

----------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------
local function AddAnimation(group, animType, target, duration, delay)
    local anim = group:CreateAnimation(animType)
    anim:SetTarget(target)
    anim:SetDuration(duration)
    anim:SetStartDelay(delay or 0)
    anim:SetSmoothing("OUT")
    return anim
end

local function AddAlpha(group, target, duration, delay, fromAlpha, toAlpha)
    local anim = AddAnimation(group, "Alpha", target, duration, delay)
    anim:SetFromAlpha(fromAlpha)
    anim:SetToAlpha(toAlpha)
    return anim
end

local function AddScale(group, target, duration, delay, fromX, fromY, toX, toY)
    local anim = AddAnimation(group, "Scale", target, duration, delay)
    anim:SetScaleFrom(fromX, fromY)
    anim:SetScaleTo(toX, toY)
    return anim
end

local function AddSlideUp(group, target, duration, delay)
    AddAnimation(group, "Translation", target, duration, delay):SetOffset(0, SLIDE_OFFSET)
end

local function AddGoldGlow(parent, layer, subLevel, atlas)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    texture:SetAtlas(atlas)
    texture:SetBlendMode("ADD")
    texture:SetVertexColor(GOLD_R, GOLD_G, GOLD_B)
    return texture
end

function BossBanner:CreateBanner()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(TEXT_WIDTH, BADGE_SIZE + 90)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    frame:Hide()

    -- Badge: Mythic+ spiky star with the masked boss portrait in its center.
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("TOP")
    frame.Badge = badge

    local glow = badge:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetAtlas("ChallengeMode-SoftYellowGlow")
    glow:SetBlendMode("ADD")
    glow:SetSize(BADGE_SIZE * 1.8, BADGE_SIZE * 1.8)
    glow:SetPoint("CENTER")
    frame.Glow = glow

    local star = badge:CreateTexture(nil, "BORDER")
    star:SetAtlas("ChallengeMode-SpikeyStar")
    star:SetAllPoints()

    -- Lock-in effects: a sheen clipped to the star's shape and a spiky glow flare.
    local starMask = badge:CreateMaskTexture()
    starMask:SetAtlas("ChallengeMode-SpikeyStar")
    starMask:SetAllPoints()

    local sheen = badge:CreateTexture(nil, "ARTWORK")
    sheen:SetAtlas("loottoast-sheen")
    sheen:SetBlendMode("ADD")
    sheen:SetSize(BADGE_SIZE * 171 / 75, BADGE_SIZE)
    sheen:SetPoint("RIGHT", badge, "LEFT")
    sheen:AddMaskTexture(starMask)
    frame.Sheen = sheen

    local lockGlow = AddGoldGlow(badge, "ARTWORK", 1, "ChallengeMode-WhiteSpikeyGlow")
    lockGlow:SetSize(BADGE_SIZE * 1.15, BADGE_SIZE * 1.15)
    lockGlow:SetPoint("CENTER")
    frame.LockGlow = lockGlow

    local portraitFrame = CreateFrame("Frame", nil, badge)
    portraitFrame:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portraitFrame:SetPoint("CENTER")

    local mask = portraitFrame:CreateMaskTexture()
    mask:SetTexture(Media.Textures.PortraitMask)
    mask:SetAllPoints()

    local bg = portraitFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(Media.Textures.PortraitBG)
    bg:SetAllPoints()
    bg:AddMaskTexture(mask)

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetAllPoints()
    portrait:AddMaskTexture(mask)
    frame.Portrait = portrait

    local skull = portraitFrame:CreateTexture(nil, "ARTWORK")
    skull:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcon_8]])
    skull:SetSize(PORTRAIT_SIZE * 0.55, PORTRAIT_SIZE * 0.55)
    skull:SetPoint("CENTER")
    frame.Skull = skull

    local shock = AddGoldGlow(portraitFrame, "OVERLAY", 1, "ChallengeMode-WhiteSpikeyGlow")
    shock:SetAllPoints(badge)
    frame.Shock = shock

    -- Text: label, divider, boss name. Anchored SLIDE_OFFSET low; the in-animation slides them up.
    local title = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(title, 13, Media.Fonts.Bold)
    title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    title:SetText("BOSS DEFEATED")
    title:SetPoint("TOP", badge, "BOTTOM", 0, -SLIDE_OFFSET)
    frame.Title = title

    local divider = CreateFrame("Frame", nil, frame)
    divider:SetSize(DIVIDER_WIDTH, 1)
    divider:SetPoint("TOP", title, "BOTTOM", 0, -6 + SLIDE_OFFSET)
    frame.Divider = divider

    local left = divider:CreateTexture(nil, "ARTWORK")
    left:SetTexture(Media.Textures.Blank)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", divider, "BOTTOM")
    left:SetGradient("HORIZONTAL", CreateColor(GOLD_R, GOLD_G, GOLD_B, 0), CreateColor(GOLD_R, GOLD_G, GOLD_B, 1))

    local right = divider:CreateTexture(nil, "ARTWORK")
    right:SetTexture(Media.Textures.Blank)
    right:SetPoint("TOPLEFT", divider, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    right:SetGradient("HORIZONTAL", CreateColor(GOLD_R, GOLD_G, GOLD_B, 1), CreateColor(GOLD_R, GOLD_G, GOLD_B, 0))

    local name = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(name, 26)
    name:SetWidth(TEXT_WIDTH)
    name:SetMaxLines(2)
    name:SetPoint("TOP", divider, "BOTTOM", 0, -8 - SLIDE_OFFSET)
    frame.Name = name

    -- One pass: the star slams in spinning and locks with a flare and sheen,
    -- text follows, then the banner fades out.
    local anim = frame:CreateAnimationGroup()
    anim:SetToFinalAlpha(true)

    AddAlpha(anim, badge, 0.25, 0, 0, 1)
    AddScale(anim, badge, 0.2, 0, 3, 3, 1, 1)
    AddAlpha(anim, glow, 0.5, 0.15, 0, 0.8)
    AddAlpha(anim, shock, 0.7, 0.2, 0.9, 0)
    AddScale(anim, shock, 0.7, 0.2, 1, 1, 1.7, 1.7)

    -- One full turn: a fast constant spin, then an ease into the default position.
    local spin = AddAnimation(anim, "Rotation", star, SPIN_FAST_TIME)
    spin:SetDegrees(-330)
    spin:SetSmoothing("NONE")
    AddAnimation(anim, "Rotation", star, SPIN_SETTLE_TIME, SPIN_FAST_TIME):SetDegrees(-30)

    -- Lock effects start just before the eased spin fully stops.
    local lockTime = SPIN_FAST_TIME + SPIN_SETTLE_TIME - 0.1
    AddAlpha(anim, lockGlow, 0.15, lockTime, 0, 1)
    AddAlpha(anim, lockGlow, 0.6, lockTime + 0.15, 1, 0)
    AddScale(anim, lockGlow, 0.75, lockTime, 0.9, 0.9, 1.15, 1.15)

    AddAlpha(anim, sheen, 0.1, lockTime, 0, 1)
    local sweep = AddAnimation(anim, "Translation", sheen, SHEEN_TIME, lockTime)
    sweep:SetOffset(BADGE_SIZE + sheen:GetWidth(), 0)
    sweep:SetSmoothing("IN_OUT")

    AddAlpha(anim, title, 0.3, 0.35, 0, 1)
    AddSlideUp(anim, title, 0.3, 0.35)

    AddAlpha(anim, divider, 0.45, 0.4, 0, 1)
    AddScale(anim, divider, 0.45, 0.4, 0.01, 1, 1, 1)

    AddAlpha(anim, name, 0.35, 0.5, 0, 1)
    AddSlideUp(anim, name, 0.35, 0.5)

    AddAlpha(anim, frame, FADE_TIME, 1 + HOLD_TIME, 1, 0)

    anim:SetScript("OnFinished", function()
        frame:Hide()
    end)
    frame.Anim = anim

    self.frame = frame
    return frame
end

----------------------------------------------------------------------------------------
-- Playback
----------------------------------------------------------------------------------------
function BossBanner:Play(name, journalEncounterID)
    local frame = self.frame or self:CreateBanner()
    local displayInfo = journalEncounterID and select(4, EJ_GetCreatureInfo(1, journalEncounterID))
    if displayInfo then
        SetPortraitTextureFromCreatureDisplayID(frame.Portrait, displayInfo)
    end
    frame.Portrait:SetShown(displayInfo ~= nil)
    frame.Skull:SetShown(displayInfo == nil)
    frame.Name:SetText(name)

    frame.Anim:Stop()
    frame:SetAlpha(1)
    frame.Badge:SetAlpha(0)
    frame.Glow:SetAlpha(0)
    frame.Shock:SetAlpha(0)
    frame.Sheen:SetAlpha(0)
    frame.LockGlow:SetAlpha(0)
    frame.Title:SetAlpha(0)
    frame.Divider:SetAlpha(0)
    frame.Name:SetAlpha(0)
    frame:Show()
    frame.Anim:Play()

    PlaySound(SOUNDKIT.UI_CHALLENGES_NEW_RECORD)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function BossBanner:OnEnable()
    -- Blizzard's banner shows only from these two events; unregistering them drops both
    -- the kill banner and the loot list.
    _G.BossBanner:UnregisterEvent("BOSS_KILL")
    _G.BossBanner:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")

    RefineUI:RegisterEventCallback("BOSS_KILL", function(_, encounterID, name)
        self:Play(name, RefineUI:IsAccessibleValue(encounterID) and FindJournalEncounter(encounterID) or nil)
    end, "BossBanner:Kill")

    -- /bossbanner [journalEncounterID]
    RefineUI:RegisterChatCommand("bossbanner", function(msg)
        local journalEncounterID = tonumber(msg) or TEST_JOURNAL_ENCOUNTER_ID
        self:Play(EJ_GetEncounterInfo(journalEncounterID) or UNKNOWN, journalEncounterID)
    end)
end
