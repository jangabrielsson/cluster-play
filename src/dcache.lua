local Container = dofile("ContainerBase.lua")

--[[
Container.id = <name DNS>,
Container.state = <state>,                -- Internal Container states: loaded, starting, started, ready, notready
Container.region = <number>,              -- Restart region , if any

Container.srvinit.mcevents_lcm = true,    -- Responds to controller lcm events.
Container.srvinit.mcevents = true,        -- Listen to multicast events
Container.srvinit.rpc = true,             -- Listen to rpc

function Container:ready(bool)        -- Called when Container ready      - override if wanted
function Container:startup()          -- Called when Container at startup - override if wanted
function Container:setReady(bool)     -- Sets liveness probe status 

Container.probes.startupdelay = 1
Container.probes.readinessdelay = 2
Container.probes.readyinterval = 4
Container.probes.notreadyinterval = 0 -- 20

Container.rpc.*
Container.mcevent.*
Container.event.*

function Container:debugf(dbgflag,fmt,...)
--]]

local C,broadCast,discoverPeers,serviceName
local multicast = true 

function Container:startup()
  self:debugf("app","Starting up")
end

function Container:ready(state)
  if state then 
    self:debugf("app","Ready") 
    setTimeout(function() discoverPeers(serviceName) end,0)
  else 
    self:debugf("app","Not ready") 
  end
end

local function peersLookup(svc,callback)
  local _,w = C.socket.dns.toip(svc)
  if type(w)=='table' then callback(w.ip) -- Repeat until we succeed
  else setTimeout(function() peersLookup(svc,callback) end,2000) end
end

local peers,values={},{}
function discoverPeers(service)
  if not Container.peersDiscovered then 
    peersLookup(service,
      function(res)
        C:debugf("disc","DNS discovery")
        for _,ip in ipairs(res) do
          if ip ~= os.ipAddress() then
            Container:debugf("disc","peer %s",ip) 
            peers[ip]=true
          end
        end
        C.peersDiscovered = true
        res = broadCast('peer',os.ipAddress())
        if res[1] then values = res[1] end
      end)
  end
end

function broadCast(fun,...)
  local args,res = {...},{}
  local function call(ip)
    res[#res+1]=C.rpc.call(ip,C.rpc.port,fun)(table.unpack(args))
  end
--  setTimeout(function() 
  for ip,_ in pairs(peers) do
    local stat,_ = pcall(call,ip) 
    if not stat then
      C:debugf("disc","peer %s removed (unresponsive)",ip)
      peers[ip]=nil 
    end
  end
--    end,0)
  return res
end

function Container:onInit()
  C = self
  self.debugFlags.contevent = true
  self.debugFlags.probe     = true
--  self.debugFlags.web     = true
  self.debugFlags.rpc       = true
  self.debugFlags.disc      = true
  self.debugFlags.cache     = true
  self.debugFlags.app       = true
  self.debugFlags.mcevent   = true
  self.debugFlags.multicast = true

  serviceName = os.getenv("SERVICE_NAME") or "dcache-headless.default.svc.cluster.local"

  self:debugf("app","Container onInit")
  self:debugf("app","Service name is %s",serviceName)
  self:debugf("app","name:         %s",self.name)
  self:debugf("app","hostname:     %s",self.hostname)
  self:debugf("app","id:           %s",self.id)
  self:debugf("app","mcevents:     %s",self.srvinit.mcevents)
  self:debugf("app","mcevents lcm: %s",self.srvinit.mcevents_lcm)
  self:debugf("app","rpc:          %s",self.srvinit.rpc)

  self.rpc.fun("getKeyValue",function(key)
      self:debugf("cache","getKeyValue[%s]=%s",key,values[key])
      return values[key],key
    end)
  self.rpc.fun("setKeyValue",function(key,value)
      self:debugf("cache","setKeyValue[%s]=%s",key,value)
      values[key]=value
      if not multicast then
        broadCast('-update',key,value)
      else
        self.mcevent.send({type='update',key=key,value=value})
      end
      return key,value
    end)
  self.mcevent.event('update',
    function(event,ip,port)
      self:debugf("cache","update2[%s]=%s",event.key,event.value)
      values[event.key]=event.value --
    end)
  self.rpc.fun("update",function(key,value)
      self:debugf("cache","update[%s]=%s",key,value)
      values[key]=value
      return key,value
    end)

  self.rpc.fun("peer",function(ip)
      self:debugf("disc","peer %s",ip)
      peers[ip]=true
      return values
    end)
  --
end

Container.start()
