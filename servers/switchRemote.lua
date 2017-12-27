-- ################################################
-- #              Switch Remote                   #
-- #                                              #
-- #  07.2015                      by: IlynPayne  #
-- ################################################

--[[
	#Opis programu
		Program służy do zdalnego kontrolowania przełączników
		aplikacji The Switch
]]

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local event = require("event")
local serial = require("serialization")
local fs = require("filesystem")
if not component.isAvailable("modem") then
	io.stderr:write("Program wymaga do dzialania karty sieciowej")
	return
end
local modem = component.modem
local serverPort = 0

local actions = {
	{"status", nil},
	{"true", true},
	{"false", false}
}

local targets = {
	{"door", 0x1},
	--{"lock", 0x2},
	{"light", 0x3},
	{"green", 0x4},
	{"red", 0x5},
	{"blue", 0x6},
	{"yellow", 0x7}
}

local function loadConfig()
	if _G["swremPort"] ~= nil and tonumber(_G["swremPort"]) ~= nil then
		serverPort = tonumber(_G["swremPort"])
	elseif fs.exists("/etc/swrem.cfg") then
		local file = io.open("/etc/swrem.cfg", "r")
		local fc = f:read()
		f:close()
		if tonumber(fc) ~= nil then
			serverPort = tonumber(fc)
			_G["swremPort"] = serverPort
		else
			local file = io.open("/etc/swrem.cfg", "w")
			file:write("0")
			file:close()
		end
	end
end

local function saveConfig()
	_G["swremPort"] = serverPort
	local file = io.open("/etc/swrem.cfg", "w")
	file:write(tostring(serverPort))
	file:close()
end

local function sendData(action, target, id)
	local port = math.random(1, 65535)
	modem.open(port)
	modem.broadcast(serverPort, port, serial.serialize({target, id, action}))
	local e = {event.pull(2, "modem_message")}
	modem.close(port)
	if #e > 0 then
		return serial.unserialize(e[7])
	else
		return nil
	end
end

local function usage()
	print("Uzycie programu:")
	print("  switchRemote <akcja> <cel> <id>")
	print()
	print("<akcja> moze przyjac jedna z nastepujacych wartosci:")
	print("  status - sprawdza status celu")
	print("  true - otwiera / wlacza wybrany cel")
	print("  false - zamyka / wylacza wybrany cel")
	print("<cel> moze przyjac jedna z nastepujacych wartosci:")
	print("  door - drzwi")
	--print("  lock - blokada drzwi")
	print("  light - swiatlo")
	print("  green/red/blue/yellow - przelacznik koloru")
	print("<id> to unikatowy identyfikator pomieszczenia")
	print()
	print("Wyswietlenie lub zmiana portu serwera:")
	print("  switchRemote port [port]")
end

local function main()
	if serverPort == 0 and #args ~= 2 and args[1] ~= "port" then
		print("Brak przypisanego portu serwera. Przypisz port:")
		print("  switchRemote port <port>")
		return
	end
	if #args == 3 then
		local a, t, i = 0, 0, 0
		for i = 1, #actions do
			if actions[i][1] == args[1] then
				a = actions[i][2]
				break
			end
		end
		for i = 1, #targets do
			if targets[i][1] == args[2] then
				t = targets[i][2]
				break
			end
		end
		i = tonumber(args[3])
		if a ~= 0 and t ~= 0 and i ~= nil then
			local r = sendData(a, t, i)
			print()
			if r ~= nil then
				if r[1] then
					if a == nil then
						print("Status: " .. tostring(r[2]))
					else
						print("Polecenie zostalo wykonane pomyslnie")
					end
				else
					print("Blad " .. r[2][1] .. ": " .. r[2][2])
				end
			else
				print("Serwer jest niedostepny")
			end
		else
			usage()
		end
	elseif #args == 1 and args[1] == "port" then
		print("Numer portu: " .. serverPort)
	elseif #args == 2 and args[1] == "port" and tonumber(args[2]) ~= nil then
		local num = tonumber(args[2])
		if num > 0 then
			serverPort = num
			saveConfig()
			print("Port zostal zapisany")
		else
			print("Wpisz poprawny port")
		end
	else
		usage()
	end
end

loadConfig()
main()