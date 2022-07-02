-- ################################################
-- #  The Guard  components subsystem / config    #
-- #                                              #
-- #  03.2022                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end


local Config = {
    hiddenComponents = { -- List of components that can't be registered
        "screen",
        "eeprom",
        "filesystem",
        "data",
        "modem",
        "keyboard",
        "gpu",
        "computer"
    },

    -- Components that have additional properties exposed to modules
    --[[
        Schema:
        additionalProperties = {
            component_name = {
                properties = {
                    -- Display order is defined by indides
                    [index] = {
                        name = "name under which property is stored",
                        displayName = "name displayed in GUI",
                        type = "string|number|decimal",
                        required = false
                   }
                },
                -- Digest is a short summary of custom properties, which
                -- is displayed on component list
                digest = function (propsObj) return "short description" end
            }
        }
    ]]
    additionalProperties = {
        os_energyturret = {
            properties = {
                [1] = {
                    name = "x",
                    displayName = "X coordinate",
                    type = "number",
                    required = true
                },
                [2] = {
                    name = "y",
                    displayName = "Y coordinate",
                    type = "number",
                    required = true
                },
                [3] = {
                    name = "z",
                    displayName = "Z coordinate",
                    type = "number",
                    required = true
                }
            },
            digest = function (props)
                return "X:" .. props.x .. " Y:" .. props.y .. " Z:" .. props.z
            end
        }
    }
}

function Config.isComponentVisible(_type)
    for _, n in pairs(Config.hiddenComponents) do
        if n == _type then return false end
    end
    return true
end

return Config
