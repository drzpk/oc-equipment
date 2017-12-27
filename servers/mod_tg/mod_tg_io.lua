-- ############################################
-- #				mod_tg_io				  #
-- #										  #
-- #  05.2016					by:IlynPayne  #
-- ############################################

--[[
	## Opis programu ##
		Program mod_tg_io jest modułem używanym na serwerze the_guard (od wersji 2.0).
		Pozwala na zarządzanie komponentami wejścia/wyjścia.
		
		Moduł pozwala na zdefiniowanie 3 typów urządzeń:
		* odbiorników (id: 1-50) - wysyłają sygnały
		* grup (id: 101-116)- pozwalają na masowe zarządzanie stanem odbiorników (limit: 10)
		* czujników (id: 61-80) - odbierają sygnały z otoczenia
		
		Każdy odbiornik i czujnik może działać w dwóch trybach: prostym i rozszerzonym.
		Pierwszy z nich jest używany dla zwykłych obwodów z czerownego kamienia.
		Z kolei drugi pozwala dodatkowo zdefiniować kolor i większą moc sygnału (do 255)
		
	## Akcje ##
		- setOutput(id:number,strength:numer) - ustawia sygnał wyjściowy
		- getInput(id:number) - pobiera aktualną wartość czujnika
		
	## Funkcje ##
		* sterowanie wyjściem z urządzeń I/O
		* tworzenie pojedynczych odbiorników i grup
		* tworzenie czujników
		* maksymalnie 48 odbiorników, 16 grup i 20 czujników
		* każdy czujnik może wywoływać do 3 akcji włączania i 3 akcji wyłączania
		* możliwość ręcznego sterowania
		
	## Schematy ##
		config { - domyślny plik konfiguracyjny
			mode:number - tryb GUI (1 - odbiorniki, 2 - grupy, 3 - czujniki)
			receivers { - odbiorniki
				[id:number] = { - identyfikator
					name:string - nazwa
					address:string - adres
					side:number - strona
					color:number or nil - kolor (jeśli nil, odbiornik działa w trybie prostym)
				}
				...
			}
			groups { - grupy
				[id:number] = { - identyfikator
					name:string - nazwa
					members = { - lista odbiorników
						id:number
						...
					}
				}
			}
			sensors { - czujniki
				[id:number] = { - identyfikator
					name:string - nazwa
					address:string - adres
					side:number - strona
					color:number or nil - kolor (jeśli nil, czujnik działa w trybie prostym)
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
			}
		}
]]

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local sides = require("sides")
local colors = require("colors")
local gml = require("gml")

local mod = {}
local server = nil
local config = nil

local box = nil
local elements = {}
local buttons = {}

local directions = {
	[0] = "dół",
	[1] = "góra",
	[2] = "północ",
	[3] = "południe",
	[4] = "zachód",
	[5] = "wschód"
}


local function freeId(tab, minn, maxx)
	for i = minn, maxx do
		if not tab[i] then
			return i
		end
	end
	return nil
end

local function count(tab)
	local i = 0
	for _, t in pairs(tab) do i = i + 1 end
	return i
end

local function refreshSelection()
	local sel = tonumber(string.match(box:getSelected() or "", "^(%d+)%."))
	if sel then
		elements[1].text = "ID: " .. tostring(sel)
		if elements[1].hidden then
			elements[1]:show()
		else
			elements[1]:draw()
		end
		local isSensor = false
		local color = false
		local side = 0
		local address = nil
		local extended
		local name = ""
		local mode = ""
		if config.mode == 1 and config.receivers[sel] then
			side = config.receivers[sel].side
			color = config.receivers[sel].color
			name = config.receivers[sel].name
			mode = config.receivers[sel].color and "rozszerzony" or "prosty"
			elements[5].text = "Strona: " .. directions[config.receivers[sel].side]
			if elements[5].hidden then
				elements[5]:show()
			else
				elements[5]:draw()
			end
			if config.receivers[sel].color then
				elements[6].text = "Kolor: " .. colors[config.receivers[sel].color]
				if elements[6].hidden then
					elements[6]:show()
				else
					elements[6]:draw()
				end
			else
				elements[6]:hide()
			end
			address = config.receivers[sel].address
			buttons[1]:show()
			buttons[2]:hide()
		elseif config.mode == 2 and config.groups[sel] then
			name = config.groups[sel].name
			mode = "grupa"
			elements[5]:hide()
			elements[6]:hide()
			pcall(function()
				address = config.receivers[config.groups[sel].members[1]].address
				side = config.receivers[config.groups[sel].members[1]].side
				color = config.receivers[config.groups[sel].members[1]].color
			end)
			for i = 1, 2 do buttons[i]:hide() end
		elseif config.mode == 3 and config.sensors[sel] then
			isSensor = true
			color = config.sensors[sel].color
			name = config.sensors[sel].name
			side = config.sensors[sel].side
			mode = config.sensors[sel].color and "rozszerzony" or "prosty"
			elements[5].text = "Strona: " .. directions[config.sensors[sel].side]
			if elements[5].hidden then
				elements[5]:show()
			else
				elements[5]:draw()
			end
			if config.sensors[sel].color then
				elements[6].text = "Kolor: " .. colors[config.receivers[sel].color]
				if elements[6].hidden then
					elements[6]:show()
				else
					elements[6]:draw()
				end
			else
				elements[6]:hide()
			end
			address = config.sensors[sel].address
			buttons[1]:hide()
			buttons[2]:show()
		else
			name = "<BŁĄD>"
			elements[3].text = "<BŁĄD>"
			for i = 1, 2 do buttons[i]:hide() end
		end
		elements[2].text = "Nazwa: " .. name
		elements[3].text = "Tryb: " .. mode
		if elements[2].hidden then
			elements[2]:show()
		else
			elements[2]:draw()
		end
		if elements[3].hidden then
			elements[3]:show()
		else
			elements[3]:draw()
		end
		
		local proxy = component.proxy(address)
		if proxy then
			local level = nil
			if isSensor then
				if color then
					level = proxy.getBundledInput(side, color)
				else
					level = proxy.getInput(side)
				end
			else
				if color then
					level = proxy.getBundledOutput(side, color)
				else
					level = proxy.getOutput(side)
				end
			end
			elements[4].text = (isSensor and "Wejście: " or "Wyjście: ") .. tostring(level)
		else
			elements[4].text = isSensor and "Wejście: -1" or "Wyjście: -1"
		end
		if elements[4].hidden then
			elements[4]:show()
		else
			elements[4]:draw()
		end
	else
		for i = 1, 6 do elements[i]:hide() end
		for i = 1, 2 do buttons[i]:hide() end
	end
end

local function refreshList()
	local tab = nil
	local list = {}
	if config.mode == 1 then tab = config.receivers
	elseif config.mode == 2 then tab = config.groups
	else tab = config.sensors end
	for i, t in pairs(tab) do
		table.insert(list, tostring(i) .. ". " .. t.name)
	end
	box:updateList(list)
	refreshSelection()
end

local function additionTemplate(edit, receiver, filling, id)
	local ret = {}
	if not receiver then
		ret.enable = {}
		ret.disable = {}
	end
	if not ret.side then ret.side = 2 end
	local prev_color = 0
	if filling then
		for a, b in pairs(filling) do ret[a] = b end
		if not receiver then
			for i = 1, 3 do
				if filling.enable[i] then
					ret.enable[i] = {}
					ret.enable[i].id = filling.enable[i].id
					ret.enable[i].p1 = filling.enable[i].p1
					ret.enable[i].p2 = filling.enable[i].p2
				end
			end
			for i = 1, 3 do
				if filling.disable[i] then
					ret.disable[i] = {}
					ret.disable[i].id = filling.disable[i].id
					ret.disable[i].p1 = filling.disable[i].p1
					ret.disable[i].p2 = filling.disable[i].p2
				end
			end
		end
	end

	local tgui = gml.create("center", "center", 65, 20)
	tgui.style = server.getStyle(mod)
	local text = ""
	if edit then
		text = receiver and "Edycja odbiornika" or "Edycja czujnika"
	else
		text = receiver and "Nowy odbiornik" or "Nowy czujnik"
	end
	tgui:addLabel("center", 1, text:len() + 1, text)
	tgui:addLabel(3, 9, 6, "Tryb:")
	tgui:addLabel(3, 4, 4, "ID:")
	tgui:addLabel(3, 5, 7, "Adres:")
	tgui:addLabel(3, 7, 7, "Nazwa:")
	tgui:addLabel(3, 11, 8, "Strona:")
	
	local lid = tgui:addLabel(12, 4, 6, "")
	if edit and id then
		lid.text = tostring(id)
	else
		if receiver then
			lid.text = tostring(freeId(config.receivers, 1, 50)) or "BŁĄD"
		else
			lid.text = tostring(count(config.sensors) + 61)
			lid.text = tostring(freeId(config.sensors, 61, 80)) or "BŁĄD"
		end
	end
	local tmp = tgui:addLabel(12, 5, 38, "")
	tmp.text = ret.address or ""
	tmp.onDoubleClick = function(t)
		local r = server.componentDialog(mod, "redstone")
		if r then
			local found = false
			for _, t in pairs(receiver and config.receivers or config.sensors) do
				if t.address == r then
					found = true
					break
				end
			end
			if not found then
				ret.address = r
				t.text = r
				t:draw()
			else
				server.messageBox(mod, "Komponent o takim adresie został już dodany.", {"OK"})
			end
		end
	end
	local name = tgui:addTextField(12, 7, 20)
	name.text = ret.name or ""
	tgui:addButton(12, 11, 12, 1, directions[ret.side], function(t)
		if ret.side < 5 then ret.side = ret.side + 1
		else ret.side = 0 end
		t.text = directions[ret.side]
		t:draw()
	end)
	local lColor = tgui:addLabel(3, 13, 7, "Kolor:")
	lColor.hidden = not ret.color
	local color = tgui:addLabel(12, 13, 12, "")
	color.hidden = not ret.color
	color.text = ret.color and colors[ret.color] or ""
	color.onClick = function(t)
		if ret.color then
			local rr = server.colorDialog(mod, false, true)
			if rr then
				ret.color = rr[1]
				t.text = colors[rr[1]]
				t:draw()
			end
		end
	end
	
	tgui:addButton(12, 9, 14, 1, ret.color and "rozszerzony" or "prosty", function(t)
		if ret.color then
			prev_color = ret.color
			ret.color = nil
			t.text = "prosty"
			lColor:hide()
			color:hide()
		else
			ret.color = prev_color 
			t.text = "rozszerzony"
			color.text = colors[ret.color]
			lColor:show()
			color:show()
		end
		t:draw()
	end)
	tgui:addButton(45, 17, 14, 1, "Anuluj", function()
		ret = filling
		tgui:close()
	end)
	tgui:addButton(29, 17, 14, 1, "Zatwierdź", function()
		if not ret.address then
			server.messageBox(mod, "Wybierz adres urządzenia.", {"OK"})
		elseif name.text:len() < 1 or name.text:len() > 20 then
			server.messageBox(mod, "Nazwa urządzenia musi mieć od 1 do 20 znaków", {"OK"})
		else
			ret.name = name.text
			tgui:close()
		end
	end)
	tgui:run()
	return ret
end

local function addReceiver()
	if #config.receivers < 48 then
		local ret = additionTemplate(false, true)
		if ret then
			table.insert(config.receivers, ret)
			refreshList()
		end
	else
		server.messageBox(mod, "Dodano już maksymalną liczbę odbiorników.", {"OK"})
	end
end

local function addSensor()
	if #config.sensors < 20 then
		local ret = additionTemplate(false, false)
		if ret then
			local id = freeId(config.sensors, 61, 80)
			if id then
				config.sensors[id] = ret
				refreshList()
			end
		end
	else
		server.messageBox(mod, "Dodano już maksymalną liczbę czujników.", {"OK"})
	end
end

local function addItem(busyIds)
	local ret = nil
	local list = {}
	local function isAvail(id)
		local avail = true
		for _, i in pairs(busyIds) do
			if i == id then
				avail = false
				break
			end
		end
		return avail
	end
	for i, t in pairs(config.receivers) do
		if isAvail(i) then
			table.insert(list, tostring(i) .. ". " .. t.name)
		end
	end
	
	local agui = gml.create("center", "center", 36, 16)
	agui.style = server.getStyle(mod)
	
	agui:addLabel("center", 1, 19, "Wybierz odbiornik")
	local l = agui:addListBox(3, 3, 30, 10, list)
	
	agui:addButton(3, 14, 14, 1, "Zatwierdź", function()
		local sel = tonumber(string.match(l:getSelected() or "", "^(%d+)%."))
		if sel then
			ret = sel
			agui:close()
		end
	end)
	agui:addButton(19, 14, 14, 1, "Anuluj", function() agui:close() end)
	
	agui:run()
	return ret
end

local function groupTemplate(fill, id)
	local ret = nil
	local ll = nil
	local items = {}
	local subs = {}
	local function refreshDetails()
		local sel = tonumber(string.match(ll:getSelected() or "", "^(%d+)%."))
		if sel and config.receivers[sel] then
			subs[1]:show()
			subs[2].text = "Strona: " .. directions[config.receivers[sel].side]
			if subs[2].hidden then
				subs[2]:show()
			else
				subs[2]:draw()
			end
			if config.receivers[sel].color then
				subs[3].text = "Kolor: " .. colors[config.receivers[sel].color]
				if subs[3].hidden then
					subs[3]:show()
				else
					subs[3]:draw()
				end
			else
				subs[3]:hide()
			end
		else
			for i = 1, 3 do subs[i]:hide() end
		end
	end
	local function refresh()
		local l = {}
		for _, i in pairs(items) do
			if config.receivers[i] then
				table.insert(l, tostring(i) .. ". " .. config.receivers[i].name)
			else
				table.insert(l, tostring(i) .. ". <BRAK>")
			end
		end
		ll:updateList(l)
		refreshDetails()
	end
	
	local ggui = gml.create("center", "center", 65, 20)
	ggui.style = server.getStyle(mod)
	
	ggui:addLabel("center", 1, fill and 13 or 11, fill and "Edycja grupy" or "Nowa grupa")
	ggui:addLabel(36, 4, 9, "ID: " .. tostring(id or #config.groups + 101))
	ggui:addLabel(36, 6, 7, "Nazwa:")
	local field = ggui:addTextField(38, 7, 20)
	field.text = fill and fill.name or ""
	if fill and fill.members then
		for a, b in pairs(fill.members) do
			items[a] = b
		end
	end
	
	subs[1] = ggui:addLabel(36, 10, 14, "Szczegóły:")
	subs[2] = ggui:addLabel(38, 11, 20, "")
	subs[3] = ggui:addLabel(38, 12, 20, "")
	
	ggui:addButton(3, 15, 14, 1, "Dodaj", function()
		if #items < 10 then
			local ret = addItem(items)
			if ret then
				table.insert(items, ret)
				refresh()
			end
		else
			server.messageBox(mod, "Dodano już maksymalną ilość urządzeń do grupy.", {"OK"})
		end
	end)
	ggui:addButton(19, 15, 14, 1, "Usuń", function()
		local sel = tonumber(string.match(ll:getSelected() or "", "^(%d+)%."))
		if sel and #items > 0 then
			if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony element?" , {"Tak", "Nie"}) == "Tak" then
				for i, i2 in pairs(items) do
					if i2 == sel then
						table.remove(items, i)
						refresh()
						return
					end
				end
			end
		end
	end)
	
	ggui:addButton(47, 18, 14, 1, "Anuluj", function()
		ret = nil
		ggui:close()
	end)
	ggui:addButton(31, 18, 14, 1, "Zatwierdź", function()
		if field.text:len() < 1 or field.text:len() > 20 then
			server.messageBox(mod, "Nazwa grupy musi mieć od 1 do 20 znaków.", {"OK"})
		elseif #items < 2 then
			server.messageBox(mod, "Grupa musi mieć co najmniej 2 urządzenia.", {"OK"})
		else
			ret = {}
			ret.name = field.text
			ret.members = items
			ggui:close()
		end
	end)
	
	ll = ggui:addListBox(3, 4, 30, 10, {})
	local fn = ll.onClick
	ll.onClick = function(...)
		fn(...)
		refreshDetails()
	end
	refresh()
	
	ggui:run()
	return ret
end

local function addGroup()
	if #config.groups < 16 then
		local ret = groupTemplate()
		if ret then
			local id = freeId(config.groups, 101, 116)
			if id then
				config.groups[id] = ret
				refreshList()
			end
		end
	else
		server.messageBox(mod, "Dodano już maksymalną ilość grup.", {"OK"})
	end
end

local function modifyEntry(t)
	local sel = tonumber(string.match(box:getSelected() or "", "^(%d+)%."))
	if not sel then return end
	if config.mode == 1 and config.receivers[sel] then
		local ret = additionTemplate(true, true, config.receivers[sel], sel)
		if ret then
			config.receivers[sel] = ret
			refreshList()
		end
	elseif config.mode == 2 and config.groups[sel] then
		local ret = groupTemplate(config.groups[sel], sel)
		if ret then
			config.groups[sel] = ret
			refreshList()
		end
	elseif config.mode == 3 and config.sensors[sel] then
		local ret = additionTemplate(true, false, config.sensors[sel], sel)
		if ret then
			config.sensors[sel] = ret
			refreshList()
		end
	end
end

local function removeEntry()
	local sel = box:getSelected()
	if not sel then return end
	local id = tonumber(sel:match("^(%d+)%."))
	if not id then return end
	if config.mode == 1 then
		if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony odbiornik?", {"Tak", "Nie"}) == "Tak" then
			config.receivers[id] = nil
			refreshList()
		end
	elseif config.mode == 2 then
		if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczoną grupę?", {"Tak", "Nie"}) == "Tak" then
			config.groups[id] = nil
			refreshList()
		end
	elseif config.mode == 3 then
		if server.messageBox(mod, "Czy na pewno chcesz usunąć zaznaczony czujnik?", {"Tak", "Nie"}) == "Tak" then
			config.sensors[id] = nil
			refreshList()
		end
	end
end

local function setOutput()
	local tab = nil
	local sel = tonumber(string.match(box:getSelected() or "", "^(%d+)%."))
	if not sel then return end
	if config.mode == 1 and config.receivers[sel] then
		tab = config.receivers[sel]
	elseif config.mode == 2 and config.groups[sel] then
		tab = config.groups[sel]
	else
		return
	end
	
	local function setValue(t, value)
		local proxy = component.proxy(t.address or "")
		if proxy and proxy.type == "redstone" then
			if t.color then
				proxy.setBundledOutput(t.side, t.color, value)
			else
				proxy.setOutput(t.side, value)
			end
		end
	end
	
	local sgui = gml.create("center", "center", 40, 7)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 15, "Ustaw wyjście")
	sgui:addLabel(3, 3, 10, "Wyjście:")
	local field = sgui:addTextField(14, 3, 10)
	sgui:addButton(23, 5, 14, 1, "Anuluj", function() sgui:close() end)
	sgui:addButton(7, 5, 14, 1, "Zatwierdź", function()
		local val = tonumber(field.text)
		if not val then
			server.messageBox(mod, "Wprowadzona wartość nie jest liczbą.", {"OK"})
		elseif val < 0 then
			server.messageBox(mod, "Wprowadź dodatnią wartość.", {"OK"})
		else
			if tab.members then
				for _, t in pairs(tab.members) do
					if config.receivers[t] then
						setValue(config.receivers[t], val)
					end
				end
			else
				setValue(tab, val)
			end
			sgui:close()
			refreshSelection()
		end
	end)
	
	sgui:run()
end

local function resetAll()
	if config.mode ~= 1 then return end
	if server.messageBox(mod, "Czy na pewno chcesz zresetować wszystkie odbiorniki?", {"Tak", "Nie"}) == "Nie" then return end
	for _, t in pairs(config.receivers) do
		local proxy = component.proxy(t.address)
		if proxy and proxy.type == "redstone" then
			for s = 0, 5 do
				if proxy.color then
					for c = 0, 15 do
						proxy.setBundledOutput(s, c, 0)
					end
				else
					proxy.setOutput(s, 0)
				end
			end
		end
	end
	server.call(mod, 5201, "Odbiorniki zostały zresetowane.", "IO", true)
	refreshSelection()
end

local function setActions()
	local sel = tonumber(string.match(box:getSelected() or "", "^(%d+)%."))
	if config.mode == 3 and sel and config.sensors[sel] then
		local buffer = {enable = {}, disable = {}}
		local int = {}
		
		for i = 1, 3 do
			if config.sensors[sel].enable[i] then
				buffer.enable[i] = {}
				buffer.enable[i].id = config.sensors[sel].enable[i].id
				buffer.enable[i].p1 = config.sensors[sel].enable[i].p1
				buffer.enable[i].p2 = config.sensors[sel].enable[i].p2
			end
		end
		for i = 1, 3 do
			if config.sensors[sel].disable[i] then
				buffer.disable[i] = {}
				buffer.disable[i].id = config.sensors[sel].disable[i].id
				buffer.disable[i].p1 = config.sensors[sel].disable[i].p1
				buffer.disable[i].p2 = config.sensors[sel].disable[i].p2
			end
		end
		
		local function updateLabels()
			for i = 1, 3 do
				if buffer.enable[i] then
					local a = server.actionDetails(mod, buffer.enable[i].id)
					if a then
						int[i].text = a.name
					else
						int[i].text = tostring(buffer.enable[i].id)
					end
				else
					int[i].text = ""
				end
				int[i]:draw()
			end
			for i = 1, 3 do
				if buffer.disable[i] then
					local a = server.actionDetails(mod, buffer.disable[i].id)
					if a then
						int[3 + i].text = a.name
					else
						int[3 + i].text = tostring(buffer.disable[i].id)
					end
				else
					int[3 + i].text = ""
				end
				int[3 + i]:draw()
			end
		end
		local function chooseAction(enable, num)
			local text = enable and int[num].text or int[3 + num].text
			local tab = enable and buffer.enable or buffer.disable
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
	
		local agui = gml.create("center", "center", 65, 14)
		agui.style = server.getStyle(mod)
		agui:addLabel("center", 1, 12, "Lista akcji")
		agui:addLabel(3, 3, 30, "Nazwa: " .. config.sensors[sel].name)
		agui:addLabel(3, 5, 20, "Akcje włączania:")
		agui:addLabel(31, 5, 20, "Akcje wyłączania:")
		
		for i = 1, 3 do
			local tt = agui:addLabel(4, 5 + i, 3, tostring(i) .. ".")
			int[i] = agui:addLabel(8, 5 + i, 22, "")
			local function exec()
				chooseAction(true, i)
			end
			tt.onDoubleClick = exec
			int[i].onDoubleClick = exec
		end
		for i = 1, 3 do
			local tt = agui:addLabel(32, 5 + i, 3, tostring(i) .. ".")
			int[3 + i] = agui:addLabel(36, 5 + i, 22, "")
			local function exec()
				chooseAction(false, i)
			end
			tt.onDoubleClick = exec
			int[3 + i].onDoubleClick = exec
		end
		
		agui:addButton(47, 11, 14, 1, "Anuluj", function() agui:close() end)
		agui:addButton(31, 11, 14, 1, "Zatwierdź", function()
			config.sensors[sel].enable = buffer.enable
			config.sensors[sel].disable = buffer.disable
			agui:close()
		end)
		updateLabels()
		agui:run()
	end
end

local function actions_setOutput(id, strength)
	local str = strength
	if str < 0 then str = 0 end
	if id > 0 and id < 51 and config.receivers[id] then
		local proxy = component.proxy(config.receivers[id].address)
		if proxy then
			local receiver = config.receivers[id]
			if receiver.color then
				proxy.setBundledOutput(receiver.side, receiver.color, str)
			else
				proxy.setOutput(receiver.side, str)
			end
			if config.mode == 1 then
				refreshSelection()
			end
		end
	elseif id > 100 and id < 117 and config.groups[id] then
		local group = config.groups[id]
		for _, i in pairs(group.members) do
			if config.receivers[i] then
				local receiver = config.receivers[i]
				local proxy = component.proxy(receiver.address)
				if proxy then
					if receiver.color then
						proxy.setBundledOutput(receiver.side, receiver.color, str)
					else
						proxy.setOutput(receiver.side, str)
					end
				end
			end
			refreshSelection()
		end
	end
end

local function actions_getInput(id)
	if id > 60 and id < 81 and config.sensors[id] then
		local sensor = config.sensors[id]
		local proxy = component.proxxy(sensor.address)
		if proxy then
			local val = nil
			if sensor.color then
				val = proxy.getBundledInput(sensor.side, sensor.color)
			else
				val = proxy.getInput(sensor.side)
			end
			return val
		end
	end
	return nil
end

local actions = {
	[1] = {
		name = "setOutput",
		type = "IO",
		desc = "Ustawia wyjście",
		p1type = "number",
		p2type = "number",
		p1desc = "identyfikator",
		p2desc = "siła sygnału",
		exec = actions_setOutput
	},
	[2] = {
		name = "getInput",
		type = "IO",
		desc = "Pobiera stan wejścia",
		p1type = "number",
		p1desc = "identyfikator",
		exec = actions_getInput
	}
}

mod.name = "io"
mod.version = version
mod.id = 33
mod.apiLevel = 2
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 9, ">> IO <<")
	window:addLabel(30, 3, 7, "Widok:")
	
	box = window:addListBox(3, 3, 25, 16, {})
	box.onDoubleClick = modifyEntry
	local fn = box.onClick
	box.onClick = function(...)
		fn(...)
		refreshSelection()
	end
	
	local tmp = window:addButton(38, 3, 14, 1, "", function(t)
		if config.mode == 1 then
			config.mode = 2
			t.text = "grupy"
		elseif config.mode == 2 then
			config.mode = 3
			t.text = "czujniki"
		else
			config.mode = 1
			t.text = "odbiorniki"
		end
		refreshList()
		t:draw()
	end)
	tmp.text = config.mode == 1 and "odbiorniki" or config.mode == 2 and "grupy" or "czujniki"
	window:addButton(30, 5, 14, 1, "Dodaj", function()
		if config.mode == 1 then addReceiver()
		elseif config.mode == 2 then addGroup()
		else addSensor() end
	end)
	window:addButton(48, 5, 14, 1, "Usuń", removeEntry)
	buttons[1] = window:addButton(30, 7, 14, 1, "Resetuj", resetAll)
	buttons[2] = window:addButton(48, 7, 14, 1, "Akcje", setActions)
	
	elements[1] = window:addLabel(39, 11, 7, "")  --id
	elements[2] = window:addLabel(39, 12, 28, "") --nazwa
	elements[3] = window:addLabel(39, 13, 18, "") --tryb
	elements[4] = window:addLabel(39, 14, 15, "") --wyjście/wejście
	elements[4].onDoubleClick = setOutput
	elements[5] = window:addLabel(39, 15, 22, "") --strona
	elements[6] = window:addLabel(39, 16, 18, "") --kolor
	for i = 1, 6 do elements[i].hidden = true end
	
	refreshList()
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	if not config.mode then config.mode = 1 end
	if not config.receivers then config.receivers = {} end
	if not config.groups then config.groups = {} end
	if not config.sensors then config.sensors = {} end
	
	core.registerEvent(mod, "redstone_changed")
end

mod.stop = function(core)
	core.saveConfig(mod, config)
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "redstone_changed" then
		--redstone_changed, address, side
		local sensor = nil
		local id = nil
		for i, t in pairs(config.sensors) do
			if t.address == e[2] and t.side == e[3] then
				sensor = config.sensors[i]
				id = i
				break
			end
		end
		local proxy = component.proxy(e[2])
		if not sensor or not proxy then return end
		local val = nil
		if sensor.color then
			val = proxy.getBundledInput(e[3], sensor.color)
		else
			val = proxy.getInput(e[3])
		end
		if val == 0 and #sensor.disable > 0 then
			for _, t in pairs(sensor.disable) do
				server.call(mod, t.id, t.p1, t.p2, true)
			end
		elseif val > 0 and #sensor.enable > 0 then
			for _, t in pairs(sensor.enable) do
				server.call(mod, t.id, t.p1, t.p2, true)
			end
		end
		server.call(mod, 5201, "Wykryto zmianę stanu czujnika: " .. sensor.name .. "(" .. tostring(id) .. ") -> " .. tostring(val), "IO", true)
		if config.mode == 3 then
			refreshSelection()
		end
	end
end

return mod