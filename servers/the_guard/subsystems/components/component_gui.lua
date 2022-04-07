-- ################################################
-- #      The Guard  components subsystem         #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["gml"] = nil
package.loaded["common/dialogs"] = nil

local gml = require("gml")
local hal = require("subsystems/components/hal")
local Component = require("subsystems/components/component")
local dialogs = require("common/dialogs")

local ComponentGui = {}


function ComponentGui:registeredComponentsList(components)
    local listBox, list = nil, nil
    local modifiedComponents = {}

    local function refreshList()
        local componentsByType = {}
        for _, c in pairs(components) do
            if not componentsByType[c.type] then componentsByType[c.type] = {} end

            local str = "[" .. c.id .. "] "
            str = str .. c.name .. " "
            str = str .. "(" .. c.address:sub(1, 8) .. "...) "
            str = str .. (c.state and "ON" or "OFF")

            -- todo: these should be custom properties
            if c.x then str = str .. "  X:" .. tostring(c.x) end
            if c.y then str = str .. "  Y:" .. tostring(c.y) end
            if c.z then str = str .. "  Z:" .. tostring(c.z) end

            if not c:isOnline() then str = "*" .. str end
            table.insert(componentsByType[c.type], str)
        end

        local componentsWithType = {}
        for a, b in pairs(componentsByType) do
            table.insert(componentsWithType, {a, b})
        end
        table.sort(componentsWithType, function(a, b) return string.byte(a[1], 1) < string.byte(b[1], 1) end)
        
        list = {}
        for _, t in pairs(componentsWithType) do
            table.insert(list, string.upper(t[1]) .. ":")
            for _, l in pairs(t[2]) do
                table.insert(list, "  " .. l)
            end
        end

        if listBox then
            listBox:updateList(list)
        end
    end

    local function enableAll()
        for _, c in pairs(components) do
            c:enable()
        end
        refreshList()
    end

    local function disableAll()
        for _, c in pairs(components) do
            c:disable()
        end
        refreshList()
    end

    local function reloadList()
        refreshList()
    end

    local function details()
        local first = listBox:getSelected():find("%[")
        local last = listBox:getSelected():find("%]")

        if first and last then
            local id = listBox:getSelected():sub(first + 1, last - 1)
            for _, c in pairs(components) do
                if c.id == id then
                    local modified = self:_componentEditor(c)
                    if modified then
                        modifiedComponents[modified.id] = modified
                    end
                    break
                end
            end

            reloadList()
        end
    end
    
    refreshList()

    local cgui = gml.create("center", "center", 90, 30)
    cgui:addLabel("center", 1, 22, "Installed components")
    listBox = cgui:addListBox(2, 3, 84, 20, list)
    listBox.onDoubleClick = details
    cgui:addLabel(4, 23, 32, "Legend: [ID] name (address...)")
    cgui:addLabel(68, 23, 13, "* - offline")
    cgui:addButton(3, 25, 21, 1, "Enable all", enableAll)
    cgui:addButton(3, 27, 21, 1, "Disable all", disableAll)
    cgui:addButton(54, 27, 14, 1, "Refresh", reloadList)
    cgui:addButton(70, 27, 14, 1, "Close", function() cgui:close() end)
    cgui:run()

    return modifiedComponents
end

function ComponentGui:unregisteredComponentsList()
    local ngui, listBox, list, componentList = nil, nil, nil, nil
    local createdComponents = {}

    local function reloadList()
        componentList = hal.getUnregisteredComponents()
        
        for address, _ in pairs(createdComponents) do
            componentList[address] = nil
        end

        list = {}
        for _, comp in pairs(componentList) do
            table.insert(list, comp.address .. "   " .. comp.type)
        end

        if listBox then
            listBox:updateList(list)
        end
    end

    local function addComponent()
        local addr = listBox:getSelected():match("^(%x+%-%x+%-%x+%-%x+%-%x+)%s%s%s(.+)")
        if addr then
            local created = self:_newComponentEditor(componentList[addr])
            if created then
                createdComponents[created.address] = created
            end
            reloadList()
        end
    end

    reloadList()

    ngui = gml.create("center", "center", 70, 30)
    ngui:addLabel("center", 1, 21, "Add new component")
    listBox = ngui:addListBox(2, 3, 64, 23, list)
    listBox.onDoubleClick = addComponent
    ngui:addButton(36, 28, 14, 1, "Refresh", function()
        reloadList()
    end)
    ngui:addButton(52, 28, 14, 1, "Close", function()
        ngui:close()
    end)

    ngui:run()

    return createdComponents
end

function ComponentGui:_newComponentEditor(selectedComponent)
    local component = Component.register(selectedComponent.address, selectedComponent.type)
    return self:_componentEditor(component, true)
end

function ComponentGui:_componentEditor(component, isNew)
    local saved = nil

    local agui = gml.create("center", "center", 54, 16)
    local title = isNew and "New component wizard" or "Component editor"
    agui:addLabel("center", 1, #title, title)
    agui:addLabel(2, 3, 20, "UID:     " .. component.id)
    agui:addLabel(2, 4, 50, "Address: " .. component.address)
    agui:addLabel(2, 5, 48, "Type:    " .. component.type)
    agui:addLabel(2, 6, 7, "Name:")
    agui:addLabel(2, 7, 9, "Status:")

    local name = agui:addTextField(11, 6, 22)
    name.text = isNew and "" or component.name

    local button = agui:addButton(11, 7, 13, 1, "enabled", function(self)
        if self.status then
            self.text = "disabled"
            self.status = false
            self:draw()
        else
            self.text = "enabled"
            self.status = true
            self:draw()
        end
    end)
    button.status = true

    agui:addButton(20, 14, 14, 1, "Apply", function()
        if name.text:len() < 1 then
            dialogs.messageBox(agui, "Component name cannot be empty.", {"OK"})
        elseif name.text:len() > 20 then
            dialogs.messageBox(agui, "Component name cannot be longer than 20 characters.", {"OK"})
        else
            component.name = name.text
            if button.status then
                component:enable()
            else
                component:disable()
            end

            saved = true
            agui:close()
        end
    end)
    agui:addButton(36, 14, 14, 1, "Cancel", function() agui:close() end)

    agui:run()

    if saved then return component end
end

return ComponentGui
