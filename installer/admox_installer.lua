--[[Plik z lista aplikacji:
	Kazda linijka bedzie zawierala tabele z nastepujacymi danymi:
	{Nazwa aplikacji: string, wersja: string, Adres pobierania: string, opis aplikacji: string, autor: string, zależności: table, nil, nazwa pliku manual: string}
]]

local wersja = "0.1.0"

local component = require("component")

if not component.isAvailable("internet") then
	io.stderr:write("Ta aplikacja wymaga zainstalowanej karty internetowej")
	return
end

local inter2 = component.internet
local gpu = component.gpu
local internet = require("internet")

if not inter2.isHttpEnabled() then
	io.stderr:write("Polaczenia z Internetem są obecnie zablokowane.")
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

local colors = 
{
	white=0xffffff,
	orange=0xffa500,
	magenta=0xff00ff,
	yellow=0xffff00,
	red=0xff0000,
	green=0x00ff00,
	blue=0x0000ff,
	cyan=0x00ffff,
	brown=0xa52a2a,
	gray=0xc9c9c9,
	silver=0xe0e0de,
	black=0x000000
}

local function textColor(color)
	if gpu.maxDepth() > 1 then
		return gpu.setForeground(color)
	end
end

local function usage()
	local prev = nil
	prev = textColor(colors.green)
	print("Menadżer pakietów Admox   wersja "..wersja)
	textColor(colors.cyan)
	print("Użycie:")
	textColor(colors.orange)
	term.write("  admox_installer info <pakiet>")
	textColor(colors.silver)
	print("  - Wyświetla informacje o wybranym pakiecie")
	textColor(colors.orange)
	term.write("  admox_installer list")
	textColor(colors.silver)
	print("  - Wyświetla listę dostępnych pakietów")
	textColor(colors.orange)
	term.write("  admox_installer update <nazwa_pakietu> [<ścieżka>]")
	textColor(colors.silver)
	print("  - Aktualizuje wybrany pakiet lub wszystkie zainstalowane, gdy nie został wybrany żaden. Gdy nie jest podana ścieżka do folderu z aplikacją, przeszukiwany jest katalog domyślny (/usr/bin).")
	textColor(colors.orange)
	term.write("  admox_installer update [<ścieżka>] -a")
	textColor(colors.silver)
	print("  - Aktualizuje wszystkie zainstalowane aplikacje. Gdy nie jest podana ścieżka, przeszukiwany jest katalog domyślny (/usr/bin)")
	textColor(colors.orange)
	term.write("  admox_installer install <nazwa pakietu> [<ściezka>]")
	textColor(colors.silver)
	print("  - Instaluje nowy pakiet w wybranej ścieżce. Gdy nie jest podana żadna, instaluje w domyślnej. Opcja f wymusza nadpisanie starej aplikacji.")
	textColor(prev)
end

local function getAppList()
	local result, appsFunction = pcall(internet.request,"http://pastebin.com/raw.php?i=deQNZ8vE")
	if result then
		apps = appsFunction()
		return serial.unserialize(tostring(apps))
	else
		return nil
	end
end

local function getApp(address)
	local appString = ""
	local result, appFunction = pcall(internet.request, address)
	local result, reason = pcall(function()
		for chunk in appFunction do
			appString = appString..chunk
		end
	end)
	if result then
		return appString
	else
		return nil
	end
end

local function packetInfo(packetName)
	if packetName == nil then
		io.stderr:write("Nie znaleziono pakietu o podanej nazwie")
		return
	end
	apps = getAppList()
	if apps==nil then
		io.stderr:write("Brak danych odebranych z serwera!")
	else
		for _,packet in pairs(apps) do
			if type(packet)=="table" and packet[1]==packetName then
				print("\n>> Informacje o pakiecie <<")
				print("\nNazwa pakietu: "..packet[1])
				print("Aktualna wersja: "..packet[2])
				print("Adres pobierania: "..string.sub(packet[3],1,27).."(...)"..string.sub(packet[3],string.len(packet[3])-8, string.len(packet[3])))
				print("Opis aplikacji: "..packet[4])
				print("Autor: "..packet[5])
				if packet[6]~=nil then
					depen = packet[6]
					term.write("Zależności: ")
					for _,name in pairs(depen) do
						term.write(name..", ")
					end
				end
				print("")
				return
			end
		end
		io.stderr:write("Nie znaleziono pakietu o podanej nazwie")
	end
end

local function printAppList()
	apps = getAppList()
	if apps~=nil then
		local page = 1
		while true do
			term.clear()
			term.setCursor(1,1)
			print("Lista dostępnych pakietów  --  strona "..tostring(page))
			for i=1, resolution[2]-2 do
				if i>#apps then break end
				app = apps[i+(resolution[2]*(page-1))]
				print(i..". "..app[1].." - "..app[4])
			end
			term.setCursor(1,resolution[2])
			term.write("Q - wyjście z listy ")
			if page>1 then term.write(" [Left] - poprzednia strona") end
			if #apps>(resolution[2]*page) then term.write("[Right] - następna strona") end

			local ev = {event.pull("key_down")}
			if ev[4] == keyboard.keys.q then
				return
			elseif ev[4] == keybaord.keys.left and #apps>(resolution[2]*page) then
				page = page + 1
			elseif ev[4] == keyboard.keys.right and page>1 then
				page = page - 1
			end
		end
		term.clear()
		term.serCursor(1,1)
	else
		io.stderr:write("Nie udało się pobrać listy aplikacji.")
	end
end

local function clearAfterFail(tab)
	for _,appl in pairs(tab) do
		fs.remove(appl)
	end
end

local function installApp(appName, directory,force_install)
	if force_install==nil then force_install = false end
	textColor(colors.blue)
	print("\nRozpoczynanie instalacji...")
	os.sleep(0.2)
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	apps = getAppList()
	if apps ~= nil then
		installed = {}
		application = nil
		for _,app in pairs(apps) do
			if app[1] == appName then
				application = app
				break
			end
		end
		if application==nil then
			textColor(colors.red)
			term.write("\nBłąd: brak aplikacji o podanej nazwie")
			return
		end
		textColor(colors.green)
		term.write("OK")
		textColor(colors.cyan)
		term.write("\nSprawdzanie katalogu docelowego...   ")
		dir = directory or "/usr/bin"
		if not fs.isDirectory(dir) then
			textColor(colors.red)
			term.write("Błąd: Katalog o nazwie "..dir.." nie istnieje!")
			return
		end
		textColor(colors.green)
		term.write("OK")
		textColor(colors.cyan)
		term.write("\nKopiowanie plików:")
		textColor(colors.silver)
		term.write("\n"..fs.concat(dir, application[1]..".lua"))
		if fs.exists(shell.resolve(application[1]..".lua")) then
			io.stderr:write("\nAplikacja jest już zainstalowana!")
			textColor(colors.yellow)
			term.write("\nInstalacja przerwana.")
			return
		end
		plikApp = io.open(fs.concat(dir, application[1]..".lua"),"w")
		table.insert(installed,application[1]..".lua")
		if plikApp~=nil then
			appCode = getApp(application[3])
			if appCode~=nil then
				plikApp:write(appCode)
				plikApp:close()
			else
				io.stderr:write("\nNie udało się pobrać pliku "..application[1]..".lua")
				if not force_install then
					io.stderr:write("\nInstalacja nie powiodła się!")
					plikApp:close()
					clearAfterFail()
					return
				else
					plikApp:close()
					fs.remove(application[1]..".lua")
				end
			end
		else
			io.stderr:write("\nNie można utworzyć pliku "..application[1]..".lua")
			if not force_install then
				io.stderr:write("\nInstalacja nie powiodła się!")
				plikApp:close()
				clearAfterFail()
				return
			else
				plikApp:close()
				fs.remove(application[1]..".lua")
			end
		end
		if application[6]~=nil then
			dependencies = application[6]
			for _,dep in pairs(dependencies) do
				term.write("\n"..fs.concat(dir,dep..".lua"))
				depCode = getApp(dep)
				if depCode~=nil then
					plikDep = io.open(dep..".lua","w")
					table.insert(installed, dep..".lua")
					if plikDep~=nil then
						plikDep:write(depCode)
						plikDep:close()
					else
						io.stderr:write("\nNie można utworzyć pliku "..dep..".lua")
						if not force_install then
							io.stderr:write("\nInstalacja nie powiodła się!")
							plikDep:close()
							clearAfterFail()
							return
						else
							plikDep:close()
							fs.remove(dep..".lua")
						end
					end
				else
					io.stderr:write("\nNie udało się pobrać pliku "..dep..".lua")
					if not force_install then
						io.stderr:write("\nInstalacja nie powiodła się!")
						plikDep:close()
						clearAfterFail()
						return
					else
						plikDep:close()
						fs.remove(dep..".lua")
					end
				end
			end
		end
		if application[8]~=nil then
			textColor(colors.cyan)
			term.write("\nPrzygotowywanie instrukcji...")
			manCode = getApp(application[8])
			if manCode~=nil then
				plikMan = io.open("/usr/man/"..application[8],"w")
				if plikMan~=nil then
					plikMan:write(manCode)
					plikMan:close()
				else
					textColor(colors.yellow)
					term.write("\nNie udało się utworzyć pliku instrukcji.")
					plikMan:close()
					fs.remove("/usr/man/"..application[8])
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

local function updateApp(appName,directory)
	if string.sub(appName, string.len(appName)-3, string.len(appName)) == ".lua" then
		appName = string.sub(appName, 1, string.len(apppName)-4)
	end
	textColor(colors.cyan)
	term.write("\nPobieranie listy aplikacji...   ")
	apps = getAppList()
	if apps~=nil then
		if appName == "**all" then
			term.write("\nAktualizowanie aplikacji: ")
			for _,app in pairs(apps) do
				textColor(colors.silver)
				if fs.exists(fs.concat(directory,app[1]..".lua")) then
					sour = loadfile(fs.concat(directory,app[1]..".lua"))
					if sour("version_check") ~= app[2] then
						ccode = getApp(app[3])
						if ccode ~= nil then
							autoFile = io.open(fs.concat(directory,app[1]..".lua"), "w")
							if autoFile~=nil then
								term.write("\n"..fs.concat(directory,app[1]..".lua"))
								autoFile:write(ccode)
								autoFile:close()
							else
								autoFile:close()
								fs.remove(fs.concat(directory,app[1]..".lua"))
							end
						end
						if app[8]~=nil then
							souCode = getApp(ap[8])
							if souCode~=nil then
								souFile = io.open("/usr/man/"..app[1],"w")
								if souFile~=nil then
									souFile:write(souCode)
									souFile:close()
								else
									souFile:close()
									fs.remove("/usr/man/"..app[1])
								end
							end
						end
					end
				end
			end
			textColor(colors.green)
			term.write("\nAktualizacja zakończona.")
			return
		else
			term.write("\nSzukanie aplikacji w repozytorium...")
			for _,application in pairs(apps) do
				if application[1] == appName then
					term.write("\nAktualizowanie aplikacji...")
					if fs.exists(fs.concat(directory, appName..".lua")) then
						appVersion = loadfile(fs.concat(directory, appName..".lua"))
						if appVersion("version_check")==application[2] then
							textColor(colors.green)
							term.write("\nAplikacja jest już aktualna. Instalacja przerwana.")
							return
						end
						textColor(colors.silver)
						term.write("\n"..fs.concat(directory, appName..".lua"))
						plikApp = io.open(fs.concat(directory, appName..".lua"), "w")
						if plikApp~=nil then
							appCode = getApp(application[3])
							if appCode~=nil then
								plikApp:write(appCode)
								plikApp:close()
								dependencies = application[6]
								if dependencies~=nil then
									textColor(colors.cyan)
									term.write("\nAktualizowanie zależności...")
									teexColor(colors.silver)
									for _,dep in pairs(dependencies) do
										for _, app2 in pairs(apps) do
											if app2[1] == dep then
												depCode = getApp(app2[3])
												if depCode~=nil then
													term.write("\n"..fs.concat(directory,app2[1]))
													plikDep = io.open(fs.concat(directory,app2[1]))
													plikDep:write(depCode)
													plikDep:close()
												end
											end
										end
									end
									textColor(colors.cyan)
									term.write("\nAktualizowanie instrukcji...")
									manCode = getApp(application[8])
									if manCode~=nil then
										plikMan = io.open("/usr/man/"..application[8],"w")
										if plikMan~=nil then
											plikMan:write(manCode)
											plikMan:close()
										else
											textColor(colors.yellow)
											term.write("\nNie udało się zaktualizować instrukcji.")
											plikMan:close()
											fs.remove("/usr/man/"..application[8])
										end
									else
										textColor(colors.yellow)
										term.write("\nNie udało się zaktualizować instrukcji.")
									end
								end
							else
								plikApp:close()
								fs.remove(fs.concat(directory, appName..".lua"))
								textColor(colors.red)
								term.write("\nNie udało się pobrać kodu aplikacji z repozytorium")
								return
							end
						else
							plikApp:close()
							fs.remove(fs.concat(directory, appName..".lua"))
							textColor(colors.red)
							term.write("\nNie udało się otworzyć pliku aplikacji.")
							return
						end
						textColor(colors.green)
						term.write("\nAktualizacja zakończona sukcesem.")
						return
					else
						textColor(colors.red)
						term.write("\nAplikacja nie jest zainstalowana na komputerze.")
						return
					end
					return
				end
			end
			textColor(colors.red)
			term.write("Repozytorium nie zawiera aplikacji o podanej nazwie.")
			return
		end
	else
		textColor(colors.red)
		term.write("Niepowodzenie\nNie można pobrać listy aplikacji. Aktualizacja przerwana")
		return
	end
end

local function main()
	if args[1] == "info" then
		packetInfo(args[2])
	elseif args[1] == "list" then
		printAppList()
	elseif args[1] == "update" and options.a then
		if args[2] == nil then
			updateApp("**all","/usr/bin")
		else
			updateApp("**all",args[2])
		end
	elseif args[1] == "update" then
		if args[3]==nil then
			updateApp(args[2],"/usr/bin")
		else
			updateApp(args[2],args[3])
		end
	elseif args[1] == "install" then
		installApp(args[2],args[3],false)
	else
		usage()
	end
end

local pprev = gpu.getForeground()
main()
gpu.setForeground(pprev)