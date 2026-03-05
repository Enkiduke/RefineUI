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
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LST_GLOW_SIZE = 8
local BORDER_EPSILON = 0.005
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
local function ResolveColorTriplet(color, fallbackR, fallbackG, fallbackB)
    if type(color) ~= "table" then
        return fallbackR, fallbackG, fallbackB
    end
    if color.r and color.g and color.b then
        return color.r, color.g, color.b
    end
    return color[1] or fallbackR, color[2] or fallbackG, color[3] or fallbackB
end

local function GetDefaultBorderColor()
    local color = Config and Config.General and Config.General.BorderColor
    local r, g, b = ResolveColorTriplet(color, 0.6, 0.6, 0.6)
    local a = (type(color) == "table" and (color.a or color[4])) or 1
    return r, g, b, a
end

local function IsRefineSkinActive(C)
    local profile = C and C.db and C.db.profile
    local skin = profile and profile.skin
    return skin and REFINE_SKINS[skin]
end

local function ColorsDiffer(r, g, b, a, dr, dg, db, da)
    return abs(r - dr) > BORDER_EPSILON
        or abs(g - dg) > BORDER_EPSILON
        or abs(b - db) > BORDER_EPSILON
        or abs((a or 1) - (da or 1)) > BORDER_EPSILON
end

local function SyncToastBorderGlow(toast, C, r, g, b, a)
    if not toast then
        return
    end

    local glow = toast.glow
    if not IsRefineSkinActive(C) then
        if glow then
            glow:Hide()
        end
        return
    end

    local dr, dg, db, da = GetDefaultBorderColor()
    r = r or dr
    g = g or dg
    b = b or db
    a = a or 1

    if ColorsDiffer(r, g, b, a, dr, dg, db, da) then
        if not glow and RefineUI.CreateGlow then
            glow = RefineUI.CreateGlow(toast, LST_GLOW_SIZE)
        end
        if glow and glow.SetBackdropBorderColor then
            glow:SetBackdropBorderColor(r, g, b, a > 0.95 and 0.95 or a)
            glow:Show()
        end
    elseif glow then
        glow:Hide()
    end
end

local function SyncToastFromCurrentBorder(toast, C)
    local border = toast and toast.Border
    local section = border and border.TOP
    if section and section.GetVertexColor then
        local r, g, b, a = section:GetVertexColor()
        SyncToastBorderGlow(toast, C, r, g, b, a)
    end
end

local function HookToastBorderColor(toast, C)
    if not toast or toast._refineLSTGlowHooked then
        return
    end

    local border = toast.Border
    if not border or not border.SetVertexColor then
        return
    end

    local originalSetVertexColor = border.SetVertexColor
    border.SetVertexColor = function(self, r, g, b, a)
        originalSetVertexColor(self, r, g, b, a)
        SyncToastBorderGlow(toast, C, r, g, b, a)
    end

    toast._refineLSTGlowHooked = true
    SyncToastFromCurrentBorder(toast, C)
end

local function HookExistingToasts(C)
    for i = 1, 64 do
        local toast = _G["LSToast" .. i]
        if toast then
            HookToastBorderColor(toast, C)
        end
    end
end

local function RegisterLSToastsSkin()
    local LST = _G.ls_Toasts
    if not LST then
        return
    end

    local E = LST[1]
    if not E or not E.RegisterSkin then
        return
    end
    local C = LST[2]

    local borderColor = (Config and Config.General and Config.General.BorderColor) or { 0.6, 0.6, 0.6 }
    local backdropColor = (Config and Config.General and Config.General.BackdropColor) or { 0.1, 0.1, 0.1, 0.8 }
    local borderTexture = (Media and Media.Textures and Media.Textures.Border) or "Interface\\AddOns\\RefineUI\\Media\\Textures\\RefineBorder.blp"

    E:RegisterSkin("refineui", {
        name = "RefineUI",
        border = {
            color = { borderColor[1], borderColor[2], borderColor[3] },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        leaves = {
            hidden = true,
        },
        dragon = {
            hidden = true,
        },
        icon = {
            tex_coords = { 5 / 64, 59 / 64, 5 / 64, 59 / 64 },
        },
        icon_border = {
            color = { borderColor[1], borderColor[2], borderColor[3] },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        icon_highlight = {
            hidden = true,
        },
        slot = {
            tex_coords = { 5 / 64, 59 / 64, 5 / 64, 59 / 64 },
        },
        slot_border = {
            color = { borderColor[1], borderColor[2], borderColor[3] },
            offset = -4,
            size = 12,
            texture = borderTexture,
        },
        text_bg = {
            hidden = true,
        },
        bg = {
            default = {
                texture = { backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4] or 0.8 },
            },
        },
        glow = {
            texture = { 1, 1, 1, 1 },
            size = { 226, 50 },
        },
        shine = {
            tex_coords = { 403 / 512, 465 / 512, 15 / 256, 61 / 256 },
            size = { 67, 50 },
            point = {
                y = -1,
            },
        },
    })

    E:RegisterSkin("refineui-minimal", {
        name = "RefineUI (Minimal)",
        template = "refineui",
        glow = {
            hidden = true,
        },
        shine = {
            hidden = true,
        },
    })

    if not callbacksRegistered and E.RegisterCallback then
        callbacksRegistered = true

        E:RegisterCallback("ToastCreated", function(_, toast)
            HookToastBorderColor(toast, C)
        end)

        E:RegisterCallback("SkinSet", function(_, toast)
            HookToastBorderColor(toast, C)
            SyncToastFromCurrentBorder(toast, C)
        end)
    end

    HookExistingToasts(C)
end

RefineUI.SkinFuncs["ls_Toasts"] = RegisterLSToastsSkin
