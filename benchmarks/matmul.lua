-- Naive matrix multiplication: nested-loop / array indexing.
local N = tonumber(arg and arg[1]) or 150
local function gen(seed)
  local m = {}
  for i = 1, N do
    m[i] = {}
    for j = 1, N do seed = (seed * 1009 + 13) % 100003; m[i][j] = seed % 100 end
  end
  return m
end
local a, b = gen(1), gen(2)
local c = {}
for i = 1, N do
  local ci, ai = {}, a[i]
  for j = 1, N do
    local s = 0
    for k = 1, N do s = s + ai[k] * b[k][j] end
    ci[j] = s
  end
  c[i] = ci
end
local trace = 0
for i = 1, N do trace = trace + c[i][i] end
print(string.format("matmul N=%d trace=%d c11=%d", N, trace, c[1][1]))
