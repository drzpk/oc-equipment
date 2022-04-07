-- ################################################
-- #    The Guard  components subsystem / hal     #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

--[[
    ## Description ##
    This file handles low-level access to components.
]]

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["subsystems/components/config"] = nil

local component = require("component")
local config = require("subsystems/components/config")

local Hal = {
    components = nil -- reference to the modules subsystem
}

function Hal.getUnregisteredComponents()
    local result = {}
    for addr, _type in component.list() do
        local canRegister = not Hal.components:isComponentRegistered(addr) and config.isComponentVisible(_type)

        if canRegister then
            local entry = {
                type = _type,
                address = addr
            }
            
            result[addr] = entry
        end
    end

    return result
end

function Hal.isConnected(address)
    return component.proxy(address) ~= nil
end

return Hal
