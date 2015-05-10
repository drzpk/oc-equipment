local event = require("event")
local term = require("term")
local key = require("keyboard")
local fs = require("filesystem")
local shell = require("shell")
local component = require("component")
local serial = require("serialization")
local modem = component.modem
local gpu = component.gpu

local wersja = "1.7"

local args, options = shell.parse(...)
if args[1]=="version_check" then return wersja end

if modem~=nil then
	if modem.isWireless()~=true	then modem=nil end
end

local res = {gpu.getResolution()}
local port = 1
local kod = 0

local changed = false

local function ladujConfig()
	if fs.exists(shell.resolve("config/iaConfig.cfg")) then
		local confFile = io.open("config/iaConfig.cfg","r")
		port = tonumber(confFile:read("*l"))
		kod = tonumber(confFile:read("*l"))
		confFile:close()
	end
end

local function zapiszConfig()
	if changed then
		if not fs.isDirectory("config") then fs.makeDirectory("config") end
		local file = io.open("config/iaConfig.cfg", "w")
		file:write(tostring(port).."\n"..(kod))
		file:close()
	end
end

local function wrt(x, y, str)
	term.setCursor(x,y)
	term.write(str)
end

local function draw()
	term.clear()
	gpu.fill(1, 1, res[1], 4, "=")
	gpu.fill(1, 2, res[1], 2, "|")
	gpu.fill(2, 2, res[1]-2, 2, " ")
	term.setCursor(3, 2)
	term.write("Iris Authenticator - program do zdalnego otwierania przesłony")
	wrt(3, 3, "Wersja " .. wersja)
	wrt(4, 7, "Port:  " .. tostring(port))
	wrt(4, 8, "Kod:   " .. tostring(kod))
	wrt(3, 10, "P - zmiana portu")
	wrt(3, 11, "K - zmiana kodu")
	wrt(3, 12, "S - wysłanie sygnalu")
	wrt(3, 13, "Q - wyjście z programu")
	wrt(1, 15, "--------")
	term.setCursor(2,16)
end

local function main()
	while true do
		draw()
		local ev = {event.pull("key_down")}
		if ev[4] == key.keys.p then
			term.write("Wprowadź nowy numer portu[10 000 - 65 530]: ")
			ret = tonumber(term.read())
			if ret~=nil then
				if ret >= 10000 and ret <= 65530 then
					port = ret
					changed = true
				else
					wrt(2, 17, "Wprowadzono niepoprawny numer portu!")
					os.sleep(2)
				end
			else
				wrt(2, 17, "Wprowadzono niepoprawny numer portu!")
				os.sleep(2)
			end
		elseif ev[4] == key.keys.k then
			term.write("Wprowadź nowy kod[10000 - 99 999]: ")
			ret = tonumber(term.read())
			if ret~=nil then
				if ret >= 10000 and ret <= 99999 then
					kod = ret
					changed = true
				else
					wrt(2, 17, "Wprowadzono niepoprawny kod!")
					os.sleep(2)
				end
			else
				wrt(2, 17, "Wprowadzono niepoprawny kod!")
				os.sleep(2)
			end
		elseif ev[4] == key.keys.s then
			if modem ~= nil then
				local localPort = 0
				repeat
					localPort = math.random(20000, 60000)
				until localPort ~= port and not modem.isOpen(localPort)
				modem.open(localPort)
				modem.broadcast(port, localPort, kod)
				wrt(2, 17, "Wiadomość została wysłana")
				evv = {event.pull(2, "modem_message")}
				if evv[1] == nil then
					wrt(4, 18, "Brak odpowiedzi!")
					os.sleep(2)
				else
					status = serial.unserialize(evv[6])
					if status[1] then
						wrt(4, 18, status[2])
						local czas = status[3] + 1
						while czas > -1 do
							wrt(4, 19, "Czas do zamknięcia przesłony: " .. czas .. " ")
							os.sleep(1)
							czas = czas - 1
						end
					else
						wrt(4, 18, status[2])
						os.sleep(2)
					end
				end
				modem.close(localPort)
			else
				wrt(2, 17, "Nie wykryto bezprzewodowego modemu!")
				os.sleep(2)
			end
		elseif ev[4] == key.keys.q then
			term.clear()
			term.setCursor(1, 1)
			return
		end
	end
end


ladujConfig()
main()
modem.close(port)
zapiszConfig()
