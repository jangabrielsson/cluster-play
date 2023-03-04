local copas, socket, json, util, DEBUG

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

function RPC:client(host,port,path)
  local sock = copas.wrap(socket.tcp())--, ssl_params)
  DEBUG('rpc',"RPC %s %s",host,port)
  assert(sock:connect(host, port))
  --DEBUG('rpc',"Client connected")
  sock:send(path.."\n")
  assert(sock:receive("*l")=="NACK","closed") -- nack
  local p = self:_pipe(sock)
  p._peer = {sock:getpeername()}
  p.name = string.format("[%s:%s]",p._peer[1],p._peer[2])
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
      p._peer = {skt:getpeername()}
      p.name = string.format("[%s:%s]",p._peer[1],p._peer[2])
      copas.addthread(connectionHandler,p)
      p._startListener()
    end,
    self.timeout or 50000, self.name or "Server")
  return cbh
end

function RPC.init(env)
  DEBUG   = env.DEBUG
  copas   = env.copas 
  socket  = env.socket
  json    = env.json
  util    = env.util
  env.rpc = RPC
end

return RPC
