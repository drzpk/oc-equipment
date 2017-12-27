-- ############################################
-- #				mod_tg_levels			  #
-- #										  #
-- #  03.2016					by:IlynPayne  #
-- ############################################

--[[
	## Opis programu ##
		Program mod_tg_levels jest modułem używanym w serwerze the_guard (od wersji 2.0).
		Pozwala na tworzenie poziomów bezpieczeństwa i odsługę alarmu.
		Program wprowadza 3 poziomy bezpieczeństwa konfigurowane za pomocą akcji.
		
		Włączenie poziomu bezpieczeństwa powoduje wywołanie akcji do niego
		przypisanych, poziom 0 jest domyślnym poziomem oznaczającym brak zagrożenia.
		
	## Akcje ##
		- getLevel() - zwraca obecny poziom bezpieczeństwa
		- setLevel(level:number) - ustawia nowy poziom bezpieczeństwa
		- alarm(timeout:number[, level:number]) - aktywuje alarm; poziom alarmu oznacza używany dźwięk
		- disableAlarm() - wyłącza wcześniej włączony alarm
		
	## Funkcje ##
		* definiowanie do 3 poziomów bezpieczeństwa
		* możliwość przypisania do 10 akcji podczas włączania danego poziomu
		* możliwość przypisania do 10 akcji podczas wyłączania danego poziomu
		* manualne włączanie alarmu
		* ustawienie zasięgu alarmu
]]

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local event = require("event")
local component = require("component")
local gml = require("gml")

local mod = {}
local server = nil
local config = nil

local indicator = {}
local lAlarm = {}
local timerID = nil
local alarms = {
	[1] = "klaxon1",
	[2] = "klaxon2"
}

local function getLevel()
	return config.level
end

local function setLevel(new_level, internal)
	if internal and config.ask then
		if server.messageBox(mod, "Czy na pewno chcesz włączyć poziom " .. tostring(new_level) .. "?", {"Tak", "Nie"}) == "Nie" then return end
	end
	for _, t in pairs(config[config.level].disable) do
		server.call(mod, t.id, t.p1, t.p2, true)
	end
	for _, t in pairs(config[new_level].enable) do
		server.call(mod, t.id, t.p1, t.p2, true)
	end
	config.level = new_level
	server.call(mod, 5201, "Włączono poziom " .. tostring(new_level), "LEVELS", true)
	for i = 0, 3 do
		indicator[i]:draw()
	end
end

local function disableAlarm(silent)
	event.cancel(timerID or 0)
	timerID = nil
	lAlarm[1].text = "wyłączony"
	lAlarm[1]:draw()
	lAlarm[3].text = "0:00"
	lAlarm[3]:draw()
	lAlarm[4].text = "Start"
	lAlarm[4]:draw()
	config.alarm = nil
	
	local ll = server.getComponentList(mod, "os_alarm")
	for _, t in pairs(ll) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.deactivate()
		end
	end
	if not silent then
		server.call(mod, 5201, "Alarm został wyłączony", "LEVELS", true)
	end
end

local function timerFunc()
	config.alarm = config.alarm - 1
	lAlarm[3].text = string.format("%d:%02d", config.alarm / 300, config.alarm % 300)
	lAlarm[3]:draw()
	if config.alarm < 0 then
		disableAlarm()
	end
end

local function enableAlarm(timeout, l)
	if type(timeout) ~= "number" or timeout > 300 or timeout < 3 then
		server.call(mod, 5203, "Wprowadzono nieprawidłowy czas alarmu", "LEVELS", true)
		return
	end
	local sound = l or config.alarmSound
	if sound > 2 or sound < 1 then
		server.call(mod, 5203, "Wprowadzono nieprawidłowy identyfikator dźwięku alarmu", "LEVELS", true)
		return
	end
	lAlarm[1].text = "włączony"
	lAlarm[1]:draw()
	lAlarm[4].text = "Stop"
	lAlarm[4]:draw()
	
	local reenable = false
	if config.alarm then reenable = true end
	config.alarm = timeout
	local ll = server.getComponentList(mod, "os_alarm")
	if #ll > 0 then
		for _, t in pairs(ll) do
			local proxy = component.proxy(t.address)
			if proxy then
				proxy.setRange(config.range)
				proxy.setAlarm(alarms[sound])
				proxy.activate()
			end
		end
	elseif not reenable then
		server.call(mod, 5203, "Nie znaleziono żadnego komponentu alarmu!", "LEVELS", true)
	end
	if not reenable then
		if timerID then
			event.cancel(timerID)
		end
		timerID = event.timer(1, timerFunc, math.huge)
		server.call(mod, 5201, "Alarm został włączony", "LEVELS", true)
	end
end

local function levelSettings(level)
	local lbox, rbox = nil, nil
	local llist, rlist = nil, nil
	
	local function refresh()
		llist = {}
		for i, t in pairs(config[level].enable) do
			local a = server.actionDetails(mod, t.id)
			if a then
				table.insert(llist, a.name .. " (" .. a.type .. ")")
			else
				table.insert(llist, "*" .. tostring(t.id) .. "*")
			end
		end
		lbox:updateList(llist)
		rlist = {}
		for i, t in pairs(config[level].disable) do
			local a = server.actionDetails(mod, t.id)
			if a then
				table.insert(rlist, a.name .. " (" .. a.type .. ")")
			else
				table.insert(rlist, "*" .. tostring(t.id) .. "*")
			end
		end
		rbox:updateList(rlist)
	end
	local function delete(id, enable)
		local l = enable and config[level].enable or config[level].disable
		for i, t in pairs(l) do
			if t.id == id then
				table.remove(l, i)
				return
			end
		end
	end
	local function findID(name)
		local a, amount = server.getActions(mod, nil, nil, name)
		if amount > 0 then
			for i, t in pairs(a) do
				if t.name == name then
					return i
				end
			end
		end
		return nil
	end
	local function details(enable)
		local l = enable and lbox or rbox
		local c = enable and config[level].enable or config[level].disable
		local m1 = l:getSelected():match("^(.*) %(")
		local m2 = l:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				for i, t in pairs(c) do
					if t.id == id then
						local tab = server.actionDialog(mod, nil, nil, c[i])
						c[i] = tab
						refresh()
						return
					end
				end
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				for i, t in pairs(c) do
					if t.id == num then
						local tab = server.actionDialog(mod, nil, nil, c[i])
						c[i] = tab
						refresh()
						return
					end
				end
			end
		end
	end
	
	local lgui = gml.create("center", "center", 70, 25)
	lgui.style = server.getStyle(mod)
	lgui:addLabel("center", 1, 9, "POZIOM " .. tostring(level))
	lgui:addLabel(2, 3, 15, "Nazwa poziomu:")
	local name = lgui:addTextField(18, 3, 20)
	name.text = config[level].name or ""
	lgui:addLabel(4, 5, 17, "Akcje włączania")
	lgui:addLabel(39, 5, 18, "Akcje wyłączania")
	lbox = lgui:addListBox(2, 6, 30, 13, {})
	lbox.onDoubleClick = function() details(true) end
	rbox = lgui:addListBox(37, 6, 30, 13, {})
	rbox.onDoubleClick = function() details(false) end
	lgui:addButton(2, 20, 14, 1, "Dodaj", function()
		if #config[level].enable < 11 then
			local result = server.actionDialog(mod)
			if result then
				table.insert(config[level].enable, result)
				refresh()
			end
		else
			server.messageBox("Dodano już maksymalną ilość akcji", {"OK"})
		end
	end)
	lgui:addButton(18, 20, 14, 1, "Usuń", function()
		if #lbox.list == 0 then return
		elseif server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Nie" then return end
		local m1 = lbox:getSelected():match("^(.*) %(")
		local m2 = lbox:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				delete(id, true)
				refresh()
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				delete(num, true)
				refresh()
			end
		end
	end)
	lgui:addButton(37, 20, 14, 1, "Dodaj", function()
		if #config[level].disable < 11 then
			local result = server.actionDialog(mod)
			if result then
				table.insert(config[level].disable, result)
				refresh()
			end
		else
			server.messageBox("Dodano już maksymalnąilość akcji", {"OK"})
		end
	end)
	lgui:addButton(53, 20, 14, 1, "Usuń", function()
		if #rbox.list == 0 then return
		elseif server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Nie" then return end
		local m1 = rbox:getSelected():match("^(.*) %(")
		local m2 = rbox:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				delete(id, false)
				refresh()
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				delete(num, false)
				refresh()
			end
		end
	end)
	lgui:addButton(53, 23, 14, 1, "Zamknij", function()
		if name.text:len() > 16 then
			server.messageBox(mod, "Nazwa poziomu nie może być dłuższa, niż 16 znaków.", {"OK"})
			return
		end
		config[level].name = name.text
		lgui:close()
	end)
	refresh()
	lgui:run()
end

local function settings()
	local sgui = gml.create("center", "center", 40, 19)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "USTAWIENIA")
	sgui:addLabel(2, 3, 7, "Opcje:")
	sgui:addLabel(4, 4, 9, "Zasięg:")
	sgui:addLabel(4, 5, 23, "Pytaj o potwierdzenie:")
	sgui:addLabel(2, 7, 9, "Poziomy:")
	
	local tRange = sgui:addTextField(14, 4, 6)
	tRange.text = tostring(config.range)
	local ask = sgui:addButton(28, 5, 8, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "nie"
		else
			t.status = true
			t.text = "tak"
		end
		t:draw()
	end)
	ask.status = config.ask
	ask.text = config.ask and "tak" or "nie"
	
	sgui:addButton(4, 8, 12, 1, "> 0 <", function() levelSettings(0) end)
	sgui:addButton(4, 10, 12, 1, "> 1 <", function() levelSettings(1) end)
	sgui:addButton(4, 12, 12, 1, "> 2 <", function() levelSettings(2) end)
	sgui:addButton(4, 14, 12, 1, "> 3 <", function() levelSettings(3) end)
	
	sgui:addButton(24, 16, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(9, 16, 14, 1, "Zatwierdź", function()
		local r = tonumber(tRange.text)
		if not r or r > 150 or r < 15 then
			server.messageBox(mod, "Zasięg musi być liczbą w zakresie 15-150", {"OK"})
		else
			config.range = r
			config.ask = ask.status
			sgui:close()
		end
	end)
	sgui:run()
end

local function synchronize()
	local amount = 0
	for address, _ in component.list("os_alarm") do
		local proxy = component.proxy(address)
		if proxy then
			proxy.setAlarm(alarms[config.alarmSound])
			proxy.setRange(config.range)
			if config.alarm then
				proxy.activate()
			else
				proxy.deactivate()
			end
			amount = amount + 1
		end
	end
	server.call(mod, 5201, "Synchronizacja zakończona. Zsynchronizowano " .. tostring(amount) .. " alarmy/ów", "LEVELS", true)
end

local actions = {
	[1] = {
		name = "getLevel",
		type = "LEVEL",
		desc = "Aktualny poziom bezpieczeństwa",
		exec = getLevel
	},
	[2] = {
		name = "setLevel",
		type = "LEVEL",
		desc = "Ustawia poziom bezpieczeństwa",
		p1type = "number",
		p1desc = "numer poziomu bezpieczeństwa (0-3)",
		exec = setLevel
	},
	[3] = {
		name = "alarm",
		type = "LEVEL",
		desc = "Włącza alarm",
		p1type = "number",
		p2type = "number",
		p1desc = "czas alarmu (3-300)",
		p2desc = "dźwięk alarmu (1-2)",
		exec = enableAlarm
	},
	[4] = {
		name = "disableAlarm",
		type = "LEVEL",
		desc = "Wyłącza alarm",
		exec = disableAlarm
	}
}

mod.name = "levels"
mod.version = version
mod.id = 11
mod.apiLevel = 2
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 13, ">> LEVELS <<")
	window:addButton(6, 4, 30, 3, "> 3." .. (config[3].name and config[3].name:sub(1, 16) or "") .. " <", function() setLevel(3, true) end)
	window:addButton(6, 8, 30, 3, "> 2." .. (config[2].name and config[2].name:sub(1, 16) or "") .. " <", function() setLevel(2, true) end)
	window:addButton(6, 12, 30, 3, "> 1." .. (config[1].name and config[1].name:sub(1, 16) or "") .. " <", function() setLevel(1, true) end)
	window:addButton(6, 16, 30, 3, "> 0.".. (config[0].name and config[0].name:sub(1, 16) or "") .. " <", function() setLevel(0, true) end)
	window:addButton(42, 16, 18, 1, "Ustawienia", settings)
	window:addButton(42, 18, 18, 1, "Synchronizacja", synchronize)
	
	window:addLabel(48, 4, 6, "ALARM")
	window:addLabel(42, 6, 8, "Status:")
	lAlarm[1] = window:addLabel(51, 6, 11, "")
	lAlarm[1].text = config.alarm and "włączony" or "wyłączony"
	window:addLabel(42, 7, 6, "Czas:")
	lAlarm[2] = window:addTextField(49, 7, 5)
	lAlarm[2].text = tostring(config.alarmTime)
	window:addLabel(42, 8, 9, "Dźwięk:")
	window:addButton(52, 8, 8, 1, tostring(config.alarmSound), function(t)
		if config.alarmSound == 1 then
			config.alarmSound = 2
			t.text = "2"
		else
			config.alarmSound = 1
			t.text = "1"
		end
		t:draw()
	end)
	window:addLabel(42, 11, 17, "Pozostały czas:")
	lAlarm[3] = window:addLabel(60, 11, 5, config.alarm and string.format("%d:%02d", config.alarm / 300, config.alarm % 300) or "")
	lAlarm[4] = window:addButton(42, 9, 10, 1, "", function(t)
		if not config.alarm then
			local newtime = tonumber(lAlarm[2].text)
			if not newtime or newtime > 300 or newtime < 3 then
				server.messageBox(mod, "Czas alarmu musi być liczbą w zakresie 3-300 sekund.", {"OK"})
				return
			end
			enableAlarm(newtime)
		else
			disableAlarm()
		end
	end)
	lAlarm[4].text = config.alarm and "Stop" or "Start"
	
	for i = 0, 3 do
		indicator[i] = server.template(mod, window, 2, 5 + (i * 4), 2, 1)
		indicator[i].level = 3 - i
		indicator[i].draw = function(t)
			if config.level == t.level then
				t.renderTarget.setBackground(0x00ff00)
			else
				t.renderTarget.setBackground(0xff0000)
			end
			t.renderTarget.fill(t.posX, t.posY, 2, 1, ' ')
		end
	end
	
	if config.alarm then
		event.timer(2, function() enableAlarm(config.alarm) end)
	end
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	if not config.level or type(config.level) ~= "number" or config.level > 3 or config.level < 0 then
		config.level = 0
	end
	if not config.alarmTime then
		config.alarmTime = 20
	end
	if not config.alarmSound then
		config.alarmSound = 1
	end
	if not config.range or config.range > 150 or config.range < 15 then
		config.range = 20
	end
	if not config.ask then
		config.ask = true
	end
	for i = 0, 3 do
		if not config[i] then
			config[i] = {}
		end
		if not config[i].enable then
			config[i].enable = {}
		else
			for a, b in pairs(config[i].enable) do
				if not b.id then table.remove(config[i].enable, a) end
			end
		end
		if not config[i].disable then
			config[i].disable = {}
		else
			for a, b in pairs(config[i].disable) do
				if not b.id then table.remove(config[i].disable, a) end
			end
		end
	end
	
	core.registerEvent(mod, "component_added")
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	if config.alarm then
		event.cancel(timerID or 0)
		local ll = server.getComponentList(mod, "os_alarm")
		if #ll > 0 then
			for _, t in pairs(ll) do
				local proxy = component.proxy(t.address)
				if proxy then
					proxy.deactivate()
				end
			end
		end
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "component_added" and e[3] == "os_alarm" then
		local proxy = component.proxy(e[2])
		if proxy then
			proxy.setRange(config.range)
			proxy.setAlarm(alarms[config.alarmSound])
			if config.alarm then
				proxy.activate()
			else
				proxy.deactivate()
			end
		end
	end
end

return mod