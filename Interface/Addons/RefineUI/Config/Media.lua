----------------------------------------------------------------------------------------
-- RefineUI Media
-- Description: Registers fonts, textures, and sounds with LibSharedMedia.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local M = [[Interface\AddOns\RefineUI\Media\]]

----------------------------------------------------------------------------------------
-- Media Table Definitions
----------------------------------------------------------------------------------------
RefineUI.Media.Fonts = {
    Default = M .. [[Fonts\ITCAvantGardeStd-Demi.ttf]],
    Bold = M .. [[Fonts\ITCAvantGardeStd-Bold.ttf]],
    Medium = M .. [[Fonts\ITCAvantGardeStd-Md.ttf]],
    Pixel = M .. [[Fonts\m5x7.ttf]],
    -- Aliases and Fallbacks
    Combat = M .. [[Fonts\m5x7.ttf]],
    Number = M .. [[Fonts\ITCAvantGardeStd-Demi.ttf]],
    Attachment = M .. [[Fonts\ITCAvantGardeStd-Demi.ttf]],
    BarlowBold = M .. [[Fonts\ITCAvantGardeStd-Bold.ttf]],
}

RefineUI.Media.Textures = {
    Blank = [[Interface\Buttons\WHITE8x8]],
    Smooth = M .. [[Textures\SmoothV2.tga]],
    Statusbar = M .. [[Textures\Statusbar.blp]],
    Border = M .. [[Textures\RefineBorder.blp]],
    Backdrop = M .. [[Textures\BackdropBlizz.tga]],
    
    -- Additional Textures
    Overlay = M..[[Textures\Overlay.tga]],
    Shadow = M..[[Textures\ShadowTex.tga]],
    Highlight = M..[[Textures\Highlight.tga]],
    Glow = M .. [[Textures\Glow.tga]],
    RefineBorder = M .. [[Textures\RefineBorder.blp]],
    
    -- Icons
    ChatCopy = M .. [[Textures\ChatCopy.blp]],
    Close = M..[[Textures\Close.tga]],
    ExitVehicle = M..[[Textures\ExitVehicle.tga]],
    
    -- Arrows
    ArrowUp = M..[[Textures\ArrowAbove.tga]],
    ArrowDown = M..[[Textures\ArrowBelow.tga]],
    ArrowLeft = M..[[Textures\ArrowLeft.tga]],
    ArrowRight = M..[[Textures\ArrowRight.tga]],
    TargetArrowLeft = M..[[Textures\LTargetArrow2.blp]],
    TargetArrowRight = M..[[Textures\RTargetArrow2.blp]],

    -- UnitFrame
    HealthBar = M .. [[Textures\SmoothV2.tga]],
    HealthBackground = M .. [[Textures\HealthBackground.blp]],
    PowerBar = M .. [[Textures\PowerBar.blp]],
    CooldownSwipe = M .. [[Textures\CDBig.blp]],
    CooldownSwipeSmall = M .. [[Textures\CDSmall.blp]],
    
    -- UnitFrame Parts
    Frame = M .. [[Textures\Frame.blp]],
    FrameSmall = M .. [[Textures\FrameSmall.blp]],
    PartyFrame = M .. [[Textures\PartyFrame.blp]],
    PetFrame = M .. [[Textures\PortraitOff-Pet.blp]],
    FrameMask = M .. [[Textures\frameMask.tga]],
    Leader = M .. [[Textures\LEADER.blp]],
    
    -- Masks (Blizzard)
    MaskHealth = "interface/hud/uipartyframeportraitoffhealthmask",
    MaskMana = "interface/hud/uipartyframeportraitoffmanamask",
    
    -- Portrait
    PortraitBG = M .. [[Textures\PortraitBG.blp]],
    PortraitBorder = M .. [[Textures\PortraitBorder.blp]],
    PortraitGlow = M .. [[Textures\PortraitGlow.blp]],
    PortraitMask = M .. [[Textures\PortraitMask.blp]],
    PortraitStatus = M .. [[Textures\PortraitStatus.blp]],
    
    -- Roles
    RoleTank = M..[[Textures\TANK.blp]],
    RoleHealer = M..[[Textures\HEALER.blp]],
    RoleDamager = M..[[Textures\DAMAGER.blp]],
    
    -- Quests
    QuestLoot = M .. [[Textures\QuestLoot.blp]],
    QuestKill = M .. [[Textures\QuestKill.blp]],
    QuestIcon = M .. [[Textures\QuestIcon.blp]],
} 

RefineUI.Media.Sounds = {
    Whisper = M .. [[Sounds\Whisper.ogg]],
    EncounterCountdown1 = M .. [[Sounds\EncounterCountdown\1.ogg]],
    EncounterCountdown2 = M .. [[Sounds\EncounterCountdown\2.ogg]],
    EncounterCountdown3 = M .. [[Sounds\EncounterCountdown\3.ogg]],
    EncounterCountdown4 = M .. [[Sounds\EncounterCountdown\4.ogg]],
    EncounterCountdown5 = M .. [[Sounds\EncounterCountdown\5.ogg]],
}

RefineUI.Media.Logo = M..[[Logo\Logo.blp]]

----------------------------------------------------------------------------------------
-- Registration (LSM)
----------------------------------------------------------------------------------------
if not LSM then return end

LSM:Register("font", "ITC Avant Garde Demi", RefineUI.Media.Fonts.Default)
LSM:Register("font", "ITC Avant Garde Bold", RefineUI.Media.Fonts.Bold)
LSM:Register("font", "ITC Avant Garde Medium", RefineUI.Media.Fonts.Medium)
LSM:Register("font", "Barlow Black", RefineUI.Media.Fonts.Combat)
LSM:Register("font", "Barlow Numbers", RefineUI.Media.Fonts.Number)

LSM:Register("statusbar", "RefineUI Statusbar", RefineUI.Media.Textures.Statusbar)
LSM:Register("sound", "RefineUI Whisper", RefineUI.Media.Sounds.Whisper)
LSM:Register("sound", "RefineUI Encounter Countdown 1", RefineUI.Media.Sounds.EncounterCountdown1)
LSM:Register("sound", "RefineUI Encounter Countdown 2", RefineUI.Media.Sounds.EncounterCountdown2)
LSM:Register("sound", "RefineUI Encounter Countdown 3", RefineUI.Media.Sounds.EncounterCountdown3)
LSM:Register("sound", "RefineUI Encounter Countdown 4", RefineUI.Media.Sounds.EncounterCountdown4)
LSM:Register("sound", "RefineUI Encounter Countdown 5", RefineUI.Media.Sounds.EncounterCountdown5)

-- Set Default Media
LSM.MediaTable.font["RefineUI"] = RefineUI.Media.Fonts.Default
LSM.MediaTable.statusbar["RefineUI"] = RefineUI.Media.Textures.Statusbar
