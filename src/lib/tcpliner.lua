local copas, socket, json, util, DEBUG

local tcpliner = {}
local handler

local servers = {}

function handler(client,port,callback)
  client:settimeout(0,'b')
  client:setoption('keepalive',true)
  local ip = client:getpeername()
  DEBUG("tcp","S CONNECT(%s)",ip)
  tcpliner.printf = function(...)
    local msg = string.format(...)
    local len,err = client:send(msg.."\n")
    if err then DEBUG("tcp","S CLOSED(%s) (send) %s",ip,err) servers[port]=nil end
  end
  local stat,res = pcall(function()
      while true do
        local data,err,extra,len
        data,err,extra = client:receive("*l")
        if data==nil and err=='closed' then 
          DEBUG("tcp","S CLOSED(%s) (recieve) %s %s.",ip,err,tostring(extra)) servers[port]=nil return 
        end
        DEBUG("tcp","S RECIEVE(%s) <= %s",ip,tostring(data))
        local msg = callback(data)
        DEBUG("tcp","S SEND(%s) => %s",ip,msg)
        len,err = client:send(msg.."\n")
        if err then DEBUG("tcp","S CLOSED(%s) (send) %s",ip,err) servers[port]=nil return end
      end
    end)
  if not stat then DEBUG("tcp"," ERR:%s",res) servers[port]=nil end
--    end) 
end

function tcpliner.startListener(port,callback)
  if servers[port] then DEBUG("tcp","server at %p exists",port) return end
  servers[port]=true
  util.createAsyncServer("tcp line server",port,
    function(client) handler(client,port,callback) end,
    "tcp")
end

function tcpliner.init(env)
  copas = env.copas
  socket = env.socket
  json = env.json
  util = env.util
  env.tcpliner=tcpliner
  DEBUG = env.DEBUG
end

--[[
  tcpliner.startListener(port,function(str)
    return "echo "..str.."\n"
  end)
--]]
return tcpliner
