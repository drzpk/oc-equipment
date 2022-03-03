-- ################################################
-- #       The Guard  modules subsystem           #
-- #                                              #
-- #  01.2021                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["gml"] = nil
package.loaded["subsystems/modules/gui_proxy"] = nil
package.loaded["subsystems/modules/module"] = nil
package.loaded["common/utils"] = nil

local fs = require("filesystem")
local uni = require("unicode")
local gml = require("gml")
local GuiProxy = require("subsystems/modules/gui_proxy")
local Module = require("subsystems/modules/module")
local utils = require("common/utils")

local MODULES_DIR = "/usr/bin/the_guard/modules"
local TEST_MODULES_DIR = "/usr/bin/the_guard/test_modules"
local SETTINGS_NAME = "modules"


---

local modules = {
    modules = { -- available modules (Module object)
        visible = {}, -- modules visible on screen (keys: 1 - upper left, 2 - upper right, 3 - lower left, 4 - lower right)
        active = {}, -- all active modules (including visible, key: module name)
		available = {}, -- all available modules (including active, key: module name)
		corrupted = {} -- [module name] = {error: "error message"}
    },
	configuration = {  -- configuration written to file
		modules = { -- list of known modules
			-- [module name] = { active = boolean, slot = number | nil}
		}
	}
}

---

function modules:_activateModule(moduleName)
	self.logger:info("activator", "Activating module {}", moduleName)
	if self.modules.active[moduleName] then
		self.logger:debug("activator", "Module {} is already active", moduleName)
		return true
	end

	local module = self.modules.available[moduleName]
	if module then
		local status, err = module:activate()
		if status then
			self.modules.active[moduleName] = module
			return true
		else
			self.logger:error("activator", "Error while activating module: " .. err)
			self.modules.corrupted[moduleName] = {
				error = err
			}
		end
	else
		self.logger:warn("activator", "Module {} wasn't found", moduleName)
		return false
	end
end

function modules:_deactivateModule(moduleName)
	self.logger:info("deactivator", "Deactivating module {}", moduleName)

	if not self.modules.active[moduleName] then
		self.logger:debug("deactivator", "Module {} isn't active", moduleName)
		return true
	end

	local module = self.modules.active[moduleName]
	module:deactivate()
	self.modules.active[moduleName] = nil

	return true
end

function modules:_showModule(moduleName, slotNo)
	self.logger:info("showModule", "Showing module " .. moduleName)
	if not self.modules.active[moduleName] then
		self.logger:warn("showModule", "An attempt was made to show inactive module " .. moduleName)
		return false
	end

	self:_hideModule(moduleName, nil, true, true)

	local moduleCurrentlyInSlot = self.modules.visible[slotNo]
	if moduleCurrentlyInSlot then
		if moduleCurrentlyInSlot.name == moduleName then
			return true
		else
			self:_hideModule(moduleCurrentlyInSlot.name, slotNo, true)
		end
	end

	local module = self.modules.active[moduleName]
	if not module then
		self.logger:error("showModule", "Module {} wasn't found", moduleName)
		return false
	end

	self.modules.visible[slotNo] = module
	local status, err = self.guiProxy:putModuleInSlot(slotNo, module)
	if not status then
		self.logger:error("showModule", "Error while showing module in slot: {}", err)
	end

	self:_saveConfiguration()
	return true
end

function modules:_hideModule(moduleName, slotNo, skipUpdatingConfiguration, silent)
	if not silent then
		self.logger:info("hideModule", "Hiding module " .. moduleName)
	end

	if not slotNo then
		for currentSlot, module in pairs(self.modules.visible) do
			if module.name == moduleName then
				slotNo = currentSlot
				break
			end
		end
	end

	if not slotNo then
		if not silent then
			self.logger:warn("hideModule", "Module {} cannot be hidden because it isn't visible in slot {}", moduleName, slotNo)
		end
		return false
	end

	self.modules.visible[slotNo] = nil
	self.guiProxy:clearSlot(slotNo)
	self:_saveConfiguration(skipUpdatingConfiguration)
	return true
end

function modules:_getSlot(moduleName)
	for slot, module in pairs(self.modules.visible) do
		if module.name == moduleName then
			return slot
		end
	end

	return nil
end

function modules:_showModuleManger()
	local changes = {} -- [moduleName] = {active: true}
	local managedModules = {}
	local managedModulesDisplay = {}
	local selectedModuleIndex = nil

	local listBox = nil
	local nameLabel = nil
	local versionLabel = nil
	local apiLevelLabel = nil
	local slotLabel = nil
	local errorLabel = nil
	local activationButton = nil

	local function refreshManagedModules()
		-- 1. modName 1.2.3 active
		managedModules = {}
		managedModulesDisplay = {}

		local index = 1
		for _, module in pairs(self.modules.available) do
			local isActive = self.modules.active[module.name]
			if changes[module.name] then
				isActive = changes[module.name].active
			end

			local slot = self:_getSlot(module.name)
			local item = {
				name = module.name,
				version = module.executable.version,
				apiLevel = module.executable.apiLevel,
				slot = slot and tostring(slot) or "",
				active = isActive
			}
			table.insert(managedModules, item)

			local line = string.format("%d. %s %s %s", index, module.name, module.executable.version, isActive and "active" or "inactive")
			table.insert(managedModulesDisplay, line)
			index = index + 1
		end

		for name, corrupted in pairs(self.modules.corrupted) do
			local item = {
				name = name,
				error = corrupted.error
			}
			table.insert(managedModules, item)

			local line = string.format("%d. %s inactive", index, name)
			table.insert(managedModulesDisplay, line)
			index = index + 1
		end

		if listBox then
			listBox:updateList(managedModulesDisplay)
			listBox.selectedLabel = nil
			selectedModuleIndex = nil
		end
	end

	local function refreshModuleDetails(lb, prevIndex, selectedIndex)
		local module = managedModules[selectedIndex]
		if not module then
			selectedModuleIndex = nil
			return
		else
			selectedModuleIndex = selectedIndex
		end
		

		if not module.error then
			nameLabel.text = module.name
			versionLabel.text = module.version
			apiLevelLabel.text = tostring(module.apiLevel)
			slotLabel.text = module.slot
			errorLabel.text = ""
			activationButton.text = module.active and "yes" or "no"

			nameLabel:draw()
			versionLabel:draw()
			apiLevelLabel:draw()
			slotLabel:draw()
			errorLabel:draw()
			activationButton:show()
			activationButton:draw()
		else
			nameLabel.text = module.name
			versionLabel.text = ""
			apiLevelLabel.text = ""
			slotLabel.text = ""
			errorLabel.text = "Error: " .. (module.error or "unknown error")

			nameLabel:draw()
			versionLabel:draw()
			apiLevelLabel:draw()
			slotLabel:draw()
			errorLabel:draw()
			activationButton:hide()
		end
	end

	local function changeActiveStatus(btn)
		local module = managedModules[selectedModuleIndex]
		if not module then return end

		local originalStatus = self.modules.active[module.name] ~= nil
		local previousStatus = nil
		if not changes[module.name] then previousStatus = originalStatus else previousStatus = changes[module.name].active end
		local currentStatus = not previousStatus

		if currentStatus == originalStatus then
			changes[module.name] = nil
		else
			changes[module.name] = {
				active = currentStatus
			}
		end

		btn.text = currentStatus and "yes" or "no"
		btn:draw()

		refreshManagedModules()
	end

	refreshManagedModules()

	local mgui = gml.create("center", "center", 90, 24)
	mgui:addLabel("center", 1, 15, "Module manager")
	
	listBox = mgui:addListBox(3, 4, 40, 15, managedModulesDisplay)
	listBox.onChange = refreshModuleDetails

	mgui:addLabel(46, 4, 10, "Name:")
	mgui:addLabel(46, 5, 10, "Version:")
	mgui:addLabel(46, 6, 10, "API Level:")
	mgui:addLabel(46, 7, 10, "Slot:")
	mgui:addLabel(46, 9, 10, "Active:")

	nameLabel = mgui:addLabel(57, 4, 30, "")
	versionLabel = mgui:addLabel(57, 5, 30, "")
	apiLevelLabel = mgui:addLabel(57, 6, 30, "")
	slotLabel = mgui:addLabel(57, 7, 30, "")
	errorLabel = mgui:addLabel(46, 11, 40, "")

	activationButton = mgui:addButton(57, 9, 10, 1, "", changeActiveStatus)
	activationButton:hide()

	mgui:addButton(55, 21, 14, 1, "Apply", function () mgui:close() end)
	mgui:addButton(71, 21, 14, 1, "Close", function ()
		changes = nil
		mgui:close()
	end)

	mgui:run()
	
	return changes
end

function modules:_showSlotManager(slotNo)
	local clearSlotLabel = "<clear slot>"
	local moduleNames = {clearSlotLabel}
	local indexToSelect = nil
	local apply = false

	local index = 1
	local nameInCurrentSlot = self.modules.visible[slotNo] and self.modules.visible[slotNo].name or nil
	for name, _ in pairs(self.modules.active) do
		table.insert(moduleNames, name)

		if nameInCurrentSlot == name then
			indexToSelect = index
		end
		index = index + 1
	end

	local sgui = gml.create("center", "center", 41, 20)
	sgui:addLabel("center", 1, 26, "Select a module for slot " .. tostring(slotNo))
	local listbox = sgui:addListBox(3, 3, 36, 10, moduleNames)
	sgui:addButton(5, 17, 13, 1, "Apply", function ()
		apply = true
		sgui:close()
	end)
	sgui:addButton(20, 17, 13, 1, "Cancel", function () sgui:close() end)

	if indexToSelect then
		listbox:select(indexToSelect)
	end

	sgui:run()
	if not apply then return end

	local newModuleName = listbox:getSelected()
	if newModuleName == nameInCurrentSlot then return end

	if newModuleName and newModuleName ~= clearSlotLabel then
		self:_showModule(newModuleName, slotNo)
	elseif nameInCurrentSlot ~= nil then
		self:_hideModule(nameInCurrentSlot)
	end
end

---

function modules:initialize()
	self.modulesLogger = self.subsystems.logging:createLogger("modules")
	Module.subsystem = self
	Module.logger = self.logger
	self:_loadConfiguration()
    return true
end

function modules:cleanup() end

function modules:createUI(rootGui)
	Module.guiProxy = GuiProxy:create(self, rootGui)
	self.guiProxy = Module.guiProxy

	for slot, module in pairs(self.modules.visible) do
		self.logger:debug("gui", "Creating gui for module " .. module.name)
		local status = module:createGUI()
		if not status then
			self.logger:error("gui", "Error while creating gui for module {}, the module will be hidden", module.name)
			-- todo: maybe display an error message in the module slot
			self.modules.visible[slot] = nil
		end
	end

	local buttonBackground = 0x0000dd -- todo: extract this color from button background style
	for slotNo, position in pairs(GuiProxy.SLOTS) do
		local x = position[1] + GuiProxy.SLOT_SIZE[1] - 1
		local y = position[2]
		local label = rootGui:addLabel(x, y, 1, "+")
		label.style["text-background"] = buttonBackground

		local ref = self
		label.onClick = function () ref:_showSlotManager(slotNo) end
	end
end

function modules:loadModules()
    local function load(directory)
        local counter = 0
        for f in fs.list(directory) do
			local fullPath = fs.concat(directory, f)
            local module, errorMessage = Module:load(fullPath)
            if module then
				self.modules.available[module.name] = module
				counter = counter + 1
			else
				self.modules.corrupted[f] = {
					error = errorMessage
				}
            end
        end

        return counter
    end

    local counter = load(MODULES_DIR)
    self.logger:info("loader", "Loaded {} modules", counter)

    if self.api.debugMode then
        local counter = load(TEST_MODULES_DIR)
        self.logger:info("loader", "Loaded {} test modules", counter)
    end
end

function modules:launchModules()
	self.logger:info("launcher", "Launching modules")
 
	local modulesToDeactivate = {}
    for moduleName, moduleConfig in pairs(self.configuration.modules) do
		if moduleConfig.active then	
			local status = self:_activateModule(moduleName)
			if not status then
				table.insert(modulesToDeactivate, moduleName)
			end

			if moduleConfig.slot ~= nil then
				self:_showModule(moduleName, moduleConfig.slot)
			end
		else
			self.logger:debug("launcher", "Module {} is inactive", moduleName)
		end
	end

	if #modulesToDeactivate > 0 then
		for _, name in pairs(modulesToDeactivate) do
			self.configuration.modules[name].active = false
			self.configuration.modules[name].slot = nil
		end

		self:_saveConfiguration(true)
	end
end

function modules:showModuleManager()
	local changes = self:_showModuleManger()

	if changes then
		for name, change in pairs(changes) do
			if change.active then
				self:_activateModule(name)
			else
				self:_deactivateModule(name)
			end
		end

		self:_saveConfiguration()
	end
end

function modules:_loadConfiguration()
	self.configuration = self.subsystems.settings:loadSubsystemSettings(self, SETTINGS_NAME)
	self.configuration.modules = self.configuration.modules or {}

	-- Check the configuration
	for name, moduleConfig in pairs(self.configuration.modules) do
		local ok = true
		if type(moduleConfig.active) ~= "boolean" then
			self.logger:error("config", "Module {}: active state is incorrect ({})", name, moduleConfig.active)
			ok = false
		elseif type(moduleConfig.slot) ~= "nil" and (type(moduleConfig.slot) ~= "number" or moduleConfig.slot < 1 or moduleConfig.slot > 4) then
			self.logger:error("config", "Module {}: wrong slot ({})", name, moduleConfig.slot)
			ok = false
		end

		if not ok then
			self.configuration.modules[name] = nil
		end
	end
end

function modules:_saveConfiguration(skipUpdating)
	self.logger:debug("save", "Saving configuration")
	if not skipUpdating then
		self:_updateConfiguration()
	end
	
	self.subsystems.settings:saveSubsystemSettings(self, SETTINGS_NAME, self.configuration)
end

function modules:_updateConfiguration()
	local modulesConfig = {}

	for name, module in pairs(self.modules.available) do
		local config = {
			active = false,
			slot = nil
		}
		modulesConfig[name] = config
	end

	for name, _ in pairs(self.modules.active) do
		modulesConfig[name].active = true
	end

	for slot, module in pairs(self.modules.visible) do
		modulesConfig[module.name].slot = slot
	end

	self.configuration.modules = modulesConfig
end


return modules