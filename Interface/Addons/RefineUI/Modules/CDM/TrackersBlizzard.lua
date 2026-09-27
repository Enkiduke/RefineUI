----------------------------------------------------------------------------------------
-- CDM Component: TrackersBlizzard
-- Description: Hosts Blizzard Tracked Buff item frames inside RefineUI trackers.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local select = select
local tostring = tostring
local max = math.max
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
-- Blizzard's Tracked Buffs viewer keeps these frames current in combat, including
-- secret aura timers that addon code cannot copy. RefineUI only reparents, positions,
-- and restyles them. Never write Lua fields on these frames or call their mutating
-- methods: tainting Blizzard's item code breaks its secret-value handling.
local VIEWER_NAME = "BuffIconCooldownViewer"
local ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local BLIZZARD_ITEM_SIZE = 40
local ITEM_FRAME_LEVEL_OFFSET = 5
local APPLICATIONS_FONT_SIZE = 14
local SETUP_CHECK_TIMER_KEY = CDM:BuildKey("BlizzardTrackers", "SetupCheck")
local SETUP_CHECK_DELAY = 2

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local itemByCooldownID = {}
local bucketByItem = setmetatable({}, { __mode = "k" })
local claimPassByItem = setmetatable({}, { __mode = "k" })
local skinByItem = setmetatable({}, { __mode = "k" })
local swipeColorByItem = setmetatable({}, { __mode = "k" })
local hookedItems = setmetatable({}, { __mode = "k" })
local claimPass = 0
local viewerHooksInstalled = false
local setupWarnings = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetViewer()
    return _G[VIEWER_NAME]
end

local function IsViewerLive(viewer)
    if not viewer then
        return false
    end
    local shown = viewer:IsShown()
    return not (issecretvalue and issecretvalue(shown)) and shown == true
end

local function PrepareItemRegions(item, ...)
    local icon = item.Icon
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region ~= icon then
            if region:IsObjectType("MaskTexture") then
                icon:RemoveMaskTexture(region)
            elseif region:IsObjectType("Texture") and region:GetAtlas() == ICON_OVERLAY_ATLAS then
                region:SetAlpha(0)
            end
        end
    end
end

local function EnsureSkin(item)
    local skin = skinByItem[item]
    if skin then
        return skin
    end

    -- Blizzard's rounded mask and overlay ring are replaced by the RefineUI border.
    PrepareItemRegions(item, item:GetRegions())
    item.DebuffBorder:SetAlpha(0)

    skin = CreateFrame("Frame", nil, item)
    skin:SetAllPoints(item)
    RefineUI.SetTemplate(skin, "Default")
    skin.Radial = skin:CreateTexture(nil, "BACKGROUND")
    skin.Radial:SetAllPoints(skin)

    skinByItem[item] = skin
    return skin
end

local function ReapplySwipeColor(item)
    local color = swipeColorByItem[item]
    if color then
        item.Cooldown:SetSwipeColor(color[1], color[2], color[3], color[4])
    end
end

local function OnItemShownStateChanged(item)
    local bucket = bucketByItem[item]
    if bucket then
        CDM:LayoutTrackerBucket(bucket)
    end
end

local function HookItem(item)
    if hookedItems[item] then
        return
    end
    hookedItems[item] = true

    local key = "CDM:BlizzardTracker:Item:" .. tostring(item)
    -- Blizzard resets the swipe color on every cooldown refresh.
    RefineUI:HookOnce(key .. ":RefreshCooldownInfo", item, "RefreshCooldownInfo", ReapplySwipeColor)
    RefineUI:HookOnce(key .. ":UpdateShownState", item, "UpdateShownState", OnItemShownStateChanged)
end

local function StyleIconItem(item, skin, cooldownID)
    skin.Radial:Hide()
    skin.bg:Show()
    skin.border:Show()

    item.Icon:SetAlpha(1)
    item.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    CDM:ApplyTrackerIconVisual(skin, cooldownID)
    CDM:ApplyTrackerCooldownSkin(item, item.Cooldown)
    item.Cooldown:SetHideCountdownNumbers(false)
    CDM:ApplyTrackerCooldownTextVisual(item.Cooldown, cooldownID)

    local applications = item.Applications
    applications:SetAlpha(1)
    applications:SetFrameLevel(item.Cooldown:GetFrameLevel() + 1)
    applications.Applications:SetFont(RefineUI.Media.Fonts.Number, APPLICATIONS_FONT_SIZE, "OUTLINE")

    swipeColorByItem[item] = CDM.TRACKER_SWIPE_COLOR
    ReapplySwipeColor(item)
end

local function StyleRadialItem(item, skin, cooldownID, bucketCfg)
    skin.bg:Hide()
    skin.border:Hide()
    skin.Radial:Show()

    item.Icon:SetAlpha(0)
    item.Applications:SetAlpha(0)

    local color = CDM:GetCooldownBorderColor(cooldownID)
    CDM:StateClear(item, "trackerCooldownSkinToken")
    CDM:ApplyRadialTrackerSkin(item, item.Cooldown, skin.Radial, color, CDM:GetCooldownFontColor(cooldownID), bucketCfg)

    swipeColorByItem[item] = { color[1], color[2], color[3], 1 }
    ReapplySwipeColor(item)
end

local function ClaimItem(item, bucket, cooldownID)
    local frame = CDM:EnsureTrackerFrame(bucket)
    if item:GetParent() ~= frame then
        item:SetParent(frame)
    end

    local level = frame:GetFrameLevel() + ITEM_FRAME_LEVEL_OFFSET
    item:SetFrameLevel(level)
    item:SetMouseMotionEnabled(false)

    local skin = EnsureSkin(item)
    skin:SetFrameLevel(max(0, level - 1))

    local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucket)
    if bucket == CDM.RADIAL_BUCKET then
        StyleRadialItem(item, skin, cooldownID, bucketCfg)
    else
        StyleIconItem(item, skin, cooldownID)
    end

    HookItem(item)
    bucketByItem[item] = bucket
    claimPassByItem[item] = claimPass
    itemByCooldownID[cooldownID] = item
end

local function ReleaseItem(item, viewer)
    bucketByItem[item] = nil
    claimPassByItem[item] = nil
    swipeColorByItem[item] = nil

    item:SetParent(viewer)
    item:SetAlpha(1)
    item:SetScale(viewer.iconScale or 1)
    item:SetSize(BLIZZARD_ITEM_SIZE, BLIZZARD_ITEM_SIZE)
end

local function WarnOnce(reason, message)
    if setupWarnings[reason] then
        return
    end
    setupWarnings[reason] = true
    RefineUI:Print(message)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:GetBlizzardTrackerItem(cooldownID)
    return itemByCooldownID[cooldownID]
end

function CDM:IsBlizzardTrackerViewerLive()
    return IsViewerLive(GetViewer())
end

function CDM:MapBlizzardTrackerItems()
    for cooldownID in pairs(itemByCooldownID) do
        itemByCooldownID[cooldownID] = nil
    end

    local viewer = GetViewer()
    if not viewer or not viewer.itemFramePool then
        return
    end

    self:InstallBlizzardTrackerHooks()
    claimPass = claimPass + 1
    if self:IsRefineRuntimeOwnerActive() then
        local bucketByCooldownID = self:GetAssignedCooldownSnapshot().bucketByCooldownID
        for item in viewer.itemFramePool:EnumerateActive() do
            local cooldownID = item.cooldownID
            local bucket = cooldownID and bucketByCooldownID[cooldownID]
            if bucket then
                ClaimItem(item, bucket, cooldownID)
            end
        end
    end

    for item in pairs(bucketByItem) do
        if claimPassByItem[item] ~= claimPass then
            ReleaseItem(item, viewer)
        end
    end
end

function CDM:SyncBlizzardTrackerItems()
    self:MapBlizzardTrackerItems()
    self:LayoutTrackers()
end

function CDM:InstallBlizzardTrackerHooks()
    if viewerHooksInstalled then
        return
    end

    local viewer = GetViewer()
    if not viewer then
        return
    end

    local function Sync()
        CDM:SyncBlizzardTrackerItems()
    end

    -- RefreshLayout re-acquires pooled frames; RefreshData reassigns cooldown IDs;
    -- the settings hooks reapply mouse and countdown state Blizzard resets.
    -- A shown viewer's RefreshLayout calls RefreshData, whose hook already synced.
    RefineUI:HookOnce("CDM:BlizzardTracker:RefreshLayout", viewer, "RefreshLayout", function(self)
        if not IsViewerLive(self) then
            Sync()
        end
    end)
    RefineUI:HookOnce("CDM:BlizzardTracker:RefreshData", viewer, "RefreshData", Sync)
    RefineUI:HookOnce("CDM:BlizzardTracker:SetTimerShown", viewer, "SetTimerShown", Sync)
    RefineUI:HookOnce("CDM:BlizzardTracker:SetTooltipsShown", viewer, "SetTooltipsShown", Sync)
    RefineUI:HookOnce("CDM:BlizzardTracker:UpdateShownState", viewer, "UpdateShownState", function()
        CDM:LayoutTrackers()
    end)

    _G.EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        if not CDM:IsRefineRuntimeOwnerActive() then
            return
        end
        CDM:MarkAssignmentsPruneDirty()
        CDM:RequestRefresh()
    end, CDM)

    viewerHooksInstalled = true
end

function CDM:ReleaseBlizzardTrackerItems()
    local viewer = GetViewer()
    for cooldownID in pairs(itemByCooldownID) do
        itemByCooldownID[cooldownID] = nil
    end
    if not viewer then
        return
    end
    for item in pairs(bucketByItem) do
        ReleaseItem(item, viewer)
    end
end

function CDM:RequestBlizzardTrackerSetupCheck()
    RefineUI:After(SETUP_CHECK_TIMER_KEY, SETUP_CHECK_DELAY, function()
        CDM:CheckBlizzardTrackerSetup()
    end)
end

function CDM:CheckBlizzardTrackerSetup()
    if not self:IsRefineRuntimeOwnerActive() or InCombatLockdown() or self:IsEditModeActive() then
        return
    end
    if not self:GetAssignedCooldownSnapshot().hasAuraAssignments then
        return
    end

    -- Tracked buffs only exist as Blizzard frames once the RefineUI layout is saved.
    self:EnsureBlizzardTrackerRuntime()
    if self:NeedsBlizzardTrackerSetup() then
        WarnOnce("setup", "CDM: open /cdm and click Finish Setup so tracked buffs show for this specialization.")
        return
    end

    local viewer = GetViewer()
    if not viewer then
        return
    end
    if not IsViewerLive(viewer) then
        WarnOnce("visibility", "CDM: set Tracked Buffs Visibility to Always in Edit Mode so tracked buffs can update.")
    elseif viewer.hideWhenInactive ~= true then
        WarnOnce("inactive", "CDM: enable Hide When Inactive for Tracked Buffs in Edit Mode so only active buffs show.")
    end
end
