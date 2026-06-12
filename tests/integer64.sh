#!/usr/bin/env bash
#
# integer64.sh - Validate the EXPERIMENTAL 64-bit integer subtype implemented
# in the luajit-int64 build (Tier-3 VM work) against the Lua 5.4.8 reference.
#
# luajit-int64 carries integer values that do not fit LuaJIT's native 32-bit
# dual-number integer as boxed int64_t/uint64_t cdata (a 64-bit carrier the VM
# already supports with exact two's-complement arithmetic). This makes
# math.maxinteger, large integer literals, 64-bit wraparound and 5.4-style
# integer printing observable in the interpreter.
#
# This script pins down BOTH the new parity (vs the 32-bit luajit-int) and the
# honest remaining boundaries (documented in docs/INT64_VM_PLAN.md). All test
# snippets use plain decimal literals that BOTH engines accept.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA54="$ROOT/build/bin/lua54"
LJ64="$ROOT/build/bin/luajit-int64"

[[ -x "$LJ64" ]] || { echo "build/bin/luajit-int64 missing; run scripts/build.sh" >&2; exit 2; }

ok=0; bad=0
chk() {  # chk "tag" "snippet"
  local mode="$1" code="$2" r j status
  r="$("$LUA54" -e "$code" 2>&1)"
  j="$("$LJ64" -e "$code" 2>&1)"
  if [[ "$r" == "$j" ]]; then status="OK  "; ok=$((ok+1)); else status="DIFF"; bad=$((bad+1)); fi
  printf "[%s] %-6s %s\n" "$status" "$mode" "$code"
  [[ "$r" != "$j" ]] && { printf "        5.4.8 : %s\n" "$r"; printf "        lj-64 : %s\n" "$j"; }
}

echo "=================================================================="
echo " Experimental 64-bit integer subtype on luajit-int64 (vs Lua 5.4.8)"
echo "=================================================================="
echo "-- 64-bit integer range -------------------------------------------"
chk range 'print(math.maxinteger, math.mininteger)'
chk range 'print(math.type(math.maxinteger), math.type(math.mininteger))'
chk range 'print(math.maxinteger + 1 == math.mininteger)'
chk range 'print(math.mininteger - 1 == math.maxinteger)'
echo "-- large integer literals (exact, > 2^53) -------------------------"
chk lit 'print(9007199254740993)'
chk lit 'print(math.type(9007199254740993))'
chk lit 'print(1000000000000)'
chk lit 'print(4611686018427387904)'
chk lit 'print(0x7fffffffffffffff)'
echo "-- 64-bit integer arithmetic & wraparound -------------------------"
chk arith 'print(math.maxinteger * 2)'
chk arith 'print(math.maxinteger + math.maxinteger)'
chk arith 'print(9007199254740993 + 1)'
chk arith 'print(9007199254740993 - 9007199254740990)'
chk arith 'print(math.maxinteger % 1000)'
chk arith 'print(math.type(9007199254740993 + 1))'
echo "-- '/' and '^' always produce a float (Lua 5.4 rule) --------------"
chk flt 'print(10 / 4, math.type(10/4))'
chk flt 'print(2 ^ 10, math.type(2^10))'
chk flt 'print(math.maxinteger / 1)'
chk flt 'print(9007199254740993 / 2)'
echo "-- mixing a 64-bit integer with a float promotes to float ---------"
chk mix 'print(math.type(math.maxinteger + 0.0))'
chk mix 'print(9007199254740992 + 0.5)'
chk mix 'print(math.type(9007199254740993 * 1.0))'
echo "-- 5.4-style display: tostring / concat / string.format -----------"
chk disp 'print(tostring(math.maxinteger))'
chk disp 'print("max="..math.maxinteger..".")'
chk disp 'print(string.format("%d", math.maxinteger))'
echo "-- math.tointeger over the 64-bit range ---------------------------"
chk toi 'print(math.tointeger(2.0^53))'
chk toi 'print(math.tointeger(math.maxinteger))'
chk toi 'print(math.tointeger(3.5))'
echo "=================================================================="
echo " KNOWN BOUNDARIES (expected DIFF; see docs/INT64_VM_PLAN.md)"
echo "=================================================================="
echo "-- arithmetic that overflows a 32-bit int promotes to float -------"
echo "   (the int32->int64 overflow promotion lives in the assembly VM)"
chk bound 'local a=1000000 print(a*a, math.type(a*a))'
chk bound 'local s=0 for i=1,100000 do s=s+i end print(s, math.type(s))'
chk bound 'print(1000000*1000000)'
echo "-- 64-bit integer cdata used as a table key is by-identity --------"
chk bound 'local t={} t[5000000000]="x" print(t[5000000000])'
echo "-- int/float comparison at 64-bit magnitude uses double conv ------"
chk bound 'print(math.maxinteger == 9223372036854775807.0)'
echo "=================================================================="
printf "Parity (top section): OK=%d  DIFF=%d  (DIFFs in the BOUNDARIES section are expected)\n" "$ok" "$bad"
