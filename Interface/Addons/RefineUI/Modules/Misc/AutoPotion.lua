local AddOnName, RefineUI = ...
local AutoPotion = RefineUI:RegisterModule("AutoPotion")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
local CreateMacro, EditMacro, GetMacroInfo = CreateMacro, EditMacro, GetMacroInfo
local InCombatLockdown = InCombatLockdown
local IsSpellKnown = IsSpellKnown
local table_insert = table.insert
local table_concat = table.concat
local pairs, ipairs = pairs, ipairs

----------------------------------------------------------------------------------------
-- Constants & Item Lists (Retail/Midnight Focus)
----------------------------------------------------------------------------------------
local MACRO_NAME = "AutoPotion"
local MACRO_ICON = "INV_Misc_QuestionMark"
local RECUPERATE_ID = 1231411 -- Out-of-combat heal spell
local FALLBACK_POT = 244838   -- Invigorating Healing Potion R2 (User Preference)

-- Priority: Healthstones > Highest Tier Potion
local ITEMS = {
    HEALTHSTONES = {
        224464, -- Demonic Healthstone (Midnight)
        5512,   -- Healthstone
    },
    POTIONS = {
        -- Midnight / Invigorating (Highest Priority)
        244849, -- Fleeting Invigorating Healing Potion R3
        244839, -- Invigorating Healing Potion R3
        244838, -- Invigorating Healing Potion R2
        244835, -- Invigorating Healing Potion R1
        
        -- The War Within / Algari
        212944, -- Fleeting Algari Healing Potion R3
        211880, -- Algari Healing Potion R3
        211879, -- Algari Healing Potion R2
        211878, -- Algari Healing Potion R1
        
        -- Dragonflight / Refreshing
        191380, -- Refreshing Healing Potion R3
        191379, -- Refreshing Healing Potion R2
        191378, -- Refreshing Healing Potion R1
        
        -- Legacy
        171267, -- Spiritual Healing Potion
        152494, -- Coastal Healing Potion
    }
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local needsUpdate = false
local currentMacroBody = nil

----------------------------------------------------------------------------------------
-- Utility Logic
----------------------------------------------------------------------------------------

local function GetBestItem(idList)
    for i = 1, #idList do
        local id = idList[i]
        if GetItemCount(id) > 0 then
            return id
        end
    end
    return nil
end

local function UpdateMacro()
    if InCombatLockdown() then
        needsUpdate = true
        return
    end

    local bestHS = GetBestItem(ITEMS.HEALTHSTONES)
    local bestPot = GetBestItem(ITEMS.POTIONS)
    local recuperateName = GetSpellName(RECUPERATE_ID)
    local hasRecuperate = recuperateName and (IsSpellKnown(RECUPERATE_ID) or IsSpellKnown(RECUPERATE_ID, true))

    local sequence = {}
    if bestHS then table_insert(sequence, "item:" .. bestHS) end
    if bestPot then table_insert(sequence, "item:" .. bestPot) end

    -- Build Header
    local tooltip = "#showtooltip "
    if hasRecuperate then
        tooltip = tooltip .. "[nocombat] " .. recuperateName .. "; "
    end
    if #sequence > 0 then
        tooltip = tooltip .. "[combat] " .. sequence[1] .. "; "
    end
    tooltip = tooltip .. "item:" .. FALLBACK_POT

    local macroLines = { tooltip }

    -- Actions
    if hasRecuperate then
        table_insert(macroLines, "/cast [nocombat] " .. recuperateName)
    end

    if #sequence > 0 then
        table_insert(macroLines, "/castsequence [@player,combat] reset=combat " .. table_concat(sequence, ", "))
    else
        table_insert(macroLines, "/use [combat] item:" .. FALLBACK_POT)
    end

    local macroBody = table_concat(macroLines, "\n")
    
    -- Performance: Avoid updating if the macro is identical
    if macroBody == currentMacroBody then
        needsUpdate = false
        return 
    end

    -- Ensure macro exists and update
    local name = GetMacroInfo(MACRO_NAME)
    if not name then
        CreateMacro(MACRO_NAME, MACRO_ICON, macroBody, nil)
    else
        EditMacro(MACRO_NAME, nil, nil, macroBody)
    end

    currentMacroBody = macroBody
    needsUpdate = false
end

----------------------------------------------------------------------------------------
-- Module Lifecycle
----------------------------------------------------------------------------------------

function AutoPotion:OnEnable()
    -- Register for bag updates (Debounced)
    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function()
        RefineUI:Debounce("AutoPotionUpdate", 0.5, UpdateMacro)
    end)

    -- Handle combat exit
    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if needsUpdate then
            UpdateMacro()
        end
    end)

    -- Handle talent changes
    RefineUI:RegisterEventCallback("TRAIT_CONFIG_UPDATED", function()
        UpdateMacro()
    end)

    -- Initial load
    UpdateMacro()
end

