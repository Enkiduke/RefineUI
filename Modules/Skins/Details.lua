local R, C, L = unpack(RefineUI)
if not C_AddOns.IsAddOnLoaded("Details") then return end
local version = C_AddOns.GetAddOnMetadata('RefineUI', 'Version') or ''
----------------------------------------------------------------------------------------
--	Details skin
----------------------------------------------------------------------------------------
-- hooksecurefunc(_detalhes.gump, "CreateNewLine", function(_, instancia, index)
-- 	local bar = _G["DetailsBarra_"..instancia.meu_id.."_"..index]
-- 	local icon = _G["DetailsBarra_IconFrame_"..instancia.meu_id.."_"..index]

-- 	if bar and not bar.backdrop then
-- 		bar:CreateBackdrop("Default")
-- 		bar.backdrop:SetPoint("TOPLEFT", icon, -2, 2)

-- 		bar.bg = bar:CreateTexture(nil, "BORDER")
-- 		bar.bg:SetAllPoints(bar)
-- 		bar.bg:SetTexture(C.media.texture)
-- 		bar.bg:SetVertexColor(.6, .6, .6, 0.25)
-- 	end

-- 	local frame = _G["DetailsUpFrameInstance"..instancia.meu_id]
-- 	if not frame.b then
-- 		frame.b = CreateFrame("Frame", nil, frame:GetParent())
-- 		frame.b:SetTemplate("Default")
-- 		frame.b:SetPoint("TOPLEFT", frame, "TOPLEFT", -23, 2)
-- 		frame.b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 34, 4)
-- 		frame.b:SetFrameLevel(frame:GetFrameLevel() - 1)
-- 	end
-- end)

local _detalhes = rawget(_G, '_detalhes')
local Details = rawget(_G, 'Details')
if _detalhes then
hooksecurefunc(_detalhes, "SetFontOutline", function(_, fontString)
	local fonte, size = fontString:GetFont()
	if fonte == "Interface\\AddOns\\RefineUI\\Media\\Fonts\\ITCAvantGardeStd-Demi.ttf" then
		fontString:SetFont(fonte, size, "OUTLINE")
		if fontString:GetShadowColor() then
			fontString:SetShadowColor(0, 0, 0, 1)
		end
	end
end)
end


local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if LSM then
LSM:Register(LSM.MediaType.FONT, "ITCAvantGardeStd-Demi", [[Interface\AddOns\RefineUI\Media\Fonts\ITCAvantGardeStd-Demi.ttf]])
LSM:Register(LSM.MediaType.FONT, "ITCAvantGardeStd-Bold", [[Interface\AddOns\RefineUI\Media\Fonts\ITCAvantGardeStd-Bold.ttf]])
LSM:Register(LSM.MediaType.STATUSBAR, 'RefineUIHeader', [[Interface\AddOns\RefineUI\Media\Textures\Details\Header.blp]])
LSM:Register(LSM.MediaType.STATUSBAR, 'RefineUIBar', [[Interface\AddOns\RefineUI\Media\Textures\Details\Bar.blp]])
LSM:Register(LSM.MediaType.STATUSBAR, 'RefineUIBG', [[Interface\AddOns\RefineUI\Media\Textures\Details\BG.blp]])
end

local function UpdateDetailsPosition()

    local detailsFrame = _G["DetailsBaseFrame1"] -- Adjust if your Details frame has a different name
    if not detailsFrame then return end


    -- -- Position Details to the left of the minimap, accounting for the title menu
    detailsFrame:SetHeight(280)
    
    -- Set the width to match the minimap
    detailsFrame:SetWidth(300)
end

local skinTable = {
    file = [[Interface\AddOns\Details\images\skins\flat_skin.blp]],
    author = "Karl-Heinz Schneider",
    version = version,
    site = "https://github.com/Karl-HeinzSchneider/WoW-Details-Skin-TheWarWithin",
    desc = "The War Within Skin.\n\n ...",
    no_cache = true,

    -- micro frames
    micro_frames = {color = {1, 1, 1, 1}, font = "Accidental Presidency", size = 10, textymod = 1},

    can_change_alpha_head = true,
    icon_anchor_main = {-1, -5},
    icon_anchor_plugins = {-7, -13},
    icon_plugins_size = {19, 18},

    -- anchors:
    icon_point_anchor = {-37, 0},
    left_corner_anchor = {-107, 0},
    right_corner_anchor = {96, 0},

    icon_point_anchor_bottom = {-37, 12},
    left_corner_anchor_bottom = {-107, 0},
    right_corner_anchor_bottom = {96, 0},

    icon_on_top = true,
    icon_ignore_alpha = true,
    icon_titletext_position = {3, 3},

    instance_cprops = {
        -- titlebar
        titlebar_shown = true,
        titlebar_height = 32,
        titlebar_texture = "RefineUIHeader",
        titlebar_texture_color = {1.0, 1.0, 1.0, 1.0},
        --
        ["toolbar_icon_file"] = "Interface\\AddOns\\Details\\images\\toolbar_icons_shadow",
        ["toolbar_side"] = 1,
        ["menu_anchor"] = {
            10, -- [1]
            10, -- [2]
            ["side"] = 2
        },
        --
        ["attribute_text"] = {
            ["enabled"] = true,
            ["shadow"] = true,
            ["side"] = 1,
            ["text_size"] = 13,
            ["custom_text"] = "{name}",
            ["text_face"] = "Friz Quadrata TT",
            ["anchor"] = {
                -4, -- [1]
                10 -- [2]
            },
            ["text_color"] = {
                NORMAL_FONT_COLOR.r, -- [1]
                NORMAL_FONT_COLOR.g, -- [2]
                NORMAL_FONT_COLOR.b, -- [3]
                NORMAL_FONT_COLOR.a -- [4]
            },
            ["enable_custom_text"] = false,
            ["show_timer"] = true
        },
        --
        ["row_info"] = {
            ["texture_highlight"] = "Interface\\FriendsFrame\\UI-FriendsList-Highlight",
            ["fixed_text_color"] = {
                1, -- [1]
                1, -- [2]
                1 -- [3]
            },
            ["height"] = 32, --
            ["space"] = {["right"] = 0, ["left"] = 0, ["between"] = 2}, --
            row_offsets = {left = 15, right = -15 - 8, top = -4, bottom = 0}, --
            ["texture_background_class_color"] = false,
            ["start_after_icon"] = false, --
            ["font_face_file"] = "Interface\\Addons\\Details\\fonts\\Accidental Presidency.ttf",
            ["backdrop"] = {
                ["enabled"] = false,
                ["size"] = 12,
                ["color"] = {
                    1, -- [1]
                    1, -- [2]
                    1, -- [3]
                    1 -- [4]
                },
                ["texture"] = "Details BarBorder 2"
            },
            ["icon_file"] = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Details\\Classes.blp",
            -- start_after_icon is duplicated; keep the keyed version above
            icon_offset = {-10, 0}, --
            --
            ["textL_show_number"] = true, --
            ["textL_outline"] = true,
            ["textL_enable_custom_text"] = false, --
            ["textL_custom_text"] = "{data1}. {data3}{data2}", --
            ["textL_class_colors"] = true,
            --
            ["textR_outline"] = true, --
            ["textR_bracket"] = "(",
            ["textR_enable_custom_text"] = false,
            ["textR_custom_text"] = "{data1} ({data2}, {data3}%)",
            ["textR_class_colors"] = false,
            ["textR_show_data"] = {
                false, -- [1]
                true, -- [2]
                true -- [3]
            },
            --
            ["fixed_texture_color"] = {
                0, -- [1]
                0, -- [2]
                0 -- [3]
            },
            ["models"] = {
                ["upper_model"] = "Spells\\AcidBreath_SuperGreen.M2",
                ["lower_model"] = "World\\EXPANSION02\\DOODADS\\Coldarra\\COLDARRALOCUS.m2",
                ["upper_alpha"] = 0.5,
                ["lower_enabled"] = false,
                ["lower_alpha"] = 0.1,
                ["upper_enabled"] = false
            },
            ["texture_custom_file"] = "Interface\\",
            ["texture_custom"] = "",
            ["alpha"] = 1,
            ["no_icon"] = false,
            ["texture"] = "RefineUIBar",
            ["texture_file"] = "Interface\\AddOns\\RefineUI\\Textures\\Details\\Bar.blp",
            ["texture_background"] = "RefineUIBG", --
            ["texture_background_file"] = "Interface\\AddOns\\RefineUI\\Textures\\Details\\BG.blp", --        

            ["fixed_texture_background_color"] = {1, 1, 1, 1}, --
            ["font_face"] = "Friz Quadrata TT", --
            ["font_size"] = 12, --
            ["textL_offset"] = 0, --
            ["text_yoffset"] = 12, --
            ["texture_class_colors"] = true,
            ["percent_type"] = 1,
            ["fast_ps_update"] = false,
            ["textR_separator"] = ",",
            ["use_spec_icons"] = true, --
            ["spec_file"] = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Details\\Specs.blp", --
            icon_size_offset = 5
        },
        --
        menu_icons_alpha = 1,
        ["show_statusbar"] = false,
        ["menu_icons_size"] = 1.07,
        ["color"] = {
            0.333333333333333, -- [1]
            0.333333333333333, -- [2]
            0.333333333333333, -- [3]
            0 -- [4]
        },
        ["bg_r"] = 0.0941176470588235,
        ["hide_out_of_combat"] = false,
        ["following"] = {
            ["bar_color"] = {
                1, -- [1]
                1, -- [2]
                1 -- [3]
            },
            ["enabled"] = false,
            ["text_color"] = {
                1, -- [1]
                1, -- [2]
                1 -- [3]
            }
        },
        ["color_buttons"] = {
            1, -- [1]
            1, -- [2]
            1, -- [3]
            1 -- [4]
        },
        ["skin_custom"] = "",
        ["menu_anchor_down"] = {
            16, -- [1]
            -3 -- [2]
        },
        ["micro_displays_locked"] = true,
        ["row_show_animation"] = {["anim"] = "Fade", ["options"] = {}},
        ["tooltip"] = {["n_abilities"] = 3, ["n_enemies"] = 3},
        ["total_bar"] = {
            ["enabled"] = false,
            ["only_in_group"] = true,
            ["icon"] = "Interface\\ICONS\\INV_Sigil_Thorim",
            ["color"] = {
                1, -- [1]
                1, -- [2]
                1 -- [3]
            }
        },
        ["show_sidebars"] = false,
        ["instance_button_anchor"] = {
            -27, -- [1]
            1 -- [2]
        },
        ["plugins_grow_direction"] = 1,
        ["menu_alpha"] = {
            ["enabled"] = false,
            ["onleave"] = 1,
            ["ignorebars"] = false,
            ["iconstoo"] = true,
            ["onenter"] = 1
        },
        ["micro_displays_side"] = 2,
        ["grab_on_top"] = false,
        ["strata"] = "LOW",
        ["bars_grow_direction"] = 1,
        ["bg_alpha"] = 0, --
        ["ignore_mass_showhide"] = false,
        ["hide_in_combat_alpha"] = 0,
        ["menu_icons"] = {
            true, -- [1]
            true, -- [2]
            true, -- [3]
            true, -- [4]
            true, -- [5]
            false, -- [6]
            ["space"] = 0,
            ["shadow"] = false
        },
        ["auto_hide_menu"] = {["left"] = false, ["right"] = false},
        ["statusbar_info"] = {
            ["alpha"] = 0,
            ["overlay"] = {
                0.333333333333333, -- [1]
                0.333333333333333, -- [2]
                0.333333333333333 -- [3]
            }
        },
        ["window_scale"] = 1,
        ["libwindow"] = {["y"] = 90.9987335205078, ["x"] = -80.0020751953125, ["point"] = "BOTTOMRIGHT"},
        ["backdrop_texture"] = "Details Ground",
        ["hide_icon"] = true,
        ["bg_b"] = 0.0941176470588235,
        -- duplicate toolbar_side key below removed
        ["bg_g"] = 0.0941176470588235,
        ["desaturated_menu"] = false,
        ["wallpaper"] = {
            ["enabled"] = false,
            ["texcoord"] = {
                0, -- [1]
                1, -- [2]
                0, -- [3]
                0.7 -- [4]
            },
            ["overlay"] = {
                1, -- [1]
                1, -- [2]
                1, -- [3]
                1 -- [4]
            },
            ["anchor"] = "all",
            ["height"] = 300,
            ["alpha"] = 0.5,
            ["width"] = 285
        },
        ["stretch_button_side"] = 1,
        ["bars_sort_direction"] = 1
    }
}

if _detalhes then _detalhes.skins["RefineUI"] = skinTable end

local lower_instance = _detalhes and _detalhes.GetLowerInstanceNumber and _detalhes:GetLowerInstanceNumber()
if lower_instance then
	for i = lower_instance, #_detalhes.tabela_instancias do
		local instance = Details and Details.GetInstance and Details:GetInstance(i)
		if instance and instance.rows_fit_in_window then
			-- for j = 1, instance.rows_fit_in_window do
			-- 	local bar = _G["DetailsBarra_Statusbar_"..i.."_"..j]
			-- 	local icon = _G["DetailsBarra_IconFrame_"..i.."_"..j]
			-- 	if bar and not bar.backdrop then
			-- 		bar:CreateBackdrop("Transparent")
			-- 		bar.backdrop:SetPoint("TOPLEFT", icon, -3, 3)

			-- 		bar.bg = bar:CreateTexture(nil, "BORDER")
			-- 		bar.bg:SetAllPoints(bar)
			-- 		bar.bg:SetTexture(C.media.texture)
			-- 		bar.bg:SetVertexColor(.6, .6, .6, 0.25)
			-- 	end
			-- end

			-- local frame = _G["DetailsUpFrameInstance"..i]
			-- frame.b = CreateFrame("Frame", nil, frame:GetParent())
			-- frame.b:SetTemplate("Overlay")
			-- frame.b:SetPoint("TOPLEFT", frame, "TOPLEFT", -24, 15)
			-- frame.b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 35, 6)
			-- frame.b:SetFrameLevel(frame:GetFrameLevel() - 1)

			instance:ChangeSkin("RefineUI")
		end
	end
end

if Details then
hooksecurefunc(Details, "ApplyProfile", function()
    C_Timer.After(1, UpdateDetailsPosition)
end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, UpdateDetailsPosition)
    end
end)