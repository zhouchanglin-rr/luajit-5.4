-- Ackermann: deep non-tail recursion.
local M = tonumber(arg and arg[1]) or 3
local N = tonumber(arg and arg[2]) or 9
local function ack(m, n)
  if m == 0 then return n + 1 end
  if n == 0 then return ack(m - 1, 1) end
  return ack(m - 1, ack(m, n - 1))
end
print(string.format("ack(%d,%d)=%d", M, N, ack(M, N)))
