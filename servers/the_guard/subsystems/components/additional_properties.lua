-- ################################################
-- # The Guard  components subsystem / add. props #
-- #                                              #
-- #  06.2022                by: Dominik Rzepka   #
-- ################################################

--[[
    ## Description ##
    Wrapper for additional properties table. Primarily used for
    encapsulating validation logic.
]]

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

local config = require("subsystems/components/config")

-- Validator signature:
-- parameter: string input
-- returns:
-- 1. true and processed input, if necessary (i.e. when converting string to number)
-- 2. false and validation message
local validators = {
    number = function (input)
        local num = tonumber(input)
        if num then
            return true, num
        else
            return false, "value is not a number"
        end
    end,
    string = function (input) return true, input end
}

local AdditionalProperties = {}

function AdditionalProperties.forComponent(component)
    local propsConfig = config.additionalProperties[component.type] or {}

    if not component.properties then
        error("Component properties must be set")
    end

    local props = {
        config = propsConfig,
        count = propsConfig.properties and #propsConfig.properties or 0,
        properties = component.properties
    }
    setmetatable(props, AdditionalProperties)
    AdditionalProperties.__index = AdditionalProperties

    props.properties = component.properties or {}
    return props
end

--[[
    Returns short description of all properties.
]]
function AdditionalProperties.digest(component)
    local propsConfig = config.additionalProperties[component.type]
    if not propsConfig then return "" end

    local fun = propsConfig.digest
    if fun then return fun(component.properties) else return "" end
end

--[[
    Return format:
    {
        index = 1,
        displayName = "name",
        value = "string value or empty string"
    }
]]
function AdditionalProperties:iterator()
    local i = 0
    return function ()
        i = i + 1
        if i > #self.config.properties then return nil end

        local propConfig = self.config.properties[i]
        local value = self.properties[propConfig.name] or ""
        return {
            index = i,
            displayName = propConfig.displayName,
            value = value
        }
    end
end

--[[
    Return format:
    1. true - properties have been set
    2. false, error list - when there are validation errors
]]
function AdditionalProperties:set(values)
    local props = self.config.properties
    if #values ~= #props then
        error("Number of passed values doens't match number of configured properties.")
    end

    local errors = {}
    local correctValues = {}

    for i = 1, #values do
        local prop = props[i]
        local value = values[i]
        local validator = validators[prop.type]

        if prop.required and value:len() == 0 then
            table.insert(errors, prop.displayName .. ": property is required")
        elseif validator then
            local isValid, data = validator(value)
            if isValid then
                correctValues[prop.name] = data or value
            else
                table.insert(errors, prop.displayName .. ": " .. data)
            end
        else
            correctValues[prop.name] = value
        end
    end

    if #errors > 0 then return false, errors end

    for name, value in pairs(correctValues) do
        self.properties[name] = value
    end

    return true
end

return AdditionalProperties
