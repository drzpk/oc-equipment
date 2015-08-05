local dataSrv2Address = 1
local version = "1"
local broadcastPort = 65533
local messages = {
	echo = 0x50f,
	ok = 0x5ea,
	color = 0x9bc,
	move = 0x19a6,
	mag = 0xb33d,
	alarm = 0x79ae,
	address = 0x812d,
	disable = 0x1a92
}
-------------------
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local dsapi = require("dsapi")
-------------------
local modem = component.modem
local rs = component.redstone

local serverPort = 0
local serverAddress = ""

local s, c = dsapi.get(dataSrv2Address, "the_guard/micro")
if s then
	local data = serialization.unserialize(c)
	if data then
		serverPort = data[1]
		serverAddress = data[2]
	else
		for i = 1, 3 do
			component.computer.beep(1500, 0.8)
			os.sleep(0.8)
		end
		return
	end
else
	for i = 1, 3 do
		component.computer.beep(1500, 0.8)
		os.sleep(0.8)
	end
	return
end

for i = 1, 15 do
	rs.setBundledOutput(2, i, 0)
end
for v, _ in pairs(component.list("os_alarm")) do
	component.proxy(v).deactivate()
end

event.timer(3, function()
	require("computer").pushSignal("timeup")
end)

local permission = false
local port = math.random(100, 59999)
modem.open(port)
modem.open(broadcastPort)
modem.send(serverAddress, serverPort, port, messages.echo, version)

local function searchAddress(name, address)
	local l = component.list(name)
	local amount, fullAddress = 0, nil
	for k, _ in pairs(l) do
		if k:find(address, 1) ~= nil or k == address then
			amount = amount + 1
			fullAddress = k
		end
	end
	return amount, fullAddress
end

--"modem_message", localAddress: string, remoteAddress: string, port: number, distance: number, remotePort: number, ...
while true do
	local e = {event.pull()}
	if e[1] == "modem_message" and e[3] == serverAddress and e[6] == serverPort then
		if e[7] == messages.ok then
			component.computer.beep(1500, 0.05)
			os.sleep(0.05)
			component.computer.beep(1500, 0.05)
			permission = true
		elseif e[7] == messages.echo then
			modem.send(serverAddress, serverPort, port, messages.echo, version)
		elseif e[7] == messages.color then
			pcall(rs.setBundledOutput, e[8], e[9], e[10])
			modem.send(serverAddress, serverPort, port, messages.ok)
			if e[11] ~= nil then
				local n = tonumber(e[11])
				if n > 0 and n < 15 then
					event.timer(n, function()
						pcall(rs.setBundledOutput, e[8], e[9], 0)
					end)
				end
			end
		elseif e[7] == messages.alarm then
			modem.send(serverAddress, serverPort, port, messages.ok)
			for v, _ in pairs(component.list("os_alarm")) do
				local a = component.proxy(v)
				if e[8] then
					a.setRange(64)
					a.activate()
					rs.setBundledOutput(2, 4, 250)
				else
					a.deactivate()
					rs.setBundledOutput(2, 4, 0)
				end
			end
		elseif e[7] == messages.address and type(e[8]) == "string" then
			local amount, address = searchAddress("os_magreader", e[8])
			if amount > 0 then
				modem.send(serverAddress, serverPort, port, messages.address, amount, address)
			end
		elseif e[7] == messages.disable then
			break
		end
	elseif e[1] == "motion" then
		modem.send(serverAddress, serverPort, port, messages.move, serialization.serialize(e))
	elseif e[1] == "magData" then
		modem.send(serverAddress, serverPort, port, messages.mag, serialization.serialize(e))
	elseif e[1] == "key_down" then
		break
	elseif e[1] == "timeup" and not permission then
		component.computer.beep(1500, 3)
		break
	end
end
modem.close(port)
modem.close(broadcastPort)