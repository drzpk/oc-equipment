local version = "1.0"
local args = {...}
if args[1] == "version_check" then return version end

--#requires
local fs = require("filesystem")
local term = require("term")
local serialization = require("serialization")
local component = require("component")
local event = require("event")
local component = require("component")
local colors = require("colors")
 
--#variables
local gpu = component.gpu
local config = {}
local reactor = nil
local running = true
local screen = "main"
--#install

local res = {gpu.getResolution()}
 
function install()
  screen = "install"
  term.clear()
  print("Wymagania:")
  print("Monitor 2 poziomu")
  print("Karta graficzne 2 poziomu")
  print("Reaktor podłączony do komputera")
  print("Klawiatura (tylko na czas instalacji, potem opcjonalnie)")
  print()
  print("Wszystkie wymagania są spełnione? (t/n)")
  --21,49
  local result = false
  while not result do
    local name, adress, char, code, player = event.pull("key_down")
    if code == 20 then
      result = true
    elseif code == 49 then
      os.exit()
    else
      print("Zła odpowiedź")
    end
  end
  --set resolution and continue
  gpu.setResolution(80,25)
  gpu.setForeground(0x000000)
  term.clear()
  gpu.setBackground(0x0000BB)
  term.clear()
  gpu.setBackground(0x808080)
  gpu.fill(20,9,40,6," ")
  --term.setCursor(20,9)
  --print("Thank you for downloading")
  term.setCursor(20,10)
  print("OpenReactor")
  term.setCursor(20,11)
  print("Wciśnij OK aby kontynuować")
  term.setCursor(20,12)
  print("Wciśnij Anuluj aby anulować instalację")
  gpu.setBackground(0x008000)
  gpu.fill(20,14,20,1," ")
  term.setCursor(29,14)
  print("OK")
  gpu.setBackground(0x800000)
  gpu.fill(40,14,20,1," ")
  term.setCursor(48,14)
  print("Anuluj")
  local event_running = true
  while event_running do
    local name, address, x, y, button, player = event.pull("touch")
    if x >= 20 and x <= 39 and y == 14 then
      print("ok")
      event_running = false
    elseif x>=40 and x <= 59 and y == 14 then
      os.exit()
    end
  end
  install_pick_reactor()
  set_color_scheme()
  save_config()
  main()
end
 
--#main
 
function main()
  screen = "main"
  gpu.setResolution(80,25)
  read_config()
  reactor = component.proxy(config.reactor)
  event.listen("touch",listen)
  while running do
    if config.auto_power.enabled == true then
      if reactor.getEnergyStored()/10^5<config.auto_power.start_percent then
        reactor.setActive(true)
      elseif reactor.getEnergyStored()/10^5>config.auto_power.stop_percent then
        reactor.setActive(false)
      end
    end
    gpu.setBackground(config.color_scheme.background)
    term.clear()
    draw_menubar()
    if screen == "main" then
      draw_main()
    elseif screen == "config" then
      draw_config()
    end
    os.sleep(0.1)
  end
end
 
--#draw_menubar
 
function draw_menubar()
  term.setCursor(1,1)
  gpu.setBackground(config.color_scheme.menubar.background)
  gpu.setForeground(config.color_scheme.menubar.foreground)
  term.clearLine()
  term.setCursor(1,1)
  term.write("Status: ")
  if reactor.getActive() then
    gpu.setForeground(config.color_scheme.success)
    term.write("Online ")
  else
    gpu.setForeground(config.color_scheme.error)
    term.write("Offline ")
  end
  if config.auto_power.enabled then
    gpu.setForeground(config.color_scheme.menubar.foreground)
    term.write("(")
    gpu.setForeground(config.color_scheme.info)
    term.write("Auto")
    gpu.setForeground(config.color_scheme.menubar.foreground)
    term.write(") ")
  end
  gpu.setForeground(config.color_scheme.menubar.foreground)
  term.write(" Temperatura paliwa: ")
  gpu.setForeground(config.color_scheme.info)
  term.write(round(reactor.getFuelTemperature()).."C ")
  gpu.setForeground(config.color_scheme.menubar.foreground)
  term.write(" Temperatura osłony: ")
  gpu.setForeground(config.color_scheme.info)
  term.write(round(reactor.getCasingTemperature()).."C ")
  term.setCursor(74,1)
  gpu.setForeground(config.color_scheme.menubar.foreground)
  term.write("[")
  gpu.setForeground(config.color_scheme.error)
  term.write("Wyjdź")
  gpu.setForeground(config.color_scheme.menubar.foreground)
  term.write("]")
end
 
--#save_config
 
function save_config()
  local file = io.open("/etc/open-reactors.cfg","w")
  file:write(serialization.serialize(config,false))
  file:close()
end
 
--#read_config
 
function read_config()
  local file = io.open("/etc/open-reactors.cfg","r")
  local c = serialization.unserialize(file:read(fs.size("/etc/open-reactors.cfg")))
  file:close()
  for k,v in pairs(c) do
    config[k] = v
  end
end
 
--#set_color_scheme
 
function set_color_scheme()
  config.color_scheme = {}
  config.color_scheme.background = 0x0000BB
  config.color_scheme.button = 0x606060
  config.color_scheme.button_disabled = 0xC0C0C0
  config.color_scheme.foreground = 0x000000
  config.color_scheme.progressBar = {}
  config.color_scheme.progressBar.background = 0x000000
  config.color_scheme.progressBar.foreground = 0xFFFFFF
  config.color_scheme.menubar={}
  config.color_scheme.menubar.background = 0x000000
  config.color_scheme.menubar.foreground = 0xFFFFFF
  config.color_scheme.success = 0x008000
  config.color_scheme.error = 0x800000
  config.color_scheme.info = 0x808000
  config.auto_power = {}
  config.auto_power.enabled = false
  config.auto_power.start_percent = 15
  config.auto_power.stop_percent = 80
end
 
--#install_pick_reactor
 
function install_pick_reactor()
  gpu.setBackground(0x0000BB)
  term.clear()
  gpu.setBackground(0x808080)
  local reactors = component.list("br_reactor")
  local len = 3
  for k,v in pairs(reactors) do
    if len<#k then
      len = #k
    end
  end
  local s_x = 40-len/2
  local s_y = 13-round(countTable(reactors)/2)
  gpu.fill(s_x-1,s_y-2,len+2,countTable(reactors)+3," ")
  term.setCursor(s_x+9,s_y-2)
  print("Wybierz reaktor")
  local i = s_y
  for k,v in pairs(reactors) do
    term.setCursor(s_x,i)
    print(k)
    i=i+1
  end
  local event_running = true
  while event_running do
    local name, address, x, y, button, player = event.pull("touch")
    print(y-s_y)
    if x>=s_x and x <= s_x+len and y>=s_y and y<= s_y+countTable(reactors) then
      event_running = false
      local i = y-s_y
      for k,v in pairs(reactors) do
        if i == 0 then
          config.reactor = k
        end
        i=i-1
      end
    end
  end
end
 
--#draw_main
 
function draw_main()
  if config.auto_power.enabled then
    gpu.setBackground(config.color_scheme.button)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1,2,69,3," ")
    term.setCursor(22,3)
    term.write("Wyłącz automatyczne przełączanie")
    gpu.setBackground(0x153F3F)
    gpu.fill(67,2,14,3," ")
    term.setCursor(70,3)
    term.write("Konfiguruj")
  else
    gpu.setBackground(config.color_scheme.button)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1,2,69,3," ")
    term.setCursor(22,3)
    term.write("Włącz automatyczne przełączanie")
    gpu.setBackground(0x153F3F)
    gpu.fill(67,2,14,3," ")
    term.setCursor(70,3)
    term.write("Zasilanie")
  end
  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(config.color_scheme.button)
  gpu.fill(1,8,13,3," ")
  gpu.fill(1,14,13,3," ")
  gpu.fill(1,20,13,3," ")
  term.setCursor(1,9)
  term.write("Bufor")
  term.setCursor(2,15)
  term.write("Paliwo")
  term.setCursor(2,21)
  term.write("Reaktywność")
  drawProgressBar(14,8,65,3,reactor.getEnergyStored()/10^7)
  drawProgressBar(14,14,65,3,reactor.getFuelAmount()/reactor.getFuelAmountMax())
  drawProgressBar(14,20,65,3,reactor.getFuelReactivity()/10^2)
  if config.auto_power.enabled then
    gpu.setBackground(config.color_scheme.success)
    gpu.fill(14+65*config.auto_power.start_percent/10^2,8,1,3," ")
    gpu.setBackground(config.color_scheme.error)
    gpu.fill(14+65*config.auto_power.stop_percent/10^2,8,1,3," ")
  end
end
 
--#draw_config
 
function draw_config()
  gpu.setBackground(config.color_scheme.button)
  gpu.fill(5,9,71,9," ")
  gpu.setForeground(0xFFFFFF)
  term.setCursor(36,9)
  term.write("Konfiguruj")
  term.setCursor(35,10)
  term.write("Start: "..config.auto_power.start_percent.."%")
  term.setCursor(36,11)
  term.write("Stop: "..config.auto_power.stop_percent.."%")
  drawProgressBar(8,12,65,3,reactor.getEnergyStored()/10^7)
  gpu.setBackground(config.color_scheme.success)
  gpu.fill(8+65*config.auto_power.start_percent/100,12,1,3," ")
  gpu.setBackground(config.color_scheme.error)
  gpu.fill(8+65*config.auto_power.stop_percent/100,12,1,3," ")
  gpu.setBackground(config.color_scheme.button)
  gpu.setForeground(0xFFFFFF)
  term.setCursor(37+#("Start: "..config.auto_power.start_percent.."%"),10)
  term.write("[")
  gpu.setForeground(config.color_scheme.error)
  term.write("-")
  gpu.setForeground(0xFFFFFF)
  term.write("]  [")
  gpu.setForeground(config.color_scheme.success)
  term.write("+")
  gpu.setForeground(0xFFFFFF)
  term.write("]")
  term.setCursor(38+#("Stop: "..config.auto_power.stop_percent.."#"),11)
  term.write("[")
  gpu.setForeground(config.color_scheme.error)
  term.write("-")
  gpu.setForeground(0xFFFFFF)
  term.write("]  [")
  gpu.setForeground(config.color_scheme.success)
  term.write("+")
  gpu.setForeground(0xFFFFFF)
  term.write("]")
  term.setCursor(5,9)
  term.write("[")
  gpu.setForeground(config.color_scheme.info)
  term.write("powrót")
  gpu.setForeground(0xFFFFFF)
  term.write("]")
end
 
--#drawProgressBar
 
function drawProgressBar(x,y,w,h,percent)
  gpu.setBackground(config.color_scheme.progressBar.background)
  gpu.fill(x,y,w,h," ")
  gpu.setBackground(config.color_scheme.progressBar.foreground)
  gpu.fill(x,y,w*percent,h," ")
end
 
--#listen
 
function listen(name,address,x,y,button,player)
  if x >= 74 and x <= 80 and y == 1 then
    running = false
  end
  if screen == "main" then
    if x >= 70 and y >=2 and x <= 80 and y <= 4 and config.auto_power.enabled ~= true then
      reactor.setActive(not reactor.getActive())
    elseif x >= 1 and y >=2 and x <= 69 and y <= 4 then
      config.auto_power.enabled = not config.auto_power.enabled
      save_config()
    elseif x >= 70 and y >= 2 and x <= 80 and y <= 4 and config.auto_power.enabled then
      screen = "config"
    end
  elseif screen=="config" then
    if x>= 5 and x <= 10 and y == 9 then
      screen="main"
    elseif x >= 37 + #("Start: "..config.auto_power.start_percent.."%") and x <= 40+#("Start: "..config.auto_power.start_percent.."%") and y == 10 and config.auto_power.start_percent ~= 0 then
      config.auto_power.start_percent = config.auto_power.start_percent-1
      save_config()
    elseif x >= 43 + #("Start: "..config.auto_power.start_percent.."%") and x <= 46+#("Start: "..config.auto_power.start_percent.."%") and y == 10 and config.auto_power.start_percent+1 ~= config.auto_power.stop_percent then
      config.auto_power.start_percent = config.auto_power.start_percent+1
      save_config()
    elseif x >= 38 + #("Stop: "..config.auto_power.stop_percent.."%") and x <= 41 + #("Stop: "..config.auto_power.stop_percent.."%") and y == 11 and config.auto_power.stop_percent - 1 ~= config.auto_power.start_percent then
      config.auto_power.stop_percent = config.auto_power.stop_percent - 1
      save_config()
    elseif x >= 44 + #("Stop: "..config.auto_power.stop_percent.."%") and x <= 47 + #("Stop: "..config.auto_power.stop_percent.."%") and y == 11 and config.auto_power.stop_percent ~= 100 then
      config.auto_power.stop_percent = config.auto_power.stop_percent + 1
      save_config()
    end
  end
end
 
--#countTable
 
function countTable(table)
local result = 0
  for k,v in pairs(table) do
    result = result+1
  end
return result
end
 
--#round
 
function round(num,idp)
  local mult = 10^(idp or 0)
  return math.floor(num*mult+0.5)/mult
end
 
--#init
if not fs.exists("/etc/open-reactors.cfg") then
  install()
else
  main()
end
event.ignore("touch",listen)
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.setResolution(res[1], res[2])
term.clear()