-- ########################################################
-- ##              Data Server wersja 2.4               ##
-- #   Serwer służący do magazynowania danych w postaci   #
-- #  plików na dyskach                                   #
-- ##   05.2015                           by: Aranthor   ##
-- ########################################################

--[[
	## Opis serwera ##
	Serwer służy do przechowywania plików. Został stworzony na postawie swojej starszej wersji 'data_serwer'.
	W odróżnieniu od poprzednika, nie przechowuje plików o nazwach wygenerowanych losowo - pozwala na
	samodzielne ustawienie nazw plików i folderów.
	Cechuje się niewielkim zasobem zapytań, który jest w pełni wystarczający do jego obsługi.
	
	## Cechy serwera ##
	1. Foldery są automatycznie tworzone podczas zapisywania do nich plików i automatycznie usuwane,
	gdy są puste.
	2. Serwer zapisuje każde zdarzenie do logu znajdującego się w folderze tymczasowym.
	3. Do przesyłu danych wykorzystuje się protokół HDP.
	4. Serwer posiada jeden kod zapytania do modyfikacji plików: 'file'. Jeśli zawartość pliku będzie
	równa 'nil', plik zostanie usunięty.
	
	## Zapytania ##
	* {reqCode.file, path, content} @ret{success}
		zapytanie wysyła plik o treści 'content', który ma być zapisany w folderze 'path'.
		Jeśli 'content' jest równy 'nil', plik jest usuwany.
		Jeśli plik już istnieje, jest nadpisywany.
	* {reqCode.get, path} @ret{success, content}
		zapytanie o zawartość pliku 'path'. Jeśli nie wystąpił błąd, serwer zwraca następującą tablicę:
		{respCode.success, 'content'}
		gdzie 'content' to zawartość pliku.
	* {reqCode.list, path} @ret{success, {tabs}}
		zapytanie o listę plików w folderze.
		{respCode.success, {{name, size}, {name, size},...}}
		gdzie 'name' oznacza nazwę pliku, 'size' - rozmiar.
		Jeśli rozmiar wynosi -1, obiekt jest folderem
	* {reqCode.echo}
		sprawdzenie, czy serwer jest dostępny
]]

--TODO: wywalenie repeatów i wstawienie filtracji (patrz dokumentacja event.pull)

local computer = require("computer")
local fs = require("filesystem")
local component = require("component")
local event = require("event")
local shell = require("shell")
local term = require("term")
local serial = require("serialization")
local key = require("keyboard")
local hdp = require("hdp")

local gpu = component.gpu
local modem = nil
if not component.isAvailable("modem") then
	io.stderr:write("Ten program wymaga do działania modemu.")
	return
else
	modem = component.modem
end

local wersja = "2.4"

local argss, optionss = shell.parse(...)
if argss[1] == "version_check" then return wersja end

local configuration = {}
local port = math.random(10000, 60000)
local print_buffer = ""
local log_buffer = ""
local working = true
local typing = false
local debug_mode = false

local colors = 
{
	red = 0xff0000,
	green = 0x00ff00,
	blue = 0x4747ff,
	yellow = 0xffff00,
	gray = 0xbebebe,
	black = 0x000000,
	white = 0xffffff,
	cyan = 0x66ccff,
	orange = 0xffa500
}

-- Zapytania do serwera
local reqCode = {
	file = 0x01, --@param:(ścieżka, zawartość)
	get  = 0x02, --@param:(ścieżka)
	list = 0x03, --@param:(ścieżka)
	echo = 0x04
}

-- Kody odpowiedzi serwera
local respCode = {
	success = 0x00, -- zadana czynność powiodła się
	failed = 0x01, -- nieznany błąd
	nomem = 0x02, -- za mało miejsca na serwerze
	notfound = 0x03, -- nie znaleziono pliku lub folderu
	badreq = 0x04, -- zapytanie jest niekompletne lub nie istnieje
	echo = 0x10
}


--[[
	struktura pliku konfiguracyjnego:
	{tablica z numerami UUID dysków,port:{numer:number,status:bool},tryb debugowania: bool}
]]
local function loadConfig()
	if fs.exists("/etc/dtsrv.cfg") then
		local configFile = io.open("/etc/dtsrv.cfg", "r")
		configuration = serial.unserialize(configFile:read())
		port = configuration[2][1]
		debug_mode = configuration[3] or debug_mode
		if configuration[2][2] then modem.open(port) end
		configFile:close()
	else
		configuration[1] = {}
		configuration[2] = {}
		configuration[3] = debug_mode
	end
end

local function saveConfig()
	configuration[2][1] = port
	configuration[2][2] = modem.isOpen(port)
	configuration[3] = debug_mode
	local configFileS = io.open("/etc/dtsrv.cfg", "w")
	configFileS:write(serial.serialize(configuration))
	configFileS:close()
end

local function setColor(color)
	if gpu.maxDepth() > 1 then return gpu.setForeground(color) end
end

local function checkDisks()
	local disks = configuration[1]
	if #disks < 1 then
		setColor(colors.orange)
		term.write("\n >>> BRAK ZAINSTALOWANYCH DYSKÓW! <<<")
		return false
	end	
	local removeList = {}
	for i = 1, #disks do
		if not component.proxy(disks[i]) then
			setColor(colors.red)
			term.write("\n".."Nie znaleziono dysku "..disks[i]:sub(1, 3).." - usuwanie wpisu")
			table.insert(removeList, i)
		end
	end
	if #removeList > 0 then
		table.sort(removeList, function(a, b) return a > b end)
		for i = 1, #removeList do
			table.remove(configuration[1], i)
		end
		saveConfig()
	end
	return true
end

local function logs(add, text)
	log_text = os.date():sub(-8).." - "..add:sub(1, 8)..": "..text
	log_buffer = log_buffer..log_text.."\n"
	if typing then
		print_buffer = print_buffer.."\n"..log_text
	else
		setColor(colors.gray)
		term.write("\n"..log_text)
	end
	if log_buffer:len() > 1024 then
		local logFile = io.open("/tmp/dtsrvlog.log","a")
		logFile:write(log_buffer)
		logFile:close()
		log_buffer = ""
	end
end

local function debugLog(text)
	if debug_mode then
		setColor(colors.yellow)
		term.write("\nDEBUG: "..os.date():sub(-8))
		setColor(colors.gray)
		term.write(" - "..text)
	end
end

local function separateCommand(comm)
	local pos = string.find(comm, " ", 1)
	if pos == nil then
		return comm, {}, {}
	else
		local com = comm:sub(1, pos-1)
		local args, options = shell.parse(comm:sub(pos+1, comm:len()))
		return com, args, options
	end
end

local function printUsage(str1, str2)
	setColor(colors.cyan)
	term.write(str1)
	setColor(colors.gray)
	term.write(" - "..str2)
end

local function commands()
	setColor(colors.yellow)
	term.write("\nLista dostępnych komend:")
	printUsage("\nhelp","Wyświetla listę komend")
	printUsage("\ndisks","Wyświetla listę zainstalowanych dysków")
	printUsage("\ninstall","Podłącza nowy dysk do serwera")
	printUsage("\nuninstall","Odłącza dysk od serwera")
	printUsage("\nport [true/false lub numer portu]","Otwarcie, zamknięcie lub zmiana portu")
	printUsage("\nlog","Wyświetla log programu")
	printUsage("\ndebug [true/false]","Przełącza tryb debugowania")
	printUsage("\nexit","Wychodzi z programu")
end

local function messageProc(...)
	os.sleep(0.2)
	local input = {...}
	debugLog("Wiadomosc: " .. input[1] .. ", " .. input[4] .. ", " .. input[6] .. ", " ..input[7])
	if input[1] == "hdp_message" and input[4] == port then
		local msg = serial.unserialize(input[7])
		if msg ~= nil then
			if #msg < 2 and msg[1] ~= reqCode.echo then
				hdp.send(input[6], port, serial.serialize({respCode.badreq}))
				logs(input[3], "Zapytanie jest niekompletne")
				debugLog("Zapytanie: " .. serial.serialize(msg))
			end
			if  #msg > 1 and msg[2]:sub(1, 1) == "/" then msg[2] = msg[2]:sub(2, msg[2]:len()) end
			if not checkDisks() then
				hdp.send(input[6], port, serial.serialize({respCode.failed}))
				logs(input[3], "Obsłużenie zapytania jest niemożliwe")
				return
			end
			if msg[1] == reqCode.file then
				if #msg == 3 or #msg == 2 then
					-- (reqCode.file, ścieżka, zawartość)
					local disks = configuration[1]

					local removed = false
					for i = 1, #disks do
						local path = "/mnt/" .. disks[i]:sub(1, 3) .. "/"..msg[2]
						if fs.exists(path) then
							fs.remove(path)
							debugLog("Usuwanie starej wersji pliku: " .. path)
							removed = true
						end
					end
					if msg[3] ~= nil then
						for i = 1, #disks do
							local disk = component.proxy(disks[i])
							if disk.spaceTotal() - disk.spaceUsed() - 1024 > msg[3]:len() then
								local path = "/mnt/" .. disks[i]:sub(1, 3) .. "/" .. msg[2]
								local segm = fs.segments(path)
								for j = 1, #segm - 1 do
									local p2 = ""
									for k = 1, j do p2 = p2 .. "/" .. segm[k] end
									if not fs.isDirectory(p2) then fs.makeDirectory(p2) end
								end
								local file = io.open(path, "w")
								file:write(msg[3])
								file:close()
								hdp.send(input[6], port, serial.serialize({respCode.success}))
								logs(input[3], "Zapisano plik " .. path)
								debugLog("Rozmiar pliku: " .. msg[3]:len())
								break
							end
							if i == #disks then
								hdp.send(input[6], port, serial.serialize({respCode.nomem}))
								logs(input[3], "Brak miejsca, by zapisac plik " .. msg[2])
								debugLog("Rozmiar pliku: " .. msg[3]:len())
							end
						end
					else
						if removed then
							hdp.send(input[6], port, serial.serialize({respCode.success}))
							logs(input[3], "Usunieto plik " .. msg[2])
						else
							hdp.send(input[6], port, serial.serialize({respCode.notfound}))
							logs(input[3], "Nie znaleziono pliku " .. msg[2] .. " od usuniecia")
						end
					end
					for i = 1, #disks do
						local pSegm = fs.segments("/mnt/" .. disks[i]:sub(1, 3) .. "/" .. msg[2])
						for j = #pSegm - 1, 1, -1 do
							local path = ""
							local counter = 0
							for x = 1, j do path = path .. "/" .. pSegm[x] end
							for file in fs.list(path) do counter = counter + 1 end
							if counter == 0 then
								fs.remove(path)
							end
						end
					end
				else
					hdp.send(input[6], port, serial.serialize({respCode.badreq}))
					logs(input[3], "Niepoprawna tresc zapytania")
					debugLog("Zapytanie: " .. input[7])
				end
			elseif msg[1] == reqCode.get then
				-- (reqCode.get, ścieżka)
				local disks = configuration[1]
				for i = 1, #disks do
					local path = "/mnt/" .. disks[i]:sub(1, 3) .. "/" .. msg[2]
					if fs.exists(path) then
						local file = io.open(path, "r")
						local fcont = file:read("*a")
						file:close()
						local status, code = hdp.send(input[6], port, serial.serialize({respCode.success, fcont}))
						if status then
							logs(input[3], "Wyslano plik " .. msg[2])
						else
							logs(input[3], "Nie udalo sie wyslac pliku " .. msg[2] .. ": " .. hdp.translateMessage(code))
						end
						break
					end
					if i == #disks then
						hdp.send(input[6], port, serial.serialize({respCode.notfound}))
						logs(input[3], "Nie znaleziono pliku " .. msg[2])
					end
				end
			elseif msg[1] == reqCode.list then
				-- (reqCode.list, ścieżka)
				local list = {}
				local disks = configuration[1]
				for i = 1, #disks do
					local path = "/mnt/" .. disks[i]:sub(1, 3) .. "/" .. msg[2]
					if fs.isDirectory(path) then
						for fname in fs.list(path) do
							local l2 = {}
							local name = fname
							if name:sub(#name, #name) == "/" then name = name:sub(1, #name - 1) end
							local size = fs.size(path .. "/" .. name)
							if fs.isDirectory(path .. "/" .. name) then size = -1 end
							table.insert(l2, name)
							table.insert(l2, size)
							table.insert(list, l2)
						end
					else
						list = nil
					end
				end
				if list then
					table.sort(list, function(a, b) return a[1]:sub(1, 1) < b[1]:sub(1, 1) end)
					local status, code = hdp.send(input[6], port, serial.serialize({respCode.success, list}))
					if status then
						logs(input[3], "Wyslano liste obiektow w katalogu " .. msg[2])
					else
						logs(input[3], "Nie udalo sie wyslac listy obiektow: " .. hdp.translateMessage(code))
					end
				else
					hdp.send(input[6], port, serial.serialize({respCode.notfound}))
					logs(input[3], "Nie znaleziono katalogu " .. msg[2] .. " do listowania")
				end
			elseif msg[1] == reqCode.echo then
				local status, code = hdp.send(input[6], port, serial.serialize({respCode.echo}))
				if status then
					logs(input[3], "Wyslano echo")
				else
					logs(input[3], "Nie udalo sie wyslac echa: " .. code .. " " .. hdp.translateMessage(code))
				end
			else
				hdp.send(input[6], port, serial.serialize({respCode.badreq}))
				logs(input[3], "Nie odnaleziono zapytania: " .. msg[1])
				debugLog("Szczegoly: " .. input[7])
			end
		else
			debugLog("Deserializacja nie powiodla sie: " .. input[7])
		end
	else
		debugLog("Wystapil nieznany blad. ")
	end
end

local function handleCommand(cmdName, args, options)
	if cmdName == "help" then
		commands()
	elseif cmdName == "disks" then
		setColor(colors.blue)
		term.write("\nDysk:    Wykorzystanie:    Pojemność:")
		available = configuration[1]
		for i = 1, #available do
			setColor(colors.gray)
			term.write("\n" .. tostring(i) .. ". " .. available[i]:sub(1, 3))
			ccur = {term.getCursor()}
			local device = component.proxy(available[i])
			if device then
				local used, total = math.ceil(device.spaceUsed() / 1024), math.ceil(device.spaceTotal() / 1024)
				local pro = math.ceil(used / total)
				term.setCursor(10, ccur[2])
				term.write(used .. "KB / " .. pro .. "%")
				term.setCursor(28, ccur[2])
				term.write(total .. "KB")
			else
				term.setCursor(9, ccur[2])
				setColor(colors.red)
				term.write(">>> NIE ZNALEZIONO <<<")
			end
		end
		checkDisks()
	elseif cmdName == "install" then
		checkDisks()
		local available = {}
		for add in component.list("filesystem") do
			device = component.proxy(add)
			if not device.isReadOnly() and device.address ~= computer.tmpAddress() and device.address ~= computer.getBootAddress() then
				already = configuration[1]
				local exx = false
				for i = 1, #already do
					if already[i] == device.address then exx = true end
				end
				if not exx then table.insert(available, device.address) end
			end
		end
		if #available > 0 then
			setColor(colors.cyan)
			term.write("\nZ dostępnych dysków wybierz numer [1-" .. tostring(#available) .. "] lub klawisz 'q', aby anulować instalację.")
			setColor(colors.gray)
			for y = 1, #available do
				term.write("\n" .. tostring(y) .. ".  " .. available[y])
			end
			term.write("\n#> ")
			local choice = term.read()
			if choice:sub(1, 1):lower() ~= "q" then
				nChoice = tonumber(choice:sub(1, 1))
				if nChoice ~= nil then
					if nChoice >= 1 and nChoice <= #available then
						table.insert(configuration[1], available[nChoice])
						setColor(colors.green)
						term.write("\nPomyślnie dodano dysk " .. available[nChoice]:sub(1, 3) .. " do serwera.")
					else
						io.stderr:write("\nWpisana liczba jest poza zakresem!")
						setColor(colors.yellow)
						term.write("\nInstalacja przerwana.")
					end
				else
					io.stderr:write("\nWpisano niepoprawną wartość!")
					setColor(colors.yellow)
					term.write("\nInstalacja przerwana.")
				end
			else
				setColor(colors.yellow)
				term.write("\nInstalacja przerwana.")
			end
		else
			setColor(colors.yellow)
			term.write("\nNie znaleziono żadnych dysków nadających się do instalacji.")
		end
	elseif cmdName == "uninstall" then
		checkDisks()
		local available = configuration[1]
		if #available > 0 then
			setColor(colors.cyan)
			term.write("\nZ listy dostępnych dysków wybierz numer dysku [1-" .. #available .. "], który chcesz odinstalować lub 'q', aby anulować.")
			setColor(colors.gray)
			for i = 1, #available do
				term.write(tostring(i) .. ".  " .. available[i])
			end
			local choice = io.read()
			if choice:sub(1, 1):lower() ~= "q" then
				nChoice = tonumber(choice:sub(1, 1))
				if nChoice ~= nil then
					if nChoice >= 1 and nChoice <= #available then
						setColor(colors.yellow)
						term.write("\nCzy na pewno chcesz odinstalować ten dysk?. Dane znajdujące się na nim będą niedostępne do jego ponownego zainstalowania [t/n]: ")
						local anwser = io.read()
						if anwser:sub(1, 1):lower() == "t" then
							term.write("\nDysk " .. available[nChoice] .. " został pomyślnie odinstalowany.")
							table.remove(available, nChoice)
							configuration[1] = available
							setColor(colors.green)
						else
							term.write("\nInstalacja przerwana.")
						end
					else
						io.stderr:write("\nWpisana liczba jest poza zakresem!")
						setColor(colors.yellow)
						term.write("\nInstalacja przerwana.")
					end
				else
					io.stderr:write("\nWpisano niepoprawną wartość!")
					setColor(colors.yellow)
					term.write("\nInstalacja przerwana.")
				end
			else
				setColor(colors.yellow)
				term.write("\nInstalacja przerwana.")
			end
		else
			setColor(colors.yellow)
			term.write("\nBrak zainstalowanych dysków.")
		end
	elseif cmdName == "port" then
		if args[1] == "true" then
			modem.open(port)
			setColor(colors.gray)
			term.write("\nPort " .. tostring(port) .. " został otwarty.")
		elseif args[1] == "false" then
			modem.close(port)
			setColor(colors.gray)
			term.write("\nPort "..tostring(port) .. " został zamknięty.")
		elseif tonumber(args[1]) ~= nil then
			newPort = tonumber(args[1])
			if newPort >= 10000 and newPort <= 60000 then
				opf = modem.isOpen(port)
				modem.close(port)
				port = newPort
				if opf then modem.open(port) end
				setColor(colors.gray)
				term.write("\nPort modemu został zmieniony. Nowy port: "..tostring(port))
			else
				io.stderr:write("\nWybrany port musi być mniejszy od 60 000 i większy od 10 000.")
			end
		elseif args[1] == nil then
			setColor(colors.cyan)
			term.write("\nStatus modemu:")
			setColor(colors.yellow)
			term.write("\nPort: ")
			setColor(colors.gray)
			term.write(tostring(port))
			setColor(colors.yellow)
			term.write("\nStatus: ")
			local sst = "Otwarty"
			if not modem.isOpen(port) then sst = "Zamknięty" end
			setColor(colors.gray)
			term.write(sst)
		else
			io.stderr:write("\nNiepoprawna składnia komendy.")
		end
	elseif cmdName == "debug" then
		setColor(colors.cyan)
		if args[1] == "true" then
			debug_mode = true
			term.write("\nTryb debugowania został włączony.")
		elseif args[1] == "false" then
			debug_mode = false
			term.write("\nTryb debugowania został wyłączony.")
		elseif args[1] == nil then
			local stan = "włączony"
			if not debug_mode then stan = "wyłączony" end
			term.write("\nTryb debugowania jest aktualnie " .. stan .. ".")
		else
			setColor(colors.red)
			term.write("\nNiepoprawna składnia komendy.")
		end
	elseif cmdName == "log" then
		local lF = io.open("/tmp/dtsrvlog.log", "a")
		lF:write(log_buffer)
		lF:close()
		log_buffer = ""
		setColor(colors.gray)
		local cat = loadfile("/bin/cat.lua")
		cat("/tmp/dtsrvlog.log")
	elseif cmdName == "exit" then
		local logFile = io.open("/tmp/dtsrvlog.log","a")
		logFile:write(log_buffer)
		logFile:close()
		saveConfig()
		working = false
		setColor(colors.yellow)
		term.write("\nProgram zakończony.")
	elseif cmdName == "\n" then
		
	else
		io.stderr:write("\n" .. cmdName .. ": nie znaleziono. Aby zobaczyć listę komend, napisz 'help'")
	end
end

local function main()
	loadConfig()
	term.clear()
	term.setCursor(1, 1)
	setColor(colors.yellow)
	term.write("Serwer danych    wersja " .. wersja)
	setColor(colors.gray)
	term.write("\n\nAby rozpocząć wpisywanie komendy, naciśnij przycisk [Enter]")
	if #configuration[1] < 1 then
		setColor(colors.orange)
		term.write("\n\n >>> UWAGA: nie dodano żadnych dysków, serwer nie będzie działał właściwie! <<<")
	end
	while working do
		if print_buffer:len() > 1 then
			setColor(colors.gray)
			term.write(print_buffer)
			print_buffer = ""
		end
		local evv = {event.pull("key_down")}
		if evv[4] == key.keys.enter then
			typing = true
			setColor(colors.red)
			term.write("\n/# ")
			setColor(colors.white)
			local cmd, args, options = separateCommand(io.read())
			handleCommand(cmd, args, options)
			typing = false
		end
	end
end

local prevColor = gpu.getForeground()
event.listen("modem_message", hdp.listen)
event.listen("hdp_message", messageProc)
main()
event.ignore("hdp_message", messageProc)
event.ignore("modem_message", hdp.listen)
gpu.setForeground(prevColor)