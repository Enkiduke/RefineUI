----------------------------------------------------------------------------------------
-- RefineUI Positions
-- Description: Tiered default anchor points for persistent UI elements.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local floor = math.floor
local pairs = pairs
local tonumber = tonumber
local type = type
local GetPhysicalScreenSize = _G.GetPhysicalScreenSize

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LAYOUT_TIER = {
    WIDE_1440 = "wide_1440",
    STANDARD_1440 = "standard_1440",
    STANDARD_1080 = "standard_1080",
}

local MANAGED_LAYOUT_NAME = {
    [LAYOUT_TIER.WIDE_1440] = "RefineUI Wide",
    [LAYOUT_TIER.STANDARD_1440] = "RefineUI 1440",
    [LAYOUT_TIER.STANDARD_1080] = "RefineUI 1080",
}

local TIER_OFFSET_SCALE = {
    [LAYOUT_TIER.WIDE_1440] = { x = 1.000, y = 1.000 },
    [LAYOUT_TIER.STANDARD_1440] = { x = 0.744, y = 1.000 },
    [LAYOUT_TIER.STANDARD_1080] = { x = 0.558, y = 0.750 },
}

local LAYOUT_DEFAULTS = {
    [LAYOUT_TIER.WIDE_1440] = {
        chat = { width = 600, height = 300 },
        unitFrames = {
            playerTargetFrameSize = 150,
            focusUseLargerFrame = true,
            partyWidth = 72,
            partyHeight = 28,
        },
        minimap = { baseSize = 294 },
        damageMeter = {
            frameWidth = 314,
            frameHeight = 294,
            barHeight = 16,
            padding = 2,
            textSize = 100,
            backgroundTransparency = 0,
        },
        objectiveTracker = { scale = 1.20 },
        actionBars = { iconSize = 100, iconPadding = 4 },
    },
    [LAYOUT_TIER.STANDARD_1440] = {
        chat = { width = 520, height = 280 },
        unitFrames = {
            playerTargetFrameSize = 140,
            focusUseLargerFrame = true,
            partyWidth = 72,
            partyHeight = 28,
        },
        minimap = { baseSize = 272 },
        damageMeter = {
            frameWidth = 300,
            frameHeight = 272,
            barHeight = 16,
            padding = 2,
            textSize = 90,
            backgroundTransparency = 0,
        },
        objectiveTracker = { scale = 1.10 },
        actionBars = { iconSize = 95, iconPadding = 4 },
    },
    [LAYOUT_TIER.STANDARD_1080] = {
        chat = { width = 460, height = 240 },
        unitFrames = {
            playerTargetFrameSize = 125,
            focusUseLargerFrame = false,
            partyWidth = 72,
            partyHeight = 28,
        },
        minimap = { baseSize = 244 },
        damageMeter = {
            frameWidth = 300,
            frameHeight = 244,
            barHeight = 16,
            padding = 2,
            textSize = 80,
            backgroundTransparency = 0,
        },
        objectiveTracker = { scale = 1.00 },
        actionBars = { iconSize = 90, iconPadding = 4 },
    },
}

local WIDE_1440_POSITIONS = {
    -- ActionBars
    ["MainActionBar"]       = { "BOTTOM", "UIParent", "BOTTOM", 0, 200 },
    ["MultiBarBottomLeft"]  = { "BOTTOM", "UIParent", "BOTTOM", 0, 250 },
    ["MultiBarBottomRight"] = { "BOTTOM", "UIParent", "BOTTOM", -170, 6 },
    ["MultiBarRight"]       = { "BOTTOM", "UIParent", "BOTTOM", 170, 6 },
    ["MultiBarLeft"]        = { "BOTTOM", "UIParent", "BOTTOM", 0, 6 },
    ["MultiBar5"]           = { "RIGHT", "UIParent", "RIGHT", -75, 0 },
    ["MultiBar6"]           = { "LEFT", "UIParent", "LEFT", 5, 0 },
    ["MultiBar7"]           = { "LEFT", "UIParent", "LEFT", 5, 0 },
    ["PetActionBar"]        = { "BOTTOMRIGHT", "ChatFrame1", "TOPRIGHT", 0, 5 },
    ["StanceBar"]           = { "BOTTOMLEFT", "MultiBarBottomLeft", "TOPLEFT", 0, 5 },
    ["OverrideActionBar"]   = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["ExtraActionBarFrame"] = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["ZoneAbilityFrame"]    = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["MicroMenuContainer"]  = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 5, 5 },
    ["VehicleSeatIndicator"] = { "RIGHT", "UIParent", "RIGHT", -6, 0 },

    -- UnitFrames
    ["PlayerFrame"]         = { "BOTTOM", "UIParent", "BOTTOM", -45, 320 },
    ["PlayerFrameAlternateManaBar"] = { "BOTTOM", "PlayerFrame", "TOP", 0, 9 },
    ["TargetFrame"]         = { "BOTTOM", "UIParent", "BOTTOM", 432, 320 },
    ["TargetFrameToT"]      = { "TOPRIGHT", "TargetFrame", "BOTTOMRIGHT", 0, -11 },
    ["PetFrame"]            = { "LEFT", "PlayerFrame", "RIGHT", -50, -4 },
    ["FocusFrame"]          = { "BOTTOM", "UIParent", "BOTTOM", -368, 320 },
    ["FocusFrameToT"]       = { "TOPLEFT", "TargetFrame", "BOTTOMLEFT", 0, -11 },
    ["PartyFrame"]          = { "CENTER", "UIParent", "CENTER", -650, 50 },
    ["BossTargetFrameContainer"] = { "CENTER", "UIParent", "CENTER", 800, 0 },
    ["ArenaEnemyFramesContainer"] = { "CENTER", "UIParent", "CENTER", 800, 0 },

    -- Class Resources
    ["RefineUI_ClassPowerBar"]    = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_SecondaryPowerBar"] = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_RuneBar"]          = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_MaelstromBar"]     = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_SoulFragmentsBar"] = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_StaggerBar"]       = { "BOTTOM", nil, "TOP", 0, 6 },
    ["RefineUI_TotemBar"]         = { "BOTTOM", nil, "TOP", 0, 20 },

    -- CastBars
    ["PlayerCastingBarFrame"]     = { "TOP", "PlayerFrame", "BOTTOM", 60, 30 },

    -- Minimap
    ["MinimapCluster"]      = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -20, 76 },
    ["RefineUI_MinimapButtonCollect"] = { "TOPRIGHT", "Minimap", "TOPRIGHT", 0, 0 },
    ["RefineUI_ExperienceBar"]       = { "TOP", "Minimap", "BOTTOM", 0, -10 },
    ["DamageMeter"]                  = { "RIGHT", "Minimap", "LEFT", 10, 0 },
    ["DamageMeterSessionWindow1"]    = { "RIGHT", "Minimap", "LEFT", 10, 0 },

    -- Chat
    ["ChatFrame1"]          = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 10, 50 },
    ["QuickJoinToastButton"] = { "BOTTOMLEFT", "ChatFrame1", "TOPLEFT", -3, 27 },
    ["BNToastFrame"]        = { "BOTTOMLEFT", "ChatFrame1", "TOPLEFT", -3, 27 },
    ["RefineUI_ToastAnchor"] = { "TOP", "UIParent", "TOP", 0, -120 },

    -- Automation / Custom
    ["RefineUI_AutoItemBarMover"] = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 0, 6 },
    ["RefineUI_AutoOpenBarMover"] = { "TOPLEFT", "ChatFrame1", "TOPRIGHT", 2, 0 },
    ["RefineUI_AutoButton"]  = { "BOTTOMLEFT", "Minimap", "TOPLEFT", -2, 27 },
    ["RefineUI_GhostFrame"]  = { "BOTTOM", "Minimap", "TOP", 0, 5 },
    ["RefineUI_TooltipAnchorMover"] = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 0, 6 },

    -- Loot
    ["GroupLootContainer"]   = { "TOP", "UIParent", "TOP", 0, -50 },
    ["LootFrame"]            = { "TOPLEFT", "UIParent", "TOPLEFT", 245, -220 },

    -- Buffs
    ["BuffFrame"]            = { "TOPRIGHT", "UIParent", "TOPRIGHT", -3, -3 },
    ["DebuffFrame"]          = { "BOTTOM", "UIParent", "BOTTOM", 0, 450 },
    ["RefineUI_BuffReminder"] = { "CENTER", "UIParent", "CENTER", 0, 0 },
    ["RefineUI_CDM_LeftTracker"] = { "CENTER", "UIParent", "CENTER", -256, 0 },
    ["RefineUI_CDM_RightTracker"] = { "CENTER", "UIParent", "CENTER", 256, 0 },
    ["RefineUI_CDM_BottomTracker"] = { "CENTER", "UIParent", "CENTER", 0, -256 },
    ["RefineUI_CDM_RadialTracker"] = { "CENTER", "UIParent", "CENTER", 0, 0 },
    ["RefineUI_EncounterTimeline_BigIcon"] = { "CENTER", "UIParent", "CENTER", 0, 400 },

    -- Panels & Widgets
    ["ObjectiveTrackerFrame"] = { "TOPLEFT", "UIParent", "TOPLEFT", 15, -10 },
    ["UIErrorsFrame"]        = { "TOP", "UIParent", "TOP", 0, -30 },
    ["RefineUI_GameTime"]    = { "BOTTOM", "UIParent", "BOTTOM", 0, 10 },
    ["TalkingHeadFrame"]     = { "TOP", "UIParent", "TOP", 0, -21 },
    ["PlayerPowerBarAlt"]    = { "TOP", "UIWidgetTopCenterContainerFrame", "BOTTOM", 0, -7 },
    ["UIWidgetTopCenterContainerFrame"] = { "TOP", "UIParent", "TOP", 1, -21 },
    ["UIWidgetBelowMinimapContainerFrame"] = { "TOP", "UIWidgetTopCenterContainerFrame", "BOTTOM", 0, -15 },

    -- Raid Manager
    ["CompactRaidFrameManager"] = { "LEFT", "UIParent", "LEFT", 0, 0 },

    -- Misc
    ["BankFrame"]            = { "LEFT", "UIParent", "LEFT", 23, 150 },
    ["ContainerFrame1"]      = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 2, 5 },
    ["RefineUI_Bags"]        = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 0, 5 },
    ["ArcheologyDigsiteProgressBar"] = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 2, 5 },
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function CopyPosition(position)
    if type(position) ~= "table" then
        return position
    end

    return {
        position[1],
        position[2],
        position[3],
        position[4],
        position[5],
    }
end

local function CopyPositions(positionMap)
    local copy = {}
    if type(positionMap) ~= "table" then
        return copy
    end

    for name, position in pairs(positionMap) do
        copy[name] = CopyPosition(position)
    end

    return copy
end

local function CopyTable(src)
    if type(src) ~= "table" then
        return src
    end

    local copy = {}
    for key, value in pairs(src) do
        copy[key] = CopyTable(value)
    end
    return copy
end

local function CopyLayoutDefaults(defaults)
    return CopyTable(defaults)
end

local function RoundScaledOffset(value, scale)
    if type(value) ~= "number" then
        return value
    end

    local scaledValue = value * scale
    if scaledValue >= 0 then
        return floor(scaledValue + 0.5)
    end

    return floor(scaledValue - 0.5)
end

local function BuildTierPositions(tierKey)
    if tierKey == LAYOUT_TIER.WIDE_1440 then
        return CopyPositions(WIDE_1440_POSITIONS)
    end

    local scaledPositions = {}
    local scale = TIER_OFFSET_SCALE[tierKey] or TIER_OFFSET_SCALE[LAYOUT_TIER.WIDE_1440]

    for name, position in pairs(WIDE_1440_POSITIONS) do
        local point, relativeTo, relativePoint, xOffset, yOffset = unpack(position)
        if relativeTo == "UIParent" then
            xOffset = RoundScaledOffset(xOffset, scale.x)
            yOffset = RoundScaledOffset(yOffset, scale.y)
        end

        scaledPositions[name] = { point, relativeTo, relativePoint, xOffset, yOffset }
    end

    return scaledPositions
end

----------------------------------------------------------------------------------------
-- Public Layout API
----------------------------------------------------------------------------------------
RefineUI.LayoutTier = LAYOUT_TIER
RefineUI.ManagedLayoutNames = MANAGED_LAYOUT_NAME
RefineUI.LayoutDefaultsByTier = LAYOUT_DEFAULTS
RefineUI.DefaultPositionsByTier = {
    [LAYOUT_TIER.WIDE_1440] = BuildTierPositions(LAYOUT_TIER.WIDE_1440),
    [LAYOUT_TIER.STANDARD_1440] = BuildTierPositions(LAYOUT_TIER.STANDARD_1440),
    [LAYOUT_TIER.STANDARD_1080] = BuildTierPositions(LAYOUT_TIER.STANDARD_1080),
}

function RefineUI:GetManagedLayoutName(tierKey)
    local key = tierKey or self:GetLayoutTier()
    return MANAGED_LAYOUT_NAME[key] or MANAGED_LAYOUT_NAME[LAYOUT_TIER.WIDE_1440]
end

function RefineUI:GetLayoutDefaults(tierKey)
    local key = tierKey or (self.GetStoredLayoutTier and self:GetStoredLayoutTier()) or self:GetLayoutTier()
    local defaults = self.LayoutDefaultsByTier and self.LayoutDefaultsByTier[key]
    if type(defaults) ~= "table" then
        defaults = self.LayoutDefaultsByTier and self.LayoutDefaultsByTier[LAYOUT_TIER.WIDE_1440]
    end
    return CopyLayoutDefaults(defaults)
end

function RefineUI:IsManagedLayoutName(layoutName)
    if type(layoutName) ~= "string" or layoutName == "" then
        return false
    end

    for _, managedName in pairs(MANAGED_LAYOUT_NAME) do
        if managedName == layoutName then
            return true
        end
    end

    return false
end

function RefineUI:GetLayoutTierFromDimensions(width, height)
    local physicalWidth = tonumber(width) or 1920
    local physicalHeight = tonumber(height) or 1080

    if physicalWidth <= 0 then
        physicalWidth = 1920
    end
    if physicalHeight <= 0 then
        physicalHeight = 1080
    end

    local aspectRatio = physicalWidth / physicalHeight
    if physicalHeight >= 1400 and aspectRatio >= 2.2 then
        return LAYOUT_TIER.WIDE_1440
    end
    if physicalHeight >= 1400 then
        return LAYOUT_TIER.STANDARD_1440
    end
    return LAYOUT_TIER.STANDARD_1080
end

function RefineUI:GetLayoutTier()
    local width, height
    if type(GetPhysicalScreenSize) == "function" then
        width, height = GetPhysicalScreenSize()
    end

    if not width or width <= 0 then
        width = self.ScreenWidth or 1920
    end
    if not height or height <= 0 then
        height = self.ScreenHeight or 1080
    end

    return self:GetLayoutTierFromDimensions(width, height)
end

function RefineUI:GetLayoutContext()
    local tierKey = self.GetStoredLayoutTier and self:GetStoredLayoutTier() or self:GetLayoutTier()
    return {
        tierKey = tierKey,
        layoutName = self:GetManagedLayoutName(tierKey),
        physicalTierKey = self:GetLayoutTier(),
    }
end

function RefineUI:GetDefaultPositionsForTier(tierKey)
    local key = tierKey or self:GetLayoutTier()
    local positionMap = self.DefaultPositionsByTier and self.DefaultPositionsByTier[key]
    if type(positionMap) ~= "table" then
        positionMap = self.DefaultPositionsByTier and self.DefaultPositionsByTier[LAYOUT_TIER.WIDE_1440]
    end
    return CopyPositions(positionMap)
end

function RefineUI:GetActiveLayoutProfile(profile)
    local db = profile or self.DB
    if type(db) ~= "table" or type(db.LayoutProfiles) ~= "table" then
        local tierKey = self.GetStoredLayoutTier and self:GetStoredLayoutTier(db) or self:GetLayoutTier()
        return nil, tierKey
    end

    local tierKey = self.GetStoredLayoutTier and self:GetStoredLayoutTier(db) or self:GetLayoutTier()
    local layoutProfile = db.LayoutProfiles[tierKey]
    if type(layoutProfile) ~= "table" then
        return nil, tierKey
    end

    return layoutProfile, tierKey
end

function RefineUI:GetActivePositionsTable(profile)
    local layoutProfile = self:GetActiveLayoutProfile(profile)
    if layoutProfile and type(layoutProfile.Positions) == "table" then
        return layoutProfile.Positions
    end

    return self.Positions
end

function RefineUI:SetPosition(name, position)
    if type(name) ~= "string" or name == "" or type(position) ~= "table" then
        return
    end

    local copiedPosition = CopyPosition(position)
    local activePositions = self:GetActivePositionsTable()
    if type(activePositions) == "table" then
        activePositions[name] = CopyPosition(copiedPosition)
    end

    if type(self.Positions) == "table" then
        self.Positions[name] = copiedPosition
    end
end

----------------------------------------------------------------------------------------
-- Runtime Baseline
----------------------------------------------------------------------------------------
RefineUI.Positions = RefineUI.Positions or RefineUI:GetDefaultPositionsForTier(LAYOUT_TIER.WIDE_1440)
