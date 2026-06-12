-- Repeated Sieve of Eratosthenes: array writes / integer loops.
local N = tonumber(arg and arg[1]) or 4000000
local REPS = tonumber(arg and arg[2]) or 5
local count = 0
for _ = 1, REPS do
  local flags = {}
  for i = 2, N do flags[i] = true end
  count = 0
  for i = 2, N do
    if flags[i] then
      count = count + 1
      for j = i + i, N, i do flags[j] = false end
    end
  end
end
print(string.format("sieve primes<=%d count=%d", N, count))
