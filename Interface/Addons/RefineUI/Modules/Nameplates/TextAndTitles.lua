----------------------------------------------------------------------------------------
-- Nameplates Component: TextAndTitles
-- Description: Name/health text updates and NPC title extraction/rendering.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local floor = math.floor
local strfind = string.find
local strmatch = string.match
local strgsub = string.gsub
local strsub = string.sub
local wipe = table.wipe
local tinsert = table.insert

local UnitHealthPercent = UnitHealthPercent
local UnitIsPlayer = UnitIsPlayer
local UnitIsFriend = UnitIsFriend
local UnitGUID = UnitGUID
local C_TooltipInfo = C_TooltipInfo
local C_NamePlate = C_NamePlate
local TOOLTIP_UNIT_LEVEL = TOOLTIP_UNIT_LEVEL

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local function GetUtil()
    local private = Nameplates:GetPrivate()
    return private and private.Util
end

local function IsNpcTitleFeatureEnabled()
    local cfg = Nameplates:GetConfiguredNameplatesConfig()
    return cfg and cfg.ShowNPCTitles ~= false
end

local function TrimTooltipLineText(text)
    local util = GetUtil()
    if util and (util.IsSecret(text) or type(text) ~= "string" or not util.IsAccessibleValue(text)) then
        return nil
    end

    local trimmed = strmatch(text, "^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

local function NormalizeNpcTitleText(text)
    local normalized = TrimTooltipLineText(text)
    if not normalized then
        return nil
    end

    if strsub(normalized, 1, 1) == "<" and strsub(normalized, -1) == ">" then
        normalized = TrimTooltipLineText(strsub(normalized, 2, -2))
    end

    if normalized == "" then
        return nil
    end

    return normalized
end

local function IsEligibleNpcTitleUnit(unit, data)
    local util = GetUtil()
    if not util or not util.IsUsableUnitToken(unit) then
        return false
    end

    local isPlayerUnit
    if data and data.isPlayer ~= nil then
        isPlayerUnit = data.isPlayer == true
    else
        isPlayerUnit = util.ReadSafeBoolean(UnitIsPlayer(unit)) == true
    end

    if isPlayerUnit then
        return false
    end

    return util.ReadSafeBoolean(UnitIsFriend("player", unit)) == true
end

local function EnsureNpcTitleFontString(unitFrame, data)
    if not unitFrame or not data or not data.RefineName then
        return nil
    end

    local private = Nameplates:GetPrivate()
    local constants = private and private.Constants
    if not constants then
        return nil
    end

    if not data.RefineNpcTitle then
        data.RefineNpcTitle = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineNpcTitle, constants.NPC_TITLE_FONT_SIZE, nil, "OUTLINE")
        data.RefineNpcTitle:SetTextColor(constants.NPC_TITLE_COLOR[1], constants.NPC_TITLE_COLOR[2], constants.NPC_TITLE_COLOR[3])
        data.RefineNpcTitle:SetJustifyH("CENTER")
        data.RefineNpcTitle:SetJustifyV("MIDDLE")
        data.RefineNpcTitle:Hide()
    end

    if data.RefineNpcTitleAnchor ~= data.RefineName then
        data.RefineNpcTitle:ClearAllPoints()
        RefineUI.Point(data.RefineNpcTitle, "TOP", data.RefineName, "BOTTOM", 0, -1)
        data.RefineNpcTitleAnchor = data.RefineName
    end

    return data.RefineNpcTitle
end

local function BuildUnitLevelPattern()
    local private = Nameplates:GetPrivate()
    local runtime = private and private.Runtime
    local util = private and private.Util
    if not runtime or not util then
        return nil
    end

    if runtime.unitLevelPattern ~= nil then
        return runtime.unitLevelPattern
    end

    if util.IsSecret(TOOLTIP_UNIT_LEVEL) or type(TOOLTIP_UNIT_LEVEL) ~= "string" or not util.IsAccessibleValue(TOOLTIP_UNIT_LEVEL) then
        return nil
    end

    local escaped = strgsub(TOOLTIP_UNIT_LEVEL, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = strgsub(escaped, "%%%%s", ".+")
    escaped = strgsub(escaped, "%%%%d", "%%d+")

    runtime.unitLevelPattern = "^" .. escaped
    return runtime.unitLevelPattern
end

local function IsTooltipLevelLine(text)
    local pattern = BuildUnitLevelPattern()
    if not pattern or not text then
        return false
    end

    return strfind(text, pattern) ~= nil
end

local function GetTooltipLineText(line)
    local util = GetUtil()
    if not util or not line or not util.IsAccessibleValue(line) then
        return nil
    end

    local leftText = util.SafeTableIndex(line, "leftText")
    local normalizedLeftText = TrimTooltipLineText(leftText)
    if normalizedLeftText then
        return normalizedLeftText
    end

    local text = util.SafeTableIndex(line, "text")
    return TrimTooltipLineText(text)
end

local function ExtractNpcTitleFromTooltipData(tooltipData)
    local private = Nameplates:GetPrivate()
    local constants = private and private.Constants
    local util = private and private.Util
    if not constants or not util then
        return nil
    end

    if not tooltipData or not util.IsAccessibleValue(tooltipData) then
        return nil
    end

    local lines = util.SafeTableIndex(tooltipData, "lines")
    if type(lines) ~= "table" or util.IsSecret(lines) or not util.IsAccessibleValue(lines) then
        return nil
    end

    local nameLineIndex = nil
    for i, line in ipairs(lines) do
        if util.SafeTableIndex(line, "type") == constants.TOOLTIP_LINE_TYPE_UNIT_NAME then
            nameLineIndex = i
            break
        end
    end

    if not nameLineIndex then
        return nil
    end

    local candidate = nil
    for i = nameLineIndex + 1, #lines do
        local line = lines[i]
        local text = GetTooltipLineText(line)
        if text then
            if IsTooltipLevelLine(text) then
                return NormalizeNpcTitleText(candidate)
            end
            candidate = text
        end
    end

    return nil
end

local function ResolveNpcTitle(unit)
    local private = Nameplates:GetPrivate()
    local runtime = private and private.Runtime
    local util = private and private.Util
    if not runtime or not util then
        return nil, true
    end

    if not util.IsUsableUnitToken(unit) then
        return nil, true
    end
    if not C_TooltipInfo or type(C_TooltipInfo.GetUnit) ~= "function" then
        return nil, true
    end

    local cacheGUID = nil
    local guid = UnitGUID(unit)
    if type(guid) == "string" and guid ~= "" and not util.IsSecret(guid) and util.IsAccessibleValue(guid) then
        cacheGUID = guid
        local cachedTitle = runtime.npcTitleCacheByGUID[cacheGUID]
        if cachedTitle ~= nil then
            if cachedTitle == false then
                return nil, true
            end
            return cachedTitle, true
        end
    end

    local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok then
        return nil, true
    end
    if tooltipData == nil then
        return nil, false
    end

    local title = ExtractNpcTitleFromTooltipData(tooltipData)
    if cacheGUID then
        runtime.npcTitleCacheByGUID[cacheGUID] = title or false
    end

    return title, true
end

local function NormalizeNameText(text, unit)
    local util = GetUtil()
    if not text then
        return ""
    end

    local isPlayerUnit = false
    if util and util.IsUsableUnitToken(unit) then
        isPlayerUnit = util.ReadSafeBoolean(UnitIsPlayer(unit)) == true
    end

    if util and not util.IsSecret(text) and isPlayerUnit then
        text = text:gsub(" %(*.*%)", ""):gsub("%-.*", "")
    end

    return text
end

local function SetRefineNameTextIfChanged(data, text)
    if not data or not data.RefineName then
        return
    end

    local util = GetUtil()
    if util and util.IsSecret(text) then
        data.RefineName:SetText(text)
        data.RefineNameText = nil
        return
    end

    local finalText = text or ""
    if data.RefineNameText == finalText then
        return
    end

    data.RefineName:SetText(finalText)
    data.RefineNameText = finalText
end

----------------------------------------------------------------------------------------
-- Shared Color Helpers (used by Threat component)
----------------------------------------------------------------------------------------
function Nameplates:SetNameColorIfChanged(data, r, g, b)
    if not data or not data.RefineName then
        return
    end

    if data.NameColorR == r and data.NameColorG == g and data.NameColorB == b then
        return
    end

    data.RefineName:SetTextColor(r, g, b)
    data.NameColorR = r
    data.NameColorG = g
    data.NameColorB = b
end

function Nameplates:SetBarColorIfChanged(statusbar, r, g, b)
    if not statusbar or not statusbar.GetStatusBarColor or not statusbar.SetStatusBarColor then
        return
    end

    local cr, cg, cb = statusbar:GetStatusBarColor()
    if cr ~= r or cg ~= g or cb ~= b then
        statusbar:SetStatusBarColor(r, g, b)
    end
end

----------------------------------------------------------------------------------------
-- NPC Title API
----------------------------------------------------------------------------------------
local function ShouldDeferNpcTitleResolve(data)
    local private = Nameplates:GetPrivate()
    local constants = private and private.Constants
    local activeNameplates = private and private.ActiveNameplates
    if not constants then
        return false
    end

    if data and data.RefineHidden == true then
        return true
    end

    local threshold = constants.NPC_TITLE_DEFER_ACTIVE_PLATE_THRESHOLD or 0
    if threshold <= 0 or type(activeNameplates) ~= "table" then
        return false
    end

    local count = 0
    for _ in pairs(activeNameplates) do
        count = count + 1
        if count >= threshold then
            return true
        end
    end

    return false
end

function Nameplates:SetNpcTitleResolveJobEnabled(enabled)
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants or not RefineUI.SetUpdateJobEnabled then
        return
    end

    RefineUI:SetUpdateJobEnabled(constants.NPC_TITLE_RESOLVE_JOB_KEY, enabled == true, false)
end

function Nameplates:EnsureNpcTitleResolveJob()
    local private = self:GetPrivate()
    local constants = private and private.Constants
    if not constants or not RefineUI.RegisterUpdateJob then
        return false
    end

    if RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(constants.NPC_TITLE_RESOLVE_JOB_KEY) then
        return true
    end

    local interval = constants.NPC_TITLE_RESOLVE_INTERVAL_SECONDS or 0.03
    RefineUI:RegisterUpdateJob(
        constants.NPC_TITLE_RESOLVE_JOB_KEY,
        interval,
        function()
            Nameplates:DrainNpcTitleResolveQueue()
        end,
        {
            enabled = false,
            safe = true,
            disableOnError = true,
        }
    )

    return true
end

function Nameplates:CancelNpcTitleResolve(unitFrame)
    if not unitFrame then
        return
    end

    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    local queued = runtime.npcTitleResolveQueuedByFrame[unitFrame]
    if queued then
        queued.cancelled = true
        runtime.npcTitleResolveQueuedByFrame[unitFrame] = nil
    end
end

function Nameplates:ClearNpcTitleResolveQueue()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    if not runtime then
        return
    end

    wipe(runtime.npcTitleResolveQueue)
    wipe(runtime.npcTitleResolveQueuedByFrame)
    runtime.npcTitleResolveHead = 1
    self:SetNpcTitleResolveJobEnabled(false)
end

function Nameplates:EnqueueNpcTitleResolve(nameplate, unitFrame, unit)
    if not nameplate or not unitFrame or not unit then
        return false
    end

    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local util = private and private.Util
    if not runtime or not util then
        return false
    end

    local resolvedUnit = util.ResolveUnitToken(unit, unitFrame.unit)
    if not resolvedUnit then
        return false
    end

    if not self:EnsureNpcTitleResolveJob() then
        return false
    end

    local existing = runtime.npcTitleResolveQueuedByFrame[unitFrame]
    if existing then
        existing.unit = resolvedUnit
        existing.nameplate = nameplate
        existing.cancelled = false
        return true
    end

    local entry = {
        nameplate = nameplate,
        unitFrame = unitFrame,
        unit = resolvedUnit,
        cancelled = false,
    }
    runtime.npcTitleResolveQueuedByFrame[unitFrame] = entry
    tinsert(runtime.npcTitleResolveQueue, entry)
    self:SetNpcTitleResolveJobEnabled(true)
    return true
end

function Nameplates:DrainNpcTitleResolveQueue()
    local private = self:GetPrivate()
    local runtime = private and private.Runtime
    local constants = private and private.Constants
    local util = private and private.Util
    if not runtime or not constants or not util then
        return
    end

    local queue = runtime.npcTitleResolveQueue
    local head = runtime.npcTitleResolveHead or 1
    local tail = #queue
    if head > tail then
        wipe(queue)
        runtime.npcTitleResolveHead = 1
        self:SetNpcTitleResolveJobEnabled(false)
        return
    end

    local budget = constants.NPC_TITLE_RESOLVE_BUDGET_PER_TICK or 4
    local processed = 0
    while processed < budget and head <= tail do
        local entry = queue[head]
        queue[head] = nil
        head = head + 1

        if entry and entry.unitFrame then
            runtime.npcTitleResolveQueuedByFrame[entry.unitFrame] = nil

            if not entry.cancelled then
                local unitFrame = entry.unitFrame
                local nameplate = unitFrame.GetParent and unitFrame:GetParent() or nil
                if nameplate and nameplate.UnitFrame == unitFrame then
                    local unit = util.ResolveUnitToken(entry.unit, unitFrame.unit)
                    if unit then
                        self:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = true, fromQueue = true })
                    end
                end
            end
        end

        processed = processed + 1
    end

    runtime.npcTitleResolveHead = head
    if head > tail then
        wipe(queue)
        runtime.npcTitleResolveHead = 1
        self:SetNpcTitleResolveJobEnabled(false)
    else
        self:SetNpcTitleResolveJobEnabled(true)
    end
end

function Nameplates:BuildNpcTitleTimerKey(unitFrame)
    local private = self:GetPrivate()
    local constants = private and private.Constants
    return (constants and constants.NPC_TITLE_TIMER_KEY_PREFIX or "Nameplates:NPCTitleRetry:") .. tostring(unitFrame)
end

function Nameplates:CancelNpcTitleRetry(unitFrame)
    if not unitFrame then
        return
    end
    RefineUI:CancelTimer(self:BuildNpcTitleTimerKey(unitFrame))
end

function Nameplates:SetNpcTitleText(data, title)
    if not data or not data.RefineNpcTitle then
        return
    end

    local util = GetUtil()
    if util and (util.IsSecret(title) or type(title) ~= "string" or not util.IsAccessibleValue(title)) then
        title = nil
    end

    if title then
        local formattedTitle = "<" .. title .. ">"
        if data.RefineNpcTitleFormatted ~= formattedTitle then
            data.RefineNpcTitle:SetText(formattedTitle)
            data.RefineNpcTitleFormatted = formattedTitle
        end
        data.RefineNpcTitle:Show()
        return
    end

    if data.RefineNpcTitleFormatted ~= "" then
        data.RefineNpcTitle:SetText("")
        data.RefineNpcTitleFormatted = ""
    end
    data.RefineNpcTitle:Hide()
end

function Nameplates:ApplyNpcTitleVisual(nameplate, unit, opts)
    if not nameplate then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local data = self:GetNameplateData(unitFrame)

    if not IsNpcTitleFeatureEnabled() then
        self:CancelNpcTitleResolve(unitFrame)
        self:CancelNpcTitleRetry(unitFrame)
        if data.RefineNpcTitle then
            self:SetNpcTitleText(data, nil)
        end
        return
    end

    local private = self:GetPrivate()
    local util = private and private.Util
    if not util then
        return
    end

    local resolvedUnit = util.ResolveUnitToken(unit, unitFrame.unit)
    if not resolvedUnit or not IsEligibleNpcTitleUnit(resolvedUnit, data) then
        self:CancelNpcTitleResolve(unitFrame)
        self:CancelNpcTitleRetry(unitFrame)
        if data.RefineNpcTitle then
            self:SetNpcTitleText(data, nil)
        end
        return
    end

    if not EnsureNpcTitleFontString(unitFrame, data) then
        return
    end

    local runtime = private and private.Runtime
    local guid = UnitGUID(resolvedUnit)
    local cacheGUID = nil
    if runtime and type(guid) == "string" and guid ~= "" and not util.IsSecret(guid) and util.IsAccessibleValue(guid) then
        cacheGUID = guid
    end

    if cacheGUID and runtime then
        local cachedTitle = runtime.npcTitleCacheByGUID[cacheGUID]
        if cachedTitle ~= nil then
            self:CancelNpcTitleResolve(unitFrame)
            self:CancelNpcTitleRetry(unitFrame)
            self:SetNpcTitleText(data, cachedTitle ~= false and cachedTitle or nil)
            return
        end
    end

    opts = opts or {}
    if opts.allowResolve ~= true then
        if opts.fromQueue ~= true then
            self:CancelNpcTitleResolve(unitFrame)
        end
        self:SetNpcTitleText(data, nil)
        return
    end

    if opts.fromQueue ~= true and opts.fromRetry ~= true and ShouldDeferNpcTitleResolve(data) then
        if self:EnqueueNpcTitleResolve(nameplate, unitFrame, resolvedUnit) then
            self:SetNpcTitleText(data, nil)
            return
        end
    end

    local resolvedTitle, isResolved = ResolveNpcTitle(resolvedUnit)
    if isResolved then
        self:CancelNpcTitleResolve(unitFrame)
        self:CancelNpcTitleRetry(unitFrame)
        self:SetNpcTitleText(data, resolvedTitle)
        return
    end

    self:SetNpcTitleText(data, nil)

    if opts.fromRetry == true then
        return
    end

    local constants = private and private.Constants
    local retryDelay = constants and constants.NPC_TITLE_RETRY_DELAY_SECONDS or 0.2
    local expectedGUID = cacheGUID
    local retryKey = self:BuildNpcTitleTimerKey(unitFrame)

    RefineUI:After(retryKey, retryDelay, function()
        if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
            return
        end

        local retryNameplate = unitFrame:GetParent()
        if not retryNameplate or retryNameplate.UnitFrame ~= unitFrame then
            return
        end

        local retryUnit = util.ResolveUnitToken(unitFrame.unit)
        if not retryUnit then
            return
        end

        if expectedGUID then
            local currentGUID = UnitGUID(retryUnit)
            if util.IsSecret(currentGUID) or not util.IsAccessibleValue(currentGUID) or currentGUID ~= expectedGUID then
                return
            end
        end

        self:ApplyNpcTitleVisual(retryNameplate, retryUnit, { allowResolve = true, fromRetry = true })
    end)
end

----------------------------------------------------------------------------------------
-- Text Rendering API
----------------------------------------------------------------------------------------
function Nameplates:UpdateName(nameplate, unit)
    if not nameplate then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local name = unitFrame.name or (unitFrame.NameContainer and unitFrame.NameContainer.Name)
    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not name then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    local desiredNameFontSize = self:GetScaledNameplateNameFontSize()

    if not data.RefineName then
        data.RefineName = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        local anchor = health or unitFrame
        RefineUI.Point(data.RefineName, "BOTTOM", anchor, health and "TOP" or "CENTER", 0, health and 4 or 0)
        data.RefineNameFontSize = desiredNameFontSize
    elseif data.RefineNameFontSize ~= desiredNameFontSize then
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        data.RefineNameFontSize = desiredNameFontSize
    end

    if data.NameSource ~= name then
        data.NameSource = name

        RefineUI:HookOnce(self:BuildHookKey(name, "SetText"), name, "SetText", function(_, txt)
            local frameData = RefineUI.NameplateData[unitFrame]
            if frameData and frameData.RefineName then
                SetRefineNameTextIfChanged(frameData, NormalizeNameText(txt or "", unitFrame.unit))
            end
        end)

        RefineUI:HookOnce(self:BuildHookKey(name, "SetAlpha"), name, "SetAlpha", function(nameObj, alpha)
            if alpha ~= 0 then
                nameObj:SetAlpha(0)
            end
        end)
    end

    name:SetAlpha(0)
    SetRefineNameTextIfChanged(data, NormalizeNameText(name:GetText() or "", unit))

    self:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = false })
end

function Nameplates:UpdateHealth(nameplate, unit)
    if not nameplate or not unit then
        return
    end

    local unitFrame = nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local health = unitFrame.healthBar or unitFrame.HealthBar
    if not health then
        return
    end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        return
    end

    if data.RefineHidden then
        return
    end

    local desiredHealthFontSize = self:GetScaledNameplateHealthFontSize()

    if not data.RefineHealth then
        local parent = (data.HealthBorderOverlay and data.HealthBorderOverlay.border) or health
        data.RefineHealth = parent:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        RefineUI.Point(data.RefineHealth, "CENTER", health, "CENTER", 0, -2)
        data.RefineHealthFontSize = desiredHealthFontSize
    elseif data.RefineHealthFontSize ~= desiredHealthFontSize then
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        data.RefineHealthFontSize = desiredHealthFontSize
    end

    local private = self:GetPrivate()
    local barTexture = private and private.Textures and private.Textures.HEALTH_BAR

    if barTexture and health.SetStatusBarTexture and data.HealthTextureApplied ~= barTexture then
        health:SetStatusBarTexture(barTexture)
        data.HealthTextureApplied = barTexture
    end
    if health.SetStatusBarDesaturated and data.HealthTextureDesaturated ~= true then
        health:SetStatusBarDesaturated(true)
        data.HealthTextureDesaturated = true
    end

    local percent = UnitHealthPercent(unit, true, RefineUI.GetPercentCurve())
    local util = private and private.Util
    if util and util.IsSecret(percent) then
        -- Secret values must never be compared or cached as comparable fields.
        data.RefineHealth:SetText(percent)
        data.LastHealthPercentSecret = true
        data.LastHealthPercentRounded = nil
        return
    end

    if type(percent) ~= "number" then
        if data.LastHealthPercentRounded ~= false then
            data.RefineHealth:SetText("")
            data.LastHealthPercentRounded = false
            data.LastHealthPercentSecret = nil
        end
        return
    end

    local roundedPercent = floor(percent + 0.5)
    if data.LastHealthPercentRounded ~= roundedPercent then
        data.RefineHealth:SetFormattedText("%.0f", percent)
        data.LastHealthPercentRounded = roundedPercent
        data.LastHealthPercentSecret = nil
    end
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function RefineUI:RefreshAllNameplateNpcTitles(_reason)
    local private = Nameplates:GetPrivate()
    local activeNameplates = private and private.ActiveNameplates or {}

    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            if nameplate and nameplate.UnitFrame then
                Nameplates:ApplyNpcTitleVisual(nameplate, nameplate.UnitFrame.unit, { allowResolve = true })
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        if nameplate and nameplate.UnitFrame then
            Nameplates:ApplyNpcTitleVisual(nameplate, unit, { allowResolve = true })
        end
    end
end

function RefineUI:RefreshAllNameplateTextScales(_reason)
    local private = Nameplates:GetPrivate()
    local activeNameplates = private and private.ActiveNameplates or {}
    local util = private and private.Util

    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            local unitFrame = nameplate and nameplate.UnitFrame
            local unit = unitFrame and util and util.ResolveUnitToken(unitFrame.unit)
            if unit then
                Nameplates:UpdateName(nameplate, unit)
                Nameplates:UpdateHealth(nameplate, unit)
            end
        end
        return
    end

    for nameplate, unit in pairs(activeNameplates) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local resolvedUnit = util and util.ResolveUnitToken(unit, unitFrame and unitFrame.unit)
        if resolvedUnit then
            Nameplates:UpdateName(nameplate, resolvedUnit)
            Nameplates:UpdateHealth(nameplate, resolvedUnit)
        end
    end
end
