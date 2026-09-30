----------------------------------------------------------------------------------------
-- GroupFinder Component: UI
-- Description: Settings button and result count on the Group Finder search panel.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:GetModule("GroupFinder")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local _G = _G
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local MenuUtil = MenuUtil
local ipairs = ipairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local OPTIONS = {
    { "QuickApply", "Quick Apply", "Sign Up submits immediately using your selected LFG roles. Hold Shift when clicking Sign Up to review roles or add a note." },
    { "AutoAccept", "Auto Accept", "Automatically accept dungeon/raid LFG invitations for applications made this session. Hold Shift to review. Unrelated party invitations remain manual." },
    false,
    { "LeaderIcon", "Leader Crown", "Mark the group leader's icon with a crown." },
    { "RealmLocation", "Realm Location", "Show where the leader's realm is: datacenter in the Americas (NA, OCE, BR, LA) or language in Europe (EN, DE, FR, ES, RU, IT, PT)." },
    { "RaidTooltipMembers", "Raid Tooltip Members", "List raid members by role and class in raid listing tooltips." },
}

----------------------------------------------------------------------------------------
-- Result Count
----------------------------------------------------------------------------------------

-- Above Blizzard's Filter button; counts the listed results, not pending applications.
function GroupFinder:CreateResultCount(searchPanel)
    local count = searchPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    RefineUI.Point(count, "BOTTOMRIGHT", searchPanel.FilterButton, "TOPRIGHT", 0, 4)
    self.resultCount = count
end

function GroupFinder:UpdateResultCount(searchPanel)
    local results = not searchPanel.searching and searchPanel.results
    if results then
        self.resultCount:SetFormattedText("%d |4group:groups;", #results)
    else
        self.resultCount:SetText("")
    end
end

----------------------------------------------------------------------------------------
-- Settings Button
----------------------------------------------------------------------------------------

function GroupFinder:BuildSettingsMenu(root)
    local db = self.db
    root:CreateTitle("Group Finder Settings")
    for _, option in ipairs(OPTIONS) do
        if option then
            local key, label, help = option[1], option[2], option[3]
            local checkbox = root:CreateCheckbox(label, function()
                return db[key]
            end, function()
                db[key] = not db[key]
                RefineUI:Print(label .. ": " .. (db[key] and "Enabled" or "Disabled"))
            end)
            checkbox:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, label)
                GameTooltip_AddNormalLine(tooltip, help)
            end)
        else
            root:CreateDivider()
        end
    end
end

-- Sits in PVEFrame's title bar left of its close button, at the close button's level so
-- the window border art does not cover it. Parented to the search panel so it only
-- shows there.
function GroupFinder:CreateSettingsButton(searchPanel)
    local closeButton = _G.PVEFrame.CloseButton
    local button = RefineUI.CreateSettingsButton(searchPanel, nil, 16)
    RefineUI.Point(button, "RIGHT", closeButton, "LEFT", -2, 0)
    button:SetFrameLevel(closeButton:GetFrameLevel())

    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Group Finder Settings")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnMouseDown", function(owner)
        if InCombatLockdown() then
            return
        end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            self:BuildSettingsMenu(root)
        end)
    end)
end
