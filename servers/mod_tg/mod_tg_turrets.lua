-- ############################################
-- #			mod_tg_turrets				  #
-- #										  #
-- #  05.2016			   by:Dominik Rzepka  #
-- ############################################

--[[
	## Description ##
		The mod_tg_turrets is a module used by the_guard server (since 2.0).
		It allows to manage energy turrets and motion detectors (from "OpenSecurity")
		
		Two types of motion detectors are supported (both from "OpenSecurity"):
		* 'motion sensor'
		* 'entity detector'
		
		First of them is used to detect movement and trigger actions
		assigned to it. The latter is used to scan area near security
		turrets (scan interval is configurable: 0.5 - 3s).
		
		Target selection mechanism can work in one of three dirrefent modes:
		* 1 (none) - attacks all entities
		* 2 (white) - attacks all entities except those on list
		* 3 (black) - attack only entities from list
		
	## Actions ##
		- enableTurrets() - enables turrets
		- disableTurrent() - disables turrets
		- enableSensors() - turns on motion detectors
		- disableSensors() - turns off motion detectors
		- setTurretsMode(mode:number) - sets turrets mode (ses the description above)
		- setSensorsMode(mode:number) - sets motion sensors mode (same turrets mode)
		
	## Functions ##
		* energy turret support (up to 12)
		* motion sensor support (up to 12 of each type)
		* adjustable turret activation time (15sec - 3min)
		* adjustable motion sensor activation time (15sec - 3min)
		* every motion sensor supports up to 3 enable and disable actions
		* adjustable entity detector scan interval (1s - 15s)
		* adjustable entity detector scan range (5 - 20 blocks)
		* adjustable motion sensor sensitivity (0.1 - 10)
		
	## Configuration scheme ##
		config { - default configuration file
			turretsState:boolean - whether turrets are active
			sensorsState:boolean - whether sensors are active
			turretsMode:number - turret target selection mode
			sensorsMode:number - motion sensor target selection mode
			sensitivity:number - motion sensor sensitivity
			delay:number - entity detector scan interval
			range:number - entity detector scan range
			turretsActive:number - turrets activation time (how long they will work since their activation)
			sensorsActive:number - sensors activation time (how long they will work since their actication)
		}
		
		Every additional configuration files below are encrypted.
		
		turrets: { - energy turrets (modules/turrets/turrets.dat)
			{
				name:string - turret name
				uid:string - turret component uid
				detectorUid:string - entity detector uid
				upside:boolean - whether turret is upside down
				hidden:boolean - whether turret is hidden in blocks (shaft length purposes)
				walls: { - walls around turret
					t:boolean - top
					b:boolean - bottom
					n:boolean - north
					s:boolean - south
					e:boolean - east
					w:boolean - west
				}
			}
			...
		}
		
		sensors: { - motion sensors (modules/turrets/sensors.dat)
			{
				name:string - sensor name
				uid:string - sensor component uid
				enable { - enable actions
					{
						id:number - action id
						p1:any - 1st parameter
						p2:any - 2nd parameter
					}
					...
				}
				disable { - disable actions
					{
						id:number - action id
						p1:any - 1st parameter
						p2:any - 2nd parameter
					}
					...
				}
			}
			...
		}
		
		lists: { - target lists (modules/turrets/lists.dat)
			turrets: {
				black: {
					[1]:string - object name
					...
				}
				white: {
					[1]:string - object name
				}
			}
			sensors: {
				black: {
					[1]:string - object name
				}
				white: {
					[1]:string - object name
				}
			}
		}
		
	## Cache ##
		In order to search turrets connected to specific detector faster, the module
		uses the following cache schema to store addresses:
		cache: {
			{
				[0]: detector
				[1]: { - turret
					index:number
					x:number
					y:number
					z:number
				}
				[2]: { - turret
					index:number
					x:number
					y:number
					z:number
				}
				...
			}
			...
		}
]]

local version = "1.3"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")
local serial = require("serialization")
local event = require("event")
local fs = require("filesystem")
local gml = require("gml")
local data = component.data

local mod = {}
local server = nil
local config = nil

local turrets = nil
local sensors = nil
local lists = nil
local cache = nil

local timer = nil
local tamount = nil


local excluded = { -- elements (unlocalized names) excluded from entity detector scanning (for turrets)
	"Kula doświadczenia",
	"Experience orb",
	"item%..*",
	"item%.item%..*",
	"entity%.opensecurity%..*",
	"entity.sgcraft.Stargate Iris.name",
	"entity.stargate_iris.name"
}
local targetHeight = 0.75 -- target height
local attemptDelay = 0.2 -- interval between turret fire attempts
local maxAttempts = 4 -- maximum number of fire attempts


local lbox, rbox, element = nil, nil, {}

local function encrypt(d)
	local s, ser = pcall(serial.serialize, d)
	if s then
		local s, enc = pcall(data.encrypt, ser, server.secretKey(mod), data.md5("turrets"))
		if s then
			local s, b = pcall(data.encode64, enc)
			if s then
				return b
			end
		end
	end
	return nil
end

local function decrypt(d)
	local s, b = pcall(data.decode64, d)
	if s then
		local s, dec = pcall(data.decrypt, b, server.secretKey(mod), data.md5("turrets"))
		if s then
			local s, tab = pcall(serial.unserialize, dec)
			if s then
				return tab
			end
		end
	end
	return nil
end

local function syncTurrets()
	for _, c in pairs(turrets) do
		local sync = server.getComponent(mod, c.uid, true)
		local sync2 = server.getComponent(mod, c.detectorUid, true)
		if sync then
			c.missing = false
			c.address = sync.address
		else
			c.missing = true
		end
		if sync2 then
			c.detector = sync2.address
		end
	end
end

local function syncSensors()
	for _, c in pairs(sensors) do
		local sync = server.getComponent(mod, c.uid)
		if sync then
			c.missing = false
			c.address = sync.address
		else
			c.missing = true
		end
	end
end

local function saveData()
	local dir = server.getConfigDirectory(mod)
	
	local function sf(tab, filename)
		local enc = encrypt(tab)
		if enc then
			local f = io.open(fs.concat(dir, filename .. ".dat"), "w")
			if f then
				f:write(enc)
				f:close()
			else
				server.log(mod, "Couldn't open file: " .. filename)
			end
		else
			server.log(mod, "Couldn't encrypt data to file " .. filename)
		end
	end
	
	sf(turrets, "turrets")
	sf(sensors, "sensors")
	sf(lists, "lists")
end

local function loadData()
	local dir = server.getConfigDirectory(mod)
	
	local function lf(filename)
		local path = fs.concat(dir, filename .. ".dat")
		if not fs.exists(path) then return {}
		elseif fs.isDirectory(path) then
			server.log(mod, "Element " .. path .. " cannot be a directory!")
		end
		local f = io.open(path, "r")
		if f then
			local d = decrypt(f:read("*a"))
			if d then
				return d
			else
				server.log(mod, "Couldn't decrypt file " .. filename)
				return {}
			end
		else
			server.log(mod, "Couldn't open data file.")
		end
	end
	
	turrets = lf("turrets")
	sensors = lf("sensors")
	lists = lf("lists")
end

local function rebuildCache()
	cache = {}
	local detectors = server.getComponentList(mod, "os_entdetector")
	if #detectors == 0 then return end
	local function ca(a)
		return a and type(a) == "number"
	end
	for _, t in pairs(detectors) do
		local d = {t.address}
		for a, t2 in pairs(turrets) do
			if t.address == t2.detector then
				local det = server.findComponents(mod, t2.address)
				if #det > 1 then
					error("An error occurred in the findComponents function")
					return
				elseif #det == 1 and ca(det[1].x) and ca(det[1].y) and ca(det[1].z) then
					local su = {
						index = a,
						x = det[1].x,
						y = det[1].y,
						z = det[1].z
					}
					table.insert(d, su)
				end
			end
		end
		if #d > 1 then
			table.insert(cache, d)
		end
	end
end

local function refreshView()
	if element[1] and element[2] then
		element[1].text = config.turretsState and "enabled" or "disabled"
		element[1]:draw()
		element[2].text = config.sensorsState and "enabled" or "disabled"
		element[2]:draw()
	end
end

local function rebuildTable(tab, target)
	local f = {}
	local index = 0
	for _, t in pairs(tab) do
		index = index + 1
		table.insert(f, tostring(index) .. ". " .. t.name)
	end
	target:updateList(f)
end

local function getIndex(str)
	local m = tonumber(string.match(str or "", "^(%d)%."))
	return m or 0
end

--[[local function getTurret(addr)
	for _, t in pairs(turrets) do
		if t.address == addr then
			return t
		end
	end
	return nil
end]]

local function openTurret(addr)
	local proxy = component.proxy(addr)
	if not proxy then return end
	proxy.powerOn()
	pcall(proxy.moveTo, 0, 0)
	proxy.extendShaft(0)
	proxy.setArmed(false)
end

local function closeTurret(addr)
	local proxy = component.proxy(addr)
	if not proxy then return end
	pcall(proxy.moveTo, 0, 0)
	proxy.extendShaft(1)
	event.timer(1.5, function() proxy.powerOff() end)
end

local function refreshSensors()
	for _, t in pairs(sensors) do
		local proxy = component.proxy(t.address or "")
		if proxy then
			proxy.setSensitivity(config.sensitivity)
		end
	end
end

local function disableTurrets()
	event.cancel(timer)
	timer = nil
	for _, t in pairs(turrets) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.extendShaft(0)
			proxy.setArmed(false)
		end
	end
	config.turretsState = false
	refreshView()
end

local function calcValues(turret, target)
	local a = target.x - (turret.x + 0.5)
	local b = (turret.z + 0.5) - target.z
	local c = math.sqrt(a * a + b * b)
	local angle = math.floor(math.atan2(a, b) * 180 / math.pi * 10) / 10
	local h = target.y + targetHeight
	local dh = turret.hidden and 1.375 or 1
	h = h - turret.y - (turret.upside and -dh or dh)
	local pitch = math.floor(math.atan(h / c) * 180 / math.pi * 10) / 10
	return angle, pitch
end

local function getEntities(adr)
	local proxy = component.proxy(adr or "")
	if not proxy then return end
	local s, entities = pcall(proxy.scanEntities, config.range)
	if s then
		local removal = {}
		for a, t in pairs(entities) do
			for _, s in pairs(excluded) do
				if t.name:match(s) then
					table.insert(removal, a)
					break
				end
			end
		end
		table.sort(removal, function(a, b) return a > b end)
		for _, b in pairs(removal) do table.remove(entities, b) end
		removal = {}
		if config.turretsMode == 2 then
			--white
			for a, t in pairs(entities) do
				for _, w in pairs(lists.turrets.white) do
					if t.name == w then
						table.insert(removal, a)
						break
					end
				end
			end
		elseif config.turretsMode == 3 then
			--black
			for a, t in pairs(entities) do
				local found = false
				for _, b in pairs(lists.turrets.black) do
					if a.name == b then
						found = true
						break
					end
				end
				if not found then
					table.insert(removal, a)
				end
			end
		end
		table.sort(removal, function(a, b) return a > b end)
		for _, b in pairs(removal) do table.remove(entities, b) end
		table.sort(entities, function(a, b) return a.range < b.range end)
		return entities
	else
		server.call(mod, 5204, "Not enough energy to continue scanning.", "turrets", true)
		event.cancel(timer)
		timer = nil
		disableTurrets()
		refreshView()
		return
	end
end

local function launch(turret, attempt)
	if attempt == 0 then
		if not turret.isReady() then
			server.call(mod, 5202, "Turret " .. turret.name .. "'s cooldown is too slow!", "turrets", true)
		end
		return 
	end
	if turret.isOnTarget() and turret.isReady() then
		local s, r = pcall(turret.fire)
		if not s and r == "not enough energy" then
			server.call(mod, 5203, "Not enough energy to keep turrets enabled.", "turrets", true)
			disableTurrets()
			return
		end
	else
		event.timer(attemptDelay, function() launch(turret, attempt - 1) end)
	end
end

local function turretsLoop()
	if tamount <= 0 then
		disableTurrets()
		return
	end
	tamount = tamount - 1
	
	local function checkYaw(angle, turret)
		if (angle >= -45 and angle <= 0) or (angle >= 0 and angle < 45) then
			return not turret.walls.n
		elseif angle >= 45 and angle < 135 then
			return not turret.walls.e
		elseif (angle >= 135 and angle <= 180) or (angle >= -180 and angle < -135) then
			return not turret.walls.s
		elseif angle >= -135 and angle < -45 then
			return not turret.walls.w
		end
		return false
	end
	local function checkPitch(angle, turret)
		if turret.upside then
			return angle <= 45 and angle >= -90
		else
			return angle >= -45 and angle <= 90
		end
	end
	for _, t in pairs(cache) do
		local entities = getEntities(t[1])
		if entities then
			for i = 2, #t do
				local pointer = t[i]
				local turret = turrets[pointer.index] or {}
				local proxy = component.proxy(turret.address or "")
				if proxy then
					for j = 1, #entities do
						local angle, pitch = calcValues(pointer, entities[j])
						if checkYaw(angle, turret) and checkPitch(pitch, turret) then
							--server.call(mod, 5201, "wykryto: " .. entities[j].name, "turretsLoop", true)
							if not proxy.isPowered() then
								proxy.powerOn()
							end
							proxy.setArmed(true)
							pcall(proxy.moveTo, angle, pitch)
							event.timer(attemptDelay, function() launch(proxy, maxAttempts) end)
							break
						end
					end
				end
			end
		end
	end
end

local function enableTurrets()
	for _, t in pairs(turrets) do
		local proxy = component.proxy(t.address)
		if proxy then
			if not proxy.isPowered() then
				proxy.powerOn()
			end
			if t.hidden then
				proxy.extendShaft(2)
			else
				proxy.extendShaft(1)
			end
			proxy.setArmed(true)
			if not t.walls.n then
				pcall(proxy.moveTo, 0, 0)
			elseif not t.walls.s then
				pcall(proxy.moveTo, 180, 0)
			elseif not t.walls.e then
				pcall(proxy.moveTo, 90, 0)
			elseif not t.walls.w then
				pcall(proxy.moveTo, 270, 0)
			end
		else
			server.call(mod, 5202, "Turret " .. t.name .. " is offline.", "turrets", true)
		end
	end
	local amount = nil
	if config.turretsActive == 0 then
		amount = math.huge
	else
		amount = math.ceil(config.turretsActive / config.delay)
	end
	timer = event.timer(config.delay, turretsLoop, math.huge)
	tamount = amount
	config.turretsState = true
	refreshView()
end

local function enableSensors()
	server.registerEvent(mod, "motion")
	config.sensorsState = true
	refreshView()
end

local function disableSensors()
	server.unregisterEvent(mod, "motion")
	config.sensorsState = false
	refreshView()
end

local function listTemplate(item)
	local ret = {}
	ret.black = {}
	ret.white = {}
	if item then
		for a, b in pairs(item.black or {}) do
			ret.black[a] = b
		end
		for a, b in pairs(item.white or {}) do
			ret.white[a] = b
		end
	end
	local lb, rb = nil, nil
	local function refreshLists()
		lb:updateList(ret.black)
		rb:updateList(ret.white)
	end
	local function addDialog()
		local ret = ""
		local agui = gml.create("center", "center", 40, 7)
		agui.style = server.getStyle(mod)
		agui:addLabel("center", 1, 14, "Enter a name:")
		local field = agui:addTextField("center", 3, 24)
		agui:addButton(24, 5, 14, 1, "Cancel", function()
			ret = nil
			agui:close()
		end)
		agui:addButton(8, 5, 14, 1, "Apply", function()
			local n = field.text
			if n:len() == 0 then
				server.messageBox(mod, "Enter a name.", {"OK"})
			elseif n:len() > 20 then
				server.messageBox(mod, "Name cannot be longer than 20 characters.", {"OK"})
			else
				ret = n
				agui:close()
			end
		end)
		agui:run()
		return ret
	end
	local function addItem(l)
		if #l > 12 then
			server.messageBox(mod, "Object limit has been reached.", {"OK"})
			return
		end
		local r = addDialog()
		if not r then return end
		table.insert(l, r)
		refreshLists()
	end
	local function removeItem(l, list)
		local sel = list:getSelected()
		if not sel then return end
		if server.messageBox(mod, "Are you sure you want to remove the selected elements?", {"Yes", "No"}) == "No" then return end
		for a, b in pairs(l) do
			if b == sel then
				table.remove(l, a)
				refreshLists()
				return
			end
		end
	end
	
	local lgui = gml.create("center", "center", 70, 26)
	lgui.style = server.getStyle(mod)
	lgui:addLabel("center", 1, 12, "Edit lists")
	lgui:addLabel(2, 4, 14, "Black list:")
	lgui:addLabel(37, 4, 14, "White list:")
	lb = lgui:addListBox(2, 6, 30, 12, {})
	rb = lgui:addListBox(37, 6, 30, 12, {})
	refreshLists()
	lgui:addButton(2, 19, 14, 1, "Add", function()
		addItem(ret.black)
	end)
	lgui:addButton(18, 19, 14, 1, "Remove", function()
		removeItem(ret.black, lb)
	end)
	lgui:addButton(37, 19, 14, 1, "Add", function()
		addItem(ret.white)
	end)
	lgui:addButton(53, 19, 14, 1, "Remove", function()
		removeItem(ret.white, rb)
	end)
	
	lgui:addButton(53, 23, 14, 1, "Cancel", function()
		ret = nil
		lgui:close()
	end)
	lgui:addButton(37, 23, 14, 1, "Apply", function()
		lgui:close()
	end)
	lgui:run()
	return ret
end

local function turretsLists()
	local r = listTemplate(lists.turrets)
	if not r then return end
	lists.turrets = r
end

local function sensorsLists()
	local r = listTemplate(lists.sensors)
	if not r then return end
	lists.sensors = r
end

local function turretTemplate(item)
	local ret = {}
	if item then
		for a, b in pairs(item) do ret[a] = b end
	end
	if type(ret.walls) ~= "table" then ret.walls = {} end
	
	local tgui = gml.create("center", "center", 66, 20)
	tgui.style = server.getStyle(mod)
	tgui:addLabel("center", 1, 18, item and "Edit a turret" or "New turret")
	tgui:addLabel(2, 4, 7, "Name:")
	local uidLabel = tgui:addLabel(2, 6, 7, "UID:")
	local detectorLabel = tgui:addLabel(2, 7, 17, "Detector UID:")
	tgui:addLabel(2, 9, 9, "Position:")
	tgui:addLabel(2, 11, 9, "Hidden:")
	tgui:addLabel(2, 13, 12, "Walls:")
	local name = tgui:addTextField(10, 4, 24)
	name.text = item and item.name or ""

	local uid = tgui:addLabel(10, 6, 38, item and item.uid or "")
	local comp = server.getComponent(mod, item.uid)
	if comp then
		uid.text = item.uid .. "  (" .. comp.name .. ")"
	end

	local function uidSelector()
		local a = server.componentDialog(mod, "os_energyturret")
		if not a then return end
		local found = false
		for _, b in pairs(turrets) do
			if b.uid == a then
				found = true
				break
			end
		end
		if not found then
			local ct = server.getComponent(mod, a)
			if not ct then
				error("An error occurred in the getComponent() function (nil).")
				return
			end
			local function cn(t)
				return t and type(t) == "number"
			end
			if not ct.state then
				server.messageBox(mod, "Cannot use this component because it's disabled.", {"OK"})
				return
			elseif not (cn(ct.x) and cn(ct.y) and cn(ct.z)) then
				server.messageBox(mod, "Turret must have all coordinates set!", {"OK"})
				return
			end
			if name.text:len() == 0 then
				name.text = ct.name:sub(1, 20)
				name:draw()
			end
			uid.text = a .. "  (" .. ct.name .. ")"
			ret.uid = a
			uid:draw()
		else
			server.messageBox(mod, "Device with such address has been already added.", {"OK"})
		end
	end
	uid.onDoubleClick = uidSelector
	uidLabel.onDoubleClick = uidSelector

	local detector = tgui:addLabel(20, 7, 38, ret and ret.detectorUid or "")
	comp = server.getComponent(mod, ret.detectorUid)
	if comp then
		detector.text = ret.detectorUid .. "  (" .. comp.name .. ")"
	end

	local function detectorSelector()
		local a = server.componentDialog(mod, "os_entdetector")
		if not a then return end
		local dt = server.getComponent(mod, a)
		if not dt then
			error("An error occurred int the getComponent() function (nil)")
			return
		end
		detector.text = a .. "  (" .. dt.name .. ")"
		ret.detectorUid = a
		detector:draw()
	end
	detector.onDoubleClick = detectorSelector
	detectorLabel.onDoubleClick = detectorSelector

	tgui:addButton(12, 9, 14, 1, ret.upside and "upside-down" or "normal", function(t)
		if ret.upside then
			ret.upside = false
			t.text = "normal"
		else
			ret.upside = true
			t.text = "upside-down"
		end
		t:draw()
	end)
	tgui:addButton(12, 11, 10, 1, ret.hidden and "yes" or "no", function(t)
		if ret.hidden then
			ret.hidden = false
			t.text = "no"
		else
			ret.hidden = true
			t.text = "yes"
		end
		t:draw()
	end)
	
	local vals = {"t", "b", "n", "s", "e", "w"}
	for i = 1, #vals do
		local temp = tgui:addLabel(15 + ((i -1) * 4), 13, 3)
		if item then
			temp.bgcolor = ret.walls[vals[i]] and 0x00ff00 or 0xff0000
		else
			temp.bgcolor = 0xff0000
		end
		temp.text = vals[i]
		temp.onClick = function(t)
			if ret.walls[vals[i]] then
				ret.walls[vals[i]] = false
				t.bgcolor = 0xff0000
			else
				ret.walls[vals[i]] = true
				t.bgcolor = 0x00ff00
			end
			t:draw()
		end
		temp.draw = function(t)
			local screenX, screenY = t:getScreenPosition()
			local ob = t.renderTarget.setBackground(t.bgcolor)
			local of = t.renderTarget.setForeground(0)
			t.renderTarget.set(screenX, screenY, " " .. t.text:sub(1, 1) .. " ")
			t.visible = true
			t.renderTarget.setBackground(ob)
			t.renderTarget.setForeground(of)
		end
	end
	
	tgui:addButton(48, 17, 14, 1, "Cancel", function()
		tgui:close()
		ret = nil
	end)
	tgui:addButton(32, 17, 14, 1, "Apply", function()
		local n = name.text
		local found = false
		for _, t in pairs(turrets) do
			if t.name == n then
				found = true
				break
			end
		end
		if config.turretsState then
			server.messageBox(mod, "Cannot modify this element while turrets are active.", {"OK"})
		elseif found and not item then
			server.messageBox(mod, "Entered name is aleady occupied.", {"OK"})
		elseif n:len() > 20 then
			server.messageBox(mod, "Device name cannot be longer than 20 characters.", {"OK"})
		elseif n:len() == 0 then
			server.messageBox(mod, "Enter device name.", {"OK"})
		elseif not ret.uid or ret.uid:len() == 0 then
			server.messageBox(mod, "Choose device UID.", {"OK"})
		elseif not ret.detectorUid or ret.detectorUid:len() == 0 then
			server.messageBox(mod, "Choose entity detector UID.", {"OK"})
		else
			ret.name = n
			tgui:close()
		end
	end)
	tgui:run()
	return ret
end

local function addTurret()
	if #turrets < 12 then
		if config.turretsState then
			server.messageBox(mod, "Cannot add new element while turrets are active.", {"OK"})
			return
		end
		local t = turretTemplate()
		if not t then return end
		table.insert(turrets, t)
		openTurret(t.address)
		rebuildTable(turrets, lbox)
		syncTurrets()
		rebuildCache()
	else
		server.messageBox(mod, "Turret limit has been reached.", {"OK"})
	end
end

local function modifyTurret()
	local sel = lbox:getSelected()
	if not sel then return end
	local m = sel:match("^%d+%.%s(.*)$")
	if not m then return end
	local t = nil
	local i = nil
	for a, b in pairs(turrets) do
		if b.name == m then
			t = b
			i = a
			break
		end
	end
	if not t then return end
	local ret = turretTemplate(t)
	if not ret then return end
	turrets[i] = ret
	rebuildTable(turrets, lbox)
	syncTurrets()
	rebuildCache()
end

local function removeTurret()
	local index = getIndex(lbox:getSelected())
	if not index or not turrets[index] then return end
	if config.turretsActive then
		server.messageBox(mod, "Cannot remove this element while turrets are active.", {"OK"})
		return
	end
	if server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "No" then return end
	table.remove(turrets, index)
	rebuildTable(turrets, lbox)
	rebuildCache()
end

local function sensorTemplate(item)
	local ret = {}
	if item then
		for a, b in pairs(item) do
			if a == "enable" then
				ret.enable = {}
				if type(b) == "table" then
					index = 0
					for _, d in pairs(b) do
						index = index + 1
						if index > 3 then break end
						local tmp = {}
						for e, f in pairs(d) do
							tmp[e] = f
						end
						table.insert(ret.enable, tmp)
					end
				end
			elseif a == "disable" then
				ret.disable = {}
				if type(b) == "table" then
					index = 0
					for _, d in pairs(b) do
						index = index + 1
						if index > 3 then break end
						local tmp = {}
						for e, f in pairs(d) do
							tmp[e] = f
						end
						table.insert(ret.disable, tmp)
					end
				end
			else
				ret[a] = b
			end
		end
	else
		ret.enable = {}
		ret.disable = {}
	end
	
	local act = {}
	local function refreshActions()
		for i = 1, 3 do
			if ret.enable[i] then
				local a = server.actionDetails(mod, ret.enable[i].id)
				if a then
					act[i].text = a.name
				else
					act[i].text = tostring(tab.enable[i].id)
				end
			else
				act[i].text = ""
			end
			act[i]:draw()
		end
		for i = 1, 3 do
			if ret.disable[i] then
				local a = server.actionDetails(mod, ret.disable[i].id)
				if a then
					act[i + 3].text = a.name
				else
					act[i + 3].text = tostring(ret.disable[i].id)
				end
			else
				act[i + 3].text = ""
			end
			act[i + 3]:draw()
		end
	end
	local function chooseAction(enable, num)
		local text = enable and act[num].text or act[num + 3].text
		local tab = enable and ret.enable or ret.disable
		if text:len() > 0 then
			local r = server.actionDialog(mod, nil, nil, tab[num])
			tab[num] = r
		else
			local r = server.actionDialog(mod)
			if r then
				tab[num] = r
			end
		end
		refreshActions()
	end
	
	local sgui = gml.create("center", "center", 60, 19)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 13, item and "Edit a sensor" or "New sensor")
	sgui:addLabel(2, 4, 7, "Name:")
	local uidLabel = sgui:addLabel(2, 6, 9, "UID:")
	sgui:addLabel(2, 9, 19, "Enable actions:")
	sgui:addLabel(32, 9, 19, "Disable actions:")
	local name = sgui:addTextField(10, 4, 22)
	name.text = ret.name or ""

	local uid = sgui:addLabel(10, 6, 38, ret.uid or "")
	local function uidSelector()
		local a = server.componentDialog(mod, "motion_sensor")
		if not a then return end
		local found = false
		for _, b in pairs(sensors) do
			if b.uid == a then
				found = true
				break
			end
		end
		if not found then
			local ct = server.getComponent(mod, a)
			if not ct then
				error("An error occurred in the getComponent() function (nil)")
				return
			end
			if not ct.state then
				server.messageBox(mod, "Cannot use this compoennt, because it's disabled.",{"OK"})
				return
			end
			if name.text:len() == 0 then
				name.text = ct.name:sub(1, 20)
				name:draw()
			end
			uid.text = a .. "  (" .. ct.name .. ")"
			ret.uid = a
			uid:draw()
		else
			server.messageBox(mod, "Device with the same address has been alread added.", {"OK"})
		end
	end
	uid.onDoubleClick = uidSelector
	uidLabel.onDoubleClick = uidSelector

	for i = 1, 3 do
		local tmp1 = sgui:addLabel(4, 10 + i, 3, tostring(i).. ".")
		act[i] = sgui:addLabel(8, 10 + i, 22, string.rep("a", 22))
		local function exec()
			chooseAction(true, i)
		end
		tmp1.onDoubleClick = exec
		act[i].onDoubleClick = exec
	end
	for i = 1, 3 do
		local tmp1 = sgui:addLabel(34, 10 + i, 3, tostring(i) .. ".")
		act[i + 3] = sgui:addLabel(38, 10 + i, 22, "")
		local function exec()
			chooseAction(false, i)
		end
		tmp1.onDoubleClick = exec
		act[i + 3].onDoubleClick = exec
	end
	refreshActions()
	
	sgui:addButton(42, 16, 14, 1, "Cancel", function()
		ret = nil
		sgui:close()
	end)
	sgui:addButton(26, 16, 14, 1, "Apply", function()
		local n = name.text
		local found = false
		for _, t in pairs(sensors) do
			if t.name == ret.name then
				found = true
				break
			end
		end
		if config.sensorsState then
			server.messageBox(mod, "Cannot modify this element while motion sensors are active.", {"OK"})
		elseif found and not item then
			server.messageBox(mod, "Device with the same name has been already added.", {"OK"})
		elseif n:len() == 0 then
			server.messageBox(mod, "Enter a device name.", {"OK"})
		elseif n:len() > 20 then
			server.messageBox(mod, "Name cannot be longer than 20 characters.", {"OK"})
		elseif not ret.uid then
			server.messageBox(mod, "Choose device UID.", {"OK"})
		else
			ret.name = n
			sgui:close()
		end
	end)
	sgui:run()
	return ret
end

local function addSensor()
	if #sensors < 12 then
		if config.sensorsState then
			server.messageBox(mod, "Cannot add element while sensors are active.", {"OK"})
			return
		end
		local t = sensorTemplate()
		if not t then return end
		table.insert(sensors, t)
		rebuildTable(sensors, rbox)
		syncSensors()
	else
		server.messageBox(mod, "Sensor limit has been reached.", {"OK"})
	end
end

local function modifySensor()
	local sel = rbox:getSelected()
	if not sel then return end
	local m = sel:match("^%d+%.%s(.*)$")
	if not m then return end
	local t = nil
	local i = nil
	for a, b in pairs(sensors) do
		if b.name == m then
			t = b
			i = a
			break
		end
	end
	if not t then return end
	local ret = sensorTemplate(t)
	if not ret then return end
	sensors[i] = ret
	rebuildTable(sensors, rbox)
	syncSensors()
end

local function removeSensor()
	local index = getIndex(rbox:getSelected())
	if not index or not sensors[index] then return end
	if config.sensorsState then
		server.messageBox(mod, "Cannot remove this element while sensors are active.",{"OK"})
		return
	end
	if server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "No" then return end
	table.remove(sensors, index)
	rebuildTable(sensors, rbox)
end

local function settings()
	local ret = {}
	ret.turretsMode = config.turretsMode
	ret.sensorsMode = config.sensorsMode
	local sgui = gml.create("center", "center", 55, 22)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Settings")
	sgui:addLabel(2, 4, 12, "Turrets:")
	sgui:addLabel(4, 6, 17, "Target mode:")
	sgui:addLabel(4, 7, 29, "Scan interval[1-15s]:")
	sgui:addLabel(4, 8, 38, "Activation time[0,15-180s]:")
	sgui:addLabel(4, 9, 26, "Scan range[5-20]:")
	sgui:addLabel(2, 12, 15, "Motion sensors:")
	sgui:addLabel(4, 14, 17, "Target mode:")
	sgui:addLabel(4, 15, 21, "Sensitivity[0.1-10]:")
	sgui:addLabel(4, 16, 28, "Activation time[0,15-180s]:")
	
	local tint = sgui:addTextField(44, 7, 5)
	local ttim = sgui:addTextField(44, 8, 5)
	local tran = sgui:addTextField(44, 9, 5)
	local ssen = sgui:addTextField(44, 15, 5)
	local sact = sgui:addTextField(44, 16, 5)
	tint.text = tostring(config.delay)
	ttim.text = tostring(config.turretsActive)
	tran.text = tostring(config.range)
	ssen.text = tostring(config.sensitivity)
	sact.text = tostring(config.sensorsActive)
	
	local names = {"everything", "white list", "black list"}
	sgui:addButton(24, 6, 14, 1, names[ret.turretsMode], function(t)
		if ret.turretsMode < 3 then
			ret.turretsMode = ret.turretsMode + 1
		else
			ret.turretsMode = 1
		end
		t.text = names[ret.turretsMode]
		t:draw()
	end)
	sgui:addButton(24, 14, 14, 1, names[ret.sensorsMode], function(t)
		if ret.sensorsMode < 3 then
			ret.sensorsMode = ret.sensorsMode + 1
		else
			ret.sensorsMode = 1
		end
		t.text = names[ret.sensorsMode]
		t:draw()
	end)
	
	sgui:addButton(38, 19, 14, 1, "Cancel", function() sgui:close() end)
	sgui:addButton(22, 19, 14, 1, "Apply", function()
		if config.turretsState or config.sensorsState then
			server.messageBox(mod, "Cannot save settings while turrets or sensors are active.", {"OK"})
			return
		end
		ret.delay = tonumber(tint.text)
		ret.turretsActive = tonumber(ttim.text)
		ret.range = tonumber(tran.text)
		ret.sensitivity = tonumber(ssen.text)
		ret.sensorsActive = tonumber(sact.text)
		if not ret.delay or ret.delay < 1 or ret.delay > 15 then
			server.messageBox(mod, "Scan interval must be a nubmer between 1 and 15.", {"OK"})
		elseif not ret.turretsActive or (ret.turretsActive ~= 0 and (ret.turretsActive < 15 or ret.turretsActive > 180)) then
			server.messageBox(mod, "Turrets activation time must be a number between 15 and 180 or 0.", {"OK"})
		elseif not ret.range or ret.range < 5 or ret.range > 20 then
			server.messageBox(mod, "Scan range must be a number between 5 and 20.", {"OK"})
		elseif not ret.sensitivity or ret.sensitivity < 0.1 or ret.sensitivity > 10 then
			server.messageBox(mod, "Sensor sensitivity must be a number from 0.1 to 10.", {"OK"})
		elseif not ret.sensorsActive or (ret.sensorsActive ~= 0 and (ret.sensorsActive < 15 or ret.sensorsActive > 180)) then
			server.messageBox(mod, "Sensor activation time must be a number between 15 and 180 or 0.", {"OK"})
		else
			config.delay = ret.delay
			config.turretsActive = ret.turretsActive
			config.range = ret.range
			config.sensitivity = ret.sensitivity
			config.sensorsActive = ret.sensorsActive
			config.turretsMode = ret.turretsMode
			config.sensorsMode = ret.sensorsMode
			sgui:close()
		end
	end)
	sgui:run()
end

local function setTurretsMode(mode)
	if mode < 0 or mode < 4 then
		config.turretsMode = mode
	else
		server.call(mod, 5203, "Turret mode is outside a range.", "turrets", true)
	end
	
end

local function setSensorsMode(mode)
	if mode > 0 or mode < 4 then
		config.sensorsMode = mode
	else
		server.call(mod, 5203, "Sensor mode is outside a range..", "turrets", true)
	end
end

local actions = {
	[1] = {
		name = "enableTurrets",
		type = "TURRETS",
		desc = "Enables turrets",
		exec = enableTurrets
	},
	[2] = {
		name = "disableTurrets",
		type = "TURRETS",
		desc = "Disabled turrets",
		exec = disableTurrets
	},
	[3] = {
		name = "enableSensors",
		type = "TURRETS",
		desc = "Enables sensors",
		exec = enableSensors
	},
	[4] = {
		name = "disableSensors",
		type = "TURRETS",
		desc = "Disables sensors",
		exec = disableSensors
	},
	[5] = {
		name = "setTurretsMode",
		type = "TURRETS",
		desc = "Sets turrets' mode",
		p1type = "number",
		p1desc = "mode [1-3]",
		exec = setTurretsMode
	},
	[6] = {
		name = "setSensorsMode",
		type = "TURRETS",
		desc = "Sets sensors' mode",
		p1type = "number",
		p1desc = "mode [1-3]",
		exec = setSensorsMode
	}
}

mod.name = "turrets"
mod.version = version
mod.id = 36
mod.apiLevel = 3
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 14, ">> TURRETS <<")
	window:addLabel(3, 3, 12, "Turrets:")
	window:addLabel(36, 3, 9, "Sensors:")
	
	lbox = window:addListBox(3, 5, 30, 10, {})
	lbox.onDoubleClick = modifyTurret
	rbox = window:addListBox(36, 5, 30, 10, {})
	rbox.onDoubleClick = modifySensor
	
	element[1] = window:addButton(18, 3, 14, 1, "", function()
		if config.turretsState then
			disableTurrets()
		else
			enableTurrets()
		end
	end)
	element[2] = window:addButton(52, 3, 14, 1, "", function(t)
		if config.sensorsState then
			disableSensors()
			t.text = "disabled"
		else
			enableSensors()
			t.text = "enabled"
		end
		t:draw()
	end)
	refreshView()
	
	window:addButton(3, 16, 14, 1, "Add", addTurret)
	window:addButton(19, 16, 14, 1, "Remove", removeTurret)
	window:addButton(3, 18, 16, 1, "Lists", turretsLists)
	window:addButton(36, 16, 14, 1, "Add", addSensor)
	window:addButton(52, 16, 14, 1, "Remove", removeSensor)
	window:addButton(50, 18, 16, 1, "Lists", sensorsLists)
	window:addButton(26, 18, 16, 1, "Settings", settings)
	
	rebuildTable(turrets, lbox)
	rebuildTable(sensors, rbox)
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	local function check(v, r1, r2)
		return not v or type(v) ~= "number" or v < r1 or v > r2
	end
	if check(config.turretsMode, 1, 3) then
		config.turretsMode = 3
	end
	if check(config.sensorsMode, 1, 3) then
		config.sensorsMode = 3
	end
	if check(config.sensitivity, 0.1, 10) then
		config.sensitivity = 0.4
	end
	if check(config.delay, 1, 15) then
		config.delay = 5
	end
	if check(config.range, 5, 20) then
		config.range = 7
	end
	if check(config.turretsActive, 15, 180) and config.turretsActive ~= 0 then
		config.turretsActive = 15
	end
	if check(config.sensorsActive, 15, 180) then
		config.sensorsActive = 15
	end
	
	loadData()
	syncTurrets()
	syncSensors()

	server.registerEvent(mod, "component_added")
	server.registerEvent(mod, "component_removed")
	
	local removal = {}
	for a, t in pairs(turrets) do
		local f1 = server.findComponents(mod, t.address)
		local f2 = server.findComponents(mod, t.detector)
		if #f1 > 0 and #f2 > 0 then
			openTurret(t.address)
		else
			server.log(mod, "TURRETS: Turret record's components are unavailable, removing...")
			table.insert(removal, a)
		end
	end
	table.sort(removal, function(a, b) return a > b end)
	for _, b in pairs(removal) do table.remove(turrets, b) end
	removal = {}
	for a_, t in pairs(sensors) do
		local f1 = server.findComponents(mod, t.address)
		if #f1 == 0 then
			server.log(mod, "TURRETS: Sensor record's components are unavailable, removing...")
			table.insert(removal, a)
		end
	end
	table.sort(removal, function(a, b) return a > b end)
	for _, b in pairs(removal) do table.remove(sensors, b) end
	refreshSensors()

	rebuildCache()
	if config.turretsState then enableTurrets() end
	if config.sensorsState then enableSensors() end
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	for _, t in pairs(sensors) do
		t.active = nil
	end
	saveData()
	server.unregisterEvent(mod, "component_added")
	server.unregisterEvent(mod, "component_removed")
	
	if timer then event.cancel(timer) end
	local tab = server.getComponentList(mod, "os_energyturret")
	for _, t in pairs(tab) do
		closeTurret(t.address)
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "motion" then
		local tab = nil
		for _, t in pairs(sensors) do
			if t.address == e[2] then
				tab = t
				break
			end
		end
		if not tab or tab.active then return end
		local found = false
		if config.sensorsMode == 1 then
			--all
			found = true
		elseif config.sensorsMode == 2 and e[6] then
			--white
			for _, t in pairs(lists.sensors.white) do
				if t == e[6] then
					return
				end
			end
		elseif config.sensorsMode == 3 and e[6]then
			--black
			for _, t in pairs(lists.sensors.black) do
				if t == e[6] then
					found = true
					break
				end
			end
		end
		if not found then return end
		for i = 1, 3 do
			local l = tab.enable[i]
			if l then
				server.call(mod, l.id, l.p1, l.p2, true)
			end
		end
		tab.active = true
		event.timer(config.sensorsActive, function()
			for i = 1, 3 do
				local l = tab.disable[i]
				if l then
					server.call(mod, l.id, l.p1, l.p2, true)
				end
			end
			tab.active = nil
		end)
	elseif e[1] == "components_changed" then
		if e[2] == "os_energyturret" or e[2] == "os_entdetector" then
			syncTurrets()
			rebuildCache()
		elseif e[2] == "motion_sensor" then
			syncSensors()
		elseif e[2] == nil then
			syncTurrets()
			syncSensors()
			rebuildCache()
		end
		
		if not config.turretsState then
			local tab = server.getComponentList(mod, "os_energyturret")
			for _, t in pairs(tab) do
				openTurret(t.address)
			end
		end
	elseif e[1] == "component_added" then
		if e[3] == "os_energyturret" then
			local found = server.findComponents(e[2])
			if #found == 1 then
				rebuildCache()
				openTurret(e[2])
			end
		elseif e[3] == "motion_sensor" then
			refreshSensors()
		end
	elseif e[1] == "component_removed" then
		if e[3] == "os_energyturret" then
			rebuildCache()
		end
	end
end

return mod