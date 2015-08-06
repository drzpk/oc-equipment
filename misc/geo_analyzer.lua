--by: Aranthor
local wersja = "1.3"
local sArgs = {...}
if sArgs[1] == "version_check" then return wersja
else
	if sArgs[1] ~= nil then
		local num = tonumber(sArgs[1])
		if num ~= nil and num >= 0.33 and num <= 3 then holoSize = num end
	end
end

local term = require("term")
local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local serial = require("serialization")
local fs = require("filesystem")

if not component.isAvailable("data") and not component.isAvailable("os_datablock") then
	io.stderr:write("Program wymaga do działania karty lub bloku danych")
end
if component.isAvailable("hologram") then
	holo = component.hologram
end
if not component.isAvailable("geolyzer") then
	io.stderr:write("Nie wykryto komponentu geolyzer!")
	return
end

local holoSize = 1.9
local geo = component.geolyzer
local data = component.data or component.os_datablock
local object = {}

local function chooseRadius()
	term.write("\nWybierz obszar skanowania: ")
	term.write("\n1. 4x4")
	term.write("\n2. 10x10")
	term.write("\n3. 16x16")
	term.write("\n4. 32x32")
	term.write("\n5. 48x48")
	term.write("\n#> ")
	local choice = 0
	while choice == 0 do
		local ev = {event.pull("key_down")}
		if ev[4] == keyboard.keys["1"] then choice = 4
		elseif ev[4] == keyboard.keys["2"] then choice = 10 
		elseif ev[4] == keyboard.keys["3"] then choice = 16
		elseif ev[4] == keyboard.keys["4"] then choice = 32
		elseif ev[4] == keyboard.keys["5"] then choice = 48
		end
	end
	return choice
end

local function saveScan()
	term.write("\nWprowadź nazwę pliku: ")
	object.name = io.read()
	term.write("Wprowadź współrzędne pomiaru: ")
	object.coords = io.read()
	term.write("Wprowadź nazwę świata: ")
	object.world = io.read()
	term.write("Wprowadź opis pliku: ")
	object.desc = io.read()
	term.write("\nWybierz dysk do zapisu:")
	local available = {}
	for add in component.list("filesystem") do
		device = component.proxy(add)
		if not device.isReadOnly() and device.address ~= require("computer").tmpAddress() then
			table.insert(available, device.address)
		end
	end
	for i = 1, #available do
		term.write("\n" .. tostring(i) .. ". " .. available[i])
	end
	local disknum = 0
	while disknum == 0 do
		local ev = {event.pull("key_down")}
		local num = tonumber(string.char(ev[3]))
		if num then
			if num > 0 and num <= #available then disknum = num end
		end
	end
	if not fs.isDirectory("/mnt/" .. available[disknum]:sub(1, 3) .. "/scans") then
		fs.makeDirectory("/mnt/" .. available[disknum]:sub(1, 3) .. "/scans")
	end
	local file = io.open("/mnt/" .. available[disknum]:sub(1, 3) .. "/scans/" .. object.name .. ".scan", "w")
	file:write(serial.serialize(object))
	file:close()
	term.write("\n\nPlik zostal zapisany na dysku: " .. "/mnt/" .. available[disknum]:sub(1, 3) .. "/scans/" .. object.name .. ".scan")
end

local function main()
	term.write("\ngeo_analyzer     wersja " .. wersja)
	local radius = chooseRadius()
	term.write("\nAby rozpoczac skanowanie, nacisnij dowolny klawisz...")
	event.pull("key_down")
	term.write("\nAnaliza rozpoczeta.")
	object.scan = {}
	for x = 1, radius do
		local buffx = {}
		for y = 1, radius do
			local b2 = geo.scan(x - (radius / 2) - 1, y - (radius / 2) - 1)
			for t = 1, #b2 do
				b2[t] = math.floor(b2[t] + 0.5)
			end
			table.insert(buffx, b2)
		end
		term.clearLine()
		term.write("Postep skanowania: " .. tostring(math.floor((x / radius * 100) + 0.5)) .. "%")
		table.insert(object.scan, data.deflate(serial.serialize(buffx)))
	end
	term.write("\nAnaliza zakonczona.")
	local save = true
	local saved = false
	if holo then
		term.write("\nWykryto podlaczony projektor. Wybierz akcje: ")
		term.write("\n1. Zapisz skan")
		term.write("\n2. Wyswietl skan")
		local ch = 0
		while ch == 0 do
			local ev = {event.pull("key_down")}
			if ev[4] == keyboard.keys["1"] then ch = 1
			elseif ev[4] == keyboard.keys["2"] then ch = 2
			end
		end
		if ch == 2 then save = false end
	end
	if save then
		saveScan()
		saved = true
	else
		holo.clear()
		holo.setScale(holoSize)
		term.write("\n\nWyswietlanie skanu na hologramie...")
		term.write("\nStrzalkami w gore i w dol reguluj widok.")
		term.write("\nKlawisz s zapisuje skan.")
		term.write("\nKlawisz 'q' konczy projekcje.")
		local yOffset = 15
		local startPos = 24 - (#object.scan / 2)
		local run = true
		while run do
			for x = 1, #object.scan do
				local osd = serial.unserialize(data.inflate(object.scan[x]))
				for y = 1, #osd do
					for z = 1, 32 do
						local color
						if osd[y][z + yOffset] == 0 then color = 0
						elseif osd[y][z + yOffset] > 90 then color = 3
						elseif osd[y][z + yOffset] > 30 then color = 1
						else color = 2
						end
						holo.set(x + startPos, z, y + startPos, color)
					end
				end
			end
			while true do
				vv = {event.pull("key_down")}
				if vv[4] == keyboard.keys.up then
					if yOffset <= 30 then
						yOffset = yOffset + 2
						break
					end
				elseif vv[4] == keyboard.keys.down then
					if yOffset >= 2 then
						yOffset = yOffset - 2
						break
					end
				elseif vv[4] == keyboard.keys.s then
					if not saved then
						saveScan()
						saved = true
					else
						term.write("\nSkan zostal juz zapisany!")
					end
				elseif vv[4] == keyboard.keys.q then
					run = false
					break
				end
			end
		end
		holo.clear()
		term.write("\nProjekcja zakonczona.")
	end	
end

main()
