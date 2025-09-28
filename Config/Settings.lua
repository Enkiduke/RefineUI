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
-- General options
----------------------------------------------------------------------------------------
local general = CreateSection("general")

general.autoScale = true       -- Auto UI Scale
general.uiScale = 0.53333      -- Your value (between 0.2 and 1) if "autoScale" is disabled
general.hideBanner = true      -- Hide Boss Banner Loot Frame
general.hideTalkingHead = true -- Hide Talking Head Frame

----------------------------------------------------------------------------------------
-- Media options
----------------------------------------------------------------------------------------
local media = CreateSection("media")

media.path = "Interface\\AddOns\\RefineUI\\Media\\"
media.normalFont = [[Interface\AddOns\RefineUI\Media\Fonts\ITCAvantGardeStd-Demi.ttf]] -- Normal font
media.normalFontStyle =
"OUTLINE"                                                                              -- Pixel font style ("MONOCHROMEOUTLINE" or "OUTLINE")
media.normalFontSize = 16                                                              -- Pixel font size for those places where it is not specified
media.boldFont = [[Interface\AddOns\RefineUI\Media\Fonts\ITCAvantGardeStd-Bold.ttf]]   -- Bold font
media.blank = [[Interface\AddOns\RefineUI\Media\Textures\RefineUIBlank.tga]]           -- Texture for borders
media.texture = [[Interface\AddOns\RefineUI\Media\Textures\RefineUIBlank.tga]]         -- Texture for status bars
media.border = [[Interface\AddOns\RefineUI\Media\Textures\RefineBorder.blp]]
media.highlight = [[Interface\AddOns\RefineUI\Media\Textures\Highlight.tga]]           -- Texture for debuffs highlight
media.whispSound = [[Interface\AddOns\RefineUI\Media\Sounds\Whisper.ogg]]              -- Sound for whispers
media.warningSound = [[Interface\AddOns\RefineUI\Media\Sounds\Warning.ogg]]            -- Sound for warning
media.procSound = [[Interface\AddOns\RefineUI\Media\Sounds\Proc.ogg]]                  -- Sound for procs

-- Unit Frame Textures
-- Use exact files that exist in Media/Textures. Prefer .blp if available.
media.healthBar = C.media.path .. "Textures/Health3"       -- extensionless to let client resolve .tga/.blp variants
media.healthBackground = C.media.path .. "Textures/HealthBG" -- extensionless path
media.portraitBorder = C.media.path .. "Textures/PortraitBorder.blp"
media.portraitMask = C.media.path .. "Textures/PortraitMask.blp"
media.portraitBackground = C.media.path .. "Textures/PortraitBG.blp"
media.portraitGlow = C.media.path .. "Textures/PortraitGlow.blp"
media.auraCooldown = C.media.path .. "Textures/CDAura.blp"      -- Aura/Cooldown swipe texture
media.experienceBar = C.media.path .. "Textures/Statusbar.blp" -- Experience bar texture


media.actionbarCooldown = C.media.path .. "Textures/CDBig.blp"
media.auraCooldown = C.media.path .. "Textures/CDBig.blp"
-- Nameplate Textures
media.nameplateHealthMask = C.media.path .. "Textures/MaskTest2.blp"
media.nameplateGlow = C.media.path .. "Textures/RefineGlow.blp"
media.castbarTexture = C.media.path .. "Textures/Castbar3.blp"
media.targetIndicatorRight = C.media.path .. "Textures/RTargetArrow2.blp"
media.targetIndicatorLeft = C.media.path .. "Textures/LTargetArrow2.blp"

media.classBorderColor = { R.color.r, R.color.g, R.color.b, 1 }                        -- Color for class borders
media.borderColor = { 0.5, 0.5, 0.5, 1 }                                               -- Color for borders
media.backdropColor = { 0.094, 0.094, 0.094, .75 }                                     -- Color for borders backdrop
media.backdropAlpha = 0.75                                                             -- Alpha for transparent backdrop

----------------------------------------------------------------------------------------
-- Unit Frames options
----------------------------------------------------------------------------------------
local unitframes = CreateSection("unitframes")

R.UF = {}
unitframes.frameWidth = 180      -- Player and Target width
unitframes.healthHeight = 20     -- Additional height for health
unitframes.powerHeight = 4       -- Additional height for power
unitframes.castbarWidth = 180    -- Player and Target castbar width
unitframes.castbarHeight = 16    -- Player and Target castbar height
unitframes.colorValue = false    -- Health/mana value is colored
unitframes.barColorValue = true  -- Health bar color by current health remaining
unitframes.unitCastbar = true    -- Show castbars
unitframes.castbarLatency = true -- Castbar latency
unitframes.castbarTicks = true   -- Castbar ticks

-- Smooth statusbar settings (HP/Power smoothing)
unitframes.smoothSpeedUp = 14            -- Heal smoothing speed (higher = faster)
unitframes.smoothSpeedDown = 20          -- Damage smoothing speed (higher = faster)
unitframes.smoothSnapAbs = 0.5           -- Absolute snap threshold (bar units)
unitframes.smoothElapsedMax = 0.20       -- Max elapsed per frame used by driver
unitframes.smoothSkipHidden = true       -- Skip smoothing when bars are hidden (snap instantly)
unitframes.smoothOnlyInCombat = true     -- Only smooth when in combat
unitframes.smoothSnapOnDeath = true      -- Instant snap on death/ghost
unitframes.smoothSnapOnResurrect = true  -- Instant snap on resurrect
unitframes.smoothSnapOnDisconnect = true -- Instant snap on disconnect
unitframes.smoothSnapOnInvisible = true  -- Instant snap on invisible
unitframes.smoothBigJumpFrac = 0         -- Big-jump fraction threshold (0 to disable)

----------------------------------------------------------------------------------------
-- Auras/Buffs/Debuffs options
----------------------------------------------------------------------------------------
local player = CreateSection("player")

player.buffSize = 48          -- Player buffs size
player.buffSpacing = 6        -- Player buffs spacing
player.buffTimer = true       -- Show cooldown timer on aura icons

player.debuffSize = 32        -- Debuffs size on unitframes
player.debuffTimer = true     -- Show cooldown timer on aura icons
player.debuffColorType = true -- Color debuff by type

----------------------------------------------------------------------------------------
-- Raid Frames options
----------------------------------------------------------------------------------------
local group = CreateSection("group")

group.byRole = true          -- Sorting players in group by role
group.aggroBorder = true     -- Aggro border
group.rangeAlpha = 0.5       -- Alpha of unitframes when unit is out of range

group.partyWidth = 160       -- Party width
group.partyHealthHeight = 20 -- Party height
group.partyPowerHeight = 3   -- Party power height

group.raidWidth = 140        -- Raid width
group.raidHealthHeight = 18  -- Raid height
group.raidPowerHeight = 2    -- Raid power height

----------------------------------------------------------------------------------------
-- ActionBar options
----------------------------------------------------------------------------------------
local actionbars = CreateSection("actionbars")

actionbars.hotkey = false  -- Show hotkey on buttons
actionbars.buttonSize = 36 -- Buttons size
actionbars.buttonSpace = 8 -- Buttons space
-- Cooldown number font size for action buttons (overrides Fonts.lua cooldownTimers size)
actionbars.cooldownFontSize = 20

----------------------------------------------------------------------------------------
-- AutoBar options
----------------------------------------------------------------------------------------
local autoitembar = CreateSection("autoitembar")

autoitembar.enable = true                  -- Enable actionbars
autoitembar.buttonSize = 36                -- Buttons size
autoitembar.buttonSpace = 8                -- Buttons space
autoitembar.consumable_mouseover = true   -- Set to false to always show the bar (changed for debugging)
autoitembar.min_consumable_item_level = 70  -- Set the minimum item level for consumables (lowered for debugging)

----------------------------------------------------------------------------------------
-- Chat options
----------------------------------------------------------------------------------------
local chat = CreateSection("chat")

chat.width = 600         -- Chat width
chat.height = 300        -- Chat height
chat.whisperSound = true -- Sound when whisper
chat.combatLog = true    -- Show CombatLog tab
chat.lootIcons = true    -- Icons for loot
chat.roleIcons = true    -- Role Icons
chat.history = true      -- Chat history

-- Timestamp options
chat.timestamps = true           -- Enable timestamps on all chat messages
chat.timestampFormat = "HHMM_24HR"    -- Format: "HHMM", "HHMMSS", "HHMM_24HR", "HHMMSS_24HR", "HHMM_AMPM", "HHMMSS_AMPM"
chat.timestampColor = true       -- Color timestamps based on message age

----------------------------------------------------------------------------------------
-- Tooltip options
----------------------------------------------------------------------------------------
local tooltip = CreateSection("tooltip")

tooltip.cursor = true       -- Tooltip above cursor
tooltip.hidebuttons = false -- Hide tooltip for actions bars
tooltip.hideCombat = true   -- Hide tooltip in combat
-- Plugins
tooltip.realm = true        -- Player realm name in tooltip
tooltip.averageiLvl = false -- Average items level
tooltip.showShift = true    -- Show items level and spec when Shift is pushed

----------------------------------------------------------------------------------------
-- Minimap options
----------------------------------------------------------------------------------------
local minimap = CreateSection("minimap")

minimap.size = 294           -- Minimap size
minimap.addonButtonSize = 28 -- Minimap Addon Button size
minimap.zoomReset = true     -- Show toggle menu
minimap.resetTime = 15       -- Show toggle menu

----------------------------------------------------------------------------------------
-- Loot options
----------------------------------------------------------------------------------------
local loot = CreateSection("loot")

loot.autoConfirmDE = true -- Auto confirm disenchant and take BoP loot

----------------------------------------------------------------------------------------
-- AutoSell options
----------------------------------------------------------------------------------------
local autosell = CreateSection("autosell")

autosell.enable = true        -- Enable the auto-sell feature
autosell.ilvlThreshold = 500   -- Sell items strictly *below* this item level
autosell.sellOnlyEquipment = true -- If true, only sell items of type Armor or Weapon

----------------------------------------------------------------------------------------
-- Loot Filter options
----------------------------------------------------------------------------------------
local lootfilter = CreateSection("lootfilter")

lootfilter.enable = true                                -- Enable loot frame
lootfilter.minQuality = 3                               -- Minimum quality to always loot (0 = Poor, 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Epic)
-- User Configuration
lootfilter.junkMinPrice = 10                            -- Minimum value (in gold) of grey items to loot
lootfilter.tradeskillSubtypes = { "Parts", "Jewelcrafting", "Cloth", "Leather", "Metal & Stone", "Cooking", "Herb",
    "Elemental", "Other", "Enchanting", "Inscription" } -- Tradeskill subtypes to always loot
lootfilter.tradeskillMinQuality = 1                     -- Quality cap for autolooting tradeskill items (0 = Poor, 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Epic)
lootfilter.gearMinQuality = 2                           -- Minimum quality of BoP weapons and armor to autoloot (0 = Poor, 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Epic)
lootfilter.gearUnknown = true                           -- Override other gear settings to loot unknown appearances
lootfilter.gearPriceOverride = 20                       -- Minimum vendor price (in gold) to loot gear regardless of other criteria

-- New merged loot settings
lootfilter.delay = 0.0                                  -- Throttle between auto-loot executions (seconds)
lootfilter.closeAfterLoot = true                        -- Close loot window after auto-looting
lootfilter.forceDisableAutoLoot = false                 -- If true, force SetCVar("autoLootDefault", "0") on load
lootfilter.debug = true                                -- Enable debug prints for filtered items
lootfilter.respectAutoLootToggle = false               -- If true, only autoloot when Blizzard's autoloot condition is met
lootfilter.keepOpenModifier = "CTRL"                    -- Hold this key to keep the loot window open ("NONE","CTRL","SHIFT","ALT")

----------------------------------------------------------------------------------------
-- Skins options
----------------------------------------------------------------------------------------
local skins = CreateSection("skins")

skins.details = true -- Blizzard frames skin
skins.opie = true    -- Skin Blizzard chat bubbles


----------------------------------------------------------------------------------------
-- Auras/Buffs/Debuffs options
----------------------------------------------------------------------------------------
local auras = CreateSection("auras")

auras.buffSize = 24            -- Buffs size on unitframes
auras.debuffSize = 24          -- Debuffs size on unitframes
auras.showSpiral = true        -- Spiral on aura icons
auras.showTimer = true         -- Show cooldown timer on aura icons
auras.playerAuras = true       -- Auras on player frame
auras.targetAuras = true       -- Auras on target frame
auras.focusDebuffs = false     -- Debuffs on focus frame
auras.fotDebuffs = false       -- Debuffs on focustarget frame
auras.petDebuffs = false       -- Debuffs on pet frame
auras.totDebuffs = false       -- Debuffs on targettarget frame
auras.bossAuras = true         -- Auras on boss frame
auras.bossDebuffs = 0          -- Number of debuffs on the boss frames
auras.bossBuffs = 3            -- Number of buffs on the boss frames
auras.playerAuraOnly = false   -- Only your debuff on target frame
auras.debuffColorType = true   -- Color debuff by type
auras.classcolorBorder = false -- Enable classcolor border for player buffs
auras.castBy = true            -- Show who cast a buff/debuff in its tooltip

----------------------------------------------------------------------------------------
-- Buffs reminder options
----------------------------------------------------------------------------------------
local reminder = CreateSection("reminder")

reminder.soloBuffsEnable = true -- Enable buff reminder
reminder.soloBuffsSound = false -- Enable warning sound notification for buff reminder
reminder.soloBuffsSize = 64     -- Icon size
reminder.soloBuffsFlash = true  -- Icon flash
reminder.raidBuffsEnable = true -- Show missing raid buffs
reminder.raidBuffsAlways = true -- Show frame always (default show only in raid)
reminder.raidBuffsSize = 28     -- Icon size
reminder.raidBuffsAlpha = 1     -- Transparent icons when the buff is present

----------------------------------------------------------------------------------------
-- Nameplate options
----------------------------------------------------------------------------------------
local nameplate = CreateSection("nameplate")

nameplate.enable = true                                  -- Enable nameplate
nameplate.width = 70                                     -- Nameplate width
nameplate.height = 9                                     -- Nameplate height
nameplate.adWidth = 0                                    -- Additional width for selected nameplate
nameplate.adHeight = 0                                   -- Additional height for selected nameplate
nameplate.alpha = .75                                    -- Non-target nameplate alpha
nameplate.noTargetAlpha = 1                              -- Non-target alpha to use when nothing is targeted
nameplate.combat = true                                  -- Automatically hide nameplates in combat
nameplate.healthValue = true                             -- Numeral health value
nameplate.showCastbarName = true                         -- Show castbar name
nameplate.classIcons = false                             -- Icons by class in PvP
nameplate.nameAbbrev = true                              -- Display abbreviated names
nameplate.shortName = true                               -- Replace names with short ones
nameplate.clamp = true                                   -- Clamp nameplates to the top of the screen when outside of view
nameplate.trackDebuffs = true                            -- Show your debuffs (from the list)
nameplate.trackBuffs = false                             -- Show dispellable enemy buffs and buffs from the list
nameplate.aurasSize = 16                                 -- Auras size
nameplate.auraTimer = false                              -- Show cooldown timer on aura icons (OFF by default)
nameplate.cooldownSwipe = true                           -- Show cooldown swipe on aura icons (performance toggle)
nameplate.healerIcon = false                             -- Show icon above enemy healers nameplate in battlegrounds
nameplate.totemIcons = false                             -- Show icon above enemy totems nameplate
nameplate.targetGlow = false                             -- Show glow texture for target
nameplate.targetIndicator = true                         -- Show target arrows for target
nameplate.onlyName = true                                -- Show only name for friendly units
nameplate.quests = true                                  -- Show quest icon
nameplate.use_api_quests = true                          -- Prefer API-only quest matching (no tooltip scans)
nameplate.questCacheTTL = 1                              -- Quest cache TTL in seconds (small values = more responsive)
nameplate.lowHealth = false                              -- Show red border when low health
nameplate.lowHealthValue = 0.2                           -- Value for low health (between 0.1 and 1)
nameplate.lowHealthColor = { 0.8, 0, 0 }                 -- Color for low health border
nameplate.targetBorder = true                            -- Color for low health border
nameplate.targetBorderColor = { .8, .8, .8 }             -- Color for low health border
nameplate.castColor = false                              -- Show color border for casting important spells
nameplate.kickColor = false                              -- Change cast color if interrupt on cd
nameplate.interruptColor = true                          -- Color interrupted text by the player who interrupted
-- Crowd Control bar options
nameplate.ccbarText = "PLAYER"                           -- Left text: SPELL | PLAYER | NONE
nameplate.ccbarFillUp = false                            -- If true, bar fills up; if false, bar empties
-- Threat
nameplate.enhanceThreat = true                           -- Enable threat feature, automatically changes by your role
	nameplate.offtankScanThrottle = 0.5                      -- Seconds between off-tank scans per unit (lower = more responsive, higher = better performance)
nameplate.goodColor = { 0.2, 0.8, 0.2 }                  -- Good threat color
nameplate.nearColor = { 1, 1, 0 }                        -- Near threat color
nameplate.badColor = { 1, 0, 0 }                         -- Bad threat color
nameplate.offtankColor = { 0, 0.5, 1 }                   -- Offtank threat color
nameplate.goodColorbg = { 0.2 * .2, 0.8 * .2, 0.2 * .2 } -- Good threat color
nameplate.nearColorbg = { 1 * .2, 1 * .2, 0 * .2 }       -- Near threat color
nameplate.badColorbg = { 1 * .2, 0 * .2, 0 * .2 }        -- Bad threat color
nameplate.offtankColorbg = { 0 * .2, 0.5 * .2, 1 * .2 }  -- Offtank threat color
nameplate.extraColor = { 1, 0.3, 0 }                     -- Explosive and Spiteful affix color
nameplate.mobColorEnable = false                         -- Change color for important mobs in dungeons
nameplate.mobColor = { 0, 0.5, 0.8 }                     -- Color for mobs

-- Friendly nameplate performance gating
-- If you never use friendly plates for health, cast, or auras, disable their elements entirely.
nameplate.disableFriendlyHealth = true                   -- Disable Health element for friendly units (still shows name text)
nameplate.disableFriendlyCastbar = true                  -- Disable Castbar element for friendly units
nameplate.disableFriendlyAuras = true                    -- Disable Auras element for friendly units
nameplate.disableFriendlyPower = true                    -- Disable Power element for friendly units (kept only on personal plate)

-- BigWigs integration
nameplate.bigwigsSkinning = true                         -- Enable BigWigs nameplate icon skinning
nameplate.bigwigsIconSize = 20                           -- Size of BigWigs nameplate icons
nameplate.bigwigsShowCooldown = true                     -- Show cooldown swipe on BigWigs icons
nameplate.bigwigsShowCount = true                        -- Show count text on BigWigs icons
nameplate.bigwigsDebug = false                           -- Enable debug messages for BigWigs skinning

----------------------------------------------------------------------------------------
-- Automation options
----------------------------------------------------------------------------------------
local automation = CreateSection("automation")

automation.autoRelease = true         -- Auto release the spirit in battlegrounds
automation.autoScreenshot = false     -- Take screenshot when player get achievement
automation.autoAcceptInvite = false   -- Auto accept invite
automation.autoZoneTrack = true       -- Auto-Track Quests by Zone
automation.autoCollapse = "NONE"      -- Auto collapse Objective Tracker (RAID, RELOAD, SCENARIO, NONE)
automation.autoSkipCinematic = true   -- Auto skip cinematics/movies that have been seen (disabled if hold Ctrl)
automation.autoSetRole = false        -- Auto set your role
automation.autoResurrection = false   -- Auto confirm resurrection
automation.autoWhisperInvite = false  -- Auto invite when whisper keyword
automation.inviteKeyword = "inv +"    -- List of keyword (separated by space)
automation.autoRepair = true          -- Auto repair
automation.autoGuildRepair = true     -- Auto repair with guild funds first (if able)
automation.autoButton = true          -- Enable AutoButton for quest items

-- AutoPotion settings
automation.autoPotion = true          -- Enable AutoPotion macro management
automation.autoPotionMacroName = "AutoPotion"  -- Name of the macro to create/update
automation.autoPotionStopCast = false -- Add /stopcasting to the macro
automation.autoPotionRaidStone = false -- If true, healthstones have lower priority than potions
automation.autoPotionCrimsonVial = false -- Enable Crimson Vial (Rogue ability) - disabled by default

----------------------------------------------------------------------------------------
-- Filger options
----------------------------------------------------------------------------------------
local filger = CreateSection("filger")

filger.enable = true           -- Enable Filger
filger.show_tooltip = false    -- Show tooltip
filger.expiration = true       -- Sort cooldowns by expiration time
filger.missing_flash = true    -- Flash Missing type buffs for attention
-- Elements
filger.show_buff = true        -- Player buffs
filger.show_proc = true        -- Player procs
filger.show_debuff = false     -- Debuffs on target
filger.show_aura_bar = false   -- Aura bars on target
filger.show_special = true     -- Special buffs on player
filger.show_pvp_player = false -- PvP debuffs on player
filger.show_pvp_target = false -- PvP auras on target
filger.show_cd = true          -- Cooldowns
-- Icons size
filger.buffs_size = 48         -- Buffs size
filger.buffs_space = 3         -- Buffs space
filger.pvp_size = 60           -- PvP auras size
filger.pvp_space = 3           -- PvP auras space
filger.cooldown_size = 30      -- Cooldowns size
filger.cooldown_space = 3      -- Cooldowns space
-- Testing
filger.test_mode = false       -- Test icon mode
filger.max_test_icon = 5       -- Number of icons in test mode

----------------------------------------------------------------------------------------
-- Scrolling Combat Text options
----------------------------------------------------------------------------------------
local sct = CreateSection("sct")

sct.enable = true            -- Global enable combat text
sct.overkill = false         -- Use blizzard damage/healing output (above mob/player head)
sct.x_offset = 0             -- Horizontal offset for text
sct.y_offset = 35            -- Vertical offset for text
sct.default_color = "ffff00" -- Default text color
sct.alpha = 1                -- Text transparency

-- Off-target options
sct.offtarget_enable = true -- Enable off-target text
sct.offtarget_size = 12     -- Off-target text size
sct.offtarget_alpha = 0.6   -- Off-target text transparency

-- Personal text options
sct.personal_enable = false           -- Enable personal text
sct.personal_only = false             -- Show only personal text
sct.personal_default_color = "ffff00" -- Personal text color
sct.personal_x_offset = 0             -- Personal text horizontal offset
sct.personal_y_offset = 0             -- Personal text vertical offset

-- Strata options
sct.strata_enable = false       -- Enable custom strata
sct.strata_target = "HIGH"      -- Target strata level
sct.strata_offtarget = "MEDIUM" -- Off-target strata level

-- Icon options
sct.icon_enable = true      -- Enable icons
sct.icon_scale = 1          -- Icon scale
sct.icon_shadow = true      -- Show icon shadow
sct.icon_position = "RIGHT" -- Icon position relative to text
sct.icon_x_offset = 0       -- Icon horizontal offset
sct.icon_y_offset = 0       -- Icon vertical offset

-- Truncate options
sct.truncate_enable = true -- Enable text truncation
sct.truncate_letter = true -- Use letter abbreviations (K, M, etc.)
sct.truncate_comma = true  -- Use comma for thousands separator

-- Size options
sct.size_crits = true                  -- Enlarge critical hits
sct.size_crit_scale = 1                -- Critical hit scale factor
sct.size_miss = false                  -- Enlarge misses
sct.size_miss_scale = 1                -- Miss scale factor
sct.size_small_hits = true             -- Reduce size of small hits
sct.size_small_hits_scale = 0.9        -- Small hit scale factor
sct.size_small_hits_hide = true        -- Hide small hits
sct.size_autoattack_crit_sizing = true -- Use crit sizing for auto-attack crits

-- Animation options
sct.animations_ability = "verticalUp"        -- Animation for ability text
sct.animations_crit = "verticalUp"           -- Animation for critical hits
sct.animations_miss = "verticalUp"           -- Animation for misses
sct.animations_autoattack = "verticalUp"     -- Animation for auto-attacks
sct.animations_autoattackcrit = "verticalUp" -- Animation for auto-attack crits
sct.animations_speed = 1                     -- Animation speed

-- Personal animation options
sct.personalanimations_normal = "verticalUp" -- Animation for normal personal text
sct.personalanimations_crit = "verticalUp"   -- Animation for personal crits
sct.personalanimations_miss = "verticalUp"   -- Animation for personal misses

----------------------------------------------------------------------------------------
-- Miscellaneous options
----------------------------------------------------------------------------------------
local misc = CreateSection("misc")

misc.afk = true             -- Spin camera while afk
misc.combatTargeting = true -- Sticky targeting in combat
misc.disableRightClickCombat = true -- Disable right click in combat

----------------------------------------------------------------------------------------
-- Combat Crosshair options
----------------------------------------------------------------------------------------
local combatcrosshair = CreateSection("combatcrosshair")

combatcrosshair.enable = true                                                        -- Enable combat crosshair
combatcrosshair.texture = [[Interface\AddOns\RefineUI\Media\Textures\Crosshair.tga]] -- Crosshair texture
combatcrosshair.color = { 1, 1, 1 }                                                  -- Crosshair color (RGB)
combatcrosshair.size = 32                                                            -- Crosshair size (default used by module if not set)
combatcrosshair.offsetx = 0                                                          -- Horizontal offset from screen center
combatcrosshair.offsety = -32                                                          -- Vertical offset from screen center
combatcrosshair.alpha = 0.6                                                          -- Baseline alpha when shown
combatcrosshair.strata = "TOOLTIP"                                                  -- Frame strata to use (sits above most UI)
combatcrosshair.blend = "ADD"                                                     -- Blend mode for texture ("ADD" for glowy)
combatcrosshair.visibility = "[combat]show; hide"                                  -- Visibility state driver string
combatcrosshair.pulseOnEnter = true                                                  -- Play small pop-in animation when shown

----------------------------------------------------------------------------------------
-- Combat Cursor options
----------------------------------------------------------------------------------------
local combatcursor = CreateSection("combatcursor")
combatcursor.enable = true                                                           -- Enable combat cursor
combatcursor.texture = [[Interface\AddOns\RefineUI\Media\Textures\CursorCircle.blp]] -- Cursor texture
combatcursor.color = { 1, 1, 1, 1 }                                                  -- Cursor color (RGBA)
combatcursor.size = 50                                                               -- Cursor size

----------------------------------------------------------------------------------------
-- BigWigs Timeline options
----------------------------------------------------------------------------------------
local bwtimeline = CreateSection("bwtimeline")

bwtimeline.enable = true           -- Enable BigWigs Timeline
bwtimeline.refresh_rate = 0.05     -- Refresh rate for the timeline
bwtimeline.smooth_queueing = true  -- Enable smooth queueing
bwtimeline.bw_alerts = true        -- Keep BigWigs bars present but invisible (alpha 0)
bwtimeline.invisible_queue = true  -- Keep queued icons hidden until visible window
bwtimeline.show_bigwigs_bars = false -- Show native BigWigs bars (useful for comparison/debug)

-- Driver and smoothing settings
bwtimeline.max_queue_icons = 6      -- Max number of queued (future) icons shown above the bar
bwtimeline.smoothing = 0.15         -- Smoothing factor for icon movement (0.1–0.3 typical)
bwtimeline.snap_eps = 0.25          -- Pixel snapping threshold to avoid SetPoint churn
bwtimeline.hz = 120                 -- Target update rate (Hz) for the timeline driver

-- Nameplate bridge settings
bwtimeline.nameplates_to_timeline = true   -- Enable nameplate -> timeline bridge inside instances
bwtimeline.np_target_only        = false    -- Only add icons for current target (default ON)
bwtimeline.np_dedupe_window      = 0.25    -- Seconds to dedupe quick-repeat abilities
bwtimeline.np_max_concurrent     = 6       -- Limit number of mob icons shown on the bar concurrently
bwtimeline.mob_alpha             = 0.95    -- Slight transparency for mob icons
bwtimeline.mob_desaturate        = false   -- Desaturate mob icons
bwtimeline.np_show_mob_name      = false   -- Prefix NP labels with mob name
bwtimeline.marker_icon_size      = 14      -- Inline raid marker icon size near the text
bwtimeline.hide_bw_nameplate_icons = true -- Suppress BigWigs Nameplates visuals (emit events only)
bwtimeline.np_debug = false    -- Debug prints for Nameplate -> Timeline bridge

-- Bar settings
bwtimeline.bar = {}
bwtimeline.bar_reverse = false                  -- Reverse bar direction
bwtimeline.bar_length = 316                     -- Length of the bar
bwtimeline.bar_width = 12                       -- Width of the bar
bwtimeline.bar_max_time = 15                    -- Maximum time displayed on the bar
bwtimeline.bar_hide_out_of_combat = true        -- Hide bar when out of combat
bwtimeline.bar_has_ticks = false                -- Show ticks on the bar
bwtimeline.bar_above_icons = true               -- Display bar above icons
bwtimeline.bar_tick_spacing = 5                 -- Spacing between ticks
bwtimeline.bar_tick_length = 20                 -- Length of ticks
bwtimeline.bar_tick_width = 1                   -- Width of ticks
bwtimeline.bar_tick_color = { 1, 1, 1, 1 }      -- Color of ticks (RGBA)
bwtimeline.bar_tick_text = true                 -- Show text on ticks
bwtimeline.bar_tick_text_font_size = 10         -- Font size of tick text
bwtimeline.bar_tick_text_position = "LEFT"      -- Position of tick text
bwtimeline.bar_tick_text_color = { 1, 1, 1, 1 } -- Color of tick text (RGBA)

-- Icon settings
bwtimeline.icons = {}
bwtimeline.icons_width = 35                      -- Width of icons
bwtimeline.icons_height = 35                     -- Height of icons
bwtimeline.icons_spacing = 3                     -- Adjust this value to increase/decrease spacing
bwtimeline.icons_duration = true                 -- Show duration on icons
bwtimeline.icons_duration_position = "CENTER"    -- Position of duration text on icons
bwtimeline.icons_duration_color = { 1, 1, 1, 1 } -- Color of duration text (RGBA)
bwtimeline.icons_name = true                     -- Show name on icons
bwtimeline.icons_name_position = "RIGHT"         -- Position of name text on icons
bwtimeline.icons_name_color = { 1, 1, 1, 1 }     -- Color of name text (RGBA)
bwtimeline.icons_name_acronym = false            -- Use acronyms for names
bwtimeline.icons_name_number = false             -- Show number on icons

bwtimeline.emphasized_color = {1, .5, 0, 1} -- Color of emphasized icons

----------------------------------------------------------------------------------------
-- MRTReminder options
----------------------------------------------------------------------------------------
local mrtreminder = CreateSection("mrtreminder")

mrtreminder.enable = false           -- Enable MRTReminder
mrtreminder.barColor = {0, 1, 0}  -- Default to orange (R, G, B values from 0 to 1)
mrtreminder.autoHide = 5            -- Time in seconds after icon hide (0 = never)
mrtreminder.autoShow = 20            -- Time in seconds before time's up to show icon
mrtreminder.speech = false           -- Use voice for notifications
mrtreminder.sound = [[Interface\AddOns\RefineUI\Media\Sounds\Alert.ogg]]  -- Sound for next cast

-- UI settings
mrtreminder.iconSize = 60           -- Size of the spell icons
mrtreminder.iconSpacing = 8         -- Spacing between icons
mrtreminder.frameStrata = "HIGH"    -- Frame strata for the reminder frame


----------------------------------------------------------------------------------------
-- Trade options
----------------------------------------------------------------------------------------
local trade = CreateSection("trade")

trade.profession_tabs = true -- Professions tabs on TradeSkill frames
trade.already_known = true   -- Colorizes recipes/mounts/pets/toys that is already known
trade.sum_buyouts = true     -- Sum up all current auctions

----------------------------------------------------------------------------------------
-- AdvCombatLog options
----------------------------------------------------------------------------------------
local advcombatlog = CreateSection("advcombatlog")

advcombatlog.enableTaunt = true
advcombatlog.enableInterrupt = true
advcombatlog.enableDispel = true
advcombatlog.enableCrowdControl = true
advcombatlog.enableDeath = true
advcombatlog.enableResurrect = true
advcombatlog.filterPlayers = true     -- Whether to filter events involving players (Currently unused, filtering based on relevance)
advcombatlog.filterPets = true        -- Whether to filter events involving pets (Currently unused, filtering based on relevance)
advcombatlog.outputLocal = true       -- Whether to output messages to the local chat frame
advcombatlog.outputChat = false       -- Whether to output messages to a specific chat channel
advcombatlog.chatChannel = "SAY"      -- The chat channel to output messages to (if outputChat is true)
advcombatlog.iconSize = 14            -- Size of inline icons in messages
advcombatlog.showTimestamps = true    -- Whether to show timestamps in messages
advcombatlog.groupMembersOnly = true -- Only process events for player/party/raid (and their pets)
advcombatlog.debug = false            -- Debug prints for Advanced Combat Log
