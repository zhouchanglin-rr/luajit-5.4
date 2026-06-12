-- Lua 5.3/5.4 utf8 library. Passes only because LuaJIT was extended with a
-- ported utf8 library; output must match the Lua 5.4.8 reference exactly.

-- charpattern length
print(#utf8.charpattern)

-- len over multibyte text
print(utf8.len("héllo wörld"), utf8.len("aé€😀"))

-- char: build strings from codepoints (ascii, 2-, 3-, 4-byte)
print(utf8.char(72, 233, 108, 108, 111))      -- Héllo
print(#utf8.char(0x1F600), #utf8.char(0x10FFFF))

-- codepoint over a range
print(utf8.codepoint("héllo", 1, 6))

-- offset: forward, the 0 case, and from the end
print(utf8.offset("héllo", 3), utf8.offset("héllo", 1), utf8.offset("héllo", -1))

-- codes iteration (position:codepoint pairs)
local out = {}
for p, c in utf8.codes("aé€") do out[#out+1] = p .. ":" .. c end
print(table.concat(out, ","))

-- roundtrip: every codepoint encodes and decodes back
local ok = true
for _, cp in ipairs({0x41, 0xE9, 0x20AC, 0x1F600, 0x10FFFF}) do
  if utf8.codepoint(utf8.char(cp)) ~= cp then ok = false end
end
print("roundtrip", ok)

-- invalid sequence -> fail + byte position (normalize so it matches)
print(utf8.len("a\xFFb"))

-- out-of-range char raises; compare behaviour, not the function name in msg
local good, msg = pcall(utf8.char, 0x80000000)
print(good, type(msg) == "string" and msg:match("out of range") ~= nil)
