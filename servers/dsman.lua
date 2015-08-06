-- #################################################
-- #        dsman - menedżer serwera danych        #
-- #                                               #
-- #  08.2015                       by: Aranthor   #
-- #################################################

local version = "1.0"

local component = require("component")
local fs = require("filesystem")
local dsapi = require("dsapi")

local args, options = require("shell").parse(...)
if args[1] == "version_check" then return version end

local dtsrvPort = 0

local function saveConfig()
	local f = io.open("/etc/dsman.cfg", "w")
	f:write(tostring(dtsrvPort))
	f:close()
end

local function loadConfig()
	if fs.exists("/etc/dsman.cfg") then
		local f = io.open("/etc/dsman.cfg", "r")
		local port = tonumber(f:read())
		f:close()
		if not port then
			io.stderr:write("Port zapisany w pliku konfiguracyjnym nie jest liczbą, usuwanie pliku")
			fs.remove("/etc/dsman.cfg")
		elseif port < 10000 or port > 60000 then
			io.stderr:write("Port zapisany w pliku konfiguracyjnym jest nieprawidłowy, usuwanie pliku")
			fs.remove("/etc/dsman.cfg")
		else
			dtsrvPort = port
		end
	end
end

local function usage()
	print("Menedżer serwera danych, wersja " .. version)
	print("Użycie programu:")
	print("  dsman send <ścieżka> <plik> [-s] - zapisuje wybrany plik do wybranej ścieżki na serwerze. Opcja -s pobiera ciąg znaków zamiast pliku")
	print("  dsman get <ścieżka> [plik] - pobiera plik z wybranej ścieżki na serwerze i zapisuje go do pliku. Gdy plik nie jest podany, pobrana zawartość jest wyświetlana na ekranie")
	print("  dsman remove <ścieżka> - usuwa plik z serwera")
	print("  dsman list <ścieżka> - wyświetla wszystkie elementy w podanym kalalogu na serwerze")
	print("  dsman port [port] - wyświetla lub zmienia port serwera danych")
end

local function send(path, source, isStream)
	if path and source then
		local content = ""
		if isStream then
			content = source
		else
			local f = io.open(source, "r")
			if f then
				content = f:read("*a")
				f:close()
			else
				io.stderr:write("Podany plik nie został odnaleziony")
				return
			end
		end
		local status, code = dsapi.write(dtsrvPort, path, content)
		if status then
			print((isStream and "Ciąg znaków" or "Plik") .. " został zapisany na serwerze")
		else
			print("Zapis nie powiódł się: " .. dsapi.translateCode(code) .. "(" .. tostring(code) .. ")")
		end
	else
		io.stderr:write("Ścieżka i/lub źródło nie mogą być puste")
	end
end

local function get(path, destination)
	if path then
		local status, content = dsapi.get(dtsrvPort, path)
		if status then
			if destination then
				local f = io.open(destination, "w")
				f:write(content)
				f:close()
				print("Zawartość została zapisana do pliku " .. destination)
			else
				print(content)
			end
		else
			io.stderr:write("Pobieranie nie powiodło się: " .. dsapi.translateCode(content) .. "(" .. tostring(content) .. ")")
		end
	else
		io.stderr:write("Ścieżka nie może być pusta")
	end
end

local function remove(path)
	if path then
		local status, code = dsapi.remove(dtsrvPort, path)
		if status then
			print("Zawartość została usunięta")
		else
			io.stderr:write("Usuwanie nie powiodło się: " .. dsapi.translateCode(code) .. "(" .. tostring(code) .. ")")
		end
	else
		io.stderr:write("Ścieżka nie może być pusta")
	end
end

local function list(path)
	if path then
		local status, iterator = dsapi.list(dtsrvPort, path)
		if status then
			print("Lista elementów w " .. path .. ":")
			print("  NAZWA             TYP     ROZMIAR")
			for name, size in iterator do
				print(string.format("  %-17s %-8s %-.2f KB", name, size == -1 and "folder" or "plik", size ~= -1 and size / 1024 or 0))
			end
		else
			io.stderr:write("Nie udało się pobrać listy: " .. dsapi.translateCode(iterator) .. "(" .. tostring(iterator) .. ")")
		end
	else
		io.stderr:write("Ścieżka nie może być pusta")
	end
end

local function port(port)
	local cp = tonumber(port)
	if not port then
		print("Port serwera: " .. tostring(dtsrvPort))
	elseif not cp then
		io.stderr:write("Podany port nie jest liczbą")
	elseif cp < 10000 or cp > 60000 then
		io.stderr:write("Podany port jest poza zakresem (10000 - 60000)")
	else
		local status = dsapi.echo(cp)
		if status then
			dtsrvPort = cp
			saveConfig()
			print("Port został zmieniony")
		else
			io.stderr:write("Brak serwera pod podanym portem")
		end
	end
end

local function main()
	if dtsrvPort == 0 and args[1] ~= "port" then
		io.stderr:write("Nie podano portu serwera. Aby dodać port, użyj 'dsman port <port>")
	else
		if args[1] == "send" then
			send(args[2], args[3], options.s)
		elseif args[1] == "get" then
			get(args[2], args[3])
		elseif args[1] == "remove" then
			remove(args[2])
		elseif args[1] == "list" then
			list(args[2])
		elseif args[1] == "port" then
			port(args[2])
		else
			usage()
		end
	end
end

loadConfig()
main()