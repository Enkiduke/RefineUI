local R, C, L = unpack(RefineUI)
local LEM = LibStub and LibStub('LibEditMode', true)

-- Namespace
R.BuffWatch = R.BuffWatch or {}

-- Local helpers (KISS/DRY)
local function GetClassKey()
    -- Match Filger’s class profile keying (localized name)
    return UnitClass("player") or "UNKNOWN"
end

local function EnsureSV()
    RefineUI_BuffWatchClassProfiles = RefineUI_BuffWatchClassProfiles or {}
    RefineUI_BuffWatchGlobal = RefineUI_BuffWatchGlobal or {}

    local classKey = GetClassKey()
    RefineUI_BuffWatchClassProfiles[classKey] = RefineUI_BuffWatchClassProfiles[classKey] or {}
    local classProfile = RefineUI_BuffWatchClassProfiles[classKey]

    classProfile.PlayerBuffs = classProfile.PlayerBuffs or {}
    RefineUI_BuffWatchGlobal.PartyBuffs = RefineUI_BuffWatchGlobal.PartyBuffs or {}

    return classProfile, RefineUI_BuffWatchGlobal
end

local function SpellExists(spellID)
    local name = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID) or GetSpellInfo(spellID)
    return name ~= nil
end

local function ResolveSpell(input)
    if not input or input == "" then return nil end
    local id = tonumber(input)
    if id and SpellExists(id) then return id end
    local name = tostring(input)
    local maybeID = select(7, GetSpellInfo(name)) -- returns spellID as 7th
    if maybeID and SpellExists(maybeID) then return maybeID end
    return nil
end

-- Convert an entry to BuffWatch element format: {id, color, nil, anyUnit, strict}
local function ToBuffWatchEntry(entry)
    if type(entry) == "table" and entry.spellID then
        local color = entry.color or C.media.borderColor
        local anyUnit = entry.anyUnit == true
        local strict = entry.strictMatching == true
        return { entry.spellID, color, nil, anyUnit, strict }
    end
    return nil
end

-- Public API: provide merged spell lists for Elements.lua
R.BuffWatch.GetMergedPlayerBuffs = function()
    local buffs = {}
    local classProfile = EnsureSV()
    local list = classProfile and classProfile.PlayerBuffs or {}
    if list and #list > 0 then
        for _, e in ipairs(list) do
            local v = ToBuffWatchEntry(e)
            if v then table.insert(buffs, v) end
        end
        return buffs
    end
    -- Fallback to defaults if SV empty
    if R.RaidBuffs and R.RaidBuffs["ALL"] then
        for _, v in pairs(R.RaidBuffs["ALL"]) do table.insert(buffs, v) end
    end
    if R.RaidBuffs and R.RaidBuffs[R.class] then
        for _, v in pairs(R.RaidBuffs[R.class]) do table.insert(buffs, v) end
    end
    return buffs
end

R.BuffWatch.GetMergedPartyBuffs = function()
    local buffs = {}
    local _, global = EnsureSV()
    local list = global and global.PartyBuffs or {}
    if list and #list > 0 then
        for _, e in ipairs(list) do
            local v = ToBuffWatchEntry(e)
            if v then table.insert(buffs, v) end
        end
        return buffs
    end
    -- Fallback to defaults if SV empty
    if R.RaidBuffs then
        for _, buffList in pairs(R.RaidBuffs) do
            for _, v in pairs(buffList) do table.insert(buffs, v) end
        end
    end
    return buffs
end

-- Update all UnitFrames that host BuffWatch elements (party + raid)
R.BuffWatch.TriggerRefresh = function()
    local function BuildPlayerBuffs()
        -- Use the same precedence as Elements.lua: SV first, fallback to defaults
        return R.BuffWatch.GetMergedPlayerBuffs()
    end
    local function BuildPartyBuffs()
        -- Use the same precedence as Elements.lua: SV first, fallback to defaults
        return R.BuffWatch.GetMergedPartyBuffs()
    end

    local function RefreshChildren(headerName)
        local header = _G[headerName]
        if not header or not header.GetChildren then return end
        for _, frame in ipairs({ header:GetChildren() }) do
            local changed = false
            if frame.PlayerBuffWatch then
                frame.PlayerBuffWatch.buffs = BuildPlayerBuffs()
                if frame.PlayerBuffWatch.icons then
                    for _, icon in pairs(frame.PlayerBuffWatch.icons) do if icon.Hide then icon:Hide() end end
                end
                frame.PlayerBuffWatch.icons = nil
                changed = true
            end
            if frame.PartyBuffWatch then
                frame.PartyBuffWatch.buffs = BuildPartyBuffs()
                if frame.PartyBuffWatch.icons then
                    for _, icon in pairs(frame.PartyBuffWatch.icons) do if icon.Hide then icon:Hide() end end
                end
                frame.PartyBuffWatch.icons = nil
                changed = true
            end
            if changed and frame.DisableElement and frame.EnableElement then
                frame:DisableElement("BuffWatch")
                frame:EnableElement("BuffWatch")
                if frame.UpdateElement then frame:UpdateElement("BuffWatch") end
            elseif changed and frame.UpdateElement then
                frame:UpdateElement("BuffWatch")
            end
        end
    end

    RefreshChildren("RefineUI_PartyHeader")
    RefreshChildren("RefineUI_RaidHeader")
end

-- Add / Remove
R.BuffWatch.AddSpell = function(listType, input)
    local classProfile, global = EnsureSV()
    local spellID = ResolveSpell(input)
    if not spellID then
        print("|cFFFFD200Error:|r Invalid spell: " .. tostring(input))
        return
    end

    local targetList
    if listType == "PLAYER" then
        targetList = classProfile.PlayerBuffs
    else
        targetList = global.PartyBuffs
    end

    -- De-dup
    for _, e in ipairs(targetList) do
        if e.spellID == spellID then
            local n = GetSpellInfo(spellID) or spellID
            print("|cFFFFD200Note:|r Already tracking " .. tostring(n))
            return
        end
    end

    local defaultColor = R.oUF_colors and R.oUF_colors.class and R.oUF_colors.class[R.class] or C.media.borderColor
    table.insert(targetList, {
        spellID = spellID,
        color = { unpack(defaultColor) },
        -- Party side never shows player casts; no per-spell anyUnit override needed
        anyUnit = nil,
        strictMatching = false,
    })

    R.BuffWatch.TriggerRefresh()
end

R.BuffWatch.RemoveSpell = function(listType, spellID)
    local classProfile, global = EnsureSV()
    spellID = tonumber(spellID)
    if not spellID then return end

    local targetList = (listType == "PLAYER") and classProfile.PlayerBuffs or global.PartyBuffs
    for i, e in ipairs(targetList) do
        if e.spellID == spellID then
            table.remove(targetList, i)
            break
        end
    end
    R.BuffWatch.TriggerRefresh()
end

-- Minimal Spell Management UI (modeled after FilgerEditMode patterns)
local function CreateBuffWatchUI(listTypeFixed, title)
    local panelName = "RefineUI_BuffWatchPanel_" .. (listTypeFixed or "GENERIC")
    local panel = CreateFrame("Frame", panelName, UIParent, "BackdropTemplate")
    panel:SetSize(680, 520)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:EnableKeyboard(true)
    panel:Hide()

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -14)
    panel.title:SetText(title or "BuffWatch")

    -- Drag area for moving panel
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", 0, 0)
    drag:SetHeight(40)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then panel:StartMoving() end end)
    drag:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then panel:StopMovingOrSizing() end end)

    -- Fixed list type per panel
    local listType = listTypeFixed or "PLAYER"

    -- Add control
    local addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addBox:SetAutoFocus(false)
    addBox:SetSize(240, 24)
    addBox:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -12)
    addBox:SetText("")
    addBox:SetCursorPosition(0)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local input = addBox:GetText()
        if input and input ~= "" then
            R.BuffWatch.AddSpell(listType, input)
            addBox:SetText("")
            if panel.RefreshList then panel:RefreshList() end
        end
    end)

    -- Scroll list
    -- Column headers for a cleaner, Filger-like layout
    local headers = CreateFrame("Frame", nil, panel)
    headers:SetSize(680, 20)
    headers:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 4, -10)
    local COL = { Icon = 5, Spell = 32, Color = 520, Delete = 600 }
    local function AddHeader(text, x)
        local fs = headers:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", headers, "LEFT", x, 0)
        fs:SetText(text)
        fs:SetTextColor(0.9, 0.9, 0.9)
    end
    AddHeader("Spell", COL.Spell)
    AddHeader("Color", COL.Color)
    AddHeader("Delete", COL.Delete + 6)
    local headerDivider = headers:CreateTexture(nil, "ARTWORK")
    headerDivider:SetColorTexture(1, 1, 1, 0.06)
    headerDivider:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", -4, -2)
    headerDivider:SetPoint("TOPRIGHT", headers, "BOTTOMRIGHT", 4, -2)
    headerDivider:SetHeight(1)

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headers, "BOTTOMLEFT", -4, -6)
    scroll:SetSize(690, 410)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(680, 1)
    scroll:SetScrollChild(list)

    local function CreateColorButton(parent, entry, onChanged)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(24, 16)
        b:SetBackdrop({ bgFile = C.media.blank, edgeFile = C.media.blank, edgeSize = 1 })
        b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        local function Sync()
            local c = entry.color or C.media.borderColor
            b:SetBackdropColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
        end
        b:SetScript("OnClick", function()
            local c = entry.color or { unpack(C.media.borderColor) }
            ColorPickerFrame:SetupColorPickerAndShow({
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    entry.color = { r, g, b }
                    Sync(); if onChanged then onChanged() end
                end,
                r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, opacity = 1,
            })
        end)
        b.Sync = Sync
        Sync()
        return b
    end

    function panel:RefreshList()
        for _, child in ipairs({ list:GetChildren() }) do child:Hide(); child:SetParent(nil) end
        local classProfile, global = EnsureSV()
        local data = (listType == "PLAYER") and classProfile.PlayerBuffs or global.PartyBuffs
        local y = 0
        if #data == 0 then
            local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            empty:SetPoint("TOPLEFT", 8, -4)
            empty:SetText("No spells added.")
            list:SetHeight(24)
            return
        end
        for i, entry in ipairs(data) do
            local row = CreateFrame("Frame", nil, list, "BackdropTemplate")
            row:SetSize(660, 28)
            row:SetPoint("TOPLEFT", 4, -y)
            row:EnableMouse(true)
            -- stripe background + hover highlight
            local shade = (i % 2 == 0) and 0.06 or 0.03
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, shade)
            local hl = row:CreateTexture(nil, "OVERLAY")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            hl:Hide()
            row:SetScript("OnEnter", function() hl:Show() end)
            row:SetScript("OnLeave", function() hl:Hide() end)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 2, 0)
            local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellID)
            if tex then icon:SetTexture(tex) end
            icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

            local name = GetSpellInfo(entry.spellID) or tostring(entry.spellID)
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", row, "LEFT", COL.Spell, 0)
            label:SetText(string.format("%s (%d)", name, entry.spellID))

            -- Party editor no longer exposes an "Any Caster" toggle; Party side never shows player casts

            local colorBtn = CreateColorButton(row, entry, function()
                R.BuffWatch.TriggerRefresh()
            end)
            colorBtn:SetPoint("LEFT", row, "LEFT", COL.Color, 0)
            colorBtn:HookScript("OnEnter", function()
                GameTooltip:SetOwner(colorBtn, "ANCHOR_RIGHT")
                GameTooltip:SetText("Icon Color", 1, 0.82, 0)
                GameTooltip:AddLine("Left-click: choose color", 1, 1, 1)
                GameTooltip:AddLine("Right-click: clear color", 1, 1, 1)
                GameTooltip:Show()
            end)
            colorBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
            colorBtn:HookScript("OnMouseUp", function(_, btn)
                if btn == "RightButton" then
                    entry.color = nil
                    if colorBtn.Sync then colorBtn:Sync() end
                    R.BuffWatch.TriggerRefresh()
                end
            end)

            local del = CreateFrame("Button", nil, row)
            del:SetSize(24, 24)
            del:SetPoint("LEFT", row, "LEFT", COL.Delete, 0)
            if del.SetNormalAtlas then
                del:SetNormalAtlas("GM-raidMarker-remove")
                del:SetPushedAtlas("GM-raidMarker-remove")
                del:SetHighlightAtlas("GM-raidMarker-remove")
                local ht = del:GetHighlightTexture()
                if ht then ht:SetAlpha(0.25) end
            else
                local n = del:CreateTexture(nil, "ARTWORK")
                n:SetAllPoints()
                n:SetAtlas("GM-raidMarker-remove", true)
                del:SetNormalTexture(n)
            end
            del:SetScript("OnEnter", function()
                GameTooltip:SetOwner(del, "ANCHOR_LEFT")
                GameTooltip:SetText("Delete", 1, 0.1, 0.1)
                GameTooltip:AddLine("Click to remove this spell", 1, 1, 1)
                GameTooltip:Show()
            end)
            del:SetScript("OnLeave", function() GameTooltip:Hide() end)
            del:SetScript("OnClick", function()
                StaticPopup_Show("BUFFWATCH_CONFIRM_DELETE", GetSpellInfo(entry.spellID) or ("Spell ID " .. entry.spellID), nil, {
                    spellID = entry.spellID,
                    listType = listType,
                    refreshFunc = function()
                        if panel.RefreshList then panel:RefreshList() end
                    end,
                })
            end)

            y = y + 30
        end
        list:SetHeight(math.max(y, 1))
    end

    -- Close button and ESC handler
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    panel:SetScript("OnKeyDown", function(_, key)
        if key == GetBindingKey("TOGGLEGAMEMENU") or key == "ESCAPE" then panel:Hide() end
    end)

    -- Hide panel on Edit Mode exit
    local owner = {}
    panel:SetScript("OnShow", function()
        if EventRegistry then
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                if panel:IsShown() then panel:Hide() end
            end, owner)
        end
        panel:RefreshList()
    end)
    panel:SetScript("OnHide", function()
        if EventRegistry then
            EventRegistry:UnregisterCallback("EditMode.Exit", owner)
        end
    end)

    return function()
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end
end

-- Register with LibEditMode or direct Edit Mode button as fallback
local function RegisterEditIntegration()
    local anchor = _G["RefineUI_Party"] or _G["RefineUI_PartyHeader"] or UIParent

    -- Create two panel toggles
    local togglePlayer = CreateBuffWatchUI("PLAYER", "Player Buffs")
    local toggleParty  = CreateBuffWatchUI("PARTY",  "Party Buffs")

    if LEM and LEM.AddFrame then
        anchor.EditModeFrameName = "RefineUI_BuffWatch"
        LEM:AddFrame(anchor, function(_, _, point, x, y)
            -- no-op for now; party anchor persists via EditMode
        end, { point = "CENTER", x = 0, y = 0 })

        if LEM.AddFrameSettingsButton then
            -- Separate buttons for each list
            LEM:AddFrameSettingsButton(anchor, { text = "Edit Player Buffs", click = function() togglePlayer() end })
            LEM:AddFrameSettingsButton(anchor, { text = "Edit Party Buffs",  click = function() toggleParty() end  })
        end
    elseif C_EditMode then
        -- Fallback: add two buttons that show during Edit Mode
        local btnPlayer = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        btnPlayer:SetSize(130, 22)
        btnPlayer:SetPoint("BOTTOM", anchor, "TOP", -75, 8)
        btnPlayer:SetText("Player Buffs")
        btnPlayer:SetScript("OnClick", togglePlayer)
        btnPlayer:Hide()

        local btnParty = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        btnParty:SetSize(130, 22)
        btnParty:SetPoint("BOTTOM", anchor, "TOP", 75, 8)
        btnParty:SetText("Party Buffs")
        btnParty:SetScript("OnClick", toggleParty)
        btnParty:Hide()

        local function Update()
            local active = C_EditMode.IsEditModeActive and C_EditMode.IsEditModeActive()
            if active then btnPlayer:Show(); btnParty:Show() else btnPlayer:Hide(); btnParty:Hide() end
        end
        anchor:HookScript("OnShow", Update)
        C_Timer.NewTicker(0.5, Update)
    end
end

-- Initialize after login so SVs are present
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    EnsureSV()
    -- Preload defaults from AuraWatch into SV if empty, then manage via SV
    if not R.BuffWatch.LoadManagedSpells then
        R.BuffWatch.LoadManagedSpells = function()
            local classProfile, global = EnsureSV()
            -- Player (class-wide): if empty, seed from AuraWatch defaults for this class
            if classProfile and type(classProfile.PlayerBuffs) == "table" and #classProfile.PlayerBuffs == 0 then
                local seeded = {}
                if R.RaidBuffs and R.RaidBuffs["ALL"] then
                    for _, v in pairs(R.RaidBuffs["ALL"]) do table.insert(seeded, { spellID = v[1], color = v[2] }) end
                end
                if R.RaidBuffs and R.RaidBuffs[R.class] then
                    for _, v in pairs(R.RaidBuffs[R.class]) do table.insert(seeded, { spellID = v[1], color = v[2] }) end
                end
                classProfile.PlayerBuffs = seeded
            end
            -- Party (global): if empty, seed from all AuraWatch defaults
            if global and type(global.PartyBuffs) == "table" and #global.PartyBuffs == 0 then
                local seeded = {}
                if R.RaidBuffs then
                    for _, list in pairs(R.RaidBuffs) do
                        for _, v in pairs(list) do
                            table.insert(seeded, { spellID = v[1], color = v[2] })
                        end
                    end
                end
                global.PartyBuffs = seeded
            end
        end
    end
    R.BuffWatch.LoadManagedSpells()
    -- Confirm delete popup
    if not StaticPopupDialogs["BUFFWATCH_CONFIRM_DELETE"] then
        StaticPopupDialogs["BUFFWATCH_CONFIRM_DELETE"] = {
            text = "Delete %s?",
            button1 = DELETE,
            button2 = CANCEL,
            OnAccept = function(self, data)
                if not data or not data.spellID or not data.listType then return end
                R.BuffWatch.RemoveSpell(data.listType, data.spellID)
                if data.refreshFunc then data.refreshFunc() end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    C_Timer.After(1, function()
        RegisterEditIntegration()
    end)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
