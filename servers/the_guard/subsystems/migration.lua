-- ################################################
-- #       The Guard  migration subsystem         #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

--[[
    ## Description ##
        This subsystem is responsible for migration of configuration files
        between the guard versions.
]]

local fs = require("filesystem")
local component = require("component")


local function migrateFrom2To3()
    local data = component.data
    if not data then return false end -- missing data component should be detected and reported in another subsystem

    local tokenFile = "/etc/the_guard/token"
    if not fs.exists(tokenFile) then return false end

    local tokenHandle = io.open(tokenFile, "r")
    local tokenContent, err = tokenHandle:read("*a")
    if not tokenContent then
        io.stderr:write("Unable to read token file\n")
        error(err)
    end
    tokenHandle:close()
    local token = data.decode64(tokenContent)
    token = data.md5(token)

    local function decryptFile(filePath, iv)
        local fullPath = fs.concat("/etc/the_guard", filePath)
        if not fs.exists(fullPath) then return function () end end

        local handle, err = io.open(fullPath, "r")
        if not handle then
            io.stderr:write("Unable to read content of file " .. fullPath .. "\n")
            error(err)
        end
        local encoded = handle:read("*a")
        handle:close()

        local success, decoded = pcall(data.decode64, encoded)
        if not success then
            io.stderr:write("Unable to decode content of file " .. fullPath .. "\n")
            error(decoded)
        end

        local decrypted = data.decrypt(decoded, token, data.md5(iv))

        handle = io.open(fullPath:gsub("dat", "conf"), "w")
        handle:write(decrypted)
        handle:close()

        return function ()
            fs.remove(fullPath)
        end
    end

    local delete1 = decryptFile("modules/auth/cards.dat", "auth")
    local delete2 = decryptFile("modules/auth/devices.dat", "auth")
    local delete3 = decryptFile("modules/auth/users.dat", "auth")
    local delete4 = decryptFile("modules/turrets/lists.dat", "turrets")
    local delete5 = decryptFile("modules/turrets/sensors.dat", "turrets")
    local delete6 = decryptFile("modules/turrets/turrets.dat", "turrets")

    delete1()
    delete2()
    delete3()
    delete4()
    delete5()
    delete6()

    fs.remove("/etc/the_guard/passwd.bin")
    fs.remove("/etc/the_guard/token")

    return true
end

local migration = {}

function migration:initialize()
    return true
end

function migration:createUI() end

function migration:cleanup() end

function migration:migrate()
    if migrateFrom2To3() then
        print("Migrated configuration files from the guard 2 to 3")
    end
end

return migration