-- ##################################################
-- #                  Projector                     #
-- #                                                #
-- #  08.2015                      by: IlynPayne    #
-- ##################################################

local version = "1.0"
local args = {...}
if args[1] == "version_check" then return version end

local component = require("component")
local serial = require("serialization")
local event = require("event")
local fs = require("filesystem")
local term = require("term")
local keyboard = require("keyboard")

if not component.isAvailable("hologram") then
	io.stderr:write("Program wymaga do działania hologramu")
	return
elseif not component.isAvailable("data") and not component.isAvailable("os_datablock") then
	io.stderr:write("Program wymaga do działania karty lub bloku danych")
	return
end
local hologram = component.hologram
local data = component.data or component.os_datablock

local object = {}
local translation = {0, 0, 0}
local length = 0
local cut = {
	scale = 2,
	old = 2,
	y = 16,
	u = 0,
	d = 0,
	n = 0,
	s = 0,
	e = 0,
	w = 0
}

local function loadConfig()
	local f = io.open("/etc/projector.cfg", "r")
	if f then
		local buffer = serial.unserialize(f:read() or "")
		f:close()
		if buffer then
			if type(buffer.scale) == "number" and buffer.scale >= 0.33 and buffer.scale <= 3 then
				cut.scale = buffer.scale
				cut.old = buffer.scale
			end
			for i = 1, 3 do
				if type(buffer.translation[i]) == "number" and buffer.translation[i] >= -5 and buffer.translation[i] <= 5 then
					translation[i] = buffer.translation[i]
				end
			end
			hologram.setTranslation(table.unpack(translation))
		end
	end
end

local function saveConfig()
	if cut.scale ~= cut.old then
		local f = io.open("/etc/projector.cfg", "w")
		f:write(serial.serialize({scale = cut.scale, translation = translation}))
		f:close()
	end
end

local function usage()
	print("Projector   wersja " .. version)
	print("Użycie:")
	print("  projector <plik>")
end

local function refresh()
	hologram.clear()
	hologram.setScale(cut.scale)
	for x = 1 + cut.e, #object.scan - cut.w do
		local osd = serial.unserialize(data.inflate(object.scan[x]))
		for y = 1 + cut.s, #osd - cut.n do
			for z = 1 + cut.d, 32 - cut.u do
				local color
				if osd[y][z + cut.y] == 0 then color = 0
				elseif osd[y][z + cut.y] > 90 then color = 3
				elseif osd[y][z + cut.y] > 30 then color = 1
				else color = 2
				end
				hologram.set(x + length, z, y + length, color)
			end
		end
	end
end

local function project()
	while true do
		term.clear()
		term.setCursor(1, 1)
		print("     Projector   wersja " .. version)
		print("Informacje:")
		print("  Nazwa: " .. object.name or "")
		print("  Opis: " .. object.desc or "")
		print("  Świat: " .. object.world or "")
		print("  Współrzędne: " .. object.coords or "")
		print("Parametry:")
		print("  Skala: " .. tostring(cut.scale) .. "  (++, --)")
		print("  Przesunięcie Y: " .. tostring(cut.y) .. "  (+UP, -DOWN)")
		print("  Odcięcie U: " .. tostring(cut.u) .. "  (+U, -u)")
		print("  Odcięcie D: " .. tostring(cut.d) .. "  (+D, -d)")
		print("  Odcięcie N: " .. tostring(cut.n) .. "  (+N, -n)")
		print("  Odcięcie S: " .. tostring(cut.s) .. "  (+S, -s)")
		print("  Odcięcie E: " .. tostring(cut.e) .. "  (+E, -e)")
		print("  Odcięcie W: " .. tostring(cut.w) .. "  (+W, -w)")
		io.write("    R - odśwież projekcję, P - wyłącz projektor, Q - wyjście")
		local e = {event.pull("key_down")}
		if e[4] == keyboard.keys.equals and keyboard.isShiftDown() then
			if cut.scale == 0.33 then cut.scale = 0.5
			elseif cut.scale <= 2.5 then cut.scale = cut.scale + 0.5 end
		elseif e[4] == keyboard.keys.minus then
			if cut.scale == 0.5 then cut.scale = 0.33
			elseif cut.scale >= 1 then cut.scale = cut.scale - 0.5 end
		elseif e[4] == keyboard.keys.up then
			if cut.y < 16 then cut.y = cut.y + 1 end
		elseif e[4] == keyboard.keys.down then
			if cut.y > 0 then cut.y = cut.y - 1 end
		elseif e[4] == keyboard.keys.u and keyboard.isShiftDown() then
			if cut.u < 16 then cut.u = cut.u + 1 end
		elseif e[4] == keyboard.keys.u then
			if cut.u > 0 then cut.u = cut.u - 1 end
		elseif e[4] == keyboard.keys.d and keyboard.isShiftDown() then
			if cut.d < 16 then cut.d = cut.d + 1 end
		elseif e[4] == keyboard.keys.d then
			if cut.d > 0 then cut.d = cut.d - 1 end
		elseif e[4] == keyboard.keys.n and keyboard.isShiftDown() then
			if cut.n < -length + 24 then cut.n = cut.n + 1 end
		elseif e[4] == keyboard.keys.n then
			if cut.n > 0 then cut.n = cut.n - 1 end
		elseif e[4] == keyboard.keys.s and keyboard.isShiftDown() then
			if cut.s < -length + 24 then cut.s = cut.s + 1 end
		elseif e[4] == keyboard.keys.s then
			if cut.s > 0 then cut.s = cut.s - 1 end
		elseif e[4] == keyboard.keys.e and keyboard.isShiftDown() then
			if cut.e < -length + 24 then cut.e = cut.e + 1 end
		elseif e[4] == keyboard.keys.e then
			if cut.e > 0 then cut.e = cut.e - 1 end
		elseif e[4] == keyboard.keys.w and keyboard.isShiftDown() then
			if cut.w < -length + 24 then cut.w = cut.w + 1 end
		elseif e[4] == keyboard.keys.w then
			if cut.w > 0 then cut.w = cut.w - 1 end
		elseif e[4] == keyboard.keys.r then
			refresh()
		elseif e[4] == keyboard.keys.p then
			hologram.clear()
		elseif e[4] == keyboard.keys.q then
			break
		end
	end
	hologram.clear()
	hologram.setTranslation(0, 0, 0)
	term.clear()
	term.setCursor(1, 1)
end

local function main()
	if args[1] then
		local f = io.open(args[1], "r")
		if f then
			local input = serial.unserialize(f:read())
			f:close()
			if input and input.scan then
				object = input
				length = 24 - #object.scan / 2
				project()
			else
				io.stderr:write("Plik ma niewłaściwy format lub jest uszkodzony")
			end
		else
			io.stderr:write("Plik nie został znaleziony")
		end
	else
		usage()
	end
end

loadConfig()
main()
saveConfig()