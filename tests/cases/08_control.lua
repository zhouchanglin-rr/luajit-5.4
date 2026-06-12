-- Control flow: numeric/generic for, while, repeat, break, goto
local acc = {}
for i = 1, 10, 2 do acc[#acc+1] = i end
print(table.concat(acc, ","))

acc = {}
for i = 10, 1, -3 do acc[#acc+1] = i end
print(table.concat(acc, ","))

-- while + break
local n, p = 1, 1
while true do p = p * 2; n = n + 1; if p > 1000 then break end end
print(n, p)

-- repeat until
local k = 0
repeat k = k + 1 until k >= 5
print(k)

-- goto (Lua 5.2+/LuaJIT 2.1 both support labels)
do
  local i = 0
  ::top::
  i = i + 1
  if i < 5 then goto top end
  print("goto reached", i)
end

-- continue pattern via goto
local sum = 0
for i = 1, 10 do
  if i % 2 == 0 then goto cont end
  sum = sum + i
  ::cont::
end
print("odd sum", sum)
