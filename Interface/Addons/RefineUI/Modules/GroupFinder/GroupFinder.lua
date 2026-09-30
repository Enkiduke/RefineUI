----------------------------------------------------------------------------------------
-- GroupFinder for RefineUI
-- Description: Premade Group Finder leader rating and crown, raid member tooltips,
--              Quick Apply, and Auto Accept.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:RegisterModule("GroupFinder", "GroupFinder")

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local _G = _G
local C_LFGList = C_LFGList
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local tContains = tContains
local type, pairs, ipairs = type, pairs, ipairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local INVITE_KEY = "GroupFinder:AcceptInvite"
local APPLICATION_EVENT_KEY = "GroupFinder:LFG_LIST_APPLICATION_STATUS_UPDATED"

-- Dungeons and raids; Quick Apply and Auto Accept cover only these.
local CATEGORIES = { [2] = true, [3] = true }

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
-- Application IDs signed up for this session; Auto Accept only answers these.
local applied = {}

-- Advanced and language filters used by the last search.
local searchedFilter, searchedLanguages

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

-- LFG text and player information are secret during chat messaging lockdown.
local function Read(value, expected)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    if type(value) == expected then
        return value
    end
end
GroupFinder.Read = Read

local function HasActivity(info, predicate)
    local ids = Read(info, "table") and Read(info.activityIDs, "table")
    if not ids then
        return false
    end
    for _, id in ipairs(ids) do
        id = Read(id, "number")
        local activity = id and C_LFGList.GetActivityInfoTable(id)
        if activity and predicate(activity) then
            return true
        end
    end
    return false
end

local function IsMythicPlus(activity)
    return activity.categoryID == 2 and Read(activity.isMythicPlusActivity, "boolean")
end

local function IsSupported(activity)
    return CATEGORIES[activity.categoryID]
end

function GroupFinder:IsMythicPlusResult(info)
    return HasActivity(info, IsMythicPlus)
end

function GroupFinder:IsSupportedResult(info)
    return HasActivity(info, IsSupported)
end

----------------------------------------------------------------------------------------
-- Filter Refresh
----------------------------------------------------------------------------------------
-- Blizzard's Filter menu saves filter changes but only searches again on reset. When a
-- pick or closing the menu leaves the filters different from the last search, search
-- again. Both run from a click or key press, which C_LFGList.Search requires. Blizzard's
-- list refreshes from its own search events; no Blizzard state is written.

-- Shallow compare. Blizzard rebuilds the activities list from a set, so lists compare
-- as sets; unchecked languages may be false or missing.
local function SameFilters(a, b)
    for key, value in pairs(a) do
        if type(value) == "table" then
            local other = b[key]
            if #value ~= #other then
                return false
            end
            for _, id in ipairs(value) do
                if not tContains(other, id) then
                    return false
                end
            end
        elseif (b[key] or false) ~= value then
            return false
        end
    end
    for key, value in pairs(b) do
        if value and a[key] == nil then
            return false
        end
    end
    return true
end

-- Mirrors LFGListSearchPanel_DoSearch, including its ResolveCategoryFilters step.
local function Search(panel, filter, languages)
    local filters = panel.filters or 0
    if panel.categoryID == GROUP_FINDER_CATEGORY_ID_DUNGEONS then
        local flags = Enum.LFGListFilter
        filters = bit.band(bit.bnot(flags.NotRecommended), bit.bor(filters, flags.Recommended))
    end
    if _G.LFGListFrame.CategorySelection.selectedCategory ~= GROUP_FINDER_CATEGORY_ID_DUNGEONS then
        filter = nil
    end
    C_LFGList.Search(panel.categoryID, filters, panel.preferredFilters or 0, languages, nil, filter)
end

function GroupFinder:SnapshotFilters()
    searchedFilter, searchedLanguages = C_LFGList.GetAdvancedFilter(), C_LFGList.GetLanguageSearchFilter()
end

function GroupFinder:RefreshIfFiltersChanged()
    local panel = _G.LFGListFrame.SearchPanel
    if not panel:IsShown() or not panel.categoryID then
        return
    end
    local filter, languages = C_LFGList.GetAdvancedFilter(), C_LFGList.GetLanguageSearchFilter()
    if searchedFilter and SameFilters(filter, searchedFilter) and SameFilters(languages, searchedLanguages) then
        return
    end
    searchedFilter, searchedLanguages = filter, languages
    Search(panel, filter, languages)
end

----------------------------------------------------------------------------------------
-- Quick Apply & Auto Accept
----------------------------------------------------------------------------------------

-- Runs after Blizzard's Sign Up opened the application dialog. Submits it with the
-- selected roles; holding Shift keeps the dialog to review roles or add a note.
function GroupFinder:QuickSignUp(panel)
    if not self.db.QuickApply or IsShiftKeyDown() or InCombatLockdown() or not CATEGORIES[panel.categoryID] then
        return
    end

    local dialog = _G.LFGListApplicationDialog
    if not dialog:IsShown() or dialog.resultID ~= panel.selectedResult or not dialog.SignUpButton:IsEnabled() then
        return
    end

    local _, status, pending = C_LFGList.GetApplicationInfo(dialog.resultID)
    if status == "none" and not pending then
        LFGListApplicationDialogSignUpButton_OnClick(dialog.SignUpButton)
    end
end

function GroupFinder:TrackApplication(id, status)
    if status == "applied" then
        applied[id] = true
    elseif status ~= "invited" then
        applied[id] = nil
    end
end

-- Matches the invite by application ID, never by leader name, and leaves unrelated
-- party invitations to Blizzard's dialog.
function GroupFinder:AcceptApplicationInvite(dialog, id)
    if not self.db.AutoAccept or IsShiftKeyDown() or not applied[id] then
        return
    end

    RefineUI:RunAfterCombat(INVITE_KEY, function()
        local _, status, pending = C_LFGList.GetApplicationInfo(id)
        if status ~= "invited" or pending or not LFGListUtil_IsAppEmpowered() then
            return
        end
        if not dialog:IsShown() or dialog.resultID ~= id or dialog.informational then
            return
        end
        if not self:IsSupportedResult(C_LFGList.GetSearchResultInfo(id)) then
            return
        end

        applied[id] = nil -- Consume before accepting can synchronously show another invite.
        LFGListInviteDialog_Accept(dialog)
    end)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------

function GroupFinder:OnInitialize()
    self.db = Config.GroupFinder
end

function GroupFinder:OnEnable()
    local searchPanel = _G.LFGListFrame.SearchPanel
    self:CreateSettingsButton(searchPanel)
    self:CreateResultCount(searchPanel)

    -- Every Blizzard search (Refresh, category change, filter reset) sets the baseline.
    hooksecurefunc("LFGListSearchPanel_DoSearch", function()
        self:SnapshotFilters()
    end)
    -- Menu picks, including submenus, report here. Typed ratings are caught on close.
    hooksecurefunc(searchPanel.FilterButton, "OnMenuResponse", function()
        self:RefreshIfFiltersChanged()
    end)
    hooksecurefunc(searchPanel.FilterButton, "OnMenuClosed", function()
        self:RefreshIfFiltersChanged()
    end)

    hooksecurefunc("LFGListSearchEntry_Update", function(entry)
        if entry.resultID and C_LFGList.HasSearchResultInfo(entry.resultID) then
            local info = C_LFGList.GetSearchResultInfo(entry.resultID)
            self:UpdateRating(entry, info)
            self:UpdateRealm(entry, info)
        end
    end)
    hooksecurefunc("LFGListSearchPanel_UpdateResults", function(panel)
        self:UpdateResultCount(panel)
    end)
    hooksecurefunc("LFGListSearchPanel_SignUp", function(panel)
        self:QuickSignUp(panel)
    end)
    hooksecurefunc("LFGListInviteDialog_Show", function(dialog, id)
        self:AcceptApplicationInvite(dialog, id)
    end)
    hooksecurefunc("LFGListGroupDataDisplayEnumerate_Update", function(...)
        self:UpdateLeaderCrown(...)
    end)
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
        self:AddRaidMembers(tooltip, resultID)
    end)

    RefineUI:RegisterEventCallback("LFG_LIST_APPLICATION_STATUS_UPDATED", function(_, id, status)
        self:TrackApplication(id, status)
    end, APPLICATION_EVENT_KEY)

    -- Restore live applications after a reload, never already pending invitations.
    for _, id in ipairs(C_LFGList.GetApplications()) do
        local _, status = C_LFGList.GetApplicationInfo(id)
        self:TrackApplication(id, status)
    end
end
