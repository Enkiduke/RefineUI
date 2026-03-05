----------------------------------------------------------------------------------------
-- CDM Component: Config
-- Description: CDM configuration defaults, validation, and mode accessors.
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
local pairs = pairs
local pcall = pcall
local GetCVarBool = GetCVarBool
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:GetConfig()
    RefineUI.Config.CDM = RefineUI.Config.CDM or {}
    local cfg = RefineUI.Config.CDM

    if cfg.Enable == nil then
        cfg.Enable = true
    end

    if type(cfg.IconSize) ~= "number" then
        cfg.IconSize = 44
    end

    if type(cfg.IconScale) ~= "number" then
        if type(cfg.IconSize) == "number" and cfg.IconSize > 0 then
            cfg.IconScale = cfg.IconSize / 44
        else
            cfg.IconScale = 1
        end
    end

    if type(cfg.Spacing) ~= "number" then
        cfg.Spacing = 6
    end

    if type(cfg.BucketSettings) ~= "table" then
        cfg.BucketSettings = {}
    end

    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        if type(cfg.BucketSettings[bucket]) ~= "table" then
            cfg.BucketSettings[bucket] = {}
        end

        if type(cfg.BucketSettings[bucket].IconScale) ~= "number" then
            local legacySize = cfg.BucketSettings[bucket].IconSize
            if type(legacySize) == "number" and legacySize > 0 then
                cfg.BucketSettings[bucket].IconScale = legacySize / 44
            else
                cfg.BucketSettings[bucket].IconScale = cfg.IconScale
            end
        end

        if type(cfg.BucketSettings[bucket].Spacing) ~= "number" then
            cfg.BucketSettings[bucket].Spacing = cfg.Spacing
        end

        if cfg.BucketSettings[bucket].Orientation ~= "VERTICAL" then
            cfg.BucketSettings[bucket].Orientation = "HORIZONTAL"
        end

        if type(cfg.BucketSettings[bucket].Direction) ~= "string" or cfg.BucketSettings[bucket].Direction == "" then
            cfg.BucketSettings[bucket].Direction = self.TRACKER_DEFAULT_DIRECTION[bucket] or "RIGHT"
        end
    end

    if cfg.HideNativeAuraViewers == nil then
        cfg.HideNativeAuraViewers = true
    end

    if cfg.SkinCooldownViewer == nil then
        cfg.SkinCooldownViewer = true
    end

    if cfg.AuraMode ~= "blizzard" then
        cfg.AuraMode = "refineui"
    end

    if cfg.SyncStrategy ~= "auto_safe" and cfg.SyncStrategy ~= "mirror_only" then
        cfg.SyncStrategy = "auto_safe"
    end

    if cfg.SourceScope ~= "all_auras" then
        cfg.SourceScope = "buffs_exact"
    end

    if type(cfg.PayloadGhostTTL) ~= "number" then
        cfg.PayloadGhostTTL = 0.20
    end

    if cfg.PayloadGhostTTL < 0 then
        cfg.PayloadGhostTTL = 0
    elseif cfg.PayloadGhostTTL > 2 then
        cfg.PayloadGhostTTL = 2
    end

    if type(cfg.LayoutAssignments) ~= "table" then
        cfg.LayoutAssignments = {}
    end

    if type(cfg.VisualOverrides) ~= "table" then
        cfg.VisualOverrides = {}
    else
        for layoutKey, layoutStyles in pairs(cfg.VisualOverrides) do
            if type(layoutStyles) ~= "table" then
                cfg.VisualOverrides[layoutKey] = nil
            else
                for rawCooldownID, style in pairs(layoutStyles) do
                    local cooldownID = rawCooldownID
                    if type(cooldownID) ~= "number" then
                        cooldownID = tonumber(rawCooldownID)
                    end

                    local validCooldownID = type(cooldownID) == "number" and cooldownID > 0
                    if not validCooldownID or type(style) ~= "table" then
                        layoutStyles[rawCooldownID] = nil
                    else
                        if type(style.Border) ~= "table" then
                            style.Border = nil
                        end
                        if type(style.Bar) ~= "table" then
                            style.Bar = nil
                        end
                        if type(style.Font) ~= "table" then
                            style.Font = nil
                        end
                        if style.Border == nil and style.Bar == nil and style.Font == nil then
                            layoutStyles[rawCooldownID] = nil
                        elseif rawCooldownID ~= cooldownID and layoutStyles[cooldownID] == nil then
                            layoutStyles[cooldownID] = style
                            layoutStyles[rawCooldownID] = nil
                        end
                    end
                end
            end
        end
    end

    return cfg
end

function CDM:IsEnabled()
    return self:GetConfig().Enable ~= false
end

function CDM:IsBlizzardCooldownManagerEnabled()
    local cvarRegistry = _G.CVarCallbackRegistry
    if cvarRegistry and type(cvarRegistry.GetCVarValueBool) == "function" then
        local ok, enabled = pcall(cvarRegistry.GetCVarValueBool, cvarRegistry, "cooldownViewerEnabled")
        if ok and not (issecretvalue and issecretvalue(enabled)) and type(enabled) == "boolean" then
            return enabled
        end
    end

    if type(GetCVarBool) == "function" then
        local ok, enabled = pcall(GetCVarBool, "cooldownViewerEnabled")
        if ok and not (issecretvalue and issecretvalue(enabled)) and type(enabled) == "boolean" then
            return enabled
        end
    end

    -- Fail open if Blizzard APIs are unavailable so CDM does not self-disable incorrectly.
    return true
end

function CDM:GetSyncStrategy()
    return self:GetConfig().SyncStrategy or "auto_safe"
end

function CDM:GetSourceScope()
    return self:GetConfig().SourceScope or "buffs_exact"
end

function CDM:GetPayloadGhostTTL()
    local ttl = self:GetConfig().PayloadGhostTTL
    if type(ttl) ~= "number" then
        return 0.20
    end
    if ttl < 0 then
        return 0
    end
    if ttl > 2 then
        return 2
    end
    return ttl
end

function CDM:GetAuraMode()
    local cfg = self:GetConfig()
    if cfg.AuraMode == "blizzard" then
        return "blizzard"
    end
    return "refineui"
end

function CDM:IsRefineAuraModeActive()
    return self:GetAuraMode() == "refineui"
end

function CDM:SetAuraMode(mode)
    local cfg = self:GetConfig()
    local previousMode = self:GetAuraMode()
    if mode == "blizzard" then
        cfg.AuraMode = "blizzard"
    else
        cfg.AuraMode = "refineui"
    end

    if previousMode ~= "refineui"
        and cfg.AuraMode == "refineui"
        and self.RequestInitialTrackedBuffClear then
        self:RequestInitialTrackedBuffClear()
    end

    self:ApplyNativeAuraViewerVisibility(true)
    self:RequestRefresh(true)
end

function CDM:ShouldHideNativeAuraViewers()
    local cfg = self:GetConfig()
    return cfg.HideNativeAuraViewers ~= false
end
