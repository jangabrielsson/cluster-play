local mobdebug = require('mobdebug')
mobdebug.coro()
local util = dofile("lib/util.lua")
local LE = dofile("lib/LE.lua")()

local rpc,probe,json,socket,mac,mc,DEBUG
local EVENT = LE.event

Container = {
  id = nil,
  name = nil,
  status = 'loaded',   -- Internal Container states: loaded, starting, started, ready, notready
  region = 0,          -- Restart region , if any
  srvinit = {
    udpevent_lcm = true, -- Responds to controller lcm events.
    udpevent = true,     -- Listen to multicast events
    udpport = 9210,
    rpc = true,          -- Listen to rpc
  },
  debugFlags = { rpc = true, mc = true, events = true, http = true , tcp = true } ,
  probes = {
    startupdelay = 1,   -- Simulated delays for transition between Container probe states
    readinessdelay = 2,
    readyinterval = 4,
    notreadyinterval = 0, --20 
  }
}

-- This simulates Container lifecycle states - starting, started, ready, and optional notready... affecting the probes
function EVENT:start(ev)
  self._tag = "Container"
  if Container.onInit then Container:onInit() end
  LE.DEBUG("contevent","STARTING")
  Container.state = 'starting'
  self:post({type='started'},Container.probes.startupdelay)
  if Container.startup then Container:startup() end
end

function EVENT:started(ev)
  Container.probes.startup.state = 200
  LE.DEBUG("contevent","STARTED")
  Container.state = 'started'
  self:post({type='ready'},Container.probes.readinessdelay)
end

function EVENT:ready(ev)
  Container.probes.readiness.state = 200
  LE.DEBUG("contevent","READY")
  Container.state = 'ready'
  if Container.ready then Container:ready(true) end
  if Container.probes.notreadyinterval and Container.probes.notreadyinterval > 0 then
    self:post({type='notReady'},Container.probes.readyinterval)
  end
end

function EVENT:notReady(ev)
  Container.probes.readiness.state = 500
  LE.DEBUG("contevent","NOT READY")
  Container.state = 'notready'
  if Container.ready then Container:read(false) end
  self:post({type='ready'},Container.probes.notreadyinterval)
end

local function init(env)
  json,rpc,probe,socket,mc,udpevent,DEBUG = 
  env.json,env.rpc,env.web.probe,env.socket,env.mcevent,env.udpevent,env.DEBUG
end

function Container:setReady(state)
  if Container.state ~= 'ready' and state then LE:post({type='ready'})
  elseif Container.state ~= 'notready' then LE:post({type='notReady'}) end
end

function Container:debugf(typ,fmt,...) DEBUG(typ,fmt,...) end

local function main(env)
  Container.locl = os.ipAddress():match("^192")~=nil
  init(env)
  LE.DEBUG = DEBUG

  Container.hostname = socket.dns.gethostname()
  Container.name = os.getenv("CONTAINER_NAME") or arg[0]:match("([%w_]+)%.lua$")
  Container.id = Container.hostname..":"..Container.name
  env.debug = Container.debugFlags

  Container.debugFlags.podevent  = true
  Container.debugFlags.probe     = true
  Container.debugFlags.tcp       = true
  Container.debugFlags.mcevent   = true
  Container.debugFlags.udpevent  = true
  Container.debugFlags.udp       = true

  Container.probes.liveness = probe("/liveness",200)
  Container.probes.startup = probe("/startup",500)
  Container.probes.readiness = probe("/readiness",500)

  Container.json      = env.json
  Container.rpc       = env.rpc
  Container.util      = env.util
  Container.mcevent   = env.mcevent
  Container.udpevent  = env.udpevent
  Container.socket    = env.socket
  Container.tcpliner  = env.tcpliner

  if Container.srvinit.udpevent_lcm or Container.srvinit.udpevent then
    udpevent.startListening(Container.srvinit.udpport)
  end

  if Container.srvinit.rpc then
    rpc.startListening(port)
  end

  if Container.srvinit.udpevent_lcm then     -- Standard mc lifecycle events used by Controller pod
    udpevent.event('containerQuery',
      function(event,ip,port)
        DEBUG("udp","QUERY")
        udpevent.send(ip,{type='containerInfo',id=Container.id,
            status=Container.status,
            hostname=Container.hostname,
            hostname=Container.name,
          })
      end)

    udpevent.event('regionQuery',
      function(event,ip,port)
        udpevent.send(ip,{type='regionInfo',id=Container.id,region=Container.region or 0})
      end)

    udpevent.event('restart',
      function(event,ip,port)
        local regsion = event.region
        udpevent.send(ip,{type='restartAck',id=Container.id})
      end)

    udpevent.event('lua',
      function(event,ip,port)
        local res = {pcall(function() return load(event.str)() end)}
        udpevent.send(ip,{type='luares',id=Container.id,res=res})
      end)
    
    udpevent.event('ping',
      function(event,ip,port)
        udpevent.send(ip,{type='pong',id=Container.id})
      end)
  end

  LE:post({type='start'})
end

function Container.start() util.start(main) end

return Container
