-- ################################################
-- #   The Guard  settings subsystem/validator    #
-- #                                              #
-- #  12.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

package.loaded["common/utils"] = nil

local utils = require("common/utils")


local ConstraintValidator = {}

ConstraintValidator.constraintDefinitions = {
    required = {
        constraintValueChecker = function (constraintValue)
            if type(constraintValue) ~= "boolean" then
                 return "Constraint value must be boolean"
            end
        end,
        validator = function (constraintValue, value)
            if not value or type(value) == "string" and #value == 0 then
                return "value is required"
            end
        end
    },

    minLength = {
        constraintValueChecker = function (constraintValue)
            if type(constraintValue) ~= "number" or constraintValue < 0 then
                return "Constraint value must be a positive number"
            end
        end,
        validator = function (constraintValue, value)
            if type(value) ~= "string" or #value < constraintValue then
                return "minimum length is " .. tostring(constraintValue)
            end
        end
    },

    maxLength = {
        constraintValueChecker = function (constraintValue)
            if type(constraintValue) ~= "number" or constraintValue < 1 then
                error("Constraint value must be a positive number")
            end
        end,
        validator = function (constraintValue, value)
            if type(value) ~= "string" or #value > constraintValue then
                return "maximum length is " .. tostring(constraintValue)
            end
        end
    },

    minValue = {
        constraintValueChecker = function (constraintValue)
            if type(constraintValue) ~= "number" or constraintValue < 0 then
                return "Constraint value must be a positive number"
            end
        end,
        validator = function (constraintValue, value)
            if type(value) ~= "number" or value < constraintValue then
                return "minimum value is " .. tostring(constraintValue)
            end
        end
    },
    
    maxValue = {
        constraintValueChecker = function (constraintValue)
            if type(constraintValue) ~= "number" or constraintValue < 0 then
                return "Constraint value must be a positive number"
            end
        end,
        validator = function (constraintValue, value)
            if type(value) ~= "number" or value > constraintValue then
                return "maximum value is " .. tostring(constraintValue)
            end
        end
    }
}

--[[
    Creates constraint validator
    @param constraints - table with constraint definitions
    @param availableConstraints - table with constraint names available for given context
    @return constraint validator
]]
function ConstraintValidator:createValidator(constraints, availableConstraints)
    local obj = {
        constraints = constraints or {}
    }

    setmetatable(obj, self)
    self.__index = self

    obj:_validateConstraints(availableConstraints)
    return obj
end

--[[
    Validates given value and returns error message if something is wrong, nil otherwise.
]]
function ConstraintValidator:validate(value)
    for constraintName, constraintValue in pairs(self.constraints) do
        local definition = self.constraintDefinitions[constraintName]
        local errorMessage = definition.validator(constraintValue, value)
        if errorMessage then return errorMessage end
    end
end

function ConstraintValidator:_validateConstraints(availableConstraints)
    for name, value in pairs(self.constraints) do
        if not utils.indexOf(availableConstraints, name) then
            error("Constraint '" .. name .. "' is not available in current context")
        end

        local definition = self.constraintDefinitions[name]
        if not definition then error("Constraint '" .. name .. "' doesn't exist") end
        local validationError = definition.constraintValueChecker(value)
        if validationError then
            error("Error while validating definition of constraint '" .. name .. "': " .. validationError)
        end
    end
end


return ConstraintValidator