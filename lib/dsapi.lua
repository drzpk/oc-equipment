-- #################################################
-- ##   API do obsługi serwera danych dataSrv2    ##
-- #                                               #
-- ##  05.2015                     by: Aranthor   ##
-- #################################################

--[[
	## Opis funkcji ##
	dsapi.write(port, path, content)
	Funkcja wysyła nowy plik na serwer. Gdy plik już istnieje, jego
	zawartość jest nadpisywana
		@param port - port serwera
		@param path - ścieżka do pliku
		@param content - zawartość pliku
		
		@return
		true - gdy zapis się powiódł
		false, kod - gdy nie uda się zapisać pliku
		
	dsapi.remove(port, path)
	Funkcja usuwa plik z serwera
		@param port - port serwera
		@param path - ścieżka do pliku
		
		@return
		true - gdy usuwanie się powiodło
		false, kod - gdy usuwanie się nie powiodło
		
	dsapi.get(port, path)
	Funkcja pobiera zawartość pliku z serwera
		@param port - port serwera
		@param path - ścieżka do pliku
		
		@return
		true, <zawartość> - gdy pobieranie się powiodło
		false, kod - gdy wystąpił błąd
		
	dsapi.list(port, path)
	Funkcja zwraca iterator do elementów podanego katalogu
		@param port - port serwera
		@param path - ścieżka do pliku
		
		@return
		true, iterator - gdy otrzymano listę
		false, kod - gdy wystąpił błąd
		Przykład:
			a, b = dsapi.list(modem, port, path)
			if a then
				for name, size in b do
					print(name, "nazwa")
					print(size, "rozmiar")
				end
			else
				print(dsapi.translateCode(b))
			end
		Jeśli rozmiar jest równy -1, obiekt jest folderem
	
	dsapi.echo(port)
	Funkcja sprawdza, czy serwer jest dostępny
		@param port - port serwera
		
		@return
		true - jeśli serwer jest dostępny
		false - jeśli nie można nawiązać połączenia z serwerem
]]

local hdp = require("hdp")
local serial = require("serialization")

local wersja = "1.1"

local aa, bb = require("shell").parse(...)
if aa[1] == "version_check" then return wersja end

-- Czas, po którym połączenie jest zrywane
local timeout = 2

-- Zapytania do serwera
local reqCode = {
	file = 0x01, --@param:(ścieżka, zawartość)
	get  = 0x02, --@param:(ścieżka)
	list = 0x03, --@param:(ścieżka)
	echo = 0x04
}

-- Kody odpowiedzi serwera wraz z opisem
local respCode = {
	success = {0x00, "czynnosc powiodla sie"}, -- zadana czynność powiodła się
	failed = {0x01, "wystapil nieznany blad"}, -- nieznany błąd
	nomem = {0x02, "za malo pamieci na serwerze"}, -- za mało miejsca na serwerze
	notfound = {0x03, "element nie zostal odnaleziony"}, -- nie znaleziono pliku lub folderu
	badreq = {0x04, "bledne zapytanie"}, -- zapytanie jest niekompletne lub nie istnieje
	echo = {0x10, "echo"},
}

local dsapi = {}

function getPort()
	local localPort = 0
	repeat
		localPort = math.random(10000, 65000)
	until localPort ~= port and not require("component").modem.isOpen(localPort)
	return localPort
end

function dsapi.write(port, path, content)
	local localPort = getPort()
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.file, path, content}))
	if status then
		local ok, input = hdp.receive(localPort, timeout) 
		if ok then 
			local tab = serial.unserialize(input[7])
			if tab ~= nil then
				if tab[1] == respCode.success[1] then
					return true
				else
					return false, tab[1]
				end
			else 
				return false, respCode.failed[1]
			end
		else
			return false, input
		end
	else
		return false, code
	end
end

function dsapi.remove(port, path)
	return dsapi.write(port, path, nil)
end

function dsapi.get(port, path)
	local localPort = getPort()
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.get, path}))
	if status then
		local ok, input = hdp.receive(localPort, timeout)
		if ok then
			local tab = serial.unserialize(input[7])
			if tab ~= nil then
				if tab[1] == respCode.success[1] then
					return true, tab[2]
				else
					return false, tab[1]
				end
			else
				return false, respCode.failed[1]
			end
		else
			return false, input
		end
	else
		return false, code
	end
end

function dsapi.list(port, path)
	local localPort = getPort()
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.list, path}))
	if status then
		local ok, input = hdp.receive(localPort, timeout)
		if ok then
			local tab = serial.unserialize(input[7])
			if tab ~= nil then
				if tab[1] == respCode.success[1] then
					local i = 0
					return true, function()
						i = i + 1
						if i <= #tab[2] then return tab[2][i][1], tab[2][i][2] end
					end
				else
					return false, tab[1]
				end
			else
				return false, respCode.failed[1]
			end
		else
			return false, input
		end
	else
		return false, code
	end
end

function dsapi.echo(port)
	local localPort = getPort()
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.echo}))
	if status then
		local ok, input = hdp.receive(localPort, 4)
		if ok then
			return true
		else
			return false
		end
	else
		return false, code
	end
end

function dsapi.translateCode(code)
	if code ~= nil then
		for _, obj in ipairs(respCode) do
			if code == obj[1] then return obj[2] end
		end
		return hdp.translateMessage(code)
	end
end

return dsapi