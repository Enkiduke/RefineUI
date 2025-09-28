local R, C, L = unpack(RefineUI)

-- Cache frequently used global functions
local _G = _G
local format = string.format
local wipe = wipe
local ipairs = ipairs
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitName = UnitName
local UnitClass = UnitClass
local UnitGUID = UnitGUID
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetRealmName = GetRealmName
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

-- Configuration
local chats = {
	CHAT_MSG_SAY = true,
	CHAT_MSG_YELL = true,
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_WHISPER_INFORM = true,
	CHAT_MSG_PARTY = true,
	CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_RAID = true,
	CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_RAID_WARNING = true,
}

local role_tex = {
	TANK = [[Interface\AddOns\RefineUI\Media\Textures\TANK.tga]],
	HEALER = [[Interface\AddOns\RefineUI\Media\Textures\HEALER.tga]],
	DAMAGER = [[Interface\AddOns\RefineUI\Media\Textures\DAMAGER.tga]],
}

-- Caching
local groupCache = {}

-- Functions
local function UpdateGroupCache()
	wipe(groupCache)
	if not IsInGroup() then return end

	for i = 1, GetNumGroupMembers() do
		local name, _, _, _, _, className, _, _, fullName = GetRaidRosterInfo(i)
		if fullName and className then
			groupCache[fullName] = className
			if name ~= fullName and not groupCache[name] then
				groupCache[name] = className
			end
		elseif name and className then
			groupCache[name] = className
		end
	end
end

local function GetPlayerClass(fullName)
	-- Prioritize group cache for efficiency
	if groupCache[fullName] then
		return groupCache[fullName]
	end

	local name = fullName:match("([^-]+)")
	local class

	-- Check if it's the player themselves
	if name == UnitName("player") then
		_, class = UnitClass("player")
	else
		-- else: If not in groupCache and not the player, we cannot reliably determine the class from just the name.
		-- The calling function will handle the nil return.
	end

	return class
end

local function CreateRoleIconString(role, classColor)
	if not role or role == "NONE" or not role_tex[role] then
		return ""
	end

	local texturePath = role_tex[role]
	return format("|T%s:16:16:0:0:16:16:0:16:0:16:%d:%d:%d|t",
		texturePath,
		classColor.r * 255,
		classColor.g * 255,
		classColor.b * 255
	)
end

-- Hooking GetColoredName
local GetColoredName_orig = _G.GetColoredName
local function GetColoredName_hook(event, _, arg2, ...)
	-- Get the base colored name from Blizzard
	local coloredName = GetColoredName_orig(event, _, arg2, ...)
	
	-- Early return for empty or invalid input
	if not arg2 or arg2 == "" then
		return coloredName
	end

	local finalName -- Variable to hold the final constructed name

	-- Determine full name for class lookup (use Name-Realm for cross-realm)
	local nameOnly, realm = arg2:match("([^-]+)-?(.*)")
	nameOnly = nameOnly or arg2
	realm = realm or ""
	local fullName = (realm ~= "" and realm ~= GetRealmName()) and arg2 or nameOnly

	local hasColor = coloredName and coloredName:find("|cff") -- Check if Blizzard provided color

	if not hasColor then
		-- Blizzard didn't provide color, add it manually
		local class = GetPlayerClass(fullName)
		local classColor = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
		local colorCode = format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
		
		if realm ~= "" then
			finalName = colorCode .. nameOnly .. "|r-" .. realm .. "|r" -- Ensure termination
		else
			finalName = colorCode .. arg2 .. "|r" -- Ensure termination
		end
	else
		-- Blizzard provided color, use it as is
		finalName = coloredName
		-- Ensure Blizzard's output ends with |r just in case
		if not finalName:find("|r$") then
			 finalName = finalName .. "|r"
		end
	end

	-- Prepend role icon if needed for specific chat types
	if chats[event] then
		local role = UnitGroupRolesAssigned(nameOnly) or UnitGroupRolesAssigned(fullName)
		if role and role ~= "NONE" then
			local class = GetPlayerClass(fullName)
			local classColor = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
			local roleIcon = CreateRoleIconString(role, classColor)
			-- Prepend icon; remove potential leading space AFTER icon is added
			finalName = roleIcon .. finalName
		end
	end

	-- No longer aggressively stripping/adding |r globally
	return finalName
end
-- Assign globally without injecting into _G to satisfy linters
GetColoredName = GetColoredName_hook

-- Event Handling
local UIRoleIcons = CreateFrame("Frame")
UIRoleIcons:RegisterEvent("PLAYER_ENTERING_WORLD")
UIRoleIcons:RegisterEvent("GROUP_ROSTER_UPDATE")
UIRoleIcons:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		UpdateGroupCache()
	elseif event == "GROUP_ROSTER_UPDATE" then
		UpdateGroupCache()
	end
end) 