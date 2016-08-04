--[[Struktura pliku z lista aplikacji:
	{
		[1] = nazwa aplikacji: string,
		[2] = wersja: string,
		[3] = adres pobierania: string,
		[4] = opis aplikacji: string,
		[5] = autor: string,
		[6] = zaleznosci: table or nil,
		[7] = czy aplikacja jest biblioteka: bool or nil,
		[8] = nazwa pliku manual: string or nil,
		[9] = zmodyfikowana nazwa aplikacji: string or nil,
		[10] = archiwum: bool or nil
	}
	
	Opcje programu:
		*list [-r]
		Wyświetla listę dostępnych pakietów. [r] wyświetla również pakiety archiwalne.
		*info <pakiet>
		Wyświetla informacje o wybranym pakiecie.
		*install <pakiet> [-f] [-n]
		Instaluje nowy pakiet. [f] wymusza instalację, [n] wyłącza instalację zależności
		*remove <pakiet> [-d]
		Usuwa pakiet. [d] usuwa również zależności.
		*test <ścieżka>
		Testuje bazę offline aplikacji pod kątem błędów.
]]

local wersja = "0.3.0"

local component = require("component")

if not component.isAvailable("internet") then
	io.stderr:write("Ta aplikacja wymaga zainstalowanej karty internetowej")
	return
end

local inter2 = component.internet
local gpu = component.gpu
local internet = require("internet")

if not inter2.isHttpEnabled() then
	io.stderr:write("Polaczenia z Internetem sa obecnie zablokowane.")
	return
end

local fs = require("filesystem")
local serial = require("serialization")
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local shell = require("shell")

local resolution = {gpu.getResolution()}
local args, options = shell.parse(...)

local appList = nil
local installed = {}

local colors = {
	white = 0xffffff,
	orange = 0xffa500,
	magenta = 0xff00ff,
	yellow = 0xffff00,
	red = 0xff0000,
	green = 0x00ff00,
	blue = 0x0000ff,
	cyan = 0x00ffff,
	brown = 0xa52a2a,
	gray = 0xc9c9c9,
	silver = 0xe0e0de,
	black = 0x000000
}

local function textColor(color)
	if gpu.maxDepth() > 1 and color then
		return gpu.setForeground(color)
	end
end

local function printCommand(com, desc)
	textColor(colors.orange)
	term.write("  arpm " .. com)
	textColor(colors.silver)
	print(" - " .. desc)
end

local function ok()
	textColor(colors.green)
	term.write("OK")
	textColor(colors.cyan)
end

local function usage()
	local prev = nil
	prev = textColor(colors.green)
	print("ARPM - ARPM Repository Package Manager     wersja " .. wersja)
	textColor(colors.cyan)
	print("Użycie:")
	printCommand("list [-r]", "Wyświetla listę dostępnych pakietów. [r] wyświetla również pakiety archiwalne.")
	printCommand("info <pakiet>", "Wyświetla informacje o wybranym pakiecie.")
	printCommand("install <pakiet> [-f] [-d]", "Instaluje nowy pakiet. [f] wymusza instalację, [n] wyłącza instalację zależności.")
	printCommand("remove <pakiet> [-d]", "Usuwa pakiet. [d] usuwa również zależności")
	printCommand("update [pakiet] [-f]", "Aktualizuje pakiet. [f] wymusza uaktualnienie.")
	printCommand("test <ścieżka>", "Testuje bazę offline aplikacji pod kątem błędów.")
	textColor(prev)
end

local function getContent(url)
	local sContent = ""
	local result, response = pcall(internet.request, url)
	if not result then
		return nil
	end
	for chunk in response do
		sContent = sContent .. chunk
	end
	return sContent
end

local function saveAppList(raw)
	local filename = "/tmp/setup-list"
	if fs.isDirectory(filename) then
		if not fs.remove(filename) then return end
	end
	local f = io.open(filename, "w")
	if f then
		f:write(raw)
		f:close()
	end
end

local function fetchAppList()
	local filename = "/tmp/setup-list"
	if fs.exists(filename) and not fs.isDirectory(filename) then
		local f = io.open(filename, "r")
		if f then
			local s = serial.unserialize(f:read("*a"))
			f:close()
			if s then
				appList = s
				return
			end
		end
	end
	local resp = getContent("https://bitbucket.org/Aranthor/oc_equipment/raw/master/installer/setup-list")
	if resp then
		local s, e = serial.unserialize(resp)
		if not s then
			io.stderr:write("Nie udało się odczytać listy aplikacji: " .. e)
		end
		appList = s
		saveAppList(resp)
	else
		io.stderr:write("Nie można polączyć się z Internetem.")
	end
end

local function getApp(url)
	return getContent(url)
end

local function getAppData(appName)
	for _, nm in pairs(appList) do
		if nm[1] == appName then return nm end
	end
	return nil
end

local function testApp(app, all)
	local warn = {}
	if type(app[1]) ~= "string" then
		table.insert(warn, "nazwa (1) nie jest ciągiem znaków")
	elseif app[1]:len() == 0 then
		table.insert(warn, "nazwa (1) jest za krótka")
	end
	if type(app[2]) ~= "string" then
		table.insert(warn, "wersja (2) nie jest ciągiem znaków")
	elseif app[2]:len() == 0 then
		table.insert(warn, "wersja (2) jest za krótka")
	end
	if type(app[3]) ~= "string" then
		table.insert(warn, "adres (3) nie jest ciągiem znaków")
	else
		local s, i = pcall(component.internet.request, app[3])
		if s then
			local d, e = pcall(i.read, 1)
			if not d then
				table.insert(warn, "adres (3): " .. e)
			end
			i.close()
		else
			table.insert(warn, "adres (3): " .. i)
		end
	end
	if type(app[4]) ~= "string" then
		table.insert(warn, "opis (4) nie jest ciągiem znaków")
	elseif app[4]:len() == 0 then
		table.insert(warn, "nie podano opisu (4)")
	end
	if type(app[5]) ~= "string" then
		table.insert(warn, "nazwa autora (5) nie jest ciągiem znaków")
	elseif app[5]:len() == 0 then
		table.insert(warn, "nie podano autora (5)")
	end
	if type(app[6]) == "table" then
		for _, dep in pairs(app[6]) do
			local found = false
			for _, a in pairs(all) do
				if a[1] == dep then
					found = true
					break
				end
			end
			if not found then
				table.insert(warn, "zależność '" .. dep .. "' nie została odnaleziona")
			end
		end
	elseif type(app[6]) ~= "nil" then
		table.insert(warn, "zależności (6) maja niewłaściwy typ danych")
	end
	if type(app[7]) ~= "boolean" and type(app[7]) ~= "nil" then
		table.insert(warn, "flaga biblioteki (7) ma niewłaściwy typ danych")
	end
	if type(app[8]) == "string" then
		if app[8]:len() == 0 then
			table.insert(warn, "nazwa pliku manual (8) jest za krótka")
		end
	elseif type(app[8]) ~= "nil" then
		table.insert(warn, "nazwa pliku manual (8) ma niewłaściwy typ danych")
	end
	if type(app[9]) == "string" then
		if app[9]:len() == 0 then
			table.insert(warn, "zmodyfikowana nazwa aplikacji (9) jest za krótka")
		end
	elseif type(app[9]) ~= "nil" then
		table.insert(warn, "zmodyfikowana nazwa aplikacji (9) ma niewłaściwy typ danych")
	end
	if type(app[10]) ~= "boolean" and type(app[10]) ~= "nil" then
		table.insert(warn, "flaga archiwum (10) ma niewłaściwy typ danych")
	end
	return warn
end

local function testRepo(path)
	if not path or path:len() == 0 then
		io.stderr:write("Nie podano ścieżki do bazy aplikacji.")
		return
	end
	if path:sub(1, 1) ~= "/" then
		path = fs.concat(shell.getWorkingDirectory(), path)
	end
	if not fs.exists(path) then
		io.stderr:write("Podany plik nie istnieje.")
		return
	end
	if fs.isDirectory(path) then
		io.stderr:write("Podany plik jest katalogiem!")
		return
	end
	local file, e = io.open(path, "r")
	if not file then
		io.stderr:write("Nie udało się otworzyć pliku: " .. e)
		return
	end
	local tab, e = serial.unserialize(file:read("*a"))
	file:close()
	if not tab then
		io.stderr:write("Nie udało się przetworzyć pliku: " .. e)
		return
	end
	textColor(colors.cyan)
	term.write("Testowanie wpisów:")
	local errors = 0
	for _, t in pairs(tab) do
		textColor(colors.silver)
		term.write("\n" .. t[1] .. "   ")
		local test = testApp(t, tab)
		if #test > 0 then
			textColor(colors.yellow)
			for _, s in pairs(test) do
				term.write("\n  " .. s)
				errors = errors + 1
			end
		else
			ok()
		end
	end
	textColor(colors.cyan)
	print("\n\nZweryfikowano " .. tostring(#tab) .. " aplikacji/e.")
	if errors > 0 then
		textColor(colors.orange)
		print("Test zakończony. Znaleziono " .. tostring(errors) .. " błędy/ów.")
	else
		textColor(colors.green)
		print("Test zakończony pomyślnie.")
	end
end

local function packetInfo(packetName)
	if not packetName or packetName == "" then
		io.stderr:write("Nie podano nazwy pakietu")
		return
	end
	fetchAppList()
	if appList then
		for _, packet in pairs(appList) do
			if type(packet) == "table" and packet[1] == packetName then
				textColor(colors.cyan)
				print("\n>> Informacje o pakiecie <<")
				textColor(colors.yellow)
				io.write("\nNazwa pakietu: ")
				textColor(colors.gray)
				print(packet[1])
				if packet[9] then
					textColor(colors.yellow)
					io.write("Nazwa pliku: ")
					textColor(colors.gray)
					print(packet[9])
				end
				textColor(colors.yellow)
				io.write("Aktualna wersja: ")
				textColor(colors.gray)
				print(packet[2])
				textColor(colors.yellow)
				io.write("Opis aplikacji: ")
				textColor(colors.gray)
				print(packet[4])
				textColor(colors.yellow)
				io.write("Autor: ")
				textColor(colors.gray)
				print(packet[5])
				textColor(colors.yellow)
				io.write("Adres pobierania: ")
				textColor(colors.gray)
				do
					if packet[3]:len() > resolution[1] - 20 then
						print(packet[3]:sub(1, math.ceil(resolution[1] / 2) - 12) .. "..." .. packet[3]:sub(math.ceil(resolution[1] / 2) + 12, packet[3]:len()))
					else
						print(packet[3])
					end
				end
				if packet[6] then
					local deps = packet[6]
					textColor(colors.yellow)
					io.write("Zaleznosci: ")
					textColor(colors.gray)
					for i = 1, #deps do
						if i < #deps then io.write(deps[i] .. ", ")
						else print(deps[i]) end
					end
				end
				textColor(colors.yellow)
				io.write("Biblioteka: ")
				textColor(colors.gray)
				if packet[7] then print("Tak") else print("Nie") end
				textColor(colors.yellow)
				io.write("Instrukcja: ")
				textColor(colors.gray)
				if packet[8] then print("Tak") else print("Nie") end
				if packet[10] then
					textColor(colors.magenta)
					print("Archiwum: Tak")
				end
				print()
				return
			end
		end
		io.stderr:write("Nie znaleziono pakietu o podanej nazwie")
	end
end

local function printAppList(archive)
	fetchAppList()
	if appList then
		local page = 1
		local apps = {}
		for _, a in pairs(appList) do
			if not a[10] then
				table.insert(apps, {a[1], a[4]})
			elseif a[10] and archive then
				table.insert(apps, {a[1], a[4], true})
			end
		end
		while true do
			term.clear()
			term.setCursor(1, 1)
			textColor(colors.green)
			io.write("Lista dostępnych pakietów     ")
			textColor(colors.orange)
			print("strona " .. tostring(page))
			for i = 1, resolution[2] - 3 do
				if i + (page - 1) * (resolution[2] - 3) > #apps then break end
				local app = apps[i + ((resolution[2] - 3) * (page - 1))]
				textColor(app[3] and colors.magenta or colors.yellow)
				io.write(i .. ". " .. app[1])
				textColor(colors.gray)
				print(" - " .. app[2])
			end
			term.setCursor(1, resolution[2])
			textColor(colors.green)
			term.write("Q - wyjście z listy ")
			if page > 1 then io.write(" [Left] - poprzednia strona") end
			if #apps > (resolution[2] * page) then io.write("[Right] - nastepna strona") end
			local ev = {event.pull("key_down")}
			if ev[4] == keyboard.keys.q then
				return
			elseif ev[4] == keyboard.keys.left and #apps > ((resolution[2] - 3) * page) then
				page = page + 1
			elseif ev[4] == keyboard.keys.right and page > 1 then
				page = page - 1
			end
		end
	else
		io.stderr:write("Nie udało się pobrać listy aplikacji.")
	end
end

local function clearAfterFail(tab)
	for _, appl in pairs(tab) do
		fs.remove(appl)
	end
end

local generateList = nil
generateList = function(appData, deps, list)
	--[[
	list = {
		{
			[1] = nazwa aplikacji:string
			[2] = adres pobierania:string,
			[3] = folder:string,
			[4] = nazwa pliku:string,
			[5] = wersja:string
			[6] = nazwa instrukcji:string or nil
		}
		...
	}
	]]
	if not list then list = {} end
	local found = false
	for _, b in pairs(list) do
		if b[1] == appData[1] then
			found = true
			break
		end
	end
	if not found then
		local saveLocation = appData[7] and "/lib/" or "/usr/bin/"
		if appData[9] then
			saveLocation = saveLocation .. appData[9]
		else
			saveLocation = saveLocation .. appData[1] .. ".lua"
		end
		local segments = fs.segments(saveLocation)
		local dir = ""
		for i = 1, #segments - 1 do
			dir = dir .. "/" .. segments[i]
		end
		dir = dir .. "/"
		local add = {
			[1] = appData[1],
			[2] = appData[3],
			[3] = dir,
			[4] = segments[#segments],
			[5] = appData[2],
			[6] = appData[8]
		}
		table.insert(list, add)
	end
	if deps then
		for _, b in pairs(appData[6] or {}) do
			local dependency = getAppData(b)
			if not dependency then
				io.stderr:write("Nie znaleziono zależności " .. b)
				return
			end
			if not generateList(dependency, true, list) then return end
		end
	end
	return list
end

local function installApp(appName, force_install, disable_dep_install)
	textColor(colors.blue)
	print("\nRozpoczynanie instalacji...")
	os.sleep(0.2)
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	fetchAppList()
	if appList then
		application = getAppData(appName)
		if not application then
			textColor(colors.red)
			term.write("\nBłąd: brak aplikacji o podanej nazwie")
			return
		end
		ok()
		term.write("\nGenerowanie listy instalacyjnej...   ")
		local list = generateList(application, not disable_dep_install)
		if not list then
			textColor(colors.yellow)
			term.write("\nInstalacja przerwana.")
			return
		end
		ok()
		term.write("\nSprawdzanie katalogów...   ")
		for _, t in pairs(list) do
			if not fs.isDirectory(t[3]) then
				local s, e = fs.makeDirectory(t[3])
				if not s then
					io.stderr:write("Nie można utworzyć katalogu " .. t[3] .. ": " .. e)
					textColor(colors.yellow)
					term.write("\nInstalacja przerwana.")
					return
				end
			end
		end
		ok()
		term.write("\nKopiowanie plików:")
		textColor(colors.silver)
		for _, t in pairs(list) do
			local filename = fs.concat(t[3], t[4])
			term.write("\n" .. filename)
			if fs.exists(filename) then
				local localfile = loadfile(filename)
				local version = localfile and localfile("version_check") or ""
				if version == t[5] and not force_install then
					io.stderr:write("\nAplikacja jest już zainstalowana!")
					textColor(colors.yellow)
					term.write("\nInstalacja przerwana.")
					return
				end
			end
			local output = io.open(filename, "w")
			if not output then
				io.stderr:write("\nNie można utworzyć pliku " .. t[4])
				if not force_install then
					io.stderr:write("\nInstalacja nie powiodła się!")
					output:close()
					clearAfterFail(installed)
				end
			end
			table.insert(installed, filename)
			local source = getApp(t[2])
			if source then
				output:write(source)
				output:close()
			else
				io.stderr:write("\nNie udało się pobrać pliku " .. t[4])
				if not force_install then
					io.stderr:write("\nInstalacja nie powiodła się!")
					output:close()
					clearAfterFail(installed)
					return
				else
					output:close()
					fs.remove(filename)
				end
			end
		end
		local manuals = {}
		for _, t in pairs(list) do
			if t[5] then
				table.insert(manuals, t[6])
			end
		end
		if #manuals > 0 then
			local manaddr = "https://bitbucket.org/Aranthor/oc_equipment/raw/master/man/"
			local mandir = "/usr/man/"
			textColor(colors.cyan)
			term.write("\nPrzygotowywanie instrukcji...")
			textColor(colors.silver)
			for _, s in pairs(manuals) do
				term.write("\n" .. s)
				local mansource = getapp(manaddr .. s)
				if mansource then
					local manfile = io.open(fs.concat(mandir, s), "w")
					if manfile then
						manfile:write(mansource)
						manfile:close()
					else
						io.stderr:write("\nNie udało się utworzyć pliku instrukcji.")
						fs.remove(fs.concat(mandir, s))
					end
				else
					io.stderr:write("\nNie odnaleziono instrukcji.")
				end
			end
		end
		textColor(colors.green)
		term.write("\nInstalacja zakończona sukcesem!")
	else
		io.stderr:write("Nie udało się pobrać listy aplikacji.")
		return
	end
end

local function uninstallApp(appName, deps)
	if not appName then
		io.stderr:write("Nie podano nazwy aplikacji.")
		return
	end
	local name = appName
	if string.sub(appName, string.len(appName) - 4, string.len(appName)) == ".lua" then
		name = string.sub(appName, 1, string.len(apppName) - 4)
	end
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	fetchAppList()
	if not appList then
		textColor(colors.red)
		term.write("Błąd\nNie udało się pobrać listy aplikacji.")
		textColor(colors.yellow)
		term.write("\nDeinstalacja przerwana.")
		return
	end
	local application = getAppData(name)
	if not application then
		textColor(colors.red)
		term.write("Błąd\nNie znaleziono aplikacji o podanej nazwie.")
		textColor(colors.yellow)
		term.write("\nDeinstalacja przerwana.")
		return
	end
	ok()
	term.write("\nGenerowanie listy deinstalacyjnej...   ")
	local list  = generateList(application, deps)
	if not list then
		textColor(colors.yellow)
		term.write("\nInstalacja przerwana.")
		return
	end
	ok()
	term.write("\nUsuwanie aplikacji:")
	textColor(colors.silver)
	for _, t in pairs(list) do
		local filename = fs.concat(t[3], t[4])
		term.write("\n" .. filename)
		if fs.exists(filename) then
			local s, e = fs.remove(filename)
			if not s then
				io.stderr:write("\nBłąd: " .. e)
			end
		end
	end
	textColor(colors.green)
	print("\nDeinstalacja zakończona pomyślnie.")
end

local function main()
	if args[1] == "list" then
		printAppList(options.r)
	elseif args[1] == "info" then
		packetInfo(args[2])
	elseif args[1] == "install" then
		installApp(args[2], options.f, options.n)
	elseif args[1] == "remove" then
		uninstallApp(args[2], options.d)
	elseif args[1] == "test" then
		testRepo(args[2])
	else
		usage()
	end
end

local pprev = gpu.getForeground()
main()
gpu.setForeground(pprev)