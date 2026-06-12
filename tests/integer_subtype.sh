#!/usr/bin/env bash
#
# integer_subtype.sh - Validate the integer/float subtype implemented in the
# dual-number LuaJIT variant (build/bin/luajit-int) against the Lua 5.4.8
# reference. See docs/INTEGER_SUBTYPE_PLAN.md.
#
# This documents BOTH what the subtype gets right and the 32-bit boundary
# (LuaJIT's dual-number integers are 32-bit; Lua 5.4's are 64-bit).
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA54="$ROOT/build/bin/lua54"
LJINT="$ROOT/build/bin/luajit-int"

[[ -x "$LJINT" ]] || { echo "build/bin/luajit-int missing; run scripts/build.sh" >&2; exit 2; }

ok=0; bad=0
chk() {  # chk "expect" "snippet"
  local mode="$1" code="$2" r j status
  r="$("$LUA54" -e "$code" 2>&1)"
  j="$("$LJINT" -e "$code" 2>&1)"
  if [[ "$r" == "$j" ]]; then status="OK  "; ok=$((ok+1)); else status="DIFF"; bad=$((bad+1)); fi
  printf "[%s] %-6s %s\n" "$status" "$mode" "$code"
  [[ "$r" != "$j" ]] && { printf "        5.4.8 : %s\n" "$r"; printf "        lj-int: %s\n" "$j"; }
}

echo "=================================================================="
echo " Integer/float subtype on luajit-int  (vs Lua 5.4.8)"
echo "=================================================================="
echo "-- math.type / classification --------------------------------------"
chk type 'print(math.type(1), math.type(1.0), math.type("x"), math.type(nil))'
chk type 'print(math.type(3), math.type(3.0), math.type(3.5))'
chk type 'print(math.type(1+2), math.type(1+2.0), math.type(2/1), math.type(2^2), math.type(5%2))'
chk type 'print(math.type(-7), math.type(-7.0), math.type(0), math.type(0.0))'
echo "-- float vs integer display ----------------------------------------"
chk print 'print(1, 2, 3, 100, -5)'
chk print 'print(1.0, 2.5, 100.0, -5.0, 0.5, 1e2)'
chk print 'print(1.0+1, 3.0*2, 10/2, 2^10)'
chk print 'print("a="..1.0, "b="..2, "c="..4.0, "d="..(7/2))'
chk print 'print(tostring(4.0), tostring(4), tostring(1/0), tostring(-1/0))'
echo "-- math.tointeger --------------------------------------------------"
chk lib  'print(math.tointeger(3.0), math.tointeger(3.5), math.tointeger(7), math.tointeger("x"))'
echo "-- integer arithmetic stays integer (within 32-bit) ----------------"
chk arith 'local s=0 for i=1,100 do s=s+i end print(s, math.type(s))'
chk arith 'print(2*3*4, math.type(2*3*4), 100-1, math.type(100-1))'
echo "=================================================================="
echo " 32-bit BOUNDARY (expected DIFF: LuaJIT int is 32-bit, 5.4 is 64-bit)"
echo "=================================================================="
chk bound 'print(math.maxinteger, math.mininteger)'
chk bound 'print(1000000*1000000)            -- 1e12 > 2^31, wraps/promotes'
chk bound 'local s=0 for i=1,100000 do s=s+i end print(s)  -- 5e9 > 2^31'
chk bound 'print(9007199254740993)           -- 2^53+1 integer literal'
echo "=================================================================="
printf "Within-range parity: OK=%d  DIFF=%d (DIFFs in the boundary section are expected)\n" "$ok" "$bad"
