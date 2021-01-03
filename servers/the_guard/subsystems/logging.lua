-- ################################################
-- #       The Guard  logging  subsystem          #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

-- todo: add logging actions

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local fs = require("filesystem")
local gml = require("gml")

local LOG_DIRECTORY = "/tmp/the_guard/logs"
local GUI_LOG_SIZE = 30
local DEFAULT_FORMAT = "NORMAL"

local logging = {}
local Logger = {}
local loggersConfiguration = {}
local guiElements = {}
local preGUIMessages = {}

local levels = {
    ERROR = {
        color = 0xff0000
    },
    WARN = {
        color = 0xffff00
    },
    INFO = {
        color = 0xffffff
    },
    DEBUG = {
        color = 0x6666ff
    }
}

local formats = {
    NORMAL = function (time, level, source, text) -- 12:04 DEBUG [source]: text
		return time .. " " .. level .. " [" .. source .. "]: " .. text
	end,
	SHORT = function (time, level, source, text) -- 12:04 D: source/text
		return time .. " " .. string.sub(level, 1, 1) .. ": " .. source .. "/" .. text
	end,
	SQUARE = function (time, level, source, text) -- 12:04[D] >source<  text
		return time .. "[" .. string.sub(level, 1, 1) .. "] >" .. source .. "<  " .. text
	end,
	PRETTY = function (time, level, source, text) -- 12:04 /D >> source | text
		return time .. " /" .. string.sub(level, 1, 1) .. " >> " .. source .. " | " .. text
	end
}

---

local function openLoggerFile(name)
	if not fs.isDirectory(LOG_DIRECTORY) then
		fs.makeDirectory(LOG_DIRECTORY)
	end

	local fullPath = fs.concat(LOG_DIRECTORY, name .. ".log")
	return io.open(fullPath, "w")
end

local function createLogger(name, logMessageListener)
	local obj = {
		name = name,
		logMessageListener = logMessageListener,
		handle = openLoggerFile(name)
	}

	setmetatable(obj, Logger)
	Logger.__index = Logger

	return obj
end

local function resolvePlaceholders(template, placeholderValues)
	local resultString = template
	for _, replacement in pairs(placeholderValues) do
		if type(replacement) ~= "string" then replacement = tostring(replacement) end
		resultString = resultString:gsub("{}", replacement, 1)
	end
	return resultString
end

---

local function showLogDetails(subsystem, element)
	local text = element:getSelected()
	if not text then return end

	local maxLines = 30
	local lines = {}
	for s in text:gmatch("[^\r\n]+") do
		if #lines == maxLines then break end
		local trimmed = s:sub(1, 104)
		table.insert(lines, trimmed)
	end
	
	local dgui = gml.create("center", "center", 110, #lines + 6)
	dgui.style = subsystem.api.getStyle()
	dgui:addLabel("center", 1, 12, "Log details")
	dgui:addButton(95, #lines + 4, 10, 1, "Close", function() dgui:close() end)

	for i, line in ipairs(lines) do
		dgui:addLabel(3, i + 2, 104, line)
	end

	dgui:run()
end

local function showFullScreenLogs(subsystem)
	local fgui = gml.create("center", "center", 130, 40)
	fgui.style = subsystem.api.getStyle()
	fgui:addLabel("center", 1, 4, "Logs")
	fgui:addButton(120, 38, 8, 1, "Close", function () fgui:close() end)

	local list = {}
	for i = 1, #guiElements.logbox.list do
		table.insert(list, guiElements.logbox.list[i])
	end

	local listbox = fgui:addListBox(2, 3, 126, 34, list)
	listbox.onDoubleClick = function (element) showLogDetails(subsystem, element) end

	fgui:run()
end

local function showSettings(subsystem)
	local availableFormats = {}
	for f, _ in pairs(formats) do
		availableFormats[f] = f
	end

	local editor = subsystem.subsystems.settings:createSubsystemSettingsEditor(subsystem, "config")
	editor:setMinimumSize(45, nil)

	local formatPreviewLabel = nil
	local updateFormatPreviewLabel = function (chosenFormat)
		local format = formats[chosenFormat]
		if not format then error("nil format: " .. tostring(chosenFormat)) end
		local exampleText = format("10:00:00", "INFO", "source", "example text")
		formatPreviewLabel.text = exampleText
		formatPreviewLabel:draw()
	end

	local formatProperty = editor:addSelectProperty("format", "Log format", availableFormats, DEFAULT_FORMAT, {required = true})
	formatProperty.selectedOptionUpdatedListener = function (newValue)
		local format = availableFormats[newValue]
		updateFormatPreviewLabel(format)
	end

	editor:addPropertySeparator()
	editor:addPropertySeparator()
	editor:addPropertySeparator()
	
	local updated, properties = editor:show("Logging settings", function (gui)
		gui:addLabel(2, 5, 15, "Format preview:")
		formatPreviewLabel = gui:addLabel(2, 6, 40, "")
		local formatValue = editor.manager:getValue("format") or DEFAULT_FORMAT
		updateFormatPreviewLabel(formatValue)
	end)
	
	if updated then
		subsystem:updateLoggersConfiguration(properties)
	end
end

---

function Logger:error(source, message, ...)
    self:log("ERROR", source, message, ...)
end

function Logger:warn(source, message, ...)
    self:log("WARN", source, message, ...)
end

function Logger:info(source, message, ...)
    self:log("INFO", source, message, ...)
end

function Logger:debug(source, message, ...)
    self:log("DEBUG", source, message, ...)
end

function Logger:log(level, source, message, ...)
	local messageText = nil
	local placeholderValues = {...}
	if #placeholderValues > 0 then
		messageText = resolvePlaceholders(message, placeholderValues)
	else
		messageText = message
	end

	local time = os.date():sub(-8)
	local fullSource = self.name .. " - " .. source
	
	local result = loggersConfiguration.format(time, level, fullSource, messageText)
	self.handle:write(result .. "\n")

	self.logMessageListener(levels[level], result)
end

function Logger:close()
	self.handle:close()
	self.handle = nil
end

-------

function logging:initialize()
	self:updateLoggersConfiguration()
    return true
end

function logging:cleanup()
	-- todo: use weak reference to keep track of all loggers and to clean them
end

function logging:updateLoggersConfiguration(config)
	if not config then
		config = self.subsystems.settings:loadSubsystemSettings(self, "config")
	end
	loggersConfiguration.format = formats[config.format or DEFAULT_FORMAT]
end

function logging:createUI(window)
	local startY = 41
    window:addLabel(142, startY + 0, 11, ">> LOGS <<")
	guiElements.logbox = window:addListBox(2, startY + 0, 135, 8, {})
	guiElements.logbox.onDoubleClick = function (element) showLogDetails(self, element) end
	window:addButton(140, startY + 4, 16, 1, "Full screen", function() showFullScreenLogs(self) end)
	window:addButton(140, startY + 6, 16, 1, "Settings", function () showSettings(self) end)
end

function logging:setGUIMode(enabled)
	local prevMode = self.guiMode
	self.guiMode = not not enabled

	if self.guiMode and prevMode ~= self.guiMode then
		while #preGUIMessages > GUI_LOG_SIZE do
			table.remove(preGUIMessages, 1)
		end
		guiElements.logbox:updateList(preGUIMessages)
		guiElements.logbox:select(#preGUIMessages)
		preGUIMessages = {}
	end
end

function logging:createLogger(loggerName)
	return createLogger(loggerName, function (level, message) self:onLogMessage(level, message) end)
end

function logging:onLogMessage(level, message)
	if not self.guiMode then
		local prev = nil
		if level.color then
			prev = component.gpu.setForeground(level.color)
		end
		print(message)
		if level.color then
			component.gpu.setForeground(prev)
		end
		table.insert(preGUIMessages, message)
	else
		local list = guiElements.logbox.list
		table.insert(list, message)
		while #list > GUI_LOG_SIZE do
			table.remove(list, 1)
		end
		guiElements.logbox:updateList(list)
	end
end

return logging