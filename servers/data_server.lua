--by: Admox
local fs = require("filesystem")
local component = require("component")
local event = require("event")
local shell = require("shell")
local term = require("term")
local serial = require("serialization")
local key = require("keyboard")

local gpu = component.gpu
local modem = component.modem

local wersja = "0.2.0beta"

local argss, optionss = shell.parse(...)
if argss[1] == "version_check" then return wersja end

local configuration = {}
local mounts = {}
local port = math.random(10000, 60000)
local print_buffer = ""
local log_buffer = ""
local working = true
local typing = false
local debug_mode = false

if modem == nil then
	io.stderr:write("Ten program wymaga do działania modemu.")
	return
end

local colors = 
{
	red = 0xff0000,
	green = 0x00ff00,
	blue = 0x4747ff,
	yellow = 0xffff00,
	gray = 0xbebebe,
	black = 0x000000,
	white = 0xffffff,
	cyan = 0x66ccff
}

--[[lista odpowiedzi i zapytań do serwera

Skład wiadomości z odpowiedzią: {odpowiedź, kod zapytania, dodatkowy parametr lub nil}
]]
local ds_code = 
{	
	--Lista zapywań do serwera
	getFile = 0x01, --parametry: folder, uuid   odpowiedź: status, plik lub nil
	setFile = 0x02, --parametry: folder lub nil, treść pliku   odpowiedź: status, uuid lub nil
	delFile = 0x03,  --parametry: folder, uuid pliku
	unused_1 = 0x04,
	getFileSize = 0x05,
	getFolder = 0x06, --parametry: uuid, nil     odpowiedź: status, lista plików w folderze lub nil
	setFolder = 0x07, --parametry: nil, nil    odpowiedź: status, uuid lub nil
	delFolder = 0x08, --parametry: uuid folderu
	getFolderSize = 0x09,  --zwraca ilość plików w folderze
	
	checkServer = 0x1d, --sprawdzenie, czy serwer jest online
	getFreeMemory = 0x1e, --zapytanie o ilość dostępnego miejsca w bajtach
	getVersion = 0x1f, --zapytanie o wersję serwera danych
	
	--Lista odpowiedzi serwera
	success = 0x20, --operacja zakończona pomyślnie
	deined = 0x21, --odmowa dostępu
	notEnoughMemory = 0x22, --brak pamięci na serwerze
	notFound = 0x23, --nie znaleziono pliku lub folderu o podanym numerze uuid
	failed = 0x24, --inny nieznany błąd
	requestNotFound = 0x25,  --nie odnaleziono zapytania
	online = 0x26,  --serwer jest online
	version = 0x27,  --wersja serwera, parametr: wersja
	notReady = 0x28,  --serwer nie jest gotowy do pracy, np. nie ma dostępnych dysków
	badTarget = 0x29,  --cel jest inny niż oczekiwano, np. plik jest folderem
	badRequest = 0x2a  --zapytanie jest niekompletne, brakuje danych
}

local function uuid()
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	return string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end)
end

local function generateUUID()
	return uuid():sub(1, 11)
end

--[[
	struktura pliku konfiguracyjnego:
	{tablica z numerami UUID dysków,port:{numer:number,status:bool},wymiana danych z serwerem:bool,tryb debugowania: bool}
]]
local function loadConfig()
	if fs.exists("/usr/config/dscfg.cfg") then
		local configFile = io.open("/usr/config/dscfg.cfg", "r")
		configuration = serial.unserialize(configFile:read())
		port = configuration[2][1]
		debug_mode = configuration[4] or debug_mode
		if configuration[2][2] then modem.open(port) end
		configFile:close()
	else
		configuration[1] = {}
		configuration[2] = {}
		configuration[3] = true
		configuration[4] = debug_mode
	end
end

local function saveConfig()
	configuration[2][1] = port
	configuration[2][2] = modem.isOpen(port)
	configuration[4] = debug_mode
	if not fs.isDirectory("/usr/config") then fs.makeDirectory("/usr/config") end
	local configFileS = io.open("/usr/config/dscfg.cfg", "w")
	configFileS:write(serial.serialize(configuration))
	configFileS:close()
end

local function setColor(color)
	if gpu.maxDepth() > 1 then return gpu.setForeground(color) end
end

local function logs(text, add)
	log_text = os.date():sub(-8).." - "..add:sub(1, 8)..": "..text
	log_buffer = log_buffer..log_text.."\n"
	if typing then
		print_buffer = print_buffer.."\n"..log_text
	else
		setColor(colors.gray)
		term.write("\n"..log_text)
	end
	if log_buffer:len() > 500 then
		local logFile = io.open("/tmp/dslog.log","a")
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

local function checkUUID(uuidNum, disks)
	--nie sprawdzam plików w folderach, ponieważ zajmie to za dużo czasu a szansa powtórzenia UUID jest znikoma
	for i = 1, #disks do
		if fs.exists("/mnt/"..disks[i]:sub(1, 3)).."/"..uuidNum then return false end
	end
	return true
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
	printUsage("\ndisks","Wyświetla listę zainstalowanych dysków na dane")
	printUsage("\ninstall","Podłącza nowy dysk do serwera")
	printUsage("\nuninstall","Odłącza dysk od serwera")
	printUsage("\nport [true/false lub numer portu]","Sterowanie portem serwera")
	printUsage("\naccess [true/false]","Umożliwia lub blokuje wymianą danych z serwerem")
	printUsage("\nlog","Wyświetla log programu")
	printUsage("\ndebug [true/false]","Przełącza tryb debugowania")
	printUsage("\nexit","Wychodzi z programu")
end

local function messageProc(...)
	local em = {...}
	debugLog(serial.serialize(em))
	if em[1] == "modem_message" then
		local request = serial.unserialize(em[6])
		local port = em[7]
		if port == nil then
			logs("brakujący port zwrotny.", em[3])
			return
		end
		if not configuration[3] then
			modem.send(em[3], port, serial.serialize({ds_code.deined, request[1], nil}))
			logs("dostęp zabroniony.", em[3])
			return
		end
		if #configuration[1] == 0 then
			modem.send(em[3], port, serial.serialize({ds_code.notReady, request[1], nil}))
			logs("serwer nie jest gotowy.", em[3])
			return
		end
		local disks = configuration[1]
		if request[1] == ds_code.getFile then
			--getFile, folder, uuid
			local fileName = nil
			if request[2] == nil then
				fileName = request[3]
			else
				fileName = request[2].."/"..request[3]
			end
			for i = 1, #disks do
				local path = "/mnt/"..disks[i]:sub(1, 3).."/"..fileName
				if fs.exists(path) then
					if not fs.isDirectory(path) then
						local cfile = io.open(path, "r")
						if cfile ~= nil then
							modem.send(em[3], port, serial.serialize({ds_code.success, request[1], cfile:read("*a")}))
							cfile:close()
							logs("Wysłano plik "..fileName, em[3])
							return
						end
						cfile:close()
					else
						modem.send(em[3], port, serial.serialize({ds_code.badTarget, request[1], nil}))
						logs("Błędne zapytanie: badTarget", em[3])
						return
					end
				end
			end
			modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
			logs("Nie znaleziono pliku "..request[3], em[3])
		elseif request[1] == ds_code.setFile then
			--setFile, folder, treść, uuid - jeśli jest, zaktualizuj plik
			local fEx = false
			for i = 1, #disks do
				local path = "/mnt/"..disks[i]:sub(1, 3)
				if request[2] ~= nil then path = path.."/"..request[2] end
				if fs.isDirectory(path) then
					fEx = true 
					break
				end
			end
			if not fEx then
				modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
				logs("nie znaleziono folderu "..request[2], em3[3])
				return
			end
			local uuidNumber = generateUUID()
			local backupDisk = nil
			local backupCopy = nil
			if request[4] ~= nil then
				for w = 1, #disks do
					local pat = "/mnt/"..disks[w]:sub(1, 3).."/"
					if request[2] ~= nil then
						pat = pat..request[2].."/"
						if not fs.isDirectory(pat) then fs.makeDirectory(pat) end
					end
					pat = pat..request[4]
					if fs.exists(pat) then
						backupDisk = pat
						bfile = io.open(pat, "r")
						backupCopy = bfile:read("*a")
						bfile:close()
						fs.remove(pat)
						uuidNumber = request[4]
						break
					elseif not fs.exists(pat) and w == #disks then
						modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
						logs("nie znaleziono pliku "..request[4].." w folderze "..path, em[3])
						return
					end
				end
			end
			for q = 1, #disks do
				local path = "/mnt/"..disks[q]:sub(1, 3)
				if request[2] ~= nil then path = path.."/"..request[2] end
				if request[3]:len() + component.proxy(disks[q]).spaceUsed() + 1024 < component.proxy(disks[q]).spaceTotal() then
					local rFile = io.open(path.."/"..uuidNumber, "w")
					rFile:write(request[3])
					rFile:close()
					modem.send(em[3], port, serial.serialize({ds_code.success, request[1], uuidNumber}))
					logs("Zapisano plik jako "..path.."/"..uuidNumber, em[3])
					return		
				end
			end
			backupFile = io.open(pat, "w")
			backupFile:write(backupCopy)
			backupFile:close()
			backupCopy = nil
			modem.send(em[3], port, serial.serialize({ds_code.notEnoughMemory, request[1], nil}))
			logs("Brak miejsca, aby zapisać plik", em[3])
		elseif request[1] == ds_code.delFile then
			--delFile, folder, uuid
			for i = 1, #disks do
				local path = "/mnt/"..disks[i]:sub(1, 3).."/"
				if request[2] ~= nil then path = path..request[2].."/" end
				path = path..request[3]
				if fs.exists(path) then
					fs.remove(path)
					modem.send(em[3], port, serial.serialize({ds_code.success, request[1], nil}))
					logs("Pomyślnie usunięto plik "..path, em[3])
					return
				end
			end
			modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
			logs(" Nie znaleziono pliku "..request[3], em[3])
		elseif request[1] == ds_code.getFileSize then
			--getFileSize, folder, uuid
			for i = 1, #disks do
				local fName = "/mnt/"..disks[i]:sub(1, 3).."/"
				if request[2] ~= nil then fName = fName..request[2].."/" end
				fName = fName..request[3]
				if fs.exists(fName) then
					local fFile = io.open(fName, "r")
					if fFile ~= nil then
						local fSize = fFile:seek("end")
						modem.send(em[3], port, serial.serialize({ds_code.success, request[1], fSize}))
						logs("Wysłano rozmiar pliku "..fName.." ("..fSize..")", em[3])
						fFile:close()
						return
					end
					fFile:close()
				end
			end	
		elseif request[1] == ds_code.getFolder then
			--getFolder, uuid		odpowiedź: lista plików w folderze
			local isFolder = false
			local tFiles = {}
			for i = 1, #disks do
				if fs.isDirectory("/mnt/"..disks[i]:sub(1, 3).."/"..request[2]) then
					for file in fs.list("/mnt/"..disks[i]:sub(1, 3).."/"..request[2]) do
						table.insert(tFiles, file)
					end
					isFolder = true
				end
			end
			if isfolder then
				modem.send(em[3], port, serial.serialize({ds_code.success, request[1], tFiles}))
				logs("Wysłano listę plików w folderze "..request[2], em[3])
			else
				modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
				logs("Nie znaleziono folderu "..request[2], em[3])
			end
		elseif request[1] == ds_code.setFolder then
			local uuidNum = generateUUID()
			debugLog("wywołanie setFolder: "..uuidNum..", "..#disks)
			for i = 1, #disks do
				local disk = component.proxy(disks[i])
				if disk.spaceUsed() + 1024 < disk.spaceTotal() then
					fs.makeDirectory("/mnt/"..disks[i]:sub(1, 3).."/"..uuidNum)
					modem.send(em[3], port, serial.serialize({ds_code.success, request[1], uuidNum}))
					logs("Wygenerowano folder "..uuidNum, em[3])
					return
				end
			end
			modem.send(em[3], port, serial.serialize({ds_code.notEnoughMemory, request[1], nil}))
			logs("brak miejsca na wygenerowanie folderu.", em[3])
		elseif request[1] == ds_code.delFolder then
			--delFolder, uuid
			local removed = false
			for i = 1, #disks do
				removed = fs.remove("/mnt/"..disks[i]:sub(1, 3).."/"..request[2])
			end
			if removed then
				modem.send(em[3], port, serial.serialize({ds_code.success, request[1], nil}))
				logs("Pomyślnie usunięto folder "..request[2], em[3])
			else
				modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
				logs("Nie znaleziono folderu "..request[2].." do usunięcia.", em[3])
			end
		elseif request[1] == ds_code.getFolderSize then
			--getFolderSize, uuid
			local isFolder = false
			local fSize = 0
			for i = 1, #disks do
				if fs.isDirectory("/mnt/"..disks[i]:sub(1, 3).."/"..request[2]) then
					for _ in fs.list("/mnt/"..disks[i]:sub(1, 3).."/"..request[2]) do
						fSize = fSize + 1
					end
					isFolder = true
				end
			end
			if isfolder then
				modem.send(em[3], port, serial.serialize({ds_code.success, request[1], fSize}))
				logs("Wysłano ilość plików w folderze "..request[2], em[3])
			else
				modem.send(em[3], port, serial.serialize({ds_code.notFound, request[1], nil}))
				logs("Nie znaleziono folderu "..request[2], em[3])
			end
		elseif request[1] == ds_code.checkServer then
			--checkServer
			modem.send(em[3], port, serial.serialize({ds_code.online, request[1], nil}))
			logs("Sprawdzenie, czy serwer jest online", em[3])
		elseif request[1] == ds_code.getFreeMemory then
			local bytes = 0
			for i = 1, #disks do
				local disk = component.proxy(disks[i])
				bytes = bytes + disk.spaceTotal() - disk.spaceUsed()
			end
			modem.send(em[3], port, serial.serialize({ds_code.success, request[1], bytes}))
			logs("Wysłano ilość dostępnego miejsca: "..bytes, em[3])
		elseif request[1] == ds_code.getVersion then
			modem.send(em[3], port, serial.serialize({ds_code.version, request[1], wersja}))
			logs("Wysłano wersję serwera: "..wersja, em[3])
		else
			modem.send(em[3], port, serial.serialize({ds_code.requestNotFound, request[1], nil}))
			logs("Nie znaleziono zapytania: "..request[1], em[3])
		end
	end
end

local function handleCommand(cmdName, args, options)
	if cmdName == "help" then
		commands()
	elseif cmdName == "disks" then
		setColor(colors.blue)
		term.write("\nDysk:    Wykorzystanie:    Pojemność:")
		setColor(colors.gray)
		available = configuration[1]
		for i = 1, #available do
			term.write("\n"..tostring(i)..". "..available[i]:sub(1, 3))
			local device = component.proxy(available[i])
			local used, total = math.ceil(device.spaceUsed() / 1024), math.ceil(device.spaceTotal() / 1024)
			local pro = math.ceil(used / total)
			ccur = {term.getCursor()}
			term.setCursor(10, ccur[2])
			term.write(used.."KB / "..pro.."%")
			term.setCursor(28, ccur[2])
			term.write(total.."KB")
		end
	elseif cmdName == "install" then
		local available = {}
		for add in component.list("filesystem") do
			device = component.proxy(add)
			if not device.isReadOnly() and device.address ~= require("computer").tmpAddress() and device.address ~= require("computer").getBootAddress() then
				already = configuration[1]
				exx = false
				for i = 1, #already do
					if already[i] == device.address then already = false end
				end
				if not exx then table.insert(available,device.address) end
			end
		end
		if #available > 0 then
			setColor(colors.cyan)
			term.write("\nZ dostępnych dysków wybierz numer [1-"..tostring(#available).."] lub klawisz 'q', aby anulować instalację.")
			setColor(colors.gray)
			for y = 1, #available do
				term.write("\n"..tostring(y)..".  "..available[y])
			end
			term.write("\n#> ")
			local choice = term.read()
			if choice:sub(1, 1):lower() ~= "q" then
				nChoice = tonumber(choice:sub(1, 1))
				if nChoice ~= nil then
					if nChoice >= 1 and nChoice <= #available then
						table.insert(configuration[1], available[nChoice])
						setColor(colors.green)
						term.write("\nPomyślnie dodano dysk "..available[nChoice]:sub(1, 3).." do bazy.")
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
		local available = configuration[1]
		if #available > 0 then
			setColor(colors.cyan)
			term.write("\nZ listy dostępnych dysków wybierz numer dysku [1-"..#available.."], który chcesz odinstalować lub 'q', aby anulować.")
			setColor(colors.gray)
			for i = 1, #available do
				term.write(tostring(i)..".  "..available[i])
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
							term.write("\nDysk "..available[nChoice].." został pomyślnie odinstalowany.")
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
			term.write("\nPort "..tostring(port).." został otwarty.")
		elseif args[1] == "false" then
			modem.close(port)
			setColor(colors.gray)
			term.write("\nPort "..tostring(port).." został zamknięty.")
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
	elseif cmdName == "access" then
		setColor(colors.cyan)
		if args[1] == "true" then
			configuration[3] = true
			term.write("\nKomunikacja z serwerem została odblokowana.")
		elseif args[1] == "false" then
			configuration[3] = false
			term.write("\nKomunikacja z serwerem została zablokowana.")
		elseif args[1] == nil then
			if configuration[3] then
				term.write("\nKomunikacja z serwerem jest włączona.")
			else
				term.write("\nKomunikacja z serwerem jest wyłączona.")
			end
		else
			setColor(colors.red)
			term.write("\nNiepoprawna składnia komendy.")
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
			term.write("\nTryb debugowania jest aktualnie "..stan..".")
		else
			setColor(colors.red)
			term.write("\nNiepoprawna składnia komendy.")
		end
	elseif cmdName == "log" then
		local lF = io.open("/tmp/dslog.log", "a")
		lF:write(log_buffer)
		lF:close()
		log_buffer = ""
		setColor(colors.gray)
		local cat = loadfile("/bin/cat.lua")
		cat("/tmp/dslog.log")
	elseif cmdName == "exit" then
		local logFile = io.open("/tmp/dslog.log","a")
		logFile:write(log_buffer)
		logFile:close()
		saveConfig()
		working = false
		setColor(colors.yellow)
		term.write("\nProgram zakończony.")
	else
		io.stderr:write("\n"..cmdName..": nie znaleziono. Aby zobaczyć listę komend, napisz 'help'")
	end
end

local function main()
	loadConfig()
	term.clear()
	term.setCursor(1,1)
	setColor(colors.yellow)
	term.write("Serwer danych,   wersja "..wersja)
	setColor(colors.gray)
	term.write("\n\nAby rozpocząć wpisywanie komendy, naciśnij przycisk [Enter]")
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
event.listen("modem_message",messageProc)
main()
event.ignore("modem_message",messageProc)
gpu.setForeground(prevColor)
