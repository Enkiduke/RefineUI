----------------------------------------------------------------------------------------
-- ActionBars EditMode
-- Description: Edit Mode settings registration and hotkey refresh helpers.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local type = type

local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12
local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS = NUM_STANCE_SLOTS or 10

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function RefreshHotkeysForBar(barKey)
    local prefix = private.BAR_KEY_TO_PREFIX[barKey]
    if not prefix then
        return
    end

    local db = ActionBars.db
    local enabled = db and db.ShowHotkeys and db.ShowHotkeys[barKey] == true
    local count = (barKey == "PetActionBar") and NUM_PET_ACTION_SLOTS
        or (barKey == "StanceBar") and NUM_STANCE_SLOTS
        or (barKey == "ExtraAction") and 1
        or NUM_ACTIONBAR_BUTTONS

    for index = 1, count do
        local button = _G[prefix .. index]
        local hotkey = button and (button.HotKey or _G[prefix .. index .. "HotKey"])
        if hotkey then
            if enabled then
                if button.UpdateHotkeys then
                    button:UpdateHotkeys(button.buttonType)
                elseif button.SetHotkeys then
                    button:SetHotkeys()
                end
            end
            private.ApplyHotkeyVisibility(button, hotkey)
        end
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:RegisterEditModeSettings()
    local lib = RefineUI.LibEditMode
    if not lib or self.editModeRegistered or not lib.SettingType or type(lib.AddSystemSettings) ~= "function" then
        return
    end

    self.editModeRegistered = true

    local actionBarSystem = Enum.EditModeSystem.ActionBar or 1
    local definitions = {
        { frame = MainActionBar, index = 1, name = "MainMenuBar" },
        { frame = MultiBarBottomLeft, index = 2, name = "MultiBarBottomLeft" },
        { frame = MultiBarBottomRight, index = 3, name = "MultiBarBottomRight" },
        { frame = MultiBarRight, index = 4, name = "MultiBarRight" },
        { frame = MultiBarLeft, index = 5, name = "MultiBarLeft" },
        { frame = MultiBar5, index = 6, name = "MultiBar5" },
        { frame = MultiBar6, index = 7, name = "MultiBar6" },
        { frame = MultiBar7, index = 8, name = "MultiBar7" },
        { frame = StanceBar, index = 11, name = "StanceBar" },
        { frame = PetActionBar, index = 12, name = "PetActionBar" },
        { frame = ExtraAbilityContainer, system = Enum.EditModeSystem.ExtraAbilities, name = "ExtraAction" },
    }

    local settingType = lib.SettingType
    local db = self.db

    for _, definition in ipairs(definitions) do
        if definition.frame then
            local barKey = definition.name

            lib:AddSystemSettings(definition.system or actionBarSystem, {
                {
                    kind = settingType.Checkbox,
                    name = "Show Hotkeys",
                    default = false,
                    get = function()
                        return db and db.ShowHotkeys and db.ShowHotkeys[barKey] == true
                    end,
                    set = function(_, value)
                        if not db then
                            return
                        end
                        if not db.ShowHotkeys then
                            db.ShowHotkeys = {}
                        end
                        db.ShowHotkeys[barKey] = value and true or false
                        RefreshHotkeysForBar(barKey)
                    end,
                },
            }, definition.index)
        end
    end
end
