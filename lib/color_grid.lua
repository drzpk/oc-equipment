-- ###############################################
-- #             Color Grid library              #
-- #                                             #
-- #   01.2019                   by: IlynPayne   #
-- ###############################################

--[[
    ## Desciription ##
    Color grid library allows to draw graphics in the GML library
    more easily.

    ## Example - grid ##
    Below is a simple usage example of grid

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

    
    ## Example - pencil ##
    Below is a simple usage example of drawing lines
    
    local colorGrid = require("color_grid")
    local pencil = colorGrid.pencil(colorGrid.pencilMode.BOLD, gui, startX, startY, width, height)
    pencil:color(0xff0000, 0x00ff00)
    pencil:beginPath(2, 5)
    pencil:up(5)
    pencil:right(50)
    pencil:down(2)
    pencil:right(3)
    pencil:endPath()
    -- Line will be drawn automatically (GML component), but can be also drawn manually
    pencil:draw()
]]

local version = "2.0"
local startArgs = {...}

if startArgs[1] == "version_check" then return version end

-- Constants
local SEQUENCE_OFFSET = 0x1000000

-- Libraries
local unicode = require("unicode")
local gml = require("gml")

local lib = {}
local Grid = {}
local Pencil = {}


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
    self:generate()
    local that = self

    local component = gml.api.baseComponent(gui, x, y, self.width, self.height, "color_grid", false)
    component.draw = function (c)
        if not c:isHidden() then
            self:draw(c.renderTarget, c.posX, c.posY, false)
            c.visible = true
        end
    end

    gui:addComponent(component)
    return component
end

--[[
Manually draws this component at specified position.
@gpu - gpu component used for drawing
@x - x position
@y - y position
@center - whether given position is centered
]]
function Grid:draw(gpu, x, y, center)
    if not self.generated then self:generate() end

    if center then
        x = x - math.floor(self.width / 2)
        y = y - math.floor(self.height / 2)
    end

    for _, seq in pairs(self.sequences) do
        gpu.setBackground(seq.color)
        gpu.fill(x + seq.x - 1, y + seq.y - 1, seq.w, seq.h, " ")
    end
    for _, point in pairs(self.points) do
        gpu.setBackground(point.color)
        gpu.set(x + point.x - 1, y + point.y - 1, " ")
    end
end

function Grid:generate()
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

lib.pencilMode = {
    BOLD = "bold"
}

local PENCIL_MODES = {
    bold = {
        vertical = unicode.char(0x2503),
        horizontal = unicode.char(0x2501),
        bottomLeft = unicode.char(0x2513),
        bottomRight = unicode.char(0x250f),
        topLeft = unicode.char(0x251b),
        topRight = unicode.char(0x2517)
    }
}

--[[
Creates a pencil GML element. Position and dimensions
act as a boundary
]]
lib.pencil = function (mode, gui, x, y, width, height)
    checkArg(1, mode, "string")
    checkArg(3, x, "number")
    checkArg(4, y, "number")
    checkArg(5, width, "number")
    checkArg(6, height, "number")

    if width < 1 then error("Width must be positive") end
    if height < 1 then error("Height must be positive") end

    local chars = PENCIL_MODES[mode]
    if not chars then
        error("Mode '" .. mode .. "' doesn't exist")
    end

    local pencil = {
        isDown = false,
        paths = {},
        mode = mode,
        chars = chars,
        x = nil,
        y = nil
    }
    setmetatable(pencil, { __index = Pencil })

    local component = gml.api.baseComponent(gui, x, y, width, height, "canvas", false)
    pencil.component = component
    pencil.component.draw = function ()
        pencil:draw()
    end

    gui:addComponent(component)
    return pencil
end

--[[
Sets pencil color. If called when pencil isn't down, changes color for all paths.
]]
function Pencil:color(foreground, background)
    if foreground then
        checkArg(1, foreground, "number")
        self.foreground = foreground
    end
    if background then
        checkArg(2, background, "number")
        self.background = background
    end

    if not self.isDown then
        for _, path in pairs(self.paths) do
            if path.foreground and foreground then path.foreground = foreground end
            if path.background and background then path.background = background end
        end
    end
end

--[[
Puts pencil down and starts drawing.
@x - the x position (counting from 1)
@y - the y position (counting form 1)
]]
function Pencil:beginPath(x, y)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    if not self.foreground then error("Foreground color wasn't set") end
    if not self.background then error("Background color wasn't set") end

    if self.isDown then error("Path has already begun") end

    self.isDown = true
    self.x = x
    self.y = y
    self.lastDx = 0
    self.lastDy = 0
end

--[[
Ends the path.
]]
function Pencil:endPath()
    if not self.isDown then error("Path hasn't begun") end
    self.isDown = false
end

function Pencil:draw()
    if self.isDown then error("Cannot draw when pencil is down") end

    local offsetX = self.component.posX - 1
    local offsetY = self.component.posY - 1
    local r = self.component.renderTarget
    for _, path in pairs(self.paths) do
        if path.draw then
            if path.background then r.setBackground(path.background) end
            if path.foreground then r.setForeground(path.foreground) end
            if path.dx ~= 0 or path.dy ~= 0 then
                r.fill(path.drawStartX + offsetX, path.drawStartY + offsetY, path.drawLengthX, path.drawLengthY, path.char)
            else
                r.set(path.drawStartX + offsetX, path.drawStartY + offsetY, path.char)
            end
        end
    end
end

function Pencil:left(length)
    self:move(length, -1, 0)
end

function Pencil:right(length)
    self:move(length, 1, 0)
end

function Pencil:up(length)
    self:move(length, 0, -1)
end

function Pencil:down(length)
    self:move(length, 0, 1)
end

--[[
Moves [length] pixels in the specified direction, excluding current positions.
For example, writing pencil:move(1, 1, 0) will draw horizontal line 2 pixels long.
]]
function Pencil:move(length, dx, dy)
    if not self.isDown then error("Pencil isn't down") end
    if type(length) ~= "number" or length < 1 then error("Length must be a positive number") end

    local last = self.paths[#self.paths]

    local jointRequired = self.lastDx ~= 0 and math.abs(self.lastDx) - math.abs(dx) ~= 0 or self.lastDy ~= 0 and math.abs(self.lastDy) - math.abs(dy) ~= 0
    if jointRequired then
        -- Path changes direction from vertical to horizontal or the other way around
        local name = ""
        if self.lastDx == 1 and dy == 1 or self.lastDy == -1 and dx == -1 then
            name = "bottomLeft"
        elseif self.lastDx == -1 and dy == 1 or self.lastDy == -1 and dx == 1 then
            name = "bottomRight"
        elseif self.lastDx == 1 and dy == -1 or self.lastDy == 1 and dx == -1 then
            name = "topLeft"
        elseif self.lastDx == -1 and dy == -1 or self.lastDy == 1 and dx == 1 then
            name = "topRight"
        else
            error("No joint matching for dx=" .. tostring(dx) .. ", dy=" .. tostring(dy) .. ", lastDx=" .. tostring(self.lastDx) .. ", lastDy=" .. tostring(self.lastDy))
        end

        -- Delete last item from previous path and add a joint item instead
        if last then
            local joint = nil
            if self:isInsideCanvas(last.endX, last.endY) then
                joint = {
                    -- Zeros indicate a single point
                    dx = 0,
                    dy = 0,
                    startX = last.endX,
                    startY = last.endY,
                    endX = last.endX,
                    endY = last.endY,
                    char = PENCIL_MODES[self.mode][name],
                    draw = true
                }
            end

            local shouldRemove = false
            if last.drawLengthX > 1 or last.drawLengthY > 1 then
                -- Shrink path
                last.endX = last.endX - last.dx
                last.endY = last.endY - last.dy
                self:updateDrawData(last)
                if last.drawLengthX == 0 and last.drawLengthY == 0 then
                    -- Last path is empty
                    shouldRemove = true
                end
            else
                -- Previous path is a single pixel (updateDrawData doesn't update length to zero)
                shouldRemove = true
            end

            if shouldRemove then table.remove(self.paths, #self.paths) end

            if joint then
                self:updateDrawData(joint)
                table.insert(self.paths, joint)
            end
        end
    end

    -- Move pencil one pixel in the target direction so the new line won't overlap with existing one
    local startXDelta = jointRequired and dx or 0
    local startYDelta = jointRequired and dy or 0

    local newPath = {
        dx = dx,
        dy = dy,
        -- Pencil start position
        startX = self.x + startXDelta,
        startY = self.y + startYDelta,
        -- Pencil end position, regardles of boundaries
        endX = self.x + dx * length,
        endY = self.y + dy * length,
        foreground = (not last or last.foreground ~= self.foreground) and self.foreground or nil,
        background = (not last or last.background ~= self.background) and self.background or nil,
        char = dx ~= 0 and self.chars.horizontal or self.chars.vertical
    }

    table.insert(self.paths, newPath)
    self:updateDrawData(self.paths[#self.paths])

    self.x = newPath.endX
    self.y = newPath.endY
    self.lastDx = dx
    self.lastDy = dy
end

function Pencil:updateDrawData(path)
    path.draw = self:isInsideCanvas(path.startX, path.startY) or self:isInsideCanvas(path.endX, path.endY)
    if not path.draw then return end

    local drawStartX = math.min(path.startX, path.endX)
    local drawStartY = math.min(path.startY, path.endY)
    local drawEndX = math.max(path.startX, path.endX)
    local drawEndY = math.max(path.startY, path.endY)

    -- Take canvas boundaries into acocunt
    drawStartX = math.max(1, math.min(self.component.width, drawStartX))
    drawStartY = math.max(1, math.min(self.component.height, drawStartY))
    drawEndX = math.max(1, math.min(self.component.width, drawEndX))
    drawEndY = math.max(1, math.min(self.component.height, drawEndY))

    path.drawStartX = drawStartX
    path.drawStartY = drawStartY
    path.drawLengthX = drawEndX - drawStartX + 1
    path.drawLengthY = drawEndY - drawStartY + 1
end

function Pencil:isInsideCanvas(x, y)
    return x >= 1 and x <= self.component.width and y >= 1 and y <= self.component.height
end

return lib
