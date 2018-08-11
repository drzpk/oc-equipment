-- ##########################################
-- #				mod_tg_auth				#
-- #										#
-- #  05.2016			by: Dominik Rzepka  #
-- ##########################################

--[[
	## Program description ##
		The mod_tg_auth is a module used by the_guard server (since 2.0).
		It requires the "OpenSecurity" Minecraft mod to be installed.
		This module allows to manage user authentication using keypads, biometric scanners or magnetic cards.
		
	## Akcje ##
		- lockMag() - blokuje czytniki kart
		- unlockMag() - odblokowuje czytniki kart
		- lockBio() - blokuje skanery biometryczne
		- unlockBio() - odblokowuje skanery biometryczne
		- lockKeypad() - blokuje klawiatury
		- unlockKeypad() - odblokowuje klawiatury

	## Actions ##
		- lockMag() - locks magnetic card readers (they can't be used)
		- unlockMag() - unlocks magnetic card readers
		- lockBio() - locks biometric scanners
		- unlockBio() - unlocks biometric scanners
		- lockKeypad() - locks keypads
		- unlockKeypad() - unlocks keypads
		
	## Functions ##
		* using external components (from the "OpenSecurity" mod) to trigger arbitrary set of actions
		* every event can trigger up to 3 open and 3 close actions
		* configurable delay between triggering open and close actions
		* keypads' keys can be shuffled
		
	## Configuration scheme ##
		cards: { - list of registered cards (/etc/the_guard/modules/auth/cards.dat)
			{
				id:string - card id
				owner:string - owner
				name:string - card name
			}
			...
		}
		users: { - list of users that can use biometric reader (/etc/the_guard/modules/auth/users.dat)
			{
				uuid:string - user identifier (UUID from Minecraft)
				name:string - user name
			}
			...
		}
		devices: { - biometric readers and keyboards (/etc/the_guard/modules/auth/devices.dat)
			readers: {
				{
					name:string - name
					address:string - address
					delay:number - delay between triggering open and close actions
					disabled:boolean - whether this reader is disabled
					open: {
						{
							id:number - action id
							p1:any - 1st parameter
							p2:any - 2nd parameter
						}
						...
					}
					close: {
						{
							id:number - action id
							p1:any - 1st parameter
							p2:any - 2nd parameter
						}
						...
					}
				}
				...
			},
			keypads: {
				(same as readers) +
				shuffle:boolean - whether to shuffle keypads' keys order
			},
			biometrics: {
				(same as readers)
			}
		}
]]

local version = "1.2"
local args = {...}

if args[1] == "version_check" then return version end

local fs = require("filesystem")
local event = require("event")
local component = require("component")
local serial = require("serialization")
local colors = require("colors")
local gml = require("gml")
local data = component.data

local mod = {}
local server = nil
local config = nil
local readers = nil
local keypads = nil
local biometrics = nil
local cards = nil
local users = nil
local inputs = {}
local internalBioEvent = nil

local lbox, rbox = nil, nil
local element = {}

local texts = {
	open = {"open", 2},
	closed = {"close", 6},
	lock = {"locked", 5},
	wrong = {"wrong", 4}
}

local function decrypt(d)
	local s, b = pcall(data.decode64, d)
	if s then
		local s, dec = pcall(data.decrypt, b, server.secretKey(mod), data.md5("auth"))
		if s then
			local s, tab = pcall(serial.unserialize, dec)
			if s then
				return tab
			end
		end
	end
	return nil
end

local function loadInternals()
	local dir = server.getConfigDirectory(mod)
	
	cards = {}
	local cfile = io.open(fs.concat(dir, "cards.dat"), "r")
	if cfile then
		local dd = decrypt(cfile:read("*a"))
		cfile:close()
		if dd then
			cards = dd
		end
	end
	users = {}
	local cfile = io.open(fs.concat(dir, "users.dat"), "r")
	if cfile then
		local dd = decrypt(cfile:read("*a"))
		cfile:close()
		if dd then
			users = dd
		end
	end
	
	readers = {}
	keypads = {}
	biometrics = {}
	local dfile = io.open(fs.concat(dir, "devices.dat"), "r")
	if dfile then
		local dd = decrypt(dfile:read("*a"))
		dfile:close()
		if dd then
			readers = dd.readers or {}
			keypads = dd.keypads or {}
			biometrics = dd.biometrics or {}
		end
	end
end

local function encrypt(d)
	local s, ser = pcall(serial.serialize, d)
	if s then
		local s, enc = pcall(data.encrypt, ser, server.secretKey(mod), data.md5("auth"))
		if s then
			local s, b = pcall(data.encode64, enc)
			if s then
				return b
			end
		end
	end
	return nil
end

local function saveInternals()
	local dir = server.getConfigDirectory(mod)
	
	local ce = encrypt(cards)
	if ce then
		local cfile = io.open(fs.concat(dir, "cards.dat"), "w")
		if cfile then
			cfile:write(ce)
			cfile:close()
		end
	end
	local ce = encrypt(users)
	if ce then
		local cfile = io.open(fs.concat(dir, "users.dat"), "w")
		if cfile then
			cfile:write(ce)
			cfile:close()
		end
	end
	
	local tab = {}
	tab.readers = readers
	tab.keypads = keypads
	tab.biometrics = biometrics
	local de = encrypt(tab)
	if de then
		local dfile = io.open(fs.concat(dir, "devices.dat"), "w")
		if dfile then
			dfile:write(de)
			dfile:close()
		end
	end
end

local function getShuffled()
	local tab = {}
	local pending = ""
	while #tab < 10 do
		pending = tostring(math.random(10) - 1)
		local added = false
		for _, s in pairs(tab) do
			if s == pending then
				added = true
				break
			end
		end
		if not added then
			table.insert(tab, pending)
		end
	end
	return tab
end

local function refreshKeypads()
	local function getInfo(addr)
		for _, t in pairs(keypads) do
			if t.address == addr then return t end
		end
		return nil
	end
	local comp = server.getComponentList(mod, "os_keypad")
	for _, t in pairs(comp) do
		local proxy = component.proxy(t.address)
		local tab = getInfo(t.address)
		if proxy and t.state and tab then
			if tab.shuffle or config.shuffleAll then
				local tab = getShuffled()
				for i = 1, 9 do
					proxy.setKey(i, tab[i], 7)
				end
				proxy.setKey(11, tab[10], 7)
			else
				for i = 1, 9 do
					proxy.setKey(i, tostring(i), 7)
				end
				proxy.setKey(10, "*", 7)
				proxy.setKey(11, "0", 7)
				proxy.setKey(12, "#", 7)
			end
			if config.keypads and not tab.disabled then
				if not inputs[t.address] then
					proxy.setDisplay(config.msg[1], config.msg[2])
				end
			else
				proxy.setDisplay(texts.lock[1], texts.lock[2])
			end
		end
	end
end

local function newCard()
	local color = nil
	local function chooseColor()
		local ret = server.colorDialog(mod, false, true)
		if ret then
			color.color = ret[1]
			color.text = colors[ret[1]]
			color:draw()
		end
	end

	local ngui = gml.create("center", "center", 50, 17)
	ngui.style = server.getStyle(mod)
	ngui:addLabel("center", 1, 9, "New card")
	ngui:addLabel(3, 4, 6, "Name:")
	ngui:addLabel(3, 6, 7, "Owner:")
	ngui:addLabel(3, 10, 8, "Locked:")
	local tmp = ngui:addLabel(3, 8, 8, "Kolor:")
	tmp.onClick = chooseColor
	
	local name = ngui:addTextField(17, 4, 20)
	local owner = ngui:addTextField(17, 6, 20)
	color = ngui:addLabel(17, 8, 16, "")
	color.onClick = chooseColor
	local lock = ngui:addButton(17, 10, 10, 1, "Yes", function(t)
		if t.status then
			if server.messageBox(mod, "Enabling this option will allow future card\nmodifications (unsafe). Are you sure\nyou want to continue?", {"Yes", "No"}) == "Yes" then
				t.status = false
				t.text = "No"
				t:draw()
			end
		else
			t.status = true
			t.text = "Yes"
			t:draw()
		end
	end)
	lock.status = true
	
	ngui:addButton(16, 14, 14, 1, "Save", function()
		if name.text:len() < 1 or name.text:len() > 16 then
			server.messageBox(mod, "Card name should have from 1 to 16 characters.", {"OK"})
		elseif owner.text:len() == 0 then
			server.messageBox(mod, "Enter the card owner.", {"OK"})
		elseif owner.text:len() > 32 then
			server.messageBox(mod, "Maximum owner's name length is 32 characters.", {"OK"})
		elseif not color.color then
			server.messageBox(mod, "Choose color of the card.", {"OK"})
		else
			local writer = component.os_cardwriter
			if writer then
				local status, msg = writer.write(data.deflate(owner.text), name.text, lock.status, color.color)
				if status then
					local tab = {}
					tab.id = msg
					tab.owner = owner.text
					tab.name = name.text
					table.insert(cards, tab)
					server.messageBox(mod, "Card was written!", {"OK"})
					ngui:close()
				else
					server.messageBox(mod, "Couldn't write card: " .. msg, {"OK"})
				end
			else
				server.messageBox(mod, "Card writer couldn't be found.", {"OK"})
			end
		end
	end)
	ngui:addButton(32, 14, 14, 1, "Cancel", function()
		ngui:close()
	end)
	ngui:run()
end

local function cardManager()
	local list, box = {}, nil
	local function refresh()
		list = {}
		for i, t in pairs(cards) do
			table.insert(list, string.format("%d. %s (%s, %s)", i, t.id, t.owner:upper(), t.name))
		end
		box:updateList(list)
	end
	local cgui = gml.create("center", "center", 90, 20)
	cgui.style = server.getStyle(mod)
	cgui:addLabel("center", 1, 13, "Card manager")
	box = cgui:addListBox(3, 3, 83, 12, {})
	cgui:addButton(72, 17, 14, 1, "Close", function() cgui:close() end)
	cgui:addButton(3, 17, 14, 1, "Add", function()
		if #cards < 16 then
			newCard()
			refresh()
		else
			server.messageBox(mod, "Card limit has been reached.", {"OK"})
		end
	end)
	cgui:addButton(19, 17, 14, 1, "Remove", function()
		local sel = box:getSelected()
		if sel and server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "Yes" then
			local num = tonumber(sel:match("^(%d+)%."))
			if num then
				table.remove(cards, num)
				refresh()
			end
		end
	end)
	refresh()
	cgui:run()
end

local function newUser()
	local bioId, bioName, userId, readAgain = nil, nil, nil, nil
	local function reloadListener()
		bioId.text = ""
		bioId:draw()
		bioName.text = ""
		bioName:draw()
		userId.text = ""
		userId:draw()
		internalBioEvent = function(event)
			if not readAgain.visible then
				readAgain.visible = true
				readAgain:draw()
			end
			bioId.text = event[2]
			bioId:draw()
			userId.text = event[3]
			userId:draw()
			local components = server.getComponentList(mod, "os_biometric")
			for _, t in pairs(components) do
				if t.address == event[2] then
					bioName.text = t.name
					bioName:draw()
					break
				end
			end
			internalBioEvent = nil
		end
	end

	local ngui = gml.create("center", "center", 75, 14)
	ngui.style = server.getStyle(mod)
	ngui:addLabel("center", 1, 16, "Add a new user")
	ngui:addLabel(2, 3, 56, "Click on any reader in order to read your identifier.")
	ngui:addLabel(2, 5, 22, "Reader's identifier:")
	ngui:addLabel(2, 6, 22, "Saved reader's name:")
	ngui:addLabel(2, 7, 18, "User identifier:")
	bioId = ngui:addLabel(31, 5, 37, "")
	bioName = ngui:addLabel(31, 6, 37, "")
	userId = ngui:addLabel(31, 7, 37, "")
	ngui:addLabel(2, 9, 12, "User name:")
	local userName = ngui:addTextField(24, 9, 30)
	readAgain = ngui:addButton(2, 12, 18, 1, "Read again", function()
		reloadListener()
	end)
	readAgain.visible = false
	ngui:addButton(27, 12, 14, 1, "Apply", function() 
		if bioId.text:len() == 0 then
			server.messageBox(mod, "No user was scanned.", {"OK"})
		elseif userName.text:len() == 0 then
			server.messageBox(mod, "Enter user display naem.", {"OK"})
		elseif userName.text:len() > 20 then
			server.messageBox(mod, "Maximum user name length is 20 characters.", {"OK"})
		else
			local entry = {
				uuid = userId.text,
				name = userName.text
			}
			table.insert(users, entry)
			internalBioEvent = nil
			ngui:close()
		end
	end)
	ngui:addButton(44, 12, 14, 1, "Cancel", function() 
		internalBioEvent = nil
		ngui:close()
	 end)

	reloadListener()
	ngui:run()
end

local function userManager()
	local list, box = {}, nil
	local function refresh()
		list = {}
		for i, t in pairs(users) do
			table.insert(list, string.format("%d. %s (%s)", i, t.uuid, t.name))
		end
		box:updateList(list)
	end

	local ugui = gml.create("center", "center", 80, 20)
	ugui.style = server.getStyle(mod)
	ugui:addLabel("center", 1, 18, "User management")
	box = ugui:addListBox(3, 3, 73, 12, {})
	ugui:addButton(62, 17, 14, 1, "Close", function() ugui:close() end)
	ugui:addButton(3, 17, 14, 1, "Add", function()
		if #users < 16 then
			newUser()
			refresh()
		else
			server.messageBox(mod, "User limit has been reached.", {"OK"})
		end
	end)
	ugui:addButton(19, 17, 14, 1, "Remove", function()
		local sel = box:getSelected()
		if sel and server.messageBox(mod, "Are you sure you want to remove the selected element?", {"Yes", "No"}) == "Yes" then
			local num = tonumber(sel:match("^(%d+)%."))
			if num then
				table.remove(users, num)
				refresh()
			end
		end
	end)
	refresh()
	ugui:run()
end

local function codeManager()
	local cgui = gml.create("center", "center", 40, 14)
	cgui.style = server.getStyle(mod)
	cgui:addLabel("center", 1, 10, "PIN list")
	cgui:addLabel(3, 4, 3, "1.")
	cgui:addLabel(3, 6, 3, "2.")
	cgui:addLabel(3, 8, 3, "3.")
	local c1 = cgui:addTextField(7, 4, 12)
	local c2 = cgui:addTextField(7, 6, 12)
	local c3 = cgui:addTextField(7, 8, 12)
	c1.text = config.codes[1] or ""
	c2.text = config.codes[2] or ""
	c3.text = config.codes[3] or ""
	cgui:addButton(20, 11, 14, 1, "Cancel", function()
		cgui:close()
	end)
	cgui:addButton(4, 11, 14, 1, "Apply", function()
		local n1 = tonumber(c1.text)
		local n2 = tonumber(c2.text)
		local n3 = tonumber(c3.text)
		if (c1.text:len() > 0 and not n1) or (c2.text:len() > 0 and not n2) or (c3.text:len() > 0 and not n3) then
			server.messageBox(mod, "PIN must be a number.", {"OK"})
		elseif c1.text:len() > 8 or c2.text:len() > 8 or c3.text:len() > 8 then
			server.messageBox(mod, "PIN can have 8 characters at most.", {"OK"})
		else
			if not n1 and not n2 and not n3 then
				local msgg = [[
Not entering any PIN will cause
keypads to stop working. Are
you sure you want to continue?
				]]
				if server.messageBox(mod, msgg, {"Yes", "No"}) == "No" then
					return
				end
			end
			local tab = {}
			if n1 then table.insert(tab, c1.text) end
			if n2 then table.insert(tab, c2.text) end
			if n3 then table.insert(tab, c3.text) end
			config.codes = tab
			cgui:close()
		end
	end)
	cgui:run()
end

local function messageManager()
	local color = config.msg[2] or 7
	local panel = nil
	local function refreshColor()
		local hex = 0
		if bit32.band(color, 4) ~= 0 then hex = hex + bit32.lshift(255, 16) end
		if bit32.band(color, 2) ~= 0 then hex = hex + bit32.lshift(255, 8) end
		if bit32.band(color, 1) ~= 0 then hex = hex + 255 end
		panel.color = hex
	end
	local mgui = gml.create("center", "center", 40, 17)
	mgui.style = server.getStyle(mod)
	mgui:addLabel("center", 1, 16, "Message editor")
	mgui:addLabel(3, 4, 13, "Message:")
	mgui:addLabel(3, 6, 10, "Red:")
	mgui:addLabel(3, 8, 9, "Green:")
	mgui:addLabel(3, 10, 11, "Blue:")
	local msg = mgui:addTextField(17, 4, 10)
	msg.text = config.msg[1] or ""
	local b1 = mgui:addButton(15, 6, 10, 1, "yes", function(t)
		if t.status then
			color = bit32.bor(color, 4)
			t.status = false
			t.text = "no"
		else
			color = bit32.band(color, 3)
			t.status = true
			t.text = "no"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 4) == 0 then
		b1.text = "no"
		b1.status = true
	end
	local b2 = mgui:addButton(15, 8, 10, 1, "yes", function(t)
		if t.status then
			color = bit32.bor(color, 2)
			t.status = false
			t.text = "yes"
		else
			color = bit32.band(color, 5)
			t.status = true
			t.text = "no"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 2) == 0 then
		b2.text = "no"
		b2.status = false
	end
	local b3 = mgui:addButton(15, 10, 10, 1, "yes", function(t)
		if t.status then
			color = bit32.bor(color, 1)
			t.status = false
			t.text = "yes"
		else
			color = bit32.band(color, 6)
			t.status = true
			t.text = "no"
		end
		refreshColor()
		panel:draw()
		t:draw()
	end)
	if bit32.band(color, 1) == 0 then
		b2.text = "no"
		b2.status = false
	end
	panel = server.template(mod, mgui, 30, 6, 2, 5)
	panel.draw = function(t)
		t.renderTarget.setBackground(t.color)
		t.renderTarget.fill(t.gui.posX + t.posX - 1, t.gui.posY + t.posY - 1, t.width, t.height, " ")
	end
	refreshColor()
	mgui:addButton(23, 13, 14, 1, "Cancel", function()
		mgui:close()
	end)
	mgui:addButton(7, 13, 14, 1, "Apply", function()
		if msg.text:len() > 8 then
			server.messageBox(mod, "Message can have 8 characters at most.", {"OK"})
		else
			config.msg[1] = msg.text
			config.msg[2] = color
			refreshKeypads()
			mgui:close()
		end
	end)
	mgui:run()
end

local function settings()
	local sgui = gml.create("center", "center", 50, 18)
	sgui.style = server.getStyle(mod)
	sgui:addLabel("center", 1, 11, "Settings")
	sgui:addLabel(2, 4, 6, "Mode:")
	sgui:addLabel(2, 5, 44, "(Devices displayed at the left side)")
	sgui:addLabel(2, 7, 10, "Readers:")
	sgui:addLabel(4, 8, 22, "Identify players:")
	sgui:addLabel(4, 9, 20, "Locked only:")
	sgui:addLabel(2, 11, 12, "Keyboards:")
	sgui:addLabel(4, 12, 17, "Shuffle all:")
	local bmode = sgui:addButton(10, 4, 16, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "bio readers"
		else
			t.status = true
			t.text = "card readers"
		end
	end)
	bmode.text = config.oldReaders and "card readers" or "biometric readers"
	bmode.status = config.oldReaders
	local b1 = sgui:addButton(27, 8, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "no"
		else
			t.status = true
			t.text = "yes"
		end
		t:draw()
	end)
	b1.text = config.identity and "yes" or "no"
	b1.status = config.identity
	local b2 = sgui:addButton(27, 9, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "no"
		else
			t.status = true
			t.text = "yes"
		end
		t:draw()
	end)
	b2.text = config.lockedOnly and "yes" or "no"
	b2.status = config.lockedOnly
	local b3 = sgui:addButton(27, 12, 10, 1, "", function(t)
		if t.status then
			t.status = false
			t.text = "no"
		else
			t.status = true
			t.text = "yes"
		end
		t:draw()
	end)
	b3.text = config.shuffleAll and "yes" or "no"
	b3.status = config.shuffleAll
	sgui:addButton(33, 15, 14, 1, "Cancel", function() sgui:close() end)
	sgui:addButton(17, 15, 14, 1, "Apply", function()
		if config.oldReaders ~= bmode.status then
			server.mesageBox(mod, "Changes will be applied after server restart.", {"OK"})
		end
		config.oldReaders = bmode.status
		config.identity = b1.status
		config.lockedOnly = b2.status
		config.shuffleAll = b3.status
		sgui:close()
	end)
	sgui:run()
end

local function refreshTables()
	local l1 = {}
	local left = config.oldReaders and readers or biometrics
	for _, t in pairs(left) do table.insert(l1, t.name) end
	lbox:updateList(l1)
	local l2 = {}
	for _, t in pairs(keypads) do table.insert(l2, t.name) end
	rbox:updateList(l2)
end

local function prepareWindow(mode, edit, initialize)
	local rettab = {}
	if initialize then
		for a, b in pairs(initialize) do rettab[a] = b end
	end
	if type(rettab.open) ~= "table" then rettab.open = {} end
	if type(rettab.close) ~= "table" then rettab.close = {} end
	local int = {}
	local addition = (mode == "keypads") and 2 or 0

	local function choose(whenReaders, whenBiometrics, whenKeypads)
		if mode == "readers" then
			return whenReaders
		elseif mode == "biometrics" then
			return whenBiometrics
		elseif mode == "keypads" then
			return whenKeypads
		else
			error("Wrong mode: " .. mode)
		end
	end
	
	local function updateLabels()
		for i = 1, 3 do
			if rettab.open[i] then
				local a = server.actionDetails(mod, rettab.open[i].id)
				if a then
					int[i].text = a.name
				else
					int[i].text = tostring(rettab.open[i].id)
				end
			else
				int[i].text = ""
			end
			int[i]:draw()
		end
		for i = 1, 3 do
			if rettab.close[i] then
				local a = server.actionDetails(mod, rettab.close[i].id)
				if a then
					int[3 + i].text = a.name
				else
					int[3 + i].text = tostring(rettab.close[i].id)
				end
			else
				int[3 + i].text = ""
			end
			int[3 + i]:draw()
		end
	end
	local function chooseAction(enable, num)
		local text = enable and int[num].text or int[3 + num].text
		local tab = enable and rettab.open or rettab.close
		if text:len() > 0 then
			local ret = server.actionDialog(mod, nil, nil, tab[num])
			tab[num] = ret
			updateLabels()
		else
			local ret = server.actionDialog(mod)
			if ret then
				tab[num] = ret
				updateLabels()
			end
		end
	end
	
	local sgui = gml.create("center", "center", 65, 23 + addition)
	sgui.style = server.getStyle(mod)
	local text = nil
	if edit then
		text = choose("Edit card reader", "Edit biometric reader", "Edit keypad")
	else
		text = choose("New card reader", "New biometric reader", "New kaypad")
	end
	local title = sgui:addLabel("center", 1, text:len() + 2, text)
	
	sgui:addLabel(2, 4, 10, "Address:")
	sgui:addLabel(2, 6, 7, "Name:")
	sgui:addLabel(2, 8, 13, "Delay:")
	sgui:addLabel(2, 10, 8, "Status:")
	sgui:addLabel(2, 13 + addition, 19, "Enable actions:")
	sgui:addLabel(30, 13 + addition, 20, "Disable actions:")
	
	if mode == "keys" then
		sgui:addLabel(2, 12, 11, "Shuffle:")
		local tmp = sgui:addButton(15, 12, 10, 1, "", function(t)
			if rettab.shuffle then
				rettab.shuffle = false
				t.text = "no"
			else
				rettab.shuffle = true
				t.text = "yes"
			end
			t:draw()
		end)
		tmp.text = rettab.shuffle and "yes" or "no"
	end
	for i = 1, 3 do
		local tt = sgui:addLabel(4, 14 + addition + i, 3, tostring(i) .. ".")
		int[i] = sgui:addLabel(8, 14 + addition + i, 20, "")
		local function exec()
			chooseAction(true, i)
		end
		tt.onDoubleClick = exec
		int[i].onDoubleClick = exec
	end
	for i = 1, 3 do
		local tt = sgui:addLabel(32, 14 + addition + i, 3, tostring(i) .. ".")
		int[3 + i] = sgui:addLabel(36, 14 + addition + i, 20, "")
		local function exec()
			chooseAction(false, i)
		end
		tt.onDoubleClick = exec
		int[3 + i].onDoubleClick = exec
	end
	
	local tmp = sgui:addLabel(15, 4, 38, "")
	tmp.onDoubleClick = function(t)
		local eventName = choose("os_magreader", "os_biometric", "os_keypad")
		local a = server.componentDialog(mod, eventName)
		if a then
			local found = false
			local tab = choose(readers, biometrics, keypads)
			for _, t in pairs(tab) do
				if a == t.address then
					found = true
					break
				end
			end
			if not found then
				t.text = a
				rettab.address = a
				t:draw()
			else
				server.messageBox(mod, "A device with the same address has been already added.", {"OK"})
			end
		end
	end
	tmp.text = rettab.address or ""
	
	int[7] = sgui:addTextField(15, 6, 20)
	int[8] = sgui:addTextField(15, 8, 10)
	int[7].text = rettab.name or ""
	int[8].text = tostring(rettab.delay or 3)
	local tmp = sgui:addButton(15, 10, 14, 1, "", function(t)
		if rettab.disabled then
			rettab.disabled = false
			t.text = "enabled"
		else
			rettab.disabled = true
			t.text = "disabled"
		end
		t:draw()
	end)
	tmp.text = rettab.disabled and "disabled" or "enabled"
	
	sgui:addButton(47, 20 + addition, 14, 1, "Cancel", function()
		sgui.ret = initialize
		sgui:close()
	end)
	sgui:addButton(31, 20 + addition, 14, 1, "Apply", function()
		local name = int[7].text
		local delay = tonumber(int[8].text)
		if name:len() == 0 then
			server.messageBox(mod, "Enter the device name.", {"OK"})
		elseif not rettab.address then
			server.messageBox(mod, "Choose the device address.", {"OK"})
		elseif not delay or delay > 20 or delay < 1 then
			server.messageBox(mod, "Delay must be a number between 1 and 20.", {"OK"})
		else
			rettab.name = name:sub(1, 20)
			rettab.delay = delay
			sgui.ret = rettab
			sgui:close()
		end
	end)
	
	updateLabels()
	return sgui
end

local function addReader()
	if #readers < 10 then
		local sgui = prepareWindow("readers", false, nil)
		sgui:run()
		if sgui.ret then
			table.insert(readers, sgui.ret)
			refreshTables()
		end
	else
		server.messageBox(mod, "Card readers limit has been reached.", {"OK"})
	end
end

local function addBiometric()
	if #biometrics < 10 then
		local sgui = prepareWindow("biometrics", false, nil)
		sgui:run()
		if sgui.ret then
			table.insert(biometrics, sgui.ret)
			refreshTables()
		end
	else
		server.messageBox(mod, "Biometric readers limit has been reached.", {"OK"})
	end
end

local function addKeypad()
	if #keypads < 10 then
		local sgui = prepareWindow("keypads", false, nil)
		sgui:run()
		if sgui.ret then
			table.insert(keypads, sgui.ret)
			refreshTables()
			refreshKeypads()
		end
	else
		server.messageBox(mod, "Keypad limit has been reached.", {"OK"})
	end
end

local function getDevice(list, name)
	for i, t in pairs(list) do
		if t.name == name then return t, i end
	end
	return nil
end

local function modifyReader()
	local sel = lbox:getSelected()
	if sel then
		local dev, index = getDevice(readers, sel)
		if dev then
			local sgui = prepareWindow("readers", true, dev)
			sgui:run()
			if sgui.ret then
				readers[index] = sgui.ret
				refreshTables()
			end
		end
	end
end

local function modifyBiometric()
	local sel = lbox:getSelected()
	if sel then
		local dev, index = getDevice(biometrics, sel)
		if dev then
			local sgui = prepareWindow("biometrics", true, dev)
			sgui:run()
			if sgui.ret then
				biometrics[index] = sgui.ret
				refreshTables()
			end
		end
	end
end

local function modifyKeypad()
	local sel = rbox:getSelected()
	if sel then
		local dev, index = getDevice(keypads, sel)
		if dev then
			local sgui = prepareWindow("keypads", true, dev)
			sgui:run()
			if sgui.ret then
				keypads[index] = sgui.ret
				refreshTables()
				refreshKeypads()
			end
		end
	end
end


local actions = {
	[1] = {
		name = "lockMag",
		type = "AUTH",
		desc = "Locks magnetic card readers",
		exec = function()
			config.readers = false
			if config.oldReaders then
				element[1].text = "disabled"
				element[1]:draw()
			end
		end
	},
	[2] = {
		name = "unlockMag",
		type = "AUTH",
		desc = "Unlocks magnetic card readers",
		exec = function()
			config.readers = true
			if config.oldReaders then
				element[1].text = "enabled"
				element[1]:draw()
			end
		end
	},
	[3] = {
		name = "lockKeypad",
		type = "AUTH",
		desc = "Locks keypads",
		exec = function()
			config.keypads = false
			element[2].text = "disabled"
			element[2]:draw()
			refreshKeypads()
		end
	},
	[4] = {
		name = "unlockKeypad",
		type = "AUTH",
		desc = "Unlocks keypads",
		exec = function()
			config.keypads = true
			element[2].text = "enabled"
			element[2]:draw()
			refreshKeypads()
		end
	},
	[5] = {
		name = "lockBio",
		type = "AUTH",
		desc = "Locks biometric readers",
		exec = function()
			config.biometrics = false
			if not config.oldReaders then
				element[1].text = "disabled"
				element[1]:draw()
			end
		end
	},
	[6] = {
		name = "unlockBio",
		type = "AUTH",
		desc = "Unlocks biometric readers",
		exec = function()
			config.biometrics = true
			if not config.oldReaders then
				element[1].text = "enabled"
				element[1]:draw()
			end
		end
	},
}

mod.name = "auth"
mod.version = version
mod.id = 27
mod.apiLevel = 2
mod.shape = "normal"
mod.actions = actions

mod.setUI = function(window)
	window:addLabel("center", 1, 11, ">> AUTH <<")
	window:addLabel(3, 3, 12, config.oldReaders and "MAG Readers:" or "BIO Readers:")
	window:addLabel(36, 3, 12, "Keypads:")
	
	lbox = window:addListBox(3, 5, 30, 10, {})
	rbox = window:addListBox(36, 5, 30, 10, {})
	lbox.onDoubleClick = config.oldReaders and modifyReader or modifyBiometric
	rbox.onDoubleClick = modifyKeypad
	refreshTables()
	
	element[1] = window:addButton(18, 3, 14, 1, "", function(t)
		local value = config.oldReaders and config.readers or config.biometrics
		if value then
			t.text = "disabled"
		else
			t.text = "enabled"
		end
		if config.oldReaders then
			config.readers = not value
		else
			config.biometrics = not value
		end
		t:draw()
	end)
	local value = config.oldReaders and config.readers or config.biometrics
	element[1].text = value and "enabled" or "disabled"
	element[2] = window:addButton(52, 3, 14, 1, "", function(t)
		if config.keypads then
			config.keypads = false
			t.text = "disabled"
		else
			config.keypads = true
			t.text = "enabled"
		end
		refreshKeypads()
		t:draw()
	end)
	element[2].text = config.keypads and "enabled" or "disabled"
	window:addButton(3, 16, 14, 1, "Add", config.oldReaders and addReader or addBiometric)
	window:addButton(19, 16, 14, 1, "Remove", function()
		local sel = lbox:getSelected()
		if sel then
			local tab = config.oldReaders and readers or biometrics
			for i, t in pairs(tab) do
				if t.name == sel and server.messageBox(mod, "Are you sure you want to remove selected element?", {"Yes", "No"}) == "Yes" then
					table.remove(tab, i)
					refreshTables()
				end
			end
		end
	end)
	window:addButton(36, 16, 14, 1, "Add", addKeypad)
	window:addButton(52, 16, 14, 1, "Remove", function()
		local sel = rbox:getSelected()
		if sel then
			for i, t in pairs(keypads) do
				if t.name == sel and server.messageBox(mod, "Are you sure you want to remove selected element?", {"Yes", "No"}) == "Yes" then
					table.remove(keypads, i)
					refreshTables()
				end
			end
		end
	end)
	window:addButton(3, 18, 14, 1, config.oldReaders and "Cards" or "Users", config.oldReaders and cardManager or userManager)
	window:addButton(36, 18, 14, 1, "PINs", codeManager)
	window:addButton(52, 18, 14, 1, "Message", messageManager)
	window:addButton(19, 18, 14, 1, "Settings", settings)
end

mod.start = function(core)
	server = core
	config = core.loadConfig(mod)
	loadInternals()
	
	if type(config.oldReaders) ~= "boolean" then
		config.oldReaders = false
	end
	if type(config.readers) ~= "boolean" then
		config.readers = true
	end
	if type(config.keypads) ~= "boolean" then
		config.keypads = true
	end
	if not config.msg then
		config.msg = {}
		table.insert(config.msg, "ready")
		table.insert(config.msg, 3)
	end
	if type(config.lockedOnly) ~= "boolean" then config.lockedOnly = true end
	if not config.codes then config.codes = {} end
	if not config.msg[1] or config.msg[1]:len() > 8 then config.msg[1] = config.msg[1]:sub(1, 8) end
	if not config.msg[2] or config.msg[2] > 7 or config.msg[2] < 0 then config.msg[2] = 3 end
	
	if core.oldReaders then
		core.registerEvent(mod, "magData") --magdata, devaddr, player, data, id, locked, side
	else
		core.registerEvent(mod, "bioReader") --bioreader, devaddr, playeruuid
	end
	core.registerEvent(mod, "keypad") --keypad, devaddr, keyid, keychar
	refreshKeypads()
end

mod.stop = function(core)
	core.saveConfig(mod, config)
	saveInternals()
	
	local comp = server.getComponentList(mod, "os_keypad")
	for _, t in pairs(comp) do
		local proxy = component.proxy(t.address)
		if proxy then
			proxy.setDisplay("", 7)
			for i = 1, 9 do
				proxy.setKey(i, tostring(i))
			end
			proxy.setKey(11, "0")
		end
	end
end

mod.pullEvent = function(...)
	local e = {...}
	if e[1] == "bioReader" then
		if not config.biometrics then return end
		if internalBioEvent ~= nil then
			internalBioEvent(e)
		end
		local user = false
		for _, u in pairs(users) do
			if u.uuid == e[3] then
				user = u
				break
			end
		end
		if not user then return end
		local bio = nil
		for _, t in pairs(biometrics) do
			if t.address == e[2] then
				bio = t
				break
			end
		end
		if bio and not bio.disabled then
			local function exec(tab)
				for _, t in pairs(tab) do
					server.call(mod, t.id, t.p1, t.p2, true)
				end
			end
			exec(bio.open)
			server.call(mod, 5201, "Player " .. user.name .. " was authorized in BIO reader \"" .. bio.name .. "\".", "AUTH", true)
			event.timer(bio.delay, function()
				exec(bio.close)
			end)
		end
	elseif e[1] == "magData" then
		if not config.readers then return end
		local card = nil
		for _, t in pairs(cards) do
			if t.id == e[5] then
				card = t
				break
			end
		end
		if card then
			local dev = nil
			for _, t in pairs(readers) do
				if t.address == e[2] then
					dev = t
					break
				end
			end
			if dev then
				if dev.disabled then return
				elseif config.lockedOnly and not e[6] then return
				elseif config.identity then
					if data.inflate(e[4]) ~= e[3] then return end
				end
				local function exec(tab)
					for _, t in pairs(tab) do
						server.call(mod, t.id, t.p1, t.p2, true)
					end
				end
				exec(dev.open)
				server.call(mod, 5201, "Player " .. e[3] .. " used a MAG card in reader " .. dev.name .. ".", "AUTH", true)
				event.timer(dev.delay, function()
					exec(dev.close)
				end)
			end
		end
	elseif e[1] == "keypad" then
		--keypad, devaddr, keyid, keychar
		if not config.keypads then return end
		local dev = nil
		for _, t in pairs(keypads) do
			if t.address == e[2] then
				dev = t
				break
			end
		end
		if dev and not dev.disabled then
			local proxy = component.proxy(dev.address)
			if not proxy then return end
			if e[3] < 10 or e[3] == 11 then
				if inputs[e[2]] then
					if inputs[e[2]]:len() < 8 then
						inputs[e[2]] = inputs[e[2]] .. e[4]
						proxy.setDisplay(string.rep("*", inputs[e[2]]:len()), 7)
					end
				else
					inputs[e[2]] = e[4]
					proxy.setDisplay("*", 7)
				end
			elseif e[3] == 10 then
				if inputs[e[2]]:len() > 1 then
					inputs[e[2]] = inputs[e[2]]:sub(1, #inputs[e[2]] - 1)
					proxy.setDisplay(string.rep("*", inputs[e[2]]:len()))
				else
					inputs[e[2]] = nil
					proxy.setDisplay(config.msg[1], config.msg[2])
				end
			elseif e[3] == 12 then
				local code = inputs[e[2]]
				if code then
					local valid = false
					for _, s in pairs(config.codes) do
						if code == s then
							valid = true
							break
						end
					end
					if valid then
						local function exec(tab)
							for _, t in pairs(tab) do
								server.call(mod, t.id, t.p1, t.p2, true)
							end
						end
						dev.disabled = true
						proxy.setDisplay(texts.open[1], texts.open[2])
						exec(dev.open)
						inputs[e[2]] = nil
						server.call(mod, 5201, "Keypad " .. dev.name .. " was used.", "AUTH", true)
						event.timer(dev.delay, function()
							proxy.setDisplay(texts.closed[1], texts.closed[2])
							exec(dev.close)
						end)
						event.timer(dev.delay + 3, function()
							dev.disabled = false
							proxy.setDisplay(config.msg[1], config.msg[2])
							if dev.shuffle then
								local sh = getShuffled()
								for i = 1, 9 do
									proxy.setKey(i, sh[i], 7)
								end
								proxy.setKey(11, sh[10], 7)
							end
						end)
					else
						dev.disabled = true
						inputs[e[2]] = nil
						proxy.setDisplay(texts.wrong[1], texts.wrong[2])
						event.timer(2, function()
							dev.disabled = false
							proxy.setDisplay(config.msg[1], config.msg[2])
							if dev.shuffle then
								local sh = getShuffled()
								for i = 1, 9 do
									proxy.setKey(i, sh[i], 7)
								end
								proxy.setKey(11, sh[10], 7)
							end
						end)
					end
				end
			end
		end
	end
end

return mod