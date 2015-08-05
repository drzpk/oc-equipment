-- ################################################
-- #                The Switch                    #
-- #                                              #
-- #  07.2015                      by: Aranthor   #
-- ################################################

--[[
	## Opis programu
		Program pozwala na sterowanie sygnałami czerwonego kamienia.
	## Struktura danych pomieszczenia
		switch[?] = {
			id - identyfikator,
			name - nazwa,
			address - adres bloku redstone I/O,
			side - strona
			door - status drzwi (true - otwarte, false - zamknięte),
			lock - status blokady drzwi,
			light - status świateł,
			green - status koloru zielonego,
			red - status koloru czerwonego,
			blue - status koloru niebieskiego,
			yellow - status koloru źółtego
		}
		
	## Wiadomości sieciowe
		Wiadomość znajduje się w siódmym parametrze (szósty zawiera port zwrotny)
		Serwer przed wysłaniem każdej wiadomości poddaje ją serializacji, a po 
		odebraniu - deserializacji.
		Zapytania do serwera:
		"{<cel>, <id>, <akcja>}"
		Cele są opisane poniżej w zmiennej 'targets'. ID to identyfikator 
		pomieszczenia. Akcja może przyjąć jedną
		z następujących wartości:
		true - otwarcie / włączenie koloru, drzwi lub blokady
		false - zamknięcie / wyłącznie koloru, drzwi lub blokady
		nil - sprawdzenie stanu
		Odpowiedzi sewera:
		"{<true/false>, [<code>]}"
		Pierwszy parametr przyjmuje wartość 'true', gdy serwer poprawnie obsłużył
		żądanie. Drugi parametr jest wtedy pusty lub opcjonalnie zawiera status
		celu.
		Gdy zapytanie jest niepoprawne, pierwszy parametr ma wartość 'false'
		a drugi zawiera tablicę z kodem oraz opisem błędu.
		
]]
package.loaded.gml = nil
package.loaded.gfxbuffer = nil

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version
elseif #args < 1 then
	print("Użycie programu:")
	print("the_switch <kod> [monitor]")
	print(" kod - kod potrzebny do wyłącznia programu")
	print(" monitor - adres monitora docelowego")
	return
end

local component = require("component")
local event = require("event")
local serial = require("serialization")
local fs = require("filesystem")
local colors = require("colors")
local gml = require("gml")
if not component.isAvailable("modem") then
	io.stderr:write("Program wymaga do działania karty sieciowej")
	return
end
local modem = component.modem

local resolution = {160, 50}

local screen = nil
local screen2 = component.screen
local gpu = component.gpu
local port = 0
local switch = {}
local GMLbgcolor = nil

local gui = nil
local title = {}
local section = {}
local page = 1
local counter = 10
local password = args[1]

local targets = {
	door = 0x1,  -- drzwi
	lock = 0x2,  -- blokada drzwi
	light = 0x3, -- światło
	green = 0x4, -- zielony kabel
	red = 0x5,   -- czerwony kabel
	blue = 0x6,  -- niebieski kabel
	yellow = 0x7, -- źółty kabel
	openall = 0x50,
	closeall = 0x51,
	lockall = 0x52,
	unlockall = 0x53,
	turnonall = 0x54,
	turnoffall = 0x55
}

local errors = {
	badTarget = {0x1, "Wybrany cel nie istnieje"},
	badID = {0x2, "Wybrany identyfikator nie istnieje"},
	badAction = {0x3, "Wybrana akcja nie istnieje"},
	internal = {0x4, "Błąd wewnętrzny serwera"}
}


local function loadConfig()
	if not fs.isDirectory("/etc/the_switch") then fs.makeDirectory("/etc/the_switch") end
	local f = nil
	if fs.exists("/etc/the_switch/config.conf") then
		f = io.open("/etc/the_switch/config.conf", "r")
		port, screenAddress, switch = table.unpack(serial.unserialize(f:read()))
		f:close()
		port = port or math.random(100, 65533)
		switch = switch or {}
		screen = component.proxy(args[2] or screenAddress or "")
		if screen == nil then 
			screen = screen2
		else
			screen.turnOn()
		end
		gpu.bind(screen.address)
	else
		f = fs.open("/etc/the_switch/config.conf", "w")
		port = math.random(100, 65533)
		f:write(serial.serialize(table.pack(port, nil, switch)))
		f:close()
	end
end

local function saveConfig()
	local f = io.open("/etc/the_switch/config.conf", "w")
	local screenAddress = ""
	if screen ~= nil then screenAddress = screen.address end
	f:write(serial.serialize({port, screenAddress, switch}))
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
	title.width = 68
	title.height = 5
	title.contains = GMLcontains
	title.isHidden = function(c) return false end
	title.draw = function(t)
		t.renderTarget.setBackground(0xff0000)
		t.renderTarget.fill(3, 3, 5, 1, ' ')--t
		t.renderTarget.fill(5, 4, 1, 4, ' ')
		t.renderTarget.fill(10, 3, 1, 5, ' ')--h
		t.renderTarget.fill(13, 3, 1, 5, ' ')
		t.renderTarget.fill(11, 5, 2, 1, ' ')
		t.renderTarget.fill(16, 3, 1, 5, ' ')--e
		t.renderTarget.fill(17, 3, 3, 1, ' ')
		t.renderTarget.fill(17, 5, 3, 1, ' ')
		t.renderTarget.fill(17, 7, 3, 1, ' ')
		t.renderTarget.fill(30, 3, 3, 1, ' ')--s
		t.renderTarget.fill(30, 5, 3, 1, ' ')
		t.renderTarget.fill(30, 7, 3, 1, ' ')
		t.renderTarget.set(29, 4, ' ')
		t.renderTarget.set(33, 6, ' ')
		t.renderTarget.fill(36, 3, 1, 2, ' ')--w
		t.renderTarget.fill(37, 5, 1, 2, ' ')
		t.renderTarget.fill(38, 7, 2, 1, ' ')
		t.renderTarget.fill(39, 5, 1, 2, ' ')
		t.renderTarget.fill(40, 7, 2, 1, ' ')
		t.renderTarget.fill(41, 5, 1, 2, ' ')
		t.renderTarget.fill(42, 3, 1, 2, ' ')
		t.renderTarget.fill(45, 3, 5, 1, ' ')--i
		t.renderTarget.fill(47, 4, 1, 3, ' ')
		t.renderTarget.fill(45, 7, 5, 1, ' ')
		t.renderTarget.fill(52, 3, 5, 1, ' ')--t
		t.renderTarget.fill(54, 4, 1, 4, ' ')
		t.renderTarget.fill(61, 3, 3, 1, ' ')--c
		t.renderTarget.fill(61, 7, 3, 1, ' ')
		t.renderTarget.set(60, 4, ' ')
		t.renderTarget.set(59, 5, ' ')
		t.renderTarget.set(60, 6, ' ')
		t.renderTarget.fill(66, 3, 1, 5, ' ')--h
		t.renderTarget.fill(69, 3, 1, 5, ' ')
		t.renderTarget.fill(67, 5, 2, 1, ' ')
	end
	gui:addComponent(title)
	return title
end

local function addBar(y)
	local bar = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gui.renderTarget
	}
	bar.posX = 1
	bar.posY = y
	bar.width = 158
	bar.height = 1
	bar.contains = GMLcontains
	bar.isHidden = function(c) return c.hidden or c.gui:isHidden() end
	bar.hide = function(element)
		if element.visible then
			element.visible = false
			element.gui:redrawRect(element.posX, element.posY, element.width, element.height)
		end
		element.hidden = true
	end
	bar.show = function(element)
		element.hidden = false
		if not element.visible then
			element:draw()
		end
	end
	bar.draw = function(t)
		if not t.hidden then
			t.renderTarget.setBackground(GMLbgcolor)
			t.renderTarget.setForeground(0xffffff)
			t.renderTarget.set(t.posX + 1, t.posY + 1, string.rep(require("unicode").char(0x2550), t.width))
			t.visible = true
		end
	end
	gui:addComponent(bar)
	return bar
end

local function addColor(x, y, hex)
	local color = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gui.renderTarget
	}
	color.posX = x
	color.posY = y
	color.width = 16
	color.height = 1
	color.color = hex
	color.contains = GMLcontains
	color.isHidden = function(c) return c.hidden or c.gui:isHidden() end
	color.hide = function(element)
		if element.visible then
			element.visible = false
			element.gui:redrawRect(element.posX, element.posY, element.width, element.height)
		end
		element.hidden = true
	end
	color.show = function(element)
		element.hidden = false
		if not element.visible then
			element:draw()
		end
	end
	color.draw = function(t)
		if not t.hidden then
			t.renderTarget.setBackground(t.color)
			t.renderTarget.fill(t.posX + 1, t.posY + 1, t.width, t.height, ' ')
			t.visible = true
		end
	end
	gui:addComponent(color)
	return color
end

local function refreshSection(index)
	local shape = section[index]
	if switch[(page - 1) * 7 + index] ~= nil then
		local s = switch[(page - 1) * 7 + index]
		shape.index["text"] = "#" .. tostring((page - 1) * 7 + index)
		shape.name["text"] = s.name
		if s.door then
			shape.doorSwitch["text"] = "Otwarte"
			shape.doorSwitch["text-color"] = 0x00ff00
		else
			shape.doorSwitch["text"] = "Zamknięte"
			shape.doorSwitch["text-color"] = 0xff0000
		end
		if s.lock then
			shape.doorLock["text"] = "Zablokowane"
			shape.doorLock["text-color"] = 0x00ff00
		else
			shape.doorLock["text"] = "Odblokowane"
			shape.doorLock["text-color"] = 0xff0000
		end
		if s.light then
			shape.lightSwitch["text"] = "Włączone"
			shape.lightSwitch["text-color"] = 0x00ff00
		else
			shape.lightSwitch["text"] = "Wyłaczone"
			shape.lightSwitch["text-color"] = 0xff0000
		end
		if s.green then
			shape.greenSwitch["text"] = "ON"
			shape.greenSwitch["text-color"] = 0x00ff00
		else
			shape.greenSwitch["text"] = "OFF"
			shape.greenSwitch["text-color"] = 0xff0000
		end
		if s.red then
			shape.redSwitch["text"] = "ON"
			shape.redSwitch["text-color"] = 0x00ff00
		else
			shape.redSwitch["text"] = "OFF"
			shape.redSwitch["text-color"] = 0xff0000
		end
		if s.blue then
			shape.blueSwitch["text"] = "ON"
			shape.blueSwitch["text-color"] = 0x00ff00
		else
			shape.blueSwitch["text"] = "OFF"
			shape.blueSwitch["text-color"] = 0xff0000
		end
		if s.yellow then
			shape.yellowSwitch["text"] = "ON"
			shape.yellowSwitch["text-color"] = 0x00ff00
		else
			shape.yellowSwitch["text"] = "OFF"
			shape.yellowSwitch["text-color"] = 0xff0000
		end
		for _, v in pairs(shape) do
			if v:isHidden() then
				v:show()
			else
				v:draw()
			end
		end
	else
		for _, v in pairs(shape) do
			if not v:isHidden() then
				v:hide()
			end
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

local function add()
	local snippet, amount = nil, 0
	local cgui = gml.create("center", "center", 55, 10, gpu)
	cgui:addLabel("center", 1, 19, "Nowe pomieszczenie")
	cgui:addLabel(2, 3, 21, "Identyfikator:   #" .. tostring(#switch + 1))
	cgui:addLabel(2, 4, 7, "Nazwa:")
	cgui:addLabel(2, 5, 7, "Adres:")
	cgui:addLabel(2, 6, 8, "Strona:")
	local name = cgui:addTextField(19, 4, 20)
	local address= cgui:addTextField(19, 5, 20)
	local side = cgui:addTextField(19, 6, 20)
	cgui:addButton(41, 8, 10, 1, "Anuluj", function() cgui:close() end)
	cgui:addButton(30, 8, 10, 1, "OK", function()
		amount, snippet = searchAddress("redstone", address["text"])
		if name["text"]:len() == 0 or address["text"]:len() == 0 or side["text"]:len() == 0 then
			GMLmessageBox("Wypełnij wszystkie pola!", {"OK"})
		elseif name["text"]:len() > 30 then
			GMLmessageBox("Nazwa nie może być dłuższa niż 30 znaków", {"OK"})
		elseif amount == 0 then
			GMLmessageBox("Nie znaleziono urządzenia Redstone I/O o podanym adresie", {"OK"})
		elseif amount > 1 then
			GMLmessageBox("Podana część adresu nie jest jednoznaczna. Wpisz więcej znaków", {"OK"})
		elseif tonumber(side["text"]) == nil or tonumber(side["text"]) > 6 or tonumber(side["text"]) < 0 then
			GMLmessageBox("Strona jest niepoprawna", {"OK"})
		else
			local item = {}
			item.name = name["text"]
			item.address = snippet
			item.side = tonumber(side["text"])
			local red = component.proxy(snippet)
			if red.getBundledOutput(item.side, colors.lightblue) > 0 then
				item.door = true
			elseif red.getBundledOutput(item.side, colors.white) > 0 then
				item.light = true
			elseif red.getBundledOutput(item.side, colors.green) > 0 then
				item.green = true
			elseif red.getBundledOutput(item.side, colors.red) > 0 then
				item.red = true
			elseif red.getBundledOutput(item.side, colors.blue) > 0 then
				item.blue = true
			elseif red.getBundledOutput(item.side, colors.yellow) > 0 then
				item.yellow = true
			end
			table.insert(switch, item)
			saveConfig()
			if #switch <= page * 7 then refreshSection(#switch - (page - 1) * 7) end
			title.page["text"] = "Strona: " .. page .. "/" .. math.ceil(#switch / 7)
			cgui:close()
		end
	end)
	cgui:run()
end

local function modify(index)
	local snippet, amount = nil, 0
	local s = switch[index + (page - 1) * 7]
	local mgui = gml.create("center", "center", 55, 10, gpu)
	mgui:addLabel("center", 1, 26, "Edycja pomieszczenia #" .. tostring(index + (page - 1) * 7))
	mgui:addLabel(2, 3, 7, "Nazwa:")
	mgui:addLabel(2, 4, 7, "Adres:")
	mgui:addLabel(2, 5, 8, "Strona:")
	local name = mgui:addTextField(19, 3, 20)
	name["text"] = s.name or ""
	local address = mgui:addTextField(19, 4, 20)
	address["text"] = s.address
	local side = mgui:addTextField(19, 5, 20)
	side["text"] = tostring(s.side)
	mgui:addButton(41, 7, 10, 1, "Anuluj", function() mgui:close() end)
	mgui:addButton(30, 7, 10, 1, "OK", function()
		amount, snippet = searchAddress("redstone", address["text"])
		if name["text"]:len() == 0 or address["text"]:len() == 0 or side["text"]:len() == 0 then
			GMLmessageBox("Wypełnij wszystkie pola!", {"OK"})
		elseif name["text"]:len() > 30 then
			GMLmessageBox("Nazwa nie może być dłuższa niż 30 znaków", {"OK"})
		elseif amount == 0 then
			print("adres: " .. address["text"] .. "  dlugosc: " .. address["text"]:len())
			GMLmessageBox("Nie znaleziono urządzenia Redstone I/O o podanym adresie", {"OK"})
		elseif amount > 1 then
			GMLmessageBox("Podana część adresu nie jest jednoznaczna. Wpisz więcej znaków", {"OK"})
		elseif tonumber(side["text"]) == nil or tonumber(side["text"]) > 6 or tonumber(side["text"]) < 0 then
			GMLmessageBox("Strona jest niepoprawna", {"OK"})
		else
			local r = component.proxy(snippet)
			r.setBundledOutput(s.side, colors.lightblue, 0)
			r.setBundledOutput(s.side, colors.white, 0)
			r.setBundledOutput(s.side, colors.green, 0)
			r.setBundledOutput(s.side, colors.red, 0)
			r.setBundledOutput(s.side, colors.blue, 0)
			r.setBundledOutput(s.side, colors.yellow, 0)
			s.name = name["text"]
			s.address = snippet
			s.side = tonumber(side["text"])
			switch[index + (page - 1) * 7] = s
			saveConfig()
			refreshSection(index)
			mgui:close()
		end
	end)
	mgui:run()
end

local function delete(index)
	if GMLmessageBox("Czy na pewno chcesz usunąć pomieszczenie #" .. tostring(index) .. "?", {"Tak", "Nie"}) == "Tak" then
		table.remove(switch, index + (page - 1) * 7)
		saveConfig()
		for i = 1, 7 do
			refreshSection(i)
		end
	end
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
		elseif not require("dsapi").echo(tonumber(field["text"])) then
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
		local dsapi = require("dsapi")
		local status, code = dsapi.write(serverPort, "the_switch/config.backup", serial.serialize({port, screenAddress, switch}))
		if status then
			GMLmessageBox("Kopia została wykonana pomyślnie", {"OK"})
		else
			GMLmessageBox("Błąd: " .. dsapi.translateCode(code), {"OK"})
		end
	end
end

local function restore()
	local serverPort = getServerAddress()
	if serverPort ~= -1 then
		local dsapi = require("dsapi")
		local status, code = dsapi.get(serverPort, "the_switch/config.backup")
		if status then
			local f = io.open("/etc/the_switch/config.conf", "w")
			screenAddress = ""
			if screen ~= nil then screenAddress = screen.address end
			f:write(code)
			f:close()
			GMLmessageBox("Przywracanie zostało wykonane pomyślnie. Komputer zostanie uruchomiony ponownie", {"OK"})
			require("computer").shutdown(true)
		else
			GMLmessageBox("Błąd: " .. dsapi.translateCode(code), {"OK"})
		end
	end
end

local function settings()
	local sgui = gml.create("center", "center", 54, 8, gpu)
	sgui:addLabel("center", 1, 11, "Ustawienia")
	sgui:addLabel(2, 3, 18, "Port [100-65533]:")
	sgui:addLabel(2, 4, 21, "Adres monitora:")
	local portField = sgui:addTextField(23, 3, 18)
	portField["text"] = tostring(port)
	local addressField = sgui:addTextField(23, 4, 18)
	if screen ~= nil then addressField["text"] = screen.address end
	sgui:addButton(2, 6, 10, 1, "Kopia", backup)
	sgui:addButton(13, 6, 14, 1, "Przywracanie", restore)
	sgui:addButton(41, 6, 10, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(30, 6, 10, 1, "OK", function()
		local amount, fullAddress = 0, ""
		if addressField["text"] ~= "" then
			amount, fullAddress = searchAddress("screen", addressField["text"])
		end
		if portField["text"] == "" then
			GMLmessageBox("Wpisz numer portu", {"OK"})
		elseif tonumber(portField["text"]) == nil then
			GMLmessageBox("Wpisany port jest niepoprawny", {"OK"})
		elseif tonumber(portField["text"]) > 65533 or tonumber(portField["text"]) < 100 then
			GMLmessageBox("Wybrany numer portu wykracza poza zakres", {"OK"})
		elseif addressField["text"] ~= "" and amount == 0 then
			GMLmessageBox("Nie znaleziono monitora o podanym adresie", {"OK"})
		elseif addressField["text"] ~= "" and amount > 1 then
			GMLmessageBox("Podany adres nie jest jednoznaczny, wpisz więcej znaków", {"OK"})
		else
			modem.close(port)
			port = tonumber(portField["text"])
			modem.open(port)
			if amount > 0 then
				GMLmessageBox("Drugi monitor będzie dostępny po ponownym uruchomieniu programu", {"OK"})
				if screen ~= nil and gui2 ~= nil then
					gui2:close()
					screen.turnOff()
				end
				gpu2 = component.proxy(fullAddress)
			end
			saveConfig()
			sgui:close()
		end
	end)
	sgui:run()
end

local function changePage(direction)
	if direction == 1 and #switch > page * 7 then
		page = page + 1
		title.page["text"] = "Strona: " .. page .. "/" .. math.ceil(#switch / 7)
		title.page:draw()
		for i = 1, 7 do refreshSection(i) end
	elseif direction == -1 and page > 1 then
		page = page - 1
		title.page["text"] = "Strona: " .. page .. "/" .. math.ceil(#switch / 7)
		title.page:draw()
		for i = 1, 7 do refreshSection(i) end
	end
end

local function switchAllDoors(bool)
	for _, v in pairs(switch) do
		v.door = bool
		local r = component.proxy(v.address or "")
		if r ~= nil then
			r.setBundledOutput(v.side, colors.lightblue, bool and 255 or 0)
		end
	end
	for i = 1, 7 do refreshSection(i) end
	saveConfig()
end

local function lockAllDoors(bool)
	for _, v in pairs(switch) do v.lock = bool end
	for i = 1, 7 do refreshSection(i) end
	saveConfig()
end

local function switchAllLights(bool)
	for _, v in pairs(switch) do
		v.light = bool
		local r = component.proxy(v.address or "")
		if r ~= nil then
			r.setBundledOutput(v.side, colors.white, bool and 255 or 0)
		end
	end
	for i = 1, 7 do refreshSection(i) end
	saveConfig()
end

local function updateCounter()
	counter = counter - 1
	if counter == 1 then saveConfig() end
end

local function switchDoor(index)
	local object = switch[(page - 1) * 7 + index]
	local r = component.proxy(object.address or "")
	if r ~= nil then
		object.door = not object.door
		r.setBundledOutput(object.side, colors.lightblue, object.door and 255 or 0)
		refreshSection(index)
		updateCounter()
	else
		GMLmessageBox("Nie odnaleziono urządzenia. Sprawdź adres", {"OK"})
	end
end

local function lockDoor(index)
	local object = switch[(page - 1) * 7 + index]
	object.lock = not object.lock
	refreshSection(index)
	updateCounter()
end

local function switchLight(index)
	local object = switch[(page - 1) * 7 + index]
	local r = component.proxy(object.address or "")
	if r ~= nil then
		object.light = not object.light
		r.setBundledOutput(object.side, colors.white, object.light and 255 or 0)
		refreshSection(index)
		updateCounter()
	else
		GMLmessageBox("Nie odnaleziono urządzenia. Sprawdź adres", {"OK"})
	end
end

local function switchSignal(color, index)
	local object = switch[(page - 1) * 7 + index]
	local r = component.proxy(object.address or "")
	if r ~= nil then
		if color == colors.green then
			object.green = not object.green
			r.setBundledOutput(object.side, color, object.green and 255 or 0)
		elseif color == colors.red then
			object.red = not object.red
			r.setBundledOutput(object.side, color, object.red and 255 or 0)
		elseif color == colors.blue then
			object.blue = not object.blue
			r.setBundledOutput(object.side, color, object.blue and 255 or 0)
		elseif color == colors.yellow then
			object.yellow = not object.yellow
			r.setBundledOutput(object.side, color, object.yellow and 255 or 0)
		end
		refreshSection(index)
		updateCounter()
	else
		GMLmessageBox("Nie odnaleziono urządzenia. Sprawdź adres", {"OK"})
	end
end

local function doExit()
	local egui = gml.create("center", "center", 45, 5)
	egui:addLabel(2, 1, 27, "Podaj hasło, aby wyjść: ")
	local pass = egui:addTextField(31, 1, 10)
	egui:addButton(32, 3, 10, 1, "Anuluj", function() egui:close() end)
	egui:addButton(21, 3, 10, 1, "OK", function()
		if pass["text"] == password then
			egui:close()
			gui:close()
		else
			GMLmessageBox("Wprowadzone hasło jest niepoprawne",{"OK"})
			egui:close()
		end
	end)
	egui:run()
end

local function main()
	gui = gml.create(1, 1, resolution[1], resolution[2], gpu)
	title.title = addTitle()
	title.version = gui:addLabel(71, 2, 5, version)
	title.settings = gui:addButton(119, 2, 15, 1, "Ustawienia", settings)
	title.exit = gui:addButton(135, 2, 12, 1, "Wyjście", function() doExit() end)
	title.page = gui:addLabel(18, 13, 15, "Strona: 1/" .. math.ceil(#switch / 7))
	title.nextPage = gui:addButton(35, 13, 4, 1, "->", function() changePage(1) end)
	title.prevPage = gui:addButton(12, 13, 4, 1, "<-", function() changePage(-1) end)
	title.allDooors = gui:addLabel(72, 8, 17, "Wszystkie drzwi:")
	title.allDoorsOpen = gui:addButton(91, 8, 9, 1, "Otwórz", function() switchAllDoors(true) end)
	title.allDoorsOpen["text-color"] = 0x00ff00
	title.allDoorsClose = gui:addButton(101, 8, 9, 1, "Zamknij", function() switchAllDoors(false) end)
	title.allDoorsClose["text-color"] = 0xff0000
	title.allDoorsLock = gui:addButton(112, 8, 10, 1, "Odblokuj", function() lockAllDoors(false) end)
	title.allDoorsLock["text-color"] = 0x00ff00
	title.allDoorsUnlock = gui:addButton(123, 8, 10, 1, "Zablokuj", function() lockAllDoors(true) end)
	title.allDoorsUnlock["text-color"] = 0xff0000
	title.allLights = gui:addLabel(72, 10, 21, "Wszystkie światła:")
	title.allLightsOn = gui:addButton(95, 10, 10, 1, "Włącz", function() switchAllLights(true) end)
	title.allLightsOn["text-color"] = 0x00ff00
	title.allLightsOff = gui:addButton(106, 10, 10, 1, "Wyłącz", function() switchAllLights(false) end)
	title.allLightsOff["text-color"] = 0xff0000
	title.addRoom = gui:addButton(132, 13, 23, 1, "Dodaj pomieszczenie", function() add() end)
	GMLbgcolor = GMLextractProperty(gui, GMLgetAppliedStyles(gui), "fill-color-bg")
	for i = 0, 6 do
		local shape = {}
		shape.bar = addBar(14 + 5 * i)
		shape.index = gui:addLabel(5, 15 + 5 * i, 4, "#1")
		shape.name = gui:addLabel(18, 15 + 5 * i, 90, "")
		shape.modify = gui:addButton(125, 15 + 5 * i, 13, 1, "Modyfikuj", function() modify(i + 1) end)
		shape.delete = gui:addButton(139, 15 + 5 * i, 9, 1, "Usuń", function() delete(i + 1) end)
		shape.door = gui:addLabel(3, 17 + 5 * i, 7, "Drzwi: ")
		shape.doorSwitch = gui:addButton(15, 17 + 5 * i, 15, 1, "Otwarte", function() switchDoor(i + 1) end)
		shape.doorSwitch["text-color"] = 0x00ff00
		shape.doorLock = gui:addButton(31, 17 + 5 * i, 17, 1, "Odblokowane", function() lockDoor(i + 1) end)
		shape.doorLock["text-color"] = 0x00ff00
		shape.light = gui:addLabel(3, 18 + 5 * i, 11, "Światło:")
		shape.lightSwitch = gui:addButton(15, 18 + 5 * i, 13, 1, "Włączone", function() switchLight(i + 1) end)
		shape.lightSwitch["text-color"] = 0x00ff00
		shape.green = addColor(59, 17 + 5 * i, 0x00ff00)
		shape.red = addColor(78, 17 + 5 * i, 0xff0000)
		shape.blue = addColor(97, 17 + 5 * i, 0x0000ff)
		shape.yellow = addColor(116, 17 + 5 * i, 0xffff00)
		shape.greenSwitch = gui:addButton(64, 18 + 5 * i, 7, 1, "OFF", function() switchSignal(colors.green, i + 1) end)
		shape.greenSwitch["text-color"] = 0xff0000
		shape.redSwitch = gui:addButton(83, 18 + 5 * i, 7, 1, "OFF", function() switchSignal(colors.red, i + 1) end)
		shape.redSwitch["text-color"] = 0xff0000
		shape.blueSwitch = gui:addButton(102, 18 + 5 * i, 7, 1, "OFF", function() switchSignal(colors.blue, i + 1) end)
		shape.blueSwitch["text-color"] = 0xff0000
		shape.yellowSwitch = gui:addButton(121, 18 + 5 * i, 7, 1, "OFF", function() switchSignal(colors.yellow, i + 1) end)
		shape.yellowSwitch["text-color"] = 0xff0000
		table.insert(section, shape)
	end
	for i = 1, 7 do
		if i > #switch then
			for j = i, 7 do
				for _, v in pairs(section[j]) do
					v:hide()
				end
			end
			break
		end
		refreshSection(i)
	end
	gui:run()
	if screen.address ~= screen2.address then screen.turnOff() end
	gpu.setBackground(0)
	require("term").clear()
end

local function modemListener(...)
	os.sleep(0.1)
	local e = {...}
	if e[4] == port then
		local msg = serial.unserialize(e[7])
		local s = switch[msg[2]]
		local color = nil
		local r = nil
		if s == nil then
			modem.send(e[3], e[6], nil, serial.serialize({false, errors.badID}))
			return
		end
		r = component.proxy(s.address or "")
		if r == nil then
			modem.send(e[3], e[6], nil, serial.serialize({false, errors.internal}))
			return
		elseif msg[3] ~= true and msg[3] ~= false and msg[3] ~= nil then
			modem.send(e[3], e[6], nil, serial.serialize({false, errors.badAction}))
			return
		end
		if msg[1] == targets.door then
			color = colors.lightblue
		elseif msg[1] == targets.light then
			color = colors.white
		elseif msg[1] == targets.green then
			color = colors.green
		elseif msg[1] == targets.red then
			color = colors.red
		elseif msg[1] == targets.blue then
			color = colors.blue
		elseif msg[1] == targets.yellow then
			color = colors.yellow
		elseif msg[1] == targets.openall then
			switchAllDoors(true)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		elseif msg[1] == targets.closeall then
			switchAllDoors(false)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		elseif msg[1] == targets.lockall then
			lockAllDoors(true)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		elseif msg[1] == targets.unlockall then
			lockAllDoors(false)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		elseif msg[1] == targets.turnonall then
			switchAllLights(true)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		elseif msg[1] == targets.turnoffall then
			switchAllLights(false)
			modem.send(e[3], e[6], nil, serial.serialize({true}))
			return
		else
			modem.send(e[3], e[6], nil, serial.serialize({false, errors.badTarget}))
			return
		end
		if msg[3] == nil then
			if msg[2] == targets.lock then
				modem.send(e[3], e[6], nil, serial.serialize({true, s.lock or false}))
				return
			end
			modem.send(e[3], e[6], nil, serial.serialize({true, r.getBundledOutput(s.side, color) > 0}))
		elseif msg[3] then
			if msg[1] == targets.door then
				s.door = true
			elseif msg[1] == targets.light then
				s.light = true
			elseif msg[1] == targets.green then
				s.green = true
			elseif msg[1] == targets.red then
				s.red = true
			elseif msg[1] == targets.blue then
				s.blue = true
			elseif msg[1] == targets.yellow then
				s.yellow = true
			end
			r.setBundledOutput(s.side, color, 255)
			if msg[2] > (page - 1) * 7 and msg[2] < page * 7 then
				refreshSection(msg[2] - (page - 1) * 7)
			end
			modem.send(e[3], e[6], nil, serial.serialize({true}))
		else
			if msg[1] == targets.door then
				s.door = false
			elseif msg[1] == targets.light then
				s.light = false
			elseif msg[1] == targets.green then
				s.green = false
			elseif msg[1] == targets.red then
				s.red = false
			elseif msg[1] == targets.blue then
				s.blue = false
			elseif msg[1] == targets.yellow then
				s.yellow = false
			end
			r.setBundledOutput(s.side, color, 0)
			if msg[2] > (page - 1) * 7 and msg[2] < page * 7 then
				refreshSection(msg[2] - (page - 1) * 7)
			end
			modem.send(e[3], e[6], nil, serial.serialize({true}))
		end
	end
end

local tempRS = {}

local function redstoneListener(...)
	local e = {...}
	for k, v in pairs(tempRS) do
		if v == e[2]:sub(1, 5) .. tostring(e[3]) then
			table.remove(tempRS, k)
			return
		end
	end
	for k, v in ipairs(switch) do
		if e[2] == v.address and e[3] == v.side and not v.lock then
			local r = component.proxy(v.address)
			if r.getBundledInput(v.side, colors.pink) > 0 then
				v.door = not v.door
				r.setBundledOutput(v.side, colors.lightblue, v.door and 255 or 0)
				table.insert(tempRS, e[2]:sub(1, 5) .. tostring(e[3]))
				if k > (page - 1) * 7 and k < page * 7 then
					refreshSection(k - (page - 1) * 7)
				end
			end
			return
		end
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
modem.open(port)
event.listen("modem_message", modemListener)
event.listen("redstone_changed", redstoneListener)
main()
gpu.bind(screen2.address)
event.ignore("modem_message", modemListener)
event.ignore("redstone_changed", redstoneListener)
modem.close(port)
saveConfig()