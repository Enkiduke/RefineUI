----------------------------------------------------------------------------------------
-- GroupIcons for RefineUI
-- Description: Class-colored portrait icons for the player and party/raid members on the Minimap and WorldMap.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")
-- Follows the Maps module (including its menu toggle), then its own menu toggle/config.
local GroupIcons = RefineUI:RegisterModule("GroupIcons", function(cfg)
    return RefineUI:IsModuleStartupEnabled("Maps") and cfg.Maps.GroupIcons ~= false
end)

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs
local floor = math.floor
local pi = math.pi
local sin, cos = math.sin, math.cos
local unpack = unpack
local wipe = wipe

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UnitPosition = UnitPosition
local GetPlayerFacing = GetPlayerFacing
local UnitClass = UnitClass
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local GetNumGroupMembers = GetNumGroupMembers
local SetPortraitTexture = SetPortraitTexture
local C_Minimap = C_Minimap
local C_ClassColor = C_ClassColor
local C_Texture = C_Texture
local issecretvalue = issecretvalue
local Minimap = _G.Minimap
local GameTooltip = _G.GameTooltip

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------

local MINIMAP_ICON_SIZE = 18
local WORLDMAP_ICON_SIZE = 24
local UPDATE_INTERVAL = 0.1
local ARROW_ATLAS = "shop-header-arrow-hover"
local ARROW_SCALE = 1.0 -- Arrow length relative to the portrait
-- Arrow offset from the portrait edge; negative tucks it into the ring.
local MINIMAP_ARROW_GAP = -6
local WORLDMAP_ARROW_GAP = -10
-- The atlas rests pointing left (see NavigationBarNavigationButtonMixin:OnLoad texcoords).
local ARROW_ROTATION_OFFSET = -pi / 2
-- Blizzard's world map "you are here" ring (GroupMembersPinMixin).
local PING_TEXTURE = [[Interface\minimap\UI-Minimap-Ping-Expand]]
local PING_SCALE = 2.5
local PING_DURATION = 1.25
local PING_FADE_IN = 0.15

local PARTY_UNITS, RAID_UNITS = {}, {}
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end

local units = {}
local unitIndex = {}
local appliedGUIDs = {}
local numUnits = 0

local minimapLayer, minimapIcons = nil, {}
local worldMapLayer, worldMapIcons = nil, {}
local minimapPlayer, worldMapPlayer, groupMembersPin

----------------------------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------------------------

local function CreateIcon(parent, size, frameLevel)
    local textures = RefineUI.Media.Textures
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(size, size)
    icon:SetFrameLevel(frameLevel)

    local mask = icon:CreateMaskTexture()
    mask:SetTexture(textures.PortraitMask)
    mask:SetAllPoints(icon)

    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(textures.PortraitBG)
    bg:SetAllPoints(icon)
    bg:AddMaskTexture(mask)

    icon.Portrait = icon:CreateTexture(nil, "ARTWORK")
    icon.Portrait:SetAllPoints(icon)
    icon.Portrait:AddMaskTexture(mask)

    icon.Ring = icon:CreateTexture(nil, "OVERLAY")
    icon.Ring:SetTexture(textures.PortraitBorder)
    RefineUI.SetOutside(icon.Ring, icon)

    icon:Hide()
    return icon
end

local function ApplyUnit(icon, unit)
    SetPortraitTexture(icon.Portrait, unit)

    local r, g, b
    local _, classFile = UnitClass(unit)
    if not issecretvalue(classFile) and classFile then
        r, g, b = C_ClassColor.GetClassColor(classFile):GetRGB()
    else
        r, g, b = unpack(RefineUI.Config.General.BorderColor)
    end
    icon.Ring:SetVertexColor(r, g, b)
    if icon.Arrow then
        icon.Arrow:SetVertexColor(r, g, b)
    end
    if icon.Ping then
        icon.Ping:SetVertexColor(r, g, b)
    end
end

local function RefreshIcon(index)
    local unit = units[index]
    if minimapIcons[index] then ApplyUnit(minimapIcons[index], unit) end
    if worldMapIcons[index] then ApplyUnit(worldMapIcons[index], unit) end
end

local function RefreshPlayerIcons()
    ApplyUnit(minimapPlayer, "player")
    ApplyUnit(worldMapPlayer, "player")
end

-- Orbits the arrow around the portrait; facing is 0 at north and grows counterclockwise.
local function PointArrow(icon, facing)
    local radius = icon.arrowRadius
    icon.Arrow:SetPoint("CENTER", icon, "CENTER", -sin(facing) * radius, cos(facing) * radius)
    icon.Arrow:SetRotation(facing + ARROW_ROTATION_OFFSET)
end

local function OnPlayerIconShow(icon)
    icon.PingAnim:Play()
end

local function CreatePlayerIcon(parent, size, arrowGap, frameLevel)
    local icon = CreateIcon(parent, size, frameLevel)
    local arrowInfo = C_Texture.GetAtlasInfo(ARROW_ATLAS)
    local arrowLength = size * ARROW_SCALE
    -- Behind the portrait and ring, above the ping.
    icon.Arrow = icon:CreateTexture(nil, "BACKGROUND", nil, -1)
    icon.Arrow:SetAtlas(ARROW_ATLAS)
    icon.Arrow:SetSize(arrowLength, arrowLength * arrowInfo.height / arrowInfo.width)
    icon.Arrow:SetDesaturated(true)
    icon.arrowRadius = (size + arrowLength) / 2 + arrowGap
    PointArrow(icon, 0)
    return icon
end

local function AddPing(icon, size)
    icon.Ping = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.Ping:SetTexture(PING_TEXTURE)
    icon.Ping:SetSize(size, size)
    icon.Ping:SetPoint("CENTER")
    icon.Ping:SetDesaturated(true)
    icon.Ping:SetAlpha(0)

    local anim = icon.Ping:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    local grow = anim:CreateAnimation("Scale")
    grow:SetScaleFrom(1, 1)
    grow:SetScaleTo(PING_SCALE, PING_SCALE)
    grow:SetDuration(PING_DURATION)
    -- Fade in from 0: on a loop reset the scale can lag a frame at full size, so that frame must be invisible.
    local fadeIn = anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(PING_FADE_IN)
    local fadeOut = anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(PING_FADE_IN)
    fadeOut:SetDuration(PING_DURATION - PING_FADE_IN)
    icon.PingAnim = anim
    icon:SetScript("OnShow", OnPlayerIconShow)
end

local function OnWorldMapIconEnter(icon)
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(units[icon.index])
    GameTooltip:AddLine("Click to set a waypoint", 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

local function OnWorldMapIconLeave()
    GameTooltip:Hide()
end

local function OnWorldMapIconMouseUp(icon, button)
    if button ~= "LeftButton" then return end
    local mapID = _G.WorldMapFrame:GetMapID()
    local x, y = Maps:WorldToMapPosition(mapID, UnitPosition(units[icon.index]))
    if x then
        Maps:PlaceUserWaypoint(mapID, x, y)
    end
end

local function EnsureIcons(icons, parent, size, frameLevel, interactive)
    for i = #icons + 1, numUnits do
        local icon = CreateIcon(parent, size, frameLevel)
        icon.index = i
        if interactive then
            icon:EnableMouse(true)
            icon:SetScript("OnEnter", OnWorldMapIconEnter)
            icon:SetScript("OnLeave", OnWorldMapIconLeave)
            icon:SetScript("OnMouseUp", OnWorldMapIconMouseUp)
        end
        icons[i] = icon
    end
    for i = numUnits + 1, #icons do
        icons[i]:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Position Updates (only while a layer is shown)
----------------------------------------------------------------------------------------

local function UpdateMinimapIcons()
    if numUnits == 0 then return end
    local playerX, playerY, _, playerInstance = UnitPosition("player")
    local half = Minimap:GetWidth() / 2
    local pixelsPerYard = half / C_Minimap.GetViewRadius()
    local limit = half - MINIMAP_ICON_SIZE / 2

    for i = 1, numUnits do
        local icon = minimapIcons[i]
        local x, y, _, instance = UnitPosition(units[i])
        -- UnitPosition's first return grows north, its second grows west.
        if playerX and x and instance == playerInstance then
            local offsetX = (playerY - y) * pixelsPerYard
            local offsetY = (x - playerX) * pixelsPerYard
            if abs(offsetX) <= limit and abs(offsetY) <= limit then
                -- Whole units: skips re-anchoring on sub-pixel drift while anyone moves.
                offsetX, offsetY = floor(offsetX + 0.5), floor(offsetY + 0.5)
                if icon.x ~= offsetX or icon.y ~= offsetY then
                    icon.x, icon.y = offsetX, offsetY
                    icon:SetPoint("CENTER", minimapLayer, "CENTER", offsetX, offsetY)
                end
                icon:Show()
            else
                icon:Hide()
            end
        else
            icon:Hide()
        end
    end
end

local function PlaceWorldMapIcon(icon, unit, mapID, width, height, iconScale)
    local x, y = Maps:WorldToMapPosition(mapID, UnitPosition(unit))
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        local offsetX, offsetY = floor(x * width + 0.5), -floor(y * height + 0.5)
        if icon.scale ~= iconScale then
            icon.scale = iconScale
            icon:SetScale(iconScale)
        end
        if icon.x ~= offsetX or icon.y ~= offsetY then
            icon.x, icon.y = offsetX, offsetY
            icon:SetPoint("CENTER", worldMapLayer, "TOPLEFT", offsetX, offsetY)
        end
        icon:Show()
    else
        icon:Hide()
    end
end

local function UpdateWorldMapIcons()
    local canvas = worldMapLayer:GetParent()
    local mapID = _G.WorldMapFrame:GetMapID()
    -- Counter the canvas zoom so icons keep a constant on-screen size.
    local canvasScale = canvas:GetScale()
    local width = canvas:GetWidth() * canvasScale
    local height = canvas:GetHeight() * canvasScale
    local iconScale = 1 / canvasScale

    PlaceWorldMapIcon(worldMapPlayer, "player", mapID, width, height, iconScale)
    for i = 1, numUnits do
        PlaceWorldMapIcon(worldMapIcons[i], units[i], mapID, width, height, iconScale)
    end
end

-- Runs every frame so turning stays smooth; each layer only turns its own arrow while visible.
local function UpdatePlayerFacing(icon)
    local facing = GetPlayerFacing()
    if facing and facing ~= icon.facing then
        icon.facing = facing
        PointArrow(icon, facing)
    end
end

local function CreateLayer(parent, update)
    local layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints(parent)
    layer:Hide()

    local elapsedTotal = 0
    layer:SetScript("OnShow", update)
    layer:SetScript("OnUpdate", function(self, elapsed)
        UpdatePlayerFacing(self.player)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < UPDATE_INTERVAL then return end
        elapsedTotal = 0
        update()
    end)
    return layer
end

----------------------------------------------------------------------------------------
-- Roster
----------------------------------------------------------------------------------------

local function AddUnit(unit)
    numUnits = numUnits + 1
    units[numUnits] = unit
    unitIndex[unit] = numUnits
end

local function OnGroupPortraitUpdate(_, unit)
    local index = unitIndex[unit]
    if index then
        RefreshIcon(index)
    end
end

local function RebuildRoster()
    wipe(unitIndex)
    numUnits = 0

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = RAID_UNITS[i]
            local isPlayer = UnitIsUnit(unit, "player")
            if issecretvalue(isPlayer) or not isPlayer then
                AddUnit(unit)
            end
        end
    else
        for i = 1, GetNumGroupMembers() - 1 do
            AddUnit(PARTY_UNITS[i])
        end
    end
    for i = numUnits + 1, #units do
        units[i] = nil
    end

    EnsureIcons(minimapIcons, minimapLayer, MINIMAP_ICON_SIZE, minimapLayer:GetFrameLevel() + 1)
    EnsureIcons(worldMapIcons, worldMapLayer, WORLDMAP_ICON_SIZE, worldMapLayer:GetFrameLevel(), true)
    -- Unfiltered portrait updates (nameplates, target, ...) are only worth receiving while grouped.
    if numUnits > 0 then
        RefineUI:RegisterEventCallback("UNIT_PORTRAIT_UPDATE", OnGroupPortraitUpdate, "Maps:GroupIcons:UNIT_PORTRAIT_UPDATE")
    else
        RefineUI:OffEvent("UNIT_PORTRAIT_UPDATE", "Maps:GroupIcons:UNIT_PORTRAIT_UPDATE")
    end
    -- Unit tokens shift on every roster change; only re-render portraits whose owner changed.
    for i = 1, numUnits do
        local guid = UnitGUID(units[i])
        if issecretvalue(guid) or guid ~= appliedGUIDs[i] then
            appliedGUIDs[i] = guid
            RefreshIcon(i)
        end
    end

    -- Position and facing are unavailable to addons inside instances; Blizzard's pin takes over there.
    local active = not IsInInstance()
    minimapLayer:SetShown(active)
    worldMapLayer:SetShown(active)
    groupMembersPin:SetAlpha(active and 0 or 1)
end

local function RequestRosterRebuild()
    RefineUI:Debounce("Maps:GroupIcons:Roster", 0.2, RebuildRoster)
end

local function RequestPortraitRefresh()
    wipe(appliedGUIDs)
    RefreshPlayerIcons()
    RequestRosterRebuild()
end

----------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------

function GroupIcons:OnEnable()
    local worldMapFrame = _G.WorldMapFrame
    minimapLayer = CreateLayer(Minimap, UpdateMinimapIcons)
    minimapLayer:SetFrameLevel(Minimap:GetFrameLevel() + 3)

    worldMapLayer = CreateLayer(worldMapFrame.ScrollContainer.Child, UpdateWorldMapIcons)
    -- Draw just above Blizzard's native group member pin.
    worldMapLayer:SetFrameLevel(worldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER") + 1)

    -- Blizzard's permanent player/party pin; hidden by alpha only, since its appearance setters taint.
    for pin in worldMapFrame:EnumeratePinsByTemplate("GroupMembersPinTemplate") do
        groupMembersPin = pin
    end

    -- The minimap player arrow can't be hidden in 12.1, so this icon covers it.
    minimapPlayer = CreatePlayerIcon(minimapLayer, MINIMAP_ICON_SIZE, MINIMAP_ARROW_GAP, minimapLayer:GetFrameLevel() + 2)
    minimapPlayer:SetPoint("CENTER")
    minimapPlayer:Show()
    minimapLayer.player = minimapPlayer
    worldMapPlayer = CreatePlayerIcon(worldMapLayer, WORLDMAP_ICON_SIZE, WORLDMAP_ARROW_GAP, worldMapLayer:GetFrameLevel() + 1)
    AddPing(worldMapPlayer, WORLDMAP_ICON_SIZE)
    worldMapLayer.player = worldMapPlayer
    RefreshPlayerIcons()

    RefineUI:RegisterEventCallback("GROUP_ROSTER_UPDATE", RequestRosterRebuild, "Maps:GroupIcons:GROUP_ROSTER_UPDATE")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", RequestPortraitRefresh, "Maps:GroupIcons:PLAYER_ENTERING_WORLD")
    RefineUI:RegisterEventCallback("PORTRAITS_UPDATED", RequestPortraitRefresh, "Maps:GroupIcons:PORTRAITS_UPDATED")
    RefineUI:RegisterUnitEventCallback("UNIT_PORTRAIT_UPDATE", "player", RefreshPlayerIcons, "Maps:GroupIcons:UNIT_PORTRAIT_UPDATE:player")

    RebuildRoster()
end
