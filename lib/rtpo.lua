-- ###########################################################################
-- ###      RTPO - Reliable Transmission Protocol for OpenComputers        ###
-- # Protokół służący do wymiany danych pomiędzy komputerami w OpenComputers #
-- #                                                                         #
-- # Protokół po wywołaniu 'require("rtop")' zwraca listę funckji            #
-- #                                                                         #
-- ### 02.2015                            Created by: Aranthor             ###
-- ###########################################################################

--[[

	### Schemat protokołu RTPO - WERSJA 1.0 ##
	
	 Nadawca						Odbiorca
(rozpoczyna połączenie)
		|===============================|
	1.  |       echo ----->             | - Inicjalicacja połączenia
		|      <----- echo              | - Odpowiedź
		|===============================|
	2.  |   {amount, <ilość>} ----->    | - Wysłanie liczby pakietów
		|   <----- ok/notEnoughMemory   | - Potwierdzenie lub błąd, jeśli brak pamięci
		|===============================|
	3.  |{packet,<numer>,<dane>} -----> | - Wysyłanie pakietów do serwera
		|       done ----->             | - Zakończenie wysyłania pakietów
		|===============================|
	4.  |<----- ok/{missing,<{pakiety}>}| - Potwierdzenie lub powrót do bloku 3. w celu
		|===============================|   ponownego wysłania brakujących pakietów
	5.  |    quit ----->                | - Zakończenie transmisji
		|===============================|
		
	## Opis poszczególnych bloków ##
	1. Sprawdzenie, czy nadawca i odbiorca są online
	2. W tym bloku następuje wysłanie liczby pakietów, aby odbiorca mógł zarezerwować
	   pamięć. W przypadku braku wystarczającej ilości pamięci, wysyłany jest błąd 'notEnoughMemory'
	   i połączenie jest zrywane.
	3. Tutaj następuje wysyłanie pakietów do odbiorcy. Na tym etapie nie jest sprawdzane, czy pakiet
	   został wysłany. Po wysłaniu pakietu należy odczekać +-0.1 sekundy, aby odbiorca mógł
	   obsłużyć pakiet ( jego komputer może działać wolniej, niż nadawcy ).
	4. Odbiorca wysyła potwierdzenie otrzynania wszystkich pakietów ('ok') lub informację o brakujących
	   ('missing') i wysyła numery pakietów, które nie dotarły. W takim przypadku protokół wraca do
	   bloku trzeciego. W przpadku przekroczenia maksymalnej ilości prób wysłania pakietów ('maxHops')
	   wysyłany jest błąd ('maxHopsReached') i połączenie jest zrywane.
	5. Nadawca wysyła komunikat o prawidłowym zakończeniu połączenia.
	
	## Wysyłanie wiadomości: ##
	modem.send(adres, port, portLokalny, wiadomosc)
	modem.broadcast(port, portLokalny, wiadomosc)
	
	## Schemat odebranej wiadomości: ##
	{"modem_message", adres lokalny, adres zdalny, port lokalny, odległość, port zdalny, wiadomość}
	
	## Odbieranie i wysyłanie wiadomości ##
	local status, msg = rtpo.receive(...)
	local status, kod = rtpo.send(...)
]]
-------------------------------------------------------------------------------

local version = "1.0"
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
local MTU = 5
-- Opóźnienie pomiędzy wysyłaniem kolejnych pakietów
local packetDelay = 0.1
-- Czas oczekiwania na odpowiedź, po którym połączenie jest zrywane
local maxTimeout = 1.2
-- Maksymalna ilość ponowień wysyłania pakietów
local maxHops = 4
-------------------------------------------------------------------------------
-- # Zmienne #
-- Ilość otwartych portów
local openedPorts = 0
-------------------------------------------------------------------------------

-- Kody nagłówków wiadomości
local codes = {
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
	unexpectedError = {0x26, "Nieznany blad"}
}
-------------------------------------------------------------------------------

local function getMessage(modem, localPort, timeout)
	local e = nil
	local cl = not modem.isOpen(localPort)
	if cl then modem.open(localPort) end
	repeat
		if timeout == nil then
			e = {event.pull("modem_message")}
		else
			e = {event.pull(timeout, "modem_message")}
		end
		if #e == 0 then e = nil end
	until e == nil or (e[2] == modem.address and e[4] == localPort)
	if cl then modem.close(localPort) end
	return e
end

local rtpo = {}

--[[ 
Nasłuchuje port
	Argumenty:
		@modem - modem, za pomocą którego ma być odebrana wiadomość
		@port - port, który na być nasłuchiwany
		@timeout - czas nasłuchiwania w sekundach lub nil(nieskończoność)
	Zwraca:
		- ( true, {<wiadomość>} ), gdy odebrano wiadomość ( patrz schemat wiadomości )
		- ( false, kod błędu ), gdy nie udało się pobrać wiadomości
]]

-- {"modem_message", adres lokalny, adres zdalny, port lokalny, odległość, port zdalny, wiadomość}
function rtpo.receive(modem, port, timeout)
	local msg = {}
	local receivedPackets = {}
	local packetsAmount = 0
	local hops = 0
	local data = {} -- wiadomość
	modem.open(port)
	repeat
		msg = getMessage(modem, port, timeout) -- odbiór: echo
	until msg == nil or msg[7] == codes.echo
	if msg ~= nil then
		print("odebralem echo")
		modem.send(msg[3], msg[6], port, codes.echo)
		repeat
			msg = getMessage(modem, port, maxTimeout) -- odbiór: liczba pakietów
		until msg == nil or type(msg[7]) == "string"
		if msg == nil then
			modem.close(port)
			return false, messages.connectionTimeout[1]
		end
		
		local content = serial.unserialize(msg[7])
		if content == nil then
			modem.close(port)
			return false, messages.malformedMessage[1]
		end
		print("odebralem liczbe pakietow", content[2])
		packetsAmount = content[2]
		for i = 1, packetsAmount do
			receivedPackets[i] = false
		end
		if packetsAmount * MTU > computer.freeMemory() + 512 then
			modem.send(msg[3], msg[6], port, codes.notEnoughMemory)
			modem.close(port)
			return false, messages.notEnoughMemory[1]
		else
			modem.send(msg[3], msg[6], port, codes.ok)
			print("wyslalem ok")
			while true do
				hops = hops + 1
				if hops > maxHops then
					modem.close(port)
					return false, messages.maxHopsReached[1]
				end
				repeat
					msg = getMessage(modem, port, maxTimeout)
					if msg == nil then
						modem.close(port)
						return false, messages.connectionTimeout[1]
					end
					if type(msg[7]) == "string" then
						content = serial.unserialize(msg[7])
						if content == nil then
							modem.close(port)
							return false, messages.unexpectedError[1]
						elseif content[1] == codes.packet and #content == 3 then
							print("odebralem "..content[2].." pakiet")
							receivedPackets[content[2]] = true
							data[content[2]] = content[3]
						else
							modem.close(port)
							return false, messages.malformedMessage[1]
						end
					end
				until msg[7] == codes.done
				print("odbieranie zakonczone")
				
				local missed = {}
				for n, c in ipairs(receivedPackets) do
					if not c then table.insert(missed, n) end
				end
				if #missed > 0 then
					modem.send(msg[3], msg[6], port, serial.serialize({codes.missing, missed}))
				else
					modem.send(msg[3], msg[6], port, codes.ok)
					modem.close(port)
					local output = ""
					for i = 1, #data do
						output = output..data[i]
					end
					return true, {msg[1], msg[2], msg[3], msg[4], msg[5], msg[6], output}
				end
			end
		end
	else
		modem.close(port)
		return false, messages.connectionTimeout[1]
	end
end

--[[
Wysyła wiadomość do odbiorcy
	Argumenty:
		@modem - modem, którym wiadomość będzie wysłana
		@address - adres odbiorcy lub nil
		@port - port, na który zostanie wysłana wiadomość
		@message - wiadomość do wysłania
	Zwraca:
		- true, gdy wiadomość została wysłana,
		- ( false, <kod błędu> ), gdy wiadomość nie została wysłana
]]
function rtpo.send(modem, address, port, message)
	local localPort = 0
	repeat
		localPort = math.random(10000, 65000)
	until localPort ~= port and not modem.isOpen(localPort)
	if address == nil then
		if not modem.broadcast(port, localPort, codes.echo) then return false, 0 end -- echo
	else
		if not modem.send(address, port, localPort, codes.echo) then return false, 0 end
	end
	
	local response = {}
	modem.open(localPort)
	response = getMessage(modem, localPort, maxTimeout)
	modem.close(localPort)
	if response == nil then return false, messages.connectionTimeout[1] end
	print("send: odebrano echo")
	local amount = math.ceil(message:len() / MTU) -- liczba pakietów do wysłania
	modem.open(localPort)
	modem.send(response[3], response[6], localPort, serial.serialize({codes.amount, amount}))
	response = getMessage(modem, localPort, maxTimeout)
	modem.close(localPort)
	if response == nil then return false, messages.connectionTimeout[1] end 
	if response[7] == codes.ok then
		-- wysyłanie pakietów
		print("rozpoczynam wysylanie")
		local packetsIDs = {}
		local hops = 0
		for counter = 1, amount do table.insert(packetsIDs, counter) end
		repeat
			hops = hops + 1
			modem.open(localPort)
			for _, packetNumber in ipairs(packetsIDs) do
				modem.send(response[3], response[6], localPort, serial.serialize({codes.packet, packetNumber, message:sub(((packetNumber - 1) * MTU) + 1, packetNumber * MTU)}))
				os.sleep(packetDelay)
				print("wyslano "..packetNumber.." pakiet")
			end
			modem.close(localPort)
			packetsIDs = {}
			modem.send(response[3], response[6], localPort, codes.done)
			response = getMessage(modem, localPort, maxTimeout)
			if response == nil then
				modem.close(localPort)
				return false, messages.connectionTimeout[1]
			elseif type(response[7]) == "string" then
				t = serial.unserialize(response[7])
				if t ~= nil then
					if t[1] == codes.missing then
						packetsIDs = response[2]
					else
						return false, messages.malformedMessage[1]
					end
				elseif type(response[7]) ~= "number" then
					return false, messages.unexpectedError[1]
				end
			end
			if hops > maxHops then
				modem.close(localPort)
				return false, messages.maxHopsReached[1]
			end
		until response[7] == codes.ok
		print("send: polaczenie zakonczone")
		modem.send(response[3], response[6], localPort, codes.quit)
		modem.close(localPort)
		return true
	elseif response[7] == codes.notEnoughMemory then
		return false, messages.notEnoughMemory[1]
	elseif response == nil then
		return false, messages.connectionTimeout[1]
	else
		return false, 0
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
		for i = 1, #messages do
			if messages[i][1] == code then return messages[i][2] end
		end
	end
	return "Nieznany blad"
end

return rtpo