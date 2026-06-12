-- Coroutines
local function producer()
  for i = 1, 5 do coroutine.yield(i * i) end
  return "done"
end
local co = coroutine.create(producer)
while true do
  local ok, val = coroutine.resume(co)
  print(ok, val, coroutine.status(co))
  if coroutine.status(co) == "dead" then break end
end

-- wrap
local gen = coroutine.wrap(function()
  local a, b = 0, 1
  while true do coroutine.yield(a); a, b = b, a + b end
end)
local fibs = {}
for _ = 1, 10 do fibs[#fibs+1] = gen() end
print(table.concat(fibs, ","))

-- two-way communication
local echo = coroutine.wrap(function(first)
  local x = first
  while true do x = coroutine.yield("got:" .. tostring(x)) end
end)
print(echo("a"), echo("b"), echo("c"))
