#!/usr/bin/env bash
#
# show_differences.sh - Empirically catalog Lua 5.4 features/semantics that
# LuaJIT does NOT implement. Each probe is a tiny snippet run under both
# engines via `-e`; we print both results side by side. A "syntax error" or
# differing value marks a porting gap.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA54="$ROOT/build/bin/lua54"
LUAJIT="$ROOT/build/bin/luajit"

run() { "$1" -e "$2" 2>&1 | head -1; }

probe() {
  local desc="$1" snippet="$2"
  local r j
  r="$(run "$LUA54" "$snippet")"
  j="$(run "$LUAJIT" "$snippet")"
  local mark="SAME"
  [[ "$r" != "$j" ]] && mark="DIFF"
  printf "[%s] %s\n" "$mark" "$desc"
  printf "      5.4.8 : %s\n" "$r"
  printf "      luajit: %s\n" "$j"
}

echo "=================================================================="
echo " Lua 5.4 feature probes  (DIFF = LuaJIT porting gap)"
echo "=================================================================="

probe "integer/float subtypes (math.type)"      'print(math.type(1), math.type(1.0))'
probe "integer literal prints without .0"        'print(1, 2, 3)'
probe "float prints with .0 (5.4) vs 3 (jit)"    'print(3.0)'
probe "floor division operator //"               'print(7 // 2, -7 // 2)'
probe "native bitwise AND  &"                    'print(5 & 3)'
probe "native bitwise OR/XOR/NOT/shift"          'print(5 | 2, 5 ~ 1, ~0, 1 << 4)'
probe "math.maxinteger / mininteger"             'print(math.maxinteger, math.mininteger)'
probe "64-bit integer exactness > 2^53"          'print(9007199254740993)'
probe "integer overflow wraps (5.4) "            'print(math.maxinteger + 1)'
probe "tointeger"                                'print(math.tointeger(3.0), math.tointeger(3.5))'
probe "string.pack / string.unpack"              'print(#string.pack("i4", 1))'
probe "string-to-int coercion keeps int"         'print(math.type("10" + 0))'
probe "local <const> attribute"                  'local x <const> = 5; print(x)'
probe "local <close> attribute (to-be-closed)"   'local x <close> = setmetatable({},{__close=function() end}); print("ok")'
probe "goto / labels (both support)"             'do ::a:: print("g") end'
probe "bit library (LuaJIT-only ext)"            'print(bit and bit.band(5,3))'
probe "utf8 library"                             'print(utf8 and utf8.len("abc"))'
probe "os.exit boolean arg"                      'os.exit(true)'

echo "=================================================================="
echo "Legend: SAME = behaviour matches; DIFF = divergence to port."
