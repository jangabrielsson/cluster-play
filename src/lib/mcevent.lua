local copas, socket, json, util, multicast, DEBUG

local mcevent = {}
local EVENTS  = {}

local function msgHandler(data,ip,port)
  local event = json.decode(data)
  if type(event)=='table' and event.type then
    local handler = EVENTS[event.type]
    if type(handler)=='function' then
      local stat,res = pcall(handler,event,ip,port)
      if not stat then DEBUG("mcevent","handler error:%s",res) end
    end
  else DEBUG("mcevent","bad data:%s",data) end
end

function mcevent.startListening(ip,port)
  mcevent.ip,mcevent.port = ip,port
  multicast.startListener(ip,port,msgHandler)
end

local mcast 
function mcevent.send(msg)
  mcast = mcast or multicast.send(mcevent.ip,mcevent.port)
  mcast(json.encode(msg))
end

function mcevent.event(typ,callback)
  EVENTS[typ]=callback
end

function mcevent.init(env)
  copas = env.copas 
  socket = env.socket
  json = env.json
  util = env.util
  multicast = env.multicast
  env.mcevent = mcevent
  mcevent.ip = ip
  mcevent.port = port
  DEBUG = env.DEBUG
end

return mcevent