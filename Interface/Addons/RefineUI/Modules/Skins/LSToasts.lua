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
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local abs = math.abs
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
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
local function ResolveColorTriplet(color, fallbackR, fallbackG, fallbackB, fallbackA)
    if type(color) ~= "table" then
        return fallbackR, fallbackG, fallbackB, fallbackA
    end

    if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b, color.a or fallbackA
    end

    return color[1] or fallbackR, color[2] or fallbackG, color[3] or fallbackB, color[4] or fallbackA
end

local function GetToastsModule()
    return RefineUI:GetModule("Toasts")
end

local function GetContract()
    local toasts = GetToastsModule()
    if toasts and type(toasts.GetToastVisualContract) == "function" then
        return toasts:GetToastVisualContract()
    end

    local borderColor = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    local backdropColor = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BackdropColor
    local borderR, borderG, borderB, borderA = ResolveColorTriplet(borderColor, 0.6, 0.6, 0.6, 1)
    local backR, backG, backB, backA = ResolveColorTriplet(backdropColor, 0.1, 0.1, 0.1, 0.8)
    local borderTexture = (RefineUI.Media and RefineUI.Media.Textures and RefineUI.Media.Textures.Border)
        or "Interface\\AddOns\\RefineUI\\Media\\Textures\\RefineBorder.blp"

    return {
        border = {
            color = { borderR, borderG, borderB, borderA },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        icon = {
            texCoords = { 0.08, 0.92, 0.08, 0.92 },
        },
        iconBorder = {
            color = { borderR, borderG, borderB, borderA },
            offset = -6,
            size = 14,
            texture = borderTexture,
        },
        slotBorder = {
            color = { borderR, borderG, borderB, borderA },
            offset = -4,
            size = 12,
            texture = borderTexture,
        },
        background = {
            color = { backR, backG, backB, backA },
        },
        titleColor = {
            1,
            0.82,
            0,
            1,
        },
        textColor = {
            1,
            1,
            1,
            1,
        },
        glow = {
            size = { 226, 50 },
            point = {
                p = "CENTER",
                rP = "CENTER",
                x = 0,
                y = 0,
            },
            color = { borderR, borderG, borderB, 0.85 },
        },
        shine = {
            texture = "Interface\\AchievementFrame\\UI-Achievement-Alert-Glow",
            texCoords = { 403 / 512, 465 / 512, 15 / 256, 61 / 256 },
            size = { 67, 50 },
            point = {
                p = "BOTTOMLEFT",
                rP = "BOTTOMLEFT",
                x = 0,
                y = -1,
            },
            color = { borderR, borderG, borderB, 1 },
        },
    }
end

local function GetActiveRefineSkin(configTable)
    local profile = configTable and configTable.db and configTable.db.profile
    local skin = profile and profile.skin
    return skin and REFINE_SKINS[skin] and skin or nil
end

local function ColorsDiffer(r, g, b, a, dr, dg, db, da)
    return abs((r or 0) - (dr or 0)) > BORDER_EPSILON
        or abs((g or 0) - (dg or 0)) > BORDER_EPSILON
        or abs((b or 0) - (db or 0)) > BORDER_EPSILON
        or abs((a or 1) - (da or 1)) > BORDER_EPSILON
end

local function GetToastBorderColor(toast)
    local border = toast and toast.Border
    local section = border and border.TOP
    if section and section.GetVertexColor then
        return section:GetVertexColor()
    end

    return nil
end

local function SyncToastAccent(toast, configTable)
    local activeSkin = GetActiveRefineSkin(configTable)
    if not toast or not activeSkin then
        return
    end

    if activeSkin == "refineui-minimal" then
        if toast.Glow and toast.Glow.SetVertexColor then
            toast.Glow:SetVertexColor(1, 1, 1, 0)
        end
        if toast.Shine and toast.Shine.SetVertexColor then
            toast.Shine:SetVertexColor(1, 1, 1, 0)
        end
        return
    end

    local r, g, b, a = GetToastBorderColor(toast)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return
    end

    local contract = GetContract()
    local defaultR, defaultG, defaultB, defaultA = ResolveColorTriplet(contract and contract.border and contract.border.color, 0.6, 0.6, 0.6, 1)
    local glowAlpha = ColorsDiffer(r, g, b, a, defaultR, defaultG, defaultB, defaultA) and 1 or 0.85

    if toast.Glow and toast.Glow.SetVertexColor then
        toast.Glow:SetVertexColor(r, g, b, glowAlpha)
    end
    if toast.Shine and toast.Shine.SetVertexColor then
        toast.Shine:SetVertexColor(r, g, b, 1)
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
    local contract = GetContract()
    local borderR, borderG, borderB, borderA = ResolveColorTriplet(contract.border.color, 0.6, 0.6, 0.6, 1)
    local iconBorderR, iconBorderG, iconBorderB, iconBorderA = ResolveColorTriplet(contract.iconBorder.color, 0.6, 0.6, 0.6, 1)
    local slotBorderR, slotBorderG, slotBorderB, slotBorderA = ResolveColorTriplet(contract.slotBorder.color, 0.6, 0.6, 0.6, 1)
    local backR, backG, backB, backA = ResolveColorTriplet(contract.background.color, 0.1, 0.1, 0.1, 0.8)
    local titleR, titleG, titleB, titleA = ResolveColorTriplet(contract.titleColor, 1, 0.82, 0, 1)
    local textR, textG, textB, textA = ResolveColorTriplet(contract.textColor, 1, 1, 1, 1)
    local glowR, glowG, glowB, glowA = ResolveColorTriplet(contract.glow and contract.glow.color, borderR, borderG, borderB, 0.85)
    local shineR, shineG, shineB, shineA = ResolveColorTriplet(contract.shine and contract.shine.color, borderR, borderG, borderB, 1)
    local glowPoint = contract.glow and contract.glow.point or { p = "CENTER", rP = "CENTER", x = 0, y = 0 }
    local shinePoint = contract.shine and contract.shine.point or { p = "BOTTOMLEFT", rP = "BOTTOMLEFT", x = 0, y = -1 }

    local skin = {
        name = minimalMotion and "RefineUI (Minimal)" or "RefineUI",
        border = {
            color = { borderR, borderG, borderB, borderA },
            offset = contract.border.offset,
            size = contract.border.size,
            texture = contract.border.texture,
        },
        title = {
            color = { titleR, titleG, titleB, titleA },
        },
        text = {
            color = { textR, textG, textB, textA },
        },
        leaves = {
            hidden = true,
        },
        dragon = {
            hidden = true,
        },
        icon = {
            tex_coords = contract.icon.texCoords,
        },
        icon_border = {
            color = { iconBorderR, iconBorderG, iconBorderB, iconBorderA },
            offset = contract.iconBorder.offset,
            size = contract.iconBorder.size,
            texture = contract.iconBorder.texture,
        },
        icon_highlight = {
            hidden = true,
        },
        slot = {
            tex_coords = contract.icon.texCoords,
        },
        slot_border = {
            color = { slotBorderR, slotBorderG, slotBorderB, slotBorderA },
            offset = contract.slotBorder.offset,
            size = contract.slotBorder.size,
            texture = contract.slotBorder.texture,
        },
        text_bg = {
            hidden = true,
        },
        bg = {
            default = {
                texture = { backR, backG, backB, backA or 0.8 },
            },
        },
        glow = {
            texture = minimalMotion and { 1, 1, 1, 0 } or { 1, 1, 1, 1 },
            color = minimalMotion and { 1, 1, 1, 0 } or { glowR, glowG, glowB, glowA },
            size = contract.glow.size,
            point = glowPoint,
        },
        shine = {
            texture = minimalMotion and { 1, 1, 1, 0 } or contract.shine.texture,
            tex_coords = contract.shine.texCoords,
            color = minimalMotion and { 1, 1, 1, 0 } or { shineR, shineG, shineB, shineA },
            size = contract.shine.size,
            point = shinePoint,
        },
    }

    return skin
end

----------------------------------------------------------------------------------------
-- Skin Registration
----------------------------------------------------------------------------------------
local function RegisterLSToastsSkin()
    local LST = _G.ls_Toasts
    if not LST then
        return
    end

    local events = LST[1]
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

RefineUI.SkinFuncs["ls_Toasts"] = RegisterLSToastsSkin
