local Container = dofile("Container.lua")

local json
local EVENTS,C = {}

local entries = {
  rpc= {
--    <label> = {
--      <clientID> = { type=‘tcp’, ip=ip, port=port, funs = { x,y,z } },
--    },
  },
  multicast = {
--    <label> = {
--       <clientID> = { type = ‘udp’, ip = ip, port=port },
--    },
  },
  udp = {
--    <label> = {
--      <clientID> = { type = ‘udp’, ip = ip, port=port },
--    },
  },
}

local function genSym() return tostring({}):match("([%a%d%A]+)$") end
local services = {}    -- Keyd on key
local serviceRegs = {} -- Keyd on id
local function publish(svcs) -- {ttl=s, services={ ip = ip, port=port, prot='rpc', name='ping' }}
  local id,regs = genSym(),{}
  for _,s in pairs(svcs.services) do 
    local key = (s.ip or "")..(s.port or "")..(s.prot or "")..(s.name or "")
    if not services[key] then
      s.id = id
      regs[#regs+1]=s
    end
  end
  if next(regs) then
    serviceRegs[id]={services=regs,flag=false}
    watchServices(id,svcs.ttl or 5)
    notifySubs("published",regs)
    return id
  end
  return 0
end

local function unpublish(id)
  serviceRegs[id]=nil
  local res = {}
  for _,s in ipairs(services) do 
    if s.id ~= id then res[#res+1]=s end
  else
    notifySubs(,"unpublish",s)
  end
  services = res
  return true
end

local function watchServices(id,ttl)
  local ref
  ref = setInterval(function()
      if serviceRegs[id]==nil then clearInterval(ref) 
      else
        if not serviceRegs[id].flag then
          unpublish(id)
        else serviceRegs[id].flag = false end
      end
    end,ttl*1000)
end

local function notifySubs(msg,svcs) -- Tell all subscriber
  for _,s in ipairs(svcs) do
    local subs = getSubscribers(s)
    if next(subs) then
      broadCast({type='msg', service=s})
    end
  end
end

broadCast({type='update', serviceID=serviceID, serviceEntry=serviceEntry},C.peer_port,C.peers)
end
local function pong(id) if serviceRegs[id] then serviceRegs[id].flag=true end end


local function broadCast(event,port,clients)
  event = json.encode(event)
  for _,ip in ipairs(clients) do
    C.udp.send(ip,port,event)
  end
end

local function mergeEntries(entry)
  for typ,e1 in pairs(entry) do
    if not entries[typ] then entries[typ]=e1
    else
      local oe = entries[typ]
      for lbl,e2 in pairs(e1) do
        if not oe[lbl] then oe[lbl]=e2
        else
          local ce = oe[lbl]
          for cl,e3 in pairs(e2) do
            ce[cl]=e3
          end
        end
      end
    end
  end  
end

local DISC = {}
function DISC.update(event,ip,port)  -- Merge entries, overwriting, should use timestamped, from peers
  C:debugf("disc","Update from %s:%s",ip,port)
  mergeEntries(event.entries)
  -- Send ack?
end

local rpcFuns = {}
function rpcFuns.getEntries() return entries end
function rpcFuns.register(entries)
  mergeEntries(entries)
  broadCast({type='update', entries = entries },C.peer_port,C.peers)
  return true 
end

function Container:onInit()
  C = self
  json = C.json
  self.debugFlags.probe     = true
  self.debugFlags.rpc       = true
  self.debugFlags.disc      = true

  local dns = self:readEnv("DNS")
  self.peer_port = tonumber(self:readEnv("PEER_UDP_PORT"))
  self.udp.startListener(self.peer_port,
    function(event,ip,port)
      event = json.decode(event)
      if DISC[event.type] then DISC[event.type](event,ip,port) end 
    end
  )
  self.peers = {}
  self.util.clientsLookup(dns,function(ips) 
      self.peers = ips
      self:debugf("disc","Peers found")
      broadCast({type='update', entries = entries },self.peer_port,self.peers)
    end)

  local rpcPort = self:readEnv("RPC_PORT")
  self.rpc.startListener(rpcPort,rpcFuns)
end

Container.start()