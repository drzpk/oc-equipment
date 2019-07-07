-- ############################################
-- #				mod_tg_logs				  #
-- #										  #
-- #  03.2016			   by:Dominik Rzepka  #
-- ############################################

--[[
	## Description ##
		The mod_tg_logs program is a module used by the_guard server (since 2.0).
		It allows to create and manage action-driven logs.
		
	## Actions ##
		- logInfo(text:string, source:string) - information log
		- logWarning(text:string, source:string) - warning log
		- logError(text:string, source:string) - error log
		- logSevere(text:string, source:string) - severe error log
		- logDebug(text:string, source:string) - debug log
		
	## Functions ##
		* managing action-driven logs
		* opening detailed log view
		* adjustable buffer size
]]
local version = "1.2"
local args = {...}

if args[1] == "version_check" then return version end

local gml = require("gml")
local fs = require("filesystem")

-- # Zmienne lokalne
local config = {}
local logbox = nil
local list = {}
local lc = {}
local max_items = 20
local buffer = {}
local server = nil
local mod = nil

-- # Logi
local levels = {
	[1] = {
		title = "SEVERE",
		color = 0xff00cc
	},
	[2] = {
		title = "ERROR",
		color = 0xff0000
	},
	[3] = {
		title = "WARNING",
		color = 0xffff00
	},
	[4] = {
		title = "INFO",
		color = 0x000000
	},
	[5] = {
		title = "DEBUG",
		color = 0x00ff00
	}
}

local formats = {
	[1] = {"normal", function(time, level, title, text) -- 12:04 DEBUG: title/text
		return time .. " " .. levels[level].title .. ": " .. title .. "/" .. text
	end},
	[2] = {"short", function(time, level, title, text) -- 12:04 D: title/text
		return time .. " " .. string.sub(levels[level].title, 1, 1) .. ": " .. title .. "/" .. text
	end},
	[3] = {"square", function(time, level, title, text) -- 12:04[D] >title<  text
		return time .. "[" .. string.sub(levels[level].title, 1, 1) .. "] >" .. title .. "<  " .. text
	end},
	[4] = {"pretty", function(time, level, title, text) -- 12:04 /D >> title | text
		return time .. " /" .. string.sub(levels[level].title, 1, 1) .. " >> " .. title .. " | " .. text
	end}
}

-- # Action handling
local function flushLog()
	if config.nosave then
		buffer = {}
		return
	end
	
	local file, e = io.open("/tmp/mod_tg_logs.log", "r")
	if file then
		local buf = file:read("*a")
		file:close()
		if math.ceil(buf:len() / 1024) > config.file then
			fs.remove("/tmp/mod_tg_logs.log")
		end
	end
	
	local text = ""
	for _, s in pairs(buffer) do
		text = text .. s .. "\n"
	end
	
	file, e = io.open("/tmp/mod_tg_logs.log", "a")
	if file then
		file:write(text)
		file:close()
	else
		server.log("log file couldn't be saved: " .. e)
	end
	buffer = {}
end

local function refreshList(l)
	l:updateList(list)
	for i, l in pairs(l.labels) do
		if lc[i] then
			l["fill-color-fg"] = lc[i]
		end
	end
	l:draw()
end

local function doLog(level, text, source)
	if config.level < level then return end
	if #list >= max_items then
		pcall(table.remove, list, 1)
		pcall(table.remove, lc, 1)
	end
	local msg = formats[config.form][2](os.date():sub(-8), level, source, text)
	table.insert(list, msg)
	table.insert(buffer, msg)
	lc[#list] = levels[level].color
	if #buffer > config.buffer then flushLog() end
	refreshList(logbox)
end

local function logSevere(text, source)
	return doLog(1, text, source)
end

local function logError(text, source)
	return doLog(2, text, source)
end

local function logWarning(text, source)
	return doLog(3, text, source)
end

local function logInfo(text, source)
	return doLog(4, text, source)
end

local function logDebug(text, source)
	return doLog(5, text, source)
end

local actions = {
	[1] = {
		name = "logInfo",
		type = "LOG",
		desc = "Information log",
		p1type = "string",
		p2type = "string",
		p1desc = "log content",
		p2desc = "log source",
		exec = logInfo
	},
	[2] = {
		name = "logWarning",
		type = "LOG",
		desc = "Warning log",
		p1type = "string",
		p2type = "string",
		p1desc = "log content",
		p2desc = "log source",
		exec = logWarning
	},
	[3] = {
		name = "logError",
		type = "LOG",
		desc = "Error log",
		p1type = "string",
		p2type = "string",
		p1desc = "log content",
		p2desc = "log source",
		exec = logError
	},
	[4] = {
		name = "logSevere",
		type = "LOG",
		desc = "Severe error log",
		p1type = "string",
		p2type = "string",
		p1desc = "log content",
		p2desc = "log source",
		exec = logSevere
	},
	[5] = {
		name = "logDebug",
		type = "LOG",
		desc = "Debug log",
		p1type = "string",
		p2type = "string",
		p1desc = "log content",
		p2desc = "log source",
		exec = logDebug,
		hidden = true
	}
}

-- # GUI functions
local function settings()
	local sgui = gml.create("center", "center", 55, 13)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Settings")
	local bl = sgui:addLabel(2, 4, 40, "Maximum buffer size [B](10~120):")
	bl.hidden = config.nofile
	local bf = sgui:addTextField(43, 4, 10)
	bf.hidden = config.nofile
	bf.visible = false
	bf.text = tostring(config.buffer)
	local fl = sgui:addLabel(2, 5, 38, "Maximum log file size [kB](2~50):")
	fl.hidden = config.nofile
	local ff = sgui:addTextField(43, 5, 10)
	ff.hidden = config.nofile
	ff.visible = false
	ff.text = tostring(config.file)
	sgui:addLabel(2, 3, 22, "Save log to file:")
	local button = sgui:addButton(24, 3, 10, 1, config.nosave and "NO" or "YES", function(t)
		t.status = not t.status
		if t.status then
			t.text = "NO"
			bl:hide()
			bf.visible = true
			bf:hide()
			fl:hide()
			ff.visible = true
			ff:hide()
		else
			t.text = "YES"
			bf.text = tostring(config.buffer)
			ff.text = tostring(config.file)
			bl:show()
			bf:show()
			fl:show()
			ff:show()
		end
		t:draw()
	end)
	button.status = config.nosave
	sgui:addLabel(2, 7, 13, "Log level:")
	sgui:addLabel(2, 8, 13, "Log style:")
	sgui:addButton(16, 7, 12, 1, tostring(config.level) .. ". " .. levels[config.level].title, function (t)
		config.level = config.level < #levels and config.level + 1 or 1
		t.text = tostring(config.level) .. ". " .. levels[config.level].title
		t:draw()
	end)
	local example = sgui:addLabel(4, 9, 30, "")
	local exbutton = nil
	local function refreshEx()
		if exbutton.status > #formats then exbutton.status = 1 end
		if formats[exbutton.status] then
			exbutton.text = formats[exbutton.status][1]
			example.text = formats[exbutton.status][2](os.date():sub(-8), 5, "title", "text")
		else
			example.text = "ERROR"
		end
		exbutton:draw()
		example:draw()
	end
	exbutton = sgui:addButton(16, 8, 12, 1, formats[config.form][1], function(t)
		t.status = t.status + 1
		refreshEx()
	end)
	exbutton.status = config.form
	refreshEx()
	sgui:addButton(39, 11, 14, 1, "Cancel", function() sgui:close() end)
	sgui:addButton(23, 11, 14, 1, "OK", function()
		local b = tonumber(bf.text)
		local f = tonumber(ff.text)
		if not b or b > 120 or b < 10 then
			server.messageBox(mod, "Buffer size is incorrect.", {"OK"})
		elseif not f or f > 50 or f < 2 then
			server.messageBox(mod, "Log file size is incorrect.", {"OK"})
		else
			config.form = exbutton.status
			config.nosave = button.status
			config.buffer = b
			config.file = f
			sgui:close()
		end
	end)
	sgui:run()
end

local function logDetails(l)
	local text = l:getSelected()
	if not text then return end
	local index = 0
	for i, s in pairs(list) do
		if s == text then
			index = i
			break
		end
	end
	local color	= 0
	if index ~= 0 and lc[index] then
		color = lc[index]
	end
	--l["fill-color-fg"] = lc[i]
	
	local dgui = gml.create("center", "center", 110, 8)
	dgui.style = server.getStyle(mod)
	dgui:addLabel(2, 3, 104, text:sub(1, 102))
	dgui:addButton(94, 6, 14, 1, "Close", function() dgui:close() end)
	dgui:run()
end

local function bigLogs()
	local bgui = gml.create("center", "center", 90, 28)
	bgui.style = server.getStyle(mod)
	bgui:addLabel("center", 1, 5, "LOGS")
	local l = bgui:addListBox(2, 3, 84, 20, {})
	l.onDoubleClick = function() logDetails(l) end
	refreshList(l)
	bgui:addButton(74, 26, 14, 1, "Close", function() bgui:close() end)
	bgui:addButton(58, 26, 14, 1, "Refresh", function() refreshList(l) end)
	bgui:run()
end

-- # Module table
mod = {}

mod.name = "logs"
mod.version = version
mod.id = 52
mod.apiLevel = 3
mod.shape = "landscape"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel(142, 1, 11, ">> LOGS <<")
	logbox = window:addListBox(1, 1, 135, 8, list)
	logbox.onDoubleClick = function() logDetails(logbox) end
	window:addButton(140, 4, 16, 1, "Settings", settings)
	window:addButton(140, 6, 16, 1, "Log window", bigLogs)
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	if not config.form or type(config.form) ~= "number" or config.form < 1 or config.form > #formats then
		config.form = 1
	end
	if not config.buffer or type(config.buffer) ~= "number" or config.buffer < 10 or config.buffer > 120 then
		config.buffer = max_items
	end
	if not config.file or type(config.file) ~= "number" or config.file < 2 or config.file > 50 then
		config.file = 10
	end
	if type(config.nosave) ~= "nil" or type(config.nosave) ~= "boolean" then
		config.nosave = false
	end
	if type(config.level) ~= "number" or config.level < 1 or config.level > 5 then
		config.level = 4
	end
end

mod.stop = function(core)
	core.saveConfig(mod, config)
end

mod.pullEvent = function(...)

end

return mod