# Implementation plan: the Lua 5.3/5.4 integer/float subtype in LuaJIT

## The problem, precisely

Lua 5.3 split the single `number` type into two **subtypes**: a 64-bit signed
**integer** and a **float** (`double`). They share the `number` type but are
distinguishable (`math.type`), have distinct arithmetic rules (`//`, `%`,
bitwise ops, overflow wrap), distinct printing (`3` vs `3.0`), and distinct
behaviour as table keys (`t[1]` and `t[1.0]` are the same slot, the integer
form being canonical).

LuaJIT was built for Lua 5.1, where **all numbers are doubles**. Values are
stored using **NaN-tagging**: a 64-bit `TValue` is either a double, or a tagged
value packed into the payload of a NaN. On 64-bit targets the tagged payload is
only ~47 bits — it **cannot hold a full 64-bit integer**. This single fact is
why a faithful 5.4 integer subtype is genuinely hard in LuaJIT.

## What LuaJIT already has: dual-number mode (`LJ_DUALNUM`)

LuaJIT ships an optional **dual-number** representation. When `LJ_DUALNUM` is
enabled, a `TValue` may carry a **32-bit integer** (tag `LJ_TISNUM`) *or* a
double. The whole engine — interpreter (in DynASM assembly), the JIT IR and
trace compiler, the GC, and the FFI — already understands this tag. Dual-number
mode is the **default on ARM/MIPS** and is build-selectable on x64 via
`-DLUAJIT_NUMMODE=2`.

Key consequence: LuaJIT's integer subtype is **32-bit**, while Lua 5.4's is
**64-bit**. Dual-number mode gives us a *real, engine-wide* integer subtype for
free, but with a narrower range and different overflow behaviour.

## Strategy: two milestones

### Milestone 1 (this change) — expose the existing 32-bit subtype to Lua

Turn on dual-number mode and make the subtype observable and 5.4-shaped at the
Lua surface, where it can be done in C without touching the assembly VM or JIT:

1. **Build**: compile LuaJIT with `-DLUAJIT_NUMMODE=2` (→ `LJ_DUALNUM=1`).
   Integer literals, integer arithmetic, and integer loop variables then carry
   the integer tag throughout the engine automatically.
2. **`math.type(x)`** — return `"integer"` / `"float"` / `nil`, driven by the
   runtime tag (`tvisint`/`tvisnum`). This is the headline, exactly-correct
   feature: the subtype becomes observable.
3. **`math.tointeger(x)`** — return the integer value if `x` is an integer or a
   float with an exact integral value in range, else `nil`.
4. **`math.maxinteger` / `math.mininteger`** — expose the integer range
   (here 32-bit: `2147483647` / `-2147483648`), as genuine integer-typed values.
5. **Float printing** — Lua 5.4 prints floats with a decimal point (`3.0`,
   `1e+20`); LuaJIT's `%.14g` drops it (`3`). Append `.0` to the `tostring`/
   concat result of a float when it has no `.`/exponent/`inf`/`nan` marker.
   Done in the C string-formatting helpers, gated by `LJ_DUALNUM`.

After this milestone, `math.type`, integer-vs-float distinction for literals and
arithmetic, integer printing, and float `.0` printing all match Lua 5.4 **within
the 32-bit integer range**.

### Milestone 2 (implemented, experimental) — true 64-bit integers

Milestone 2 is now available in the `luajit-int64` build (built by
`scripts/build.sh` with `-DLUAJIT_ENABLE_INT64SUBTYPE`). It is an experimental,
interpreter-level 64-bit integer subtype, documented in full — design,
implementation and honest boundaries — in
[INT64_VM_PLAN.md](INT64_VM_PLAN.md). Summary:

- **Carrier.** Integer values that do not fit the 32-bit dual-number integer
  are carried as boxed `int64_t`/`uint64_t` cdata, which the VM already supports
  with exact two's-complement arithmetic and wraparound.
- **Correct now (verified 28/28 vs Lua 5.4.8 in `tests/integer64.sh`):**
  `math.maxinteger`/`mininteger` (exact `±2^63`), `math.type`/`math.tointeger`
  over the 64-bit range, large integer literals (`> 2^53`), 64-bit arithmetic
  and wraparound, `/` and `^` always producing floats, float-mixing promoting to
  float, and 5.4-style integer display (`tostring`/`..`/`string.format`).
- **JIT-consistent.** The trace recorder bails on int64-carrier arithmetic so
  compiled and interpreted results are identical (the cost: such arithmetic is
  not JIT-compiled in this build).
- **Still differs (documented boundaries):** arithmetic that overflows a 32-bit
  integer promotes to *float* (the overflow path lives in the DynASM assembly
  interpreter); int64 cdata table keys are by-identity not by-value; int/float
  comparison at 64-bit magnitude uses double conversion.

The remaining VM work — assembly overflow promotion, a real 64-bit JIT IR,
table-key canonicalisation and exact comparison — is laid out in
[INT64_VM_PLAN.md](INT64_VM_PLAN.md). The notes below describe the original,
not-yet-done state of that work.

### Milestone 2 (original blocker analysis) — true 64-bit integers

This is the large, high-risk work. It requires:

- a value representation that can hold a 64-bit integer (e.g. boxing like the
  FFI's `int64_t` cdata, or a different tagging scheme) — the core blocker;
- rewriting the integer arithmetic/comparison paths in the **DynASM assembly
  interpreter** for every architecture (`vm_x64.dasc`, `vm_arm64.dasc`, …);
- teaching the **JIT** to record, type-narrow, and emit 64-bit integer IR, with
  correct overflow-wrap semantics and guards;
- 64-bit-aware `//`, `%`, bitwise operators, `string.format` integer specifiers,
  `math.floor/ceil/abs/...` integer returns, and integer table-key
  canonicalisation;
- `tonumber`/lexer rules that pick integer vs float per the 5.4 grammar.

`docs/PORTING.md` tracks this as the Tier-3 effort.

## Honesty about scope

Milestone 1 is a real, engine-wide integer subtype — not a fake — but it is
**32-bit**. Programs that stay within ±2^31 behave like Lua 5.4 for typing,
arithmetic and printing. Programs relying on 64-bit integers (large literals,
`math.maxinteger == 2^63-1`, 64-bit wrap) will differ; those need Milestone 2.
The test suite below pins down exactly where parity holds.

## Verification

- `math.type` / `math.tointeger` / printing compared directly against the Lua
  5.4.8 reference (`tests/cases/11_integer_subtype.lua`, run on both engines).
- The full existing cross-engine suite must still be **10/10** identical.
- Benchmarks re-run to measure the performance impact of dual-number mode.
- `tests/check_5x_syntax.sh` re-run to confirm `math.type` flips to OK.
