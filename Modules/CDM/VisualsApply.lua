----------------------------------------------------------------------------------------
-- CDM Component: VisualsApply
-- Description: Application of visual overrides to cooldown viewer frames.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local next = next
local format = string.format

local CreateFrame = CreateFrame
local GetTime = GetTime
local ColorPickerFrame = ColorPickerFrame
local Menu = Menu
local EventRegistry = _G.EventRegistry
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local CATEGORY_ESSENTIAL = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
local CATEGORY_UTILITY = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility
local DEFAULT_BAR_COLOR_FALLBACK = { 1, 0.5, 0.25, 1 }
local SWIPE_OVERLAY_INSET = 2
local SWIPE_FRAMELEVEL_OFFSET = 40
local SWIPE_COLOR_R = 0
local SWIPE_COLOR_G = 0
local SWIPE_COLOR_B = 0
local SWIPE_COLOR_A = 0.8
local VISUAL_BORDER_TEMPLATE_TOKEN = "icon_template_v1"
local VISUAL_REFRESH_TIMER_KEY = CDM:BuildKey("Visuals", "Refresh")
local VISUAL_GCD_RECHECK_TIMER_PREFIX = CDM:BuildKey("Visuals", "GCDRecheck")
local SETTINGS_STATE_KEY = "settingsInjectionState"
local TRACKED_BAR_ICON_SIZE_BONUS = 4
local TRACKED_BAR_ICON_X_OFFSET = 0
local TRACKED_BAR_BAR_OVERLAP_OFFSET = -6
local TRACKED_BAR_NAME_LEFT_PADDING = 4
local TRACKED_BAR_NAME_BASE_LEFT_X = 5
local TRACKED_BAR_NAME_BASE_RIGHT_X = -25
local RUNTIME_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end


local function GetSafeFrameStrata(frame)
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return nil
    end

    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if not ok or IsSecret(strata) or type(strata) ~= "string" or strata == "" then
        return nil
    end

    return strata
end


local function GetSafeFrameLevel(frame)
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return nil
    end

    local ok, level = pcall(frame.GetFrameLevel, frame)
    if not ok or IsSecret(level) or type(level) ~= "number" then
        return nil
    end

    return level
end


local function GetSafeRegionExtent(region, methodName)
    if not region or type(region[methodName]) ~= "function" then
        return nil
    end

    local ok, value = pcall(region[methodName], region)
    if not ok or IsSecret(value) or type(value) ~= "number" then
        return nil
    end

    return value
end


local function IsUsableCooldownID(value)
    if IsSecret(value) then
        return false
    end
    return type(value) == "number" and value > 0
end


local function ClampColorComponent(value, defaultValue)
    local number = tonumber(value)
    if not number then
        number = defaultValue or 1
    end
    if number < 0 then
        number = 0
    elseif number > 1 then
        number = 1
    end
    return number
end


local function NormalizeColor(color, fallback)
    local source = color
    if type(source) ~= "table" then
        source = fallback
    end
    if type(source) ~= "table" then
        source = { 1, 1, 1, 1 }
    end

    local alpha = source[4]
    if alpha == nil then
        alpha = 1
    end

    return {
        ClampColorComponent(source[1], 1),
        ClampColorComponent(source[2], 1),
        ClampColorComponent(source[3], 1),
        ClampColorComponent(alpha, 1),
    }
end


local function ColorsEqual(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    local epsilon = 0.0001
    for i = 1, 4 do
        local lhs = tonumber(left[i]) or (i == 4 and 1 or 0)
        local rhs = tonumber(right[i]) or (i == 4 and 1 or 0)
        if math.abs(lhs - rhs) > epsilon then
            return false
        end
    end
    return true
end


local function CopyColor(source)
    if type(source) ~= "table" then
        return nil
    end
    local normalized = NormalizeColor(source)
    return { normalized[1], normalized[2], normalized[3], normalized[4] }
end


local function ColorToToken(color)
    local normalized = NormalizeColor(color)
    return format("%.3f:%.3f:%.3f:%.3f", normalized[1], normalized[2], normalized[3], normalized[4])
end


local function GetHookID(object)
    if object and type(object.GetName) == "function" then
        local name = object:GetName()
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(object)
end


local function ResolveCooldownIDFromFrame(frame)
    if not frame then
        return nil
    end

    if type(frame.GetCooldownID) == "function" then
        local ok, cooldownID = pcall(frame.GetCooldownID, frame)
        if ok and IsUsableCooldownID(cooldownID) then
            return cooldownID
        end
    end

    if IsUsableCooldownID(frame.cooldownID) then
        return frame.cooldownID
    end

    if type(frame.cooldownInfo) == "table" and IsUsableCooldownID(frame.cooldownInfo.cooldownID) then
        return frame.cooldownInfo.cooldownID
    end

    return nil
end


local function ResolveCooldownInfo(frame, cooldownID)
    if frame and type(frame.GetCooldownInfo) == "function" then
        local ok, info = pcall(frame.GetCooldownInfo, frame)
        if ok and type(info) == "table" then
            return info
        end
    end

    if IsUsableCooldownID(cooldownID) and CDM.GetCooldownInfo then
        return CDM:GetCooldownInfo(cooldownID)
    end

    return nil
end


local function GetCurrentBarDefaultColor()
    local color = _G.COOLDOWN_BAR_DEFAULT_COLOR
    if color and type(color.GetRGBA) == "function" then
        local r, g, b, a = color:GetRGBA()
        return NormalizeColor({ r, g, b, a })
    end
    return CopyColor(DEFAULT_BAR_COLOR_FALLBACK)
end


local function BuildColorDisplayInfo(color)
    local normalized = NormalizeColor(color)
    return {
        r = normalized[1],
        g = normalized[2],
        b = normalized[3],
        opacity = normalized[4],
        hasOpacity = 1,
    }
end


local function BuildColorPickerInfo(colorCopy, onChanged)
    local function Notify()
        if onChanged then
            onChanged()
        end
    end

    local info = BuildColorDisplayInfo(colorCopy)
    info.swatchFunc = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        colorCopy[1], colorCopy[2], colorCopy[3] = r, g, b
        Notify()
    end
    info.opacityFunc = function()
        local a = ColorPickerFrame:GetColorAlpha()
        colorCopy[4] = a
        Notify()
    end
    info.cancelFunc = function(previous)
        if previous then
            colorCopy[1] = previous.r or colorCopy[1]
            colorCopy[2] = previous.g or colorCopy[2]
            colorCopy[3] = previous.b or colorCopy[3]
            colorCopy[4] = previous.a or previous.opacity or colorCopy[4]
        end
        Notify()
    end
    return info
end


local function AddColorSwatch(rootDescription, label, getColor, commitColor)
    rootDescription:CreateColorSwatch(label, function()
        if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
            return
        end

        local current = NormalizeColor(getColor and getColor() or nil)
        local colorCopy = { current[1], current[2], current[3], current[4] }
        ColorPickerFrame:SetupColorPickerAndShow(BuildColorPickerInfo(colorCopy, function()
            if commitColor then
                commitColor(colorCopy)
            end
        end))
    end, BuildColorDisplayInfo(getColor and getColor() or nil))
end


local function GetIconAnchorRegion(frame)
    if not frame then
        return nil, nil
    end

    local icon = frame.Icon
    if not icon then
        return nil, nil
    end

    if type(icon.GetObjectType) == "function" then
        local objectType = icon:GetObjectType()
        if objectType == "Texture" then
            return frame, icon
        elseif objectType == "Frame" then
            if icon.Icon and type(icon.Icon.GetObjectType) == "function" and icon.Icon:GetObjectType() == "Texture" then
                return frame, icon.Icon
            end
            return frame, icon
        end
    end

    return nil, nil
end


local function GetBarRegion(frame)
    if not frame then
        return nil
    end
    if frame.Bar and type(frame.Bar.SetStatusBarColor) == "function" then
        return frame.Bar
    end
    if frame.StatusBar and type(frame.StatusBar.SetStatusBarColor) == "function" then
        return frame.StatusBar
    end
    return nil
end


local function GetCooldownRegion(frame)
    if frame and frame.Cooldown and type(frame.Cooldown.SetSwipeTexture) == "function" then
        return frame.Cooldown
    end
    return nil
end


local function IsSettingsItemFrame(frame)
    return frame and type(frame.SetAsCooldown) == "function"
end


local function GetGCDRecheckTimerKey(frame)
    return VISUAL_GCD_RECHECK_TIMER_PREFIX .. ":" .. tostring(frame)
end


local function CancelGCDRecheck(frame)
    if frame and RefineUI.CancelTimer then
        RefineUI:CancelTimer(GetGCDRecheckTimerKey(frame))
    end
end


local function QueueGCDRecheck(frame, cooldownID)
    if not frame or not RefineUI.After then
        return
    end
    if not CDM.IsBlizzardSpellIconFrame or not CDM.IsFrameOnGlobalCooldown then
        return
    end
    if not CDM:IsBlizzardSpellIconFrame(frame, cooldownID) then
        return
    end
    if not CDM:IsFrameOnGlobalCooldown(frame) then
        CancelGCDRecheck(frame)
        return
    end

    local cooldown = GetCooldownRegion(frame)
    if not cooldown or type(cooldown.GetCooldownTimes) ~= "function" then
        return
    end

    local okTimes, startMS, durationMS = pcall(cooldown.GetCooldownTimes, cooldown)
    if not okTimes or IsSecret(startMS) or IsSecret(durationMS) then
        return
    end
    if type(startMS) ~= "number" or type(durationMS) ~= "number" or durationMS <= 0 then
        CancelGCDRecheck(frame)
        return
    end

    local remainingSeconds = ((startMS + durationMS) - (GetTime() * 1000)) / 1000
    if remainingSeconds <= 0 then
        CancelGCDRecheck(frame)
        return
    end
    if remainingSeconds > 3 then
        CancelGCDRecheck(frame)
        return
    end

    RefineUI:After(GetGCDRecheckTimerKey(frame), remainingSeconds + 0.02, function()
        CDM:ApplyVisualsToCooldownFrame(frame)
    end)
end


local function ApplyFrameCooldownAnchors(frame, cooldown)
    if not frame or not cooldown then
        return
    end

    local _, iconRegion = GetIconAnchorRegion(frame)
    local anchorTarget = iconRegion or frame
    if not anchorTarget then
        return
    end

    local anchorToken = "v2:" .. tostring(anchorTarget) .. ":" .. tostring(SWIPE_OVERLAY_INSET)
    if CDM:StateGet(frame, "visualSwipeAnchorToken") == anchorToken then
        return
    end

    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", -SWIPE_OVERLAY_INSET, SWIPE_OVERLAY_INSET)
    cooldown:SetPoint("BOTTOMRIGHT", anchorTarget, "BOTTOMRIGHT", SWIPE_OVERLAY_INSET, -SWIPE_OVERLAY_INSET)

    if cooldown.SetFrameStrata then
        local strata = GetSafeFrameStrata(frame)
        if strata then
            cooldown:SetFrameStrata(strata)
        end
    end
    if cooldown.SetFrameLevel then
        local baseLevel = GetSafeFrameLevel(frame)
        if baseLevel then
            cooldown:SetFrameLevel(baseLevel + SWIPE_FRAMELEVEL_OFFSET)
        end
    end

    CDM:StateSet(frame, "visualSwipeAnchorToken", anchorToken)
end


local function GetRefineCooldownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end

    if type(textures.CooldownSwipe) == "string" and textures.CooldownSwipe ~= "" then
        return textures.CooldownSwipe
    end
    if type(textures.CooldownSwipeSmall) == "string" and textures.CooldownSwipeSmall ~= "" then
        return textures.CooldownSwipeSmall
    end
    return nil
end


local function GetFrameBarColor(frame)
    local bar = GetBarRegion(frame)
    if not bar then
        return nil
    end

    if type(bar.GetStatusBarColor) == "function" then
        local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
        if ok then
            return NormalizeColor({ r, g, b, a })
        end
    end

    if bar.FillTexture and type(bar.FillTexture.GetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(bar.FillTexture.GetVertexColor, bar.FillTexture)
        if ok then
            return NormalizeColor({ r, g, b, a })
        end
    end

    return GetCurrentBarDefaultColor()
end


local function ApplyBarColor(frame, color)
    local bar = GetBarRegion(frame)
    if not bar then
        return
    end

    local normalized = NormalizeColor(color)
    if type(bar.SetStatusBarColor) == "function" then
        pcall(bar.SetStatusBarColor, bar, normalized[1], normalized[2], normalized[3], normalized[4])
    end
    if bar.FillTexture and type(bar.FillTexture.SetVertexColor) == "function" then
        pcall(bar.FillTexture.SetVertexColor, bar.FillTexture, normalized[1], normalized[2], normalized[3], normalized[4])
    end
end


local function IsRefineInjectedItem(owner)
    local bucket = CDM:StateGet(owner, "bucketKey")
    if type(bucket) ~= "string" then
        return false
    end
    if bucket == CDM.NOT_TRACKED_KEY then
        return true
    end
    for i = 1, #CDM.TRACKER_BUCKETS do
        if bucket == CDM.TRACKER_BUCKETS[i] then
            return true
        end
    end
    return false
end


local function GetOwnerCooldownID(owner)
    if not owner then
        return nil
    end

    if type(owner.GetCooldownID) == "function" then
        local ok, cooldownID = pcall(owner.GetCooldownID, owner)
        if ok and IsUsableCooldownID(cooldownID) then
            return cooldownID
        end
    end

    if IsUsableCooldownID(owner.cooldownID) then
        return owner.cooldownID
    end

    return nil
end


local function GetAssignmentTargetIndex(bucket)
    local ids = CDM.GetBucketCooldownIDs and CDM:GetBucketCooldownIDs(bucket)
    if type(ids) ~= "table" then
        return 1
    end
    return #ids + 1
end


local function IsSpellCategory(category)
    if IsSecret(category) then
        return false
    end
    return category == CATEGORY_ESSENTIAL or category == CATEGORY_UTILITY
end


local function IsTrackedBarCategory(category)
    if IsSecret(category) then
        return false
    end
    return category == TRACKED_BAR
end


local function GetSettingsItemCategory(frame)
    if not frame or type(frame.GetParent) ~= "function" then
        return nil
    end

    local categoryFrame = frame:GetParent()
    if not categoryFrame or type(categoryFrame.GetCategoryObject) ~= "function" then
        return nil
    end

    local categoryObject = categoryFrame:GetCategoryObject()
    if type(categoryObject) ~= "table" or type(categoryObject.GetCategory) ~= "function" then
        return nil
    end

    local okCategory, category = pcall(categoryObject.GetCategory, categoryObject)
    if not okCategory or IsSecret(category) then
        return nil
    end

    return category
end


local function EnsureVisualBorderFrame(frame)
    local overlay = CDM:StateGet(frame, "visualBorderOverlay")
    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        RefineUI.AddAPI(overlay)
        local frameStrata = GetSafeFrameStrata(frame)
        if frameStrata then
            overlay:SetFrameStrata(frameStrata)
        end
        local frameLevel = GetSafeFrameLevel(frame)
        if frameLevel then
            overlay:SetFrameLevel(frameLevel + 30)
        end
        overlay:EnableMouse(false)
        CDM:StateSet(frame, "visualBorderOverlay", overlay)
    end

    if CDM:StateGet(overlay, "visualBorderTemplateToken") ~= VISUAL_BORDER_TEMPLATE_TOKEN then
        if RefineUI.SetTemplate then
            RefineUI.SetTemplate(overlay, "Icon")
        else
            RefineUI.CreateBorder(overlay, 4, 4)
        end
        CDM:StateSet(overlay, "visualBorderTemplateToken", VISUAL_BORDER_TEMPLATE_TOKEN)
    end

    return overlay
end


local function EnsureTrackedBarIconPortraitBorder(frame)
    local border = CDM:StateGet(frame, "trackedBarIconPortraitBorder")
    if border then
        return border
    end

    local parentFrame = frame.Icon
    if type(parentFrame) ~= "table" or type(parentFrame.CreateTexture) ~= "function" then
        parentFrame = frame
    end

    border = parentFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    border:Hide()
    border:SetTexture(RefineUI.Media.Textures.PortraitBorder or RefineUI.Media.Textures.RefineBorder)
    border:SetDrawLayer("OVERLAY", 7)
    CDM:StateSet(frame, "trackedBarIconPortraitBorder", border)
    return border
end


local function EnsureTrackedBarIconMask(frame, iconTexture)
    if not iconTexture then
        return nil
    end

    local mask = CDM:StateGet(frame, "trackedBarIconMask")
    if not mask then
        local maskParent = frame.Icon
        if type(maskParent) ~= "table" or type(maskParent.CreateMaskTexture) ~= "function" then
            maskParent = frame
        end
        mask = maskParent:CreateMaskTexture(nil, "ARTWORK")
        mask:SetTexture(RefineUI.Media.Textures.PortraitMask or "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        CDM:StateSet(frame, "trackedBarIconMask", mask)
    end

    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -2, 2)
    mask:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 2, -2)

    if not CDM:StateGet(frame, "trackedBarIconMaskAttached", false) then
        if type(iconTexture.AddMaskTexture) == "function" then
            pcall(iconTexture.AddMaskTexture, iconTexture, mask)
        end
        CDM:StateSet(frame, "trackedBarIconMaskAttached", true)
    end

    return mask
end


local function EnsureTrackedBarBarBorderFrame(frame)
    local overlay = CDM:StateGet(frame, "trackedBarBarBorderOverlay")
    if overlay then
        return overlay
    end

    overlay = CreateFrame("Frame", nil, frame)
    RefineUI.AddAPI(overlay)
    local frameStrata = GetSafeFrameStrata(frame)
    if frameStrata then
        overlay:SetFrameStrata(frameStrata)
    end
    local frameLevel = GetSafeFrameLevel(frame)
    if frameLevel then
        overlay:SetFrameLevel(frameLevel + 35)
    end
    overlay:EnableMouse(false)
    RefineUI.CreateBorder(overlay, 2, 4, 12)
    overlay:Hide()
    CDM:StateSet(frame, "trackedBarBarBorderOverlay", overlay)
    return overlay
end


local function GetTrackedBarNameRegion(frame)
    if not frame then
        return nil
    end

    if type(frame.GetNameFontString) == "function" then
        local ok, nameRegion = pcall(frame.GetNameFontString, frame)
        if ok and nameRegion then
            return nameRegion
        end
    end

    local barRegion = frame.Bar
    if barRegion and barRegion.Name then
        return barRegion.Name
    end

    return nil
end


local function ApplyTrackedBarNamePadding(frame, barRegion)
    local nameRegion = GetTrackedBarNameRegion(frame)
    if not nameRegion or not barRegion then
        return
    end

    local desiredToken = TRACKED_BAR_NAME_LEFT_PADDING
    if CDM:StateGet(frame, "trackedBarNamePaddingToken") == desiredToken then
        return
    end

    nameRegion:ClearAllPoints()
    nameRegion:SetPoint("TOPLEFT", barRegion, "TOPLEFT", TRACKED_BAR_NAME_BASE_LEFT_X + TRACKED_BAR_NAME_LEFT_PADDING, 0)
    nameRegion:SetPoint("BOTTOMRIGHT", barRegion, "BOTTOMRIGHT", TRACKED_BAR_NAME_BASE_RIGHT_X, 0)
    CDM:StateSet(frame, "trackedBarNamePaddingToken", desiredToken)
end


local function ApplyTrackedBarGeometry(frame, iconTexture, barRegion)
    if not frame or not iconTexture or not barRegion then
        return
    end

    local iconContainer = frame.Icon
    local isRuntimeIconContainer = type(iconContainer) == "table"
        and type(iconContainer.SetSize) == "function"
        and type(iconTexture.GetParent) == "function"
        and iconTexture:GetParent() == iconContainer

    if isRuntimeIconContainer then
        local baseWidth = CDM:StateGet(frame, "trackedBarIconBaseWidth")
        local baseHeight = CDM:StateGet(frame, "trackedBarIconBaseHeight")
        if IsSecret(baseWidth) or type(baseWidth) ~= "number" or baseWidth <= 0 then
            baseWidth = GetSafeRegionExtent(iconContainer, "GetWidth") or 30
            CDM:StateSet(frame, "trackedBarIconBaseWidth", baseWidth)
        end
        if IsSecret(baseHeight) or type(baseHeight) ~= "number" or baseHeight <= 0 then
            baseHeight = GetSafeRegionExtent(iconContainer, "GetHeight") or 30
            CDM:StateSet(frame, "trackedBarIconBaseHeight", baseHeight)
        end

        iconContainer:ClearAllPoints()
        iconContainer:SetPoint("LEFT", frame, "LEFT", TRACKED_BAR_ICON_X_OFFSET, 0)
        iconContainer:SetSize(baseWidth + TRACKED_BAR_ICON_SIZE_BONUS, baseHeight + TRACKED_BAR_ICON_SIZE_BONUS)

        barRegion:ClearAllPoints()
        barRegion:SetPoint("LEFT", iconContainer, "RIGHT", TRACKED_BAR_BAR_OVERLAP_OFFSET, 0)
        barRegion:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    else
        local baseWidth = CDM:StateGet(frame, "trackedBarIconBaseWidth")
        local baseHeight = CDM:StateGet(frame, "trackedBarIconBaseHeight")
        if IsSecret(baseWidth) or type(baseWidth) ~= "number" or baseWidth <= 0 then
            baseWidth = GetSafeRegionExtent(iconTexture, "GetWidth") or 38
            CDM:StateSet(frame, "trackedBarIconBaseWidth", baseWidth)
        end
        if IsSecret(baseHeight) or type(baseHeight) ~= "number" or baseHeight <= 0 then
            baseHeight = GetSafeRegionExtent(iconTexture, "GetHeight") or 38
            CDM:StateSet(frame, "trackedBarIconBaseHeight", baseHeight)
        end

        iconTexture:ClearAllPoints()
        iconTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", TRACKED_BAR_ICON_X_OFFSET, 0)
        iconTexture:SetSize(baseWidth + TRACKED_BAR_ICON_SIZE_BONUS, baseHeight + TRACKED_BAR_ICON_SIZE_BONUS)

        barRegion:ClearAllPoints()
        barRegion:SetPoint("LEFT", iconTexture, "RIGHT", TRACKED_BAR_BAR_OVERLAP_OFFSET, 0)
        barRegion:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    end

    ApplyTrackedBarNamePadding(frame, barRegion)
end


local function HideTrackedBarCustomVisuals(frame)
    local iconBorder = CDM:StateGet(frame, "trackedBarIconPortraitBorder")
    if iconBorder then
        iconBorder:Hide()
    end

    local barBorder = CDM:StateGet(frame, "trackedBarBarBorderOverlay")
    if barBorder then
        barBorder:Hide()
    end

    CDM:StateClear(frame, "trackedBarIconPortraitBorderToken")
    CDM:StateClear(frame, "trackedBarBarBorderToken")
end


local function AnchorVisualBorderFrame(frame, overlay)
    local parentFrame, iconRegion = GetIconAnchorRegion(frame)
    if not parentFrame or not iconRegion then
        overlay:Hide()
        return false
    end

    overlay:ClearAllPoints()
    if type(iconRegion.GetObjectType) == "function" and iconRegion:GetObjectType() == "Texture" then
        overlay:SetPoint("TOPLEFT", iconRegion, "TOPLEFT", -1, 1)
        overlay:SetPoint("BOTTOMRIGHT", iconRegion, "BOTTOMRIGHT", 1, -1)
    else
        overlay:SetPoint("TOPLEFT", iconRegion, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", iconRegion, "BOTTOMRIGHT", 0, 0)
    end

    local parentStrata = GetSafeFrameStrata(parentFrame)
    if parentStrata then
        overlay:SetFrameStrata(parentStrata)
    end
    local parentLevel = GetSafeFrameLevel(parentFrame)
    if parentLevel then
        overlay:SetFrameLevel(parentLevel + 30)
    end
    return true
end


local function ApplyFrameBorderVisual(frame, cooldownID, skinEnabled)
    if CDM:IsTrackedBarFrame(frame, cooldownID) and not IsSettingsItemFrame(frame) then
        local genericOverlay = CDM:StateGet(frame, "visualBorderOverlay")
        if genericOverlay then
            genericOverlay:Hide()
        end
        CDM:StateClear(frame, "visualBorderToken")

        if not skinEnabled then
            HideTrackedBarCustomVisuals(frame)
            return
        end

        local borderColor = CDM:GetResolvedBorderColorForFrame(frame, cooldownID)
        local _, iconTexture = GetIconAnchorRegion(frame)
        local barRegion = GetBarRegion(frame)

        if iconTexture and barRegion then
            ApplyTrackedBarGeometry(frame, iconTexture, barRegion)
        end

        if iconTexture then
            local iconBorder = EnsureTrackedBarIconPortraitBorder(frame)
            EnsureTrackedBarIconMask(frame, iconTexture)

            local iconParent = nil
            if type(iconTexture.GetParent) == "function" then
                iconParent = iconTexture:GetParent()
            end
            if iconParent then
                local iconParentLevel = GetSafeFrameLevel(iconParent)
                local baseLevel = GetSafeFrameLevel(frame)
                if iconParentLevel and baseLevel then
                    local desiredLevel = baseLevel + 8
                    if iconParentLevel < desiredLevel then
                        iconParent:SetFrameLevel(desiredLevel)
                    end
                end
            end

            if type(iconTexture.SetDrawLayer) == "function" then
                iconTexture:SetDrawLayer("OVERLAY", 6)
            end

            iconBorder:ClearAllPoints()
            iconBorder:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -4, 4)
            iconBorder:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 4, -4)

            local iconToken = tostring(cooldownID) .. ":" .. ColorToToken(borderColor)
            if CDM:StateGet(frame, "trackedBarIconPortraitBorderToken") ~= iconToken then
                iconBorder:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
                CDM:StateSet(frame, "trackedBarIconPortraitBorderToken", iconToken)
            end
            iconBorder:Show()
        end

        if barRegion then
            local barBorder = EnsureTrackedBarBarBorderFrame(frame)
            local barRegionStrata = GetSafeFrameStrata(barRegion)
            local frameStrata = GetSafeFrameStrata(frame)
            if barRegionStrata then
                barBorder:SetFrameStrata(barRegionStrata)
            elseif frameStrata then
                barBorder:SetFrameStrata(frameStrata)
            end
            local iconParentLevel = nil
            if iconTexture and type(iconTexture.GetParent) == "function" then
                local iconParent = iconTexture:GetParent()
                if iconParent then
                    iconParentLevel = GetSafeFrameLevel(iconParent)
                end
            end
            local barRegionLevel = GetSafeFrameLevel(barRegion)
            local frameLevel = GetSafeFrameLevel(frame)
            if barRegionLevel or frameLevel then
                local desiredLevel = ((barRegionLevel or frameLevel or 1) + 1)
                if type(iconParentLevel) == "number" and desiredLevel >= iconParentLevel then
                    desiredLevel = iconParentLevel - 1
                end
                if desiredLevel < 1 then
                    desiredLevel = 1
                end
                barBorder:SetFrameLevel(desiredLevel)
            end
            barBorder:ClearAllPoints()
            barBorder:SetPoint("TOPLEFT", barRegion, "TOPLEFT", -2, 2)
            barBorder:SetPoint("BOTTOMRIGHT", barRegion, "BOTTOMRIGHT", 2, -2)
            local barToken = tostring(cooldownID) .. ":" .. ColorToToken(borderColor)
            if CDM:StateGet(frame, "trackedBarBarBorderToken") ~= barToken then
                if barBorder.border and barBorder.border.SetBackdropBorderColor then
                    barBorder.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
                end
                CDM:StateSet(frame, "trackedBarBarBorderToken", barToken)
            end
            barBorder:Show()

            if iconTexture and type(iconTexture.GetParent) == "function" then
                local iconParent = iconTexture:GetParent()
                if iconParent and type(iconParent.SetFrameStrata) == "function" and type(iconParent.SetFrameLevel) == "function" then
                    local barBorderStrata = GetSafeFrameStrata(barBorder)
                    if barBorderStrata then
                        iconParent:SetFrameStrata(barBorderStrata)
                    end
                    local barBorderLevel = GetSafeFrameLevel(barBorder)
                    local frameLevel = GetSafeFrameLevel(frame)
                    local parentLevel = barBorderLevel or frameLevel
                    if parentLevel then
                        iconParent:SetFrameLevel(parentLevel + 2)
                    end
                end
            end
        end

        return
    end

    HideTrackedBarCustomVisuals(frame)

    local overlay = EnsureVisualBorderFrame(frame)
    if not skinEnabled then
        overlay:Hide()
        CDM:StateClear(frame, "visualBorderToken")
        return
    end

    if not AnchorVisualBorderFrame(frame, overlay) then
        CDM:StateClear(frame, "visualBorderToken")
        return
    end

    local borderColor = CDM:GetResolvedBorderColorForFrame(frame, cooldownID)
    local token = tostring(cooldownID) .. ":" .. ColorToToken(borderColor)
    if CDM:StateGet(frame, "visualBorderToken") ~= token then
        if overlay.border and overlay.border.SetBackdropBorderColor then
            overlay.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
        CDM:StateSet(frame, "visualBorderToken", token)
    end

    overlay:Show()
end


local function ApplyFrameBarVisual(frame, cooldownID, skinEnabled)
    local bar = GetBarRegion(frame)
    if not bar then
        CDM:StateClear(frame, "visualBarToken")
        return
    end

    local overrideColor = nil
    if skinEnabled then
        overrideColor = CDM:GetCooldownBarColor(cooldownID)
    end

    local currentToken = CDM:StateGet(frame, "visualBarToken")
    if type(overrideColor) == "table" then
        local defaultColor = CDM:StateGet(frame, "visualDefaultBarColor")
        if type(defaultColor) ~= "table" then
            defaultColor = GetFrameBarColor(frame) or GetCurrentBarDefaultColor()
            CDM:StateSet(frame, "visualDefaultBarColor", defaultColor)
        end

        local token = "override:" .. ColorToToken(overrideColor)
        if currentToken ~= token then
            ApplyBarColor(frame, overrideColor)
            CDM:StateSet(frame, "visualBarToken", token)
        end
    elseif type(currentToken) == "string" and string.find(currentToken, "^override:", 1, false) then
        local restore = CDM:StateGet(frame, "visualDefaultBarColor")
        if type(restore) ~= "table" then
            restore = GetFrameBarColor(frame) or GetCurrentBarDefaultColor()
        end
        ApplyBarColor(frame, restore)
        CDM:StateClear(frame, "visualBarToken")
        CDM:StateClear(frame, "visualDefaultBarColor")
    else
        CDM:StateClear(frame, "visualBarToken")
    end
end


local function ApplyFrameCooldownSwipe(frame, skinEnabled)
    local cooldown = GetCooldownRegion(frame)
    if not cooldown then
        CDM:StateClear(frame, "visualSwipeToken")
        CDM:StateClear(frame, "visualSwipeAnchorToken")
        return
    end

    ApplyFrameCooldownAnchors(frame, cooldown)

    if not skinEnabled then
        CDM:StateClear(frame, "visualSwipeToken")
        return
    end

    local swipeTexture = GetRefineCooldownSwipeTexture()
    if type(swipeTexture) ~= "string" or swipeTexture == "" then
        CDM:StateClear(frame, "visualSwipeToken")
        return
    end

    if cooldown.SetDrawEdge then
        pcall(cooldown.SetDrawEdge, cooldown, false)
    end
    if cooldown.SetDrawBling then
        pcall(cooldown.SetDrawBling, cooldown, true)
    end
    if cooldown.SetDrawSwipe then
        pcall(cooldown.SetDrawSwipe, cooldown, true)
    end
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, SWIPE_COLOR_R, SWIPE_COLOR_G, SWIPE_COLOR_B, SWIPE_COLOR_A)
    end
    local token = "swipe:v2:" .. swipeTexture
    if CDM:StateGet(frame, "visualSwipeToken") ~= token then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
        CDM:StateSet(frame, "visualSwipeToken", token)
    end
end


local function ApplyCooldownTextColor(cooldown, color)
    if not cooldown then
        return
    end

    local normalized = NormalizeColor(color)
    local applied = false

    if type(cooldown.GetCountdownFontString) == "function" then
        local ok, countdownText = pcall(cooldown.GetCountdownFontString, cooldown)
        if ok and countdownText and type(countdownText.SetTextColor) == "function" then
            countdownText:SetTextColor(normalized[1], normalized[2], normalized[3], normalized[4])
            applied = true
        end
    end

    if not applied and type(cooldown.GetRegions) == "function" then
        local regions = { cooldown:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
                region:SetTextColor(normalized[1], normalized[2], normalized[3], normalized[4])
                applied = true
            end
        end
    end
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:ApplyTrackerCooldownTextVisual(cooldown, cooldownID)
    if not cooldown then
        return
    end

    local textColor
    if IsUsableCooldownID(cooldownID) then
        textColor = self:GetCooldownFontColor(cooldownID)
    else
        textColor = self:GetDefaultFontColor()
    end

    ApplyCooldownTextColor(cooldown, textColor)
end


local function ApplyFrameCooldownTextVisual(frame, cooldownID, _skinEnabled)
    local cooldown = GetCooldownRegion(frame)
    if not cooldown then
        CDM:StateClear(frame, "visualTextToken")
        return
    end

    local textColor = CDM:GetCooldownFontColor(cooldownID)
    local token = ColorToToken(textColor)
    if CDM:StateGet(frame, "visualTextToken") ~= token then
        ApplyCooldownTextColor(cooldown, textColor)
        CDM:StateSet(frame, "visualTextToken", token)
    end
end


local function SuppressFrameCooldownFlash(frame)
    if not frame then
        return
    end

    local flash = frame.CooldownFlash
    if flash then
        if flash.SetAlpha then
            pcall(flash.SetAlpha, flash, 0)
        end
        if flash.Hide then
            pcall(flash.Hide, flash)
        end
    end

    if frame.SetPlayFlash then
        pcall(frame.SetPlayFlash, frame, false)
    end
end


local function ClearFrameVisualState(frame, restoreDefaultTextColor)
    if not frame then
        return
    end

    CancelGCDRecheck(frame)

    local overlay = CDM:StateGet(frame, "visualBorderOverlay")
    if overlay then
        overlay:Hide()
    end
    HideTrackedBarCustomVisuals(frame)

    local barToken = CDM:StateGet(frame, "visualBarToken")
    if type(barToken) == "string" and string.find(barToken, "^override:", 1, false) then
        local defaultColor = CDM:StateGet(frame, "visualDefaultBarColor")
        if defaultColor then
            ApplyBarColor(frame, defaultColor)
        end
    end

    CDM:StateClear(frame, "visualBorderToken")
    CDM:StateClear(frame, "visualBarToken")
    CDM:StateClear(frame, "visualDefaultBarColor")
    CDM:StateClear(frame, "visualSwipeToken")
    CDM:StateClear(frame, "visualSwipeAnchorToken")

    if restoreDefaultTextColor ~= false then
        local cooldown = GetCooldownRegion(frame)
        if cooldown then
            ApplyCooldownTextColor(cooldown, CDM:GetDefaultFontColor())
        end
    end
    CDM:StateClear(frame, "visualTextToken")
end


function CDM:ApplyVisualsToCooldownFrame(frame)
    if not frame then
        return
    end

    if self.IsBlizzardCooldownManagerEnabled and not self:IsBlizzardCooldownManagerEnabled() then
        -- Treat CDM visuals as fully inactive when Blizzard Cooldown Manager is disabled.
        ClearFrameVisualState(frame, false)
        return
    end

    local cooldownID = ResolveCooldownIDFromFrame(frame)
    if not IsUsableCooldownID(cooldownID) then
        ClearFrameVisualState(frame, true)
        return
    end

    local skinEnabled = self:IsSkinCooldownViewerEnabled()
    ApplyFrameBorderVisual(frame, cooldownID, skinEnabled)
    ApplyFrameBarVisual(frame, cooldownID, skinEnabled)
    ApplyFrameCooldownSwipe(frame, skinEnabled)
    ApplyFrameCooldownTextVisual(frame, cooldownID, skinEnabled)
    SuppressFrameCooldownFlash(frame)
    QueueGCDRecheck(frame, cooldownID)
end


local function InstallVisualCooldownHooks(frame, hookID)
    local cooldown = GetCooldownRegion(frame)
    if not cooldown then
        return
    end

    RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":Cooldown:OnShow", cooldown, "OnShow", function()
        CDM:ApplyVisualsToCooldownFrame(frame)
    end)
    RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":Cooldown:OnHide", cooldown, "OnHide", function()
        CDM:ApplyVisualsToCooldownFrame(frame)
    end)
    RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":Cooldown:OnCooldownDone", cooldown, "OnCooldownDone", function()
        CDM:ApplyVisualsToCooldownFrame(frame)
    end)
end


function CDM:RegisterVisualItemFrame(frame)
    if not frame then
        return
    end
    if self:StateGet(frame, "visualHooksInstalled", false) then
        self:ApplyVisualsToCooldownFrame(frame)
        return
    end

    local hookID = GetHookID(frame)
    if type(frame.SetCooldownID) == "function" then
        RefineUI:HookOnce("CDM:Visuals:" .. hookID .. ":SetCooldownID", frame, "SetCooldownID", function(hookedFrame)
            CDM:ApplyVisualsToCooldownFrame(hookedFrame)
        end)
    end
    if type(frame.ClearCooldownID) == "function" then
        RefineUI:HookOnce("CDM:Visuals:" .. hookID .. ":ClearCooldownID", frame, "ClearCooldownID", function(hookedFrame)
            CDM:ApplyVisualsToCooldownFrame(hookedFrame)
        end)
    end
    if type(frame.RefreshData) == "function" then
        RefineUI:HookOnce("CDM:Visuals:" .. hookID .. ":RefreshData", frame, "RefreshData", function(hookedFrame)
            CDM:ApplyVisualsToCooldownFrame(hookedFrame)
        end)
    end
    RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":OnShow", frame, "OnShow", function(hookedFrame)
        CDM:ApplyVisualsToCooldownFrame(hookedFrame)
    end)
    InstallVisualCooldownHooks(frame, hookID)

    self:StateSet(frame, "visualHooksInstalled", true)
    self:ApplyVisualsToCooldownFrame(frame)
end


local function ApplyViewerVisuals(viewer)
    if not viewer or type(viewer.GetChildren) ~= "function" then
        return
    end

    local ok, children = pcall(function()
        return { viewer:GetChildren() }
    end)
    if not ok or type(children) ~= "table" then
        return
    end

    for i = 1, #children do
        local frame = children[i]
        if frame and (frame.Cooldown or frame.Bar or frame.Icon) then
            CDM:RegisterVisualItemFrame(frame)
        end
    end
end


local function ApplyCategoryVisuals(categoryFrame)
    if not categoryFrame or type(categoryFrame.itemPool) ~= "table" or type(categoryFrame.itemPool.EnumerateActive) ~= "function" then
        return
    end

    for itemFrame in categoryFrame.itemPool:EnumerateActive() do
        CDM:RegisterVisualItemFrame(itemFrame)
    end
end


local function ApplySettingsVisuals(settingsFrame)
    if not settingsFrame then
        return
    end

    if settingsFrame.categoryPool and type(settingsFrame.categoryPool.EnumerateActive) == "function" then
        for categoryFrame in settingsFrame.categoryPool:EnumerateActive() do
            ApplyCategoryVisuals(categoryFrame)
        end
    end

    local state = CDM:StateGet(settingsFrame, SETTINGS_STATE_KEY)
    if type(state) == "table" and type(state.categories) == "table" then
        for _, categoryFrame in pairs(state.categories) do
            ApplyCategoryVisuals(categoryFrame)
        end
    end
end


function CDM:ApplyCooldownViewerVisuals()
    for i = 1, #RUNTIME_VIEWERS do
        ApplyViewerVisuals(_G[RUNTIME_VIEWERS[i]])
    end

    ApplySettingsVisuals(self:GetCooldownViewerSettingsFrame())
end


function CDM:RequestCooldownViewerVisualRefresh()
    if self.visualRefreshQueued then
        return
    end

    self.visualRefreshQueued = true
    local function RunVisualRefresh()
        CDM.visualRefreshQueued = nil
        CDM:ApplyCooldownViewerVisuals()
    end

    if RefineUI.After then
        RefineUI:After(VISUAL_REFRESH_TIMER_KEY, 0, RunVisualRefresh)
    else
        RunVisualRefresh()
    end
end


local function InstallViewerVisualHooks()
    if CDM.viewerVisualHooksInstalled then
        return
    end

    for i = 1, #RUNTIME_VIEWERS do
        local viewerName = RUNTIME_VIEWERS[i]
        local viewer = _G[viewerName]
        if viewer then
            local hookID = GetHookID(viewer)
            if type(viewer.OnAcquireItemFrame) == "function" then
                RefineUI:HookOnce("CDM:Visuals:" .. hookID .. ":OnAcquireItemFrame", viewer, "OnAcquireItemFrame", function(_, itemFrame)
                    CDM:RegisterVisualItemFrame(itemFrame)
                end)
            end
            RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":OnShow", viewer, "OnShow", function()
                CDM:RequestCooldownViewerVisualRefresh()
            end)
        end
    end

    local settingsFrame = CDM:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        local hookID = GetHookID(settingsFrame)
        RefineUI:HookScriptOnce("CDM:Visuals:" .. hookID .. ":OnShow", settingsFrame, "OnShow", function()
            CDM:RequestCooldownViewerVisualRefresh()
        end)
        if type(settingsFrame.RefreshLayout) == "function" then
            RefineUI:HookOnce("CDM:Visuals:" .. hookID .. ":RefreshLayout", settingsFrame, "RefreshLayout", function()
                CDM:RequestCooldownViewerVisualRefresh()
            end)
        end
    end

    CDM.viewerVisualHooksInstalled = true
end


local function InstallVisualEventCallbacks()
    if CDM.visualEventCallbacksInstalled then
        return
    end

    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
            CDM:RequestCooldownViewerVisualRefresh()
        end, CDM)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            CDM:RequestCooldownViewerVisualRefresh()
        end, CDM)
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            CDM.viewerVisualHooksInstalled = nil
            InstallViewerVisualHooks()
            if CDM.InstallVisualMenuHooks then
                CDM:InstallVisualMenuHooks()
            end
            CDM:RequestCooldownViewerVisualRefresh()
        end
    end, "CDM:Visuals:AddonLoaded")

    CDM.visualEventCallbacksInstalled = true
end


function CDM:InitializeVisuals()
    if self.visualsInitialized then
        return
    end

    InstallViewerVisualHooks()
    InstallVisualEventCallbacks()
    if self.InstallVisualMenuHooks then
        self:InstallVisualMenuHooks()
    end
    self:RequestCooldownViewerVisualRefresh()

    self.visualsInitialized = true
end
