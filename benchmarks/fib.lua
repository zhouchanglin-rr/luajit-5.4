-- Recursive Fibonacci: function-call / recursion stress.
local N = tonumber(arg and arg[1]) or 34
local function fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end
local r = fib(N)
print(string.format("fib(%d)=%d", N, r))
