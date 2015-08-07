--[[Struktura pliku z lista aplikacji:
	{Nazwa aplikacji: string,
	wersja: string,
	Adres pobierania: string,
	opis aplikacji: string,
	autor: string,
	zaleznosci: table,
	czy aplikacja jest biblioteka: bool,
	nazwa pliku manual: string,
	zmodyfikowana nazwa aplikacji: string lub nil
	archiwum: bool}
]]

local wersja = "0.2.0"

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

appList = nil

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
	if gpu.maxDepth() > 1 then
		return gpu.setForeground(color)
	end
end

local function usage()
	local prev = nil
	prev = textColor(colors.green)
	print("ARPM - Aranthor's Repository Package Manager     wersja " .. wersja)
	textColor(colors.cyan)
	print("Użycie:")
	textColor(colors.orange)
	term.write("  arpm install <pakiet> [-f]")
	textColor(colors.silver)
	print("  - Instaluje nowy pakiet. Użycie opcji -f wymusza nadpisanie starej aplikacji.")
	textColor(colors.orange)
	term.write("  arpm info <pakiet>")
	textColor(colors.silver)
	print("  - Wyświetla informacje o wybranym pakiecie")
	textColor(colors.orange)
	term.write("  arpm list [-r]")
	textColor(colors.silver)
	print("  - Wyświetla liste dostępnych pakietów. Użycie opcji -r wyświetla również pakiety archiwalne")
	textColor(colors.orange)
	term.write("  arpm update <pakiet> [-f]")
	textColor(colors.silver)
	print("  - Aktualizuje wybrany pakiet. Użycie opcji -f wymusza uaktualnienie.")
	textColor(colors.orange)
	term.write("  arpm uninstall <pakiet> [-d]")
	textColor(colors.silver)
	print("  - Odinstalowuje wybrany pakiet. Użycie opcji -d powoduje odinstalowanie zależnosci")
	textColor(prev)
end

local function getContent(url)
	local sContent = ""
	local result, response = pcall(internet.request, url)
	if not result then
		return nil
	end
	for chunk in response do
		sContent = sContent..chunk
	end
	return sContent
end

local function getAppList()
	--[[local f = io.open("/usr/bin/setup-list", "r")
	local ss, ee = serial.unserialize(f:read("*a"))
	f:close()
	if not ss then
		error(tostring(ss) .. "   " .. ee)
	end
	appList = ss]]
	if not appList then
		local resp = getContent("https://bitbucket.org/Aranthor/oc_equipment/raw/master/installer/setup-list")
		if resp then
			local ss, ee = serial.unserialize(resp)
			if not ss then
				error(tostring(ss) .. "   " .. ee)
			end
			appList = ss
		else
			io.stderr:write("Nie można polączyć się z Internetem")
		end
	end
end

local function getApp(url)
	return getContent(url)
end

local function getAppData(appName)
	for _,nm in pairs(appList) do
		if nm[1] == appName then return nm end
	end
	return nil
end

local function packetInfo(packetName)
	if not packetName or packetName == "" then
		io.stderr:write("Nie podano nazwy pakietu")
		return
	end
	getAppList()
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
	getAppList()
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
			elseif ev[4] == keybaord.keys.left and #apps > ((resolution[2] - 3) * page) then
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

local function installApp(appName, force_install)
	textColor(colors.blue)
	print("\nRozpoczynanie instalacji...")
	os.sleep(0.2)
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	getAppList()
	if appList then
		installed = {}
		application = nil
		for _, app in pairs(appList) do
			if app[1] == appName then
				application = app
				break
			end
		end
		if not application then
			textColor(colors.red)
			term.write("\nBlad: brak aplikacji o podanej nazwie")
			return
		end
		textColor(colors.green)
		term.write("OK")
		textColor(colors.cyan)
		term.write("\nSprawdzanie katalogu docelowego...   ")
		dir = "/usr/bin"
		if application[7] then dir = "/lib" end
		if not fs.isDirectory(dir) then fs.makeDirectory(dir) end
		nam = application[9] or application[1] .. ".lua"
		textColor(colors.green)
		term.write("OK")
		textColor(colors.cyan)
		term.write("\nKopiowanie plików:")
		textColor(colors.silver)
		term.write("\n" .. fs.concat(dir, nam))
		if fs.exists(shell.resolve(fs.concat(dir, nam))) and not force_install then
			io.stderr:write("\nAplikacja jest juz zainstalowana!")
			textColor(colors.yellow)
			term.write("\nInstalacja przerwana.")
			return
		end
		plikApp = io.open(fs.concat(dir, nam), "w")
		table.insert(installed, fs.concat(dir, nam))
		if plikApp then
			appCode = getApp(application[3])
			if appCode then
				plikApp:write(appCode)
				plikApp:close()
			else
				io.stderr:write("\nNie udało się pobrać pliku " .. nam)
				if not force_install then
					io.stderr:write("\nInstalacja nie powiodła się!")
					plikApp:close()
					clearAfterFail(installed)
					return
				else
					plikApp:close()
					fs.remove(fs.concat(dir, nam))
				end
			end
		else
			io.stderr:write("\nNie można utworzyć pliku " .. nam)
			if not force_install then
				io.stderr:write("\nInstalacja nie powiodła się!")
				plikApp:close()
				clearAfterFail(installed)
				return
			else
				plikApp:close()
				fs.remove(fs.concat(dir, nam))
			end
		end
		if application[6] then
			dependencies = application[6]
			for _, dep in pairs(dependencies) do
				ddata = getAppData(dep)
				if not ddata then
					clearAfterFail(installed)
					textColor(colors.red)
					term.write("\nNie można odnaleźć zależnosći o nazwie " .. dep .. " w bazie")
					term.write("\nInstalacja przerwana.")
					return
				end
				depDir = dir
				if ddata[7] then
					if ddata[7] then depDir = "/lib" end
				end
				fileName = ddata[9] or ddata[1]..".lua"
				term.write("\n" .. fs.concat(depDir, fileName))
				depCode = getApp(ddata[3])
				plikDep = io.open(fs.concat(depDir, fileName),"w")
				if depCode then
					table.insert(installed, fs.concat(depDir, fileName))
					if plikDep then
						plikDep:write(depCode)
						plikDep:close()
					else
						io.stderr:write("\nNie można utworzyć pliku " .. fileName)
						if not force_install then
							io.stderr:write("\nInstalacja nie powiodla się!")
							plikDep:close()
							clearAfterFail(installed)
							return
						else
							plikDep:close()
							fs.remove(fs.concat(depDir, fileName))
						end
					end
				else
					io.stderr:write("\nNie udało się pobrać pliku " .. dep .. ".lua")
					if not force_install then
						io.stderr:write("\nInstalacja nie powiodła się!")
						plikDep:close()
						clearAfterFail(installed)
						return
					else
						plikDep:close()
						fs.remove(fs.concat(depDir, dep .. ".lua"))
					end
				end
			end
		end
		if application[8] then
			textColor(colors.cyan)
			term.write("\nPrzygotowywanie instrukcji...")
			manCode = getApp(application[8])
			if manCode then
				plikMan = io.open("/usr/man/" .. application[8], "w")
				if plikMan then
					plikMan:write(manCode)
					plikMan:close()
				else
					textColor(colors.yellow)
					term.write("\nNie udało się utworzyć pliku instrukcji.")
					plikMan:close()
					fs.remove("/usr/man/" .. application[8])
				end
			else
				textColor(colors.yellow)
				term.write("\nNie udało się pobrać instrukcji.")
			end
		end
		textColor(colors.green)
		term.write("\nInstalacja zakończona sukcesem!")
	else
		io.stderr:write("Nie udało się pobrać listy aplikacji.")
		return
	end
end

local function doUpdate(application, force)
	local directory = application[7] and "/lib" or "/usr/bin"
	local appName = application[9] or application[1] .. ".lua"
	textColor(colors.green)
	term.write("\nAktualizowanie aplikacji " .. application[1] .. "...")
	if fs.exists(fs.concat(directory, appName)) then
		local appVersion = loadfile(fs.concat(directory, appName))
		if appVersion("version_check") == application[2] and not force then
			textColor(colors.yellow)
			term.write("\nAplikacja jest juz aktualna. Instalacja przerwana.")
			return
		end
		textColor(colors.silver)
		term.write("\n" .. fs.concat(directory, appName))
		local plikApp = io.open(fs.concat(directory, appName), "w")
		if plikApp then
			local appCode = getApp(application[3])
			if appCode then
				plikApp:write(appCode)
				plikApp:close()
				local dependencies = application[6]
				if dependencies then
					textColor(colors.cyan)
					term.write("\nAktualizowanie zależności...")
					textColor(colors.silver)
					for _, dep in pairs(dependencies) do
						for _, app2 in pairs(appList) do
							if app2[1] == dep then
								depCode = getApp(app2[3])
								if depCode then
									local subdir = app2[7] and "/lib" or "/usr/bin"
									local subname = app2[9] or app2[1] .. ".lua"
									term.write("\n" .. fs.concat(subdir, subname))
									plikDep = io.open(fs.concat(subdir, subname), "w")
									plikDep:write(depCode)
									plikDep:close()
								end
							end
						end
					end
					textColor(colors.cyan)
					term.write("\nAktualizowanie instrukcji...")
					manCode = getApp(application[8])
					if manCode then
						plikMan = io.open("/usr/man/" .. application[8], "w")
						if plikMan then
							plikMan:write(manCode)
							plikMan:close()
						else
							textColor(colors.yellow)
							term.write("\nNie udało się zaktualizować instrukcji.")
							plikMan:close()
							fs.remove("/usr/man/" .. application[8])
						end
					else
						textColor(colors.yellow)
						term.write("\nNie udało się zaktualizować instrukcji.")
					end
				end
			else
				plikApp:close()
				fs.remove(fs.concat(directory, appFile))
				textColor(colors.red)
				term.write("\nNie udało się pobrać kodu aplikacji z repozytorium")
			end
		else
			plikApp:close()
			fs.remove(fs.concat(directory, appFile))
			textColor(colors.red)
			term.write("\nNie udało się otworzyć pliku aplikacji.")
			return
		end
		textColor(colors.green)
		term.write("\nAktualizacja zakończona sukcesem.")
	else
		textColor(colors.red)
		term.write("\nAplikacja nie jest zainstalowana na komputerze.")
	end
end

local function updateApp(appName, force)
	if string.sub(appName, string.len(appName) - 3, string.len(appName)) == ".lua" then
		appName = string.sub(appName, 1, string.len(apppName) - 4)
	end
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	getAppList()
	if appList then
		if not appName then
			io.stderr:write("Nie podano nazwy aplikacji")
		else
			term.write("\nSzukanie aplikacji w repozytorium...")
			for _, application in pairs(appList) do
				if application[1] == appName or application[9] == appName then
					doUpdate(application, force)
					return
				end
			end
			textColor(colors.red)
			term.write("Repozytorium nie zawiera aplikacji o podanej nazwie.")
		end
	else
		io.stderr:write("Niepowodzenie\nNie można pobrać listy aplikacji. Aktualizacja przerwana")
	end
end

local function doUninstall(application)
	local fname = application[9] or application[1] .. ".lua"
	local path = application[7] and "/lib/" or "/usr/bin/"
	return fs.remove(path .. fname)
end

local function uninstallApp(appName, deps)
	local name = appName
	if string.sub(appName, string.len(appName) - 3, string.len(appName)) == ".lua" then
		name = string.sub(appName, 1, string.len(apppName) - 4)
	end
	textColor(colors.cyan)
	print("\nPobieranie listy aplikacji...   ")
	getAppList()
	if appList then
		for _, application in pairs(appList) do
			if application[1] == name then
				textColor(colors.green)
				print("Odinstalowywanie aplikacji " .. name .. "...")
				if not doUninstall(application) then
					textColor(colors.red)
					print("Nie znaleziono pliku aplikacji. Deinstalacja przerwana.")
					return
				end
				if deps then
					textColor(colors.cyan)
					print("Usuwanie zależności:")
					textColor(color.gray)
					for _, dep in pairs(application[6] or {}) do
						print(dep)
						local data = getAppData(dep)
						if data then
							if not doUninstall(data) then
								textColor(colors.orange)
								print("Nie znaleziono pliku zależności")
							end
						else
							textColor(colors.orange)
							print("Zależność nie została odnaleziona na serwerze")
						end
					end	
				end
				textColor(colors.green)
				print("\nDeinstalacja zakończona pomyślnie")
				return
			end
		end
		io.stderr:write("Nie znaleziono aplikacji o podanej nazwie")
	else
		io.stderr:write("Nie udało się pobrać listy aplikacji. Deinstalacja przerwana.")
	end
end

local function main()
	if args[1] == "info" then
		packetInfo(args[2])
	elseif args[1] == "list" then
		printAppList(options.r)
	elseif args[1] == "update" then
		updateApp(args[2], options.f)
	elseif args[1] == "install" then
		installApp(args[2], options.f)
	elseif args[1] == "uninstall" then
		uninstallApp(args[2], options.d)
	else
		usage()
	end
end

local pprev = gpu.getForeground()
main()
gpu.setForeground(pprev)