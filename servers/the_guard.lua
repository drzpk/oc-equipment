-- ################################################
-- #                The Guard  2.0                #
-- #                                              #
-- #  03.2016                      by: IlynPayne  #
-- ################################################

--[[
	## Opis programu ##
		Program służy jako centrum sterowania systemem zabezpieczeń.
		Większość funkcji programu jest realizowana za pomocą moda OpenSecurity.
		
		Nowa architektura zakłada podział programu na moduły, które mogą być rozwijane
		niezależnie. Powoduje to zwiększenie bezpieczeństwa - awaria jednego z
		modułów nie powoduje przerwania pracy całego systemu.
		
	## Opis techniczny ##
		Poprzednia wersja serwera (1.0) du komunikacji z urządzeniami peryferyjnymi
		używała innych komputerów z uruchomionymi na nich programami 'micro'.
		W wersjach wyższych zrezygnowano z tego na rzecz kablowego podłaczenia
		komponentów. Rozwiązanie takie ma jednak wady: przy domyślnej konfiguracji
		do najlepszego serwera mogą zostać podłączone maksymalnie 64 moduły, wliczając
		te na płycie głównej.
		
		Jak zostało to już wcześniej wspomniane, program sam w sobie nie będzie
		posiadał żadnej funkcjonalności. 
		Wyjątkiem od tej reguły będzie katalog komponentów. Komponenty wpisane do
		katalogu będą mogły być łatwiej zarządzane, otrzymają również dodatkowe
		parametry, takie, jak współrzędne czy status.
		Moduły korzystające z katalogu komponentów będą odporne na nieautoryzowane
		podłączenie nieznanego komponentu.
		
	## Lista dostępnych modułów ##
		- levels (mod_tg_levels) - obsługa poziomów bezpieczeństwa
		- logs (mod_tg_logs) - menedżer logów systemowych
		- io (mod_tg_io) - obsługa wejścia/wyjścia (redstone/project red/network)
		- auth (mot_tg_auth) - autoryzacja użytkownika za pomocą kart i terminali
		- motion (mod_tg_turrets) - obsługa detektorów ruchu i wieżyczek
		
	## Architektura modułów ##
		Aby moduł został zaakceptowany przez serwer, musi zwracać tablicę
		asocjacyjną zawierającą następujące elementy:
		- name:string - nazwa modułu
		- version:string - wersja modułu
		- id: number - unikalny identyfikator modułu
		- apiLevel:number - wersja serwera
		- shape:string - kształt okna modułu ("normal", "landscape")
		- actions:table - tablica zawierająca dostępne akcje
		- setUI(window) - tworzy gotowy interfejs użytkownika, funkcja wywoływana po start()
		- start(server:table):function - funkcja wywoływana w momencie startu
		  modułu, jako parametr podaje się interfejs serwera
		- stop(server_table):function - funkcja wywoływana w momencie wyłączania modułu
		- pullEvent(...):function - obsługa zarejestrowanych wydarzeń
		
		Akcje to zadania, które może wykonać dany moduł. Akcje udostępnione
		przez jeden moduł są globalne, czyli może je zobaczyć oraz wykonać
		każdy inny moduł. Każda akcja to tablica składająca się z następujących
		elementów:
		[id:number - identyfikator akcji, unikalny w skali modułu]
		{
			name:string - nazwa akcji
			type:string - typ akcji
			desc:string - opis akcji
			p1type:string - typ pierwszego parametru
			p2type:string - typ drugiego parametru
			p1desc:sting - opis pierwszego parametru
			p2desc:string - opis drugiego parametru
			exec:function - funkcja wykonująca akcję
			hidden:boolean - czy akcja ma być ukryta
		}
		Typy akcji używane są dla ułatwienia obsługi (np. dany moduł może
		potrzebować tylko akcji jednego typu). Funkcja akcji może przyjąć do
		2 parametrów dowolnego typu.
		
		Kategorie akcji są dowolne. Należy jednak wziąć pod uwagę, że inny moduł
		może chcieć wykonywać akcje tylko jednego typu, dlatego zaleca się,
		aby każda akcja była przypisana do jednej z następujących kategorii:
		* CORE - akcje udostępniane przez serwer
		* LOG - akcje związane z logami
		* IO - akcje związane z obsługą obwodów elektrycznych
		* LEVEL - akcje związane z poziomami bezpieczeństwa
		* AUTH - akcje związane z autoryzacją
		* TURRET - akcje związane z wieżyczkami i detektorami ruchu
		
		Moduł samodzielnie dba o tworzenie i przechowywanie akcji!
		
		Oprócz akcji moduł może również obsługiwać event listener. Serwer
		generuje następujące wydarzenia:
		* {"components_changed"} - gdy komponent został dodany, usunięty lub zmodyfikowany
		
	## Struktura zmiennych konfiguracyjnych ##
		settings: { - globalne ustawienia programu (plik /etc/the_guard/config.conf)
			port: number - port używany przez moduły do wykonywania połączeń, moduły mogą zignorować to ustawienie,
			backupPort: number - port serwera danych, używany do kopii zapasowych i przywracania danych,
			debugMode:bool - stan trybu debugowania,
			dark:bool - czy używany jest ciemny motyw,
			saveOnExit:bool - czy konfiguracja ma być zapisywana ponownie przy zamknięciu
		}
		
		modules: { - informacje o modułach (plik /etc/the_guard/modules.conf)
			[zone:number] { - zajmowana strefa
				name:string - nazwa modułu*
				file:string - nazwa pliku
				version:string - wersja modułu*
				shape:string - wymiary modułu*
			}
			...
		}
		
		components: { - lista zainstalowanych komponentów (plik /etc/the_guard/components.conf)
			{
				address:string - adres komponentu
				type: string - typ komponentu
				name:string - nazwa
				state:bool - status komponentu (włączony/wyłączony)
				x: number - współrzędna X komponentu (opcjonalnie)
				y: number - współrzędna Y komponentu (opcjonalnie)
				z: number - współrzędna Z komponentu (opcjonalnie)
			}
			...
		}
		
		passwd:string - przechowuje hasło główne programu zakodowane w SHA-256
		(plik /etc/the_guard/passwd.bin)
		
		Pozostałe moduły przechowują swoje pliki konfiguracyjne w folderze
		'/etc/the_guard/modules'. Każdy moduł posiada domyślnie 1 plik
		konfiguracyjny w formacie <nazwa_modułu>.conf.
		
		*Pozycje oznaczone gwiazdką nie są zapisywane do plików konfiguracyjnych
		
	## Interfejs ##
		Program udostępnia interfejs umożliwiający modułom działanie.
		Wszystkie funkcje interfejsu są opisane niżej w kodzie.
			
		Okno serwera jest podzielone na 5 stref. 4 pierwsze strefy mają
		takie same wymiary. Piąta strefa jest zwykle przeznaczona na moduł
		logów. Współrzędne elementów GUI modułów są względne do początku
		strefy. Moduł wychodzący poza strefę zostanie wyłączony.
]]

local version = "2.0"
local apiLevel = 2
local args = {...}

if args[1] == "version_check" then return version end

local computer = require("computer")
local component = require("component")
local event = require("event")
local serial = require("serialization")
local uni = require("unicode")
local fs = require("filesystem")
local term = require("term")
local gml = require("gml")
local dsapi = require("dsapi")
local colors = require("colors")
if not component.isAvailable("modem") then
	io.stderr:write("Program wymaga do dzialania karty sieciowej")
	return
end
local modem = component.modem

local data = nil
if component.isAvailable("data") then
	data = component.data
end
if not data then
	io.stderr:write("Serwer wymaga do dzialania karty danych 2 poziomu")
	return
elseif not data.encrypt then
	io.stderr:write("Zamontowana karta danych musi być przynajmniej 2 poziomu")
	return
end

local resolution = {component.gpu.getResolution()}
if not resolution[1] == 160 or not resolution[2] == 50 then
	io.stderr:write("Serwer wymaga rozdzielczości ekranu 160x50 (obecna to " .. tostring(resolution[1]) .. "x" .. tostring(resolution[2]))
	return
end

-- # Konfiguracja
local passwd = nil -- hasło główne
local settings = {} -- ustawienia
local components = {} -- zainstalowane komponenty
local modules = {} -- dostępne moduły
local bmodules = {} -- uszkodzone moduły
local pmodules = {} -- moduły oczekujące na instalację
local token = nil -- identyfikator urządzenia

local configDir = "/etc/the_guard"
local modulesDir = "/usr/bin/mod_tg"

-- # Deklaracje funkcji
local silentLog = nil
local GMLmessageBox = nil
local GMLcontains = nil
local GMLgetAppliedStyles = nil
local GMLextractProperty = nil
local GMLextractProperties = nil
local GMLfindStyleProperties = nil
local GMLcalcBody = nil

-- # Strefy
local zones = {
	[1] = {1, 1},
	[2] = {70, 1},
	[3] = {1, 21},
	[4] = {70, 21},
	[5] = {1, 41},
	normal = {68, 19},
	landscape = {158, 10}
}

-- # Zmienne
local gui = nil
local mod = {}
local intlog = ""
local lastlog = {}
local loglines = 0

-- # Interfejs dla modułów
local interface = {}
local actions = {}
local events = {}
local eventsready = false
local revents = {}
local backgroundListener = nil

--[[
Ładuje plik konfiguracyjny modułu
	@mod - moduł wywołujący
	RET: tablica asocjacyjna z konfiguracją
]]
interface.loadConfig = function(mod)
	local path = fs.concat("/etc/the_guard/modules", mod.name .. ".conf")
	if fs.isDirectory(path) then
		fs.remove(path)
	elseif fs.exists(path) then
		local f = io.open(path, "r")
		if f then
			local s, r = pcall(serial.unserialize, f:read("*a"))
			if s then
				f:close()
				return r
			else
				f:close()
				return {}
			end
		else
			return {}
		end
	else
		return {}
	end
end

--[[
Zapisuje konfigurację do pliku
	@mod - moduł wywołujący
	@tab - tablica z konfiguracją
]]
interface.saveConfig = function(mod, tab)
	if not fs.isDirectory("/etc/the_guard/modules") then
		fs.makeDirectory("/etc/the_guard/modules")
	end
	if type(tab) == "table" then
		local path = fs.concat("/etc/the_guard/modules", mod.name .. ".conf")
		if fs.isDirectory(path) then
			fs.remove(path)
		else
			local t = serial.serialize(tab)
			if t then
				local f = io.open(path, "w")
				if f then
					f:write(t)
					f:close()
				end
			end
		end
	end
end

--[[
Zwraca moduł
	@mod - moduł wywołujący
	@name - nazwa żądanego modułu
	RET: moduł
]]
interface.getModule = function(mod, name)
	for _, t in pairs(modules) do
		if t.name == name then return t end
	end
	return nil
end

--[[
Rejestruje nowe wydarzenie
	@mod - moduł wywołujący
	@name - nazwa wydarzenia
]]
interface.registerEvent = function(mod, name)
	if not events[mod.name] then events[mod.name] = {} end
	for _, n in pairs(events[mod.name]) do
		if n == name then return end
	end
	table.insert(events[mod.name], name)
	local registered = false
	for _, s in pairs(revents) do
		if s == name then
			registered = true
			break
		end
	end
	if not registered then
		table.insert(revents, name)
		if eventsready then
			event.listen(name, backgroundListener)
		end
	end
end

--[[
Wyrejestrowuje wydarzenie
	@mod - moduł wywołujący
	@name - nazwa wydarzenia
]]
interface.unregisterEvent = function(mod, name)
	if events[mod.name] then
		for i, s in pairs(events[mod.name]) do
			if s == name then
				table.remove(events[mod.name], i)
				break
			end
		end
		local left = false
		for _, t in pairs(events) do
			for _, t2 in pairs(t) do
				if t2 == name then
					left = true
					break
				end
			end
		end
		if not left then
			for i, s in pairs(revents) do
				if s == name then
					table.remove(revents, i)
					event.ignore(name, backgroundListener)
					break
				end
			end
		end
	end
end

--[[
Zwraca listę akcji
	@mod - moduł wywołujący
	@type:string or nil - filtr typu akcji
	@target:string or nil - filtr modułu
	@name:string or nil - filtr nazwy
	RET: <lista akcji, liczba akcji>
]]
interface.getActions = function(mod, type, target, name)
	local ac = {}
	local amount = 0
	for m, t in pairs(actions) do
		if (target and m == target) or (not target) then
			for id, at in pairs(t) do
				if (type and (at.type == type or at.type == "")) or (not type) then
					if (name and at.name:find(name)) or (not name) then
						ac[id] = at
						amount = amount + 1
					end
				end
			end
		end
	end
	return ac, amount
end

--[[
Zwraca tablicę z zarejestrowanymi komponentami
	@mod - moduł wywołujący
	@name - nazwa kategorii komponentu
	RET: <tablica z komponentami>
]]
interface.getComponentList = function(mod, name)
	local ret = {}
	for _, t in pairs(components) do
		if t.state then
			if name then
				if name:lower() == t.type:lower() then
					table.insert(ret, t)
				end
			else
				table.insert(ret, t)
			end
		end
	end
	return ret
end

--[[
Wyszukuje zarejestrowany komponent na podstawie podanej części adresu
	@mod - moduł wywołujący
	@pattern - część adresu
	RET: <znalezione komponenty:table>
]]
interface.findComponents = function(mod, pattern)
	local ret = {}
	local pat = pattern and string.gsub(pattern, "-", "%%-") or ""
	for _, t in pairs(components) do
		if t.address:find(pat) then
			table.insert(ret, t)
		end
	end
	return ret
end

--[[
Wywołuje daną akcję
	@mod - moduł wywołujący
	@id - identyfikator akcji
	@p1 - parametr 1. lub nil
	@p2 - parametr 2. lub nil
	@silent:boolean - nie wyświetlanie komunikatów o błędach
	RET: <wartość zwracana przez akcję> or nil
]]
interface.call = function(mod, id, p1, p2, silent)
	local a = interface.actionDetails(mod, id)
	if a then
		local et = ""
		if a.p1type and type(p1) ~= a.p1type then
			et = type(p1) .. " ~= " .. a.p1type
		elseif a.p2type and type(p2) ~= a.p2type then
			if et:len() > 0 then
				et = et .. ", " 
			end
			et = et .. type(p2) .. " ~= " .. a.p2type
		else
			local s, r = pcall(a.exec, p1, p2)
			if s then
				return r
			else
				silentLog("interface.call", "nie udało się wywołać akcji " .. tostring(id) .. ": " .. r)
				if not silent then
					GMLmessageBox(gui, "Nie udało się wywołać akcji " .. tostring(id), {"OK"})
				end
				return nil
			end
		end
		if et:len() > 0 then
			local m = "Do akcji podano nieprawidłowe parametry. ("
			silentLog("interface.call", m .. et .. ")")
			if not silent then
				GMLmessageBox(gui, m .. et .. ")", {"OK"})
			end
		end
	else
		silentLog("interface.call", "akcja " .. tostring(id) .. " nie została odneleziona")
		if not silent then
			GMLmessageBox(gui, "Nie odnalziono akcji " .. tostring(id) .. "!", {"OK"})
		end
	end
	return nil
end

--[[
Zwraca tablicę danej akcji
	@mod - moduł wywołujący
	@id - identyfikator akcji
	RET: <tablica akcji> or nil
]]
interface.actionDetails = function(mod, id)
	for _, t in pairs(actions) do
		for i, a in pairs(t) do
			if i == id then
				return a
			end
		end
	end
	return nil
end

--[[
Dodaje nowy log
	@mod - moduł wywołujący
	@msg - wiadomość do wyświetlenia
]]
interface.log = function(mod, msg)
	silentLog(mod.name, msg)
end

--[[
Wyświetla okno wiadomości
	@mod - moduł wywołujący
	@message - wiadomość do wyświetlenia
	@buttons - tablica z przyciskami
	RET: <wybrany przycisk>
]]
interface.messageBox = function(mod, message, buttons)
	local r, e = pcall(GMLmessageBox, gui, message, buttons)
	if r then
		return e
	else
		silentLog("interface.messageBox", "nie udało się wyświetlić wiadomości: " .. e)
		return nil
	end
end

--[[
Wyświetla okno dialogowe wyboru akcji
	@mod - moduł wywołujący
	@type:string or nil - kategoria akcji
	@target:string or nil - moduł udostępniający akcje
	@fill:table or nil - tablica asocjacyjne z gotowym wypełnieniem ({[id:number],[p1],[p2]})
	@hidden:boolean - czy ukryte akcje mają być wyświetlane
	RET:<wybór użytkownika (patrz parametr fill)> or nil
]]
interface.actionDialog = function(mod, typee, target, fill, hidden)
	local ac = interface.getActions(mod, typee, target)
	local sublist = nil
	local ll = {}
	local box = nil
	local rs = {}
	local ret = {}
	
	local function rebuild(l)
		ll = {}
		for _, t in pairs(l) do
			if (hidden and t.hidden) or not t.hidden then
				table.insert(ll, t.name .. " (" .. t.type:upper() .. ")")
			end
		end
		table.sort(ll)
		box:updateList(ll)
	end
	local function update(id, t)
		if not id or not t then
			ret.id = nil
			for i = 1, 7 do rs[i]:hide() end
			return
		end
		ret.id = id
		rs[1].text = t.desc:sub(1, 39)
		rs[1]:show()
		rs[1]:draw()
		rs[2]:show()
		rs[3].text = tostring(id)
		rs[3]:show()
		rs[3]:draw()
		if t.p1type then
			rs[4].text = string.sub(t.p1desc .. "(" .. t.p1type .. ")", 1, 39)
			rs[4]:show()
			rs[4]:draw()
			rs[5]:show()
			rs[5]:draw()
		else
			rs[4]:hide()
			rs[5]:hide()
		end
		if t.p2type then
			rs[6].text = string.sub(t.p2desc .. "(" .. t.p2type .. ")", 1, 39)
			rs[6]:show()
			rs[6]:draw()
			rs[7]:show()
			rs[7]:draw()
		else
			rs[6]:hide()
			rs[7]:hide()
		end
	end
	local function doRefresh(l)
		local selected = box:getSelected():match("^(.*) %(")
		if selected then
			for i, t in pairs(l) do
				if t.name == selected then
					update(i, t)
					return
				end
			end
		end
		for i = 1, 7 do rs[i]:hide() end
	end
	local function refresh()
		doRefresh(sublist or ac)
	end
	
	local agui = gml.create("center", "center", 80, 24)
	agui.style = interface.getStyle(mod)
	agui:addLabel("center", 1, 18, "Okno wyboru akcji")
	rs[1] = agui:addLabel(35, 6, 40, "")
	rs[2] = agui:addLabel(35, 8, 15, "Identyfikator:")
	rs[4] = agui:addLabel(35, 11, 40, "")
	rs[6] = agui:addLabel(35, 14, 40, "")
	local search = agui:addTextField(2, 4, 14)
	agui:addButton(17, 4, 12, 1, "Szukaj", function()
		if search.text:len() > 0 then
			sublist = {}
			for i, t in pairs(ac) do
				if t.name:find(search.text) then
					sublist[i] = t
				end
			end
		else
			sublist = nil
		end
		rebuild(sublist or ac)
		refresh()
	end)
	box = agui:addListBox(2, 6, 28, 14, {})
	box.onChange = refresh
	rs[3] = agui:addLabel(51, 8, 10, "")
	rs[5] = agui:addTextField(38, 12, 20)
	rs[5].visible = false
	rs[7] = agui:addTextField(38, 15, 20)
	rs[7].visible = false
	agui:addButton(3, 22, 14, 1, "Wyczyść", function()
		ret.id = nil
		update()
	end)
	agui:addButton(63, 22, 14, 1, "Anuluj", function()
		agui:close()
		ret = fill
	end)
	agui:addButton(47, 22, 14, 1, "Zatwierdź", function()
		if not ret.id then
			agui:close()
			return
		end
		local a = interface.actionDetails(nil, tonumber(rs[3].text))
		if a then
			if a.p1type then
				if a.p1type == "number" then
					local n = tonumber(rs[5].text)
					if not n then
						GMLmessageBox(gui, "Pierwszy parametr musi być liczbą", {"OK"})
						return
					end
					ret.p1 = n
				elseif rs[5].text:len() == 0 then
					GMLmessageBox(gui, "Pierwszy parametr nie może być pusty.", {"OK"})
					return
				else
					ret.p1 = rs[5].text
				end
			end
			if a.p2type then 
				if a.p2type == "number" then
					local n = tonumber(rs[7].text)
					if not n then
						GMLmessageBox(gui, "Drugi parametr musi być liczbą", {"OK"})
						return
					end
					ret.p2 = n
				elseif rs[7].text:len() == 0 then
					GMLmessageBox(gui, "Drugi parametr nie może być pusty.", {"OK"})
					return
				else
					ret.p2 = rs[7].text
				end
			end
			agui:close()
		end
	end)
	local function firstFill(id, t)
		if not id or not t then
			ret.id = nil
			for i = 1, 7 do rs[i].hidden = true end
			return
		end
		ret.id = id
		rs[1].text = t.desc:sub(1, 39)
		rs[3].text = tostring(id)
		if t.p1type then
			rs[4].text = string.sub(t.p1desc .. "(" .. t.p1type .. ")", 1, 39)
		else
			rs[4].hidden = true
			rs[5].hidden = true
		end
		if t.p2type then
			rs[6].text = string.sub(t.p2desc .. "(" .. t.p2type .. ")", 1, 39)
		else
			rs[6].hidden = true
			rs[7].hidden = true
		end
	end
	if fill and fill.id then
		local a = interface.actionDetails(nil, fill.id)
		if a then
			if fill.p1 and type(fill.p1) == "number" then
				rs[5].text = tostring(fill.p1)
			else
				rs[5].text = fill.p1 or ""
			end
			if fill.p2 and type(fill.p2) == "number" then
				rs[7].text = tostring(fill.p2)
			else
				rs[7].text = fill.p2 or ""
			end
			firstFill(fill.id, a)
		else
			firstFill()
			GMLmessageBox(gui, "Nie znaleziono akcji o podanym identyfikatorze.", {"OK"})
		end
	else
		firstFill()
	end
	rebuild(ac)
	agui:run()
	return (ret and ret.id) and ret or nil
end

--[[
Wyświetla okno dialogowe wyboru komponentu
	@mod - moduł wywołujący
	@typee - typ komponentu
	RET: <adres komponentu> or nil
]]
interface.componentDialog = function(mod, typee)
	local cl = interface.getComponentList(mod, typee)
	local box, list, chosen = {}, {}, nil
	local ret = nil
	
	local function refreshList()
		list = {}
		for _, t in pairs(cl) do
			local s = string.format("[%s]  %s  %s  (%s, %s, %s)", t.type:upper(), t.address, t.name and t.name:sub(1, 20) or "", t.x and tostring(t.x) or "", t.y and tostring(t.y) or "", t.z and tostring(t.z) or "")
			table.insert(list, s)
		end
		box:updateList(list)
	end
	local function update()
		local sel = box:getSelected()
		if sel then
			local found = sel:match("%x+%-%x+%-%x+%-%x+%-%x+")
			if found then
				local amount = #interface.findComponents(mod, found)
				if amount == 1 then
					chosen.text = found
					ret = found
				elseif amount > 1 then
					chosen.text = "<niejednoznaczny>"
					ret = nil
				else
					chosen.text = "<nie znaleziono>"
					ret = nil
				end
				chosen:draw()
			end
		end
	end
	local dgui = gml.create("center", "center", 110, 27)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 23, "Okno wyboru komponentu")
	box = dgui:addListBox(2, 3, 104, 15, {})
	local old = box.onClick
	box.onClick = function(...)
		old(...)
		update()
	end
	dgui:addLabel(5, 20, 15, "Wybrany adres:")
	chosen = dgui:addLabel(21, 20, 40, "")
	dgui:addButton(90, 24, 14, 1, "Anuluj", function()
		ret = nil
		dgui:close()
	end)
	dgui:addButton(74, 24, 14, 1, "Zatwierdź", function()
		dgui:close()
	end)
	refreshList()
	dgui:run()
	return ret
end

--[[
Wyświetla okno dialogowe wyboru koloru
	@mod - moduł wywołujący
	@hex:boolean - czy zwrócić wybrany kolor w formacie hexadecymalnym
	@api:boolean - czy zwrócić wybrany kolor w formacie api colors
	@name:boolean - czy zwrócić wybrany kolor w formie tekstu
	RET:{[hex], [colors]} or nil
]]
interface.colorDialog = function(mod, hex, api, name)
	local color = nil
	local rettab = {}
	local bar = nil
	local eqs = {
		[0] = 0xFFFFFF,
		[1] = 0xFFA500,
		[2] = 0xFF00FF,
		[3] = 0xADD8E6,
		[4] = 0xFFFF00,
		[5] = 0x00FF00,
		[6] = 0xFFC0CB,
		[7] = 0x808080,
		[8] = 0xC0C0C0,
		[9] = 0x00FFFF,
		[10] = 0x800080,
		[11] = 0x0000FF,
		[12] = 0xA52A2A,
		[13] = 0x008000,
		[14] = 0xFF0000,
		[15] = 0x000000
	}
	local function updateBar(new)
		color = new
		bar.color = eqs[new]
		bar:draw()
	end
	local cgui = gml.create("center", "center", 32, 25)
	cgui.style = gui.style
	cgui:addLabel("center", 1, 14, "Wybierz kolor")
	for i = 0, 15 do
		local tmp = cgui:addLabel(3, 4 + i, 12, colors[i])
		tmp.onClick = function() updateBar(i) end
	end
	bar = interface.template(mod, cgui, 20, 4, 3, 16)
	bar.draw = function(t)
		if t.color then
			t.renderTarget.setBackground(t.color)
			t.renderTarget.fill(t.gui.posX + t.posX - 1, t.gui.posY + t.posY - 1, t.width, t.height, " ")
		end
	end
	cgui:addButton(1, 23, 14, 1, "Zatwierdź", function()
		if hex then table.insert(rettab, eqs[color]) end
		if api then table.insert(rettab, color) end
		if name then table.insert(rettab, colors[i]) end
		cgui:close()
	end)
	cgui:addButton(16, 23, 14, 1, "Anuluj", function()
		rettab = nil
		cgui:close()
	end)
	cgui:run()
	return rettab
end

--[[
Tworzy szablon dla nowego komponentu
	@mod - moduł wywołujący
	@target - gui docelowe
	@x - pozycja X
	@y - pozycja Y
	@w - szerokość elementu
	@h - wysokość elementu
	RET: <szablon>
]]
interface.template = function(mod, target, x, y, w, h)
	local temp = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		horizontal = isHorizontal,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg")
	}
	temp.posX = x + 1
	temp.posY = y + 1
	temp.width = w
	temp.height = h
	temp.contains = GMLcontains
	temp.isHidden = function() return false end
	temp.draw = function() end
	target:addComponent(temp)
	return temp
end

--[[
Zwraca domyślny katalog modułu
	@mod - moduł wywołujący
	RET: ścieżka absolutna do katalogu
]]
interface.getConfigDirectory = function(mod)
	local dir = fs.concat(configDir .. "/modules", mod.name)
	if not fs.isDirectory(dir) then fs.makeDirectory(dir) end
	return dir
end

--[[
Zwraca klucz szyfrujący
	@mod - moduł wywołujący
	RET: klucz w formacie binarnym
]]
interface.secretKey = function(mod)
	return token
end

--[[
Zwraca styl używany przez okno głowne
	@mod - moduł wywołujący
	RET: tablica ze stylem
]]
interface.getStyle = function(mod)
	return gui.style
end

-- # Funkcje pomocnicze Gui
GMLmessageBox = function(target, message, buttons)
	local buttons = buttons or {"cancel", "ok"}
	local choice
	local lines = {}
	message:gsub("([^\n]+)", function(line) lines[#lines+1] = line end)
	local i = 1
	while i <= #lines do
		if #lines[i] > 46 then
			local s, rs = lines[i], lines[i]:reverse()
			local pos =- 26
			local prev = 1
			while #s > prev + 45 do
				local space = rs:find(" ", pos)
				if space then
					table.insert(lines, i, s:sub(prev, #s - space))
					prev = #s - space + 2
					pos =- (#s - space + 48)
				else
					table.insert(lines, i, s:sub(prev, prev + 45))
					prev = prev + 46
					pos = pos - 46
				end
				i = i + 1
			end
			lines[i] = s:sub(prev)
		end
		i = i + 1
	end

	local gui = gml.create("center", "center", 50, 6 + #lines, gpu)
	gui.style = target.style
	local labels = {}
	for i = 1, #lines do
		labels[i] = gui:addLabel(2, 1 + i, 46, lines[i])
	end
	local buttonObjs = {}
	local xpos = 2
	for i = 1, #buttons do
		if i == #buttons then xpos =- 2 end
		buttonObjs[i]=gui:addButton(xpos, -2, #buttons[i] + 2, 1, buttons[i], function() choice = buttons[i] gui.close() end)
		xpos = xpos + #buttons[i] + 3
	end

	gui:changeFocusTo(buttonObjs[#buttonObjs])
	gui:run()
	return choice
end

GMLcontains = function(element,x,y)
	local ex, ey, ew, eh = element.posX, element.posY, element.width, element.height
	return x >= ex and x <= ex + ew - 1 and y >= ey and y <= ey + eh - 1
end

GMLgetAppliedStyles = function(element)
	local styleRoot = element.style
	assert(styleRoot)

	local depth, state, class, elementType = element.renderTarget.getDepth(), element.state or "*", element.class or "*", element.type

	local nodes = {styleRoot}
	local function filterDown(nodes, key)
		local newNodes = {}
		for i = 1, #nodes do
			if key ~= "*" and nodes[i][key] then
				newNodes[#newNodes + 1] = nodes[i][key]
			end
			if nodes[i]["*"] then
				newNodes[#newNodes + 1] = nodes[i]["*"]
			end
		end
		return newNodes
	end
	nodes = filterDown(nodes, depth)
	nodes = filterDown(nodes, state)
	nodes = filterDown(nodes, class)
	nodes = filterDown(nodes, elementType)
	return nodes
end

GMLextractProperty = function(element, styles, property)
	if element[property] then
		return element[property]
	end
	for j = 1, #styles do
		local v = styles[j][property]
		if v ~= nil then
			return v
		end
	end
end

GMLextractProperties = function(element, styles, ...)
	local props = {...}
	local vals = {}
	for i = 1, #props do
		vals[#vals + 1] = extractProperty(element, styles, props[i])
		if #vals ~= i then
			for k, v in pairs(styles[1]) do print('"' .. k .. '"', v, k == props[i] and "<-----!!!" or "") end
			error("Could not locate value for style property " .. props[i] .. "!")
		end
	end
	return table.unpack(vals)
end

GMLfindStyleProperties = function(element,...)
	local props = {...}
	local nodes = GMLgetAppliedStyles(element)
	return GMLextractProperties(element, nodes, ...)
end

GMLcalcBody = function(element)
	local x, y, w, h = element.posX, element.posY, element.width, element.height
	local border, borderTop, borderBottom, borderLeft, borderRight =
     GMLfindStyleProperties(element, "border", "border-top", "border-bottom", "border-left", "border-right")

	if border then
		if borderTop then
			y = y + 1
			h = h - 1
		end
		if borderBottom then
			h = h - 1
		end
		if borderLeft then
			x = x + 1
			w = w - 1
		end
		if borderRight then
			w = w - 1
		end
	end
	return x, y, w, h
end

local function addBar(target, x, y, length, isHorizontal)
	local bar = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		horizontal = isHorizontal,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg")
	}
	bar.posX = x
	bar.posY = y
	bar.width = isHorizontal and length or 1
	bar.height = isHorizontal and 1 or length
	bar.contains = GMLcontains
	bar.isHidden = function() return false end
	bar.draw = function(t)
		t.renderTarget.setBackground(t.bgcolor)
		t.renderTarget.setForeground(0xffffff)
		if t.horizontal then
			t.renderTarget.set(t.posX + 1, t.posY + 1, string.rep(uni.char(0x2550), t.width))
		else
			for i = 1, t.height do
				t.renderTarget.set(t.posX + 1, t.posY + i, uni.char(0x2551))
			end
		end
	end
	target:addComponent(bar)
	return bar
end

local function addSymbol(target, x, y, code)
	local symbol = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg"),
		code = code,
		posX = x,
		posY = y,
		width = 1,
		height = 1,
		contains = GMLcontains,
		isHidden = function() return false end
	}
	symbol.draw = function(t)
		t.renderTarget.setBackground(t.bgcolor)
		t.renderTarget.setForeground(0xffffff)
		t.renderTarget.set(t.posX, t.posY, uni.char(t.code))
	end
	target:addComponent(symbol)
	return symbol
end

local function addTitle(target, posX, posY)
	local title = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		posX = posX,
		posY = posY,
		width = 15,
		height = 5,
		contains = GMLcontains,
		isHidden = function() return false end
	}
	title.draw = function(t)
		t.renderTarget.setBackground(0x00a6ff)
		t.renderTarget.fill(t.posX, t.posY, 5, 1, ' ') --t
		t.renderTarget.fill(t.posX + 2, t.posY + 1, 1, 4, ' ')
		t.renderTarget.fill(t.posX + 9, t.posY, 4, 1, ' ') --g
		t.renderTarget.fill(t.posX + 9, t.posY + 4, 4, 1, ' ')
		t.renderTarget.fill(t.posX + 10, t.posY + 2, 3, 1, ' ')
		t.renderTarget.set(t.posX + 8, t.posY + 1, ' ')
		t.renderTarget.set(t.posX + 8, t.posY + 3, ' ')
		t.renderTarget.set(t.posX + 7, t.posY + 2, ' ')
		t.renderTarget.set(t.posX + 12, t.posY + 3, ' ')
	end
	target:addComponent(title)
	return title
end

-- # Inne funkcje
local function flushLog()
	local file = io.open("/tmp/tg.log", "a")
	if file then
		file:write(intlog)
		file:close()
		intlog = ""
	end
end

silentLog = function(source, description, disableTimer, color)
	local timer = disableTimer and "" or (os.date():sub(-8) .. " - ")
	local text = timer .. source .. ": " .. description
	intlog = intlog .. text .. "\n"
	loglines = loglines + 1
	if loglines > 20 then
		flushLog()
		loglines = 0
	end
	table.insert(lastlog, text)
	if #lastlog > 10 then table.remove(lastlog, 1) end
	return text
end

local function internalLog(source, description, disableTimer, color)
	local prev = nil
	if color then
		prev = component.gpu.setForeground(color)
	end
	print(silentLog(source, description, disableTimer, color))
	if color then
		component.gpu.setForeground(prev)
	end
end

local function isPasswordValid(plain)
	return data.sha256(plain) == passwd
end



-- # Konfiguracja
local save = {}

function save.log(silent, ...)
	if silent then
		silentLog(...)
		save.err()
	else
		internalLog(...)
	end
end

function save.err()
	GMLmessageBox(gui, "Wystąpił błąd podczas zapisu ustawień, sprawdź logi", {"OK"})
end

function save.settings(silent)
	local r, s = pcall(serial.serialize, settings)
	if r then
		local f, e = io.open("/etc/the_guard/config.conf", "w")
		if f then
			f:write(s)
			f:close()
		else
			save.log(silent, "save", "nie można otworzyć settings: " .. e)
			return false
		end
	else
		save.log(silent, "save", "błąd serializacji settings: " .. s)
		return false
	end
	return true
end

function save.modules(silent)
	local out = {}
	for z, t in pairs(modules) do
		out[z] = {file = t.file}
	end
	local r, s = pcall(serial.serialize, out)
	if r then
		local f, e = io.open("/etc/the_guard/modules.conf", "w")
		if f then
			f:write(s)
			f:close()
		else
			save.log(silent, "save", "nie można otworzyć modules: " .. e)
			return false
		end
	else
		save.log(silent, "save", "błąd serializacji modules: " .. s)
		return false
	end
	return true
end

function save.components(silent)
	local r, s = pcall(serial.serialize, components)
	if r then
		local f, e = io.open("/etc/the_guard/components.conf", "w")
		if f then
			f:write(s)
			f:close()
		else
			save.log(silent, "save", "nie można otworzyć components: " .. e)
			return false
		end
	else
		save.log(silent, "save", "błąd serializacji components: " .. s)
		return false
	end
	return true
end

function save.passwd(silent)
	local output = data.encode64(passwd)
	local f, e = io.open("/etc/the_guard/passwd.bin", "wb")
	if f then
		f:write(output)
		f:close()
	else
		save.log(silent, "save", "nie można otworzyć passwd: " .. e)
		return false
	end
	return true
end

local function saveConfig()
	if not save.settings() then
		internalLog("save", "zapis settings nieudany", false, 0xff0000)
	end
	if not save.modules() then
		internalLog("save", "zapis modules nieudany", false, 0xff0000)
	end
	if not save.components() then
		internalLog("save", "zapis components nieudany", false, 0xff0000)
	end
	if not save.passwd() then
		internalLog("save", "zapis passwd nieudany", false, 0xff0000)
	end
end

local function loadConfig()
	local function checkSettings()
		local dirty = false
		if not settings.port then
			settings.port = math.random(1000, 50000)
			dirty = true
		end
		if not settings.backupPort then
			settings.backupPort = math.random(1000, 50000)
			dirty = true
		end
		if not settings.debugMode then
			settings.debugMode = false
			dirty = true
		end
		if not settings.dark then
			settings.dark = false
			dirty = true
		end
		if dirty then
			save.settings(true)
		end
	end
	
	local function checkModules()
		local counter = 0
		for i, m in pairs(modules) do
			local added = true
			if type(i) ~= "number" then
				internalLog("checkModules", "niepoprawny identyfikator strefy")
				modules[i] = nil
				added = false
			else
				if type(m.file) == "string" then
					local path = m.file
					if not (fs.exists(path) and not fs.isDirectory(path)) then
						internalLog("checkModules", "plik nie istnieje")
						modules[i] = nil
						added = false
					end
				else
					internalLog("checkModules", "brak nazwy pliku")
					modules[i] = nil
					added = false
				end
			end
			if added then counter = counter + 1 end
		end
		internalLog("Sprawdzono " .. tostring(counter) .. " moduły/ów", "", true)
	end
	
	local function checkComponents()
		local counter = 0 
		for i, c in pairs(components) do
			if type(c["address"]) == "string" then
				if component.proxy(c["address"]) then
					if type(c["type"]) ~= "string" then
						internalLog("checkComponents", "niepoprawny typ")
						components[i]["type"] = ""
					end
					if type(c["state"]) ~= "boolean" then
						internalLog("checkComponents", "niepoprawny stan")
						components[i]["state"] = false
					end
					if not (type(c["x"]) == "number" or type(c["x"]) == "nil") then
						internalLog("checkComponents", "niepoprawny x")
						components[i]["x"] = nil
					end
					if not (type(c["y"]) == "number" or type(c["y"]) == "nil") then
						internalLog("checkComponents", "niepoprawny y")
						components[i]["y"] = nil
					end
					if not (type(c["z"]) == "number" or type(c["z"]) == "nil") then
						internalLog("checkComponents", "niepoprawny z")
						components[i]["z"] = nil
					end
				else
					internalLog("checkComponents", "urządzenie " .. c["address"] .. " jest offline")
					components[i].state = false
				end
			else
				internalLog("checkComponents", "niepoprawny format adresu")
				if type(i) == "number" then
					table.remove(components, i)
				else
					components[i] = nil
				end
			end
			counter = counter + 1
		end
		internalLog("Sprawdzono " .. tostring(counter) .. " komponenty/ów", "", true)
	end
	
	local function checkPassword()
		if not passwd or passwd:len() == 0 then
			local prev = component.gpu.setForeground(0xff0000)
			print("Brak hasła głównego, podaj nowe hasło")
			component.gpu.setForeground(prev)
			local i1, i2 = "", ""
			local text = require("text")
			repeat
				io.write("#> ")
				i1 = term.read(nil, nil, nil, "*")
				i1 = text.trim(i1)
				print("Powtórz hasło:")
				io.write("#> ")
				i2 = term.read(nil, nil, nil, "*")
				i2 = text.trim(i2)
				if i1 ~= i2 then
					local prev = component.gpu.setForeground(0xffff00)
					print("Wprowadzono różne hasła, wprowadź hasło ponownie:")
					component.gpu.setForeground(prev)
				end
			until i1 == i2
			passwd = data.sha256(i1)
			local f, e = io.open("/etc/the_guard/passwd.bin", "wb")
			if f then
				f:write(data.encode64(passwd))
				f:close()
			else
				internalLog("passwd", "Nie udało się zapisać hasła: " .. e)
				return false
			end
		end
		
		return true
	end

	local dir = "/etc/the_guard/"
	internalLog("Wczytywanie ustawień", "", true)
	local path = fs.concat(dir, "/config.conf")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "r")
		if f then
			local s = serial.unserialize(f:read("*a"))
			if s then
				settings = s
			else
				internalLog("loadConfig", "plik settings uszkodzony lub pusty", false, 0xffff00)
			end
			f:close()
		else
			internalLog("loadConfig", "błąd pliku settings: " .. e, false, 0xff0000)
			return false
		end
	else
		internalLog("loadConfig", "brak pliku settings, tworzenie ustawień")
	end
	checkSettings()
	
	path = fs.concat(dir, "modules.conf")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "r")
		if f then
			local s = serial.unserialize(f:read("*a"))
			if s then
				modules = s
			else
				internalLog("loadConfig", "plik modules uszkodzony lub pusty",  false, 0xffff00)
			end
			f:close()
		else
			internalLog("loadConfig", "błąd pliku modules: " .. e, false, 0xff0000)
			return false
		end
	else
		internalLog("loadConfig", "brak pliku modules, tworzenie listy")
	end
	checkModules()
	
	path = fs.concat(dir, "components.conf")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "r")
		if f then
			local s = serial.unserialize(f:read("*a"))
			if s then
				components = s
			else
				internaLog("loadConfig", "plik components uszkodzony lub pusty", false, 0xffff00)
			end
			f:close()
		else
			internalLog("loadConfig", "błąd pliku components: " .. e, false, 0xff0000)
			return false
		end
	else
		internalLog("loadConfig", "brak pliku components, tworzenie listy")
	end
	checkComponents()
	
	path = fs.concat(dir, "passwd.bin")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "rb")
		if f then
			passwd = data.decode64(f:read("*a"))
			f:close()
		else
			internalLog("passwd", "nie udało się otworzyć pliku: " .. e)
			f:close()
			return false
		end
	else
		internalLog("passwd", "brak pliku passwd, tworzenie nowego")
	end
	if not checkPassword() then return false end
	
	return true
end

-- # Funkcje przycisków
local function passwordPrompt()
	local status = false
	local function insertTextTF(tf, text)
		if tf.selectEnd ~= 0 then
			tf:removeSelected()
		end
		tf.real = tf.real:sub(1, tf.cursorIndex - 1) .. text .. tf.real:sub(tf.cursorIndex)
		tf.text = string.rep("*", #tf.real)
		tf.cursorIndex = tf.cursorIndex + #text
		if tf.cursorIndex - tf.scrollIndex + 1 > tf.width then
			local ts = tf.scrollIndex + math.floor(tf.width / 3)
			if tf.cursorIndex - ts + 1 > tf.width then
				ts = tf.cursorIndex - tf.width + math.floor(tf.width / 3)
			end
			tf.scrollIndex = ts
		end
	end
	local pgui = gml.create("center", "center", 50, 8)
	if gui then
		pgui.style = gui.style
	end
	pgui:addLabel("center", 1, 16, "Wprowadź hasło:")
	local field = pgui:addTextField("center", 3, 30)
	field.real = ""
	field.insertText = insertTextTF
	pgui:addButton(20, 5, 12, 1, "OK", function() 
		if isPasswordValid(field.real) then
			status = true
		end
		pgui:close()
	end)
	pgui:addButton(34, 5, 12, 1, "Anuluj", function() pgui:close() end)
	pgui:run()
	return status
end

local function componentDetails(t)
	local dgui = gml.create("center", "center", 55, 16)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 22, "Szczegóły komponentu")
	dgui:addLabel(2, 3, 48, "Adres:      " .. t.address)
	dgui:addLabel(2, 4, 48, "Typ:        " .. t.type)
	dgui:addLabel(2, 5, 7, "Nazwa:")
	local name = dgui:addTextField(14, 5, 20)
	name.text = t.name or ""
	dgui:addLabel(2, 6, 9, "Status:")
	local avail = dgui:addLabel(2, 7, 22, "")
	dgui:addLabel(2, 9, 17, "Współrzędna X:")
	dgui:addLabel(2, 10, 17, "Współrzędna Y:")
	dgui:addLabel(2, 11, 17, "Współrzędna Z:")
	local cx = dgui:addTextField(20, 9, 10)
	local cy = dgui:addTextField(20, 10, 10)
	local cz = dgui:addTextField(20, 11, 10)
	cx.text = t.x and tostring(t.x) or ""
	cy.text = t.y and tostring(t.y) or ""
	cz.text = t.z and tostring(t.z) or ""
	local button = dgui:addButton(11, 6, 13, 1, "włączony", function(self)
		if self.status then
			self.text = "wyłączony"
			self.status = false
			self:draw()
		else
			self.text = "włączony"
			self.status = true
			self:draw()
		end
	end)
	button.status = t.state
	local function refreshAvail()
		if component.proxy(t.address) then
			avail.text = "Dostępność: online"
		else
			avail.text = "Dostępność: offline"
			button.status = false
			button.text = "wyłączony"
			button:draw()
		end
		avail:draw()
	end
	refreshAvail()
	dgui:addButton(25, 7, 12, 1, "Odśwież", refreshAvail)
	dgui:addButton(4, 14, 14, 1, "Usuń", function()
		if GMLmessageBox(gui, "Czy na pewno chcesz usunąć ten element?", {"Tak", "Nie"}) == "Tak" then
			for i, t2 in pairs(components) do
				if t.address == t2.address then
					components[i] = nil
					save.components(true)
					dgui:close()
					break
				end
			end
		end
	end)
	dgui:addButton(20, 14, 14, 1, "Zapisz", function()
		local nx = tonumber(cx.text)
		local ny = tonumber(cy.text)
		local nz = tonumber(cz.text)
		if not nx and cx.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna X jest niepoprawna", {"OK"})
		elseif not ny and cy.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna Y jest niepoprawna", {"OK"})
		elseif not nz and cz.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna Z jest niepoprawna", {"OK"})
		elseif name.text:len() > 20 then
			GMLmessageBox(gui, "Nazwa nie może być dłuższa, niż 20 znaków.", {"OK"})
		else
			t.state = button.status
			t.name = name.text
			t.x = nx
			t.y = ny
			t.z = nz
			save.components(true)
			dgui:close()
		end
	end)
	dgui:addButton(36, 14, 14, 1, "Anuluj", function() dgui:close() end)
	dgui:run()
end

local function bComponentList()
	local list, tab = nil, nil
	local function refreshList()
		local buffer = {}
		for _, t in pairs(components) do
			if not buffer[t.type] then buffer[t.type] = {} end
			local str = t.address .. ", "
			if t.name and t.name:len() > 0 then
				str = str .. "[" .. t.name .. "] "
			end
			str = str .. (t.state and "ON" or "OFF")
			if t.x then str = str .. "  X:" .. tostring(t.x) end
			if t.y then str = str .. "  Y:" .. tostring(t.y) end
			if t.z then str = str .. "  Z:" .. tostring(t.z) end
			if not component.proxy(t.address) then str = "*" .. str end
			table.insert(buffer[t.type], str)
		end
		local buffer2 = {}
		for a, b in pairs(buffer) do
			table.insert(buffer2, {a, b})
		end
		table.sort(buffer2, function(a, b) return string.byte(a[1], 1) < string.byte(b[1], 1) end)
		tab = {}
		for _, t in pairs(buffer2) do
			table.insert(tab, string.upper(t[1]) .. ":")
			for _, l in pairs(t[2]) do
				table.insert(tab, "  " .. l)
			end
		end
	end
	local function enableAll()
		for _, t in pairs(components) do
			if component.proxy(t.address) then t.state = true end
		end
		refreshList()
		list:updateList(tab)
		save.components(true)
		computer.pushSignal("components_changed")
	end
	local function disableAll()
		for _, t in pairs(components) do
			t.state = false
		end
		refreshList()
		list:updateList(tab)
		save.component(true)
		computer.pushSignal("components_changed")
	end
	local function deleteOffline()
		if GMLmessageBox(gui, "Czy na pewno chcesz usunąć urządzenia, które są offline?", {"Tak", "Nie"}) == "Tak" then
			for i, t in pairs(components) do
				if not component.proxy(t.address) then components[i] = nil end
			end
			refreshList()
			list:updateList(tab)
			save.components(true)
			computer.pushSignal("components_changed")
		end
	end
	local function reloadList()
		refreshList()
		list:updateList(tab)
	end
	local function details()
		local addr = list:getSelected():match("^%s%s%**(%x+%-%x+%-%x+%-%x+%-%x+),.+")
		if addr then
			for _, t in pairs(components) do
				if t.address == addr then
					componentDetails(t)
					break
				end
			end
		end
		refreshList()
		list:updateList(tab)
		computer.pushSignal("components_changed")
	end
	
	refreshList()
	local cgui = gml.create("center", "center", 90, 30)
	cgui.style = gui.style
	cgui:addLabel("center", 1, 25, "Zainstalowane komponenty")
	list = cgui:addListBox(2, 3, 84, 20, tab)
	list.onDoubleClick = details
	cgui:addLabel(68, 23, 13, "* - offline")
	cgui:addButton(3, 25, 21, 1, "Włącz wszystkie", enableAll)
	cgui:addButton(3, 27, 21, 1, "Wyłącz wszystkie", disableAll)
	cgui:addButton(26, 27, 18, 1, "Usuń offline", deleteOffline)
	cgui:addButton(54, 27, 14, 1, "Odżwież", reloadList)
	cgui:addButton(70, 27, 14, 1, "Zamknij", function() cgui:close() end)
	cgui:run()
end

local function addCreator(address, typee)
	local agui = gml.create("center", "center", 52, 15)
	agui.style = gui.style
	agui:addLabel("center", 1, 29, "Kreator dodawania komponentu")
	agui:addLabel(2, 3, 48, "Adres:  " .. address)
	agui:addLabel(2, 4, 48, "Typ:    " .. typee)
	agui:addLabel(2, 5, 7, "Nazwa:")
	agui:addLabel(2, 6, 9, "Status:")
	agui:addLabel(2, 8, 17, "Współrzędna X:")
	agui:addLabel(2, 9, 17, "Współrzędna Y:")
	agui:addLabel(2, 10, 17, "Współrzędna Z:")
	local name = agui:addTextField(11, 5, 22)
	local cx = agui:addTextField(20, 8, 10)
	local cy = agui:addTextField(20, 9, 10)
	local cz = agui:addTextField(20, 10, 10)
	local button = agui:addButton(11, 6, 13, 1, "włączony", function(self)
		if self.status then
			self.text = "wyłączony"
			self.status = false
			self:draw()
		else
			self.text = "włączony"
			self.status = true
			self:draw()
		end
	end)
	button.status = true
	agui:addButton(20, 13, 14, 1, "Zapisz", function()
		local nx = tonumber(cx.text)
		local ny = tonumber(cy.text)
		local nz = tonumber(cz.text)
		if not nx and cx.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna X jest niepoprawna", {"OK"})
		elseif not ny and cy.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna Y jest niepoprawna", {"OK"})
		elseif not nz and cz.text:len() > 0 then
			GMLmessageBox(gui, "Współrzędna Z jest niepoprawna", {"OK"})
		elseif name.text:len() > 20 then
			GMLmessageBox(gui, "Nazwa komponentu nie może być dłuższa, niż 20 znaków.", {"OK"})
		else
			local t = {
				address = address,
				type = typee,
				name = name.text,
				state = button.status,
				x = nx,
				y = ny,
				z = nz
			}
			table.insert(components, t)
			save.components(true)
			agui:close()
		end
	end)
	agui:addButton(36, 13, 14, 1, "Anuluj", function() agui:close() end)
	agui:run()
end

local function bNewComponent()
	local list, tab = nil, nil
	local function isAdded(address)
		for _, t in pairs(components) do
			if t.address == address then return true end
		end
		return false
	end
	local function reloadList()
		tab = {}
		for addr, name in component.list() do
			if not isAdded(addr) then
				table.insert(tab, addr .. "   " .. name)
			end
		end
	end
	local function addComponent()
		local addr, typ = list:getSelected():match("^(%x+%-%x+%-%x+%-%x+%-%x+)%s%s%s(.+)")
		if addr and typ then
			addCreator(addr, typ)
			reloadList()
			list:updateList(tab)
		end
	end
	reloadList()
	local ngui = gml.create("center", "center", 70, 30)
	ngui.style = gui.style
	ngui:addLabel("center", 1, 21, "Dodaj nowy komponent")
	list = ngui:addListBox(2, 3, 64, 23, tab)
	list.onDoubleClick = addComponent
	ngui:addButton(36, 28, 14, 1, "Odśwież", function()
		reloadList()
		list:updateList(tab)
	end)
	ngui:addButton(52, 28, 14, 1, "Wyjście", function() ngui:close() end)
	ngui:run()
end

local function bModuleList()
	local changeg = false
	local llist, rlist = nil, nil
	local ltab, rtab = {}, {}
	
	local function refTabs()
		ltab = {}
		for i = 1, 4 do
			if modules[i] then
				if #ltab == 0 then table.insert(ltab, "  NORMAL:") end
				table.insert(ltab, tostring(i) .. ". " .. modules[i].name .. ", " .. modules[i].version)
			end
		end
		if modules[5] then
			if #ltab > 0 then table.insert(ltab, "") end
			table.insert(ltab, "  LANDSCAPE:")
			table.insert(ltab, "5. " .. modules[5].name .. ", " .. modules[5].version)
		end
		
		rtab = {}
		local n, l = {}, {}
		for _, t in pairs(pmodules) do
			if t.shape == "normal" then
				table.insert(n, t.name .. ", " .. t.version)
			elseif t.shape == "landscape" then
				table.insert(l, t.name .. ", " .. t.version)
			end
		end
		if #n > 0 then
			table.insert(rtab, "  normal")
			for _, e in pairs(n) do table.insert(rtab, e) end
		end
		if #l > 0 then
			if #n > 0 then table.insert(rtab, "") end
			for _, e in pairs(l) do table.insert(rtab, e) end
		end
		
		if #ltab == 0 then table.insert(ltab, "") end
		if #rtab == 0 then table.insert(rtab, "") end
	end
	
	local function up()
		if #ltab > 1 then
			local num = tonumber(llist:getSelected():match("^(%d)%. .+"))
			if num and num > 1 and num < 5 then
				if modules[num - 1] then
					local buffer = modules[num - 1]
					modules[num - 1] = modules[num]
					modules[num] = buffer
				else
					modules[num - 1] = modules[num]
					modules[num] = nil
				end
				refTabs()
				llist:updateList(ltab)
				changed = true
			end
		end
	end
	
	local function down()
		if #ltab > 1 then
			local num = tonumber(llist:getSelected():match("^(%d)%. .+"))
			if num and num > 0 and num < 4 then
				if modules[num + 1] then
					local buffer = modules[num + 1]
					modules[num + 1] = modules[num]
					modules[num] = buffer
				else
					modules[num + 1] = modules[num]
					modules[num] = nil
				end
				refTabs()
				llist:updateList(ltab)
				changed = true
			end
		end
	end
	
	local function getIndex(pname)
		if not pname then return nil end
		for i, t in pairs(pmodules) do
			if t.name == pname then return i end
		end
		return nil
	end
	
	local function toLeft()
		local index = getIndex(rlist:getSelected():match("^(.+), .+"))
		if index and pmodules[index].shape == "normal" then
			local free = nil
			for i = 1, 4 do
				if not modules[i] then free = i break end
			end
			if free then
				modules[free] = pmodules[index]
				pmodules[index] = nil
				refTabs()
				llist:updateList(ltab)
				rlist:updateList(rtab)
				changed = true
			else
				GMLmessageBox(gui, "Brak wolnych stref", {"OK"})
			end
		elseif index and pmodules[index].shape == "landscape" then
			if not modules[5] then
				modules[5] = pmodules[index]
				pmodules[index] = nil
				refTabs()
				llist:updateList(ltab)
				rlist:updateList(rtab)
				changed = true
			else
				GMLmessageBox(gui, "Brak wolnych stref", {"OK"})
			end
		end
	end
	
	local function toRight()
		local num = tonumber(llist:getSelected():match("^(%d)%. .+"))
		if num then
			table.insert(pmodules, modules[num])
			modules[num] = nil
			refTabs()
			llist:updateList(ltab)
			rlist:updateList(rtab)
			changed = true
		end
	end
	refTabs()
	local mgui = gml.create("center", "center", 90, 24)
	mgui.style = gui.style
	mgui:addLabel("center", 1, 15, "Lista modułów")
	mgui:addLabel(3, 3, 17, "Aktywne moduły:")
	mgui:addLabel(57, 3, 20, "Nieaktywne moduły:")
	llist = mgui:addListBox(3, 5, 30, 14, ltab)
	rlist = mgui:addListBox(57, 5, 30, 14, rtab)
	mgui:addButton(35, 8, 9, 1, "-->", toRight)
	mgui:addButton(46, 8, 9, 1, "<--", toLeft)
	mgui:addButton(35, 12, 6, 1, "/\\", up)
	mgui:addButton(35, 14, 6, 1, "\\/", down)
	mgui:addButton(71, 21, 14, 1, "Zamknij", function() mgui:close() end)

	mgui:run()
	if changed then
		save.modules(true)
		GMLmessageBox(gui, "Zmiany zostaną wprowadzone po restarcie serwera", {"OK"})
	end
end

local function componentDistribution()
	local list, all, tab = nil, nil
	local function refreshList()
		local buffer = {}
		local total = 0
		for _, c in pairs(component.list()) do
			if not buffer[c] then buffer[c] = 0 end
			buffer[c] = buffer[c] + 1
			total = total + 1
		end
		local b2 = {}
		for a, b in pairs(buffer) do
			table.insert(b2, {a, b})
		end
		table.sort(b2, function(a, b) return a[1]:byte(1) < b[1]:byte(1) end)
		tab = {}
		for _, t in pairs(b2) do
			table.insert(tab, t[1]:upper() .. ": " .. tostring(t[2]))
		end
		all.text = "Razem: " .. tostring(total)
	end
	local dgui = gml.create("center", "center", 50, 18)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 21, "Rozkład komponentów")
	all = dgui:addLabel(4, 13, 15, "")
	refreshList()
	list = dgui:addListBox(2, 3, 44, 9, tab)
	dgui:addButton(18, 15, 14, 1, "Odśwież", function()
		refreshList()
		list:updateList(tab)
		all:draw()
	end)
	dgui:addButton(34, 15, 14, 1, "Zamknij", function() dgui:close() end)
	dgui:run()
end

local function bInformation()
	local igui = gml.create("center", "center", 50, 11)
	igui.style = gui.style
	igui:addLabel("center", 1, 11, "Informacje")
	igui:addLabel(2, 3, 14, "Użycie dysku:")
	igui:addLabel(2, 4, 16, "Użycie pamięci:")
	igui:addLabel(2, 5, 23, "Podłączone komponenty:")
	igui:addLabel(2, 6, 18, "Dostępna energia:")
	local iHdd = igui:addLabel(26, 3, 20, "")
	local iMem = igui:addLabel(26, 4, 20, "")
	local iCom = igui:addLabel(26, 5, 20, "")
	local iEne = igui:addLabel(26, 6, 20, "")
	local function refreshInformation()
		local fs = component.proxy(computer.getBootAddress())
		if fs then
			local a = math.ceil(fs.spaceUsed() / 1024)
			local b = math.ceil(fs.spaceTotal() / 1024)
			local str = tostring(math.ceil(a / b * 100)) .. "%  "
			str = str .. tostring(a) .. "/" .. tostring(b) .. "KB"
			iHdd.text = str
		else
			iHdd.text = "<niedostępne>"
		end
		iHdd:draw()
		local total = math.ceil(computer.totalMemory() / 1024)
		local free = total - math.ceil(computer.freeMemory() / 1024)
		local str = tostring(math.ceil(free / total * 100)) .. "%  "
		str = str .. tostring(free) .. "/" .. tostring(total) .. "KB"
		iMem.text = str
		iMem:draw()
		local camount = 0
		for _, _ in component.list() do camount = camount + 1 end
		iCom.text = tostring(camount)
		iCom:draw()
		iEne.text = tostring(math.ceil(computer.energy() / computer.maxEnergy() * 100)) .. "%"
		iEne:draw()
	end
	iCom.onDoubleClick = componentDistribution
	refreshInformation()
	igui:addButton(18, 8, 14, 1, "Odśwież", refreshInformation)
	igui:addButton(34, 8, 14, 1, "Zamknij", function() igui:close() end)
	igui:run()
end

local function backup(port)
	if GMLmessageBox(gui, "Czy na pewno chcesz wykonać kopię zapasową", {"Tak", "Nie"}) == "Nie" then
		return
	end
	if not dsapi.echo(port or 1) then
		GMLmessageBox(gui, "Serwer danych nie został odnaleziony.", {"OK"})
		return
	end
	
	local list = {}
	local function updateList(path)
		local iter, err = fs.list(fs.concat("/etc", path))
		if not iter then
			GMLmessageBox(gui, "Nie udało się wykonać listy elementów: " .. err, {"OK"})
			return false
		end
		for s in iter do
			local subpath = fs.concat(path, s)
			if s:sub(-1) == "/" then
				if not updateList(subpath) then return false end
			else
				table.insert(list, subpath)
			end
		end
		return true
	end
	local bgui
	local function beginBackup()
		local maxx = #list
		local success = true
		local errormsg = ""
		for _, t in pairs(list) do
			local file, e = io.open(fs.concat("/etc", t), "r")
			if file then
				local status, err = dsapi.write(port, t, file:read("*a"))
				file:close()
				if not status then
					errormsg = dsapi.translateCode(err)
					success = false
					break
				end
			else
				errormsg = e
				success = false
				break
			end
		end
		if success then
			GMLmessageBox(gui, "Kopia zapasowa wykonana pomyślnie!", {"OK"})
		else
			GMLmessageBox(gui, "Nie udało się wykonać kopii zapasowej: " .. errormsg, {"OK"})
		end
		bgui:close()
	end
	if updateList("/the_guard") then
		bgui = gml.create("center", "center", 60, 7)
		bgui.style = gui.style
		bgui:addLabel("center", 2, 44, "Podczas wykonywania kopii zapasowej program")
		bgui:addLabel("center", 3, 22, "może nie odpowiadać.")
		bgui:addButton("center", 5, 14, 1, "Start", beginBackup)
		bgui:run()
	end
end

local function restore(port)
	if GMLmessageBox(gui, "Czy na pewno chcesz przywrócić dane z kopii zapasowej?", {"Tak", "Nie"}) == "Nie" then
		return
	end
	if not dsapi.echo(port or 1) then
		GMLmessageBox(gui, "Serwer danych nie został odnaleziony.", {"OK"})
		return
	end
	
	local function createList(list, path)
		local status, iter = dsapi.list(port, path)
		if status then
			for name, size in iter do
				local subpath = fs.concat(path, name)
				if size == -1 then
					local a, b = createList(list, subpath)
					if not a then return false, b end
				else
					table.insert(list, subpath)
				end
			end
		else
			return false, dsapi.translateCode(iter)
		end
		return true
	end
	local function checkDirectory(path)
		local segments = fs.segments(path)
		table.remove(segments, #segments)
		local subpath = ""
		for _, t in pairs(segments) do subpath = subpath .. "/" .. t end
		if not fs.isDirectory(subpath) then
			fs.makeDirectory(subpath)
		end
	end
	local rgui = nil
	local function beginRestore()
		local list = {}
		local status, e = createList(list, "/the_guard")
		local success = true
		if status then
			for _, t in pairs(list) do
				local s2, content = dsapi.get(port, t)
				if s2 then
					local subpath = fs.concat("/etc", t)
					checkDirectory(subpath)
					local file, e2 = io.open(subpath, "w")
					if file then
						file:write(content)
						file:close()
					else
						success = false
						GMLmessageBox(gui, "Nie udało się utworzyć pliku: " .. e2, {"OK"})
						break
					end
				else
					success = false
					GMLmessageBox(gui, "Nie udało się przywrócić danych: " .. dsapi.translateCode(content), {"OK"})
					break
				end
			end
		else
			success = false
			GMLmessageBox(gui, "Nie udało się utworzyć listy plików: " .. e, {"OK"})
		end
		if success then
			GMLmessageBox(gui, "Przywracanie danych zakończone sukcesem. Teraz następi ponowne uruchomienie komputera.", {"OK"})
			computer.shutdown(true)
		end
		rgui:close()
	end
	
	rgui = gml.create("center", "center", 60, 8)
	rgui.style = gui.style
	rgui:addLabel("center", 2, 44, "Podczas przywracania danych program")
	rgui:addLabel("center", 3, 47, "może nie odpowiadać. Po zakończeniu komputer")
	rgui:addLabel("center", 4, 30, "zostanie uruchomiony ponownie")
	rgui:addButton("center", 6, 14, 1, "Start", beginRestore)
	rgui:run()
end

local function bSettings()
	local sgui = gml.create("center", "center", 60, 13)
	sgui.style = gui.style
	sgui:addLabel("center", 1, 11, "Ustawienia")
	sgui:addLabel(2, 3, 13, "Główny port:")
	sgui:addLabel(2, 4, 12, "Port kopii:")
	sgui:addLabel(2, 6, 18, "Tryb debugowania:")
	sgui:addLabel(2, 7, 14, "Ciemny motyw:")
	sgui:addLabel(2, 8, 23, "Zapis przy zamknięciu:")
	local mainport = sgui:addTextField(16, 3, 9)
	mainport.text = tostring(settings.port)
	local backupport = sgui:addTextField(16, 4, 9)
	backupport.text = tostring(settings.backupPort)
	local function switchState(self)
		if self.status then
			self.status = false
			self.text = "nie"
		else
			self.status = true
			self.text = "tak"
		end
		self:draw()
	end
	local function switchDebugMode(self)
		if not self.status then
			local mmsg =
[[
Aktywacja trybu debugowania sprawi,
że do włączenia programu nie będzie
wymagane podanie hasła.
Czy chcesz kontynuować?
]]
			if GMLmessageBox(gui, mmsg, {"Tak", "Nie"}) == "Nie" then return end
			switchState(self)
		else
			switchState(self)
		end
	end
	local bDebug = sgui:addButton(26, 6, 11, 1, "", switchDebugMode)
	bDebug.text = settings.debugMode and "tak" or "nie"
	bDebug.status = settings.debugMode
	local bDark = sgui:addButton(26, 7, 11, 1, "", switchState)
	bDark.text = settings.dark and "tak" or "nie"
	bDark.status = settings.dark
	local bSave = sgui:addButton(26, 8, 11, 1, "", switchState)
	bSave.text = settings.saveOnExit and "tak" or "nie"
	bSave.status = settings.saveOnExit
	sgui:addButton(41, 3, 16, 1, "Kopia", function()
		local n = tonumber(backupport.text)
		if n and n > 1 and n < 65535 then
			backup(n)
		else
			backup(nil)
		end
	end)
	sgui:addButton(41, 5, 16, 1, "Przywracanie", function()
		local n = tonumber(backupport.text)
		if n and n > 1 and n < 65535 then
			restore(n)
		else
			restore(nil)
		end
	end)
	sgui:addButton(27, 10, 14, 1, "Zapisz", function()
		local p1 = tonumber(mainport.text)
		local p2 = tonumber(backupport.text)
		if not p1 then
			GMLmessageBox(gui, "Główny port jest nieprawidłowy", {"OK"})
		elseif p1 > 65535 or p1 < 1 then
			GMLmessageBox(gui, "Główny port wykracza poza zakres", {"OK"})
		elseif not p2 then
			GMLmessageBox(gui, "Port kopii jest nieprawidłowy", {"OK"})
		elseif p2 > 65535 or p2 < 1 then
			GMLmessageBox(gui, "Port kopii wykracza poza zakres", {"OK"})
		else
			local p1open, p2open = false, false
			if modem and modem.isOpen(p1) then
				modem.close(p1)
				p1open = true
			end
			if modem and modem.isOpen(p2) then
				modem.close(p2)
				p2open = true
			end
			settings.port = p1
			settings.backupPort = p2
			settings.debugMode = bDebug.status
			settings.dark = bDark.status
			settings.saveOnExit = bSave.status
			if p1open and modem then modem.open(p1) end
			if p2open and modem then modem.open(p2) end
			save.settings(true)
			sgui:close()
		end
	end)
	sgui:addButton(43, 10, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:run()
end

local function bLogs()
	local ll, list = {}, nil
	local function refresh()
		ll = {}
		for _, s in pairs(lastlog) do
			table.insert(ll, s:sub(1, 82))
		end
	end
	local function details()
		local line = nil
		for _, s in pairs(lastlog) do
			if s:sub(1, 20) == list:getSelected():sub(1, 20) then
				line = s
				break
			end
		end
		if line then
			local buffer = {}
			local count = 0
			for i = 1, line:len(), 85 do
				count = count + 1
				if i < line:len() then 
					if count < 10 then
						local tmp = line:sub(i, i + 85)
						if count > 1 then
							tmp = "   " .. tmp
						end
						table.insert(buffer, tmp)
					else
						table.insert(buffer, "(...)")
						break
					end
				else
					break
				end
			end
			local dgui = gml.create("center", "center", 110, 6 + #buffer)
			dgui.style = gui.style
			dgui:addLabel("center", 1, 11, "Szczegóły")
			for i = 1, #buffer do
				dgui:addLabel(2, 2 + i, 90, buffer[i])
			end
			dgui:addButton(92, 4 + #buffer, 14, 1, "Zamknij", function() dgui:close() end)
			dgui:run()
			refresh()
			list:updateList(ll)
		end
	end
	refresh()
	local lgui = gml.create("center", "center", 90, 18)
	lgui.style = gui.style
	lgui:addLabel("center", 1, 14, "Ostatnie logi")
	list = lgui:addListBox(3, 3, 84, 12, ll)
	list.onDoubleClick = details
	lgui:addButton(55, 17, 14, 1, "Odśwież", function()
		refresh()
		list:updateList(ll)
	end)
	lgui:addButton(71, 17, 14, 1, "Zamknij", function() lgui:close() end)
	lgui:run()
end

local function bLock()
	if settings.debugMode then return end
	local lgui = gml.create(1, 1, resolution[1], resolution[2])
	lgui.style = gui.style
	lgui:addLabel("center", 23, 26, " << PROGRAM ZABLOKOWANY >>")
	lgui:addButton("center", 25, 16, 3, "ODBLOKUJ", function()
		if passwordPrompt() then
			lgui:close()
		else
			GMLmessageBox(lgui, "Wprowadzone hasło jest niepoprawne.", {"OK"})
		end
	end)
	lgui:run()
end

-- # Zabezpieczenia przed crashami
local function safeCall(fun, ...)
	local s, r = pcall(fun, ...)
	if not s then
		GMLmessageBox(gui, "Wystąpił błąd podczas wykonywania programu.\nSzczegóły w logach.")
		silentLog("safeCall", r)
		gui:draw()
		return nil
	end
	return r
end

local function secureFunction(fun, ...)
	local s, r = pcall(fun, ...)
	if not s then
		GMLmessageBox(gui, "Wystąpił błąd podczas wykonywania funkcji modułu.\n.Szczegóły w logach.")
		silentLog("secureFunction", r)
		gui:draw()
		return nil
	end
	return r
end

local function errorHandler(err)
	internalLog("Wystąpił bład", err, false, 0xff0000)
	io.stderr:write(debug.traceback())
	print()
end

local function bExit(b)
	if not settings.debugMode then
		if not passwordPrompt() then
			GMLmessageBox(gui, "Podane hasło jest nieprawidłowe.", {"OK"})
			return
		end
	end
	gui:close()
end

-- # Main GUI
local function createMainGui()
	gui = gml.create(1, 1, resolution[1], resolution[2])
	
	if settings.dark then
		local s, r = pcall(gml.loadStyle, "dark")
		if s then
			gui.style = r
		else
			internalLog("gui", "nie można załadować ciemnego stylu", false, 0xffff00)
		end
	end
	
	addTitle(gui, 143, 3)
	gui:addLabel(150, 7, 8, "(" .. version .. ")")
	gui:addButton(141, 13, 16, 1, "Komponenty", function() safeCall(bComponentList) end)
	gui:addButton(141, 15, 16, 1, "Nowy komponent", function() safeCall(bNewComponent) end)
	gui:addButton(141, 17, 16, 1, "Moduły", function() safeCall(bModuleList) end)
	gui:addButton(141, 19, 16, 1, "Informacje", function() safeCall(bInformation) end)
	gui:addButton(142, 25, 14, 1, "Ustawienia", function() safeCall(bSettings) end)
	gui:addButton(142, 27, 14, 1, "Logi", function() safeCall(bLogs) end)
	gui:addButton(142, 29, 14, 1, "Blokada", function() safeCall(bLock) end)
	gui:addButton(142, 31, 14, 1, "Wyjście", function() safeCall(bExit) end)
	
	addBar(gui, 138, 1, 39, false)
	addBar(gui, 1, 40, 158, true)
	addBar(gui, 69, 1, 19, false)
	addBar(gui, 69, 21, 19, false)
	addBar(gui, 1, 20, 68, true)
	addBar(gui, 70, 20, 68, true)
	
	addSymbol(gui, 70, 1, 0x2566)
	addSymbol(gui, 139, 1, 0x2566)
	addSymbol(gui, 1, 21, 0x2560)
	addSymbol(gui, 1, 41, 0x2560)
	addSymbol(gui, 139, 21, 0x2563)
	addSymbol(gui, 160, 41, 0x2563)
	addSymbol(gui, 70, 41, 0x2569)
	addSymbol(gui, 139, 41, 0x2569)
	addSymbol(gui, 70, 21, 0x256c)
end

-- # Loader
local function initializeActions()
	actions = {}
	for _, t in pairs(modules) do
		local mul = mod[t.name].id * 100
		local buff = {}
		for n, at in pairs(mod[t.name].actions) do
			buff[n + mul] = at
		end
		actions[t.name] = buff
	end
end

local function loadModules()
	local function doActionValidation(ac)
		local davn = "action validator"
		local counter = 0
		for i, t in pairs(ac) do
			if type(i) ~= "number" then
				internalLog(davn, "niepoprawny identyfikator (" .. type(i) .. ")")
				return false
			elseif type(t["type"]) ~= "string" then
				internalLog(davn, "niepoprawny typ (" .. type(t["type"]) .. ")")
				return false
			elseif type(t["desc"]) ~= "string" then
				internalLog(davn, "niepoprawny opis (" .. type(t["desc"]) .. ")")
				return false
			elseif type(t["exec"]) ~= "function" then
				internalLog(davn, "brak definicji funkcji")
				return false
			elseif t["hidden"] and type(t["hidden"]) ~= "boolean" then
				internalLog(davn, "widoczność niezdefiniowana")
				return false
			end
			local p1t = type(t["p1type"])
			if p1t == "string" then
				if not (t["p1type"] == "number" or t["p1type"] == "string" or t["p1type"] == "table" or t["p1type"] == "function" or t["p1type"] == "nil") then
					internalLog(davn, "pierwszy typ niepoprawny (" .. t["p1type"] .. ")")
					return false
				end
				if type(t["p1desc"]) ~= "string" then
					internalLog(davn, "pierwszy opis jest pusty")
					return false
				end
			elseif p1t ~= "nil" then
				internalLog(davn, "pierwszy parametr niepoprawny (" .. p1t .. ")")
				return false
			end
			local p2t = type(t["p2type"])
			if p2t == "string" then
				if not (t["p2type"] == "number" or t["p2type"] == "string" or t["p2type"] == "table" or t["p2type"] == "function" or t["p2type"] == "nil") then
					internalLog(davn, "drugi typ niepoprawny (" .. t["p2type"] .. ")")
					return false
				end
				if type(t["p2desc"]) ~= "string" then
					internalLog(davn, "drugi opis jest pusty")
					return false
				end
			elseif p2t ~= "nil" then
				internalLog(davn, "drugi parametr niepoprawny (" .. p2t .. ")")
				return false
			end
			counter = counter + 1
		end
		internalLog(" zweryfikowano " .. tostring(counter) .. " akcji", "", true)
		return true
	end
	
	local function checkID(id)
		for _, t in pairs(mod) do
			if t.id == id then return false end
		end
		return true
	end
	
	local function doValidation(mo)
		local dvn = "validator"
		if type(mo.name) ~= "string" then
			internalLog(dvn, "brak nazwy")
			return false
		end
		if type(mo.version) ~= "string" then
			internalLog(dvn, "brak numeru wersji")
			return false
		elseif type(mo.id) ~= "number" then
			internalLog(dvn, "brak identyfikatora")
			return false
		elseif not checkID(mo.id) then
			internalLog(dvn, "identyfikator " .. tostring(mo.id) .. " jest już używany")
			return false
		elseif type(mo.apiLevel) ~= "number" then
			internalLog(dvn, "brak poziomu api")
			return false
		elseif mo.apiLevel < apiLevel then
			internalLog(dvn, "za stara wersja serwera")
			return false
		elseif type(mo.shape) ~= "string" then
			internalLog(dvn, "brak zdefiniowanego kształtu")
			return false
		elseif mo.shape ~= "normal" and mo.shape ~= "landscape" then
			internalLog(dvn, "nieprawidłowy kształt")
			return false
		elseif type(mo.setUI) ~= "function" then
			internalLog(dvn, "brak funkcji setUI()")
			return false
		elseif type(mo.start) ~= "function" then
			internalLog(dvn, "brak funkcji start()")
			return false
		elseif type(mo.stop) ~= "function" then
			internalLog(dvn, "brak funkcji stop()")
			return false
		elseif type(mo.pullEvent) ~= "function" then
			internalLog(dvn, "brak funkcji pullEvent()")
			return false
		elseif type(mo.actions) ~= "table" then
			internalLog(dvn, "brak zdefiniowanych akcji")
			return false
		elseif not doActionValidation(mo.actions) then
			return false
		end
		return true
	end
	
	local function loadModule(filename)
		local m, e = loadfile(filename)
		if m then
			local s, buffer = pcall(m)
			if s then
				if buffer and doValidation(buffer) then
					return buffer
				else
					internalLog("Moduł uszkodzony", "dezaktywacja", true, 0xff0000)
					return nil
				end
			else
				internalLog("Błąd składni", buffer, true, 0xff0000)
			end
		else
			internalLog("loader", "błąd ładowania: " .. e)
			return nil
		end
	end
	
	for num, tab in pairs(modules) do
		if type(num) ~= "number" then
			internalLog("loader", "nieprawidłowa strefa, wpis usunięty")
			modules[num] = nil
		elseif num > 0 and num < 6 then
			if type(tab.file) == "string" then
				local buffer = loadModule(tab.file)
				if buffer then
					if not mod[buffer.name] then
						if (buffer.shape == "normal" and (num > 0 and num < 5)) or (buffer.shape == "landscape" and num == 5) then
							mod[buffer.name] = buffer
							modules[num].name = buffer.name
							modules[num].version = buffer.version
							modules[num].shape = buffer.shape
							modules[num].id = buffer.id
						else
							internaLog("loader", "strefa nie odpowiada kształtowi")
							modules[num] = nil
						end
					else
						internalLog("loader", "moduł o nazwie " .. buffer.name .. " już istnieje", 0xffff00)
					end
				else
					modules[num] = nil
					table.insert(bmodules, tab.file)
				end
			else
				internalLog("loader", "wpis modułu uszkodzony, wpis usunięty")
				modules[num] = nil
			end
		end
	end
	initializeActions()
	
	local function isAdded(filename)
		local v1, v2 = false, false
		for _, t in pairs(modules) do
			if t.file == filename then
				v1 = true
				break
			end
		end
		for _, t in pairs(bmodules) do
			if t == filename then
				v2 = true
				break
			end
		end
		return v1 or v2
	end
	internalLog("Ładowanie niezainstalowanych modułów", "", true, 0x00a6ff)
	for n in fs.list(modulesDir) do
		local name = n:match("^mod_tg_(.+)%.lua$")
		if name and not isAdded(fs.concat(modulesDir, n)) then
			internalLog("  " .. name, "", true, 0xffff00)
			local buffer = loadModule(fs.concat(modulesDir, n))
			if buffer then
				local t = {
					name = buffer.name,
					file = fs.concat(modulesDir, n),
					version = buffer.version,
					shape = buffer.shape,
					id = buffer.id
				}
				table.insert(pmodules, t)
			end
		end
	end
end

-- #Nasłuchiwacze
backgroundListener = function(...)
	local params = {...}
	for m, t in pairs(events) do
		for _, n in pairs(t) do
			if params[1] == n and mod[m] then
				mod[m].pullEvent(...)
			end
		end
	end
end

local function getComponentID(addr)
	for i, t in pairs(components) do
		if t.address == addr then return i end
	end
	return nil
end

local function internalListener(...)
	local params = {...}
	if params[1] == "component_added" then
		local id = getComponentID(params[2])
		if id then
			components[id].state = true
		end
	elseif params[1] == "component_removed" then
		local id = getComponentID(params[2])
		if id then
			components[id].state = false
		end
	end
end

local function createGUI()
	local function calcPosition(x, y, width, height, maxWidth, maxHeight)
		width = math.min(width, maxWidth)
		height = math.min(height, maxHeight)

		if x == "left" then
			x = 1
		elseif x == "right" then
			x = maxWidth - width + 1
		elseif x == "center" then
			x = math.max(1, math.floor((maxWidth - width) / 2))
		elseif x < 0 then
			x = maxWidth - width + 2 + x
		elseif x < 1 then
			x = 1
		elseif x + width - 1 > maxWidth then
			x = maxWidth - width + 1
		end

		if y == "top" then
			y = 1
		elseif y == "bottom" then
			y = maxHeight - height + 1
		elseif y == "center" then
			y = math.max(1, math.floor((maxHeight - height) / 2))
		elseif y < 0 then
			y = maxHeight - height + 2 + y
		elseif y < 1 then
			y = 1
		elseif y + height - 1 > maxHeight then
			y = maxHeight - height + 1
		end

		return x, y, width, height
	end
	for z, t in pairs(modules) do
		if z > 0 and z < 6 then
			internalLog(t.name, "")
			local m = mod[t.name]
			if m then
				local coord = zones[z]
				local dim = m.shape == "normal" and zones.normal or zones.landscape
				local subgui = gml.create(coord[1], coord[2], dim[1] + 2, dim[2] + 2)
				local counter = 0
				subgui.addLabel = function(...)
					local aa = {...}
					local x, y, w = calcPosition(aa[2], aa[3], aa[4], 1, dim[1], dim[2])
					counter = counter + 1
					local g = gui:addLabel(x + coord[1] - 1, y + coord[2] - 1, w, aa[5])
					g.mark = true
					return g
				end
				subgui.addButton = function(...)
					local aa = {...}
					local x, y, w, h = calcPosition(aa[2], aa[3], aa[4], aa[5], dim[1], dim[2])
					counter = counter + 1
					local g = gui:addButton(x + coord[1] - 1, y + coord[2] - 1, w, h, aa[6], aa[7])
					g.mark = true
					return g
				end
				subgui.addTextField = function(...)
					local aa = {...}
					local x, y, w = calcPosition(aa[2], aa[3], aa[4], 1, dim[1], dim[2])
					counter = counter + 1
					local g = gui:addTextField(x + coord[1] - 1, y + coord[2] - 1, w, aa[5])
					g.mark = true
					return g
				end
				subgui.addListBox = function(...)
					local aa = {...}
					local x, y, w, h = calcPosition(aa[2], aa[3], aa[4], aa[5], dim[1], dim[2])
					counter = counter + 1
					local g = gui:addListBox(x + coord[1] - 1, y + coord[2] - 1, w, h, aa[6])
					g.mark = true
					return g
				end
				subgui.addComponent = function(obj, comp)
					comp.posX = comp.posX + coord[1] - 1
					comp.posY = comp.posY + coord[2] - 1
					comp.bodyX, comp.bodyY, comp.bodyW, comp.bodyH = GMLcalcBody(comp)
					gui:addComponent(comp)
				end
				local s, r = pcall(m.setUI, subgui)
				
				if s then
					for _, t in pairs(gui.components) do
						if t.mark then
							if t.onClick then
								local o = t.onClick
								t.onClick = function(...)
									return secureFunction(o, ...) 
								end
							end
							if t.onDoubleClick then
								local o = t.onDoubleClick
								t.onDoubleClick = function(...)
									return secureFunction(o, ...)
								end
							end
							if t.onBeginDrag then
								local o = t.onBeginDrag
								t.onBeginDrag = function(...)
									return secureFunction(o, ...)
								end
							end
							if t.onDrag then
								local o = t.onDrag
								t.onDrag = function(...)
									return secureFunction(o, ...)
								end
							end
							if t.onDrop then
								local o = t.onDrop
								t.onDrop = function(...)
									return secureFunction(o, ...)
								end
							end
						end
					end
					internalLog("dodano " .. counter .. " elemnty/ów GUI", "", false)
				else
					internalLog("modGUI", "nie udało się utworzyć GUI: " .. r, false, 0xffff00)
				end
			else
				internalLog("modGUI", "błąd integralności, nie znaleziono modułu", false, 0xff0000)
			end
		end
	end
end

local function main()
	if fs.exists("/etc/the_guard") and not fs.isDirectory("/etc/the_guard") then
		internalLog("main", "usuwanie błędnego folderu")
		fs.remove("/etc/the_guard")
	end
	if not fs.exists("/etc/the_guard") then
		internalLog("main", "brak folderu konfiguracji, tworzenie nowego")
		fs.makeDirectory("/etc/the_guard")
	end

	internalLog("Ładowanie konfiguracji", "", true, 0x00a6ff)
	if not loadConfig() then
		internalLog("main", "ładowanie nie powiodło się", false, 0xff0000)
		return false
	end
	
	if not settings.debugMode then
		local try = 0
		repeat
			if passwordPrompt() then break end
			try = try + 1
		until try == 3
		if try == 3 then
			internalLog("main", "zbyt wiele prób podania hasła", false, 0xff0000)
			return false
		end
	end
	
	internalLog("Ładowanie modułów", "", true, 0x00a6ff)
	loadModules()
	
	internalLog("Uruchamianie modułów", "", true, 0x00a6ff)
	for n, m in pairs(mod) do
		internalLog(n, "")
		local s, e = pcall(m.start, interface)
		if not s then
			internalLog("niepowodzenie", e, false, 0xff0000)
		end
	end
	
	internalLog("Tworzenie GUI", "", true, 0x00a6ff)
	createMainGui()
	
	internalLog("Tworzenie GUI modułów", "", true, 0x00a6ff)
	createGUI()
	
	internalLog("init", "Ładowanie nasłuchiwania w tle")
	event.listen("component_added", internalListener)
	event.listen("component_removed", internalListener)
	for _, e in pairs(revents) do
		event.listen(e, backgroundListener)
	end
	eventsready = true
	
	internalLog("Uruchamianie serwera", "", false, 0x00ff00)
	os.sleep(0.5)
	gui:run()
	os.sleep(0.5)
	eventsready = nil
	
	internalLog("init", "Wyłączanie nasłuchiwania w tle")
	event.ignore("component_added", internalListener)
	event.ignore("component_removed", internalListener)
	for _, e in pairs(revents) do
		event.ignore(e, backgroundListener)
	end
	
	internalLog("Wyłączanie modułów", "", true, 0x00a6ff)
	for n, m in pairs(mod) do
		internalLog(n, "")
		xpcall(m.stop, errorHandler, interface)
	end
	
	if settings.saveOnExit then
		internalLog("Zapisywanie konfiguracji", "", true)
		saveConfig()
	end
	internalLog("Zapisywanie logów", "", true, 0x00a6ff)
	flushLog()
	return true
end

local function loadToken()
	local path = fs.concat(configDir, "token")
	local ee = component.eeprom
	if not ee then
		internalLog("token", "Nie odnaleziono pamięci EEPROM!", false, 0xff0000)
		return false
	end
	if fs.isDirectory(path) then fs.remove(path) end
	if fs.exists(path) then
		local file, e = io.open(path, "r")
		if file then
			local dec = data.decode64(file:read("*a"))
			if dec then
				if ee.address == dec then
					token = data.md5(ee.address)
					return true
				else
					internalLog("token", "Tokeny się różnią!", false, 0xff0000)
				end
			else
				internalLog("token", "Nie udało się zdekodować tokenu", false, 0xff0000)
			end
		else
			internalLog("token", "Nie udało się otworzyć pliku tokenu (" .. e .. ")", false, 0xff0000)
		end
	else
		internalLog("token", "Brak tokenu, tworzenie nowego", false, 0xffff00)
		local file, e = io.open(path, "w")
		if file then
			file:write(data.encode64(ee.address))
			file:close()
			token = data.md5(ee.address)
			return true
		else
			internalLog("token", "Nie udało się utworzyć tokenu (" .. e .. ")", false, 0xff0000)
		end
	end
	return false
end

local function init()
	local prev = component.gpu.setForeground(0x00ff00)
	print("Serwer THE GUARD, wersja " .. version)
	component.gpu.setForeground(prev)
	internalLog("init", "Ładowanie tokenu")
	if not loadToken() then
		internalLog("init", "Inicjalizacje nieudana", false, 0xff0000)
		return
	end
	internalLog("init", "Inicjalizacja serwera")
	if not main() then
		internalLog("init", "Inicjalizacje nieudana", false, 0xff0000)
		return
	end
end

init()