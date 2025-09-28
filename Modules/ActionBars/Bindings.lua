local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Binding buttons(ncHoverBind by Nightcracker)
----------------------------------------------------------------------------------------
local bind, oneBind, localmacros = CreateFrame("Frame", "HoverBind", UIParent), true, 0

SlashCmdList.MOUSEOVERBIND = function()
	if InCombatLockdown() then
		print("|cffffff00" .. ERR_NOT_IN_COMBAT .. "|r")
		return
	end
	if not bind.loaded then
		bind:SetFrameStrata("DIALOG")
		bind:EnableMouse(true)
		bind:EnableKeyboard(true)
		bind:EnableMouseWheel(true)
		bind.texture = bind:CreateTexture()
		bind.texture:SetPoint("TOPLEFT", bind, 2, -2)
		bind.texture:SetPoint("BOTTOMRIGHT", bind, -2, 2)
		bind.texture:SetColorTexture(1, 1, 1, 0.3)
		bind:Hide()

		local elapsed = 0
		GameTooltip:HookScript("OnUpdate", function(self, e)
			elapsed = elapsed + e
			if elapsed < 0.2 then return else elapsed = 0 end
			if not self.comparing and IsModifiedClick("COMPAREITEMS") then
				GameTooltip_ShowCompareItem(self)
				self.comparing = true
			elseif self.comparing and not IsModifiedClick("COMPAREITEMS") then
				for _, frame in pairs(self.shoppingTooltips) do
					frame:Hide()
				end
				self.comparing = false
			end
		end)

		hooksecurefunc(GameTooltip, "Hide", function(self) for _, tt in pairs(self.shoppingTooltips) do tt:Hide() end end)

		bind:SetScript("OnEnter", function()
			GameTooltip:SetOwner(bind, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOM", bind, "TOP", 0, 2)
			GameTooltip:AddLine(bind.button.name, 1, 1, 1)

			if #bind.button.bindings == 0 then
				GameTooltip:AddLine(L_BIND_NO_SET, 0.6, 0.6, 0.6)
			else
				GameTooltip:AddDoubleLine(L_BIND_BINDING, L_BIND_KEY, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
				for i = 1, #bind.button.bindings do
					GameTooltip:AddDoubleLine(i, bind.button.bindings[i])
				end
			end
			GameTooltip:Show()
		end)

		bind:SetScript("OnEvent", function(self) self:Deactivate(false) end)
		bind:SetScript("OnLeave", function(self) self:HideFrame() end)
		bind:SetScript("OnKeyDown", function(self, key) self:Listener(key) end)
		bind:SetScript("OnMouseDown", function(self, key) self:Listener(key) end)
		bind:SetScript("OnMouseWheel",
			function(self, delta) if delta > 0 then self:Listener("MOUSEWHEELUP") else self:Listener("MOUSEWHEELDOWN") end end)

		function bind:Update(b, spellmacro)
			if not self.enabled or InCombatLockdown() then return end
			self.button = b
			self.spellmacro = spellmacro

			self:ClearAllPoints()
			self:SetAllPoints(b)
			self:Show()

			ShoppingTooltip1:Hide()

			if spellmacro == "SPELL" then
                local SpellBook_GetSpellBookSlot = rawget(_G, 'SpellBook_GetSpellBookSlot') or C_SpellBook and C_SpellBook.GetSpellBookItemIndex
                local GetSpellBookItemName = rawget(_G, 'GetSpellBookItemName') or C_SpellBook and C_SpellBook.GetSpellBookItemName
                local sbf = rawget(_G, 'SpellBookFrame')
                local bookType = (sbf and sbf.bookType) or (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player)
                if SpellBook_GetSpellBookSlot and GetSpellBookItemName then
                    self.button.id = SpellBook_GetSpellBookSlot(self.button)
                    self.button.name = GetSpellBookItemName(self.button.id, bookType)
                end

				GameTooltip:Show()
				GameTooltip:SetScript("OnHide", function(self)
					self:SetOwner(bind, "ANCHOR_NONE")
					self:SetPoint("BOTTOM", bind, "TOP", 0, 1)
					self:AddLine(bind.button.name, 1, 1, 1)
					bind.button.bindings = { GetBindingKey(spellmacro .. " " .. bind.button.name) }
					if #bind.button.bindings == 0 then
						self:AddLine(L_BIND_NO_SET, 0.6, 0.6, 0.6)
					else
						self:AddDoubleLine(L_BIND_BINDING, L_BIND_KEY, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
						for i = 1, #bind.button.bindings do
							self:AddDoubleLine(i, bind.button.bindings[i])
						end
					end
					self:Show()
					self:SetScript("OnHide", nil)
				end)
			elseif spellmacro == "MACRO" then
				self.button.id = self.button.selectionIndex or self.button:GetID()

				if localmacros == 1 then self.button.id = self.button.id + MAX_ACCOUNT_MACROS end

				self.button.name = GetMacroInfo(self.button.id)

				GameTooltip:SetOwner(bind, "ANCHOR_NONE")
				GameTooltip:SetPoint("BOTTOM", bind, "TOP", 0, 1)
				GameTooltip:AddLine(bind.button.name, 1, 1, 1)

				bind.button.bindings = { GetBindingKey(spellmacro .. " " .. bind.button.name) }
				if #bind.button.bindings == 0 then
					GameTooltip:AddLine(L_BIND_NO_SET, 0.6, 0.6, 0.6)
				else
					GameTooltip:AddDoubleLine(L_BIND_BINDING, L_BIND_KEY, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
					for i = 1, #bind.button.bindings do
						GameTooltip:AddDoubleLine(i, bind.button.bindings[i], 1, 1, 1)
					end
				end
				GameTooltip:Show()
			elseif spellmacro == "STANCE" or spellmacro == "PET" then
				self.button.id = tonumber(b:GetID())
				self.button.name = b:GetName()

				if not self.button.name then return end

				if not self.button.id or self.button.id < 1 or self.button.id > (spellmacro == "STANCE" and 10 or 12) then
					self.button.bindstring = "CLICK " .. self.button.name .. ":LeftButton"
				else
					self.button.bindstring = (spellmacro == "STANCE" and "SHAPESHIFTBUTTON" or "BONUSACTIONBUTTON") ..
					self.button.id
				end

				GameTooltip:Show()
				GameTooltip:SetScript("OnHide", function(self)
					self:SetOwner(bind, "ANCHOR_NONE")
					self:SetPoint("BOTTOM", bind, "TOP", 0, 1)
					self:AddLine(bind.button.name, 1, 1, 1)
					bind.button.bindings = { GetBindingKey(bind.button.bindstring) }
					if #bind.button.bindings == 0 then
						self:AddLine(L_BIND_NO_SET, 0.6, 0.6, 0.6)
					else
						self:AddDoubleLine(L_BIND_BINDING, L_BIND_KEY, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
						for i = 1, #bind.button.bindings do
							self:AddDoubleLine(i, bind.button.bindings[i])
						end
					end
					self:Show()
					self:SetScript("OnHide", nil)
				end)
			else
				self.button.action = tonumber(b.action)
				self.button.name = b:GetName()

				if not self.button.name then return end

				if not self.button.action or self.button.action < 1 or self.button.action > 132 then
					self.button.bindstring = "CLICK " .. self.button.name .. ":LeftButton"
				else
					local modact = 1 + (self.button.action - 1) % 12
					if self.button.name == "ExtraActionButton1" then
						self.button.bindstring = "EXTRAACTIONBUTTON1"
					elseif self.button.action < 13 or self.button.action > 72 then
						self.button.bindstring = "ACTIONBUTTON" .. modact
					elseif self.button.action < 73 and self.button.action > 60 then
						self.button.bindstring = "MULTIACTIONBAR1BUTTON" .. modact
					elseif self.button.action < 61 and self.button.action > 48 then
						self.button.bindstring = "MULTIACTIONBAR2BUTTON" .. modact
					elseif self.button.action < 49 and self.button.action > 36 then
						self.button.bindstring = "MULTIACTIONBAR4BUTTON" .. modact
					elseif self.button.action < 37 and self.button.action > 24 then
						self.button.bindstring = "MULTIACTIONBAR3BUTTON" .. modact
					elseif self.button.action < 25 and self.button.action > 12 then
						self.button.bindstring = "CLICK " .. self.button.name .. ":LeftButton"
					end
				end

				bind.button.bindings = { GetBindingKey(bind.button.bindstring) }
				bind:GetScript("OnEnter")()
			end
		end

		function bind:Listener(key)
			if GetBindingKey(key) == "OPENCHAT" then
				DEFAULT_CHAT_FRAME.editBox:Show()
				return
			end
			if GetBindingByKey(key) == "SCREENSHOT" then
				RunBinding("SCREENSHOT")
				return
			end
			if #self.button.bindings > 0 and oneBind then
				for i = 1, #self.button.bindings do
					SetBinding(self.button.bindings[i])
				end
				self:Update(self.button, self.spellmacro)
				if self.spellmacro ~= "MACRO" then GameTooltip:Hide() end
			end
			if key == "ESCAPE" or key == "RightButton" then
				for i = 1, #self.button.bindings do
					SetBinding(self.button.bindings[i])
				end
				print("|cffffff00" .. L_BIND_CLEARED .. "|r" .. " |cff00ff00" .. self.button.name .. "|r|cffffff00.|r")
				self:Update(self.button, self.spellmacro)
				if self.spellmacro ~= "MACRO" then GameTooltip:Hide() end
				return
			end

			if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT"
				or key == "RALT" or key == "UNKNOWN" or key == "LeftButton" then
				return
			end
			if key == "MiddleButton" then key = "BUTTON3" end
			if key:find("Button%d") then key = key:upper() end

			local alt = IsAltKeyDown() and "ALT-" or ""
			local ctrl = IsControlKeyDown() and "CTRL-" or ""
			local shift = IsShiftKeyDown() and "SHIFT-" or ""

			if not self.spellmacro or self.spellmacro == "PET" or self.spellmacro == "STANCE" then
				SetBinding(alt .. ctrl .. shift .. key, self.button.bindstring)
			else
				SetBinding(alt .. ctrl .. shift .. key, self.spellmacro .. " " .. self.button.name)
			end
			print(alt .. ctrl .. shift .. key .. " |cff00ff00bound to |r" .. self.button.name .. ".")
			self:Update(self.button, self.spellmacro)
			if self.spellmacro ~= "MACRO" then GameTooltip:Hide() end
		end

		function bind:HideFrame()
			self:ClearAllPoints()
			self:Hide()
			GameTooltip:Hide()
		end

		function bind:Activate()
			self.enabled = true
			self:RegisterEvent("PLAYER_REGEN_DISABLED")
            if C.actionbars.enable then
				if C.actionbars.bottombars_mouseover == true then
                    local fn = rawget(_G, 'BottomBarMouseOver'); if fn then fn(1) end
				end
				if C.actionbars.rightbars_mouseover == true then
                    local fn = rawget(_G, 'RightBarMouseOver'); if fn then fn(1) end
				end
				if C.actionbars.stancebar_mouseover == true then
                    local fn = rawget(_G, 'StanceBarMouseOver'); if fn then fn(1) end
				end
				if C.actionbars.petbar_mouseover == true and C.actionbars.petbar_horizontal == true then
                    local fn = rawget(_G, 'PetBarMouseOver'); if fn then fn(1) end
				end
				if C.actionbars.bar7_enable and C.actionbars.bar7_mouseover then
                    local fn = rawget(_G, 'Bar7MouseOver'); if fn then fn(1) end
				end
				if C.actionbars.bar8_enable and C.actionbars.bar8_mouseover then
                    local fn = rawget(_G, 'Bar8MouseOver'); if fn then fn(1) end
				end
			end
		end

		function bind:Deactivate(save)
			local which = GetCurrentBindingSet()
			if save then
				SaveBindings(which)
				print("|cffffff00" .. L_BIND_SAVED .. "|r")
			else
				LoadBindings(which)
				print("|cffffff00" .. L_BIND_DISCARD .. "|r")
			end
			self.enabled = false
			self:HideFrame()
			self:UnregisterEvent("PLAYER_REGEN_DISABLED")
			StaticPopup_Hide("KEYBIND_MODE")
            if C.actionbars.enable then
				if C.actionbars.bottombars_mouseover == true then
                    local fn = rawget(_G, 'BottomBarMouseOver'); if fn then fn(0) end
				end
				if C.actionbars.rightbars_mouseover == true then
                    local fn = rawget(_G, 'RightBarMouseOver'); if fn then fn(0) end
				end
				if C.actionbars.stancebar_mouseover == true and C.actionbars.stancebar_horizontal == true and C.actionbars.stancebar_hide ~= true then
                    local fn = rawget(_G, 'StanceBarMouseOver'); if fn then fn(C.actionbars.stancebar_mouseover_alpha) end
				end
				if C.actionbars.petbar_mouseover == true and C.actionbars.petbar_horizontal == true then
                    local fn = rawget(_G, 'PetBarMouseOver'); if fn then fn(0) end
				end
				if C.actionbars.bar7_enable and C.actionbars.bar7_mouseover then
                    local fn = rawget(_G, 'Bar7MouseOver'); if fn then fn(0) end
				end
				if C.actionbars.bar8_enable and C.actionbars.bar8_mouseover then
                    local fn = rawget(_G, 'Bar8MouseOver'); if fn then fn(0) end
				end
			end
		end

		StaticPopupDialogs.KEYBIND_MODE = {
			text = L_BIND_INSTRUCT,
			button1 = APPLY,
			button2 = CANCEL,
			OnAccept = function()
				bind:Deactivate(true)
				ReloadUI()
			end,
			OnCancel = function() bind:Deactivate(false) end,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = false,
			preferredIndex = 5,
		}

		-- Registering
		for i = 1, 12 do
			local b = _G["ActionButton" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			b = _G["MultiBarBottomLeftButton" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			b = _G["MultiBarLeftButton" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			b = _G["MultiBarRightButton" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			b = _G["MultiBarBottomRightButton" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			b = _G["MultiBar5Button" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			local b = _G["MultiBar6Button" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)

			local b = _G["MultiBar7Button" .. i]
			b:HookScript("OnEnter", function(self) bind:Update(self) end)
		end

		for i = 1, 10 do
			local b = _G["StanceButton" .. i]
			if b then
				b:HookScript("OnEnter", function(self) bind:Update(self, "STANCE") end)
			else
				return
			end
		end

		for i = 1, NUM_PET_ACTION_SLOTS do
			local b = _G["PetActionButton" .. i]
			if b then
				b:HookScript("OnEnter", function(self) bind:Update(self, "PET") end)
			else
				return
			end
		end

		for i = 1, 12 do
			local b = _G["SpellButton" .. i]
			if b then
				b:HookScript("OnEnter", function(self) bind:Update(self, "SPELL") end)
			else
				return
			end
		end

		ExtraActionButton1:HookScript("OnEnter", function(self) bind:Update(self) end)

        local function registermacro()
            if bind._macroHooksInstalled then return end
            if not MacroFrame then
                -- Defer until Macro UI loads
                if not bind._macroHookFrame then
                    local f = CreateFrame("Frame")
                    f:RegisterEvent("ADDON_LOADED")
                    f:SetScript("OnEvent", function(_, ev, addon)
                        if addon == "Blizzard_MacroUI" then
                            registermacro()
                            f:UnregisterAllEvents()
                            bind._macroHookFrame = nil
                        end
                    end)
                    bind._macroHookFrame = f
                end
                return
            end

            -- Safely hook MacroFrame update to wire hover binding over macro list entries
            if type(MacroFrame.Update) == "function" then
                hooksecurefunc(MacroFrame, "Update", function(frame)
                    local list = frame and frame.MacroSelector and frame.MacroSelector.ScrollBox and frame.MacroSelector.ScrollBox.ScrollTarget
                    if not list then return end
                    if list.EnumerateChildren then
                        for child in list:EnumerateChildren() do
                            local button = child
                            if button and not button.hook then
                                button:HookScript("OnEnter", function(self) bind:Update(button, "MACRO") end)
                                button.hook = true
                            end
                        end
                    else
                        for _, button in next, { list:GetChildren() } do
                            if button and not button.hook then
                                button:HookScript("OnEnter", function(self) bind:Update(button, "MACRO") end)
                                button.hook = true
                            end
                        end
                    end
                end)
            end
            if MacroFrameTab1 then MacroFrameTab1:HookScript("OnMouseUp", function() localmacros = 0 end) end
            if MacroFrameTab2 then MacroFrameTab2:HookScript("OnMouseUp", function() localmacros = 1 end) end
            bind._macroHooksInstalled = true
        end

        registermacro()
    end
    bind.loaded = 1
end
