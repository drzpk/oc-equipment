-- ################################################
-- #      The Guard  components subsystem         #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["gml"] = nil
package.loaded["common/utils"] = nil
package.loaded["subsystems/components/hal"] = nil
package.loaded["subsystems/components/component"] = nil
package.loaded["subsystems/components/component_gui"] = nil

local fs = require("filesystem")
local gml = require("gml")
local utils = require("common/utils")

local hal = require("subsystems/components/hal")
local Component = require("subsystems/components/component")
local componentGui = require("subsystems/components/component_gui")

local SETTINGS_NAME = "components"

---

local components = {
    components = {} -- registered components (Component objects)
}

---

function components:initialize()
    hal.components = self
    local ref = self
    Component._generateUid = function () return self:_generateUid() end
    Component.logger = self.logger
    return true
end

function components:cleanup() end

function components:createUI(rootGui) end

function components:loadComponents()
    self:_loadConfiguration()

    -- todo: temporary
    local test = Component.register("3312836c-fe7c-42f5-b302-a5123c80ecb0", "redstone")
    table.insert(self.components, test)
end

function components:showComponentManager()
    local clones = self:_cloneComponents()
    local modifiedComponents = componentGui:registeredComponentsList(clones)
    local changed = false

    for id, component in pairs(modifiedComponents) do
        changed = true
        if component then
            local key = self:_findComponentKey(id)
            local originalComponent = self.components[key]
            originalComponent:updateFrom(component)
        else
            self:_deleteComponent(id)
        end
    end

    if changed then
        self:_saveConfiguration()
    end
end

function components:showNewComponentWizard()
    local createdComponents = componentGui:unregisteredComponentsList()
    local changed = false

    for _, component in pairs(createdComponents) do
        table.insert(self.components, component)
        changed = true
    end

    if changed then
        self:_saveConfiguration()
    end
end

function components:isComponentRegistered(addr)
    for _, comp in pairs(self.components) do
        if addr == comp.address then return true end
    end

    return false
end

function components:_deleteComponent(id)
    local key = self:_findComponentKey(id)
    if key then
        table.remove(self.components, key)
        return true
    end
    
    return false
end

function components:_findComponentKey(id)
    for key, component in pairs(self.components) do
        if component.id == id then
            return key
        end
    end

    return nil
end

function components:_loadConfiguration()
    self.logger:debug("load", "Loading configuration")
    
    local configuration = self.subsystems.settings:loadSubsystemSettings(self, SETTINGS_NAME)
    configuration = configuration or {}

    for _, componentConfig in pairs(configuration) do
        local component, err = Component.load(componentConfig)
        if component then
            table.insert(self.components, component)
        else
            self.logger:error("load", "Error while loading component: {}", err)
        end
    end
end

function components:_saveConfiguration()
    self.logger:debug("save", "Saving configuration")

    local configuration = {}
    for _, component in pairs(self.components) do
        local componentConfig = component:save()
        table.insert(configuration, componentConfig)
    end
    
    self.subsystems.settings:saveSubsystemSettings(self, SETTINGS_NAME, configuration)
end

function components:_cloneComponents()
    -- Should clone be used? What if an old instance is kept somewhere?
    local clones = {}
    for _, component in pairs(self.components) do
        local clone = component:clone()
        table.insert(clones, clone)
    end

    return clones
end

function components:_generateUid()
    local function generator()
        local template ='xyxyxy'
        return string.gsub(template, '[xy]', function (c)
            local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
            return string.format('%x', v)
        end)
    end

    while true do
        local uid = generator()
        local unique = true
        for _, c in pairs(self.components) do
            if c.id == uid then
                unique = false
                break
            end
        end

        if unique then return uid end
    end
end

return components
