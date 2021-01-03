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
package.loaded["common/utils"] = nil

local gml = require("gml")
---
local SettingsManager = require("subsystems/settings/settings_manager")
local ConstraintValidator = require("subsystems/settings/constraint_validator")
local utils = require("common/utils")


local SettingsEditor = {}

local function checkArg(number, requiredType, value, allowNil)
    if type(value) == "nil" and allowNil then return end

    if type(value) ~= requiredType then
        error("Wrong argument " .. tostring(number) .. ": required '" .. requiredType .. "' type but got '" .. type(value) .. "'")
    end
end

--[[
    @ret: status, selected option index
]]
local function showSelectPropertyModal(options, currentOptionIndex, isRequired)
    local status = false
    local selectedOption = nil

    local mgui = gml.create("center", "center", 30, 18)
    mgui:addLabel("center", 1, 16, "Select an option")
    local listbox = mgui:addListBox(3, 3, 26, 12, options)
    
    if currentOptionIndex then listbox:select(currentOptionIndex) end
    listbox.onChange = function ()
        if not currentOptionIndex and isRequired then
            table.remove(listbox.list, 1)
            listbox:updateList(listbox.list)
        end
        listbox.onChange = nil
    end

    mgui:addButton(16, 16, 10, 1, "Cancel", function () mgui:close() end)
    mgui:addButton(4, 16, 10, 1, "Select", function ()
        if listbox.selectedLabel then
            status = true
            selectedOption = listbox.selectedLabel
            mgui:close()
        else
            api.messageBox(nil, "An option must be selected", {"OK"})
        end
    end)

    mgui:run()
    return status, selectedOption
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

    self:_addProperty(property)
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

    self:_addProperty(property)
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

    self:_addProperty(property)
    self.manager:defineBooleanProperty(key, defaultValue)
end

--[[
    Available constraints:
    required
]]
function SettingsEditor:addSelectProperty(key, name, options, defaultOption, constraints)
    if defaultOption and not options[defaultOption] then
        error("Default option doesn't exist in options table")
    end

    local optionKeys = {}
    local optionLabels = {}
    for k, l in pairs(options) do
        table.insert(optionKeys, k)
        table.insert(optionLabels, l)
    end

    local property = {
        kind = "property",
        key = key,
        name = name,
        type = "select",
        optionKeys = optionKeys,
        optionLabels = optionLabels,
        default = defaultOption,
        modalSelectOptionThreshold = 10,
        selectedOptionUpdatedListener = nil,
        valueWidth = 12,
        requiresSeparators = true,
        validator = ConstraintValidator:createValidator(constraints, {"required"})
    }

    self:_addProperty(property)
    self.manager:defineRawProperty(key, defaultOption)
    return property
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
    Used to impose restrictions on minimum editor window size, so, for example, a custom GUI elements
    can fit (see the second parameter of SettingsEditor:show function).
]]
function SettingsEditor:setMinimumSize(minWidth, minHeight)
    if type(minWidth) == "number" and minWidth > 0 then
        self.minWidth = minWidth
    end
    if type(minHeight) == "number" and maxHeight > 0 then
        self.minHeight = minHeight
    end
end

--[[
    Displays the editor

    @param customElementCreatorHandler - a function called to add custom GUI elements.
        First parameter is the editor's GUI.
    @returns table: {
        updated = false, -- whether properties were updated (user clicked OK button)
        properties = {} -- properties table (with current values)
    }
]]
function SettingsEditor:show(title, customElementCreatorHandler)
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

    if self.minWidth then
        totalWidth = math.max(totalWidth, self.minWidth)
    end
    if self.minHeight then
        totalHeight = max.max(totalHeight, self.minHeight)
    end
    self.totalWidth = totalWidth
    self.totalHeight = totalHeight

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

    if type(customElementCreatorHandler) == "function" then
        customElementCreatorHandler(gui)
    end

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

    elseif property.type == "select" then
        local value = manager:getValue(property.key)
        local labels = utils.copy(property.optionLabels)
        local isRequired = property.validator and property.validator.constraints.required
        if not value then
            -- add empty choice
            table.insert(labels, 1, "")
        end

        local getTableValue = function (tab, index)
            if not isRequired and index == 1 then
                -- first option is empty if property isn't required
                return nil
            else
                if not isRequired then index = index - 1 end
                return tab[index]
            end
        end

        if #property.optionKeys < property.modalSelectOptionThreshold then
            -- combo box
            property.guiElement = gui:addComboBox(valueX, y - 1, property.valueWidth, labels)
            for i, l in pairs(property.optionKeys) do
                if l == value then
                    if not isRequired then i = i + 1 end
                    property.guiElement:select(i, false)
                    break
                end
            end
            
            property.guiElement.onSelected = function (element, selectedPosition)
                local newValue = getTableValue(property.optionKeys, selectedPosition)
                manager:setValue(property.key, newValue)
                if property.selectedOptionUpdatedListener then property.selectedOptionUpdatedListener(newValue) end
                if isRequired and not value and not element.wasRemoved then
                    table.remove(element.list, 1)
                    element:updateList(element.list)
                    element.wasRemoved = true
                end
            end
        else
            -- modal window
            local updateButtonLabel = function (label)
                property.guiElement.text = label
                property.guiElement:draw()
            end
            property.guiElement = gui:addButton(valueX, y, property.valueWidth, 1, "", function ()
                local value = manager:getValue(property.key)
                local index = not isRequired and 1 or nil
                for i, l in pairs(property.optionKeys) do
                    if l == value then
                        index = i
                        if not isRequired then index = index + 1 end
                        break
                    end
                end

                local status, selectedIndex = showSelectPropertyModal(labels, index, isRequired)
                if status then
                    local newKey = getTableValue(property.optionKeys, selectedIndex)
                    manager:setValue(property.key, newKey)
                    if property.selectedOptionUpdatedListener then property.selectedOptionUpdatedListener(newKey) end

                    local newLabel = getTableValue(property.optionLabels, selectedIndex)
                    updateButtonLabel(newLabel)
                end
            end)

            local index = nil
            local valueToCompare = value or property.default
            for i, v in pairs(property.optionKeys) do
                if v == valueToCompare then
                    updateButtonLabel(property.optionLabels[i])
                    break
                end
            end
        end

    else
        error("Unknown property type: " .. property.type)
    end
end

function SettingsEditor:_addProperty(property)
    local lastProperty = self.properties[#self.properties]
    if lastProperty then
        if property.requiresSeparators and lastProperty.kind ~= "separator" then
            error("Property '" .. property.key .. "' requires a separator before it")
        elseif lastProperty.requiresSeparators and property.kind ~= "separator" then
            error("Property '" .. lastProperty.key .. "' requires a separator after it")
        end
    end

    table.insert(self.properties, property)
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
