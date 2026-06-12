-- Fannkuch-redux: array permutation / integer ops.
local N = tonumber(arg and arg[1]) or 10
local p, q, s = {}, {}, {}
for i = 1, N do p[i] = i; q[i] = i; s[i] = i end
local sign, maxflips, sum = 1, 0, 0
while true do
  local q1 = p[1]
  if q1 ~= 1 then
    for i = 2, N do q[i] = p[i] end
    local flips = 1
    while true do
      local qq = q[q1]
      if qq == 1 then
        sum = sum + sign * flips
        if flips > maxflips then maxflips = flips end
        break
      end
      q[q1] = q1
      if q1 >= 4 then
        local i, j = 2, q1 - 1
        repeat q[i], q[j] = q[j], q[i]; i = i + 1; j = j - 1 until i >= j
      end
      q1 = qq
      flips = flips + 1
    end
  end
  if sign == 1 then
    p[2], p[1] = p[1], p[2]; sign = -1
  else
    p[2], p[3] = p[3], p[2]; sign = 1
    local done = false
    for i = 3, N do
      local sx = s[i]
      if sx ~= 1 then s[i] = sx - 1; break end
      if i == N then done = true; break end
      s[i] = i
      local t = p[1]
      for j = 1, i do p[j] = p[j+1] end
      p[i+1] = t
    end
    if done then break end
  end
end
print(string.format("fannkuch(%d) sum=%d max=%d", N, sum, maxflips))
