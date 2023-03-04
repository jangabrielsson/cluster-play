local copas, socket, json, util, DEBUG

local udp = {}

local function udp.send(host,port)
  local key = host..port
  if cs[key] then return cs[key] end
  local sock = copas.wrap(socket.upd())--, ssl_params)
  cs[key] = function(msg)
    msg = json.encode(msg)
    sock:send(msg.."\n")
  end
  return cs[key]
end

local function startHandler(port,callback)
  local server = socket.udp()
  server:setsockname("*",port)
  function handler(skt)
    skt = copas.wrap(skt)
    print("UDP connection handler")

    while true do
      local s, err
      print("receiving...")
      msg, err = skt:receive()
      if not msg then
        print("Receive error: ", err)
        return
      end
      callback(msg)
    end
  end
  copas.addserver(server, handler, 1)
end

function udp.init(env,port,handler)
  copas = env.copas 
  socket = env.socket
  json = env.json
  util = env.util
  env.udp = udp
  DEBUG = env.DEBUG
  udp.port = port or 8769
  startHandler(port,handler)
end

return udp
