local json,socket,copas,util,DEBUG
local web = {}

function web.clientAsyncHandler(client,handler)
  local headers,referer = {}
  while true do
    local l,_,_ = client:receive()
    DEBUG("web_extra","Request:%s",l)
    if l then
      local body,header,e,b
      local method,call = l:match("^(%w+) (.*) HTTP/1.1")
      repeat
        header,e,b = client:receive()
        if header then
          local key,val = header:match("^(.-):%s*(.*)")
          referer = key and key:match("^[Rr]eferer") and val or referer
          if key then headers[key:lower()] = val
            DEBUG("web_extra","Header:%s",header)
          elseif header~="" then
            DEBUG("web_extra","Unknown request data:%s",header or "nil") 
          end
        end
        if header=="" then
          if headers['content-length'] and tonumber(headers['content-length'])>0 then
            body = client:receive(tonumber(headers['content-length']))
            DEBUG("web_extra","Body:%s",body) 
          end
          header=nil
        end
      until header == nil or e == 'closed'
      DEBUG("web_extra","Request served:%s",l)
      if handler then handler(method,client,call,body,referer,headers) end
      client:close()
      return
    end
  end
end

local paths= {}

local dfltPage =
[[HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Origin
Content-Type: text/html

<!DOCTYPE html>
<html>
<body>
OK
</body>
</html>
]]

local function webhandler(method,client,call,body,referer,headers)
 -- DEBUG("web",method,call)
  if paths[call] then paths[call](client,headers) else
    DEBUG("probe","DEFAULT:%s",call)
    client:send(dfltPage)
  end
end

local serverStarted = false
function web.start(port)
  if not serverStarted then
    util.createAsyncServer("My webserver",port,
      function(skt) web.clientAsyncHandler(skt,webhandler) end,
      "probe"
    )
    serverStarted = true
  end
end

function web.init(env,port)
  copas = env.copas 
  socket = env.socket
  json = env.json
  util = env.util
  env.web = web
  web.port = port or 8767
  DEBUG = env.DEBUG
end

function web.probe(path,istate,cb)
  local state = { state = istate, cb = cb }
  local count,last=0
  paths[path] = function(client)
    count=count+1
    if state.state ~= last then
      last = state.state
      DEBUG("probe","%s=%s (%s)",path,state.state,count)
    end
    local res = dfltPage:gsub("200",tostring(state.state and 200 or 500))
    client:send(res)
    if state.cb then state.cb(state.state) end
  end
  return state
end

return web