local _, RefineUI = ...
local Module = RefineUI:RegisterModule("AdventureGuidePlanner")

function Module:BuildKey(...)
    local key = "AdventureGuidePlanner"
    for index = 1, select("#", ...) do key = key .. ":" .. tostring(select(index, ...)) end
    return key
end

function Module:OnEnable()
    self:RegisterWeeklyHubEvents()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
        if RefineUI:IsSecretValue(addonName) then return end
        if addonName == "Blizzard_EncounterJournal" then self:InstallWeeklyHub() end
    end, self:BuildKey("Runtime", "ADDON_LOADED"))
    if type(EncounterJournal) == "table" then self:InstallWeeklyHub() end
end
