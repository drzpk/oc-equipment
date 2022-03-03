-- ##########################################
-- #		  logging test module			#
-- #										#
-- #  08.2020			by: Dominik Rzepka  #
-- ##########################################

local version = "1.0"
local args = {...}

local mod = {
    name = "test_logging",
    version = version,
    apiLevel = 6,
    actions = {}
}

local function _logInfoMessage()
    mod.logger:info("test_logging", "this is a test message")
end

function mod.setUI(window)
    window:addLabel("center", 1, 26, ">> logging test module <<")
    window:addButton(2, 3, 24, 1, "test message", _logInfoMessage)
end

function mod.start(api)
    mod.logger = api.logger()
end

function mod.stop(api)

end

function mod.pullEvent(event)

end

return mod