-- Lua 5.3/5.4 string.pack/unpack/packsize. Passes only because LuaJIT was
-- extended with a ported implementation; output must match Lua 5.4.8 exactly.
-- Values stay within 2^53 so the double-based LuaJIT numbers are exact.

-- packsize of fixed-width formats
print(string.packsize("i4"), string.packsize("i4i8d"), string.packsize(">!8 i4 d"))

-- integer roundtrip across widths and endianness
print(string.unpack("i4", string.pack("i4", 305419896)))
print(string.unpack(">i2 <i2", string.pack(">i2 <i2", 258, -2)))
print(string.unpack("<I4", string.pack("<I4", 4000000000)))

-- exact byte layout (endianness)
print(string.byte(string.pack(">i4", 0x01020304), 1, 4))
print(string.byte(string.pack("<i4", 0x01020304), 1, 4))

-- floats / doubles roundtrip (format to fixed precision for determinism)
print(string.format("%.5f", (string.unpack("d", string.pack("d", 3.14159)))))
print(string.format("%.3f", (string.unpack("f", string.pack("f", 2.5)))))

-- length-prefixed and zero-terminated strings
print(string.unpack("s4", string.pack("s4", "hello world")))
print(string.unpack("z", string.pack("z", "zterm")))

-- fixed-size char field with padding
local packed = string.pack("c8", "abc")
print(#packed, (packed:gsub("%z", ".")))

-- alignment: '!8' aligns the double to an 8-byte boundary
local p = string.pack("!8 b d", 1, 2.5)
print(#p, string.unpack("!8 b d", p))

-- multiple values + final position
print(string.unpack("i1i1i1", string.pack("i1i1i1", 10, 20, 30)))
