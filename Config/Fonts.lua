local R, C, L = unpack(RefineUI)

-- Helper function to create sections
local function CreateSection(name)
	C[name] = C[name] or {}
	return setmetatable({}, {
		__newindex = function(t, k, v)
			rawset(C[name], k, v)
		end
	})
end

----------------------------------------------------------------------------------------
--	RefineUI fonts configuration file
--	BACKUP THIS FILE BEFORE UPDATING!
----------------------------------------------------------------------------------------
local font = CreateSection("font")

font.normal = C.media.normalFont


-- General fonts
font.chat = { C.media.normalFont, 16, "OUTLINE" }
font.chatTabs = { C.media.normalFont, 16, "OUTLINE" }
font.actionBars = { C.media.normalFont, 12, "OUTLINE" }
font.threatMeter = { C.media.normalFont, 8, "OUTLINE" }
font.raid_cooldowns = { C.media.normalFont, 12, "OUTLINE" }
font.cooldownTimers = { C.media.boldFont, 20, "THICK, OUTLINE" }
font.loot = { C.media.normalFont, 14, "OUTLINE" }
font.minimap = { C.media.normalFont, 16, "THICKOUTLINE" }
font.stylization = { C.media.normalFont, 15, "OUTLINE" }
font.bags = { C.media.normalFont, 12, "OUTLINE" }
font.quest = { C.media.normalFont, 14, "OUTLINE" }
font.databar = { C.media.normalFont, 16, "OUTLINE" }
font.databar_small = { C.media.normalFont, 10, "OUTLINE" }
font.sct = { C.media.normalFont, 10, "OUTLINE" }

-- Nameplates fonts
font.nameplates = {
	default = { C.media.normalFont, 8, "OUTLINE" },
	name = { C.media.normalFont, 7, "OUTLINE" },
	title = { C.media.normalFont, 6, "OUTLINE" },
	health = { C.media.normalFont, 8, "OUTLINE" },
	spell = { C.media.normalFont, 6, "OUTLINE" },
	spelltime = { C.media.boldFont, 6, "OUTLINE" },
	quest = { C.media.normalFont, 6, "OUTLINE" },
	auras = { C.media.normalFont, 10, "OUTLINE" },
	aurasCount = { C.media.normalFont, 5, "OUTLINE" },
}

-- Unit frames fonts
font.unitframes = {
	default = { C.media.normalFont, 10, "OUTLINE" },
	health = { C.media.normalFont, 16, "OUTLINE" },
	name = { C.media.normalFont, 18, "OUTLINE" },
	spellname = { C.media.normalFont, 12, "OUTLINE" },
	spelltime = { C.media.boldFont, 14, "OUTLINE" },
}

-- Unit frames fonts
font.group = {
	name = { C.media.normalFont, 14, "OUTLINE" },
}

-- Auras fonts
font.auras = {
	default = { C.media.boldFont, 10, "OUTLINE" },
	player_duration = { C.media.boldFont, 18, "THICKOUTLINE" },
	player_count = { C.media.boldFont, 12, "OUTLINE" },
	player_debuffs_duration = { C.media.normalFont, 8, "OUTLINE" },
	small = { C.media.normalFont, 10, "OUTLINE" },
	smallTime = { C.media.normalFont, 10, "OUTLINE" },
	smallCount = { C.media.normalFont, 10, "OUTLINE" },
}

-- Nameplates fonts
font.actionbars = {
	hotkey = { C.media.normalFont, 12, "OUTLINE" },
	count = { C.media.normalFont, 8, "OUTLINE" },
}


-- Filger bar fonts
font.filger = {
	main = { C.media.normalFont, 8, "OUTLINE" },
	time = { C.media.normalFont, 20, "OUTLINE" },
	count = { C.media.normalFont, 12, "OUTLINE" },
}

-- BW Timeline fonts
font.bwt = {
	default = { C.media.normalFont, 12, "OUTLINE" },
	duration = { C.media.boldFont, 12, "OUTLINE" },
	tick = { C.media.normalFont, 10, "OUTLINE" },
}

-- Blizzard fonts
font.tooltip_header_size = 13
font.tooltip_size = 11
font.bubble_size = 10
font.quest_tracker_font_mult = 1