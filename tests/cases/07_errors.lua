-- Error handling: pcall, error, assert, select, varargs
local ok, err = pcall(function() error("boom") end)
print(ok, err:match("boom$") ~= nil)

local ok2, err2 = pcall(function() error({code=42}) end)
print(ok2, type(err2), err2.code)

-- error with level 0 (no position info)
local ok3, err3 = pcall(function() error("raw", 0) end)
print(ok3, err3)

-- Strip a leading "chunk:line: " position prefix. Lua 5.4's assert/error add
-- one; LuaJIT (5.1 lineage) does not for assert. We compare message *content*.
local function strip(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("^.-:%d+: ", ""))
end

-- assert pass-through
print(pcall(function() return assert(10, "unused") end))
do local ok, m = pcall(function() return assert(false, "failed!") end); print(ok, strip(m)) end
do local ok, m = pcall(function() return assert(nil) end); print(ok, strip(m)) end

-- xpcall with handler
local function handler(e) return "handled:" .. strip(e) end
print(xpcall(function() error("x") end, handler))

-- varargs and select
local function count(...) return select("#", ...) end
print(count(), count(1), count(1,2,nil,4))
local function pick(...) return select(2, ...) end
print(pick("a","b","c","d"))

-- nested pcall
print(pcall(pcall, function() error("inner") end))
