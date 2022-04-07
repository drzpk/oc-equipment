-- ################################################
-- # The Guard  components subsystem / component  #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

--[[
    ## Description ##
    Component provides a layer of abstraction between the_guard modules
    and physical hardware. This enables the following:
      - swapping underlying devices seamlessly without reconfiguring modules that use them
      - enabling and disabling components without the need of physically disconnecting them from network
]]

local hal = require("subsystems/components/hal")

local Component = {
    id = nil,
    address = nil,
    type = nil,
    name = nil,
    state = nil, -- todo: add 'offline' property, so component state doesn't change when it's disconnected
    properties = nil,

    -- set by the subsystem
    logger = nil,
    _generateUid = nil
}

function Component.register(address, _type, id)
    local component = {}
    setmetatable(component, Component)
    Component.__index = Component

    component.id = Component._generateUid()
    component.address = address
    component.type = _type
    component.properties = {}

    Component.logger:debug("component", "Registering new component with id {}, address {} and type {}", component.id, address, type)
    return component
end

function Component.load(config)
    local component = {}
    setmetatable(component, Component)
    Component.__index = Component

    component.id = config.id
    component.address = config.address
    component.type = config.type
    component.name = config.name
    component.state = config.state
    component.properties = config.properties

    local error = component:_checkConfiguration()
    if not error then
        return component
    else
        return nil, error
    end
end

function Component:updateFrom(otherComponent)
    self.name = otherComponent.name
    if self.state ~= otherComponent.state then
        if otherComponent.state then
            self:enable()
        else
            self:disable()
        end
    end
end

function Component:clone()
    local config = self:save()
    return Component.load(config)
end

function Component:isOnline()
    -- todo
    return true
end

function Component:isActive()
    return self.state and self:isOnline()
end

function Component:enable()
    self.state = true
end

function Component:disable()
    self.state = false
end

function Component:save()
    local export = {
        id = self.id,
        address = self.address,
        type = self.type,
        name = self.name,
        state = self.state,
        properties = self.properties
    }

    return export
end

function Component:_checkConfiguration()
    -- todo: check custom properties (should be a flat list with primitive types)

    if type(self.id) ~= "string" then
        self.id = self:_generateUid()
        self.logger:warn("checkComponent", "Invalid id, generated a new one: {}", self.id)
    end

    if type(self.name) ~= "string" then
        return "Missing name for component " .. self.id
    end

    if type(self.address) == "string" then
        if not hal.isConnected(self.address) then
            self.logger:debug("checkComponent", "Component {} is offline", self.name)
            self.state = false
        end  
    else
        return "Invalid address type: " .. type(self.address)
    end

    if type(self.state) ~= "boolean" then
        self.logger:warn("checkComponent", "Invalid state ({}) setting to false", type(self.state))
        self.state = false
    end

    if type(self.type) ~= "string" then
        return "Invalid type of component type: " .. type(self.type)
    end
end

return Component
