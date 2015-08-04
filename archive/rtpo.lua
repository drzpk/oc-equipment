-- ###########################################################################
-- ###      RTPO - Reliable Transmission Protocol for OpenComputers        ###
-- # Protokół służący do wymiany danych pomiędzy komputerami w OpenComputers #
-- #                                                                         #
-- #                                                                         #
-- #                                                                         #
-- ### 02.2015                            Created by: Aranthor             ###
-- ###########################################################################

--[[

	### Schemat protokołu RTPO - WERSJA 2.0 ###
	
	 Nadawca						Odbiorca
(rozpoczyna połączenie)
		|===============================|
	1.  |       rtpo (x2) ----->        | - Inicjalicacja połączenia
		|     <----- echo (x2)          | - Odpowiedź
		|===============================|
	2.  |    amount, <ilość> ----->     | - Wysłanie liczby pakietów
		|   <----- ok/notEnoughMemory   | - Potwierdzenie lub błąd, jeśli brak pamięci
		|===============================|
	3.  | packet,<numer>,<dane>  -----> | - Wysyłanie pakietów do serwera
		|       done ----->             | - Zakończenie wysyłania pakietów
		|===============================|
	4.  |<----- ok/ missing,<{pakiety}> | - Potwierdzenie lub powrót do bloku 3. w celu
		|===============================|   ponownego wysłania brakujących pakietów
	5.  |     quit         ----->       | - Zakończenie transmisji
		|===============================|
		
	## Opis poszczególnych bloków ##
	1. Sprawdzenie połączenia i wysłanie informacji o użytym protokole.
		(dwukrotnie - na potrzeby nasłuchiwania w tle)
	2. W tym bloku następuje wysłanie liczby pakietów, aby odbiorca mógł zarezerwować
	   pamięć. W przypadku braku wystarczającej ilości pamięci, wysyłany jest błąd 'notEnoughMemory'
	   i połączenie jest zrywane.
	3. Wysyłanie pakietów. Po wysłaniu pakietu następuje 0.1 sekundy przerwy,
		aby odbiorca mógł obsłużyć pakiet.
	4. Odbiorca wysyła potwierdzenie otrzynania wszystkich pakietów ('ok') lub informację o brakujących
	   ('missing') i wysyła numery pakietów, które nie dotarły. W takim przypadku protokół wraca do
	   bloku trzeciego. W przpadku przekroczenia maksymalnej ilości prób wysłania pakietów ('maxHops')
	   wysyłany jest błąd ('maxHopsReached') i połączenie jest zrywane.
	5. Nadawca wysyła komunikat o prawidłowym zakończeniu połączenia.
	
	## Wysyłanie wiadomości: ##
	status, kod = rtpo.send(address, port, ...)
	
	## Odbieranie wiadomości: ##
	status, kod/wiadomość = rtpo.receive(port, timeout)
	
	## Odbieranie wiadomości w tle: ##
	event.listen("modem_message", function(...)
		local msg = {...}
		if msg[7] == 0 then
			local status, output = rtpo.receive(modem, msg[4], timeout)
			if status then
				print("wiadomosc: " .. output)
			end
		end
	end)
	
	## Struktura odebranej wiadomości: ##
	(Od wiadomości "modem_message" różni się tylko pierwszym parametrem)
	{"rtpo_message", adres lokalny, adres zdalny, port lokalny, odległość, ...}
]]
-------------------------------------------------------------------------------

local version = "2.0"
local args = {...}
if args[1] == "version_check" then
	return version
end

local computer = require("computer")
local component = require("component")
local event = require("event")
local serial = require("serialization")
-------------------------------------------------------------------------------
-- #  Stałe, niektóre uzależnione od konfiguracji moda OpenComputers    #
-- #    nie zmieniaj ich wartości jeśli nie wiesz, do czego służą       #

-- Maksymalna wielkosc danych w pakiecie w bajtach
local MTU = nil
-- Opóźnienie pomiędzy wysyłaniem kolejnych pakietów
local packetDelay = 0.3
-- Czas oczekiwania na odpowiedź, po którym połączenie jest zrywane
local maxTimeout = 2
-- Maksymalna ilość ponowień wysyłania pakietów
local maxHops = 2
-------------------------------------------------------------------------------
-- # Zmienne #
local modem = nil
-------------------------------------------------------------------------------

-- Kody nagłówków wiadomości
local codes = {
	rtpo = 0x00,	-- Informacja o użytym protokole
	echo = 0x01,	-- Rozpoczęcie połączenia
	amount = 0x02,	-- Ilość pakietów od wysłania
	packet = 0x03,  -- Numer pakietu
	done = 0x04, 	-- Zakończenie wysyłania pakietów
	ok = 0x05,		-- Potwierdzenie
	missing = 0x06,	-- Tablica z brakującymi pakietami
	quit = 0x06		-- Zakończenie połączenia
}

-- Kody błędów wraz z opisem
local messages = {
	notEnoughMemory = {0x20, "Za malo pamieci RAM"},
	maxHopsReached = {0x21, "Osiagnieto maksymalna ilosc prob"},
	noConnection = {0x22, "Brak polaczenia"},
	connectionAborted = {0x23, "Polaczenie przerwane"},
	connectionTimeout = {0x24, "Przekroczono limit czasu oczekiwania"},
	malformedMessage = {0x25, "Niepoprawna skladnia wiadomosci"},
	unexpectedError = {0x26, "Nieznany blad"},
	internalError = {0x27, "Blad sprzetowy"}
}
-------------------------------------------------------------------------------

local function getMessage(localPort, timeout, background)
	local e = nil
	if not background then modem.open(localPort) end
	if timeout == nil then
		e = {event.pull("modem_message", modem.address)}
	else
		e = {event.pull(timeout, "modem_message", modem.address)}
	end
	if not background then modem.close(localPort) end
	if #e == 0 then e = nil end
	return e
end

local rtpo = {}

--[[ 
Nasłuchuje port
	Argumenty:
		@port - port, który na być nasłuchiwany
		@timeout - czas nasłuchiwania w sekundach lub nil(nieskończoność)
		@background - wyłączenie automatycznego otwierania i zamykania portów (true/false/nil)
	Zwraca:
		- ( true, {<wiadomość>} ), gdy odebrano wiadomość ( patrz schemat wiadomości )
		- ( false, kod błędu ), gdy nie udało się pobrać wiadomości
]]

function rtpo.receive(port, timeout, background)
	local msg = {}
	local receivedPackets = {}
	local packetsAmount = 0
	local hops = 0
	local data = {}
	local try = 0
	--Blok #1
	repeat
		try = try + 1
		msg = getMessage(port, timeout, background)
		os.sleep(packetDelay)
		if not msg then
			return false, messages.connectionTimeout[1]
		elseif try > 3 then
			return false, messages.unexpectedError[1]
		else
			modem.send(msg[3], msg[6], port, codes.echo)
		end
	until msg[7] == codes.amount
	--Blok #2
	packetsAmount = tonumber(msg[8] or "0")
	if packetsAmount < 1 then
		return false, messages.malformedMessage[1]
	end
	for i = 1, packetsAmount do
		receivedPackets[i] = false
	end
	if packetsAmount * MTU > computer.freeMemory() + 1024 then
		modem.send(msg[3], msg[6], port, codes.notEnoughMemory)
		return false, messages.notEnoughMemory[1]
	else
		modem.send(msg[3], msg[6], port, codes.ok)
		while true do
			hops = hops + 1
			if hops > maxHops then
				return false, messages.maxHopsReached[1]
			end
			--Blok #3
			repeat
				msg = getMessage(port, maxTimeout, background)
				if msg == nil then
					return false, messages.connectionTimeout[1]
				end
				if type(msg[7]) == "number" and msg[7] == codes.packet and type(msg[8]) == "number" then
					receivedPackets[msg[8]] = true
					data[msg[8]] = msg[9] or ""
				elseif msg[7] ~= codes.done then
					return false, messages.unexpectedError[1]
				end
			until msg[7] == codes.done
			--Blok #4
			local missed = {}
			for i = 1, packetsAmount do
				if not receivedPackets[i] then table.insert(missed, i) end
			end
			if #missed > 0 then
				modem.send(msg[3], msg[6], port, codes.missing, serial.serialize(missed))
			else
				--Blok #5
				modem.send(msg[3], msg[6], port, codes.ok)
				local output = ""
				for i = 1, #data do
					output = output..data[i]
				end
				return true, {"rtpo_message", msg[2], msg[3], msg[4], msg[5], table.unpack(serial.unserialize(output) or {})}
			end
		end
	end
end

--[[
Wysyła wiadomość do odbiorcy
	Argumenty:
		@address - adres odbiorcy lub nil
		@port - port, na który zostanie wysłana wiadomość
		@... - wiadomość
	Zwraca:
		- true, gdy wiadomość została wysłana,
		- ( false, <kod błędu> ), gdy wiadomość nie została wysłana
]]
function rtpo.send(address, port, ...)
	--Blok #1
	local message = serial.serialize(table.pack(...))
	local localPort = 0
	repeat
		localPort = math.random(10000, 65000)
	until localPort ~= port and not modem.isOpen(localPort)
	for i = 1, 2 do
		os.sleep(packetDelay)
		if address then
			if not modem.send(address, port, localPort, codes.rtpo) then return false, internalError[1] end
		else
			if not modem.broadcast(port, localPort, codes.rtpo) then return false, internalError[1] end
		end 
	end
	--Blok #2
	local response = {}
	local amount = math.ceil(message:len() / MTU)
	if address then
		modem.send(address, port, localPort, codes.amount, amount)
	else
		modem.broadcast(port, localPort, codes.amount, amount)
	end
	repeat
		response = getMessage(localPort, maxTimeout)
		if response == nil then return false, messages.connectionTimeout[1] end
	until response[7] ~= codes.echo
	if response == nil then return false, messages.connectionTimeout[1] end
	--Blok #3
	if response[7] == codes.ok then
		local packetsIDs = {}
		local hops = 0
		for counter = 1, amount do table.insert(packetsIDs, counter) end
		repeat
			hops = hops + 1
			if hops > maxHops then
				return false, messages.maxHopsReached[1]
			end
			for _, packetNumber in ipairs(packetsIDs) do
				modem.send(response[3], response[6], localPort, codes.packet, packetNumber, message:sub(((packetNumber - 1) * MTU) + 1, packetNumber * MTU))
				os.sleep(packetDelay)
			end
			packetsIDs = {}
			modem.send(response[3], response[6], localPort, codes.done)
			response = getMessage(localPort, maxTimeout)
			--Blok #4
			if response == nil then
				return false, messages.connectionTimeout[1]
			elseif response[7] == codes.missing then
				local s = serial.unserialize(response[8] or "")
				if s ~= nil then
					packetsIDs = s
				else
					return false, messages.malformedMessage[1]
				end
			elseif response[7] ~= codes.ok then
				return false, messages.malformedMessage[1]
			end
		until response[7] == codes.ok
		--Blok #5
		modem.send(response[3], response[6], localPort, codes.quit)
		return true
	elseif response[7] == codes.notEnoughMemory then
		return false, messages.notEnoughMemory[1]
	else
		return false, messages.unexpectedError[1]
	end
end

--[[
Tłumaczy kod błędu na jego opis tekstowy
	Argumenty:
		@code - kod błędu
	Zwraca:
		Opis tekstowy błędu
		lub wiadomość 'Nieznany blad' gdy nie znaleziono błędu o podanym kodzie
]]
function rtpo.translateMessage(code)
	if code ~= nil then
		for _, obj in ipairs(messages) do
			if obj[1] == code then return obj[2] end
		end
	end
	return "Nieznany blad"
end

if not component.isAvailable("modem") then
	return nil, "Modem jest niedostepny"
end
modem = component.modem
MTU = modem.maxPacketSize()
if MTU < 20 then return
	nil, "Zbyt male MTU"
end
return rtpo