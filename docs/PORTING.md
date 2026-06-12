# Porting LuaJIT to Lua 5.4: analysis & roadmap

This document is the honest engineering assessment behind this repo: what it
takes to move LuaJIT from its current Lua 5.1-based language level up to Lua
5.4, what was actually done here, and what remains.

## Background

LuaJIT 2.1 implements the **Lua 5.1** language, plus a selection of Lua 5.2/5.3
extensions (e.g. `goto`/labels, `__pairs`, some library additions) gated behind
`LUAJIT_ENABLE_LUA52COMPAT`. It is a tracing JIT: hot bytecode traces are
compiled to machine code via an SSA IR. Crucially, **LuaJIT numbers are IEEE-754
doubles** (with an internal integer fast path), whereas **Lua 5.3+ introduced a
first-class 64-bit integer subtype**. That single design difference is the root
of most of the porting difficulty.

## Update: integer/float subtype (Milestone 1 implemented)

A dual-number LuaJIT variant (`build/bin/luajit-int`, built with
`-DLUAJIT_NUMMODE=2`) now implements a real runtime integer/float subtype. See
[INTEGER_SUBTYPE_PLAN.md](INTEGER_SUBTYPE_PLAN.md). Status changes vs the table
below (verified by `tests/integer_subtype.sh`, 12/12 within-range parity):

- `math.type(x)` — **implemented** (returns integer/float/nil).
- `math.tointeger(x)` — **implemented**.
- `math.maxinteger`/`mininteger` — **implemented** (32-bit values in this build).
- float prints with `.0` (`print(3.0)` → `3.0`) — **implemented**.
- integer-vs-float typing for literals, arithmetic, concat — **implemented**.

Remaining within this area: **64-bit** integers (this variant is 32-bit, so
integers above 2^31 promote to float — Milestone 2), numeric `for` loop float
typing, and the `//` operator.

## Empirical gap analysis

Output of `tests/show_differences.sh` (run on both engines). `DIFF` = a Lua 5.4
behaviour LuaJIT does not match; `SAME` = already compatible.

| Feature / behaviour | Status | Notes |
|---|---|---|
| `local x <const>` attribute | **SAME (ported here)** | Implemented + enforced in this repo |
| `goto` / labels | SAME | LuaJIT 2.1 supports these |
| integer literal printing (`1`, `2`) | SAME | both print without `.0` |
| `os.exit(true)` boolean arg | SAME | supported |
| `math.type(x)` | DIFF | no integer/float subtype in LuaJIT |
| float prints as `3.0` (5.4) vs `3` (jit) | DIFF | display of the float subtype |
| floor division `//` | DIFF | operator absent in LuaJIT lexer/parser |
| native bitwise `& \| ~ << >>` | DIFF | LuaJIT uses the `bit` library instead |
| `math.maxinteger` / `math.mininteger` | DIFF | no 64-bit integer subtype |
| 64-bit integer exactness `> 2^53` | DIFF | doubles lose precision; int64 is exact |
| integer overflow wraps | DIFF | depends on the integer subtype |
| `math.tointeger` | DIFF | no integer subtype |
| `string.pack` / `string.unpack` | DIFF | library not present |
| string→number coercion keeps integer | DIFF | depends on integer subtype |
| `local x <close>` (to-be-closed) | DIFF | rejected here; needs VM/GC work |
| `utf8` library | DIFF | not present in LuaJIT |
| `bit` library | (LuaJIT-only) | exists in LuaJIT, not in 5.4 |

Plus a smaller, already-known semantic difference surfaced by the correctness
suite: in Lua 5.4 `assert(false, msg)` routes through `error()` and prepends a
`chunk:line:` position prefix; LuaJIT raises the message verbatim. (The test
suite normalizes this prefix and the README documents it.)

## What was ported here: `local <const>`

`<const>` is the ideal first port: it is **purely compile-time** (no VM, GC, or
JIT changes) yet is a real, user-visible Lua 5.4 language feature.

Changes (all in the parser):

1. **`lj_errmsg.h`** — three new error messages: `XATTR` (unknown attribute),
   `XCONST` (`attempt to assign to const variable '%s'`, matching Lua 5.4's
   wording), and `XCLOSE` (explicit "unsupported" message for `<close>`).
2. **`lj_parse.c`**
   - a new variable flag `VSTACK_VAR_CONST = 0x08` alongside the existing
     `VSTACK_VAR_RW` / goto / label flags;
   - a `parse_attrib()` helper that parses the optional `'<' Name '>'` after each
     local name and maps `const`→flag, `close`→error, anything else→error;
   - `parse_local()` records the attribute per declared variable and applies the
     const flag *after* `var_add()` (which resets `info` to 0);
   - `bcemit_store()` — the single chokepoint for all variable stores — raises
     `XCONST` if the target local **or upvalue** is const. Putting the check
     here means assignment through a captured upvalue is caught too, while the
     initializer (which writes registers directly, not via `bcemit_store`) is
     unaffected.

Why this is safe: the new local isn't in scope during its own initializer, so
`local x <const> = x` resolves the RHS `x` to an outer variable exactly as Lua
5.4 does, and the const flag can never block the initialization.

Verification: `tests/cases/10_const_5_4.lua` runs on **both** engines and
produces identical output, including observing the compile error via `load()`.

## Roadmap for the rest (in suggested order)

**Tier 1 — compile-time only (days each, low risk).**
- `//` floor-division operator: add the token in `lj_lex.c`, the binop in
  `lj_parse.c`, and lower it to existing float floor semantics. With doubles it
  matches Lua 5.4 *float* `//`; integer `//` needs Tier 3.
- Native bitwise operators `& | ~ << >>`: parse them and lower to the existing
  `bit.*` fast functions / IR. Semantics match for values in the safe range;
  full 64-bit semantics need Tier 3.
- `utf8` library and `string.pack`/`unpack`: pure C library additions
  (`lib_utf8.c`, extend `lib_string.c`); no VM changes.

**Tier 2 — `<close>` to-be-closed variables (weeks, medium risk).**
- Track to-be-closed slots per scope; on scope exit (normal, break, goto,
  return, *and* error unwinding) call `__close`. Touches the parser, the VM's
  scope/return paths, and error unwinding in `lj_err.c`. The JIT must bail
  (not trace) scopes containing tbc variables initially.

**Tier 3 — the integer/float subtype (months, high risk; the core of "5.4").**
- Introduce a true 64-bit integer subtype so `math.type`, `math.maxinteger`,
  exact `> 2^53` integers, overflow wrap, integer `//` and `%`, and integer
  bitwise ops all match. This is invasive: the value representation, every
  arithmetic/comparison path, the IR and trace compiler's number handling,
  constant encoding, `tostring`/formatting, table key hashing, and the FFI all
  assume the dual-number model. This is the work that makes a "LuaJIT for 5.4"
  genuinely hard and is why no complete community port exists.

**Tier 4 — runtime/library tail.**
- Remaining library and metamethod deltas (`__close`, integer-aware
  `string.format`, `math` integer returns, `assert`/`error` position policy,
  generational GC tuning), and an expanded conformance suite (ideally the PUC
  `testes/` adapted to run without the internal C test API).

## How to reproduce every claim here

```bash
scripts/build.sh                       # both engines
tests/run_tests.sh                     # 10/10 identical output
tests/show_differences.sh              # the gap table above
python3 benchmarks/run_benchmarks.py   # the speedup table
build/bin/luajit -e 'local x <const> = 1; x = 2'   # -> const error (ported)
```
