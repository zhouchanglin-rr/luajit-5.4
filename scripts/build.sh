#!/usr/bin/env bash
#
# build.sh - Build both vendored engines (reference Lua 5.4.8 and LuaJIT)
# into a common build/ directory so they can be compared side-by-side.
#
# Usage: scripts/build.sh [clean]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SRC="$ROOT/vendor/lua-5.4.8"
LJ_SRC="$ROOT/vendor/luajit"
BUILD="$ROOT/build"
BIN="$BUILD/bin"

NPROC="$( (nproc 2>/dev/null) || echo 4)"

if [[ "${1:-}" == "clean" ]]; then
  echo ">> cleaning"
  make -C "$LUA_SRC" clean >/dev/null 2>&1 || true
  make -C "$LJ_SRC" clean >/dev/null 2>&1 || true
  rm -rf "$BUILD"
  exit 0
fi

mkdir -p "$BIN"

# ---- Reference Lua 5.4.8 ---------------------------------------------------
# The lua/lua git mirror ships the development makefile (flat layout). We build
# a normal release binary without enabling the internal test harness.
echo ">> building reference Lua 5.4.8"
make -C "$LUA_SRC" clean >/dev/null 2>&1 || true
make -C "$LUA_SRC" -j"$NPROC" \
  CC=gcc \
  MYCFLAGS="-DLUA_USE_LINUX -O2 -fno-stack-protector -fno-common" \
  MYLIBS="-Wl,-E -ldl -lreadline" >/dev/null
cp "$LUA_SRC/lua" "$BIN/lua54"
cp "$LUA_SRC/luac" "$BIN/luac54" 2>/dev/null || true

# ---- LuaJIT ----------------------------------------------------------------
# Two builds:
#  * luajit      - standard single-number build (all numbers are doubles).
#                  This is the baseline used by the correctness suite and the
#                  benchmark comparison. Exact integers up to 2^53.
#  * luajit-int  - dual-number build (-DLUAJIT_NUMMODE=2): a real runtime
#                  integer/float subtype (math.type, float ".0" printing, ...).
#                  Integers are 32-bit here; see docs/INTEGER_SUBTYPE_PLAN.md.
echo ">> building LuaJIT (standard / single-number)"
make -C "$LJ_SRC" clean >/dev/null 2>&1 || true
make -C "$LJ_SRC" -j"$NPROC" >/dev/null 2>&1
cp "$LJ_SRC/src/luajit" "$BIN/luajit"

echo ">> building LuaJIT (integer/float subtype, dual-number mode)"
make -C "$LJ_SRC" clean >/dev/null 2>&1 || true
make -C "$LJ_SRC" -j"$NPROC" XCFLAGS="-DLUAJIT_NUMMODE=2" >/dev/null 2>&1
cp "$LJ_SRC/src/luajit" "$BIN/luajit-int"
make -C "$LJ_SRC" clean >/dev/null 2>&1 || true

echo ">> done. Binaries in $BIN:"
"$BIN/lua54" -v
"$BIN/luajit" -v
