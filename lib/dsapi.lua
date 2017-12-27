-- #################################################
-- ##   API do obs�ugi serwera danych dataSrv2    ##
-- #                                               #
-- ##  05.2015                     by: IlynPayne  ##
-- #################################################

--[[
	## Opis funkcji ##
	dsapi.write(port, path, content)
	Funkcja wysy�a nowy plik na serwer. Gdy plik ju� istnieje, jego
	zawarto�� jest nadpisywana
		@param port - port serwera
		@param path - �cie�ka do pliku
		@param content - zawarto�� pliku
		
		@return
		true - gdy zapis si� powi�d�
		false, kod - gdy nie uda si� zapisa� pliku
		
	dsapi.remove(port, path)
	Funkcja usuwa plik z serwera
		@param port - port serwera
		@param path - �cie�ka do pliku
		
		@return
		true - gdy usuwanie si� powiod�o
		false, kod - gdy usuwanie si� nie powiod�o
		
	dsapi.get(port, path)
	Funkcja pobiera zawarto�� pliku z serwera
		@param port - port serwera
		@param path - �cie�ka do pliku
		
		@return
		true, <zawarto��> - gdy pobieranie si� powiod�o
		false, kod - gdy wyst�pi� b��d
		
	dsapi.list(port, path)
	Funkcja zwraca iterator do element�w podanego katalogu
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
	
	dsapi.echo(port)
	Funkcja sprawdza, czy serwer jest dost�pny
		@param port - port serwera
		
		@return
		true - je�li serwer jest dost�pny
		false - je�li nie mo�na nawi�za� po��czenia z serwerem
]]

local hdp = require("hdp")
local serial = require("serialization")
local fs = require("filesystem")

local wersja = "2.3"

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
	echo = {0x10, "echo"}, -- echo
	badname = {0x11, "rozszerzenie nie moze skladac sie z cyfr"}
}

local dsapi = {}

function getPort(port)
	local localPort = 0
	repeat
		localPort = math.random(10000, 65000)
	until localPort ~= port and not require("component").modem.isOpen(localPort)
	return localPort
end

function dsapi.list(port, path, split)
	local localPort = getPort(port)
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.list, path}))
	if status then
		local ok, input = hdp.receive(localPort, timeout)
		if ok then
			local tab = serial.unserialize(input[7])
			if tab ~= nil then
				if tab[1] == respCode.success[1] then
					iter = tab[2]
					iter2 = {}
					if not split then
						for a, b in pairs(iter) do
							local result = b[1]:match("%.%d+$")
							if result then
								local found = false
								for ind, pos in pairs(iter2) do
									if pos[1] == b[1]:sub(1, -result:len() - 1) then
										iter[ind][2] = iter[ind][2] + b[2]
										found = true
										break
									end
								end
								if not found then
									table.insert(iter2, {result, b[2]})
								end
							else
								table.insert(iter2, {b[1], b[2]})
							end
						end
					end
					local i = 0
					return true, function()
						i = i + 1
						if i <= #iter then return iter[i][1], iter[i][2] end
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

local function doWrite(port, path, content)
	local localPort = getPort(port)
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.file, path, content}))
	if status then
		local ok, input = hdp.receive(localPort, timeout + 3) 
		if ok then 
			local tab = serial.unserialize(input[7])
			if tab then
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

function dsapi.write(port, path, content)
	local segments = fs.segments(path or "")
	if segments[#segments]:match("%.%d+$") then
		return false, respCode.badname[1]
	end
	if content:len() > 10240 and false then
		local parts = math.ceil(content:len() / 10240)
		for part = 1, parts do
			local suffix = "." .. (part < 10 and ("0" .. tostring(part)) or tostring(part))
			local s, c = doWrite(port, path .. suffix, content:sub(1 + (part - 1) * 10240, part * 10240))
			if not s then return false, c end
			os.sleep(0.5)
		end
		return true
	else
		return doWrite(port, path, content)
	end
end

local function getSegments(port, path)
	local subpath = "/"
	local segments = fs.segments(path or "")
	for i = 1, #segments - 1 do
		subpath = subpath .. "/" .. segments[i]
	end
	local s, i = dsapi.list(port, subpath, true)
	if s then
		local list = {}
		for name, size in i do
			if name == segments[#segments] then return true, {subpath .. "/" .. name} end
			if name:match("^" .. segments[#segments] .. "%.%d+$") then
				table.insert(list, subpath .. "/" .. name)
			end
		end
		if #list == 0 then
			return false, respCode.notfound[2]
		end
		return true, list
	else
		return false, i
	end
end

function dsapi.remove(port, path)
	local r, l = getSegments(port, path)
	if r then
		for i = 1, #l do
			os.sleep(0.5)
			local s, c = doWrite(port, l[i], nil)
			if not s then return false, c end
		end
		return true
	else
		return false, l
	end
end

local function doGet(port, path)
	local localPort = getPort(port)
	local status, code = hdp.send(port, localPort, serial.serialize({reqCode.get, path}))
	if status then
		local ok, input = hdp.receive(localPort, timeout + 3)
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

function dsapi.get(port, path)
	local r, s = getSegments(port, path)
	if r then
		local data = ""
		for i = 1, #s do
			local r, c = doGet(port, s[i])
			if r then
				data = data .. c
			else
				return false, c
			end			
		end
		return true, data
	else
		return false, s
	end
end

function dsapi.echo(port)
	local localPort = getPort(port)
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
		for _, obj in pairs(respCode) do
			if code == obj[1] then return obj[2] end
		end
		return hdp.translateMessage(code)
	end
end

return dsapi