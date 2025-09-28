local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = (ns and ns.oUF) or rawget(_G, "oUF")
if not oUF then return end
local AuraUtil = AuraUtil

----------------------------------------------------------------------------------------
--	Radial Statusbar functions
----------------------------------------------------------------------------------------

local cos, sin, pi2, halfpi = math.cos, math.sin, math.rad(360), math.rad(90)

local function TransformTexture(tx, x, y, angle, aspect)
    local c, s = cos(angle), sin(angle)
    local y, oy = y / aspect, 0.5 / aspect
    local ULx, ULy = 0.5 + (x - 0.5) * c - (y - oy) * s, (oy + (y - oy) * c + (x - 0.5) * s) * aspect
    local LLx, LLy = 0.5 + (x - 0.5) * c - (y + oy) * s, (oy + (y + oy) * c + (x - 0.5) * s) * aspect
    local URx, URy = 0.5 + (x + 0.5) * c - (y - oy) * s, (oy + (y - oy) * c + (x + 0.5) * s) * aspect
    local LRx, LRy = 0.5 + (x + 0.5) * c - (y + oy) * s, (oy + (y + oy) * c + (x + 0.5) * s) * aspect
    tx:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end

-- Permanently pause our rotation animation after it starts playing
local function OnPlayUpdate(self)
    self:SetScript('OnUpdate', nil)
    self:Pause()
end

local function OnPlay(self)
    self:SetScript('OnUpdate', OnPlayUpdate)
end

local function SetRadialStatusBarValue(self, value)
    value = math.max(0, math.min(1, value))

    if self._reverse then
        value = 1 - value
    end

    local q = self._clockwise and (1 - value) or value
    local quadrant = q >= 0.75 and 1 or q >= 0.5 and 2 or q >= 0.25 and 3 or 4

    if self._quadrant ~= quadrant then
        self._quadrant = quadrant
        for i = 1, 4 do
            self._textures[i]:SetShown(self._clockwise and i < quadrant or not self._clockwise and i > quadrant)
        end
        self._scrollframe:SetAllPoints(self._textures[quadrant])
    end

    local rads = value * pi2
    if not self._clockwise then rads = -rads + halfpi end
    TransformTexture(self._wedge, -0.5, -0.5, rads, self._aspect)
    self._rotation:SetRadians(-rads)
end

local function OnSizeChanged(self, width, height)
    self._wedge:SetSize(width, height)
    self._aspect = width / height
end

-- Creates a function that calls a method on all textures at once
local function CreateTextureFunction(func)
    return function(self, ...)
        for i = 1, 4 do
            self._textures[i][func](self._textures[i], ...)
        end
        self._wedge[func](self._wedge, ...)
    end
end

-- Pass calls to these functions on our frame to its textures
local TextureFunctions = {
    SetTexture = CreateTextureFunction('SetTexture'),
    SetBlendMode = CreateTextureFunction('SetBlendMode'),
    SetVertexColor = CreateTextureFunction('SetVertexColor'),
}

local function CreateRadialStatusBar(parent)
    local bar = CreateFrame('Frame', nil, parent)

    local scrollframe = CreateFrame('ScrollFrame', nil, bar)
    scrollframe:SetPoint('BOTTOMLEFT', bar, 'CENTER')
    scrollframe:SetPoint('TOPRIGHT')
    bar._scrollframe = scrollframe

    local scrollchild = CreateFrame('frame', nil, scrollframe)
    scrollframe:SetScrollChild(scrollchild)
    scrollchild:SetAllPoints(scrollframe)

    local wedge = scrollchild:CreateTexture()
    wedge:SetPoint('BOTTOMRIGHT', bar, 'CENTER')
    bar._wedge = wedge

    -- Create quadrant textures
    local textures = {
        bar:CreateTexture(), -- Top Right
        bar:CreateTexture(), -- Bottom Right
        bar:CreateTexture(), -- Bottom Left
        bar:CreateTexture()  -- Top Left
    }

    textures[1]:SetPoint('BOTTOMLEFT', bar, 'CENTER')
    textures[1]:SetPoint('TOPRIGHT')
    textures[1]:SetTexCoord(0.5, 1, 0, 0.5)

    textures[2]:SetPoint('TOPLEFT', bar, 'CENTER')
    textures[2]:SetPoint('BOTTOMRIGHT')
    textures[2]:SetTexCoord(0.5, 1, 0.5, 1)

    textures[3]:SetPoint('TOPRIGHT', bar, 'CENTER')
    textures[3]:SetPoint('BOTTOMLEFT')
    textures[3]:SetTexCoord(0, 0.5, 0.5, 1)

    textures[4]:SetPoint('BOTTOMRIGHT', bar, 'CENTER')
    textures[4]:SetPoint('TOPLEFT')
    textures[4]:SetTexCoord(0, 0.5, 0, 0.5)

    bar._textures = textures
    bar._quadrant = nil
    bar._clockwise = true
    bar._reverse = false
    bar._aspect = 1
    bar:HookScript('OnSizeChanged', OnSizeChanged)

    for method, func in pairs(TextureFunctions) do
        bar[method] = func
    end

    bar.SetRadialStatusBarValue = SetRadialStatusBarValue

    local group = wedge:CreateAnimationGroup()
    local rotation = group:CreateAnimation('Rotation')
    bar._rotation = rotation
    rotation:SetDuration(0)
    rotation:SetEndDelay(1)
    rotation:SetOrigin('BOTTOMRIGHT', 0, 0)
    group:SetScript('OnPlay', OnPlay)
    group:Play()

    return bar
end

R.CreateRadialStatusBar = CreateRadialStatusBar

----------------------------------------------------------------------------------------
--	CombinedPortrait element
----------------------------------------------------------------------------------------

local CombinedPortrait = {
    indexByID = {},   --[questID] = questIndex
    activeQuests = {} --[questTitle] = questID
}

-- Cache quest scan results by GUID to avoid expensive tooltip:SetUnit() calls.
-- Keyed by unit GUID; cleared on quest log changes. TTL keeps data fresh if needed.
local QUEST_CACHE_TTL = 1 -- default seconds (short TTL to balance freshness and scan reduction)
-- Allow an override from the addon's config (if present)
if C and C.nameplate and tonumber(C.nameplate.questCacheTTL) then
    QUEST_CACHE_TTL = tonumber(C.nameplate.questCacheTTL)
end
local questCache = {} -- [guid] = { ts = GetTime(), quests = QuestList }
-- Runtime toggle / detection for API-only quest matching
local USE_API_QUESTS = true

local function IsAPIQuestSupportAvailable()
    return type(C_QuestLog) == 'table' and type(C_QuestLog.IsUnitOnQuest) == 'function' and
        type(C_QuestLog.GetNumQuestLogEntries) == 'function' and type(GetQuestObjectiveInfo) == 'function'
end
-- Default to using the API when available, but allow a config override
USE_API_QUESTS = IsAPIQuestSupportAvailable()
if C and C.nameplate and type(C.nameplate.use_api_quests) == 'boolean' then
    USE_API_QUESTS = C.nameplate.use_api_quests
end

-- Runtime API toggles exposed for testing/debugging. Call from other modules like:
-- RefineUI.Libs.oUF.Modules.DynamicPortrait.SetAPIOnly(false)
function CombinedPortrait.SetAPIOnly(flag)
    USE_API_QUESTS = not not flag
    if R and R.PortraitManager and R.PortraitManager._debug then
        print(('|CombinedPortrait: SetAPIOnly -> %s'):format(
            tostring(USE_API_QUESTS)))
    end
end

function CombinedPortrait.SetCacheTTL(seconds)
    local n = tonumber(seconds)
    if n and n > 0 then
        QUEST_CACHE_TTL = n
        if R and R.PortraitManager and R.PortraitManager._debug then
            print(('|CombinedPortrait: SetCacheTTL -> %fs')
                :format(QUEST_CACHE_TTL))
        end
    end
end

-- Candidate quests (built on quest log updates). Each entry: { questID, questLogIndex, objectives = { { index, type } }, itemTexture }
local questCandidates = {}

local function BuildQuestCandidates()
    wipe(questCandidates)
    if not C_QuestLog.GetNumQuestLogEntries then return end
    for questID, qIndex in pairs(CombinedPortrait.indexByID) do
        if questID and qIndex and qIndex > 0 then
            local _, texture = GetQuestLogSpecialItemInfo(qIndex)
            local num = GetNumQuestLeaderBoards(qIndex) or 0
            local objectives = {}
            for objIndex = 1, num do
                local objectiveText, objectiveType, finished = GetQuestObjectiveInfo(questID, objIndex, false)
                if objectiveText and not finished then
                    -- Keep objectives that are likely to map to units or show progress
                    if objectiveType == "monster" or objectiveType == "item" or objectiveType == "object" or strmatch(objectiveText, "%%") or strmatch(objectiveText, "(%d+)/(%d+)") then
                        objectives[#objectives + 1] = { index = objIndex, type = objectiveType }
                    end
                end
            end
            if #objectives > 0 then
                questCandidates[#questCandidates + 1] = {
                    questID = questID,
                    questLogIndex = qIndex,
                    objectives =
                        objectives,
                    itemTexture = texture
                }
            end
        end
    end
    if R and R.PortraitManager and R.PortraitManager._debug then
        print(('|CombinedPortrait: BuildQuestCandidates -> %d candidates'):format(#questCandidates))
    end
end

-- Forward-declare CheckTextForQuest so MatchUnitToCandidates can call it even
-- though the implementation appears later in this file.
local CheckTextForQuest

local function MatchUnitToCandidates(unit, guid)
    if not guid or not USE_API_QUESTS then return nil end
    -- Return cached results if fresh
    local cached = questCache[guid]
    if cached and (GetTime() - cached.ts) < QUEST_CACHE_TTL then
        if R and R.PortraitManager and R.PortraitManager._debug then
            print(('|CombinedPortrait: cache HIT guid=%s'):format(tostring(guid)))
        end
        return cached.quests
    end

    if #questCandidates == 0 then
        questCache[guid] = { ts = GetTime(), quests = nil }
        return nil
    end

    local QuestList
    for _, cand in ipairs(questCandidates) do
        local qid = cand.questID
        local isOn = false
        local okFn = C_QuestLog.IsUnitOnQuest
        if type(okFn) == 'function' then
            -- C_QuestLog.IsUnitOnQuest(unit, questID)
            isOn = okFn(unit, qid)
        end
        if isOn then
            -- For each candidate objective, query progress and map to QuestList
            for _, obj in ipairs(cand.objectives) do
                local objectiveText, objectiveType, finished = GetQuestObjectiveInfo(qid, obj.index, false)
                if objectiveText and not finished then
                    local progress, isComplete, isPercent = CheckTextForQuest(objectiveText)
                    if progress and not isComplete then
                        local questType
                        if objectiveType == "item" or objectiveType == "object" then
                            questType = "LOOT_ITEM"
                        elseif objectiveType == "monster" then
                            questType = "KILL"
                        end
                        local texture = cand.itemTexture
                        if texture then questType = "QUEST_ITEM" end
                        if not QuestList then QuestList = {} end
                        QuestList[#QuestList + 1] = {
                            isPercent = isPercent,
                            itemTexture = texture,
                            objectiveProgress = progress,
                            questType = questType or "DEFAULT",
                            questLogIndex = cand.questLogIndex,
                            questID = qid
                        }
                        -- keep collecting possible objectives for the same quest
                    end
                end
            end
        end
    end

    questCache[guid] = { ts = GetTime(), quests = QuestList }
    if R and R.PortraitManager and R.PortraitManager._debug then
        if QuestList then
            print(('|CombinedPortrait: MatchUnitToCandidates -> matched guid=%s count=%d'):format(tostring(guid),
                #QuestList))
        else
            print(('|CombinedPortrait: MatchUnitToCandidates -> no match guid=%s'):format(tostring(guid)))
        end
    end
    return QuestList
end

local ScanTooltip = CreateFrame("GameTooltip", "oUF_CombinedPortraitTooltip", UIParent, "GameTooltipTemplate")
local ThreatTooltip = THREAT_TOOLTIP:gsub("%%d", "%%d-")

-- CC helpers (use whitelist from Config/Filters/CCDebuffs.lua)
R.CCDebuffs = R.CCDebuffs or {}

local function IsWhitelistedCCAura(data)
    if not data or not data.isHarmful then return false end
    local sid = data.spellId
    if sid and R.CCDebuffs[sid] then return true end
    if not sid and R.CCDebuffsByName and data.name then
        return R.CCDebuffsByName[data.name] ~= nil
    end
    if not sid and data.name and R.CCDebuffsByName then
        return R.CCDebuffsByName[data.name] ~= nil
    end
    if sid and not R.CCDebuffs[sid] and R.CCDebuffsByName and data.name then
        return R.CCDebuffsByName[data.name] ~= nil
    end
    return false
end

local function FindActiveCC(unit)
    local best
    if not AuraUtil or not AuraUtil.ForEachAura then return nil end
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(data)
        if IsWhitelistedCCAura(data) then
            local remain = (data.expirationTime or 0) - GetTime()
            if remain and remain > 0 then
                if not best then
                    best = data
                else
                    local bestRemain = (best.expirationTime or 0) - GetTime()
                    if remain > bestRemain then
                        best = data
                    end
                end
            end
        end
        return false
    end, true)
    return best
end

CheckTextForQuest = function(text)
    local x, y = strmatch(text, "(%d+)/(%d+)")
    if x and y then
        return tonumber(x) / tonumber(y), x == y -- Return progress (0 to 1) and whether it's complete
    elseif not strmatch(text, ThreatTooltip) then
        local progress = tonumber(strmatch(text, "([%d%.]+)%%"))
        if progress and progress <= 100 then
            return progress / 100, progress == 100,
                true -- Return progress (0 to 1), whether it's complete, and isPercent
        end
    end
    return nil, false -- Return nil if no quest info found, and false for not complete
end

local function GetQuests(unitID)
    -- Avoid expensive tooltip scans when not needed. Use C_QuestLog.IsUnitOnQuest
    -- to quickly determine if any quest work is required for this unit.
    local guid = UnitGUID(unitID)
    if not guid then return end

    -- Cheap early-exit: if the player has no quests at all, skip scanning.
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() == 0 then
        return nil
    end

    -- Return cached results if recent
    local cached = questCache[guid]
    if cached and (GetTime() - cached.ts) < QUEST_CACHE_TTL then
        return cached.quests
    end

    -- Instance-type early-exit: avoid matching in arenas/pvp/raid
    local _, instanceType = IsInInstance()
    if instanceType == "arena" or instanceType == "pvp" or instanceType == "raid" then
        -- Cache a miss for this GUID so we don't re-check repeatedly in instances
        if guid then
            questCache[guid] = { ts = GetTime(), quests = nil }
        end
        return nil
    end

    -- Prefer the API-driven matcher when available to avoid tooltip:SetUnit scans.
    if USE_API_QUESTS then
        if R and R.PortraitManager and R.PortraitManager._debug then
            print(('|CombinedPortrait: Attempt API match for guid=%s')
                :format(tostring(guid)))
        end
        local apiResult = MatchUnitToCandidates(unitID, guid)
        if apiResult ~= nil then
            if R and R.PortraitManager and R.PortraitManager._debug then
                print(('|CombinedPortrait: API match result for guid=%s -> %s'):format(tostring(guid),
                    tostring(#(apiResult or {}))))
            end
            return apiResult
        end
        -- API returned nil (no match). Don't cache the miss here so the
        -- tooltip fallback can run and detect cases the API might miss.
        if R and R.PortraitManager and R.PortraitManager._debug then
            print(('|CombinedPortrait: API returned no match for guid=%s, falling back to tooltip'):format(tostring(guid)))
        end
    end

    -- If we reach here, do a single tooltip scan and cache the result.

    ScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    ScanTooltip:SetUnit(unitID)
    ScanTooltip:Show()

    local QuestList, activeID
    for i = 3, ScanTooltip:NumLines() do
        local str = _G["oUF_CombinedPortraitTooltipTextLeft" .. i]
        local text = str and str:GetText()
        if not text or text == "" then break end

        local progress, isComplete, isPercent = CheckTextForQuest(text)
        local activeQuest = CombinedPortrait.activeQuests[text]
        if activeQuest then activeID = activeQuest end

        if progress and not isComplete then
            local questType, index, texture, _
            if activeID then
                index = CombinedPortrait.indexByID[activeID]
                _, texture = GetQuestLogSpecialItemInfo(index)
                for i = 1, GetNumQuestLeaderBoards(index) or 0 do
                    local objectiveText, objectiveType, finished = GetQuestObjectiveInfo(activeID, i, false)
                    if objectiveText and not finished then
                        if objectiveType == "item" or objectiveType == "object" then
                            questType = "LOOT_ITEM"
                        elseif objectiveType == "monster" then
                            questType = "KILL"
                        end
                    end
                end
            end

            if texture then
                questType = "QUEST_ITEM"
            end

            if not QuestList then QuestList = {} end
            QuestList[#QuestList + 1] = {
                isPercent = isPercent,
                itemTexture = texture,
                objectiveProgress = progress,
                questType = questType or "DEFAULT",
                questLogIndex = index,
                questID = activeID
            }
        end
    end

    ScanTooltip:Hide()

    -- Cache scan results for the GUID
    questCache[guid] = { ts = GetTime(), quests = QuestList }
    return QuestList
end

-- Helper to set portrait border with optional debug printing
local function SetPortraitBorder(frame, r, g, b, tag)
    if not frame or not frame.PortraitBorder then return end
    if R and R.PortraitManager and R.PortraitManager._debug then
        local cr, cg, cb = frame.PortraitBorder:GetVertexColor()
        print(("|CombinedPortrait.Helper[%s]: before r=%.2f g=%.2f b=%.2f -> want r=%.2f g=%.2f b=%.2f"):format(
            tostring(tag or 'unk'), cr or 0, cg or 0, cb or 0, r or 0, g or 0, b or 0))
    end
    frame.PortraitBorder:SetVertexColor(r, g, b)
    if R and R.PortraitManager and R.PortraitManager._debug then
        local cr2, cg2, cb2 = frame.PortraitBorder:GetVertexColor()
        print(("|CombinedPortrait.Helper[%s]: after r=%.2f g=%.2f b=%.2f"):format(tostring(tag or 'unk'), cr2 or 0,
            cg2 or 0, cb2 or 0))
    end
end

local function Update(self, event, unit)
    if not unit or not self.unit or not UnitIsUnit(self.unit, unit) then return end

    local element = self.CombinedPortrait
    if not element then return end

    if element.PreUpdate then
        element:PreUpdate(unit)
    end

    local guid = UnitGUID(unit)
    local isAvailable = UnitIsConnected(unit) and UnitIsVisible(unit)

    -- Reset isQuestMob property
    self.isQuestMob = false

    -- Check for spell cast (highest priority)
    local castName, _, castTexture = UnitCastingInfo(unit)
    if not castName then
        castName, _, castTexture = UnitChannelInfo(unit)
    end

    if castName and castTexture then
        -- If casting while in CC state, prioritize casting (CC didn't work)
        if element.currentState == 'cc' and self.PortraitBorder then
            -- Clear CC state since casting takes priority
            element.currentState = 'cast'
        end
        element:SetTexture(castTexture)
        if element.Text then element.Text:SetText("") end
        element.currentState = 'cast'

        -- Set portrait border to cast color (highest priority) via PortraitManager
        if self.PortraitBorder then
            -- Get cast color from castbar system
            local castbar = self.Castbar
            local rr, rg, rb
            if castbar and castbar:IsShown() then
                rr, rg, rb = castbar:GetStatusBarColor()
            else
                -- Fallback cast color
                rr, rg, rb = 1, 0.8, 0
            end
            local applied = false
            if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                applied = R.PortraitManager.RequestColor(self, rr, rg, rb, 'cast')
                if R.PortraitManager._debug then
                    print(("|CombinedPortrait.Update: requested cast color r=%.2f g=%.2f b=%.2f applied=%s")
                        :format(rr or 0, rg or 0, rb or 0, tostring(applied)))
                end
            end
            if not applied then
                -- Fallback: directly set border and clear any manager claim so we don't get blocked
                SetPortraitBorder(self, rr, rg, rb, 'cast')
                if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                    R.PortraitManager.ClearClaim(self)
                else
                    self._portraitManagerClaim = nil
                    self._portraitManagerClaimTS = nil
                end
            end
        end
        local radial = element.radialStatusbar or self.PortraitRadialStatusbar
        if not radial then
            if R and R.UF and R.UF.EnsurePortraitRadial then
                radial = R.UF.EnsurePortraitRadial(self)
            elseif R and R.NP and R.NP.EnsurePortraitRadial and self.PortraitFrame then
                R.NP.EnsurePortraitRadial(self)
                radial = self.PortraitRadialStatusbar
            end
        end
        if radial and radial.SetRadialStatusBarValue then
            radial:SetRadialStatusBarValue(0)
            radial:Hide()
        end
    else
        -- Check for Crowd Control (medium priority before quest)
        local cc = FindActiveCC(unit)
        if cc and cc.icon then
            -- Apply CC icon and border tint
            element:SetTexture(cc.icon)
            if element.Text then element.Text:SetText("") end
            element.currentState = 'cc'

            -- Border: set to blue while CC is active (use PortraitManager)
            if self.PortraitBorder then
                local applied = false
                if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                    applied = R.PortraitManager.RequestColor(self, 0.2, 0.6, 1, 'cc')
                    if R.PortraitManager._debug then
                        print(("|CombinedPortrait.Update: requested cc color applied=%s")
                            :format(tostring(applied)))
                    end
                end
                if not applied then
                    SetPortraitBorder(self, 0.2, 0.6, 1, 'cc')
                    if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                        R.PortraitManager.ClearClaim(self)
                    else
                        self._portraitManagerClaim = nil
                        self._portraitManagerClaimTS = nil
                    end
                end
            end

            -- Hide radial during CC
            local radial = element.radialStatusbar or self.PortraitRadialStatusbar
            if not radial then
                if R and R.UF and R.UF.EnsurePortraitRadial then
                    radial = R.UF.EnsurePortraitRadial(self)
                elseif R and R.NP and R.NP.EnsurePortraitRadial and self.PortraitFrame then
                    R.NP.EnsurePortraitRadial(self)
                    radial = self.PortraitRadialStatusbar
                end
            end
            if radial and radial.SetRadialStatusBarValue then
                radial:SetRadialStatusBarValue(0)
                radial:Hide()
            end
        else
            -- Not CC: restore border to appropriate color
            if element.currentState == 'cc' and self.PortraitBorder then
                -- CC ended, restore to target or default color
                local tr, tg, tb
                if UnitIsUnit(unit, 'target') and C.nameplate.targetBorder then
                    tr, tg, tb = unpack(C.nameplate.targetBorderColor)
                else
                    tr, tg, tb = C.media.borderColor[1], C.media.borderColor[2], C.media.borderColor[3]
                end
                local applied = false
                if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                    applied = R.PortraitManager.RequestColor(self, tr, tg, tb, 'restore')
                end
                if not applied then
                    SetPortraitBorder(self, tr, tg, tb, 'restore')
                    if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                        R.PortraitManager.ClearClaim(self)
                    else
                        self._portraitManagerClaim = nil
                        self._portraitManagerClaimTS = nil
                    end
                end
            elseif element.currentState == 'cast' and self.PortraitBorder then
                -- Cast ended, restore to target or default color
                local tr, tg, tb
                if UnitIsUnit(unit, 'target') and C.nameplate.targetBorder then
                    tr, tg, tb = unpack(C.nameplate.targetBorderColor)
                else
                    tr, tg, tb = C.media.borderColor[1], C.media.borderColor[2], C.media.borderColor[3]
                end
                local applied = false
                if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                    applied = R.PortraitManager.RequestColor(self, tr, tg, tb, 'quest_restore')
                end
                if not applied then
                    SetPortraitBorder(self, tr, tg, tb, 'quest_restore')
                    if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                        R.PortraitManager.ClearClaim(self)
                    else
                        self._portraitManagerClaim = nil
                        self._portraitManagerClaimTS = nil
                    end
                end
            end

            -- Check for quest status (medium priority)
            local questList = GetQuests(unit)
            if questList and #questList > 0 then
                self.isQuestMob = true -- Set isQuestMob property
                local quest = questList[1]
                -- Ensure radial exists lazily if needed
                local radial = element.radialStatusbar or self.PortraitRadialStatusbar
                if not radial then
                    if R and R.UF and R.UF.EnsurePortraitRadial then
                        radial = R.UF.EnsurePortraitRadial(self)
                    elseif R and R.NP and R.NP.EnsurePortraitRadial and self.PortraitFrame then
                        R.NP.EnsurePortraitRadial(self)
                        radial = self.PortraitRadialStatusbar
                    end
                end
                if radial and radial.SetRadialStatusBarValue then
                    radial:SetRadialStatusBarValue(quest.objectiveProgress)
                    radial:Show()
                end

                if quest.questType == "LOOT_ITEM" then
                    element:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\QuestLoot.blp")
                elseif quest.questType == "KILL" then
                    element:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\QuestKill.blp")
                elseif quest.questType == "QUEST_ITEM" then
                    element:SetTexture(quest.itemTexture)
                else
                    element:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\QuestIcon.blp")
                end

                if element.Text then
                    local newText = quest.isPercent and (math.floor(quest.objectiveProgress * 100) .. "%") or
                        tostring(math.floor(quest.objectiveProgress * 100))
                    element.Text:SetText(newText)
                    element.Text:SetTextColor(1, 0.82, 0)
                    element.Text:Show()
                end
                element.currentState = 'quest'
            else
                -- Default to normal portrait (lowest priority)
                SetPortraitTexture(element, unit)
                if element.Text then element.Text:SetText("") end
                element.currentState = 'portrait'
                local radial = element.radialStatusbar or self.PortraitRadialStatusbar
                if not radial then
                    if R and R.UF and R.UF.EnsurePortraitRadial then
                        radial = R.UF.EnsurePortraitRadial(self)
                    elseif R and R.NP and R.NP.EnsurePortraitRadial and self.PortraitFrame then
                        R.NP.EnsurePortraitRadial(self)
                        radial = self.PortraitRadialStatusbar
                    end
                end
                if radial and radial.SetRadialStatusBarValue then
                    radial:SetRadialStatusBarValue(0)
                    radial:Hide()
                end
                -- Restore border when returning to normal portrait (via PortraitManager)
                if self.PortraitBorder then
                    local tr, tg, tb
                    if UnitIsUnit(unit, "target") and C.nameplate.targetBorder then
                        tr, tg, tb = unpack(C.nameplate.targetBorderColor)
                    else
                        tr, tg, tb = C.media.borderColor[1], C.media.borderColor[2], C.media.borderColor[3]
                    end
                    local applied = false
                    if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                        applied = R.PortraitManager.RequestColor(self, tr, tg, tb, 'default_restore')
                    end
                    if not applied then
                        SetPortraitBorder(self, tr, tg, tb, 'default_restore')
                        if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                            R.PortraitManager.ClearClaim(self)
                        else
                            self._portraitManagerClaim = nil
                            self._portraitManagerClaimTS = nil
                        end
                    end
                end
            end
        end
    end

    element:Show()
    element.guid = guid
    element.state = isAvailable

    if element.PostUpdate then
        return element:PostUpdate(unit)
    end
end

-- Minimal cooperative API: allow other modules (e.g., NP) to request portrait color changes.
-- The PortraitManager collects owners and asks them to apply colors according to their
-- internal priorities. Owners should return true if they applied the color, false to decline.
R.PortraitManager = R.PortraitManager or {}
local PM = R.PortraitManager
-- Owners are stored in a map and an ordered list so iteration is deterministic.
PM._ownersMap = PM._ownersMap or {}
PM._ownersOrder = PM._ownersOrder or {}
-- Default to no debug spam; set R.PortraitManager._debug = true at runtime to enable verbose traces
PM._debug = PM._debug or false

local function rebuildOwnerOrder()
    -- Sort owners by priority desc, then registration order asc
    table.sort(PM._ownersOrder, function(a, b)
        local ea = PM._ownersMap[a]
        local eb = PM._ownersMap[b]
        if not ea or not eb then return (ea and true) end
        if ea.priority == eb.priority then
            return (ea.registerIndex or 0) < (eb.registerIndex or 0)
        end
        return (ea.priority or 0) > (eb.priority or 0)
    end)
end

function PM.RegisterOwner(name, handlers, priority)
    if not name or type(handlers) ~= 'table' then return end
    priority = tonumber(priority) or 0
    if not PM._ownersMap[name] then
        PM._ownersOrder[#PM._ownersOrder + 1] = name
    end
    PM._ownersMap[name] = { handlers = handlers, priority = priority, registerIndex = #PM._ownersOrder }
    rebuildOwnerOrder()
end

function PM.UnregisterOwner(name)
    if not name or not PM._ownersMap[name] then return end
    PM._ownersMap[name] = nil
    for i = #PM._ownersOrder, 1, -1 do
        if PM._ownersOrder[i] == name then
            table.remove(PM._ownersOrder, i)
        end
    end
end

function PM.RequestColor(frame, r, g, b, reason)
    if not frame then return false end
    -- ensure frame has a claim version to guard delayed callbacks
    frame._portraitClaimVersion = frame._portraitClaimVersion or 0
    for i = 1, #PM._ownersOrder do
        local name = PM._ownersOrder[i]
        local entry = PM._ownersMap[name]
        if entry and entry.handlers and type(entry.handlers.ApplyColor) == 'function' then
            local handler = entry.handlers
            -- Set a short-lived pending claim so any RestoreDefault calls triggered
            -- during handler execution will be ignored due to recent claim timestamp.
            frame._portraitManagerClaim = '__pending'
            frame._portraitManagerClaimTS = GetTime()
            if PM._debug then
                print(("|PortraitManager: RequestColor pre-claim owner=%s reason=%s"):format(name, tostring(reason)))
            end
            local ok = handler.ApplyColor(frame, r, g, b, reason)
            if not ok then
                -- clear pending claim and continue to next owner
                frame._portraitManagerClaim = nil
                frame._portraitManagerClaimTS = nil
            end
            if PM._debug then
                print(("|PortraitManager: RequestColor owner=%s reason=%s r=%.2f g=%.2f b=%.2f -> %s"):format(name,
                    tostring(reason), r or 0, g or 0, b or 0, ok and 'APPLIED' or 'DECLINED'))
            end
            if ok then
                -- finalize the claim with the real reason
                frame._portraitManagerClaim = reason
                frame._portraitManagerClaimTS = GetTime()
                -- capture version to ensure delayed reapply only touches same logical frame
                local localVersion = frame._portraitClaimVersion
                -- Re-apply the color a couple times shortly after to beat racey overrides
                if frame.PortraitBorder then
                    local rr, rg, rb = r, g, b
                    local C_Timer_After = C_Timer and C_Timer.After
                    C_Timer_After(0.05, function()
                        if frame and frame.PortraitBorder and frame._portraitManagerClaim == reason and frame._portraitClaimVersion == localVersion then
                            frame.PortraitBorder:SetVertexColor(rr, rg, rb)
                            if PM._debug then
                                print(("|PortraitManager: reapplied color for reason=%s r=%.2f g=%.2f b=%.2f")
                                    :format(tostring(reason), rr, rg, rb))
                            end
                        end
                    end)
                    C_Timer_After(0.12, function()
                        if frame and frame.PortraitBorder and frame._portraitManagerClaim == reason and frame._portraitClaimVersion == localVersion then
                            frame.PortraitBorder:SetVertexColor(rr, rg, rb)
                        end
                    end)
                end
                return true
            end
        end
    end
    if PM._debug then
        print(("|PortraitManager: RequestColor no owner applied reason=%s"):format(tostring(reason)))
    end
    return false
end

function PM.RestoreDefault(frame)
    if not frame then return end
    -- If a recent claim exists, avoid immediately restoring because this may be
    -- a race where a different module requested a color (e.g., cast) just now.
    local grace = 0.15
    if frame._portraitManagerClaimTS and (GetTime() - frame._portraitManagerClaimTS) < grace then
        if PM._debug then
            local caller = (debugstack and debugstack()) or "<no trace>"
            print(("|PortraitManager: RestoreDefault ignored due to recent claim=%s (%.2fs < %.2fs) caller:\n%s"):format(
                tostring(frame._portraitManagerClaim), GetTime() - frame._portraitManagerClaimTS, grace, caller))
        end
        return
    end
    -- clear any claim when restoring default
    frame._portraitManagerClaim = nil
    frame._portraitManagerClaimTS = nil
    for i = 1, #PM._ownersOrder do
        local name = PM._ownersOrder[i]
        local entry = PM._ownersMap[name]
        if entry and entry.handlers and type(entry.handlers.RestoreDefault) == 'function' then
            entry.handlers.RestoreDefault(frame)
        end
    end
end

-- Clear any manager claim immediately and force a restore via the manager.
-- This centralizes the common pattern used by other modules that used to
-- manually clear _portraitManagerClaim/_portraitManagerClaimTS and call
-- RestoreDefault themselves.
function PM.ReleaseClaimAndRestore(frame)
    if not frame then return end
    -- Clear any local claim state so RestoreDefault won't bail out due to a
    -- recent claim timestamp.
    frame._portraitManagerClaim = nil
    frame._portraitManagerClaimTS = nil
    if PM._debug then
        local caller = (debugstack and debugstack()) or "<no trace>"
        print(("|PortraitManager: ReleaseClaimAndRestore invoked for frame, caller:\n%s"):format(caller))
    end
    PM.RestoreDefault(frame)
end

-- Clear a claim without restoring default. Useful for fallbacks that directly
-- set the portrait border and just need to ensure the manager won't block it.
function PM.ClearClaim(frame)
    if not frame then return end
    frame._portraitManagerClaim = nil
    frame._portraitManagerClaimTS = nil
    if PM._debug then
        print("|PortraitManager: ClearClaim invoked for frame")
    end
end

-- EnsureClearClaim: centralized fallback used by external modules that need to
-- clear any manager claim before directly manipulating the portrait border.
-- This encapsulates the common fallback pattern: prefer Invalidate(), then
-- ClearClaim(), and lastly perform a local metadata clear while bumping
-- _portraitClaimVersion so delayed reapply timers ignore recycled frames.
function PM.EnsureClearClaim(frame)
    if not frame then return false end
    if type(PM.Invalidate) == 'function' then
        PM.Invalidate(frame)
        if PM._debug then print("|PortraitManager: EnsureClearClaim -> Invalidate") end
        return true
    end
    if type(PM.ClearClaim) == 'function' then
        PM.ClearClaim(frame)
        if PM._debug then print("|PortraitManager: EnsureClearClaim -> ClearClaim") end
        return true
    end
    -- Final local fallback
    frame._portraitManagerClaim = nil
    frame._portraitManagerClaimTS = nil
    frame._portraitClaimVersion = (frame._portraitClaimVersion or 0) + 1
    if PM._debug then
        print(("|PortraitManager: EnsureClearClaim -> local fallback bumpVersion=%d"):format(frame
            ._portraitClaimVersion))
    end
    return false
end

-- Invalidate a frame's portrait claim state for reuse. This increments the
-- frame's _portraitClaimVersion so any delayed reapply closures will skip
-- acting on recycled frames. It also clears any local claim metadata.
function PM.Invalidate(frame)
    if not frame then return end
    frame._portraitClaimVersion = (frame._portraitClaimVersion or 0) + 1
    frame._portraitManagerClaim = nil
    frame._portraitManagerClaimTS = nil
    if PM._debug then
        print(("|PortraitManager: Invalidate called - newVersion=%d"):format(frame._portraitClaimVersion))
    end
end

-- Priority map used by CombinedPortrait when deciding whether to accept requests.
-- Keep this aligned with CombinedPortrait's internal rules: casting takes priority
-- over CC (see Update(): casting overrides cc), then quest, then default portrait.
local PRIORITY = { cast = 3, cc = 2, quest = 1, portrait = 0 }

local function combinedApplyColorRequest(frame, r, g, b, reason)
    if not frame or not frame.CombinedPortrait then return false end
    local element = frame.CombinedPortrait
    local cur = element.currentState or 'portrait'
    local curP = PRIORITY[cur] or 0
    local reqP = PRIORITY[reason] or 2
    -- If current state has strictly higher priority, decline
    if curP > reqP then
        if PM._debug then
            print(('|CombinedPortrait: Decline ApplyColor reason=%s cur=%s curP=%d reqP=%d'):format(tostring(reason),
                tostring(cur), curP, reqP))
        end
        return false
    end
    -- Apply the color and claim the state
    if frame.PortraitBorder then
        frame.PortraitBorder:SetVertexColor(r, g, b)
    end
    element.currentState = reason
    if PM._debug then
        print(('|CombinedPortrait: ApplyColor reason=%s applied cur=%s'):format(tostring(reason),
            tostring(element.currentState)))
        if frame.PortraitBorder then
            local cr, cg, cb = frame.PortraitBorder:GetVertexColor()
            print(("|CombinedPortrait: AfterSetVertexColor r=%.2f g=%.2f b=%.2f"):format(cr or 0, cg or 0, cb or 0))
        end
    end
    return true
end

local function combinedRestoreDefault(frame)
    if not frame or not frame.CombinedPortrait then return end
    -- If some other module holds a claim OR claim was very recent, don't restore yet
    local grace = 0.15
    if frame._portraitManagerClaim or (frame._portraitManagerClaimTS and (GetTime() - frame._portraitManagerClaimTS) < grace) then
        if PM._debug then
            print(("|CombinedPortrait: combinedRestoreDefault skipped due to claim=%s age=%.2fs"):format(
                tostring(frame._portraitManagerClaim),
                frame._portraitManagerClaimTS and (GetTime() - frame._portraitManagerClaimTS) or -1))
        end
        return
    end
    if frame.PortraitBorder then
        if UnitIsUnit(frame.unit, "target") and C.nameplate.targetBorder then
            local tr, tg, tb = unpack(C.nameplate.targetBorderColor)
            SetPortraitBorder(frame, tr, tg, tb, 'restore_default')
        else
            SetPortraitBorder(frame, C.media.borderColor[1], C.media.borderColor[2], C.media.borderColor[3],
                'restore_default')
        end
    end
end

-- Register CombinedPortrait as an owner so NP and others can request colors
PM.RegisterOwner('CombinedPortrait', { ApplyColor = combinedApplyColorRequest, RestoreDefault = combinedRestoreDefault })

local function Path(self, ...)
    return (self.CombinedPortrait.Override or Update)(self, ...)
end

local function ForceUpdate(element)
    return Path(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self, unit)
    local element = self.CombinedPortrait
    if element then
        element.__owner = self
        element.ForceUpdate = ForceUpdate

        -- Initialize isQuestMob property
        self.isQuestMob = false

        self:RegisterEvent('UNIT_PORTRAIT_UPDATE', Path)
        self:RegisterEvent('UNIT_MODEL_CHANGED', Path)
        self:RegisterEvent('UNIT_CONNECTION', Path)
        self:RegisterEvent('UNIT_SPELLCAST_START', Path)
        self:RegisterEvent('UNIT_SPELLCAST_STOP', Path)
        self:RegisterEvent('UNIT_SPELLCAST_CHANNEL_START', Path)
        self:RegisterEvent('UNIT_SPELLCAST_CHANNEL_STOP', Path)
        self:RegisterEvent('QUEST_LOG_UPDATE', Path, true)
        self:RegisterEvent('UNIT_NAME_UPDATE', Path)
        self:RegisterEvent('UNIT_AURA', Path)

        SetCVar("showQuestTrackingTooltips", 1)

        element:Show()

        return true
    end
end

local function Disable(self)
    local element = self.CombinedPortrait
    if element then
        element:Hide()

        self:UnregisterEvent('UNIT_PORTRAIT_UPDATE', Path)
        self:UnregisterEvent('UNIT_MODEL_CHANGED', Path)
        self:UnregisterEvent('UNIT_CONNECTION', Path)
        self:UnregisterEvent('UNIT_SPELLCAST_START', Path)
        self:UnregisterEvent('UNIT_SPELLCAST_STOP', Path)
        self:UnregisterEvent('UNIT_SPELLCAST_CHANNEL_START', Path)
        self:UnregisterEvent('UNIT_SPELLCAST_CHANNEL_STOP', Path)
        self:UnregisterEvent('QUEST_LOG_UPDATE', Path)
        self:UnregisterEvent('UNIT_NAME_UPDATE', Path)
        self:UnregisterEvent('UNIT_AURA', Path)
    end
end


local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function(self, event)
    -- Handle combat log death events separately and early-exit to avoid
    -- rebuilding the full quest index when only a single GUID is affected.
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" or subevent == "PARTY_KILL" then
            if destGUID and questCache[destGUID] then
                -- Invalidate only the affected GUID cache entry and ForceUpdate any matching nameplates
                questCache[destGUID] = nil
                for _, nameplate in pairs(oUF.objects) do
                    if nameplate and nameplate.CombinedPortrait and nameplate.guid == destGUID then
                        local cp = nameplate.CombinedPortrait
                        if cp.ForceUpdate then cp:ForceUpdate() end
                    end
                end
            end
        end
        return
    end

    wipe(CombinedPortrait.indexByID)
    wipe(CombinedPortrait.activeQuests)
    -- Clear GUID -> quest tooltip cache on any quest log change so we don't show stale info
    wipe(questCache)

    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local id = C_QuestLog.GetQuestIDForLogIndex(i)
        if id and id > 0 then
            CombinedPortrait.indexByID[id] = i

            local title = C_QuestLog.GetTitleForLogIndex(i)
            if title then CombinedPortrait.activeQuests[title] = id end
        end
    end

    -- Build candidate list for API-driven matching so MatchUnitToCandidates
    -- can quickly check only relevant quests instead of scanning the full log.
    if USE_API_QUESTS then
        BuildQuestCandidates()
    end

    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent(event)
    end

    if event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
        for _, nameplate in pairs(oUF.objects) do
            if nameplate and nameplate.CombinedPortrait then
                local cp = nameplate.CombinedPortrait
                if cp.ForceUpdate then
                    cp:ForceUpdate() -- Force update for each nameplate
                end
            end
        end
    end
end)

oUF:AddElement('CombinedPortrait', Path, Enable, Disable)
