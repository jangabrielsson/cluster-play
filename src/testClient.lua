local util = dofile("Container.lua")

local C,json

function Container:started()
  self:debugf("app","Starting up")
end

function Container:ready(state)
  if state then self:debugf("app","Ready") 
  else self:debugf("app","Not ready") end
end

local myFuns = {}
function myFuns.print(str) C:debugf("app","%s",str) end

Container.debugFlags.contevent = true
Container.debugFlags.web_extra = true

function Subscription(ep)
  local self = {}
  function self:endpoints()
  end
end

function Container:onInit()
  C,json = self,self.json
  print("onInit")
  self.debugFlags.app  = true
  self.debugFlags.disc = true
  self.debugFlags.rpc  = false

  local rpcPort = self:readEnv("RPC_PORT")
  local server = self:serverLink(rpcPort,{'myFuns','LCMfuns'},{name='RPC'})
  function server:opened(pipe,ep) end
  function server:closed(pipe,ep) end

  local f1,f2 = {},{}
  for name,_ in pairs(myFuns) do f1[name]={fun=f} end
  for name,_ in pairs(self.LCMfuns) do f2[name]={fun=f} end
  server.funs = { myFuns = f1, LCMfuns = f2 }

  self.disc = self:startDiscovery(self:readEnv("DISC_ENDPOINT"))

  self.disc:register(self:endpoint('rpc',nil,rpcPort,'myFuns'))
  self.disc:register(self:endpoint('rpc',nil,rpcPort,'LCMfuns'))

  function Subscription(f)
    local subs,started = {},false
    return function(eps)
      local change = false
      for _,ep in ipairs(eps) do if not subs[ep.address] then change=true subs[ep.address]=ep end end
      if change then
        subs = karray(subs) table.sort(subs,function(a,b) return a.address <= b.address end)
        if not started then started=true setTimeout(f,0) end
      end
    end
  end

  self.disc:subscribe("rpc://.-:.-/test",Subscription(function(subs)
        while #subs>0 do
          
          C:debugf('app',"ping:%d -> %s",i,rpc:call("ping",i))
          i=i+1
          C:wait(1)
        end
      end))

--  self:subSingleLink('test',
--    function(epa)
--      local ep=epa[1]
--      local client = self:clientLink(ep,{reconnect=true,name="Pinger"})
--      local i = 42
--      function client:opened(rpc)
--        while true do
--          C:debugf('app',"ping:%d -> %s",i,rpc:call("ping",i))
--          i=i+1
--          C:wait(1)
--        end
--      end
--    end))

end
Container.start()