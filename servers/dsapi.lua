-- #################################################
-- ##   API do obs�ugi serwera danych dataSrv2    ##
-- #                                               #
-- ##  05.2015                     by: Aranthor   ##
-- #################################################

--[[
	## Opis funkcji ##
	dsapi.write(modem, port, path, content)
	Funkcja wysy�a nowy plik na serwer. Gdy plik ju� istnieje, jego
	zawarto�� jest nadpisywana
		@param modem - modem, z kt�rego zostanie wys�ana wiadomo��
		@param port - port serwera
		@param path - �cie�ka do pliku
		@param content - zawarto�� pliku
		
		@return
		true - gdy zapis si� powi�d�
		false, kod - gdy nie uda si� zapisa� pliku
		
	dsapi.remove(modem, port, path)
	Funkcja usuwa plik z serwera
		@param modem - modem, z kt�rego zostanie wys�ana wiadomo��
		@param port - port serwera
		@param path - �cie�ka do pliku
		
		@return
		true - gdy usuwanie si� powiod�o
		false, kod - gdy usuwanie si� nie powiod�o
		
	dsapi.get(modem, port, path)
	Funkcja pobiera zawarto�� pliku z serwera
		@param modem - modem, z kt�rego zostanie wys�ana wiadomo��
		@param port - port serwera
		@param path - �cie�ka do pliku
		
		@return
		true, <zawarto��> - gdy pobieranie si� powiod�o
		false, kod - gdy wyst�pi� b��d
		
	dsapi.list(modem, port, path)
	Funkcja zwraca iterator do element�w podanego katalogu
		@param modem - modem, z kt�rego zostanie wys�ana wiadomo��
		@param port - port serwera
		@param path - �cie�ka do pliku
		
		@return
		true, iterator - gdy otrzymano list�
		false, kod - gdy wyst�pi� b��d
		Przyk�ad:
			a, b = dsapi.list(modem, port, path)
			if a then
				for name, size in b do
					print(name, "nazwa")
					print(size, "rozmiar")
				end
			else
				print(dsapi.translateCode(b))
			end
		Je�li rozmiar jest r�wny -1, obiekt jest folderem
	
	dsapi.echo(modem, port)
	Funkcja sprawdza, czy serwer jest dost�pny
		@param modem - modem, z kt�rego zostanie wys�ana wiadomo��
		@param port - port serwera
		
		@return
		true - je�li serwer jest dost�pny
		false - je�li nie mo�na nawi�za� po��czenia z serwerem
]]

local rtpo = require("rtpo")
local serial = require("serialization")

local wersja = "1.0"

local aa, bb = require("shell").parse(...)
if aa[1] == "version_check" then return wersja end

-- Czas, po kt�rym po��czenie jest zrywane
local timeout = 2

-- Zapytania do serwera
local reqCode = {
	file = 0x01, --@param:(�cie�ka, zawarto��)
	get  = 0x02, --@param:(�cie�ka)
	list = 0x03, --@param:(�cie�ka)
	echo = 0x04
}

-- Kody odpowiedzi serwera wraz z opisem
local respCode = {
	success = {0x00, "czynnosc powiodla sie"}, -- zadana czynno�� powiod�a si�
	failed = {0x01, "wystapil nieznany blad"}, -- nieznany b��d
	nomem = {0x02, "za malo pamieci na serwerze"}, -- za ma�o miejsca na serwerze
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