-- ###############################################
-- #             Color Grid library              #
-- #                                             #
-- #   01.2019                   by: IlynPayne   #
-- ###############################################

--[[
    ## Desciription ##
    Color grid library allows to draw graphics in the GML library
    more easily.

    ## Example ##
    Below is a simple usage example

    local colorGrid = require("color_grid")
    local grid = colorGrid.grid({
		["#"] = 0xff6600
	})
	grid:line("#######  #####   #####  #######")
	grid:line("   #     #      #          #   ")
	grid:line("   #     #####   #####     #   ")
	grid:line("   #     #            #    #   ")
	grid:line("   #     #####   #####     #   ")
	grid:generateComponent(gui, 5, 5)
]]

local version = "1.0"
local startArgs = {...}

if startArgs[1] == "version_check" then return version end

-- Constants
local SEQUENCE_OFFSET = 0x1000000

-- Libraries
local gml = require("gml")

local lib = {}
local Grid = {}


--[[
Creates and returns new color grid.
@colorDefinition - table of colors (see an example in the header)
]]
lib.grid = function (colorDefinition)
    local grid = {}
    setmetatable(grid, { __index = Grid })
    grid.width = 0
    grid.height = 0
    grid.lines = {}

    grid.colors = {}
    local colorsMt = {}
    colorsMt.__index = function (table, key)
        if rawget(table, key) ~= nil then return table[key] end
        error("Color with key '" .. key .. "' wasn't found")
    end
    setmetatable(grid.colors, colorsMt)

    if (type(colorDefinition) == "table") then
        for shape, color in pairs(colorDefinition) do
            grid:color(shape, color)
        end
    end

    return grid
end

--[[
Adds a new line. The grid dimensions expand as new lines are added.
]]
function Grid:line(line)
    self.width = math.max(self.width, #line)
    self.height = self.height + 1
    table.insert(self.lines, line)
end

--[[
Defines new color.
@shape - character that will represent new color. Must be a single character.
@color - color value.
]]
function Grid:color(shape, color)
    checkArg(1, shape, "string")
    checkArg(2, color, "number")
    if (string.len(shape) ~= 1) then
        error("shape must be exactly one character long")
    end

    self.colors[shape] = color
end

--[[
Generates component from this object and adds it to a GUI.
Width and height are determined by grid size.
]]
function Grid:generateComponent(gui, x, y)
    if self.generated then error('grid already generated') end

    -- after generating component this grid becomes read-only
    self.generated = true
    self:convertToBitmap()

    -- search for sequences
    self.sequences = {}
    self.points = {}
    self.nextSequence = 1
    self:translate()
    self:generatePoints()

    self.colors = nil
    self.lines = nil

    local component = gml.api.baseComponent(gui, x, y, self.width, self.height, "color_grid", false)
    component.draw = function (c)
        if not c:isHidden() then
            for _, seq in pairs(self.sequences) do
                c.renderTarget.setBackground(seq.color)
                c.renderTarget.fill(c.posX + seq.x - 1, c.posY + seq.y - 1, seq.w, seq.h, " ")
            end
            for _, point in pairs(self.points) do
                c.renderTarget.setBackground(point.color)
                c.renderTarget.set(c.posX + point.x - 1, c.posY + point.y - 1, " ")
            end
            c.visible = true
        end
    end

    gui:addComponent(component)
    return component
end

function Grid:translate()
    local start = nil
    local current = nil

    -- search for sequences horizontally
    for y = 1, self.height do
        for x = 1, self.width do
            local c = self.bitmap[y][x]
            if c > 0 and c < SEQUENCE_OFFSET and current == nil then
                -- start sequence
                start = x
                current = c
            end
            if current ~= nil and (x == self.width or self.bitmap[y][x + 1] == 0 or self.bitmap[y][x + 1] >= SEQUENCE_OFFSET) then
                -- end sequence
                if x - start > 0 then
                    for j = start, x do
                        self.bitmap[y][j] = self.bitmap[y][j] + SEQUENCE_OFFSET
                    end
        
                    table.insert(self.sequences, {
                        color = c,
                        x =  start,
                        y = y,
                        w = x - start + 1,
                        h = 1
                    })
                end
    
                start = nil
                current = nil
            end
        end
    end

    -- search for sequences vertically
    start = nil
    current = nil
    for x = 1, self.width do
        for y = 1, self.height do
            local c = self.bitmap[y][x]
            if c > 0 and c < SEQUENCE_OFFSET and current == nil then
                start = y
                current = c
            end
            if current ~= nil and (y == self.height or self.bitmap[y + 1][x] == 0 or self.bitmap[y + 1][x] >= SEQUENCE_OFFSET) then
                -- end sequence
                if y - start > 0 then
                    for j = start, y do
                        self.bitmap[j][x] = self.bitmap[j][x] + SEQUENCE_OFFSET
                    end

                    table.insert(self.sequences, {
                        color = c,
                        x = x,
                        y = start,
                        w = 1,
                        h = y - start + 1
                    })
                end

                start = nil
                current = nil
            end
        end
    end
end

function Grid:generatePoints()
    for y = 1, self.height do
        for x = 1, self.width do
            if self.bitmap[y][x] < SEQUENCE_OFFSET and self.bitmap[y][x] > 0 then
                table.insert(self.points, {
                    color = self.bitmap[y][x],
                    x = x,
                    y = y
                })
            end
        end
    end
end

function Grid:convertToBitmap()
    self.bitmap = {}
    for _, line in pairs(self.lines) do
        local bitmapLine = {}
        for i = 1, #line do
            if line:sub(i, i) == " " then
                table.insert(bitmapLine, 0)
            else
                table.insert(bitmapLine, self.colors[line:sub(i, i)])
            end
        end
        for i = #line + 1, self.width do
            table.insert(bitmapLine, 0)
        end

        table.insert(self.bitmap, bitmapLine)
    end
end

return lib
