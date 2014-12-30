package.loaded.gml = nil
package.loaded.gfxbuffer = nil

local wersja = "0.2.4"
local startArgs = {...}

local computer = require("computer")
local component = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local term = require("term")
local gml = require("gml")
local serial = require("serialization")
local gpu = component.gpu

--parametry wrot
local address = nil
local sg = nil
local closeIrisOnIncomming = false

--zmienne techniczne
local dialDialog = false
local timerID = nil
local timerEneriga = nil
local czasDoZamkniecia = 0

local cfgInfo = "\n--Struktura pliku konfiguracyjnego:\nadres sterownika wrot: string,\nAutomatyczne zamykanie przeslony przy polaczeniu przychodzacym: bool"

--funkcja skopiowana z gmlDialogs i przerobiona
local function messageBox(message,buttons, colorb, colorf)
  checkArg(1,message,"string")
  checkArg(2,buttons,"table","nil")
  checkArg(3,colorb,"number","nil")
  checkArg(4,colorf,"number","nil")
  local color_bg = colorb or 0xb4b4b4
  local color_fg = colorf or 0x000000

  local buttons=buttons or {"cancel","ok"}
  local choice

  local lines={}
  message:gsub("([^\n]+)",function(line) lines[#lines+1]=line end)
  local i=1
  while i<=#lines do
    if #lines[i]>26 then
      local s,rs=lines[i],lines[i]:reverse()
      local pos=-26
      local prev=1
      while #s>prev+25 do
        local space=rs:find(" ",pos)
        if space then
          table.insert(lines,i,s:sub(prev,#s-space))
          prev=#s-space+2
          pos=-(#s-space+28)
        else
          table.insert(lines,i,s:sub(prev,prev+25))
          prev=prev+26
          pos=pos-26
        end
        i=i+1
      end
      lines[i]=s:sub(prev)
    end
    i=i+1
  end

  local guiD=gml.create("center","center",30,6+#lines)
  guiD["fill-color-bg"] = color_bg
  --guiD["fill-color-fg"] = color-fg

  local labels={}
  for i=1,#lines do
    labels[i]=guiD:addLabel(2,1+i,26,lines[i])
	labels[i]["text-color"] = color_fg
	labels[i]["text-background"] = color_bg
  end

  local buttonObjs={}

  local xpos=2
  for i=1,#buttons do
    if type(buttons[i])~="string" then error("Tablica musi byc wypelniona typem string",2) end
    if i==#buttons then xpos=-2 end
    buttonObjs[i]=guiD:addButton(xpos,-2,#buttons[i]+2,1,buttons[i],function() choice=buttons[i] guiD.close() end)
    xpos=xpos+#buttons[i]+3
  end

  guiD:changeFocusTo(buttonObjs[#buttonObjs])
  guiD:run()

  return choice
end

if computer.totalMemory() < 1536 * 1024 then
	retu = messageBox("Ten komputer nie spełnia zalecanych wymagan sprzetowych aplikacji (1.5MB RAM). Moga wystapic problemy z dzialaniem aplikacji. Czy chcesz kontynuowac?", {"Tak", "Nie"})
	if retu == "Nie" then 
		error("Za malo pamieci operacyjnej!")
		return
	end
end

local function zapiszPlik()
	local plik = io.open("sgConf.cfg", "w")
	plik:write(serial.serialize(table.pack(address, closeIrisOnIncomming))..cfgInfo)
	plik:close()
end

if not fs.exists(shell.resolve("sgConf.cfg")) or startArgs[1]~=nil then
	address = startArgs[1]
	if address == nil then
		messageBox("Adres sterownika wrot jest nieprawidlowy",{"Zamknij"})
		return
	end
	sg = component.proxy(address)
	if sg==nil then
		messageBox("Adres sterownika wrot jest nieprawidlowy",{"Zamknij"})
		--return
	end
	zapiszPlik()
	if sg==nil then return end
else
	local plik = io.open("sgConf.cfg", "r")
	address, closeIrisOnIncomming = table.unpack(serial.unserialize(plik:read()))
	sg = component.proxy(address)
	if sg == nil then
		messageBox("Adres sterownika wrot jest nieprawidlowy",{"Zamknij"})
		return
	end
end

local function gammaLogo()
	old = gpu.getBackground()
	reso = {gpu.getResolution()}
	gpu.setBackground(0xAB7800)
	gpu.set(-9, 2, " ")
	gpu.set(-8, 3, " ")
	gpu.set(-7, 4, " ")
	gpu.setBackground(old)
end

local function rysujWrota(chevron)
	
end

local function translateBool(boodl)
	if boodl then return "tak"
	else return "nie" end
end

local function separateAddress(addr)
	return string.sub(addr, 1, 4).."-"..string.sub(addr, 5, 7).."-"..string.sub(addr, 8, 9)
end

local function translateState()
	state, chev = sg.stargateState()
	if state=="Idle" then return "Bezczynny" end
	if state=="Dialling" then return "Wybieranie adresu" end
	if state=="Connecting" then return "Otwieranie tunelu" end
	if state=="Connected" then return "Tunel aktywny" end
	if state=="Offline" then return "Offline" end
end

local function translateIrisState()
	if sg.irisState()=="Open" then return "Otwarta" end
	if sg.irisState()=="Opening" then return "Otwieranie" end
	if sg.irisState()=="Closed" then return "Zamknieta" end
	if sg.irisState()=="Closing" then return "Zamykanie" end
	return "Offline"
end

local function translateResponse(res)
	if res=="Malformed stargate address" or res=="bad arguments #1 (string expected, got no value)" then return "Niepoprawny adres wrot!"
	elseif string.sub(res, 1, 23)=="No stargate at address " then return "Brak wrot o adresie "..string.sub(res, 24).."!"
	elseif string.sub(res, 1, 28)=="Not enough chevrons to dial " then return "Te wrota nie obsluguja tunelow miedzywymiarowych"
	else return "Nie mozna otworzyc tunelu!"
	end
end

local function round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function getEnergy()
	--maksymalna energia: 1 023 400 EU
	proc = math.floor(100*(sg.energyAvailable()*20/1000000)+0.5)
	if proc > 100 then proc = 100 end
	procenty = proc.."%"
	eu = string.reverse(tostring(round(sg.energyAvailable(), 0)*20))
	eu2 = ""
	for i=1, string.len(eu) do
		if i%3==0 and i~=0 then 
			eu2 = eu2..string.sub(eu,i,i).." "
		else
			eu2 = eu2..string.sub(eu,i,i)
		end
	end
	eu2 = string.reverse(eu2)
	return procenty.. "  /  "..eu2.." EU"
end

local function przelaczPrzeslone()
	if translateIrisState() == "Otwarta" then
		sg.closeIris()
	elseif translateIrisState() == "Zamknieta" then
		sg.openIris()
	end
end

local lAutomatyczne
local lInfo = {}

local function zmienAZP()
	closeIrisOnIncomming = not closeIrisOnIncomming
	lAutomatyczne["text"] = "Automatyczne przelaczanie przeslony: "..translateBool(closeIrisOnIncomming)
	lAutomatyczne:draw()
end

local res = {gpu.getResolution()}

local function fTimerEnergia()
	computer.pushSignal("energy_reload")
end

local function nowyTunel()
	dialDialog = true
	local gTunel = gml.create("center", res[2]-math.floor((res[2]/3))-3, 60, 9)
	local background = 0xFFD078
	gTunel["fill-color-bg"] = background
	gTunel["border-color-bg"] = background
	local lAdres = gTunel:addLabel("left", 3, 26, "Wprowadz adres docelowy:")
	lAdres["text-background"] = background
	local tAdres = gTunel:addTextField(-2, 3, 12)
	local lCzas = gTunel:addLabel("left", 5, 34, "Wprowadz czas polaczenia[15-300]:")
	lCzas["text-background"] = background
	local tCzas = gTunel:addTextField(-2, 5, 7)
	local lWykryto = gTunel:addLabel("center", 5, 33, "Wykryto polaczenie przychodzace!")
	lWykryto["text-background"] = background
	lWykryto["text-color"] = 0xFF9191
	lWykryto:hide()
	local bZatwierdz = gTunel:addButton(20, 7, 13, 1, "Zatwierdz",
	function()
		if translateState()=="Bezczynny" then
			status, out = pcall(sg.energyToDial, tAdres["text"])
			if status then
				if sg.energyAvailable() > out + 2500 then
					--jest energia
					status2, out2 = pcall(sg.dial, tAdres["text"])
					if status2 then
						if tonumber(tCzas["text"]) then
							if tonumber(tCzas["text"]) > 14 and tonumber(tCzas["text"]) <= 300 then
								czasDoZamkniecia = tonumber(tCzas["text"])
							end
						else
							czasDoZamkniecia = 300
						end
						lInfo[1]["text"] = "<< Polaczenie wychodzace >>"
						lInfo[1]["text-color"] = 0x23DB1D
						lInfo[1]:show()
						lInfo[1]:draw()
						lInfo[2]["text"] = "Zewnetrzny adres: "..separateAddress(sg.remoteAddress())
						lInfo[2]:show()
						lInfo[2]:draw()
						lInfo[3]["text"] = "Zablokowane symbole: 0"
						lInfo[3]:show()
						lInfo[3]:draw()
						os.sleep(1)
						gTunel:close()
					else
						messageBox(translateResponse(out2), {"OK"})
					end
				else
					messageBox("Brak wystarczajacej ilosci energii do wykonania polaczenia", {"OK"})
				end
			else
				messageBox(translateResponse(out), {"Zamknij"})
			end
		elseif 
			translateState()=="Tunel aktywny" then messageBox("Jest już otwarty inny tunel", {"OK"})
			gTunel:close()
		else 
			messageBox("Blad: nie mozna otworzyc tunelu", {"OK"})
			gTunel:close()
		end
	end)
	local bAnuluj = gTunel:addButton(38, 7, 13, 1, "Anuluj",
		function()
			gTunel.close()
		end)
	
	gTunel:addHandler("sgDialIn",
		function()
			os.sleep(0.5)
			lAdres:hide()
			tAdres:hide()
			lCzas:hide()
			tCzas:hide()
			bZatwierdz:hide()
			bAnuluj:hide()
			lWykryto:show()
			gTunel:draw()
			os.sleep(3)
			gTunel.close()
		end)
	gTunel:run()
	dialDialog = false
	gTunel=nil
end

local function nowyTunelCoroutine()
	local cor = coroutine.create(nowyTunel)
	coroutine.resume(cor)
end

local function zamknijTunel()
	if sg.stargateState() == "Connected" then sg.disconnect() end
end


local gui = gml.create(0, 0, res[1], res[2])
local lNazwaProgramu = gui:addLabel("left", 1, 85, "Kontroler Wrot, wersja "..wersja)
local lAdresWrot = gui:addLabel("left", 4, 60, "Adres wrot: "..separateAddress(sg.localAddress()))
lAdresWrot["text-color"] = 0x4F72FF
local lStatusWrot = gui:addLabel("left", 5, 35, "Status wrot: "..translateState())
lStatusWrot["text-color"] = 0x4F72FF
local lStatusPrzeslony = gui:addLabel("left", 6, 90, "Status przeslony: "..translateIrisState())
local lEnergia = gui:addLabel("left", 7, 130, "Dostepna energia: "..getEnergy())
lAutomatyczne = gui:addLabel("left", 8, 41, "Automatyczne przelaczanie przeslony: "..translateBool(closeIrisOnIncomming))
local bAutomatyczne = gui:addButton(58, 8, 9, 1, "Zmien", zmienAZP)
local bPrzeslona = gui:addButton(2,11, 22, 3, "Przelacz przeslone", przelaczPrzeslone)
local bOtworzTunel = gui:addButton(27, 11, 22, 3, "Otworz tunel", nowyTunel)
local bZamknijPolaczenie = gui:addButton(52, 11, 22, 3, "Zamknij tunel", zamknijTunel)
local bWyjscie = gui:addButton("right", 15, 10, 1, "Wyjscie", function() gui:close() end)
lInfo[1] = gui:addLabel(3, 17, 40, "Info1")
lInfo[2] = gui:addLabel(3, 18, 40, "Info2")
lInfo[3] = gui:addLabel(3, 19, 40, "Info3")
for i=1, 3 do lInfo[i]:hide() end

local function odliczanie()
	if czasDoZamkniecia < 0 then
		sg.disconnect()
		event.cancel(timerID)
	else
		minuty = tostring(math.floor(czasDoZamkniecia/60))
		sekundy = tostring(60*((czasDoZamkniecia/60)-math.floor(czasDoZamkniecia/60)))
		if string.len(sekundy)==1 then sekundy = "0"..sekundy end
		lInfo[3]["text"] = "Pozostaly czas: "..minuty..":"..sekundy
		lInfo[3]:draw()
		czasDoZamkniecia = czasDoZamkniecia-1
	end
end

local function eventListener(...)
	local ev = {...}
	if ev[1]=="sgDialIn" then
		if closeIrisOnIncomming then
			coroutine.resume(coroutine.create(function()
				os.sleep(5)
				sg.closeIris()
			end))
		end
		lInfo[1]["text"] = ">> Polaczenie przychodzace <<"
		lInfo[1]["text-color"] = 0xC47300
		lInfo[1]:show()
		lInfo[1]:draw()
		lInfo[2]["text"] = "Zewnetrzny adres: "..separateAddress(sg.remoteAddress())
		lInfo[2]:show()
		lInfo[2]:draw()
		lInfo[3]["text"] = "Zablokowane symbole: 0"
		lInfo[3]:show()
		lInfo[3]:draw()
	elseif ev[1]=="sgDialOut" then
	
	elseif ev[1]=="sgIrisStateChange" then
		lStatusPrzeslony["text"] = "Status przeslony: "..translateIrisState()
		lStatusPrzeslony:draw()
	elseif ev[1]=="sgStargateStateChange" then
		lStatusWrot["text"] = "Status wrot: "..translateState()
		lStatusWrot:draw()
		if ev[3]=="Idle" then
			if closeIrisOnIncomming then
				coroutine.resume(coroutine.create(function()
					os.sleep(1.5)
					sg.openIris()
				end))
			end
			for i=1, 3 do lInfo[i]:hide() end
			event.cancel(timerID)
			czasDoZamkniecia = 0
		elseif ev[3]=="Connected" then
			lInfo[3]["text"] = "Pozostaly czas: "
			lInfo[3]:draw()
			if czasDoZamkniecia==0 then czasDoZamkniecia = 300-4 end
			os.sleep(0.2)
			timerID = event.timer(1, odliczanie, math.huge)
		end
	elseif ev[1] == "sgChevronEngaged" then
		_, chevronNumber = sg.stargateState()
		lInfo[3]["text"] = "Zablokowane symbole: "..chevronNumber
		lInfo[3]:draw()
	elseif ev[1] == "energy_reload" then
		lEnergia["text"] = "Dostepna energia: "..getEnergy()
		lEnergia:draw()
	end
end

event.listen("sgDialIn", eventListener)
event.listen("sgDialOut", eventListener)
event.listen("sgIrisStateChange", eventListener)
event.listen("sgStargateStateChange", eventListener)
event.listen("sgChevronEngaged", eventListener)
event.listen("energy_reload", eventListener)

timerEneriga = event.timer(3, fTimerEnergia, math.huge)
gui:run()
event.cancel(timerEneriga)

event.ignore("sgDialIn", eventListener)
event.ignore("sgDialOut", eventListener)
event.ignore("sgIrisStateChange", eventListener)
event.ignore("sgStargateStateChange", eventListener)
event.ignore("sgChevronEngaged", eventListener)
event.ignore("energy_reload", eventListener)