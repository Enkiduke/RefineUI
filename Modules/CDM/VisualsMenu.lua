----------------------------------------------------------------------------------------
-- CDM Component: VisualsMenu
-- Description: Context-menu hooks for per-cooldown visual override controls.
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
local ColorPickerFrame = ColorPickerFrame
local Menu = Menu
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local DEFAULT_BAR_COLOR_FALLBACK = { 1, 0.5, 0.25, 1 }

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
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


local function CopyColor(source)
    if type(source) ~= "table" then
        return nil
    end
    local normalized = NormalizeColor(source)
    return { normalized[1], normalized[2], normalized[3], normalized[4] }
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


local function AddRefineTrackerAssignmentMenu(rootDescription, cooldownID)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("RefineUI Tracker")

    rootDescription:CreateButton("Assign to Left", function()
        CDM:AssignCooldownToBucket(cooldownID, "Left", GetAssignmentTargetIndex("Left"))
        CDM:RequestRefresh(true)
    end)
    rootDescription:CreateButton("Assign to Right", function()
        CDM:AssignCooldownToBucket(cooldownID, "Right", GetAssignmentTargetIndex("Right"))
        CDM:RequestRefresh(true)
    end)
    rootDescription:CreateButton("Assign to Bottom", function()
        CDM:AssignCooldownToBucket(cooldownID, "Bottom", GetAssignmentTargetIndex("Bottom"))
        CDM:RequestRefresh(true)
    end)
    rootDescription:CreateButton("Move to Not Tracked", function()
        CDM:UnassignCooldownID(cooldownID)
        CDM:RequestRefresh(true)
    end)
end


local function AddVisualColorMenu(rootDescription, cooldownID, showBarColor, isSpellIcon)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("RefineUI Colors")

    local borderLabel = isSpellIcon and "Cooldown Border Color" or "Border Color"
    AddColorSwatch(rootDescription, borderLabel, function()
        return CDM:GetCooldownBorderColor(cooldownID)
    end, function(color)
        CDM:SetCooldownBorderColor(cooldownID, color)
    end)

    AddColorSwatch(rootDescription, "Font Color", function()
        return CDM:GetCooldownFontColor(cooldownID)
    end, function(color)
        CDM:SetCooldownFontColor(cooldownID, color)
    end)

    if showBarColor then
        AddColorSwatch(rootDescription, "Bar Color", function()
            return CDM:GetCooldownBarColor(cooldownID) or GetCurrentBarDefaultColor()
        end, function(color)
            CDM:SetCooldownBarColor(cooldownID, color)
        end)
    end

    rootDescription:CreateButton("Reset RefineUI Colors", function()
        CDM:ClearCooldownVisualStyle(cooldownID, "All")
    end)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InstallVisualMenuHooks()
    if self.visualMenuHooksInstalled then
        return
    end
    if not Menu or type(Menu.ModifyMenu) ~= "function" then
        return
    end

    Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription)
        local cooldownID = GetOwnerCooldownID(owner)
        if not IsUsableCooldownID(cooldownID) then
            return
        end

        local info = ResolveCooldownInfo(owner, cooldownID)
        local isSpellIcon = CDM:IsBlizzardSpellIconFrame(owner, cooldownID)
        local showBarColor = info and not IsSecret(info.category) and info.category == TRACKED_BAR
        AddVisualColorMenu(rootDescription, cooldownID, showBarColor, isSpellIcon)

        if IsRefineInjectedItem(owner) then
            AddRefineTrackerAssignmentMenu(rootDescription, cooldownID)
        end
    end)

    self.visualMenuHooksInstalled = true
end

