local copas, socket, json, util, DEBUG

local udp = {}

function udp.startListener(port,callback,opts)
  port = tonumber(port)
  assert(type(port)=='number',"upd port needs number")
  assert(type(callback)=='function',"udp callback needs function")
  opts = opts or {}
  opts.debug = opts.debug or "udp"
  opts.name = opts.name or "UDP server"
  local server = socket.udp()
  server:setsockname("*",port)
  server = copas.wrap(server)
  udp.server = server
  local function handler(skt)
    DEBUG(opts.debug,"%s started at %s",opts.name,port)

    while true do
      local s, ip, port = skt:receivefrom()
      if not s then
        DEBUG(opts.debug,"Receive error: ", ip)
        return
      end
      DEBUG(opts.debug,"Received data:%s" ,s)
      callback(s,ip,port)
    end
  end
  copas.addserver(server, handler, 1)
end

function udp.send(ip,port,msg)
  udp.server:sendto(msg,ip,port)
end

function udp.init(env)
  copas   = env.copas 
  socket  = env.socket
  json    = env.json
  util    = env.util
  env.udp = udp
  DEBUG   = env.DEBUG
end

return udp
