(function()
 local targets = {}
 local enable_menu = true

 local ci, cl, filesystems, last_error = component.invoke, component.list, {}
 local eeprom, gpu, screen = cl("eeprom", true)(), cl("gpu", true)(), cl("screen", true)()
 for address in cl("screen", true) do if #ci(address, "getKeyboards") > 0 then screen = address end end
 if not gpu or not screen then enable_menu = false end
 for target in string.gmatch(ci(eeprom, "getData"), "([^,]+)") do table.insert(targets, target) end

 local probe = not #targets
 for address in cl("filesystem", true) do
  if address ~= computer.tmpAddress() then
   table.insert(filesystems, address)
   if probe then table.insert(targets, "disk://" .. address .. "/init.lua") end
  end
 end

 local function boot_target(target)
  local code, inet, address = "", cl("internet", true)()
  if string.match(target, "http://") then
   if not inet or not ci(inet, "isHttpEnabled") then error("No internet card available or HTTP disabled", 0) end
   local req, reason = ci(inet, "request", target)
   if not req then error("Failed to issue request: " .. reason, 0) end
   while true do
    local data, reason = req.read()
    if not data then req.close(); if reason then error(reason, 0) end break end
    code = code .. data
   end
  elseif string.match(target, "disk://") then
   local disk, filename = string.match(target, "disk://([%w-]+)([/%g]+)")
   for i, a in ipairs(filesystems) do if string.sub(a, 1, #disk) == disk then address = a end end
   if not address then error("Can't find disk: " .. disk, 0) end
   local file, reason = ci(address, "open", filename)
   if not file then error("Can't open file: "  .. reason, 0) end
   while true do
    local data, reason = ci(address, "read", file, math.huge)
    if not data then ci(address, "close", file); if reason then error(reason, 0) end break end
    code = code .. data
   end
  else
   error("Don't know how to boot: " .. target, 0)
  end
  local init, reason = load(code, "init.lua")
  if not init then error(reason, 0) end
  function computer.getBootAddress() return address end
  return init
 end

 for i, target in ipairs(targets) do
  local ok, result = pcall(boot_target, target)
  if ok then return result else last_error = result end
 end

 if enable_menu then
  if not probe then
   for address in cl("filesystem", true) do
    if address ~= computer.tmpAddress() then
     table.insert(targets, "disk://" .. address .. "/init.lua")
    end
   end
  end
  table.insert(targets, "_")
  ci(gpu, "bind", screen)
  local w, h = ci(gpu, "maxResolution")
  local sel, epos = 1, 1
  while true do
   ci(gpu, "fill", 1, 1, w, h, " ")
   ci(gpu, "set", 1, 1, "Titan BIOS")
   for i, target in ipairs(targets) do
    target = (sel == i and "> " or "  ") .. target
    ci(gpu, "set", 1, i+1, target)
   end
   if last_error then ci(gpu, "set", 1, #targets + 2, "Last error: " .. last_error) end
   local event, addr, char, code = computer.pullSignal()
   if event == "key_down" then
    if char == 13 then
     local ok, result = pcall(boot_target, targets[sel])
     if ok then return result else last_error = result end
    elseif char == 8 then
     targets[sel] = string.sub(targets[sel], 1, -2)
    elseif char == 0 then
     if code == 200 then
      sel = sel - 1
     elseif code == 208 then
      sel = sel + 1
     end
     sel = math.min(math.max(sel, 1), #targets)
    else
     targets[sel] = targets[sel] .. string.char(char)
    end
   end
  end
 end

 error(last_error or "Can't find anything to boot", 0)
end)()()