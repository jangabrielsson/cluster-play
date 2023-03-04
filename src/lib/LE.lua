----------------------------------------
-- LE - Light Event Library
-- Documentation at https://forum.fibaro.com/topic/49113-hc3-quickapps-coding-tips-and-tricks/?do=findComment&comment=251398
-----------------------------------------

local function lightEvents(env)
  local LE = { debug = true  }
  local EVENT={}; LE._event = EVENT
  function LE:event(ev,fun)
    assert(ev.type,"Event missing type")
    local t = ev.type
    local p = t:sub(1,1)
    if p=='+' then p ='post' t=t:sub(2)
    elseif p=='-' then p ='pre' t=t:sub(2)
    else p ='mid' end
    local tab = EVENT[t] or {pre={},mid={},post={}}
    tab[p][#tab[p]+1]=fun
    EVENT[t]=tab
  end
  local function _debugf(self,...) _DEBUG(...) end
  local function _print(self,...) print(self._tag,...) end
  local function callHandlers(hs,event)
    for _,f in ipairs(hs) do
      local stat,res = pcall(f,event)
      if not stat then error(res,3) end
    end
  end
  local function _post(self,event,sec)
    sec = sec or 0
    return setTimeout(function()
        local t = event.type
        assert(t,"Missing event type")
        local hs = EVENT[t]
        assert(hs,"Undefined event type:"..t)        
        self:debugf("Event:%s",t)
        if #hs.pre>0 then callHandlers(hs.pre,event) end
        if #hs.mid>0 then callHandlers(hs.mid,event) end
        if #hs.post>0 then callHandlers(hs.post,event) end
      end,1000*(sec >= os.time() and sec-os.time() or sec))
  end
  function LE:cancel(ref) clearTimeout(ref) end
  function LE:post(event,sec,ctx)
    ctx=ctx or {}
    ctx.post,ctx.debugf,ctx.trace,ctx.print,ctx.error,ctx.http,ctx._tag=_post,_debugf,_trace,_print,_error,LE._send,ctx._tag or ""
    ctx.debugFlag = LE.debugFlag or "LE"
    _post(ctx,event,sec) 
  end
  return LE
end

----------------------------------------------------
-- Example
-----------------------------------------------------

--local LE = lightEvents()
--if true then -- redefine send for test purpose when no access to remote server
--  local resps={ login={{value={token={name="myToken"}}}}, value={{value={enable=0}}} } -- Fixed responses
--  function LE._send(self,event,method,path,_) -- ignore data, we make our own response
--    local url,resp = (self.baseURL or "")..path,{}
--    for t,d in pairs(resps) do if path:match(t) then resp=d break end end
--    self:debug("success ",url,json.encode(resp))
--    self:post({type=event.type.."_success",url=url,data=resp})
--  end
--end
--EVENT = LE.event

--function EVENT:test1(event)
--  self:post({type='test2',a=event.a+1},event.a)
--end

--function EVENT:test2(event)
--  self:post({type='test3',a=event.a+1},event.a)
--end

--function EVENT:test3(event)
--  self:dispatch("device_%2_%1",event.id,">30",event.value,"==value")
--  self:print(event.a)
--end

--function QuickApp:onInit()
--  self:debug(self.name, self.id)
--  LE:post({type='test1',a=1})
--  LE:post({type='test1',a=2})
--  LE:post({type='test1',a=3})
--end

--function EVENT:test1(event)
--  self.b=self.b+1
--  self:post({type='test2',a=event.a+1})
--end

--function EVENT:test2(event)
--  self.b=self.b+1
--  self:post({type='test3',a=event.a+1})
--end

--function EVENT:test3(event)
--  self:print(event.a,self.b)
--end

--function QuickApp:onInit()
--  self:debug(self.name, self.id)
--  LE:post({type='test1',a=9},0,{b=8,_tag="A1"})
--  LE:post({type='test1',a=10},0,{b=6,_tag="A2"})
--  LE:post({type='test1',a=12},0,{b=5,_tag="A3"})
--end

------

--function EVENT:getValue(event)
--  self:http(event,"GET","valueGet&name='X'")
--end
--function EVENT:getValue_success(event)
--  self:debug("Enable:",event.data[1].value.enable)
--end
--function EVENT:getValue_error(event)
--  self:error(event.error)
--end

--function QuickApp:onInit()
--  self:debug(self.name, self.id)
--  local pwd = self:getVariable("password")
--  LE:post({type='getValue'},0,{pwd=pwd,baseURL="http://myservices?cmd="})
--end

------

--function EVENT:getValue(event)
--  if not self.token then
--      self.nextStep = 'getValue'
--      self:post({type='login'})
--  else 
--    self:http(event,"GET","valueGet&name=X&token="..self.token)
--  end
--end
--function EVENT:getValue_success(event)
--  self:debug("Enable:",event.data[1].value.enable)
--end
--function EVENT:getValue_error(event)
--  self:error(event.error)
--end
--function EVENT:login(event)
--  self:http(event,"GET","login&pwd="..self.pwd)
--end
--function EVENT:login_success(event)
--  self:debug("Logged in")
--  self.token = event.data[1].value.token.name
--  self:post({type=self.nextStep})
--end
--function EVENT:login_error(event)
--  self:eror(event.error)
--end

--function QuickApp:onInit()
--  self:debug(self.name, self.id)
--  local pwd = self:getVariable("password")
--  LE:post({type='getValue'},0,{pwd=pwd,baseURL="http://myservices?cmd="})
--end


return lightEvents
