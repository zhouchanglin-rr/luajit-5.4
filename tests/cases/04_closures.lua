-- Closures, upvalues, recursion
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c = counter()
print(c(), c(), c())

local function adder(x) return function(y) return x + y end end
print(adder(10)(5), adder(100)(23))

-- shared upvalue between two closures
local function pair()
  local v = 0
  local function get() return v end
  local function set(x) v = x end
  return get, set
end
local g, s = pair()
s(42); print(g())

-- recursion
local function fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end
print(fib(20))

-- mutual recursion
local even, odd
function even(n) if n == 0 then return true else return odd(n-1) end end
function odd(n) if n == 0 then return false else return even(n-1) end end
print(even(10), odd(10))

-- tail-call deep loop
local function loop(n, acc) if n == 0 then return acc end return loop(n-1, acc+n) end
print(loop(100000, 0))
