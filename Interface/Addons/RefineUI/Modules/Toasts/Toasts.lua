----------------------------------------------------------------------------------------
-- RefineUI Toasts
-- Description: Styles Blizzard alert toasts and injects custom RefineUI toasts.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local Module = RefineUI:RegisterModule("Toasts")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local select = select
local lower = string.lower
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_AddOns = C_AddOns
local C_Container = C_Container
local C_Timer = C_Timer
local C_CurrencyInfo = C_CurrencyInfo
local C_Garrison = C_Garrison
local C_HousingCatalog = C_HousingCatalog
local C_Item = C_Item
local C_LegendaryCrafting = C_LegendaryCrafting
local C_MountJournal = C_MountJournal
local C_PerksActivities = C_PerksActivities
local C_PetJournal = C_PetJournal
local C_QuestLog = C_QuestLog
local C_Spell = C_Spell
local C_ToyBox = C_ToyBox
local C_TradeSkillUI = C_TradeSkillUI
local C_TransmogCollection = C_TransmogCollection
local C_WarbandScene = C_WarbandScene
local GetMoney = GetMoney
local GetMoneyString = GetMoneyString
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local UnitClass = UnitClass
local BreakUpLargeNumbers = BreakUpLargeNumbers
local PlaySound = PlaySound
local ToggleCharacter = ToggleCharacter

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local MOVER_FRAME_NAME = "RefineUI_ToastAnchor"
local CUSTOM_TOAST_TEMPLATE = "RefineUIToastAlertFrameTemplate"
local TOAST_STATE_REGISTRY = "ToastsState"

local ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_02"
local CLICK_ACTION_TOKEN_FRAME = "token_frame"
local TOAST_TEST_COMMAND = "toasttest"
local TOAST_TEST_INTERVAL_SECONDS = 1
local NORMALIZED_TOAST_WIDTH = 224
local NORMALIZED_TOAST_HEIGHT = 48
local TOAST_ICON_SIZE = 42
local TOAST_ICON_OFFSET_X = 3
local TOAST_ICON_OFFSET_Y = -3
local TOAST_TEXT_LEFT = 50
local TOAST_TEXT_RIGHT = -4
local TOAST_TITLE_TOP = -2
local TOAST_TITLE_HEIGHT = 14
local TOAST_BODY_BOTTOM = 2
local TOAST_BODY_HEIGHT = 28
local TOAST_STACK_SPACING = 14
local TOAST_TITLE_COLOR_R = 1
local TOAST_TITLE_COLOR_G = 0.82
local TOAST_TITLE_COLOR_B = 0
local TOAST_COLOR_MATCH_EPSILON = 0.08

local COLOR_REFINED_GOLD = { 1, 0.82, 0 }
local COLOR_ACHIEVEMENT = { 1, 0.675, 0.125 }
local COLOR_MONEY = { 0.9, 0.75, 0.26 }
local COLOR_ARCHAEOLOGY = { 0.9, 0.4, 0.1 }
local COLOR_TRANSMOG = { 1, 0.5, 1 }

local TOAST_SOURCE_SPECIAL_COLORS = {
    AchievementAlertFrame_SetUp = COLOR_ACHIEVEMENT,
    CriteriaAlertFrame_SetUp = COLOR_ACHIEVEMENT,
    MoneyWonAlertFrame_SetUp = COLOR_MONEY,
    DigsiteCompleteToastFrame_SetUp = COLOR_ARCHAEOLOGY,
    NewCosmeticAlertFrameSystem_SetUp = COLOR_TRANSMOG,
    MonthlyActivityAlertFrame_SetUp = COLOR_REFINED_GOLD,
    InitiativeTaskCompleteAlertFrameSystem_SetUp = COLOR_REFINED_GOLD,
}

local BLIZZARD_TOAST_SETUPS = {
    "GuildChallengeAlertFrame_SetUp",
    "DungeonCompletionAlertFrame_SetUp",
    "ScenarioAlertFrame_SetUp",
    "ScenarioLegionInvasionAlertFrame_SetUp",
    "AchievementAlertFrame_SetUp",
    "CriteriaAlertFrame_SetUp",
    "LootWonAlertFrame_SetUp",
    "LootUpgradeFrame_SetUp",
    "MoneyWonAlertFrame_SetUp",
    "HonorAwardedAlertFrame_SetUp",
    "DigsiteCompleteToastFrame_SetUp",
    "EntitlementDeliveredAlertFrame_SetUp",
    "RafRewardDeliveredAlertFrame_SetUp",
    "GarrisonBuildingAlertFrame_SetUp",
    "GarrisonMissionAlertFrame_SetUp",
    "GarrisonRandomMissionAlertFrame_SetUp",
    "GarrisonCommonFollowerAlertFrame_SetUp",
    "GarrisonFollowerAlertFrame_SetUp",
    "GarrisonShipFollowerAlertFrame_SetUp",
    "GarrisonTalentAlertFrame_SetUp",
    "WorldQuestCompleteAlertFrame_SetUp",
    "LegendaryItemAlertFrame_SetUp",
    "NewRecipeLearnedAlertFrame_SetUp",
    "NewPetAlertFrame_SetUp",
    "NewMountAlertFrame_SetUp",
    "NewToyAlertFrame_SetUp",
    "NewWarbandSceneAlertFrame_SetUp",
    "NewRuneforgePowerAlertSystem_SetUp",
    "NewCosmeticAlertFrameSystem_SetUp",
    "MonthlyActivityAlertFrame_SetUp",
    "GuildRenameAlertFrame_SetUp",
    "HousingItemEarnedAlertFrameSystem_SetUp",
    "InitiativeTaskCompleteAlertFrameSystem_SetUp",
}

local BLIZZARD_MIXIN_SETUPS = {
    { mixin = "ItemAlertFrameMixin", method = "SetUpDisplay" },
    { mixin = "SkillLineSpecsUnlockedAlertFrameMixin", method = "SetUp" },
}

local SUPPRESSED_TEXTURE_KEYS = {
    "Background",
    "Background2",
    "Background3",
    "StandardBackground",
    "FancyBackground",
    "ToastBackground",
    "PvPBackground",
    "RatedPvPBackground",
    "BGAtlas",
    "BaseQualityBorder",
    "UpgradeQualityBorder",
    "BorderGlow",
    "GuildBanner",
    "GuildBorder",
    "Watermark",
    "IconBorder",
    "raidArt",
    "dungeonArt",
    "EmblemBackground",
    "EmblemBorder",
    "GuildTabardBackground",
    "GuildTabardBorder",
    "Blank",
    "IconBG",
    "Border",
    "Glow",
    "LightRays",
    "LightRays2",
    "Sparkles",
    "LeafTL",
    "LeafL",
    "LeafBL",
    "LeafTR",
    "LeafBR",
    "Divider",
}

local SUPPRESSED_ANON_ATLAS = {
    ["Toast-Frame"] = true,
    ["Toast-IconBG"] = true,
    ["legioninvasion-Toast-Frame"] = true,
    ["Garr_Toast"] = true,
    ["Garr_MissionToast"] = true,
    ["recipetoast-bg"] = true,
    ["communities-guildbanner-background"] = true,
    ["communities-guildbanner-border"] = true,
    ["housing-item-toast-background"] = true,
    ["housing-item-toast-frame"] = true,
    ["housing-item-toast-leaf01"] = true,
    ["housing-item-toast-leaf02"] = true,
    ["housing-item-toast-leaf03"] = true,
    ["housing-item-toast-leaf04"] = true,
    ["housing-item-toast-leaf06"] = true,
    ["housing-item-toast-divider"] = true,
    ["housing-item-toast-glow"] = true,
    ["housing-item-toast-lightrays01"] = true,
    ["housing-item-toast-lightrays02"] = true,
    ["housing-item-toast-sparkles-flipbook"] = true,
}

local SUPPRESSED_TEXTURE_PATTERNS = {
    "interface\\guildframe\\guildchallenges",
    "interface\\archeology\\archeologytoast",
    "interface\\achievementframe\\ui-achievement-alert-glow",
    "interface\\lootframe\\loottoast",
}

RefineUI:CreateDataRegistry(TOAST_STATE_REGISTRY, "k")

local function GetState(owner, key, defaultValue)
    return RefineUI:RegistryGet(TOAST_STATE_REGISTRY, owner, key, defaultValue)
end

local function SetState(owner, key, value)
    RefineUI:RegistrySet(TOAST_STATE_REGISTRY, owner, key, value)
end

local function GetConfig()
    local cfg = RefineUI.Config and RefineUI.Config.Toasts
    if type(cfg) ~= "table" then
        RefineUI.Config.Toasts = {}
        cfg = RefineUI.Config.Toasts
    end

    if cfg.SkinBlizzard == nil then
        cfg.SkinBlizzard = true
    end
    if cfg.ShowCurrency == nil then
        cfg.ShowCurrency = true
    end
    if cfg.ShowMoney == nil then
        cfg.ShowMoney = true
    end
    if cfg.ShowNegative == nil then
        cfg.ShowNegative = true
    end

    cfg.MinimumCurrencyChange = tonumber(cfg.MinimumCurrencyChange) or 1
    if cfg.MinimumCurrencyChange < 1 then
        cfg.MinimumCurrencyChange = 1
    end

    local moneyThreshold = tonumber(cfg.MinimumMoneyChange)
    if moneyThreshold == nil then
        moneyThreshold = 1
    end

    -- Legacy migration: early Toasts builds defaulted this to 10000 (1g), which hid small coin loot.
    if moneyThreshold == 10000 and cfg._moneyThresholdMigrated ~= true then
        moneyThreshold = 1
        cfg._moneyThresholdMigrated = true
    end

    if moneyThreshold < 1 then
        moneyThreshold = 1
    end
    cfg.MinimumMoneyChange = moneyThreshold

    return cfg
end

local function ResolveColorTriplet(color, fallbackR, fallbackG, fallbackB, fallbackA)
    if type(color) == "table" then
        if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
            return color.r, color.g, color.b, color.a or fallbackA
        end

        return color[1] or fallbackR, color[2] or fallbackG, color[3] or fallbackB, color[4] or fallbackA
    end

    return fallbackR, fallbackG, fallbackB, fallbackA
end

local function GetDefaultToastBorderColor()
    local bordersModule = RefineUI.Borders
    if bordersModule and type(bordersModule.GetDefaultBorderColor) == "function" then
        local r, g, b, a = bordersModule:GetDefaultBorderColor()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, a or 1
        end
    end

    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    return ResolveColorTriplet(color, 0.6, 0.6, 0.6, 1)
end

local function NormalizeQuality(quality)
    if type(quality) ~= "number" then
        return nil
    end

    quality = floor(quality + 0.5)
    if quality < 0 or quality > 8 then
        return nil
    end

    return quality
end

local function GetQualityBorderColor(quality)
    quality = NormalizeQuality(quality)
    if not quality then
        return nil
    end

    local bordersModule = RefineUI.Borders
    if bordersModule and type(bordersModule.GetQualityColor) == "function" then
        local r, g, b, a = bordersModule:GetQualityColor(quality)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, a or 1
        end
    end

    local color = RefineUI.Colors and RefineUI.Colors.Quality and RefineUI.Colors.Quality[quality]
    if color and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b, color.a or 1
    end

    if type(GetItemQualityColor) == "function" then
        local r, g, b = GetItemQualityColor(quality)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, 1
        end
    end

    local fallback = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if fallback and type(fallback.r) == "number" and type(fallback.g) == "number" and type(fallback.b) == "number" then
        return fallback.r, fallback.g, fallback.b, 1
    end

    return nil
end

local function GetItemQualityFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    local _, _, quality = GetItemInfo(itemLink)
    return NormalizeQuality(quality)
end

local function GetItemQualityFromID(itemID)
    if type(itemID) ~= "number" then
        return nil
    end

    local _, _, quality = GetItemInfo(itemID)
    return NormalizeQuality(quality)
end

local function ColorsClose(r, g, b, tr, tg, tb, epsilon)
    local e = epsilon or TOAST_COLOR_MATCH_EPSILON
    return abs((r or 0) - (tr or 0)) <= e
        and abs((g or 0) - (tg or 0)) <= e
        and abs((b or 0) - (tb or 0)) <= e
end

local function MatchColorToItemQuality(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end

    for quality = 0, 8 do
        local qr, qg, qb = GetQualityBorderColor(quality)
        if qr and ColorsClose(r, g, b, qr, qg, qb, TOAST_COLOR_MATCH_EPSILON) then
            return quality
        end
    end

    return nil
end

local function MatchColorToWorldQuestQuality(r, g, b)
    local qualityTable = _G.WORLD_QUEST_QUALITY_COLORS
    if type(qualityTable) ~= "table" then
        return nil
    end

    for quality, color in pairs(qualityTable) do
        if type(quality) == "number" and type(color) == "table" and ColorsClose(r, g, b, color.r, color.g, color.b, TOAST_COLOR_MATCH_EPSILON) then
            return quality
        end
    end

    return nil
end

local function IsCoinTexture(iconTexture)
    if not iconTexture or type(iconTexture.GetTexture) ~= "function" then
        return false
    end

    local texture = iconTexture:GetTexture()
    if type(texture) ~= "string" then
        return false
    end

    local normalized = lower(texture:gsub("/", "\\"))
    return normalized:find("inv_misc_coin_", 1, true) ~= nil
end

local function SetToastContext(frame, context)
    if not frame then
        return
    end

    SetState(frame, "toastContext", context)
end

local function GetToastContext(frame)
    if not frame then
        return nil
    end

    return GetState(frame, "toastContext")
end

local function CaptureSetupContext(frame, source, ...)
    if not frame then
        return
    end

    local a1, _, _, a4, a5, a6 = ...
    local context = {
        source = source,
    }

    if source == "LootWonAlertFrame_SetUp" then
        context.itemLink = a1
    elseif source == "LootUpgradeFrame_SetUp" then
        context.itemLink = a1
        context.baseQuality = NormalizeQuality(a5)
    elseif source == "LegendaryItemAlertFrame_SetUp" then
        context.itemLink = a1
        context.itemQuality = 5
    elseif source == "GarrisonFollowerAlertFrame_SetUp" then
        context.followerID = a1
        context.quality = NormalizeQuality(a4)
    elseif source == "GarrisonCommonFollowerAlertFrame_SetUp" then
        context.followerID = a1
        context.quality = NormalizeQuality(a4)
    elseif source == "GarrisonShipFollowerAlertFrame_SetUp" then
        context.followerID = a1
        context.quality = NormalizeQuality(a6)
    elseif source == "GarrisonMissionAlertFrame_SetUp" or source == "GarrisonRandomMissionAlertFrame_SetUp" then
        if type(a1) == "table" and a1.isRare then
            context.itemQuality = 3
        end
    elseif source == "WorldQuestCompleteAlertFrame_SetUp" then
        if type(a1) == "table" then
            context.questID = a1.questID
            context.questQuality = NormalizeQuality(a1.quality)
        else
            context.questID = a1
        end
    elseif source == "EntitlementDeliveredAlertFrame_SetUp" or source == "RafRewardDeliveredAlertFrame_SetUp" then
        context.entitlementType = a1
        context.payloadID = a4
    elseif source == "NewPetAlertFrame_SetUp" then
        context.petID = a1
    elseif source == "NewToyAlertFrame_SetUp" then
        context.toyID = a1
    elseif source == "NewWarbandSceneAlertFrame_SetUp" then
        context.warbandSceneID = a1
    elseif source == "NewRuneforgePowerAlertSystem_SetUp" then
        context.runeforgePowerID = a1
        context.itemQuality = 5
    elseif source == "NewCosmeticAlertFrameSystem_SetUp" then
        context.transmogSourceID = a1
    elseif source == "ItemAlertFrameMixin:SetUpDisplay" then
        context.itemLink = a1
        context.baseQuality = NormalizeQuality(a5)
    end

    SetToastContext(frame, context)
end

local function ResolveDefaultPosition()
    local defaultPoint, defaultX, defaultY = "TOP", 0, -120
    local pos = RefineUI.Positions and RefineUI.Positions[MOVER_FRAME_NAME]
    if type(pos) == "table" then
        defaultPoint = pos[1] or defaultPoint
        defaultX = tonumber(pos[4]) or defaultX
        defaultY = tonumber(pos[5]) or defaultY
    end

    return {
        point = defaultPoint,
        x = defaultX,
        y = defaultY,
    }
end

local function SavePosition(point, x, y)
    local cfg = GetConfig()
    cfg.Position = {
        point or "TOP",
        "UIParent",
        point or "TOP",
        x or 0,
        y or 0,
    }
end

local function ApplyStoredPosition(frame)
    if not frame then
        return
    end

    local cfg = GetConfig()
    local defaultPos = ResolveDefaultPosition()
    local pos = cfg.Position or (RefineUI.Positions and RefineUI.Positions[MOVER_FRAME_NAME])

    frame:ClearAllPoints()
    if type(pos) == "table" then
        local point, relativeTo, relativePoint, x, y = unpack(pos)
        local anchor = (type(relativeTo) == "string" and _G[relativeTo]) or relativeTo or UIParent
        frame:SetPoint(point or defaultPos.point, anchor, relativePoint or point or defaultPos.point, x or defaultPos.x, y or defaultPos.y)
    else
        frame:SetPoint(defaultPos.point, UIParent, defaultPos.point, defaultPos.x, defaultPos.y)
    end
end

local function EnsureMover()
    if Module.Mover then
        ApplyStoredPosition(Module.Mover)
        return Module.Mover
    end

    local mover = _G[MOVER_FRAME_NAME]
    if not mover then
        mover = CreateFrame("Frame", MOVER_FRAME_NAME, UIParent)
    end

    RefineUI.Size(mover, NORMALIZED_TOAST_WIDTH, NORMALIZED_TOAST_HEIGHT)
    mover:SetFrameStrata("DIALOG")
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)
    mover:SetAlpha(0)
    mover:Show()

    ApplyStoredPosition(mover)
    Module.Mover = mover

    return mover
end

local function ApplyAlertFrameAnchor()
    local alertFrame = _G.AlertFrame
    if not alertFrame or type(alertFrame.SetBaseAnchorFrame) ~= "function" then
        return
    end

    local mover = EnsureMover()
    alertFrame:SetBaseAnchorFrame(mover)
    alertFrame:UpdateAnchors()
end

local function RegisterMoverInEditMode()
    if Module.EditModeRegistered then
        return
    end

    local lib = RefineUI.LibEditMode
    if not lib or type(lib.AddFrame) ~= "function" then
        return
    end

    local mover = EnsureMover()
    local defaultPos = ResolveDefaultPosition()

    lib:AddFrame(mover, function(_, _, point, x, y)
        SavePosition(point, x, y)
        ApplyStoredPosition(mover)
        ApplyAlertFrameAnchor()
    end, defaultPos, "Toasts")

    Module.EditModeRegistered = true
end

local function InstallQueueSpacingHook()
    if Module.QueueSpacingHooked then
        return
    end

    local queueMixin = _G.AlertFrameQueueMixin
    if type(queueMixin) ~= "table" or type(queueMixin.AdjustAnchors) ~= "function" then
        return
    end

    RefineUI:HookOnce("Toasts:AlertFrameQueueMixin:AdjustAnchors", queueMixin, "AdjustAnchors", function(self, relativeAlert)
        if not self.alertFramePool or type(self.alertFramePool.EnumerateActive) ~= "function" then
            return
        end

        for alertFrame in self.alertFramePool:EnumerateActive() do
            alertFrame:ClearAllPoints()
            alertFrame:SetPoint("BOTTOM", relativeAlert, "TOP", 0, TOAST_STACK_SPACING)
            relativeAlert = alertFrame
        end
    end)

    Module.QueueSpacingHooked = true
end

local function EnsureAchievementUIFunctionsLoaded()
    if type(_G.AchievementShield_OnLoad) == "function" then
        return true
    end

    if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" and type(C_AddOns.LoadAddOn) == "function" then
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
        end
    else
        local loadAddOn = _G.UIParentLoadAddOn or _G.LoadAddOn
        if type(loadAddOn) == "function" then
            pcall(loadAddOn, "Blizzard_AchievementUI")
        end
    end

    return type(_G.AchievementShield_OnLoad) == "function"
end

local function StyleFontString(fontString, size)
    if not fontString or type(fontString.GetFont) ~= "function" then
        return
    end
    RefineUI.Font(fontString, size or 12)
end

local function NormalizeText(value)
    if type(value) ~= "string" then
        return nil
    end

    local text = value:match("^%s*(.-)%s*$")
    if text == "" then
        return nil
    end

    return text
end

local function GetFontStringText(fontString)
    if not fontString or type(fontString.GetText) ~= "function" then
        return nil
    end

    return NormalizeText(fontString:GetText())
end

local function GetFontStringColor(fontString)
    if not fontString or type(fontString.GetTextColor) ~= "function" then
        return nil
    end

    local r, g, b = fontString:GetTextColor()
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end

    return r, g, b
end

local function SuppressFontString(fontString)
    if not fontString then
        return
    end

    fontString:SetAlpha(0)
    fontString:Hide()

    if type(fontString.HookScript) == "function" and not GetState(fontString, "showSuppressed", false) then
        fontString:HookScript("OnShow", fontString.Hide)
        SetState(fontString, "showSuppressed", true)
    end
end

local function SuppressTexture(texture)
    if not texture then
        return
    end

    texture:SetAlpha(0)
    texture:Hide()

    if type(texture.HookScript) == "function" and not GetState(texture, "showSuppressed", false) then
        texture:HookScript("OnShow", texture.Hide)
        SetState(texture, "showSuppressed", true)
    end
end

local function ShouldSuppressAnonymousTexture(texture)
    if not texture then
        return false
    end

    if type(texture.GetAtlas) == "function" then
        local atlas = texture:GetAtlas()
        if atlas and SUPPRESSED_ANON_ATLAS[atlas] then
            return true
        end
    end

    if type(texture.GetTexture) == "function" then
        local value = texture:GetTexture()
        if type(value) == "string" then
            value = value:gsub("/", "\\"):lower()
            for i = 1, #SUPPRESSED_TEXTURE_PATTERNS do
                if value:find(SUPPRESSED_TEXTURE_PATTERNS[i], 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function ResolveTextureCandidate(candidate)
    if not candidate then
        return nil, nil
    end

    if type(candidate.GetObjectType) == "function" and candidate:GetObjectType() == "Texture" then
        return candidate, candidate
    end

    if type(candidate) ~= "table" then
        return nil, nil
    end

    local texture = candidate.Texture or candidate.Icon or candidate.Portrait
    if texture and type(texture.GetObjectType) == "function" and texture:GetObjectType() == "Texture" then
        return texture, candidate
    end

    if type(candidate.GetRegions) == "function" then
        local regionCount = select("#", candidate:GetRegions())
        for i = 1, regionCount do
            local region = select(i, candidate:GetRegions())
            if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
                return region, candidate
            end
        end
    end

    return nil, nil
end

local function IsLikelyIconTexture(texture)
    if not texture or type(texture.GetObjectType) ~= "function" or texture:GetObjectType() ~= "Texture" then
        return false
    end

    if ShouldSuppressAnonymousTexture(texture) then
        return false
    end

    if type(texture.GetWidth) ~= "function" or type(texture.GetHeight) ~= "function" then
        return false
    end

    local width = texture:GetWidth() or 0
    local height = texture:GetHeight() or 0
    if width < 20 or height < 20 then
        return false
    end
    if width > 96 or height > 96 then
        return false
    end

    return true
end

local function FindFallbackIconTexture(frame, depth)
    if not frame then
        return nil, nil
    end

    depth = depth or 0
    if depth > 2 then
        return nil, nil
    end

    if type(frame.GetRegions) == "function" then
        local regionCount = select("#", frame:GetRegions())
        for i = 1, regionCount do
            local region = select(i, frame:GetRegions())
            if IsLikelyIconTexture(region) then
                return region, region
            end
        end
    end

    if type(frame.GetChildren) == "function" then
        local childCount = select("#", frame:GetChildren())
        for i = 1, childCount do
            local child = select(i, frame:GetChildren())
            if child and child ~= frame then
                local texture, owner = FindFallbackIconTexture(child, depth + 1)
                if texture then
                    return texture, owner
                end
            end
        end
    end

    return nil, nil
end

local function ResolveIconTexture(frame)
    if not frame then
        return nil, nil
    end

    local iconTexture, iconOwner = ResolveTextureCandidate(frame.Icon)
    if iconTexture then
        return iconTexture, iconOwner
    end

    if frame.lootItem then
        iconTexture, iconOwner = ResolveTextureCandidate(frame.lootItem.Icon)
        if iconTexture then
            return iconTexture, iconOwner
        end
    end

    local fallbackCandidates = {
        frame.EmblemIcon,
        frame.DigsiteTypeTexture,
        frame.Banner,
        frame.GuildTabardEmblem,
        frame.MissionType,
        frame.PortraitFrame and frame.PortraitFrame.Portrait,
    }

    for i = 1, #fallbackCandidates do
        iconTexture, iconOwner = ResolveTextureCandidate(fallbackCandidates[i])
        if iconTexture then
            return iconTexture, iconOwner
        end
    end

    return FindFallbackIconTexture(frame, 0)
end

local function TryCropIconTexture(iconTexture)
    if not iconTexture or type(iconTexture.SetTexCoord) ~= "function" then
        return
    end

    if type(iconTexture.GetNumMaskTextures) == "function" then
        local ok, maskCount = pcall(iconTexture.GetNumMaskTextures, iconTexture)
        if ok and type(maskCount) == "number" and maskCount > 0 then
            return
        end
    end

    if type(iconTexture.GetAtlas) == "function" then
        local atlas = iconTexture:GetAtlas()
        if atlas and atlas ~= "" then
            return
        end
    end

    pcall(iconTexture.SetTexCoord, iconTexture, 0.08, 0.92, 0.08, 0.92)
end

local function NormalizeIconLayout(frame, iconTexture, iconOwner)
    if not frame or not iconTexture then
        return
    end

    if iconOwner and iconOwner ~= iconTexture and type(iconOwner.ClearAllPoints) == "function" then
        iconOwner:ClearAllPoints()
        if type(iconOwner.SetPoint) == "function" then
            iconOwner:SetPoint("TOPLEFT", frame, "TOPLEFT", TOAST_ICON_OFFSET_X, TOAST_ICON_OFFSET_Y)
        end
        if type(iconOwner.SetSize) == "function" then
            iconOwner:SetSize(TOAST_ICON_SIZE, TOAST_ICON_SIZE)
        end
    end

    if type(iconTexture.ClearAllPoints) == "function" then
        iconTexture:ClearAllPoints()
    end

    if iconOwner and iconOwner ~= iconTexture and type(iconOwner.GetObjectType) == "function" and iconOwner:GetObjectType() ~= "Texture" then
        iconTexture:SetPoint("TOPLEFT", iconOwner, "TOPLEFT", 0, 0)
        iconTexture:SetPoint("BOTTOMRIGHT", iconOwner, "BOTTOMRIGHT", 0, 0)
    else
        iconTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", TOAST_ICON_OFFSET_X, TOAST_ICON_OFFSET_Y)
        iconTexture:SetSize(TOAST_ICON_SIZE, TOAST_ICON_SIZE)
    end

    TryCropIconTexture(iconTexture)
end

local function EnsureIconBorder(frame, iconTexture, stateKey)
    if not frame or not iconTexture then
        return
    end

    if type(iconTexture.GetObjectType) ~= "function" or iconTexture:GetObjectType() ~= "Texture" then
        return
    end

    local key = stateKey or "iconBorder"
    local border = GetState(frame, key)
    if not border then
        border = CreateFrame("Frame", nil, frame)
        RefineUI.SetTemplate(border, "Icon")
        SetState(frame, key, border)
    end

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 3, -3)
    border:SetFrameStrata(frame:GetFrameStrata())
    border:SetFrameLevel((frame:GetFrameLevel() or 1) + 6)
    border:Show()

    TryCropIconTexture(iconTexture)
end

local TITLE_TEXT_KEYS = {
    "Title",
    "Label",
    "HeaderLabel",
    "completionText",
    "TitleText",
    "Unlocked",
    "CollectedLabel",
    "CompletedLabel",
}

local BODY_TEXT_KEYS = {
    "Name",
    "ItemName",
    "GuildName",
    "Amount",
    "Type",
    "Count",
    "QuestName",
    "MissionName",
    "DigsiteType",
    "TaskName",
    "DecorType",
    "DecorName",
    "instanceName",
    "dungeonName",
    "ZoneName",
    "WhiteText",
    "WhiteText2",
    "BaseQualityItemName",
    "UpgradeQualityItemName",
    "RollValue",
}

local function FirstTextByKeys(frame, keys)
    for i = 1, #keys do
        local fontString = frame[keys[i]]
        local text = GetFontStringText(fontString)
        if text then
            return text, fontString
        end
    end

    return nil, nil
end

local function JoinTextParts(a, b)
    local aText = NormalizeText(a)
    local bText = NormalizeText(b)
    if aText and bText then
        return aText .. "  " .. bText
    end

    return aText or bText
end

local function ResolveUnifiedText(frame)
    if frame and frame.Type and frame.Count and frame.EmblemIcon then
        return NormalizeText(_G.GUILD_CHALLENGE_LABEL) or "Guild Challenge", JoinTextParts(GetFontStringText(frame.Type), GetFontStringText(frame.Count)), frame.Type
    end

    if frame and frame._refineClickAction then
        local label = GetFontStringText(frame.Label)
        local name = GetFontStringText(frame.Name)
        local amount = GetFontStringText(frame.Amount)
        return label, JoinTextParts(name, amount), frame.Amount or frame.Name
    end

    if frame and frame.completionText and frame.instanceName then
        return GetFontStringText(frame.completionText), GetFontStringText(frame.instanceName), frame.instanceName
    end

    if frame and frame.CollectedLabel and frame.DecorName then
        return GetFontStringText(frame.CollectedLabel), GetFontStringText(frame.DecorName), frame.DecorName
    end

    if frame and frame.CompletedLabel and frame.TaskName then
        return GetFontStringText(frame.CompletedLabel), GetFontStringText(frame.TaskName), frame.TaskName
    end

    local titleText = nil
    local titleSource = nil
    local bodyText = nil
    local bodySource = nil

    if frame then
        titleText, titleSource = FirstTextByKeys(frame, TITLE_TEXT_KEYS)
        bodyText, bodySource = FirstTextByKeys(frame, BODY_TEXT_KEYS)
    end

    if not titleText then
        titleText = bodyText or ""
        titleSource = bodySource
        bodyText = ""
        bodySource = nil
    end

    return titleText or "", bodyText or "", bodySource or titleSource
end

local function EnsureUnifiedTextFields(frame)
    local title = GetState(frame, "unifiedTitle")
    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", nil, 20)
        SetState(frame, "unifiedTitle", title)
    end

    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", TOAST_TEXT_LEFT, TOAST_TITLE_TOP)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", TOAST_TEXT_RIGHT, TOAST_TITLE_TOP)
    title:SetHeight(TOAST_TITLE_HEIGHT)
    title:SetJustifyH("CENTER")
    title:SetJustifyV("MIDDLE")
    title:SetWordWrap(false)
    StyleFontString(title, 11)

    local body = GetState(frame, "unifiedBody")
    if not body then
        body = frame:CreateFontString(nil, "OVERLAY", nil, 20)
        SetState(frame, "unifiedBody", body)
    end

    body:ClearAllPoints()
    body:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", TOAST_TEXT_LEFT, TOAST_BODY_BOTTOM)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", TOAST_TEXT_RIGHT, TOAST_BODY_BOTTOM)
    body:SetHeight(TOAST_BODY_HEIGHT)
    body:SetJustifyH("CENTER")
    body:SetJustifyV("MIDDLE")
    body:SetMaxLines(2)
    body:SetWordWrap(true)
    StyleFontString(body, 12)

    return title, body
end

local function ResolveContextQuality(frame, context)
    local directCandidates = {
        context and context.itemQuality,
        context and context.quality,
        context and context.questQuality,
        frame and frame.itemQuality,
        frame and frame.quality,
        frame and frame.rarity,
        frame and frame.itemRarity,
        frame and frame.lootItem and frame.lootItem.itemQuality,
    }

    for i = 1, #directCandidates do
        local quality = NormalizeQuality(directCandidates[i])
        if quality then
            return quality
        end
    end

    if context then
        local quality = GetItemQualityFromLink(context.itemLink)
        if quality then
            return quality
        end

        quality = GetItemQualityFromID(context.itemID)
        if quality then
            return quality
        end

        quality = NormalizeQuality(context.baseQuality)
        if quality then
            return quality
        end

        if context.source == "EntitlementDeliveredAlertFrame_SetUp" or context.source == "RafRewardDeliveredAlertFrame_SetUp" then
            quality = GetItemQualityFromID(context.payloadID)
            if quality then
                return quality
            end
        end

        if context.questID and type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestTagInfo) == "function" then
            local info = C_QuestLog.GetQuestTagInfo(context.questID)
            quality = NormalizeQuality(info and info.quality)
            if quality then
                return quality
            end
        end

        if context.petID and type(C_PetJournal) == "table" and type(C_PetJournal.GetPetStats) == "function" then
            local _, _, _, _, rarity = C_PetJournal.GetPetStats(context.petID)
            quality = NormalizeQuality((rarity or 2) - 1)
            if quality then
                return quality
            end
        end

        if context.warbandSceneID and type(C_WarbandScene) == "table" and type(C_WarbandScene.GetWarbandSceneEntry) == "function" then
            local info = C_WarbandScene.GetWarbandSceneEntry(context.warbandSceneID)
            quality = NormalizeQuality(info and info.quality)
            if quality then
                return quality
            end
        end

        if context.toyID then
            quality = GetItemQualityFromID(context.toyID)
            if quality then
                return quality
            end
        end

        if context.transmogSourceID and type(C_TransmogCollection) == "table" and type(C_TransmogCollection.GetAppearanceSourceInfo) == "function" then
            local sourceInfo = C_TransmogCollection.GetAppearanceSourceInfo(context.transmogSourceID)
            quality = sourceInfo and GetItemQualityFromLink(sourceInfo.transmoglink) or nil
            if quality then
                return quality
            end
        end
    end

    local quality = frame and GetItemQualityFromLink(frame.itemLink) or nil
    if quality then
        return quality
    end

    return nil
end

local function ResolveQualityFromTextColor(fontString)
    local r, g, b = GetFontStringColor(fontString)
    if not r then
        return nil
    end

    local quality = MatchColorToItemQuality(r, g, b)
    if quality then
        return quality
    end

    return MatchColorToWorldQuestQuality(r, g, b)
end

local function ResolveEntitlementTransmogColor(context)
    if type(context) ~= "table" then
        return nil
    end

    if context.source ~= "EntitlementDeliveredAlertFrame_SetUp" and context.source ~= "RafRewardDeliveredAlertFrame_SetUp" then
        return nil
    end

    local entitlementType = context.entitlementType
    local entitlementEnum = Enum and Enum.WoWEntitlementType
    if type(entitlementType) ~= "number" or type(entitlementEnum) ~= "table" then
        return nil
    end

    if entitlementType == entitlementEnum.Appearance
        or entitlementType == entitlementEnum.AppearanceSet
        or entitlementType == entitlementEnum.Illusion
    then
        return COLOR_TRANSMOG[1], COLOR_TRANSMOG[2], COLOR_TRANSMOG[3], 1
    end

    return nil
end

local function ResolveToastBorderColor(frame, context, bodySource, iconTexture)
    if type(context) == "table" and context.borderColor ~= nil then
        local r, g, b, a = ResolveColorTriplet(context.borderColor, nil, nil, nil, 1)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, a or 1
        end
    end

    local source = type(context) == "table" and context.source or nil
    local special = source and TOAST_SOURCE_SPECIAL_COLORS[source]
    if special then
        return special[1], special[2], special[3], special[4] or 1
    end

    if type(context) == "table" and context.toastType == "money" then
        return COLOR_MONEY[1], COLOR_MONEY[2], COLOR_MONEY[3], 1
    end

    local transmogR, transmogG, transmogB, transmogA = ResolveEntitlementTransmogColor(context)
    if transmogR then
        return transmogR, transmogG, transmogB, transmogA
    end

    if source == "MoneyWonAlertFrame_SetUp" and IsCoinTexture(iconTexture) then
        return COLOR_MONEY[1], COLOR_MONEY[2], COLOR_MONEY[3], 1
    end

    local quality = ResolveContextQuality(frame, context)
    if not quality then
        quality = ResolveQualityFromTextColor(bodySource)
    end

    if quality then
        local r, g, b, a = GetQualityBorderColor(quality)
        if r then
            return r, g, b, a or 1
        end
    end

    if type(context) == "table" and context.toastType == "currency" then
        return COLOR_REFINED_GOLD[1], COLOR_REFINED_GOLD[2], COLOR_REFINED_GOLD[3], 1
    end

    return GetDefaultToastBorderColor()
end

local function ApplyBorderColor(borderFrame, r, g, b, a)
    if not borderFrame or type(borderFrame.SetBackdropBorderColor) ~= "function" then
        return
    end

    borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
end

local function ApplyToastBorderColor(frame, r, g, b, a)
    if not frame then
        return
    end

    ApplyBorderColor(frame.border, r, g, b, a)
    ApplyBorderColor(GetState(frame, "frameIconBorder"), r, g, b, a)
    ApplyBorderColor(GetState(frame, "lootItemIconBorder"), r, g, b, a)
end

local function BuildSuppressionMaps(frame, iconTexture)
    local allowedTextures = {}
    if iconTexture then
        allowedTextures[iconTexture] = true
    end
    if frame.bg then
        allowedTextures[frame.bg] = true
    end

    local skipFrames = {}
    if frame.border then
        skipFrames[frame.border] = true
    end

    local frameIconBorder = GetState(frame, "frameIconBorder")
    if frameIconBorder then
        skipFrames[frameIconBorder] = true
    end

    local lootItemIconBorder = GetState(frame, "lootItemIconBorder")
    if lootItemIconBorder then
        skipFrames[lootItemIconBorder] = true
    end

    return allowedTextures, skipFrames
end

local function SuppressFrameArt(frame, allowedTextures, keepFontStrings, skipFrames, depth)
    if not frame then
        return
    end

    depth = depth or 0
    if depth > 5 then
        return
    end

    if type(frame.GetRegions) == "function" then
        local regionCount = select("#", frame:GetRegions())
        for i = 1, regionCount do
            local region = select(i, frame:GetRegions())
            if region and type(region.GetObjectType) == "function" then
                local objectType = region:GetObjectType()
                if objectType == "Texture" then
                    if not allowedTextures[region] then
                        SuppressTexture(region)
                    end
                elseif objectType == "FontString" then
                    if not keepFontStrings[region] then
                        SuppressFontString(region)
                    end
                end
            end
        end
    end

    if type(frame.GetChildren) ~= "function" then
        return
    end

    local childCount = select("#", frame:GetChildren())
    for i = 1, childCount do
        local child = select(i, frame:GetChildren())
        if child and child ~= frame and not skipFrames[child] then
            SuppressFrameArt(child, allowedTextures, keepFontStrings, skipFrames, depth + 1)
        end
    end
end

function Module:StyleToastFrame(frame)
    if not frame then
        return
    end

    if not GetState(frame, "baseStyled", false) then
        RefineUI.SetTemplate(frame, "Transparent")
        SetState(frame, "baseStyled", true)
    end

    if not GetState(frame, "contextClearHooked", false) and type(frame.HookScript) == "function" then
        frame:HookScript("OnHide", function(self)
            SetToastContext(self, nil)
        end)
        SetState(frame, "contextClearHooked", true)
    end

    frame:SetSize(NORMALIZED_TOAST_WIDTH, NORMALIZED_TOAST_HEIGHT)

    local iconTexture, iconOwner = ResolveIconTexture(frame)
    NormalizeIconLayout(frame, iconTexture, iconOwner)
    EnsureIconBorder(frame, iconTexture, "frameIconBorder")
    if not iconTexture then
        local frameBorder = GetState(frame, "frameIconBorder")
        if frameBorder then
            frameBorder:Hide()
        end
    end

    if frame.lootItem then
        SuppressTexture(frame.lootItem.IconBorder)
        local lootTexture = select(1, ResolveTextureCandidate(frame.lootItem.Icon))
        if lootTexture and lootTexture ~= iconTexture then
            EnsureIconBorder(frame, lootTexture, "lootItemIconBorder")
        else
            local lootBorder = GetState(frame, "lootItemIconBorder")
            if lootBorder then
                lootBorder:Hide()
            end
        end
    end

    for _, key in ipairs(SUPPRESSED_TEXTURE_KEYS) do
        SuppressTexture(frame[key])
    end

    for i = 1, 5 do
        SuppressTexture(frame["Arrow" .. i])
    end

    if frame.Icon and type(frame.Icon) == "table" then
        SuppressTexture(frame.Icon.Overlay)
        SuppressTexture(frame.Icon.Bling)
    end

    if frame.glow then
        frame.glow.suppressGlow = true
        SuppressTexture(frame.glow)
    end
    if frame.glowFrame and frame.glowFrame.glow then
        SuppressTexture(frame.glowFrame.glow)
    end
    if frame.shine then
        SuppressTexture(frame.shine)
    end

    local titleText, bodyText, bodySource = ResolveUnifiedText(frame)
    local unifiedTitle, unifiedBody = EnsureUnifiedTextFields(frame)
    unifiedTitle:SetText(titleText or "")
    unifiedTitle:SetTextColor(TOAST_TITLE_COLOR_R, TOAST_TITLE_COLOR_G, TOAST_TITLE_COLOR_B)
    unifiedBody:SetText(bodyText or "")

    local bodyR, bodyG, bodyB = GetFontStringColor(bodySource)
    unifiedBody:SetTextColor(bodyR or 1, bodyG or 1, bodyB or 1)

    local context = GetToastContext(frame)
    local borderR, borderG, borderB, borderA = ResolveToastBorderColor(frame, context, bodySource, iconTexture)
    ApplyToastBorderColor(frame, borderR, borderG, borderB, borderA)

    local allowedTextures, skipFrames = BuildSuppressionMaps(frame, iconTexture)
    local keepFontStrings = {
        [unifiedTitle] = true,
        [unifiedBody] = true,
    }

    SuppressFrameArt(frame, allowedTextures, keepFontStrings, skipFrames, 0)

    if frame.Shield and frame.Shield.Points then
        StyleFontString(frame.Shield.Points, 11)
        frame.Shield.Points:SetTextColor(1, 1, 1)
    end
end

function Module:StyleActiveAlertFrames()
    local alertFrame = _G.AlertFrame
    if not alertFrame or type(alertFrame.alertFrameSubSystems) ~= "table" then
        return
    end

    for _, subSystem in ipairs(alertFrame.alertFrameSubSystems) do
        if type(subSystem) == "table" then
            if subSystem.alertFramePool and type(subSystem.alertFramePool.EnumerateActive) == "function" then
                for frame in subSystem.alertFramePool:EnumerateActive() do
                    self:StyleToastFrame(frame)
                end
            elseif subSystem.alertFrame then
                self:StyleToastFrame(subSystem.alertFrame)
            end
        end
    end
end

local function OpenTokenFrame()
    if type(ToggleCharacter) == "function" then
        ToggleCharacter("TokenFrame")
    end
end

local function RefineToastFrame_OnClick(self, button, down)
    if _G.AlertFrame_OnClick and _G.AlertFrame_OnClick(self, button, down) then
        return
    end

    if self._refineClickAction == CLICK_ACTION_TOKEN_FRAME then
        OpenTokenFrame()
    end
end

local function RefineCustomToast_SetUp(frame, data)
    if type(data) ~= "table" or not data.icon then
        return false
    end

    frame.Icon:SetTexture(data.icon)
    frame.Icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    frame.Label:SetText(data.label or "")
    frame.Name:SetText(data.name or "")
    frame.Amount:SetText(data.amountText or "")

    local amountColor = data.amountColor
    if type(amountColor) == "table" then
        frame.Amount:SetTextColor(amountColor[1] or 1, amountColor[2] or 1, amountColor[3] or 1)
    else
        frame.Amount:SetTextColor(1, 1, 1)
    end

    frame._refineClickAction = data.clickAction
    SetToastContext(frame, {
        source = "RefineCustomToast",
        toastType = data.toastType,
        borderColor = data.borderColor,
        itemQuality = NormalizeQuality(data.itemQuality),
        itemLink = data.itemLink,
        itemID = data.itemID,
        currencyID = data.currencyID,
    })

    if not GetState(frame, "customClickBound", false) then
        frame:SetScript("OnClick", RefineToastFrame_OnClick)
        SetState(frame, "customClickBound", true)
    end

    Module:StyleToastFrame(frame)

    if data.soundKit and PlaySound then
        PlaySound(data.soundKit)
    end

    return true
end

function Module:EnsureCustomToastSystem()
    if self.CustomToastSystem then
        return
    end

    local alertFrame = _G.AlertFrame
    if not alertFrame or type(alertFrame.AddQueuedAlertFrameSubSystem) ~= "function" then
        return
    end

    self.CustomToastSystem = alertFrame:AddQueuedAlertFrameSubSystem(CUSTOM_TOAST_TEMPLATE, RefineCustomToast_SetUp, 4, 18)
end

local function FormatNumberDelta(value)
    local absolute = abs(value)
    local amountText = BreakUpLargeNumbers and BreakUpLargeNumbers(absolute) or tostring(absolute)
    if value > 0 then
        return "+" .. amountText, { 0.35, 1, 0.35 }
    end
    return "-" .. amountText, { 1, 0.35, 0.35 }
end

function Module:QueueCurrencyToast(currencyID, quantityChange)
    local cfg = GetConfig()
    if cfg.ShowCurrency == false then
        return
    end
    if quantityChange < 0 and cfg.ShowNegative == false then
        return
    end
    if abs(quantityChange) < (cfg.MinimumCurrencyChange or 1) then
        return
    end
    if not C_CurrencyInfo or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then
        return
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info or info.isHeader then
        return
    end

    self:EnsureCustomToastSystem()
    if not self.CustomToastSystem then
        return
    end

    local amountText, amountColor = FormatNumberDelta(quantityChange)
    local label = quantityChange > 0 and "Currency Gained" or "Currency Spent"

    self.CustomToastSystem:AddAlert({
        icon = info.iconFileID or ICON_COIN,
        label = label,
        name = info.name or CURRENCY,
        amountText = amountText,
        amountColor = amountColor,
        toastType = "currency",
        currencyID = currencyID,
        itemQuality = NormalizeQuality(info.quality),
        clickAction = CLICK_ACTION_TOKEN_FRAME,
        soundKit = SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or nil,
    })
end

function Module:QueueMoneyToast(delta)
    local cfg = GetConfig()
    if cfg.ShowMoney == false then
        return
    end
    if delta < 0 and cfg.ShowNegative == false then
        return
    end
    if abs(delta) < (cfg.MinimumMoneyChange or 0) then
        return
    end

    self:EnsureCustomToastSystem()
    if not self.CustomToastSystem then
        return
    end

    local label = delta > 0 and "Money Gained" or "Money Spent"
    local amountColor = delta > 0 and { 0.35, 1, 0.35 } or { 1, 0.35, 0.35 }
    local moneyText = GetMoneyString and GetMoneyString(abs(delta), true) or tostring(abs(delta))
    local amountText = (delta > 0 and "+" or "-") .. moneyText

    self.CustomToastSystem:AddAlert({
        icon = ICON_COIN,
        label = label,
        name = MONEY,
        amountText = amountText,
        amountColor = amountColor,
        toastType = "money",
        clickAction = CLICK_ACTION_TOKEN_FRAME,
        soundKit = SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or nil,
    })
end

function Module:OnCurrencyDisplayUpdate(_, currencyType, _, quantityChange)
    if type(currencyType) ~= "number" or type(quantityChange) ~= "number" or quantityChange == 0 then
        return
    end
    self:QueueCurrencyToast(currencyType, quantityChange)
end

function Module:OnPlayerMoney()
    local currentMoney = GetMoney and GetMoney() or 0
    local lastMoney = self.LastMoney
    self.LastMoney = currentMoney

    if type(lastMoney) ~= "number" then
        return
    end

    local delta = currentMoney - lastMoney
    if delta == 0 then
        return
    end

    self:QueueMoneyToast(delta)
end

function Module:RegisterCustomEvents()
    if self.EventsRegistered then
        return
    end

    RefineUI:RegisterEventCallback("CURRENCY_DISPLAY_UPDATE", function(...)
        Module:OnCurrencyDisplayUpdate(...)
    end, "Toasts:CURRENCY_DISPLAY_UPDATE")

    RefineUI:RegisterEventCallback("PLAYER_MONEY", function(...)
        Module:OnPlayerMoney(...)
    end, "Toasts:PLAYER_MONEY")

    self.EventsRegistered = true
end

local function TryAddAlert(systemName, ...)
    local system = _G[systemName]
    if type(system) ~= "table" or type(system.AddAlert) ~= "function" then
        return false, "system unavailable"
    end

    local ok, err = pcall(system.AddAlert, system, ...)
    if not ok then
        return false, err
    end

    return true
end

local function NormalizeReason(reason)
    if reason == nil then
        return "unknown error"
    end

    local text = tostring(reason)
    local firstLine = text:match("([^\r\n]+)")
    return firstLine or text
end

local function ExtractItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    return tonumber(itemLink:match("item:(%d+)"))
end

local function GetFirstBagItemLink()
    if type(C_Container) ~= "table" then
        return nil
    end

    local hasSlots = type(C_Container.GetContainerNumSlots) == "function"
    local hasInfo = type(C_Container.GetContainerItemInfo) == "function"
    local hasLink = type(C_Container.GetContainerItemLink) == "function"
    if not hasSlots or (not hasInfo and not hasLink) then
        return nil
    end

    for bagID = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bagID) or 0
        for slotID = 1, slots do
            if hasInfo then
                local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                if itemInfo and itemInfo.hyperlink then
                    return itemInfo.hyperlink
                end
            end

            if hasLink then
                local link = C_Container.GetContainerItemLink(bagID, slotID)
                if link then
                    return link
                end
            end
        end
    end

    return nil
end

local function GetTestItemLink()
    local bagLink = GetFirstBagItemLink()
    if bagLink then
        return bagLink
    end

    local fallbackIDs = { 6948, 171267, 122270, 19019 }
    for _, itemID in ipairs(fallbackIDs) do
        local name, link = nil, nil
        if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
            name, link = C_Item.GetItemInfo(itemID)
        elseif type(GetItemInfo) == "function" then
            name, link = GetItemInfo(itemID)
        end

        if name and link then
            return link
        end
    end

    return nil
end

local function GetTestCurrencyID()
    if type(C_CurrencyInfo) ~= "table" or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then
        return nil
    end

    local preferredIDs = { 2032, 1220, 1792, 824, 823, 1191, 777, 515 }
    for _, currencyID in ipairs(preferredIDs) do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.name and not info.isHeader then
            return currencyID
        end
    end

    if type(C_CurrencyInfo.GetCurrencyListSize) == "function" and type(C_CurrencyInfo.GetCurrencyListInfo) == "function" then
        local listSize = C_CurrencyInfo.GetCurrencyListSize() or 0
        for index = 1, listSize do
            local ok, entry = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
            if ok and type(entry) == "table" and type(entry.currencyTypesID) == "number" then
                local info = C_CurrencyInfo.GetCurrencyInfo(entry.currencyTypesID)
                if info and info.name and not info.isHeader then
                    return entry.currencyTypesID
                end
            end
        end
    end

    return nil
end

local function GetTestMountID()
    if type(C_MountJournal) ~= "table" or type(C_MountJournal.GetMountIDs) ~= "function" then
        return nil
    end

    local mountIDs = C_MountJournal.GetMountIDs()
    if type(mountIDs) ~= "table" then
        return nil
    end

    for i = 1, #mountIDs do
        local mountID = mountIDs[i]
        if type(C_MountJournal.GetMountInfoByID) == "function" then
            local name = C_MountJournal.GetMountInfoByID(mountID)
            if name then
                return mountID
            end
        else
            return mountID
        end
    end

    return nil
end

local function GetTestPetID()
    if type(C_PetJournal) ~= "table" or type(C_PetJournal.GetPetInfoByIndex) ~= "function" then
        return nil
    end

    local petID = C_PetJournal.GetPetInfoByIndex(1)
    return petID
end

local function GetTestToyID()
    if type(C_ToyBox) ~= "table" or type(C_ToyBox.GetToyFromIndex) ~= "function" then
        return nil
    end

    local toyCount = 50
    if type(C_ToyBox.GetNumFilteredToys) == "function" then
        toyCount = C_ToyBox.GetNumFilteredToys() or toyCount
    end

    for index = 1, toyCount do
        local itemID = C_ToyBox.GetToyFromIndex(index)
        if type(itemID) == "number" and itemID > 0 then
            return itemID
        end
    end

    return nil
end

local function GetTestWarbandSceneID()
    if type(C_WarbandScene) ~= "table" then
        return nil
    end
    if type(C_WarbandScene.GetRandomEntryID) ~= "function" then
        return nil
    end

    local sceneID = C_WarbandScene.GetRandomEntryID()
    if type(sceneID) ~= "number" then
        return nil
    end

    if type(C_WarbandScene.GetWarbandSceneEntry) == "function" then
        local info = C_WarbandScene.GetWarbandSceneEntry(sceneID)
        if not info then
            return nil
        end
    end

    return sceneID
end

local function GetTestRecipeID()
    if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.GetTradeSkillLineForRecipe) ~= "function" then
        return nil
    end

    local preferred = { 7183, 190992 }
    for _, recipeID in ipairs(preferred) do
        local tradeSkillID = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
        if tradeSkillID then
            return recipeID
        end
    end

    if type(C_TradeSkillUI.GetAllRecipeIDs) == "function" then
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if type(recipeIDs) == "table" then
            for i = 1, #recipeIDs do
                local recipeID = recipeIDs[i]
                if C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID) then
                    return recipeID
                end
            end
        end
    end

    return nil
end

local function GetTestSkillLineIDs()
    if type(C_TradeSkillUI) ~= "table" then
        return nil, nil
    end

    if type(C_TradeSkillUI.GetChildProfessionInfo) == "function" then
        local info = C_TradeSkillUI.GetChildProfessionInfo()
        if type(info) == "table" and type(info.professionID) == "number" then
            local tradeSkillID = info.parentProfessionID or info.professionID
            return info.professionID, tradeSkillID
        end
    end

    if type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local info = C_TradeSkillUI.GetBaseProfessionInfo()
        if type(info) == "table" and type(info.professionID) == "number" then
            return info.professionID, info.professionID
        end
    end

    if type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) == "function" then
        local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
        if type(skillLines) == "table" and type(skillLines[1]) == "number" then
            return skillLines[1], skillLines[1]
        end
    end

    return nil, nil
end

local function GetTestPerksActivityID()
    if type(C_PerksActivities) ~= "table" or type(C_PerksActivities.GetPerksActivityInfo) ~= "function" then
        return nil
    end

    local preferredID = 144
    local info = C_PerksActivities.GetPerksActivityInfo(preferredID)
    if info then
        return preferredID
    end

    for perksID = 1, 300 do
        info = C_PerksActivities.GetPerksActivityInfo(perksID)
        if info then
            return perksID
        end
    end

    return nil
end

local function GetTestRuneforgePowerID()
    if type(C_LegendaryCrafting) ~= "table" then
        return nil
    end

    if type(C_LegendaryCrafting.GetRuneforgePowerInfo) == "function" then
        local info = C_LegendaryCrafting.GetRuneforgePowerInfo(2)
        if info then
            return 2
        end
    end

    if type(C_LegendaryCrafting.GetRuneforgePowers) == "function" then
        local powers = C_LegendaryCrafting.GetRuneforgePowers()
        if type(powers) == "table" and type(powers[1]) == "number" then
            return powers[1]
        end
    end

    return nil
end

local function GetTestTransmogSourceID()
    if type(C_TransmogCollection) ~= "table" then
        return nil
    end
    if type(C_TransmogCollection.GetCategoryAppearances) ~= "function" or type(C_TransmogCollection.GetAppearanceSources) ~= "function" then
        return nil
    end

    for category = 1, 8 do
        local appearances = C_TransmogCollection.GetCategoryAppearances(category)
        if type(appearances) == "table" then
            for i = 1, #appearances do
                local appearance = appearances[i]
                local visualID = appearance and appearance.visualID
                if type(visualID) == "number" then
                    local sources = C_TransmogCollection.GetAppearanceSources(visualID)
                    if type(sources) == "table" then
                        for j = 1, #sources do
                            local source = sources[j]
                            local sourceID = source and (source.sourceID or source.itemModifiedAppearanceID)
                            if type(sourceID) == "number" then
                                return sourceID
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function AddNumber(list, value)
    if type(value) == "number" then
        list[#list + 1] = value
    end
end

local function GetMissionFollowerTypes()
    local list = {}
    local followerEnum = Enum and Enum.GarrisonFollowerType
    if type(followerEnum) ~= "table" then
        return list
    end

    AddNumber(list, followerEnum.FollowerType_9_0_GarrisonFollower)
    AddNumber(list, followerEnum.FollowerType_8_0_GarrisonFollower)
    AddNumber(list, followerEnum.FollowerType_7_0_GarrisonFollower)
    AddNumber(list, followerEnum.FollowerType_6_0_GarrisonFollower)

    return list
end

local function GetBoatFollowerType()
    local followerEnum = Enum and Enum.GarrisonFollowerType
    return type(followerEnum) == "table" and followerEnum.FollowerType_6_0_Boat or nil
end

local function GetGarrisonTypeForFollowerType(followerTypeID)
    local followerEnum = Enum and Enum.GarrisonFollowerType
    local garrisonEnum = Enum and Enum.GarrisonType
    if type(followerEnum) ~= "table" or type(garrisonEnum) ~= "table" then
        return nil
    end

    if followerTypeID == followerEnum.FollowerType_9_0_GarrisonFollower then
        return garrisonEnum.Type_9_0_Garrison
    elseif followerTypeID == followerEnum.FollowerType_8_0_GarrisonFollower then
        return garrisonEnum.Type_8_0_Garrison
    elseif followerTypeID == followerEnum.FollowerType_7_0_GarrisonFollower then
        return garrisonEnum.Type_7_0_Garrison
    elseif followerTypeID == followerEnum.FollowerType_6_0_GarrisonFollower or followerTypeID == followerEnum.FollowerType_6_0_Boat then
        return garrisonEnum.Type_6_0_Garrison
    end

    return nil
end

local function GetFirstMissionInfo(followerTypeID)
    if type(C_Garrison) ~= "table" or type(C_Garrison.GetAvailableMissions) ~= "function" then
        return nil
    end
    if type(followerTypeID) ~= "number" then
        return nil
    end

    local missions = C_Garrison.GetAvailableMissions(followerTypeID)
    if type(missions) == "table" and type(missions[1]) == "table" then
        return missions[1]
    end

    return nil
end

local function GetFirstFollower(followerTypeID)
    if type(C_Garrison) ~= "table" or type(C_Garrison.GetFollowers) ~= "function" then
        return nil
    end
    if type(followerTypeID) ~= "number" then
        return nil
    end

    local followers = C_Garrison.GetFollowers(followerTypeID)
    if type(followers) == "table" and type(followers[1]) == "table" then
        return followers[1]
    end

    return nil
end

local function GetFollowerID(followerData)
    if type(followerData) ~= "table" then
        return nil
    end
    return followerData.followerID or followerData.garrFollowerID or followerData.id
end

local function GetTestGarrisonTalentData()
    if type(C_Garrison) ~= "table" then
        return nil, nil
    end
    if type(C_Garrison.GetTalentInfo) ~= "function" then
        return nil, nil
    end

    local classID = select(3, UnitClass("player"))
    local garrisonEnum = Enum and Enum.GarrisonType
    if type(garrisonEnum) ~= "table" then
        return nil, nil
    end

    local garrisonTypes = {
        garrisonEnum.Type_9_0_Garrison,
        garrisonEnum.Type_8_0_Garrison,
        garrisonEnum.Type_7_0_Garrison,
    }

    for _, garrisonType in ipairs(garrisonTypes) do
        if type(C_Garrison.GetTalentTreeIDsByClassID) == "function" and type(C_Garrison.GetTalentTreeInfo) == "function" then
            local treeIDs = C_Garrison.GetTalentTreeIDsByClassID(garrisonType, classID)
            if type(treeIDs) == "table" and treeIDs[1] then
                local treeInfo = C_Garrison.GetTalentTreeInfo(treeIDs[1])
                local talentID = treeInfo and treeInfo.talents and treeInfo.talents[1] and treeInfo.talents[1].id
                if type(talentID) == "number" then
                    local talentInfo = C_Garrison.GetTalentInfo(talentID)
                    if type(talentInfo) == "table" then
                        return garrisonType, talentInfo
                    end
                end
            end
        end

        if type(C_Garrison.GetCompleteTalent) == "function" then
            local talentID = C_Garrison.GetCompleteTalent(garrisonType)
            if type(talentID) == "number" then
                local talentInfo = C_Garrison.GetTalentInfo(talentID)
                if type(talentInfo) == "table" then
                    return garrisonType, talentInfo
                end
            end
        end
    end

    return nil, nil
end

local function GetTestHousingRewardData()
    local itemType = Enum and Enum.HousingItemToastType and Enum.HousingItemToastType.Decor or nil
    local itemName = "Test Decor"
    local iconTexture = "Interface\\Icons\\INV_Misc_Houseground_City_Brick_01"

    if type(C_HousingCatalog) == "table" and type(C_HousingCatalog.GetCatalogEntryInfoByRecordID) == "function" then
        local catalogType = Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or nil
        if type(catalogType) == "number" then
            local info = C_HousingCatalog.GetCatalogEntryInfoByRecordID(catalogType, 17630, false)
            if info then
                itemName = info.name or itemName
                iconTexture = info.iconTexture or iconTexture
            end
        end
    end

    if type(itemType) ~= "number" then
        return nil
    end

    return {
        itemType = itemType,
        itemName = itemName,
        icon = iconTexture,
    }
end

local function BuildRewardData(name, subtypeID, iconTextureFile)
    return {
        name = name,
        subtypeID = subtypeID,
        iconTextureFile = iconTextureFile,
        moneyAmount = 123456,
        experienceGained = 12345,
        numRewards = 1,
        rewards = {
            {
                texturePath = ICON_COIN,
                rewardID = 0,
            },
        },
        hasBonusStep = true,
        isBonusStepComplete = true,
    }
end

local function BuildWorldQuestData()
    return {
        questID = 999999,
        taskName = "RefineUI World Quest Test",
        icon = "Interface\\Icons\\Achievement_Quests_Completed_TwilightHighlands",
        displayAsObjective = false,
        money = 23456,
        xp = 6789,
        currencyRewards = {
            ICON_COIN,
        },
    }
end

function Module:BuildToastTestEntries()
    local entries = {}
    local itemLink = GetTestItemLink()
    local itemID = ExtractItemIDFromLink(itemLink) or 6948
    local currencyID = GetTestCurrencyID()
    local mountID = GetTestMountID()
    local petID = GetTestPetID()
    local toyID = GetTestToyID()
    local warbandSceneID = GetTestWarbandSceneID()
    local recipeID = GetTestRecipeID()
    local skillLineID, tradeSkillID = GetTestSkillLineIDs()
    local perksActivityID = GetTestPerksActivityID()
    local runeforgePowerID = GetTestRuneforgePowerID()
    local transmogSourceID = GetTestTransmogSourceID()
    local housingRewardData = GetTestHousingRewardData()

    local missionFollowerTypes = GetMissionFollowerTypes()
    local missionInfo = nil
    for i = 1, #missionFollowerTypes do
        missionInfo = GetFirstMissionInfo(missionFollowerTypes[i])
        if missionInfo then
            break
        end
    end

    local boatFollowerType = GetBoatFollowerType()
    local boatMissionInfo = GetFirstMissionInfo(boatFollowerType)

    local followerData = nil
    local followerTypeID = nil
    for i = 1, #missionFollowerTypes do
        followerData = GetFirstFollower(missionFollowerTypes[i])
        if followerData then
            followerTypeID = missionFollowerTypes[i]
            break
        end
    end

    local shipFollowerData = GetFirstFollower(boatFollowerType)
    local followerID = GetFollowerID(followerData)
    local shipFollowerID = GetFollowerID(shipFollowerData)

    local followerInfo = nil
    if type(C_Garrison) == "table" and type(C_Garrison.GetFollowerInfo) == "function" and type(followerID) == "number" then
        followerInfo = C_Garrison.GetFollowerInfo(followerID)
    end
    local shipFollowerInfo = nil
    if type(C_Garrison) == "table" and type(C_Garrison.GetFollowerInfo) == "function" and type(shipFollowerID) == "number" then
        shipFollowerInfo = C_Garrison.GetFollowerInfo(shipFollowerID)
    end

    local garrisonTypeForBuilding = nil
    if type(C_Garrison) == "table" and type(C_Garrison.GetLandingPageGarrisonType) == "function" then
        garrisonTypeForBuilding = C_Garrison.GetLandingPageGarrisonType()
    end
    garrisonTypeForBuilding = garrisonTypeForBuilding or GetGarrisonTypeForFollowerType(followerTypeID)
    if type(garrisonTypeForBuilding) ~= "number" and Enum and Enum.GarrisonType then
        garrisonTypeForBuilding = Enum.GarrisonType.Type_6_0_Garrison
    end

    local garrisonBuildingName = "RefineUI Building Test"
    if type(C_Garrison) == "table" and type(C_Garrison.GetBuildings) == "function" and type(C_Garrison.GetBuildingInfo) == "function" and type(garrisonTypeForBuilding) == "number" then
        local buildings = C_Garrison.GetBuildings(garrisonTypeForBuilding)
        local firstBuilding = type(buildings) == "table" and buildings[1] or nil
        local buildingID = firstBuilding and firstBuilding.buildingID
        if type(buildingID) == "number" then
            local _, buildingName = C_Garrison.GetBuildingInfo(buildingID)
            garrisonBuildingName = buildingName or garrisonBuildingName
        end
    end

    local garrisonTypeForTalent, talentData = GetTestGarrisonTalentData()

    local itemName, itemTexture = nil, nil
    if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
        itemName = C_Item.GetItemInfo(itemID)
    elseif type(GetItemInfo) == "function" then
        itemName = GetItemInfo(itemID)
    end

    if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
        itemTexture = select(5, C_Item.GetItemInfoInstant(itemID))
    end
    itemTexture = itemTexture or ICON_COIN
    itemName = itemName or "RefineUI Reward"

    local mountName, mountIcon = nil, nil
    if type(mountID) == "number" and type(C_MountJournal) == "table" and type(C_MountJournal.GetMountInfoByID) == "function" then
        mountName, _, mountIcon = C_MountJournal.GetMountInfoByID(mountID)
    end
    mountName = mountName or "RefineUI Mount"
    mountIcon = mountIcon or itemTexture

    local entitlementTypeItem = Enum and Enum.WoWEntitlementType and Enum.WoWEntitlementType.Item or 0
    local entitlementTypeMount = Enum and Enum.WoWEntitlementType and Enum.WoWEntitlementType.Mount or entitlementTypeItem

    local function AddTest(label, run)
        entries[#entries + 1] = {
            label = label,
            run = run,
        }
    end

    AddTest("RefineUI Currency Delta", function()
        local cfg = GetConfig()
        if cfg.ShowCurrency == false then
            return false, "ShowCurrency disabled"
        end
        if type(currencyID) ~= "number" then
            return false, "no currency available"
        end
        Module:QueueCurrencyToast(currencyID, 999999)
        return true
    end)

    AddTest("RefineUI Money Delta", function()
        local cfg = GetConfig()
        if cfg.ShowMoney == false then
            return false, "ShowMoney disabled"
        end
        Module:QueueMoneyToast(123456)
        return true
    end)

    AddTest("Guild Challenge", function()
        return TryAddAlert("GuildChallengeAlertSystem", 1, 1, 3)
    end)

    AddTest("Dungeon Completion", function()
        local rewardData = BuildRewardData("RefineUI Dungeon Test", _G.LFG_SUBTYPEID_HEROIC or 1, "Interface\\LFGFrame\\LFGIcon-Dungeon")
        return TryAddAlert("DungeonCompletionAlertSystem", rewardData)
    end)

    AddTest("Scenario Completion", function()
        local rewardData = BuildRewardData("RefineUI Scenario Test", _G.LFG_SUBTYPEID_HEROIC or 1, "Interface\\Icons\\INV_Misc_Map_01")
        return TryAddAlert("ScenarioAlertSystem", rewardData)
    end)

    AddTest("Invasion Scenario", function()
        return TryAddAlert("InvasionAlertSystem", 999998, "RefineUI Invasion Test", true, 8000, 45000)
    end)

    AddTest("Achievement", function()
        if not EnsureAchievementUIFunctionsLoaded() then
            return false, "Blizzard_AchievementUI unavailable"
        end
        return TryAddAlert("AchievementAlertSystem", 6, false)
    end)

    AddTest("Criteria", function()
        if not EnsureAchievementUIFunctionsLoaded() then
            return false, "Blizzard_AchievementUI unavailable"
        end
        return TryAddAlert("CriteriaAlertSystem", 6, CRITERIA_COMPLETE or "Criteria Complete")
    end)

    AddTest("Loot Won", function()
        if not itemLink then
            return false, "no item link available"
        end
        return TryAddAlert("LootAlertSystem", itemLink, 1)
    end)

    AddTest("Loot Upgrade", function()
        if not itemLink then
            return false, "no item link available"
        end
        local baseQuality = Enum and Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2
        return TryAddAlert("LootUpgradeAlertSystem", itemLink, 1, nil, baseQuality)
    end)

    AddTest("Money Won", function()
        return TryAddAlert("MoneyWonAlertSystem", 98765)
    end)

    AddTest("Honor Awarded", function()
        return TryAddAlert("HonorAwardedAlertSystem", 250)
    end)

    AddTest("Digsite Complete", function()
        return TryAddAlert("DigsiteCompleteAlertSystem", "Night Elf Digsite", "Interface\\Icons\\Trade_Archaeology_NightElf_Crystal")
    end)

    AddTest("Entitlement Delivered", function()
        return TryAddAlert("EntitlementDeliveredAlertSystem", entitlementTypeItem, itemTexture, itemName, itemID, true)
    end)

    AddTest("RAF Reward Delivered", function()
        return TryAddAlert("RafRewardDeliveredAlertSystem", entitlementTypeMount, mountIcon, mountName, mountID or 129, true, 3)
    end)

    AddTest("Garrison Building", function()
        if type(garrisonTypeForBuilding) ~= "number" then
            return false, "no garrison type available"
        end
        return TryAddAlert("GarrisonBuildingAlertSystem", garrisonBuildingName, garrisonTypeForBuilding)
    end)

    AddTest("Garrison Mission", function()
        if not missionInfo then
            return false, "no mission data available"
        end
        return TryAddAlert("GarrisonMissionAlertSystem", missionInfo)
    end)

    AddTest("Garrison Ship Mission", function()
        if not boatMissionInfo then
            return false, "no ship mission data available"
        end
        return TryAddAlert("GarrisonShipMissionAlertSystem", boatMissionInfo)
    end)

    AddTest("Garrison Random Mission", function()
        if not missionInfo then
            return false, "no mission data available"
        end
        return TryAddAlert("GarrisonRandomMissionAlertSystem", missionInfo)
    end)

    AddTest("Garrison Follower", function()
        if type(followerID) ~= "number" then
            return false, "no follower data available"
        end
        local name = (followerData and followerData.name) or "RefineUI Follower"
        local level = (followerData and followerData.level) or 1
        local quality = (followerData and followerData.quality) or 2
        return TryAddAlert("GarrisonFollowerAlertSystem", followerID, name, level, quality, false, followerInfo or followerData)
    end)

    AddTest("Garrison Ship Follower", function()
        if type(shipFollowerID) ~= "number" then
            return false, "no ship follower data available"
        end
        local name = (shipFollowerData and shipFollowerData.name) or "RefineUI Ship Follower"
        local className = (shipFollowerData and (shipFollowerData.className or shipFollowerData.classSpecName or shipFollowerData.class)) or FOLLOWERLIST_LABEL_CLASS
        local textureKit = shipFollowerData and shipFollowerData.textureKit
        local level = (shipFollowerData and shipFollowerData.level) or 1
        local quality = (shipFollowerData and shipFollowerData.quality) or 2
        return TryAddAlert("GarrisonShipFollowerAlertSystem", shipFollowerID, name, className, textureKit, level, quality, false, shipFollowerInfo or shipFollowerData)
    end)

    AddTest("Garrison Talent", function()
        if type(garrisonTypeForTalent) ~= "number" or type(talentData) ~= "table" then
            return false, "no talent data available"
        end
        return TryAddAlert("GarrisonTalentAlertSystem", garrisonTypeForTalent, talentData)
    end)

    AddTest("World Quest Complete", function()
        return TryAddAlert("WorldQuestCompleteAlertSystem", BuildWorldQuestData())
    end)

    AddTest("Legendary Item", function()
        if not itemLink then
            return false, "no item link available"
        end
        return TryAddAlert("LegendaryItemAlertSystem", itemLink)
    end)

    AddTest("New Recipe Learned", function()
        if type(recipeID) ~= "number" then
            return false, "no recipe available"
        end
        local recipeLevel = nil
        if type(C_Spell) == "table" and type(C_Spell.GetSpellSkillLineAbilityRank) == "function" then
            recipeLevel = C_Spell.GetSpellSkillLineAbilityRank(recipeID)
        end
        return TryAddAlert("NewRecipeLearnedAlertSystem", recipeID, recipeLevel)
    end)

    AddTest("Skill Line Specs Unlocked", function()
        if type(skillLineID) ~= "number" or type(tradeSkillID) ~= "number" then
            return false, "no profession data available"
        end
        return TryAddAlert("SkillLineSpecsUnlockedAlertSystem", skillLineID, tradeSkillID)
    end)

    AddTest("New Pet", function()
        if not petID then
            return false, "no pet available"
        end
        return TryAddAlert("NewPetAlertSystem", petID)
    end)

    AddTest("New Mount", function()
        if type(mountID) ~= "number" then
            return false, "no mount available"
        end
        return TryAddAlert("NewMountAlertSystem", mountID)
    end)

    AddTest("New Toy", function()
        if type(toyID) ~= "number" then
            return false, "no toy available"
        end
        return TryAddAlert("NewToyAlertSystem", toyID)
    end)

    AddTest("New Warband Scene", function()
        if type(warbandSceneID) ~= "number" then
            return false, "no warband scene available"
        end
        return TryAddAlert("NewWarbandSceneAlertSystem", warbandSceneID)
    end)

    AddTest("New Runeforge Power", function()
        if type(runeforgePowerID) ~= "number" then
            return false, "no runeforge power available"
        end
        return TryAddAlert("NewRuneforgePowerAlertSystem", runeforgePowerID)
    end)

    AddTest("New Cosmetic", function()
        if type(transmogSourceID) ~= "number" then
            return false, "no transmog source available"
        end
        return TryAddAlert("NewCosmeticAlertFrameSystem", transmogSourceID)
    end)

    AddTest("Monthly Activity", function()
        if type(perksActivityID) ~= "number" then
            return false, "no activity available"
        end
        return TryAddAlert("MonthlyActivityAlertSystem", perksActivityID)
    end)

    AddTest("Guild Rename", function()
        return TryAddAlert("GuildRenameAlertSystem", "RefineUI Test Guild")
    end)

    AddTest("Housing Item Earned", function()
        if not housingRewardData then
            return false, "housing API unavailable"
        end
        return TryAddAlert("HousingItemEarnedAlertFrameSystem", housingRewardData)
    end)

    AddTest("Initiative Task Complete", function()
        return TryAddAlert("InitiativeTaskCompleteAlertFrameSystem", "Complete RefineUI toast pipeline test")
    end)

    return entries
end

function Module:StopToastTest(silent)
    if self.ToastTestTicker and type(self.ToastTestTicker.Cancel) == "function" then
        self.ToastTestTicker:Cancel()
    end

    self.ToastTestTicker = nil
    self.ToastTestQueue = nil
    self.ToastTestIndex = nil

    if not silent then
        self:Print("ToastTest: stopped.")
    end
end

function Module:StartToastTest()
    self:InitializeToasts()
    EnsureAchievementUIFunctionsLoaded()
    self:StopToastTest(true)

    local queue = self:BuildToastTestEntries()
    if type(queue) ~= "table" or #queue == 0 then
        self:Print("ToastTest: no spawners available.")
        return
    end

    self.ToastTestQueue = queue
    self.ToastTestIndex = 0

    self:Print("ToastTest: running %d toast spawns (1/sec). Use /refine %s stop to cancel.", #queue, TOAST_TEST_COMMAND)

    local function RunNextToast()
        if not Module.ToastTestQueue then
            return
        end

        local index = (Module.ToastTestIndex or 0) + 1
        Module.ToastTestIndex = index
        local entry = Module.ToastTestQueue[index]

        if not entry then
            Module:StopToastTest(true)
            Module:Print("ToastTest: complete.")
            return
        end

        local success = false
        local reason = nil

        local ok, runSuccess, runReason = pcall(entry.run)
        if ok then
            success = runSuccess ~= false
            reason = runReason
        else
            success = false
            reason = runSuccess
        end

        if success then
            Module:Print("ToastTest [%d/%d]: %s", index, #queue, entry.label)
        else
            Module:Print("ToastTest [%d/%d]: %s (skipped: %s)", index, #queue, entry.label, NormalizeReason(reason))
        end

        if index >= #queue then
            Module:StopToastTest(true)
            Module:Print("ToastTest: complete.")
        end
    end

    RunNextToast()
    if self.ToastTestQueue then
        self.ToastTestTicker = C_Timer.NewTicker(TOAST_TEST_INTERVAL_SECONDS, RunNextToast)
    end
end

function Module:HandleToastTestCommand(msg)
    local action = (msg and msg:match("^(%S+)") or ""):lower()

    if action == "stop" then
        self:StopToastTest()
        return
    end

    if action == "status" then
        if self.ToastTestQueue then
            local index = self.ToastTestIndex or 0
            self:Print("ToastTest: running (%d/%d).", index, #self.ToastTestQueue)
        else
            self:Print("ToastTest: not running.")
        end
        return
    end

    if action == "help" then
        self:Print("Usage: /refine %s [start|stop|status]", TOAST_TEST_COMMAND)
        return
    end

    self:StartToastTest()
end

function Module:RegisterToastTestCommand()
    if self.ToastTestCommandRegistered then
        return
    end

    RefineUI.ChatCommands = RefineUI.ChatCommands or {}
    RefineUI.ChatCommands[TOAST_TEST_COMMAND] = function(msg)
        Module:HandleToastTestCommand(msg)
    end

    self.ToastTestCommandRegistered = true
end

function Module:InstallBlizzardSkinHooks()
    if self.HooksInstalled then
        return
    end

    local cfg = GetConfig()
    if cfg.SkinBlizzard == false then
        self.HooksInstalled = true
        return
    end

    RefineUI:HookOnce("Toasts:AlertFrame_ShowNewAlert", "AlertFrame_ShowNewAlert", function(frame)
        Module:StyleToastFrame(frame)
    end)

    if _G.AlertFrame then
        RefineUI:HookOnce("Toasts:AlertFrame:UpdateAnchors", _G.AlertFrame, "UpdateAnchors", function()
            Module:StyleActiveAlertFrames()
        end)
    end

    for _, setupFuncName in ipairs(BLIZZARD_TOAST_SETUPS) do
        RefineUI:HookOnce("Toasts:" .. setupFuncName, setupFuncName, function(frame, ...)
            CaptureSetupContext(frame, setupFuncName, ...)
            Module:StyleToastFrame(frame)
        end)
    end

    for _, entry in ipairs(BLIZZARD_MIXIN_SETUPS) do
        local mixin = _G[entry.mixin]
        if type(mixin) == "table" then
            local source = entry.mixin .. ":" .. entry.method
            RefineUI:HookOnce("Toasts:" .. source, mixin, entry.method, function(frame, ...)
                CaptureSetupContext(frame, source, ...)
                Module:StyleToastFrame(frame)
            end)
        end
    end

    self.HooksInstalled = true
end

function Module:InitializeToasts()
    if self.Initialized then
        InstallQueueSpacingHook()
        ApplyAlertFrameAnchor()
        RefineUI:OffEvent("PLAYER_ENTERING_WORLD", "Toasts:PLAYER_ENTERING_WORLD")
        return
    end
    if not _G.AlertFrame then
        return
    end

    EnsureAchievementUIFunctionsLoaded()
    EnsureMover()
    RegisterMoverInEditMode()
    InstallQueueSpacingHook()
    ApplyAlertFrameAnchor()
    self:InstallBlizzardSkinHooks()
    self:StyleActiveAlertFrames()
    self:EnsureCustomToastSystem()
    self.LastMoney = GetMoney and GetMoney() or 0
    self:RegisterCustomEvents()

    self.Initialized = true
    RefineUI:OffEvent("PLAYER_ENTERING_WORLD", "Toasts:PLAYER_ENTERING_WORLD")
end

function Module:OnEnable()
    local cfg = GetConfig()
    if cfg.Enable == false then
        return
    end

    self:RegisterToastTestCommand()
    self:InitializeToasts()

    if not self.Initialized then
        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
            Module:InitializeToasts()
        end, "Toasts:PLAYER_ENTERING_WORLD")
    end
end
