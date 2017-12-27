-- ############################################
-- #				mod_tg_auth				  #
-- #										  #
-- #  05.2016					by:IlynPayne  #
-- ############################################

--[[
	## Opis programu ##
		Program mod_tg_auth jest modułem używanym w serwerze the_guard (od wersji 2.0).
		Program wymaga do działania zainstalowanego moda "opensecurity"
		Moduł pozwala na zarządzanie autoryzacją użytkownika. Odbywa się to
		za pomocą czytników kart i klawiatur numerycznych.
		Obsługiwane są tylko magnetyczne, obsługa kart RFID nie została wprowadzona
		(Wymagają one ręcznie uruchamianego skanera).
		
	## Akcje ##
		- lockMag() - blokuje czytniki kart
		- unlockMag() - odblokowuje czytniki kart
		- lockKeypad() - blokuje klawiatury
		- unlockKeypad() - odblokowuje klawiatury
		
	## Funkcje ##
		* wykorzystanie czytników kart i klawiatur do generowania akcji
		* do każdego zdarzenia można przypisać 3 akcje otwarcia i 3 akcje zamknięcia
		* możliwość wyboru czasu oczekiwania na uruchomienie akcji zamknięcia
		* opcjonalne losowanie kolejności klawiszy na klawiaturze po każdym poprawnym kodzie
		* możliwość włączenia blokady na terminale
		
	## Schematy ##
		cards: { - lista zarejestrowanych kart (plik /etc/the_guard/modules/auth/cards.dat)
			{
				id:string - identyfikator karty
				owner:string - właściciel
				name:string - nazwa karty
			}
			...
		}
		devices: { - czytniki i klawiatury (plik /etc/the_guard/modules/auth/devices.dat)
			readers: {
				{
					name:string - nazwa
					address:string - adres komponentu
					delay:number - opóźnienie zamykania
					disabled:boolean - czy czytnik jest niekatywny
					open: {
						{
							id:number - identyfikator akcji
							p1:any - parametr 1
							p2:any - parametr 2
						}
						...
					}
					close: {
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
			keypads: {
				(to samo, co w readers) +
				shuffle:boolean - czy losować kolejność klawiszy
			}
		}
]]

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local fs = require("filesystem")
local event = require("event")
local component = require("component")
local serial = require("serialization")
local colors = require("colors")
local gml = require("gml")
local data = component.data

local mod = {}
local server = nil
local config = nil
local readers = nil
local keypads = nil
local cards = nil
local inputs = {}

local lbox, rbox = nil, nil
local element = {}

local messages = {
	[1] = {
		"No Empty Slots",
		"Brak wolnych slotów"
	},
	[2] = {
		"No card in slot", 
		"Brak karty w slocie"
	},
	[3] = {
		"Data is Null",
		"Brak danych do zapisania"
	},
	[4] = {
		"Not enough power in OC Network.",
		"Brak wystarczającej ilości energii"
	}
}

local texts = {
	open = {"open", 2},
	closed = {"close", 6},
	lock = {"locked", 5},
	wrong = {"wrong", 4}
}

local function decrypt(d)
	local s, b = pcall(data.decode64, d)
	if s then
		local s, dec = pcall(data.decrypt, b, server.secretKey(mod), data.md5("auth"))
		if s then
			local s, tab = pcall(serial.unserialize, dec)
			if s then
				return tab
			end
		end
	end
	return nil
end

local function loadInternals()
	local dir = server.getConfigDirectory(mod)
	
	cards = {}
	local cfile = io.open(fs.concat(dir, "cards.dat"), "r")
	if cfile then
		local dd = decrypt(cfile:read("*a"))
		cfile:close()
		if dd then
			cards = dd
		end
	end
	
	readers = {}
	keypads = {}
	local dfile = io.open(fs.concat(dir, "devices.dat"), "r")
	if dfile then
		local dd = decrypt(dfile:read("*a"))
		dfile:close()
		if dd then
			readers = dd.readers
			keypads = dd.keypads
		end
	end
end

local function encrypt(d)
	local s, ser = pcall(serial.serialize, d)
	if s then
		local s, enc = pcall(data.encrypt, ser, server.secretKey(mod), data.md5("auth"))
		if s then
			local s, b = pcall(data.encode64, enc)
			if s then
				return b
			end
		end
	end
	return nil
end

local function saveInternals()
	local dir = server.getConfigDirectory(mod)
	
	local ce = encrypt(cards)
	if ce then
		local cfile = io.open(fs.concat(dir, "cards.dat"), "w")
		if cfile then
			cfile:write(ce)
			cfile:close()
		end
	end
	
	local tab = {}
	tab.readers = readers
	tab.keypads = keypads
	local de = encrypt(tab)
	if de then
		local dfile = io.open(fs.concat(dir, "devices.dat"), "w")
		if dfile then
			dfile:write(de)
			dfile:close()
		end
	end
end

local function getShuffled()
	local tab = {}
	local pending = ""
	while #tab < 10 do
		pending = tostring(math.random(10) - 1)
		local added = false
		for _, s in pairs(tab) do
			if s == pending then
				added = true
				break
			end
		end
		if not added then
			table.insert(tab, pending)
		end
	end
	return tab
end

local function refreshKeypads()
	local function getInfo(addr)
		for _, t in pairs(keypads) do
			if t.address == addr then return t end
		end
		return nil
	end
	local comp = server.getComponentList(mod, "os_keypad")
	for _, t in pairs(comp) do
		local proxy = component.proxy(t.address)
		local tab = getInfo(t.address)
		if proxy and t.state and tab then
			if tab.shuffle or config.shuffleAll then
				local tab = getShuffled()
				for i = 1, 9 do
					proxy.setKey(i, tab[i], 7)
				end
				proxy.setKey(11, tab[10], 7)
			else
				for i = 1, 9 do
					proxy.setKey(i, tostring(i), 7)
				end
				proxy.setKey(10, "*", 7)
				proxy.setKey(11, "0", 7)
				proxy.setKey(12, "#", 7)
			end
			if config.keypads and not tab.disabled then
				if not inputs[t.address] then
					proxy.setDisplay(config.msg[1], config.msg[2])
				end
			else
				proxy.setDisplay(texts.lock[1], texts.lock[2])
			end
		end
	end
end

local function newCard()
	local color = nil
	local function chooseColor()
		local ret = server.colorDialog(mod, false, true)
		if ret then
			color.color = ret[1]
			color.text = colors[ret[1]]
			color:draw()
		end
	end

	local ngui = gml.create("center", "center", 50, 17)
	ngui.style = server.getStyle(mod)
	ngui:addLabel("center", 1, 11, "Nowa karta")
	ngui:addLabel(3, 4, 7, "Nazwa:")
	ngui:addLabel(3, 6, 13, "Właściciel:")
	ngui:addLabel(3, 10, 9, "Blokada:")
	local tmp = ngui:addLabel(3, 8, 8, "Kolor:")
	tmp.onClick = chooseColor
	
	local name = ngui:addTextField(17, 4, 20)
	local owner = ngui:addTextField(17, 6, 20)
	color = ngui:addLabel(17, 8, 16, "")
	color.onClick = chooseColor
	local lock = ngui:addButton(17, 10, 10, 1, "Tak", function(t)
		if t.status then
			if server.messageBox(mod, "Wyłączenie tej opcji sprawi, że karta będzie\npodatna na modyfikacje.\nCzy chcesz kontynuować?", {"Tak", "Nie"}) == "Tak" then
				t.status = false
				t.text = "Nie"
				t:draw()
			end
		else
			t.status = true
			t.text = "Tak"
			t:draw()
		end
	end)
	lock.status = true
	
	ngui:addButton(16, 14, 14, 1, "Zapisz", function()
		if name.text:len() < 1 or name.text:len() > 16 then
			server.messageBox(mod, "Nazwa karty powinna mieć od 1 do 16 znaków.", {"OK"})
		elseif owner.text:len() == 0 then
			server.messageBox(mod, "Podaj właściciela karty.", {"OK"})
		elseif owner.text:len() > 32 then
			server.messageBox(mod, "Maksymalna długość nazwy gracza to 32 znaki.", {"OK"})
		elseif not color.color then
			server.messageBox(mod, "Wybierz kolor karty.", {"OK"})
		else
			local writer = component.os_cardwriter
			if writer then
				local status, msg = writer.write(data.deflate(owner.text), name.text, lock.status, color.color)
				if status then
					local tab = {}
					tab.id = msg
					tab.owner = owner.text
					tab.name = name.text
					table.insert(cards, tab)
					server.messageBox(mod, "Karta została zapisana!", {"OK"})
					ngui:close()
				else
					local message = "nieznany błąd"
					for _, t in pairs(messages) do
						if t[1]:lower() == msg:lower() then
							message = t[2]
						end
					end
					server.messageBox(mod, "Zapis nieudany: " ..message, {"OK"})
				end
			else
				server.messageBox(mod, "Nie odnaleziono czytnika kart.", {"OK"})
			end
		end
	end)
	ngui:addButton(32, 14, 14, 1, "Anuluj", function()
		ngui:close()
	end)
	ngui:run()
end

local function cardManager()
	local list, box = {}, nil
	local function refresh()
		list = {}
		for i, t in pairs(cards) do
			table.insert(list, string.format("%d. %s (%s, %s)", i, t.id, t.owner:upper(), t.name))
		end
		box:updateList(list)
	end
	local cgui = gml.create("center", "center", 90, 20)
	cgui.style = server.getStyle(mod)
	cgui:addLabel("center", 1, 15, "Menedżer kart")
	box = cgui:addListBox(3, 3, 83, 12, {})
	cgui:addButton(72, 17, 14, 1, "Zamknij", function() cgui:close() end)
	cgui:addButton(3, 17, 14, 1, "Dodaj", function()
		if #cards < 16 then
			newCard()
			refresh()
		else
			server.messageBox(mod, "Utworzono już maksymalną liczbę kart.", {"OK"})
		end
	end)
	cgui:addButton(19, 17, 14, 1, "Usuń", function()
		local sel = box:getSelected()
		if sel and server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Tak" then
			local num = tonumber(sel:match("^(%d+)%."))
			if num then
				table.remove(cards, num)
				refresh()
			end
		end
	end)
	refresh()
	cgui:run()
end

local function codeManager()
	local cgui = gml.create("center", "center", 40, 14)
	cgui.style = server.getStyle(mod)
	cgui:addLabel("center", 1, 13, "Lista kodów")
	cgui:addLabel(3, 4, 3, "1.")
	cgui:addLabel(3, 6, 3, "2.")
	cgui:addLabel(3, 8, 3, "3.")
	local c1 = cgui:addTextField(7, 4, 12)
	local c2 = cgui:addTextField(7, 6, 12)
	local c3 = cgui:addTextField(7, 8, 12)
	c1.text = config.codes[1] or ""
	c2.text = config.codes[2] or ""
	c3.text = config.codes[3] or ""
	cgui:addButton(20, 11, 14, 1, "Anuluj", function()
		cgui:close()
	end)
	cgui:addButton(4, 11, 14, 1, "Zatwierdź", function()
		local n1 = tonumber(c1.text)
		local n2 = tonumber(c2.text)
		local n3 = tonumber(c3.text)
		if (c1.text:len() > 0 and not n1) or (c2.text:len() > 0 and not n2) or (c3.text:len() > 0 and not n3) then
			server.messageBox(mod, "Kod musi być liczbą.", {"OK"})
		elseif c1.text:len() > 8 or c2.text:len() > 8 or c3.text:len() > 8 then
			server.messageBox(mod, "Kod może mieć maksymalnie 8 znaków.", {"OK"})
		else
			if not n1 and not n2 and not n3 then
				local msgg = [[
Niewpisanie żadnego kodu sprawi,
że klawiatury przestaną działać.
Czy chcesz kontynuować?
				]]
				if server.messageBox(mod, msgg, {"Tak", "Nie"}) == "Nie" then
					return
				end
			end
			local tab = {}
			if n1 then table.insert(tab, c1.text) end
			if n2 then table.insert(tab, c2.text) end
			if n3 then table.insert(tab, c3.text) end
			config.codes = tab
			cgui:close()
		end
	end)
	cgui:run()
end

local function messageManager()
	local color = config.msg[2] or 7
	local panel = nil
	local function refreshColor()
		local hex = 0
		if bit32.band(color, 4) ~= 0 then hex = hex + bit32.lshift(255, 16) end
		if bit32.band(color, 2) ~= 0 then hex = hex + bit32.lshift(255, 8) end
		if bit32.band(color, 1) ~= 0 then hex = hex + 255 end
		panel.color = hex
	end
	local mgui = gml.create("center", "center", 40, 17)
	mgui.style = server.getStyle(mod)
	mgui:addLabel("center", 1, 19, "Edytor wiadomości")
	mgui:addLabel(3, 4, 13, "Wiadomość:")
	mgui:addLabel(3, 6, 10, "Czerwony:")
	mgui:addLabel(3, 8, 9, "Zielony:")
	mgui:addLabel(3, 10, 11, "Niebieski:")
	local msg = mgui:addTextField(17, 4, 10)
	msg.text = config.msg[1] or ""
	local b1 = mgui:addButton(15, 6, 10, 1, "tak", function(t)
		if t.status then
			color = bit32.bor(color, 4)
			t.status = false
			t.text = "tak"
		else
			color = bit32.band(color, 3)
			t.status = true
			t.text = "nie"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 4) == 0 then
		b1.text = "nie"
		b1.status = true
	end
	local b2 = mgui:addButton(15, 8, 10, 1, "tak", function(t)
		if t.status then
			color = bit32.bor(color, 2)
			t.status = false
			t.text = "tak"
		else
			color = bit32.band(color, 5)
			t.status = true
			t.text = "nie"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 2) == 0 then
		b2.text = "nie"
		b2.status = false
	end
	local b3 = mgui:addButton(15, 10, 10, 1, "tak", function(t)
		if t.status then
			color = bit32.bor(color, 1)
			t.status = false
			t.text = "tak"
		else
			color = bit32.band(color, 6)
			t.status = true
			t.text = "nie"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 1) == 0 then
		b2.text = "nie"
		b2.status = false
	end
	panel = server.template(mod, mgui, 30, 6, 2, 5)
	panel.draw = function(t)
		t.renderTarget.setBackground(t.color)
		t.renderTarget.fill(t.gui.posX + t.posX - 1, t.gui.posY + t.posY - 1, t.width, t.height, " ")
	end
	refreshColor()
	mgui:addButton(23, 13, 14, 1, "Anuluj", function()
		mgui:close()
	end)
	mgui:addButton(7, 13, 14, 1, "Zatwierdź", function()
		if msg.text:len() > 8 then
			server.messageBox(mod, "Wiadomość może mieć maksymalnie 8 znaków.", {"OK"})
		else
			config.msg[1] = msg.text
			config.msg[2] = color
			refreshKeypads()
			mgui:close()
		end
	end)
	mgui:run()
end

local function settings()
	local sgui = gml.create("center", "center", 50, 15)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Ustawienia")
	sgui:addLabel(2, 4, 10, "Czytniki:")
	sgui:addLabel(4, 5, 22, "Identyfikacja gracza:")
	sgui:addLabel(4, 6, 20, "Tylko zablokowane:")
	sgui:addLabel(2, 8, 12, "Klawiatury:")
	sgui:addLabel(4, 9, 17, "Losuj wszystkie:")
	local b1 = sgui:addButton(27, 5, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "nie"
		else
			t.status = true
			t.text = "tak"
		end
		t:draw()
	end)
	b1.text = config.identity and "tak" or "nie"
	b1.status = config.identity
	local b2 = sgui:addButton(27, 6, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "nie"
		else
			t.status = true
			t.text = "tak"
		end
		t:draw()
	end)
	b2.text = config.lockedOnly and "tak" or "nie"
	b2.status = config.lockedOnly
	local b3 = sgui:addButton(27, 9, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "nie"
		else
			t.status = true
			t.text = "tak"
		end
		t:draw()
	end)
	b3.text = config.shuffleAll and "tak" or "nie"
	b3.status = config.shuffleAll
	sgui:addButton(33, 12, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(17, 12, 14, 1, "Zatwierdź", function()
		config.identity = b1.status
		config.lockedOnly = b2.status
		config.shuffleAll = b3.status
		sgui:close()
	end)
	sgui:run()
end

local function refreshTables()
	local l1 = {}
	for _, t in pairs(readers) do table.insert(l1, t.name) end
	lbox:updateList(l1)
	local l2 = {}
	for _, t in pairs(keypads) do table.insert(l2, t.name) end
	rbox:updateList(l2)
end

local function prepareWindow(keys, edit, initialize)
	local rettab = {}
	if initialize then
		for a, b in pairs(initialize) do rettab[a] = b end
	end
	if type(rettab.open) ~= "table" then rettab.open = {} end
	if type(rettab.close) ~= "table" then rettab.close = {} end
	local int = {}
	local addition = keys and 2 or 0
	
	local function updateLabels()
		for i = 1, 3 do
			if rettab.open[i] then
				local a = server.actionDetails(mod, rettab.open[i].id)
				if a then
					int[i].text = a.name
				else
					int[i].text = tostring(rettab.open[i].id)
				end
			else
				int[i].text = ""
			end
			int[i]:draw()
		end
		for i = 1, 3 do
			if rettab.close[i] then
				local a = server.actionDetails(mod, rettab.close[i].id)
				if a then
					int[3 + i].text = a.name
				else
					int[3 + i].text = tostring(rettab.close[i].id)
				end
			else
				int[3 + i].text = ""
			end
			int[3 + i]:draw()
		end
	end
	local function chooseAction(enable, num)
		local text = enable and int[num].text or int[3 + num].text
		local tab = enable and rettab.open or rettab.close
		if text:len() > 0 then
			local ret = server.actionDialog(mod, nil, nil, tab[num])
			tab[num] = ret
			updateLabels()
		else
			local ret = server.actionDialog(mod)
			if ret then
				tab[num] = ret
				updateLabels()
			end
		end
	end
	
	local sgui = gml.create("center", "center", 65, 23 + addition)
	sgui.style = server.getStyle(mod)
	local title = sgui:addLabel("center", 1, 18, "")
	if edit then
		title.text = keys and "Edycja klawiatury" or "Edycja czytnika"
	else
		title.text = keys and "Nowa klawiatura" or "Nowy czytnik"
	end
	
	sgui:addLabel(2, 4, 7, "Adres:")
	sgui:addLabel(2, 6, 7, "Nazwa:")
	sgui:addLabel(2, 8, 13, "Opóźnienie:")
	sgui:addLabel(2, 10, 8, "Status:")
	sgui:addLabel(2, 13 + addition, 19, "Akcje włączania:")
	sgui:addLabel(30, 13 + addition, 20, "Akcje wyłączania:")
	
	if keys then
		sgui:addLabel(2, 12, 11, "Losowanie:")
		local tmp = sgui:addButton(15, 12, 10, 1, "", function(t)
			if rettab.shuffle then
				rettab.shuffle = false
				t.text = "nie"
			else
				rettab.shuffle = true
				t.text = "tak"
			end
			t:draw()
		end)
		tmp.text = rettab.shuffle and "tak" or "nie"
	end
	for i = 1, 3 do
		local tt = sgui:addLabel(4, 14 + addition + i, 3, tostring(i) .. ".")
		int[i] = sgui:addLabel(8, 14 + addition + i, 20, "")
		local function exec()
			chooseAction(true, i)
		end
		tt.onDoubleClick = exec
		int[i].onDoubleClick = exec
	end
	for i = 1, 3 do
		local tt = sgui:addLabel(32, 14 + addition + i, 3, tostring(i) .. ".")
		int[3 + i] = sgui:addLabel(36, 14 + addition + i, 20, "")
		local function exec()
			chooseAction(false, i)
		end
		tt.onDoubleClick = exec
		int[3 + i].onDoubleClick = exec
	end
	
	local tmp = sgui:addLabel(15, 4, 38, "")
	tmp.onDoubleClick = function(t)
		local a = server.componentDialog(mod, keys and "os_keypad" or "os_magreader")
		if a then
			local found = false
			for _, t in pairs(keys and keypads or readers) do
				if a == t.address then
					found = true
					break
				end
			end
			if not found then
				t.text = a
				rettab.address = a
				t:draw()
			else
				server.messageBox(mod, "Urządzenie o takim adresie zostało już dodane.", {"OK"})
			end
		end
	end
	tmp.text = rettab.address or ""
	
	int[7] = sgui:addTextField(15, 6, 20)
	int[8] = sgui:addTextField(15, 8, 10)
	int[7].text = rettab.name or ""
	int[8].text = tostring(rettab.delay or 3)
	local tmp = sgui:addButton(15, 10, 14, 1, "", function(t)
		if rettab.disabled then
			rettab.disabled = false
			t.text = "włączony"
		else
			rettab.disabled = true
			t.text = "wyłączony"
		end
		t:draw()
	end)
	tmp.text = rettab.disabled and "wyłączony" or "włączony"
	
	sgui:addButton(47, 20 + addition, 14, 1, "Anuluj", function()
		sgui.ret = initialize
		sgui:close()
	end)
	sgui:addButton(31, 20 + addition, 14, 1, "Zatwierdź", function()
		local name = int[7].text
		local delay = tonumber(int[8].text)
		if name:len() == 0 then
			server.messageBox(mod, "Podaj nazwę urządzenia.", {"OK"})
		elseif not rettab.address then
			server.messageBox(mod, "Wybierz adresu urządzenia.", {"OK"})
		elseif not delay or delay > 20 or delay < 1 then
			server.messageBox(mod, "Opóźnienie musi być liczbą w przedziale 1-20.", {"OK"})
		else
			rettab.name = name:sub(1, 20)
			rettab.delay = delay
			sgui.ret = rettab
			sgui:close()
		end
	end)
	
	updateLabels()
	return sgui
end

local function addReader()
	if #readers < 10 then
		local sgui = prepareWindow(false, false, nil)
		sgui:run()
		if sgui.ret then
			table.insert(readers, sgui.ret)
			refreshTables()
		end
	else
		server.messageBox(mod, "Dodano już maksymalną ilość czytników.", {"OK"})
	end
end

local function addKeypad()
	if #keypads < 10 then
		local sgui = prepareWindow(true, false, nil)
		sgui:run()
		if sgui.ret then
			table.insert(keypads, sgui.ret)
			refreshTables()
			refreshKeypads()
		end
	else
		server.messageBox(mod, "Dodano już maksymalną ilość klawiatur.", {"OK"})
	end
end

local function getDevice(list, name)
	for i, t in pairs(list) do
		if t.name == name then return t, i end
	end
	return nil
end

local function modifyReader()
	local sel = lbox:getSelected()
	if sel then
		local dev, index = getDevice(readers, sel)
		if dev then
			local sgui = prepareWindow(false, true, dev)
			sgui:run()
			if sgui.ret then
				readers[index] = sgui.ret
				refreshTables()
			end
		end
	end
end

local function modifyKeypad()
	local sel = rbox:getSelected()
	if sel then
		local dev, index = getDevice(keypads, sel)
		if dev then
			local sgui = prepareWindow(true, true, dev)
			sgui:run()
			if sgui.ret then
				keypads[index] = sgui.ret
				refreshTables()
				refreshKeypads()
			end
		end
	end
end


local actions = {
	[1] = {
		name = "lockMag",
		type = "AUTH",
		desc = "Blokuje czytniki",
		exec = function()
			config.readers = false
			element[1].text = "wyłączone"
			element[1]:draw()
		end
	},
	[2] = {
		name = "unlockMag",
		type = "AUTH",
		desc = "Odblokocuje czytniki",
		exec = function()
			config.readers = true
			element[1].text = "włączone"
			element[1]:draw()
		end
	},
	[3] = {
		name = "lockKeypad",
		type = "AUTH",
		desc = "Blokuje klawiatury",
		exec = function()
			config.keypads = false
			element[2].text = "wyłączone"
			element[2]:draw()
			refreshKeypads()
		end
	},
	[4] = {
		name = "unlockKeypad",
		type = "AUTH",
		desc = "Odblokowuje klawiatury",
		exec = function()
			config.keypads = true
			element[2].text = "właczone"
			element[2]:draw()
			refreshKeypads()
		end
	},
	
}

mod.name = "auth"
mod.version = version
mod.id = 27
mod.apiLevel = 2
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 11, ">> AUTH <<")
	window:addLabel(3, 3, 10, "Czytniki:")
	window:addLabel(36, 3, 12, "Klawiatury:")
	
	lbox = window:addListBox(3, 5, 30, 10, {})
	rbox = window:addListBox(36, 5, 30, 10, {})
	lbox.onDoubleClick = modifyReader
	rbox.onDoubleClick = modifyKeypad
	refreshTables()
	
	element[1] = window:addButton(18, 3, 14, 1, "", function(t)
		if config.readers then
			config.readers = false
			t.text = "wyłączone"
		else
			config.readers = true
			t.text = "włączone"
		end
		t:draw()
	end)
	element[1].text = config.readers and "włączone" or "wyłączone"
	element[2] = window:addButton(52, 3, 14, 1, "", function(t)
		if config.keypads then
			config.keypads = false
			t.text = "wyłączone"
		else
			config.keypads = true
			t.text = "włączone"
		end
		refreshKeypads()
		t:draw()
	end)
	element[2].text = config.keypads and "włączone" or "wyłączone"
	window:addButton(3, 16, 14, 1, "Dodaj", addReader)
	window:addButton(19, 16, 14, 1, "Usuń", function()
		local sel = lbox:getSelected()
		if sel then
			for i, t in pairs(readers) do
				if t.name == sel and server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Tak" then
					table.remove(readers, i)
					refreshTables()
				end
			end
		end
	end)
	window:addButton(36, 16, 14, 1, "Dodaj", addKeypad)
	window:addButton(52, 16, 14, 1, "Usuń", function()
		local sel = rbox:getSelected()
		if sel then
			for i, t in pairs(keypads) do
				if t.name == sel and server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Tak" then
					table.remove(keypads, i)
					refreshTables()
				end
			end
		end
	end)
	window:addButton(3, 18, 14, 1, "Karty", cardManager)
	window:addButton(36, 18, 14, 1, "Kody", codeManager)
	window:addButton(52, 18, 14, 1, "Wiadomość", messageManager)
	window:addButton(19, 18, 14, 1, "Ustawienia", settings)
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	loadInternals()
	
	if type(config.readers) ~= "boolean" then
		config.readers = true
	end
	if type(config.keypads) ~= "boolean" then
		config.keypads = true
	end
	if not config.msg then
		config.msg = {}
		table.insert(config.msg, "ready")
		table.insert(config.msg, 3)
	end
	if type(config.lockedOnly) ~= "boolean" then config.lockedOnly = true end
	if not config.codes then config.codes = {} end
	if not config.msg[1] or config.msg[1]:len() > 8 then config.msg[1] = config.msg[1]:sub(1, 8) end
	if not config.msg[2] or config.msg[2] > 7 or config.msg[2] < 0 then config.msg[2] = 3 end
	
	core.registerEvent(mod, "magData") --magdata, devaddr, player, data, id, locked, side
	core.registerEvent(mod, "keypad") --keypad, devaddr, keyid, keychar
	refreshKeypads()
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	saveInternals()
	
	local comp = server.getComponentList(mod, "os_keypad")
	for _, t in pairs(comp) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.setDisplay("", 7)
			for i = 1, 9 do
				proxy.setKey(i, tostring(i))
			end
			proxy.setKey(11, "0")
		end
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "magData" then
		if not config.readers then return end
		local card = nil
		for _, t in pairs(cards) do
			if t.id == e[5] then
				card = t
				break
			end
		end
		if card then
			local dev = nil
			for _, t in pairs(readers) do
				if t.address == e[2] then
					dev = t
					break
				end
			end
			if dev then
				if dev.disabled then return
				elseif config.lockedOnly and not e[6] then return
				elseif config.identity then
					if data.inflate(e[4]) ~= e[3] then return end
				end
				local function exec(tab)
					for _, t in pairs(tab) do
						server.call(mod, t.id, t.p1, t.p2, true)
					end
				end
				exec(dev.open)
				server.call(mod, 5201, "Gracz " .. e[3] .. " użył karty w czytniku " .. dev.name .. ".", "AUTH", true)
				event.timer(dev.delay, function()
					exec(dev.close)
				end)
			end
		end
	elseif e[1] == "keypad" then
		--keypad, devaddr, keyid, keychar
		if not config.keypads then return end
		local dev = nil
		for _, t in pairs(keypads) do
			if t.address == e[2] then
				dev = t
				break
			end
		end
		if dev and not dev.disabled then
			local proxy = component.proxy(dev.address)
			if not proxy then return end
			if e[3] < 10 or e[3] == 11 then
				if inputs[e[2]] then
					if inputs[e[2]]:len() < 8 then
						inputs[e[2]] = inputs[e[2]] .. e[4]
						proxy.setDisplay(string.rep("*", inputs[e[2]]:len()), 7)
					end
				else
					inputs[e[2]] = e[4]
					proxy.setDisplay("*", 7)
				end
			elseif e[3] == 10 then
				if inputs[e[2]]:len() > 1 then
					inputs[e[2]] = inputs[e[2]]:sub(1, #inputs[e[2]] - 1)
					proxy.setDisplay(string.rep("*", inputs[e[2]]:len()))
				else
					inputs[e[2]] = nil
					proxy.setDisplay(config.msg[1], config.msg[2])
				end
			elseif e[3] == 12 then
				local code = inputs[e[2]]
				if code then
					local valid = false
					for _, s in pairs(config.codes) do
						if code == s then
							valid = true
							break
						end
					end
					if valid then
						local function exec(tab)
							for _, t in pairs(tab) do
								server.call(mod, t.id, t.p1, t.p2, true)
							end
						end
						dev.disabled = true
						proxy.setDisplay(texts.open[1], texts.open[2])
						exec(dev.open)
						inputs[e[2]] = nil
						server.call(mod, 5201, "Użyto klawiatury " .. dev.name .. ".", "AUTH", true)
						event.timer(dev.delay, function()
							proxy.setDisplay(texts.closed[1], texts.closed[2])
							exec(dev.close)
						end)
						event.timer(dev.delay + 3, function()
							dev.disabled = false
							proxy.setDisplay(config.msg[1], config.msg[2])
							if dev.shuffle then
								local sh = getShuffled()
								for i = 1, 9 do
									proxy.setKey(i, sh[i], 7)
								end
								proxy.setKey(11, sh[10], 7)
							end
						end)
					else
						dev.disabled = true
						inputs[e[2]] = nil
						proxy.setDisplay(texts.wrong[1], texts.wrong[2])
						event.timer(2, function()
							dev.disabled = false
							proxy.setDisplay(config.msg[1], config.msg[2])
							if dev.shuffle then
								local sh = getShuffled()
								for i = 1, 9 do
									proxy.setKey(i, sh[i], 7)
								end
								proxy.setKey(11, sh[10], 7)
							end
						end)
					end
				end
			end
		end
	end
end

return mod