-- ################################################
-- #                The Guard  3.0                #
-- #                                              #
-- #  03.2016                by: Dominik Rzepka   #
-- ################################################

--[[
	## Description ##
		This program serves as a security system control center. Most of the
		functionality is acheived by using "OpenSecurity" Minecraft mod.
		
	## Technical description ##
		Previous version of this server (1.0) used separate computers to communicate
		with security components - they had the 'micro' program installed. In newer
		versions this architecture was abandoned. It was superseded by a modular
		architecture and all components have to be connected directly to the server.
		This solution has one major drawback: maximum number of simultaneously
		connected components is 64.
		
		Now this server acts merely as a container - it provides only very little
		functionality on its own. Instead, external modules can be attached in order
		to acheive desired functionality. The module catalogue offers an easy
		way to manage all available modules.

		Components connected to server aren't automatically available to modules
		(that is only if they try to obtain components through the API). Instead,
		they have to be manually registered first.

	# Idea of actions ##
		Modules can provide or use so-called actions: they allow modules to perform
		predefined tasks defined in one of active modules. Each action can handle
		up to 2 optional parameters.

		Thanks to the concept actions, modules don't use each other's functionality
		directly. Instead, they communicate through the_guard server and on it lies
		the responsibility to find a module with specified action and call it. It
		allows to create complex modules whose functionality can be flexibly
		configured by user - by specifying what actions to call and when.

	## List of officially supported modules ##
		- levels (mod_tg_levels) - security levels management
		- logs (mod_tg_logs) - action-driven logger
		- io (mod_tg_io) - IO devices support (redstone/project red/network)
		- auth (mot_tg_auth) - user authentication (keypads, biometric scanners, cards)
		- turrets (mod_tg_turrets) - energy turrets and motion sensors
		
	## Module architecture ##
		In order for a module to be accepted by the server, it has to return
		an associative table containing the following entries:
		- name:string - name of a module
		- version:string - version of a module
		- id: number - unique module identifier
		- apiLevel:number - supported server API version
		- shape:string - module window shape ("normal", "landscape")
		- actions:table - table with available actions
		- setUI(window) - creates and returns main GUI, called after start()
		- start(server:table):function - called on server start - used to initialize module
		- stop(server_table):function - called on server stop
		- pullEvent(...):function - event handler (only registered events)
		
		Actions are a tasks that a module can perform. They are shared across
		server instance - can be viewed as well as executed by any other module.
		Actions' table structure is as follows:
		[id:number - action identifier, unique within a module]
		{
			name:string - action name
			type:string - action type
			desc:string - action description
			p1type:string - type of the 1st parameter
			p2type:string - type o the 2nd parameter
			p1desc:sting - description of the 1st parameter
			p2desc:string - description of the 2nd parameter
			exec:function - function containing task to execute
			hidden:boolean - whether this action should be hidden
		}

		Action parameters are optional. For example, if only one parameter is used,
		action should define only p1* fields.

		Actions types are used to facilitate usage of the server (i.e. a module
		may need only action of a specific type). Types used by server and
		official modules:
		* CORE - actions created by server
		* LOG - log-related actions
		* IO - actions related to redstone circuits
		* LEVEL - actions that deal with security levels
		* AUTH - user identity, authentication and authorization
		* TURRET - actions defined in the mod_tg_turret module. Related to turrets and sensors.

		Aside from actions, a module can listen for events. Server automatically emits the following events:
		* {"components_changed", "<component_type> or nil"} - when a registered component was added, modified or removed

		In order to receive every other type of event, a component must explicitly register
		it through the server API.
		
	## Configuration scheme ##
		settings: { - global program settings (/etc/the_guard/config.conf)
			port: number - port used for network connection in modules (they may ingore this setting),
			backupPort: number - data server port, used in backup/restore operations,
			debugMode:bool - debug mode state,
			dark:bool - whether to use dark mode,
			saveOnExit:bool - whether configuration has to be saved again before exit
		}
		
		modules: { - module information (/etc/the_guard/modules.conf)
			[zone:number] { - occupied zone
				name:string - module name*
				file:string - module file
				version:string - module version*
				shape:string - module dimensions*
			}
			...
		}
		
		components: { - list of installed components (/etc/the_guard/components.conf)
			{
				id:number - component id
				address:string - address
				type: string - component type
				name:string - name
				state:bool - components status (enabled/disabled)
				x: number - X coordinate of a module (optional)
				y: number - Y coordinate of a module (optional)
				z: number - Z coordinate of a module (optional)
			}
			...
		}
		
		passwd:string - server master password (hashed using SHA-256)
		(/etc/the_guard/passwd.bin)
		
		Modules keep their configuration files in '/etc/the_guard/modules' directory.
		Each module by default has one configuration file: <module_name>.conf
		
		*Fields marked by asterisk aren't saved to configuration files
		
	## Interface ##
		The server provices an interface (API) allowing modules to operate.
		All of the interface's methods are documented in the code below
		(prefixed with 'interface.').

		Server window is divided to 5 zones. First 4 zones have identical
		dimensions. 5. zone is wide and usually serves as a space for
		a log module. Coordinates for module's GUI are relative to the
		beginning of a zone. Module whose GUI goes beyond zone borders
		will be disabled.
]]

-- todo: actions subsystem; look for doActionValidation function in version 2.x
-- todo: api subsystem; standardize api docs: https://stevedonovan.github.io/ldoc/manual/doc.md.html
-- todo: maintenance subsystem (crash log generation)
-- todo: network and component subsystem

local version = "3.0.0"
local apiLevel = 6
local args = {...}

if args[1] == "version_check" then return version end
local strict = args[1] == "strict"

local computer = require("computer")
local component = require("component")
local event = require("event")
local serial = require("serialization")
local os = require("os")
local uni = require("unicode")
local fs = require("filesystem")
local term = require("term")
local gml = require("gml")
local dsapi = require("dsapi")
local colors = require("colors")
if not component.isAvailable("modem") then
	io.stderr:write("Server requires a network card in order to work.")
	return
end
local modem = component.modem

local data = nil
if component.isAvailable("data") then
	data = component.data
end
if not data and false then -- todo: debug-only
	io.stderr:write("Server requires a data card tier 2 in order to work.")
	return
elseif false and not data.encrypt then
	io.stderr:write("Used data card must be at least of tier 2.")
	return
end

local resolution = {component.gpu.getResolution()}
if not resolution[1] == 160 or not resolution[2] == 50 then
	io.stderr:write("Server requires 160x50 screen resolution (current resolution: " .. tostring(resolution[1]) .. "x" .. tostring(resolution[2]))
	return
end

-- # Configuration
local passwd = nil -- master password
local settings = {} -- settings
local token = nil -- device token (id)

local SUBSYSTEMS_DIR = "/usr/bin/the_guard/subsystems"
local CONFIG_DIR = "/etc/the_guard"

-- # Function declarations
local GMLmessageBox = nil
local GMLcontains = nil
local GMLgetAppliedStyles = nil
local GMLextractProperty = nil
local GMLextractProperties = nil
local GMLfindStyleProperties = nil
local GMLcalcBody = nil

local subsystems = {}

local logger = nil
local subsystemsLogger = nil
local modulesLogger = nil

-- # variables
local gui = nil
local mod = {}
local internalMod = math.random()

-- # Module interface
local interface = {}
local actions = {}
local events = {}
local eventsready = false
local revents = {}
local backgroundListener = nil

interface.apiLevel = apiLevel
interface.debugMode = true -- todo

--[[
Loads module's primary configuration file
	@mod - calling module
	RET: table with config
]]
interface.loadConfig = function(mod)
	local path = fs.concat("/etc/the_guard/modules", mod.name .. ".conf")
	if fs.isDirectory(path) then
		fs.remove(path)
	elseif fs.exists(path) then
		local f = io.open(path, "r")
		if f then
			local s, r = pcall(serial.unserialize, f:read("*a"))
			if s then
				f:close()
				return r
			else
				f:close()
				return {}
			end
		else
			return {}
		end
	else
		return {}
	end
end

--[[
Saves module's primary configuration to file
	@mod - calling module
	@tab - table with config
]]
interface.saveConfig = function(mod, tab)
	if not fs.isDirectory("/etc/the_guard/modules") then
		fs.makeDirectory("/etc/the_guard/modules")
	end
	if type(tab) == "table" then
		local path = fs.concat("/etc/the_guard/modules", mod.name .. ".conf")
		if fs.isDirectory(path) then
			fs.remove(path)
		else
			local t = serial.serialize(tab)
			if t then
				local f = io.open(path, "w")
				if f then
					f:write(t)
					f:close()
				end
			end
		end
	end
end

--[[
Returns module by name
	@mod - calling module
	@name - target module's name
	RET: desired module or nil
]]
interface.getModule = function(mod, name)
	for _, t in pairs(modules) do
		if t.name == name then return t end
	end
	return nil
end

--[[
Registers new event
	@mod - calling module
	@name - event name
]]
interface.registerEvent = function(mod, name)
	if not events[mod.name] then events[mod.name] = {} end
	for _, n in pairs(events[mod.name]) do
		if n == name then return end
	end
	table.insert(events[mod.name], name)
	local registered = false
	for _, s in pairs(revents) do
		if s == name then
			registered = true
			break
		end
	end
	if not registered then
		table.insert(revents, name)
		if eventsready then
			event.listen(name, backgroundListener)
		end
	end
end

--[[
Unregisters an event
	@mod - calling module
	@name - event name
]]
interface.unregisterEvent = function(mod, name)
	if events[mod.name] then
		for i, s in pairs(events[mod.name]) do
			if s == name then
				table.remove(events[mod.name], i)
				break
			end
		end
		local left = false
		for _, t in pairs(events) do
			for _, t2 in pairs(t) do
				if t2 == name then
					left = true
					break
				end
			end
		end
		if not left then
			for i, s in pairs(revents) do
				if s == name then
					table.remove(revents, i)
					event.ignore(name, backgroundListener)
					break
				end
			end
		end
	end
end

--[[
Returns list of actions
	@mod - calling module
	@type:string or nil - action type filter
	@target:string or nil - module filter
	@name:string or nil - action name filter
	RET: <list of actions, number of actions>
]]
interface.getActions = function(mod, type, target, name)
	local ac = {}
	local amount = 0
	for m, t in pairs(actions) do
		if (target and m == target) or (not target) then
			for id, at in pairs(t) do
				if (type and (at.type == type or at.type == "")) or (not type) then
					if (name and at.name:find(name)) or (not name) then
						ac[id] = at
						amount = amount + 1
					end
				end
			end
		end
	end
	return ac, amount
end

--[[
Returns table with registered components
	@mod - calling module
	@type - component type or nil
	@force - show even disabled components
	RET: <table with components>
]]
interface.getComponentList = function(mod, type, force)
	local ret = {}
	for _, t in pairs(components) do
		if t.state then
			if type then
				if type == t.type then
					table.insert(ret, t)
				end
			else
				table.insert(ret, t)
			end
		end
	end
	return ret
end

--[[
Returns a single component
	@mod - calling module
	@uid - uid of a component
	@force - return even disabled component
	RET: <component> or nil
]]
interface.getComponent = function(mod, uid, force)
	if not uid then return nil end
	for _, c in pairs(components) do
		if c.id == uid then
			if c.state or force then return c
			else return nil end
		end
	end
	return nil
end

--[[
Searches for a registered components based on given address part
	@mod - calling module
	@pattern - address part
	RET: <found components:table>
]]
interface.findComponents = function(mod, pattern)
	local ret = {}
	local pat = pattern and string.gsub(pattern, "-", "%%-") or ""
	for _, t in pairs(components) do
		if t.address:find(pat) then
			table.insert(ret, t)
		end
	end
	return ret
end

--[[
Invokes given action
	@mod - calling module
	@id - action ID
	@p1 - 1st parameter or nil
	@p2 - 1nd parameter or nil
	@silent:boolean - whether not to display error messages
	RET: <action result> or nil
]]
interface.call = function(mod, id, p1, p2, silent)
	local a = interface.actionDetails(mod, id)
	if a then
		local et = ""
		if a.p1type and type(p1) ~= a.p1type then
			et = type(p1) .. " ~= " .. a.p1type
		elseif a.p2type and type(p2) ~= a.p2type then
			if et:len() > 0 then
				et = et .. ", " 
			end
			et = et .. type(p2) .. " ~= " .. a.p2type
		else
			local s, r = pcall(a.exec, p1, p2)
			if s then
				return r
			else
				logger:error("interface.call", "action {} call failed: {}" .. r, id, r)
				if not silent then
					GMLmessageBox(gui, "Action " .. tostring(id) .. " call failed.", {"OK"})
				end
				return nil
			end
		end
		if et:len() > 0 then
			local m = "Wrong action parameters. ("
			logger:error("interface.call", m .. et .. ")")
			if not silent then
				GMLmessageBox(gui, m .. et .. ")", {"OK"})
			end
		end
	else
		logger:error("interface.call", "action {} wasn't found", id)
		if not silent then
			GMLmessageBox(gui, "Couldn't find action " .. tostring(id) .. "!", {"OK"})
		end
	end
	return nil
end

--[[
Invokes given action by name
	@mod - calling module
	@id - action name
	@p1 - 1st parameter or nil
	@p2 - 1nd parameter or nil
	@silent:boolean - whether not to display error messages
	RET: <action result> or nil
]]
interface.callByName = function(mod, name, p1, p2, silent)
	local found = nil
	for _, t in pairs(actions) do
		for i, a in pairs(t) do
			if a.name == name then
				found = i
				break
			end
		end
		if found ~= nil then break end
	end
	if found ~= nil then
		return interface.call(mod, found, p1, p2, silent)
	else
		logger:error("interface.call", "action \"" .. name .. "\" wasn't found")
		if not silent then
			GMLmessageBox(gui, "Couldn't find action with name " .. name .. "!", {"OK"})
		end
		return nil
	end
end

--[[
Returns table of given action
	@mod - calling module
	@id - action ID
	RET: <action table> or nil
]]
interface.actionDetails = function(mod, id)
	for _, t in pairs(actions) do
		for i, a in pairs(t) do
			if i == id then
				return a
			end
		end
	end
	return nil
end

--[[
Returns the logger
	@mod - calling module
	@msg - message do display
]]
interface.logger = function(mod, msg)
	return modulesLogger
end

--[[
Similar to pcall but automatically logs error
message in the system logs.
	SINCE: API.4
]]
interface.pcall = function(mod, ...)
	local s, r = pcall(...)
	if not s then
		logger:error(mod.name, r)
	end

	return s, r
end

--[[
Runs given function in a try-catch (xpcall in Lua) block.
	@mod - subsystem or module
	@fun - function to execute
	@disableLogging - if set to true, error won't be logged
	@severe - if set to true, a crash window will be displayed (it will allow to upload to Pastebin or similar server)
	@ret status, result
	SINCE: API.6
]]
interface.tryCatch = function(mod, fun, disableLogging, severe)
	local status, result = xpcall(fun, function (message)
		local fullMessage = message .. "\n" .. debug.traceback()
		if not disableLogging then
			mod.logger:error("tryCatch", fullMessage)
		end
	end)

	if not status and severe then
		-- todo: crash window
	end

	return status, result
end

--[[
Returns function wrapped in an error handler
that will automatically add proper error
message to the system logs.
	@mod - calling module
	@fun - function to wrap
	RET: function wrapped in an error handler
	SINCE: API.4
]]
interface.errorHandler = function(mod, fun)
	return function ()
		local s, r = interface.pcall(mod, fun)
		return r
	end
end

--[[
Redirect this call to event.timer but first
wraps the callback in an interface.errorHandler
	SINCE: API.4
]]
interface.timer = function(mod, interval, callback, times)
	return event.timer(interval, interface.errorHandler(mod, callback), times)
end

--[[
Displays message box
	@mod - calling module
	@message - message to display
	@buttons - table with buttons
	RET: <selected button>
]]
interface.messageBox = function(mod, message, buttons)
	local r, e = pcall(GMLmessageBox, gui, message, buttons)
	if r then
		return e
	else
		logger:error("interface.messageBox", "couldn't display message: " .. e)
		return nil
	end
end

--[[
Displays dialog selection window
	@mod - calling module
	@type:string or nil - action category
	@target:string or nil - module name filter
	@fill:table or nil - table with current action settings ({[id:number],[p1],[p2]})
	@hidden:boolean - whether to display hidden actions
	RET:<user choice (see the fill parameter))> or nil
]]
interface.actionDialog = function(mod, typee, target, fill, hidden)
	local ac = interface.getActions(mod, typee, target)
	local sublist = nil
	local ll = {}
	local box = nil
	local rs = {}
	local ret = {}
	
	local function rebuild(l)
		ll = {}
		for _, t in pairs(l) do
			if (hidden and t.hidden) or not t.hidden then
				table.insert(ll, t.name .. " (" .. t.type:upper() .. ")")
			end
		end
		table.sort(ll)
		box:updateList(ll)
	end
	local function update(id, t)
		if not id or not t then
			ret.id = nil
			for i = 1, 7 do rs[i]:hide() end
			return
		end
		ret.id = id
		rs[1].text = t.desc:sub(1, 39)
		rs[1]:show()
		rs[1]:draw()
		rs[2]:show()
		rs[3].text = tostring(id)
		rs[3]:show()
		rs[3]:draw()
		if t.p1type then
			rs[4].text = string.sub(t.p1desc .. "(" .. t.p1type .. ")", 1, 39)
			rs[4]:show()
			rs[4]:draw()
			rs[5]:show()
			rs[5]:draw()
		else
			rs[4]:hide()
			rs[5]:hide()
		end
		if t.p2type then
			rs[6].text = string.sub(t.p2desc .. "(" .. t.p2type .. ")", 1, 39)
			rs[6]:show()
			rs[6]:draw()
			rs[7]:show()
			rs[7]:draw()
		else
			rs[6]:hide()
			rs[7]:hide()
		end
	end
	local function doRefresh(l)
		local selected = box:getSelected():match("^(.*) %(")
		if selected then
			for i, t in pairs(l) do
				if t.name == selected then
					update(i, t)
					return
				end
			end
		end
		for i = 1, 7 do rs[i]:hide() end
	end
	local function refresh()
		doRefresh(sublist or ac)
	end
	
	local agui = gml.create("center", "center", 80, 24)
	agui.style = interface.getStyle(mod)
	agui:addLabel("center", 1, 24, "Action selection window")
	rs[1] = agui:addLabel(35, 6, 40, "")
	rs[2] = agui:addLabel(35, 8, 15, "Identifier:")
	rs[4] = agui:addLabel(35, 11, 40, "")
	rs[6] = agui:addLabel(35, 14, 40, "")
	local search = agui:addTextField(2, 4, 14)
	agui:addButton(17, 4, 12, 1, "Search", function()
		if search.text:len() > 0 then
			sublist = {}
			for i, t in pairs(ac) do
				if t.name:find(search.text) then
					sublist[i] = t
				end
			end
		else
			sublist = nil
		end
		rebuild(sublist or ac)
		refresh()
	end)
	box = agui:addListBox(2, 6, 28, 14, {})
	box.onChange = refresh
	rs[3] = agui:addLabel(51, 8, 10, "")
	rs[5] = agui:addTextField(38, 12, 20)
	rs[5].visible = false
	rs[7] = agui:addTextField(38, 15, 20)
	rs[7].visible = false
	agui:addButton(3, 22, 14, 1, "Clear", function()
		ret.id = nil
		update()
	end)
	agui:addButton(63, 22, 14, 1, "Cancel", function()
		agui:close()
		ret = fill
	end)
	agui:addButton(47, 22, 14, 1, "Apply", function()
		if not ret.id then
			agui:close()
			return
		end
		local a = interface.actionDetails(nil, tonumber(rs[3].text))
		if a then
			if a.p1type then
				if a.p1type == "number" then
					local n = tonumber(rs[5].text)
					if not n then
						GMLmessageBox(gui, "First parameter must be a number.", {"OK"})
						return
					end
					ret.p1 = n
				elseif rs[5].text:len() == 0 then
					GMLmessageBox(gui, "First parameter cannot be empty.", {"OK"})
					return
				else
					ret.p1 = rs[5].text
				end
			end
			if a.p2type then 
				if a.p2type == "number" then
					local n = tonumber(rs[7].text)
					if not n then
						GMLmessageBox(gui, "Second parameter must be a number.", {"OK"})
						return
					end
					ret.p2 = n
				elseif rs[7].text:len() == 0 then
					GMLmessageBox(gui, "Second parameter cannot be empty..", {"OK"})
					return
				else
					ret.p2 = rs[7].text
				end
			end
			agui:close()
		end
	end)
	local function firstFill(id, t)
		if not id or not t then
			ret.id = nil
			for i = 1, 7 do rs[i].hidden = true end
			return
		end
		ret.id = id
		rs[1].text = t.desc:sub(1, 39)
		rs[3].text = tostring(id)
		if t.p1type then
			rs[4].text = string.sub(t.p1desc .. "(" .. t.p1type .. ")", 1, 39)
		else
			rs[4].hidden = true
			rs[5].hidden = true
		end
		if t.p2type then
			rs[6].text = string.sub(t.p2desc .. "(" .. t.p2type .. ")", 1, 39)
		else
			rs[6].hidden = true
			rs[7].hidden = true
		end
	end
	if fill and fill.id then
		local a = interface.actionDetails(nil, fill.id)
		if a then
			if fill.p1 and type(fill.p1) == "number" then
				rs[5].text = tostring(fill.p1)
			else
				rs[5].text = fill.p1 or ""
			end
			if fill.p2 and type(fill.p2) == "number" then
				rs[7].text = tostring(fill.p2)
			else
				rs[7].text = fill.p2 or ""
			end
			firstFill(fill.id, a)
		else
			firstFill()
			GMLmessageBox(gui, "Couldn't find action with given ID.", {"OK"})
		end
	else
		firstFill()
	end
	rebuild(ac)
	agui:run()
	return (ret and ret.id) and ret or nil
end

--[[
Displays component selection dialog window 
	@mod - calling module
	@typee - component type filter
	@force - include disabled compoennts
	RET: <component UID> or nil
]]
interface.componentDialog = function(mod, typee, force)
	local cl = interface.getComponentList(mod, typee, force)
	local box, list, chosenAddr, chosenUid = {}, {}, nil, nil
	local ret = nil
	
	local function refreshList()
		list = {}
		for _, t in pairs(cl) do
			local s = string.format("[%s] %s  %s  (%s, %s, %s)", t.id, t.name and t.name:sub(1, 20) or "", t.address, t.x and tostring(t.x) or "", t.y and tostring(t.y) or "", t.z and tostring(t.z) or "")
			table.insert(list, s)
		end
		box:updateList(list)
	end
	local function update()
		local sel = box:getSelected()
		if sel then
			local first = sel:find("%[")
			local last = sel:find("%]")
			if first and last then
				local found = sel:sub(first + 1, last - 1)
				local comp = interface.getComponent(mod, found, force)
				if comp then
					chosenUid.text = found
					chosenAddr.text = comp.address
					ret = found
				else
					chosenUid.text = "<not found>"
					chosenAddr.text = "<not found>"
					ret = nil
				end
				chosenUid:draw()
				chosenAddr:draw()
			end
		end
	end
	local dgui = gml.create("center", "center", 110, 27)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 27, "Component selection window")
	box = dgui:addListBox(2, 3, 104, 15, {})
	local old = box.onClick
	box.onClick = function(...)
		old(...)
		update()
	end
	dgui:addLabel(5, 20, 12, "Chosen UID:")
	dgui:addLabel(5, 21, 15, "Chosen address:")
	chosenUid = dgui:addLabel(21, 20, 10, "")
	chosenAddr = dgui:addLabel(21, 21, 40, "")
	dgui:addButton(90, 24, 14, 1, "Cancel", function()
		ret = nil
		dgui:close()
	end)
	dgui:addButton(74, 24, 14, 1, "Apply", function()
		dgui:close()
	end)
	refreshList()
	dgui:run()
	return ret
end

--[[
Dispays color picker dialog window
	@mod - calling module
	@hex:boolean - whether to return color in hex format
	@api:boolean - whether to return color in api colors format
	@name:boolean - whether to return color as text
	RET:{[hex], [colors]} or nil
]]
interface.colorDialog = function(mod, hex, api, name)
	local color = nil
	local rettab = {}
	local bar = nil
	local eqs = {
		[0] = 0xFFFFFF,
		[1] = 0xFFA500,
		[2] = 0xFF00FF,
		[3] = 0xADD8E6,
		[4] = 0xFFFF00,
		[5] = 0x00FF00,
		[6] = 0xFFC0CB,
		[7] = 0x808080,
		[8] = 0xC0C0C0,
		[9] = 0x00FFFF,
		[10] = 0x800080,
		[11] = 0x0000FF,
		[12] = 0xA52A2A,
		[13] = 0x008000,
		[14] = 0xFF0000,
		[15] = 0x000000
	}
	local function updateBar(new)
		color = new
		bar.color = eqs[new]
		bar:draw()
	end
	local cgui = gml.create("center", "center", 32, 25)
	cgui.style = gui.style
	cgui:addLabel("center", 1, 14, "Choose a color")
	for i = 0, 15 do
		local tmp = cgui:addLabel(3, 4 + i, 12, colors[i])
		tmp.onClick = function() updateBar(i) end
	end
	bar = interface.template(mod, cgui, 20, 4, 3, 16)
	bar.draw = function(t)
		if t.color then
			t.renderTarget.setBackground(t.color)
			t.renderTarget.fill(t.gui.posX + t.posX - 1, t.gui.posY + t.posY - 1, t.width, t.height, " ")
		end
	end
	cgui:addButton(1, 23, 14, 1, "Apply", function()
		if hex then table.insert(rettab, eqs[color]) end
		if api then table.insert(rettab, color) end
		if name then table.insert(rettab, colors[i]) end
		cgui:close()
	end)
	cgui:addButton(16, 23, 14, 1, "Cancel", function()
		rettab = nil
		cgui:close()
	end)
	cgui:run()
	return rettab
end

--[[
Creates a template for a new component
	@mod - calling module
	@target - target GUI
	@x - X position
	@y - Y position
	@w - element width
	@h - element height
	RET: <template>
]]
interface.template = function(mod, target, x, y, w, h)
	local temp = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		horizontal = isHorizontal,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg")
	}
	temp.posX = x + 1
	temp.posY = y + 1
	temp.width = w
	temp.height = h
	temp.contains = GMLcontains
	temp.isHidden = function() return false end
	temp.draw = function() end
	target:addComponent(temp)
	return temp
end

--[[
Returns default module directory
	@mod - calling module
	RET: absolute path to module directory
]]
interface.getConfigDirectory = function(mod)
	local dir = fs.concat(CONFIG_DIR .. "/modules", mod.name)
	if not fs.isDirectory(dir) then fs.makeDirectory(dir) end
	return dir
end

--[[
Returns encryption key
	@mod - calling module
	RET: encryption key in binary format
]]
interface.secretKey = function(mod) -- todo: remove this (settings will be managed by the dedicated subsystem)
	return token
end

--[[
Returns theme used by server
	@mod - calling module
	RET: style table
]]
interface.getStyle = function(mod)
	return gui.style
end

interface.createSettingsEditor = function (mod, settingsName)
	return subsystems.settings:createModuleSettingsEditor(mod, settingsName)
end

-- # Funkcje pomocnicze Gui
GMLmessageBox = function(target, message, buttons)
	local buttons = buttons or {"cancel", "ok"}
	local choice
	local lines = {}
	message:gsub("([^\n]+)", function(line) lines[#lines+1] = line end)
	local i = 1
	while i <= #lines do
		if #lines[i] > 46 then
			local s, rs = lines[i], lines[i]:reverse()
			local pos =- 26
			local prev = 1
			while #s > prev + 45 do
				local space = rs:find(" ", pos)
				if space then
					table.insert(lines, i, s:sub(prev, #s - space))
					prev = #s - space + 2
					pos =- (#s - space + 48)
				else
					table.insert(lines, i, s:sub(prev, prev + 45))
					prev = prev + 46
					pos = pos - 46
				end
				i = i + 1
			end
			lines[i] = s:sub(prev)
		end
		i = i + 1
	end

	local gui = gml.create("center", "center", 50, 6 + #lines, gpu)
	gui.style = target.style
	local labels = {}
	for i = 1, #lines do
		labels[i] = gui:addLabel(2, 1 + i, 46, lines[i])
	end
	local buttonObjs = {}
	local xpos = 2
	for i = 1, #buttons do
		if i == #buttons then xpos =- 2 end
		buttonObjs[i]=gui:addButton(xpos, -2, #buttons[i] + 2, 1, buttons[i], function() choice = buttons[i] gui.close() end)
		xpos = xpos + #buttons[i] + 3
	end

	gui:changeFocusTo(buttonObjs[#buttonObjs])
	gui:run()
	return choice
end

GMLcontains = function(element,x,y)
	local ex, ey, ew, eh = element.posX, element.posY, element.width, element.height
	return x >= ex and x <= ex + ew - 1 and y >= ey and y <= ey + eh - 1
end

GMLgetAppliedStyles = function(element)
	local styleRoot = element.style
	assert(styleRoot)

	local depth, state, class, elementType = element.renderTarget.getDepth(), element.state or "*", element.class or "*", element.type

	local nodes = {styleRoot}
	local function filterDown(nodes, key)
		local newNodes = {}
		for i = 1, #nodes do
			if key ~= "*" and nodes[i][key] then
				newNodes[#newNodes + 1] = nodes[i][key]
			end
			if nodes[i]["*"] then
				newNodes[#newNodes + 1] = nodes[i]["*"]
			end
		end
		return newNodes
	end
	nodes = filterDown(nodes, depth)
	nodes = filterDown(nodes, state)
	nodes = filterDown(nodes, class)
	nodes = filterDown(nodes, elementType)
	return nodes
end

GMLextractProperty = function(element, styles, property)
	if element[property] then
		return element[property]
	end
	for j = 1, #styles do
		local v = styles[j][property]
		if v ~= nil then
			return v
		end
	end
end

GMLextractProperties = function(element, styles, ...)
	local props = {...}
	local vals = {}
	for i = 1, #props do
		vals[#vals + 1] = extractProperty(element, styles, props[i])
		if #vals ~= i then
			for k, v in pairs(styles[1]) do print('"' .. k .. '"', v, k == props[i] and "<-----!!!" or "") end
			error("Could not locate value for style property " .. props[i] .. "!")
		end
	end
	return table.unpack(vals)
end

GMLfindStyleProperties = function(element,...)
	local props = {...}
	local nodes = GMLgetAppliedStyles(element)
	return GMLextractProperties(element, nodes, ...)
end

GMLcalcBody = function(element)
	local x, y, w, h = element.posX, element.posY, element.width, element.height
	local border, borderTop, borderBottom, borderLeft, borderRight =
     GMLfindStyleProperties(element, "border", "border-top", "border-bottom", "border-left", "border-right")

	if border then
		if borderTop then
			y = y + 1
			h = h - 1
		end
		if borderBottom then
			h = h - 1
		end
		if borderLeft then
			x = x + 1
			w = w - 1
		end
		if borderRight then
			w = w - 1
		end
	end
	return x, y, w, h
end

local function addBar(target, x, y, length, isHorizontal)
	local bar = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		horizontal = isHorizontal,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg")
	}
	bar.posX = x
	bar.posY = y
	bar.width = isHorizontal and length or 1
	bar.height = isHorizontal and 1 or length
	bar.contains = GMLcontains
	bar.isHidden = function() return false end
	bar.draw = function(t)
		t.renderTarget.setBackground(t.bgcolor)
		t.renderTarget.setForeground(0xffffff)
		if t.horizontal then
			t.renderTarget.set(t.posX + 1, t.posY + 1, string.rep(uni.char(0x2550), t.width))
		else
			for i = 1, t.height do
				t.renderTarget.set(t.posX + 1, t.posY + i, uni.char(0x2551))
			end
		end
	end
	target:addComponent(bar)
	return bar
end

local function addSymbol(target, x, y, code)
	local symbol = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		bgcolor = GMLextractProperty(target, GMLgetAppliedStyles(target), "fill-color-bg"),
		code = code,
		posX = x,
		posY = y,
		width = 1,
		height = 1,
		contains = GMLcontains,
		isHidden = function() return false end
	}
	symbol.draw = function(t)
		t.renderTarget.setBackground(t.bgcolor)
		t.renderTarget.setForeground(0xffffff)
		t.renderTarget.set(t.posX, t.posY, uni.char(t.code))
	end
	target:addComponent(symbol)
	return symbol
end

local function addTitle(target, posX, posY)
	local title = {
		visible = false,
		hidden = false,
		gui = target,
		style = target.style,
		focusable = false,
		type = "label",
		renderTarget = target.renderTarget,
		posX = posX,
		posY = posY,
		width = 15,
		height = 5,
		contains = GMLcontains,
		isHidden = function() return false end
	}
	title.draw = function(t)
		t.renderTarget.setBackground(0x00a6ff)
		t.renderTarget.fill(t.posX, t.posY, 5, 1, ' ') --t
		t.renderTarget.fill(t.posX + 2, t.posY + 1, 1, 4, ' ')
		t.renderTarget.fill(t.posX + 9, t.posY, 4, 1, ' ') --g
		t.renderTarget.fill(t.posX + 9, t.posY + 4, 4, 1, ' ')
		t.renderTarget.fill(t.posX + 10, t.posY + 2, 3, 1, ' ')
		t.renderTarget.set(t.posX + 8, t.posY + 1, ' ')
		t.renderTarget.set(t.posX + 8, t.posY + 3, ' ')
		t.renderTarget.set(t.posX + 7, t.posY + 2, ' ')
		t.renderTarget.set(t.posX + 12, t.posY + 3, ' ')
	end
	target:addComponent(title)
	return title
end


local function validateSubsystem(name, subsystem)
	if type(subsystem) ~= "table" then
		error("Subsystem " .. name .. " wasn't loaded correctly")
	elseif type(subsystem.initialize) ~= "function" then
		error("Subsystem '" .. name .. "' is missing initialization function")
	elseif type(subsystem.cleanup) ~= "function" then
		error("Subsystem " .. name .. " is missing cleanup function")
	elseif type(subsystem.createUI) ~= "function" then
		error("Subsystem " .. name .. " is missing UI creation function")
	end
end

local function loadSubsystem(name)
	local subsystemFile = nil
	if fs.isDirectory(fs.concat(SUBSYSTEMS_DIR, name)) then
		subsystemFile = fs.concat(SUBSYSTEMS_DIR, name, name .. ".lua")
	elseif fs.exists(fs.concat(SUBSYSTEMS_DIR, name .. ".lua")) then
		subsystemFile = fs.concat(SUBSYSTEMS_DIR, name .. ".lua")
	else
		error("Subsystem " .. name .. " wasn't found")
	end

	local compiled, err = loadfile(subsystemFile)
	if compiled then
		local status, subsystem = pcall(compiled)
		if status then
			validateSubsystem(name, subsystem)
			subsystems[name] = subsystem

			subsystem.name = name
			subsystem.api = interface
			subsystem.subsystems = subsystems
			subsystem.logger = subsystemsLogger

			if not subsystem:initialize() then
				io.stderr:write("Initialization of subsystem: " .. name .. " failed\n")
				os.exit(1)
			end
		else
			io.stderr:write("Error while starting subsystem: " .. name .. "\n")
			io.stderr:write(subsystem)
			os.exit(1)
		end
	else
		io.stderr:write("Error while loading subsystem: " .. name .. "\n")
		io.stderr:write(err)
		os.exit(1)
	end
end

local function injectContextIntoSubsystems()
	local context = {
		guiStyle = gui.style,
		api = interface
	}

	for _, subsystem in pairs(subsystems) do
		subsystem.context = context
	end
end

-- # Other functions

local function isPasswordValid(plain)
	return data.sha256(plain) == passwd
end

-- # Configuration
local save = {}

function save.err()
	GMLmessageBox(gui, "An error occurred while saving settings, check the logs.", {"OK"})
end

function save.settings(silent)
	local r, s = pcall(serial.serialize, settings)
	if r then
		local f, e = io.open("/etc/the_guard/config.conf", "w")
		if f then
			f:write(s)
			f:close()
		else
			logger:error("save", "error while opening settings file: " .. e)
			return false
		end
	else
		logger:error("save", "cannot serialize settings: " .. s)
		return false
	end
	return true
end

function save.passwd(silent)
	local output = data.encode64(passwd)
	local f, e = io.open("/etc/the_guard/passwd.bin", "wb")
	if f then
		f:write(output)
		f:close()
	else
		logger:error("save", "cannot open master password file: " .. e)
		return false
	end
	return true
end

local function saveConfig()
	if not save.settings() then
		logger:error("save", "couldn't save settings")
	end
	if not save.modules() then
		logger:error("save", "couldn't save modules' settings")
	end
	if not save.components() then
		logger:error("save", "couldn't save components' settings")
	end
	if not save.passwd() then
		logger:error("save", "couldn't save master password")
	end
end

local function loadConfig()
	local function checkSettings()
		local dirty = false
		if not settings.port then
			settings.port = math.random(1000, 50000)
			dirty = true
		end
		if not settings.backupPort then
			settings.backupPort = math.random(1000, 50000)
			dirty = true
		end
		if not settings.debugMode then
			settings.debugMode = false
			dirty = true
		end
		if not settings.dark then
			settings.dark = false
			dirty = true
		end
		if dirty then
			save.settings(true)
		end
	end
	
	local function checkModules() -- todo: move to the modules subsystem
		local counter = 0
		for i, m in pairs(modules) do
			local added = true
			if type(i) ~= "number" then
				logger:error("checkModules", "wrong zone identifier")
				modules[i] = nil
				added = false
			else
				if type(m.file) == "string" then
					local path = m.file
					if not (fs.exists(path) and not fs.isDirectory(path)) then
						logger:error("checkModules", "file doesn't exist")
						modules[i] = nil
						added = false
					end
				else
					logger:error("checkModules", "missing file name")
					modules[i] = nil
					added = false
				end
			end
			if added then counter = counter + 1 end
		end
		logger:debug("checkModules", "Checked {} module(s)", counter)
	end
	
	local function checkPassword() -- todo: to be changed
		if true then return true end 
		if not passwd or passwd:len() == 0 then
			local prev = component.gpu.setForeground(0xff0000)
			print("No master password set. Enter a new password")
			component.gpu.setForeground(prev)
			local i1, i2 = "", ""
			local text = require("text")
			repeat
				io.write("#> ")
				i1 = term.read(nil, nil, nil, "*")
				i1 = text.trim(i1)
				print("Repeat password")
				io.write("#> ")
				i2 = term.read(nil, nil, nil, "*")
				i2 = text.trim(i2)
				if i1 ~= i2 then
					local prev = component.gpu.setForeground(0xffff00)
					print("Passwords don't match. Try again.")
					component.gpu.setForeground(prev)
				end
			until i1 == i2
			passwd = data.sha256(i1)
			local f, e = io.open("/etc/the_guard/passwd.bin", "wb")
			if f then
				f:write(data.encode64(passwd))
				f:close()
			else
				logger:error("passwd", "An error occurred while saving password: " .. e)
				return false
			end
		end
		
		return true
	end

	local dir = "/etc/the_guard/"
	logger:info("loadConfig", "Loading settings")
	local path = fs.concat(dir, "/config.conf")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "r")
		if f then
			local s = serial.unserialize(f:read("*a"))
			if s then
				settings = s
			else
				logger:error("loadConfig", "settings file is corrupted or empty")
			end
			f:close()
		else
			logger:error("loadConfig", "settings file error: " .. e)
			return false
		end
	else
		logger:error("loadConfig", "settings file missing, loading defaults")
	end
	checkSettings()

	path = fs.concat(dir, "passwd.bin")
	if fs.exists(path) and not fs.isDirectory(path) then
		local f, e = io.open(path, "rb")
		if f then
			passwd = data.decode64(f:read("*a"))
			f:close()
		else
			logger:error("passwd", "couldn't open password file: " .. e)
			f:close()
			return false
		end
	else
		logger:error("passwd", "password file missing, loading defaults")
	end
	if not checkPassword() then return false end
	
	return true
end

-- # Buttons' functions
local function passwordPrompt()
	local status = false
	local function insertTextTF(tf, text)
		if tf.selectEnd ~= 0 then
			tf:removeSelected()
		end
		tf.real = tf.real:sub(1, tf.cursorIndex - 1) .. text .. tf.real:sub(tf.cursorIndex)
		tf.text = string.rep("*", #tf.real)
		tf.cursorIndex = tf.cursorIndex + #text
		if tf.cursorIndex - tf.scrollIndex + 1 > tf.width then
			local ts = tf.scrollIndex + math.floor(tf.width / 3)
			if tf.cursorIndex - ts + 1 > tf.width then
				ts = tf.cursorIndex - tf.width + math.floor(tf.width / 3)
			end
			tf.scrollIndex = ts
		end
	end
	local pgui = gml.create("center", "center", 50, 8)
	if gui then
		pgui.style = gui.style
	end
	pgui:addLabel("center", 1, 18, "Enter a password:")
	local field = pgui:addTextField("center", 3, 30)
	field.real = ""
	field.insertText = insertTextTF
	pgui:addButton(20, 5, 12, 1, "OK", function() 
		if isPasswordValid(field.real) then
			status = true
		end
		pgui:close()
	end)
	pgui:addButton(34, 5, 12, 1, "Cancel", function() pgui:close() end)
	pgui:run()
	return status
end

local function componentDetails(t)
	local shouldRefresh = false
	local dgui = gml.create("center", "center", 55, 16)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 18, "Component details")
	dgui:addLabel(2, 3, 50, "UID:        " .. t.id)
	local addrLabel = dgui:addLabel(2, 4, 50, "Address:    " .. t.address)
	dgui:addLabel(2, 5, 48, "Type:       " .. t.type)
	dgui:addLabel(2, 6, 7, "Name:")
	local name = dgui:addTextField(14, 6, 20)
	name.text = t.name or ""
	dgui:addLabel(2, 7, 9, "State:")
	local avail = dgui:addLabel(2, 8, 22, "")
	dgui:addLabel(2, 10, 17, "X coordinate:")
	dgui:addLabel(2, 11, 17, "Y coordinate:")
	dgui:addLabel(2, 12, 17, "Z coordinate:")
	local cx = dgui:addTextField(20, 10, 10)
	local cy = dgui:addTextField(20, 11, 10)
	local cz = dgui:addTextField(20, 12, 10)
	cx.text = t.x and tostring(t.x) or ""
	cy.text = t.y and tostring(t.y) or ""
	cz.text = t.z and tostring(t.z) or ""

	addrLabel.onDoubleClick = function()
		local newAddr = bNewComponent(true, t.type)
		if newAddr then
			local proxy = component.proxy(newAddr)
			if proxy and proxy.type == t.type then
				addrLabel.newAddr = newAddr
				addrLabel.text = "Address:    " .. newAddr
				addrLabel:draw()
			elseif proxy and proxy.type ~= type then
				GMLmessageBox(gui, "Component type cannot be changed.", {"OK"})
			else
				GMLmessageBox(gui, "Component isn't available.", {"OK"})
			end
		end
	end

	local button = dgui:addButton(11, 7, 13, 1, t.state and "enabled" or "disabled", function(self)
		if self.status then
			self.text = "disabled"
			self.status = false
			self:draw()
		else
			self.text = "enabled"
			self.status = true
			self:draw()
		end
	end)
	button.status = t.state
	local function refreshAvail()
		if component.proxy(t.address) then
			avail.text = "Availability: online"
		else
			avail.text = "Availability: offline"
			button.status = false
			button.text = "disabled"
			button:draw()
		end
		avail:draw()
	end
	refreshAvail()
	dgui:addButton(25, 8, 12, 1, "Refresh", refreshAvail)
	dgui:addButton(4, 15, 14, 1, "Remove", function()
		if GMLmessageBox(gui, "Are you sure you want to remove this element?", {"Yes", "No"}) == "Yes" then
			for i, t2 in pairs(components) do
				if t.address == t2.address then
					components[i] = nil
					save.components(true)
					dgui:close()
					break
				end
			end
		end
	end)
	dgui:addButton(20, 15, 14, 1, "Save", function()
		local nx = tonumber(cx.text)
		local ny = tonumber(cy.text)
		local nz = tonumber(cz.text)
		if not nx and cx.text:len() > 0 then
			GMLmessageBox(gui, "The X coordinate is incorrect.", {"OK"})
		elseif not ny and cy.text:len() > 0 then
			GMLmessageBox(gui, "The Y coordinate is incorrect.", {"OK"})
		elseif not nz and cz.text:len() > 0 then
			GMLmessageBox(gui, "The Z coordinate is incorrect.", {"OK"})
		elseif name.text:len() > 20 then
			GMLmessageBox(gui, "Name cannot be longer than 20 characters.", {"OK"})
		else
			t.state = button.status
			t.name = name.text
			t.x = nx
			t.y = ny
			t.z = nz
			if addrLabel.newAddr then t.address = addrLabel.newAddr end
			save.components(true)
			computer.pushSignal("components_changed", t.type)
			dgui:close()
			shouldRefresh = true
		end
	end)
	dgui:addButton(36, 15, 14, 1, "Cancel", function() dgui:close() end)
	dgui:run()
	return shouldRefresh
end

local function componentDistribution()
	local list, all, tab = nil, nil
	local function refreshList()
		local buffer = {}
		local total = 0
		for _, c in pairs(component.list()) do
			if not buffer[c] then buffer[c] = 0 end
			buffer[c] = buffer[c] + 1
			total = total + 1
		end
		local b2 = {}
		for a, b in pairs(buffer) do
			table.insert(b2, {a, b})
		end
		table.sort(b2, function(a, b) return a[1]:byte(1) < b[1]:byte(1) end)
		tab = {}
		for _, t in pairs(b2) do
			table.insert(tab, t[1]:upper() .. ": " .. tostring(t[2]))
		end
		all.text = "Razem: " .. tostring(total)
	end
	local dgui = gml.create("center", "center", 50, 18)
	dgui.style = gui.style
	dgui:addLabel("center", 1, 22, "Component distrubution")
	all = dgui:addLabel(4, 13, 15, "")
	refreshList()
	list = dgui:addListBox(2, 3, 44, 9, tab)
	dgui:addButton(18, 15, 14, 1, "Refresh", function()
		refreshList()
		list:updateList(tab)
		all:draw()
	end)
	dgui:addButton(34, 15, 14, 1, "Close", function() dgui:close() end)
	dgui:run()
end

local function bInformation()
	local igui = gml.create("center", "center", 50, 11)
	igui.style = gui.style
	igui:addLabel("center", 1, 11, "Information")
	igui:addLabel(2, 3, 14, "Disk usage:")
	igui:addLabel(2, 4, 16, "Memory usage:")
	igui:addLabel(2, 5, 23, "Connected component:")
	igui:addLabel(2, 6, 18, "Available energy:")
	local iHdd = igui:addLabel(26, 3, 20, "")
	local iMem = igui:addLabel(26, 4, 20, "")
	local iCom = igui:addLabel(26, 5, 20, "")
	local iEne = igui:addLabel(26, 6, 20, "")
	local function refreshInformation()
		local fs = component.proxy(computer.getBootAddress())
		if fs then
			local a = math.ceil(fs.spaceUsed() / 1024)
			local b = math.ceil(fs.spaceTotal() / 1024)
			local str = tostring(math.ceil(a / b * 100)) .. "%  "
			str = str .. tostring(a) .. "/" .. tostring(b) .. "KB"
			iHdd.text = str
		else
			iHdd.text = "N/A"
		end
		iHdd:draw()
		local total = math.ceil(computer.totalMemory() / 1024)
		local free = total - math.ceil(computer.freeMemory() / 1024)
		local str = tostring(math.ceil(free / total * 100)) .. "%  "
		str = str .. tostring(free) .. "/" .. tostring(total) .. "KB"
		iMem.text = str
		iMem:draw()
		local camount = 0
		for _, _ in component.list() do camount = camount + 1 end
		iCom.text = tostring(camount)
		iCom:draw()
		iEne.text = tostring(math.ceil(computer.energy() / computer.maxEnergy() * 100)) .. "%"
		iEne:draw()
	end
	iCom.onDoubleClick = componentDistribution
	refreshInformation()
	igui:addButton(18, 8, 14, 1, "Refresh", refreshInformation)
	igui:addButton(34, 8, 14, 1, "Close", function() igui:close() end)
	igui:run()
end

local function backup(port)
	if GMLmessageBox(gui, "Are you sure you want to create a backup?", {"Yes", "No"}) == "No" then
		return
	end
	if not dsapi.echo(port or 1) then
		GMLmessageBox(gui, "Data server wasn't found.", {"OK"})
		return
	end
	
	local list = {}
	local function updateList(path)
		local iter, err = fs.list(fs.concat("/etc", path))
		if not iter then
			GMLmessageBox(gui, "Couldn't create element list: " .. err, {"OK"})
			return false
		end
		for s in iter do
			local subpath = fs.concat(path, s)
			if s:sub(-1) == "/" then
				if not updateList(subpath) then return false end
			else
				table.insert(list, subpath)
			end
		end
		return true
	end
	local bgui
	local function beginBackup()
		local maxx = #list
		local success = true
		local errormsg = ""
		for _, t in pairs(list) do
			local file, e = io.open(fs.concat("/etc", t), "r")
			if file then
				local status, err = dsapi.write(port, t, file:read("*a"))
				file:close()
				if not status then
					errormsg = dsapi.translateCode(err)
					success = false
					break
				end
			else
				errormsg = e
				success = false
				break
			end
		end
		if success then
			GMLmessageBox(gui, "Backup has been successfully created!", {"OK"})
		else
			GMLmessageBox(gui, "Couldn't create a backup: " .. errormsg, {"OK"})
		end
		bgui:close()
	end
	if updateList("/the_guard") then
		bgui = gml.create("center", "center", 60, 7)
		bgui.style = gui.style
		bgui:addLabel("center", 2, 44, "During backup procedure server")
		bgui:addLabel("center", 3, 22, "may be unresponsive.")
		bgui:addButton("center", 5, 14, 1, "Start", beginBackup)
		bgui:run()
	end
end

local function restore(port)
	if GMLmessageBox(gui, "Are you usre you want to restore data from backup?", {"Yes", "No"}) == "No" then
		return
	end
	if not dsapi.echo(port or 1) then
		GMLmessageBox(gui, "Data server wans't found.", {"OK"})
		return
	end
	
	local function createList(list, path)
		local status, iter = dsapi.list(port, path)
		if status then
			for name, size in iter do
				local subpath = fs.concat(path, name)
				if size == -1 then
					local a, b = createList(list, subpath)
					if not a then return false, b end
				else
					table.insert(list, subpath)
				end
			end
		else
			return false, dsapi.translateCode(iter)
		end
		return true
	end
	local function checkDirectory(path)
		local segments = fs.segments(path)
		table.remove(segments, #segments)
		local subpath = ""
		for _, t in pairs(segments) do subpath = subpath .. "/" .. t end
		if not fs.isDirectory(subpath) then
			fs.makeDirectory(subpath)
		end
	end
	local rgui = nil
	local function beginRestore()
		local list = {}
		local status, e = createList(list, "/the_guard")
		local success = true
		if status then
			for _, t in pairs(list) do
				local s2, content = dsapi.get(port, t)
				if s2 then
					local subpath = fs.concat("/etc", t)
					checkDirectory(subpath)
					local file, e2 = io.open(subpath, "w")
					if file then
						file:write(content)
						file:close()
					else
						success = false
						GMLmessageBox(gui, "Couldn't create file: " .. e2, {"OK"})
						break
					end
				else
					success = false
					GMLmessageBox(gui, "Data restore operation failed: " .. dsapi.translateCode(content), {"OK"})
					break
				end
			end
		else
			success = false
			GMLmessageBox(gui, "Couldn't create file list: " .. e, {"OK"})
		end
		if success then
			GMLmessageBox(gui, "Data restore completed. The computer will reboot.", {"OK"})
			computer.shutdown(true)
		end
		rgui:close()
	end
	
	rgui = gml.create("center", "center", 60, 8)
	rgui.style = gui.style
	rgui:addLabel("center", 2, 44, "During data restore server may be")
	rgui:addLabel("center", 3, 47, "unresponsive. After the operation")
	rgui:addLabel("center", 4, 30, "computer will reboot.")
	rgui:addButton("center", 6, 14, 1, "Start", beginRestore)
	rgui:run()
end

local function openMainSettings()
	
	local sgui = gml.create("center", "center", 60, 13)
	sgui.style = gui.style
	sgui:addLabel("center", 1, 11, "Settings")
	sgui:addLabel(2, 3, 13, "Main port:")
	sgui:addLabel(2, 4, 12, "Backup port:")
	sgui:addLabel(2, 6, 18, "Debug mode:")
	sgui:addLabel(2, 7, 14, "Dark theme:")
	sgui:addLabel(2, 8, 23, "Save before closing:")
	local mainport = sgui:addTextField(16, 3, 9)
	mainport.text = tostring(settings.port)
	local backupport = sgui:addTextField(16, 4, 9)
	backupport.text = tostring(settings.backupPort)
	local function switchState(self)
		if self.status then
			self.status = false
			self.text = "no"
		else
			self.status = true
			self.text = "yes"
		end
		self:draw()
	end
	local function switchDebugMode(self)
		if not self.status then
			local mmsg =
[[
Activation of debug mode will turn
off password protection. Are you
sure you want to continue?
]]
			if GMLmessageBox(gui, mmsg, {"Yes", "No"}) == "No" then return end
			switchState(self)
		else
			switchState(self)
		end
	end
	local bDebug = sgui:addButton(26, 6, 11, 1, "", switchDebugMode)
	bDebug.text = settings.debugMode and "yes" or "no"
	bDebug.status = settings.debugMode
	local bDark = sgui:addButton(26, 7, 11, 1, "", switchState)
	bDark.text = settings.dark and "yes" or "no"
	bDark.status = settings.dark
	local bSave = sgui:addButton(26, 8, 11, 1, "", switchState)
	bSave.text = settings.saveOnExit and "yes" or "no"
	bSave.status = settings.saveOnExit
	sgui:addButton(41, 3, 16, 1, "Backup", function()
		local n = tonumber(backupport.text)
		if n and n > 1 and n < 65535 then
			backup(n)
		else
			backup(nil)
		end
	end)
	sgui:addButton(41, 5, 16, 1, "Restore", function()
		local n = tonumber(backupport.text)
		if n and n > 1 and n < 65535 then
			restore(n)
		else
			restore(nil)
		end
	end)
	sgui:addButton(27, 10, 14, 1, "Apply", function()
		local p1 = tonumber(mainport.text)
		local p2 = tonumber(backupport.text)
		if not p1 then
			GMLmessageBox(gui, "Main port is invalid.", {"OK"})
		elseif p1 > 65535 or p1 < 1 then
			GMLmessageBox(gui, "Main port is out of range.", {"OK"})
		elseif not p2 then
			GMLmessageBox(gui, "Backup port is invalid.", {"OK"})
		elseif p2 > 65535 or p2 < 1 then
			GMLmessageBox(gui, "Backup port is out of range.", {"OK"})
		else
			local p1open, p2open = false, false
			if modem and modem.isOpen(p1) then
				modem.close(p1)
				p1open = true
			end
			if modem and modem.isOpen(p2) then
				modem.close(p2)
				p2open = true
			end
			settings.port = p1
			settings.backupPort = p2
			settings.debugMode = bDebug.status
			settings.dark = bDark.status
			settings.saveOnExit = bSave.status
			if p1open and modem then modem.open(p1) end
			if p2open and modem then modem.open(p2) end
			save.settings(true)
			sgui:close()
		end
	end)
	sgui:addButton(43, 10, 14, 1, "Cancel", function() sgui:close() end)
	sgui:run()
end

local function lockInterface()
	if settings.debugMode then return end

	local function showLock()
		local lgui = gml.create(1, 1, resolution[1], resolution[2])
		lgui.style = gui.style
		lgui:addLabel("center", 23, 22, " << PROGRAM LOCKED >>")
		lgui:addButton("center", 25, 16, 3, "UNLOCK", function()
			if passwordPrompt() then
				lgui:close()
			else
				GMLmessageBox(lgui, "Entered password is incorrect.", {"OK"})
			end
		end)
		lgui:run()	
	end

	local frame = gml.api.saveFrame(gui)
	while true do
		local s, e = pcall(showLock)
		if s then break end
	end
	gml.api.restoreFrame(frame)
end

-- # Crash protection
local function safeCall(fun, ...)
	local s, r = pcall(fun, ...)
	if not s then
		GMLmessageBox(gui, "An error occurred during program execution.\nFurther details are available in logs.")
		local trace = debug.traceback()
		trace = trace:gsub('\t', '')
		logger:error("safeCall", r .. "\n" .. trace)
		gui:draw()
		return nil
	end
	return r
end

local function secureErrorHandler(err)
	local trace = debug.traceback()
	trace = trace:gsub('\t', '')
	logger:error("secureFunction", err .. '\n' .. trace)
end

local function secureFunction(fun, ...)
	-- todo: temporarily disable error handler while logging sybsystem overhaul is in progress
	if true then return fun(...) end 

	local args = {...}
	local call = function()
		fun(table.unpack(args))
	end
	local s, r = xpcall(call, secureErrorHandler)
	if not s then
		GMLmessageBox(gui, "An error occurred during module execution.\nFurther details are available in logs.")
		gui:draw()
		return nil
	end
	return r
end

local function errorHandler(err)
	logger:error("An error occurred: " .. err)
	io.stderr:write(debug.traceback()) -- todo: shouldn't this be written to log?
	print()
end

local function bExit(b)
	if not settings.debugMode then
		if not passwordPrompt() then
			GMLmessageBox(gui, "Entered password is incorrect.", {"OK"})
			return
		end
	end
	gui:close()
end

-- # Main GUI
local function createMainGui()
	logger:info("gui", "Creating main GUI")
	gui = gml.create(1, 1, resolution[1], resolution[2])
	
	if settings.dark then
		local s, r = pcall(gml.loadStyle, "dark")
		if s then
			gui.style = r
		else
			logger:error("gui", "cannot load dark theme")
		end
	end
	
	addTitle(gui, 143, 3)
	gui:addLabel(150, 7, 8, "(" .. version .. ")")
	gui:addButton(141, 13, 16, 1, "Components", function() subsystems.components:showComponentManager() end)
	gui:addButton(141, 15, 16, 1, "New component", function() subsystems.components:showNewComponentWizard() end)
	gui:addButton(141, 17, 16, 1, "Modules", function() subsystems.modules:showModuleManager() end)
	gui:addButton(141, 19, 16, 1, "Information", function() safeCall(bInformation) end)
	gui:addButton(142, 25, 14, 1, "Settings", function() safeCall(openMainSettings) end)
	gui:addButton(142, 27, 14, 1, "Lock program", function() safeCall(lockInterface) end)
	gui:addButton(142, 29, 14, 1, "Exit", function() safeCall(bExit) end)
	
	addBar(gui, 138, 1, 39, false)
	addBar(gui, 1, 40, 158, true)
	addBar(gui, 69, 1, 19, false)
	addBar(gui, 69, 21, 19, false)
	addBar(gui, 1, 20, 68, true)
	addBar(gui, 70, 20, 68, true)
	
	addSymbol(gui, 70, 1, 0x2566)
	addSymbol(gui, 139, 1, 0x2566)
	addSymbol(gui, 1, 21, 0x2560)
	addSymbol(gui, 1, 41, 0x2560)
	addSymbol(gui, 139, 21, 0x2563)
	addSymbol(gui, 160, 41, 0x2563)
	addSymbol(gui, 70, 41, 0x2569)
	addSymbol(gui, 139, 41, 0x2569)
	addSymbol(gui, 70, 21, 0x256c)
end

-- # Loader
local function initializeActions()
	actions = {}

	actions["the_guard"] = {
		[1] = {
			name = "reflect",
			type = "CORE",
			desc = "Invokes function of given component",
			p1type = "string",
			p2type = "string",
			p1desc = "Component UID",
			p2desc = "Function invocation",
			hidden = false,
			exec = function(p1, p2)
				local comp = interface.getComponent(internalMod, p1, false)
				if comp then
					local invocation = "component.proxy('" .. comp.address .. "')." .. p2
					local fun, err = load(invocation)
					if fun then
						fun()
					else
						logger:error("reflect", "function invocation failed: " .. err)
					end
				else
					logger:error("reflect", "couldn't find component with id " .. p1)
				end
			end
		}
	}

	-- todo: actions
	-- for _, t in pairs(modules) do 
	-- 	local mul = mod[t.name].id * 100
	-- 	local buff = {}
	-- 	for n, at in pairs(mod[t.name].actions) do
	-- 		buff[n + mul] = at
	-- 	end
	-- 	actions[t.name] = buff
	-- end
end

-- #Event listeners
backgroundListener = function(...)
	local params = {...}
	for m, t in pairs(events) do
		for _, n in pairs(t) do
			if params[1] == n and mod[m] then
				local s, r = pcall(function () mod[m].pullEvent(table.unpack(params)) end)
				if not s then
					logger:error(mod[m].name .. ".event", r)
				end
			end
		end
	end
end

local function getComponentID(addr)
	for i, t in pairs(components) do
		if t.address == addr then return i end
	end
	return nil
end

local function internalListener(...)
	local params = {...}
	if params[1] == "component_added" then
		local id = getComponentID(params[2])
		if id then
			components[id].state = true
		end
	elseif params[1] == "component_removed" then
		local id = getComponentID(params[2])
		if id then
			components[id].state = false
		end
	end
end

local function createSubsystemsGUIs()
	logger:info("subsystems", "Creatings subsystems' GUIs")
	for _, subsystem in pairs(subsystems) do
		subsystem:createUI(gui)
	end
end

local function main()
	if fs.exists("/etc/the_guard") and not fs.isDirectory("/etc/the_guard") then
		logger.warn("configuration", "deleting invalid directory")
		fs.remove("/etc/the_guard")
	end
	if not fs.exists("/etc/the_guard") then
		logger:info("configuration", "config directory missing, creating")
		fs.makeDirectory("/etc/the_guard")
	end

	logger:info("configuration", "Loading configuration")
	if not loadConfig() then
		logger:error("configuration", "loading failed")
		return false
	end
	
	if not settings.debugMode then
		local try = 0
		repeat
			if passwordPrompt() then break end
			try = try + 1
		until try == 3
		if try == 3 then
			logger:error("configuration", "too many incorrect password attempts")
			return false
		end
	end
	
	subsystems.components:loadComponents()
	subsystems.modules:loadModules()
	
	createMainGui()
	createSubsystemsGUIs()

	subsystems.modules:launchModules()
	
	logger:info("init", "Loading event listeners")
	event.listen("component_added", internalListener)
	event.listen("component_removed", internalListener)
	for _, e in pairs(revents) do
		event.listen(e, backgroundListener)
	end
	eventsready = true

	injectContextIntoSubsystems()
	
	logger:info("init", "Starting the server")
	subsystems.logging:setGUIMode(true)
	os.sleep(0.5)
	gui:run()
	os.sleep(0.5)
	subsystems.logging:setGUIMode(false)
	eventsready = nil
	
	logger:info("init", "Unloading events listeners")
	event.ignore("component_added", internalListener) -- todo: this should probably be moved to the cleanup function
	event.ignore("component_removed", internalListener)
	for _, e in pairs(revents) do
		event.ignore(e, backgroundListener)
	end
	
	for n, m in pairs(mod) do
		logger:debug("init", "Disabling module " .. n)
		xpcall(m.stop, errorHandler, interface)
	end
	
	if settings.saveOnExit then
		logger:info("init", "Saving configuration")
		saveConfig()
	end

	return true
end

local function initailizeLogging()
	logger = subsystems.logging:createLogger("main")
	subsystemsLogger = subsystems.logging:createLogger("subsystems")
	modulesLogger = subsystems.logging:createLogger("modules")
end

local function init()
	loadSubsystem("migration")
	subsystems.migration:migrate()
	subsystems.migration = nil

	loadSubsystem("settings")
	loadSubsystem("logging")
	initailizeLogging()

	loadSubsystem("components")
	loadSubsystem("ui")
	loadSubsystem("modules")

	if not fs.isDirectory(CONFIG_DIR) then
		fs.makeDirectory(CONFIG_DIR)
	end

	local prev = component.gpu.setForeground(0x00ff00)
	print("THE GUARD server, version " .. version .. "\n")
	component.gpu.setForeground(prev)

	logger:info("init", "Loading token")
	logger:info("init", "Initializing the server")
	if not main() then
		logger:error("init", "Initialization failed")
		return
	end
end

local function cleanup()
	if logger then logger:close() end
	if subsystemsLogger then subsystemsLogger:close() end
	if modulesLogger then modulesLogger:close() end

	if subsystems then
		for _, subsystem in pairs(subsystems) do
			if subsystem.cleanup then subsystem:cleanup() end
		end
	end
end

local function starter()
	local status, msg = xpcall(init, function (err)
		io.stderr:write("Unhandled the_guard error:\n")
		io.stderr:write(err .. "\n")
		io.stderr:write(debug.traceback())
	end)

	-- Cleanup must always be called (i.e. to close open files)
	cleanup()
end

starter()