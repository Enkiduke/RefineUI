local R, C, L = unpack(RefineUI)

-- Early, taint-safe suppression of Blizzard's compact party/raid frames
-- Strategy:
-- - Set CVars to prevent showing party/raid frames
-- - Reparent and unregister events on key containers if they exist
-- - Avoid hooksecurefunc on CompactRaidFrameManager_UpdateShown
-- - Respect Edit Mode and avoid combat lockdown changes

local f = CreateFrame("Frame")
local pendingDisable

local function disableCompactFrames()
    -- CVars to reduce Blizzard frames from appearing
    if not InCombatLockdown() then
        pcall(SetCVar, "useCompactPartyFrames", 0)
        pcall(SetCVar, "raidFramesDisplayIncomingHeals", 0)
        pcall(SetCVar, "raidFramesDisplayPowerBars", 0)
        pcall(SetCVar, "raidFramesDisplayOnlyDispellableDebuffs", 0)
        pcall(SetCVar, "raidFramesDisplayClassColor", 1)
        pcall(SetCVar, "displayPartyBackground", 0)
    end

    -- Hide party/raid related frames if they exist
    local hider = R.Hider or UIParent

    local function handle(frame)
        if not frame then return end
        if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
        frame:Hide()
        if frame.SetParent then frame:SetParent(hider) end
    end

    -- Party frame container (Retail uses PartyFrame)
    local PartyFrame = rawget(_G, "PartyFrame")
    handle(PartyFrame)
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            handle(member)
        end
    end

    -- Compact raid manager and container
    handle(rawget(_G, "CompactRaidFrameManager"))
    handle(rawget(_G, "CompactRaidFrameContainer"))

    -- Compact party members (used by some modes)
    for i = 1, (rawget(_G, "MEMBERS_PER_RAID_GROUP") or 5) do
        handle(_G["CompactPartyFrameMember" .. i])
    end

    -- Arena compact frames
    local CompactArenaFrame = rawget(_G, "CompactArenaFrame")
    handle(CompactArenaFrame)
    if CompactArenaFrame and CompactArenaFrame.memberUnitFrames then
        for _, member in next, CompactArenaFrame.memberUnitFrames do
            handle(member)
        end
    end
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_LOGIN" then
        disableCompactFrames()
        -- Also run after Edit Mode applies layouts on login
        C_Timer.After(0, disableCompactFrames)
    elseif event == "ADDON_LOADED" then
        if addon == "Blizzard_CompactRaidFrames" then
            -- If Blizzard loads the module later, suppress again
            C_Timer.After(0, disableCompactFrames)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if InCombatLockdown() then
            pendingDisable = true
        else
            disableCompactFrames()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingDisable then
            pendingDisable = nil
            disableCompactFrames()
        end
    end
end)
