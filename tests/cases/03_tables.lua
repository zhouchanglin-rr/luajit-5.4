-- Table library and iteration
local t = {5, 3, 9, 1, 7, 2}
table.sort(t)
print(table.concat(t, ","))
table.sort(t, function(a,b) return a > b end)
print(table.concat(t, ","))

table.insert(t, 100)
table.insert(t, 1, -1)
print(table.concat(t, ","))
print(table.remove(t), table.remove(t, 1))
print(table.concat(t, ","))

-- length and holes (well-defined sequence ops only)
local seq = {}
for i = 1, 10 do seq[i] = i * i end
print(#seq, seq[1], seq[10])

-- key iteration in sorted order for determinism
local m = {banana=3, apple=5, cherry=1}
local keys = {}
for k in pairs(m) do keys[#keys+1] = k end
table.sort(keys)
for _, k in ipairs(keys) do io.write(k, "=", m[k], " ") end
print()

-- nested
local matrix = {{1,2,3},{4,5,6},{7,8,9}}
local sum = 0
for i=1,#matrix do for j=1,#matrix[i] do sum = sum + matrix[i][j] end end
print("sum", sum)
