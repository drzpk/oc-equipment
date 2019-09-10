-- ###############################################
-- #            Support Library v1               #
-- #                                             #
-- #   01.2019                   by: IlynPayne   #
-- ###############################################

--[[
    ## Description ##
    This library provides various utilities

    ## Context ##
    Some of functions in this library use optional context object.
    Context allows to detect whether application is running - otherwise
    these functions won't work. Context is any object that provides
    field 'running' (such as GML library).
]]


local version = "1.2"
local startArgs = {...}

if startArgs[1] == "version_check" then return version end

-- Libraries
local event = require("event")

local lib = {}

--[[
Specialized version of checkArg for checking number ranges.
    @pos - position of argument
    @value - argument value
    @minValue - minimum valid value
    @maxValue - maximum valid value
    @excluside - whether given min/max constraints should be treated as exclusive ranges (false by default)
]]
lib.checkNumber = function (pos, value, minValue, maxValue, exclusive)
--bad argument #n (type1 expected, got type(value))
    checkArg(pos, value, "number")
    if (exclusive and value < minValue) or (not exclusive and value <= minValue) then
        error("bad argument #" .. tonumber(pos) .. " (minimum valid value is " .. tostring(minValue) .. ")")
    elseif (exclusive and value > maxValue) or (not exclusive and value >= maxValue) then
        error("bad argument #" .. tonumber(pos) .. " (maximum valid value is " .. tostring(maxValue) .. ")")
    end
end

--[[
Creates context-aware timer instance
    @callback - function that will be called on each timer tick.
    @context - the context object (optional)
    RET: timer instance
]]
lib.timer = function (callback, context)
    local function tickFunction(self)
        if self.count <= 0 or (self.context and not self.context.running) then
            self:stop()
        else
            self.count = self.count - 1
            self.callback(self)
        end
    end
    return {
        --[[
        Starts the timer
            @interval - timer interval
            @count - how many times timer should be run
            @force - stops previously running timer
            RET: whether timer has been started (if not, check if is already running
                or whether context is running).
        ]]
        start = function (self, interval, count, force)
            lib.checkNumber(1, interval, 0, math.huge, true)
            lib.checkNumber(2, count, 0, math.huge, true)

            if self.running then
                if force then
                    self:stop()
                else
                    return false
                end
            end

            self.interval = interval
            self.count = count
            self.timerId = event.timer(self.interval, function () tickFunction(self) end, math.huge)
            return true
        end,
        --[[
        Stops the timer
            @silent - if set to true, onStop callback won't be invoked
        ]]
        stop = function (self, silent)
            if self.timerId then
                event.cancel(self.timerId)
            end
            self.running = false
            if not silent and type(self.onStop) == "function" then
                self.onStop(self)
            end
        end,
        --[[
        Function to call when the timer is stopped
        ]]
        onStop = nil,
        timerId = nil,
        running = false,
        callback = callback,
        context = context
    }
end

return lib