----------------------------------------------------------------------------------------
-- RefineUI Configuration
-- Description: Main configuration file.
-- Note: You must Reload UI (/reload) after making changes to this file.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

-- Local config table (assigned to RefineUI.Config at the end)
-- Local config table (assigned to RefineUI.Config at the end)
local C = {}
C.Version = 1

----------------------------------------------------------------------------------------
-- 1. General Settings
----------------------------------------------------------------------------------------
C.General = {
    -- [ UI Scale ]
    -- Controls the overall size of the UI.
    -- Value between 0.64 (small) and 1.0 (large).
    UseUIScale = true,
    -- Scale = 0.71,

    -- [ Visual Style ]
    -- Border color for all frames (r, g, b)
    BorderColor = { 0.6, 0.6, 0.6 },
    
    -- Background color for frames/panels
    BackdropColor = { 0.1, 0.1, 0.1, 0.7 },
    
    -- Shadow/Glow color
    ShadowColor = { 0.05, 0.05, 0.05, 0.5 },

    -- [ Appearance ]
    Appearance = {
        Font = "RefineUI", -- Default LSM font name or path
        FontFlag = "OUTLINE",
        ShadowOffset = { 1, -1 },
        ShadowColor = { 0, 0, 0, 1 },
    },

    -- [ Cooldowns ]
    Cooldown = {
        ExpireColor  = { 1, 0, 0 },    -- < 3s (Red)
        SecondsColor = { 1, 1, 0 },    -- < 10s (Yellow)
        MinuteColor  = { 1, 1, 1 },    -- Standard (White)
    },

    -- [ Debug ]
    Debug = {
        Observability = false,
    },
}

----------------------------------------------------------------------------------------
-- 2. UnitFrames
----------------------------------------------------------------------------------------
C.UnitFrames = {
    Enable = true, -- Master switch for UnitFrames module
    DisableTooltips = true, -- Disable tooltips on UnitFrames
    Scale = 1.5, -- Default Scale for Player/Target/Focus frames
    
    -- [ Global Params ]
    Layout = {
        Width = 164,
        Height = 40,
        VerticalOffset = -20,
        BorderSize = 12,
        HitRectHeight = 68,
        BackgroundAlpha = 0.45,
    },
    
    Bars = {
        Spacing = 0,
        Padding = 3,
        HealthHeight = 26,
        ManaHeight = 6,
        HealthColor = { 0.1, 0.8, 0.1 },
        ManaColor = { 0.1, 0.4, 0.9 },
        UseClassColor = true,
        UseReactionColor = true,
        UsePowerColor = true,
    },
    
    Fonts = {
        HPSize = 16,
        ManaSize = 8,
        NameSize = 12,
        NameWidth = 180,
    },
    
    Icons = {
        EliteSize = 15,
        LeaderOffset = { -86, -24.5 },
        RaidTargetOffset = { -56, -42 },
        BossOffset = { -3.5, -1 },
    },

    Portraits = {
        Enable = true,
        Size = 48,
        InnerSize = 36,
        Offset = { 18, 0 }, -- Base offset
    },
    
    CastBars = {
        Height = 18,
        Width = 164, -- Matches Layout.Width usually
        Color = { 1, 0.7, 0 }, -- Goldish
        IconSize = 20,
        ShowTime = true,
        ShowIcon = true,
    },
    
    Auras = {
        Size = 18,      -- Default aura icon size
        LargeSize = 22, -- Size for player-cast/important auras
        Spacing = 0,    -- Space between icons
    },

    DataBars = {
        Width = 124,    -- Default width for all resource bars
        Height = 10,     -- Default height for bars (e.g. Class Power)
        HeightLarge = 14, -- Height for larger bars (e.g. Maelstrom, Stagger)
        Spacing = 2,    -- Spacing between pips/segments
        YOffset = 4,    -- Default vertical offset from the unit frame
        
        ClassPowerBar   = true,
        SecondaryPowerBar = true,
        RuneBar         = true,
        MaelstromBar    = true,
        StaggerBar      = true,
        SoulFragmentsBar = true,
        TotemBar        = true,
        
        ExperienceBar = {
            Enable = true,
            AutoTrack = "CLOSEST", -- "NONE", "RECENT", "CLOSEST"
            Position = { "TOP", "UIParent", "TOP", 0, -12 },
        },
    },
}

----------------------------------------------------------------------------------------
-- 3. ActionBars
----------------------------------------------------------------------------------------
C.ActionBars = {
    Enable = true,
    ButtonSize = 30,
    Spacing = 4,
    HotKey = false,  -- Show/abbreviate hotkey text on buttons
}

----------------------------------------------------------------------------------------
-- 4. Automation
----------------------------------------------------------------------------------------
C.Automation = {
    AutoRepair = true,
    GuildRepair = true,
    
    AutoButton = {
        Enable = true,
    },
    
    AutoItemBar = {
        Enable = true,
        ButtonSize = 36,
        ButtonSpacing = 6,
        ButtonLimit = 12,
        BarAlpha = 1,
        BarVisible = "MOUSEOVER", -- ALWAYS, IN_COMBAT, OUT_OF_COMBAT, MOUSEOVER, NEVER
        MinItemLevel = 1,
        Orientation = "HORIZONTAL", -- "HORIZONTAL" or "VERTICAL"
        ButtonDirection = "REVERSE", -- Orientation-aware label in Edit Mode
        ButtonWrap = "REVERSE", -- Orientation-aware label in Edit Mode
        ShowPotions = true,
        ShowFlasks = true,
        ShowFoodAndDrink = true,
        ShowItemEnhancements = true,
        ShowOtherConsumables = true,
        TrackedItems = {}, -- Added by drag/drop onto the bar
        HiddenItems = {}, -- Hidden via Ctrl+Right Click on bar items
        CategoryOrder = {}, -- Runtime-populated from fixed Auto Item Bar categories
        CategoryEnabled = {}, -- Runtime-populated enabled state per category key
        CategorySchemaVersion = 0, -- Auto-migrated by module when category list changes
    },
}

----------------------------------------------------------------------------------------
-- 4.5 ClickCasting
----------------------------------------------------------------------------------------
C.ClickCasting = {
    Enable = true,
    SchemaVersion = 1,
    TrackedEntries = {},
    SpecBindings = {},
    UI = {
        PanelShown = false,
    },
}

----------------------------------------------------------------------------------------
-- 5. RadBar
----------------------------------------------------------------------------------------
C.RadBar = {
    Enable = true,
    Rings = {
        Main = {
            Slices = {},
        },
    },
}

----------------------------------------------------------------------------------------
-- 6. AFK
----------------------------------------------------------------------------------------
C.AFK = {
    Enable = true,
}

----------------------------------------------------------------------------------------
-- 7. Chat
----------------------------------------------------------------------------------------
C.Chat = {
    Enable = true,
    Width = 600,
    Height = 300,
    TimeStamps = true,    -- Show timestamps in chat
    TabsMouseOver = true, -- Only show tabs on mouseover
    CombatLog = true,     -- Skin the Combat Log (Frame 2)
    History = true,       -- Enable Chat History
    ChatIcons = true,     -- Add icons to chat links
    RoleIcons = true,     -- Add class-colored role icons to party/raid chat messages
}

----------------------------------------------------------------------------------------
-- 8. Auras
----------------------------------------------------------------------------------------
C.Auras = {
    Enable = true,
    TimedBuffBorderEnabled = true,
    TimedBuffBorderColor = { 0.12, 0.9, 0.12 },
    SafeHidePassiveBuffs = false,
    ShowPassiveBuffsInEditMode = true,
    AllowDebuffTooltipsInCombat = false,
}

----------------------------------------------------------------------------------------
-- 9. BuffReminder
----------------------------------------------------------------------------------------
C.BuffReminder = {
    Enable = true,
    Size = 44,
    Spacing = 6,
    Flash = true,
    Sound = false,
    ClassColor = true,
    CategorySettings = {
        raid = { Enable = true, InstanceOnly = false, Expanded = true },
        targeted = { Enable = true, InstanceOnly = false, Expanded = true },
        self = { Enable = true, InstanceOnly = false, Expanded = true },
    },
    EntrySettings = {},
}

----------------------------------------------------------------------------------------
-- 9.5 CDM
----------------------------------------------------------------------------------------
C.CDM = {
    Enable = true,
    IconSize = 44,
    IconScale = 1,
    Spacing = 6,
    SkinCooldownViewer = true,
    SyncStrategy = "auto_safe", -- settings-flow CDM sync mode
    SourceScope = "buffs_exact", -- "buffs_exact" or "all_auras"
    PayloadGhostTTL = 0.20,
    BucketSettings = {
        Left = {
            IconScale = 1,
            Spacing = 6,
            Orientation = "HORIZONTAL",
            Direction = "LEFT",
        },
        Right = {
            IconScale = 1,
            Spacing = 6,
            Orientation = "HORIZONTAL",
            Direction = "RIGHT",
        },
        Bottom = {
            IconScale = 1,
            Spacing = 6,
            Orientation = "HORIZONTAL",
            Direction = "LEFT",
        },
    },
    HideNativeAuraViewers = true,
    AuraMode = "refineui", -- "refineui" or "blizzard"
    LayoutAssignments = {},
    VisualOverrides = {},
}

----------------------------------------------------------------------------------------
-- 9.6 Encounter Timeline
----------------------------------------------------------------------------------------
C.EncounterTimeline = {
    Enable = true,
    SkinEnabled = true,
    SkinTrackView = true,
    SkinTimerView = true,
    SkinBorderColorMode = "icon_classification", -- icon_classification, severity, event_color, default
    TrackTextAnchor = "LEFT", -- LEFT, RIGHT (track view text only)
    SkinUseEventColorBorder = true,
    SkinUseIconMaskStyles = true,
    SkinDispelBorderEnable = true,
    SkinDeadlyGlowEnable = true,
    RespectUserViewMode = true,

    BigIconEnable = true,
    BigIconSize = 72,
    BigIconThresholdSeconds = 5,
    BigIconSpacing = 6,
    BigIconOrientation = "HORIZONTAL", -- HORIZONTAL, VERTICAL
    BigIconGrowDirection = "RIGHT", -- Horizontal: RIGHT, LEFT, CENTERED. Vertical: UP, DOWN, CENTERED
    BigIconIconFallback = 134400,

    PullTimerEnable = true,
    PullTimerIconFileID = 134376,

    ReadyCheckEnable = true,
    ReadyCheckIconFileID = 134400,
    ReadyCheckFallbackDuration = 35,

    AudioCountdownEnable = true,
    AudioCountdownMode = "latest_wins",
    AudioCountdownChannel = "Master",
    AudioCountdownVoicePrefix = "EncounterCountdown",
    AudioCountdownSeverityLow = true,
    AudioCountdownSeverityMedium = true,
    AudioCountdownSeverityHigh = true,
    AudioCountdownRoleFilterEnabled = false,
    AudioCountdownIncludeRoleless = false,
    AudioCountdownSourceFilter = "all", -- all, encounter, script
    AudioCountdownUnknownSeverityPolicy = "exclude", -- exclude, include, as_medium
}

----------------------------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------------------------
C.Bags = {
    Enable = true,
    ShowItemLevel = true,
    ShowQualityBorder = true,
}

----------------------------------------------------------------------------------------
-- Skins
----------------------------------------------------------------------------------------
C.Skins = {
    Enable = true,
    CharacterPanel = {
        Enable = true,
        ShowCurrentMaxItemLevel = true,
        ShowSlotIndicators = true,
        ShowEnchantIndicators = true,
        ShowFilledGemIndicators = true,
        ShowEmptySocketIndicators = true,
        ShowNoSocketIndicators = true,
        ShowNoItemIndicators = true,
        ShowIndicatorText = false,
        ShowMissingIndicatorText = false,
        ShowHealthTotal = true,
        ShowManaTotal = true,
    },
}

----------------------------------------------------------------------------------------
-- 10. Tooltip
----------------------------------------------------------------------------------------
C.Tooltip = {
    Enable = true,
    HideInCombat = true,
}

----------------------------------------------------------------------------------------
-- 11. Maps
----------------------------------------------------------------------------------------
C.Maps = {
    Enable = true,
    Size = 294,
    ZoomReset = true,
    ResetTime = 5,
    WorldMap = true,
    WorldQuestList = {
        Enable = true,
        Sort = "TIME", -- "TIME" or "NAME"
        Collapsed = false,
    },
    ButtonCollect = true,
    AddonButtonSize = 32,
    AddonButtonSpacing = 6,
    AddonButtonOrientation = "VERTICAL", -- "HORIZONTAL" or "VERTICAL"
    AddonButtonGrowDirection = "FORWARD", -- Orientation-aware in Edit Mode
    Portals = {
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
    },
}

----------------------------------------------------------------------------------------
-- 12. Nameplates
----------------------------------------------------------------------------------------
C.Nameplates = {
    CastBar = {
        Height = 20,
        Width = 140, 
        IconSize = 20,
        Colors = {
            Interruptible = { 1, 0.7, 0 },    -- Gold
            NonInterruptible = { 1, 0.2, 0.2 }, -- Red (Shielded)
        },
    },
    
    -- Target
    TargetIndicator = true,
    ShowNPCTitles = true,
    ShowPetNames = false,
    UnitNameScale = 1,
    HealthTextScale = 1,
    DynamicPortraitScale = 1,
    TargetBorderColor = { .8, .8, .8 },
    Size = { 150, 20 }, -- Standard Nameplate Size
    
    -- Alpha
    Alpha = 0.8,         -- Minimum alpha for non-targets (reduces X-ray effect)
    NoTargetAlpha = 1.0, -- Alpha when nothing is targeted

    -- Threat (Health Bar)
    -- Uses Blizzard's nameplateThreatDisplay pipeline for state/events.
    -- RefineUI applies role-aware threat palette overrides on top.
    Threat = {
        Enable = true,
        InstanceOnly = false,

        -- Used by RefineUI hybrid threat coloring.
        SafeColor = { 0.2, 0.8, 0.2 },
        TransitionColor = { 1, 1, 0 },
        WarningColor = { 1, 0, 0 },

        -- Legacy fields retained for SavedVariables compatibility.
        OffTankColor = { 0, 0.5, 1 },
        OffTankScanThrottle = 0.5,
    },

    -- Crowd Control Bar
    CrowdControl = {
        Enable = true,             -- Master switch (can also toggle with /refine ccbar)
        HideWhileCasting = true,   -- Cast visuals take priority
        HideAuraIcons = true,      -- Hide Blizzard CC aura icons when CC bar is enabled
        Color = { 0.2, 0.6, 1.0 }, -- Fill color
        BorderColor = { 0.2, 0.6, 1.0 }, -- Portrait/CC border accent
    },
}

----------------------------------------------------------------------------------------
-- 13. Loot
----------------------------------------------------------------------------------------
C.Loot = {
    Enable = true, -- Master switch for Loot module
    
    -- [ Automation ]
    AutoConfirm = true, -- Auto confirm BoP/Rolls
    AutoSell = true,    -- Auto sell Low iLvl Gear
    FasterLoot = true,  -- Faster auto loot
    
    -- [ AutoSell Settings ]
    AutoSellIlvlThreshold = 0.70, -- < 1 = % of current ilvl, >= 1 = specific ilvl
    AutoSellOnlyEquipment = true,
    AutoSellIgnoreEquipmentSets = true,
    
    -- [ Filtering ]
    LootFilter = {
        Enable = true,
        MinQuality = 2,           -- Minimum quality to loot (0=Poor, 1=Common, 2=Uncommon...)
        GearMinQuality = 2,       -- Minimum quality for gear
        TradeskillMinQuality = 1, -- Minimum quality for trade goods
        GearPriceOverride = 500,  -- Always loot gear worth more than this (in gold)
        JunkMinPrice = 10,        -- Always loot junk worth more than this (in gold)
        GearUnknown = true,       -- Always loot uncollected appearances
        IgnoreOldExpansionTradeskill = false, -- Ignore tradeskill items from previous expansions
    },

    -- [ Advanced Rules ]
    AdvancedRules = {
        Rules = {}, -- Bootstrapped by LootRules module if empty
    },
}

----------------------------------------------------------------------------------------
-- 14. Combat
----------------------------------------------------------------------------------------
C.Combat = {
    CrosshairEnable = true, -- Enable Crosshair
    CrosshairSize = 24,
    CrosshairTexture = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Crosshair", 
    CrosshairOffsetX = 0,
    CrosshairOffsetY = -35,
    
    CursorEnable = true, -- Enable Combat Cursor (Circle under char)
    CursorSize = 50,
    CursorTexture = "Interface\\AddOns\\RefineUI\\Media\\Textures\\CursorCircle.blp", 
    
    StickyTargeting = true,      -- Prevent clicking on world to deselect target
    DisableRightClickInteraction = false, -- Disable right click interaction (Camera Only)
    AutoTargetOnClick = false,   -- Auto target mouseover on click (CAUTION)
}

----------------------------------------------------------------------------------------
-- 15. ErrorsFrame
----------------------------------------------------------------------------------------
C.ErrorsFrame = {
    Enable = true,
    TextColor = { 1, 0.1, 0.1 },
}

----------------------------------------------------------------------------------------
-- 16. FadeIn
----------------------------------------------------------------------------------------
C.FadeIn = {
    Enable = true,
}

----------------------------------------------------------------------------------------
-- 17. GameTime
----------------------------------------------------------------------------------------
C.GameTime = {
    Enable = true,
}

----------------------------------------------------------------------------------------
-- 18. TalkingHead
----------------------------------------------------------------------------------------
C.TalkingHead = {
    Enable = true,
    NoTalkingHead = true, -- Hide the Talking Head frame
    TalkingHeadToChat = false, -- Deprecated: chat redirect removed for taint safety
}

----------------------------------------------------------------------------------------
-- 19. Quests
----------------------------------------------------------------------------------------
C.Quests = {
    Enable = true,
    HeaderSkinning = false,

    AutoAccept = false,
    AutoComplete = false,
    AutoCollapseMode = "NEVER", -- "NEVER", "COMBAT", "INSTANCE", "RELOAD"
    AutoZoneTrack = true,
}

----------------------------------------------------------------------------------------
-- 20. Toasts
----------------------------------------------------------------------------------------
C.Toasts = {
    Enable = true,
    SkinBlizzard = true, -- Restyle Blizzard alert toasts after their setup functions run
    ShowCurrency = true, -- Add custom currency-delta toasts into AlertFrame pipeline
    ShowMoney = true, -- Add custom money-delta toasts into AlertFrame pipeline
    ShowNegative = true, -- Show spent/lost values in addition to gains
    MinimumCurrencyChange = 1, -- Absolute minimum change to show a currency toast
    MinimumMoneyChange = 1, -- Copper threshold (1 = show all money changes)
}

----------------------------------------------------------------------------------------
-- 21. SCT (Scrolling Combat Text)
----------------------------------------------------------------------------------------
C.SCT = {
    Enable = true,
    
    font = "Pixel", -- Default font (from media)
    font_size = 12,
    font_flags = "OUTLINE",

    alpha = 1,
    scroll_height = 50,
    
    -- Offsets for text spawn
    x_offset = 0,
    y_offset = 25,
    
    personal_x_offset = 0,
    personal_y_offset = -180,

    -- [ Animations ]
    -- Valid: "verticalUp", "verticalDown", "fountain", "rainfall", "disabled"
    animations = {
        outgoing = {
            normal = "verticalUp",
            crit = "verticalUp", 
            miss = "verticalUp",
        },
        personal = {
            normal = "verticalUp",
            crit = "verticalUp",
            miss = "verticalUp",
        },
    },
    
    animations_speed = 1.5, -- Duration in seconds

    -- [ Text Formatting ]
    truncate_enable = true,
    truncate_letter = true, -- 1.2k instead of 1,200
    truncate_comma = false,

    -- [ Scaling ]
    size_small_hits_scale = 0.75,
    size_crit_scale = 1.5,
    size_miss_scale = 1.25,

    -- [ Filtering ]
    -- Note: Thresholds are IGNORED for secret values
    size_small_hits = true,
    size_small_hits_hide = false, 
    
    -- [ Icons ]
    icon_enable = true,
    icon_scale = 1.8,
    icon_position = "LEFT", -- "LEFT", "RIGHT", "TOP", "BOTTOM"
    icon_x_offset = -5,
    icon_y_offset = 0,
    
    -- [ Damage Types ]
    -- Colors are handled internally via RefineUI.Colors or fallback
}

----------------------------------------------------------------------------------------
-- Export Configuration
----------------------------------------------------------------------------------------
RefineUI.Config = C
