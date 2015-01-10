--by: Admox
local event = require("event")
local serial = require("serialization")
local component = require("component")

local modem = component.modem

local wersja = "1.3"

local argss = (...)
if argss[1] == "version_check" then return wersja end

local ds = {}

local ds_code = 
{
	--Lista zapywañ do serwera		>>	SKOPIOWANO Z PLIKU DATA_SERVER.LUA, WERSJA 0.1.0alpha	<<
	getFile = 0x01, --parametry: folder, uuid   odpowiedŸ: status, plik lub nil
	setFile = 0x02, --parametry: folder lub nil, treœæ pliku   odpowiedŸ: status, uuid lub nil
	delFile = 0x03,  --parametry: folder, uuid pliku
	unused_1 = 0x04,
	getFileSize = 0x05,  --parametry: folder, uuid
	getFolder = 0x06, --parametry: uuid, nil     odpowiedŸ: status, lista plików w folderze lub nil
	setFolder = 0x07, --parametry: nil    odpowiedŸ: status, uuid lub nil
	delFolder = 0x08, --parametry: uuid folderu
	getFolderSize = 0x09,  --zwraca iloœæ plików w folderze
	
	checkServer = 0x1d, --sprawdzenie, czy serwer jest online
	getFreeMemory = 0x1e, --zapytanie o iloœæ dostêpnego miejsca w bajtach
	getVersion = 0x1f, --zapytanie o wersjê serwera danych
	
	--Lista odpowiedzi serwera
	success = 0x20, --operacja zakoñczona pomyœlnie
	deined = 0x21, --odmowa dostêpu
	notEnoughMemory = 0x22, --brak pamiêci na serwerze
	notFound = 0x23, --nie znaleziono pliku lub folderu o podanym numerze uuid
	failed = 0x24, --inny nieznany b³¹d
	requestNotFound = 0x25,  --nie odnaleziono zapytania
	online = 0x26,  --serwer jest online
	version = 0x27,  --wersja serwera, parametr: wersja
	notReady = 0x28,  --serwer nie jest gotowy do pracy, np. nie ma dostêpnych dysków
	badTarget = 0x29,  --cel jest inny ni¿ oczekiwano, np. plik jest folderem
	badRequest = 0x2a  --zapytanie jest niekompletne, brakuje danych
}

local desc =
{
	success = {true,"Operacja zakonczona pomyslnie."},
	deined = {false,"Odmowa dostepu."},
	notEnoughMemory = {false,"Brak pamieci na serwerze."},
	notFound = {false,"Zadany element nie zosta³ odnaleziony."},
	failed = {false,"Nieznany blad."},
	requestNotFound = {false,"Nie odnaleziono zapytania na serwerze."},
	online = {true,"Serwer jest online."},
	version = {true,"Sprawdzenie wersji serwera."},
	notReady = {false,"Serwer nie jest gotowy."},
	badTarget = {false,"Wskazany obiekt jest inny, ni¿ oczekiwano."},
	badRequest = {false,"Zapytanie jest niekompletne."}
}

local function translateAnwser(anw)
	return desc[anw]
end

local function sendM(inst, msgTable)
	local reqCode = msgTable[1]
	modem.open(inst.local_port)
	local anwser = nil
	modem.broadcast(inst.port, serial.serialize(msgTable), inst.local_port)
	local even = {event.pull(inst.timeout, "modem_message")}
	if #even == 0 then return nil end
	--print("DEBUG: "..serial.serialize(even))
	anwser = serial.unserialize(even[6])
	modem.close(inst.local_port)
	return anwser
end

local function findRequest(code)
	for name, hex in pairs(ds_code) do
		if code == hex then return name end
	end
	return "failed"
end

--[[
Funkcja zwraca tablicê:
[1] = powodzenie zapytania (true/false)
[2] = Opis b³êdu lub wartoœæ zwrócona przez serwer
	Przyk³adowe u¿ycie:
		ds = require("ds-api")
		core = ds.create(10000) -- numer portu
		response = {ds:getFile(nil, "fj3j53l0f")} --ospowiedŸ api
]]
local function request(core, msgTable)
	local ans = sendM(core, msgTable)
	if ans == nil then return {false,"Nie mozna po³aczyc siê z serwerem."} end
	local ret = translateAnwser(findRequest(ans[1]))
	if ret[1] then
		return ret[1], ans[3]
	else
		return table.unpack(ret)
	end
end

local function createCore(portn)
	if type(portn) ~= "number" or portn < 10000 or portn > 60000 then
		io.stderr:write("\nB³êdny port.")
		return
	end
	local cor = 
	{
		local_port = math.random(10000, 60000),
		port = portn,
		timeout = 2
	}
	cor.request = request
	
	return cor
end

--Pobiera zawartoœæ pliku.				Parametry: folder(jeœli brak - nil), uuid
local function getFile(core, folder, uuid)
	return core:request({ds_code.getFile, folder, uuid}) --return: zawartoœæ pliku
end

--Wysy³a plik na serwer.				Parametry: folder(jeœli brak - nil), zawartoœæ pliku
local function setFile(core, folder, content)
	return core:request({ds_code.setFile, folder, content}) --return: uuid nowego pliku
end

--Usuwa plik z serwera.					Parametry: folder(jeœli brak - nil), uuid
local function delFile(core, folder, uuid)
	return core:request({ds_code.delFile, folder, uuid}) --return: nil
end

--Pobiera rozmiar pliku.				Parametry: folder(jeœli brak - nil), uuid	
local function getFileSize(core, folder, uuid)
	return core:request({ds_code.getFileSize, folder, uuid}) --return: rozmiar pliku
end

--Pobiera listê plików w folderze.		Parametry: uuid
local function getFolder(core, uuid)
	return core:request({ds_code.getFolder, uuid, nil}) --return: tablica z list¹ plików
end

--Tworzy nowy folder na serwerze.		Parametry: nil
local function setFolder(core)
	return core:request({ds_code.setFolder, nil, nil}) --return: uuid nowego folderu
end

--Usuwa folder z serwera				Parametry: uuid
local function delFolder(core, uuid)
	return core:request({ds_code.delFolder, uuid, nil}) --return: nil
end

--Zwraca iloœæ plików w folderze		Parametry: uuid
local function getFolderSize(code, uuid)
	return core:request({ds_code.getFolderSize, uuid, nil}) --return: iloœæ plików
end

--Sprawdza, czy serwer jest online		Parametry: nil
local function checkServer(core)
	return core:request({ds_code.checkServer, nil, nil}) --return: kod odpowiedzi 'online'
end

--Zwraca iloœæ dostêpnego miejsca		Parametry: nil
local function getFreeMemory(core)
	return core:request({ds_code.getFreeMemory, nil, nil}) --return: iloœæ dostêpnego miejsca w bajtach
end

--Zaraca aktualn¹ wersjê serwera		Parametry: nil
local function getVersion(core)
	return core:request({ds_code.getVersion, nil, nil}) --return: wersja serwera danych
end

function ds.create(port)
	if modem == nil then return nil end
	local core = createCore(port)
	core.getFile = getFile
	core.setFile = setFile
	core.delFile = delFile
	core.getFileSize = getFileSize
	core.setFolder = setFolder
	core.delFolder = delFolder
	core.getFolderSize = getFolderSize
	core.checkServer = checkServer
	core.getFreeMemory = getFreeMemory
	core.getVersion = getVersion
	
	return core
end

return ds