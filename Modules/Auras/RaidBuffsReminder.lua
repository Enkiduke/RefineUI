local R, C, L = unpack(RefineUI)
-- Safer early-out: handle nil C.reminder gracefully
if not (C.reminder and C.reminder.raidBuffsEnable) then return end

-- NOTE:
-- This module is currently disabled (legacy implementation below is commented out).
-- Keeping the file loaded preserves config gates and avoids runtime errors.
-- If/when re-enabling, prefer sharing helpers with SelfBuffsReminder (icons, alpha/flash rules)
-- and AuraUtil.ForEachAura for scanning to minimize C->Lua crossings.

--------------------------------------------------------------------------------
-- Upvalues (kept here for potential reactivation; no functional change while code is commented)
--------------------------------------------------------------------------------
-- local _G = _G
-- local AuraUtil, C_PaperDollInfo = AuraUtil, C_PaperDollInfo

-- ----------------------------------------------------------------------------------------
-- -- Upvalues
-- ----------------------------------------------------------------------------------------
-- local CreateFrame, GetWeaponEnchantInfo, IsInGroup, IsInInstance = CreateFrame, GetWeaponEnchantInfo, IsInGroup, IsInInstance
-- local UIFrameFadeIn, UIFrameFadeOut = UIFrameFadeIn, UIFrameFadeOut
-- local wipe, unpack, tinsert, ceil = wipe, unpack, table.insert, math.ceil
-- local AuraUtil, C_PaperDollInfo = AuraUtil, C_PaperDollInfo
-- local pairs, ipairs = pairs, ipairs

-- ----------------------------------------------------------------------------------------
-- -- Local Variables
-- ----------------------------------------------------------------------------------------
-- local playerBuff = {}
-- local icons = {}
-- local buffTypes = { "Flask", "BattleElixir", "GuardianElixir", "Food", "Stamina", "Vers", "Reduce", "Custom" }
-- local buffFrames = {}
-- local visible = false

-- ----------------------------------------------------------------------------------------
-- -- Helper Functions
-- ----------------------------------------------------------------------------------------
-- local function CheckElixir()
--     local battleElixir, guardianElixir = false, false
--     for _, buffType in ipairs({ "BattleElixir", "GuardianElixir" }) do
--         for _, buffData in ipairs(R.ReminderBuffs[buffType]) do
--             local name, icon = unpack(buffData)
--             if playerBuff[name] then
--                 if buffType == "BattleElixir" then
--                     battleElixir = true
--                 else
--                     guardianElixir = true
--                 end
--                 if not battleElixir then buffFrames.FlaskFrame.t:SetTexture(icon) end
--                 break
--             end
--         end
--     end
--     buffFrames.FlaskFrame:SetAlpha(battleElixir and guardianElixir and C.reminder.raidBuffsAlpha or 1)
--     return battleElixir and guardianElixir
-- end

-- local function CheckWeaponBuff()
--     local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
--     local OffhandHasWeapon = C_PaperDollInfo.OffhandHasWeapon()
--     local weaponBuffed = hasMainHandEnchant and (not OffhandHasWeapon or hasOffHandEnchant)
--     buffFrames.WeaponFrame:SetAlpha(weaponBuffed and C.reminder.raidBuffsAlpha or 1)
--     return weaponBuffed
-- end

-- local function CheckBuff(buffName)
--     return AuraUtil.FindAuraByName(buffName, "player") ~= nil
-- end

-- ----------------------------------------------------------------------------------------
-- -- Main Functions
-- ----------------------------------------------------------------------------------------
-- local function UpdateBuffs()
--     wipe(playerBuff)
    
--     -- Check all possible buffs
--     for _, buffType in ipairs(buffTypes) do
--         for _, buffData in ipairs(R.ReminderBuffs[buffType]) do
--             local name = buffData[1]
--             if CheckBuff(name) then
--                 playerBuff[name] = true
--             end
--         end
--     end

--     if R.Role == "Caster" or R.Role == "Healer" then
--         R.ReminderCasterBuffs()
--     else
--         R.ReminderPhysicalBuffs()
--     end

--     local allBuffed = true
--     for buffType, frame in pairs(buffFrames) do
--         if buffType == "FlaskFrame" then
--             allBuffed = allBuffed and CheckElixir()
--         elseif buffType == "WeaponFrame" then
--             frame.t:SetTexture(135250)
--             allBuffed = allBuffed and CheckWeaponBuff()
--         else
--             local buffed = false
--             for _, buffData in ipairs(R.ReminderBuffs[buffType:gsub("Frame", "")]) do
--                 local name, icon = unpack(buffData)
--                 if playerBuff[name] then
--                     buffed = true
--                     frame.t:SetTexture(icon)
--                     break
--                 end
--             end
--             frame:SetAlpha(buffed and C.reminder.raidBuffsAlpha or 1)
--             allBuffed = allBuffed and buffed
--         end
--     end

--     return allBuffed
-- end

-- local function UpdateVisibility()
--     local _, instanceType = IsInInstance()
--     local shouldBeVisible = not ((not IsInGroup() or instanceType ~= "raid") and not C.reminder.raidBuffsAlways)

--     if shouldBeVisible and not UpdateBuffs() then
--         if not visible then UIFrameFadeIn(RaidBuffReminder, 0.5) end
--         visible = true
--     else
--         if visible then UIFrameFadeOut(RaidBuffReminder, 0.5) end
--         visible = false
--     end
-- end

-- local function OnAuraChange(self, event, unit)
--     if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
--     UpdateVisibility()
-- end

-- ----------------------------------------------------------------------------------------
-- -- Frame Creation
-- ----------------------------------------------------------------------------------------
-- local RaidBuffsAnchor = CreateFrame("Frame", "RaidBuffsAnchor", UIParent)
-- RaidBuffsAnchor:SetSize((C.reminder.raidBuffsSize * 6) + 15, C.reminder.raidBuffsSize)
-- RaidBuffsAnchor:SetPoint(unpack(C.position.raidBuffs))

-- local RaidBuffReminder = CreateFrame("Frame", "RaidBuffReminder", UIParent)
-- RaidBuffReminder:CreatePanel("Invisible", (C.reminder.raidBuffsSize * 6) + 15, C.reminder.raidBuffsSize + 4, "TOPLEFT", RaidBuffsAnchor, "TOPLEFT", 0, 4)
-- RaidBuffReminder:SetScript("OnEvent", OnAuraChange)
-- RaidBuffReminder:RegisterUnitEvent("UNIT_AURA", "player")
-- RaidBuffReminder:RegisterEvent("PLAYER_ENTERING_WORLD")
-- RaidBuffReminder:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
-- RaidBuffReminder:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- RaidBuffReminder:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")

-- local line = ceil(C.minimap.size / (C.reminder.raidBuffsSize + 2))

-- local buffButtons = {}

-- for i, buffType in ipairs(buffTypes) do
--     local frame = CreateFrame("Frame", buffType .. "Frame", RaidBuffReminder)
--     frame:SetTemplate("Default")
--     frame:SetSize(C.reminder.raidBuffsSize, C.reminder.raidBuffsSize)

--     if i == 1 then
--         frame:SetPoint("BOTTOMLEFT", RaidBuffReminder, "BOTTOMLEFT", 0, 0)
--     elseif i == line then
--         frame:SetPoint("BOTTOM", buffButtons[1], "TOP", 0, 6)
--     else
--         frame:SetPoint("LEFT", buffButtons[i - 1], "RIGHT", 6, 0)
--     end

--     frame:SetFrameLevel(RaidBuffReminder:GetFrameLevel() + 2)

--     frame.t = frame:CreateTexture(nil, "OVERLAY")
--     frame.t:CropIcon()

--     buffFrames[buffType .. "Frame"] = frame
--     tinsert(buffButtons, frame)
--     tinsert(icons, frame)
-- end

-- local function UpdatePositions()
--     local line = ceil(C.minimap.size / (C.reminder.raidBuffsSize + 2))
--     local first
--     for i, buff in ipairs(icons) do
--         buff:ClearAllPoints()
--         if buff:GetAlpha() == C.reminder.raidBuffsAlpha then
--             line = line + 1
--         else
--             if not first then
--                 buff:SetPoint("BOTTOMLEFT", RaidBuffReminder, "BOTTOMLEFT", 0, 0)
--                 first = true
--             else
--                 buff:SetPoint("LEFT", icons[i - 1], "RIGHT", 6, 0)
--             end
--             buff:SetAlpha(i < line and 1 or 0)
--         end
--     end
-- end

-- RaidBuffReminder:SetScript("OnUpdate", UpdatePositions)