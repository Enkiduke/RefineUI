local R, C, L = unpack(RefineUI)

-- Helper function to create sections
local function CreateSection(name)
    C[name] = C[name] or {}
    return setmetatable({}, {
        __newindex = function(t, k, v)
            rawset(C[name], k, v)
        end
    })
end

----------------------------------------------------------------------------------------
--	Position options
--	BACKUP THIS FILE BEFORE UPDATING!
----------------------------------------------------------------------------------------
local position = CreateSection("position")

-- ActionBar positions
position.mainBar = {"BOTTOM", UIParent, "BOTTOM", 0, 50}
position.multiBarBottomLeft = {"BOTTOM", MainMenuBar, "TOP", 0, 4}
position.multiBarBottomRight = {"BOTTOM", MultiBarBottomLeft, "TOP", 0, 4}
position.multiBarRight = {"RIGHT", UIParent, "RIGHT", -10, 0}
position.multiBarLeft = {"RIGHT", MultiBarRight, "LEFT", -4, 0}
position.multiBar5 = {"RIGHT", UIParent, "RIGHT", -75, 0}
position.multiBar6 = {"LEFT", UIParent, "LEFT", 5, 0}
position.multiBar7 = {"LEFT", UIParent, "LEFT", 5, 0}
position.petBar = {"BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 5}
position.stanceBar = {"BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 5}
position.vehicleBar = {"BOTTOMRIGHT", ActionButton1, "BOTTOMLEFT", -3, 0}
position.extraButton = {"BOTTOM", UIParent, "BOTTOM", 0, 150}
position.zoneButton = {"BOTTOM", UIParent, "BOTTOM", 0, 150}
position.microMenu = {"BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0}

-- UnitFrame positions
position.unitframes = {
    player = {"BOTTOM", UIParent, "BOTTOM", 0, 320},
    classResources = {"BOTTOM", "RefineUI_Player", "TOP", 0, 9},
    target = {"BOTTOM", UIParent, "BOTTOM", 400, 320},
    targetTarget = {"TOPRIGHT", "RefineUI_Target", "BOTTOMRIGHT", 0, -11},
    pet = {"LEFT", "RefineUI_Player", "RIGHT", 6, 0},
    focus = {"BOTTOM", UIParent, "BOTTOM", -400, 320},
    focusTarget = {"TOPLEFT", "RefineUI_Target", "BOTTOMLEFT", 0, -11},
    party = {"CENTER", UIParent, "CENTER", -550, 2},
    raid = {"CENTER", UIParent, "CENTER", -550, 0},
    arena = {"CENTER", UIParent, "CENTER", 800, 0},
    boss = {"CENTER", UIParent, "CENTER", 800, 0},
    tank = {"BOTTOMLEFT", "MainActionBarAnchor", "BOTTOMRIGHT", 10, 18},
    experienceBar = {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10},
    playerPortrait = {"TOPRIGHT", "RefineUI_Player", "TOPLEFT", -12, 27},
    targetPortrait = {"TOPLEFT", "RefineUI_Target", "TOPRIGHT", 12, 27},
    playerCastbar = {"TOP", "RefineUI_Player", "BOTTOM", 0, -7},
    targetCastbar = {"TOP", "RefineUI_Target", "BOTTOM", 0, -7},
    focusCastbar = {"TOP", "RefineUI_Focus", "BOTTOM", 0, -9},
}

-- Filger positions
position.filger = {
    left_buff = {"CENTER", UIParent, "CENTER", -256, 0},             -- "LEFT_BUFF"
    right_buff = {"CENTER", UIParent, "CENTER", 256, 0},              -- "RIGHT_BUFF"
    bottom_buff = {"CENTER", UIParent, "CENTER", 0, -256},            -- "BOTTOM_BUFF"
}

-- Miscellaneous positions
position.minimap = {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 50}
position.minimapButtons = {"BOTTOMLEFT", Minimap, "TOPLEFT", -2, 8}
position.tooltip = {"BOTTOMRIGHT", Minimap, "TOPRIGHT", 2, 5}
position.details = {"BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -310, 40}
position.vehicle = {"BOTTOMRIGHT", MainMenuBar, "BOTTOMLEFT", -1, 0}
position.ghost = {"BOTTOM", Minimap, "TOP", 0, 5}
position.bag = {"BOTTOMRIGHT", Minimap, "TOPRIGHT", 2, 5}
position.bank = {"LEFT", UIParent, "LEFT", 23, 150}
position.archaeology = {"BOTTOMRIGHT", Minimap, "TOPRIGHT", 2, 5}
position.autoButton = {"BOTTOMLEFT", Minimap, "TOPLEFT", -2, 27}
position.autoitembar = {"BOTTOM", ChatFrame1, "TOP", 0, 4}
position.chat = {"BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 50}
position.bnPopup = {"BOTTOMLEFT", ChatFrame1, "TOPLEFT", -3, 27}
position.bwtimeline = {"CENTER", UIParent, "CENTER", -425, 0}
position.objectiveTracker = {"TOPLEFT", UIParent, "TOPLEFT", 10, -10}
position.loot = {"TOPLEFT", UIParent, "TOPLEFT", 245, -220}
position.groupLoot = {"TOP", "UIParent", "TOP", 0, -50}
position.threatMeter = {"BOTTOMLEFT", "MainActionBarAnchor", "BOTTOMRIGHT", 7, 16}
position.bgScore = {"BOTTOMLEFT", ActionButton12, "BOTTOMRIGHT", 10, -2}
position.raidCooldown = {"TOPLEFT", ChatFrame1, "TOPRIGHT", 7, 1}
position.enemyCooldown = {"BOTTOMLEFT", "RefineUI_Player", "TOPRIGHT", 33, 62}
position.pulseCooldown = {"CENTER", UIParent, "CENTER", 0, 0}
position.playerBuffs = {"TOPRIGHT", UIParent, "TOPRIGHT", -3, -3}
position.selfBuffs = {"CENTER", UIParent, "CENTER", 0, 0}
position.raidBuffs = {"TOPLEFT", Minimap, "BOTTOMLEFT", 0, -10}
position.raidUtility = {"TOP", UIParent, "TOP", 0, 0}
position.topPanel = {"TOP", UIParent, "TOP", 0, -21}
position.achievement = {"TOP", UIParent, "TOP", 0, -21}
position.uierror = {"TOP", UIParent, "TOP", 0, -30}
position.talkingHead = {"TOP", UIParent, "TOP", 0, -21}
position.altPowerBar = {"TOP", UIWidgetTopCenterContainerFrame, "BOTTOM", 0, -7}
position.uiwidgetTop = {"TOP", UIParent, "TOP", 1, -21}
position.uiwidgetBelow = {"TOP", UIWidgetTopCenterContainerFrame, "BOTTOM", 0, -15}
position.compactRaid = {"LEFT", UIParent, "LEFT", 0, 0}

-- Mirror timer Y-offsets
position.mirrorTimers = {
    BREATH = -96,
    EXHAUSTION = -116,
    FEIGNDEATH = -142,
}