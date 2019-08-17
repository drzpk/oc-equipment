-- ############################################
-- #		    TG2 config decryptor		  #
-- #										  #
-- #  08.2019			   by:Dominik Rzepka  #
-- ############################################

--[[
    ## Description ##
    Simple script used to decrypt config files encrypted with The Guard 2
]]

local version = "1.0"
local args = {...}

if args[1] == "version_check" then return version end

local fs = require("filesystem")
local component = require("component")
local serial = require("serialization")



local data = nil
if component.isAvailable("data") then
	data = component.data
end
if not data then
	io.stderr:write("App requires a data card tier 2 in order to work.")
	return
elseif not data.encrypt then
	io.stderr:write("Used data card must be at least of tier 2.")
	return
end

local tokenFile = "/etc/the_guard/token"


local function loadToken()
    if not fs.exists(tokenFile) then
        print("Token not found")
        return
    end

    local file, e = io.open(tokenFile, "r")
    if file then
        local dec = data.decode64(file:read("*a"))
        if dec then
           return data.md5(dec)
        else
            internalLog("Couldn't decode the token")
        end
    else
        print("Couldn't open token file (" .. e .. ")")
    end
end

local function loadFile(filename)
    local content = nil

    local file, e = io.open(filename, "r")
    if file then
        content = file:read("*a")
        file:close()
    else
        print("Couldn't open config file: " .. e)
        return
    end

    local result, content = pcall(data.decode64, content)
	if result then
		return content
    else
        print("Couldn't load config file: " .. content)
	end
end

local function prettyPrint(content)
    local result, obj = pcall(serial.unserialize, content)
    if result then
        print(serial.serialize(obj, math.huge))
    else
        print(content)
    end
end

local function main()
    if #args ~= 2 then
        print("Usage:")
        print("tg2_decrypt <filename> <iv>")
        return
    end

    local encrypted = loadFile(args[1])
    if not encrypted then return end

    local key = loadToken()
    if not key then return end

    local result, content = pcall(data.decrypt, encrypted, key, data.md5(args[2]))
    if result then
        prettyPrint(content)
    else
        print("Decryption failed: " .. content)
    end
end

main()