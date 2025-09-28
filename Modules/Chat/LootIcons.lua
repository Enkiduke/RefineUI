local R, C, L = unpack(RefineUI)

-- Fast sentinels / locals
local HAS_ITEM = "|Hitem:"
local gsub = string.gsub
local match = string.match
local format = string.format

-- Cache frequently used global functions
local ipairs = ipairs
local C_Item = C_Item
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter

-- Config gate
if not (C.chat and C.chat.lootIcons) then return end

-- Size gate (0 disables without removing feature flag)
local ICON_SIZE = C.chat.lootIconSize or 16
if ICON_SIZE <= 0 then return end

-- Tiny per-session cache for itemID -> texture path
local itemIconCache = setmetatable({}, { __mode = "kv" })

local function AddLootIcons(self, event, msg, ...)
    -- Fast path: if there's no item link, do nothing
    if not msg or not msg:find(HAS_ITEM, 1, true) then return end

    -- Replace item links with icon + link (same output as before)
    msg = gsub(msg, "(\124c%x+\124Hitem:[%d:]+\124h.-\124h\124r)", function(link)
        local itemID = match(link, "item:(%d+)")
        if not itemID then return link end
        local icon = itemIconCache[itemID]
        if icon == nil then
            icon = C_Item.GetItemIconByID(itemID)
            itemIconCache[itemID] = icon or false
        end
        if not icon then return link end
        return format("\124T%s:%d:%d:0:0:64:64:5:59:5:59\124t%s", icon, ICON_SIZE, ICON_SIZE, link)
    end)
    return false, msg, ...
end

	-- Add the filter to multiple chat message types
	local chatEvents = {
		"CHAT_MSG_LOOT",
		"CHAT_MSG_CHANNEL",
		"CHAT_MSG_SAY",
		"CHAT_MSG_YELL",
		"CHAT_MSG_WHISPER",
		"CHAT_MSG_WHISPER_INFORM",
		"CHAT_MSG_PARTY",
		"CHAT_MSG_PARTY_LEADER",
		"CHAT_MSG_RAID",
		"CHAT_MSG_RAID_LEADER",
		"CHAT_MSG_INSTANCE_CHAT",
		"CHAT_MSG_INSTANCE_CHAT_LEADER",
		"CHAT_MSG_GUILD",
		"CHAT_MSG_OFFICER",
		"CHAT_MSG_EMOTE",
		"CHAT_MSG_AFK",
		"CHAT_MSG_DND",
	}

    for _, event in ipairs(chatEvents) do
        ChatFrame_AddMessageEventFilter(event, AddLootIcons)
    end