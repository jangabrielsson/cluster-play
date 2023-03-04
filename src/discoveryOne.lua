local Container = dofile("Container.lua")

local C,json

local clients = {}
local notifySubs

--- "rpc://<ip>:port/path"
--- "rpc://.-:.-/path"
local function publish(eps,disc) -- {"<prot>://<ip>:<port>/<path>", ...}
  local pubs = clients[disc].pubs
  local neps = {}
  for _,ep in ipairs(eps) do
    if not pubs[ep] then
      pubs[ep]=true
      neps[#neps+1]=ep
      C:debugf("disc","Added pub %s from %s",ep,disc.name)
    end
  end
  notifySubs(neps,disc)
  return true 
end

local function lookup(epp,disc)
  local res = {}
  for cl,es in pairs(clients) do
    if cl ~= disc then
      for ep,_ in pairs(es.pubs) do
        if ep:match(epp) then res[#res+1]=ep end
      end
    end
  end
  return res
end

local function subscribe(epps,disc)
  local res = {}
  local subs = clients[disc].subs
  for _,epp in ipairs(epps) do
    if not subs[epp] then
      subs[epp]=true
      local ms = lookup(epp,disc)
      if next(ms) then res[epp]=ms end
      C:debugf("disc","Added sub %s from %s",epp,disc.name)
    end
  end
  if next(res) then 
    setTimeout(function() disc:pcall('subscription',res) end,0) 
  end
  return "OK"
end

function notifySubs(eps,disc)
  for d2,e in pairs(clients) do                -- loop through all clients
    if d2 ~= disc then
      local res = {}
      for epp,_ in pairs(e.subs) do            -- Collect matching ep's from eps
        for _,ep in ipairs(eps) do
          if ep:match(epp) then
            local r = res[epp] or {}
            r[#r+1]=ep
            res[epp]=r
          end
        end
      end
      if next(res) then                       -- If any match, notify subscriber
        d2:pcall("subscription",res)
      end
    end
  end
end

local function closeConnection(_,disc)
  C:debugf("disc","Client connection closed: %s",disc.name)
  local e = clients[disc]
  clients[disc]=nil
  for ep,_ in pairs(e.pubs) do       -- Remove published eps
    C:debugf("disc","Removed pub %s from %s",ep,disc.name)
--    for d2,es in pairs(clients) do
--      if isSubscribing(d2,ep) then
--      end
--    end
  end
  for epp,_ in pairs(e.subs) do       -- Remove subscriptions
    C:debugf("disc","Removed sub %s from %s",epp,disc.name)
  end
end

local function clientHandler(_,disc)
  C:debugf("disc","Connection from %s %s",disc.name,disc.path)
  clients[disc]={ pubs = {}, subs = {} }
  disc.funs = {
    discovery = {
      publish = { fun=function(eps) return publish(eps,disc) end },
      subscribe = { fun=function(eps) return subscribe(eps,disc) end },
      _rpcGetFuns = { fun=disc.listFuns},
    },
    test = {
      ping = { sync=true, fun=function(x) return "pong:"..(x+1) end },
    }
  }
end

Container.debugFlags.web         = true
Container.debugFlags.contevent   = true
--Container.debugFlags.web_extra = true
Container.debugFlags.probe       = true

function Container:onInit()
  C = self
  json = C.json
  self.debugFlags.app       = true
  self.debugFlags.rpc       = true
  self.debugFlags.disc      = true
  self.debugFlags.web       = true

  self:debugf("app","Starting %s",self.name)
  local rpcPort = self:readEnv("RPC_PORT")
  local server = self:serverLink(rpcPort,{'discovery','test'},{name='discovery'})
  server.opened = clientHandler
  server.closed = closeConnection

  local dd = {name='disc'}
  clients[dd]={ pubs = { [self:endpoint("rpc",nil,rpcPort,"test")]=true }, subs = {} }
end

Container.start()