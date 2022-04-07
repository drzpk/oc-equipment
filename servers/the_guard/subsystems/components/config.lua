-- ################################################
-- #  The Guard  components subsystem / config    #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end


local Config = {
    hiddenComponents = { -- List of components that can't be registered
        "screen",
        "eeprom",
        "filesystem",
        "data",
        "modem",
        "keyboard",
        "gpu",
        "computer"
    }
}

function Config.isComponentVisible(_type)
    for _, n in pairs(Config.hiddenComponents) do
        if n == _type then return false end
    end
    return true
end

return Config
