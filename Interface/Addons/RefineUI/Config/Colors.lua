----------------------------------------------------------------------------------------
-- RefineUI Colors
-- Description: Centralized color palette and helper functions.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local C = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local min = math.min
local floor = math.floor
local format = string.format
local pairs = pairs
local unpack = unpack

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local UnitClass = UnitClass
local C_Item = C_Item
local C_CurveUtil = C_CurveUtil
local Enum = Enum

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
-- Creates a color table that can be indexed [1],[2],[3] or .r,.g,.b
local function CreateColor(r, g, b, a)
    local color = {}
    
    if r > 1 or g > 1 or b > 1 then
        r, g, b = r/255, g/255, b/255 -- Handle 0-255 inputs
    end
    
    color.r, color.g, color.b = r, g, b
    color[1], color[2], color[3] = r, g, b
    
    if a then
        color.a = a
        color.colorStr = format("|c%02x%02x%02x%02x", a*255, r*255, g*255, b*255)
    else
        color.colorStr = format("|cff%02x%02x%02x", r*255, g*255, b*255)
    end
    
    return color
end

RefineUI.CreateColor = CreateColor

----------------------------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------------------------
RefineUI.Colors = {
    -- Empowered Casts (Evoker)
    EmpowerStages = {
        CreateColor(96, 172, 85),
        CreateColor(176, 172, 57),
        CreateColor(200, 140, 56),
        CreateColor(202, 69, 57),
    },

    -- Unit Reaction
    Reaction = {
        [1] = CreateColor(222, 95, 95), -- Hated
        [2] = CreateColor(222, 95, 95), -- Hostile
        [3] = CreateColor(222, 145, 95), -- Unfriendly
        [4] = CreateColor(255, 221, 60), -- Neutral
        [5] = CreateColor(86, 174, 87), -- Friendly
        [6] = CreateColor(86, 174, 87), -- Honored
        [7] = CreateColor(86, 174, 87), -- Revered
        [8] = CreateColor(86, 174, 87), -- Exalted
    },

    -- Classes
    Class = {
        ["DEATHKNIGHT"] = CreateColor(196, 30, 58),
        ["DEMONHUNTER"] = CreateColor(163, 48, 201),
        ["DRUID"]       = CreateColor(255, 124, 10),
        ["EVOKER"]      = CreateColor(51, 147, 127),
        ["HUNTER"]      = CreateColor(170, 211, 114),
        ["MAGE"]        = CreateColor(63, 199, 235),
        ["MONK"]        = CreateColor(0, 255, 150),
        ["PALADIN"]     = CreateColor(244, 140, 186),
        ["PRIEST"]      = CreateColor(255, 255, 255),
        ["ROGUE"]       = CreateColor(255, 244, 104),
        ["SHAMAN"]      = CreateColor(0, 112, 221),
        ["WARLOCK"]     = CreateColor(135, 136, 238),
        ["WARRIOR"]     = CreateColor(198, 155, 109),
    },
    
    -- Power Types
    Power = {
        ["MANA"]        = CreateColor(0, 140, 255),
        ["RAGE"]        = CreateColor(255, 50, 50),
        ["FOCUS"]       = CreateColor(255, 175, 100),
        ["ENERGY"]      = CreateColor(255, 225, 75),
        ["COMBO_POINTS"]= CreateColor(255, 225, 75),
        ["RUNES"]       = CreateColor(150, 150, 150),
        ["RUNIC_POWER"] = CreateColor(0, 200, 255),
        ["SOUL_SHARDS"] = CreateColor(180, 130, 220),
        ["LUNAR_POWER"] = CreateColor(100, 200, 255),
        ["HOLY_POWER"]  = CreateColor(240, 230, 120),
        ["MAELSTROM"]   = CreateColor(170, 95, 235),
        ["INSANITY"]    = CreateColor(100, 50, 180),
        ["CHI"]         = CreateColor(190, 240, 200),
        ["ARCANE_CHARGES"] = CreateColor(100, 150, 255),
        ["FURY"]        = CreateColor(200, 100, 200),
        ["PAIN"]        = CreateColor(255, 130, 50),
        ["ESSENCE"]     = CreateColor(100, 220, 200),
    },
}

-- ----------------------------------------------------------------------------
-- Item Quality
-- ----------------------------------------------------------------------------
RefineUI.Colors.Quality = {}
for i = 0, 8 do
    local r, g, b = C_Item.GetItemQualityColor(i)
    RefineUI.Colors.Quality[i] = CreateColor(r, g, b)
end

-- ----------------------------------------------------------------------------
-- Quick Access (Cached)
-- ----------------------------------------------------------------------------
local myClass = select(2, UnitClass("player"))
RefineUI.MyClassColor = RefineUI.Colors.Class[myClass]

-- ----------------------------------------------------------------------------
-- Curves (WoW 12.0+)
-- ----------------------------------------------------------------------------
if C_CurveUtil then
    RefineUI.CurvePercent = CurveConstants and CurveConstants.ScaleTo100 or 1.0
    RefineUI.SmoothBars = Enum.StatusBarInterpolation.ExponentialEaseOut

    -- Dispel / Debuff Types
    local DEBUFF_COLORS = {
        [0] = DEBUFF_TYPE_NONE_COLOR,
        [1] = DEBUFF_TYPE_MAGIC_COLOR,
        [2] = DEBUFF_TYPE_CURSE_COLOR,
        [3] = DEBUFF_TYPE_DISEASE_COLOR,
        [4] = DEBUFF_TYPE_POISON_COLOR,
        [9] = DEBUFF_TYPE_BLEED_COLOR, -- Enrage
        [11] = DEBUFF_TYPE_BLEED_COLOR, -- Bleed
    }

    RefineUI.DispelColorCurve = C_CurveUtil.CreateColorCurve()
    RefineUI.DispelColorCurve:SetType(Enum.LuaCurveType.Step)
    for typeID, colorInfo in pairs(DEBUFF_COLORS) do
        RefineUI.DispelColorCurve:AddPoint(typeID, colorInfo)
    end

    -- Health Gradient
    -- Red (Low) -> Yellow (Mid) -> Custom/Class (High)
    if C.UnitFrames and C.UnitFrames.HealthBarColor then
        local H = C.UnitFrames.HealthBarColor
        RefineUI.UnitFramesHealthColorCurve = C_CurveUtil.CreateColorCurve()
        RefineUI.UnitFramesHealthColorCurve:SetType(Enum.LuaCurveType.Cosine)
        RefineUI.UnitFramesHealthColorCurve:AddPoint(0, _G.CreateColor(0.6, 0, 0, 0.7))
        RefineUI.UnitFramesHealthColorCurve:AddPoint(0.90, _G.CreateColor(0.6, 0.6, 0, 0.7))
        RefineUI.UnitFramesHealthColorCurve:AddPoint(1, _G.CreateColor(unpack(H)))
    end
    
    -- Cooldowns
    if C.General and C.General.Cooldown then
        local CD = C.General.Cooldown
        RefineUI.CooldownColorCurve = C_CurveUtil.CreateColorCurve()
        RefineUI.CooldownColorCurve:SetType(Enum.LuaCurveType.Step)
        RefineUI.CooldownColorCurve:AddPoint(0,  _G.CreateColor(unpack(CD.ExpireColor)))
        RefineUI.CooldownColorCurve:AddPoint(4,  _G.CreateColor(unpack(CD.SecondsColor)))
        RefineUI.CooldownColorCurve:AddPoint(60, _G.CreateColor(unpack(CD.MinuteColor)))
    end

    -- Cast Colors (WoW 12.0 barType Solution)
    -- These are standard RGB tables, safe for non-secret logic
    RefineUI.Colors.Cast = {
        Interruptible    = {1, 0.8, 0},
        NonInterruptible = {1, 0.2, 0.2},
    }
    RefineUI.Colors.CastBG = {
        Interruptible    = {0.3, 0.24, 0},
        NonInterruptible = {0.3, 0.06, 0.06},
    }
end
