-- #################################################
-- ##   API do obs³ugi serwera danych dataSrv2    ##
-- #                                               #
-- ##  05.2015                     by: Aranthor   ##
-- #################################################

--[[
	## Opis funkcji ##
	dsapi.write(modem, port, path, content)
	Funkcja wysy³a nowy plik na serwer. Gdy plik ju¿ istnieje, jego
	zawartoœæ jest nadpisywana
		@param modem - modem, z którego zostanie wys³ana wiadomoœæ
		@param port - port serwera
		@param path - œcie¿ka do pliku
		@param content - zawartoœæ pliku
		
		@return
		true - gdy zapis siê powiód³
		false, kod - gdy nie uda siê zapisaæ pliku
		
	dsapi.remove(modem, port, path)
	Funkcja usuwa plik z serwera
		@param modem - modem, z którego zostanie wys³ana wiadomoœæ
		@param port - port serwera
		@param path - œcie¿ka do pliku
		
		@return
		true - gdy usuwanie siê powiod³o
		false, kod - gdy usuwanie siê nie powiod³o
		
	dsapi.get(modem, port, path)
	Funkcja pobiera zawartoœæ pliku z serwera
		@param modem - modem, z którego zostanie wys³ana wiadomoœæ
		@param port - port serwera
		@param path - œcie¿ka do pliku
		
		@return
		true, <zawartoœæ> - gdy pobieranie siê powiod³o
		false, kod - gdy wyst¹pi³ b³¹d
		
	dsapi.list(modem, port, path)
	Funkcja zwraca iterator do elementów podanego katalogu
		@param modem - modem, z którego zostanie wys³ana wiadomoœæ
		@param port - port serwera
		@param path - œcie¿ka do pliku
		
		@return
		true, iterator - gdy otrzymano listê
		false, kod - gdy wyst¹pi³ b³¹d
		Przyk³ad:
			a, b = dsapi.list(modem, port, path)
			if a then
				for name, size in b do
					print(name, "nazwa")
					print(size, "rozmiar")
				end
			else
				print(dsapi.translateCode(b))
			end
		Jeœli rozmiar jest równy -1, obiekt jest folderem
	
	dsapi.echo(modem, port)
	Funkcja sprawdza, czy serwer jest dostêpny
		@param modem - modem, z którego zostanie wys³ana wiadomoœæ
		@param port - port serwera
		
		@return
		true - jeœli serwer jest dostêpny
		false - jeœli nie mo¿na nawi¹zaæ po³¹czenia z serwerem
]]

local rtpo = require("rtpo")
local serial = require("serialization")

local wersja = "1.0"

local aa, bb = require("shell").parse(...)
if aa[1] == "version_check" then return wersja end

-- Czas, po którym po³¹czenie jest zrywane
local timeout = 2

-- Zapytania do serwera
local reqCode = {
	file = 0x01, --@param:(œcie¿ka, zawartoœæ)
	get  = 0x02, --@param:(œcie¿ka)
	list = 0x03, --@param:(œcie¿ka)
	echo = 0x04
}

-- Kody odpowiedzi serwera wraz z opisem
local respCode = {
	success = {0x00, "czynnosc powiodla sie"}, -- zadana czynnoœæ powiod³a siê
	failed = {0x01, "wystapil nieznany blad"}, -- nieznany b³¹d
	nomem = {0x02, "za malo pamieci na serwerze"}, -- za ma³o miejsca na serwerze
	notfound = {0x03, "element nie zostal odnaleziony"}, -- nie znaleziono pliku lub folderu
	badreq = {0x04, "bledne zapytanie"}, -- zapytanie jest niekompletne lub nie istnieje
	echo = {0x10, "echo"},
}

local dsapi = {}

function getPort(modem)
	local localPort = 0
	repeat
		localPort = math.random(10000, 65000)
	until localPort ~= port and not modem.isOpen(localPort)
	return localPort
end

function dsapi.write(modem, port, path, content)
	local localPort = getPort(modem)
	local status, code = rtpo.send(modem, nil, port, localPort, serial.serialize({reqCode.file, path, content}))
	if status then
		local ok, input = rtpo.receive(modem, localPort, timeout) 
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

function dsapi.remove(modem, port, path)
	return dsapi.write(modem, port, path, nil)
end

function dsapi.get(modem, port, path)
	local localPort = getPort(modem)
	local status, code = rtpo.send(modem, nil, port, localPort, serial.serialize({reqCode.get, path}))
	if status then
		local ok, input = rtpo.receive(modem, localPort, timeout)
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

function dsapi.list(modem, port, path)
	local localPort = getPort(modem)
	local status, code = rtpo.send(modem, nil, port, localPort, serial.serialize({reqCode.list, path}))
	if status then
		local ok, input = rtpo.receive(modem, localPort, timeout)
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

function dsapi.echo(modem, port)
	local localPort = getPort(modem)
	local status, code = rtpo.send(modem, nil, port, localPort, serial.serialize({reqCode.echo}))
	if status then
		local ok, input = rtpo.receive(modem, localPort, 4)
		if ok then
			return true
		else
			return false
		end
	else
		return false
	end
end

function dsapi.translateCode(code)
	if code ~= nil then
		for _, obj in ipairs(respCode) do
			if code == obj[1] then return obj[2] end
		end
		return rtpo.translateMessage(code)
	end
end

return dsapi