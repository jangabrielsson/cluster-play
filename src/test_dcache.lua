local util = dofile("lib/util.lua")
local LE = dofile("lib/LE.lua")()
local mobdebug = require('mobdebug')
mobdebug.coro()

local rpc,probe,json,mac,socket,copas,DEBUG

local function init(env)
  json,rpc,probe,socket,copas,DEBUG = env.json,env.rpc,env.web.probe,env.socket,env.copas,env.DEBUG
end

local function process(fun,...)
  local args = {...}
  setTimeout(function() 
      local stat,res = pcall(function()
          fun(table.unpack(args)) 
        end)
      if not stat then print(res) end
    end,0)
end

local function main(env)
  mac = os.ipAddress():match("^192")~=nil
  init(env)
--  env.debug.rpc   = true
  env.debug.client   = true
  local cache = {}
  local ip = socket.dns.toip("localhost")
  cache.set = rpc.call(ip,30111,"setKeyValue")
  cache.get = rpc.call(ip,30111,"getKeyValue")

  local function test(key,r)
    local reps,t = r or 1000,os.clock()
    for i=1,reps do
      cache.set(key,i)
      if cache.get(key)~=i then error(key.." cache error:"..i) end
    end
    t = os.clock()-t
    DEBUG("client","SET/GET:%s %.3fms, %.0f transactions/s",key,t,reps/t)
  end

  process(test,"a",1000)
  process(test,"b",1000)
end

util.start(main)