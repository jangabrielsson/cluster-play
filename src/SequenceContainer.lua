local util = dofile("Container.lua")

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

Container.debugFlags.contevent = true
Container.debugFlags.probe     = true
Container.debugFlags.web       = true
--Container.debugFlags.web_extra       = true


function Container:started()
  local delay = Container:readEnv("DELAY","0")
  self:debugf("app","Delaying readiness with %ss",delay)
  setTimeout(function() self:setReady(true) end,1000*delay)
end

function Container:onInit()
  self.debugFlags.app = true
  self:debugf("app","Container onInit")
  self:debugf("app","name:         %s",self.name)
  self:debugf("app","hostname:     %s",self.hostname)
  self:debugf("app","id:           %s",self.id)
  self:debugf("app","ip:           %s",os.ipAddress())
  self:debugf("app","My logname is %s",self.logName)
  --self.debugFlags._logName = self.logName..":"
  self.debugFlags._logTag = function() return self.logName end
  
  local flag = false
  self.probes.readiness.cb = function(state)
    if state and not flag then self:debugf("app","CONT:%s READY",self.logName) flag = true end

  end
end

Container.start()
