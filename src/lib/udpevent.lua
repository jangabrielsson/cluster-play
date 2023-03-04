local copas, socket, json, util, udp, DEBUG

local udpevent = {}
local EVENTS  = {}

local function msgHandler(data,ip,port)
  local event = json.decode(data)
  if type(event)=='table' and event.type then
    local handler = EVENTS[event.type]
    if type(handler)=='function' then
      local stat,res = pcall(handler,event,ip,port)
      if not stat then DEBUG("udpevent","handler error:%s",res) end
    end
  else DEBUG("udpevent","bad data:%s",data) end
end

function udpevent.startListening(port)
  udpevent.port = port
  udp.startListener(port,msgHandler)
end

function udpevent.send(ip,msg)
  udp.send(ip,udpevent.port,(json.encode(msg)))
end

function udpevent.event(typ,callback)
  EVENTS[typ]=callback
end

function udpevent.init(env)
  copas = env.copas 
  socket = env.socket
  json = env.json
  util = env.util
  udp = env.udp
  env.udpevent = udpevent
  DEBUG = env.DEBUG
end

return udpevent