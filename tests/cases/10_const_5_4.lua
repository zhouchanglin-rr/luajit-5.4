-- Lua 5.4 <const> attribute. This case ONLY passes because the LuaJIT side has
-- been ported to accept and enforce <const>. It must behave identically to the
-- Lua 5.4.8 reference, including the compile-time error on reassignment.

-- 1. Declaration and read.
local x <const> = 42
print(x)

-- 2. Mixed declaration; non-const neighbours remain writable.
local a, b <const>, c = 1, 2, 3
a = 10; c = 30
print(a, b, c)

-- 3. const used in expressions / closures.
local k <const> = 7
local function mul(n) return n * k end
print(mul(6))

-- 4. Reassigning a const is a COMPILE error. Use load() so we can observe it
--    as data and normalize the position prefix for cross-engine comparison.
local function strip(s) return type(s) == "string" and (s:gsub("^.-:%d+: ", "")) or s end
local f, err = load("local y <const> = 1; y = 2")
print(f == nil, strip(err))

-- 5. A valid const program loads fine.
local g = load("local z <const> = 5; return z * 2")
print(g())
