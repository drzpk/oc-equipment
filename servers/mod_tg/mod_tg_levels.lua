-- ############################################
-- #				mod_tg_levels			  #
-- #										  #
-- #  03.2016					by:IlynPayne  #
-- ############################################

--[[
	## Description ##
		The mod_tg_levels program is a module used by the_guard server (since 2.0).
		It allows to create and manage security levels. Each level can trigger multiple
		actions when it's turned on or off. This module also supports alarm
		blocks (from "OpenSecurity"). 
		
	## Akcje ##
		- getLevel() - get current security level (from 0 to 3)
		- setLevel(level:number) - sets new security level
		- alarm(timeout:number[, level:number]) - activates alarm; level parameter indicates used sound
		- disableAlarm() - deactivates alarm
		
	## Functions ##
		* managing up to 3 security levels
		* each level can trigger up to 10 actions when it's turned on or off
		* manual alarm switching
		* setting alarm range
]]

local version = "1.1"
local args = {...}

if args[1] == "version_check" then return version end

local event = require("event")
local component = require("component")
local gml = require("gml")

local mod = {}
local server = nil
local config = nil

local indicator = {}
local lAlarm = {}
local timerID = nil
local alarms = {
	[1] = "klaxon1",
	[2] = "klaxon2"
}

local function getLevel()
	return config.level
end

local function setLevel(new_level, internal)
	if internal and config.ask then
		if server.messageBox(mod, "Are you sure you want to switch to level " .. tostring(new_level) .. "?", {"Yes", "No"}) == "No" then return end
	end
	for _, t in pairs(config[config.level].disable) do
		server.call(mod, t.id, t.p1, t.p2, true)
	end
	for _, t in pairs(config[new_level].enable) do
		server.call(mod, t.id, t.p1, t.p2, true)
	end
	config.level = new_level
	server.call(mod, 5201, "Switched to level " .. tostring(new_level), "LEVELS", true)
	for i = 0, 3 do
		indicator[i]:draw()
	end
end

local function disableAlarm(silent)
	event.cancel(timerID or 0)
	timerID = nil
	lAlarm[1].text = "disabled"
	lAlarm[1]:draw()
	lAlarm[3].text = "0:00"
	lAlarm[3]:draw()
	lAlarm[4].text = "Start"
	lAlarm[4]:draw()
	config.alarm = nil
	
	local ll = server.getComponentList(mod, "os_alarm")
	for _, t in pairs(ll) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.deactivate()
		end
	end
	if not silent then
		server.call(mod, 5201, "Alarm has been disabled.", "LEVELS", true)
	end
end

local function timerFunc()
	config.alarm = config.alarm - 1
	lAlarm[3].text = string.format("%d:%02d", config.alarm / 300, config.alarm % 300)
	lAlarm[3]:draw()
	if config.alarm < 0 then
		disableAlarm()
	end
end

local function enableAlarm(timeout, l)
	if type(timeout) ~= "number" or timeout > 300 or timeout < 3 then
		server.call(mod, 5203, "Entered alarm time is incorrect.", "LEVELS", true)
		return
	end
	local sound = l or config.alarmSound
	if sound > 2 or sound < 1 then
		server.call(mod, 5203, "Entered alarm sound ID is incorrect.", "LEVELS", true)
		return
	end
	lAlarm[1].text = "enabled"
	lAlarm[1]:draw()
	lAlarm[4].text = "Stop"
	lAlarm[4]:draw()
	
	local reenable = false
	if config.alarm then reenable = true end
	config.alarm = timeout
	local ll = server.getComponentList(mod, "os_alarm")
	if #ll > 0 then
		for _, t in pairs(ll) do
			local proxy = component.proxy(t.address)
			if proxy then
				proxy.setRange(config.range)
				proxy.setAlarm(alarms[sound])
				proxy.activate()
			end
		end
	elseif not reenable then
		server.call(mod, 5203, "No alarm block is connected!", "LEVELS", true)
	end
	if not reenable then
		if timerID then
			event.cancel(timerID)
		end
		timerID = event.timer(1, timerFunc, math.huge)
		server.call(mod, 5201, "Alarm has been turned on.", "LEVELS", true)
	end
end

local function levelSettings(level)
	local lbox, rbox = nil, nil
	local llist, rlist = nil, nil
	
	local function refresh()
		llist = {}
		for i, t in pairs(config[level].enable) do
			local a = server.actionDetails(mod, t.id)
			if a then
				table.insert(llist, a.name .. " (" .. a.type .. ")")
			else
				table.insert(llist, "*" .. tostring(t.id) .. "*")
			end
		end
		lbox:updateList(llist)
		rlist = {}
		for i, t in pairs(config[level].disable) do
			local a = server.actionDetails(mod, t.id)
			if a then
				table.insert(rlist, a.name .. " (" .. a.type .. ")")
			else
				table.insert(rlist, "*" .. tostring(t.id) .. "*")
			end
		end
		rbox:updateList(rlist)
	end
	local function delete(id, enable)
		local l = enable and config[level].enable or config[level].disable
		for i, t in pairs(l) do
			if t.id == id then
				table.remove(l, i)
				return
			end
		end
	end
	local function findID(name)
		local a, amount = server.getActions(mod, nil, nil, name)
		if amount > 0 then
			for i, t in pairs(a) do
				if t.name == name then
					return i
				end
			end
		end
		return nil
	end
	local function details(enable)
		local l = enable and lbox or rbox
		local c = enable and config[level].enable or config[level].disable
		local m1 = l:getSelected():match("^(.*) %(")
		local m2 = l:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				for i, t in pairs(c) do
					if t.id == id then
						local tab = server.actionDialog(mod, nil, nil, c[i])
						c[i] = tab
						refresh()
						return
					end
				end
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				for i, t in pairs(c) do
					if t.id == num then
						local tab = server.actionDialog(mod, nil, nil, c[i])
						c[i] = tab
						refresh()
						return
					end
				end
			end
		end
	end
	
	local lgui = gml.create("center", "center", 70, 25)
	lgui.style = server.getStyle(mod)
	lgui:addLabel("center", 1, 9, "LEVEL " .. tostring(level))
	lgui:addLabel(2, 3, 15, "Level name:")
	local name = lgui:addTextField(18, 3, 20)
	name.text = config[level].name or ""
	lgui:addLabel(4, 5, 17, "Enable actions")
	lgui:addLabel(39, 5, 18, "Disable actions")
	lbox = lgui:addListBox(2, 6, 30, 13, {})
	lbox.onDoubleClick = function() details(true) end
	rbox = lgui:addListBox(37, 6, 30, 13, {})
	rbox.onDoubleClick = function() details(false) end
	lgui:addButton(2, 20, 14, 1, "Add", function()
		if #config[level].enable < 11 then
			local result = server.actionDialog(mod)
			if result then
				table.insert(config[level].enable, result)
				refresh()
			end
		else
			server.messageBox("Action limit has been reached.", {"OK"})
		end
	end)
	lgui:addButton(18, 20, 14, 1, "Remove", function()
		if #lbox.list == 0 then return
		elseif server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "No" then return end
		local m1 = lbox:getSelected():match("^(.*) %(")
		local m2 = lbox:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				delete(id, true)
				refresh()
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				delete(num, true)
				refresh()
			end
		end
	end)
	lgui:addButton(37, 20, 14, 1, "Add", function()
		if #config[level].disable < 11 then
			local result = server.actionDialog(mod)
			if result then
				table.insert(config[level].disable, result)
				refresh()
			end
		else
			server.messageBox("Action limit has been reached.", {"OK"})
		end
	end)
	lgui:addButton(53, 20, 14, 1, "Remove", function()
		if #rbox.list == 0 then return
		elseif server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "No" then return end
		local m1 = rbox:getSelected():match("^(.*) %(")
		local m2 = rbox:getSelected():match("^%*(%d+)%*$")
		if m1 then
			local id = findID(m1)
			if id then
				delete(id, false)
				refresh()
			end
		elseif m2 then
			local num = tonumber(m2)
			if num then
				delete(num, false)
				refresh()
			end
		end
	end)
	lgui:addButton(53, 23, 14, 1, "Close", function()
		if name.text:len() > 16 then
			server.messageBox(mod, "Level name cannot be longer than 16 characters.", {"OK"})
			return
		end
		config[level].name = name.text
		lgui:close()
	end)
	refresh()
	lgui:run()
end

local function settings()
	local sgui = gml.create("center", "center", 40, 19)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "SETTINGS")
	sgui:addLabel(2, 3, 9, "Options:")
	sgui:addLabel(4, 4, 9, "Range:")
	sgui:addLabel(4, 5, 23, "Ask for confirmation:")
	sgui:addLabel(2, 7, 9, "Levels:")
	
	local tRange = sgui:addTextField(14, 4, 6)
	tRange.text = tostring(config.range)
	local ask = sgui:addButton(28, 5, 8, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "no"
		else
			t.status = true
			t.text = "yes"
		end
		t:draw()
	end)
	ask.status = config.ask
	ask.text = config.ask and "yes" or "no"
	
	sgui:addButton(4, 8, 12, 1, "> 0 <", function() levelSettings(0) end)
	sgui:addButton(4, 10, 12, 1, "> 1 <", function() levelSettings(1) end)
	sgui:addButton(4, 12, 12, 1, "> 2 <", function() levelSettings(2) end)
	sgui:addButton(4, 14, 12, 1, "> 3 <", function() levelSettings(3) end)
	
	sgui:addButton(24, 16, 14, 1, "Cancel", function() sgui:close() end)
	sgui:addButton(9, 16, 14, 1, "Apply", function()
		local r = tonumber(tRange.text)
		if not r or r > 150 or r < 15 then
			server.messageBox(mod, "Range must be a number from 15 to 150.", {"OK"})
		else
			config.range = r
			config.ask = ask.status
			sgui:close()
		end
	end)
	sgui:run()
end

local function synchronize()
	local amount = 0
	for _, c in pairs(server.getComponentList(mod, "os_alarm")) do
		local proxy = component.proxy(c.address)
		if proxy then
			proxy.setAlarm(alarms[config.alarmSound])
			proxy.setRange(config.range)
			if config.alarm then
				proxy.activate()
			else
				proxy.deactivate()
			end
			amount = amount + 1
		end
	end
	server.call(mod, 5201, "Synchronization complete. Synchronized " .. tostring(amount) .. " alarm(s).", "LEVELS", true)
end

local actions = {
	[1] = {
		name = "getLevel",
		type = "LEVEL",
		desc = "Returns current security level",
		exec = getLevel
	},
	[2] = {
		name = "setLevel",
		type = "LEVEL",
		desc = "Sets new security level",
		p1type = "number",
		p1desc = "security level number (0-3)",
		exec = setLevel
	},
	[3] = {
		name = "alarm",
		type = "LEVEL",
		desc = "Enables alarm",
		p1type = "number",
		p2type = "number",
		p1desc = "alarm duration (3-300)",
		p2desc = "alarm sound id (1-2)",
		exec = enableAlarm
	},
	[4] = {
		name = "disableAlarm",
		type = "LEVEL",
		desc = "Disables alarm",
		exec = disableAlarm
	}
}

mod.name = "levels"
mod.version = version
mod.id = 11
mod.apiLevel = 3
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 13, ">> LEVELS <<")
	window:addButton(6, 4, 30, 3, "> 3." .. (config[3].name and config[3].name:sub(1, 16) or "") .. " <", function() setLevel(3, true) end)
	window:addButton(6, 8, 30, 3, "> 2." .. (config[2].name and config[2].name:sub(1, 16) or "") .. " <", function() setLevel(2, true) end)
	window:addButton(6, 12, 30, 3, "> 1." .. (config[1].name and config[1].name:sub(1, 16) or "") .. " <", function() setLevel(1, true) end)
	window:addButton(6, 16, 30, 3, "> 0.".. (config[0].name and config[0].name:sub(1, 16) or "") .. " <", function() setLevel(0, true) end)
	window:addButton(42, 16, 18, 1, "Settings", settings)
	window:addButton(42, 18, 18, 1, "Synchronize", synchronize)
	
	window:addLabel(48, 4, 6, "ALARM")
	window:addLabel(42, 6, 8, "Status:")
	lAlarm[1] = window:addLabel(51, 6, 11, "")
	lAlarm[1].text = config.alarm and "enabled" or "disabled"
	window:addLabel(42, 7, 6, "Time:")
	lAlarm[2] = window:addTextField(49, 7, 5)
	lAlarm[2].text = tostring(config.alarmTime)
	window:addLabel(42, 8, 9, "Sound:")
	window:addButton(52, 8, 8, 1, tostring(config.alarmSound), function(t)
		if config.alarmSound == 1 then
			config.alarmSound = 2
			t.text = "2"
		else
			config.alarmSound = 1
			t.text = "1"
		end
		t:draw()
	end)
	window:addLabel(42, 11, 17, "Remaining time:")
	lAlarm[3] = window:addLabel(60, 11, 5, config.alarm and string.format("%d:%02d", config.alarm / 300, config.alarm % 300) or "")
	lAlarm[4] = window:addButton(42, 9, 10, 1, "", function(t)
		if not config.alarm then
			local newtime = tonumber(lAlarm[2].text)
			if not newtime or newtime > 300 or newtime < 3 then
				server.messageBox(mod, "Alarm time must be a number between 3 and 300 seconds.", {"OK"})
				return
			end
			enableAlarm(newtime)
		else
			disableAlarm()
		end
	end)
	lAlarm[4].text = config.alarm and "Stop" or "Start"
	
	for i = 0, 3 do
		indicator[i] = server.template(mod, window, 2, 5 + (i * 4), 2, 1)
		indicator[i].level = 3 - i
		indicator[i].draw = function(t)
			if config.level == t.level then
				t.renderTarget.setBackground(0x00ff00)
			else
				t.renderTarget.setBackground(0xff0000)
			end
			t.renderTarget.fill(t.posX, t.posY, 2, 1, ' ')
		end
	end
	
	if config.alarm then
		event.timer(2, function() enableAlarm(config.alarm) end)
	end
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	
	if not config.level or type(config.level) ~= "number" or config.level > 3 or config.level < 0 then
		config.level = 0
	end
	if not config.alarmTime then
		config.alarmTime = 20
	end
	if not config.alarmSound then
		config.alarmSound = 1
	end
	if not config.range or config.range > 150 or config.range < 15 then
		config.range = 20
	end
	if not config.ask then
		config.ask = true
	end
	for i = 0, 3 do
		if not config[i] then
			config[i] = {}
		end
		if not config[i].enable then
			config[i].enable = {}
		else
			for a, b in pairs(config[i].enable) do
				if not b.id then table.remove(config[i].enable, a) end
			end
		end
		if not config[i].disable then
			config[i].disable = {}
		else
			for a, b in pairs(config[i].disable) do
				if not b.id then table.remove(config[i].disable, a) end
			end
		end
	end
	
	core.registerEvent(mod, "component_added")
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	if config.alarm then
		event.cancel(timerID or 0)
		local ll = server.getComponentList(mod, "os_alarm")
		if #ll > 0 then
			for _, t in pairs(ll) do
				local proxy = component.proxy(t.address)
				if proxy then
					proxy.deactivate()
				end
			end
		end
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "component_added" and e[3] == "os_alarm" then
		local proxy = component.proxy(e[2])
		if proxy then
			proxy.setRange(config.range)
			proxy.setAlarm(alarms[config.alarmSound])
			if config.alarm then
				proxy.activate()
			else
				proxy.deactivate()
			end
		end
	end
end

return mod