-- Metatables and metamethods (common subset)
local Vec = {}
Vec.__index = Vec
function Vec.new(x, y) return setmetatable({x=x, y=y}, Vec) end
function Vec.__add(a, b) return Vec.new(a.x+b.x, a.y+b.y) end
function Vec.__eq(a, b) return a.x==b.x and a.y==b.y end
function Vec.__lt(a, b) return (a.x*a.x+a.y*a.y) < (b.x*b.x+b.y*b.y) end
function Vec.__tostring(v) return string.format("(%d,%d)", v.x, v.y) end
function Vec.__call(v, k) return v.x*k, v.y*k end

local a = Vec.new(1, 2)
local b = Vec.new(3, 4)
print(tostring(a + b))
print(a == Vec.new(1,2), a == b)
print(a < b, b < a)
print(a(10))

-- __index function fallback
local defaults = setmetatable({}, {__index = function(_, k) return "default:"..k end})
defaults.real = "value"
print(defaults.real, defaults.missing)

-- __newindex capture
local log = {}
local proxy = setmetatable({}, {__newindex = function(t, k, v) log[#log+1] = k.."="..tostring(v) end})
proxy.a = 1; proxy.b = 2
print(table.concat(log, ","))
