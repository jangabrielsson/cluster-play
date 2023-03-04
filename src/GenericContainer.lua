local util = dofile("ContainerBase.lua")

--[[
Container.state = <state>,                -- Internal Container states: loaded, starting, started, ready, notready
Container.region = <number>,              -- Restart region , if any

Container.srvinit.udpevent_lcm = true,    -- Responds to controller lcm events.
Container.srvinit.udpevent = true,        -- Listen to udp events
Container.srvinit.udpport = 9210,         -- Listen to udp events
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

local util = dofile("Container.lua")

local C,json

function Container:started()
  self:debugf("app","Starting up")
end

function Container:ready(state)
  if state then self:debugf("app","Ready") 
  else self:debugf("app","Not ready") end
end

local testFuns = {}
function testFuns.ping(x) return x+1 end

Container.debugFlags.contevent = true
Container.debugFlags.web_extra = true

function Container:onInit()
  C,json = self,self.json
  print("onInit")
  self.debugFlags.app  = true
  self.debugFlags.disc = true
  self.debugFlags.rpc  = false

  local rpcPort = self:readEnv("RPC_PORT")
  local server = self:serverLink(rpcPort,{'test','LCMfuns'},{name='RPC'})
  function server:opened(pipe,ep) end
  function server:closed(pipe,ep) end
  local f1,f2 = {},{}
  for name,_ in pairs(testFuns) do f1[name]={fun=f} end
  for name,_ in pairs(self.LCMfuns) do f2[name]={fun=f} end
  server.funs = { test = f1, LCMfuns = f2 }

  self.disc = self:startDiscovery(self:readEnv("DISC_ENDPOINT"))

  self.disc:register(self:endpoint('rpc',nil,rpcPort,'test'))
  self.disc:register(self:endpoint('rpc',nil,rpcPort,'LCMfuns'))

end

Container.start()