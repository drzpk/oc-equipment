-- ###############################################
-- #              SGCX graphics                  #
-- #                                             #
-- #   03.2020                   by: IlynPayne   #
-- ###############################################

--[[
    Template (not a 1:1 copy):
                                                                    ###  |
                                                               /----# #  |
                                                               |    ###  |
   /-----------------------------------------------------------/         |
   |                                                                ###  |
   |  /-------------------------------------------------------------# #  |
   |  |                                                             ###  |
   |  |      /-------------------------------------------------\         |
   |  |      |                                                 |    ###  |
   |  |      |             /-------------------------------\   \----# #  |
   |  |      |             |                               |        ###  |
   |  |      |     #######@@@#######                       |             |
   |  |      | #####       |       #####                   |        ###  |
   |  |      @@@           |           @@@-------------\   \--------# #  |
   |  |    #@@             |             @@#           |            ###  |
   |  |   ##               |                ##         |                 |
   |  |  ##               ###               ##         |            ###  |
   |  | ##                ###                ##        \------------# #  |
   |  | ##                                   ##                     ###  |
   |  \-@@                 #                 @@---------------\          |
   |    @@                ###                @@               |     ###  |
   |    ##               ## ##               ##               \-----# #  |
   |    ##              ##   ##              ##                     ###  |
   |    ##             ##     ##             ##                          |
   |     ##           ##       ##           ##                      ###  |
   |      @@               |               @@                 /-----# #  |
   \-------@@#             |             #@@------------------/     ###  |
             ###           |           ###                               |
               #####       |       #####                            ###  |
                   #@@@####=####@@@#                          /-----# #  |
                     |           |                            |     ###  |
                     |           \----------------------------/          |
                     |                                              ###  |
                     \----------------------------------------------# #  |
                                                                    ###  |
                                                                         |
--------------------------------------------------------------------------

]]


local version = "1.0"
local startArgs = {...}
if startArgs[1] == "version_check" then return version end

-- Imports
package.loaded.color_grid = nil
local gml = require("gml")
local colorGrid = require("color_grid")

-- Constants
local SYMBOLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local COLORS = {
    frame = 0x333333,
    activeChevron = 0xff6600,
    iris = 0xb4b4b4,
    eventHorizon = 0x4086FF,
    box = 0x333333,
    lineActive = 0xff0000,
    lineInactive = 0x330000,
    text = 0xffffff
}
local graphics = {}

graphics.createStargateComponent = function (gui, startX, startY)
    local backgroundColor = gml.api.findStyleProperties(gui, "fill-color-bg")

    local stargateWidth = 40
    local stargateHeight = 20
    local stargateXOffset = 5
    local stargateYOffset = 10
    local totalWidth = 68
    local totalHeight = 35
    local boxesXOffset = 63
    local boxesYOffset = 0
    local stargate = gml.api.baseComponent(gui, startX, startY, totalWidth, totalHeight, "stargate", false)

    stargate.symbolIndex = 0
    stargate.shouldDraw = true
    stargate.onIrisOpened = function (t)
        t.irisClosed = false
        t:fill()
    end
    stargate.onIrisClosed = function (t)
        t.irisClosed = true
        t:fill()
    end
    stargate.onConnected = function (t, remoteAddress)
        t.connected = true
        t:fill()

        if remoteAddress and t.symbolIndex == 0 then
            -- No symbols were locked, do all necessary drawing
            for i = 1, #remoteAddress do
                t.lockSymbol(t, i, remoteAddress:sub(i, i), true)
            end
        end
    end
    stargate.onDisconnected = function (t)
        t.connected = false
        t:fill()
        t:lockSymbol(0)
    end
    stargate.onSymbolLocked = function (t, symbolNo, symbolLetter)
        t:lockSymbol(symbolNo, symbolLetter)
    end
    stargate.suspendDrawing = function (t)
        t.shouldDraw = false
    end
    stargate.activateDrawing = function (t)
        t.shouldDraw = true
        if t.redrawRequired then
            t:draw()
            t.redrawRequired = false
        end
    end

    stargate.pencils = {}
    for i = 1, 9 do
        table.insert(stargate.pencils, colorGrid.pencil(colorGrid.pencilMode.BOLD, gui, startX, startY + 1, totalWidth - 3, totalHeight - 2))
        stargate.pencils[i]:color(COLORS.lineInactive, backgroundColor)
    end

    stargate.draw = function (t)
        if t:isHidden() then return end
        if not t.shouldDraw then
            t.redrawRequired = true
            return
        end

        local subdraw = function (x, y, vx, vy)
            for i = 0, 3 do
                t.renderTarget.set(x, y + 6 * vy + i * vy, ' ')
                t.renderTarget.set(x + 1 * vx, y + 6 * vy + i * vy, ' ')
            end
            t.renderTarget.set(x + 1 * vx, y + 5 * vy, ' ')
            t.renderTarget.set(x + 2 * vx, y + 5 * vy, ' ')
            t.renderTarget.set(x + 2 * vx, y + 4 * vy, ' ')
            t.renderTarget.set(x + 3 * vx, y + 4 * vy, ' ')
            t.renderTarget.set(x + 3 * vx, y + 3 * vy, ' ')
            t.renderTarget.set(x + 4 * vx, y + 3 * vy, ' ')
            t.renderTarget.set(x + 5 * vx, y + 3 * vy, ' ')
            t.renderTarget.set(x + 5 * vx, y + 2 * vy, ' ')
            t.renderTarget.set(x + 6 * vx, y + 2 * vy, ' ')
            t.renderTarget.set(x + 7 * vx, y + 2 * vy, ' ')
            for i = 0, 4 do
                t.renderTarget.set(x + 7 * vx + i * vx, y + 1 * vy, ' ')
            end
            for i = 0, 8 do
                t.renderTarget.set(x + 11 * vx + i * vx, y, ' ')
            end
        end

        t.renderTarget.setBackground(COLORS.frame)
        subdraw(t.posX + stargateXOffset, t.posY + stargateYOffset, 1, 1)
        subdraw(t.posX + stargateWidth - 1 + stargateXOffset, t.posY + stargateYOffset, -1, 1)
        subdraw(t.posX + stargateXOffset, t.posY + stargateHeight - 1 + stargateYOffset, 1, -1)
        subdraw(t.posX + stargateWidth - 1 + stargateXOffset, t.posY + stargateHeight - 1 + stargateYOffset, -1, -1)

        t:drawBoxes()

        t.visible = true
    end
    stargate.drawBoxes = function (t)
        t.renderTarget.setBackground(COLORS.box)
        for i = 0, 8 do
            t.renderTarget.fill(t.posX + boxesXOffset, t.posY + boxesYOffset + i * 4, 5, 3, ' ')
        end
        t.renderTarget.setBackground(backgroundColor)
        for i = 0, 8 do
            t.renderTarget.fill(t.posX + boxesXOffset + 1, t.posY + boxesYOffset + i * 4 + 1, 3, 1, ' ')
        end
    end
    stargate.fill = function (t)
        if not t.shouldDraw then
            t.redrawRequired = true
            return
        end
        if t.irisClosed then
            t:doFill(COLORS.iris)
        elseif t.connected then
            t:doFill(COLORS.eventHorizon)
        else
            t:doFill(backgroundColor)
        end
    end
	stargate.doFill = function (t, hex)
		local subfill = function (sy, vy)
			t.renderTarget.fill(t.posX + stargateXOffset + 12, sy + 1 * vy, 16, 1, ' ')
			t.renderTarget.fill(t.posX + stargateXOffset + 8, sy + 2 * vy, 24, 1, ' ')
			t.renderTarget.fill(t.posX + stargateXOffset + 6, sy + 3 * vy, 28, 1, ' ')
			t.renderTarget.fill(t.posX + stargateXOffset + 4, sy + 4 * vy, 32, 1, ' ')
			t.renderTarget.fill(t.posX + stargateXOffset + 3, sy + 5 * vy, 34, 1, ' ')
		end
		t.renderTarget.setBackground(hex)
		subfill(t.posY + stargateYOffset, 1)
		t.renderTarget.fill(t.posX + stargateXOffset + 2, t.posY + stargateYOffset + 6, 36, 8, ' ')
		subfill(t.posY + stargateYOffset + stargateHeight - 1, -1)
	end
    stargate.lockSymbol = function (t, number, symbolLetter, hideChevrons)
        if not t.shouldDraw then
            t.redrawRequired = true
            return
        end
		if (number >= 1 and t.symbolIndex == 0) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
			t.renderTarget.fill(t.posX + 2 + stargateXOffset, t.posY + 15 + stargateYOffset, 2, 1, ' ')
            t.renderTarget.fill(t.posX + 3 + stargateXOffset, t.posY + 16 + stargateYOffset, 2, 1, ' ')
            stargate.pencils[1]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[1]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 1, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 1
		end
		if (number >= 2 and t.symbolIndex == 1) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
            t.renderTarget.fill(t.posX + stargateXOffset, t.posY + 8 + stargateYOffset, 2, 2, ' ')
            stargate.pencils[2]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[2]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 5, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 2
		end
		if (number >= 3 and t.symbolIndex == 2) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
			t.renderTarget.fill(t.posX + 5 + stargateXOffset, t.posY + 2 + stargateYOffset, 3, 1, ' ')
            t.renderTarget.fill(t.posX + 4 + stargateXOffset, t.posY + 3 + stargateYOffset, 2, 1, ' ')
            stargate.pencils[3]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[3]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 9, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 3
		end
		if (number >= 4 and t.symbolIndex == 3) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
            t.renderTarget.fill(t.posX + 18 + stargateXOffset, t.posY + stargateYOffset, 4, 1, ' ')
            stargate.pencils[4]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[4]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 13, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 4
		end
		if (number >= 5 and t.symbolIndex == 4) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
			t.renderTarget.fill(t.posX + 32 + stargateXOffset, t.posY + 2 + stargateYOffset, 3, 1, ' ')
            t.renderTarget.fill(t.posX + 34 + stargateXOffset, t.posY + 3 + stargateYOffset, 2, 1, ' ')
            stargate.pencils[5]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[5]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 17, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 5
		end
		if (number >= 6 and t.symbolIndex == 5) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
            t.renderTarget.fill(t.posX + 38 + stargateXOffset, t.posY + 8 + stargateYOffset, 2, 2, ' ')
            stargate.pencils[6]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[6]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 21, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 6
		end
		if (number >= 7 and t.symbolIndex == 6) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
			t.renderTarget.fill(t.posX + 35 + stargateXOffset, t.posY + 16 + stargateYOffset, 2, 1, ' ')
            t.renderTarget.fill(t.posX + 36 + stargateXOffset, t.posY + 15 + stargateYOffset, 2, 1, ' ')
            stargate.pencils[7]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[7]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 25, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 7
		end
		if (number >= 8 and t.symbolIndex == 7) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
            t.renderTarget.fill(t.posX + 24 + stargateXOffset, t.posY + 19 + stargateYOffset, 4, 1, ' ')
            stargate.pencils[8]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[8]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 29, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 8
		end
		if (number == 9 and t.symbolIndex == 8) or number == 0 then
			t.renderTarget.setBackground(number == 0 and COLORS.frame or COLORS.activeChevron)
            t.renderTarget.fill(t.posX + 12 + stargateXOffset, t.posY + 19 + stargateYOffset, 4, 1, ' ')
            stargate.pencils[9]:color(number == 0 and COLORS.lineInactive or COLORS.lineActive, nil)
            stargate.pencils[9]:draw()
            t.renderTarget.setBackground(backgroundColor)
            t.renderTarget.setForeground(COLORS.text)
            t.renderTarget.set(t.posX + boxesXOffset + 2, t.posY + boxesYOffset + 33, number == 0 and ' ' or symbolLetter)
			t.symbolIndex = 9
        end

        t:fill()
        if number == 0 then 
            t.symbolIndex = 0    
        elseif not hideChevrons then
            -- Draw a chevron
            local index = SYMBOLS:find(symbolLetter:sub(1, 1):upper())
            if not index then
                print('no index')
                return
            end

            local symbol = graphics.symbols[index + 1]
            local grid = colorGrid.grid({
                ["#"] = COLORS.activeChevron
            })

            for _, s in pairs(symbol) do
                grid:line(s)
            end

            local sx = startX + stargateXOffset + math.floor(stargateWidth / 2)
            local sy = startY + stargateYOffset + math.floor(stargateHeight / 2)
            grid:draw(t.renderTarget, sx, sy, true)
        end
    end

    -- Below are lines connecting stargate to chevron boxes

    -- 1st chevron
    stargate.pencils[1]:beginPath(stargateXOffset + 3, stargateYOffset + stargateHeight - 4)
    stargate.pencils[1]:left(7)
    stargate.pencils[1]:up(23)
    stargate.pencils[1]:right(59)
    stargate.pencils[1]:up(2)
    stargate.pencils[1]:right(3)
    stargate.pencils[1]:endPath()

    -- 2nd chevron
    stargate.pencils[2]:beginPath(stargateXOffset, stargateYOffset + 9)
    stargate.pencils[2]:left(1)
    stargate.pencils[2]:up(14)
    stargate.pencils[2]:right(59)
    stargate.pencils[2]:endPath()

    -- 3rd chevron
    stargate.pencils[3]:beginPath(stargateXOffset + 5, stargateYOffset + 2)
    stargate.pencils[3]:up(5)
    stargate.pencils[3]:right(50)
    stargate.pencils[3]:down(2)
    stargate.pencils[3]:right(3)
    stargate.pencils[3]:endPath()

    -- 4th chevron
    stargate.pencils[4]:beginPath(stargateXOffset + 20, stargateYOffset - 1)
    stargate.pencils[4]:up(1)
    stargate.pencils[4]:right(31)
    stargate.pencils[4]:down(5)
    stargate.pencils[4]:right(7)
    stargate.pencils[4]:endPath()

    -- 5th chevron
    stargate.pencils[5]:beginPath(stargateXOffset + stargateWidth - 4, stargateYOffset + 2)
    stargate.pencils[5]:right(11)
    stargate.pencils[5]:down(5)
    stargate.pencils[5]:right(11)
    stargate.pencils[5]:endPath()

    -- 6th chevron
    stargate.pencils[6]:beginPath(stargateXOffset + stargateWidth + 1, stargateYOffset + 9)
    stargate.pencils[6]:right(14)
    stargate.pencils[6]:down(2)
    stargate.pencils[6]:right(3)
    stargate.pencils[6]:endPath()

    -- 7th chevron
    stargate.pencils[7]:beginPath(stargateXOffset + stargateWidth - 2, stargateYOffset + 16)
    stargate.pencils[7]:right(17)
    stargate.pencils[7]:up(1)
    stargate.pencils[7]:right(3)
    stargate.pencils[7]:endPath()

    -- 8th chevron
    stargate.pencils[8]:beginPath(26 + stargateXOffset, stargateYOffset + stargateHeight)
    stargate.pencils[8]:down(1)
    stargate.pencils[8]:right(29)
    stargate.pencils[8]:up(2)
    stargate.pencils[8]:right(3)
    stargate.pencils[8]:endPath()

    -- 9th chevron
    stargate.pencils[9]:beginPath(14 + stargateXOffset, stargateYOffset + stargateHeight)
    stargate.pencils[9]:down(3)
    stargate.pencils[9]:right(44)
    stargate.pencils[9]:endPath()

    gui:addComponent(stargate)

    return stargate
end

-- https://stargate.fandom.com/wiki/Glyph
graphics.symbols = {
    [1] = { -- Point of origin
        "    ###",
        "    ###",
        "",
        "     #",
        "    ###",
        "   ## ##",
        "  ##   ##",
        " ##     ##",
        "##       ##"
    },
    [2] = { -- Crater
        "   ########",
        "   ##    ##",
        "   ##   ##",
        "    #####",
        "   ##   ##",
        "  ##     ##",
        " ##       ##",
        "  ##      ##",
        "####      ####"
    },
    [3] = { -- Virgo
        "     #####   #####",
        "   ##      ####",
        "  ## #  #####",
        "   #######",
        "   ##  ##",
        "   ######",
        "  ###    ####",
        " ###       ####### ",
        "####"
    },
    [4] = { -- Bootes
        "     #####",
        "  #####",
        "### ##",
        "     ##",
        "      ##",
        "        ##",
        "          ###",
        "           #  #",
        "            ####"
    },
    [5] = { -- Centaurus
        "       ####",
        "        ##",
        "       ##",
        "  #   ##",
        "  ###### ",
        " #  #  ##",
        "  ##    ##",
        "# #      ##",
        " #       ####"
    },
    [6] = { -- Libra
        "         ###",
        "   #######",
        "  # ##",
        " #  ##",
        "#   ##",
        "#   ##        ##",
        " #  ##    ######",
        "  # ## ###",
        "   #####"
    },
    [7] = { -- Serpens Caput
        "             ####",
        "              ##",
        "             ##",
        "     ####   ##",
        "     #   ###",
        "   ######",
        "  ##",
        " ##",
        "####"
    },
    [8] = { -- Norma
        "##",
        "#  ##",
        "#    ##",
        "#  ##",
        "##         ##",
        "           #  ##",
        "           #    ##",
        "           #  ##",
        "           ##"
    },
    [9] = { -- Scorpious
        "          #######",
        "         ##     ##",
        "         ##    ##",
        "         ##    #",
        "#####   ##",
        " ###   ##",
        " #######",
        " ###",
        "#####"
    },
    [10] = { -- Corona Australis
        "      ##",
        "    ##  ##",
        "    ########",
        "        #####",
        "            ##",
        " #          ##",
        "# #      #####",
        "### #########",
        "    #####"
    },
    [11] = { -- Scutum
        "  #",
        "  ##",
        " #  #",
        " #  #  ##",
        "#    #  ##",
        "######",
        "     ###",
        "      ###",
        "       ####"
    },
    [12] = { --Sagitarius
        "           ###",
        "           #####",
        " ###           ##",
        "#  #           ##",
        "#  #           ##",
        "#  #   ###     ##",
        "#############  ##",
        "       ##   ####",
        "        ##"
    },
    [13] = { -- Aqulia
        "  ###",
        "  ##",
        " ##",
        "###",
        "   ####  #",
        "      ####",
        "   ####  #",
        "####",
        "##"
    },
    [14] = { -- Microscopium
        " ####",
        "  ##       ###",
        "  ##       #  #",
        " ##        ###",
        " ##              #",
        " ##         ######",
        "##     ######    #",
        "########",
        "###"
    },
    [15] = { -- Capricornus
        "    ####",
        "   ##  ###",
        "   ##    ###",
        "  ##       ##",
        "  ##        ##",
        " ##          ##",
        " ###################",
        "##                ##",
        "##"
    },
    [16] = { -- Piscis Austrinus
        "",
        "           #########",
        "     ########    #  ##",
        " #####           #   ##",
        "##               #    ##",
        " ######          #   ##",
        "     ######      #  ##",
        "          ##########",
        ""
    },
    [17] = { -- Equuleus
        "####",
        "#######  ##",
        " ##   #####",
        "  ##",
        "   ##",
        "    ##",
        "     ##   ####",
        "      ########",
        "        ##"
    },
    [18] = { -- Aquarius
        "          ####",
        "           ##",
        "            ##",
        "             ###",
        "     ####    ##",
        "       ###  ##",
        "#        #####",
        "###########",
        "#"
    },
    [19] = { -- Pegasus
        "",
        "          #      #####",
        "   ##########   ###",
        " ###      #######    ###",
        "              ###     ###",
        "  ##############",
        " ##",
        "###",
        ""
    },
    [20] = { -- Sculptor
        "           ####",
        "            ##",
        "           ##",
        "          ##",
        "         ##",
        "#####   ###",
        "#    #####",
        " #  ###",
        "  ###"
    },
    [21] = { -- Pisces
        "               ###",
        " ###     ########",
        "##  ######    ##",
        " ###          ##",
        "             ##",
        "             ##",
        "             ##",
        "           ###",
        "            ###"
    },
    [22] = { -- Andromeda
        "",
        "",
        "         ##      #   ##",
        "    ##################",
        "  #####          #   ##",
        "##############",
        "            ###",
        "",
        ""
    },
    [23] = { -- Triangulum
        "#####",
        "##  ###",
        " ##   ###",
        " ##     ###",
        "  ##      ##",
        "  ##     ##",
        "   ##   ##",
        "   ##  ##",
        "   #####"
    },
    [24] = { -- Aries
        "",
        "",
        "",
        "#                  #",
        "#########  #########",
        "#      ######      #",
        "",
        "",
        ""
    },
    [25] = { -- Perseus
        " ###",
        "#####",
        " #  ###",
        "     ###",
        "        ######",
        "            ####",
        "##          #  #",
        "######      #  #",
        "     ############"
    },
    [26] = { -- Cetus
        "#",
        "######",
        "     ####",
        "       #######",
        "       ##    ##",
        "      ##      ##",
        "      ##      ##",
        "      ##  #####",
        "     ######"
    },
    [27] = { -- Taurus
        "",
        "",
        "                   #",
        "#         ##########",
        "###########",
        "#       ####",
        "           ##########",
        "",
        ""
    },
    [28] = { -- Auriga
        "       ##",
        "####  ####",
        " ##",
        " ##       ####",
        " ##        ##",
        " ##        ##",
        " ###      ##",
        "###########",
        " ###"
    },
    [29] = { -- Eridanus
        "",
        "",
        "                    #",
        "         #####  #  ###",
        "        ##  ########",
        "###   #####",
        "  #####",
        "",
        ""
    },
    [30] = { -- Orion
        " #########",
        "  ##     ######",
        "   ##      ##",
        "   ##     ##",
        "     ######",
        "  ###     ##",
        " ##       ##",
        "######     ##",
        "     #######"
    },
    [31] = { -- Canis Minor
        "     ######",
        " #####   ##",
        "  ##    ##",
        "   ##  ##",
        "     ##",
        "   ##  ##",
        "  ##    ##",
        " ##   #####",
        "#######"
    },
    [32] = { -- Monoceros
        "",
        "              ####",
        "#####      #####  ###",
        "    ##   #####      ##",
        "   ########          ###",
        "###  ##",
        " #  ##",
        "  ###",
        ""
    },
    [33] = { -- Gemini
        "                 ###",
        "                ##",
        " #################",
        " ##             ##",
        "###             ##",
        " ##             ##",
        " #################",
        " ##             ###",
        ""
    },
    [34] = { -- Hydra
        "",
        "###",
        "##",
        " ####   #",
        "   ###### # ##",
        "            ###",
        "              ###",
        "                ##",
        ""
    },
    [35] = { -- Lynx
        "",
        "",
        "",
        "    #########       ##",
        "######    ####    ####",
        "             #######",
        "",
        "",
        ""
    },
    [36] = { -- Cancer
        " ##",
        "####",
        "        ####",
        "       ###",
        "      ##",
        "      ##",
        "     ##",
        "     ##",
        "   #####"
    },
    [37] = { -- Sextans
        "    ####",
        "     ##",
        "",
        "     ##",
        "####",
        "  ###",
        "    ###",
        "     ###",
        "     #####"
    },
    [38] = { -- Leo Miner
        " ###",
        "####",
        "   ###",
        "     ###",
        "       ###",
        "          ####",
        "             ####   #",
        "                #####",
        "                    #"
    },
    [39] = { -- Leo
        "        ##",
        "       #####",
        "      ##   ##",
        "###   ##    ##",
        "########     ##",
        "       ##     ##",
        "        ##     ##",
        "       ####     ###",
        "                #####"
    }
}

return graphics