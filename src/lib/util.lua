local function addPath(p,front) package.path=front and (p..";"..package.path) or (package.path..";"..p) end
addPath("./lib/?",true)
addPath("./lib/?.lua",true)

local socket = require("socket")
local copas  = require("copas")
copas.timer  = require("copas/timer")
local rpc = dofile("lib/rpc.lua")
local udp = dofile("lib/udp.lua")
local web = dofile("lib/web.lua")
local json = dofile("lib/json.lua")

local env
local function printf(fmt,...) print(string.format(fmt,...)) end
local debugFlags = { _logName = "", _logTag = function() return os.ipAddress() end } 
function _DEBUG(typ,fmt,...) 
  if env.debug[typ] then printf("%s/%s[%s%-4s]"..fmt,env.debug._logTag(),os.date("%X"),env.debug._logName or "",typ,...) end 
end
env = { debug = debugFlags, printf=printf, DEBUG=_DEBUG }

local util = { env = env }

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

function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function os.sourcefile(l)
  local file = debug.getinfo(l or 3, 'S')                                      -- Find out what file we are running
  if file and file.source then
    file = file.source
    if not file:sub(1,1)=='@' then error("Can't locate file:"..file) end  -- Is it a file?
    return file:sub(2)
  end
end

local __IPAddress
function os.ipAddress()
  if __IPAddress then return __IPAddress end
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress,_ = mySocket:getsockname()-- returns IP and Port
  __IPAddress = myDevicesIpAddress == "0.0.0.0" and "127.0.0.1" or myDevicesIpAddress
  return __IPAddress
end

function util.createAsyncServer(name,port,handler,dbg)
  if not dbg then dbg = "web" end
  local server,msg = socket.bind("*", port)
  if not server then print("Faild binding port ",port,msg) end
  assert(server,(msg or "").." ,port "..port)
  local i, msg2 = server:getsockname()
  if not i then print("Faild binding port ",port,msg2) end
  assert(i, msg2)
  copas.addserver(server,function(skt) handler(copas.wrap(skt)) end, 50000, name)
  _DEBUG(dbg,"Created %s at prot://%s:%s/",name,os.ipAddress(),port)
end

local dnsFound = {}
local function clientsLookup(svc,callback)
  local _,w = socket.dns.toip(svc)
  if type(w)=='table' then
    local res = {}
    for _,ip in ipairs(w.ip) do
      if ip ~= os.ipAddress() then res[#res+1]=ip end
    end
    _DEBUG("dns","Clients found")
    callback(res) 
    -- Repeat until we succeed
  else 
    if not dnsFound[svc] then
      _DEBUG("dns","No clients bound to %s %s",svc,tostring(w))
      dnsFound[svc]=true
    end
    setTimeout(function() clientsLookup(svc,callback) end,2000) 
  end -- try in 2s
end
util.clientsLookup = clientsLookup

function util.discoverClients(service,callback,interval)
  clientsLookup(service,
    function(res)
      local clients = {}
      _DEBUG("dns","DNS discovery")
      for _,ip in ipairs(res) do
        _DEBUG("dns","client %s",ip) 
        clients[ip]=true
      end
      callback(clients)
      if interval then setTimeout(function() util.discoverClients(service,callback,interval) end,interval*1000) end
    end)
end

function util.start(main)
  copas.loop(function()
      env.copas = copas
      env.socket=socket
      env.json=json
      env.util=util
      rpc.init(env)
      web.init(env)
      udp.init(env)
      copas.addthread(function() main(env) end)
    end)
end

return util