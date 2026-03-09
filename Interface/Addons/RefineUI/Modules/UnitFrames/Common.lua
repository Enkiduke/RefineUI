----------------------------------------------------------------------------------------
-- UnitFrames Component: Common
-- Description: Shared helpers for hook keys, frame lookup, and guarded re-anchoring.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tostring = tostring
local xpcall = xpcall
local geterrorhandler = geterrorhandler

local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Hook Keys
----------------------------------------------------------------------------------------
function UnitFrames:GetHookOwnerId(owner)
    if type(owner) == "table" and owner.GetName then
        local name = owner:GetName()
        if name and name ~= "" then
            return name
        end
    end

    return tostring(owner)
end

function UnitFrames:BuildHookKey(owner, method)
    return "UnitFrames:" .. self:GetHookOwnerId(owner) .. ":" .. tostring(method)
end

----------------------------------------------------------------------------------------
-- Shared Guards
----------------------------------------------------------------------------------------
function UnitFrames:WithStateGuard(owner, key, fn)
    if not owner or type(fn) ~= "function" then
        return false
    end

    if self:GetState(owner, key, false) then
        return false
    end

    self:SetState(owner, key, true)
    local ok = xpcall(fn, geterrorhandler())
    self:SetState(owner, key, nil)
    return ok
end

----------------------------------------------------------------------------------------
-- Frame Helpers
----------------------------------------------------------------------------------------
function UnitFrames:GetFrameContainers(frame)
    if not frame then
        return nil
    end

    local content = frame.PlayerFrameContent or frame.TargetFrameContent
    if not content then
        return nil
    end

    local contentMain = content.PlayerFrameContentMain or content.TargetFrameContentMain
    if not contentMain then
        return nil
    end

    local hpContainer = contentMain.HealthBarsContainer
    local manaBar = contentMain.ManaBarArea and contentMain.ManaBarArea.ManaBar or contentMain.ManaBar
    return content, contentMain, hpContainer, manaBar
end

function UnitFrames:IsTargetFocusOrBossFrame(frame)
    if not frame then
        return false
    end

    if frame == TargetFrame or frame == FocusFrame then
        return true
    end

    if frame.isBossFrame == true then
        return true
    end

    return self:IsBossUnit(frame.unit)
end

function UnitFrames:EnforceHiddenRegion(region, hiddenFrame)
    if not region then
        return
    end

    region:SetAlpha(0)
    region:Hide()

    if hiddenFrame and not InCombatLockdown() and region.SetParent then
        region:SetParent(hiddenFrame)
    end

    RefineUI:HookOnce(self:BuildHookKey(region, "SetAlpha:Hidden"), region, "SetAlpha", function(selfRegion, alpha)
        if alpha ~= 0 then
            selfRegion:SetAlpha(0)
        end
    end)

    RefineUI:HookOnce(self:BuildHookKey(region, "Show:Hidden"), region, "Show", function(selfRegion)
        selfRegion:Hide()
    end)
end

function UnitFrames:EnsureTooltipHooks(frame)
    if not frame or not Config.UnitFrames.DisableTooltips then
        return
    end

    if self:GetState(frame, "TooltipHooksRegistered", false) then
        return
    end

    RefineUI:HookScriptOnce(self:BuildHookKey(frame, "OnEnter:TooltipGate"), frame, "OnEnter", function(selfFrame)
        if IsShiftKeyDown() then
            return
        end

        if _G.GameTooltip and _G.GameTooltip:IsOwned(selfFrame) then
            _G.GameTooltip:Hide()
        end
    end)

    RefineUI:HookScriptOnce(self:BuildHookKey(frame, "OnLeave:TooltipGate"), frame, "OnLeave", function(selfFrame)
        if _G.GameTooltip and _G.GameTooltip:IsOwned(selfFrame) then
            _G.GameTooltip:Hide()
        end
    end)

    self:SetState(frame, "TooltipHooksRegistered", true)
end
