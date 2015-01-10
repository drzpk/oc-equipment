--by: Admox
local fs = require("filesystem")
local component = require("component")
local term = require("term")
local shell = require("shell")
local ds = require("ds-api")

local modem = component.modem
local gpu = component.gpu

if modem == nil then
	io.stderr:write("Program wymaga do dzia³ania modemu.")
	return
end

local args, options = shell.parse(...)

local wersja = "1.1"

if args[1] == "version_check" then return wersja end

local colors = 
{
	red = 0xff0000,
	green = 0x00ff00,
	blue = 0x4747ff,
	yellow = 0xffff00,
	gray = 0xbebebe,
	black = 0x000000,
	white = 0xffffff,
	cyan = 0x66ccff
}

local function setColor(color)
	if gpu.maxDepth() > 1 then return gpu.setForeground(color) end
end

local function printUsage()
	term.write("\nKlient serwera danych, wersja "..wersja)
	term.write("\nDostepne komendy:")
	term.write("\nds-manager getFile <uuid> [<nazwa pliku>] - pobiera klucz z serwera")
	term.write("\nds-manager setFile <nazwa pliku> [-s] - zapisuje klucz na serwerze. Opcja 's' pobiera ciag znaków zamiast pliku")
	term.write("\nds-manager delFile <uuid> - usuwa klucz z serwera")
	term.write("\nds-manager getFileSize <nazwa pliku> - pobiera rozmiar klucza")
end

local function getPort()
	if not fs.exists("/tmp/dsmanportnum") then
		local port = 0
		term.write("\n")
		while port == 0 do
			term.write("Podaj numer portu serwera [10'000-60'000]: ")
			buff = io.read()
			buff = tonumber(buff)
			if buff ~= nil then port = buff end
			if port > 60000 or port < 10000 then port = 0 end
		end
		manFile = io.open("/tmp/dsmanportnum", "w")
		manFile:write(tostring(port))
		manFile:close()
		return port
	else
		manFile = io.open("/tmp/dsmanportnum", "r")
		local port = tonumber(namFile:read())
		namFile:close()
		return port
	end
end

local function getFile(uuid, name)
	core = ds.create(getPort())
	local resp = {core:getFile(nil, uuid)}
	if resp[1] then
		if name ~= nil then
			if fs.exists(shell.resolve(name)) then
				setColor(colors.red)
				term.write("\nPlik o takiej nazwie ju¿ instnieje.")
				return
			end
			local file = io.open(name, "w")
			file:write(resp[2])
			file:close()
			setColor(colors.green)
			term.write("\nPomyslnie zapisano klucz do pliku.")
		else
			setColor(colors.blue)
			term.write("\nOdpowiedÅº serwera: ")
			setColor(colors.gray)
			term.write(resp[2])
		end
	else
		setColor(colors.red)
		term.write("\nNie udalo sie pobrac klucza z serwera.")
		setColor(colors.yellow)
		term.write("\nPrzyczyna: ")
		setColor(colors.gray)
		term.write(resp[2])
	end
end

local function setFile(name, str)
	core = ds.create(getPort())
	local to_send = ""
	if str then
		to_send = name
	else
		if fs.exists(shell.resolve(name)) then
			local file = io.open(name, "r")
			to_send = file:read("*a")
			file:close()
		else
			setColor(colors.red)
			term.write("\nPlik o takiej nazwie nie instnieje.")
			return
		end
	end
	local resp = {core:setFile(nil, to_send)}
	if resp[1] then
		setColor(colors.green)
		term.write("\nPomyslnie wyslano klucz na serwer.")
		setColor(colors.cyan)
		term.write("\nUUID danych: ")
		setColor(colors.gray)
		term.write(resp[2])
	else
		setColor(colors.red)
		term.write("\nNie udalo sie wyslac klucza na serwer.")
		setColor(colors.yellow)
		term.write("\nPrzyczyna: ")
		setColor(colors.gray)
		term.write(resp[2])
	end
end

local function delFile(name)
	core = ds.create(getPort())
	local resp = {core:delFile(nil, name)}
	if resp[1] then
		setColor(colors.green)
		term.write("\nPomyslnie usunieto klucz "..name.." z serwera.")
	else
		setColor(colors.red)
		term.write("\nNie udalo sie usunac klucza z serwera.")
		setColor(colors.yellow)
		term.write("\nPrzyczyna: ")
		setColor(colors.gray)
		term.write(resp[2])
	end
end

local function getFileSize(name)
	core = ds.create(getPort())
	local resp = {core:getFileSize(nil, name)}
	if resp[1] then
		setColor(colors.green)
		term.write("\nPobrano rozmiar klucza z serwera.")
		setColor(colors.cyan)
		term.write("\nPrzyczyna: ")
		setColor(colors.gray)
		term.write(resp[2])
	else
		setColor(colors.red)
		term.write("\nNie udalo sie pobrac rozmiaru klucza.")
		setColor(colors.yellow)
		term.write("\nPrzyczyna: ")
		setColor(colors.gray)
		term.write(resp[2])
	end
end

local function main()
	if #args > 0 then
		args[1] = args[1]:lower()
		if args[1] == "getfile" then getFile(args[2], args[3])
		elseif args[1] == "setfile" then setFile(args[2], options.s)
		elseif args[1] == "delfile" then delFile(args[2])
		elseif args[1] == "getfilesize" then getFileSize(args[2])
		else
			printUsage()
		end
	else
		printUsage()
	end
end

main()