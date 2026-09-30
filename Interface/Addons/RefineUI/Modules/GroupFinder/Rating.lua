----------------------------------------------------------------------------------------
-- GroupFinder Component: Rating
-- Description: Leader Mythic+ rating on Mythic+ search entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:GetModule("GroupFinder")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local C_ChallengeMode = C_ChallengeMode
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local floor = math.floor

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local ratings = RefineUI:CreateDataRegistry("GroupFinder:Ratings", "k")

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

-- The entry's third line holds Playstyle in a 176-unit column. Reserve fixed space there
-- without measuring restricted text or touching the group name, status, or members.
function GroupFinder:UpdateRating(entry, info)
    local state = ratings[entry]
    if state then
        state.label:SetText("")
        if state.reserved then
            entry.Playstyle:SetWidth(0)
            state.reserved = nil
        end
    end

    if not self:IsMythicPlusResult(info) then
        return
    end
    local score = self.Read(info.leaderOverallDungeonScore, "number")
    if not score then
        return
    end

    if not state then
        local label = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        RefineUI.Point(label, "TOPLEFT", entry, "TOPLEFT", 118, -36)
        RefineUI.Size(label, 64, 14)
        label:SetJustifyH("RIGHT")
        state = { label = label }
        ratings[entry] = state
    end

    entry.Playstyle:SetWidth(RefineUI:Scale(100))
    state.reserved = true
    local color = C_ChallengeMode.GetDungeonScoreRarityColor(score) or HIGHLIGHT_FONT_COLOR
    state.label:SetTextColor(color:GetRGB())
    state.label:SetFormattedText("%d", floor(score))
end
