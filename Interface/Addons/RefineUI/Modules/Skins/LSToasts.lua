----------------------------------------------------------------------------------------
-- Skins Component: LS:Toasts
-- Description: Registers RefineUI skins for LS:Toasts.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BORDER_EPSILON = 0.005
local ICON_TEX_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local SHINE_TEXTURE = "Interface\\AchievementFrame\\UI-Achievement-Alert-Glow"
local SHINE_TEX_COORDS = { 403 / 512, 465 / 512, 15 / 256, 61 / 256 }
local REFINE_SKINS = {
    refineui = true,
    ["refineui-minimal"] = true,
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local callbacksRegistered = false

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetBorderColor()
    local color = Config.General.BorderColor
    return color[1], color[2], color[3], color[4] or 1
end

local function GetActiveRefineSkin(configTable)
    local profile = configTable and configTable.db and configTable.db.profile
    local skin = profile and profile.skin
    return skin and REFINE_SKINS[skin] and skin or nil
end

local function ColorsDiffer(r, g, b, a, dr, dg, db, da)
    return abs(r - dr) > BORDER_EPSILON
        or abs(g - dg) > BORDER_EPSILON
        or abs(b - db) > BORDER_EPSILON
        or abs((a or 1) - da) > BORDER_EPSILON
end

local function SyncToastAccent(toast, configTable)
    local activeSkin = GetActiveRefineSkin(configTable)
    if not toast or not activeSkin then
        return
    end

    local glow, shine = toast.Glow, toast.Shine
    if activeSkin == "refineui-minimal" then
        if glow then
            glow:SetVertexColor(1, 1, 1, 0)
        end
        if shine then
            shine:SetVertexColor(1, 1, 1, 0)
        end
        return
    end

    local borderTop = toast.Border and toast.Border.TOP
    if not borderTop then
        return
    end

    local r, g, b, a = borderTop:GetVertexColor()
    local defaultR, defaultG, defaultB, defaultA = GetBorderColor()
    local glowAlpha = ColorsDiffer(r, g, b, a, defaultR, defaultG, defaultB, defaultA) and 1 or 0.85

    if glow then
        glow:SetVertexColor(r, g, b, glowAlpha)
    end
    if shine then
        shine:SetVertexColor(r, g, b, 1)
    end
end

local function SyncExistingToasts(configTable)
    for index = 1, 64 do
        local toast = _G["LSToast" .. index]
        if toast then
            SyncToastAccent(toast, configTable)
        end
    end
end

local function BuildSkinDefinition(minimalMotion)
    local borderR, borderG, borderB, borderA = GetBorderColor()
    local backdrop = Config.General.BackdropColor
    local borderTexture = Media.Textures.Border

    return {
        name = minimalMotion and "RefineUI (Minimal)" or "RefineUI",
        border = {
            color = { borderR, borderG, borderB, borderA },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        title = {
            color = { 1, 0.82, 0, 1 },
        },
        text = {
            color = { 1, 1, 1, 1 },
        },
        leaves = {
            hidden = true,
        },
        dragon = {
            hidden = true,
        },
        icon = {
            tex_coords = ICON_TEX_COORDS,
        },
        icon_border = {
            color = { borderR, borderG, borderB, borderA },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        icon_highlight = {
            hidden = true,
        },
        slot = {
            tex_coords = ICON_TEX_COORDS,
        },
        slot_border = {
            color = { borderR, borderG, borderB, borderA },
            offset = -4,
            size = 12,
            texture = borderTexture,
        },
        text_bg = {
            hidden = true,
        },
        bg = {
            default = {
                texture = { backdrop[1], backdrop[2], backdrop[3], backdrop[4] or 0.8 },
            },
        },
        glow = {
            texture = minimalMotion and { 1, 1, 1, 0 } or { 1, 1, 1, 1 },
            color = minimalMotion and { 1, 1, 1, 0 } or { borderR, borderG, borderB, 0.85 },
            size = { 226, 50 },
            point = { p = "CENTER", rP = "CENTER", x = 0, y = 0 },
        },
        shine = {
            texture = minimalMotion and { 1, 1, 1, 0 } or SHINE_TEXTURE,
            tex_coords = SHINE_TEX_COORDS,
            color = minimalMotion and { 1, 1, 1, 0 } or { borderR, borderG, borderB, 1 },
            size = { 67, 50 },
            point = { p = "BOTTOMLEFT", rP = "BOTTOMLEFT", x = 0, y = -1 },
        },
    }
end

----------------------------------------------------------------------------------------
-- Skin Registration
----------------------------------------------------------------------------------------
local function RegisterLSToastsSkin()
    local LST = _G.ls_Toasts
    local events = LST and LST[1]
    if not events or not events.RegisterSkin then
        return
    end
    local configTable = LST[2]

    events:RegisterSkin("refineui", BuildSkinDefinition(false))
    events:RegisterSkin("refineui-minimal", BuildSkinDefinition(true))

    if not callbacksRegistered and events.RegisterCallback then
        callbacksRegistered = true

        local function HandleToastEvent(_, toast)
            SyncToastAccent(toast, configTable)
        end

        events:RegisterCallback("ToastCreated", HandleToastEvent)
        events:RegisterCallback("SkinSet", HandleToastEvent)
        events:RegisterCallback("SkinReset", HandleToastEvent)
        events:RegisterCallback("ToastSpawned", HandleToastEvent)
    end

    SyncExistingToasts(configTable)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupLSToastsSkin()
    -- Core's SkinFuncs loader runs this on ls_Toasts' ADDON_LOADED, or on
    -- PLAYER_ENTERING_WORLD when ls_Toasts loaded first.
    RefineUI.SkinFuncs["ls_Toasts"] = RegisterLSToastsSkin
end
