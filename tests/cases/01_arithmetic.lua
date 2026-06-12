-- Arithmetic, using explicit formatting so integer/float display differences
-- between LuaJIT (dual-number) and Lua 5.4 (int/float subtypes) do not matter.
local function f(x) return string.format("%.6g", x) end

print(f(1+2), f(10-3), f(6*7), f(20/8))
print(f(2^10), f(math.floor(7/2)), f(7 % 3), f(-7 % 3))
print(f(math.fmod(7,3)), f(math.fmod(-7,3)))
print(f(1e9 * 3), f(123456789 + 987654321))
print(string.format("%d %d %d", 5, -5, 0))
print(string.format("%x %o", 255, 8))

-- comparison chain
local a, b, c = 3, 5, 5
print(a < b, b <= c, a == b, b == c, a ~= b)

-- precedence
print(f(2 + 3 * 4 - 1), f((2+3) * (4-1)), f(2^2^3))

-- math helpers
print(f(math.abs(-9)), f(math.max(1,7,3)), f(math.min(4,2,8)))
print(f(math.sqrt(144)), math.huge > 1e300)
print(string.format("%.4f %.4f", math.sin(0), math.cos(0)))
