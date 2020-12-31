-- ################################################
-- #    The Guard  settings subsystem/editor      #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded.gml = nil
package.loaded["subsystems/settings/settings_manager"] = nil
package.loaded["subsystems/settings/constraint_validator"] = nil

local gml = require("gml")
---
local SettingsManager = require("subsystems/settings/settings_manager")
local ConstraintValidator = require("subsystems/settings/constraint_validator")


local SettingsEditor = {}

local function checkArg(number, requiredType, value, allowNil)
    if type(value) == "nil" and allowNil then return end

    if type(value) ~= requiredType then
        error("Wrong argument " .. tostring(number) .. ": required '" .. requiredType .. "' type but got '" .. type(value) .. "'")
    end
end

--[[
    Creates new settings editor
    @param api - the guard api
    @param settingsObject - settings object
    @param editorCloseCallback - function to call when editor is closed. First parameter is set to the same
        object as SettingsEditor:show function's return value and is called before it.
]]
function SettingsEditor:new(api, settingsObject, editorCloseCallback)
    local manager = SettingsManager:new(settingsObject)
    local obj = {
        api = api,
        properties = {},
        buttons = {},
        manager = manager,
        closeCallback = editorCloseCallback,
        originalSettingsObject = settingsObject
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

--[[
    Available constraints:
    required, minLength, maxLength
]]
function SettingsEditor:addStringProperty(key, name, defaultValue, constraints)
    checkArg(3, "string", defaultValue, true)

    local property = {
        kind = "property",
        key = key,
        name = name,
        type = "string",
        default = defaultValue,
        valueWidth = 10,
        validator = ConstraintValidator:createValidator(constraints, {"required", "minLength", "maxLength"})
    }

    table.insert(self.properties, property)
    self.manager:defineStringProperty(key, defaultValue)
end

--[[
    Available constraints:
    required, minValue, maxValue
]]
function SettingsEditor:addIntegerProperty(key, name, defaultValue, constraints)
    checkArg(3, "number", defaultValue, true)

    local property = {
        kind = "property",
        key = key,
        name = name,
        type = "integer",
        default = defaultValue,
        valueWidth = 8,
        validator = ConstraintValidator:createValidator(constraints, {"required", "minValue", "maxValue"})
    }

    table.insert(self.properties, property)
    self.manager:defineNumberProperty(key, defaultValue)
end


function SettingsEditor:addBooleanProperty(key, name, defaultValue)
    checkArg(3, "boolean", defaultValue, true)
        
    local property = {
        kind = "property",
        key = key,
        name = name,
        type = "boolean",
        default = defaultValue,
        valueWidth = 8
    }

    table.insert(self.properties, property)
    self.manager:defineBooleanProperty(key, defaultValue)
end

function SettingsEditor:addPropertySeparator()
    local property = {
        kind = "separator"
    }
    table.insert(self.properties, property)
end

function SettingsEditor:addButton(name, handler)
    local button = {
        kind = "button",
        name = name,
        handler = handler
    }
    table.insert(self.buttons, button)
end

function SettingsEditor:addButtonSeparator()
    local button = {
        kind = "separator"
    }
    table.insert(self.buttons, button)
end

--[[
    Displays the editor
    @returns table: {
        updated = false, -- whether properties were updated (user clicked OK button)
        properties = {} -- properties table (with current values)
    }
]]
function SettingsEditor:show(title)
    if #self.properties == 0 then error("No properties were defined") end

    local verticalPadding = 1
    local horizontalPadding = 1
    local nameValueDistance = 2
    local valueButtonDistance = 4
    local minWidth = 28

    local nameWidth = self:_getMaxPropertyNameWidth()
    local valueWidth = self:_getMaxPropertyValueWidth()
    local buttonWidth = self:_getButtonsWidth()
    local totalWidth = math.max(minWidth, nameWidth + nameValueDistance + 1 + valueWidth + horizontalPadding * 2 + valueButtonDistance + buttonWidth + 2)
    local totalHeight = math.max(#self.properties, #self.buttons) + 4 + 2
    local valueX = horizontalPadding + nameWidth + nameValueDistance + 1
    local buttonX = valueX + valueWidth + valueButtonDistance

    local gui = gml.create("center", "center", totalWidth, totalHeight)
    gui:addLabel("center", 1, title:len(), title)

    local currentY = 3
    for _, property in pairs(self.properties) do
        if property.kind == "property" then
            self:_createPropertyGUI(gui, property, horizontalPadding + 1, valueX, currentY)
        end
        currentY = currentY + 1
    end

    currentY = 3
    for _, button in pairs(self.buttons) do
        if button.kind == "button" then
            self:_createButtonGUI(gui, button, buttonX, currentY, buttonWidth)
        end
        currentY = currentY + 1
    end

    local notSelf = self
    gui:addButton(totalWidth - 28, totalHeight, 10, 1, "Apply", function ()
        if notSelf:_validateProperties() then
            notSelf.saveProperties = true
            gui:close()
        end
    end)
    gui:addButton(totalWidth - 13, totalHeight, 10, 1, "Cancel", function () gui:close() end)

    gui:run()

    local result = self:_getResult()
    if self.closeCallback then self.closeCallback(result) end
    return result
end

function SettingsEditor:_getMaxPropertyNameWidth()
    local max = 0
    for _, property in pairs(self.properties) do
        if property.kind == "property" then
            max = math.max(property.name:len(), max)
        end
    end
    return max
end

function SettingsEditor:_getMaxPropertyValueWidth()
    local max = 0
    for _, property in pairs(self.properties) do
        if property.kind == "property" then
            max = math.max(property.valueWidth, max)
        end
    end
    return max
end

function SettingsEditor:_getButtonsWidth()
    local max = 0
    for _, button in pairs(self.buttons) do
        if button.kind == "button" then
            max = math.max(button.name:len(), max)
        end
    end

    local buttonWidthLimit = 16
    local buttonPadding = 2
    return math.min(max + buttonPadding * 2, buttonWidthLimit)
end

function SettingsEditor:_createPropertyGUI(gui, property, labelX, valueX, y)
    gui:addLabel(labelX, y, property.name:len(), property.name)

    local api = self.api
    local manager = self.manager
    if property.type == "string" then
        property.guiElement = gui:addTextField(valueX, y, property.valueWidth)
        property.guiElement.text = manager:getValue(property.key) or ""
        property.guiElement.propertyKey = property.key
        property.guiElement.lostFocus = function (e)
            manager:setValue(e.propertyKey, e.text)
        end

    elseif property.type == "integer" then
        property.guiElement = gui:addTextField(valueX, y, property.valueWidth)
        property.guiElement.text = tostring(manager:getValue(property.key) or "")
        property.guiElement.propertyKey = property.key
        property.guiElement.previousText = property.guiElement.text
        property.guiElement.lostFocus = function(e)
            local status = pcall(function () manager:setValue(e.propertyKey, e.text) end)
            if not status then
                api.messageBox(nil, "Invalid value format.")
                e.text = e.previousText
                e:draw()
            else
                manager:setValue(e.propertyKey, e.text)
                e.previousText = e.text
            end
        end

    elseif property.type == "boolean" then
        local value = manager:getValue(property.key)
        property.guiElement = gui:addButton(valueX, y, property.valueWidth, 1, value and "yes" or "no", function (e)
            if e.text == "yes" then
                manager:setValue(e.propertyKey, false)
                e.text = "no"
            else
                manager:setValue(e.propertyKey, true)
                e.text = "yes"
            end
            e:draw()
        end)
        property.guiElement.propertyKey = property.key

    else
        error("Unknown property type: " .. property.type)
    end
end

function SettingsEditor:_createButtonGUI(gui, button, x, y, width)
    local manager = self.manager
    gui:addButton(x, y, width, 1, button.name, function (e) button.handler(e, manager) end)
end

function SettingsEditor:_validateProperties()
    local validationMessages = ""
    local validationResult = true

    for _, property in pairs(self.properties) do
        local result = self:_validateProperty(property)
        if result then
            local message = "\"" .. property.name .. "\": " .. result
            validationMessages = validationMessages .. message .. "\n"
        end
    end

    if #validationMessages > 0 then
        validationResult = false
        self.api.messageBox(nil, "There were validation errors:\n\n" .. validationMessages, {"OK"})
    end

    return validationResult
end

function SettingsEditor:_validateProperty(property)
    if property.validator then
        local value = self.manager:getValue(property.key)
        return property.validator:validate(value)
    end
end

function SettingsEditor:_getResult()
    if self.saveProperties then
        return {
            updated = true,
            properties = self.manager:getSettings()
        }
    else
        return {
            updated = false,
            properties = self.originalSettingsObject
        }
    end
end

return SettingsEditor
