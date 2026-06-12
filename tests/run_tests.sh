#!/usr/bin/env bash
#
# run_tests.sh - Cross-engine correctness suite.
#
# Each program in tests/cases/*.lua is written in the common Lua subset that
# both LuaJIT and Lua 5.4.8 support, and prints deterministic, explicitly
# formatted output to STDOUT. We run every case under BOTH engines and require
# their STDOUT to be byte-for-byte identical. The Lua 5.4.8 reference output is
# the oracle; any divergence is a LuaJIT-vs-5.4 correctness difference.
#
# NOTE: only stdout is compared. Uncaught-error/traceback wording legitimately
# differs between the two independent VMs, so error-path tests catch errors with
# pcall and print normalized results to stdout.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build/bin"
LUA54="$BIN/lua54"
LUAJIT="$BIN/luajit"
CASES="$ROOT/tests/cases"

if [[ ! -x "$LUA54" || ! -x "$LUAJIT" ]]; then
  echo "Engines not built. Run scripts/build.sh first." >&2
  exit 2
fi

pass=0; fail=0; failed_list=()
printf "%-26s %-10s %s\n" "CASE" "RESULT" "DETAIL"
printf "%s\n" "------------------------------------------------------------"
tmp="$(mktemp -d)"
for f in "$CASES"/*.lua; do
  name="$(basename "$f")"
  "$LUA54"  "$f" >"$tmp/ref.out" 2>/dev/null; rc_ref=$?
  "$LUAJIT" "$f" >"$tmp/jit.out" 2>/dev/null; rc_jit=$?
  if cmp -s "$tmp/ref.out" "$tmp/jit.out" 2>/dev/null || \
     python3 -c "import sys;sys.exit(0 if open(sys.argv[1],'rb').read()==open(sys.argv[2],'rb').read() else 1)" "$tmp/ref.out" "$tmp/jit.out"; then
    if [[ "$rc_ref" == "$rc_jit" ]]; then
      pass=$((pass+1)); printf "%-26s %-10s %s\n" "$name" "PASS" "(exit $rc_ref)"
    else
      fail=$((fail+1)); failed_list+=("$name")
      printf "%-26s %-10s %s\n" "$name" "FAIL" "(stdout equal but exit differs: ref $rc_ref / jit $rc_jit)"
    fi
  else
    fail=$((fail+1)); failed_list+=("$name")
    printf "%-26s %-10s %s\n" "$name" "FAIL" "(stdout differs; ref exit $rc_ref / jit exit $rc_jit)"
    echo "    --- unified diff (- Lua5.4.8  + LuaJIT) ---"
    python3 - "$tmp/ref.out" "$tmp/jit.out" <<'PY' | sed 's/^/    /'
import sys, difflib
a=open(sys.argv[1]).read().splitlines(keepends=True)
b=open(sys.argv[2]).read().splitlines(keepends=True)
sys.stdout.writelines(difflib.unified_diff(a,b,'lua5.4.8','luajit',n=1))
PY
  fi
done
rm -rf "$tmp"

printf "%s\n" "------------------------------------------------------------"
echo "TOTAL: $((pass+fail))  PASS: $pass  FAIL: $fail"
if (( fail > 0 )); then
  echo "Failing: ${failed_list[*]}"
  exit 1
fi
