local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = R.oUF or (ns and ns.oUF) or rawget(_G, "oUF")
local UF = R.UF

-- Upvalues
local unpack = unpack


----------------------------------------------------------------------------------------
-- Party Frame Creation
----------------------------------------------------------------------------------------
local function CreateRaidFrame(self)
    -- Configure base unit frame
    UF.ConfigureUnitFrame(self)

    -- Create frame elements
    UF.CreateHealthBar(self)
    UF.CreatePowerBar(self)
    UF.CreateNameText(self)
    UF.CreateRaidDebuffs(self)
    UF.CreateRaidTargetIndicator(self)
    UF.CreateDebuffHighlight(self)
	UF.CreatePartyAuraWatch(self)
    UF.CreateGroupIcons(self)
    UF.ApplyGroupSettings(self)

    return self
end

local frameWidth = C.group.partyWidth
local frameHeight = C.group.partyHealthHeight + C.group.partyPowerHeight

-- Create anchor earlier to ensure it's available when placing the header
local raid = CreateFrame("Frame", "RaidAnchor", UIParent)
oUF:Factory(function(self)
    oUF:RegisterStyle("RefineUI_Raid", CreateRaidFrame)
    oUF:SetActiveStyle("RefineUI_Raid")
    
    local raidgroup = self:SpawnHeader("RefineUI_RaidHeader", nil, "raid,party,solo",
        "oUF-initialConfigFunction", [[
            local header = self:GetParent()
            self:SetWidth(header:GetAttribute("initial-width"))
            self:SetHeight(header:GetAttribute("initial-height"))
        ]],
        "initial-width", frameWidth - 15,
        "initial-height", R.Scale(frameHeight),
        "showRaid", true,
        "showParty", false,
        "showPlayer", true,
        "showSolo", false,
        "groupBy", "ASSIGNEDROLE",
        "groupingOrder", "TANK,HEALER,DAMAGER,NONE",
        "sortMethod", "NAME",
        "maxColumns", 8,
        "unitsPerColumn", 5,
        "columnSpacing", R.Scale(14),
        "yOffset", R.Scale(-60),
        "point", "TOP",
        "columnAnchorPoint", "RIGHT"
    )
    
    raidgroup:SetPoint("RIGHT", _G["RaidAnchor"])
    _G["RaidAnchor"]:SetSize(frameWidth, R.Scale(frameHeight) * 5 + R.Scale(7) * 4)
    _G["RaidAnchor"]:SetPoint(unpack(C.position.unitframes.raid))
	-- raidgroup:SetScale(0.9)
end)

-- anchor already created above

----------------------------------------------------------------------------------------
-- Expose CreateTargetFrame function
----------------------------------------------------------------------------------------
R.CreateRaidFrame = CreateRaidFrame

-- Blizzard compact frames are disabled early in Modules/Blizzard/CompactRaidFrames.lua