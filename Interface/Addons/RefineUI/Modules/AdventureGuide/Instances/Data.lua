-- UI adapters over the addon-wide achievement catalog.
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")
local Data = RefineUI.InstanceAchievements
for name, method in pairs(Data) do
    if type(method) == "function" then
        Module[name] = function(_, ...) return method(Data, ...) end
    end
end
function Module:InitializeData()
    self:CancelPendingInstanceRowBuilds()
    self:InvalidateCompletionData()
    self._filteredSourceRows, self._filteredBossToken, self._filteredRows = nil, nil, nil
end
function Module:RequestInstanceAchievementRows(instanceID, isRaid, callback)
    -- The Guide page and its Achievements tab are visible, so build ahead of card work.
    return Data:RequestInstanceAchievementRows(instanceID, isRaid, callback, self, true)
end
function Module:CancelPendingInstanceRowBuilds()
    Data:ReleaseOwner(self)
end
