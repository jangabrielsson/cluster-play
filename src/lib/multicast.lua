local copas, socket, json, util, DEBUG

local multicast = {}

function multicast.startListener(ip,port,callback)
  ip,port = ip or "226.192.1.1", port or 11111
  local listen = socket.udp()
--  listen:setoption('broadcast',true)
--  listen:setoption('reuseaddr',true)
  listen:setoption('reuseport',true)
  listen:setsockname(ip,port)  --this only works if the device supports multicast
  local name = listen:getsockname()
  assert(name,"multicast not supported")  --test to see if device supports multicast
  listen:setoption( "ip-add-membership", { multiaddr=ip, interface = os.ipAddress() } )
  listen:setoption('ip-multicast-loop',false)
  --listen:settimeout(0)  --move along if there is nothing to hear

  function handler(skt)
    skt = copas.wrap(skt)
    DEBUG("multicast","Multicast listener %s:%s",ip,port)
    while true do
      local data,ip,port = skt:receivefrom()
      if not data then
        if ip~='timeout' then 
          DEBUG("multicast","Receive error: ", ip)
        end
      else 
        DEBUG("multicast","data from %s:%s",ip,port)
        callback(data,ip,port) 
      end
    end
  end

  copas.addserver(listen, handler, 1)
end

function multicast.send(ip,port)
  ip,port = ip or "226.192.1.1",port or 11111
  local send = socket.udp()
  send:settimeout( 0 )  --this is important 
  return function(msg) 
    --multicast IP range from 224.0.0.0 to 239.255.255.255
    DEBUG("multicast","sending %s:%s - '%s'",ip,port,msg)
    send:sendto( msg, ip, port )
  end
end

function multicast.init(env)
  copas = env.copas 
  socket = env.socket
  json = env.json
  util = env.util
  env.multicast = multicast
  DEBUG = env.DEBUG
end

return multicast