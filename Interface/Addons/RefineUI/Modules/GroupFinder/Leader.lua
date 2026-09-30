----------------------------------------------------------------------------------------
-- GroupFinder Component: Leader
-- Description: Crown over the group leader's icon on enumerated search entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:GetModule("GroupFinder")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local C_ChatInfo = C_ChatInfo
local C_LFGList = C_LFGList
local CreateFrame = CreateFrame
local ipairs, pairs = ipairs, pairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LEADER_ATLAS = "groupfinder-icon-leader"
local LEADER_WIDTH = 14
local LEADER_HEIGHT = 9

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local crowns = RefineUI:CreateDataRegistry("GroupFinder:LeaderCrowns", "k")

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

-- Walks icons in the same right-to-left order as LFGListGroupDataDisplayEnumerate_Update,
-- over the same displayData table. Members sharing role and class have identical icons,
-- so the crown marks the first of them.
local function FindLeaderIcon(enumerate, numPlayers, displayData, iconOrder, showClassesByRole, role, class)
    local iconIndex = numPlayers
    for _, key in ipairs(iconOrder) do
        if showClassesByRole then
            for memberClass, count in pairs(displayData.classesByRole[key]) do
                if key == role and memberClass == class then
                    return enumerate.Icons[iconIndex]
                end
                iconIndex = iconIndex - count
            end
        else
            if key == role or key == class then
                return enumerate.Icons[iconIndex]
            end
            iconIndex = iconIndex - displayData[key]
        end
        if iconIndex < 1 then
            return
        end
    end
end

local function GetCrown(enumerate)
    local crown = crowns[enumerate]
    if not crown then
        crown = CreateFrame("Frame", nil, enumerate)
        crown:EnableMouse(false)
        RefineUI.Size(crown, LEADER_WIDTH, LEADER_HEIGHT)
        local texture = crown:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetAtlas(LEADER_ATLAS)
        crowns[enumerate] = crown
    end
    return crown
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function GroupFinder:UpdateLeaderCrown(enumerate, numPlayers, displayData, _, iconOrder, showClassesByRole)
    local crown = crowns[enumerate]
    if crown then
        crown:Hide()
    end

    -- The group data display is also used outside search entries; those have no resultID.
    local id = enumerate:GetParent():GetParent().resultID
    if not self.db.LeaderIcon or not id or C_ChatInfo.InChatMessagingLockdown() then
        return
    end

    local leader = C_LFGList.GetSearchResultLeaderInfo(id)
    local icon = leader and FindLeaderIcon(enumerate, numPlayers, displayData, iconOrder, showClassesByRole,
        leader.assignedRole, leader.classFilename)
    if not icon then
        return
    end

    crown = GetCrown(enumerate)
    crown:ClearAllPoints()
    RefineUI.Point(crown, "BOTTOM", icon, "TOP", 0, 0)
    crown:SetFrameLevel(icon:GetFrameLevel() + 5)
    crown:Show()
end
