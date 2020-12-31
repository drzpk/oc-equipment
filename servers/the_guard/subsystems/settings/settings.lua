-- ################################################
-- #        The Guard  settings subsystem         #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

--[[
    ## Description ##
        This subsystem manages all settings of the guard
        and provides convenient interface to edit them.
]]

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end


package.loaded.gml = nil
package.loaded["subsystems/settings/settings_editor"] = nil

local component = require("component")
local fs = require("filesystem")
local gml = require("gml")
local serial = require("serialization")
---
local SettingsEditor = require("subsystems/settings/settings_editor")

local data = nil
local masterPassword = nil

local ROOT_CONFIG_DIR = "/etc/the_guard"
local MODULES_CONFIG_SUBDIR = "modules"


-- Internal functions

local function loadModuleConfigContent(module, settingsName)
    if not settingsName:match("^[%a_]+$") then
        error("Settings name can contain only letters and underscore")
    end

    local configDirectoryName = fs.concat(ROOT_CONFIG_DIR, MODULES_CONFIG_SUBDIR, module.name)
    if not fs.isDirectory(configDirectoryName) then
        fs.makeDirectory(configDirectoryName)
    end

    local configFileName = fs.concat(configDirectoryName, settingsName .. ".conf")
    local content = nil

    if fs.exists(configFileName) then
        local handle = io.open(configFileName, "r")
        local raw = handle:read("*a")
        handle:close()

        local status, obj = pcall(serial.unserialize, raw)
        if not status then
            io.stderr:write("Failed to unserialize contents of file " .. configFileName .. "\n")
            error(obj)
        end

        content = obj
    else
        content = {}
    end

    return content
end

local function saveModuleConfigContent(module, settingsName, content)
    local serialized = serial.serialize(content)
    local configFileName = fs.concat(ROOT_CONFIG_DIR, MODULES_CONFIG_SUBDIR, module.name, settingsName .. ".conf")
    local handle = io.open(configFileName, "w")
    handle:write(serialized)
    handle:close()
end

-- Subsystem API

local settings = {}

function settings:initialize()
    if not component.data or not component.data.encrypt then
        io.stderr:write("Data component of tier 2 or 3 is required")
        return false
    end
    data = component.data

    return true
end

function settings:createModuleSettingsEditor(module, settingsName)
    local callback = function (result)
        if result.updated then
            saveModuleConfigContent(module, settingsName, result.properties)
        end
    end

    local content = loadModuleConfigContent(module, settingsName)
    return SettingsEditor:new(self.context.api, content, callback)
end

function settings:requiresMasterPassword()
    -- todo: need to rethink settings encryption 
    return false
end

function settings:loadSystemSettings(password)
    
end

function settings:loadModuleSettings()

end

return settings