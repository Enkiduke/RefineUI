----------------------------------------------------------------------------------------
-- Waypoint: small enhancements to Blizzard's existing navigation frame.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")
local C_Map, C_SuperTrack = C_Map, C_SuperTrack
local format, tonumber = string.format, tonumber
local unpack = unpack
local issecretvalue = issecretvalue
local IsInInstance = IsInInstance
local OFFSCREEN_ARROW_ATLAS = "Radial_Wheel_Select_Pointer"
local OFFSCREEN_ARROW_ROTATION_OFFSET = math.pi / 2
local OFFSCREEN_ARROW_SCALE = 1
local BEAM_ALPHA_MIN, BEAM_ALPHA_MAX = 0.3, 0.75

local function IsNumber(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Explicit percent coordinates only; never guess map names or coordinate formats.
function Maps:WaypointCommand(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    if message:lower() == "clear" then
        C_Map.ClearUserWaypoint()
        return
    end
    message = message:gsub("%s*,%s*", " ")
    local mapID, x, y = message:match("^(%d+)%s+(%S+)%s+(%S+)$")
    if not mapID then
        x, y = message:match("^(%S+)%s+(%S+)$")
        mapID = C_Map.GetBestMapForUnit("player")
    end
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not IsNumber(mapID) or not IsNumber(x) or not IsNumber(y)
        or x < 0 or x > 100 or y < 0 or y > 100 then
        RefineUI:Print("Usage: /way [mapID] x, y (0-100), or /way clear")
        return
    end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        RefineUI:Print("A waypoint cannot be placed on that map.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
end

function Maps:UpdateWaypointInstanceState()
    local inInstance = IsInInstance()
    inInstance = inInstance and true or false
    if inInstance and not self.waypointWasInInstance then
        if C_Map.HasUserWaypoint() then
            C_Map.ClearUserWaypoint()
        end
        C_SuperTrack.ClearAllSuperTracked()
    end
    self.waypointWasInInstance = inInstance
end

function Maps:RefreshWaypointDestination()
    local label = self.waypointLabel
    if not label then return end
    local title
    if C_SuperTrack.IsSuperTrackingUserWaypoint() then
        local point = C_Map.GetUserWaypoint()
        if point then
            local info = C_Map.GetMapInfo(point.uiMapID)
            local position = point.position
            local x, y = position and position.x, position and position.y
            if IsNumber(x) and IsNumber(y) then
                title = format("%s · %.1f, %.1f", info and info.name or "Waypoint", x * 100, y * 100)
            end
        end
    elseif C_SuperTrack.IsSuperTrackingAnything() then
        -- Blizzard resolves the active target, including non-quest map pins.
        title = C_SuperTrack.GetSuperTrackedItemName()
    end
    if issecretvalue and issecretvalue(title) then title = nil end
    label:SetText(title or "")
    label:SetShown(title ~= nil and not self.waypointFrame.isClamped)
end

function Maps:UpdateWaypointDistance(frame)
    -- Reuse Blizzard's distance and update cadence. Do not mutate its cached distance,
    -- replace methods, or force the native distance text/arrow to be visible.
    local distance = frame.distance
    local near = self.db.Waypoint.ColorByDistance and IsNumber(distance)
        and distance >= 0 and distance <= self.db.Waypoint.NearDistance or false
    if near ~= self.waypointNear then
        self.waypointNear = near
        if near then
            frame.DistanceText:SetTextColor(0.3, 1, 0.4)
        else
            frame.DistanceText:SetTextColor(1, 0.82, 0)
        end
    end
    if self.waypointLabel then
        self.waypointLabel:SetShown(not frame.isClamped and self.waypointLabel:GetText() ~= "")
    end
end

function Maps:StyleWaypointIcon(frame)
    local scale = self.db.Waypoint.IconScale or 1.15
    frame.Icon:SetAtlas("Waypoint-MapPin-Tracked", true)
    frame.Icon:SetDrawLayer("OVERLAY", 3)
    frame.Icon:SetScale(scale)
    local size = math.max(frame.Icon:GetWidth(), frame.Icon:GetHeight()) * scale
    self.waypointBacking:SetSize(size + 40, size + 40)
    self.waypointPinHighlight:SetSize(size, size)
    self.waypointGlow:SetSize(size + 30, size + 30)
end

function Maps:UpdateWaypointArrow(frame, nativeArrowUpdated)
    local clamped = frame.isClamped and true or false
    if self.waypointClamped ~= clamped then
        self.waypointClamped = clamped
        frame.Arrow:SetScale(clamped and OFFSCREEN_ARROW_SCALE or 1)
    end
    if clamped and self.waypointOffscreenArrowAvailable then
        if not self.waypointArrowCustomized then
            self.waypointArrowAtlas = frame.Arrow:GetAtlas()
            self.waypointArrowTexture = frame.Arrow:GetTexture()
            self.waypointArrowTexCoord = { frame.Arrow:GetTexCoord() }
            local point, relativeTo, relativePoint, x, y = frame.Arrow:GetPoint(1)
            self.waypointArrowPoint = {
                point = point or "CENTER",
                relativeTo = relativeTo,
                relativePoint = relativePoint or "CENTER",
                x = IsNumber(x) and x or 0,
                y = IsNumber(y) and y or 0,
            }
            self.waypointArrowCustomized = true
        end
        if frame.Arrow:GetAtlas() ~= OFFSCREEN_ARROW_ATLAS then
            frame.Arrow:SetAtlas(OFFSCREEN_ARROW_ATLAS, true)
        end
        local rotation = frame.Arrow:GetRotation()
        if nativeArrowUpdated or self.waypointArrowBaseRotation == nil then
            self.waypointArrowBaseRotation = rotation
        end
        local adjustedRotation = (self.waypointArrowBaseRotation or 0) + OFFSCREEN_ARROW_ROTATION_OFFSET
        frame.Arrow:SetRotation(adjustedRotation)
        -- The radial pointer atlas already includes the ring-to-arrow spacing.
        -- Sharing the pin's center places its half ring around the pin's outside edge.
        local x, y = 0, 0
        local point, relativeTo, relativePoint, currentX, currentY = frame.Arrow:GetPoint(1)
        if point ~= "CENTER" or relativeTo ~= frame.Icon or relativePoint ~= "CENTER"
            or currentX ~= x or currentY ~= y then
            frame.Arrow:ClearAllPoints()
            frame.Arrow:SetPoint("CENTER", frame.Icon, "CENTER", x, y)
        end
    elseif self.waypointArrowCustomized then
        if self.waypointArrowAtlas then
            frame.Arrow:SetAtlas(self.waypointArrowAtlas, true)
        else
            frame.Arrow:SetTexture(self.waypointArrowTexture)
            frame.Arrow:SetTexCoord(unpack(self.waypointArrowTexCoord))
        end
        if not nativeArrowUpdated then
            frame.Arrow:SetRotation(self.waypointArrowBaseRotation or 0)
        end
        local anchor = self.waypointArrowPoint
        frame.Arrow:ClearAllPoints()
        frame.Arrow:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.x, anchor.y)
        self.waypointArrowCustomized = false
        self.waypointArrowBaseRotation = nil
        self.waypointArrowPoint = nil
    end
    local shown = frame.Icon:IsShown()
    local beamShown = shown and not clamped
    if self.waypointBeamShown ~= beamShown then
        self.waypointBeamShown = beamShown
        self.waypointBeam:SetShown(beamShown)
        if beamShown and frame:IsShown() then
            -- Restart both timelines from their minimum alpha in the same update.
            self.waypointBackingPulse:Stop()
            self.waypointBeamPulse:Stop()
            self.waypointBackingPulse:Play()
            self.waypointBeamPulse:Play()
        else
            self.waypointBeamPulse:Stop()
        end
    end
    if self.waypointIconShown ~= shown then
        self.waypointIconShown = shown
        self.waypointBacking:SetShown(shown)
        self.waypointPinHighlight:SetShown(shown)
        self.waypointGlow:SetShown(shown)
        if shown and frame:IsShown() then
            if not beamShown then
                self.waypointBackingPulse:Play()
            end
        else
            self.waypointBackingPulse:Stop()
            self.waypointBeamPulse:Stop()
        end
    end
end

function Maps:PulseWaypoint()
    local frame = self.waypointFrame
    if not self.waypointPulse then return end
    self.waypointPulse:Stop()
    if self.db.Waypoint.PulseOnChange ~= false and frame:IsShown()
        and frame.Icon:IsShown() and C_SuperTrack.IsSuperTrackingAnything() then
        self.waypointPulse:Play()
    end
end

function Maps:SetupWaypointIcon(frame)
    if not frame.Icon or not frame.Arrow then return end
    self.waypointOffscreenArrowAvailable = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(OFFSCREEN_ARROW_ATLAS) ~= nil
    -- Native animation groups are owned by the navigation frame so its
    -- fades and visibility still apply. No OnUpdate, timers, or method replacements.
    local beam = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
    beam:SetAtlas("shop-header-menu-selected-line-left")
    -- This atlas is a horizontal strip; rotate its long axis into a vertical beam.
    beam:SetRotation(3 * math.pi / 2)
    beam:SetDesaturated(true)
    beam:SetVertexColor(1, 0.82, 0)
    beam:SetAlpha(BEAM_ALPHA_MIN)
    beam:SetBlendMode("ADD")
    beam:SetSize(240, 28)
    -- Rotation is around the texture center and does not rotate its anchors.
    beam:SetPoint("CENTER", frame.Icon, "CENTER", 0, 120)
    self.waypointBeam = beam
    local beamPulse = beam:CreateAnimationGroup()
    beamPulse:SetLooping("REPEAT")
    local beamBrighten = beamPulse:CreateAnimation("Alpha")
    beamBrighten:SetOrder(1)
    beamBrighten:SetFromAlpha(BEAM_ALPHA_MIN)
    beamBrighten:SetToAlpha(BEAM_ALPHA_MAX)
    beamBrighten:SetDuration(0.8)
    local beamDim = beamPulse:CreateAnimation("Alpha")
    beamDim:SetOrder(2)
    beamDim:SetFromAlpha(BEAM_ALPHA_MAX)
    beamDim:SetToAlpha(BEAM_ALPHA_MIN)
    beamDim:SetDuration(0.8)
    beamPulse:SetScript("OnStop", function() beam:SetAlpha(BEAM_ALPHA_MIN) end)
    self.waypointBeamPulse = beamPulse

    local backing = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    backing:SetAtlas("AftLevelup-WhiteStarBurst")
    backing:SetVertexColor(1, 0.82, 0, 1)
    backing:SetAlpha(0.65)
    backing:SetBlendMode("ADD")
    backing:SetPoint("CENTER", frame.Icon, "CENTER")
    self.waypointBacking = backing
    local backingPulse = backing:CreateAnimationGroup()
    backingPulse:SetLooping("REPEAT")
    local brighten = backingPulse:CreateAnimation("Alpha")
    brighten:SetOrder(1)
    brighten:SetFromAlpha(0.65)
    brighten:SetToAlpha(1)
    brighten:SetDuration(0.8)
    local dim = backingPulse:CreateAnimation("Alpha")
    dim:SetOrder(2)
    dim:SetFromAlpha(1)
    dim:SetToAlpha(0.65)
    dim:SetDuration(0.8)
    backingPulse:SetScript("OnStop", function() backing:SetAlpha(0.65) end)
    self.waypointBackingPulse = backingPulse

    local pinHighlight = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    pinHighlight:SetAtlas("Waypoint-MapPin-Highlight", true)
    pinHighlight:SetVertexColor(1, 0.82, 0)
    pinHighlight:SetBlendMode("ADD")
    pinHighlight:SetPoint("CENTER", frame.Icon, "CENTER")
    pinHighlight:SetAlpha(0.8)
    self.waypointPinHighlight = pinHighlight

    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    glow:SetTexture("Interface\\Buttons\\IconBorder-GlowRing")
    glow:SetVertexColor(1, 0.82, 0.25)
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", frame.Icon, "CENTER")
    glow:SetAlpha(0)
    self.waypointGlow = glow
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("NONE")
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(0.85)
    fadeIn:SetDuration(0.12)
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetOrder(2)
    fadeOut:SetFromAlpha(0.85)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.38)
    local function ResetGlow() glow:SetAlpha(0) end
    pulse:SetScript("OnFinished", ResetGlow)
    pulse:SetScript("OnStop", ResetGlow)
    self.waypointPulse = pulse
    RefineUI:HookOnce("Waypoint:Icon", frame, "UpdateIcon", function(target)
        self:StyleWaypointIcon(target)
        self:UpdateWaypointArrow(target)
    end)
    RefineUI:HookOnce("Waypoint:IconSize", frame, "UpdateIconSize", function(target)
        self:StyleWaypointIcon(target)
    end)
    RefineUI:HookOnce("Waypoint:Arrow", frame, "UpdateArrow", function(target)
        self:UpdateWaypointArrow(target, true)
    end)
    RefineUI:HookScriptOnce("Waypoint:Hide", frame, "OnHide", function()
        pulse:Stop()
        backingPulse:Stop()
        beamPulse:Stop()
        self.waypointIconShown = nil
        self.waypointBeamShown = nil
    end)
    RefineUI:HookScriptOnce("Waypoint:Show", frame, "OnShow", function()
        self:UpdateWaypointArrow(frame)
    end)
    self:StyleWaypointIcon(frame)
    self:UpdateWaypointArrow(frame)
end

function Maps:AttachWaypointFrame()
    local frame = SuperTrackedFrame
    if self.waypointFrame or not frame or not frame.DistanceText then return end
    self.waypointFrame = frame
    self:SetupWaypointIcon(frame)
    frame.DistanceText:SetFont(RefineUI.Media.Fonts.Default, self.db.Waypoint.FontSize, "OUTLINE")
    frame.DistanceText:SetShadowColor(0, 0, 0, 1)
    frame.DistanceText:SetShadowOffset(1, -1)
    if self.db.Waypoint.ShowDestination then
        local label = frame:CreateFontString(nil, "OVERLAY")
        label:SetFont(RefineUI.Media.Fonts.Default, 12, "OUTLINE")
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(1, -1)
        label:SetPoint("TOP", frame.DistanceText, "BOTTOM", 0, -4)
        label:SetWidth(240)
        label:SetMaxLines(2)
        label:SetTextColor(1, 1, 1)
        self.waypointLabel = label
    end
    RefineUI:HookOnce("Waypoint:Distance", frame, "UpdateDistanceText", function(target)
        self:UpdateWaypointDistance(target)
    end)
    self:RefreshWaypointDestination()
    self:UpdateWaypointDistance(frame)
end

function Maps:SetupWaypoint()
    if not self.db.Waypoint or not self.db.Waypoint.Enable or self.waypointStarted then return end
    self.waypointStarted = true
    RefineUI:RegisterChatCommand("way", function(message) self:WaypointCommand(message) end)
    local function Refresh(event)
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            self:UpdateWaypointInstanceState()
        end
        self:AttachWaypointFrame()
        self:RefreshWaypointDestination()
        if event == "SUPER_TRACKING_CHANGED" then
            self:PulseWaypoint()
        elseif event == "USER_WAYPOINT_UPDATED" and C_SuperTrack.IsSuperTrackingUserWaypoint() then
            if C_Map.HasUserWaypoint() then
                self:PulseWaypoint()
            elseif self.waypointPulse then
                self.waypointPulse:Stop()
            end
        end
    end
    RefineUI:RegisterEventCallback("NAVIGATION_FRAME_DESTROYED", function()
        if self.waypointPulse then self.waypointPulse:Stop() end
        if self.waypointBackingPulse then self.waypointBackingPulse:Stop() end
        if self.waypointBeamPulse then self.waypointBeamPulse:Stop() end
        self.waypointIconShown = nil
        self.waypointBeamShown = nil
    end, "Waypoint:NavigationDestroyed")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED", "QUEST_LOG_UPDATE", "NAVIGATION_FRAME_CREATED" }) do
        RefineUI:RegisterEventCallback(event, Refresh, "Waypoint:" .. event)
    end
    -- Hook placement rather than reacting to all waypoint updates (including clearing).
    if self.db.Waypoint.AutoTrack then
        RefineUI:HookOnce("Waypoint:AutoTrack", C_Map, "SetUserWaypoint", function()
            if C_Map.HasUserWaypoint() then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
    end
    self:UpdateWaypointInstanceState()
    self:AttachWaypointFrame()
end
