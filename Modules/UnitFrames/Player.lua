local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
local UF = R.UF

-- Upvalues
local unpack = unpack

----------------------------------------------------------------------------------------
-- Player Frame Creation
----------------------------------------------------------------------------------------
local function CreatePlayerFrame(self)
    -- Configure base unit frame
    UF.ConfigureUnitFrame(self)
    -- Create frame elements
    UF.CreateHealthBar(self)
    UF.CreatePowerBar(self)
    UF.CreatePortraitAndCastIcon(self)
    UF.CreateCastBar(self)
    UF.CreateClassResources(self)
    UF.CreateDebuffs(self)
    UF.CreateRaidTargetIndicator(self)
    UF.CreateExperienceBar(self)
    -- Note: BuffWatch is ONLY for party/raid frames, not player frame
    return self
end

----------------------------------------------------------------------------------------
-- Player Frame Initialization
----------------------------------------------------------------------------------------
-- Register and set the player frame style
oUF:RegisterStyle('RefineUI_Player', CreatePlayerFrame)
oUF:SetActiveStyle('RefineUI_Player')

-- Spawn the player frame
local player = oUF:Spawn("player", "RefineUI_Player", UIParent)

-- Set frame size and position
R.SetPixelSize(player, R.frameWidth, R.frameHeight)
player:SetPoint(unpack(C.position.unitframes.player))
R.PixelSnap(player)

----------------------------------------------------------------------------------------
-- Expose CreatePlayerFrame function
----------------------------------------------------------------------------------------
UF.CreatePlayerFrame = CreatePlayerFrame