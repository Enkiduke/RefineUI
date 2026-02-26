----------------------------------------------------------------------------------------
-- RefineUI Fonts
-- Description: Applies global font overrides to the game client.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local unpack = unpack

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------
local function SetFont(obj, font, size, style, r, g, b, sr, sg, sb, sox, soy)
    if not obj then return end

    style = style or ""
    -- Use the Media table we created in Config/Media.lua
    -- Make sure Config is loaded/exists, otherwise default to 1
    local scale = (RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.Scale) or 1.0
    
    obj:SetFont(font, size * scale, style)

    if sr and sg and sb then 
        obj:SetShadowColor(sr, sg, sb) 
    end
    
    if sox and soy then 
        obj:SetShadowOffset(sox, soy) 
    end
    
    if r and g and b then 
        obj:SetTextColor(r, g, b) 
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
local function InitializeFonts()
    local NORMAL = RefineUI.Media.Fonts.Default
    local COMBAT = RefineUI.Media.Fonts.Combat
    
    -- Global Font Globals
    _G.UNIT_NAME_FONT = NORMAL
    _G.STANDARD_TEXT_FONT = NORMAL
    _G.DAMAGE_TEXT_FONT = RefineUI.Media.Fonts.Pixel
    _G.DAMAGE_TEXT_FONT = RefineUI.Media.Fonts.Pixel
    _G.COMBAT_TEXT_FONT = RefineUI.Media.Fonts.Pixel

    -- Manual Force for existing frames (if Blizzard_CombatText is loaded)
    if CombatTextFont then
        SetFont(CombatTextFont, RefineUI.Media.Fonts.Pixel, 25, "OUTLINE")
    end

    -- Base fonts
    SetFont(_G.AchievementFont_Small, NORMAL, 11, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.InvoiceFont_Med, NORMAL, 13, nil, 0.15, 0.09, 0.04)
    SetFont(_G.InvoiceFont_Small, NORMAL, 11, nil, 0.15, 0.09, 0.04)
    SetFont(_G.MailFont_Large, NORMAL, 15, nil, 0, 0, 0, 0, 0, 0, 1, -1)
    SetFont(_G.NumberFont_Outline_Huge, NORMAL, 30, "THICKOUTLINE", 30)
    SetFont(_G.NumberFont_Outline_Large, NORMAL, 17, "OUTLINE")
    SetFont(_G.NumberFont_Outline_Med, NORMAL, 15, "OUTLINE")
    SetFont(_G.NumberFont_Shadow_Med, NORMAL, 14)
    SetFont(_G.NumberFont_Shadow_Small, NORMAL, 13, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.NumberFont_Normal_Med, NORMAL, 13)
    SetFont(_G.NumberFont_Small, NORMAL, 10)
    SetFont(_G.NumberFontSmallWhiteLeft, NORMAL, 12)
    SetFont(_G.QuestFont_Large, NORMAL, 16)
    SetFont(_G.QuestFont_Shadow_Huge, NORMAL, 19, nil, nil, nil, nil, 0.54, 0.4, 0.1)
    SetFont(_G.QuestFont_Shadow_Small, NORMAL, 15)
    SetFont(_G.QuestFont_Super_Huge, NORMAL, 20, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.QuestFont_Huge, NORMAL, 17, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.QuestFont_Enormous, NORMAL, 30, nil, 1, 0.82, 0)
    SetFont(_G.ReputationDetailFont, NORMAL, 11, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.SpellFont_Small, NORMAL, 11)
    SetFont(_G.SystemFont_InverseShadow_Small, NORMAL, 11)
    SetFont(_G.SystemFont_Large, NORMAL, 17)
    SetFont(_G.SystemFont_Huge1, NORMAL, 20)
    SetFont(_G.SystemFont_Huge2, NORMAL, 24)
    SetFont(_G.SystemFont_Med1, NORMAL, 13)
    SetFont(_G.SystemFont_Med2, NORMAL, 14, nil, 0.15, 0.09, 0.04)
    SetFont(_G.SystemFont_Med3, NORMAL, 15)
    SetFont(_G.SystemFont_Outline, NORMAL, 13, "OUTLINE")
    SetFont(_G.SystemFont_OutlineThick_Huge2, NORMAL, 22, "THICKOUTLINE")
    SetFont(_G.SystemFont_OutlineThick_Huge4, NORMAL, 27, "THICKOUTLINE")
    SetFont(_G.SystemFont_OutlineThick_WTF, NORMAL, 31, "THICKOUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.SystemFont_Huge1_Outline, NORMAL, 19, "OUTLINE")
    SetFont(_G.SystemFont_Outline_Small, NORMAL, 12, "OUTLINE")
    SetFont(_G.SystemFont_Shadow_Huge1, NORMAL, 20)
    SetFont(_G.SystemFont_Shadow_Huge3, NORMAL, 25)
    SetFont(_G.SystemFont_Shadow_Large, NORMAL, 17)
    SetFont(_G.SystemFont_Shadow_Large2, NORMAL, 17)
    SetFont(_G.SystemFont_Shadow_Med1, NORMAL, 13)
    SetFont(_G.SystemFont_Shadow_Med2, NORMAL, 13)
    SetFont(_G.SystemFont_Shadow_Med3, NORMAL, 15)
    SetFont(_G.SystemFont_Shadow_Med1_Outline, NORMAL, 13)
    SetFont(_G.SystemFont16_Shadow_ThickOutline, NORMAL, 16, "OUTLINE")
    SetFont(_G.SystemFont22_Shadow_Outline, NORMAL, 22, "OUTLINE")
    SetFont(_G.SystemFont_Shadow_Small, NORMAL, 11)
    SetFont(_G.SystemFont_Shadow_Small2, NORMAL, 11)
    SetFont(_G.SystemFont_Small, NORMAL, 12)
    SetFont(_G.SystemFont_Small2, NORMAL, 12)
    SetFont(_G.SystemFont_Tiny, NORMAL, 11)
    SetFont(_G.GameTooltipHeader, NORMAL, 14, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Tooltip_Med, NORMAL, 12, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Tooltip_Small, NORMAL, 11, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.FriendsFont_Small, NORMAL, 11)
    SetFont(_G.FriendsFont_Normal, NORMAL, 12)
    SetFont(_G.FriendsFont_Large, NORMAL, 15)
    SetFont(_G.FriendsFont_UserText, NORMAL, 11)
    SetFont(_G.CoreAbilityFont, NORMAL, 32, nil, 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.ChatBubbleFont, NORMAL, 10, "OUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Game13FontShadow, NORMAL, 14)
    SetFont(_G.Game32Font_Shadow2, NORMAL, 32)
    SetFont(_G.Game15Font_o1, NORMAL, 15)
    SetFont(_G.Fancy14Font, NORMAL, 14)
    SetFont(_G.Game18Font, NORMAL, 18)
    SetFont(_G.Game16Font, NORMAL, 16)
    SetFont(_G.Game12Font, NORMAL, 12)
    SetFont(_G.Game13Font, NORMAL, 13)
    SetFont(_G.Fancy16Font, NORMAL, 16)
    SetFont(_G.FriendsFont_11, NORMAL, 11)
    SetFont(_G.PriceFont, NORMAL, 13)
    SetFont(_G.Number11Font, NORMAL, 10)
    SetFont(_G.Number12Font, NORMAL, 11)
    SetFont(_G.Number12FontOutline, NORMAL, 11, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Number13Font, NORMAL, 12)
    SetFont(_G.Number15Font, NORMAL, 14)
    SetFont(_G.Game11Font_o1, NORMAL, 11, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Game12Font_o1, NORMAL, 12, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Game13Font_o1, NORMAL, 13, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.Game15Font_Shadow, NORMAL, 16)
    SetFont(_G.SystemFont_Shadow_Large_Outline, NORMAL, 15, "OUTLINE")

    -- Derived fonts
    SetFont(_G.BossEmoteNormalHuge, NORMAL, 27, "THICKOUTLINE")
    SetFont(_G.ErrorFont, NORMAL, 16)
    SetFont(_G.QuestFontNormalSmall, NORMAL, 13, nil, nil, nil, nil, 0.54, 0.4, 0.1)
    SetFont(_G.WorldMapTextFont, NORMAL, 32, "OUTLINE")
    SetFont(_G.SubZoneTextFont, NORMAL, 30, "OUTLINE")
    SetFont(_G.WhiteNormalNumberFont, NORMAL, 11)
    SetFont(_G.ZoneTextString, NORMAL, 32, "OUTLINE")
    SetFont(_G.SubZoneTextString, NORMAL, 25, "OUTLINE")
    SetFont(_G.PVPInfoTextString, NORMAL, 22, "THINOUTLINE")
    SetFont(_G.PVPArenaTextString, NORMAL, 22, "THINOUTLINE")
    SetFont(_G.QuestMapRewardsFont, NORMAL, 12, nil, nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.NumberFontNormalSmall, NORMAL, 11, "OUTLINE")
    
    -- Quest Fonts (Missing)
    SetFont(_G.QuestFont, NORMAL, 13, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestFontNormalHuge, NORMAL, 15, "OUTLINE", 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoTitleHeader, NORMAL, 16, "OUTLINE", 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoDescriptionHeader, NORMAL, 14, "OUTLINE", 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoObjectivesHeader, NORMAL, 14, "OUTLINE", 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoDescriptionText, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoObjectivesText, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoRewardText, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoRewardsFrameQuestInfoItemContextLine, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestInfoRewardsFrameQuestInfoItemName, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    SetFont(_G.QuestTitleFont, NORMAL, 16, "OUTLINE", 1, 0.82, 0, 0, 0, 0, 1, -1)
    SetFont(_G.QuestTextFont, NORMAL, 12, "OUTLINE", 1, 1, 1, 0, 0, 0, 1, -1)
    
    -- Other
    SetFont(_G.ObjectiveFont, NORMAL, 13, "OUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.ObjectiveTrackerHeaderFont, NORMAL, 14, "OUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    SetFont(_G.ObjectiveTrackerLineFont, NORMAL, 13, "OUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    for i = 12, 22 do
        SetFont(_G["ObjectiveTrackerFont" .. i], NORMAL, i, "OUTLINE", nil, nil, nil, 0, 0, 0, 1, -1)
    end
end

local function RegisterFontsStartup()
    local key = "Config:Fonts"
    local priority = 20

    local function startup()
        InitializeFonts()

        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self, event, arg1)
            if event == "ADDON_LOADED" and arg1 == "Blizzard_CombatText" then
                if CombatTextFont then
                    SetFont(CombatTextFont, RefineUI.Media.Fonts.Pixel, 25, "OUTLINE")
                end
            end
        end)
    end

    if type(RefineUI.RegisterStartupCallback) == "function" then
        RefineUI:RegisterStartupCallback(key, startup, priority)
        return
    end

    -- Lifecycle.lua may not be loaded yet; seed the startup queue directly.
    RefineUI.StartupCallbacks = RefineUI.StartupCallbacks or {}
    if RefineUI.StartupCallbacks[key] then return end

    RefineUI.StartupCallbackOrder = (RefineUI.StartupCallbackOrder or 0) + 1
    RefineUI.StartupCallbacks[key] = {
        key = key,
        fn = startup,
        priority = priority,
        order = RefineUI.StartupCallbackOrder,
    }
end

RegisterFontsStartup()
