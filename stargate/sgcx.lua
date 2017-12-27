-- ###############################################
-- #                  SGCX                       #
-- #                                             #
-- #   12.2014                   by: Aranthor    #
-- ###############################################


local version = "0.5.0"
local startArgs = {...}

if startArgs[1] == "version_check" then return version end

local computer = require("computer")
local component = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local term = require("term")
local gml = require("gml")
local serial = require("serialization")
local gpu = component.gpu
local res = {gpu.getResolution()}
if res[1] ~= 160 or res[2] ~= 50 then
	io.stderr:write("Program wymaga do dzialania karty graficznej i monitora 3 poziomu")
	return
end
if not component.isAvailable("modem") then
	io.stderr:write("Program wymaga do działania modemu")
	return
end
local modem = component.modem

local gui = nil
local darkStyle = nil
local element = {}
local data = {}
local sg = nil
local irisTimeout = 11
local sgChunk = {}

local tmp = {}
local dialDialog = false
local timerID = nil
local timerEneriga = nil
local irisTime = 0
local irisTimer = nil
local timeToClose = 0

-- Stałe do obliczania adresów
local SYMBOLS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
local NUM_SYMBOLS = SYMBOLS:len()
local MIN_COORD = -139967
local MAX_COORD = 139967
local MIN_DIM = -648
local MAX_DIM = 1295
local DIM_RANGE = 1296
local MC = 279937
local PC = 93563
local QC = 153742
local MD = 1297
local PD = 953
local QD = 788

local function saveConfig()
	local plik = io.open("/etc/sg.cfg", "w")
	plik:write(serial.serialize(data))
	plik:close()
end

local function loadConfig()
	if not fs.exists("/etc/sg.cfg") or startArgs[1] then
		if not startArgs[1] then
			io.stderr:write("Brak pliku konfiguracyjnego. Aby go utworzyć, napisz sgcx <adres_interfejsu_wrót>")
			return false
		end
		data.address = startArgs[1]
		sg = component.proxy(startArgs[1])
		if not sg then
			io.stderr:write("Podany adres jest nieprawidłowy!")
			return false
		end
	else
		local plik = io.open("/etc/sg.cfg", "r")
		data = serial.unserialize(plik:read()) or {}
		plik:close()
		sg = component.proxy(data.address or "")
		if not sg then
			GMLmessageBox("Adres interfejsu wrót jest nieprawidłowy",{"Zamknij"})
			return false
		end
	end
	data.list = data.list or {}
	data.port = data.port or math.random(10000, 50000)
	data.irisCode = data.irisCode or math.random(1000, 9999)
	if data.portStatus then modem.open(data.port) end
	return true
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
		t.renderTarget.setBackground(tmp.GMLbgcolor)
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

local function addTitle()
	local title = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gui.renderTarget,
		horizontal = isHorizontal,
		posX = 3,
		posY = 3,
		width = 28,
		height = 5
	}
	title.contains = GMLcontains
	title.isHidden = function() return false end
	title.draw = function(t)
		t.renderTarget.setBackground(0xff6600)
		t.renderTarget.fill(4, 3, 3, 1, ' ')--s
		t.renderTarget.fill(4, 5, 3, 1, ' ')
		t.renderTarget.fill(4, 7, 3, 1, ' ')
		t.renderTarget.set(3, 4, ' ')
		t.renderTarget.set(7, 6, ' ')
		t.renderTarget.fill(12, 3, 4, 1, ' ')--g
		t.renderTarget.fill(12, 7, 4, 1, ' ')
		t.renderTarget.fill(13, 5, 3, 1, ' ')
		t.renderTarget.set(11, 4, ' ')
		t.renderTarget.set(10, 5, ' ')
		t.renderTarget.set(11, 6, ' ')
		t.renderTarget.set(15, 6, ' ')
		t.renderTarget.fill(20, 3, 3, 1, ' ')--c
		t.renderTarget.fill(20, 7, 3, 1, ' ')
		t.renderTarget.set(19, 4, ' ')
		t.renderTarget.set(18, 5, ' ')
		t.renderTarget.set(19, 6, ' ')
		t.renderTarget.fill(25, 3, 2, 1, ' ')--x
		t.renderTarget.fill(26, 4, 2, 1, ' ')
		t.renderTarget.fill(27, 5, 3, 1, ' ')
		t.renderTarget.fill(26, 6, 2, 1, ' ')
		t.renderTarget.fill(25, 7, 2, 1, ' ')
		t.renderTarget.fill(29, 4, 2, 1, ' ')
		t.renderTarget.fill(30, 3, 2, 1, ' ')
		t.renderTarget.fill(29, 6, 2, 1, ' ')
		t.renderTarget.fill(30, 7, 2, 1, ' ')
	end
	gui:addComponent(title)
	return title
end

local function addStargate(cx, cy)
	local stargate = {
		visible = false,
		hidden = false,
		gui = gui,
		style = gui.style,
		focusable = false,
		type = "label",
		renderTarget = gpu,
		horizontal = isHorizontal,
		posX = 95,
		posY = 25,
		width = 40,
		height = 20,
		color = 0x333333,
		symbolIndex = 0
	}
	stargate.contains = GMLcontains
	stargate.isHidden = function() return false end
	stargate.draw = function(t)
		if not t.visible then
			local subdraw = function(x, y, vx, vy)
				for i = 0, 3 do
					t.renderTarget.set(x, y + 6 * vy + i * vy, ' ')
					t.renderTarget.set(x + 1 * vx, y + 6 * vy + i * vy, ' ')
				end
				t.renderTarget.set(x + 1 * vx, y + 5 * vy, ' ')
				t.renderTarget.set(x + 2 * vx, y + 5 * vy, ' ')
				t.renderTarget.set(x + 2 * vx, y + 4 * vy, ' ')
				t.renderTarget.set(x + 3 * vx, y + 4 * vy, ' ')
				t.renderTarget.set(x + 3 * vx, y + 3 * vy, ' ')
				t.renderTarget.set(x + 4 * vx, y + 3 * vy, ' ')
				t.renderTarget.set(x + 5 * vx, y + 3 * vy, ' ')
				t.renderTarget.set(x + 5 * vx, y + 2 * vy, ' ')
				t.renderTarget.set(x + 6 * vx, y + 2 * vy, ' ')
				t.renderTarget.set(x + 7 * vx, y + 2 * vy, ' ')
				for i = 0, 4 do
					t.renderTarget.set(x + 7 * vx + i * vx, y + 1 * vy, ' ')
				end
				for i = 0, 8 do
					t.renderTarget.set(x + 11 * vx + i * vx, y, ' ')
				end
			end
			t.renderTarget.setBackground(0x333333)
			subdraw(t.posX, t.posY, 1, 1)
			subdraw(t.posX + t.width - 1, t.posY, -1, 1)
			subdraw(t.posX, t.posY + t.height - 1, 1, -1)
			subdraw(t.posX + t.width - 1, t.posY + t.height - 1, -1, -1)
			t.visible = true
		end
		if sg.irisState() == "Closed" then
			t:fill(0xb4b4b4)
		elseif sg.stargateState() == "Connected" then
			t:fill(0x4086FF)
		else
			t:fill(tmp.GMLbgcolor)
		end
	end
	stargate.fill = function(t, hex)
		local subfill = function(sy, vy)
			t.renderTarget.fill(t.posX + 12, sy, 16, 1, ' ')
			t.renderTarget.fill(t.posX + 8, sy + 1 * vy, 24, 1, ' ')
			t.renderTarget.fill(t.posX + 6, sy + 2 * vy, 28, 1, ' ')
			t.renderTarget.fill(t.posX + 4, sy + 3 * vy, 32, 1, ' ')
			t.renderTarget.fill(t.posX + 3, sy + 4 * vy, 34, 1, ' ')
		end
		t.renderTarget.setBackground(hex)
		subfill(t.posY + 1, 1)
		t.renderTarget.fill(t.posX + 2, t.posY + 6, 36, 8, ' ')
		subfill(t.posY + t.height - 2, -1)
	end
	stargate.lockSymbol = function(t, number)
		if (number == 1 and t.symbolIndex == 0) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 2, t.posY + 15, 2, 1, ' ')
			t.renderTarget.fill(t.posX + 3, t.posY + 16, 2, 1, ' ')
			t.symbolIndex = 1
		end
		if (number == 2 and t.symbolIndex == 1) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX, t.posY + 8, 2, 2, ' ')
			t.symbolIndex = 2
		end
		if (number == 3 and t.symbolIndex == 2) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 5, t.posY + 2, 3, 1, ' ')
			t.renderTarget.fill(t.posX + 4, t.posY + 3, 2, 1, ' ')
			t.symbolIndex = 3
		end
		if (number == 4 and t.symbolIndex == 3) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 18, t.posY, 4, 1, ' ')
			t.symbolIndex = 4
		end
		if (number == 5 and t.symbolIndex == 4) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 32, t.posY + 2, 3, 1, ' ')
			t.renderTarget.fill(t.posX + 34, t.posY + 3, 2, 1, ' ')
			t.symbolIndex = 5
		end
		if (number == 6 and t.symbolIndex == 5) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 38, t.posY + 8, 2, 2, ' ')
			t.symbolIndex = 6
		end
		if (number == 7 and t.symbolIndex == 6) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 35, t.posY + 16, 2, 1, ' ')
			t.renderTarget.fill(t.posX + 36, t.posY + 15, 2, 1, ' ')
			t.symbolIndex = 7
		end
		if (number == 8 and t.symbolIndex == 7) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 24, t.posY + 19, 4, 1, ' ')
			t.symbolIndex = 8
		end
		if (number == 9 and t.symbolIndex == 8) or number == 0 then
			t.renderTarget.setBackground(number == 0 and t.color or 0xff6600)
			t.renderTarget.fill(t.posX + 12, t.posY + 19, 4, 1, ' ')
			t.symbolIndex = 9
		end
		if number == 0 then t.symbolIndex = 0 end
	end
	gui:addComponent(stargate)
	return stargate
end

local function updateCounter()
	if not tmp.counter or tmp.counter >= 5 then
		tmp.counter = 0
		saveConfig()
	else
		tmp.counter = tmp.counter + 1
	end
end

local function separateAddress(addr)
	return string.sub(addr, 1, 4) .. "-" .. string.sub(addr, 5, 7) .. "-" .. string.sub(addr, 8, 9)
end

local function translateState()
	state = sg.stargateState()
	if state == "Idle" then return "Bezczynny" end
	if state == "Dialling" then return "Wybieranie adresu" end
	if state == "Connecting" then return "Otwieranie tunelu" end
	if state == "Connected" then return "Tunel aktywny" end
	if state == "Offline" then return "Offline" end
	return state
end

local function translateIrisState()
	if sg.irisState() == "Open" then return "Otwarta" end
	if sg.irisState() == "Opening" then return "Otwieranie" end
	if sg.irisState() == "Closed" then return "Zamknięta" end
	if sg.irisState() == "Closing" then return "Zamykanie" end
	return "Offline"
end

local function translateResponse(res)
	if res == "Malformed stargate address" or res == "bad arguments #1 (string expected, got no value)" then return "Niepoprawny adres wrót!"
	elseif string.sub(res, 1, 23) == "No stargate at address " then return "Brak wrót o adresie " .. string.sub(res, 24) .. "!"
	elseif string.sub(res, 1, 28) == "Not enough chevrons to dial " then return "Wrota nie obslugują tunelów międzywymiarowych"
	elseif res == "Stargate has insufficient energy" then return "Za mało energi do nawiązania połączenia"
	else return "Nie można otworzyć tunelu (" .. res .. ")"
	end
end

local function round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function getEnergy()
	local percent = tostring(math.floor(100 * (sg.energyAvailable() * 80 / 4000000) + 0.5) - 1) .. "%"
	eu = string.reverse(tostring(round(sg.energyAvailable(), 0) * 80))
	eu2 = ""
	for i=1, string.len(eu) do
		if i % 3 == 0 and i ~= 0 then 
			eu2 = eu2 .. string.sub(eu, i, i) .. " "
		else
			eu2 = eu2 .. string.sub(eu, i, i)
		end
	end
	eu2 = string.reverse(eu2)
	return percent ..  "  /  " .. eu2 .. " RF"
end

local function energyRefresh()
	element.energy["text"] = "Energia: " .. getEnergy()
	element.energy:draw()
end

local function irisTimerFunction()
	if irisTime < 0 then
		sg.closeIris()
		event.cancel(irisTimer)
		irisTimer = nil
	else
		irisTime = irisTime - 1
	end
end

local function modifyList(action)
	if action == "add" then
		if element.name["text"] == "" or element.world["text"] == "" or element.address["text"] == "" then
			GMLmessageBox("Uzupełnij wszystkie pola", {"OK"})
		elseif element.name["text"]:len() > 20 or element.world["text"]:len() > 20 then
			GMLmessageBox("Długość nazwy i/lub świata nie mogą przekraczać 20 znaków", {"OK"})
		elseif not sg.energyToDial(element.address["text"]) then
			GMLmessageBox("Adres jest niepoprawny lub nie istnieje", {"OK"})
		else
			for _, v in pairs(data.list) do
				if v.name == element.name["text"] then
					GMLmessageBox("Adres o podanej nazwie jest już na liście", {"OK"})
					return
				elseif v.address == element.address then
					GMLmessageBox("Podany adres jest już na liście pod nazwą " .. v.name, {"OK"})
					return
				end
			end
			local l = {
				name = element.name["text"],
				world = element.world["text"],
				address = element.address["text"]:upper()
			}
			table.insert(data.list, l)
			local list = {}
			for _, v in pairs(data.list) do
				table.insert(list, v.name .. " (" .. v.world .. ")")
			end
			element.list:updateList(list)
			saveConfig()
			GMLmessageBox("Adres został dodany do listy", {"OK"})
		end
	elseif action == "modify" and element.list:getSelected() then
		if element.name["text"] == "" or element.world["text"] == "" or element.address["text"] == "" then
			GMLmessageBox("Uzupełnij wszystkie pola", {"OK"})
		elseif element.name["text"]:len() > 20 or element.world["text"]:len() > 20 then
			GMLmessageBox("Długość nazwy i/lub świata nie mogą przekraczać 20 znaków", {"OK"})
		elseif not sg.energyToDial(element.address["text"]) then
			GMLmessageBox("Adres jest niepoprawny lub nie istnieje", {"OK"})
		else
			if GMLmessageBox("Czy na pewno chcesz zmodyfikować wpis?", {"Tak", "Nie"}) == "Tak" then
				local selected = element.list:getSelected()
				for _, v in pairs(data.list) do
					if selected == v.name .. " (" .. v.world .. ")" then
						v.name = element.name["text"]
						v.world = element.world["text"]
						v.address = element.address["text"]:upper()
						local list = {}
						for _, v in pairs(data.list) do
							table.insert(list, v.name .. " (" .. v.world .. ")")
						end
						element.list:updateList(list)
						saveConfig()
						GMLmessageBox("Wpis został zmodyfikowany", {"OK"})
						break
					end
				end
			end
		end
	elseif action == "remove" and element.list:getSelected() then
		if GMLmessageBox("Czy na pewno chcesz usunąć zaznaczony element?", {"Tak", "Nie"}) == "Tak" then
			local selected = element.list:getSelected()
			for k, v in pairs(data.list) do
				if selected == v.name .. " (" .. v.world .. ")" then
					table.remove(data.list, k)
					local list = {}
					for _, v in pairs(data.list) do
						table.insert(list, v.name .. " (" .. v.world .. ")")
					end
					element.list:updateList(list)
					saveConfig()
					GMLmessageBox("Wpis został usunięty", {"OK"})
					break
				end
			end
		end
	end
end

local function dial()
	if sg.stargateState() == "Idle" then
		local status, response = sg.dial(element.address["text"])
		if status then
			element.connectionType["text"] = "Połączenie wychodzące"
			element.connectionType:show()
			local timeout = tonumber(element.time["text"])
			if timeout and timeout >= 10 and timeout <= 300 then
				timeToClose = timeout
			else
				timeToClose = 300
				element.time["text"] = ""
				element.time:draw()
			end
		else
			GMLmessageBox(translateResponse(response), {"OK"})
		end
	elseif sg.stargateState() == "Connected" or sg.stargateState() == "Dialling" then
		sg.disconnect()
		timeToClose = -1
		if timerID ~= nil then
			event.cancel(timerID)
		end
	elseif sg.stargateState() ~= "Offline" then
		GMLmessageBox("Wrota są zajęte", {"OK"})
	end
end

local function hash(i1, i2, i3)
	local r = (((i1 + 1) * i2) % i3) - 1
	return r
end

local function chunkInRange(c)
	return c >= MIN_COORD and c <= MAX_COORD
end

local function getSymbols(i1, i2)
	local ret = ""
	while i2 > 0 do
		i2 = i2 - 1
		i = (i1 % NUM_SYMBOLS) + 1
		ret = ret .. SYMBOLS:sub(i, i)
		i1 = math.floor(i1 / NUM_SYMBOLS)
	end
	
	return ret:reverse()
end

local function getSymbolsValue(s)
	l = 0
	for x = 1, s:len() do
		local index = 0
		for i = 1, NUM_SYMBOLS do
			if SYMBOLS:sub(i, i) == s:sub(x, x) then
				index = i - 1
				break
			end
		end
		l = (l * NUM_SYMBOLS) + index
	end
	
	return l
end

local function interleave(i1, i2)
	l1 = 1
	l2 = 0
	while i1 > 0 or i2 > 0 do
		l2 = l2 + (l1 * (i1 % 6))
		i1 = math.floor(i1 / 6)
		l1 = l1 * 6
		l2 = l2 + (l1 * (i2 % 6))
		i2 = math.floor(i2 / 6)
		l1 = l1 * 6
	end
	
	return l2
end

local function fromBaseSix(s)
	local ret = 0
	for i = 1, s:len() do
		local f = tonumber(s:sub(i, i))
		ret = ret + f * math.pow(6, i - 1)
	end
	
	return ret
end

local function uninterleave(i)
	local i1 = ''
	local i2 = ''
	while i > 0 do
		i1 = i1 .. tostring(i % 6)
		i = math.floor(i / 6)
		i2 = i2 .. tostring(i % 6)
		i = math.floor(i / 6)
	end
	
	i1 = fromBaseSix(i1)
	i2 = fromBaseSix(i2)
	return {i1, i2}
end

local function chunkToAddress(cx, cz)
	if not chunkInRange(cx) then
		GMLmessageBox("Współrzędna X jest poza zasięgem adresacji", {"OK"})
		return
	elseif not chunkInRange(cz) then
		GMLmessageBox("Współrzędna Z jest poza zasięgem adresacji", {"OK"})
		return
	end
	
	local l = interleave(hash(cx - MIN_COORD, PC, MC), hash(cz - MIN_COORD, PC, MC))
	return getSymbols(l, 7)
end

local function addressToChunk(address)
	local l = getSymbolsValue(address:sub(1, 7))
	if not l then return end
	local a = uninterleave(l)
	local i = MIN_COORD + hash(a[1], QC, MC)
	local j = MIN_COORD + hash(a[2], QC, MC)
	return {i, j}
end

local function computeDistance(addressTarget, chunkTarget)
	if not chunkTarget then
		chunkTarget = addressToChunk(addressTarget)
		if not chunkTarget then return end
	end
	
	local dx = math.abs(sgChunk[1] - chunkTarget[1])
	local dz = math.abs(sgChunk[2] - chunkTarget[2])
	local dist = math.sqrt(dx * dx + dz * dz)
	dist = math.floor(dist * 160) / 10
	return dist
end

local function clearAddress(addr)
	if not addr or addr:len() < 7 then return nil end
	local clear = ""
	for i = 1, 7 do
		local c = string.byte(addr:sub(i, i))
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57) then
			clear = clear .. addr:sub(i, i)
		elseif c >= 97 and c <= 122 then
			clear = clear .. string.char(c - 32)
		else
			return nil
		end
	end
	return clear
end

local function coordsCalculator()
	local cgui = gml.create("center", "center", 60, 21)
	cgui.style = darkStyle
	cgui:addButton(42, 18, 12, 1, "Zamknij", function() cgui:close() end)
	cgui:addLabel(3, 2, 4, "X:")
	cgui:addLabel(3, 5, 4, "Z:")
	cgui:addLabel(3, 8, 10, "Chunk X:")
	cgui:addLabel(3, 11, 10, "Chunk Z:")
	local posX = cgui:addTextField(3, 3, 14)
	local posZ = cgui:addTextField(3, 6, 14)
	local posCX = cgui:addTextField(3, 9, 14)
	local posCZ = cgui:addTextField(3, 12, 14)
	cgui:addLabel(38, 5, 8, "Adres:")
	local address = cgui:addTextField(38, 6, 17)
	cgui:addButton(38, 8, 17, 1, "Kopiuj z listy", function()
		address.text = element.address.text
		address:draw()
	end)
	cgui:addLabel(38, 10, 13, "Odległość:")
	local distance = cgui:addLabel(38, 11, 17, "0")
	cgui:addLabel(3, 15, 56, "* Symbole światów nie są generowane deterministycznie")
	local function updateDistance(cx, cz)
		local dist = computeDistance(nil, {cx, cz})
		distance.text = tostring(dist)
		distance:draw()
	end
	local function updateAddress(cx, cz)
		local addr = chunkToAddress(cx, cz)
		if addr then
			address.text = addr
			address:draw()
		end
		updateDistance(cx, cz)
	end
	cgui:addButton(22, 5, 11, 2, "--->", function()
		if posX.text:len() > 0 and posZ.text:len() > 0 then
			local npx = tonumber(posX.text)
			local npz = tonumber(posZ.text)
			if not npx then
				GMLmessageBox("Współrzędna X musi być liczbą", {"OK"})
			elseif not npz then
				GMLmessageBox("Współrzędne Z musi być liczbą", {"OK"})
			else
				updateAddress(math.floor(npx / 16), math.floor(npz / 16))
			end
		elseif posCX.text:len() > 0 and posCZ.text:len() > 0 then
			local ncx = tonumber(posCX.text)
			local ncz = tonumber(posCZ.text)
			if not ncx then
				GMLmessageBox("Współrzędna chunka X musi być liczbą", {"OK"})
			elseif not ncz then
				GMLmessageBox("Współrzędna chunka Z musi być liczbą", {"OK"})
			else
				updateAddress(ncx, ncz)
			end
		else
			GMLmessageBox("Uzupełnij współrzędne bloku lub chunka", {"OK"})
		end
	end)
	cgui:addButton(22, 10, 11, 2, "<---", function()
		if address.text:len() >= 7 then
			local cleared = clearAddress(address.text)
			if not cleared then
				GMLmessageBox("Adres zawiera niedozwolone znaki", {"OK"})
			else
				local chunk = addressToChunk(cleared)
				posCX.text = tostring(chunk[1])
				posCX:draw()
				posCZ.text = tostring(chunk[2])
				posCZ:draw()
				posX.text = tostring(chunk[1] * 16)
				posX:draw()
				posZ.text = tostring(chunk[2] * 16)
				posZ:draw()
				updateDistance(chunk[1], chunk[2])
			end
		else
			GMLmessageBox("Pole adresu musi zawierać 7 znaków", {"OK"})
		end
	end)
	cgui:run()
end

local function createUI()
	gui = gml.create(0, 0, res[1], res[2])
	gui.style = darkStyle
	addTitle()
	gui:addLabel(35, 2, 10, version)["text-color"] = 0x666666
	addBar(53, 1, 15, false)
	element.stargate = addStargate()
	gui:addButton("right", 1, 10, 1, "Wyjście", function() gui:close() end)
	gui:addLabel(56, 4, 20, "Adres: " .. separateAddress(sg.localAddress()))
	element.status = gui:addLabel(56, 5, 25, "Status: " .. translateState())
	element.iris = gui:addLabel(56, 6, 25, "Przesłona: " .. translateIrisState())
	element.energy = gui:addLabel(56, 7, 35, "Energia: " .. getEnergy())
	element.distance = gui:addLabel(56, 8, 35, "Odległość: ")
	element.connectionType = gui:addLabel(56, 11, 30, "")
	element.connectionType:hide()
	element.remoteAddress = gui:addLabel(56, 12, 30, "")
	element.remoteAddress:hide()
	element.timeout = gui:addLabel(56, 13, 30, "")
	element.timeout:hide()
	gui:addLabel(3, 20, 16, "Lista adresów:")
	local list = {}
	for a, v in pairs(data.list) do
		table.insert(list, tostring(a) .. ". " .. v.name .. " (" .. v.world .. ")")
	end
	element.list = gui:addListBox(3, 21, 40, 24, list)
	element.list.onChange = function(listBox)
		local sel = listBox:getSelected()
		if not sel then return end
		local index = tonumber(sel:match("^(%d+)%.%s"))
		if not index or not data.list[index] then return end
		element.name["text"] = data.list[index].name
		element.name:draw()
		element.world["text"] = data.list[index].world
		element.world:draw()
		element.address["text"] = data.list[index].address
		element.address:draw()
		local clear = clearAddress(element.address.text)
		if clear then
			element.distance.text = "Odległość: " .. tostring(computeDistance(clear))
			element.distance:draw()
		end
	end
	gui:addButton(4, 46, 10, 2, "Dodaj", function() modifyList("add") end)
	gui:addButton(15, 46, 10, 2, "Usuń", function() modifyList("remove") end)
	gui:addButton(27, 46, 15, 2, "Modyfikuj", function() modifyList("modify") end)
	gui:addLabel(45, 22, 7, "Nazwa:")["text-color"] = 0x999999
	gui:addLabel(45, 25, 9, "Świat:")["text-color"] = 0x999999
	gui:addLabel(45, 29, 9, "Adres:")["text-color"] = 0x999999
	gui:addLabel(45, 32, 27, "Czas połączenia [10-300]:")["text-color"] = 0x999999
	element.name = gui:addTextField(45, 23, 25)
	element.world = gui:addTextField(45, 26, 25)
	element.address = gui:addTextField(45, 30, 25)
	element.time = gui:addTextField(45, 33, 10)
	element.dial = gui:addButton(45, 36, 25, 3, "Otwórz tunel", dial)
	element.irisButton = gui:addButton(45, 40, 25, 3, "", function()
		if sg.irisState() == "Open" then
			sg.closeIris()
		elseif sg.irisState() == "Closed" then
			sg.openIris()
		end
	end)
	element.irisButton["text"] = sg.irisState() == "Closed" and "Otwórz przesłonę" or (sg.irisState() == "Open" and "Zamknij przesłonę" or "Przełącz przesłonę")
	element.autoIris = gui:addLabel(45, 44, 7, "Tryb:")
	gui:addButton(52, 44, 18, 1, data.autoIris and "automatyczny" or "ręczny", function(self)
		data.autoIris = not data.autoIris
		self["text"] = data.autoIris and "automatyczny" or "ręczny"
		self:draw()
		updateCounter()
	end)
	gui:addLabel(110, 5, 7, "Port:")
	gui:addButton(118, 5, 15, 1, data.portStatus and "Otwarty" or "Zamknięty", function(self)
		if data.portStatus then
			modem.close(data.port)
			self["text"] = "Zamknięty"
			self["text-color"] = 0xff0000
		else
			modem.open(data.port)
			self["text"] = "Otwarty"
			self["text-color"] = 0x00ff00
		end
		data.portStatus = not data.portStatus
		self:draw()
		updateCounter()
	end)["text-color"] = data.portStatus and 0x00ff00 or 0xff0000
	gui:addLabel(110, 6, 8, "Kanał:")
	gui:addButton(118, 6, 15, 1, tostring(data.port), function(self)
		local isOpen = modem.isOpen(data.port)
		if isOpen then modem.close(data.port) end
		data.port = math.random(10000, 50000)
		self["text"] = tostring(data.port)
		self:draw()
		if isOpen then modem.open(data.port) end
		updateCounter()
	end)
	gui:addLabel(110, 7, 6, "Kod:")
	gui:addButton(118, 7, 15, 1, tostring(data.irisCode), function(self)
		data.irisCode = math.random(1000, 9999)
		self["text"] = tostring(data.irisCode)
		self:draw()
	end)
	gui:addButton(110, 9, 23, 1, "Kalkulator adresów", function() coordsCalculator() end)
	tmp.GMLbgcolor = GMLextractProperty(gui, GMLgetAppliedStyles(gui), "fill-color-bg")
	gui:run()
end

local function main()
	local address = sg.localAddress():sub(1, 7)
	sgChunk = addressToChunk(address)
	
	require("term").setCursorBlink(false)
	darkStyle = gml.loadStyle("dark")
	createUI()
end

local function countdown()
	if timeToClose < 0 then
		sg.disconnect()
		event.cancel(timerID)
	else
		minuty = tostring(math.floor(timeToClose / 60))
		sekundy = tostring(60 * ((timeToClose / 60) - math.floor(timeToClose / 60)))
		if string.len(sekundy) == 1 then sekundy = "0" .. sekundy end
		element.timeout["text"] = "Pozostały czas: " .. minuty .. ":" .. sekundy
		element.timeout:draw()
		timeToClose = timeToClose - 1
	end
end

local function __eventListener(...)
	local ev = {...}
	if ev[1] == "sgDialIn" then
		if data.autoIris then
			event.timer(5, function()
				sg.closeIris()
			end)
		end
		timeToClose = 300
		element.connectionType["text"] = "Połączenie przychodzące"
		element.connectionType:show()
		element.remoteAddress["text"] = "Zewnętrzny adres: " .. separateAddress(sg.remoteAddress())
		element.remoteAddress:show()
	elseif ev[1] == "sgIrisStateChange" then
		element.iris["text"] = "Przesłona: " .. translateIrisState()
		element.iris:draw()
		if ev[3] == "Closed" then
			element.irisButton["text"] = "Otwórz przesłonę"
			element.irisButton:draw()
		elseif ev[3] == "Open" then
			element.irisButton["text"] = "Zamknij przesłonę"
			element.irisButton:draw()
		end
		if ev[3] == "Open" or ev[3] == "Closed" then element.stargate:draw() end
	elseif ev[1] == "sgStargateStateChange" then
		element.status["text"] = "Status: " .. translateState()
		element.status:draw()
		if ev[3] == "Idle" then
			if data.autoIris then
				event.timer(2, function()
					sg.openIris()
				end)
			end
			element.connectionType:hide()
			element.remoteAddress:hide()
			element.timeout:hide()
			element.dial["text"] = "Otwórz tunel"
			element.dial:draw()
			if timerID then
				event.cancel(timerID)
			end
			timeToClose = 0
			element.stargate:draw()
			element.stargate:lockSymbol(0)
		elseif ev[3] == "Connected" then
			element.remoteAddress["text"] = "Zewnętrzny adres: " .. separateAddress(sg.remoteAddress())
			element.remoteAddress:show()
			element.timeout["text"] = "Pozostały czas: "
			element.timeout:show()
			element.dial["text"] = "Zamknij tunel"
			element.dial:draw()
			timerID = event.timer(1, countdown, 301)
			element.stargate:draw()
		end
	elseif ev[1] == "sgChevronEngaged" then
		element.stargate:lockSymbol(ev[3])
	elseif ev[1] == "modem_message" then
		if ev[4] == data.port then
			if ev[7] == data.irisCode then
				os.sleep(0.1)
				modem.send(ev[3], ev[6], serial.serialize({true, "Przesłona otwarta", irisTimeout}))
				if sg.irisState() == "Closed" then
					sg.openIris()
					irisTime = irisTimeout
					irisTimer = event.timer(1, irisTimerFunction, irisTimeout + 5)
				end
			else
				os.sleep(0.1)
				modem.send(ev[3], ev[6], serial.serialize({false, "Błędny kod przesłony!", irisTimeout}))
			end
		end
	end
end

local function eventListener(...)
	local args = {...}
	local status, msg = pcall(__eventListener, table.unpack(args))
	if not status then
		GMLmessageBox("Blad: " .. msg)
	end
end


if not loadConfig() then return end
event.listen("sgDialIn", eventListener)
event.listen("sgIrisStateChange", eventListener)
event.listen("sgStargateStateChange", eventListener)
event.listen("sgChevronEngaged", eventListener)
event.listen("modem_message", eventListener)
timerEneriga = event.timer(5, energyRefresh, math.huge)
main()
event.cancel(timerEneriga)
event.ignore("sgDialIn", eventListener)
event.ignore("sgIrisStateChange", eventListener)
event.ignore("sgStargateStateChange", eventListener)
event.ignore("sgChevronEngaged", eventListener)
event.ignore("modem_message", eventListener)
saveConfig()
