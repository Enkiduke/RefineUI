----------------------------------------------------------------------------------------
-- Minimap for RefineUI
-- Description: Handles Minimap styling, controls, and cleanup to legacy parity.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local rawget = rawget

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_Timer = C_Timer
local C_AddOns = C_AddOns
local GetCursorPosition = GetCursorPosition
local CreateFrame = CreateFrame
local GetMinimapZoneText = GetMinimapZoneText
local GetZoneText = GetZoneText
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster
local UIParent = _G.UIParent

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------

local DEFAULT_MINIMAP_SIZE = 294

local function GetCurrentLayoutTierKey()
    local context = RefineUI.GetLayoutContext and RefineUI:GetLayoutContext() or nil
    local tierKey = context and context.tierKey or nil
    if type(tierKey) ~= "string" or tierKey == "" then
        tierKey = RefineUI.GetLayoutTier and RefineUI:GetLayoutTier() or nil
    end
    return tierKey
end

local function GetDefaultMinimapSize(tierKey)
    local defaults = RefineUI.GetLayoutDefaults and RefineUI:GetLayoutDefaults(tierKey) or nil
    local minimapDefaults = defaults and defaults.minimap or nil
    local defaultSize = tonumber(minimapDefaults and minimapDefaults.baseSize)
    if not defaultSize or defaultSize <= 0 then
        defaultSize = DEFAULT_MINIMAP_SIZE
    end
    return defaultSize
end

local function ForceHideFrame(frame, hookKey)
    if not frame then return end
    frame:Hide()
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
    if hookKey and frame.HookScript then
        RefineUI:HookScriptOnce(hookKey, frame, "OnShow", function(self)
            self:Hide()
            if self.SetAlpha then
                self:SetAlpha(0)
            end
        end)
    end
end

local trackingClickProxy
local customZoneText
local minimapBorderHost

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

local function GetZoneColor()
    local pvpType = _G.C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return 0.41, 0.8, 0.94
    elseif pvpType == "arena" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "friendly" then
        return 0.1, 1.0, 0.1
    elseif pvpType == "hostile" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "contested" then
        return 1.0, 0.7, 0.0
    elseif pvpType == "combat" then
        return 1.0, 0.1, 0.1
    else
        return 1.0, 0.9294, 0.7607
    end
end

local function EnsureCustomZoneText()
    if customZoneText then return customZoneText end

    customZoneText = Minimap:CreateFontString(nil, "OVERLAY")
    local fontPath = (RefineUI.Media and RefineUI.Media.Fonts and RefineUI.Media.Fonts.Default) or _G.STANDARD_TEXT_FONT
    customZoneText:SetFont(fontPath, RefineUI:Scale(14), "OUTLINE")
    customZoneText:SetPoint("TOP", Minimap, "TOP", 0, -3)
    customZoneText:SetJustifyH("CENTER")
    customZoneText:Hide()

    return customZoneText
end

local function ShowCustomZoneText()
    local zoneName = GetMinimapZoneText and GetMinimapZoneText()
    if not zoneName or zoneName == "" then
        zoneName = GetZoneText and GetZoneText()
    end

    if not zoneName or zoneName == "" then
        if customZoneText then customZoneText:Hide() end
        return
    end

    local r, g, b = GetZoneColor()
    local label = EnsureCustomZoneText()
    label:SetText(zoneName)
    label:SetTextColor(r, g, b)
    label:Show()
end

local function HideCustomZoneText()
    if customZoneText then
        customZoneText:Hide()
    end
end

local function RefreshCustomZoneText()
    if trackingClickProxy and trackingClickProxy.IsMouseOver and trackingClickProxy:IsMouseOver() then
        ShowCustomZoneText()
    end
end

local function EnsureMinimapBorderHost()
    if minimapBorderHost then
        return minimapBorderHost
    end

    minimapBorderHost = CreateFrame("Frame", nil, MinimapCluster)
    minimapBorderHost:SetFrameStrata(Minimap:GetFrameStrata())
    minimapBorderHost:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    minimapBorderHost:EnableMouse(false)
    minimapBorderHost:ClearAllPoints()
    minimapBorderHost:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    minimapBorderHost:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
    RefineUI.CreateBorder(minimapBorderHost, 6, 6)
    if minimapBorderHost.bg then
        minimapBorderHost.bg:Hide()
    end

    return minimapBorderHost
end

local function UpdateMinimapSelectionFrame()
    if not MinimapCluster or not MinimapCluster.Selection then
        return
    end

    local selectionAnchor = minimapBorderHost and (minimapBorderHost.RefineBorder or minimapBorderHost.border) or Minimap
    if not selectionAnchor then
        return
    end

    MinimapCluster.Selection:ClearAllPoints()
    MinimapCluster.Selection:SetPoint("TOPLEFT", selectionAnchor, "TOPLEFT", 0, 0)
    MinimapCluster.Selection:SetPoint("BOTTOMRIGHT", selectionAnchor, "BOTTOMRIGHT", 0, 0)

    if MinimapCluster.UpdateClampOffsets then
        MinimapCluster:UpdateClampOffsets()
    end
end

local function ApplyInstanceDifficultyLayout()
    local instanceDifficulty = MinimapCluster and MinimapCluster.InstanceDifficulty
    if not instanceDifficulty then
        return
    end

    instanceDifficulty:SetParent(Minimap)
    instanceDifficulty:ClearAllPoints()
    instanceDifficulty:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)

    for _, key in ipairs({"Default", "Guild", "ChallengeMode"}) do
        local diff = instanceDifficulty[key]
        if diff then
            if diff.Border then
                diff.Border:Hide()
            end

            if diff.Background then
                diff.Background:SetSize(36, 36)
                diff.Background:ClearAllPoints()
                diff.Background:SetPoint("CENTER", diff, "CENTER", 0, 0)
                if key == "Default" then
                    diff.Background:SetVertexColor(0.6, 0.3, 0)
                elseif key == "ChallengeMode" then
                    diff.Background:SetVertexColor(0.8, 0.8, 0)
                else
                    diff.Background:SetVertexColor(1, 1, 1)
                end
            end

            if diff.Instance and diff.Instance.Layout then
                diff.Instance:Layout()
            end
            if diff.Layout then
                diff:Layout()
            end
        end
    end

    if instanceDifficulty.Update then
        instanceDifficulty:Update()
    end
end

local function RefreshMinimapLayoutOverlays()
    ApplyInstanceDifficultyLayout()
    UpdateMinimapSelectionFrame()
end

local function GetPreferredMinimapSize(maps)
    local db = maps and maps.db or nil
    local tierKey = GetCurrentLayoutTierKey()
    local defaultSize = GetDefaultMinimapSize(tierKey)
    local preferredSize

    if type(db) == "table" then
        db.LayoutSizes = db.LayoutSizes or {}

        preferredSize = tonumber(db.LayoutSizes[tierKey])
        if not preferredSize or preferredSize <= 0 then
            local legacySize = tonumber(db.Size)
            if legacySize and legacySize > 0 and legacySize ~= DEFAULT_MINIMAP_SIZE then
                preferredSize = legacySize
            else
                preferredSize = defaultSize
            end
            db.LayoutSizes[tierKey] = preferredSize
        end

        db.Size = preferredSize
    end

    if not preferredSize or preferredSize <= 0 then
        preferredSize = defaultSize
    end
    return preferredSize
end

local function GetCurrentMinimapEditModeScale()
    local minimapContainer = MinimapCluster and MinimapCluster.MinimapContainer
    local scale = minimapContainer and minimapContainer.GetScale and minimapContainer:GetScale() or 1
    if type(scale) ~= "number" or scale <= 0 then
        scale = 1
    end
    return scale
end

function Maps:SetupMinimap()
    if not self.db or self.db.Enable ~= true then return end
    local db = RefineUI.DB
    local installReady = db and db.Installed and db.InstallState == "ready"

    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)

    if _G.MinimapCompassTexture then _G.MinimapCompassTexture:Hide() end
    if MinimapCluster.BorderTop then RefineUI.StripTextures(MinimapCluster.BorderTop) end
    
    local zoomInBtn = rawget(Minimap, 'ZoomIn')
    if zoomInBtn and zoomInBtn.Kill then zoomInBtn:Kill() elseif zoomInBtn then RefineUI.Kill(zoomInBtn) end
    local zoomOutBtn = rawget(Minimap, 'ZoomOut')
    if zoomOutBtn and zoomOutBtn.Kill then zoomOutBtn:Kill() elseif zoomOutBtn then RefineUI.Kill(zoomOutBtn) end

    Minimap:SetMaskTexture(RefineUI.Media.Textures.Blank)
    Minimap:SetArchBlobRingAlpha(0)
    Minimap:SetQuestBlobRingAlpha(0)
    Minimap:SetArchBlobRingScalar(0)
    Minimap:SetQuestBlobRingScalar(0)

    local function ApplyMinimapSize(scale)
        local preferredSize = GetPreferredMinimapSize(self)
        local effectiveScale = tonumber(scale) or GetCurrentMinimapEditModeScale()
        if effectiveScale <= 0 then
            effectiveScale = 1
        end
        local clusterSize = preferredSize * effectiveScale

        if MinimapCluster.MinimapContainer then
            MinimapCluster.MinimapContainer:SetSize(preferredSize, preferredSize)
        end
        Minimap:SetSize(preferredSize, preferredSize)

        MinimapCluster:SetSize(clusterSize, clusterSize)
        if MinimapCluster.Selection then
            MinimapCluster.Selection:SetSize(clusterSize, clusterSize)
        end

        if self.RequestButtonCollectRefresh then
            self:RequestButtonCollectRefresh()
        end
    end

    self.RefreshMinimapSize = function(_, scale)
        ApplyMinimapSize(scale)
    end

    RefineUI:HookOnce("Minimap:MinimapCluster:SetEditModeScale", MinimapCluster, "SetEditModeScale", function(_, scale)
        ApplyMinimapSize(scale)
    end)
    RefineUI:HookOnce("Minimap:MinimapCluster:UpdateSystemSettingHeaderUnderneath", MinimapCluster, "UpdateSystemSettingHeaderUnderneath", RefreshMinimapLayoutOverlays)
    ApplyMinimapSize()
    
    -- Keep Blizzard default minimap anchoring until install/layout is ready.
    -- Moving MinimapCluster while EditMode still marks it as default can produce
    -- negative right-action-bar autoscale in Blizzard startup layout math.
    if installReady then
        MinimapCluster:ClearAllPoints()
        if self.positions.MinimapCluster then
            MinimapCluster:SetPoint(unpack(self.positions.MinimapCluster))
        else
            MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -26, -26)
        end
    end
    if MinimapCluster.MinimapContainer then
        Minimap:ClearAllPoints()
        Minimap:SetAllPoints(MinimapCluster.MinimapContainer)
    end
    
    MinimapCluster:SetFrameLevel(10)
    EnsureMinimapBorderHost()
    RefineUI:HookOnce("Minimap:MinimapCluster:AnchorSelectionFrame", MinimapCluster, "AnchorSelectionFrame", UpdateMinimapSelectionFrame)
    RefreshMinimapLayoutOverlays()
    MinimapCluster:EnableMouse(false)

    ApplyInstanceDifficultyLayout()

    if _G.QueueStatusButton then
        _G.QueueStatusButton:ClearAllPoints()
        _G.QueueStatusButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 0)
        _G.QueueStatusButton:SetParent(Minimap)
        _G.QueueStatusButton:SetScale(0.75)

        RefineUI:HookOnce("Minimap:QueueStatusButton:SetPoint", _G.QueueStatusButton, "SetPoint", function(self, _, anchor)
            if anchor ~= Minimap then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 0)
            end
        end)
        
        RefineUI:HookOnce("Minimap:QueueStatusButton:SetScale", _G.QueueStatusButton, "SetScale", function(self, scale)
            if scale ~= 0.75 then self:SetScale(0.75) end
        end)
    end

    if MinimapCluster.IndicatorFrame then
        local MailFrame = MinimapCluster.IndicatorFrame.MailFrame
        if MailFrame then
            RefineUI:HookOnce("Minimap:IndicatorMailFrame:SetPoint", MailFrame, "SetPoint", function(self, _, anchor)
                if anchor ~= Minimap then
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -2, 4)
                end
            end)
            if _G.MiniMapMailIcon then _G.MiniMapMailIcon:SetSize(20, 18) end
        end
        
        local Crafting = MinimapCluster.IndicatorFrame.CraftingOrderFrame
        if Crafting then
            RefineUI:HookOnce("Minimap:IndicatorCrafting:SetPoint", Crafting, "SetPoint", function(self, _, anchor)
                if anchor ~= Minimap then
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 4)
                end
            end)
        end
    end

    if self.db.ZoomReset then
        local resetting = 0
        RefineUI:RegisterEventCallback("MINIMAP_UPDATE_ZOOM", function()
            if Minimap:GetZoom() > 0 and resetting == 0 then
                resetting = 1
                C_Timer.After(self.db.ResetTime or 5, function()
                    Minimap:SetZoom(0)
                    resetting = 0
                end)
            end
        end)
    end

    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, d)
        if d > 0 then
            local zi = rawget(Minimap, 'ZoomIn')
            if zi and zi.Click then zi:Click() end
        elseif d < 0 then
            local zo = rawget(Minimap, 'ZoomOut')
            if zo and zo.Click then zo:Click() end
        end
    end)

    if not trackingClickProxy then
        trackingClickProxy = CreateFrame("Frame", nil, Minimap)
    end
    trackingClickProxy:SetAllPoints(Minimap)
    trackingClickProxy:SetFrameStrata(Minimap:GetFrameStrata())
    trackingClickProxy:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    trackingClickProxy:EnableMouse(true)
    if trackingClickProxy.SetPropagateMouseMotion then
        trackingClickProxy:SetPropagateMouseMotion(true)
    end
    if trackingClickProxy.SetPropagateMouseClicks then
        trackingClickProxy:SetPropagateMouseClicks(false)
    end
    trackingClickProxy:SetPassThroughButtons("LeftButton", "MiddleButton")
    trackingClickProxy:SetScript("OnEnter", ShowCustomZoneText)
    trackingClickProxy:SetScript("OnLeave", HideCustomZoneText)
    trackingClickProxy:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        if not (MinimapCluster.Tracking and MinimapCluster.Tracking.Button and MinimapCluster.Tracking.Button.OpenMenu) then return end

        MinimapCluster.Tracking.Button:OpenMenu()
        local menu = MinimapCluster.Tracking.Button.menu
        if not menu then return end

        local ok = pcall(function()
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            menu:ClearAllPoints()
            menu:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
        end)

        if not ok then
            menu:ClearAllPoints()
            menu:SetPoint("TOPRIGHT", Minimap, "LEFT", -4, 0)
        end
    end)

    RefineUI:RegisterEventCallback("ZONE_CHANGED", RefreshCustomZoneText, "Minimap:CustomZoneText:ZoneChanged")
    RefineUI:RegisterEventCallback("ZONE_CHANGED_INDOORS", RefreshCustomZoneText, "Minimap:CustomZoneText:ZoneChangedIndoors")
    RefineUI:RegisterEventCallback("ZONE_CHANGED_NEW_AREA", RefreshCustomZoneText, "Minimap:CustomZoneText:ZoneChangedNewArea")

    ForceHideFrame(MinimapCluster.ZoneTextButton, "Minimap:ZoneTextButton:OnShow:Hide")
    ForceHideFrame(_G.GameTimeFrame, "Minimap:GameTimeFrame:OnShow:Hide")
    ForceHideFrame(_G.TimeManagerClockButton, "Minimap:TimeManagerClockButton:OnShow:Hide")
    ForceHideFrame(_G.AddonCompartmentFrame, "Minimap:AddonCompartmentFrame:OnShow:Hide")
    if _G.MinimapZoneText then _G.MinimapZoneText:Hide() end
    if _G.TimeManagerClockTicker then _G.TimeManagerClockTicker:Hide() end
    if _G.GameTimeCalendarInvitesTexture then _G.GameTimeCalendarInvitesTexture:Hide() end
    if MinimapCluster.Tracking then
        if MinimapCluster.Tracking.Background then
            MinimapCluster.Tracking.Background:Hide()
            RefineUI:HookScriptOnce("Minimap:TrackingBackground:OnShow:Hide", MinimapCluster.Tracking.Background, "OnShow", function(self)
                self:Hide()
            end)
        end
        if MinimapCluster.Tracking.Button then
            MinimapCluster.Tracking.Button:SetAlpha(0)
            RefineUI:HookScriptOnce("Minimap:TrackingButton:OnShow:Alpha", MinimapCluster.Tracking.Button, "OnShow", function(self)
                self:SetAlpha(0)
            end)
        end
    end
    if MinimapCluster.IndicatorFrame then
        MinimapCluster.IndicatorFrame:Hide()
        RefineUI:HookScriptOnce("Minimap:IndicatorFrame:OnShow:Hide", MinimapCluster.IndicatorFrame, "OnShow", function(self)
            self:Hide()
        end)
    end

    local feedback = rawget(_G, 'FeedbackUIButton')
    if feedback then
        feedback:ClearAllPoints()
        feedback:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 0)
        feedback:SetScale(0.8)
    end

    if _G.StreamingIcon then
        _G.StreamingIcon:ClearAllPoints()
        _G.StreamingIcon:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, -10)
        _G.StreamingIcon:SetScale(0.8)
        _G.StreamingIcon:SetFrameStrata("BACKGROUND")
    end

    if _G.GhostFrame then
        RefineUI.StripTextures(_G.GhostFrame)
        RefineUI.SetTemplate(_G.GhostFrame, "Transparent")
        _G.GhostFrame:ClearAllPoints()
        if self.positions.RefineUI_GhostFrame then
            _G.GhostFrame:SetPoint(unpack(self.positions.RefineUI_GhostFrame))
        else
            _G.GhostFrame:SetPoint("TOP", UIParent, "TOP", 0, -50)
        end
        
        if _G.GhostFrameContentsFrameIcon then
            _G.GhostFrameContentsFrameIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            _G.GhostFrameContentsFrameIcon:SetSize(32, 32)
            _G.GhostFrameContentsFrame:SetFrameLevel(_G.GhostFrameContentsFrame:GetFrameLevel() + 2)
            RefineUI.CreateBackdrop(_G.GhostFrameContentsFrame, "Transparent")
            if _G.GhostFrameContentsFrame.bg then
                 _G.GhostFrameContentsFrame.bg:SetPoint("TOPLEFT", _G.GhostFrameContentsFrameIcon, -2, 2)
                 _G.GhostFrameContentsFrame.bg:SetPoint("BOTTOMRIGHT", _G.GhostFrameContentsFrameIcon, 2, -2)
            end
        end
    end

    ForceHideFrame(_G.AddonCompartmentFrame, "Minimap:AddonCompartmentFrame:OnShow:Hide")
    ForceHideFrame(_G.GameTimeFrame, "Minimap:GameTimeFrame:OnShow:Hide")
    if MinimapCluster.IndicatorFrame then
        MinimapCluster.IndicatorFrame:SetParent(Minimap)
        MinimapCluster.IndicatorFrame:Hide()
    end
    if MinimapCluster.Tracking then
        if MinimapCluster.Tracking.Background then MinimapCluster.Tracking.Background:Hide() end
        if MinimapCluster.Tracking.Button then MinimapCluster.Tracking.Button:SetAlpha(0) end
    end
    local HiddenFrames = {
        "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag",
        "MiniMapWorldMapButton", "MinimapBackdrop", "TimeManagerClockTicker",
    }
    for _, name in ipairs(HiddenFrames) do
        local f = _G[name]
        if f then
            f:Hide()
            if f.UnregisterAllEvents then f:UnregisterAllEvents() end
        end
    end

    ForceHideFrame(MinimapCluster.ZoneTextButton, "Minimap:ZoneTextButton:OnShow:Hide")
    if _G.MinimapZoneText then _G.MinimapZoneText:Hide() end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_TimeManager" then
            if _G.TimeManagerClockButton then
                ForceHideFrame(_G.TimeManagerClockButton, "Minimap:TimeManagerClockButton:OnShow:Hide")
            end
        elseif addon == "Blizzard_HybridMinimap" then
            local hm = _G.HybridMinimap
            hm:SetFrameStrata("BACKGROUND")
            hm:SetFrameLevel(100)
            hm.MapCanvas:SetUseMaskTexture(false)
            hm.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            hm.MapCanvas:SetUseMaskTexture(true)
        end
    end)
    
    if C_AddOns.IsAddOnLoaded("Blizzard_TimeManager") then
        if _G.TimeManagerClockButton then
            ForceHideFrame(_G.TimeManagerClockButton, "Minimap:TimeManagerClockButton:OnShow:Hide")
        end
    end

    if _G.ExpansionLandingPageMinimapButton then
        _G.ExpansionLandingPageMinimapButton:SetScale(0.0001)
        _G.ExpansionLandingPageMinimapButton:SetAlpha(0)
    end
end

_G.GetMinimapShape = function() return "SQUARE" end
