----------------------------------------------------------------------------------------
-- Mythic+ for RefineUI
-- Description: Refines Blizzard's Mythic+ surfaces and keystone interaction.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local MythicPlus = RefineUI:RegisterModule("MythicPlus")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pcall = pcall
local tostring = tostring
local C_AddOns = C_AddOns
local C_ChallengeMode = C_ChallengeMode
local C_Container = C_Container
local C_MythicPlus = C_MythicPlus
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local CursorHasItem = CursorHasItem
local ItemLocation = ItemLocation
local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
local SecondsToClock = SecondsToClock

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CHALLENGES_ADDON = "Blizzard_ChallengesUI"
local KEYSTONE_LINK_TAG = "Hkeystone:"
local KEYSTONE_INSERT_DELAY = 0.1
local TIME_FOR_3 = 0.60
local TIME_FOR_2 = 0.80

----------------------------------------------------------------------------------------
-- Auto Insert Keystone
----------------------------------------------------------------------------------------
local function IsKeystoneLink(link)
    return RefineUI:IsAccessibleValue(link) and type(link) == "string"
        and link:find(KEYSTONE_LINK_TAG, 1, true) ~= nil
end

local function CanUseKeystone(bag, slot)
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot
        or not C_ChallengeMode or type(C_ChallengeMode.CanUseKeystoneInCurrentMap) ~= "function" then
        return false
    end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local ok, canUse = pcall(C_ChallengeMode.CanUseKeystoneInCurrentMap, itemLocation)
    return ok and RefineUI:IsAccessibleValue(canUse) and canUse == true
end

local function FindUsableKeystone()
    if not C_Container or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemLink) ~= "function" then
        return nil
    end

    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if IsKeystoneLink(link) and CanUseKeystone(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil
end

local function HasSlottedKeystone()
    if not C_ChallengeMode or type(C_ChallengeMode.HasSlottedKeystone) ~= "function" then
        return false
    end

    local ok, slotted = pcall(C_ChallengeMode.HasSlottedKeystone)
    return ok and RefineUI:IsAccessibleValue(slotted) and slotted == true
end

function MythicPlus:AutoInsertKeystone()
    local config = RefineUI.Config.MythicPlus
    if not config or config.AutoInsertKeystone == false or self.keystoneInsertPending
        or (InCombatLockdown and InCombatLockdown()) or HasSlottedKeystone()
        or (CursorHasItem and CursorHasItem()) then
        return
    end

    local bag, slot = FindUsableKeystone()
    if not bag then
        return
    end

    self.keystoneInsertPending = true
    C_Timer.After(KEYSTONE_INSERT_DELAY, function()
        self.keystoneInsertPending = nil
        if (InCombatLockdown and InCombatLockdown()) or HasSlottedKeystone()
            or (CursorHasItem and CursorHasItem()) then
            return
        end

        local link = C_Container.GetContainerItemLink(bag, slot)
        if not IsKeystoneLink(link) or not CanUseKeystone(bag, slot) then
            return
        end

        C_Container.PickupContainerItem(bag, slot)
        if CursorHasItem and CursorHasItem() then
            C_ChallengeMode.SlotKeystone()
        end
    end)
end

----------------------------------------------------------------------------------------
-- Mythic+ Dungeons Page
----------------------------------------------------------------------------------------
local function FormatTime(seconds)
    if not RefineUI:IsAccessibleValue(seconds) or type(seconds) ~= "number" then
        return nil
    end
    return SecondsToClock(seconds, seconds >= 3600)
end

local function GetColoredKeystoneLevel(level)
    local text = "+" .. tostring(level)
    if C_ChallengeMode and type(C_ChallengeMode.GetKeystoneLevelRarityColor) == "function" then
        local ok, color = pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, level)
        if ok and color and type(color.WrapTextInColorCode) == "function" then
            return color:WrapTextInColorCode(text)
        end
    end
    return text
end

function MythicPlus:UpdateOwnedKeystoneText()
    local frame = _G.ChallengesFrame
    local child = frame and frame.WeeklyInfo and frame.WeeklyInfo.Child
    if not child then
        return
    end

    if not child.RefineUIOwnedKeystone then
        local text = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -10, 70)
        text:SetWidth(320)
        text:SetJustifyH("RIGHT")
        text:SetWordWrap(false)
        child.RefineUIOwnedKeystone = text
    end

    local text = child.RefineUIOwnedKeystone
    local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel
        and C_MythicPlus.GetOwnedKeystoneLevel()
    if not RefineUI:IsAccessibleValue(mapID) or type(mapID) ~= "number"
        or not RefineUI:IsAccessibleValue(level) or type(level) ~= "number" then
        text:Hide()
        return
    end

    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if not RefineUI:IsAccessibleValue(name) or type(name) ~= "string" or name == "" then
        text:Hide()
        return
    end

    text:SetText("|cffffd200Keystone:|r " .. name .. " " .. GetColoredKeystoneLevel(level))
    text:Show()
end

local function AddDungeonTimerTooltip(icon)
    if not icon or not RefineUI:IsAccessibleValue(icon.mapID) or type(icon.mapID) ~= "number" then
        return
    end

    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(icon.mapID)
    local limit = FormatTime(timeLimit)
    if not limit then
        return
    end

    local time2 = FormatTime(timeLimit * TIME_FOR_2)
    local time3 = FormatTime(timeLimit * TIME_FOR_3)
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    GameTooltip_AddColoredLine(GameTooltip,
        "Time limit " .. limit .. "  |  +2 " .. time2 .. "  |  +3 " .. time3,
        HIGHLIGHT_FONT_COLOR)
    GameTooltip:Show()
end

function MythicPlus:HookDungeonIcons()
    local frame = _G.ChallengesFrame
    local icons = frame and frame.DungeonIcons
    if type(icons) ~= "table" then
        return
    end

    for index = 1, #icons do
        local icon = icons[index]
        RefineUI:HookScriptOnce("MythicPlus:DungeonIcon:" .. tostring(icon), icon, "OnEnter", AddDungeonTimerTooltip)
    end
end

function MythicPlus:UpdateChallengesFrame()
    self:UpdateOwnedKeystoneText()
    self:HookDungeonIcons()
end

function MythicPlus:SetupChallengesFrame()
    local frame = _G.ChallengesFrame
    if not frame or self.challengesFrameHooked then
        return
    end
    self.challengesFrameHooked = true

    RefineUI:HookOnce("MythicPlus:ChallengesFrame:Update", frame, "Update", function()
        self:UpdateChallengesFrame()
    end)
    RefineUI:HookScriptOnce("MythicPlus:ChallengesFrame:OnShow", frame, "OnShow", function()
        self:UpdateChallengesFrame()
    end)
    self:UpdateChallengesFrame()
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function MythicPlus:OnInitialize()
    RefineUI:RegisterEventCallback("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN", function()
        self:AutoInsertKeystone()
    end, "MythicPlus:AutoInsertKeystone")

    if C_AddOns and C_AddOns.IsAddOnLoaded(CHALLENGES_ADDON) then
        self:SetupChallengesFrame()
    else
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
            if addonName == CHALLENGES_ADDON then
                self:SetupChallengesFrame()
                RefineUI:OffEvent("ADDON_LOADED", "MythicPlus:ChallengesUI")
            end
        end, "MythicPlus:ChallengesUI")
    end
end
