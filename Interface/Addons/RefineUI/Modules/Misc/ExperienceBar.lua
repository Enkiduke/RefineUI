local AddOnName, RefineUI = ...
local LibEditMode = LibStub("LibEditMode")

-- Call Modules
local ExperienceBar = RefineUI:RegisterModule("ExperienceBar", function(cfg)
    local unitFrames = cfg.UnitFrames
    local dataBars = type(unitFrames) == "table" and unitFrames.DataBars
    local experienceBar = type(dataBars) == "table" and dataBars.ExperienceBar
    if type(experienceBar) == "table" then
        return experienceBar.Enable ~= false
    end
    if type(experienceBar) == "boolean" then
        return experienceBar
    end
    return true
end)

-- Lib Globals
local _G = _G
local unpack = unpack
local ipairs = ipairs
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
local tostring = tostring
local tonumber = tonumber
local type = type
local sort = table.sort

-- WoW Globals
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local GetXPExhaustion = GetXPExhaustion
local UnitLevel = UnitLevel
local IsXPUserDisabled = IsXPUserDisabled
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitHonor = UnitHonor
local UnitHonorMax = UnitHonorMax
local UnitHonorLevel = UnitHonorLevel
local C_Reputation = C_Reputation
local C_MajorFactions = C_MajorFactions
local C_PvP = C_PvP
local C_Texture = C_Texture
local GameTooltip = GameTooltip
local BreakUpLargeNumbers = BreakUpLargeNumbers
local UIFrameFadeRemoveFrame = UIFrameFadeRemoveFrame

-- Locals
local Mult = 2.5
local BAR_WIDTH = 294
local BAR_HEIGHT = 30
local ICON_SIZE = BAR_HEIGHT + 4
local ICON_GAP = 6
local MAJOR_FACTION_ICON_ATLAS_FORMAT = "majorfactions_icons_%s512"
local DEFAULT_IDLE_ALPHA = 0.5
local DEFAULT_BAR_SCALE = 1.0
local MIN_BAR_SCALE = 0.75
local MAX_BAR_SCALE = 1.5
local FRAME_NAME = "RefineUI_ExperienceBar"
local UPDATE_KEY = "ExperienceBar:Update"

local Colors = {
    experience = { 0.6 * Mult, 0, 0.6 * Mult }, -- Purple
    rested = { 0, 0.39, 0.88 }, -- Blue
    honor = { 1, 0.71, 0 }, -- Orange
    renown = { 0.4, 0.2, 0.8 }, -- Covenant Purple
    reputation = { 0, 0.6, 1 }, -- Blue
}

local TEXT_FORMATS = {
    { text = "None", value = "NONE" },
    { text = "Percent", value = "PERCENT" },
    { text = "Compact", value = "COMPACT" },
    { text = "Complete", value = "COMPLETE" },
}

local UPDATE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION",
    "ENABLE_XP_GAIN",
    "DISABLE_XP_GAIN",
    "HONOR_XP_UPDATE",
    "HONOR_LEVEL_UPDATE",
    "UPDATE_FACTION",
    "UPDATE_EXPANSION_LEVEL",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "MAJOR_FACTION_UNLOCKED",
}

local VEHICLE_EVENTS = {
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
}

local EXPANSION_LEVEL = {
    DRAGONFLIGHT = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.Dragonflight) or 9,
    WAR_WITHIN = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.WarWithin) or 10,
    MIDNIGHT = (Enum and Enum.ExpansionLevel and Enum.ExpansionLevel.Midnight) or 11,
}

local MAJOR_FACTION_EXPANSIONS = {
    { id = EXPANSION_LEVEL.MIDNIGHT, label = "Midnight" },
    { id = EXPANSION_LEVEL.WAR_WITHIN, label = "The War Within" },
    { id = EXPANSION_LEVEL.DRAGONFLIGHT, label = "Dragonflight" },
}

local LastGainedFactionID = nil

local function ClampAlpha(value, fallback)
    local alpha = tonumber(value)
    if not alpha then
        alpha = fallback or DEFAULT_IDLE_ALPHA
    end

    if alpha < 0 then
        return 0
    elseif alpha > 1 then
        return 1
    end

    return alpha
end

local function ClampScale(value)
    local scale = tonumber(value)
    if not scale then
        scale = DEFAULT_BAR_SCALE
    end

    if scale < MIN_BAR_SCALE then
        scale = MIN_BAR_SCALE
    elseif scale > MAX_BAR_SCALE then
        scale = MAX_BAR_SCALE
    end

    return floor((scale * 100) + 0.5) / 100
end

local function IsMaxLevel(level)
    local maxLevel = GetMaxLevelForPlayerExpansion()
    if maxLevel == 0 then
        maxLevel = _G.MAX_PLAYER_LEVEL or 0
    end
    return level >= maxLevel
end

local function RunUpdate()
    ExperienceBar:Update()
end

-- Coalesce event bursts (quest turn-ins, login) into one update on the next frame
local function RequestUpdate()
    RefineUI:Debounce(UPDATE_KEY, 0, RunUpdate)
end

----------------------------------------------------------------------------------------
-- Faction Data
----------------------------------------------------------------------------------------
local function ProcessFactionData(factionData)
    local name = factionData.name
    local factionID = factionData.factionID
    local reaction = factionData.reaction or 0
    local currentStanding = factionData.currentStanding or 0
    local currentThreshold = factionData.currentReactionThreshold or 0
    local nextThreshold = factionData.nextReactionThreshold

    local cur = max(0, currentStanding - currentThreshold)
    local maxVal = (nextThreshold and (nextThreshold - currentThreshold)) or 1
    if maxVal <= 0 then maxVal = 1 end
    if cur > maxVal then cur = maxVal end
    local perc = floor(cur / maxVal * 100 + 0.5)

    if factionID then
        local isParagon = C_Reputation.IsFactionParagon(factionID)

        -- Renown progress unless the faction is maxed and has moved on to Paragon
        if not (isParagon and C_MajorFactions.HasMaximumRenown(factionID)) then
            local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorFactionData and majorFactionData.renownLevel then
                local rCur = majorFactionData.renownReputationEarned or 0
                local rMax = majorFactionData.renownLevelThreshold or 1
                if rMax <= 0 then rMax = 1 end
                if rCur > rMax then rCur = rMax end
                local rPerc = floor(rCur / rMax * 100 + 0.5)
                return rCur, rMax, rPerc, 0, 0, majorFactionData.renownLevel, "renown", majorFactionData.name or name, factionID
            end
        end

        if isParagon then
            local currentValue, threshold = C_Reputation.GetFactionParagonInfo(factionID)
            if currentValue and threshold then
                local pMax = threshold > 0 and threshold or 1
                local pCur = currentValue % pMax
                local pPerc = floor(pCur / pMax * 100 + 0.5)
                return pCur, pMax, pPerc, 0, 0, "Paragon", "reputation", name, factionID
            end
        end
    end

    local standingText = _G["FACTION_STANDING_LABEL" .. reaction] or tostring(reaction)
    return cur, maxVal, perc, 0, 0, standingText, "reputation", name, factionID
end

local function GetMajorFactionIconAtlas(factionID)
    if not factionID then
        return nil
    end

    local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
    if not (majorFactionData and majorFactionData.textureKit) then
        return nil
    end

    local atlas = format(MAJOR_FACTION_ICON_ATLAS_FORMAT, majorFactionData.textureKit)
    if not C_Texture.GetAtlasInfo(atlas) then
        return nil
    end

    return atlas
end

local function SortMajorFactions(a, b)
    if a.uiPriority ~= b.uiPriority then
        return a.uiPriority < b.uiPriority
    end

    if a.name and b.name then
        return a.name < b.name
    end

    return (a.factionID or 0) < (b.factionID or 0)
end

local function GetMajorFactionDataForExpansion(expansionID)
    local majorFactions = {}
    local factionIDs = C_MajorFactions.GetMajorFactionIDs(expansionID)
    if factionIDs then
        for _, factionID in ipairs(factionIDs) do
            if not C_MajorFactions.IsMajorFactionHiddenFromExpansionPage(factionID) then
                local data = C_MajorFactions.GetMajorFactionData(factionID)
                if data then
                    majorFactions[#majorFactions + 1] = data
                end
            end
        end
    end

    sort(majorFactions, SortMajorFactions)
    return majorFactions
end

local function GetClosestFaction()
    local currentExpansionID = GetExpansionLevel()
    local bestCurrentData, bestCurrentPerc = nil, -1
    local bestFallbackData, bestFallbackPerc = nil, -1

    for _, expansionInfo in ipairs(MAJOR_FACTION_EXPANSIONS) do
        local factionIDs = C_MajorFactions.GetMajorFactionIDs(expansionInfo.id)
        if factionIDs then
            for _, factionID in ipairs(factionIDs) do
                local majorFactionData = not C_MajorFactions.IsMajorFactionHiddenFromExpansionPage(factionID)
                    and C_MajorFactions.GetMajorFactionData(factionID)
                if majorFactionData then
                    local isCurrent = majorFactionData.expansionID == currentExpansionID
                    local perc

                    if C_MajorFactions.HasMaximumRenown(factionID) then
                        if C_Reputation.IsFactionParagon(factionID) then
                            local currentValue, threshold = C_Reputation.GetFactionParagonInfo(factionID)
                            if currentValue and threshold and threshold > 0 then
                                perc = (currentValue % threshold) / threshold
                            end
                        end
                    elseif isCurrent and majorFactionData.isUnlocked then
                        local rMax = majorFactionData.renownLevelThreshold or 1
                        if rMax > 0 then
                            perc = (majorFactionData.renownReputationEarned or 0) / rMax
                        end
                    end

                    if perc then
                        if isCurrent then
                            if perc > bestCurrentPerc then
                                bestCurrentPerc = perc
                                bestCurrentData = majorFactionData
                            end
                        elseif perc > bestFallbackPerc then
                            bestFallbackPerc = perc
                            bestFallbackData = majorFactionData
                        end
                    end
                end
            end
        end
    end

    return bestCurrentData or bestFallbackData
end

local function GetRecentFaction()
    if not LastGainedFactionID then return nil end
    return C_Reputation.GetFactionDataByID(LastGainedFactionID)
end

local function GetExperienceValues(level)
    local cur, maxVal = UnitXP("player"), UnitXPMax("player")
    if maxVal <= 0 then maxVal = 1 end
    local rested = GetXPExhaustion() or 0
    local perc = floor(cur / maxVal * 100 + 0.5)
    local restedPerc = floor(rested / maxVal * 100 + 0.5)
    return cur, maxVal, perc, rested, restedPerc, level, "experience", nil, nil
end

----------------------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------------------
function ExperienceBar:GetBarScale()
    return ClampScale(self.db and self.db.Scale)
end

function ExperienceBar:GetScaledMetrics()
    local scale = self:GetBarScale()
    local width = max(1, floor((BAR_WIDTH * scale) + 0.5))
    local height = max(1, floor((BAR_HEIGHT * scale) + 0.5))
    local iconSize = max(1, floor((ICON_SIZE * scale) + 0.5))
    local iconGap = max(0, floor((ICON_GAP * scale) + 0.5))
    local textSize = max(8, floor((16 * scale) + 0.5))

    return width, height, iconSize, iconGap, textSize
end

function ExperienceBar:IsMouseoverEnabled()
    return not self.db or self.db.Mouseover ~= false
end

function ExperienceBar:GetIdleAlpha()
    return ClampAlpha(self.db and self.db.Alpha, DEFAULT_IDLE_ALPHA)
end

function ExperienceBar:ApplyAlphaState()
    local frame = self.Frame
    UIFrameFadeRemoveFrame(frame)

    if LibEditMode:IsInEditMode() or not self:IsMouseoverEnabled() or frame:IsMouseOver() then
        frame:SetAlpha(1)
    else
        frame:SetAlpha(self:GetIdleAlpha())
    end
end

function ExperienceBar:UpdateBarLayout(showIcon)
    local _, _, iconSize, iconGap = self:GetScaledMetrics()

    self.Bar:ClearAllPoints()
    RefineUI.Point(self.Bar, "TOPLEFT", self.Frame, "TOPLEFT", showIcon and (iconSize + iconGap) or 0, 0)
    RefineUI.Point(self.Bar, "BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", 0, 0)
end

function ExperienceBar:ApplyScale()
    local width, height, iconSize, _, textSize = self:GetScaledMetrics()

    RefineUI:SetPixelSize(self.Frame, width, height)
    RefineUI:SetPixelSize(self.IconFrame, iconSize, iconSize)
    RefineUI.Font(self.Text, textSize, nil, "OUTLINE", true)

    self:UpdateBarLayout(self.IconFrame:IsShown())
end

function ExperienceBar:RegisterEditModeSettings()
    if self._alphaSetting then
        return
    end

    local alphaSetting = {
        kind = LibEditMode.SettingType.Slider,
        name = "Alpha When Not Moused-Over",
        default = DEFAULT_IDLE_ALPHA,
        minValue = 0,
        maxValue = 1,
        valueStep = 0.05,
        disabled = not self:IsMouseoverEnabled(),
        get = function()
            return ExperienceBar:GetIdleAlpha()
        end,
        set = function(_, value)
            ExperienceBar.db.Alpha = ClampAlpha(value, DEFAULT_IDLE_ALPHA)
            ExperienceBar:ApplyAlphaState()
        end,
    }

    self._alphaSetting = alphaSetting
    LibEditMode:AddFrameSettings(self.Frame, {
        {
            kind = LibEditMode.SettingType.Slider,
            name = "Scale",
            default = DEFAULT_BAR_SCALE,
            minValue = MIN_BAR_SCALE,
            maxValue = MAX_BAR_SCALE,
            valueStep = 0.05,
            formatter = function(value)
                return format("%.2f", ClampScale(value))
            end,
            get = function()
                return ExperienceBar:GetBarScale()
            end,
            set = function(_, value)
                ExperienceBar.db.Scale = ClampScale(value)
                ExperienceBar:ApplyScale()
            end,
        },
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = "Text",
            default = "NONE",
            values = TEXT_FORMATS,
            get = function()
                return ExperienceBar.db.TextFormat
            end,
            set = function(_, value)
                ExperienceBar.db.TextFormat = value
                ExperienceBar:Update()
            end,
        },
        {
            kind = LibEditMode.SettingType.Checkbox,
            name = "Mouseover",
            default = false,
            get = function()
                return ExperienceBar:IsMouseoverEnabled()
            end,
            set = function(_, value)
                ExperienceBar.db.Mouseover = value == true
                ExperienceBar:ApplyAlphaState()
                alphaSetting.disabled = not ExperienceBar:IsMouseoverEnabled()
                LibEditMode:RefreshFrameSettings(ExperienceBar.Frame)
            end,
        },
        alphaSetting,
    })
end

function ExperienceBar:RegisterEditModeCallbacks()
    if self._editModeCallbacksRegistered then
        return
    end

    local function OnEditModeChanged()
        ExperienceBar:Update()
        ExperienceBar:ApplyAlphaState()
    end

    LibEditMode:RegisterCallback("enter", OnEditModeChanged)
    LibEditMode:RegisterCallback("exit", OnEditModeChanged)

    self._editModeCallbacksRegistered = true
end

----------------------------------------------------------------------------------------
-- Context Menu
----------------------------------------------------------------------------------------
local function AddFactionMenu(parent, majorFactionData)
    local factionID = majorFactionData.factionID
    local name = majorFactionData.name or ("Faction " .. tostring(factionID))
    local isMaxed = C_MajorFactions.HasMaximumRenown(factionID)
    local text = format("%s (Lvl %d)", name, majorFactionData.renownLevel or 0)

    if not majorFactionData.isUnlocked then
        text = "|cff808080" .. text .. " (" .. (_G.MAJOR_FACTION_BUTTON_FACTION_LOCKED or "Locked") .. ")|r"
    elseif isMaxed then
        text = "|cff808080" .. text .. " (Maxed)|r"
    end

    parent:CreateRadio(text, function()
        local watched = C_Reputation.GetWatchedFactionData()
        return watched and watched.factionID == factionID
    end, function()
        if not majorFactionData.isUnlocked or isMaxed then
            return
        end

        C_Reputation.SetWatchedFactionByID(factionID)
        RefineUI:Print("Watching: " .. name)
    end)
end

local function BuildContextMenu(_, rootDescription)
    local db = ExperienceBar.db
    rootDescription:CreateTitle("Experience Bar")

    local pIsMaxLevel = IsMaxLevel(UnitLevel("player"))

    local experienceRadio = rootDescription:CreateRadio("Experience", function()
        return not pIsMaxLevel and (db.SubMaxTrackMode or "EXPERIENCE") == "EXPERIENCE"
    end, function()
        db.SubMaxTrackMode = "EXPERIENCE"
        RefineUI:Print("Tracking: Experience")
        ExperienceBar:Update()
    end)
    experienceRadio:SetEnabled(not pIsMaxLevel)

    rootDescription:CreateRadio("Reputation", function()
        return pIsMaxLevel or db.SubMaxTrackMode == "REPUTATION"
    end, function()
        db.SubMaxTrackMode = "REPUTATION"
        RefineUI:Print("Tracking: Reputation")
        ExperienceBar:Update()
    end)

    rootDescription:CreateDivider()

    local currentWatched = C_Reputation.GetWatchedFactionData()

    local autoTrackMenu = rootDescription:CreateButton(db.AutoTrack == "RECENT" and "Auto-Track (Recent)" or "Auto-Track (Closest)")
    autoTrackMenu:SetEnabled(not currentWatched)

    autoTrackMenu:CreateRadio("Closest", function() return db.AutoTrack == "CLOSEST" end, function()
        db.AutoTrack = "CLOSEST"
        RefineUI:Print("Auto-Track: Closest")
        ExperienceBar:Update()
    end)

    autoTrackMenu:CreateRadio("Recent", function() return db.AutoTrack == "RECENT" end, function()
        db.AutoTrack = "RECENT"
        RefineUI:Print("Auto-Track: Recent")
        ExperienceBar:Update()
    end)

    rootDescription:CreateDivider()

    if currentWatched then
        rootDescription:CreateButton("|cffFF0000Stop Tracking|r " .. (currentWatched.name or ""), function()
            C_Reputation.SetWatchedFactionByID(0)
            RefineUI:Print("Manual tracking cleared. Auto-Track resumed.")
        end)
        rootDescription:CreateDivider()
    end

    for _, expansionInfo in ipairs(MAJOR_FACTION_EXPANSIONS) do
        local majorFactions = GetMajorFactionDataForExpansion(expansionInfo.id)
        if #majorFactions > 0 then
            local menu = rootDescription:CreateButton(expansionInfo.label)
            for _, majorFactionData in ipairs(majorFactions) do
                AddFactionMenu(menu, majorFactionData)
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------
function ExperienceBar:CreateBar()
    local Container = CreateFrame("Frame", FRAME_NAME, _G.UIParent)
    local width, height, iconSize = self:GetScaledMetrics()

    RefineUI:SetPixelSize(Container, width, height)

    -- Position Priority: Central Config > DB Saved > Default
    local pos = (RefineUI.Positions and RefineUI.Positions[FRAME_NAME]) or { "TOP", "Minimap", "BOTTOM", 0, -10 }
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    if type(relativeTo) == "string" then
        relativeTo = _G[relativeTo] or _G.UIParent
    end
    RefineUI.Point(Container, point, relativeTo, relativePoint, x, y)

    Container.editModeName = "Experience Bar"
    LibEditMode:AddFrame(Container, function(frame, layout, point, x, y)
        RefineUI:SetPosition(FRAME_NAME, { point, "UIParent", point, x, y })
    end, { point = point, x = x, y = y })

    Container:EnableMouse(true)
    Container:SetAlpha(1)

    local Bar = CreateFrame("StatusBar", nil, Container)
    RefineUI.Point(Bar, "TOPLEFT", Container, "TOPLEFT", 0, 0)
    RefineUI.Point(Bar, "BOTTOMRIGHT", Container, "BOTTOMRIGHT", 0, 0)
    Bar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
    Bar:SetStatusBarColor(unpack(Colors.experience))
    RefineUI.CreateBackdrop(Bar)

    if Bar.bg and Bar.bg.border then
        Bar.bg.border:SetFrameLevel(Bar:GetFrameLevel() + 1)
    end

    local IconFrame = CreateFrame("Frame", nil, Container)
    RefineUI:SetPixelSize(IconFrame, iconSize, iconSize)
    RefineUI.Point(IconFrame, "LEFT", Container, "LEFT", 0, 0)
    RefineUI.CreateBackdrop(IconFrame, "Default")
    IconFrame:Hide()

    if IconFrame.bg and IconFrame.bg.border then
        IconFrame.bg.border:SetFrameLevel(IconFrame:GetFrameLevel() + 1)
    end

    local IconTexture = IconFrame:CreateTexture(nil, "ARTWORK")
    IconTexture:SetPoint("TOPLEFT", IconFrame, "TOPLEFT", 2, -2)
    IconTexture:SetPoint("BOTTOMRIGHT", IconFrame, "BOTTOMRIGHT", -2, 2)

    local BarRested = CreateFrame("StatusBar", nil, Bar)
    RefineUI.SetInside(BarRested)
    BarRested:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
    BarRested:SetStatusBarColor(unpack(Colors.rested))
    BarRested:SetFrameLevel(Bar:GetFrameLevel() - 1)
    BarRested:Hide()

    local InvisFrame = CreateFrame("Frame", nil, Bar)
    InvisFrame:SetFrameLevel(Bar:GetFrameLevel() + 10)
    RefineUI.SetInside(InvisFrame)

    local Text = InvisFrame:CreateFontString(nil, "OVERLAY")
    RefineUI.Point(Text, "CENTER", Bar, "CENTER", 0, 0)

    Container:SetScript("OnEnter", function(frame) ExperienceBar:OnEnter(frame) end)
    Container:SetScript("OnLeave", function(frame) ExperienceBar:OnLeave(frame) end)
    Container:SetScript("OnMouseUp", function(frame, button)
        if button == "RightButton" then
            MenuUtil.CreateContextMenu(frame, BuildContextMenu)
        end
    end)

    self.Frame = Container
    self.Bar = Bar
    self.BarRested = BarRested
    self.IconFrame = IconFrame
    self.IconTexture = IconTexture
    self.Text = Text

    self:ApplyScale()
    self:RegisterEditModeSettings()
    self:RegisterEditModeCallbacks()
    self:ApplyAlphaState()
end

function ExperienceBar:UpdateTrackedFactionIcon(factionID)
    if factionID == self._iconFactionID then
        return
    end
    self._iconFactionID = factionID

    local atlas = GetMajorFactionIconAtlas(factionID)
    if atlas then
        self.IconTexture:SetAtlas(atlas, true)
    end

    if (atlas ~= nil) ~= self.IconFrame:IsShown() then
        self.IconFrame:SetShown(atlas ~= nil)
        self:UpdateBarLayout(atlas ~= nil)
    end
end

----------------------------------------------------------------------------------------
-- Values
----------------------------------------------------------------------------------------
function ExperienceBar:GetValues()
    local pLevel = UnitLevel("player")
    local pIsMaxLevel = IsMaxLevel(pLevel)

    if pIsMaxLevel or self.db.SubMaxTrackMode == "REPUTATION" then
        -- 1. Faction explicitly watched via "Show as Experience Bar"
        local factionData = C_Reputation.GetWatchedFactionData()
        if factionData then
            return ProcessFactionData(factionData)
        end

        -- 2. Honor, when explicitly watched at max level
        if pIsMaxLevel and IsWatchingHonorAsXP() then
            local level = UnitHonorLevel("player")
            if C_PvP.GetNextHonorLevelForReward(level) then
                local cur = UnitHonor("player")
                local maxVal = UnitHonorMax("player") or 1
                if maxVal <= 0 then maxVal = 1 end
                local perc = floor(cur / maxVal * 100 + 0.5)
                return cur, maxVal, perc, 0, 0, level, "honor", nil, nil
            end
        end

        -- 3. Auto-tracked major faction
        local autoTrack = self.db.AutoTrack
        if autoTrack == "RECENT" then
            factionData = GetRecentFaction() or GetClosestFaction()
        elseif autoTrack == "CLOSEST" then
            factionData = GetClosestFaction()
        end
        if factionData then
            return ProcessFactionData(factionData)
        end
    end

    if not pIsMaxLevel then
        return GetExperienceValues(pLevel)
    end

    return 0, 1, 0, 0, 0, pLevel, "none", nil, nil
end

function ExperienceBar:OnEnter(frame)
    local cur, maxVal, perc, rested, restedPerc, level, barType, name = self:GetValues()

    GameTooltip:ClearLines()
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR", 0, -6)

    if barType == "renown" then
        local RENOWN = _G.RENOWN or "Renown"
        local RENOWN_LEVEL_LABEL = _G.RENOWN_LEVEL_LABEL or "Level %d"
        GameTooltip:AddLine(format("%s - %s", name or RENOWN, format(RENOWN_LEVEL_LABEL, level or 0)))
        GameTooltip:AddDoubleLine("Current Renown:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
    elseif barType == "reputation" then
        GameTooltip:AddLine(format("%s - %s", name or "Reputation", level or ""))
        GameTooltip:AddDoubleLine("Current Reputation:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
    elseif barType == "honor" then
        GameTooltip:AddLine(HONOR_LEVEL_LABEL:format(level or 0))
        GameTooltip:AddDoubleLine("Current Honor:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
    elseif barType == "experience" then
        GameTooltip:AddLine("|cffffd200Experience|r")
        GameTooltip:AddDoubleLine("Current Experience:", format("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Remaining Experience:", format("%s (%d%%)", BreakUpLargeNumbers(maxVal - cur), floor((maxVal - cur) / maxVal * 100)), 1, 1, 1, 1, 1, 1)

        if rested > 0 then
            GameTooltip:AddDoubleLine("Rested Experience:", format("%s (%d%%)", BreakUpLargeNumbers(rested), restedPerc), 0, 0.6, 1, 1, 1, 1)
        end
    end

    GameTooltip:Show()

    if self:IsMouseoverEnabled() and not LibEditMode:IsInEditMode() then
        RefineUI:FadeIn(frame, 0.2, 1)
    else
        self:ApplyAlphaState()
    end
end

function ExperienceBar:OnLeave(frame)
    GameTooltip:Hide()

    if self:IsMouseoverEnabled() and not LibEditMode:IsInEditMode() then
        RefineUI:FadeOut(frame, 0.5, self:GetIdleAlpha())
    else
        self:ApplyAlphaState()
    end
end

function ExperienceBar:UpdateText(cur, maxVal, perc)
    local textFormat = self.db.TextFormat
    if textFormat == "PERCENT" then
        self.Text:SetFormattedText("%d%%", perc)
    elseif textFormat == "COMPACT" then
        self.Text:SetFormattedText("%s / %s (%d%%)", RefineUI:ShortValue(cur), RefineUI:ShortValue(maxVal), perc)
    elseif textFormat == "COMPLETE" then
        self.Text:SetFormattedText("%s / %s (%d%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(maxVal), perc)
    else
        self.Text:SetText("")
    end
end

function ExperienceBar:Update()
    local cur, maxVal, perc, rested, _, _, barType, _, factionID = self:GetValues()
    local isEditMode = LibEditMode:IsInEditMode()

    if not isEditMode and (barType == "none"
        or UnitHasVehicleUI("player")
        or (barType == "experience" and IsXPUserDisabled())) then
        self.Frame:Hide()
        return
    end

    -- Placeholder fill so the bar is visible while positioning in Edit Mode
    if isEditMode and cur == 0 and maxVal == 1 then
        cur, maxVal, perc = 50, 100, 50
    end

    self.Bar:SetMinMaxValues(0, maxVal)
    self.Bar:SetValue(cur)
    self:UpdateText(cur, maxVal, perc)

    if barType ~= self._barType then
        self._barType = barType
        self.Bar:SetStatusBarColor(unpack(Colors[barType] or Colors.experience))
    end

    if barType == "experience" and rested > 0 then
        self.BarRested:SetMinMaxValues(0, maxVal)
        self.BarRested:SetValue(min(cur + rested, maxVal))
        self.BarRested:Show()
    else
        self.BarRested:Hide()
    end

    self:UpdateTrackedFactionIcon(factionID)

    if not self.Frame:IsShown() then
        self.Frame:Show()
        self:ApplyAlphaState()
    end
end

local function OnFactionStandingChanged(_, factionID)
    if not C_Reputation.IsMajorFaction(factionID) then
        return
    end

    LastGainedFactionID = factionID
    if ExperienceBar.db.AutoTrack == "RECENT" then
        RequestUpdate()
    end
end

function ExperienceBar:RegisterEvents()
    RefineUI:OnEvents(UPDATE_EVENTS, RequestUpdate, UPDATE_KEY)
    RefineUI:OnUnitEvents("player", VEHICLE_EVENTS, RequestUpdate, UPDATE_KEY)
    RefineUI:RegisterEventCallback("FACTION_STANDING_CHANGED", OnFactionStandingChanged, "ExperienceBar:FactionStandingChanged")

    -- Watch changes made through Blizzard UI (Reputation/PvP frames refresh their bars manually)
    RefineUI:HookOnce("ExperienceBar:SetWatchingHonorAsXP", "SetWatchingHonorAsXP", RequestUpdate)
    RefineUI:HookOnce("ExperienceBar:C_Reputation:SetWatchedFactionByIndex", C_Reputation, "SetWatchedFactionByIndex", RequestUpdate)
    RefineUI:HookOnce("ExperienceBar:C_Reputation:SetWatchedFactionByID", C_Reputation, "SetWatchedFactionByID", RequestUpdate)
end

function ExperienceBar:OnEnable()
    local config = RefineUI.Config.UnitFrames and RefineUI.Config.UnitFrames.DataBars and RefineUI.Config.UnitFrames.DataBars.ExperienceBar
    if not config then return end

    -- Migration: Handle old boolean config
    if type(config) ~= "table" then
        config = {
            Enable = config,
        }
        RefineUI.Config.UnitFrames.DataBars.ExperienceBar = config
    end

    if not config.Enable then return end
    self.db = config
    if self.db.SubMaxTrackMode ~= "EXPERIENCE" and self.db.SubMaxTrackMode ~= "REPUTATION" then
        self.db.SubMaxTrackMode = "EXPERIENCE"
    end
    self.db.Scale = ClampScale(self.db.Scale)
    if self.db.Mouseover == nil then
        self.db.Mouseover = false
    end
    self.db.Alpha = ClampAlpha(self.db.Alpha, DEFAULT_IDLE_ALPHA)
    self.db.TextFormat = self.db.TextFormat or "NONE"
    if self.db.Position then
        if not RefineUI.Positions[FRAME_NAME] then
            RefineUI:SetPosition(FRAME_NAME, self.db.Position)
        end
        self.db.Position = nil
    end

    self:CreateBar()
    self:RegisterEvents()
    self:Update()

    -- Disable Default XP Bar
    if _G.MainStatusTrackingBarContainer then
        RefineUI.AddAPI(_G.MainStatusTrackingBarContainer)
        RefineUI.Kill(_G.MainStatusTrackingBarContainer)
    end
end
