-- Deterministic algorithms exercising integer-range math (< 2^53),
-- so LuaJIT (doubles) and Lua 5.4 (64-bit ints) agree under %d formatting.

-- Sieve of Eratosthenes
local function sieve(n)
  local is = {}
  for i = 2, n do is[i] = true end
  for i = 2, math.floor(math.sqrt(n)) do
    if is[i] then for j = i*i, n, i do is[j] = false end end
  end
  local primes = {}
  for i = 2, n do if is[i] then primes[#primes+1] = i end end
  return primes
end
local p = sieve(100)
print(#p, table.concat(p, ","))

-- gcd
local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end
print(gcd(1071, 462), gcd(48, 18))

-- string-based bignum-free factorial via float stays exact <= 18!
local function fact(n) local r = 1 for i = 2, n do r = r * i end return r end
print(string.format("%d %d %d", fact(5), fact(10), fact(15)))

-- quicksort
local function qsort(a, lo, hi)
  lo = lo or 1; hi = hi or #a
  if lo < hi then
    local pivot, i = a[hi], lo - 1
    for j = lo, hi - 1 do
      if a[j] <= pivot then i = i + 1; a[i], a[j] = a[j], a[i] end
    end
    a[i+1], a[hi] = a[hi], a[i+1]
    qsort(a, lo, i); qsort(a, i+2, hi)
  end
  return a
end
print(table.concat(qsort({9,3,7,1,8,2,6,4,5,0}), ","))

-- simple hash sum over a string
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 1000000007 end
  return h
end
print(hash("the quick brown fox jumps over the lazy dog"))
