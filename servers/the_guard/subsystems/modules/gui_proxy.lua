-- ################################################
-- #   The Guard  modules subsystem / gui proxy   #
-- #                                              #
-- #  01.2021                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["gml"] = nil

local gml = require("gml")

local SLOT_SIZE = {68, 19}
local SLOTS = {
	[1] = {1, 1},
	[2] = {70, 1},
	[3] = {1, 21},
	[4] = {70, 21}
}
local GML_PROXY_SLOT_NO = "_gml_proxy_slot_no"

local proxy = {
    SLOTS = SLOTS,
    SLOT_SIZE = SLOT_SIZE
}

function proxy:create(subsystem, rootGui)
    local obj = {
        api = subsystem.api,
        logger = subsystem.logger,
        rootGui = rootGui,
        slots = {} -- modules in slots
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function proxy:putModuleInSlot(slotNo, module)
    self.logger:debug("proxy", "Putting module {} in slot {}", module.name, slotNo)
    if self.slots[slotNo] then
        self:clearSlot(slotNo)
    end

    local oldSlotNo = nil
    for no, name in pairs(self.slots) do
        if module.name == name then
            oldSlotNo = no
            break
        end
    end
    if oldSlotNo then
        self:clearSlot(oldSlotNo)
    end

    local proxygui = self:_createGmlProxy(slotNo)
    local status, err = self.api.tryCatch(self, function () module.executable.setUI(proxygui) end, nil)
    if not status then return false, err end

    self.slots[slotNo] = module.name
    self.rootGui:draw()
    return true
end

function proxy:clearSlot(slotNo)
    local componentsToRemove = {}
    for _, cmp in pairs(self.rootGui.components) do
        if cmp[GML_PROXY_SLOT_NO] == slotNo then
            table.insert(componentsToRemove, cmp)
        end
    end

    for _, cmp in pairs(componentsToRemove) do
        self.rootGui:removeComponent(cmp)
    end

    self.slots[slotNo] = nil

    if #componentsToRemove > 0 then
        self.rootGui:draw()
    end
end

function proxy:_createGmlProxy(slotNo)
    local gmlProxy = {}
    local slot = SLOTS[slotNo]

    gmlProxy.addLabel = function (_, x, y, width, labelText)
        x, y, width = self:_calculateGmlComponentPosition(x, y, width, 1)
        local label = self.rootGui:addLabel(x + slot[1] - 1, y + slot[2] - 1, width, labelText)
        self:_createComponentProxy(label, slotNo)
        return label
    end

    gmlProxy.addButton = function (_, x, y, width, height, buttonText, onClick)
        x, y, width, height = self:_calculateGmlComponentPosition(x, y, width, height)
        local button = self.rootGui:addButton(x + slot[1] - 1, y + slot[2] - 1, width, height, buttonText, onClick)
        self:_createComponentProxy(button, slotNo)
        return button
    end

    gmlProxy.addTextField = function (_, x, y, width, text)
        x, y, width = self:_calculateGmlComponentPosition(x, y, width, 1)
        local textField = self.rootGui:addTextField(x + slot[1] - 1, y + slot[2] - 1, width, text)
        self:_createComponentProxy(textField, slotNo)
        return textField
    end

    gmlProxy.addListBox = function (_, x, y, width, height, list)
        x, y, width, height = self:_calculateGmlComponentPosition(x, y, width, height)
        local listBox = self.rootGui:addListBox(x + slot[1] - 1, y + slot[2] - 1, width, height, list)
        self:_createComponentProxy(listBox, slotNo)
        return listBox
    end

    gmlProxy.addComboBox = function (_, x, y, width, list)
        x, y, width = self:_calculateGmlComponentPosition(x, y, width, 1)
        local comboBox = self.rootGui:addComboBox(x, y, width, list)
        self:_createComponentProxy(comboBox, slotNo)
        return comboBox
    end

    return gmlProxy
end

function proxy:_createComponentProxy(component, slotNo)
    component[GML_PROXY_SLOT_NO] = slotNo

    local createFunctionProxy = function (functionName)
        local functionToCall = component[functionName]
        if type(functionToCall) ~= "function" then return end

        return function (...)
            local params = {...}
            local status, result = self.api.tryCatch(self, function() functionToCall(table.unpack(params)) end, true)
            if not status then
                self.logger:error("proxy", "Error while executing function '{}' in component '{}': {}", functionName, component.name, result)
            end
        end
    end

    createFunctionProxy("onClick")
    createFunctionProxy("onDoubleClick")
    createFunctionProxy("onBeginDrag")
    createFunctionProxy("onDrag")
    createFunctionProxy("onDrop")
    createFunctionProxy("onSelected")
    createFunctionProxy("onChange")
end

function proxy:_calculateGmlComponentPosition(x, y, width, height)
    local maxWidth = SLOT_SIZE[1]
    local maxHeight = SLOT_SIZE[2]

    local width = math.min(width, maxWidth)
    local height = math.min(height, maxHeight)

    if x == "left" then
        x = 1
    elseif x == "right" then
        x = maxWidth - width + 1
    elseif x == "center" then
        x = math.max(1, math.floor((maxWidth - width) / 2))
    elseif x < 0 then
        x = maxWidth - width + 2 + x
    elseif x < 1 then
        x = 1
    elseif x + width - 1 > maxWidth then
        x = maxWidth - width + 1
    end

    if y == "top" then
        y = 1
    elseif y == "bottom" then
        y = maxHeight - height + 1
    elseif y == "center" then
        y = math.max(1, math.floor((maxHeight - height) / 2))
    elseif y < 0 then
        y = maxHeight - height + 2 + y
    elseif y < 1 then
        y = 1
    elseif y + height - 1 > maxHeight then
        y = maxHeight - height + 1
    end

    return x, y, width, height
end

return proxy