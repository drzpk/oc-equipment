--         Hologram Viewer
-- by NEO, Totoro (aka MoonlightOwl)
-- 11/12/2014, all right reserved =)

local version = "0.60 Beta"
 
local fs = require('filesystem')
local com = require('component')
local args = { ... }
if args == "version_check" then return version
elseif args[1] == "-c" then
	if com.isAvailable("hologram") then com.hologram.clear() end
	return
end
 
-- ================================ H O L O G R A M S   S T U F F ================================ --
-- loading add. components
function trytofind(name)
  if com.isAvailable(name) then
    return com.getPrimary(name)
  else
    return nil
  end
end
 
-- constants
HOLOH = 32
HOLOW = 48
 
-- hologram vars
holo = {}
colortable = {{},{},{}}
hexcolortable = {}
proj_scale = 1.0
 
function set(x, y, z, value)
  if holo[x] == nil then holo[x] = {} end
  if holo[x][y] == nil then holo[x][y] = {} end
  holo[x][y][z] = value
end
function get(x, y, z)
  if holo[x] ~= nil and holo[x][y] ~= nil and holo[x][y][z] ~= nil then
    return holo[x][y][z]
  else
    return 0
  end
end
function rgb2hex(r,g,b)
  return r*65536+g*256+b
end
 
function loadHologram(filename)
  if filename == nil then
    error("[ERROR] Wrong file name.")
    return false
  end
  if string.sub(filename, -3) ~= '.3d' then
    filename = filename..'.3d'
  end
  if fs.exists(filename) then
    file = io.open(filename, 'rb')
    -- load palette
    for i=1, 3 do
      for c=1, 3 do
        colortable[i][c] = string.byte(file:read(1))
      end
      hexcolortable[i] = rgb2hex(colortable[i][1], colortable[i][2], colortable[i][3])
    end
    -- load voxel array
    holo = {}
    for x=1, HOLOW do
      for y=1, HOLOH do
        for z=1, HOLOW, 4 do
          byte = string.byte(file:read(1))
          for i=0, 3 do
            a = byte % 4
            byte = math.floor(byte / 4)
            if a ~= 0 then set(x,y,z+i, a) end
          end
        end
      end
    end
    file:close()
    print("Plik załadowany pomyślnie")
    return true
  else
    error("[BŁĄD] Plik "..filename.." nie został znaleziony.")
    return false
  end
end
 
function scaleHologram(scale)
  if scale == nil or scale<0.33 or scale>4 then
    error("[BŁĄD] Skala hologramu musi znadować się w zakresie [0.33, 4.00].")
  end
  proj_scale = scale
end
 
function drawHologram()
  -- check hologram projector availability
  h = trytofind('hologram')
  if h ~= nil then
    local depth = h.maxDepth()
    -- clear projector
    h.clear()
    -- set projector scale
    h.setScale(proj_scale)
    -- send palette
    if depth == 2 then
      for i=1, 3 do
        h.setPaletteColor(i, hexcolortable[i])
      end
    else
      h.setPaletteColor(1, hexcolortable[1])
    end
    -- send voxel array
    for x=1, HOLOW do
      for y=1, HOLOH do
        for z=1, HOLOW do
          n = get(x,y,z)
          if n ~= 0 then
            if depth == 2 then
              h.set(x,y,z,n)
            else
              h.set(x,y,z,1)
            end
          end
        end
      end      
    end
    print("Zrobione.")
  else
    error("[BŁĄD] Nie znaleziono projektora.")
  end
end
-- =============================================================================================== --
 
-- Main part
loadHologram(args[1])
 
if args[2] ~= nil then
  scaleHologram(tonumber(args[2]))
end
 
drawHologram()