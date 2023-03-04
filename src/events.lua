
local debugFlags,format,equal,copy,toTime = fibaro.debugFlags,string.format,table.equal,table.copy,fibaro.toTime

--  local function DEBUG(...) if debugFlags.event then fibaro.debugf(nil,...) end end
local Events = {}

local em,handlers = { sections = {}, stats={tried=0,matched=0}},{}
em.BREAK, em.TIMER, em.RULE = '%%BREAK%%', '%%TIMER%%', '%%RULE%%'
em._handlers = handlers
local handleEvent,invokeHandler
local function isEvent(e) return type(e)=='table' and e.type end
local function isRule(e) return type(e)=='table' and e[em.RULE] end

local function post(ev,t,log)
  local now = os.time()
  t = type(t)=='string' and toTime(t) or t or 0
  if t < 0 then return elseif t < now then t = t+now end
  if debugFlags.post and (type(ev)=='function' or not ev._sh) then DEBUG('event',"Posting %s at %s%s",ev,os.date("%c",t),type(log)=='string' and ("("..log..")") or "") end
  if type(ev) == 'function' then
    return setTimeout(function() ev(ev) end,1000*(t-now),log)
  elseif isEvent(ev) then
    return setTimeout(function() handleEvent(ev) end,1000*(t-now),log)
  else
    error("post(...) not event or function;",tostring(ev))
  end
end
Event.post = post 

-- Cancel post in the future
function Event.cancel(ref) clearTimeout(ref) end

local function transform(obj,tf)
  if type(obj) == 'table' then
    local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
    return res
  else return tf(obj) end
end

local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
local constraints = {}
constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
constraints['<>'] = function(val) return function(x) return tostring(x):match(val) end end
constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
constraints[''] = function(_) return function(x) return x ~= nil end end
em.coerce = coerce

local function compilePattern2(pattern)
  if type(pattern) == 'table' then
    if pattern._var_ then return end
    for k,v in pairs(pattern) do
      if type(v) == 'string' and v:sub(1,1) == '$' then
        local var,op,val = v:match("$([%w_]*)([<>=~]*)(.*)")
        var = var =="" and "_" or var
        local c = constraints[op](tonumber(val) or val)
        pattern[k] = {_var_=var, _constr=c, _str=v}
      else compilePattern2(v) end
    end
  end
  return pattern
end

local function compilePattern(pattern)
  pattern = compilePattern2(copy(pattern))
  if pattern.type and type(pattern.id)=='table' and not pattern.id._constr then
    local m = {}; for _,id in ipairs(pattern.id) do m[id]=true end
    pattern.id = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.id}
  end
  return pattern
end

local function match(pattern0, expr0)
  local matches = {}
  local function unify(pattern,expr)
    if pattern == expr then return true
    elseif type(pattern) == 'table' then
      if pattern._var_ then
        local var, constr = pattern._var_, pattern._constr
        if var == '_' then return constr(expr)
        elseif matches[var] then return constr(expr) and unify(matches[var],expr) -- Hmm, equal?
        else matches[var] = expr return constr(expr) end
      end
      if type(expr) ~= "table" then return false end
      for k,v in pairs(pattern) do if not unify(v,expr[k]) then return false end end
      return true
    else return false end
  end
  return unify(pattern0,expr0) and matches or false
end

function invokeHandler(env)
  local t = os.time()
  env.last,env.rule.time = t-(env.rule.time or 0),t
  local status, res = pcall(env.rule.action,env) -- call the associated action
  if not status then
    if type(res)=='string' and not debugFlags.extendedErrors then res = res:gsub("(%[.-%]:%d+:)","") end
    DEBUG('event',"Error in %s: %s",env.rule.doc,res)
    env.rule._disabled = true -- disable rule to not generate more errors
    em.stats.errors=(em.stats.errors or 0)+1
  else return res end
end

local toHash,fromHash={},{}
fromHash['device'] = function(e) return {"device"..e.id..e.property,"device"..e.id,"device"..e.property,"device"} end
fromHash['global-variable'] = function(e) return {'global-variable'..e.name,'global-variable'} end
fromHash['quickvar'] = function(e) return {"quickvar"..e.id..e.name,"quickvar"..e.id,"quickvar"..e.name,"quickvar"} end
fromHash['profile'] = function(e) return {'profile'..e.property,'profile'} end
fromHash['weather'] = function(e) return {'weather'..e.property,'weather'} end
fromHash['custom-event'] = function(e) return {'custom-event'..e.name,'custom-event'} end
fromHash['deviceEvent'] = function(e) return {"deviceEvent"..e.id..e.value,"deviceEvent"..e.id,"deviceEvent"..e.value,"deviceEvent"} end
fromHash['sceneEvent'] = function(e) return {"sceneEvent"..e.id..e.value,"sceneEvent"..e.id,"sceneEvent"..e.value,"sceneEvent"} end
toHash['device'] = function(e) return "device"..(e.id or "")..(e.property or "") end   

toHash['global-variable'] = function(e) return 'global-variable'..(e.name or "") end
toHash['quickvar'] = function(e) return 'quickvar'..(e.id or "")..(e.name or "") end
toHash['profile'] = function(e) return 'profile'..(e.property or "") end
toHash['weather'] = function(e) return 'weather'..(e.property or "") end
toHash['custom-event'] = function(e) return 'custom-event'..(e.name or "") end
toHash['deviceEvent'] = function(e) return 'deviceEvent'..(e.id or "")..(e.value or "") end
toHash['sceneEvent'] = function(e) return 'sceneEvent'..(e.id or "")..(e.value or "") end

local function comboToStr(r)
  local res = { r.doc }
  for _,s in ipairs(r.subs) do res[#res+1]="   "..tostring(s) end
  return table.concat(res,"\n")
end
local function rule2str(rule) return rule.doc end

local function map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
local function mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end

local function comboEvent(e,action,rl,doc)
  local rm = {[em.RULE]=e, action=action, doc=doc, subs=rl}
  rm.enable = function() mapF(function(e0) e0.enable() end,rl) return rm end
  rm.disable = function() mapF(function(e0) e0.disable() end,rl) return rm end
  rm.tag = function(t) mapF(function(e0) e0.tag(t) end,rl) return rm end
  rm.start = function(event) invokeHandler({rule=rm,event=event}) return rm end
  rm.__tostring = comboToStr
  return rm
end

function Event.event(pattern,fun,doc)
  doc = doc or format("Event(%s) => ..",json.encodeFast(pattern))
  if type(pattern) == 'table' and pattern[1] then 
    return comboEvent(pattern,fun,map(function(es) return Event.event(es,fun) end,pattern),doc) 
  end
  if isEvent(pattern) then
    if pattern.type=='device' and pattern.id and type(pattern.id)=='table' then
      return Event.event(map(function(id) local e1 = copy(pattern); e1.id=id return e1 end,pattern.id),fun,doc)
    end
  else error("Bad event pattern, needs .type field") end
  assert(type(fun)=='function',"Second argument must be Lua function")
  local cpattern = compilePattern(pattern)
  local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
  handlers[hashKey] = handlers[hashKey] or {}
  local rules = handlers[hashKey]
  local rule,fn = {[em.RULE]=cpattern, event=pattern, action=fun, doc=doc}, true
  for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
    if equal(cpattern,rs[1].event) then 
      rs[#rs+1] = rule
      fn = false break 
    end
  end
  if fn then rules[#rules+1] = {rule} end
  rule.enable = function() rule._disabled = nil Event.post({type='ruleEnable',rule=rule,_sh=true}) return rule end
  rule.disable = function() rule._disabled = true Event.post({type='ruleDisable',rule=rule,_sh=true}) return rule end
  rule.start = function(event) invokeHandler({rule=rule, event=event, p={}}) return rule end
  rule.tag = function(t) rule._tag = t or __TAG; return rule end
  rule.__tostring = rule2str
  if em.SECTION then
    local s = em.sections[em.SECTION] or {}
    s[#s+1] = rule
    em.sections[em.SECTION] = s
  end
  if em.TAG then rule._tag = em.TAG end
  return rule
end

function Event.removeEvent(pattern,fun)
  local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
  local rules,i,j= handlers[hashKey] or {},1,1
  while j <= #rules do
    local rs = rules[j]
    while i <= #rs do
      if rs[i].action==fun then
        table.remove(rs,i)
      else i=i+i end
    end
    if #rs==0 then table.remove(rules,j) else j=j+1 end
  end
end

local function ruleHandler2string(e)
  return format("%s => %s",tostring(e.event),tostring(e.rule))
end

function handleEvent(ev)
  local hasKeys = fromHash[ev.type] and fromHash[ev.type](ev) or {ev.type}
  for _,hashKey in ipairs(hasKeys) do
    for _,rules in ipairs(handlers[hashKey] or {}) do -- Check all rules of 'type'
      local i,m=1,nil
      em.stats.tried=em.stats.tried+1
      for j=1,#rules do
        if not rules[j]._disabled then    -- find first enabled rule, among rules with same head
          m = match(rules[i][em.RULE],ev) -- and match against that rule
          break
        end
      end
      if m then                           -- we have a match
        for j=i,#rules do                 -- executes all rules with same head
          local rule=rules[j]
          if not rule._disabled then 
            em.stats.matched=em.stats.matched+1
            if invokeHandler({event = ev, p=m, rule=rule, __tostring=ruleHandler2string}) == em.BREAK then return end
          end
        end
      end
    end
  end
end

local function handlerEnable(t,handle)
  if type(handle) == 'string' then table.mapf(em[t],em.sections[handle] or {})
  elseif isRule(handle) then handle[t]()
  elseif type(handle) == 'table' then table.mapf(em[t],handle) 
  else error('Not an event handler') end
  return true
end

function Event.enable(handle,opt)
  if type(handle)=='string' and opt then 
    for s,e in pairs(em.sections or {}) do 
      if s ~= handle then handlerEnable('disable',e) end
    end
  end
  return handlerEnable('enable',handle) 
end
function Event.disable(handle) return handlerEnable('disable',handle) end

function Event.trueFor(time,test,action,delay)
  local timers = {}
  if type(delay)=='table' then
    delay = copy(delay)
    delay = delay[1] and delay or {delay}
    assert(isEvent(delay[1]),"4th argument not an event for trueFor(...)")
    local state,ref = false
    local function ac()
      if debugFlags.trueFor then DEBUG('trueFor',"trueFor: action()") end
      if action() then
        state = os.time()+time
        if debugFlags.trueFor then DEBUG('trueFor',"trueFor: rescheduling action()") end
        ref = setTimeout(ac,1000*(state-os.time()))
        timers[1]=ref
      else
        ref = nil
        timers[1]=nil
        state = true 
      end
    end
    local  function check()
      if test() then
        if state == false then
          state=os.time()+time
          if debugFlags.trueFor then DEBUG('trueFor',"trueFor: test() true, running action() in %ss",state-os.time()) end
          ref = setTimeout(ac,1000*(state-os.time()))
          timers[1]=ref
        elseif state == true then
          state = state -- NOP
        end
      else
        if ref then timers[1]=nil ref = clearTimeout(ref) end
        if debugFlags.trueFor then DEBUG('trueFor',"trueFor: test() false, cancelling action()") end
        state=false
      end
    end
    for _,e in ipairs(delay) do
      Event.event(e,check)
    end
    check()
    return function() 
      if timers[1] then clearTimeout(timers[1]) end
      for _,e in ipairs(delay) do Event.removeEvent(e,check) end
    end
  else
    delay = delay or 1000
    local state = false
    local  function loop()
      if test() then
        if state == false then
          state=os.time()+time
        elseif state == true then
          state = state -- NOP
        elseif state <=  os.time() then
          if action() then
            state = os.time()+time
          else
            state = true 
          end
        end
      else
        state=false
      end
      timers[1]=setTimeout(loop,delay)
    end
    loop()
    return function() if timers[1] then clearTimeout(timers[1]) end end 
  end
end
