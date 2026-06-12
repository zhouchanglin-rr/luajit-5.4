#!/usr/bin/env bash
#
# check_5x_syntax.sh - Audit this project's LuaJIT support for Lua 5.3 / 5.4
# language features and standard-library additions, against the Lua 5.4.8
# reference. Each probe is classified by:
#   VER  : the Lua version that introduced it (5.3 or 5.4)
#   KIND : syntax (parser) | library (stdlib) | semantics (runtime behaviour)
#
# A probe is "OK" on LuaJIT when running it does not error AND the result
# matches the intent. "FAIL" means LuaJIT errors or diverges from 5.4.8.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA54="$ROOT/build/bin/lua54"
LUAJIT="$ROOT/build/bin/luajit"

# Run a snippet and strip the engine's absolute-path prefix so error messages
# from both engines are directly comparable (both reduce to "(command line):N: ...").
run() { "$1" -e "$2" 2>&1 | head -1 | sed -e "s#$LUA54: ##g" -e "s#$LUAJIT: ##g"; }
errored() { [[ "$1" == *"(command line):"* ]]; }

n_ok=0; n_fail=0
probe() {
  local ver="$1" kind="$2" desc="$3" snippet="$4"
  local r j status
  r="$(run "$LUA54" "$snippet")"
  j="$(run "$LUAJIT" "$snippet")"
  if [[ "$r" == "$j" ]]; then
    # Identical output (including identical error messages) => behaviour matches.
    status=" OK "; n_ok=$((n_ok+1))
  elif errored "$j" && ! errored "$r"; then
    # LuaJIT errors where 5.4.8 succeeds => unsupported feature (porting gap).
    status="FAIL"; n_fail=$((n_fail+1))
  else
    # Both run but produce different results => semantic divergence.
    status="DIFF"; n_fail=$((n_fail+1))
  fi
  printf "[%s] %-4s %-9s | %s\n" "$status" "$ver" "$kind" "$desc"
  printf "        5.4.8 : %s\n" "$r"
  printf "        luajit: %s\n" "$j"
}

echo "######################################################################"
echo "# Lua 5.3 language features"
echo "######################################################################"
probe 5.3 syntax    "floor division operator  //"          'print(7 // 2)'
probe 5.3 syntax    "bitwise AND  &"                        'print(6 & 3)'
probe 5.3 syntax    "bitwise OR  |"                         'print(4 | 1)'
probe 5.3 syntax    "bitwise XOR / NOT  ~"                  'print(5 ~ 1, ~0)'
probe 5.3 syntax    "shift operators  << >>"                'print(1 << 4, 256 >> 2)'
probe 5.3 syntax    "\\u{} unicode string escape"           'print(#"\u{48}\u{49}")'
probe 5.3 semantics "integer/float subtype (math.type)"    'print(math.type(1), math.type(1.0))'
probe 5.3 semantics "float prints with .0"                 'print(10.0)'
probe 5.3 semantics "64-bit integer exact > 2^53"          'print(9007199254740993)'
probe 5.3 library   "math.maxinteger / mininteger"         'print(math.maxinteger)'
probe 5.3 library   "math.tointeger"                        'print(math.tointeger(3.0))'
probe 5.3 library   "string.pack"                           'print(#string.pack("i4", 1))'
probe 5.3 library   "string.unpack"                         'print((string.unpack("i4", string.rep("\1",4))))'
probe 5.3 library   "string.packsize"                       'print(string.packsize("i8"))'
probe 5.3 library   "table.move"                            'local t={1,2,3}; table.move(t,1,3,2); print(t[2],t[3],t[4])'
probe 5.3 library   "utf8.len / utf8.char"                  'print(utf8 and utf8.len("abc"))'
probe 5.3 library   "coroutine.isyieldable"                'print(type(coroutine.isyieldable))'

echo
echo "######################################################################"
echo "# Lua 5.4 language features"
echo "######################################################################"
probe 5.4 syntax    "local <const> attribute (PORTED)"     'local x <const> = 5; print(x)'
probe 5.4 semantics "<const> reassignment is an error"     'local x <const> = 1; x = 2'
probe 5.4 syntax    "local <close> attribute"              'local x <close> = setmetatable({},{__close=function()end}); print("ok")'
probe 5.4 library   "coroutine.close"                       'print(type(coroutine.close))'
probe 5.4 library   "warn()"                                'print(type(warn))'
probe 5.4 library   "math.random integer-range arg"        'math.randomseed(1); local v=math.random(1,6); print(v>=1 and v<=6)'
probe 5.4 semantics "integer for-loop stays integer"       'for i=1,1 do print(math.type and math.type(i) or "n/a") end'

echo
echo "######################################################################"
echo "# Already-supported pre-5.3 extensions (sanity)"
echo "######################################################################"
probe 5.2 syntax    "goto / labels"                         'do ::a:: print("g") end'
probe 5.2 library   "table.pack / table.unpack"             'local t=table.pack(1,2,3); print(t.n, (table.unpack(t)))'

echo "######################################################################"
printf "SUMMARY: OK=%d  FAIL/DIFF=%d\n" "$n_ok" "$n_fail"
echo "Note: 'OK' means LuaJIT matches Lua 5.4.8 for that probe."
