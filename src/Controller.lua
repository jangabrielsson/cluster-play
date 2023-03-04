local util = dofile("Container.lua")

local C,json

function Container:started()
  self:debugf("app","Starting up")
end

function Container:ready(state)
  if state then self:debugf("app","Ready") 
  else self:debugf("app","Not ready") end
end

local clients = {}

local commands = {
  ['help'] = function(arg)
    return
[[ 
Controller:
- list [containers | regions]
- restart [all | <region>]
- lua -<containername> <lua expression>
]]
  end,
  ['ping'] = function(str,what)
    C:broadCast({type="ping"})
  end,
  ['list'] = function(str,what)
    what = what or ""
    if ("containers"):match("^"..what) then
      C:broadCast({type="containerQuery"})
      return C.json.encode(clients)
    elseif ("regions"):match("^"..what) then
      C:broadCast({type="regionQuery"})
    else return "Unknown argument:"..tostring(what) end 
  end,
  ['lua'] = function(str,_)
    local name,lua = str:match("^lua%s+%-([%w_%-]+)%s+(.*)")
    if not name then
      name = '.*'
      lua = str:match("^lua%s+(.*)")
    else name = "^"..name end
    C:broadCast({type='lua',str=lua},name)
  end,
  ['restart'] = function(str,reg)
    local r = tonumber(reg)
    if r then 
      C:broadCast({type="restart",region=r})
    else return "Unknown argument:"..tostring(reg) end
  end
}

function Container:onInit()
  C,json = self,self.json
  print("onInit")
  local cli_port = 8712
  self.debugFlags.app  = true
  self.debugFlags.disc = true
  self.debugFlags.rpc  = false

  local rpcPort = self:readEnv("RPC_PORT")

  self.disc = self:startDiscovery(self:readEnv("DISC_ENDPOINT"))

  self.disc:subscribe({"rpc://.-:.-/LCMfuns"},function(ep)
        local client = self:clientLink(ep,{reconnect=true,name="Pinger"})
        local i = 42
        function client:opened(pipe)
          while true do
            C:debugf('app',"ping:%d -> %s",i,pipe:call("ping",i))
            i=i+1
            C:wait(1)
          end
        end
        function client:closed(pipe) end
      end)

  self.tcpliner.startListener(cli_port,
    function(data)
      local args = {}
      data:gsub("([%w_]+)",function(w) args[#args+1]=w end)
      if args[1] and commands[args[1]] then return commands[args[1]](data,select(2,table.unpack(args))) or "ok"
      else return "Unknown command: "..data end
    end)

end

Container.start()