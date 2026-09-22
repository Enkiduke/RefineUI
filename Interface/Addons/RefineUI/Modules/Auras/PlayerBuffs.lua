----------------------------------------------------------------------------------------
-- RefineUI Player Buffs
-- Description: Secret-safe, managed player-buff filtering and styling for WoW 12.1+.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Auras = RefineUI:GetModule("Auras")
if not Auras then return end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local pairs = pairs
local math = math
local max = math.max
local min = math.min
local pcall = pcall
local string = string
local tonumber = tonumber
local type = type
local unpack = unpack

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BASE_ICON_SIZE = 32
local MAX_BUFFS_PER_GROUP = 32
local BORDER_INSET = 4
local BORDER_EDGE_SIZE = 8
local BORDER_COORD_START = 0.0625
local BORDER_TEXTURE = [[Interface\AddOns\RefineUI\Media\Textures\RefineBorder.blp]]
local COOLDOWN_SWIPE_OFFSET = 1.5
local COOLDOWN_FRAME_LEVEL_OFFSET = 50
local REFRESH_EVENT_KEY = "Auras:ManagedPlayerBuffs:PlayerRegenEnabled"
local DISPEL_OVERLAY_SLOT_KEY = "PlayerDispellableDebuff"
local DISPEL_OVERLAY_TEXTURE = [[Interface\FullScreenTextures\LowHealth]]
local DISPEL_OVERLAY_ALPHA = 0.40

local BORDER_PIECE_ORDER = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}

local BORDER_TEXTURE_UVS = {
    TopLeftCorner = { 0.5078125, BORDER_COORD_START, 0.5078125, 0.9375, 0.6171875, BORDER_COORD_START, 0.6171875, 0.9375 },
    TopRightCorner = { 0.6328125, BORDER_COORD_START, 0.6328125, 0.9375, 0.7421875, BORDER_COORD_START, 0.7421875, 0.9375 },
    BottomLeftCorner = { 0.7578125, BORDER_COORD_START, 0.7578125, 0.9375, 0.8671875, BORDER_COORD_START, 0.8671875, 0.9375 },
    BottomRightCorner = { 0.8828125, BORDER_COORD_START, 0.8828125, 0.9375, 0.9921875, BORDER_COORD_START, 0.9921875, 0.9375 },
    TopEdge = { 0.2578125, "repeatX", 0.3671875, "repeatX", 0.2578125, BORDER_COORD_START, 0.3671875, BORDER_COORD_START },
    BottomEdge = { 0.3828125, "repeatX", 0.4921875, "repeatX", 0.3828125, BORDER_COORD_START, 0.4921875, BORDER_COORD_START },
    LeftEdge = { 0.0078125, BORDER_COORD_START, 0.0078125, "repeatY", 0.1171875, BORDER_COORD_START, 0.1171875, "repeatY" },
    RightEdge = { 0.1328125, BORDER_COORD_START, 0.1328125, "repeatY", 0.2421875, BORDER_COORD_START, 0.2421875, "repeatY" },
}

local DEFAULT_GROUPS = {
    Important = { Enable = true, Scale = 1.00, BorderColor = { 1.00, 0.55, 0.10, 1 } },
    BigDefensive = { Enable = true, Scale = 1.00, BorderColor = { 0.20, 0.75, 1.00, 1 } },
    ExternalDefensive = { Enable = true, Scale = 1.00, BorderColor = { 1.00, 0.40, 0.85, 1 } },
    Self = { Enable = true, Scale = 1.00, BorderColor = { 0.12, 0.90, 0.12, 1 } },
    External = { Enable = true, Scale = 1.00, BorderColor = { 0.35, 0.65, 1.00, 1 } },
    WeaponEnchant = { Enable = true, Scale = 1.00, BorderColor = { 0.65, 0.25, 0.90, 1 } },
}

local GROUP_DEFINITIONS = {
    { key = "Important", label = "Important Buffs" },
    { key = "BigDefensive", label = "Big Defensives" },
    { key = "ExternalDefensive", label = "External Defensives" },
    { key = "Self", label = "Self Buffs" },
    { key = "External", label = "External Buffs" },
}

local DURATION_FILTERS = {
    ALL = nil,
    THIRTY_SECONDS = 30,
    ONE_MINUTE = 60,
    TWO_MINUTES = 120,
    FIVE_MINUTES = 300,
    TIMED = math.huge,
}

----------------------------------------------------------------------------------------
-- Configuration Helpers
----------------------------------------------------------------------------------------
local function ClampNumber(value, low, high, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return max(low, min(high, value))
end

local function CopyDefaultColor(defaultColor)
    return { defaultColor[1], defaultColor[2], defaultColor[3], defaultColor[4] or 1 }
end

local function EnsurePlayerBuffConfig()
    Config.Auras = Config.Auras or {}
    local cfg = Config.Auras.PlayerBuffs
    if type(cfg) ~= "table" then
        cfg = {}
        Config.Auras.PlayerBuffs = cfg
    end

    if not DURATION_FILTERS[cfg.DurationFilter] and cfg.DurationFilter ~= "ALL" then
        cfg.DurationFilter = "ALL"
    end

    if type(cfg.Groups) ~= "table" then
        cfg.Groups = {}
    end

    for key, defaults in pairs(DEFAULT_GROUPS) do
        local group = cfg.Groups[key]
        if type(group) ~= "table" then
            group = {}
            cfg.Groups[key] = group
        end
        if group.Enable == nil then group.Enable = defaults.Enable end
        group.Scale = ClampNumber(group.Scale, 0.50, 2.00, defaults.Scale)
        if type(group.BorderColor) ~= "table" then
            group.BorderColor = CopyDefaultColor(defaults.BorderColor)
        end
        for index = 1, 4 do
            group.BorderColor[index] = ClampNumber(
                group.BorderColor[index], 0, 1, defaults.BorderColor[index] or 1)
        end
    end

    return cfg
end

local function GetGroupConfig(key)
    return EnsurePlayerBuffConfig().Groups[key]
end

----------------------------------------------------------------------------------------
-- Secret-state Helpers
----------------------------------------------------------------------------------------
local function AurasAreSecret()
    local secrets = _G.C_Secrets
    if not secrets or type(secrets.ShouldAurasBeSecret) ~= "function" then return false end
    local ok, result = pcall(secrets.ShouldAurasBeSecret)
    if not ok then return true end
    if _G.issecretvalue and _G.issecretvalue(result) then return true end
    return result == true
end

local function ManagedBuffsSupported()
    return _G.AuraUtil
        and type(_G.AuraUtil.CreateFilterString) == "function"
        and _G.AuraUtil.AuraFilters
        and _G.AuraContainerSortMethod
        and _G.AuraContainerSortDirection
        and _G.AnchorUtil
        and _G.AnchorUtil.FlowLayoutAxis
        and _G.AnchorUtil.FlowDirection
        and _G.CustomAuraContainerItemEnchantmentPlacement
        and _G.AuraContainerItemEnchantmentSlot
        and _G.BuffFrame
end

local function PlayerDispelOverlaySupported()
    local filter = _G.AuraUtil and _G.AuraUtil.AuraFilters
    local sortMethod = _G.AuraContainerSortMethod
    local sortDirection = _G.AuraContainerSortDirection

    return _G.AuraUtil
        and type(_G.AuraUtil.CreateFilterString) == "function"
        and filter
        and filter.Harmful
        and filter.Raid
        and sortMethod
        and sortMethod.UnitFrameDebuff
        and sortDirection
        and sortDirection.Normal
        and _G.Enum
        and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
        and _G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
        and _G.UIParent
end

function Auras:IsManagedPlayerBuffsSupported()
    return ManagedBuffsSupported() and true or false
end

local function InitializePlayerDispelOverlayButton(button)
    button:SetAllPoints(button:GetParent())
    button:EnableMouse(false)

    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetTexture(DISPEL_OVERLAY_TEXTURE)
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(true)

    button:AddDispelTypeTexture(texture, {
        showWhenHarmful = true,
        showWhenHelpful = false,
        showWithoutDispelType = false,
        style = _G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
        customDispelColorCurve = Auras:GetDispelColorCurve(DISPEL_OVERLAY_ALPHA),
    })
end

function Auras:InitializePlayerDispelOverlay()
    if self.PlayerDispelOverlayContainer then return true end
    if not PlayerDispelOverlaySupported() then return false end

    local ok, containerOrError = pcall(CreateFrame,
        "AuraContainer", "RefineUI_PlayerDispelOverlay", _G.UIParent, "CustomAuraContainerTemplate")
    if not ok or not containerOrError then
        self:Error("Player dispel overlay is unavailable:", containerOrError)
        return false
    end

    local container = containerOrError
    container:SetAllPoints(_G.UIParent)
    container:SetFrameStrata("FULLSCREEN")
    container:EnableMouse(false)
    container:SetUnit("player")
    self.PlayerDispelOverlayContainer = container

    local filter = _G.AuraUtil.AuraFilters
    local dispellableByPlayer = _G.AuraUtil.CreateFilterString(filter.Harmful, filter.Raid)
    local configured, configureError = pcall(function()
        container:AddAuraSlot(DISPEL_OVERLAY_SLOT_KEY, dispellableByPlayer, {
            sortMethod = _G.AuraContainerSortMethod.UnitFrameDebuff,
            sortDirection = _G.AuraContainerSortDirection.Normal,
            initializeFrame = InitializePlayerDispelOverlayButton,
        })
    end)

    if not configured then
        container:Hide()
        self.PlayerDispelOverlayContainer = nil
        self:Error("Unable to configure player dispel overlay:", configureError)
        return false
    end

    return true
end

----------------------------------------------------------------------------------------
-- Managed Button Styling
----------------------------------------------------------------------------------------
local function ResolveBorderCoord(value, repeatX, repeatY)
    if value == "repeatX" then return repeatX end
    if value == "repeatY" then return repeatY end
    return value
end

local function UpdateManagedBorder(button)
    local border = button and button.RefineManagedBorder
    if not border then return end

    local width = border:GetWidth()
    local height = border:GetHeight()
    local effectiveScale = border:GetEffectiveScale()
    local repeatX = max(0, (width / BORDER_EDGE_SIZE) * effectiveScale - 2 - BORDER_COORD_START)
    local repeatY = max(0, (height / BORDER_EDGE_SIZE) * effectiveScale - 2 - BORDER_COORD_START)

    for pieceName, coords in pairs(BORDER_TEXTURE_UVS) do
        local texture = border[pieceName]
        texture:SetTexCoord(
            ResolveBorderCoord(coords[1], repeatX, repeatY),
            ResolveBorderCoord(coords[2], repeatX, repeatY),
            ResolveBorderCoord(coords[3], repeatX, repeatY),
            ResolveBorderCoord(coords[4], repeatX, repeatY),
            ResolveBorderCoord(coords[5], repeatX, repeatY),
            ResolveBorderCoord(coords[6], repeatX, repeatY),
            ResolveBorderCoord(coords[7], repeatX, repeatY),
            ResolveBorderCoord(coords[8], repeatX, repeatY))
    end
end

local function SetManagedBorderColor(button, color)
    local border = button and button.RefineManagedBorder
    if not border then return end

    for index = 1, #border.Pieces do
        border.Pieces[index]:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function CreateManagedBorder(button)
    -- CustomAuraContainer buttons can already be secret/restricted here. Build the
    -- border directly in initializeFrame and avoid scripts/hooks on the aura button.
    local border = CreateFrame("Frame", nil, button)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -BORDER_INSET, BORDER_INSET)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", BORDER_INSET, -BORDER_INSET)
    border:SetFrameLevel(button:GetFrameLevel() + 2)
    border:EnableMouse(false)
    border.Pieces = {}

    for index = 1, #BORDER_PIECE_ORDER do
        local pieceName = BORDER_PIECE_ORDER[index]
        local texture = border:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetBlendMode("BLEND")
        texture:SetTexture(BORDER_TEXTURE, true, true)
        border[pieceName] = texture
        border.Pieces[index] = texture
    end

    local tl, tr = border.TopLeftCorner, border.TopRightCorner
    local bl, br = border.BottomLeftCorner, border.BottomRightCorner
    local top, bottom = border.TopEdge, border.BottomEdge
    local left, right = border.LeftEdge, border.RightEdge

    tl:SetPoint("TOPLEFT", border, "TOPLEFT")
    tr:SetPoint("TOPRIGHT", border, "TOPRIGHT")
    bl:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT")
    br:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT")
    tl:SetSize(BORDER_EDGE_SIZE, BORDER_EDGE_SIZE)
    tr:SetSize(BORDER_EDGE_SIZE, BORDER_EDGE_SIZE)
    bl:SetSize(BORDER_EDGE_SIZE, BORDER_EDGE_SIZE)
    br:SetSize(BORDER_EDGE_SIZE, BORDER_EDGE_SIZE)

    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    top:SetHeight(BORDER_EDGE_SIZE)
    bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    bottom:SetHeight(BORDER_EDGE_SIZE)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    left:SetWidth(BORDER_EDGE_SIZE)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    right:SetWidth(BORDER_EDGE_SIZE)

    button.RefineManagedBorder = border
end

local function ApplyButtonStyle(button, style)
    if not button or not style then return end

    local scale = ClampNumber(style.scale, 0.50, 2.00, 1)
    local size = BASE_ICON_SIZE * scale
    button:SetSize(size, size)

    if button.RefineIcon then
        button.RefineIcon:ClearAllPoints()
        button.RefineIcon:SetAllPoints(button)
    end
    if button.RefineCooldown then
        local swipeOffset = COOLDOWN_SWIPE_OFFSET * scale
        button.RefineCooldown:ClearAllPoints()
        button.RefineCooldown:SetPoint(
            "TOPLEFT", button, "TOPLEFT", -swipeOffset, swipeOffset)
        button.RefineCooldown:SetPoint(
            "BOTTOMRIGHT", button, "BOTTOMRIGHT", swipeOffset, -swipeOffset)
        button.RefineCooldown:SetFrameLevel(button:GetFrameLevel() + COOLDOWN_FRAME_LEVEL_OFFSET)
    end

    local color = style.color or { 1, 1, 1, 1 }
    UpdateManagedBorder(button)
    SetManagedBorderColor(button, color)

    button:SetAlpha(style.enabled == false and 0 or 1)
    if not InCombatLockdown() and button.EnableMouse then
        button:EnableMouse(style.enabled ~= false)
    end
end

local function InitializeAuraButton(button, style)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.RefineIcon = icon
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetMinimumCountdownDuration(0)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetFrameLevel(button:GetFrameLevel() + COOLDOWN_FRAME_LEVEL_OFFSET)
    if RefineUI.Media and RefineUI.Media.Textures and RefineUI.Media.Textures.CooldownSwipe then
        cooldown:SetSwipeTexture(RefineUI.Media.Textures.CooldownSwipe)
    end
    button.RefineCooldown = cooldown
    button:SetDurationCooldown(cooldown)

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    RefineUI.Font(count, 12, nil, "OUTLINE")
    button.RefineCount = count
    button:SetApplicationCount(count)

    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT", 0, 0)
    button:SetHideTooltipInCombat(false)
    button:SetCancelAuraButtons("RightButtonUp")
    button.RefineBuffStyle = style

    CreateManagedBorder(button)
    ApplyButtonStyle(button, style)
end

local function RefreshStyleTable(style, key)
    local cfg = GetGroupConfig(key)
    style.enabled = cfg.Enable ~= false
    style.scale = cfg.Scale
    style.color = cfg.BorderColor
end

----------------------------------------------------------------------------------------
-- Aura Group Construction
----------------------------------------------------------------------------------------
local function BuildGroupFilterString(key)
    local auraUtil = _G.AuraUtil
    local filter = auraUtil.AuraFilters
    local parts = { filter.Helpful }

    if key == "Important" then
        parts[#parts + 1] = filter.Important
        parts[#parts + 1] = "!" .. filter.BigDefensive
        parts[#parts + 1] = "!" .. filter.ExternalDefensive
    elseif key == "BigDefensive" then
        parts[#parts + 1] = filter.BigDefensive
    elseif key == "ExternalDefensive" then
        parts[#parts + 1] = "!" .. filter.BigDefensive
        parts[#parts + 1] = filter.ExternalDefensive
    elseif key == "Self" then
        parts[#parts + 1] = filter.Player
        parts[#parts + 1] = "!" .. filter.Important
        parts[#parts + 1] = "!" .. filter.BigDefensive
        parts[#parts + 1] = "!" .. filter.ExternalDefensive
    elseif key == "External" then
        parts[#parts + 1] = "!" .. filter.Player
        parts[#parts + 1] = "!" .. filter.Important
        parts[#parts + 1] = "!" .. filter.BigDefensive
        parts[#parts + 1] = "!" .. filter.ExternalDefensive
    end

    return auraUtil.CreateFilterString(unpack(parts))
end

local function GetDurationCandidateFilters()
    local mode = EnsurePlayerBuffConfig().DurationFilter or "ALL"
    local maximum = DURATION_FILTERS[mode]
    if maximum == nil then return {} end
    return { maxDuration = maximum }
end

local function GetBlizzardBuffLayout()
    local frame = _G.BuffFrame
    local layout = frame and frame.AuraContainer
    return {
        isHorizontal = not layout or layout.isHorizontal ~= false,
        addIconsToRight = layout and layout.addIconsToRight == true,
        addIconsToTop = layout and layout.addIconsToTop == true,
        iconStride = (layout and layout.iconStride) or 8,
        iconScale = (layout and layout.iconScale) or 1,
        iconPadding = (layout and layout.iconPadding) or 5,
    }
end

local function GetContainerAnchorPoint(layout)
    if layout.addIconsToTop then
        return layout.addIconsToRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
    end
    return layout.addIconsToRight and "TOPLEFT" or "TOPRIGHT"
end

local function SuppressLegacyBuffFrame()
    local frame = _G.BuffFrame
    if not frame then return end

    if frame.AuraContainer then
        frame.AuraContainer:Hide()
    end

    -- Blizzard's legacy container is already hidden. Do not inspect or reparent its
    -- aura buttons while their values and frames may be restricted.
    if AurasAreSecret() then return end

    local holder = Auras._legacyBuffHolder
    if not holder then
        holder = CreateFrame("Frame", nil, _G.UIParent)
        holder:Hide()
        Auras._legacyBuffHolder = holder
    end

    for _, list in ipairs({ frame.auraFrames, frame.exampleAuraFrames }) do
        if type(list) == "table" then
            for _, button in ipairs(list) do
                local forbidden = button and button.IsForbidden and button:IsForbidden()
                if button and not forbidden and button:GetParent() ~= holder then
                    button:SetParent(holder)
                    button:Hide()
                end
            end
        end
    end

    if frame.ConsolidatedBuffs then frame.ConsolidatedBuffs:Hide() end
    if frame.CollapseAndExpandButton then frame.CollapseAndExpandButton:Hide() end
end

local function ConfigureContainerLayout(container)
    local layout = GetBlizzardBuffLayout()
    local point = GetContainerAnchorPoint(layout)
    local padding = ClampNumber(layout.iconPadding, 0, 24, 5)
    local stride = math.floor(ClampNumber(layout.iconStride, 1, 32, 8) + 0.5)

    container:SetFlowLayoutAxis(layout.isHorizontal
        and _G.AnchorUtil.FlowLayoutAxis.Horizontal
        or _G.AnchorUtil.FlowLayoutAxis.Vertical)
    container:SetFlowLayoutAnchorPoint(point)
    container:SetFlowLayoutGrowthDirection(
        layout.addIconsToRight and _G.AnchorUtil.FlowDirection.Right or _G.AnchorUtil.FlowDirection.Left,
        layout.addIconsToTop and _G.AnchorUtil.FlowDirection.Up or _G.AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    container:SetFlowLayoutMaximumLineSize(stride * BASE_ICON_SIZE + max(0, stride - 1) * padding)
    container:SetScale(ClampNumber(layout.iconScale, 0.5, 2.0, 1))
    container:ClearAllPoints()
    container:SetPoint(point, _G.BuffFrame, point, 0, 0)

    for index, definition in ipairs(GROUP_DEFINITIONS) do
        local cfg = GetGroupConfig(definition.key)
        local size = BASE_ICON_SIZE * cfg.Scale
        container:SetAuraGroupLayout(definition.key, {
            elementSpacing = padding,
            lineSpacing = padding,
            groupSpacing = padding,
            groupLineSpacing = padding,
            elementWidth = size,
            elementHeight = size,
            layoutIndex = index,
        })
    end

    local enchantCfg = GetGroupConfig("WeaponEnchant")
    local enchantSize = enchantCfg.Enable ~= false and (BASE_ICON_SIZE * enchantCfg.Scale) or 0
    container:SetItemEnchantmentLayout({
        placement = _G.CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups,
        elementSpacing = padding,
        lineSpacing = padding,
        groupSpacing = padding,
        elementWidth = enchantSize,
        elementHeight = enchantSize,
        layoutIndex = 0,
    })
end

local function RestyleManagedButtons(container)
    for _, definition in ipairs(GROUP_DEFINITIONS) do
        local key = definition.key
        local style = Auras._managedBuffStyles[key]
        local count = container:GetAuraGroupFrameCount(key)
        for index = 1, count do
            local button = container:GetAuraGroupFrame(key, index)
            local forbidden = button and button.IsForbidden and button:IsForbidden()
            if button and not forbidden then
                ApplyButtonStyle(button, style)
            end
        end
    end

    local enchantStyle = Auras._managedBuffStyles.WeaponEnchant
    for _, button in ipairs(Auras._managedEnchantButtons or {}) do
        local forbidden = button and button.IsForbidden and button:IsForbidden()
        if button and not forbidden then
            ApplyButtonStyle(button, enchantStyle)
        end
    end
end

----------------------------------------------------------------------------------------
-- Runtime Refresh
----------------------------------------------------------------------------------------
function Auras:RefreshManagedPlayerBuffs()
    local container = self.ManagedPlayerBuffContainer
    if not container then return end

    if AurasAreSecret() then
        self._managedBuffRefreshPending = true
        return
    end
    self._managedBuffRefreshPending = nil

    for key, style in pairs(self._managedBuffStyles) do
        RefreshStyleTable(style, key)
    end

    local candidateFilters = GetDurationCandidateFilters()
    for _, definition in ipairs(GROUP_DEFINITIONS) do
        local cfg = GetGroupConfig(definition.key)
        container:SetAuraGroupFilterString(definition.key, BuildGroupFilterString(definition.key))
        container:SetAuraGroupCandidateFilters(definition.key, candidateFilters)
        container:SetAuraGroupMaxFrameCount(
            definition.key, cfg.Enable ~= false and MAX_BUFFS_PER_GROUP or 0)
    end

    ConfigureContainerLayout(container)
    RestyleManagedButtons(container)
    container:UpdateAllAuras()
    SuppressLegacyBuffFrame()
end

----------------------------------------------------------------------------------------
-- Edit Mode Settings
----------------------------------------------------------------------------------------
local function FormatScalePercent(value)
    return string.format("%d%%", math.floor(((value or 1) * 100) + 0.5))
end

local function BuildMenuColorInfo(color)
    return {
        r = color[1] or 1,
        g = color[2] or 1,
        b = color[3] or 1,
        opacity = color[4] or 1,
        hasOpacity = 1,
    }
end

local function OpenGroupBorderColorPicker(key)
    if not _G.ColorPickerFrame or type(_G.ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
        return
    end

    local cfg = GetGroupConfig(key)
    local color = {
        cfg.BorderColor[1], cfg.BorderColor[2], cfg.BorderColor[3], cfg.BorderColor[4] or 1,
    }

    local function CommitColor()
        local target = GetGroupConfig(key).BorderColor
        target[1], target[2], target[3], target[4] = color[1], color[2], color[3], color[4]
        Auras:RefreshManagedPlayerBuffs()
    end

    local info = BuildMenuColorInfo(color)
    info.swatchFunc = function()
        color[1], color[2], color[3] = _G.ColorPickerFrame:GetColorRGB()
        CommitColor()
    end
    info.opacityFunc = function()
        color[4] = _G.ColorPickerFrame:GetColorAlpha()
        CommitColor()
    end
    info.cancelFunc = function(previous)
        if previous then
            color[1] = previous.r or color[1]
            color[2] = previous.g or color[2]
            color[3] = previous.b or color[3]
            color[4] = previous.a or previous.opacity or color[4]
        end
        CommitColor()
    end

    _G.ColorPickerFrame:SetupColorPickerAndShow(info)
end

local function BuildGroupSettingsMenu(owner, rootDescription, key, label)
    local cfg = GetGroupConfig(key)

    local function UpdateSummary()
        if owner and type(owner.SetDefaultText) == "function" then
            local group = GetGroupConfig(key)
            owner:SetDefaultText(
                (group.Enable ~= false and "Shown, " or "Hidden, ") .. FormatScalePercent(group.Scale))
        end
    end
    UpdateSummary()

    rootDescription:CreateTitle(label)
    rootDescription:CreateCheckbox("Show", function()
        return GetGroupConfig(key).Enable ~= false
    end, function()
        local group = GetGroupConfig(key)
        group.Enable = group.Enable == false
        Auras:RefreshManagedPlayerBuffs()
        UpdateSummary()
    end)

    local scaleMenu = rootDescription:CreateButton("Scale: " .. FormatScalePercent(cfg.Scale))
    if scaleMenu and type(scaleMenu.SetScrollMode) == "function" then
        scaleMenu:SetScrollMode(300)
    end
    for percent = 50, 200, 5 do
        local selectedPercent = percent
        local selectedScale = selectedPercent / 100
        scaleMenu:CreateRadio(selectedPercent .. "%", function()
            return math.abs(GetGroupConfig(key).Scale - selectedScale) < 0.001
        end, function()
            GetGroupConfig(key).Scale = selectedScale
            Auras:RefreshManagedPlayerBuffs()
            UpdateSummary()
        end)
    end

    local borderColor = cfg.BorderColor
    rootDescription:CreateColorSwatch("Border Color", function()
        OpenGroupBorderColorPicker(key)
    end, BuildMenuColorInfo(borderColor))
end

local function RegisterManagedBuffEditModeSettings()
    if Auras._managedBuffEditModeSettingsRegistered then return true end

    local lib = RefineUI.LibEditMode
    local enums = _G.Enum
    local system = enums and enums.EditModeSystem and enums.EditModeSystem.AuraFrame
    local systemIndices = enums and enums.EditModeAuraFrameSystemIndices
    local buffIndex = systemIndices and systemIndices.BuffFrame
    if not lib or type(lib.AddSystemSettings) ~= "function" or not lib.SettingType
        or system == nil or buffIndex == nil then
        return false
    end

    local settingType = lib.SettingType
    local settings = {}

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Duration",
        desc = "Filter using each aura's total duration. Any timed filter also hides permanent buffs.",
        default = "ALL",
        values = {
            { text = "All durations", value = "ALL" },
            { text = "30 seconds or less", value = "THIRTY_SECONDS" },
            { text = "1 minute or less", value = "ONE_MINUTE" },
            { text = "2 minutes or less", value = "TWO_MINUTES" },
            { text = "5 minutes or less", value = "FIVE_MINUTES" },
            { text = "All timed buffs", value = "TIMED" },
        },
        get = function()
            return EnsurePlayerBuffConfig().DurationFilter or "ALL"
        end,
        set = function(_, value)
            if value ~= "ALL" and DURATION_FILTERS[value] == nil then value = "ALL" end
            EnsurePlayerBuffConfig().DurationFilter = value
            Auras:RefreshManagedPlayerBuffs()
        end,
    }

    local function AddGroupSettings(key, label, shortLabel)
        local defaults = DEFAULT_GROUPS[key]
        settings[#settings + 1] = {
            kind = settingType.Dropdown,
            name = shortLabel or label,
            desc = "Configure visibility, icon scale, and border color for " .. string.lower(label) .. ".",
            default = key,
            get = function()
                return key
            end,
            set = function()
                local cfg = GetGroupConfig(key)
                cfg.Enable = defaults.Enable
                cfg.Scale = defaults.Scale
                cfg.BorderColor = CopyDefaultColor(defaults.BorderColor)
                Auras:RefreshManagedPlayerBuffs()
            end,
            generator = function(owner, rootDescription)
                BuildGroupSettingsMenu(owner, rootDescription, key, label)
            end,
        }
    end

    AddGroupSettings("Important", "Important Buffs", "Important")
    AddGroupSettings("BigDefensive", "Big Defensives", "Big Defensive")
    AddGroupSettings("ExternalDefensive", "External Defensives", "External Def.")
    AddGroupSettings("Self", "Self Buffs", "Self")
    AddGroupSettings("External", "External Buffs", "External")
    AddGroupSettings("WeaponEnchant", "Weapon Enchants", "Weapon Enchant")

    lib:AddSystemSettings(system, settings, buffIndex)
    Auras._managedBuffEditModeSettings = settings
    Auras._managedBuffEditModeSettingsRegistered = true
    return true
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Auras:InitializeManagedPlayerBuffs()
    if self.ManagedPlayerBuffContainer then return true end
    if not ManagedBuffsSupported() then return false end

    EnsurePlayerBuffConfig()

    self._managedBuffStyles = self._managedBuffStyles or {}
    for key in pairs(DEFAULT_GROUPS) do
        local style = self._managedBuffStyles[key] or {}
        self._managedBuffStyles[key] = style
        RefreshStyleTable(style, key)
    end

    local ok, containerOrError = pcall(CreateFrame,
        "AuraContainer", "RefineUI_PlayerBuffContainer", _G.BuffFrame, "CustomAuraContainerTemplate")
    if not ok or not containerOrError then
        self:Error("Managed player buffs are unavailable:", containerOrError)
        return false
    end

    local container = containerOrError
    container:SetSize(1, 1)
    container:SetUnit("player")
    self.ManagedPlayerBuffContainer = container

    local sortMethod = _G.AuraContainerSortMethod.AuraInstanceIDOnly
        or _G.AuraContainerSortMethod.Default
    local sortDirection = _G.AuraContainerSortDirection.Normal

    local configured, configureError = pcall(function()
        for index, definition in ipairs(GROUP_DEFINITIONS) do
            local key = definition.key
            local style = self._managedBuffStyles[key]
            container:AddAuraGroup(key, BuildGroupFilterString(key), {
                maxFrameCount = GetGroupConfig(key).Enable ~= false and MAX_BUFFS_PER_GROUP or 0,
                candidateFilters = GetDurationCandidateFilters(),
                sortMethod = sortMethod,
                sortDirection = sortDirection,
                layout = { layoutIndex = index },
                initializeFrame = function(button)
                    InitializeAuraButton(button, style)
                end,
            })
        end

        self._managedEnchantButtons = {}
        local enchantStyle = self._managedBuffStyles.WeaponEnchant
        for _, slot in ipairs({
            _G.AuraContainerItemEnchantmentSlot.MainHand,
            _G.AuraContainerItemEnchantmentSlot.OffHand,
            _G.AuraContainerItemEnchantmentSlot.Ranged,
        }) do
            if slot ~= nil then
                local button = container:AddItemEnchantment(slot, {
                    hidePermanent = true,
                    initializeFrame = function(enchantButton)
                        InitializeAuraButton(enchantButton, enchantStyle)
                    end,
                })
                self._managedEnchantButtons[#self._managedEnchantButtons + 1] = button
            end
        end
    end)

    if not configured then
        container:Hide()
        self.ManagedPlayerBuffContainer = nil
        self:Error("Unable to configure managed player buffs:", configureError)
        return false
    end

    -- Establish anchoring and group geometry immediately. A reload can occur while
    -- aura data is secret, in which case the normal refresh intentionally waits.
    ConfigureContainerLayout(container)

    if type(_G.BuffFrame.UpdateAuraButtons) == "function" then
        RefineUI:HookOnce("Auras:ManagedPlayerBuffs:UpdateAuraButtons",
            _G.BuffFrame, "UpdateAuraButtons", SuppressLegacyBuffFrame)
    end
    if type(_G.BuffFrame.UpdateGridLayout) == "function" then
        RefineUI:HookOnce("Auras:ManagedPlayerBuffs:UpdateGridLayout",
            _G.BuffFrame, "UpdateGridLayout", function()
                Auras:RefreshManagedPlayerBuffs()
            end)
    end
    if type(_G.BuffFrame.OnEditModeEnter) == "function" then
        RefineUI:HookOnce("Auras:ManagedPlayerBuffs:OnEditModeEnter",
            _G.BuffFrame, "OnEditModeEnter", function()
                Auras:RefreshManagedPlayerBuffs()
            end)
    end

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if Auras._managedBuffRefreshPending then
            Auras:RefreshManagedPlayerBuffs()
        end
    end, REFRESH_EVENT_KEY)

    local settingsRegistered, settingsError = pcall(RegisterManagedBuffEditModeSettings)
    if not settingsRegistered then
        self:Error("Unable to register player-buff Edit Mode settings:", settingsError)
    end
    SuppressLegacyBuffFrame()
    self:RefreshManagedPlayerBuffs()
    return true
end
