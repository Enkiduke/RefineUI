----------------------------------------------------------------------------------------
-- RefineUI Positions
-- Description: Default anchor points for UI elements.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Positions
----------------------------------------------------------------------------------------
-- Format: FrameName = { Point, RelativeTo, RelativePoint, X, Y }
-- Note: RelativeTo should be a STRING to prevent load-order issues (nil globals).
RefineUI.Positions = {
    -- ActionBars
    ["MainActionBar"]       = { "BOTTOM", "UIParent", "BOTTOM", 0, 200 },
    ["MultiBarBottomLeft"]  = { "BOTTOM", "UIParent", "BOTTOM", 0, 250 }, -- Absolute to avoid MainMenuBar nil issues
    ["MultiBarBottomRight"] = { "BOTTOM", "UIParent", "BOTTOM", -170, 6 }, -- Action Bar 3 (left side, center gap)
    ["MultiBarRight"]       = { "BOTTOM", "UIParent", "BOTTOM", 170, 6 }, -- Action Bar 4 (bottom center)
    ["MultiBarLeft"]        = { "BOTTOM", "UIParent", "BOTTOM", 0, 6 }, -- Action Bar 5 (right side, center gap)
    ["MultiBar5"]           = { "RIGHT", "UIParent", "RIGHT", -75, 0 },
    ["MultiBar6"]           = { "LEFT", "UIParent", "LEFT", 5, 0 },
    ["MultiBar7"]           = { "LEFT", "UIParent", "LEFT", 5, 0 },
    ["PetActionBar"]        = { "BOTTOMRIGHT", "ChatFrame1", "TOPRIGHT", 0, 5 },
    ["StanceBar"]           = { "BOTTOMRIGHT", "ChatFrame1", "TOPRIGHT", 0, 5 },
    ["OverrideActionBar"]   = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["ExtraActionBarFrame"] = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["ZoneAbilityFrame"]    = { "BOTTOM", "UIParent", "BOTTOM", 0, 50 },
    ["MicroMenuContainer"]  = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 5, 5 },
    
    -- UnitFrames
    ["PlayerFrame"]         = { "BOTTOM", "UIParent", "BOTTOM", -45, 320 },
    ["PlayerFrameAlternateManaBar"] = { "BOTTOM", "PlayerFrame", "TOP", 0, 9 },
    ["TargetFrame"]         = { "BOTTOM", "UIParent", "BOTTOM", 432, 320 },
    ["TargetFrameToT"]      = { "TOPRIGHT", "TargetFrame", "BOTTOMRIGHT", 0, -11 },
    ["PetFrame"]            = { "LEFT", "PlayerFrame", "RIGHT", 6, 0 },
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
    ["RefineUI_StaggerBar"]       = { "BOTTOM", nil, "TOP", 0, 20 },
    ["RefineUI_TotemBar"]         = { "BOTTOM", nil, "TOP", 0, 20 },
    
    -- CastBars
    ["PlayerCastingBarFrame"]       = { "TOP", "PlayerFrame", "BOTTOM", 60, 30 },

    -- Minimap
    ["MinimapCluster"]      = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -10, 50 },
    ["RefineUI_MinimapButtonCollect"] = { "TOPRIGHT", "Minimap", "TOPRIGHT", 0, 0 },
    ["RefineUI_ExperienceBar"]       = { "TOP", "Minimap", "BOTTOM", 0, -10 },
    ["DamageMeter"]                  = { "RIGHT", "Minimap", "LEFT", 10, 0 }, -- EditMode system frame anchor
    ["DamageMeterSessionWindow1"]    = { "RIGHT", "Minimap", "LEFT", 10, 0 },    
    -- Chat
    ["ChatFrame1"]          = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 10, 50 },
    ["QuickJoinToastButton"] = { "BOTTOMLEFT", "ChatFrame1", "TOPLEFT", -3, 27 }, 
    ["BNToastFrame"]        = { "BOTTOMLEFT", "ChatFrame1", "TOPLEFT", -3, 27 },
    ["RefineUI_ToastAnchor"] = { "TOP", "UIParent", "TOP", 0, -120 },

    -- Automation / Custom
    ["RefineUI_AutoItemBarMover"] = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 0, 6 },
    ["RefineUI_AutoButton"]  = { "BOTTOMLEFT", "Minimap", "TOPLEFT", -2, 27 },
    ["RefineUI_GhostFrame"]  = { "BOTTOM", "Minimap", "TOP", 0, 5 },
    
    -- Loot
    ["GroupLootContainer"]   = { "TOP", "UIParent", "TOP", 0, -50 },
    ["LootFrame"]            = { "TOPLEFT", "UIParent", "TOPLEFT", 245, -220 },
    
    -- Buffs
    ["BuffFrame"]            = { "TOPRIGHT", "UIParent", "TOPRIGHT", -3, -3 },
    ["DebuffFrame"]          = { "TOPRIGHT", "UIParent", "TOPRIGHT", -3, -150 },
    ["RefineUI_BuffReminder"] = { "CENTER", "UIParent", "CENTER", 0, 0 },
    ["RefineUI_CDM_LeftTracker"] = { "CENTER", "UIParent", "CENTER", -256, 0 },
    ["RefineUI_CDM_RightTracker"] = { "CENTER", "UIParent", "CENTER", 256, 0 },
    ["RefineUI_CDM_BottomTracker"] = { "CENTER", "UIParent", "CENTER", 0, -256 },
    ["RefineUI_EncounterTimeline_BigIcon"] = { "CENTER", "UIParent", "CENTER", 0, -180 },
    
    -- Panels & Widgets
    ["ObjectiveTrackerFrame"] = { "TOPLEFT", "UIParent", "TOPLEFT", 15, -10 },
    ["UIErrorsFrame"]        = { "TOP", "UIParent", "TOP", 0, -30 },
    ["TalkingHeadFrame"]     = { "TOP", "UIParent", "TOP", 0, -21 },
    ["PlayerPowerBarAlt"]    = { "TOP", "UIWidgetTopCenterContainerFrame", "BOTTOM", 0, -7 },
    ["UIWidgetTopCenterContainerFrame"] = { "TOP", "UIParent", "TOP", 1, -21 },
    ["UIWidgetBelowMinimapContainerFrame"] = { "TOP", "UIWidgetTopCenterContainerFrame", "BOTTOM", 0, -15 },
    
    -- Raid Manager
    ["CompactRaidFrameManager"] = { "LEFT", "UIParent", "LEFT", 0, 0 },
    
    -- Misc
    ["BankFrame"]            = { "LEFT", "UIParent", "LEFT", 23, 150 },
    ["ContainerFrame1"]      = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 2, 5 },
    ["RefineUI_Bags"]         = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 0, 5 },
    ["ArcheologyDigsiteProgressBar"] = { "BOTTOMRIGHT", "Minimap", "TOPRIGHT", 2, 5 },
}
