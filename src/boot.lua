local util = dofile("lib/util.lua")
local LE = dofile("lib/LE.lua")()
local mobdebug = require('mobdebug')
mobdebug.coro()

local rpc,probe,json,mac,DEBUG

EVENT = LE.event

local STARTUPDELAY = 2 
local READINESSDELAY = 5 
local READYINTERVAL = 20
local UNREADYINTERVAL = 0--20 
local livenessProbe,startupProbe,readinessProbe

local function discoverPeers(svc,callback)
  -- my-app-headless.default.svc.cluster.local has address 10.42.2.50
  local res = {}
  local str = os.capture("host "..svc, true)
  str:gsub("([%w%.%-]+) has address ([%d%.]+)",function(name,ip) 
      res[ip]=true
    end)
  if next(res) then callback(res)
  else setTimeout(function() discoverPeers(svc,callback) end,3000) end
end

function EVENT:start(ev)
  self._tag = "POD"
  LE.DEBUG("POD","STARTING")
  self:post({type='started'},STARTUPDELAY)
end

function EVENT:started(ev)
  startupProbe.state = 200
  LE.DEBUG("POD","STARTED")
  self:post({type='ready'},READINESSDELAY)
end

function EVENT:ready(ev)
  readinessProbe.state = 200
  LE.DEBUG("POD","READY")

  self:post({type='discoverPeers', name="my-app-headless.default.svc.cluster.local"})

  if UNREADYINTERVAL > 0 then
    self:post({type='notReady'},READYINTERVAL)
  end
end

function EVENT:notReady(ev)
  readinessProbe.state = 500
  LE.DEBUG("POD","NOT READY")
  self:post({type='ready'},UNREADYINTERVAL)
end

local peers={}
function EVENT:discoverPeers(ev)
  if not self.dnsLookup then 
    discoverPeers("my-app-headless.default.svc.cluster.local",
      function(res)
        DEBUG("POD","DNS Discovery")
        for ip,_ in pairs(res) do
          if ip ~= os.ipAddress() then
            DEBUG("POD","%s",ip) 
            peers[ip]=true
          end
        end
        self.dnsLookup = true 
      end)
  end
end

local function setupDiscovery()
  rpc.fun("MY_IP",function(ip) 
      peers[ip]=true 
    end)
end


local function init(env)
  json,rpc,probe,DEBUG = env.json,env.rpc,env.web.probe,env.DEBUG
end

local function main(env)
  mac = os.ipAddress():match("^192")~=nil
  init(env)
  LE.DEBUG = env.DEBUG
  env.debug.LE    = true
  env.debug.POD   = true
  env.debug.probe = true
  env.debug.web   = true
  env.debug.rpc   = true

  setupDiscovery()

  livenessProbe = probe("/liveness",200)
  startupProbe = probe("/startup",500)
  readinessProbe = probe("/readiness",500)

  LE:post({type='start'})
  rpc.fun("test",function(a,b) return a+b end)

  local function runTest()
    for i=1,1000 do 
      if mac then rpc.call("localhost",30333,"test",{3,i}) end
    end
  end
end

util.start(main)