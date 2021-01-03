-- ################################################
-- #    The Guard  settings subsystem/manager     #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

local SettingsManager = {
    _type = "SettingsManager"
}

function SettingsManager:new(settings)
    local obj = {
        properties = {},
        values = {}
    }

    setmetatable(obj, self)
    self.__index = self

    obj:_loadExistingProperties(settings)

    return obj
end

function SettingsManager:defineStringProperty(key, defaultValue)
    self:_defineProperty(key, "string", defaultValue, nil)
end

function SettingsManager:defineNumberProperty(key, defaultValue)
    self:_defineProperty(key, "number", defaultValue, function (input) return tonumber(input) end)
end

function SettingsManager:defineBooleanProperty(key, defaultValue)
    self:_defineProperty(key, "boolean", defaultValue, function (input) return input and true or false end)
end

function SettingsManager:defineRawProperty(key, defaultValue)
    self:_defineProperty(key, nil, defaultValue, nil)
end

function SettingsManager:getValue(key)
    local property = self.properties[key]
    if not property then
        error("Property '" .. key "' wasn't found")
    end

    local value = self.values[property.key]
    if type(value) == "nil" then value = property.default end
    return value
end

--[[
    Sets property value and converts it to a proper type if necessary.
]]
function SettingsManager:setValue(key, value)
    local property = self.properties[key]
    if not property then
        error("Property '" .. key "' wasn't found")
    end

    local targetValue = value
    if value and property.type and type(value) ~= property.type then
        if property.converter then
            local status, result = pcall(property.converter, value)
            if status then
                targetValue = result
            else
                error("Conversion failed for key '" .. key .. "' and type '" .. property.type .. "': " .. result)
            end
        else
            error("No converter found for key '" .. key .. "' and type '" .. property.type .. "'")
        end
    end

    self.values[property.key] = targetValue
end

--[[
    Returns updated settings.
]]
function SettingsManager:getSettings()
    local filtered = {}
    for _, property in pairs(self.properties) do
        local value = self.values[property.key]
        if type(value) == "nil" then value = property.defaultValue end
        filtered[property.key] = value
    end

    return filtered
end

function SettingsManager:_loadExistingProperties(obj)
    for name, value in pairs(obj) do
        self.values[name] = value
    end
end


function SettingsManager:_defineProperty(key, propertyType, defaultValue, fromStringConverter)
    -- no default value means that property is "nillable"
    if defaultValue and propertyType and type(defaultValue) ~= propertyType then
        error("Wrong default value for property '" .. key .. "': required '" .. propertyType .. "' type but got '" .. type(defaultValue) .. "'")
    end

    local property = {
        key = key,
        type = propertyType,
        default = defaultValue,
        converter = fromStringConverter
    }

    self.properties[key] = property
end

return SettingsManager