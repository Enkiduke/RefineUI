----------------------------------------------------------------------------------------
-- RefineUI Toasts
-- Description: Skins Blizzard alert toasts as uniform cards and adds RefineUI toasts
--              to the same AlertFrame queue.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Toasts = RefineUI:RegisterModule("Toasts", function(cfg)
    local settings = cfg.Toasts
    return not (type(settings) == "table" and settings.Enable == false)
end)

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs
local huge = math.huge
local ipairs = ipairs
local max = math.max
local min = math.min
local pairs = pairs
local sort = table.sort
local type = type
local unpack = unpack
local wipe = wipe

local BreakUpLargeNumbers = BreakUpLargeNumbers
local C_CurrencyInfo = C_CurrencyInfo
local C_Item = C_Item
local ColorManager = ColorManager
local CreateColorFromHexString = CreateColorFromHexString
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetTime = GetTime
local HandleModifiedItemClick = HandleModifiedItemClick
local InCombatLockdown = InCombatLockdown
local PlaySound = PlaySound
local UIParent = UIParent

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ANCHOR_NAME = "RefineUI_ToastAnchor"
local MODULE_TITLE = "Toasts"
local TEMPLATE = "RefineUIToastAlertFrameTemplate"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local QUESTION_ICON = 134400
local INVASION_ICON = "Interface\\Icons\\Ability_Warlock_DemonicPower"

local BACKGROUND_ATLAS = "UI-Frame-Delves-notification-frame"
local GLOW_TEXTURE = "Interface\\AchievementFrame\\UI-Achievement-Alert-Glow"

local CARD_WIDTH = 220
local CARD_HEIGHT = 44
local ICON_SIZE = 28
-- Icon border offset outside the icon (the "Icon" template default is 4).
local ICON_BORDER_INSET = 6
local BAR_HEIGHT = 1
-- The RefineUI border (12px edge, 4px outside) stays solid about 2.5px into the card.
local BAR_INSET = 3
local STACK_SPACING = 8
local SLIDE_DISTANCE = 24
local SLIDE_SPEED = 12
local SHINE_WIDTH, SHINE_HEIGHT = 66, 52
local GLOW_WIDTH, GLOW_HEIGHT = 312, 140
-- A RefineUI toast for something a Blizzard special loot alert showed within this window is a duplicate.
local SPECIAL_WINDOW = 3

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local GLOW_COORDS = { 5 / 512, 395 / 512, 5 / 256, 167 / 256 }
local SHINE_COORDS = { 403 / 512, 465 / 512, 14 / 256, 62 / 256 }
-- Rising upgrade arrows: start delay and x offset from the icon's bottom center.
local ARROWS = {
    { 0, 0 },
    { 0.1, -8 },
    { 0.2, 12 },
    { 0.3, 6 },
    { 0.4, -12 },
}
local TITLE_R, TITLE_G, TITLE_B = 1, 0.82, 0
local ACHIEVEMENT_COLOR = { r = 1, g = 0.675, b = 0.125 }
-- Alerts (entry.alert) share the card but get their own border color, badge, and sound.
local ALERT_COLOR = { r = 1, g = 0.5, b = 0.1 }
local ALERT_BADGE_ATLAS = "adventureguide-microbutton-alert"
local ALERT_BADGE_SIZE = 14
local ALERT_SOUND = SOUNDKIT.ALARM_CLOCK_WARNING_3

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
-- Blizzard toast art is parented here so SetUp and animation code keep working unseen.
local hider = CreateFrame("Frame")
hider:Hide()

local anchor
local cardWidth, cardHeight, stackSpacing, slideDistance, barInset, barWidth
local stack = {}         -- active alert frames, oldest first
local showCount = 0      -- orders alerts across subsystems
local stackCount = 0     -- active alerts at the last layout
local maxVisible
local pumping
local refineSystem       -- RefineUI subsystem on AlertFrame
local recipes = {}       -- Blizzard subsystem -> recipe
local byKey = {}         -- merge key -> live RefineUI entry
local held = {}          -- RefineUI entries held until combat ends
local specialTimes = {}  -- merge key -> time of the last Blizzard special loot alert

----------------------------------------------------------------------------------------
-- Blizzard Recipes
----------------------------------------------------------------------------------------
-- Each returns what the system's SetUp filled: icon, title, text, extra, color.
-- Regions are read after SetUp; plain values are used as-is.
local function ItemAlert(f)
    return f.Icon, f.Label, f.Name
end

local function TitleName(f)
    return f.Icon, f.Title, f.Name
end

local function MissionAlert(f)
    return f.MissionType, f.Title, f.Name
end

local BLIZZARD_RECIPES = {
    AchievementAlertSystem = function(f) return f.Icon.Texture, f.Unlocked, f.Name, f.Shield.Points, ACHIEVEMENT_COLOR end,
    CriteriaAlertSystem = function(f) return f.Icon.Texture, f.Unlocked, f.Name, nil, ACHIEVEMENT_COLOR end,
    MonthlyActivityAlertSystem = function(f) return f.Icon.Texture, f.Unlocked, f.Name end,
    GuildChallengeAlertSystem = function(f) return f.EmblemIcon, GUILD_CHALLENGE_LABEL, f.Type, f.Count end,
    GuildRenameAlertSystem = function(f) return nil, f.HeaderLabel, f.GuildName end,
    DungeonCompletionAlertSystem = function(f) return f.dungeonTexture, f.completionText, f.instanceName end,
    ScenarioAlertSystem = function(f) return f.dungeonTexture, SCENARIO_COMPLETED, f.dungeonName end,
    InvasionAlertSystem = function(f) return INVASION_ICON, SCENARIO_INVASION_COMPLETE, f.ZoneName end,
    DigsiteCompleteAlertSystem = function(f) return f.DigsiteTypeTexture, f.Title, f.DigsiteType end,
    EntitlementDeliveredAlertSystem = function(f) return f.Icon, BLIZZARD_STORE_PURCHASE_COMPLETE, f.Title end,
    RafRewardDeliveredAlertSystem = function(f) return f.Icon, f.Description, f.Title end,
    GarrisonBuildingAlertSystem = TitleName,
    GarrisonMissionAlertSystem = MissionAlert,
    GarrisonShipMissionAlertSystem = MissionAlert,
    GarrisonRandomMissionAlertSystem = function(f) return f.MissionType, GARRISON_MISSION_ADDED_TOAST1, GARRISON_MISSION_ADDED_TOAST2, f.Level end,
    GarrisonFollowerAlertSystem = function(f) return f.PortraitFrame.Portrait, f.Title, f.Name end,
    GarrisonShipFollowerAlertSystem = function(f) return f.Portrait, f.Title, f.Name end,
    GarrisonTalentAlertSystem = TitleName,
    WorldQuestCompleteAlertSystem = function(f) return f.QuestTexture, f.ToastText, f.QuestName end,
    LegendaryItemAlertSystem = function(f) return f.Icon, LEGENDARY_ITEM_LOOT_LABEL, f.ItemName end,
    LootAlertSystem = function(f) return f.lootItem.Icon, f.Label, f.ItemName, f.lootItem.Count end,
    LootUpgradeAlertSystem = function(f) return f.Icon, f.TitleText, f.WhiteText end,
    MoneyWonAlertSystem = function(f) return f.Icon, f.Label, f.Amount end,
    HonorAwardedAlertSystem = function(f) return f.Icon, f.Label, f.Amount end,
    NewRecipeLearnedAlertSystem = TitleName,
    SkillLineSpecsUnlockedAlertSystem = TitleName,
    NewPetAlertSystem = ItemAlert,
    NewMountAlertSystem = ItemAlert,
    NewToyAlertSystem = ItemAlert,
    NewWarbandSceneAlertSystem = ItemAlert,
    NewRuneforgePowerAlertSystem = ItemAlert,
    NewCosmeticAlertFrameSystem = ItemAlert,
    HousingItemEarnedAlertFrameSystem = function(f) return f.Icon, f.CollectedLabel, f.DecorName end,
    InitiativeTaskCompleteAlertFrameSystem = function(f) return f.Checkmark, f.CompletedLabel, f.TaskName end,
}

----------------------------------------------------------------------------------------
-- Card
----------------------------------------------------------------------------------------
local function AddAlpha(group, key, order, from, to, duration, delay)
    local anim = group:CreateAnimation("Alpha")
    anim:SetChildKey(key)
    anim:SetOrder(order)
    anim:SetFromAlpha(from)
    anim:SetToAlpha(to)
    anim:SetDuration(duration)
    anim:SetStartDelay(delay or 0)
    return anim
end

local function SetBar(card, fraction)
    card.barFraction = fraction
    card.Bar:SetWidth(max(barWidth * fraction, 0.001))
end

local function Bar_OnUpdate(card)
    local fraction = card.barFrom * (1 - (GetTime() - card.barStart) / card.barDelay)
    if fraction <= 0 then
        fraction = 0
        card:SetScript("OnUpdate", nil)
    end
    SetBar(card, fraction)
end

-- Drains the bar from its current fill over the fade-out delay.
local function StartBar(card, delay)
    if delay <= 0 then
        SetBar(card, 0)
        return
    end
    card.barFrom = card.barFraction
    card.barStart = GetTime()
    card.barDelay = delay
    card:SetScript("OnUpdate", Bar_OnUpdate)
end

local function WaitGroup_OnPlay(group)
    local card = group:GetParent().RefineCard
    if card then
        StartBar(card, group.animOut:GetStartDelay())
    end
end

local function WaitGroup_OnStop(group)
    local card = group:GetParent().RefineCard
    if card then
        card:SetScript("OnUpdate", nil)
    end
end

local function Card_OnHide(card)
    card:SetScript("OnUpdate", nil)
    SetBar(card, 1)
end

local function CreateCard(frame)
    local card = CreateFrame("Frame", nil, frame)
    card:SetAllPoints()
    RefineUI.SetTemplate(card, "Zero")

    local background = card:CreateTexture(nil, "BACKGROUND", nil, -7)
    background:SetAtlas(BACKGROUND_ATLAS)
    background:SetAllPoints()

    local slot = CreateFrame("Frame", nil, card)
    slot:SetSize(RefineUI:Scale(ICON_SIZE), RefineUI:Scale(ICON_SIZE))
    slot:SetPoint("LEFT", RefineUI:Scale(7), 0)
    RefineUI.SetTemplate(slot, "Icon")
    RefineUI.CreateBorder(slot, ICON_BORDER_INSET, ICON_BORDER_INSET)
    card.IconSlot = slot

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    card.Icon = icon

    local badgeFrame = CreateFrame("Frame", nil, slot)
    badgeFrame:SetAllPoints()
    badgeFrame:SetFrameLevel(slot.border:GetFrameLevel() + 1)
    local badge = badgeFrame:CreateTexture(nil, "OVERLAY")
    badge:SetAtlas(ALERT_BADGE_ATLAS)
    badge:SetSize(RefineUI:Scale(ALERT_BADGE_SIZE), RefineUI:Scale(ALERT_BADGE_SIZE))
    badge:SetPoint("CENTER", slot, "TOPRIGHT", -2, -2)
    badge:Hide()
    card.Badge = badge

    local count = card:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(count, 12)
    count:SetPoint("RIGHT", -RefineUI:Scale(8), 0)
    count:SetJustifyH("RIGHT")
    card.Count = count

    local title = card:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(title, 10)
    title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", RefineUI:Scale(9), -1)
    title:SetPoint("RIGHT", count, "LEFT", -RefineUI:Scale(6), 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    card.Title = title

    local text = card:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(text, 12)
    text:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", RefineUI:Scale(9), 1)
    text:SetPoint("RIGHT", count, "LEFT", -RefineUI:Scale(6), 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    card.Text = text

    local flash = card:CreateTexture(nil, "OVERLAY")
    flash:SetTexture(WHITE_TEXTURE)
    flash:SetBlendMode("ADD")
    flash:SetAllPoints()
    flash:SetAlpha(0)
    local pulse = flash:CreateAnimationGroup()
    local pulseIn = pulse:CreateAnimation("Alpha")
    pulseIn:SetFromAlpha(0)
    pulseIn:SetToAlpha(0.25)
    pulseIn:SetDuration(0.12)
    pulseIn:SetOrder(1)
    local pulseOut = pulse:CreateAnimation("Alpha")
    pulseOut:SetFromAlpha(0.25)
    pulseOut:SetToAlpha(0)
    pulseOut:SetDuration(0.35)
    pulseOut:SetOrder(2)
    card.Flash = flash
    card.Pulse = pulse

    -- Above the border frame, inset past its solid edge.
    local barFrame = CreateFrame("Frame", nil, card)
    barFrame:SetAllPoints()
    barFrame:SetFrameLevel(card.border:GetFrameLevel() + 1)
    local bar = barFrame:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(WHITE_TEXTURE)
    bar:SetPoint("BOTTOMLEFT", barInset, barInset)
    bar:SetSize(barWidth, RefineUI:Scale(BAR_HEIGHT))
    card.Bar = bar
    card.barFraction = 1
    card:SetScript("OnHide", Card_OnHide)

    -- Intro: glow flare and a sheen sweeping across (ls_Toasts style).
    local glow = card:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetTexture(GLOW_TEXTURE)
    glow:SetTexCoord(unpack(GLOW_COORDS))
    glow:SetSize(RefineUI:Scale(GLOW_WIDTH), RefineUI:Scale(GLOW_HEIGHT))
    glow:SetPoint("CENTER")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    card.Glow = glow

    local shine = card:CreateTexture(nil, "OVERLAY", nil, 1)
    shine:SetTexture(GLOW_TEXTURE)
    shine:SetTexCoord(unpack(SHINE_COORDS))
    shine:SetSize(RefineUI:Scale(SHINE_WIDTH), cardHeight)
    shine:SetPoint("LEFT")
    shine:SetBlendMode("ADD")
    shine:SetAlpha(0)
    card.Shine = shine

    local intro = card:CreateAnimationGroup()
    intro:SetToFinalAlpha(true)
    AddAlpha(intro, "Glow", 1, 0, 1, 0.2)
    AddAlpha(intro, "Glow", 2, 1, 0, 0.5)
    AddAlpha(intro, "Shine", 1, 0, 1, 0.2)
    local sweep = intro:CreateAnimation("Translation")
    sweep:SetChildKey("Shine")
    sweep:SetOrder(2)
    sweep:SetOffset(cardWidth - RefineUI:Scale(SHINE_WIDTH), 0)
    sweep:SetDuration(0.85)
    AddAlpha(intro, "Shine", 2, 1, 0, 0.5, 0.35)
    card.Intro = intro

    -- Upgrade: arrows rising from the icon.
    local arrows = slot:CreateAnimationGroup()
    arrows:SetToFinalAlpha(true)
    for i = 1, #ARROWS do
        local delay, x = ARROWS[i][1], ARROWS[i][2]
        local key = "Arrow" .. i
        local arrow = slot:CreateTexture(nil, "OVERLAY", nil, 3)
        arrow:SetPoint("CENTER", icon, "BOTTOM", RefineUI:Scale(x), 0)
        arrow:SetAlpha(0)
        slot[key] = arrow

        AddAlpha(arrows, key, 1, 0, 1, 0.25, delay):SetSmoothing("IN")
        AddAlpha(arrows, key, 1, 1, 0, 0.25, delay + 0.25):SetSmoothing("OUT")
        local rise = arrows:CreateAnimation("Translation")
        rise:SetChildKey(key)
        rise:SetOrder(1)
        rise:SetOffset(0, RefineUI:Scale(40))
        rise:SetStartDelay(delay)
        rise:SetDuration(0.5)
    end
    card.Arrows = arrows

    -- The duration bar follows Blizzard's fade-out timer, including hover pauses.
    local waitGroup = frame.waitAndAnimOut
    if waitGroup then
        waitGroup:HookScript("OnPlay", WaitGroup_OnPlay)
        waitGroup:HookScript("OnStop", WaitGroup_OnStop)
        if waitGroup:IsPlaying() then
            StartBar(card, waitGroup.animOut:GetStartDelay())
        end
    end

    frame.RefineCard = card
    return card
end

local function PlayIntro(card, arrowAtlas)
    card.Intro:Restart()
    if arrowAtlas then
        for i = 1, #ARROWS do
            card.IconSlot["Arrow" .. i]:SetAtlas(arrowAtlas, true)
        end
        card.Arrows:Restart()
    end
end

-- Borders take the item quality (or toast) color; nil keeps the RefineUI border color.
local function SetCardColor(card, color)
    local r, g, b
    if color then
        r, g, b = color.r, color.g, color.b
    else
        r, g, b = unpack(RefineUI.Config.General.BorderColor)
    end
    card.border:SetBackdropBorderColor(r, g, b, 1)
    card.IconSlot.border:SetBackdropBorderColor(r, g, b, 1)
    card.Bar:SetVertexColor(r, g, b, 0.9)
    card.Flash:SetVertexColor(r, g, b)
    card.Glow:SetVertexColor(r, g, b)
    card.Shine:SetVertexColor(r, g, b)
end

----------------------------------------------------------------------------------------
-- Blizzard Alerts
----------------------------------------------------------------------------------------
local function StripFrame(frame)
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        regions[i]:SetParent(hider)
    end

    local card = frame.RefineCard
    local children = { frame:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child ~= card then
            child:SetParent(hider)
        end
    end
end

local function CopyIcon(icon, source)
    if type(source) == "table" then
        local atlas = source:GetAtlas()
        if atlas then
            icon:SetAtlas(atlas)
            return
        end
        local texture = source:GetTexture()
        if texture then
            icon:SetTexture(texture)
            local ulx, uly, llx, lly, urx, ury, lrx, lry = source:GetTexCoord()
            if ulx == 0 and uly == 0 and lrx == 1 and lry == 1 then
                icon:SetTexCoord(unpack(ICON_CROP))
            else
                icon:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
            end
            return
        end
        source = nil
    end
    icon:SetTexture(source or QUESTION_ICON)
    icon:SetTexCoord(unpack(ICON_CROP))
end

local function GetLabel(value)
    if type(value) == "table" then
        return value:GetText()
    end
    return value
end

-- Item alerts color by the item's quality; others by a leading color code in their text.
local function ResolveColor(frame, text)
    local link = frame.hyperlink
    if link and not frame.isCurrency then
        local quality = C_Item.GetItemQualityByID(link)
        local colorData = quality and ColorManager.GetColorDataForItemQuality(quality)
        if colorData then
            return colorData, true
        end
    end

    local hex = text and text:match("^|c(%x%x%x%x%x%x%x%x)")
    if hex then
        return CreateColorFromHexString(hex)
    end
    return nil
end

local function SkinBlizzardAlert(frame, recipe)
    local card = frame.RefineCard
    -- Pooled frames keep their stripped state; only SetUp-created children need another pass.
    if frame:GetNumRegions() > 0 or frame:GetNumChildren() > (card and 1 or 0) then
        StripFrame(frame)
    end
    card = card or CreateCard(frame)
    frame:SetSize(cardWidth, cardHeight)

    local icon, title, text, extra, color = recipe(frame)
    CopyIcon(card.Icon, icon)
    card.Title:SetText(GetLabel(title) or "")
    card.Text:SetText(GetLabel(text) or "")
    card.Count:SetText(extra and extra:IsShown() and extra:GetText() or "")

    local isQuality
    if not color then
        color, isQuality = ResolveColor(frame, card.Text:GetText())
    end
    SetCardColor(card, color)

    if isQuality then
        card.Text:SetTextColor(color.r, color.g, color.b)
    elseif type(text) == "table" then
        card.Text:SetTextColor(text:GetTextColor())
    else
        card.Text:SetTextColor(1, 1, 1)
    end

    -- LootUpgradeFrame_SetUp sets the upgrade quality's arrow atlas on Arrow1-5.
    local arrow = frame.Arrow1
    PlayIntro(card, arrow and arrow:GetAtlas())
end

-- Merge key of what a Blizzard special loot alert showed, so RefineUI skips its own toast.
local function GetSpecialKey(frame, system)
    if system == _G.MoneyWonAlertSystem then
        return "money"
    end
    local link = frame.hyperlink
    if not link then
        return
    end
    if frame.isCurrency then
        local currencyID = C_CurrencyInfo.GetCurrencyIDFromLink(link)
        return currencyID and "currency:" .. currencyID
    end
    local itemID = C_Item.GetItemInfoInstant(link)
    return itemID and "item:" .. itemID
end

local function MarkSpecial(key)
    specialTimes[key] = GetTime()
    local entry = byKey[key]
    if entry then
        byKey[key] = nil
        entry.cancelled = true
        if entry.frame then
            entry.frame:Hide()
        end
    end
end

----------------------------------------------------------------------------------------
-- Stack Layout (top anchored, grows down; replaces AlertFrameQueueMixin's bottom-up chain)
----------------------------------------------------------------------------------------
local function SortByShowOrder(a, b)
    return a.refineOrder < b.refineOrder
end

local function Stack_OnUpdate(self, elapsed)
    local step = min(1, elapsed * SLIDE_SPEED)
    local moving = false

    for i = 1, #stack do
        local frame = stack[i]
        local x, y, targetY = frame.refineX, frame.refineY, frame.refineTargetY
        if abs(x) > 0.5 or abs(targetY - y) > 0.5 then
            x = x - x * step
            y = y + (targetY - y) * step
            moving = true
        else
            x, y = 0, targetY
        end
        frame.refineX, frame.refineY = x, y
        frame:SetPoint("TOP", anchor, "TOP", x, -y)
    end

    if not moving then
        self:SetScript("OnUpdate", nil)
    end
end

-- Active alerts across every pooled subsystem (includes ones acquired but not yet shown).
local function CountActive()
    local count = 0
    for _, system in ipairs(AlertFrame.alertFrameSubSystems) do
        local pool = system.alertFramePool
        if pool then
            count = count + pool:GetNumActive()
        end
    end
    return count
end

-- A released alert only rechecks its own queue; give the free slot to any waiting subsystem.
local function PumpQueues()
    if pumping then
        return
    end
    pumping = true
    for _, system in ipairs(AlertFrame.alertFrameSubSystems) do
        if system.alertFramePool then
            while system:GetNumQueuedAlerts() > 0 and system:CheckQueuedAlerts() do
            end
        end
    end
    pumping = false
end

-- Runs after AlertFrame:UpdateAnchors (alert shown or released) and after skinning resizes.
local function LayoutStack()
    wipe(stack)
    for _, system in ipairs(AlertFrame.alertFrameSubSystems) do
        local pool = system.alertFramePool
        if pool then
            for frame in pool:EnumerateActive() do
                -- Not shown yet: acquired for a new alert, so it slides in from the left.
                if not frame:IsShown() then
                    showCount = showCount + 1
                    frame.refineOrder = showCount
                    frame.refineX = -slideDistance
                    frame.refineY = nil
                end
                frame.refineOrder = frame.refineOrder or 0
                stack[#stack + 1] = frame
            end
        end
    end
    sort(stack, SortByShowOrder)

    local y = 0
    for i = 1, #stack do
        local frame = stack[i]
        frame.refineTargetY = y
        frame.refineX = frame.refineX or 0
        frame.refineY = frame.refineY or y
        frame:ClearAllPoints()
        frame:SetPoint("TOP", anchor, "TOP", frame.refineX, -frame.refineY)
        y = y + frame:GetHeight() + stackSpacing
    end

    anchor:SetScript("OnUpdate", Stack_OnUpdate)

    local shrank = #stack < stackCount
    stackCount = #stack
    if shrank then
        PumpQueues()
    end
end

local function OnShowNewAlert(frame)
    if frame == BNToastFrame then
        if Toasts.db.Social then
            Toasts:RouteBNToast(frame)
        end
        return
    end

    local system = frame.queue
    if not system then
        return
    end

    if system == refineSystem then
        PlayIntro(frame.RefineCard)
        return
    end

    local recipe = recipes[system]
    if recipe then
        SkinBlizzardAlert(frame, recipe)
        LayoutStack()
    end

    local key = GetSpecialKey(frame, system)
    if key then
        MarkSpecial(key)
    end
end

----------------------------------------------------------------------------------------
-- RefineUI Toasts
----------------------------------------------------------------------------------------
local function FillEntry(frame)
    local entry = frame.entry
    local card = frame.RefineCard
    local color = entry.color or (entry.quality and ColorManager.GetColorDataForItemQuality(entry.quality))
        or (entry.alert and ALERT_COLOR)
    SetCardColor(card, color)
    card.Badge:SetShown(entry.alert == true)

    if entry.atlas then
        card.Icon:SetAtlas(entry.atlas)
    else
        card.Icon:SetTexture(entry.icon or QUESTION_ICON)
        card.Icon:SetTexCoord(unpack(entry.iconCoords or ICON_CROP))
    end
    card.Title:SetText(entry.title or "")

    local textColor = entry.textColor or (entry.quality and color) or HIGHLIGHT_FONT_COLOR
    card.Text:SetTextColor(textColor.r, textColor.g, textColor.b)

    local count = entry.count
    if entry.countFormat == "money" then
        card.Text:SetText(C_CurrencyInfo.GetCoinTextureString(count))
        card.Count:SetText("")
    else
        card.Text:SetText(entry.text or "")
        if entry.countFormat == "+" then
            card.Count:SetText("+" .. BreakUpLargeNumbers(count))
        elseif count and count > 1 then
            card.Count:SetText("x" .. count)
        else
            card.Count:SetText(entry.extra or "")
        end
    end
end

local function ReleaseEntry(frame)
    local entry = frame.entry
    if not entry then
        return
    end
    frame.entry = nil
    entry.frame = nil
    if entry.key and byKey[entry.key] == entry then
        byKey[entry.key] = nil
    end
end

local function Toast_OnEnter(self)
    AlertFrame_PauseOutAnimation(self)
    local link = self.entry and self.entry.link
    if link then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function Toast_OnLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
    AlertFrame_ResumeOutAnimation(self)
end

local function Toast_OnClick(self, button, down)
    if AlertFrame_OnClick(self, button, down) then
        return
    end
    local entry = self.entry
    if not entry then
        return
    end
    if entry.link and HandleModifiedItemClick(entry.link) then
        return
    end
    if entry.onClick then
        entry.onClick(entry)
    end
end

local function Toast_OnHide(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
    -- Releasing to the pool can show the next queued toast on this same frame.
    if not self:IsShown() then
        ReleaseEntry(self)
    end
end

local function RefineToast_SetUp(frame, entry)
    if entry.cancelled then
        return false
    end

    if not frame.RefineCard then
        CreateCard(frame)
        frame:SetScript("OnEnter", Toast_OnEnter)
        frame:SetScript("OnLeave", Toast_OnLeave)
        frame:SetScript("OnClick", Toast_OnClick)
        frame:HookScript("OnHide", Toast_OnHide)
    end

    ReleaseEntry(frame)
    frame.entry = entry
    entry.frame = frame
    frame:SetSize(cardWidth, cardHeight)
    FillEntry(frame)
    AlertFrame_SetDuration(frame, entry.duration or Toasts.db.Duration)

    local sound = entry.alert and ALERT_SOUND or entry.sound
    if sound and Toasts.db.Sound then
        PlaySound(sound)
    end
end

-- entry fields:
--   key          merge key; a live entry with the same key is updated instead of duplicated
--   icon         texture path or fileID; iconCoords overrides the default icon crop
--   title        small gold label; text: main line
--   quality      item quality (colors accent and text); color/textColor override with {r,g,b}
--   count        number merged by addition; countFormat "+" (delta) or "money" (coin string)
--   extra        short right-aligned text when no count is shown
--   link         hyperlink for tooltip and modified clicks; onClick(entry) for left clicks
--   sound        SOUNDKIT id; duration: seconds override
--   alert        alert styling: alert border color, badge, and the alert sound
--   atlas        icon atlas instead of icon
function Toasts:Add(entry)
    local key = entry.key
    if key then
        local specialTime = specialTimes[key]
        if specialTime and GetTime() - specialTime < SPECIAL_WINDOW then
            return
        end

        local existing = byKey[key]
        if existing then
            if entry.count and existing.count then
                existing.count = existing.count + entry.count
            else
                for field, value in pairs(entry) do
                    existing[field] = value
                end
            end

            local frame = existing.frame
            if frame then
                local card = frame.RefineCard
                FillEntry(frame)
                card.Pulse:Restart()
                SetBar(card, 1)
                AlertFrame_PlayOutroAnimation(frame)
            end
            return
        end
        byKey[key] = entry
    end

    -- RefineUI toasts are low priority; hold them until combat ends.
    if InCombatLockdown() then
        held[#held + 1] = entry
        return
    end

    refineSystem:AddAlert(entry)
end

local function FlushHeld()
    for i = 1, #held do
        local entry = held[i]
        held[i] = nil
        if not entry.cancelled then
            refineSystem:AddAlert(entry)
        end
    end
end

----------------------------------------------------------------------------------------
-- Position / Edit Mode
----------------------------------------------------------------------------------------
local function GetDefaultPosition()
    local point, relativeTo, relativePoint, x, y = unpack(RefineUI.Positions[ANCHOR_NAME])
    return point, _G[relativeTo] or UIParent, relativePoint, x, y
end

function Toasts:ApplyPosition()
    local pos = self.db.Position
    anchor:ClearAllPoints()
    if type(pos) == "table" and pos[1] then
        anchor:SetPoint(pos[1], UIParent, pos[3] or pos[1], pos[4] or 0, pos[5] or 0)
    else
        anchor:SetPoint(GetDefaultPosition())
    end
end

function Toasts:RegisterEditMode()
    local lib = RefineUI.LibEditMode
    if not lib then
        return
    end

    local defaultPoint, _, _, defaultX, defaultY = GetDefaultPosition()
    lib:AddFrame(anchor, function(_, _, point, x, y)
        if point == defaultPoint and x == defaultX and y == defaultY then
            -- Reset: return to the default position.
            self.db.Position = nil
        else
            self.db.Position = { point, "UIParent", point, x, y }
        end
        self:ApplyPosition()
    end, {
        point = defaultPoint,
        x = defaultX,
        y = defaultY,
    }, MODULE_TITLE)
end

----------------------------------------------------------------------------------------
-- Test
----------------------------------------------------------------------------------------
local TEST_INTERVAL = 0.25
local TEST_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
-- Follower IDs are GUID strings; hover calls C_Garrison.GetFollowerLink(followerID).
local TEST_FOLLOWER_ID = "0x0000000000000000"
local testTicker

local function TestRewardData(name, icon)
    return {
        name = name,
        subtypeID = LFG_SUBTYPEID_HEROIC,
        iconTextureFile = icon,
        moneyAmount = 123456,
        experienceGained = 12345,
        numRewards = 1,
        rewards = { { texturePath = "Interface\\Icons\\INV_Misc_Coin_02", rewardID = 0 } },
        hasBonusStep = true,
        isBonusStepComplete = true,
    }
end

-- One entry per skinned Blizzard system plus each RefineUI source; a step returning false is skipped.
local function BuildTests()
    local _, hearthstone = C_Item.GetItemInfo(6948)
    local garrisonFollower = Enum.GarrisonFollowerType.FollowerType_6_0_GarrisonFollower
    local missionInfo = { name = "Test Mission", typeAtlas = "GarrMission_MissionIcon-Combat", followerTypeID = garrisonFollower, level = 40, iLevel = 0, isRare = true }

    return {
        { "Achievement", function() AchievementAlertSystem:AddAlert(6, false) end },
        { "Criteria", function() CriteriaAlertSystem:AddAlert(6, "Test Criteria") end },
        { "Loot Won", function() return hearthstone ~= nil and LootAlertSystem:AddAlert(hearthstone, 1) end },
        { "Loot Upgrade", function() return hearthstone ~= nil and LootUpgradeAlertSystem:AddAlert(hearthstone, 1, nil, Enum.ItemQuality.Poor) end },
        { "Legendary Item", function() return hearthstone ~= nil and LegendaryItemAlertSystem:AddAlert(hearthstone) end },
        { "Money Won", function() MoneyWonAlertSystem:AddAlert(98765) end },
        { "Honor Awarded", function() HonorAwardedAlertSystem:AddAlert(250) end },
        { "Dungeon Completion", function() DungeonCompletionAlertSystem:AddAlert(TestRewardData("Test Dungeon", "Interface\\LFGFrame\\LFGIcon-Dungeon")) end },
        { "Scenario Completion", function() ScenarioAlertSystem:AddAlert(TestRewardData("Test Scenario", "Interface\\Icons\\INV_Misc_Map_01")) end },
        { "Invasion", function() InvasionAlertSystem:AddAlert(999998, "Test Invasion", true, 8000, 45000) end },
        { "World Quest", function()
            WorldQuestCompleteAlertSystem:AddAlert({ questID = 999999, taskName = "Test World Quest", icon = TEST_ICON, displayAsObjective = false, money = 23456, xp = 6789, currencyRewards = {} })
        end },
        { "Digsite", function() DigsiteCompleteAlertSystem:AddAlert("Night Elf", "Interface\\Icons\\Trade_Archaeology_NightElf_Crystal") end },
        { "Store Purchase", function() EntitlementDeliveredAlertSystem:AddAlert(Enum.WoWEntitlementType.Item, TEST_ICON, "Test Purchase", 6948, true) end },
        { "Recruit-a-Friend", function() RafRewardDeliveredAlertSystem:AddAlert(Enum.WoWEntitlementType.Mount, TEST_ICON, "Test Reward", 6, true, 3) end },
        { "Garrison Building", function() GarrisonBuildingAlertSystem:AddAlert("Test Building", Enum.GarrisonType.Type_6_0_Garrison) end },
        { "Garrison Mission", function() GarrisonMissionAlertSystem:AddAlert(missionInfo) end },
        { "Garrison Ship Mission", function() GarrisonShipMissionAlertSystem:AddAlert(missionInfo) end },
        { "Garrison Random Mission", function() GarrisonRandomMissionAlertSystem:AddAlert(missionInfo) end },
        { "Garrison Follower", function()
            local info = { followerTypeID = garrisonFollower, portraitIconID = QUESTION_ICON, quality = 4, level = 40, iLevel = 675, isTroop = false }
            GarrisonFollowerAlertSystem:AddAlert(TEST_FOLLOWER_ID, "Test Follower", 40, 4, false, info)
        end },
        { "Garrison Ship Follower", function() GarrisonShipFollowerAlertSystem:AddAlert(TEST_FOLLOWER_ID, "Test Ship", "Destroyer", nil, 1, 3, false, {}) end },
        { "Garrison Talent", function() GarrisonTalentAlertSystem:AddAlert(Enum.GarrisonType.Type_7_0_Garrison, { icon = TEST_ICON, treeID = 0 }) end },
        { "Recipe Learned", function() NewRecipeLearnedAlertSystem:AddAlert(2538) end },
        { "Specializations Unlocked", function() SkillLineSpecsUnlockedAlertSystem:AddAlert(164, 164) end },
        { "New Pet", function()
            local petID = C_PetJournal.GetPetInfoByIndex(1)
            return petID ~= nil and NewPetAlertSystem:AddAlert(petID)
        end },
        { "New Mount", function() NewMountAlertSystem:AddAlert(6) end },
        { "New Toy", function()
            local toyID = C_ToyBox.GetToyFromIndex(1)
            return toyID ~= nil and toyID > 0 and NewToyAlertSystem:AddAlert(toyID)
        end },
        { "New Warband Scene", function()
            local sceneID = C_WarbandScene.GetRandomEntryID()
            return sceneID ~= nil and NewWarbandSceneAlertSystem:AddAlert(sceneID)
        end },
        { "New Runeforge Power", function()
            local primary, other = C_LegendaryCrafting.GetRuneforgePowers()
            local powerID = (primary and primary[1]) or (other and other[1])
            return powerID ~= nil and NewRuneforgePowerAlertSystem:AddAlert(powerID)
        end },
        { "New Cosmetic", function()
            local link = GetInventoryItemLink("player", INVSLOT_CHEST)
            local sourceID = link and select(2, C_TransmogCollection.GetItemInfo(link))
            return sourceID ~= nil and NewCosmeticAlertFrameSystem:AddAlert(sourceID)
        end },
        { "Traveler's Log", function()
            local info = C_PerksActivities.GetPerksActivitiesInfo()
            local activity = info and info.activities[1]
            return activity ~= nil and MonthlyActivityAlertSystem:AddAlert(activity.ID)
        end },
        { "Housing Decor", function()
            HousingItemEarnedAlertFrameSystem:AddAlert({ itemType = Enum.HousingItemToastType.Decor, itemName = "Test Decor", icon = "Interface\\Icons\\INV_Misc_Houseground_City_Brick_01" })
        end },
        { "Endeavor Task", function() InitiativeTaskCompleteAlertFrameSystem:AddAlert("Test Endeavor Task") end },
        { "Guild Challenge", function() GuildChallengeAlertSystem:AddAlert(1, 1, 3) end },
        { "Guild Rename", function() GuildRenameAlertSystem:AddAlert("Test Guild") end },
        { "RefineUI Loot", function()
            Toasts:Add({ key = "test:item", icon = TEST_ICON, title = YOU_RECEIVED_LABEL, text = "Test Item", quality = 3, count = 1 })
        end },
        { "RefineUI Loot (merge)", function()
            Toasts:Add({ key = "test:item", icon = TEST_ICON, title = YOU_RECEIVED_LABEL, text = "Test Item", quality = 3, count = 2 })
        end },
        { "RefineUI Currency", function()
            Toasts:Add({ key = "test:currency", icon = "Interface\\Icons\\INV_Misc_Coin_17", title = CURRENCY, text = "Test Currency", quality = 4, count = 250, countFormat = "+" })
        end },
        { "RefineUI Gold", function()
            Toasts:Add({ key = "test:money", icon = "Interface\\Icons\\INV_Misc_Coin_01", title = MONEY, count = 124500, countFormat = "money" })
        end },
        { "RefineUI Battle.net", function()
            Toasts:Add({ key = "test:bnet", icon = "Interface\\FriendsFrame\\UI-Toast-ToastIcons", iconCoords = { 0, 0.25, 0.5, 1 }, title = BN_TOAST_ONLINE, text = "Test Friend", color = FRIENDS_BNET_NAME_COLOR, textColor = FRIENDS_BNET_NAME_COLOR })
        end },
        { "Alert: Mail", function()
            Toasts:Add({ alert = true, icon = "Interface\\Icons\\INV_Letter_15", title = RefineUI.Locale.Toasts.NewMail, text = "Test Sender" })
        end },
        { "Alert: Rare", function()
            Toasts:Add({ alert = true, atlas = "VignetteKillElite", title = RefineUI.Locale.Toasts.Rare, text = "Test Rare" })
        end },
    }
end

local function RunTest()
    if testTicker then
        testTicker:Cancel()
    end
    if not AchievementFrame then
        AchievementFrame_LoadUI()
    end
    if not GarrisonFollowerOptions then
        C_AddOns.LoadAddOn("Blizzard_GarrisonBase")
    end

    local tests = BuildTests()
    local index = 0
    testTicker = C_Timer.NewTicker(TEST_INTERVAL, function()
        index = index + 1
        local name, run = tests[index][1], tests[index][2]
        local ok, result = pcall(run)
        if not ok then
            RefineUI:Error("toasttest", name, result)
        elseif result == false then
            RefineUI:Print("toasttest skipped: " .. name)
        end
    end, #tests)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Toasts:OnEnable()
    self.db = RefineUI.Config.Toasts

    cardWidth = RefineUI:Scale(CARD_WIDTH)
    cardHeight = RefineUI:Scale(CARD_HEIGHT)
    stackSpacing = RefineUI:Scale(STACK_SPACING)
    slideDistance = RefineUI:Scale(SLIDE_DISTANCE)
    barInset = RefineUI:Scale(BAR_INSET)
    barWidth = cardWidth - 2 * barInset

    anchor = CreateFrame("Frame", ANCHOR_NAME, UIParent)
    anchor:SetSize(cardWidth, cardHeight)
    anchor:SetClampedToScreen(true)
    self:ApplyPosition()
    self:RegisterEditMode()

    -- Alert systems without a pool (e.g. group loot) still chain from the base anchor.
    AlertFrame:SetBaseAnchorFrame(anchor)
    RefineUI:HookOnce("Toasts:AlertFrame:UpdateAnchors", AlertFrame, "UpdateAnchors", LayoutStack)
    AlertFrame:UpdateAnchors()

    maxVisible = self.db.MaxVisible
    refineSystem = AlertFrame:AddQueuedAlertFrameSubSystem(TEMPLATE, RefineToast_SetUp, maxVisible, huge)

    -- One cap across all toasts; extras wait in their own queue. Keeps Blizzard's existing
    -- conditions (e.g. AchievementAlertSystem waits out pet battles).
    for _, system in ipairs(AlertFrame.alertFrameSubSystems) do
        if system.alertFramePool then
            local condition = system.canShowMoreConditionFunc
            system:SetCanShowMoreConditionFunc(function()
                return CountActive() < maxVisible and (not condition or condition())
            end)
        end
    end

    if self.db.Blizzard then
        for name, recipe in pairs(BLIZZARD_RECIPES) do
            local system = _G[name]
            if system then
                recipes[system] = recipe
            end
        end
    end
    RefineUI:HookOnce("Toasts:AlertFrame_ShowNewAlert", "AlertFrame_ShowNewAlert", OnShowNewAlert)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", FlushHeld, "Toasts:PLAYER_REGEN_ENABLED")
    RefineUI:RegisterChatCommand("toasttest", RunTest)

    self:EnableSources()
    self:EnableAlerts()
end
