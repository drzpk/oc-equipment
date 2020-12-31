-- ################################################
-- #       The Guard  logging  subsystem          #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local component = require("component")

local buffer = {}

local formats = {
    NORMAL = function (time, level, title, text) -- 12:04 DEBUG: title/text
		return time .. " " .. levels[level].title .. ": " .. title .. "/" .. text
	end,
	SHORT = function (time, level, title, text) -- 12:04 D: title/text
		return time .. " " .. string.sub(levels[level].title, 1, 1) .. ": " .. title .. "/" .. text
	end,
	SQUARE = function (time, level, title, text) -- 12:04[D] >title<  text
		return time .. "[" .. string.sub(levels[level].title, 1, 1) .. "] >" .. title .. "<  " .. text
	end,
	PRETTY = function (time, level, title, text) -- 12:04 /D >> title | text
		return time .. " /" .. string.sub(levels[level].title, 1, 1) .. " >> " .. title .. " | " .. text
	end
}


local logging = {}

logging.levels = {
    SEVERE = {
        color = 0xff00cc
    },
    ERROR = {
        color = 0xff0000
    },
    WARN = {
        color = 0xffff00
    },
    INFO = {
        color = 0x000000
    },
    DEBUG = {
        color = 0x00ff00
    }
}

function logging.initialize()
    return true
end

function logging:log(level, source, message, ...)

end

function logging:consoleLog(level, source, message, ...)
    local prev = nil
	if level.color then
		prev = component.gpu.setForeground(level.color)
	end
	print(self:log(level, source, message, ...))
	if level.color then
		component.gpu.setForeground(prev)
	end
end

return logging