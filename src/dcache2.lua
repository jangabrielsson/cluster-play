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

Container.srvinit.udpevent_lcm = true

function Container:startup()
  self:debugf("app","Starting up")
end

function Container:ready(state)
  if state then 
    self:debugf("app","Ready") 
  else 
    self:debugf("app","Not ready") 
  end
end

function Container:onInit()
  self.debugFlags.app = true
  self.debugFlags.contevent = true
  self.debugFlags.udp = true
  -- self.id
  -- self.status
  -- self.region
  -- self.debugflags

  self:readConfig("
  self:debugf("app","Container onInit")
  self:debugf("app","name:         %s",self.name)
  self:debugf("app","hostname:     %s",self.hostname)
  self:debugf("app","id:           %s",self.id)
  self:debugf("app","mcevents:     %s",self.srvinit.mcevents)
  self:debugf("app","mcevents lcm: %s",self.srvinit.mcevents_lcm)
  self:debugf("app","rpc:          %s",self.srvinit.rpc)
  --
end

Container.start()