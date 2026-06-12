-- String library: common subset shared by LuaJIT and Lua 5.4
local s = "Hello, Lua World"
print(#s, s:upper(), s:lower())
print(s:sub(1,5), s:sub(-5), s:sub(8,10))
print(s:find("Lua"), s:find("xyz"))
print(("ab"):rep(3), ("ab"):rep(3, "-"))
print(string.byte("A"), string.char(72,105))
print(("a,b,c,d"):gsub(",", ";"))

-- gmatch tokenizing
local out = {}
for w in ("the quick brown fox"):gmatch("%a+") do out[#out+1] = w end
print(table.concat(out, "|"))

-- captures
local d, m, y = ("21/06/2026"):match("(%d+)/(%d+)/(%d+)")
print(d, m, y)

-- format variety
print(string.format("[%5d][%-5d][%05.2f][%s]", 42, 42, 3.14159, "x"))
print(string.format("%q", "line\n\"quote\""))

-- reverse / len
print(("abcde"):reverse(), ("hello"):len())
