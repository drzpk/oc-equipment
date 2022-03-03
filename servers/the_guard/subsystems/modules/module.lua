-- ################################################
-- #       The Guard  modules subsystem           #
-- #                                              #
-- #  01.2021                by: Dominik Rzepka   #
-- ################################################

local fs = require("filesystem")

-- todo: modules should be stripped down only to required properties when they aren't enabled
local Module = {}

function Module:load(moduleFile)
    local segments = fs.segments(moduleFile)
    self.logger:debug("module", "Loading module " .. segments[#segments])

    local compiled, errorMessage = loadfile(moduleFile)
    if not compiled then
        self.logger:error("module", "Error while parsing module {}: {}", moduleFile, errorMessage)
        return nil, ("parsing error: " .. errorMessage)
    end

    local status, executable = self.subsystem.api.tryCatch(self.subsystem, compiled)
    if not status then return nil end

    local module = {}
    setmetatable(module, self)
    self.__index = self

    if not executable.name or type(executable.name) ~= "string" or #executable.name == 0 then
        self.logger:error("module", "Module {} is missing a name", moduleFile)
        return nil, "name is missing"
    end

    module.name = executable.name
	module.executable = executable

    local validationMessages = module:_validate()
    if #validationMessages > 0 then
        for _, message in pairs(validationMessages) do
            self.logger:error("validator", "Error while validating module {}: {}", module.name, message)
        end
        return nil, validationMessages[1]
    end

    return module
end

function Module:activate()
	-- todo: registering events (inject a function into the module object)
    local function starter()
        self.executable.start(self.subsystem.api)
    end
	local status, err = self.subsystem.api.tryCatch(self.subsystem, starter, true)
	if not status then
		return false, err
	end

	return true
end

function Module:deactivate()
	-- todo: unregister all events
	self.subsystem.api.tryCatch(self.subsystem, self.executable.stop)
end

function Module:_validate()
	local messages = {}
    local function msg(value)
        table.insert(messages, value)
	end
	
	local mod = self.executable

    if type(mod.version) ~= "string" or #mod.version == 0 then
        msg("missing version")
    end
    if mod.id then
        msg("id was removed in the_guard 3")
    end
    if type(mod.apiLevel) ~= "number" then
        msg("missing api level")
    end
    if mod.apiLevel and mod.apiLevel > self.subsystem.api.apiLevel then
        msg("too old server version")
    end
    if type(mod.setUI) ~= "function" then
        msg("missing setUI() function")
    end
    if type(mod.start) ~= "function" then
        msg("missing start() function")
    end
    if type(mod.stop) ~= "function" then
        msg("missing stop() function")
    end
    if type(mod.pullEvent) ~= "function" then
        msg("missing pullEvent() function")
    end
    return messages
end

function Module:createGUI(window)
    local status, err = self.subsystem.api.tryCatch(self.subsystem, function () self.executable.createUI(window) end)
    return status
end

return Module
