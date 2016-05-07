-- ################################################################
-- #         HDP - Huge (amount of) Data Protocol                 #
-- #                                                              #
-- #  08.2015                                      by: Aranthor   #
-- ################################################################

--[[
	## Opis protokołu ##
	HDP to protokół służący do łatwego wysyłania danych przez sieć OC.
	Cechuje się elastycznością - w przypadku, gdy ilość wysyłanych danych przekracza
	wartość MTU, są one dzielone na segmenty.
	W przypadku niedostarczenia któregoś z segmentów, adresat wysyła prośbę o ponowne wysłanie.
	
	Jako że poprzednie wersje protokołu nie działały prawidłowo w sieciach z dużym opóźnieniem
	(pozyżej 30 sekund gry, 0.4 sekund), od wersji 2.0 każdy wysłany segment wymaga potwierdzenia jego odbioru.
	
	Wersje 2.x i wyższe nie są kompatybilne z 1.x.

	## Schemat połączenia ##
	Nadawca								Odbiorca
	=============================================
	|1.			hdp, <wersja> --->				|
	|		<--- (echo, <wersja>)/finish		|
	=============================================
	|2			data, <dane> --->				|
	|				<--- ok						|
	=============================================
	|3.1.		length, <segmenty> --->			|
	|			<--- ok/memory					|
	=============================================
	|3.2.		segment, numer, <dane> --->		|
	|				<--- ok						|
	=============================================
	|4.				finish --->					|
	|											|
	=============================================
	
	1. Sprawdzenie połączenia i wysłanie informacji o protokole oraz o jego wersji.
	   Jest to sposób na wykrycie starszych wersji protokołu (które w odpowiedzi nie wysyłają numeru wersji),
	   oraz innych nieobsługiwanych wersji.
	2. Jeśli ilość wysyłanych danych nie przekracza MTU, wszystko wysyłane jest
	   w jednym pakiecie. Ilość prób wysyłania zależy od wartości maxAttempts. Po zakończeniu
	   wysyłania protokół przechodzi do fazy #4.
	3.1. Wysłanie ilości segmentów i rozpoczęcie transferu lub błąd, jeśli odbiorca ma za mało pamięci
	3.2. Wysyłanie kolejnych segmentów danych i sygnalizacja zakończenia transferu
	4. Zakończenie połączenia.
	
	## Budowa komunikanu "hdp_message" ##
	{
		1. "hdp_message"
		2. adres adresata
		3. adres nadawcy
		4. port adreata
		5. odległość
		6 - ... wiadomość
	}
]]

local version = "2.1"
local major_version = 2
local args = {...}
if args[1] == "version_check" then return version end

local computer = require("computer")
local component = require("component")
local event = require("event")
local serial = require("serialization")

local MTU = 6192 -- wielkość segmentu danych (pomniejszona o 2KB)
local delay = 0.1 -- opóźnienie pomiędzy segmentami
local maxTimeout = 2 -- maksymalny czas oczekiwania
local maxAttempts = 2 -- ilość ponowień wysłania wiadomości

local hdp = {}
local modem = nil
if component.isAvailable("modem") then modem = component.modem end

local code = {
	hdp = 0x10f,
	echo = 0x110,
	length = 0x111,
	ok = 0x112,
	memory = 0x113,
	segment = 0x114,
	finish = 0x115,
	reply = 0x116,
	["end"] = 0x117, -- unused
	data = 0x118
}

local errors = {
	timeout = {0x130, "Przekroczono limit czasu oczekiwania"},
	maxAttempts = {0x131, "Osiagnieto maksymalna ilosc ponownych transferow"},
	incorrect = {0x132, "Niepoprawna skladnia wiadomosci"},
	memory = {0x133, "Za malo pamieci RAM"},
	incompatibleH = {0x134, "Używana wersja protokołu przestarzała"},
	incompatibleL = {0x135, "Host docelowy używa przestarzałej wersji protokołu"}
}

-- tryb debugowania
local debugMode = false

local function debugPrint(...)
	if debugMode then
		print(os.date():sub(-8) .. " - ", ...)
	end
end

local function checkPort(port)
	return type(port) == "number" and port > 0 and port < 65535
end

local function checkCompatibility(remoteVersion)
	return remoteVersion and remoteVersion >= major_version
end

local function receiveMessage(port, timeout)
	local msg = {}
	msg = {event.pull(timeout or maxTimeout, "modem_message", modem.address, nil, port)}
	if #msg == 0 then msg = nil end
	return msg
end

local function sendSegments(address, port, localPort, segments, message)
	for _, segment in pairs(segments) do
		for attempt = 1, maxAttempts do
			debugPrint("3.2. attempt: ", attempt)
			debugPrint("3.2. wysylanie wiadomosci (segment): ", segment)
			modem.send(address, port, localPort, code.segment, message:sub(((segment - 1) * MTU) + 1, segment * MTU))
			local resp = receiveMessage(localPort)
			debugPrint("3.2 odpowiedz: ", serial.serialize(resp))
			if not resp and attempt == maxAttempts then
				return false, errors.timeout[1]
			elseif resp[7] ~= code.ok then
				return false, errors.incorrect[1]
			end
		end
	end
	return true
end

function setModem(newModem)
	if newModem.type == "modem" then
		modem = newModem
	end
end

function setDebug(deb)
	debugMode = deb
end

function send(localPort, port, ...)
	debugPrint("1. wysylanie wiadomosci (hdp): ", serial.serialize(...))
	modem.broadcast(port, localPort, code.hdp, major_version)
	local resp = receiveMessage(localPort)
	debugPrint("1. odpowiedz: ", serial.serialize(resp))
	
	if not resp then
		return false, errors.timeout[1]
	elseif resp[7] == code.finish then
		return false, errors.incompatibleL[1]
	elseif resp[7] == code.echo and checkPort(resp[6]) then
		if not checkCompatibility(resp[8]) then
			return false, code.incompatibleH[1]
		end
		
		local message = serial.serialize(table.pack(...))
		if message:len() <= MTU then
			for attempt = 1, maxAttempts do
				debugPrint("2. attempt: ", attempt)
				debugPrint("2. wysylanie wiadomosci (data)")
				modem.send(resp[3], resp[6], localPort, code.data, message)
				resp = receiveMessage(localPort)
				debugPrint("2. odpowiedz: ", serial.serialize(resp))
				
				if not resp then
					if attempt == maxAttempts then
						return false, errors.timeout[1]
					end
				elseif not checkPort(resp[6]) then
					return false, errors.incorrect[1]
				elseif resp[7] == code.ok then
					break
				end
			end
		else
			local amount = math.ceil(message:len() / MTU)
			debugPrint("3.1 wysylanie wiadomosci (length): ", amount)
			modem.send(resp[3], resp[6], localPort, code.length, amount)
			resp = receiveMessage(localPort)
			debugPrint("3.1 odpowiedz: ", serial.serialize(resp))
			if not resp then
				return false, errors.timeout[1]
			elseif resp[7] == code.memory then
				return false, errors.memory[1]
			elseif resp[7] ~= code.ok then
				return false, errors.incorrect[1]
			end
			
			segments = {}
			for i = 1, amount do table.insert(segments, i) end
			local status, err = sendSegments(resp[3], resp[6], localPort, segments, message)
			
			if not status then
				return false, err
			end
		end
		
		debugPrint("4. wysylanie wiadomosci (finish)")
		modem.send(resp[3], resp[6], localPort, code.finish)
		--[[resp = receiveMessage(localPort)
		debugPrint("4. odpowiedz: " serial.serialize(resp))
		if not resp then
			return false, errors.timeout[1]
		elseif resp[7] ~= code.end then
			return false, errors.incorrect[1]
		end]]
		
		return true
	end
	
	return false, errors.incorrect[1]
end

function send2(localPort, port, ...)
	debugPrint("1. wysylanie wiadomosci (hdp): ", serial.serialize(...))
	modem.broadcast(port, localPort, code.hdp)
	local resp = receiveMessage(localPort)
	debugPrint("1. odpowiedz: ", serial.serialize(resp))
	if resp and resp[7] and resp[7] == code.echo and checkPort(resp[6]) then
		local message = serial.serialize(table.pack(...))
		local amount = math.ceil(message:len() / MTU)
		debugPrint("2. wysylanie wiadomosci (length)")
		modem.send(resp[3], resp[6], localPort, code.length, message:len())
		resp = receiveMessage(localPort)
		debugPrint("2. odpowiedz: ", serial.serialize(resp))
		if resp and resp[7] and checkPort(resp[6]) then
			if resp[7] == code.ok then
				for attempt = 1, maxAttempts do
					debugPrint("3. attempt: ", attempt)
					local segment = 0
					repeat
						segment = segment + 1
						os.sleep(delay)
						debugPrint("wyslano segment: ", segment, "/" .. tostring(amount))
						modem.send(resp[3], resp[6], localPort, code.segment, message:sub(((segment - 1) * MTU) + 1, segment * MTU))
					until segment == amount
					debugPrint("4. wysylanie wiadomosci (finish)")
					modem.send(resp[3], resp[6], localPort, code.finish)
					resp = receiveMessage(localPort)
					debugPrint("4. odpowiedz: ", serial.serialize(resp))
					if resp and resp[7] and checkPort(resp[6]) then
						if resp[7] == code["end"] then
							return true
						elseif resp[7] ~= code.reply then
							return false, errors.incorrect[1]
						end
					elseif not resp then
						return false, errors.timeout[1]
					elseif not checkPort(resp[6]) or not resp[7] then	
						return false, errors.incorrect[1]
					else
						return false, errors.incorrect[1]
					end
				end
				return false, errors.maxAttempts[1]
			elseif resp[7] == code.memory then
				return false, errors.memory[1]
			else
				return false, errors.incorrect[1]
			end
		elseif not resp then
			return false, errors.timeout[1]
		end
		return false, errors.incorrect[1]
	elseif not resp then
		return false, errors.timeout[1]
	end
	return false, errors.incorrect[1]
end

function receive(port)
	local msg = receiveMessage(port, maxTimeout * 2)
	debugPrint("2. odebrano wiadomosc: ", serial.serialize(msg))
	
	if not msg then
		return false, errors.timeout[1]
	elseif not checkPort(msg[6]) then
		return false, errors.incorrect[1]
	end
	
	if msg[7] == code.data then
		local final = {"hdp_message"}
		for i = 2, #msg do table.insert(final, msg[i]) end
		debugPrint("2. wysylanie odpowiedzi (ok)")
		modem.send(msg[3], msg[6], port, code.ok)
		msg = receiveMessage(port)
		debugPrint("4. obebrano wiadomosc: ", serial.serialize(msg))
		
		if not msg then
			return false, errors.timeout[1]
		elseif msg[7] ~= code.finish or not checkPort(msg[6]) then
			return false, errors.incorrect[1]
		end
		
		--[[debugPrint("4. wysylanie odpowiedzi (end)")
		modem.send(msg[3], msg[6], port, code["end"])]]
		return true, {"hdp_message", final[2], final[3], final[4], final[5], table.unpack(serial.unserialize(final[8]) or {})}
	elseif msg[7] == code.length and type(msg[8]) == "number" then
		if msg[8] * MTU < computer.freeMemory() + 1024 * 50 then
			debugPrint("3.1. wysylanie odpowiedzi (memory): ", msg[8], computer.freeMemory())
			modem.send(msg[3], msg[6], port, code.memory)
			return false, errors.memory[1]
		end
		
		local attempt = 0
		local segments = msg[8]-----
		local final_t = {}
		debugPrint("3.1. wysylanie odpowiedzi (ok)")
		modem.send(msg[3], msg[6], port, code.ok)
		
		while attempt <= maxAttempts do
			msg = receiveMessage(port)
			debugPrint("3.2. odebano wiadomosc: ", serial.serialize(msg))
			if not msg then
				return false, errors.timeout[1]
			elseif msg[7] == code.finish then
				--[[debugPrint("4. wysylanie odpowiedzi")
				modem.send(msg[3], msg[6], port, code["end"])]]
				local final = ""
				for _, b in pairs(final_t) do final = final .. b end
				return true, {"hdp_message", msg[2], msg[3], msg[4], msg[5], table.unpack(serial.unserialize(final) or {})}
			elseif msg[7] ~= code.segment or not checkPort(msg[6]) or type(msg[8]) ~= "number" then
				return false, errors.incorrect[1]
			end
			
			final_t[msg[8]] = msg[9]
			debugPrint("3.2 wysylanie odpowiedzi (ok)")
			modem.send(msg[3], msg[6], port, code.ok)
		end
		
		return false, errors.incorrect[1]
	end
	return false, errors.incorrect[1]
end

function receive2(port)
	local msg = receiveMessage(port)
	debugPrint("2. odebrano wiadomosc: ", serial.serialize(msg))
	if msg and msg[7] and checkPort(msg[6]) and type(msg[8]) == "number" then
		if msg[7] == code.length then
			if msg[8] < computer.freeMemory() + 1024 * 10 then
				debugPrint("2. wysylanie wiadomosci (ok)")
				modem.send(msg[3], msg[6], port, code.ok)
				local length = msg[8]
				for attempt = 1, maxAttempts do
					debugPrint("3. attempt: ", attempt)
					local data = ""
					repeat
						msg = receiveMessage(port)
						debugPrint("4. odebrano segment: ", serial.serialize(msg))
						if msg and msg[7] and checkPort(msg[6]) and msg[7] == code.segment then
							data = data .. msg[8] or ""
						elseif not msg then
							return false, errors.timeout[1]
						elseif msg[7] ~= code.segment and msg[7] ~= code.finish then
							return false, errors.incorrect[1]
						end
					until msg[7] == code.finish
					if data:len() == length then
						debugPrint("4. wysylanie wiadomosci (end)")
						modem.send(msg[3], msg[6], port, code["end"])
						return true, {"hdp_message", msg[2], msg[3], msg[4], msg[5], table.unpack(serial.unserialize(data) or {})}
					else
						debugPrint("4. wysylanie wiadomosci (reply)")
						modem.send(msg[3], msg[6], port, code.reply)
					end
				end
				return false, errors.maxAttempts[1]
			else
				modem.send(msg[3], msg[6], port, code.memory)
				return false, errors.memory[1]
			end
		end
		return false, error.incorrect[1]
	elseif not msg then
		return false, errors.timeout[1]
	end
	return false, errors.incorrect[1]
end

function translateMessage(msgCode)
	if msgCode then
		for _, obj in pairs(errors) do
			if obj[1] == msgCode then return obj[2] end
		end
	end
	return "Nieznany blad"
end

--[[
Przełącza tryb debugowania
	@deb: true/false
]]
hdp.setDebug = setDebug
--[[
Ustawia modem, z którego będą wysyłane wiadomości
	@newModem: modem
]]
hdp.setModem = setModem
hdp.translateMessage = translateMessage
--[[
Wysyła wiadomość na wskazany port
	@port: port docelowy
	@...: wiadomość
	returns:
		true - gdy wiadomość dostarczona pomyślnie
		false, kod - gdy wiadomość nie została wysłana
]]
hdp.send = function(port, ...)
	local localPort = 0
	repeat
		localPort = math.random(10000, 60000)
	until localPort ~= port and not modem.isOpen(localPort)
	modem.open(localPort)
	local status, code = send(localPort, port, ...)
	modem.close(localPort)
	return status, code
end
--[[
Odbiera wiadomość
	@port: nasłuchiwany port
	@timeout: czas nasłuchiwania
	returns:
		true, wiadomość - gdy odebrano wiadomość
		false, kod - gdy odbieranie nie powiodło się
]]
hdp.receive = function(port, timeout)
	local status, content = false, errors.timeout[1]
	local isOpen = modem.isOpen(port)
	if not isOpen then modem.open(port) end
	local e = {event.pull(timeout, "modem_message", modem.address, nil, port)}
	debugPrint("1. odebrano wiadomosc: ", serial.serialize(e))
	if #e > 0 and e[7] == code.hdp then
		if not checkCompatibility(e[8]) then
			modem.send(e[3], e[6], port, code.finish)
			return false, errors.incompatibleH[1]
		end
		debugPrint("1. wyslano odpowiedz (echo)")
		modem.send(e[3], e[6], port, code.echo, major_version)
		status, content = receive(port)
	end
	if not isOpen then modem.close(port) end
	return status, content
end
--[[
Nasłuchuje wiadomości w tle. Użyj jako drugi parametr w funkcji event.listen.
Funkcja przyjmuje wiadomości typu "modem_message"; po zakończonym przetwarzaniu
generuje wiadomość typu "hdp_message".
]]
hdp.listen = function(...)
	local e = {...}
	if e[7] == code.hdp then
		debugPrint("1. odebrano wiadomosc: ", serial.serialize(e))
		if not checkCompatibility(e[8]) then
			return false, errors.incompatibleH[1]
		end
		debugPrint("1. wyslano odpowiedz (echo)")
		modem.send(e[3], e[6], e[4], code.echo, major_version)
		status, content = receive(e[4])
		if status then
			computer.pushSignal(table.unpack(content))
		end
	end
end

ret = modem and hdp or nil
return ret