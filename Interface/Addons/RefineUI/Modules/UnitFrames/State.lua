----------------------------------------------------------------------------------------
-- UnitFrames Component: State
-- Description: Shared constants, registries, and runtime state for UnitFrames.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local ipairs = ipairs
local wipe = table.wipe
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local UNITFRAME_STATE_REGISTRY = "UnitFramesState"
local UNITFRAME_DATA_REGISTRY = "UnitFramesData"
local MAX_BOSS_FRAMES = 5

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
UnitFrames.Private = UnitFrames.Private or {}
local Private = UnitFrames.Private

Private.Constants = Private.Constants or {
    MAX_BOSS_FRAMES = MAX_BOSS_FRAMES,
    BOSS_HEALTH_WIDTH = 126,
    BOSS_HEALTH_HEIGHT = 20,
    BOSS_MANA_WIDTH = 134,
    BOSS_MANA_HEIGHT = 10,
    PET_FRAME_WIDTH = 120,
    PET_FRAME_HEIGHT = 49,
    PET_BORDER_WIDTH = 256,
    PET_BORDER_HEIGHT = 64,
    PET_BORDER_X = 0,
    PET_BORDER_Y = -14,
    PET_HEALTH_WIDTH = 62,
    PET_HEALTH_HEIGHT = 26,
    PET_HEALTH_X = -19,
    PET_HEALTH_Y = -10,
    POWER_TYPE_MANA = Enum.PowerType.Mana,
    TEXTURE_FRAME = Media.Textures.Frame,
    TEXTURE_FRAME_SMALL = Media.Textures.FrameSmall,
    TEXTURE_FRAME_PET = Media.Textures.PetFrame or [[Interface\AddOns\RefineUI\Media\Textures\PortraitOff-Pet.blp]],
    TEXTURE_BACKGROUND = Media.Textures.HealthBackground,
    MASK_FRAME = Media.Textures.FrameMask,
    MASK_HEALTH = Media.Textures.MaskHealth,
    MASK_MANA = Media.Textures.MaskMana,
    TEXTURE_HEALTH_BAR = Media.Textures.HealthBar,
    TEXTURE_POWER_BAR = Media.Textures.PowerBar,
    TEXTURE_SECONDARY_MANA_OVERLAY = Media.Textures.Smooth or [[Interface\Buttons\WHITE8x8]],
}

Private.Runtime = Private.Runtime or {
    runtimeEventsRegistered = false,
    runtimeHooksRegistered = false,
}

Private.PendingStaticStyleFrames = Private.PendingStaticStyleFrames or setmetatable({}, { __mode = "k" })
Private.FrameList = Private.FrameList or {}

local FrameData = RefineUI:CreateDataRegistry(UNITFRAME_DATA_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
function UnitFrames:GetPrivate()
    return Private
end

function UnitFrames:GetFrameData(frame)
    if not frame then
        return nil
    end

    local data = FrameData[frame]
    if not data then
        data = {}
        FrameData[frame] = data
    end
    return data
end

function UnitFrames:GetState(owner, key, defaultValue)
    return RefineUI:RegistryGet(UNITFRAME_STATE_REGISTRY, owner, key, defaultValue)
end

function UnitFrames:SetState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(UNITFRAME_STATE_REGISTRY, owner, key)
        return
    end

    RefineUI:RegistrySet(UNITFRAME_STATE_REGISTRY, owner, key, value)
end

function UnitFrames:IsBossUnit(unit)
    return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

function UnitFrames:GetBossFrameForUnit(unit)
    if not self:IsBossUnit(unit) then
        return nil
    end

    local unitIndex = unit:match("^boss(%d+)$")
    if not unitIndex then
        return nil
    end

    return _G["Boss" .. unitIndex .. "TargetFrame"]
end

function UnitFrames:AddBossFrames(frameList)
    local function TryAdd(frame)
        if not frame then
            return
        end

        for _, existing in ipairs(frameList) do
            if existing == frame then
                return
            end
        end

        frameList[#frameList + 1] = frame
    end

    if BossTargetFrameContainer and BossTargetFrameContainer.BossTargetFrames then
        for _, bossFrame in ipairs(BossTargetFrameContainer.BossTargetFrames) do
            TryAdd(bossFrame)
        end
        return
    end

    for index = 1, MAX_BOSS_FRAMES do
        TryAdd(_G["Boss" .. index .. "TargetFrame"])
    end
end

function UnitFrames:GetManagedFrames()
    local frameList = Private.FrameList
    wipe(frameList)

    if PlayerFrame then
        frameList[#frameList + 1] = PlayerFrame
    end
    if TargetFrame then
        frameList[#frameList + 1] = TargetFrame
    end
    if FocusFrame then
        frameList[#frameList + 1] = FocusFrame
    end
    if PetFrame then
        frameList[#frameList + 1] = PetFrame
    end

    self:AddBossFrames(frameList)
    return frameList
end

function UnitFrames:QueueStaticStyle(frame)
    if not frame then
        return
    end

    Private.PendingStaticStyleFrames[frame] = true
end
