local mobdebug = require('mobdebug')
mobdebug.coro()
local util = dofile("lib/util.lua")

local C
local rpc,probe,json,socket,copas,DEBUG

Container = {
  id = nil,
  name = nil,
  status = 'loaded',   -- Internal Container states: loaded, starting, started, ready, notready
  region = 0,          -- Restart region , if any
  startInfo = true,
  srvinit = {
  },
  debugFlags = util.env.debug,
  probes = {
    startupdelay = 1,   -- Simulated delays for transition between Container probe states
    readinessdelay = 2,
    readyinterval = 4,
    notreadyinterval = 0, --20 
  }
}

--------------------------------------------------------
local function karray(kvtab) local r = {} for k,v in pairs(kvtab) do r[#r+1]=k end return r end
local function varray(kvtab) local r = {} for k,v in pairs(kvtab) do r[#r+1]=v end return r end

------------------- Events -----------------------------
do
  local EVENT={}; Container._event = EVENT
  function Container:event(ev,fun)
    assert(ev.type,"Event missing type")
    local t = ev.type
    local p = t:sub(1,1)
    if p=='+' then p ='post' t=t:sub(2)
    elseif p=='-' then p ='pre' t=t:sub(2)
    else p ='mid' end
    local tab = EVENT[t] or {pre={},mid={},post={}}
    tab[p][#tab[p]+1]=fun
    EVENT[t]=tab
  end

  local function callHandlers(hs,event)
    for _,f in ipairs(hs) do
      local stat,res = pcall(f,event)
      if not stat then error(res,3) end
    end
  end
  function Container:post(event,sec)
    sec = sec or 0
    return setTimeout(function()
        local t = event.type
        assert(t,"Missing event type")
        local hs = EVENT[t]
        assert(hs,"Undefined event type:"..t)        
        self:debugf("Event:%s",t)
        if #hs.pre>0 then callHandlers(hs.pre,event) end
        if #hs.mid>0 then callHandlers(hs.mid,event) end
        if #hs.post>0 then callHandlers(hs.post,event) end
      end,1000*(sec >= os.time() and sec-os.time() or sec))
  end

  function Container:cancel(ref) clearTimeout(ref) return nil end
end
------------------------------------------------------

-- This simulates Container lifecycle states - starting, started, ready, and optional notready... affecting the probes 
function Container:startLC()

  Container:event({type='c:start'},function(ev)
      self:debugf('contevent',"STARTING")
      local delay
      if self.onInit then delay = self:onInit() end
      self.state = 'starting'
      self:post({type='c:started'},tonumber(delay) or self.probes.startupdelay or 0)
    end)

  Container:event({type='c:started'},function(ev)
      C.probes.startup.state = true
      C:debugf('contevent',"STARTED")
      C.state = 'started'
      if C.started then C:started() else
        C:post({type='c:ready'},C.probes.readinessdelay or 0)
      end
    end)

  Container:event({type='c:ready'},function(ev)
      self.probes.readiness.state = true
      self:debugf('contevent',"READY")
      self.state = 'ready'
      if self.ready then C:ready(true) end
      if self.probes.notreadyinterval and self.probes.notreadyinterval > 0 then
        self:post({type='c:notReady'},self.probes.readyinterval)
      end
    end)

  Container:event({type='c:notReady'},function(ev)
      self.probes.readiness.state = false
      self:debugf('contevent',"NOT READY")
      self.state = 'notready'
      if self.ready then C:ready(false)
      else 
        self:post({type='c:ready'},self.probes.notreadyinterval)
      end
    end)

  self:post({type='c:start'})
end

local function init(env)
  json,rpc,probe,socket,copas,DEBUG = 
  env.json,env.rpc,env.web.probe,env.socket,env.copas,env.DEBUG
end

-- function Container:onInit() called at startup
-- function Container:started() called after startup delay, responsible to set ready
-- function Container:ready(bool) called with readiness state true/false

function Container:setReady(state)
  if state then
    if self.state ~= 'ready' then self:post({type='c:ready'}) end
  else
    if self.state ~= 'notready' then self:post({type='c:notReady'}) end
  end
end

function Container:endpoint(proto,host,port,path)
  local str = (port==nil and path==nil) and proto or string.format("%s://%s:%d/%s",proto,host or os.ipAddress(),tonumber(port),path)
  local ep = { address = str, match=function(self,str) return string.match(self.address,str) end }
  return setmetatable(ep,{
      __tostring = function(o) return o.address end,
      __concat = function(op1,op2) return tostring(op1)..tostring(op2) end,
      __eq = function(a,b) return a.address==b.address end,
    })
end

----------- LCM funs ------------
local LCMfuns = {}
function LCMfuns.ping() return "pong" end
function LCMfuns.containerInfo() 
end
function LCMfuns.restart() 
end
function LCMfuns.lua(str)
end
Container.LCMfuns = LCMfuns

----------- Discovery -----------
local services,subscriptions = {},{}

function Container:serverLink(port,paths,opts)
  opts = opts or {}
  local linkm = {}
  self.rpc:server(port,function(pipe)
      C:debugf("LINK '%s' established (s:%s)",opts.name or "link",pipe.name)
      function pipe:closeHandler()
        C:debugf("LINK '%s' closed (s:%s)",opts.name or "Link",pipe.name)
        if linkm.closed then pcall(linkm.closed,linkm,pipe) end
      end
      if linkm.opened then pcall(linkm.opened,linkm,pipe) end   
      pipe.funs = pipe.funs or linkm.funs
    end,paths)
  return linkm
end

function Container:clientLink(ep,opts)
  assert(ep,"endpoint is nil")
  opts = opts or {}
  ep = type(ep)=='string' and self:endpoint(ep) or ep
  local linkm = { opts=opts }
  function linkm:close() pipe:close() end
  local function loop()
    local stat,res = pcall(function()
        self:debugf("container","Trying connction: %s",ep)
        local pipe = self:endpointConnect(ep)
        self:debugf("link","LINK '%s' established (c:%s)",opts.name or "link",pipe.name)
        function pipe:closeHandler()
          C:debugf("link","LINK '%s' closed (c:%s)",opts.name or "link",pipe.name)
          if linkm.closed then pcall(linkm.closed,linkm,pipe) end
          if ep.invalid==nil and opts.reconnect then setTimeout(loop,1000*(opts.reconnectDelay or 3)) end
        end
        if linkm.opened then pcall(linkm.opened,linkm,pipe) end
      end)
    if stat==false and ep.invalid==nil then print(res)  setTimeout(loop,1000*(opts.retryDelay or 3)) end
  end
  setTimeout(loop,0)
  return linkm
end

function Container:subSingleLink(path,newSub,opts)
  opts = opts or {first=true}
  local last,found={}
  return function(eps)
    if last[1]==nil then last[1]=eps[path][1]
    else
      for _,ep in ipairs(eps[path]) do 
        if last[1]==ep then found = true break end
      end
      if not found then
        last[1].invalid = true
        last[1]=eps[path][1]
      end
    end
    if found then return 
    else
      newSub(last)
    end
  end
end

function Container:wait(s) copas.pause(s) end

function Container:startDiscovery(endpoint)
  assert(endpoint,"No discovery endpoint")
  self:debugf("container","Discovery at: %s",endpoint)
  local link = self:clientLink(endpoint,{reconnect=true,name="discovery"})
  function link:opened(disc)
    disc.funs = { discovery = { subscription = { fun = function(eps) C:post({type='d:subs',subs=eps }) end } } }
    disc:call("publish",karray(services))
    disc:call("subscribe",karray(subscriptions))
  end
  function link:closed(disc)
  end

  local substEP = {"(10%.42%.%d+%.%d+:6977)","localhost:30123"}
  Container:event({type='d:subs'},function(ev)
      for epp,eps in pairs(ev.subs or {}) do
        for k,ep in ipairs(eps) do
          if self.locl then ep = ep:gsub(table.unpack(substEP)) end
          ep = self:endpoint(ep)
          eps[k] = ep
        end
        if subscriptions[epp] then
          pcall(subscriptions[epp],eps)
        end
      end
    end)

  local f = {}

  function f:register(ep) services[ep]=true end

  function f:subscribe(epp,cb) subscriptions[epp] = cb end

  return f
end -- Discovery

---------------------------------

function Container:debugf(typ,fmt,...) DEBUG(typ,fmt,...) end
function Container:readEnv(name,dflt)
  local v
  if self.locl then
    local file = io.open("params.json")
    local data = json.decode(file:read("*all"))
    v = data[self.name.."_"..name]
  else v = os.getenv(name) end
  if v~=nil then return v else return dflt end
end

local creators = {}

function creators.rpc(host,port,path)
  return C.rpc:client(host,port,path)
end

function Container:endpointConnect(ep)
  local proto,host,port,path = ep:match("^(%a+)://([%w%.%-]+):(%d+)/(.*)$")
  assert(proto and creators[proto] and host and port and path,"Bad endpoint "..ep)
  return creators[proto](host,port,path)
end

local function main(self,env)
  C = self
  self.locl = not os.ipAddress():match("^10%.") --~=nil or os.ipAddress():match("^147")~=nil
  init(env)

  self.hostname = socket.dns.gethostname()
  self.name = os.getenv("CONTAINER_NAME") or arg[0]:match("([%w_]+)%.lua$")
  self.logName = self:readEnv("CONTAINER_LOGNAME","")
  self.id = self.hostname..":"..self.name
  --env.debug = self.debugFlags

  self.debugFlags.contevent = true
  self.debugFlags.container = true
  self.debugFlags.probe     = true
  self.debugFlags.tcp       = true
  self.debugFlags.udp       = true
  self.debugFlags.disc      = true
  self.debugFlags.link      = true

  if self.startInfo then
    self:debugf("container","Container onInit")
    self:debugf("container","name:           %s",self.name)
    self:debugf("container","hostname:       %s",self.hostname)
    self:debugf("container","id:             %s",self.id)
    self:debugf("container","ip:             %s",os.ipAddress())
    self:debugf("container","container name: %s",self.name)
    if self.logName and self.logName~="" then 
      self:debugf("container","log name:       %s",self.logName) end
    end
    self:debugf("container","local:          %s",tostring(self.locl))
    
    self:debugf("probe","Setting up probes...")
    local probePort = tonumber(self:readEnv("PROBE_PORT","8765"))
    env.web.start(probePort)
    self.probes.liveness = probe("/liveness",true)
    self.probes.startup = probe("/startup",false)
    self.probes.readiness = probe("/readiness",false)

    self.probes.podstart = probe("/podstart",true)
    self.probes.podstop = probe("//podstop",true)

    self.json      = env.json
    self.rpc       = env.rpc
    self.util      = env.util
    self.udp       = env.udp
    self.socket    = env.socket

    self:startLC()
  end

  function Container.start()    
    util.start(function(env) main(Container,env) end)
  end

  return Container
