----------------------------------------------------------------------------------------
-- GroupFinder Component: Tooltip
-- Description: Member list on raid search tooltips, which Blizzard shows only as counts.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:GetModule("GroupFinder")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local C_ChatInfo = C_ChatInfo
local C_LFGList = C_LFGList
local CreateAtlasMarkup = CreateAtlasMarkup
local LFG_LIST_GROUP_DATA_ATLASES_BORDERLESS = LFG_LIST_GROUP_DATA_ATLASES_BORDERLESS
local LFG_LIST_TOOLTIP_CLASS_ROLE = LFG_LIST_TOOLTIP_CLASS_ROLE
local MEMBERS_COLON = MEMBERS_COLON
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local ipairs = ipairs
local format = string.format
local sort = table.sort

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ROLE_PRIORITY = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local LEADER_MARKUP = CreateAtlasMarkup("groupfinder-icon-leader", 14, 9, 0, 0)
local LEAVER_MARKUP = CreateAtlasMarkup("groupfinder-icon-leaver", 12, 12, 0, 0)

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function SortGroups(a, b)
    local roleA, roleB = ROLE_PRIORITY[a.role] or 4, ROLE_PRIORITY[b.role] or 4
    if roleA ~= roleB then
        return roleA < roleB
    end
    if a.isLeader ~= b.isLeader then
        return a.isLeader
    end
    if a.class ~= b.class then
        return a.class < b.class
    end
    return a.specName < b.specName
end

-- Members sharing role, class, and spec collapse to one counted line.
local function CollectGroups(resultID, numMembers)
    local groups, byKey = {}, {}
    for index = 1, numMembers do
        local member = C_LFGList.GetSearchResultPlayerInfo(resultID, index)
        if member and member.assignedRole then
            local specName = member.specName or ""
            local key = member.assignedRole .. "\1" .. member.classFilename .. "\1" .. specName
            local group = byKey[key]
            if not group then
                group = {
                    role = member.assignedRole,
                    class = member.classFilename,
                    className = member.className,
                    specName = specName,
                    count = 0,
                    isLeader = false,
                    isLeaver = false,
                }
                byKey[key] = group
                groups[#groups + 1] = group
            end
            group.count = group.count + 1
            group.isLeader = group.isLeader or member.isLeader
            group.isLeaver = group.isLeaver or member.isLeaver
        end
    end
    sort(groups, SortGroups)
    return groups
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

-- Appends after Blizzard's lines instead of rebuilding the tooltip, so Blizzard's
-- colors and other addons' lines stay intact.
function GroupFinder:AddRaidMembers(tooltip, resultID)
    if not self.db.RaidTooltipMembers or C_ChatInfo.InChatMessagingLockdown() then
        return
    end

    local info = C_LFGList.GetSearchResultInfo(resultID)
    local activity = C_LFGList.GetActivityInfoTable(info.activityIDs[1], nil, info.isWarMode)
    if not activity or activity.displayType ~= Enum.LFGListDisplayType.RoleCount or info.numMembers == 0 then
        return
    end

    local groups = CollectGroups(resultID, info.numMembers)
    if #groups == 0 then
        return
    end

    local firstLine = tooltip:NumLines() + 1
    tooltip:AddLine(" ")
    tooltip:AddLine(MEMBERS_COLON)
    for _, group in ipairs(groups) do
        local color = RAID_CLASS_COLORS[group.class] or NORMAL_FONT_COLOR
        local text = group.specName ~= "" and format(LFG_LIST_TOOLTIP_CLASS_ROLE, group.className, group.specName) or group.className
        if group.count > 1 then
            text = format("%s (%d)", text, group.count)
        end
        if group.isLeader then
            text = text .. " " .. LEADER_MARKUP
        end
        if group.isLeaver then
            text = text .. " " .. LEAVER_MARKUP
        end
        local roleIcon = CreateAtlasMarkup(LFG_LIST_GROUP_DATA_ATLASES_BORDERLESS[group.role], 13, 13, 0, 0)
        tooltip:AddLine(roleIcon .. " " .. text, color.r, color.g, color.b)
    end

    -- RefineUI's tooltip styling runs on show; this tooltip is already shown.
    if RefineUI:IsModuleStartupEnabled("Tooltip") then
        for index = firstLine, tooltip:NumLines() do
            RefineUI.Font(tooltip:GetLeftLine(index), 12, nil, "OUTLINE")
        end
    end
    tooltip:Show()
end
