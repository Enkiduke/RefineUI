local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = R.oUF or (ns and ns.oUF) or rawget(_G, "oUF")
local UF = R.UF

-- Upvalues
local unpack = unpack


----------------------------------------------------------------------------------------
-- Party Frame Creation
----------------------------------------------------------------------------------------
local function CreatePartyFrame(self)
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

----------------------------------------------------------------------------------------
-- Target Frame Initialization
----------------------------------------------------------------------------------------
-- Register and set the target frame style
oUF:Factory(function(self)
    oUF:RegisterStyle("RefineUI_Party", CreatePartyFrame)
    oUF:SetActiveStyle("RefineUI_Party")
    -- Use a distinct header name to avoid colliding with our anchor frame
    local partyHeader = self:SpawnHeader("RefineUI_PartyHeader", nil, "custom [@raid6,exists] hide;show",
        "oUF-initialConfigFunction", [[
				local header = self:GetParent()
				self:SetWidth(header:GetAttribute("initial-width"))
				self:SetHeight(header:GetAttribute("initial-height"))
			]],
        "initial-width", C.group.partyWidth,
        "initial-height", R.Scale(C.group.partyHealthHeight + C.group.partyPowerHeight),
        "showSolo", false,
        "showPlayer", true,
        "groupBy",  "ASSIGNEDROLE",
        "groupingOrder", "TANK,HEALER,DAMAGER,NONE",
        "sortMethod", "NAME",
        "showParty", true,
        "showRaid", true,
        "xOffset",  R.PixelPerfect(0),
        "yOffset",  R.PixelPerfect(-58),
        "point", "TOP"
    )
    -- Anchor the header to our party anchor frame
    partyHeader:SetPoint("CENTER", _G["RefineUI_Party"])
    _G["RefineUI_Party"]:SetSize(C.group.partyWidth, C.group.partyHealthHeight * 5 + 7 * 4)
    R.PixelSnap(partyHeader)
end)

-- Create anchors
local party = CreateFrame("Frame", "RefineUI_Party", UIParent)
party:SetPoint(unpack(C.position.unitframes.party))
R.PixelSnap(party)

-- Rely on oUF header attributes for child layout; no manual repositioning is needed



----------------------------------------------------------------------------------------
-- Expose CreateTargetFrame function
----------------------------------------------------------------------------------------
UF.CreatePartyFrame = CreatePartyFrame
