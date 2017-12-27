-- ############################################
-- #			mod_tg_turrets				  #
-- #										  #
-- #  05.2016					by:IlynPayne  #
-- ############################################

--[[
	## Opis programu ##
		Program mod_tg_turrets jest modułem używanym na serwerze the_guard (od wersji 2.0).
		Pozwala na zarządzanie wieżyczkami i detektorami ruchu.
		
		Wieżyczki pochodzą z moda OpenSecurity.
		Obsługiwane są 2 typy detektorów ruchu:
		* 'motion sensor' z moda OpenComputers
		* 'entity detector' z moda OpenSecurity
		
		Pierwszy z nich jest wykorzystywany do wykrywania ruchu
		i uruchamiania akcji do niego przypisanych.
		Z kolei drugi służy do skanowania otoczenia w pobliżu wieżyczek.
		Odstępy pomiędzy poszczególnymi skanami mogą być zmienione (0.5 - 3s).
		
		Mechanizm wybierania celu może działać w trzech trybach:
		* 1 (none) - atakowane są wszystkie obiekty w zasięgu
		* 2 (white) - atakowane są obiekty nie będące na białej liście
		* 3 (black) - atakowane są obiekty znajdujące się na czarnej liście
		
	## Akcje ##
		- enableTurrets() - włącza wieżyczki
		- disableTurrent() - wyłącza wieżyczki
		- enableSensors() - włącza detektory ruchu
		- disableSensors() - wyłącza detektory ruchu
		- setTurretsMode(mode:number) - ustawia tryb wieżyczek
		- setSensorsMode(mode:number) - ustawia tryb sensorów
		
	## Funkcje ##
		* obsługa wieżyczek (maksymalnie 12)
		* obsługa sensorów ruchu (maksymalnie 12 każdego rodzaju)
		* ustawianie czasu aktywacji wieżyczek (15 sekund - 3 minuty)
		* ustawianie czasu aktywacji sensorów (15 sekund - 3 minuty)
		* każdy sensor obsługuje do 3 akcji włączania i 3 akcji wyłaczania
		* zmiana interwału skanowania (1s - 15s)
		* zmiana zasięgu skanu (5 - 20 bloków)
		* ustawianie czułości sensorów (0.1 - 10)
		
	## Schematy ##
		config { - domyślny plik konfiguracyjny
			turretsState:boolean - czy wieżyczki są aktywne
			sensorsState:boolean - czy sensory są aktywne
			turretsMode:number - tryb mechanizmu wybierania wieżyczek
			sensorsMode:number - tryb mechanizmu wybierania detektorów
			sensitivity:number - czułość sensorów ruchu
			delay:number - odstęp pomiędzy skanami
			range:number - zasięg skanowania
			turretsActive:number - czas aktywacji wieżyczek
			sensorsActive:number - czas aktywacji sensorów
		}
		
		Wszystkie dodatkowe pliki konfiguracyjne będą szyfrowane.
		
		turrets: { - wieżyczki (plik modules/turrets/turrets.dat)
			{
				name:string - nazwa urządzenia
				address:string - adres urządzenia
				detector:string - adres detektora
				upside:boolean - czy jest do góry nogami
				hidden:boolean - czy jest schowana między blokami
				walls: { - obudowanie ścianami
					t:boolean - góra
					b:boolean - dół
					n:boolean - północ
					s:boolean - południe
					e:boolean - wschód
					w:boolean - zachód
				}
			}
			...
		}
		
		sensors: { - detektory ruchu (plik modules/turrets/sensors.dat)
			{
				name:string - nazwa sensora
				address:string - adres urządzenia
				enable { - akcje włączania
					{
						id:number - identyfikator akcji
						p1:any - parametr 1
						p2:any - parametr 2
					}
					...
				}
				disable { - akcje wyłaczania
					{
						id:number - identyfikator akcji
						p1:any - parametr 1
						p2:any - parametr 2
					}
					...
				}
			}
			...
		}
		
		lists: { - listy (plik modules/turrets/lists.dat)
			turrets: {
				black: {
					[1]:string - nazwa obiektu
					...
				}
				white: {
					[1]:string - nazwa obiektu
				}
			}
			sensors: {
				black: {
					[1]:string - nazwa obiektu
				}
				white: {
					[1]:string - nazwa obiektu
				}
			}
		}
		
	## Cache ##
		W celu szybszego wyszukiwania wieżyczek podłączonych do danego
		detektora, moduł wykorzystuje pamięć podręczną do przechowywania adresów:
		cache: {
			{
				[0]: detektor
				[1]: { - wieżyczka
					index:number
					x:number
					y:number
					z:number
				}
				[2]: { - wieżyczka
					index:number
					x:number
					y:number
					z:number
				}
				...
			}
			...
		}
]]

local version = "1.1"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local serial = require("serialization")
local event = require("event")
local fs = require("filesystem")
local gml = require("gml")
local data = component.data

local mod = {}
local server = nil
local config = nil

local turrets = nil
local sensors = nil
local lists = nil
local cache = nil

local timer = nil
local tamount = nil


local excluded = { -- elementy wykluczone ze skanowania
	"Kula doświadczenia",
	"Experience orb",
	"item%..*",
	"item%.item%..*",
	"entity%.opensecurity%..*",
	"entity.sgcraft.Stargate Iris.name"
}
local targetHeight = 0.75 -- wysokość celu
local attemptDelay = 0.2 -- interwał prób strzału
local maxAttempts = 4 -- maksymalna ilość prób strzału
local turretHeight = 0.38


local lbox, rbox, element = nil, nil, {}

local function encrypt(d)
	local s, ser = pcall(serial.serialize, d)
	if s then
		local s, enc = pcall(data.encrypt, ser, server.secretKey(mod), data.md5("turrets"))
		if s then
			local s, b = pcall(data.encode64, enc)
			if s then
				return b
			end
		end
	end
	return nil
end

local function decrypt(d)
	local s, b = pcall(data.decode64, d)
	if s then
		local s, dec = pcall(data.decrypt, b, server.secretKey(mod), data.md5("turrets"))
		if s then
			local s, tab = pcall(serial.unserialize, dec)
			if s then
				return tab
			end
		end
	end
	return nil
end

local function saveData()
	local dir = server.getConfigDirectory(mod)
	
	local function sf(tab, filename)
		local enc = encrypt(tab)
		if enc then
			local f = io.open(fs.concat(dir, filename .. ".dat"), "w")
			if f then
				f:write(enc)
				f:close()
			else
				server.log(mod, "Nie udało się otworzyć pliku " .. filename)
			end
		else
			server.log(mod, "Nie udało się zaszyfrować danych " .. filename)
		end
	end
	
	sf(turrets, "turrets")
	sf(sensors, "sensors")
	sf(lists, "lists")
end

local function loadData()
	local dir = server.getConfigDirectory(mod)
	
	local function lf(filename)
		local path = fs.concat(dir, filename .. ".dat")
		if not fs.exists(path) then return {}
		elseif fs.isDirectory(path) then
			server.log(mod, "Element " .. path .. " nie może być katalogiem!")
		end
		local f = io.open(path, "r")
		if f then
			local d = decrypt(f:read("*a"))
			if d then
				return d
			else
				server.log(mod, "Nie udało się odszyfrować pliku " .. filename)
				return {}
			end
		else
			server.log(mod, "Nie udało się otworzyć pliku.")
		end
	end
	
	turrets = lf("turrets")
	sensors = lf("sensors")
	lists = lf("lists")
end

local function rebuildCache()
	cache = {}
	local detectors = server.getComponentList(mod, "os_entdetector")
	if #detectors == 0 then return end
	local function ca(a)
		return a and type(a) == "number"
	end
	for _, t in pairs(detectors) do
		local d = {t.address}
		for a, t2 in pairs(turrets) do
			if t.address == t2.detector then
				local det = server.findComponents(mod, t2.address)
				if #det > 1 then
					error("Wystąpił błąd w funkcji findComponents")
					return
				elseif #det == 1 and ca(det[1].x) and ca(det[1].y) and ca(det[1].z) then
					local su = {
						index = a,
						x = det[1].x,
						y = det[1].y,
						z = det[1].z
					}
					table.insert(d, su)
				end
			end
		end
		if #d > 1 then
			table.insert(cache, d)
		end
	end
end

local function refreshView()
	if element[1] and element[2] then
		element[1].text = config.turretsState and "włączone" or "wyłączone"
		element[1]:draw()
		element[2].text = config.sensorsState and "włączone" or "wyłączone"
		element[2]:draw()
	end
end

local function rebuildTable(tab, target)
	local f = {}
	local index = 0
	for _, t in pairs(tab) do
		index = index + 1
		table.insert(f, tostring(index) .. ". " .. t.name)
	end
	target:updateList(f)
end

local function getIndex(str)
	local m = tonumber(string.match(str or "", "^(%d)%."))
	return m or 0
end

--[[local function getTurret(addr)
	for _, t in pairs(turrets) do
		if t.address == addr then
			return t
		end
	end
	return nil
end]]

local function openTurret(addr)
	local proxy = component.proxy(addr)
	if not proxy then return end
	proxy.powerOn()
	pcall(proxy.moveTo, 0, 0)
	proxy.extendShaft(0)
	proxy.setArmed(false)
end

local function closeTurret(addr)
	local proxy = component.proxy(addr)
	if not proxy then return end
	pcall(proxy.moveTo, 0, 0)
	proxy.extendShaft(1)
	event.timer(1.5, function() proxy.powerOff() end)
end

local function refreshSensors()
	for _, t in pairs(sensors) do
		local proxy = component.proxy(t.address or "")
		if proxy then
			proxy.setSensitivity(config.sensitivity)
		end
	end
end

local function disableTurrets()
	event.cancel(timer)
	timer = nil
	for _, t in pairs(turrets) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.extendShaft(0)
			proxy.setArmed(false)
		end
	end
	config.turretsState = false
	refreshView()
end

local function calcValues(turret, target)
	local a = target.x - (turret.x + 0.5)
	local b = (turret.z + 0.5) - target.z
	local c = math.sqrt(a * a + b * b)
	local angle = math.floor(math.atan2(a, b) * 180 / math.pi * 10) / 10
	local h = (target.y + targetHeight) - (turret.y + (turret.upside and 1 or 0))
	if turret.hidden and turret.upside then
		h = h - turretHeight
	elseif turret.hidden then
		h = h + turretHeight
	end
	local pitch = math.floor(math.atan(h / c) * 180 / math.pi * 10) / 10
	return angle, pitch
end

local function getEntities(adr)
	local proxy = component.proxy(adr or "")
	if not proxy then return end
	local s, entities = pcall(proxy.scanEntities, config.range)
	if s then
		local removal = {}
		for a, t in pairs(entities) do
			for _, s in pairs(excluded) do
				if t.name:match(s) then
					table.insert(removal, a)
					break
				end
			end
		end
		table.sort(removal, function(a, b) return a > b end)
		for _, b in pairs(removal) do table.remove(entities, b) end
		removal = {}
		if config.turretsMode == 2 then
			--white
			for a, t in pairs(entities) do
				for _, w in pairs(lists.turrets.white) do
					if t.name == w then
						table.insert(removal, a)
						break
					end
				end
			end
		elseif config.turretsMode == 3 then
			--black
			for a, t in pairs(entities) do
				local found = false
				for _, b in pairs(lists.turrets.black) do
					if a.name == b then
						found = true
						break
					end
				end
				if not found then
					table.insert(removal, a)
				end
			end
		end
		table.sort(removal, function(a, b) return a > b end)
		for _, b in pairs(removal) do table.remove(entities, b) end
		table.sort(entities, function(a, b) return a.range < b.range end)
		return entities
	else
		server.call(mod, 5204, "Za mało energii, aby kontynuować skanowanie.", "turrets", true)
		event.cancel(timer)
		timer = nil
		disableTurrets()
		refreshView()
		return
	end
end

local function launch(turret, attempt)
	if attempt == 0 then
		if not turret.isReady() then
			server.call(mod, 5202, "Wieżyczka " .. turret.name .. " ma zbyt wolny czas ochładzania!", "turrets", true)
		end
		return 
	end
	if turret.isOnTarget() and turret.isReady() then
		local s, r = pcall(turret.fire)
		if not s and r == "not enough energy" then
			server.call(mod, 5203, "Brak energii na kontynuację pracy wieżyczek", "turrets", true)
			disableTurrets()
			return
		end
	else
		event.timer(attemptDelay, function() launch(turret, attempt - 1) end)
	end
end

local function turretsLoop()
	if tamount <= 0 then
		disableTurrets()
		return
	end
	tamount = tamount - 1
	
	local function checkYaw(angle, turret)
		if (angle >= -45 and angle <= 0) or (angle >= 0 and angle < 45) then
			return not turret.walls.n
		elseif angle >= 45 and angle < 135 then
			return not turret.walls.e
		elseif (angle >= 135 and angle <= 180) or (angle >= -180 and angle < -135) then
			return not turret.walls.s
		elseif angle >= -135 and angle < -45 then
			return not turret.walls.w
		end
		return false
	end
	local function checkPitch(angle, turret)
		if turret.upside then
			return angle <= 45 and angle >= -90
		else
			return angle >= -45 and angle <= 90
		end
	end
	for _, t in pairs(cache) do
		local entities = getEntities(t[1])
		if entities then
			for i = 2, #t do
				local pointer = t[i]
				local turret = turrets[pointer.index] or {}
				local proxy = component.proxy(turret.address or "")
				if proxy then
					for j = 1, #entities do
						local angle, pitch = calcValues(pointer, entities[j])
						if checkYaw(angle, turret) and checkPitch(pitch, turret) then
							--server.call(mod, 5201, "wykryto: " .. entities[j].name, "turretsLoop", true)
							if not proxy.isPowered() then
								proxy.powerOn()
							end
							proxy.setArmed(true)
							pcall(proxy.moveTo, angle, pitch)
							event.timer(attemptDelay, function() launch(proxy, maxAttempts) end)
							break
						end
					end
				end
			end
		end
	end
end

local function enableTurrets()
	for _, t in pairs(turrets) do
		local proxy = component.proxy(t.address)
		if proxy then
			if not proxy.isPowered() then
				proxy.powerOn()
			end
			if t.hidden then
				proxy.extendShaft(2)
			else
				proxy.extendShaft(1)
			end
			proxy.setArmed(true)
			if not t.walls.n then
				pcall(proxy.moveTo, 0, 0)
			elseif not t.walls.s then
				pcall(proxy.moveTo, 180, 0)
			elseif not t.walls.e then
				pcall(proxy.moveTo, 90, 0)
			elseif not t.walls.w then
				pcall(proxy.moveTo, 270, 0)
			end
		else
			server.call(mod, 5202, "Wieżyczka " .. t.name .. " jest offline.", "turrets", true)
		end
	end
	local amount = nil
	if config.turretsActive == 0 then
		amount = math.huge
	else
		amount = math.ceil(config.turretsActive / config.delay)
	end
	timer = event.timer(config.delay, turretsLoop, math.huge)
	tamount = amount
	config.turretsState = true
	refreshView()
end

local function enableSensors()
	server.registerEvent(mod, "motion")
	config.sensorsState = true
	refreshView()
end

local function disableSensors()
	server.unregisterEvent(mod, "motion")
	config.sensorsState = false
	refreshView()
end

local function listTemplate(item)
	local ret = {}
	ret.black = {}
	ret.white = {}
	if item then
		for a, b in pairs(item.black or {}) do
			ret.black[a] = b
		end
		for a, b in pairs(item.white or {}) do
			ret.white[a] = b
		end
	end
	local lb, rb = nil, nil
	local function refreshLists()
		lb:updateList(ret.black)
		rb:updateList(ret.white)
	end
	local function addDialog()
		local ret = ""
		local agui = gml.create("center", "center", 40, 7)
		agui.style = server.getStyle(mod)
		agui:addLabel("center", 1, 14, "Podaj nazwę:")
		local field = agui:addTextField("center", 3, 24)
		agui:addButton(24, 5, 14, 1, "Anuluj", function()
			ret = nil
			agui:close()
		end)
		agui:addButton(8, 5, 14, 1, "Zatwierdź", function()
			local n = field.text
			if n:len() == 0 then
				server.messageBox(mod, "Wprowadź nazwę.", {"OK"})
			elseif n:len() > 20 then
				server.messageBox(mod, "Dlugość nazwy nie może być dłuższa, niż 20 znaków.", {"OK"})
			else
				ret = n
				agui:close()
			end
		end)
		agui:run()
		return ret
	end
	local function addItem(l)
		if #l > 12 then
			server.messageBox(mod, "Dodano już maksymalną liczbę obiektów.", {"OK"})
			return
		end
		local r = addDialog()
		if not r then return end
		table.insert(l, r)
		refreshLists()
	end
	local function removeItem(l, list)
		local sel = list:getSelected()
		if not sel then return end
		if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Nie" then return end
		for a, b in pairs(l) do
			if b == sel then
				table.remove(l, a)
				refreshLists()
				return
			end
		end
	end
	
	local lgui = gml.create("center", "center", 70, 26)
	lgui.style = server.getStyle(mod)
	lgui:addLabel("center", 1, 12, "Edycja list")
	lgui:addLabel(2, 4, 14, "Czarna lista:")
	lgui:addLabel(37, 4, 14, "Biała lista:")
	lb = lgui:addListBox(2, 6, 30, 12, {})
	rb = lgui:addListBox(37, 6, 30, 12, {})
	refreshLists()
	lgui:addButton(2, 19, 14, 1, "Dodaj", function()
		addItem(ret.black)
	end)
	lgui:addButton(18, 19, 14, 1, "Usuń", function()
		removeItem(ret.black, lb)
	end)
	lgui:addButton(37, 19, 14, 1, "Dodaj", function()
		addItem(ret.white)
	end)
	lgui:addButton(53, 19, 14, 1, "Usuń", function()
		removeItem(ret.white, rb)
	end)
	
	lgui:addButton(53, 23, 14, 1, "Anuluj", function()
		ret = nil
		lgui:close()
	end)
	lgui:addButton(37, 23, 14, 1, "Zatwierdź", function()
		lgui:close()
	end)
	lgui:run()
	return ret
end

local function turretsLists()
	local r = listTemplate(lists.turrets)
	if not r then return end
	lists.turrets = r
end

local function sensorsLists()
	local r = listTemplate(lists.sensors)
	if not r then return end
	lists.sensors = r
end

local function turretTemplate(item)
	local ret = {}
	if item then
		for a, b in pairs(item) do ret[a] = b end
	end
	if type(ret.walls) ~= "table" then ret.walls = {} end
	
	local tgui = gml.create("center", "center", 66, 20)
	tgui.style = server.getStyle(mod)
	tgui:addLabel("center", 1, 18, item and "Edycja wieżyczki" or "Nowa wieżyczka")
	tgui:addLabel(2, 4, 7, "Nazwa:")
	tgui:addLabel(2, 6, 7, "Adres:")
	tgui:addLabel(2, 7, 17, "Adres detektora:")
	tgui:addLabel(2, 9, 9, "Pozycja:")
	tgui:addLabel(2, 11, 9, "Ukrycie:")
	tgui:addLabel(2, 13, 12, "Obudowanie:")
	local name = tgui:addTextField(10, 4, 24)
	name.text = item and item.name or ""
	local tmp = tgui:addLabel(10, 6, 38, item and item.address or "")
	tmp.onDoubleClick = function(t)
		local a = server.componentDialog(mod, "os_energyturret")
		if not a then return end
		local found = false
		for _, b in pairs(turrets) do
			if b.address == a then
				found = true
				break
			end
		end
		if not found then
			local ct = server.findComponents(mod, a)
			if #ct ~= 1 then
				error("Wystąpił błąd w funkcji serwera: findComponents() > 1")
				return
			end
			ct = ct[1]
			local function cn(t)
				return t and type(t) == "number"
			end
			if not ct.state then
				server.messageBox(mod, "Nie można użyć tego komponentu, ponieważ jest wyłączony.", {"OK"})
				return
			elseif not (cn(ct.x) and cn(ct.y) and cn(ct.z)) then
				server.messageBox(mod, "Wieżyczka musi mieć określone wszystkie współrzędne!", {"OK"})
				return
			end
			if name.text:len() == 0 then
				name.text = ct.name:sub(1, 20)
				name:draw()
			end
			t.text = a
			ret.address = a
			t:draw()
		else
			server.messageBox(mod, "Urządzenie o takim adresie zostało już dodane.", {"OK"})
		end
	end
	tmp = tgui:addLabel(20, 7, 38, ret.detector or "")
	tmp.onDoubleClick = function(t)
		local a = server.componentDialog(mod, "os_entdetector")
		if not a then return end
		if #server.findComponents(mod, a) ~= 1 then
			error("Wystąpiłbłąd w funkcji serwera: findComponents() > 1")
			return
		end
		t.text = a
		ret.detector = a
		t:draw()
	end
	tgui:addButton(12, 9, 14, 1, ret.upside and "odwrócona" or "normalna", function(t)
		if ret.upside then
			ret.upside = false
			t.text = "normalna"
		else
			ret.upside = true
			t.text = "odwrócona"
		end
		t:draw()
	end)
	tgui:addButton(12, 11, 10, 1, ret.hidden and "tak" or "nie", function(t)
		if ret.hidden then
			ret.hidden = false
			t.text = "nie"
		else
			ret.hidden = true
			t.text = "tak"
		end
		t:draw()
	end)
	
	local vals = {"t", "b", "n", "s", "e", "w"}
	for i = 1, #vals do
		local temp = tgui:addLabel(15 + ((i -1) * 4), 13, 3)
		if item then
			temp.bgcolor = ret.walls[vals[i]] and 0x00ff00 or 0xff0000
		else
			temp.bgcolor = 0xff0000
		end
		temp.text = vals[i]
		temp.onClick = function(t)
			if ret.walls[vals[i]] then
				ret.walls[vals[i]] = false
				t.bgcolor = 0xff0000
			else
				ret.walls[vals[i]] = true
				t.bgcolor = 0x00ff00
			end
			t:draw()
		end
		temp.draw = function(t)
			local screenX, screenY = t:getScreenPosition()
			local ob = t.renderTarget.setBackground(t.bgcolor)
			local of = t.renderTarget.setForeground(0)
			t.renderTarget.set(screenX, screenY, " " .. t.text:sub(1, 1) .. " ")
			t.visible = true
			t.renderTarget.setBackground(ob)
			t.renderTarget.setForeground(of)
		end
	end
	
	tgui:addButton(48, 17, 14, 1, "Anuluj", function()
		tgui:close()
		ret = nil
	end)
	tgui:addButton(32, 17, 14, 1, "Zatwierdź", function()
		local n = name.text
		local found = false
		for _, t in pairs(turrets) do
			if t.name == n then
				found = true
				break
			end
		end
		if config.turretsState then
			server.messageBox(mod, "Nie można zmodyfikować elementu, gdy wieżyczki są aktywne.", {"OK"})
		elseif found and not item then
			server.messageBox(mod, "Wybrana nazwa jest już zajęta.", {"OK"})
		elseif n:len() > 20 then
			server.messageBox(mod, "Nazwa urządzenia nie może być dłuższa, niż 20 znaków.", {"OK"})
		elseif n:len() == 0 then
			server.messageBox(mod, "Podaj nazwę dla urządzenia.", {"OK"})
		elseif not ret.address or ret.address:len() == 0 then
			server.messageBox(mod, "Wybierz adres urządzenia", {"OK"})
		elseif not ret.detector or ret.detector:len() == 0 then
			server.messageBox(mod, "Wybierz adres detektora", {"OK"})
		else
			ret.name = n
			tgui:close()
		end
	end)
	tgui:run()
	return ret
end

local function addTurret()
	if #turrets < 12 then
		if config.turretsState then
			server.messageBox(mod, "Nie można dodać nowego elementu, gdy wieżyczki są aktywne.", {"OK"})
			return
		end
		local t = turretTemplate()
		if not t then return end
		table.insert(turrets, t)
		openTurret(t.address)
		rebuildTable(turrets, lbox)
		rebuildCache()
	else
		server.messageBox(mod, "Dodano już maksymalną liczbę wieżyczek.", {"OK"})
	end
end

local function modifyTurret()
	local sel = lbox:getSelected()
	if not sel then return end
	local m = sel:match("^%d+%.%s(.*)$")
	if not m then return end
	local t = nil
	local i = nil
	for a, b in pairs(turrets) do
		if b.name == m then
			t = b
			i = a
			break
		end
	end
	if not t then return end
	local ret = turretTemplate(t)
	if not ret then return end
	turrets[i] = ret
	rebuildTable(turrets, lbox)
	rebuildCache()
end

local function removeTurret()
	local index = getIndex(lbox:getSelected())
	if not index or not turrets[index] then return end
	if config.turretsActive then
		server.messageBox(mod, "Nie można usunąć elementu, gdy wieżyczki są aktywne.", {"OK"})
		return
	end
	if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Nie" then return end
	table.remove(turrets, index)
	rebuildTable(turrets, lbox)
	rebuildCache()
end

local function sensorTemplate(item)
	local ret = {}
	if item then
		for a, b in pairs(item) do
			if a == "enable" then
				ret.enable = {}
				if type(b) == "table" then
					index = 0
					for _, d in pairs(b) do
						index = index + 1
						if index > 3 then break end
						local tmp = {}
						for e, f in pairs(d) do
							tmp[e] = f
						end
						table.insert(ret.enable, tmp)
					end
				end
			elseif a == "disable" then
				ret.disable = {}
				if type(b) == "table" then
					index = 0
					for _, d in pairs(b) do
						index = index + 1
						if index > 3 then break end
						local tmp = {}
						for e, f in pairs(d) do
							tmp[e] = f
						end
						table.insert(ret.disable, tmp)
					end
				end
			else
				ret[a] = b
			end
		end
	else
		ret.enable = {}
		ret.disable = {}
	end
	
	local act = {}
	local function refreshActions()
		for i = 1, 3 do
			if ret.enable[i] then
				local a = server.actionDetails(mod, ret.enable[i].id)
				if a then
					act[i].text = a.name
				else
					act[i].text = tostring(tab.enable[i].id)
				end
			else
				act[i].text = ""
			end
			act[i]:draw()
		end
		for i = 1, 3 do
			if ret.disable[i] then
				local a = server.actionDetails(mod, ret.disable[i].id)
				if a then
					act[i + 3].text = a.name
				else
					act[i + 3].text = tostring(ret.disable[i].id)
				end
			else
				act[i + 3].text = ""
			end
			act[i + 3]:draw()
		end
	end
	local function chooseAction(enable, num)
		local text = enable and act[num].text or act[num + 3].text
		local tab = enable and ret.enable or ret.disable
		if text:len() > 0 then
			local r = server.actionDialog(mod, nil, nil, tab[num])
			tab[num] = r
		else
			local r = server.actionDialog(mod)
			if r then
				tab[num] = r
			end
		end
		refreshActions()
	end
	
	local sgui = gml.create("center", "center", 60, 19)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 15, item and "Edycja sensora" or "Nowy sensor")
	sgui:addLabel(2, 4, 7, "Nazwa:")
	sgui:addLabel(2, 6, 7, "Adres:")
	sgui:addLabel(2, 9, 19, "Akcje włączania:")
	sgui:addLabel(32, 9, 19, "Akcje wyłączania:")
	local name = sgui:addTextField(10, 4, 22)
	name.text = ret.name or ""
	local tmp = sgui:addLabel(10, 6, 38, ret.address or "")
	tmp.onDoubleClick = function(t)
		local a = server.componentDialog(mod, "motion_sensor")
		if not a then return end
		local found = false
		for _, b in pairs(sensors) do
			if b.address == a then
				found = true
				break
			end
		end
		if not found then
			local ct = server.findComponents(mod, a)
			if #ct ~= 1 then
				error("Wystąpił błąd w funkcji serwera: findComponents() > 1")
				return
			end
			ct = ct[1]
			if not ct.state then
				server.messageBox(mod, "Nie można użyć tego komponentu, ponieważ jest wyłączony.",{"OK"})
				return
			end
			if name.text:len() == 0 then
				name.text = ct.name:sub(1, 20)
				name:draw()
			end
			t.text = a
			ret.address = a
			t:draw()
		else
			server.messageBox(mod, "Urządzenie o takim adresie zostało już dodane.", {"OK"})
		end
	end
	for i = 1, 3 do
		local tmp1 = sgui:addLabel(4, 10 + i, 3, tostring(i).. ".")
		act[i] = sgui:addLabel(8, 10 + i, 22, string.rep("a", 22))
		local function exec()
			chooseAction(true, i)
		end
		tmp1.onDoubleClick = exec
		act[i].onDoubleClick = exec
	end
	for i = 1, 3 do
		local tmp1 = sgui:addLabel(34, 10 + i, 3, tostring(i) .. ".")
		act[i + 3] = sgui:addLabel(38, 10 + i, 22, "")
		local function exec()
			chooseAction(false, i)
		end
		tmp1.onDoubleClick = exec
		act[i + 3].onDoubleClick = exec
	end
	refreshActions()
	
	sgui:addButton(42, 16, 14, 1, "Anuluj", function()
		ret = nil
		sgui:close()
	end)
	sgui:addButton(26, 16, 14, 1, "Zatwierdź", function()
		local n = name.text
		local found = false
		for _, t in pairs(sensors) do
			if t.name == ret.name then
				found = true
				break
			end
		end
		if config.sensorsState then
			server.messageBox(mod, "Nie można zmodyfikować elementu, gdy sensory są aktywne.", {"OK"})
		elseif found and not item then
			server.messageBox(mod, "Urządzenie o takiej nazwie zostało już dodane.", {"OK"})
		elseif n:len() == 0 then
			server.messageBox(mod, "Wprowadź nazwę dla urządzenia.", {"OK"})
		elseif n:len() > 20 then
			server.messageBox(mod, "Długość nazwy nie może przekraczać 20 znaków.", {"OK"})
		elseif ret.address:len() == 0 then
			server.messageBox(mod, "Wybierz adres urządzenia.", {"OK"})
		else
			ret.name = n
			sgui:close()
		end
	end)
	sgui:run()
	return ret
end

local function addSensor()
	if #sensors < 12 then
		if config.sensorsState then
			server.messageBox(mod, "Nie można dodać elementu, gdy sensory są aktywne.", {"OK"})
			return
		end
		local t = sensorTemplate()
		if not t then return end
		table.insert(sensors, t)
		rebuildTable(sensors, rbox)
	else
		server.messageBox(mod, "Dodano już maksymalną liczbę sensorów.", {"OK"})
	end
end

local function modifySensor()
	local sel = rbox:getSelected()
	if not sel then return end
	local m = sel:match("^%d+%.%s(.*)$")
	if not m then return end
	local t = nil
	local i = nil
	for a, b in pairs(sensors) do
		if b.name == m then
			t = b
			i = a
			break
		end
	end
	if not t then return end
	local ret = sensorTemplate(t)
	if not ret then return end
	sensors[i] = ret
	rebuildTable(sensors, rbox)
end

local function removeSensor()
	local index = getIndex(rbox:getSelected())
	if not index or not sensors[index] then return end
	if config.sensorsState then
		server.messageBox(mod, "Nie można usunąć elemenu, gdy sensory są aktywne.",{"OK"})
		return
	end
	if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Nie" then return end
	table.remove(sensors, index)
	rebuildTable(sensors, rbox)
end

local function settings()
	local ret = {}
	ret.turretsMode = config.turretsMode
	ret.sensorsMode = config.sensorsMode
	local sgui = gml.create("center", "center", 55, 22)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Ustawienia")
	sgui:addLabel(2, 4, 12, "Wieżyczki:")
	sgui:addLabel(4, 6, 17, "Tryb wykrywania:")
	sgui:addLabel(4, 7, 29, "Interwał skanowania[1-15s]:")
	sgui:addLabel(4, 8, 38, "Czas aktywacji wieżyczek[0,15-180s]:")
	sgui:addLabel(4, 9, 26, "Zasięg skanowania[5-20]:")
	sgui:addLabel(2, 12, 10, "Sensory:")
	sgui:addLabel(4, 14, 17, "Tryb wykrywania:")
	sgui:addLabel(4, 15, 19, "Czułość[0.1-10]:")
	sgui:addLabel(4, 16, 25, "Czas aktywacji[0,15-180s]:")
	
	local tint = sgui:addTextField(44, 7, 5)
	local ttim = sgui:addTextField(44, 8, 5)
	local tran = sgui:addTextField(44, 9, 5)
	local ssen = sgui:addTextField(31, 15, 5)
	local sact = sgui:addTextField(31, 16, 5)
	tint.text = tostring(config.delay)
	ttim.text = tostring(config.turretsActive)
	tran.text = tostring(config.range)
	ssen.text = tostring(config.sensitivity)
	sact.text = tostring(config.sensorsActive)
	
	local names = {"wszystko", "biała lista", "czarna lista"}
	sgui:addButton(24, 6, 14, 1, names[ret.turretsMode], function(t)
		if ret.turretsMode < 3 then
			ret.turretsMode = ret.turretsMode + 1
		else
			ret.turretsMode = 1
		end
		t.text = names[ret.turretsMode]
		t:draw()
	end)
	sgui:addButton(24, 14, 14, 1, names[ret.sensorsMode], function(t)
		if ret.sensorsMode < 3 then
			ret.sensorsMode = ret.sensorsMode + 1
		else
			ret.sensorsMode = 1
		end
		t.text = names[ret.sensorsMode]
		t:draw()
	end)
	
	sgui:addButton(38, 19, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(22, 19, 14, 1, "Zatwierdź", function()
		if config.turretsState or config.sensorsState then
			server.messageBox(mod, "Nie można zapisać ustawień, gdy wieżyczki lub sensory są włączone.", {"OK"})
			return
		end
		ret.delay = tonumber(tint.text)
		ret.turretsActive = tonumber(ttim.text)
		ret.range = tonumber(tran.text)
		ret.sensitivity = tonumber(ssen.text)
		ret.sensorsActive = tonumber(sact.text)
		if not ret.delay or ret.delay < 1 or ret.delay > 15 then
			server.messageBox(mod, "Interwał skanowania musi być liczbą w zakresie od 1 do 15.", {"OK"})
		elseif not ret.turretsActive or (ret.turretsActive ~= 0 and (ret.turretsActive < 15 or ret.turretsActive > 180)) then
			server.messageBox(mod, "Czas aktywacji wieżyczek musi być liczbą o wartości 0 lub w zakresie od 15 do 180.", {"OK"})
		elseif not ret.range or ret.range < 5 or ret.range > 20 then
			server.messageBox(mod, "Zasięg skanowania musi być liczbą w zakresie od 5 do 20.", {"OK"})
		elseif not ret.sensitivity or ret.sensitivity < 0.1 or ret.sensitivity > 10 then
			server.messageBox(mod, "Czułość sensorów musi być liczbą w zakresie od 0.1 do 10.", {"OK"})
		elseif not ret.sensorsActive or (ret.sensorsActive ~= 0 and (ret.sensorsActive < 15 or ret.sensorsActive > 180)) then
			server.messageBox(mod, "Czas aktywacji sensorów musi być liczbą o wartości 0 lub w zakresie od 15 do 180.", {"OK"})
		else
			config.delay = ret.delay
			config.turretsActive = ret.turretsActive
			config.range = ret.range
			config.sensitivity = ret.sensitivity
			config.sensorsActive = ret.sensorsActive
			config.turretsMode = ret.turretsMode
			config.sensorsMode = ret.sensorsMode
			sgui:close()
		end
	end)
	sgui:run()
end

local function setTurretsMode(mode)
	if mode < 0 or mode < 4 then
		config.turretsMode = mode
	else
		server.call(mod, 5203, "Wartość trybu wykracza poza zakres.", "turrets", true)
	end
	
end

local function setSensorsMode(mode)
	if mode > 0 or mode < 4 then
		config.sensorsMode = mode
	else
		server.call(mod, 5203, "Wartość trybu wykracza poza zakres.", "turrets", true)
	end
end

local actions = {
	[1] = {
		name = "enableTurrets",
		type = "TURRETS",
		desc = "Włącza wieżyczki",
		exec = enableTurrets
	},
	[2] = {
		name = "disableTurrets",
		type = "TURRETS",
		desc = "Wyłącza wieżyczki",
		exec = disableTurrets
	},
	[3] = {
		name = "enableSensors",
		type = "TURRETS",
		desc = "Włącza sensory",
		exec = enableSensors
	},
	[4] = {
		name = "disableSensors",
		type = "TURRETS",
		desc = "Wyłącza sensory",
		exec = disableSensors
	},
	[5] = {
		name = "setTurretsMode",
		type = "TURRETS",
		desc = "Ustawia tryb wieżyczek",
		p1type = "number",
		p1desc = "tryb [1-3]",
		exec = setTurretsMode
	},
	[6] = {
		name = "setSensorsMode",
		type = "TURRETS",
		desc = "Ustawia tryb sensorów",
		p1type = "number",
		p1desc = "tryb [1-3]",
		exec = setSensorsMode
	}
}

mod.name = "turrets"
mod.version = version
mod.id = 36
mod.apiLevel = 2
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 14, ">> TURRETS <<")
	window:addLabel(3, 3, 12, "Wieżyczki:")
	window:addLabel(36, 3, 9, "Sensory:")
	
	lbox = window:addListBox(3, 5, 30, 10, {})
	lbox.onDoubleClick = modifyTurret
	rbox = window:addListBox(36, 5, 30, 10, {})
	rbox.onDoubleClick = modifySensor
	
	element[1] = window:addButton(18, 3, 14, 1, "", function()
		if config.turretsState then
			disableTurrets()
		else
			enableTurrets()
		end
	end)
	element[2] = window:addButton(52, 3, 14, 1, "", function(t)
		if config.sensorsState then
			disableSensors()
			t.text = "wyłączone"
		else
			enableSensors()
			t.text = "włączone"
		end
		t:draw()
	end)
	refreshView()
	
	window:addButton(3, 16, 14, 1, "Dodaj", addTurret)
	window:addButton(19, 16, 14, 1, "Usuń", removeTurret)
	window:addButton(3, 18, 16, 1, "Listy", turretsLists)
	window:addButton(36, 16, 14, 1, "Dodaj", addSensor)
	window:addButton(52, 16, 14, 1, "Usuń", removeSensor)
	window:addButton(50, 18, 16, 1, "Listy", sensorsLists)
	window:addButton(26, 18, 16, 1, "Ustawienia", settings)
	
	rebuildTable(turrets, lbox)
	rebuildTable(sensors, rbox)
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	local function check(v, r1, r2)
		return not v or type(v) ~= "number" or v < r1 or v > r2
	end
	if check(config.turretsMode, 1, 3) then
		config.turretsMode = 3
	end
	if check(config.sensorsMode, 1, 3) then
		config.sensorsMode = 3
	end
	if check(config.sensitivity, 0.1, 10) then
		config.sensitivity = 0.4
	end
	if check(config.delay, 1, 15) then
		config.delay = 5
	end
	if check(config.range, 5, 20) then
		config.range = 7
	end
	if check(config.turretsActive, 15, 180) and config.turretsActive ~= 0 then
		config.turretsActive = 15
	end
	if check(config.sensorsActive, 15, 180) then
		config.sensorsActive = 15
	end
	
	loadData()
	server.registerEvent(mod, "component_added")
	server.registerEvent(mod, "component_removed")
	
	local removal = {}
	for a, t in pairs(turrets) do
		local f1 = server.findComponents(mod, t.address)
		local f2 = server.findComponents(mod, t.detector)
		if #f1 > 0 and #f2 > 0 then
			openTurret(t.address)
		else
			server.log(mod, "TURRETS: Komponenty rekordu wieżyczki są niedostępne, usuwanie rekordu...")
			table.insert(removal, a)
		end
	end
	table.sort(removal, function(a, b) return a > b end)
	for _, b in pairs(removal) do table.remove(turrets, b) end
	removal = {}
	for a_, t in pairs(sensors) do
		local f1 = server.findComponents(mod, t.address)
		if #f1 == 0 then
			server.log(mod, "TURRETS: Komponent rekordu sensora jest niedostępny, usuwanie rekordu...")
			table.insert(removal, a)
		end
	end
	table.sort(removal, function(a, b) return a > b end)
	for _, b in pairs(removal) do table.remove(sensors, b) end
	refreshSensors()
	
	rebuildCache()
	if config.turretsState then enableTurrets() end
	if config.sensorsState then enableSensors() end
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	for _, t in pairs(sensors) do
		t.active = nil
	end
	saveData()
	server.unregisterEvent(mod, "component_added")
	server.unregisterEvent(mod, "component_removed")
	
	if timer then event.cancel(timer) end
	local tab = server.getComponentList(mod, "os_energyturret")
	for _, t in pairs(tab) do
		closeTurret(t.address)
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "motion" then
		local tab = nil
		for _, t in pairs(sensors) do
			if t.address == e[2] then
				tab = t
				break
			end
		end
		if not tab or tab.active then return end
		local found = false
		if config.sensorsMode == 1 then
			--all
			found = true
		elseif config.sensorsMode == 2 and e[6] then
			--white
			for _, t in pairs(lists.sensors.white) do
				if t == e[6] then
					return
				end
			end
		elseif config.sensorsMode == 3 and e[6]then
			--black
			for _, t in pairs(lists.sensors.black) do
				if t == e[6] then
					found = true
					break
				end
			end
		end
		if not found then return end
		for i = 1, 3 do
			local l = tab.enable[i]
			if l then
				server.call(mod, l.id, l.p1, l.p2, true)
			end
		end
		tab.active = true
		event.timer(config.sensorsActive, function()
			for i = 1, 3 do
				local l = tab.disable[i]
				if l then
					server.call(mod, l.id, l.p1, l.p2, true)
				end
			end
			tab.active = nil
		end)
	elseif e[1] == "components_changed" then
		rebuildCache()
		if not config.turretsState then
			local tag = server.getComponentList(mod, "os_energyturret")
			for _, t in pairs(tab) do
				openTurret(t.address)
			end
		end
	elseif e[1] == "component_added" then
		if e[3] == "os_energyturret" then
			local found = server.findComponents(e[2])
			if #found == 1 then
				rebuildCache()
				openTurret(e[2])
			end
		elseif e[3] == "motion_sensor" then
			refreshSensors()
		end
	elseif e[1] == "component_removed" then
		if e[3] == "os_energyturret" then
			rebuildCache()
		end
	end
end

return mod