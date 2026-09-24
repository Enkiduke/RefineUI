----------------------------------------------------------------------------------------
-- Auto Accept for RefineUI
-- Description: Handles quest auto accept and auto complete events
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoAccept = RefineUI:RegisterModule("AutoAccept", function(cfg)
    local quests = cfg.Quests
    if type(quests) ~= "table" or quests.Enable == false then
        return false
    end
    return quests.AutoAccept == true or quests.AutoComplete == true
end)

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
--	Auto Accept Quest
----------------------------------------------------------------------------------------
local function AutoAcceptQuest()
    if QuestFrame:IsShown() then
        if QuestFrameAcceptButton:IsVisible() then
            QuestFrameAcceptButton:Click()
        end
    end
end

----------------------------------------------------------------------------------------
--	Auto Complete Quest
----------------------------------------------------------------------------------------
local function AutoCompleteQuest()
    if QuestFrame:IsShown() and QuestFrameCompleteButton:IsVisible() then
        QuestFrameCompleteButton:Click()
    elseif QuestFrameRewardPanel:IsShown() then
        QuestFrameCompleteQuestButton:Click()
    end
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoAccept:OnInitialize()
    if not Config.Quests.Enable then
        return
    end

    RefineUI:RegisterEventCallback("QUEST_DETAIL", function()
        if Config.Quests.AutoAccept then
            AutoAcceptQuest()
        end
    end, "AutoAccept:Detail")

    RefineUI:RegisterEventCallback("QUEST_COMPLETE", function()
        if Config.Quests.AutoComplete then
            AutoCompleteQuest()
        end
    end, "AutoAccept:Complete")
end
