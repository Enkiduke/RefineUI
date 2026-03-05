----------------------------------------------------------------------------------------
-- Portals for RefineUI
-- Description: Minimap portals button and categorized teleport menu.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")
if not Maps then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local format = string.format
local lower = string.lower
local max = math.max
local min = math.min
local floor = math.floor
local tinsert = table.insert
local tsort = table.sort
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup
local PlayerHasToy = PlayerHasToy
local IsUsableSpell = _G.IsUsableSpell
local IsUsableItem = _G.IsUsableItem
local canaccessvalue = _G.canaccessvalue
local UIParent = _G.UIParent
local Minimap = _G.Minimap
local GameTooltip = _G.GameTooltip
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Item = C_Item
local C_ToyBox = C_ToyBox
local C_Texture = C_Texture
local GetSpellInfo = GetSpellInfo
local GetSpellCooldown = GetSpellCooldown
local GetItemCooldown = GetItemCooldown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PORTALS_BUTTON_NAME = "RefineUI_MinimapPortalsButton"
local PORTALS_MENU_NAME = "RefineUI_MinimapPortalsMenu"
local PORTALS_SUBMENU_NAME = "RefineUI_MinimapPortalsSubmenu"
local PORTALS_CLICK_CATCHER_NAME = "RefineUI_MinimapPortalsClickCatcher"

local ATLAS_PORTAL_BUTTON = "MagePortalAlliance"
local ATLAS_PIN_ICON = "friendslist-recentallies-Pin-yellow"
local FALLBACK_BUTTON_SPELL_ID = 10059
local ICON_QUESTION_MARK = 134400

local ROW_KIND_ACTION = "ACTION"
local ROW_KIND_CATEGORY = "CATEGORY"
local ROW_KIND_HEADER = "HEADER"

local ACTION_TYPE_SPELL = "spell"
local ACTION_TYPE_ITEM = "item"
local ACTION_TYPE_TOY = "toy"

local CATEGORY_KEY = {
    DUNGEON_RAID = "DUNGEON_RAID",
    TOYS = "TOYS",
    PROFESSIONS = "PROFESSIONS",
    CLASS = "CLASS",
    MAGE_TELEPORTS = "MAGE_TELEPORTS",
    MAGE_PORTALS = "MAGE_PORTALS",
}

local CATEGORY_LABEL = {
    [CATEGORY_KEY.DUNGEON_RAID] = "Dungeon/Raid Teleports",
    [CATEGORY_KEY.TOYS] = "Toys",
    [CATEGORY_KEY.PROFESSIONS] = "Professions",
    [CATEGORY_KEY.CLASS] = "Class Teleports",
    [CATEGORY_KEY.MAGE_TELEPORTS] = "Mage Teleports",
    [CATEGORY_KEY.MAGE_PORTALS] = "Mage Portals",
}

local CATEGORY_FALLBACK_ICON = {
    [CATEGORY_KEY.DUNGEON_RAID] = 236798,
    [CATEGORY_KEY.TOYS] = 237285,
    [CATEGORY_KEY.PROFESSIONS] = 136243,
    [CATEGORY_KEY.CLASS] = 135726,
    [CATEGORY_KEY.MAGE_TELEPORTS] = 135757,
    [CATEGORY_KEY.MAGE_PORTALS] = 135743,
}

local DEFAULT_PORTALS_CONFIG = {
    Enable = true,
    ButtonSize = 24,
    ButtonOffsetX = -3,
    ButtonOffsetY = 3,
    MenuWidth = 320,
    RowHeight = 24,
    MaxVisibleRows = 14,
    CloseOnMove = true,
    CloseOnCastStart = true,
    PinnedActions = {},
}

local MENU_PADDING_X = 10
local MENU_PADDING_Y = 10
local BUTTON_ICON_INSET = 1
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local PIN_ICON_SIZE = 16
local PIN_UNPINNED_R, PIN_UNPINNED_G, PIN_UNPINNED_B, PIN_UNPINNED_A = 0.62, 0.62, 0.62, 0.95
local PIN_PINNED_R, PIN_PINNED_G, PIN_PINNED_B, PIN_PINNED_A = 1, 0.82, 0, 1

local EVENT_KEY = {
    PLAYER_ENTERING_WORLD = "Maps:Portals:PLAYER_ENTERING_WORLD",
    SPELLS_CHANGED = "Maps:Portals:SPELLS_CHANGED",
    PLAYER_TALENT_UPDATE = "Maps:Portals:PLAYER_TALENT_UPDATE",
    PLAYER_SPECIALIZATION_CHANGED = "Maps:Portals:PLAYER_SPECIALIZATION_CHANGED",
    BAG_UPDATE_DELAYED = "Maps:Portals:BAG_UPDATE_DELAYED",
    NEW_TOY_ADDED = "Maps:Portals:NEW_TOY_ADDED",
    TOYS_UPDATED = "Maps:Portals:TOYS_UPDATED",
    SPELL_UPDATE_COOLDOWN = "Maps:Portals:SPELL_UPDATE_COOLDOWN",
    BAG_UPDATE_COOLDOWN = "Maps:Portals:BAG_UPDATE_COOLDOWN",
    PLAYER_REGEN_ENABLED = "Maps:Portals:PLAYER_REGEN_ENABLED",
    PLAYER_STARTED_MOVING = "Maps:Portals:PLAYER_STARTED_MOVING",
    UNIT_SPELLCAST_START = "Maps:Portals:UNIT_SPELLCAST_START",
}

local TIMER_KEY = {
    FULL_REFRESH = "Maps:Portals:FullRefresh",
}

local UPDATE_JOB_KEY = {
    BUTTON_VISIBILITY = "Maps:Portals:ButtonVisibility",
}

local HEARTHSTONE_TOP_LEVEL = {
    { label = "Hearthstone", itemID = 6948, spellID = 8690 },
    { label = "Dalaran Hearthstone", itemID = 140192, spellID = 222695 },
    { label = "Garrison Hearthstone", itemID = 110560, spellID = 171253 },
}

local TELEPORT_HOME_SPELL_ID = 1233637
local MOLE_MACHINE_SPELL_ID = 265225

local EXPANSION_DUNGEON_DATA = {
    { name = "Wrath of the Lich King", iconID = 236798, spellIDs = { 1254555 } },
    { name = "Cataclysm", iconID = 630784, spellIDs = { 445424, 424142, 410080 } },
    { name = "Mists of Pandaria", iconID = 630786, spellIDs = { 131225, 131222, 131231, 131229, 131232, 131206, 131228, 131205, 131204 } },
    { name = "Warlords of Draenor", iconID = 1031537, spellIDs = { 159897, 159895, 159901, 159900, 159896, 159899, 159898, 1254557, 159902 } },
    { name = "Legion", iconID = 1408999, spellIDs = { 424153, 393766, 424163, 393764, 373262, 410078, 1254551 } },
    { name = "Battle for Azeroth", iconID = 2065618, spellIDs = { 424187, 410071, 467553, 467555, 373274, 445418, 464256, 410074, 424167 } },
    { name = "Shadowlands", iconID = 3642306, spellIDs = { 354468, 354465, 354464, 354462, 354463, 354469, 354466, 367416, 354467, 373190, 373192, 373191 } },
    { name = "Dragonflight", iconID = 4672499, spellIDs = { 393273, 393279, 393267, 424197, 393283, 393276, 393262, 393256, 393222, 432257, 432258, 432254 } },
    { name = "The War Within", iconID = 5770811, spellIDs = { 445417, 445440, 445416, 445441, 445414, 1237215, 1216786, 445444, 445443, 445269, 1226482, 1239155 } },
    { name = "Midnight", iconID = 7578704, spellIDs = { 1254572, 1254559, 1254563, 1254400 } },
}
local DUNGEON_NAME_OVERRIDES = {
    [1254555] = "Pit of Saron",
    [445424] = "Grim Batol",
    [424142] = "Throne of the Tides",
    [410080] = "Vortex Pinnacle, The",
    [131225] = "Gate of the Setting Sun",
    [131222] = "Mogu'Shan Palace",
    [131231] = "Scarlet Halls",
    [131229] = "Scarlet Monastery",
    [131232] = "Scholomance",
    [131206] = "Shado-Pan Monastery",
    [131228] = "Siege of Niuzao Temple",
    [131205] = "Stormstout Brewery",
    [131204] = "Temple of the Jade Serpent",
    [159897] = "Auchindoun",
    [159895] = "Bloodmaul Slag Mines",
    [159901] = "Everbloom, The",
    [159900] = "Grimrail Depot",
    [159896] = "Iron Docks",
    [159899] = "Shadowmoon Burial Grounds",
    [159898] = "Skyreach (WOD)",
    [1254557] = "Skyreach",
    [159902] = "Upper Blackrock Spire",
    [424153] = "Black Rook Hold",
    [393766] = "Court of Stars",
    [424163] = "Darkheart Thicket",
    [393764] = "Halls of Valor",
    [373262] = "Karazhan",
    [410078] = "Neltharion's Lair",
    [1254551] = "Seat of the Triumvirate",
    [424187] = "Atal'Dazar",
    [410071] = "Freehold",
    [467553] = "MOTHERLODE!!, The",
    [467555] = "MOTHERLODE!!, The",
    [373274] = "Operation: Mechagon",
    [445418] = "Siege of Boralus",
    [464256] = "Siege of Boralus",
    [410074] = "Underrot, The",
    [424167] = "Waycrest Manor",
    [354468] = "De Other Side",
    [354465] = "Halls of Atonement",
    [354464] = "Mists of Tirna Scithe",
    [354462] = "Necrotic Wake, The",
    [354463] = "Plaguefall",
    [354469] = "Sanguine Depths",
    [354466] = "Spires of Ascension",
    [367416] = "Tazavesh, the Veiled Market",
    [354467] = "Theater of Pain",
    [373190] = "Castle Nathria",
    [373192] = "Sepulcher of the First Ones",
    [373191] = "Sanctum of Domination",
    [393273] = "Algeth'ar Academy",
    [393279] = "Azure Vault, The",
    [393267] = "Brackenhide Hollow",
    [424197] = "Dawn of the Infinite",
    [393283] = "Halls of Infusion",
    [393276] = "Neltharus",
    [393262] = "Nokhud Offensive, The",
    [393256] = "Ruby Life Pools",
    [393222] = "Uldaman: Legacy of Tyr",
    [432257] = "Aberrus, the Shadowed Crucible",
    [432258] = "Amirdrassil, the Dream's Hope",
    [432254] = "Vault of the Incarnates",
    [445417] = "Ara-Kara, City of Echoes",
    [445440] = "Cinderbrew Meadery",
    [445416] = "City of Threads",
    [445441] = "Darkflame Cleft",
    [445414] = "Dawnbreaker, The",
    [1237215] = "Eco-Dome Al'dani",
    [1216786] = "Operation: Floodgate",
    [445444] = "Priory of the Sacred Flame",
    [445443] = "Rookery, The",
    [445269] = "Stonevault, The",
    [1226482] = "Liberation of Undermine",
    [1239155] = "Manaforge Omega",
    [1254572] = "Magister's Terrace",
    [1254559] = "Maisara Caverns",
    [1254563] = "Nexus-Point Xenas",
    [1254400] = "Windrunner Spire",
}

local HEARTHSTONE_TOY_IDS = {
    190237, 166747, 265100, 93672, 208704, 188952, 210455, 190196,
    54452, 172179, 166746, 162973, 163045, 209035, 168907, 64488,
    184353, 257736, 165669, 182773, 180290, 165802, 228940, 200630,
    206195, 165670, 212337, 193588, 142542, 183716,
}
local HEARTHSTONE_TOY_LOOKUP = {}
for i = 1, #HEARTHSTONE_TOY_IDS do
    HEARTHSTONE_TOY_LOOKUP[HEARTHSTONE_TOY_IDS[i]] = true
end

local PROFESSION_ITEM_IDS = {
    18984, 18986, 30542, 30544, 48933, 87215, 112059,
    151652, 167075, 168807, 168808, 172924, 198156, 221966,
}

local CLASS_TELEPORT_SPELLS = {
    DEATHKNIGHT = {
        { spellID = 50977, label = "Death Gate" },
    },
    MONK = {
        { spellID = 126892, label = "Zen Pilgrimage" },
    },
    SHAMAN = {
        { spellID = 556, label = "Astral Recall" },
    },
}

local DRUID_TELEPORT_PRIMARY_SPELL_ID = 193753
local DRUID_TELEPORT_FALLBACK_SPELL_ID = 18960

local MAGE_TELEPORT_SPELLS = {
    3561, 3562, 3563, 3565, 3566, 3567, 32271, 32272, 49358, 49359,
    53140, 88342, 88344, 132621, 132627, 176248, 193759, 224869,
    281403, 281404, 344587, 395277, 446540, 1259190,
}

local MAGE_PORTAL_SPELLS = {
    10059, 11416, 11417, 11418, 11419, 11420, 32266, 32267, 49360, 49361,
    53142, 88345, 88346, 132620, 132626, 176246, 224871, 281400, 281402,
    344597, 395289, 446534, 1259194,
}

local FACTION_RESTRICTED_SPELLS = {
    [467553] = "Alliance",
    [467555] = "Horde",
    [49358] = "Horde",
    [49359] = "Alliance",
    [49360] = "Horde",
    [49361] = "Alliance",
    [88342] = "Alliance",
    [88344] = "Horde",
    [88345] = "Alliance",
    [88346] = "Horde",
    [132620] = "Alliance",
    [132621] = "Alliance",
    [132626] = "Horde",
    [132627] = "Horde",
    [281400] = "Alliance",
    [281402] = "Horde",
    [281403] = "Alliance",
    [281404] = "Horde",
    [1259190] = "Horde",
    [1259194] = "Horde",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local portalsButton
local portalsButtonIcon
local portalsMenu
local portalsSubmenu
local clickCatcher
local submenuScrollUpIndicator
local submenuScrollDownIndicator

local rootRows = {}
local submenuRows = {}
local rootEntries = {}
local submenuEntriesByCategory = {}
local activeSubmenuCategory
local submenuScrollOffset = 0

local pendingFullRefresh = false
local portalsInitialized = false
local portalsEventsRegistered = false

local RowState = setmetatable({}, { __mode = "k" })

local RequestFullRefresh
local ClosePortalsMenus
local OpenSubmenu

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ClampNumber(value, low, high, fallback)
    local number = tonumber(value)
    if not number then
        number = fallback
    end
    if number < low then
        return low
    end
    if number > high then
        return high
    end
    return number
end

local function GetPortalsConfig()
    local dbPortals = Maps.db and Maps.db.Portals
    local configPortals = Config and Config.Maps and Config.Maps.Portals

    local function ReadValue(key)
        if type(dbPortals) == "table" and dbPortals[key] ~= nil then
            return dbPortals[key]
        end
        if type(configPortals) == "table" and configPortals[key] ~= nil then
            return configPortals[key]
        end
        return DEFAULT_PORTALS_CONFIG[key]
    end

    return {
        Enable = ReadValue("Enable") ~= false,
        ButtonSize = floor(ClampNumber(ReadValue("ButtonSize"), 16, 48, DEFAULT_PORTALS_CONFIG.ButtonSize) + 0.5),
        ButtonOffsetX = floor(ClampNumber(ReadValue("ButtonOffsetX"), -64, 64, DEFAULT_PORTALS_CONFIG.ButtonOffsetX) + 0.5),
        ButtonOffsetY = floor(ClampNumber(ReadValue("ButtonOffsetY"), -64, 64, DEFAULT_PORTALS_CONFIG.ButtonOffsetY) + 0.5),
        MenuWidth = floor(ClampNumber(ReadValue("MenuWidth"), 200, 480, DEFAULT_PORTALS_CONFIG.MenuWidth) + 0.5),
        RowHeight = floor(ClampNumber(ReadValue("RowHeight"), 18, 36, DEFAULT_PORTALS_CONFIG.RowHeight) + 0.5),
        MaxVisibleRows = floor(ClampNumber(ReadValue("MaxVisibleRows"), 6, 30, DEFAULT_PORTALS_CONFIG.MaxVisibleRows) + 0.5),
        CloseOnMove = ReadValue("CloseOnMove") ~= false,
        CloseOnCastStart = ReadValue("CloseOnCastStart") ~= false,
    }
end

local function MigratePortalsConfigDefaults()
    local dbPortals = Maps.db and Maps.db.Portals
    if type(dbPortals) ~= "table" then
        return
    end

    if dbPortals.ButtonSize == 22 then
        dbPortals.ButtonSize = DEFAULT_PORTALS_CONFIG.ButtonSize
    end
    if type(dbPortals.PinnedActions) ~= "table" then
        dbPortals.PinnedActions = {}
        return
    end

    local keepHearthToyKey
    for i = 1, #HEARTHSTONE_TOY_IDS do
        local key = ACTION_TYPE_TOY .. ":" .. tostring(HEARTHSTONE_TOY_IDS[i])
        if dbPortals.PinnedActions[key] == true then
            keepHearthToyKey = key
            break
        end
    end

    if not keepHearthToyKey then
        return
    end

    for key, enabled in pairs(dbPortals.PinnedActions) do
        if enabled == true and key ~= keepHearthToyKey then
            local actionType, actionIDText = tostring(key):match("^([^:]+):(%d+)$")
            local actionID = tonumber(actionIDText)
            if actionType == ACTION_TYPE_TOY and actionID and HEARTHSTONE_TOY_LOOKUP[actionID] then
                dbPortals.PinnedActions[key] = nil
            end
        end
    end
end

local function GetPlayerClassToken()
    local classToken = RefineUI.MyClass
    if classToken and classToken ~= "" then
        return classToken
    end
    local _, token = UnitClass("player")
    return token
end

local function IsMagePlayer()
    return GetPlayerClassToken() == "MAGE"
end

local function EnsureRowState(row)
    local state = RowState[row]
    if not state then
        state = {}
        RowState[row] = state
    end
    return state
end

local function GetDefaultBorderColor()
    local color = Config and Config.General and Config.General.BorderColor
    if type(color) == "table" then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

local function SetBorderColor(frame, r, g, b, a)
    if not frame then
        return
    end
    local border = frame.RefineBorder or frame.border
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(r, g, b, a or 1)
    end
end

local function IsDescendantOf(frame, ancestor)
    if not frame or not ancestor then
        return false
    end

    local current = frame
    while current do
        if current == ancestor then
            return true
        end

        if type(current.GetParent) ~= "function" then
            break
        end

        local ok, parent = pcall(current.GetParent, current)
        if not ok then
            break
        end

        current = parent
    end

    return false
end

local function IsPortalTooltipOwner(owner)
    if not owner then
        return false
    end

    if owner == portalsButton or owner == portalsMenu or owner == portalsSubmenu then
        return true
    end

    if IsDescendantOf(owner, portalsButton) or IsDescendantOf(owner, portalsMenu) or IsDescendantOf(owner, portalsSubmenu) then
        return true
    end

    return false
end

local function HidePortalTooltipIfOwned()
    local owner = GameTooltip and GameTooltip:GetOwner()
    if IsPortalTooltipOwner(owner) then
        GameTooltip:Hide()
    end
end

local function AddToUISpecialFrames(frameName)
    local specialFrames = _G.UISpecialFrames
    if type(specialFrames) ~= "table" then
        return
    end
    for i = 1, #specialFrames do
        if specialFrames[i] == frameName then
            return
        end
    end
    tinsert(specialFrames, frameName)
end

local function NormalizeSortKey(label)
    if type(label) ~= "string" then
        return ""
    end
    return lower(label)
end

local function SortEntriesByLabel(entries)
    tsort(entries, function(a, b)
        local aKey = NormalizeSortKey(a and a.label)
        local bKey = NormalizeSortKey(b and b.label)
        if aKey == bKey then
            return tostring(a and a.actionID or a and a.label or "") < tostring(b and b.actionID or b and b.label or "")
        end
        return aKey < bKey
    end)
end

local function GetPinnedActionsTable(createIfMissing)
    local mapsConfig = Maps.db
    if type(mapsConfig) ~= "table" then
        return nil
    end

    if type(mapsConfig.Portals) ~= "table" then
        if not createIfMissing then
            return nil
        end
        mapsConfig.Portals = {}
    end

    local portalsConfig = mapsConfig.Portals
    if type(portalsConfig.PinnedActions) ~= "table" then
        if not createIfMissing then
            return nil
        end
        portalsConfig.PinnedActions = {}
    end

    return portalsConfig.PinnedActions
end

local function BuildEntryPinKey(entry)
    if type(entry) ~= "table" or entry.kind ~= ROW_KIND_ACTION then
        return nil
    end

    local actionType = entry.actionType
    local actionID = entry.actionID
    if type(actionType) ~= "string" or type(actionID) ~= "number" then
        return nil
    end

    return actionType .. ":" .. tostring(actionID)
end

local function IsHearthstoneToyPinKey(pinKey)
    local actionType, actionIDText = tostring(pinKey):match("^([^:]+):(%d+)$")
    local actionID = tonumber(actionIDText)
    return actionType == ACTION_TYPE_TOY and actionID and HEARTHSTONE_TOY_LOOKUP[actionID] == true
end

local function IsHearthstoneToyEntry(entry)
    return type(entry) == "table"
        and entry.kind == ROW_KIND_ACTION
        and entry.actionType == ACTION_TYPE_TOY
        and type(entry.actionID) == "number"
        and HEARTHSTONE_TOY_LOOKUP[entry.actionID] == true
end

local function ClearPinnedHearthstoneToys(exceptPinKey)
    local pinnedActions = GetPinnedActionsTable(false)
    if type(pinnedActions) ~= "table" then
        return
    end

    for key, enabled in pairs(pinnedActions) do
        if enabled == true and key ~= exceptPinKey and IsHearthstoneToyPinKey(key) then
            pinnedActions[key] = nil
        end
    end
end

local function IsEntryPinned(entry)
    local key = BuildEntryPinKey(entry)
    if not key then
        return false
    end

    local pinnedActions = GetPinnedActionsTable(false)
    return type(pinnedActions) == "table" and pinnedActions[key] == true
end

local function SetEntryPinned(entry, pinned)
    local key = BuildEntryPinKey(entry)
    if not key then
        return
    end

    local pinnedActions = GetPinnedActionsTable(true)
    if type(pinnedActions) ~= "table" then
        return
    end

    if pinned then
        if IsHearthstoneToyEntry(entry) then
            ClearPinnedHearthstoneToys(key)
        end
        pinnedActions[key] = true
    else
        pinnedActions[key] = nil
    end
end

local function CloneActionEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    return {
        kind = entry.kind,
        label = entry.label,
        iconID = entry.iconID,
        actionType = entry.actionType,
        actionID = entry.actionID,
        spellID = entry.spellID,
        itemID = entry.itemID,
        actionSpellName = entry.actionSpellName,
        pinKey = entry.pinKey,
        isPinnedRoot = entry.isPinnedRoot == true,
    }
end

local function BuildAvailableActionEntryMap(submenuMap)
    local availableByKey = {}
    for _, entries in pairs(submenuMap) do
        if type(entries) == "table" then
            for i = 1, #entries do
                local entry = entries[i]
                local key = BuildEntryPinKey(entry)
                if key and not availableByKey[key] then
                    availableByKey[key] = entry
                end
            end
        end
    end
    return availableByKey
end

local function BuildPinnedHearthstoneReplacementEntry(submenuMap)
    local pinnedActions = GetPinnedActionsTable(false)
    if type(submenuMap) ~= "table" or type(pinnedActions) ~= "table" then
        return nil, nil
    end

    local availableByKey = BuildAvailableActionEntryMap(submenuMap)
    for i = 1, #HEARTHSTONE_TOY_IDS do
        local itemID = HEARTHSTONE_TOY_IDS[i]
        local key = ACTION_TYPE_TOY .. ":" .. tostring(itemID)
        if pinnedActions[key] == true and availableByKey[key] then
            local copy = CloneActionEntry(availableByKey[key])
            if copy then
                copy.pinKey = key
                copy.isPinnedRoot = true
            end
            return copy, key
        end
    end

    return nil, nil
end

local function BuildPinnedRootEntries(submenuMap)
    local pinnedActions = GetPinnedActionsTable(false)
    if type(submenuMap) ~= "table" or type(pinnedActions) ~= "table" then
        return {}
    end

    local availableByKey = BuildAvailableActionEntryMap(submenuMap)

    local pinnedEntries = {}
    for key, enabled in pairs(pinnedActions) do
        if enabled == true and not IsHearthstoneToyPinKey(key) and availableByKey[key] then
            local copy = CloneActionEntry(availableByKey[key])
            if copy then
                copy.pinKey = key
                copy.isPinnedRoot = true
                tinsert(pinnedEntries, copy)
            end
        end
    end

    SortEntriesByLabel(pinnedEntries)
    return pinnedEntries
end

local function IsSpellAllowedForFaction(spellID)
    local requiredFaction = FACTION_RESTRICTED_SPELLS[spellID]
    if not requiredFaction then
        return true
    end
    return UnitFactionGroup("player") == requiredFaction
end

local function IsSpellKnownSafe(spellID)
    if type(spellID) ~= "number" then
        return false
    end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" and C_SpellBook.IsSpellKnown(spellID) then
        return true
    end
    if C_SpellBook and type(C_SpellBook.IsSpellKnownOrInSpellBook) == "function" and C_SpellBook.IsSpellKnownOrInSpellBook(spellID) then
        return true
    end
    if type(_G.IsPlayerSpell) == "function" and _G.IsPlayerSpell(spellID) then
        return true
    end
    if type(_G.IsSpellKnown) == "function" and _G.IsSpellKnown(spellID) then
        return true
    end
    return false
end

local function GetSpellInfoSafe(spellID)
    if type(spellID) ~= "number" then
        return nil, nil
    end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            return info.name, info.iconID or info.iconFileID
        end
    end
    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
    return nil, nil
end

local function GetSpellCooldownSafe(spellID)
    if type(GetSpellCooldown) == "function" then
        local startTime, duration = GetSpellCooldown(spellID)
        if type(startTime) == "number" and type(duration) == "number" then
            return startTime, duration
        end
    end

    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
        if type(cooldownInfo) == "table" then
            return cooldownInfo.startTime, cooldownInfo.duration
        end
    end
    return 0, 0
end

local function GetItemCooldownSafe(itemID)
    if type(GetItemCooldown) == "function" then
        local startTime, duration = GetItemCooldown(itemID)
        if type(startTime) == "number" and type(duration) == "number" then
            return startTime, duration
        end
    end

    if C_Item and type(C_Item.GetItemCooldown) == "function" then
        local startTime, duration = C_Item.GetItemCooldown(itemID)
        return startTime, duration
    end
    return 0, 0
end

local function GetItemCountSafe(itemID)
    if C_Item and type(C_Item.GetItemCount) == "function" then
        return C_Item.GetItemCount(itemID) or 0
    end
    return 0
end

local function IsToyOwned(itemID)
    return type(PlayerHasToy) == "function" and PlayerHasToy(itemID) == true
end

local function IsSpellUsableSafe(spellID)
    if type(spellID) ~= "number" then
        return false
    end

    if type(IsUsableSpell) == "function" then
        local isUsable = IsUsableSpell(spellID)
        if isUsable == false then
            return false
        end
    end

    return true
end

local function IsToyUsableSafe(itemID)
    if type(itemID) ~= "number" then
        return false
    end

    if C_ToyBox and type(C_ToyBox.IsToyUsable) == "function" then
        return C_ToyBox.IsToyUsable(itemID) == true
    end

    return true
end

local function IsItemUsableSafe(itemID)
    if type(itemID) ~= "number" then
        return false
    end

    if type(IsUsableItem) == "function" then
        local isUsable = IsUsableItem(itemID)
        if isUsable == false then
            return false
        end
    end

    return true
end

local function IsItemOwned(itemID)
    return GetItemCountSafe(itemID) > 0
end

local function GetItemIconSafe(itemID)
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local iconID = C_Item.GetItemIconByID(itemID)
        if type(iconID) == "number" then
            return iconID
        end
    end
    return nil
end

local function GetItemNameSafe(itemID)
    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local itemName = C_Item.GetItemNameByID(itemID)
        if type(itemName) == "string" and itemName ~= "" then
            return itemName
        end
    end

    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local itemInfo = C_Item.GetItemInfo(itemID)
        if type(itemInfo) == "table" then
            return itemInfo.itemName or itemInfo.name
        end
        if type(itemInfo) == "string" and itemInfo ~= "" then
            return itemInfo
        end
    end

    return nil
end

local function GetToyInfoSafe(itemID)
    if not C_ToyBox or type(C_ToyBox.GetToyInfo) ~= "function" then
        return nil, nil
    end

    local toyInfoA, toyInfoB, toyInfoC = C_ToyBox.GetToyInfo(itemID)
    if type(toyInfoA) == "table" then
        return toyInfoA.toyName or toyInfoA.name, toyInfoA.icon
    end

    local toyName
    local toyIcon

    if type(toyInfoB) == "string" then
        toyName = toyInfoB
    elseif type(toyInfoA) == "string" then
        toyName = toyInfoA
    end

    if type(toyInfoC) == "number" then
        toyIcon = toyInfoC
    elseif type(toyInfoB) == "number" then
        toyIcon = toyInfoB
    end

    return toyName, toyIcon
end

local function ResolveItemOrToyAction(itemID)
    if IsToyOwned(itemID) then
        return ACTION_TYPE_TOY, itemID
    end
    if IsItemOwned(itemID) then
        return ACTION_TYPE_ITEM, itemID
    end
    return nil, nil
end

local function ResolveHearthstoneAction(itemID, spellID)
    if IsToyOwned(itemID) then
        return ACTION_TYPE_TOY, itemID
    end
    if IsItemOwned(itemID) then
        return ACTION_TYPE_ITEM, itemID
    end
    if spellID and IsSpellKnownSafe(spellID) then
        return ACTION_TYPE_SPELL, spellID
    end
    return nil, nil
end

local function BuildSpellActionEntry(spellID, labelOverride)
    if type(spellID) ~= "number" or not IsSpellAllowedForFaction(spellID) or not IsSpellKnownSafe(spellID) then
        return nil
    end

    local spellName, spellIcon = GetSpellInfoSafe(spellID)
    if not spellName then
        return nil
    end

    return {
        kind = ROW_KIND_ACTION,
        label = labelOverride or spellName,
        iconID = spellIcon or ICON_QUESTION_MARK,
        actionType = ACTION_TYPE_SPELL,
        actionID = spellID,
        spellID = spellID,
        actionSpellName = spellName,
    }
end

local function BuildItemOrToyActionEntry(itemID, labelOverride)
    local actionType, actionID = ResolveItemOrToyAction(itemID)
    if not actionType then
        return nil
    end

    local label = labelOverride
    local iconID = GetItemIconSafe(itemID) or ICON_QUESTION_MARK

    if actionType == ACTION_TYPE_TOY then
        local toyName, toyIcon = GetToyInfoSafe(itemID)
        label = label or toyName
        if toyIcon then
            iconID = toyIcon
        end
    else
        label = label or GetItemNameSafe(itemID)
    end

    if not label or label == "" then
        label = format("item:%d", itemID)
    end

    return {
        kind = ROW_KIND_ACTION,
        label = label,
        iconID = iconID,
        actionType = actionType,
        actionID = actionID,
        itemID = itemID,
    }
end

local function BuildHearthstoneEntry(data)
    local actionType, actionID = ResolveHearthstoneAction(data.itemID, data.spellID)
    if not actionType then
        return nil
    end

    local iconID = GetItemIconSafe(data.itemID)
    local label = data.label
    local spellName

    if actionType == ACTION_TYPE_TOY then
        local toyName, toyIcon = GetToyInfoSafe(data.itemID)
        if toyName and toyName ~= "" then
            label = data.label or toyName
        end
        if toyIcon then
            iconID = toyIcon
        end
    elseif actionType == ACTION_TYPE_SPELL then
        spellName, iconID = GetSpellInfoSafe(actionID)
        label = data.label or spellName or data.label
    end

    if not iconID then
        iconID = ICON_QUESTION_MARK
    end

    local entry = {
        kind = ROW_KIND_ACTION,
        label = label or data.label,
        iconID = iconID,
        actionType = actionType,
        actionID = actionID,
        itemID = data.itemID,
        spellID = data.spellID,
    }
    if actionType == ACTION_TYPE_SPELL then
        entry.actionSpellName = spellName
    end
    return entry
end

local function BuildDungeonRaidEntries()
    local entries = {}

    for i = 1, #EXPANSION_DUNGEON_DATA do
        local expansion = EXPANSION_DUNGEON_DATA[i]
        local spellEntries = {}

        for j = 1, #expansion.spellIDs do
            local spellID = expansion.spellIDs[j]
            local entry = BuildSpellActionEntry(spellID, DUNGEON_NAME_OVERRIDES[spellID])
            if entry then
                tinsert(spellEntries, entry)
            end
        end

        if #spellEntries > 0 then
            SortEntriesByLabel(spellEntries)
            tinsert(entries, {
                kind = ROW_KIND_HEADER,
                label = expansion.name,
                iconID = expansion.iconID or CATEGORY_FALLBACK_ICON[CATEGORY_KEY.DUNGEON_RAID],
            })
            for j = 1, #spellEntries do
                tinsert(entries, spellEntries[j])
            end
        end
    end

    return entries
end

local function BuildToyEntries()
    local entries = {}

    for i = 1, #HEARTHSTONE_TOY_IDS do
        local itemID = HEARTHSTONE_TOY_IDS[i]
        if IsToyOwned(itemID) then
            local entry = BuildItemOrToyActionEntry(itemID)
            if entry then
                tinsert(entries, entry)
            end
        end
    end

    SortEntriesByLabel(entries)
    return entries
end

local function BuildProfessionEntries()
    local entries = {}
    local seenKey = {}

    local moleEntry = BuildSpellActionEntry(MOLE_MACHINE_SPELL_ID, "Dark Iron Mole Machine")
    if moleEntry and IsSpellUsableSafe(moleEntry.spellID or moleEntry.actionID) then
        local key = ACTION_TYPE_SPELL .. ":" .. tostring(moleEntry.actionID)
        seenKey[key] = true
        tinsert(entries, moleEntry)
    end

    for i = 1, #PROFESSION_ITEM_IDS do
        local itemID = PROFESSION_ITEM_IDS[i]
        local entry = BuildItemOrToyActionEntry(itemID)
        if entry then
            local isUsable = false
            if entry.actionType == ACTION_TYPE_TOY then
                isUsable = IsToyUsableSafe(entry.actionID)
            elseif entry.actionType == ACTION_TYPE_ITEM then
                isUsable = IsItemUsableSafe(entry.actionID)
            end

            if not isUsable then
                entry = nil
            end
        end

        if entry then
            local key = tostring(entry.actionType) .. ":" .. tostring(entry.actionID)
            if not seenKey[key] then
                seenKey[key] = true
                tinsert(entries, entry)
            end
        end
    end

    SortEntriesByLabel(entries)
    return entries
end

local function BuildClassEntries()
    local classToken = GetPlayerClassToken()
    local entries = {}

    if classToken == "MAGE" then
        return entries
    end

    if classToken == "DRUID" then
        local dreamwalkEntry = BuildSpellActionEntry(DRUID_TELEPORT_PRIMARY_SPELL_ID, "Dreamwalk")
        if dreamwalkEntry then
            tinsert(entries, dreamwalkEntry)
        else
            local moongladeEntry = BuildSpellActionEntry(DRUID_TELEPORT_FALLBACK_SPELL_ID, "Teleport: Moonglade")
            if moongladeEntry then
                tinsert(entries, moongladeEntry)
            end
        end
        SortEntriesByLabel(entries)
        return entries
    end

    local classSpells = CLASS_TELEPORT_SPELLS[classToken]
    if type(classSpells) ~= "table" then
        return entries
    end

    for i = 1, #classSpells do
        local spellData = classSpells[i]
        local entry = BuildSpellActionEntry(spellData.spellID, spellData.label)
        if entry then
            tinsert(entries, entry)
        end
    end

    SortEntriesByLabel(entries)
    return entries
end

local function BuildMageEntries(spellList)
    local entries = {}
    if not IsMagePlayer() then
        return entries
    end

    for i = 1, #spellList do
        local spellID = spellList[i]
        local entry = BuildSpellActionEntry(spellID)
        if entry then
            tinsert(entries, entry)
        end
    end

    SortEntriesByLabel(entries)
    return entries
end

local function AddCategoryEntry(rootList, submenuMap, categoryKey, entries)
    if type(entries) ~= "table" or #entries == 0 then
        return
    end

    local iconID = CATEGORY_FALLBACK_ICON[categoryKey] or ICON_QUESTION_MARK
    for i = 1, #entries do
        local entry = entries[i]
        if entry.kind == ROW_KIND_ACTION and entry.iconID then
            iconID = entry.iconID
            break
        end
    end

    tinsert(rootList, {
        kind = ROW_KIND_CATEGORY,
        label = CATEGORY_LABEL[categoryKey] or categoryKey,
        iconID = iconID,
        categoryKey = categoryKey,
    })

    submenuMap[categoryKey] = entries
end

local function BuildRootAndSubmenuEntries()
    local newRootEntries = {}
    local newSubmenuEntriesByCategory = {}
    local dungeonEntries = BuildDungeonRaidEntries()
    local toyEntries = BuildToyEntries()
    local professionEntries = BuildProfessionEntries()
    local classEntries = BuildClassEntries()
    local mageTeleportEntries = BuildMageEntries(MAGE_TELEPORT_SPELLS)
    local magePortalEntries = BuildMageEntries(MAGE_PORTAL_SPELLS)

    if #dungeonEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.DUNGEON_RAID] = dungeonEntries
    end
    if #toyEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.TOYS] = toyEntries
    end
    if #professionEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.PROFESSIONS] = professionEntries
    end
    if #classEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.CLASS] = classEntries
    end
    if #mageTeleportEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.MAGE_TELEPORTS] = mageTeleportEntries
    end
    if #magePortalEntries > 0 then
        newSubmenuEntriesByCategory[CATEGORY_KEY.MAGE_PORTALS] = magePortalEntries
    end

    local pinnedHearthstoneReplacement = BuildPinnedHearthstoneReplacementEntry(newSubmenuEntriesByCategory)
    for i = 1, #HEARTHSTONE_TOP_LEVEL do
        if i == 1 and pinnedHearthstoneReplacement then
            tinsert(newRootEntries, pinnedHearthstoneReplacement)
        else
            local hearthEntry = BuildHearthstoneEntry(HEARTHSTONE_TOP_LEVEL[i])
            if hearthEntry then
                tinsert(newRootEntries, hearthEntry)
            end
        end
    end

    local pinnedEntries = BuildPinnedRootEntries(newSubmenuEntriesByCategory)

    for i = 1, #pinnedEntries do
        tinsert(newRootEntries, pinnedEntries[i])
    end

    local teleportHomeEntry = BuildSpellActionEntry(TELEPORT_HOME_SPELL_ID, "Teleport Home")
    if teleportHomeEntry then
        tinsert(newRootEntries, teleportHomeEntry)
    end

    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.DUNGEON_RAID, dungeonEntries)
    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.TOYS, toyEntries)
    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.PROFESSIONS, professionEntries)
    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.CLASS, classEntries)
    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.MAGE_TELEPORTS, mageTeleportEntries)
    AddCategoryEntry(newRootEntries, newSubmenuEntriesByCategory, CATEGORY_KEY.MAGE_PORTALS, magePortalEntries)

    return newRootEntries, newSubmenuEntriesByCategory
end
----------------------------------------------------------------------------------------
-- Row Rendering
----------------------------------------------------------------------------------------
local function ClearActionAttributes(row)
    if not row or InCombatLockdown() then
        return
    end

    row:SetAttribute("type", nil)
    row:SetAttribute("item", nil)
    row:SetAttribute("spell", nil)
    row:SetAttribute("macrotext", nil)
    row:SetAttribute("type1", nil)
    row:SetAttribute("item1", nil)
    row:SetAttribute("spell1", nil)
    row:SetAttribute("toy", nil)
    row:SetAttribute("toy1", nil)
    row:SetAttribute("macrotext1", nil)
end

local function GetEntryCooldown(entry)
    if not entry or entry.kind ~= ROW_KIND_ACTION then
        return 0, 0
    end

    if entry.actionType == ACTION_TYPE_SPELL then
        return GetSpellCooldownSafe(entry.spellID or entry.actionID)
    end

    local itemID = entry.itemID or entry.actionID
    return GetItemCooldownSafe(itemID)
end

local function UpdateRowCooldown(row)
    if not row or not row.cooldown or not row.text then
        return
    end

    local state = RowState[row]
    local entry = state and state.entry
    if not entry or entry.kind ~= ROW_KIND_ACTION then
        row.cooldown:Hide()
        return
    end

    local startTime, duration = GetEntryCooldown(entry)
    local hasSecretStart = RefineUI.IsSecretValue and RefineUI:IsSecretValue(startTime)
    local hasSecretDuration = RefineUI.IsSecretValue and RefineUI:IsSecretValue(duration)
    local canInspectStart = not hasSecretStart
    local canInspectDuration = not hasSecretDuration
    if type(canaccessvalue) == "function" then
        if hasSecretStart then
            canInspectStart = canaccessvalue(startTime) == true
        end
        if hasSecretDuration then
            canInspectDuration = canaccessvalue(duration) == true
        end
    end

    if canInspectStart and canInspectDuration then
        local startNumber = tonumber(startTime) or 0
        local durationNumber = tonumber(duration) or 0
        if durationNumber > 1.5 and startNumber > 0 then
            row.cooldown:SetCooldown(startNumber, durationNumber)
            row.cooldown:Show()
            row.text:SetTextColor(0.65, 0.65, 0.65)
            return
        end

        row.cooldown:Hide()
        row.cooldown:SetCooldown(0, 0)
        row.text:SetTextColor(1, 1, 1)
        return
    end

    if RefineUI.HasValue and RefineUI:HasValue(startTime) and RefineUI:HasValue(duration) then
        row.cooldown:SetCooldown(startTime, duration)
        row.cooldown:Show()
    else
        row.cooldown:Hide()
        row.cooldown:SetCooldown(0, 0)
    end
    row.text:SetTextColor(1, 1, 1)
end

local function ConfigureRowAction(row, entry)
    if not row or not entry then
        return
    end
    if InCombatLockdown() then
        pendingFullRefresh = true
        return
    end

    ClearActionAttributes(row)

    if entry.kind ~= ROW_KIND_ACTION then
        return
    end

    if entry.actionType == ACTION_TYPE_SPELL then
        local spellID = entry.spellID or entry.actionID
        local spellName = entry.actionSpellName
        if not spellName and type(spellID) == "number" and C_Spell and type(C_Spell.GetSpellName) == "function" then
            spellName = C_Spell.GetSpellName(spellID)
        end
        local spellToken = spellName or spellID
        if type(spellID) == "number" then
            row:SetAttribute("type", "spell")
            row:SetAttribute("spell", spellToken)
            row:SetAttribute("type1", "spell")
            row:SetAttribute("spell1", spellToken)
        end
    elseif entry.actionType == ACTION_TYPE_ITEM then
        local itemToken = format("item:%d", entry.actionID)
        row:SetAttribute("type", "item")
        row:SetAttribute("item", itemToken)
        row:SetAttribute("type1", "item")
        row:SetAttribute("item1", itemToken)
    elseif entry.actionType == ACTION_TYPE_TOY then
        row:SetAttribute("type", "toy")
        row:SetAttribute("toy", entry.actionID)
        row:SetAttribute("type1", "toy")
        row:SetAttribute("toy1", entry.actionID)
    end
end

local function UpdatePinButtonForRow(row, entry)
    if not row or not row.pinButton or not row.pinIcon then
        return
    end

    local pinKey = (type(entry) == "table" and entry.pinKey) or BuildEntryPinKey(entry)
    local isPinnable = type(entry) == "table" and entry.kind == ROW_KIND_ACTION and type(pinKey) == "string" and (row.isSubmenuRow or entry.isPinnedRoot == true)
    if not isPinnable then
        row.pinButton:Hide()
        return
    end

    local pinned = IsEntryPinned(entry)
    if row.pinIcon.SetAtlas then
        row.pinIcon:SetAtlas(ATLAS_PIN_ICON, true)
    else
        row.pinIcon:SetTexture(ICON_QUESTION_MARK)
        row.pinIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end

    if pinned then
        row.pinIcon:SetDesaturated(false)
        row.pinIcon:SetVertexColor(PIN_PINNED_R, PIN_PINNED_G, PIN_PINNED_B, PIN_PINNED_A)
    else
        row.pinIcon:SetDesaturated(true)
        row.pinIcon:SetVertexColor(PIN_UNPINNED_R, PIN_UNPINNED_G, PIN_UNPINNED_B, PIN_UNPINNED_A)
    end

    row.pinButton:Show()
end

local function OnPinButtonEnter(self)
    local row = self and self:GetParent()
    local state = row and RowState[row]
    local entry = state and state.entry
    if not entry then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if IsEntryPinned(entry) then
        GameTooltip:SetText("Unpin from main menu", 1, 1, 1)
    else
        GameTooltip:SetText("Pin to main menu", 1, 1, 1)
    end
    GameTooltip:Show()
end

local function OnPinButtonLeave()
    GameTooltip:Hide()
end

local function OnPinButtonClick(self, button)
    if button ~= "LeftButton" or InCombatLockdown() then
        return
    end

    local row = self and self:GetParent()
    local state = row and RowState[row]
    local entry = state and state.entry
    if not entry or entry.kind ~= ROW_KIND_ACTION then
        return
    end

    local currentlyPinned = IsEntryPinned(entry)
    SetEntryPinned(entry, not currentlyPinned)
    UpdatePinButtonForRow(row, entry)
    RequestFullRefresh(true)
end

local function ApplyEntryToRow(row, entry)
    local state = EnsureRowState(row)
    state.entry = entry

    row.text:SetText(entry.label or "")
    row.icon:SetTexture(entry.iconID or ICON_QUESTION_MARK)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    row.arrow:SetShown(entry.kind == ROW_KIND_CATEGORY)
    row.headerSeparator:Hide()
    if row.pinButton then
        row.pinButton:Hide()
    end

    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(entry.kind == ROW_KIND_HEADER and 0 or 0.7)
    end

    if entry.kind == ROW_KIND_HEADER then
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetTextColor(1, 0.82, 0)
        row.cooldown:Hide()
        row.icon:SetDesaturated(false)
        local separatorStart = 40 + floor(row.text:GetStringWidth() + 0.5)
        local maxStart = (row:GetWidth() or 0) - 24
        if separatorStart < maxStart then
            row.headerSeparator:ClearAllPoints()
            row.headerSeparator:SetPoint("LEFT", row, "LEFT", separatorStart, 0)
            row.headerSeparator:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.headerSeparator:Show()
        end
        ConfigureRowAction(row, entry)
        return
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    if row.isSubmenuRow or entry.isPinnedRoot == true then
        row.text:SetPoint("RIGHT", row, "RIGHT", -26, 0)
    else
        row.text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    end

    if entry.kind == ROW_KIND_CATEGORY then
        row.text:SetTextColor(1, 1, 1)
        row.cooldown:Hide()
        row.icon:SetDesaturated(false)
        ConfigureRowAction(row, entry)
        return
    end

    row.icon:SetDesaturated(false)
    UpdatePinButtonForRow(row, entry)
    ConfigureRowAction(row, entry)
    UpdateRowCooldown(row)
end

local function OnRowEnter(self)
    local state = RowState[self]
    local entry = state and state.entry
    if not entry then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

    if entry.kind == ROW_KIND_ACTION then
        if entry.actionType == ACTION_TYPE_SPELL and entry.spellID then
            GameTooltip:SetSpellByID(entry.spellID)
        elseif entry.itemID then
            GameTooltip:SetItemByID(entry.itemID)
        else
            GameTooltip:SetText(entry.label or "Portals", 1, 1, 1)
        end
    elseif entry.kind == ROW_KIND_CATEGORY then
        GameTooltip:SetText(entry.label or "Category", 1, 1, 1)
        GameTooltip:AddLine("Click to open", 0.75, 0.75, 0.75)
    else
        GameTooltip:SetText(entry.label or "", 1, 0.82, 0)
    end

    GameTooltip:Show()
end

local function OnRowLeave()
    GameTooltip:Hide()
end

local function OnRowClick(self, button)
    if button ~= "LeftButton" then
        return
    end

    if InCombatLockdown() then
        return
    end

    local state = RowState[self]
    local entry = state and state.entry
    if not entry then
        return
    end

    if entry.kind == ROW_KIND_CATEGORY then
        OpenSubmenu(entry.categoryKey, self)
    end
end

local function CreateMenuRow(parent, isSubmenuRow)
    local row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    row.isSubmenuRow = isSubmenuRow == true
    row:SetFrameStrata(parent:GetFrameStrata())
    row:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
    row:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    row:SetAttribute("useOnKeyDown", false)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)
    row:HookScript("OnMouseUp", OnRowClick)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexture(ICON_QUESTION_MARK)
    row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    row.cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    row.cooldown:SetDrawEdge(false)
    row.cooldown:SetSwipeColor(0, 0, 0, 0.7)
    row.cooldown:Hide()

    row.text = row:CreateFontString(nil, "OVERLAY")
    if RefineUI.Font then
        RefineUI.Font(row.text, 12, (Media and Media.Fonts and Media.Fonts.Default), "OUTLINE")
    else
        row.text:SetFont((Media and Media.Fonts and Media.Fonts.Default) or _G.STANDARD_TEXT_FONT, 12, "OUTLINE")
    end
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
    row.text:SetJustifyH("LEFT")

    row.pinButton = CreateFrame("Button", nil, row)
    row.pinButton:SetSize(PIN_ICON_SIZE, PIN_ICON_SIZE)
    row.pinButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.pinButton:SetFrameStrata(row:GetFrameStrata())
    row.pinButton:SetFrameLevel(row:GetFrameLevel() + 4)
    row.pinButton:RegisterForClicks("LeftButtonUp")
    if row.pinButton.SetPropagateMouseClicks then
        row.pinButton:SetPropagateMouseClicks(false)
    end
    row.pinButton:SetScript("OnEnter", OnPinButtonEnter)
    row.pinButton:SetScript("OnLeave", OnPinButtonLeave)
    row.pinButton:SetScript("OnClick", OnPinButtonClick)
    row.pinButton:Hide()

    row.pinIcon = row.pinButton:CreateTexture(nil, "ARTWORK")
    row.pinIcon:SetAllPoints(row.pinButton)
    if row.pinIcon.SetAtlas then
        row.pinIcon:SetAtlas(ATLAS_PIN_ICON, true)
    else
        row.pinIcon:SetTexture(ICON_QUESTION_MARK)
        row.pinIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
    row.pinIcon:SetVertexColor(PIN_UNPINNED_R, PIN_UNPINNED_G, PIN_UNPINNED_B, PIN_UNPINNED_A)

    row.headerSeparator = row:CreateTexture(nil, "ARTWORK")
    row.headerSeparator:SetHeight(1)
    row.headerSeparator:SetColorTexture(0.55, 0.55, 0.55, 0.7)
    row.headerSeparator:Hide()

    row.arrow = row:CreateTexture(nil, "OVERLAY")
    row.arrow:SetTexture("interface/moneyframe/arrow-left-up")
    row.arrow:SetSize(14, 14)
    row.arrow:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.arrow:Hide()

    return row
end

local function EnsureRootRows(count)
    for i = #rootRows + 1, count do
        rootRows[i] = CreateMenuRow(portalsMenu, false)
    end
end

local function EnsureSubmenuRows(count)
    for i = #submenuRows + 1, count do
        submenuRows[i] = CreateMenuRow(portalsSubmenu, true)
    end
end

----------------------------------------------------------------------------------------
-- Menu Rendering
----------------------------------------------------------------------------------------
local function UpdatePortalsButtonIcon()
    if not portalsButtonIcon then
        return
    end

    local atlasInfo = C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(ATLAS_PORTAL_BUTTON)
    if atlasInfo and portalsButtonIcon.SetAtlas then
        portalsButtonIcon:SetAtlas(ATLAS_PORTAL_BUTTON, true)
        return
    end

    local _, fallbackIcon = GetSpellInfoSafe(FALLBACK_BUTTON_SPELL_ID)
    portalsButtonIcon:SetTexture(fallbackIcon or ICON_QUESTION_MARK)
    portalsButtonIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
end

local function ShouldShowPortalsButton()
    if not portalsButton then
        return false
    end

    if portalsButton:IsMouseOver() then
        return true
    end

    if Minimap and Minimap:IsMouseOver() then
        return true
    end

    return false
end

local function UpdatePortalsButtonVisibility(force)
    if not portalsButton then
        return
    end
    if InCombatLockdown() then
        return
    end

    local shouldShow = ShouldShowPortalsButton()
    if shouldShow then
        if not portalsButton:IsShown() then
            portalsButton:Show()
        end
        portalsButton:EnableMouse(true)
        if force or portalsButton:GetAlpha() < 1 then
            portalsButton:SetAlpha(1)
        end
    else
        portalsButton:EnableMouse(false)
        if force or portalsButton:GetAlpha() > 0 then
            portalsButton:SetAlpha(0)
        end
    end
end

local function EnsurePortalsButtonVisibilityUpdateJob()
    if not RefineUI.RegisterUpdateJob then
        return
    end

    if RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(UPDATE_JOB_KEY.BUTTON_VISIBILITY) then
        if RefineUI.SetUpdateJobEnabled then
            RefineUI:SetUpdateJobEnabled(UPDATE_JOB_KEY.BUTTON_VISIBILITY, true, true)
        end
        if RefineUI.RunUpdateJobNow then
            RefineUI:RunUpdateJobNow(UPDATE_JOB_KEY.BUTTON_VISIBILITY)
        end
        return
    end

    RefineUI:RegisterUpdateJob(UPDATE_JOB_KEY.BUTTON_VISIBILITY, 0.08, function()
        UpdatePortalsButtonVisibility(false)
    end, {
        enabled = true,
    })

    if RefineUI.RunUpdateJobNow then
        RefineUI:RunUpdateJobNow(UPDATE_JOB_KEY.BUTTON_VISIBILITY)
    end
end

local function UpdatePortalsButtonLayout()
    if not portalsButton then
        return
    end

    local cfg = GetPortalsConfig()

    portalsButton:ClearAllPoints()
    RefineUI.Point(portalsButton, "BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", cfg.ButtonOffsetX, cfg.ButtonOffsetY)
    RefineUI.Size(portalsButton, cfg.ButtonSize, cfg.ButtonSize)
    portalsButton:SetFrameLevel((Minimap and Minimap:GetFrameLevel() or 1) + 30)
    if portalsButtonIcon then
        portalsButtonIcon:ClearAllPoints()
        portalsButtonIcon:SetPoint("TOPLEFT", portalsButton, "TOPLEFT", BUTTON_ICON_INSET, -BUTTON_ICON_INSET)
        portalsButtonIcon:SetPoint("BOTTOMRIGHT", portalsButton, "BOTTOMRIGHT", -BUTTON_ICON_INSET, BUTTON_ICON_INSET)
    end
end

local function RefreshVisibleCooldowns()
    if not portalsMenu then
        return
    end

    if not portalsMenu:IsShown() and (not portalsSubmenu or not portalsSubmenu:IsShown()) then
        return
    end

    for i = 1, #rootRows do
        local row = rootRows[i]
        if row and row:IsShown() then
            UpdateRowCooldown(row)
        end
    end

    for i = 1, #submenuRows do
        local row = submenuRows[i]
        if row and row:IsShown() then
            UpdateRowCooldown(row)
        end
    end
end

local function UpdateSubmenuScrollIndicators(totalEntries, visibleRows)
    if not submenuScrollUpIndicator or not submenuScrollDownIndicator then
        return
    end

    local maxOffset = max(0, totalEntries - visibleRows)
    submenuScrollUpIndicator:SetShown(totalEntries > visibleRows and submenuScrollOffset > 0)
    submenuScrollDownIndicator:SetShown(totalEntries > visibleRows and submenuScrollOffset < maxOffset)
end

local function RefreshSubmenuRows()
    if not portalsSubmenu then
        return
    end

    local cfg = GetPortalsConfig()
    local entries = submenuEntriesByCategory[activeSubmenuCategory]
    if type(entries) ~= "table" or #entries == 0 then
        portalsSubmenu:Hide()
        return
    end

    local totalEntries = #entries
    local visibleRows = min(totalEntries, cfg.MaxVisibleRows)
    local maxOffset = max(0, totalEntries - visibleRows)
    if submenuScrollOffset > maxOffset then
        submenuScrollOffset = maxOffset
    end

    EnsureSubmenuRows(cfg.MaxVisibleRows)

    local rowWidth = cfg.MenuWidth - (MENU_PADDING_X * 2)
    for i = 1, #submenuRows do
        local row = submenuRows[i]
        local entryIndex = submenuScrollOffset + i
        local entry = entries[entryIndex]

        if i <= visibleRows and entry then
            row:Show()
            row:ClearAllPoints()
            RefineUI.Point(row, "TOPLEFT", portalsSubmenu, "TOPLEFT", MENU_PADDING_X, -MENU_PADDING_Y - ((i - 1) * cfg.RowHeight))
            RefineUI.Size(row, rowWidth, cfg.RowHeight)
            ApplyEntryToRow(row, entry)
        else
            row:Hide()
            local state = RowState[row]
            if state then
                state.entry = nil
            end
            if not InCombatLockdown() then
                ClearActionAttributes(row)
            end
        end
    end

    RefineUI.Size(portalsSubmenu, cfg.MenuWidth, (MENU_PADDING_Y * 2) + (visibleRows * cfg.RowHeight))
    UpdateSubmenuScrollIndicators(totalEntries, visibleRows)
end

local function RefreshRootRows()
    if not portalsMenu then
        return
    end

    local cfg = GetPortalsConfig()
    local rowCount = #rootEntries

    EnsureRootRows(rowCount)

    local rowWidth = cfg.MenuWidth - (MENU_PADDING_X * 2)
    for i = 1, #rootRows do
        local row = rootRows[i]
        local entry = rootEntries[i]

        if entry then
            row:Show()
            row:ClearAllPoints()
            RefineUI.Point(row, "TOPLEFT", portalsMenu, "TOPLEFT", MENU_PADDING_X, -MENU_PADDING_Y - ((i - 1) * cfg.RowHeight))
            RefineUI.Size(row, rowWidth, cfg.RowHeight)
            ApplyEntryToRow(row, entry)
        else
            row:Hide()
            local state = RowState[row]
            if state then
                state.entry = nil
            end
            if not InCombatLockdown() then
                ClearActionAttributes(row)
            end
        end
    end

    RefineUI.Size(portalsMenu, cfg.MenuWidth, max((MENU_PADDING_Y * 2) + (cfg.RowHeight * max(rowCount, 1)), cfg.RowHeight + (MENU_PADDING_Y * 2)))
end

local function PositionRootMenu()
    if not portalsMenu or not portalsButton then
        return
    end

    portalsMenu:ClearAllPoints()
    RefineUI.Point(portalsMenu, "BOTTOMRIGHT", portalsButton, "TOPLEFT", -6, 4)
end

local function PositionSubmenu(anchorRow)
    if not portalsSubmenu or not portalsMenu then
        return
    end

    local cfg = GetPortalsConfig()
    local screenWidth = UIParent:GetRight() or _G.GetScreenWidth()
    local menuRight = portalsMenu:GetRight() or 0

    portalsSubmenu:ClearAllPoints()
    if (menuRight + cfg.MenuWidth + 12) < screenWidth then
        RefineUI.Point(portalsSubmenu, "TOPLEFT", anchorRow or portalsMenu, "TOPRIGHT", 8, 0)
    else
        RefineUI.Point(portalsSubmenu, "TOPRIGHT", anchorRow or portalsMenu, "TOPLEFT", -8, 0)
    end
end

ClosePortalsMenus = function()
    if InCombatLockdown() then
        return
    end

    if portalsSubmenu then
        portalsSubmenu:Hide()
    end
    if portalsMenu then
        portalsMenu:Hide()
    end
    if clickCatcher then
        clickCatcher:Hide()
    end
    HidePortalTooltipIfOwned()
    UpdatePortalsButtonVisibility(true)
end

OpenSubmenu = function(categoryKey, anchorRow)
    if InCombatLockdown() then
        return
    end

    local entries = submenuEntriesByCategory[categoryKey]
    if type(entries) ~= "table" or #entries == 0 then
        if portalsSubmenu then
            portalsSubmenu:Hide()
        end
        return
    end

    activeSubmenuCategory = categoryKey
    submenuScrollOffset = 0
    RefreshSubmenuRows()
    PositionSubmenu(anchorRow)
    portalsSubmenu:Show()
    if clickCatcher then
        clickCatcher:Show()
    end
    RefreshVisibleCooldowns()
end
local function ToggleRootMenu()
    if InCombatLockdown() then
        return
    end
    if not portalsMenu or not clickCatcher then
        return
    end

    if portalsMenu:IsShown() then
        ClosePortalsMenus()
        return
    end

    if #rootEntries == 0 then
        RequestFullRefresh(true)
    end
    if #rootEntries == 0 then
        return
    end

    PositionRootMenu()
    clickCatcher:Show()
    portalsMenu:Show()
    if portalsSubmenu then
        portalsSubmenu:Hide()
    end
    RefreshVisibleCooldowns()
    UpdatePortalsButtonVisibility(true)
end

local function OnSubmenuMouseWheel(_, delta)
    if InCombatLockdown() then
        return
    end

    local cfg = GetPortalsConfig()
    local entries = submenuEntriesByCategory[activeSubmenuCategory]
    if type(entries) ~= "table" then
        return
    end

    local totalEntries = #entries
    local visibleRows = min(totalEntries, cfg.MaxVisibleRows)
    if totalEntries <= visibleRows then
        return
    end

    local maxOffset = max(0, totalEntries - visibleRows)
    if delta > 0 then
        submenuScrollOffset = max(0, submenuScrollOffset - 1)
    else
        submenuScrollOffset = min(maxOffset, submenuScrollOffset + 1)
    end
    RefreshSubmenuRows()
end

local function CreatePortalsButton()
    if portalsButton then
        return
    end

    local cfg = GetPortalsConfig()
    portalsButton = CreateFrame("Button", PORTALS_BUTTON_NAME, Minimap)
    portalsButton:SetFrameStrata(Minimap:GetFrameStrata())
    portalsButton:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 30)
    portalsButton:RegisterForClicks("LeftButtonUp")

    RefineUI.Size(portalsButton, cfg.ButtonSize, cfg.ButtonSize)
    RefineUI.Point(portalsButton, "BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", cfg.ButtonOffsetX, cfg.ButtonOffsetY)
    RefineUI.SetTemplate(portalsButton, "Default")

    portalsButtonIcon = portalsButton:CreateTexture(nil, "ARTWORK")
    portalsButtonIcon:SetPoint("TOPLEFT", portalsButton, "TOPLEFT", BUTTON_ICON_INSET, -BUTTON_ICON_INSET)
    portalsButtonIcon:SetPoint("BOTTOMRIGHT", portalsButton, "BOTTOMRIGHT", -BUTTON_ICON_INSET, BUTTON_ICON_INSET)

    UpdatePortalsButtonIcon()

    portalsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Portals", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
        SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 1)
    end)

    portalsButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        local r, g, b, a = GetDefaultBorderColor()
        SetBorderColor(self, r, g, b, a)
        UpdatePortalsButtonVisibility(false)
    end)

    portalsButton:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ToggleRootMenu()
        end
    end)

    portalsButton:Show()
    UpdatePortalsButtonLayout()
    EnsurePortalsButtonVisibilityUpdateJob()
    UpdatePortalsButtonVisibility(true)
end

local function CreateMenus()
    if portalsMenu and portalsSubmenu and clickCatcher then
        return
    end

    local cfg = GetPortalsConfig()

    clickCatcher = CreateFrame("Frame", PORTALS_CLICK_CATCHER_NAME, UIParent)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:SetFrameStrata("DIALOG")
    clickCatcher:SetFrameLevel(5)
    clickCatcher:EnableMouse(true)
    clickCatcher:Hide()
    clickCatcher:SetScript("OnMouseUp", function()
        if (portalsMenu and portalsMenu:IsShown() and portalsMenu:IsMouseOver()) or (portalsSubmenu and portalsSubmenu:IsShown() and portalsSubmenu:IsMouseOver()) then
            return
        end
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if (portalsMenu and portalsMenu:IsShown() and portalsMenu:IsMouseOver()) or (portalsSubmenu and portalsSubmenu:IsShown() and portalsSubmenu:IsMouseOver()) then
                    return
                end
                ClosePortalsMenus()
            end)
            return
        end
        ClosePortalsMenus()
    end)

    portalsMenu = CreateFrame("Frame", PORTALS_MENU_NAME, UIParent, "BackdropTemplate")
    portalsMenu:SetFrameStrata("TOOLTIP")
    portalsMenu:SetFrameLevel(50)
    portalsMenu:SetClampedToScreen(true)
    portalsMenu:EnableMouse(true)
    RefineUI.Size(portalsMenu, cfg.MenuWidth, cfg.RowHeight + (MENU_PADDING_Y * 2))
    RefineUI.SetTemplate(portalsMenu, "Transparent")
    RefineUI.CreateBorder(portalsMenu, 6, 6, 12)
    portalsMenu:Hide()
    portalsMenu:SetScript("OnHide", function()
        if portalsSubmenu then
            portalsSubmenu:Hide()
        end
        if clickCatcher then
            clickCatcher:Hide()
        end
        UpdatePortalsButtonVisibility(true)
    end)

    portalsSubmenu = CreateFrame("Frame", PORTALS_SUBMENU_NAME, UIParent, "BackdropTemplate")
    portalsSubmenu:SetFrameStrata("TOOLTIP")
    portalsSubmenu:SetFrameLevel(60)
    portalsSubmenu:SetClampedToScreen(true)
    portalsSubmenu:EnableMouse(true)
    portalsSubmenu:EnableMouseWheel(true)
    RefineUI.Size(portalsSubmenu, cfg.MenuWidth, cfg.RowHeight + (MENU_PADDING_Y * 2))
    RefineUI.SetTemplate(portalsSubmenu, "Transparent")
    RefineUI.CreateBorder(portalsSubmenu, 6, 6, 12)
    portalsSubmenu:Hide()
    portalsSubmenu:SetScript("OnMouseWheel", OnSubmenuMouseWheel)

    submenuScrollUpIndicator = portalsSubmenu:CreateFontString(nil, "OVERLAY")
    if RefineUI.Font then
        RefineUI.Font(submenuScrollUpIndicator, 11, (Media and Media.Fonts and Media.Fonts.Default), "OUTLINE")
    else
        submenuScrollUpIndicator:SetFont((Media and Media.Fonts and Media.Fonts.Default) or _G.STANDARD_TEXT_FONT, 11, "OUTLINE")
    end
    submenuScrollUpIndicator:SetPoint("TOPRIGHT", portalsSubmenu, "TOPRIGHT", -8, -4)
    submenuScrollUpIndicator:SetText("▲")
    submenuScrollUpIndicator:Hide()

    submenuScrollDownIndicator = portalsSubmenu:CreateFontString(nil, "OVERLAY")
    if RefineUI.Font then
        RefineUI.Font(submenuScrollDownIndicator, 11, (Media and Media.Fonts and Media.Fonts.Default), "OUTLINE")
    else
        submenuScrollDownIndicator:SetFont((Media and Media.Fonts and Media.Fonts.Default) or _G.STANDARD_TEXT_FONT, 11, "OUTLINE")
    end
    submenuScrollDownIndicator:SetPoint("BOTTOMRIGHT", portalsSubmenu, "BOTTOMRIGHT", -8, 4)
    submenuScrollDownIndicator:SetText("▼")
    submenuScrollDownIndicator:Hide()

    AddToUISpecialFrames(PORTALS_MENU_NAME)
    AddToUISpecialFrames(PORTALS_SUBMENU_NAME)
end

----------------------------------------------------------------------------------------
-- Refresh Pipeline
----------------------------------------------------------------------------------------
local function RebuildPortalEntries()
    if InCombatLockdown() then
        pendingFullRefresh = true
        return
    end

    pendingFullRefresh = false
    UpdatePortalsButtonLayout()

    local newRootEntries, newSubmenuEntriesByCategory = BuildRootAndSubmenuEntries()
    rootEntries = newRootEntries
    submenuEntriesByCategory = newSubmenuEntriesByCategory

    RefreshRootRows()

    if activeSubmenuCategory and submenuEntriesByCategory[activeSubmenuCategory] then
        RefreshSubmenuRows()
    else
        activeSubmenuCategory = nil
        if portalsSubmenu then
            portalsSubmenu:Hide()
        end
    end

    if portalsMenu and portalsMenu:IsShown() and #rootEntries == 0 then
        ClosePortalsMenus()
    end
end

RequestFullRefresh = function(immediate)
    if InCombatLockdown() then
        pendingFullRefresh = true
        return
    end

    if immediate then
        RebuildPortalEntries()
        return
    end

    RefineUI:Debounce(TIMER_KEY.FULL_REFRESH, 0.12, RebuildPortalEntries)
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
local function RegisterPortalsEvents()
    if portalsEventsRegistered then
        return
    end

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        RequestFullRefresh()
    end, EVENT_KEY.PLAYER_ENTERING_WORLD)

    RefineUI:RegisterEventCallback("SPELLS_CHANGED", function()
        RequestFullRefresh()
    end, EVENT_KEY.SPELLS_CHANGED)

    RefineUI:RegisterEventCallback("PLAYER_TALENT_UPDATE", function()
        RequestFullRefresh()
    end, EVENT_KEY.PLAYER_TALENT_UPDATE)

    RefineUI:RegisterEventCallback("PLAYER_SPECIALIZATION_CHANGED", function(_, unitTarget)
        if unitTarget == "player" then
            RequestFullRefresh()
        end
    end, EVENT_KEY.PLAYER_SPECIALIZATION_CHANGED)

    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function()
        RequestFullRefresh()
    end, EVENT_KEY.BAG_UPDATE_DELAYED)

    RefineUI:RegisterEventCallback("NEW_TOY_ADDED", function()
        RequestFullRefresh()
    end, EVENT_KEY.NEW_TOY_ADDED)

    RefineUI:RegisterEventCallback("TOYS_UPDATED", function()
        RequestFullRefresh()
    end, EVENT_KEY.TOYS_UPDATED)

    RefineUI:RegisterEventCallback("SPELL_UPDATE_COOLDOWN", function()
        RefreshVisibleCooldowns()
    end, EVENT_KEY.SPELL_UPDATE_COOLDOWN)

    RefineUI:RegisterEventCallback("BAG_UPDATE_COOLDOWN", function()
        RefreshVisibleCooldowns()
    end, EVENT_KEY.BAG_UPDATE_COOLDOWN)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if pendingFullRefresh then
            RequestFullRefresh(true)
        else
            RefreshVisibleCooldowns()
        end
    end, EVENT_KEY.PLAYER_REGEN_ENABLED)

    RefineUI:RegisterEventCallback("PLAYER_STARTED_MOVING", function()
        local cfg = GetPortalsConfig()
        if cfg.CloseOnMove then
            ClosePortalsMenus()
        end
    end, EVENT_KEY.PLAYER_STARTED_MOVING)

    RefineUI:RegisterEventCallback("UNIT_SPELLCAST_START", function(_, unitTarget)
        local cfg = GetPortalsConfig()
        if cfg.CloseOnCastStart and unitTarget == "player" then
            ClosePortalsMenus()
        end
    end, EVENT_KEY.UNIT_SPELLCAST_START)

    portalsEventsRegistered = true
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Maps:SetupPortals()
    MigratePortalsConfigDefaults()

    local cfg = GetPortalsConfig()
    if not cfg.Enable then
        return
    end

    CreatePortalsButton()
    CreateMenus()
    RegisterPortalsEvents()

    if portalsInitialized then
        RequestFullRefresh()
        return
    end

    portalsInitialized = true
    RequestFullRefresh(true)
end
