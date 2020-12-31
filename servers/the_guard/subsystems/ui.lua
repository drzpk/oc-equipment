-- ################################################
-- #          The Guard  ui subsystem             #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end


local gml = require("gml")


local ui = {}

function ui:initialize()
    return true
end

function ui:messageBox(message, buttons)
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
    gui.style = self.context.guiStyle
    
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

return ui
