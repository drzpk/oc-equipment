-- ################################################
-- #                The Guard                     #
-- #                                              #
-- #  07.2015                      by: Aranthor   #
-- ################################################

--[[
	## Opis programu
		Program służy jako centrum sterowania systemem zabezpieczeń.
		Pozwala na sterowanie:
		- alarmem
		- osłoną
		- cewkami Tesli
		- zabezpieczeniami z wykorzystaniem kart magnetycznych (OpenSecurity)
	## Opis techniczny
		Działanie programu opiera się na mikrokontrolerach. Programowanie 
		EEPROM wykonuje się z poziomu guard_ee. Każdy mikrokontroler po 
		włączeniu wysyła do serwera sygnał informujący o jego dostępności (tak samo jest z serwerem)
	## Schematy komunikacji (lewa strona - mikrokontroler, prawa strona - serwer)
	  *Mikrokontroler jest online
		messages.echo, version --->
		<--- messages.ok/messages.disable
	  *Serwer jest online
		<--- messages.echo
		messages.echo, version --->
		<--- messages.ok/messages.disable
	  *Ustaw kolor
	    <--- messages.color, strona, kolor, sila, [czas]
		messages.ok --->
	  *Czujnik ruchu
		messages.move, {zdarzenie} --->
	  *Zdarzenie karty magnetycznej
	    messages.mag, {zdarzenie} --->
	  *Alarm
	    <--- messages.alarm, true/false
		messages.ok --->
	  *Adres
		<--- messages.address, adres
		messages.address, liczba, pełny adres --->
]]

local version = "1.0"
local microVersion = "1"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local event = require("event")
local serial = require("serialization")
local fs = require("filesystem")
local gml = require("gml")
local sides = require("sides")
local colors = require("colors")
local dsapi = require("dsapi")
if not component.isAvailable("modem") then
	io.stderr:write("Program wymaga do dzialania karty sieciowej")
	return
end
local modem = component.modem
if not (component.isAvailable("data") or component.isAvailable("os_datablock")) then
	io.stderr:write("Program wymaga do dzialania karty lub bloku danych (data card, data block)")
	return
end
local datacard = component.data or component.os_datablock

local resolution = {160, 50}
local screen = nil
local screen2 = component.screen
local gpu = component.gpu
local GMLbgcolor = nil
local logstr = ""
local logtab = {}
local tid = nil
local ctid = nil
local resplist = {}
local counter = 0
local silent = false
local readers = {}

local data = {}
local cards = {}
local micros = {}
local creatures = {}

local gui = nil
local logList = nil
local detector = {}
local magnetic = {}
local switch = {}

local messages = {
	echo = 0x50f,
	ok = 0x5ea,
	color = 0x9bc,
	move = 0x19a6,
	mag = 0xb33d,
	alarm = 0x79ae,
	address = 0x812d,
	disable = 0x1a92
}

local function beep()
	component.computer.beep(1500, 0.05)
	os.sleep(0.05)
	component.computer.beep(1500, 0.05)
	os.sleep(0.05)
	component.computer.beep(1500, 0.05)
end

local function loadConfig()
	if fs.exists("/etc/the_guard/config.cfg") then
		local f = io.open("/etc/the_guard/config.cfg", "r")
		data = serial.unserialize(datacard.decode64(f:read())) or {}
		f:close()
		local f2 = io.open("/etc/the_guard/cards", "r")
		cards = serial.unserialize(datacard.decode64(f2:read())) or {}
		f2:close()
	end
	screen = component.proxy(data.screen or "") or screen2
	gpu.bind(screen.address)
	if data.port == nil then data.port = math.random(60000, 65533) end
	if data.password == nil then
		local g = gml.create("center", "center", 46, 7, gpu)
		g:addLabel(2, 1, 43, "Brak hasła głównego, podaj nowe hasło:")
		local field = g:addTextField("center", 3, 28)
		g:addButton(30, 5, 8, 1, "OK", function()
			if field["text"] ~= "" then
				data.password = datacard.md5(field["text"])
				g:close()
			else
				beep()
			end
		end)
		g:run()
	end
	data.detector = data.detector or {}
	data.detector.list = data.detector.list or {}
	data.magnetic = data.magnetic or {}
	data.magnetic.list = data.magnetic.list or {}
end

local function saveConfig()
	if not fs.isDirectory("/etc/the_guard") then fs.makeDirectory("/etc/the_guard") end
	local f = io.open("/etc/the_guard/config.cfg", "w")
	data.modemAddress = modem.address
	f:write(datacard.encode64(serial.serialize(data)))
	f:close()
	f = io.open("/etc/the_guard/cards", "w")
	f:write(datacard.encode64(serial.serialize(cards)))
	f:close()
end

local function GMLcontains(element,x,y)
  local ex, ey, ew, eh = element.posX, element.posY, element.width, element.height
  return x >= ex and x <= ex + ew - 1 and y >= ey and y <= ey + eh - 1
end

function GMLgetAppliedStyles(element)
  local styleRoot=element.style
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

function GMLextractProperty(element, styles, property)
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

function GMLmessageBox(message, buttons)
  local buttons = buttons or {"cancel", "ok"}
  local choice
  local lines = {}
  message:gsub("([^\n]+)", function(line) lines[#lines+1] = line end)
  local i = 1
  while i <= #lines do
    if #lines[i] > 26 then
      local s, rs = lines[i], lines[i]:reverse()
      local pos =- 26
      local prev = 1
      while #s > prev + 25 do
        local space = rs:find(" ", pos)
        if space then
          table.insert(lines, i, s:sub(prev, #s-space))
          prev = #s - space + 2
          pos =- (#s - space + 28)
        else
          table.insert(lines, i, s:sub(prev, prev+25))
          prev = prev + 26
          pos = pos - 26
        end
        i = i + 1
      end
      lines[i] = s:sub(prev)
    end
    i = i + 1
  end

  local gui = gml.create("center", "center", 30, 6 + #lines, gpu)
  local labels = {}
  for i = 1, #lines do
    labels[i] = gui:addLabel(2, 1 + i, 26, lines[i])
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

local function addTitle()
	local title = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gui.renderTarget
	}
	title.posX = 3
	title.posY = 3
	title.width = 62
	title.height = 5
	title.contains = GMLcontains
	title.isHidden = function() return false end
	title.draw = function(t)
		t.renderTarget.setBackground(0x0000ff)
		t.renderTarget.fill(3, 3, 5, 1, ' ')--t
		t.renderTarget.fill(5, 4, 1, 4, ' ')
		t.renderTarget.fill(10, 3, 1, 5, ' ')--h
		t.renderTarget.fill(13, 3, 1, 5, ' ')
		t.renderTarget.fill(11, 5, 2, 1, ' ')
		t.renderTarget.fill(16, 3, 1, 5, ' ')--e
		t.renderTarget.fill(17, 3, 3, 1, ' ')
		t.renderTarget.fill(17, 5, 3, 1, ' ')
		t.renderTarget.fill(17, 7, 3, 1, ' ')
		t.renderTarget.fill(30, 3, 4, 1, ' ')--g
		t.renderTarget.fill(30, 7, 4, 1, ' ')
		t.renderTarget.fill(31, 5, 3, 1, ' ')
		t.renderTarget.set(29, 4, ' ')
		t.renderTarget.set(28, 5, ' ')
		t.renderTarget.set(29, 6, ' ')
		t.renderTarget.set(34, 6, ' ')
		t.renderTarget.fill(37, 3, 1, 4, ' ')--u
		t.renderTarget.fill(38, 6, 1, 2, ' ')
		t.renderTarget.fill(39, 7, 2, 1, ' ')
		t.renderTarget.fill(40, 6, 1, 2, ' ')
		t.renderTarget.fill(41, 3, 1, 4, ' ')
		t.renderTarget.fill(44, 6, 1, 2, ' ')--a
		t.renderTarget.fill(45, 4, 1, 3, ' ')
		t.renderTarget.fill(46, 3, 3, 1, ' ')
		t.renderTarget.fill(46, 6, 3, 1, ' ')
		t.renderTarget.fill(49, 4, 1, 3, ' ')
		t.renderTarget.fill(50, 6, 1, 2, ' ')
		t.renderTarget.fill(53, 3, 1, 5, ' ')--r
		t.renderTarget.fill(54, 3, 3, 1, ' ')
		t.renderTarget.fill(54, 5, 3, 1, ' ')
		t.renderTarget.fill(57, 6, 1, 2, ' ')
		t.renderTarget.set(57, 4, ' ')
		t.renderTarget.fill(60, 3, 1, 5, ' ')--d
		t.renderTarget.fill(61, 3, 3, 1, ' ')
		t.renderTarget.fill(61, 7, 3, 1, ' ')
		t.renderTarget.fill(64, 4, 1, 3, ' ')
	end
	gui:addComponent(title)
	return title
end

local function addBar(x, y, length, isHorizontal)
	local bar = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gui.renderTarget,
		horizontal = isHorizontal
	}
	bar.posX = x
	bar.posY = y
	bar.width = isHorizontal and length or 1
	bar.height = isHorizontal and 1 or length
	bar.contains = GMLcontains
	bar.isHidden = function() return false end
	bar.draw = function(t)
		t.renderTarget.setBackground(GMLbgcolor)
		t.renderTarget.setForeground(0xffffff)
		if t.horizontal then
			t.renderTarget.set(t.posX + 1, t.posY + 1, string.rep(require("unicode").char(0x2550), t.width))
		else
			local uni = require("unicode")
			for i = 1, t.height do
				t.renderTarget.set(t.posX + 1, t.posY + i, uni.char(0x2551))
			end
		end
	end
	gui:addComponent(bar)
	return bar
end

local function updateCounter()
	counter = counter + 1
	if counter >= 5 then
		counter = 0
		saveConfig()
	end
end

local function logs(msg)
	logstr = logstr .. "\n" .. os.date() .. "  " .. msg
	if logstr:len() > 200 then
		local f = io.open("/tmp/guard.log", "a")
		f:write(logstr)
		f:close()
		logstr = ""
	end
	table.insert(logtab, msg)
	if #logtab > 10 then table.remove(logtab, 1) end
	logList:updateList(logtab)
	logList:select(#logtab)
end

local function getServerAddress()
	local value = -1
	local ggui = gml.create("center", "center", 46, 5, gpu)
	ggui:addLabel(2, 1, 28, "Podaj port serwera danych:")
	local field = ggui:addTextField(32, 1, 8)
	ggui:addButton(34, 3, 10, 1, "Anuluj", function() ggui:close() end)
	ggui:addButton(23, 3, 10, 1, "OK", function()
		if field["text"] == "" or tonumber(field["text"]) == nil then
			GMLmessageBox("Wprowadź poprawny port", {"OK"})
		elseif not dsapi.echo(tonumber(field["text"])) then
			GMLmessageBox("Brak serwera pod podanym portem", {"OK"})
		else
			value = tonumber(field["text"])
			ggui:close()
		end
	end)
	ggui:run()
	return value
end

local function backup()
	local serverPort = getServerAddress()
	if serverPort ~= -1 then
		local status1, code1 = dsapi.write(serverPort, "the_guard/config.backup", datacard.encode64(serial.serialize(data)))
		os.sleep(0.2)
		local status2, code2 = dsapi.write(serverPort, "the_guard/cards", datacard.encode64(serial.serialize(cards)))
		if status1 and status2 then
			GMLmessageBox("Kopia została wykonana pomyślnie", {"OK"})
			logs("Wykonano kopię zapasową")
		else
			GMLmessageBox("Błąd: " .. dsapi.translateCode(status1 and code1 or code2), {"OK"})
			logs("Nie udało się wykonać kopii zapasowej: " .. dsapi.translateCode(status1 and code1 or code2))
		end
	end
end

local function restore()
	local serverPort = getServerAddress()
	if serverPort ~= -1 then
		local status1, code1 = dsapi.get(serverPort, "the_guard/config.backup")
		local status2, code2 = dsapi.get(serverPort, "the_guard/cards")
		if status1 and status2 then
			local f = io.open("/etc/the_guard/config.cfg", "w")
			f:write(code1)
			f:close()
			f = io.open("/etc/the_guard/cards", "w")
			f:write(code2)
			f:close()
			GMLmessageBox("Przywracanie zostało wykonane pomyślnie. Komputer zostanie uruchomiony ponownie", {"OK"})
			require("computer").shutdown(true)
		else
			GMLmessageBox("Błąd: " .. dsapi.translateCode(status1 and code1 or code2), {"OK"})
			logs("Nie udało się przywrócić danych: " .. dsapi.translateCode(status1 and code1 or code2))
		end
	end
end

local function searchAddress(name, address)
	local l = component.list(name)
	local amount, fullAddress = 0, nil
	for k, _ in pairs(l) do
		if k:find(address, 1) ~= nil or k == address then
			amount = amount + 1
			fullAddress = k
		end
	end
	return amount, fullAddress
end

local function checkConnections()
	if resplist == nil then return end
	for k, _ in pairs(micros) do
		if resplist[k] == nil then
			logs("Mikrokontroler (" .. k:sub(1,5) .. ") nie odpowiada")
			micros[k] = nil
			break
		end
	end
end

local function sendCommand(...)
	event.cancel(tid or 0)
	for k, v in pairs(micros) do
		modem.send(k, v, data.port, ...)
	end
	if resplist ~= nil then
		resplist = {}
		tid = event.timer(2, checkConnections)
	end
end

local function checkBlockade()
	if data.blockade then
		if not silent then
			GMLmessageBox("Nie można zmienić tego ustawienia podczas całkowitej blokady!", {"OK"})
		end
		return false
	end
	return true
end

local function tesla()
	if checkBlockade() then
		if not data.tesla then
			sendCommand(messages.color, sides.back, colors.red, 250)
			data.tesla = true
			switch.tesla["text-color"] = 0x00ff00
			logs("Cewka Tesli została włączona")
		else
			sendCommand(messages.color, sides.back, colors.red, 0)
			data.tesla = false
			switch.tesla["text-color"] = 0xff0000
			logs("Cewka Tesli została wyłączona")
		end
		switch.tesla:draw()
		updateCounter()
	end
end

local function shield()
	if checkBlockade() then
		if not data.shield then
			sendCommand(messages.color, sides.back, colors.lightblue, 250)
			data.shield = true
			switch.shield["text-color"] = 0x00ff00
			logs("Osłona została włączona")
		else
			sendCommand(messages.color, sides.back, colors.lightblue, 0)
			data.shield = false
			switch.shield["text-color"] = 0xff0000
			logs("Osłona została wyłączona")
		end
		switch.shield:draw()
		updateCounter()
	end
end

local function alarm()
	if checkBlockade() then
		if not data.alarm then
			sendCommand(messages.alarm, true)
			data.alarm = true
			switch.alarm["text-color"] = 0x00ff00
			logs("Alarm został włączony")
		else
			sendCommand(messages.alarm, false)
			data.alarm = false
			switch.alarm["text-color"] = 0xff0000
			logs("Alarm został wyłączony")
		end
		switch.alarm:draw()
		updateCounter()
	end
end

local function blockade()
	resplist = nil
	if not data.blockade then
		local ans = true
		if not silent then
			ans = GMLmessageBox("Czy na pewno chcesz włączyć całkowitą blokadę?", {"Tak", "Nie"}) == "Tak"
		end
		if ans then
			data.alarm = false
			data.shield = false
			data.tesla = false
			alarm()
			if data.switchPort ~= nil then
				os.sleep(0.5)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x51}))
				os.sleep(0.1)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x52}))
				os.sleep(0.1)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x55}))
			end
			os.sleep(0.5)
			shield()
			os.sleep(0.5)
			resplist = {}
			tesla()
			data.blockade = true
			switch.blockade["text-color"] = 0x00ff00
			switch.blockade:draw()
			updateCounter()
			logs("Całkowita blokada została właczona")
		end
	else
		if GMLmessageBox("Czy na pewno chcesz wyłączyć całkowitą blokadę?", {"Tak", "Nie"}) == "Tak" then
			data.blockade = false
			data.alarm = true
			data.tesla = true
			tesla()
			if data.switchPort ~= nil then
				os.sleep(0.5)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x50}))
				os.sleep(0.1)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x53}))
				os.sleep(0.1)
				modem.broadcast(data.switchPort, data.port, serial.serialize({0x54}))
			end
			os.sleep(0.5)
			resplist = {}
			alarm()
			os.sleep(0.5)
			switch.blockade["text-color"] = 0xff0000
			switch.blockade:draw()
			updateCounter()
			logs("Całkowita blokada została wyłączona")
		end
	end
end

local function lockScreen()
	local lgui = gml.create(1, 1, resolution[1], resolution[2], gpu)
	lgui:addLabel("center", 21, 40, "Wprowadź hasło, aby odblokować ekran:")
	local field = lgui:addTextField("center", 23, 30)
	lgui:changeFocusTo(lgui:addButton(84, 25, 10, 1, "OK", function()
		if datacard.md5(field["text"]) ~= data.password then
			field["text"] = ""
			field:draw()
			beep()
		else
			lgui:close()
		end
	end))
	lgui:run()
end

local function settings()
	local sgui = gml.create("center", "center", 55, 10, gpu)
	sgui:addLabel(20, 1, 11, "Ustawienia")
	sgui:addLabel(2, 3, 21, "Port [60000-65533]:")
	sgui:addLabel(2, 4, 30, "Port the_switch [100-65533]:")
	sgui:addLabel(2, 5, 30, "Port dataSrv2 [10000-60000]:")
	sgui:addLabel(2, 6, 17, "Adres monitora:")
	local port = sgui:addTextField(34, 3, 8)
	port["text"] = tostring(data.port)
	local tsPortf = sgui:addTextField(34, 4, 8)
	tsPortf["text"] = tostring(data.switchPort or "")
	local dsPort = sgui:addTextField(34, 5, 8)
	dsPort["text"] = tostring(data.dsPort or "")
	local madd = sgui:addTextField(21, 6, 21)
	madd["text"] = data.screen or ""
	sgui:addButton(3, 8, 10, 1, "Kopia", backup)
	sgui:addButton(14, 8, 14, 1, "Przywracanie", restore)
	sgui:addButton(42, 8, 10, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(31, 8, 10, 1, "OK", function()
		local amount, faddress = nil, nil
		local sPort = tonumber(port["text"])
		local tsPort = tonumber(tsPortf["text"])
		local dsnPort = tonumber(dsPort["text"])
		if madd["text"] ~= "" then
			amount, faddress = searchAddress("screen", madd["text"])
		end
		if not sPort or not tsPort then
			GMLmessageBox("Wprowadzony port jest niepoprawny", {"OK"})
			if sPort == nil then port["text"] = ""
			elseif tsPort == nil then tsPortf["text"] = "" end
		elseif sPort < 60000 or sPort > 65533 then
			GMLmessageBox("Wprowadzony port wykracza poza zakres", {"OK"})
			sPort["text"] = ""
		elseif tsPort < 100 or tsPort > 65533 then
			GMLmessageBox("Wprowadzony port wykracza poza zakres", {"OK"})
			tsPortf["text"] = ""
		elseif dsnPort and (dsnPort < 10000 or dsnPort > 60000) then
			GMLmessageBox("Wprowadzony port wykracza poza zakres", {"OK"})
			dsPort["text"] = ""
		elseif dsnPort and not dsapi.echo(dsnPort) then
			GMLmessageBox("Brak serwera danych pod podanym portem", {"OK"})
		elseif amount ~= nil and amount == 0 then
			GMLmessageBox("Nie znaleziono monitora o podanym adresie", {"OK"})
			madd["text"] = ""
		elseif amount ~= nil and amount > 1 then
			GMLmessageBox("Podany adres jest niejednoznaczny. Podaj więcej znaków", {"OK"})
		else
			if dsnPort then
				local s, c = dsapi.write(dsnPort, "the_guard/micro", serial.serialize({data.port, modem.address}))
				if s then
					logs("Zaktualizowano dane na serwerze")
				else
					logs("Nie można połączyć się z serwerem: " .. dsapi.translateCode(c))
				end
			end
			--[[if tostring(data.port) ~= port["text"] then
				if GMLmessageBox("Zmiana portu serwera spowoduje, że wszystkie mikrokontrolery przestaną działać.\
				Czy na pewno chcesz kontynuować?", {"Tak", "Nie"}) == "Nie" then return end
			end]]
			modem.close(data.port)
			data.port = sPort
			modem.open(data.port)
			data.switchPort = tsPort
			data.dsPort = dsnPort
			data.screen = faddress
			saveConfig()
			sgui:close()
		end
	end)
	sgui:addButton(34, 1, 15, 1, "Zmień hasło", function()
		local pgui = gml.create("center", "center", 50, 8, gpu)
		pgui:addLabel("center", 1, 16, "Zmiania hasła")
		pgui:addLabel(2, 3, 15, "Stare hasło:")
		pgui:addLabel(2, 4, 14, "Nowe hasło:")
		local op = pgui:addTextField(18, 3, 25)
		local np = pgui:addTextField(18, 4, 25)
		pgui:addButton(37, 6, 10, 1, "Anuluj", function() pgui:close() end)
		pgui:addButton(26, 6, 10, 1, "OK", function()
			if op["text"] == "" or np["text"] == "" then
				GMLmessageBox("Pola nie mogą być puste", {"OK"})
			elseif datacard.md5(op["text"]) ~= data.password then
				GMLmessageBox("Stare hasło jest niepoprawne", {"OK"})
			else
				data.password = datacard.md5(np["text"])
				saveConfig()
				pgui:close()
			end
		end)
		pgui:run()
	end)
	sgui:run()
end

local function sync()
	local oldMicros = micros
	local oldAmount = 0
	for k, _ in pairs(micros) do oldAmount = oldAmount + 1 end
	resplist = {}
	modem.broadcast(65533, data.port, messages.echo)
	event.timer(3, function()
		local newAmount = 0
		for k, _ in pairs(micros) do newAmount = newAmount + 1 end
		local added, removed = 0, 0
		for k, _ in pairs(micros) do
			local lap = 0
			for k2, _ in pairs(oldMicros) do
				lap = lap + 1
				if k ~= k2 and lap == oldAmount then
					added = added + 1
				end
			end
		end
		for k, _ in pairs(oldMicros) do
			local lap = 0
			for k2, _ in pairs(micros) do
				lap = lap + 1
				if k ~= k2 and lap == newAmount then
					removed = removed + 1
				end
			end
		end
		saveConfig()
		local igui = gml.create("center", "center", 35, 9, gpu)
		igui:addLabel("center", 1, 25, "ODŚWIEŻANIE ZAKOŃCZONE")
		igui:addLabel(2, 3, 30, "Liczba mikrokontrolerów: " .. newAmount)
		igui:addLabel(12, 4, 15, "Dodano: " .. tostring(added))
		igui:addLabel(12, 5, 15, "Usunięto: " .. tostring(removed))
		igui:addButton("center", 7, 10, 1, "OK", function() igui:close() end)
		igui:run()
	end)
end

local function performExit()
	local egui = gml.create("center", "center", 46, 7, gpu)
	egui:addLabel("center", 1, 30, "Aby wyjść, wprowadź hasło:")
	local field = egui:addTextField("center", 3, 28)
	egui:addButton(22, 5, 10, 1, "OK", function()
		if datacard.md5(field["text"]) ~= data.password then
			field["text"] = ""
			field:draw()
			beep()
		else
			egui:close()
			gui:close()
		end
	end)
	egui:addButton(33, 5, 10, 1, "Anuluj", function()
		egui:close()
	end)
	egui:run()
end

local function raiseAlert(level)
	silent = true
	if level == 4 and not data.blockade then
		blockade()
		if data.detector.cooldown then
			event.timer(data.detector.cooldown, function()
				if data.blockade then
					blockade()
				end
			end)
		end
	else
		resplist = nil
		if level > 0 and not data.alarm then
			alarm()
			if data.detector.cooldown then
				event.timer(data.detector.cooldown, function()
					resplist = nil
					if data.alarm then alarm() end
					resplist = {}
				end)
			end
		end
		os.sleep(0.5)
		if level == 2 and not data.shield then
			shield()
		elseif level == 3 and not data.tesla then
			tesla()
			if data.detector.cooldown then
				event.timer(data.detector.cooldown, function()
					if data.tesla then
						resplist = nil
						tesla()
					end
					sleep(0.5)
					resplist = {}
				end)
			end
		end
		resplist = {}
	end
	silent = false
end

local function modifyDetector(action)
	if action == "add" then
		local agui = gml.create("center", "center", 35, 6, gpu)
		agui:addLabel(2, 1, 25, "Podaj nazwę celu:")
		local field = agui:addTextField("center", 2, 25)
		agui:addButton(23, 4, 10, 1, "Anuluj", function() agui:close() end)
		agui:addButton(12, 4, 10, 1, "OK", function()
			if field["text"] == "" then
				beep()
				return
			end
			for _, v in ipairs(data.detector.list ) do
				if v == field["text"] then
					GMLmessageBox("Cel o takiej nazwie jest już na liście", {"OK"})
					return
				end
			end
			table.insert(data.detector.list, field["text"])
			detector.list:updateList(data.detector.list)
			updateCounter()
			agui:close()
		end)
		agui:run()
	elseif action == "remove" then
		local s = detector.list:getSelected()
		for i, v in ipairs(data.detector.list) do
			if v == s then
				table.remove(data.detector.list, i)
				detector.list:updateList(data.detector.list)
				updateCounter()
			end
		end
	elseif action == "mode" then
		data.detector.mode = not data.detector.mode
		detector.listMode["text"] = data.detector.mode and "whitelist" or "blacklist"
		detector.listMode:draw()
		updateCounter()
	elseif action == "level" then
		if not data.detector.level or data.detector.level > 3 then
			data.detector.level = 0
		else
			data.detector.level = data.detector.level + 1
		end
		detector.level["text"] = tostring(data.detector.level)
		detector.level:draw()
		updateCounter()
	elseif action == "cooldown" then
		if not data.detector.cooldown then
			data.detector.cooldown = 10
		elseif data.detector.cooldown < 30 then
			data.detector.cooldown = data.detector.cooldown + 10
		elseif data.detector.cooldown == 30 then
			data.detector.cooldown = 60
		elseif data.detector.cooldown == 60 then
			data.detector.cooldown = 120
		else
			data.detector.cooldown = nil
		end
		detector.cooldown["text"] = tostring(data.detector.cooldown or 0)
		detector.cooldown:draw()
		updateCounter()
	end
end

local function createMagneticCreator(oldName, oldObject)
	local retValue = nil
	local usedColors = {}
	local availableColors = {}
	availableColors.index = oldObject and oldObject.color or 1
	for i = 0, 15 do table.insert(availableColors, i) end
	for _, v in pairs(data.magnetic.list) do
		table.insert(usedColors, v.color)
	end
	table.sort(usedColors, function(a, b) return a > b end)
	for i = 1, #usedColors do
		table.remove(availableColors, usedColors[i])
	end
	local agui = gml.create("center", "center", 40, 11, gpu)
	agui:addLabel("center", 1, 16, oldObject and "Edytuj czytnik" or "Nowy czytnik")
	agui:addLabel(2, 3, 8, "Nazwa:")
	agui:addLabel(2, 4, 8, "Adres:")
	agui:addLabel(2, 5, 9, "Poziom:")
	agui:addLabel(2, 6, 8, "Kolor:")
	agui:addLabel(2, 7, 16, "Czas otwarcia:")
	local name = agui:addTextField(13, 3, 20)
	name["text"] = oldName or ""
	local address = agui:addTextField(13, 4, 20)
	address["text"] = oldObject and oldObject.address or ""
	local level = agui:addButton(13, 5, 6, 1, "1", function(self)
		if self["text"] == "1" then
			self["text"] = "2"
		else
			self["text"] = "1"
		end
		self:draw()
	end)
	level["text"] = oldObject and tostring(oldObject.level) or "1"
	local color = agui:addButton(13, 6, 12, 1, "", function(self)
		if availableColors.index < #availableColors then
			availableColors.index = availableColors.index + 1
		else
			availableColors.index = 1
		end
		self["text"] = colors[availableColors[availableColors.index]]
		self:draw()
	end)
	color["text"] = colors[oldObject and oldObject.color or availableColors[1]]
	local timeout = agui:addButton(20, 7, 6, 1, "5", function(self)
		local number = tonumber(self["text"])
		if number == 1 then number = 2
		elseif number == 2 then number = 3
		elseif number == 3 then number = 5
		elseif number == 5 then number = 10
		elseif number == 10 then number = 15
		else number = 1 end
		self["text"] = tostring(number)
		self:draw()
	end)
	timeout["text"] = oldObject and tostring(oldObject.timeout) or "5"
	agui:addButton(28, 9, 10, 1, "Anuluj", function()
		agui:close()
		retValue = false
	end)
	agui:addButton(17, 9, 10, 1, "OK", function()
		if name["text"] == "" or address["text"] == "" then
			GMLmessageBox("Wypełnij wszystkie pola", {"OK"})
		elseif data.magnetic.list[name["text"]] ~= nil then
			GMLmessageBox("Czynik o takiej nazwie już istnieje")
		else
			resplist = nil
			readers = {}
			sendCommand(messages.address, address["text"])
			os.sleep(2)
			if not readers[1] then
				GMLmessageBox("Nie znaleziono czytnika o podanym adresie", {"OK"})
			elseif readers[1] > 1 then
				GMLmessageBox("Podana część adresu wskazuje na kilka urządzeń. Podaj więcej znaków", {"OK"})
			else
				local tab = {}
				tab.address = readers[2]
				tab.level = tonumber(level["text"])
				tab.color = colors[color["text"]]
				tab.timeout = tonumber(timeout["text"])
				data.magnetic.list[name["text"]] = tab
				local list = {}
				for k, _ in pairs(data.magnetic.list or {}) do table.insert(list, k) end
				magnetic.list:updateList(list)
				saveConfig()
				agui:close()
				retValue = true
			end
			readers = nil
		end
	end)
	agui:run()
	return retValue
end

local function modifyMagnetic(action)
	if action == "add" then
		local amount = 0
		for _, _ in pairs(data.magnetic.list) do amount = amount + 1 end
		if amount < 16 then
			createMagneticCreator()
		else
			GMLmessageBox("Osiągnięto już maksymalną liczbę zarejestrowanych czytników", {"OK"})
		end
	elseif action == "remove" then
		local selName = magnetic.list:getSelected()
		if selName and data.magnetic.list[selName] then
			if GMLmessageBox("Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Tak" then
				data.magnetic.list[selName] = nil
				local list = {}
				for k, _ in pairs(data.magnetic.list or {}) do table.insert(list, k) end
				magnetic.list:updateList(list)
				saveConfig()
			end
		end
	elseif action == "modify" then
		local selName = magnetic.list:getSelected()
		if selName and data.magnetic.list[selName] then
			local tempContainer = data.magnetic.list[selName]
			data.magnetic.list[selName] = nil
			if not createMagneticCreator(selName, tempContainer) then
				data.magnetic.list[selName] = tempContainer
			end
		end
	elseif action == "card" then
		data.magnetic.card = not data.magnetic.card
		magnetic.card["text"] = data.magnetic.card and "tak" or "nie"
		magnetic.card["text-color"] = data.magnetic.card and 0x00ff00 or 0xff0000
		magnetic.card:draw()
		updateCounter()
	elseif action == "player" then
		data.magnetic.player = not data.magnetic.player
		magnetic.player["text"] = data.magnetic.player and "tak" or "nie"
		magnetic.player["text-color"] = data.magnetic.player and 0x00ff00 or 0xff0000
		magnetic.player:draw()
		updateCounter()
	elseif action == "codes" then
		local cgui = gml.create("center", "center", 50, 7, gpu)
		cgui:addLabel("center", 1, 41, "Wprowadź nowy kod kart magnetycznych:")
		local field = cgui:addTextField("center", 3, 30)
		cgui:addButton(38, 5, 10, 1, "Anuluj", function() cgui:close() end)
		cgui:addButton(27, 5, 10, 1, "OK", function()
			if field["text"] == "" then
				beep()
			elseif field["text"]:len() > 20 then
				GMLmessageBox("Kod nie może być dłuższy niż 20 znaków", {"OK"})
			elseif not tonumber(field["text"]) then
				GMLmessageBox("Wprowadzony kod musi być liczbą", {"OK"})
			else
				if data.magnetic.password and data.magnetic.password ~= tonumber(field["text"]) then
					if GMLmessageBox("Zmiana hasła spowoduje, że wszystkie karty magnetyczne przestaną działać. Czy chcesz kontynuować?", {"Tak", "Nie"}) == "Nie" then
						return
					end
				end
				data.magnetic.password = tonumber(field["text"])
				saveConfig()
				cgui:close()
			end
		end)
		cgui:run()
	end
end

local function addCard()
	if not component.isAvailable("os_cardwriter") then
		GMLmessageBox("Urządzenie zapisujące karty nie jest dostępne", {"OK"})
		return
	elseif not component.isAvailable("os_magreader") then
		GMLmessageBox("Czytnik kart nie jest dostępny", {"OK"})
		return
	elseif not data.magnetic.password then
		GMLmessageBox("Aby dodać kartę, ustaw kod kart magnetycznych", {"OK"})
		return
	end
	local leftList, rightList = {}, {}
	for k, _ in pairs(data.magnetic.list) do table.insert(leftList, k) end
	local cgui = gml.create("center", "center", 70, 34, gpu)
	cgui:addLabel("center", 1, 12, "Nowa karta")
	cgui:addLabel(2, 7, 9, "Nazwa:")
	cgui:addLabel(2, 9, 9, "Gracz:")
	cgui:addLabel(2, 11, 9, "Poziom:")
	cgui:addLabel(2, 13, 9, "Kolor:")
	cgui:addLabel(2, 15, 25, "Dostępne pomieszczenia:")
	local field = cgui:addTextField(13, 7, 20)
	local pName = cgui:addTextField(13, 9, 20)
	local level = cgui:addButton(13, 11, 8, 1, "1", function(self)
		self["text"] = self["text"] == "1" and "2" or "1"
		self:draw()
	end)
	local color = cgui:addButton(13, 13, 11, 1, "white", function(self)
		self.ind = self.ind < 15 and self.ind + 1 or 0
		self["text"] = colors[self.ind]
		self:draw()
	end)
	color.ind = 0
	local leftBox = cgui:addListBox(2, 18, 28, 14, leftList)
	leftBox:hide()
	local rightBox = cgui:addListBox(50, 18, 28, 14, {})
	rightBox:hide()
	local rightButton = cgui:addButton(31, 22, 8, 2, "--->", function()
		local sel = leftBox:getSelected()
		if sel then
			for k, v in pairs(leftList) do
				if v == sel then
					table.remove(leftList, k)
					break
				end
			end
			table.insert(rightList, sel)
			leftBox:updateList(leftList)
			rightBox:updateList(rightList)
		end
	end)
	rightButton:hide()
	local leftButton = cgui:addButton(31, 25, 8, 2, "<---", function()
		local sel = rightBox:getSelected()
		if sel then
			for k, v in pairs(rightList) do
				if v == sel then
					table.remove(rightList, k)
					break
				end
			end
			table.insert(leftList, sel)
			leftBox:updateList(leftList)
			rightBox:updateList(rightList)
		end
	end)
	leftButton:hide()
	cgui:addButton(29, 15, 12, 1, "wszystkie", function(self)
		if self["text"] == "wybrane" then
			self["text"] = "wszystkie"
			self:draw()
			leftBox:hide()
			rightBox:hide()
			leftButton:hide()
			rightButton:hide()
		else
			self["text"] = "wybrane"
			self:draw()
			leftBox:show()
			rightBox:show()
			leftButton:show()
			rightButton:show()
		end
	end)
	cgui:addButton(58, 1, 10, 1, "Anuluj", function() cgui:close() end)
	cgui:addButton("center", 3, 24, 3, "DODAJ KARTĘ", function()
		if not component.isAvailable("os_cardwriter") then
			GMLmessageBox("Urządzenie zapisujące karty nie jest dostępne", {"OK"})
		elseif not component.isAvailable("os_magreader") then
			GMLmessageBox("Czytnik kart nie jest dostępny", {"OK"})
		elseif field["text"] == "" or pName["text"] == "" then
			GMLmessageBox("Wypełnij wszystkie pola", {"OK"})
		elseif field["text"]:len() > 20 then
			GMLmessageBox("Nazwa karty nie może być dłuższa, niż 20 znaków", {"OK"})
		elseif pName["text"]:len() > 20 then
			GMLmessageBox("Nazwa gracza nie może być dłuższa, niż 20 znaków", {"OK"})
		else
			local cardcontent = {}
			cardcontent.player = pName["text"]
			cardcontent.level = tonumber(level["text"])
			cardcontent.pass = data.magnetic.password
			if not rightBox:isHidden() and #rightList > 0 then
				cardcontent.rooms = rightList
			end
			local deflatedData = datacard.encode64(datacard.deflate(serial.serialize(cardcontent)))
			if deflatedData:len() >= 128 then
				GMLmessageBox("Rozmiar danych przekracza pojemność karty. Usuń kilka pomieszczeń.")
				return
			end
			local writer = component.os_cardwriter
			if writer.write(deflatedData, field["text"], true, colors[color["text"]]) then
				local e = {}
				saveConfig()
				local igui = gml.create("center", "center", 49, 5, gpu)
				igui:addLabel(2, 1, 27, "Zapisywanie powiodło się.")
				igui:addLabel(2, 2, 45, "W ciągu 15 sekund kliknij kartą na czytnik,")
				igui:addLabel(2, 3, 31, "aby zarejestrować ją w bazie.")
				event.timer(1, function()
					e = {event.pull(14, "magData")}
					os.sleep(0.5)
					igui:close()
				end)
				igui:run()
				if e[1] == "magData" then
					if e[4] == deflatedData then
						table.insert(cards, {field["text"], e[5]})
						saveConfig()
						GMLmessageBox("Rejestracja powiodła się", {"OK"})
					else
						GMLmessageBox("Została odczytana niewłaściwa karta. Rejestracja nie powiodła się", {"OK"})
					end
				else
					GMLmessageBox("Rejestracja karty nie powiodła się", {"OK"})
				end
				cgui:close()
			else
				GMLmessageBox("Zapisywanie nie powiodło się: brak karty w slocie", {"OK"})
			end
		end
	end)
	cgui:run()
end

local function removeCard()
	local lgui = gml.create("center", "center", 48, 35)
	local newCards = cards
	local list = {}
	for _, v in pairs(cards) do table.insert(list, v[1]) end
	lgui:addLabel("center", 1, 12, "Usuń karty")
	local box = lgui:addListBox(2, 3, 44, 25, list)
	lgui:addButton(37, 33, 10, 1, "Anuluj", function() lgui:close() end)
	lgui:addButton(26, 33, 10, 1, "OK", function()
		cards = newCards
		saveConfig()
		lgui:close()
	end)
	lgui:addButton("center", 30, 13, 2, "Usuń", function()
		local sel = box:getSelected()
		if sel then
			for k, v in pairs(newCards) do
				if v[1] == sel then
					table.remove(newCards, k)
					break
				end
			end
			list = {}
			for _, v in pairs(newCards) do table.insert(list, v[1]) end
			box:updateList(list)
		end
	end)
	lgui:run()
end

local function removeAllCards()
	if GMLmessageBox("Usunięcie listy kart magnetycznych spowoduje, że wszystkie dotychczas utworzone przestaną działać. Czy chcesz kontynuować?", {"Tak", "Nie"}) == "Tak" then
		cards = {}
		saveConfig()
	end
end


--[[local function installSoftware()
	local oldList = component.list("filesystem")
	local igui = gml.create("center", "center", 50, 15)
	igui:addLabel("center", 1, 25, "Instalator kontrolerów")
	igui:addLabel(2, 3, 24, "1. Włóż dysk do stacji")
	igui:addLabel(2, 4, 34, "2. Wciśnij przycisk \"ISNTALUJ\"")
	igui:addLabel(2, 5, 46, "3. Na dysku zostanie zainstalowany kontroler")
	igui:addLabel("center", 6, 35, "UWAGA: dysk zostanie sofrmatowany")
	igui:addButton("center", 12, 10, 1, "Anuluj", function() igui:close() end)
	igui:addButton("center", 8, 15, 3, "INSTALUJ", function()
		local newList = component.list("filesystem")
		local disk = nil
		local dAmount = 0
		for _, _ in pairs(oldList) do
			dAmount = dAmount + 1
		end
		for k, _ in pairs(newList) do
			local a = 0
			for k2, _ in pairs(oldList) do
				a = a + 1
				if k == k2 then
					break
				elseif k ~= k2 and a == dAmount then
					disk = component.proxy(k)
					break
				end
			end
			if disk then break end
		end
		if disk then
			if GMLmessageBox("Adres dysku: " .. disk.address:sub(1, 3) ..". Czy chcesz kontynuować?", {"Tak", "Nie"}) == "Nie" then
				return
			end
			local rl = disk.list("/")
			for i = 1, #rl do
				disk.remove(rl[i])
			end
			local copy = function(name)
				local f = io.open(name, "r")
				local stream = f:read()
				f:close()
				local desc = disk.open(name, "w")
				disk.write(desc, stream)
				disk.close(desc)
			end
			disk.makeDirectory("/lib")
			copy("/lib/package.lua")
			copy("/lib/buffer.lua")
			copy("/lib/filesystem.lua")
			copy("/lib/io.lua")
			copy("/lib/event.lua")
			copy("/lib/serialization.lua")
			copy("/lib/keyboard.lua")
			local initStream = ""
			initStream = initStream .. "local serverPort = " .. tostring(data.port) .. "\n"
			initStream = initStream .. "local serverAddress = \"" .. modem.address .. "\"\n"
			initStream = initStream .. "local version = \"" .. microVersion .. "\"\n"
			initStream = initStream .. softStream
			local desc = disk.open("init.lua", "w")
			disk.write(desc, initStream)
			disk.close(desc)
			GMLmessageBox("Oprogramowanie zostało zapisane na dysku", {"OK"})
			igui:close()
		else
			GMLmessageBox("Nie znaleziono nowego dysku", {"OK"})
		end
	end)
	igui:run()
end]]

local function init()
	switch.blockade["text-color"] = data.blockade and 0x00ff00 or 0xff0000
	switch.tesla["text-color"] = data.tesla and 0x00ff00 or 0xff0000
	switch.shield["text-color"] = data.shield and 0x00ff00 or 0xff0000
	switch.alarm["text-color"] = data.alarm and 0x00ff00 or 0xff0000
	detector.list:updateList(data.detector.list or {})
	detector.listMode["text"] = data.detector.mode and "whitelist" or "blacklist"
	detector.level["text"] = tostring(data.detector.level or 0)
	detector.cooldown["text"] = tostring(data.detector.cooldown or 0)
	
	local list = {}
	for k, _ in pairs(data.magnetic.list or {}) do table.insert(list, k) end
	magnetic.list:updateList(list)
	magnetic.card["text"] = data.magnetic.card and "tak" or "nie"
	magnetic.card["text-color"] = data.magnetic.card and 0x00ff00 or 0xff0000
	magnetic.player["text"] = data.magnetic.player and "tak" or "nie"
	magnetic.player["text-color"] = data.magnetic.player and 0x00ff00 or 0xff0000
	
	ctid = event.timer(60, function()
		creatures = {}
	end, math.huge)
end

local function main()
	gui = gml.create(1, 1, resolution[1], resolution[2], gpu)
	addTitle()
	gui:addLabel(65, 2, 5, version)
	addBar(121, 1, 48, false)
	addBar(1, 9, 120, true)
	addBar(1, 41, 120, true)
	addBar(60, 10, 31, false)
	addBar(122, 31, 37, true)
	gui:addLabel(124, 2, 10, "POZIOM 4")
	gui:addLabel(124, 9, 10, "POZIOM 3")
	gui:addLabel(124, 16, 10, "POZIOM 2")
	gui:addLabel(124, 23, 10, "POZIOM 1")
	switch.blockade = gui:addButton(127, 4, 30, 3, "Całkowita blokada", blockade)
	switch.tesla = gui:addButton(127, 11, 30, 3, "Cewka Tesli", tesla)
	switch.shield = gui:addButton(127, 18, 30, 3, "Osłona", shield)
	switch.alarm = gui:addButton(127, 25, 30, 3, "Alarm", alarm)
	gui:changeFocusTo(gui:addButton(136, 33, 20, 1, "Zablokuj ekran", lockScreen))
	gui:addButton(136, 37, 20, 1, "Synchronizacja", sync)
	gui:addButton(143, 39, 13, 1, "Ustawienia", settings)
	gui:addButton(146, 47, 10, 1, "Wyjście", performExit)
	gui:addLabel(22, 11, 20, "DETEKTORY RUCHU")
	gui:addLabel(4, 14, 18, "Lista stworzeń:")
	detector.list = gui:addListBox(3, 15, 37, 20, {})
	detector.add = gui:addButton(46, 16, 12, 2, "Dodaj", function() modifyDetector("add") end)
	detector.add = gui:addButton(46, 19, 12, 2, "Usuń", function() modifyDetector("remove") end)
	gui:addLabel(4, 36, 12, "Tryb listy:")
	gui:addLabel(4, 38, 24, "Poziom bezpieczeństwa:")
	gui:addLabel(4, 40, 25, "Czas trwania alarmu [s]:")
	detector.listMode = gui:addButton(17, 36, 12, 1, "blacklist", function() modifyDetector("mode") end)
	detector.level = gui:addButton(28, 38, 4, 1, "0", function() modifyDetector("level") end)
	detector.cooldown = gui:addButton(29, 40, 6, 1, "10", function() modifyDetector("cooldown") end)
	gui:addLabel(85, 11, 12, "CZYTNIKI")
	gui:addLabel(64, 14, 18, "Lista czytników:")
	magnetic.list = gui:addListBox(63, 15, 37, 20, {})
	gui:addButton(106, 16, 12, 2, "Dodaj", function() modifyMagnetic("add") end)
	gui:addButton(106, 19, 12, 2, "Usuń", function() modifyMagnetic("remove") end)
	gui:addButton(106, 22, 12, 2, "Modyfikuj", function() modifyMagnetic("modify") end)
	gui:addLabel(64, 36, 20, "Autoryzacja karty:")
	gui:addLabel(64, 38, 20, "Autoryzacja gracza:")
	magnetic.card = gui:addButton(84, 36, 6, 1, "nie", function() modifyMagnetic("card") end)
	magnetic.player = gui:addButton(84, 38, 6, 1, "tak", function() modifyMagnetic("player") end)
	gui:addButton(64, 40, 14, 1, "Zmień kody", function() modifyMagnetic("codes") end)
	gui:addButton(96, 36, 14, 1, "Dodaj kartę", addCard)
	gui:addButton(96, 38, 14, 1, "Usuń kartę", removeCard)
	gui:addButton(96, 40, 24, 1, "Usuń wszystkie karty", removeAllCards)
	gui:addLabel(4, 42, 5, "LOGI:")
	logList = gui:addListBox(3, 43, 114, 6, {})
	GMLbgcolor = GMLextractProperty(gui, GMLgetAppliedStyles(gui), "fill-color-bg")
	init()
	event.timer(0.5, function() modem.broadcast(65533, data.port, messages.echo) end)
	gui:run()
end

--"modem_message", localAddress: string, remoteAddress: string, port: number, distance: number, remotePort: number, ...
local function modemListener(...)
	local e = {...}
	if e[7] == messages.echo then
		if e[8] == microVersion then
			modem.send(e[3], e[6], data.port, messages.ok)
			micros[e[3]] = e[6]
			logs("Dodano mikrokontroler (" .. e[3]:sub(1, 5) .. ")")
			component.computer.beep(1800, 0.4)
		else
			modem.send(e[3], e[6], data.port, messages.disable)
			logs("Mikrokontroler (" .. e[3]:sub(1, 5) .. ") jest nieaktualny (v" .. e[8] ..", aktualna wersja: v" .. microVersion .. ")")
		end
	elseif e[7] == messages.ok then
		if resplist ~= nil then
			resplist[e[3]] = math.random()
		end
	elseif e[7] == messages.mag then
		local s = serial.unserialize(e[8])
		if s ~= nil and s[1] == "magData" and s[6] then
			local inflated = serial.unserialize(datacard.inflate(datacard.decode64(s[4] or "")) or "")
			if inflated then
				local failmsg = function(msg)
					logs("Nieudana próba użycia karty (" .. s[5]:sub(1, 5) .. "): " .. msg)
				end
				local genuine = false
				local access = true
				for k, v in pairs(cards) do
					if v[2] == s[5] then
						genuine = true
						if inflated.rooms and not inflated.rooms[k] then access = false end
						break
					end
				end
				if data.blockade and inflated.level < 2 then
					failmsg("pierwszy poziom podczas blokady")
				elseif inflated.pass ~= data.magnetic.password then
					failmsg("błędne hasło")
				elseif not access then
					failmsg("brak dostępu")
				elseif data.magnetic.card and not genuine then
					failmsg("karta nie jest autentyczna")
				elseif data.magnetic.player and inflated.player ~= s[3] then
					failmsg("weryfikacja gracza nie powiodła się")
				else
					for _, v in pairs(data.magnetic.list) do
						if v.address == s[2] then
							if v.level <= inflated.level then
								sendCommand(messages.color, sides.right, v.color, 250, v.timeout)
								logs("Użyto karty " .. s[5]:sub(1, 5))
								return
							else
								failmsg("zbyt niski poziom")
							end
						end
					end
					failmsg("nie znaleziono czytnika o adresie " .. s[2]:sub(1, 5))
				end
			end
		end
	elseif e[7] == messages.move then
		local s = serial.unserialize(e[8])
		if s ~= nil and s[1] == "motion" and creatures[s[6]] == nil then
			creatures[s[6]] = math.random()
			logs("Wykryto obiekt: " .. s[6])
			if data.detector.mode then
				for _, v in pairs(data.detector.list) do
					if v ~= s[6] then
						raiseAlert(data.detector.level or 0)
					end
				end
			else
				for _, v in pairs(data.detector.list) do
					if v == s[6] then
						raiseAlert(data.detector.level or 0)
					end
				end
			end
		end
	elseif e[7] == messages.address and type(readers) == "table" and #readers == 0 then
		readers[1] = e[8]
		readers[2] = e[9]
	end
end

loadConfig()
local r = {gpu.getResolution()}
if r[1] ~= 160 or r[2] ~= 50 then
	gpu.bind(screen2.address)
	io.stderr:write("Docelowy monitor i/lub karta graficzna nie jest urzadzeniem 3 poziomu")
	return
end
r = nil
if data.modemAddress and data.modemAddress ~= modem.address then
	GMLmessageBox("Wykryto nową kartę sieciową. Dotychczas utworzone mikrokontrolery przestaną działać.", {"OK"})
end
modem.open(data.port)
event.listen("modem_message", modemListener)
main()
event.ignore("modem_message", modemListener)
modem.close(data.port)
event.cancel(ctid or 0)
saveConfig()
gpu.bind(screen2.address)