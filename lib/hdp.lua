-- ################################################################
-- #         HDP - Huge (amount of) Data Protocol                 #
-- #                                                              #
-- #  08.2015                                      by: Aranthor   #
-- ################################################################

--[[
	## Opis protokołu ##
	HDP to bezpołączeniowy protokół służący do wysyłania przez sieć dużej ilości danych
	- takiej, która przekracza wartość MTU. Protokół wyposażony jest w prosty mechanizm
	wykrywania zagubionych pakietów. W przypadku gdy dostarczona wiadomość jest
	niekompletna, wysyłana jest ponownie w całości (w odróżnieniu od protokołu RTPO).

	## Schemat połączenia ##
	Nadawca								Odbiorca
	=============================================
	|1.				hdp --->					|
	|				<--- echo					|
	=============================================
	|2.			length, <długość> --->			|
	|			<--- ok/memory					|
	=============================================
	|3.			segment, <dane> --->			|
	|				finish --->					|
	=============================================
	|4.			<--- end/reply					|
	|											|
	=============================================
	
	1. Sprawdzenie połączenia i wysłanie informacji o protokole
	2. Wysłanie długości wiadomości i rozpoczęcie transferu lub błąd, jeśli odbiorca ma za mało pamięci
	3. Wysyłanie kolejnych segmentów danych i sygnalizacja zakończenia transferu
	4. Zakończenie lub ponowienie wysyłania w przypadku niedostarczenia wiadomości	
]]

local version = "1.0"
local args = {...}
if args[1] == "version_check" then return version end

local computer = require("computer")
local component = require("component")
local event = require("event")
local serial = require("serialization")

local MTU = 1024 -- wielkość segmentu danych
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
	["end"] = 0x117
}

local errors = {
	timeout = {0x130, "Przekroczono limit czasu oczekiwania"},
	maxAttempts = {0x131, "Osiagnieto maksymalna ilosc ponownych transferow"},
	incorrect = {0x132, "Niepoprawna skladnia wiadomosci"},
	memory = {0x133, "Za malo pamieci RAM"}
}

local function checkPort(port)
	return type(port) == "number" and port > 0 and port < 65535
end

local function receiveMessage(port)
	local msg = {}
	msg = {event.pull(maxTimeout, "modem_message", modem.address, nil, port)}
	if #msg == 0 then msg = nil end
	return msg
end

function setModem(newModem)
	if newModem.type == "modem" then
		modem = newModem
	end
end

function send(localPort, port, ...)
	os.sleep(delay)
	modem.broadcast(port, localPort, code.hdp)
	local resp = receiveMessage(localPort)
	if resp and resp[7] and resp[7] == code.echo and checkPort(resp[6]) then
		os.sleep(delay)
		local message = serial.serialize(table.pack(...))
		local amount = math.ceil(message:len() / MTU)
		modem.send(resp[3], resp[6], localPort, code.length, message:len())
		resp = receiveMessage(localPort)
		if resp and resp[7] and checkPort(resp[6]) then
			if resp[7] == code.ok then
				for attempt = 1, maxAttempts do
					local segment = 1
					repeat
						os.sleep(delay)
						modem.send(resp[3], resp[6], localPort, code.segment, message:sub(((segment - 1) * MTU) + 1, segment * MTU))
					until segment == amount
					os.sleep(delay)
					modem.send(resp[3], resp[6], localPort, code.finish)
					resp = receiveMessage(localPort)
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
	local msg = receiveMessage(port)
	if msg and msg[7] and checkPort(msg[6]) and type(msg[8]) == "number" then
		if msg[7] == code.length then
			os.sleep(delay)
			if msg[8] < computer.freeMemory() + 1024 * 10 then
				modem.send(msg[3], msg[6], port, code.ok)
				local length = msg[8]
				for attempt = 1, maxAttempts do
					local data = ""
					repeat
						msg = receiveMessage(port)
						if msg and msg[7] and checkPort(msg[6]) and msg[7] == code.segment then
							data = data .. msg[8] or ""
						elseif not msg then
							return false, errors.timeout[1]
						elseif msg[7] ~= code.segment and msg[7] ~= code.finish then
							return false, errors.incorrect[1]
						end
					until msg[7] == code.finish
					os.sleep(delay)
					if data:len() == length then
						modem.send(msg[3], msg[6], port, code["end"])
						return true, {"hdp_message", msg[2], msg[3], msg[4], msg[5] , table.unpack(serial.unserialize(data) or {})}
					else
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
		for _, obj in ipairs(errors) do
			if obj[1] == msgCode then return obj[2] end
		end
	end
	return "Nieznany blad"
end

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
	until localPort ~= port and not modem.isOpen(port)
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
	if #e > 0 and e[7] and e[7] == code.hdp then
		os.sleep(delay)
		modem.send(e[3], e[6], port, code.echo)
		status, content = receive(port)
	end
	if not isOpen then modem.close(port) end
	return status, content
end
--[[
Nasłuchuje wiadomości w tle. Użyj jako drugi parametr w funkcji event.listen.
]]
hdp.listen = function(...)
	local e = {...}
	if e[7] and e[7] == code.hdp then
		os.sleep(delay)
		modem.send(e[3], e[6], e[4], code.echo)
		status, content = receive(e[4])
		if status then
			computer.pushSignal(table.unpack(content))
		end
	end
end

return modem and hdp or nil