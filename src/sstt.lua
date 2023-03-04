local function addPath(p,front) package.path=front and (p..";"..package.path) or (package.path..";"..p) end
addPath("./lib/?",true)
addPath("./lib/?.lua",true)
local mobdebug = require('mobdebug')
mobdebug.coro()
local socket = require("socket")
local copas  = require("copas")
copas.timer  = require("copas/timer")
local json = dofile("lib/json.lua")

function setTimeout(fun,ms)
  return copas.timer.new({
      delay = ms/1000,                   -- delay in seconds
      recurring = false,                 -- make the timer repeat
      params = fun,
      callback = function(timer_obj, params)
        xpcall(params,function(err)
            print(debug.traceback(err))
          end)
      end
    })
end

function clearTimeout(timer) timer:cancel() return nil end
function DEBUG(_,...) print(string.format(...)) end

--[[
  rpc.TIMEOUT = <s>              -- Default timeout (20s)
  pipe = rpc.client(ip,port)
  pipe = rpc.server(port)
  pipe.funs = { <name> = {sync=<boolean>, fun=<fun>} }
  pipe.closeHandler = <function>
  pipe:call(<name>,...)
  pipe:close()
  pipe.TIMEOUT = <s>
  pipe:timeout(s):call(<name>,...)
--]]

local RPC = { TIMEOUT = 20 }
local unpack = table.unpack

function RPC:_pipe(sock)
  local r,calls,id = { path=nil, TIMEOUT = self.TIMEOUT },{},0
  sock:settimeout(0,'b')
  sock:setoption('keepalive',true)
  local function missing(path,name) error("Missing rpcfun: "..path.."/"..name) end
  local function caller(id,fun,...)
    local res = {reply={pcall(fun,...)},id=id}
    res = json.encode(res)
    local a = sock:send(res.."\n")
    DEBUG('rpc',"reply %d %s",a or 'nil',res)
  end
  function r._startListener()
    copas.pause(0)
    while true do
      local l,msg = sock:receive("*l")
      if l==nil and msg=='closed' then
        if r.closeHandler then r.closeHandler() end
        return
      end
      DEBUG('rpc',"recieving %s %s",tostring(l),msg or "")
      l = json.decode(l)
      if l.call then
        local call = (r.funs[l.path] or {})[l.call]
        if call==nil then caller(l.id,missing,l.path,l.call)
        elseif call.async then copas.addthread(function() caller(l.id,call.fun,unpack(l.args)) end,0)
        else caller(l.id,call.fun,unpack(l.args)) end
      elseif l.reply then
        local co = calls[l.id]
        calls[l.id]=l.reply
        copas.wakeup(co)
      end
    end
  end
  function r:pcall(fun,...)
    local args,res = {...}
    id = id+1
    local data = json.encode({call=fun,args=args,path=r.path,id=id})
    local a = sock:send(data.."\n")
    DEBUG('rpc',"call %d %s",a or "",data)
    calls[id] = coroutine.running()
    local t = r.TT or r.TIMEOUT
    r.TT = nil
    copas.pause(t)
    res,calls[id] = calls[id],nil
    return type(res)=='table' and res or {false,'timeout'}
  end
  function r:call(fun,...)
    local res = self:pcall(fun,...)
    if res[1] then return select(2,unpack(res))
    else error(res[2]) end
  end
  function r:timeout(s) self.TT = s return self end
  function r:close() sock:close() end
  function r.listFuns()
    local res = {}
    for name,_ in pairs(r.funs or {}) do res[#res+1]=name end
    return res
  end
  return r
end

function link(sock)
  local r,calls,id = { TIMEOUT = self.TIMEOUT },{},0
  sock:settimeout(0,'b')
  sock:setoption('keepalive',true)
  function r._startListener()
    copas.pause(0)
    while true do
      local l,msg = sock:receive("*l")
      if l==nil and msg=='closed' then
        if r.closeHandler then r.closeHandler() end
        return
      end
      r.incomingData(l)
    end
  end
  function r:send(data)
    return sock:send(data.."\n")
  end
  function r:close() sock:close() end
  return r
end

function clientLink(host,port)
  local sock = copas.wrap(socket.tcp())--, ssl_params)
  assert(sock:connect(host, port))
  sock:send(path.."\n")
  assert(sock:receive("*l")=="NACK","closed") -- nack
  local l = link(sock)
  copas.addthread(l._startListener)
  return l
end

function rpcHandler(link)
  local r,calls,id = { path=nil, TIMEOUT = self.TIMEOUT },{},0
  local function missing(path,name) error("Missing rpcfun: "..path.."/"..name) end
  local function caller(id,fun,...)
    local res = {reply={pcall(fun,...)},id=id}
    res = json.encode(res)
    local a = link:send(res)
    DEBUG('rpc',"reply %d %s",a or 'nil',res)
  end
  function r.incomingData(data)
    copas.pause(0)
    DEBUG('rpc',"recieving %s",tostring(data))
    data = json.decode(data)
    if data.call then
      local call = (r.funs[l.path] or {})[data.call]
      if call==nil then caller(data.id,missing,data.path,data.call)
      elseif call.async then copas.addthread(function() caller(data.id,call.fun,unpack(data.args)) end,0)
      else caller(data.id,call.fun,unpack(data.args)) end
    elseif data.reply then
      local co = calls[data.id]
      calls[data.id]=l.reply
      copas.wakeup(co)
    end
  end
  function r:pcall(fun,...)
    local args,res = {...}
    id = id+1
    local data = json.encode({call=fun,args=args,path=r.path,id=id})
    local a = link:send(data)
    DEBUG('rpc',"call %d %s",a or "",data)
    calls[id] = coroutine.running()
    local t = r.TT or r.TIMEOUT
    r.TT = nil
    copas.pause(t)
    res,calls[id] = calls[id],nil
    return type(res)=='table' and res or {false,'timeout'}
  end
  function r:call(fun,...)
    local res = self:pcall(fun,...)
    if res[1] then return select(2,unpack(res))
    else error(res[2]) end
  end
  function r:timeout(s) self.TT = s return self end
  function r:close() link:close() end
  function r.listFuns()
    local res = {}
    for name,_ in pairs(r.funs or {}) do res[#res+1]=name end
    return res
  end
  return r
end

function rpcClient(port,paths)
  local link = clientLink(host,port)
  local rpc = rpcHandler(link)
  link.incomingHandler = rpc.incomingHandler
  return rpc
end

function rpcServer(host,handler,path)
  serverLink(port,function(link)
      local rpc = rpcHandler(link)
      link.incomingHandler = rpc.incomingHandler
    end
  )
  local rpc = rpcHandler(link)
  link.incomingHandler = rpc.incomingHandler
  return rpc
end

function serverLink(port)
  local server,msg = socket.bind("*", port)
  assert(server,(msg or "").." ,port "..port)
  local i, msg2 = server:getsockname()
  assert(i, msg2)
  copas.addserver(server,function(skt) 
      skt = copas.wrap(skt)
      local l = link(skt)
      l.path = skt:receive("*l")
      skt:send("NACK\n")
      l._peers = {skt:getpeername()}
      l.name = string.format("[%s:%s]",l._peers[1],l._peers[2])
      copas.addthread(connectionHandler,l) 
      l._startListener()
    end,
    self.timeout or 50000, self.name or "Server")
end

function RPC:client(host,port,path)
  local sock = copas.wrap(socket.tcp())--, ssl_params)
  assert(sock:connect(host, port))
  --DEBUG('rpc',"Client connected")
  sock:send(path.."\n")
  assert(sock:receive("*l")=="NACK","closed") -- nack
  local p = self:_pipe(sock)
  p.path = path
  copas.addthread(p._startListener)
  return p
end

function RPC:server(port,connectionHandler,paths)
  local server,msg = socket.bind("*", port)
  assert(server,(msg or "").." ,port "..port)
  local i, msg2 = server:getsockname()
  assert(i, msg2)
  DEBUG('rpc',"rpc server at %s",port)
  local dpaths = {}
  for _,p in ipairs(paths) do dpaths[p]=true end
  copas.addserver(server,function(skt) 
      skt = copas.wrap(skt)
      local p = self:_pipe(skt)
      p.path = skt:receive("*l")
      if not dpaths[p.path] then skt.close() return end
      skt:send("NACK\n")
      p._peers = {skt:getpeername()}
      p.name = string.format("[%s:%s]",p._peers[1],p._peers[2])
      copas.addthread(connectionHandler,p) 
      p._startListener()
    end,
    self.timeout or 50000, self.name or "Server")
end

local rpc = RPC

--copas.autoclose = false
local port = 9654
local function main()
  --copas.debug.start()
  setTimeout(
    function()
      RPC:server(port,function(pipe)
          print("S Connected")
          pipe.funs = {
            test = {
              a = {fun=function(x) return x+x end},
              b = {async=true, fun=function(x) 
                  local y = pipe:call('c',x+1)
                  print("S:",y)
                  return 2*y
                end
              },
              _rpcGetFuns = {fun=pipe.listFuns},
            }
          }
          pipe.tag = "Server"
          function pipe.closeHandler() print"Server closed" end
        end,
        {"test"})
    end,0)
  setTimeout(
    function()
      local pipe = RPC:client("localhost",port,"test")
      pipe.funs = {
        test = {
          c = {fun=function(x) return x+2 end },
          _rpcGetFuns = {fun=pipe.listFuns },
        }
      }
      function pipe.closeHandler() print"Client closed" end
      print("C0:",json.encode(pipe:call("_rpcGetFuns")))
      print("C1:",pipe:call('a',10))
      print("C2:",pipe:call('b',20))
      print("C3:",pipe:call('a',30))
      pipe:close()
    end,
    0)
end

copas.loop(main)
