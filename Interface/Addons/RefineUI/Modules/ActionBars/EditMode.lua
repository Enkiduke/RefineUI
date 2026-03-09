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
        or NUM_ACTIONBAR_BUTTONS

    for index = 1, count do
        local button = _G[prefix .. index]
        if button then
            local hotkey = button.HotKey or _G[prefix .. index .. "HotKey"]
            if hotkey then
                if enabled then
                    if button.UpdateHotkeys then
                        button:UpdateHotkeys(button.buttonType)
                    elseif button.SetHotkeys then
                        button:SetHotkeys()
                    end
                    hotkey:ClearAllPoints()
                    RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -4)
                    RefineUI.Font(hotkey, 11, nil, "THINOUTLINE")
                    hotkey:SetAlpha(1)
                    hotkey:Show()
                else
                    hotkey:SetAlpha(0)
                    hotkey:Hide()
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:RegisterEditModeSettings()
    if not RefineUI.LibEditMode or self.editModeRegistered then
        return
    end

    self.editModeRegistered = true
    self.SystemFrames = {}

    local actionBarSystem = Enum.EditModeSystem.ActionBar
    if not actionBarSystem then
        actionBarSystem = 1
    end

    local definitions = {
        { frame = MainActionBar, system = actionBarSystem, index = 1, name = "MainMenuBar" },
        { frame = MultiBarBottomLeft, system = actionBarSystem, index = 2, name = "MultiBarBottomLeft" },
        { frame = MultiBarBottomRight, system = actionBarSystem, index = 3, name = "MultiBarBottomRight" },
        { frame = MultiBarRight, system = actionBarSystem, index = 4, name = "MultiBarRight" },
        { frame = MultiBarLeft, system = actionBarSystem, index = 5, name = "MultiBarLeft" },
        { frame = MultiBar5, system = actionBarSystem, index = 6, name = "MultiBar5" },
        { frame = MultiBar6, system = actionBarSystem, index = 7, name = "MultiBar6" },
        { frame = MultiBar7, system = actionBarSystem, index = 8, name = "MultiBar7" },
        { frame = StanceBar, system = actionBarSystem, index = 11, name = "StanceBar" },
        { frame = PetActionBar, system = actionBarSystem, index = 12, name = "PetActionBar" },
    }

    if not RefineUI.EditModeRegistrations then
        RefineUI.EditModeRegistrations = {}
    end

    for _, definition in ipairs(definitions) do
        local bar = definition.frame
        if bar and definition.system then
            if not self.SystemFrames[definition.system] then
                self.SystemFrames[definition.system] = {}
            end

            local mapKey = definition.index or "Base"
            self.SystemFrames[definition.system][mapKey] = bar

            local registrationKey = definition.system .. "-" .. mapKey
            if not RefineUI.EditModeRegistrations[registrationKey] then
                RefineUI.EditModeRegistrations[registrationKey] = true
            end

            local lib = RefineUI.LibEditMode
            if lib and lib.SettingType and type(lib.AddSystemSettings) == "function" then
                local settingType = lib.SettingType
                local barKey = definition.name
                local db = self.db

                lib:AddSystemSettings(definition.system, {
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
end
