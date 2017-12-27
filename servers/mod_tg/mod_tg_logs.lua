-- ############################################
-- #				mod_tg_logs				  #
-- #										  #
-- #  03.2016					by:IlynPayne  #
-- ############################################

--[[
	## Opis programu ##
		Program mod_tg_logs jest modułem używanym w serwerze the_guard (od wersji 2.0).
		Pozwala na tworzenie i zarządzanie logami systemowymi.
		
	## Akcje ##
		- logInfo(text:string, source:string) - log informacyjny
		- logWarning(text:string, source:string) - log ostrzegawczy
		- logError(text:string, source:string) - log sygnalizujący błąd
		- logSevere(text:string, source:string) - log oznaczający poważny błąd
		- logDebug(text:string, source:string) - debug log
		
	## Funkcje ##
		* otwieranie większego okna logów
		* ustawianie rozmiaru bufora
		* określanie maksymalnej wielkości pliku
]]
local version = "1.0"
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
		title = "INFO",
		color = 0x000000
	},
	[2] = {
		title = "WARNING",
		color = 0xffff00
	},
	[3] = {
		title = "ERROR",
		color = 0xff0000
	},
	[4] = {
		title = "SEVERE",
		color = 0xff00cc
	},
	[5] = {
		title = "DEBUG",
		color = 0x00ff00
	}
}

local formats = {
	[1] = {"normal", function(time, level, title, text) -- 12:04 DEBUG: tytuł/tekst
		return time .. " " .. levels[level].title .. ": " .. title .. "/" .. text
	end},
	[2] = {"short", function(time, level, title, text) -- 12:04 D: tytuł/tekst
		return time .. " " .. string.sub(levels[level].title, 1, 1) .. ": " .. title .. "/" .. text
	end},
	[3] = {"square", function(time, level, title, text) -- 12:04[D] >tytuł<  tekst
		return time .. "[" .. string.sub(levels[level].title, 1, 1) .. "] >" .. title .. "<  " .. text
	end},
	[4] = {"pretty", function(time, level, title, text) -- 12:04 /D >> tytuł | tekst
		return time .. " /" .. string.sub(levels[level].title, 1, 1) .. " >> " .. title .. " | " .. text
	end}
}

-- # Obsługa akcji
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
		server.log("nie udało się zapisać logów: " .. e)
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

local function logInfo(text, source)
	return doLog(1, text, source)
end

local function logWarning(text, source)
	return doLog(2, text, source)
end

local function logError(text, source)
	return doLog(3, text, source)
end

local function logSevere(text, source)
	return doLog(4, text, source)
end

local function logDebug(text, source)
	return doLog(5, text, source)
end

local actions = {
	[1] = {
		name = "logInfo",
		type = "LOG",
		desc = "Log informacyjny",
		p1type = "string",
		p2type = "string",
		p1desc = "treść logu",
		p2desc = "źródło logu",
		exec = logInfo
	},
	[2] = {
		name = "logWarning",
		type = "LOG",
		desc = "Log ostrzegawczy",
		p1type = "string",
		p2type = "string",
		p1desc = "treść logu",
		p2desc = "źródło logu",
		exec = logWarning
	},
	[3] = {
		name = "logError",
		type = "LOG",
		desc = "Log sygnalizujący błąd",
		p1type = "string",
		p2type = "string",
		p1desc = "treść logu",
		p2desc = "źródło logu",
		exec = logError
	},
	[4] = {
		name = "logSevere",
		type = "LOG",
		desc = "Log oznaczający poważny błąd",
		p1type = "string",
		p2type = "string",
		p1desc = "treść logu",
		p2desc = "źródło logu",
		exec = logSevere
	},
	[5] = {
		name = "logDebug",
		type = "LOG",
		desc = "DebugLog",
		p1type = "string",
		p2type = "string",
		p1desc = "treść logu",
		p2desc = "źródło logu",
		exec = logDebug,
		hidden = true
	}
}

-- # Funkcje GUI
local function settings()
	local sgui = gml.create("center", "center", 55, 11)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Ustawienia")
	local bl = sgui:addLabel(2, 4, 40, "Maksymalny rozmiar bufora [B](10~120):")
	bl.hidden = config.nofile
	local bf = sgui:addTextField(43, 4, 10)
	bf.hidden = config.nofile
	bf.visible = false
	bf.text = tostring(config.buffer)
	local fl = sgui:addLabel(2, 5, 38, "Maksymalny rozmiar pliku [kB](2~50):")
	fl.hidden = config.nofile
	local ff = sgui:addTextField(43, 5, 10)
	ff.hidden = config.nofile
	ff.visible = false
	ff.text = tostring(config.file)
	sgui:addLabel(2, 3, 22, "Zapisuj log do pliku:")
	local button = sgui:addButton(24, 3, 10, 1, config.nosave and "NIE" or "TAK", function(t)
		t.status = not t.status
		if t.status then
			t.text = "NIE"
			bl:hide()
			bf.visible = true
			bf:hide()
			fl:hide()
			ff.visible = true
			ff:hide()
		else
			t.text = "TAK"
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
	sgui:addLabel(2, 7, 13, "Styl logów:")
	local example = sgui:addLabel(4, 8, 30, "")
	local exbutton = nil
	local function refreshEx()
		if exbutton.status > #formats then exbutton.status = 1 end
		if formats[exbutton.status] then
			exbutton.text = formats[exbutton.status][1]
			example.text = formats[exbutton.status][2](os.date():sub(-8), 5, "tytuł", "tekst")
		else
			example.text = "ERROR"
		end
		exbutton:draw()
		example:draw()
	end
	exbutton = sgui:addButton(16, 7, 12, 1, formats[config.form][1], function(t)
		t.status = t.status + 1
		refreshEx()
	end)
	exbutton.status = config.form
	refreshEx()
	sgui:addButton(39, 9, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(23, 9, 14, 1, "OK", function()
		local b = tonumber(bf.text)
		local f = tonumber(ff.text)
		if not b or b > 120 or b < 10 then
			server.messageBox(mod, "Rozmiar bufora jest niepoprawny", {"OK"})
		elseif not f or f > 50 or f < 2 then
			server.messageBox(mod, "rozmiar pliku jest niepoprawny", {"OK"})
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
	dgui:addButton(94, 6, 14, 1, "Zamknij", function() dgui:close() end)
	dgui:run()
end

local function bigLogs()
	local bgui = gml.create("center", "center", 90, 28)
	bgui.style = server.getStyle(mod)
	bgui:addLabel("center", 1, 5, "LOGI")
	local l = bgui:addListBox(2, 3, 84, 20, {})
	l.onDoubleClick = function() logDetails(l) end
	refreshList(l)
	bgui:addButton(74, 26, 14, 1, "Zamknij", function() bgui:close() end)
	bgui:addButton(58, 26, 14, 1, "Odśwież", function() refreshList(l) end)
	bgui:run()
end

-- # Tablica modułu
mod = {}

mod.name = "logs"
mod.version = version
mod.id = 52
mod.apiLevel = 2
mod.shape = "landscape"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel(142, 1, 11, ">> LOGS <<")
	logbox = window:addListBox(1, 1, 135, 8, list)
	logbox.onDoubleClick = function() logDetails(logbox) end
	window:addButton(140, 4, 16, 1, "Ustawienia", settings)
	window:addButton(140, 6, 16, 1, "Okno logów", bigLogs)
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
end

mod.stop = function(core)
	core.saveConfig(mod, config)
end

mod.pullEvent = function(...)

end

return mod