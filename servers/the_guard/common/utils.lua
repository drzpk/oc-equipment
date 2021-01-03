-- ################################################
-- #             The Guard     utils              #
-- #                                              #
-- #  08.2020                by: Dominik Rzepka   #
-- ################################################

local version = "1.0.0"
local args = {...}

if args[1] == "version_check" then return version end

local utils = {}


function utils.split(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
       if s ~= 1 or cap ~= "" then
          table.insert(t, cap)
       end
       last_end = e+1
       s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
       cap = str:sub(last_end)
       table.insert(t, cap)
    end
    return t
 end

function utils.deepcopy(orig)
    local origType = type(orig)
    local copy
    if origType == 'table' then
        copy = {}
        for origKey, origValue in next, orig, nil do
            copy[deepcopy(origKey)] = deepcopy(origValue)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function utils.copy(orig)
    local origType = type(orig)
    local copy
    if origType == 'table' then
        copy = {}
        for origKey, origValue in pairs(orig) do
            copy[origKey] = origValue
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function utils.indexOf(value, item)
    local type = type(value)
    if type == "table" then
        for i, v in ipairs(value) do
            if v == item then return i end
        end
    elseif type == "string" then
        error("not implemented")
    else
        error("Wrong type")
    end
end

return utils