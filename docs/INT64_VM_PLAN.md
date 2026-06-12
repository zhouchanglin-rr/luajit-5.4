# Tier-3 VM work: 64-bit integers in LuaJIT (`luajit-int64`)

This is the design, implementation and *honest boundary* of the experimental
64-bit integer subtype added in the `luajit-int64` build. It is the Tier-3
"integer/float subtype" work flagged in [PORTING.md](PORTING.md) and the
Milestone 2 follow-on to [INTEGER_SUBTYPE_PLAN.md](INTEGER_SUBTYPE_PLAN.md).

> **Scope, up front.** A *complete* 64-bit integer subtype in LuaJIT is a
> multi-month effort (the README and PORTING.md say so, and it remains true).
> This change does **not** claim to be complete. It delivers a real, compiled,
> tested slice that makes 64-bit integers observable and correct **in the
> interpreter** for literals, `math.maxinteger`, and operations on explicit
> 64-bit values — and it is careful to keep the JIT in agreement with the
> interpreter. The parts that genuinely require rewriting the DynASM assembly
> interpreter are identified precisely and left as future work.

## The core blocker (why this is hard)

LuaJIT stores every value in a 64-bit NaN-tagged `TValue`. The integer field is
**32-bit**:

```c
/* lj_obj.h */
struct {
  LJ_ENDIAN_LOHI(
    int32_t i;     /* Integer value.            */
  , uint32_t it;   /* Internal object tag (MSW).*/
  )
};
```

The upper 32 bits are always the type tag — in both the default and `LJ_GC64`
layouts. There is **no room for an inline 64-bit integer** without abandoning
NaN-tagging (which would change the representation of every double and require
rewriting the whole engine). This single fact is why a faithful 64-bit integer
subtype is hard in LuaJIT, and why dual-number mode (`LJ_DUALNUM`) is only
*32-bit*.

## The carrier: int64 cdata

LuaJIT already has exactly one value that can hold a full 64-bit integer with
correct two's-complement arithmetic: the FFI's `int64_t`/`uint64_t` **cdata**.
Empirically (stock LuaJIT):

```
9223372036854775807LL + 1LL   -->  -9223372036854775808LL   (exact 64-bit wrap)
1000000LL * 1000000LL         -->  1000000000000LL
string.format("%d", 1LL<<62)  -->  4611686018427387904       (no suffix)
```

The arithmetic, comparison, modulo, wraparound and `%d` formatting are already
implemented and well-tested in `lj_carith.c`. The only things that do not match
Lua 5.4 out of the box are (a) the `LL`/`ULL` print suffix, (b) classification
(`math.type`), (c) a couple of operator-semantics gaps, and (d) the JIT lowering.

**Strategy:** keep small integers in the fast 32-bit dual-number representation
(`LJ_TISNUM`), and use int64 cdata as the **wide carrier** for integer values
that do not fit 32 bits. Make the Lua surface treat the wide carrier as the
integer subtype, and fix the operator-semantics and JIT gaps so results are
consistent.

Everything is gated behind `LUAJIT_ENABLE_INT64SUBTYPE` (→ `LJ_INT64SUBTYPE`,
which requires `LJ_DUALNUM` and `LJ_HASFFI`). The standard `luajit` and the
32-bit `luajit-int` builds are byte-for-byte unaffected.

## What was implemented (all compiled and tested)

| Area | File | Change |
|---|---|---|
| Feature gate | `lj_arch.h` | `LJ_INT64SUBTYPE` macro |
| Carrier predicates | `lj_ctype.h` | `tvisint64` / `cdata_isint64` / `cdata_isuint64` |
| `math.maxinteger`/`mininteger` | `lib_math.c` | exact 64-bit (`2^63-1` / `-2^63`) as int64 cdata |
| `math.type` | `lib_math.c` | int64 cdata → `"integer"` |
| `math.tointeger` | `lib_math.c` | handles int64 cdata and floats over the full 64-bit range |
| Integer display | `lj_ctype.c` | int64 cdata renders with no `LL`/`ULL` suffix (5.4 style) |
| Concatenation | `lj_meta.c` | `..` accepts the int64 carrier and stringifies it like a 5.4 integer |
| 64-bit literals | `lj_lex.c` | integer literals `> 2^31` parse as int64 cdata (decimal `> 2^63-1` stays float; hex wraps mod `2^64`) |
| Operator semantics | `lj_carith.c` | `/` and `^` always yield a float; mixing the carrier with a float promotes to float (Lua 5.4 rules) — via `lj_vm_foldarith` |
| JIT consistency | `lj_crecord.c` | the recorder bails on int64-carrier arithmetic so traces fall back to the interpreter and produce identical results |

### Why the JIT bail matters

`luajit-int64` keeps the JIT on. But the trace recorder (`lj_crecord.c`) lowers
cdata int64 arithmetic with plain C semantics (`/` is integer division, a float
operand is truncated). Before the bail was added, a hot loop computing
`9007199254740992 / 4` returned the integer `2251799813685248` once compiled,
while the interpreter (correctly) returned the float `2.5`. The recorder now
aborts when an operand is a 64-bit integer carrier, so the operation runs in the
interpreter and JIT-compiled results match interpreted results and Lua 5.4. The
cost is that int64-carrier arithmetic is not JIT-compiled in this build;
all-`double` and within-`int32` numeric loops still trace and run at full speed.

## Verification

`tests/integer64.sh` compares `luajit-int64` against the Lua 5.4.8 reference.
**28/28** parity in the core section:

- 64-bit range: `math.maxinteger`/`mininteger`, `max+1 == min`, `min-1 == max`;
- exact large literals (`9007199254740993`, `4611686018427387904`, `0x7fff...`);
- 64-bit arithmetic and wraparound (`max*2`, `max+max`, `%`, big `+`/`-`);
- `/` and `^` always float; float-mixing promotes to float;
- 5.4-style display via `tostring`, `..`, and `string.format("%d", ...)`;
- `math.tointeger` across the 64-bit range.

The standard cross-engine suite (`tests/run_tests.sh`, run on the baseline
`luajit`) remains **10/10**, and `tests/integer_subtype.sh` (the 32-bit
`luajit-int`) is unchanged. Hot-loop tests confirm the JIT now agrees with the
interpreter for the operations above.

## Honest boundaries (still differ from Lua 5.4)

These are validated and labelled as *expected* DIFFs in the BOUNDARIES section
of `tests/integer64.sh`:

1. **Arithmetic that overflows a 32-bit integer promotes to float, not to a
   64-bit integer.** The int32→int64 overflow check lives in the **DynASM
   assembly interpreter** (`BC_ADDVV`/`SUBVV`/`MULVV` and the numeric `FORL`
   loop), which on overflow widens to `double`. So `a*a` for `a=1000000`, a
   `for` loop summing past `2^31`, and even the constant-folded `1000000*1000000`
   become floats. This is deliberately kept *consistent* (compile-time and
   runtime behave the same) rather than partially patched. Fixing it requires
   editing the assembly overflow paths to box an int64 carrier — the central
   remaining VM task.
2. **A 64-bit integer carrier used as a table key is by-identity, not
   by-value.** `t[5000000000] = x; t[5000000000]` returns `nil` because each
   literal is a distinct cdata object and table hashing uses cdata identity.
   Lua 5.4 canonicalises integer keys by value. Fixing it requires int64-aware
   key hashing/canonicalisation in `lj_tab.c`.
3. **Integer/float comparison at 64-bit magnitude uses `double` conversion.**
   `math.maxinteger == 9223372036854775807.0` is `true` here but `false` in Lua
   5.4 (which compares the exact integer against the rounded float). Fixing it
   requires the exact int/float comparison logic Lua 5.4 uses.

Out of scope here and tracked separately: the `//` floor-division operator and
the native bitwise operators `& | ~ << >>` (Tier-1 lexer/parser work in
PORTING.md), `string.pack`/`utf8`, and `<close>` (Tier-2).

## The remaining path to a complete 64-bit subtype

In rough order of effort/risk:

1. **Assembly overflow promotion.** Rewrite the integer add/sub/mul overflow
   and numeric-`for` paths in `vm_x64.dasc` (and every other `vm_*.dasc`) to
   produce a 64-bit integer carrier instead of a double. This is the single
   highest-value remaining change and the largest.
2. **JIT 64-bit integer IR.** Teach the recorder/optimiser/back-end to track a
   real 64-bit integer subtype (not just FFI int64), with overflow-wrap guards,
   so the operations above re-gain JIT speed instead of bailing.
3. **Table-key canonicalisation** and **exact int/float comparison** in the VM
   and library paths.
4. A representation that boxes less aggressively than per-value cdata (the GC
   pressure of boxing every wide integer is the reason a cdata carrier is a
   stepping stone, not the destination).

This change makes 1–4 incrementally testable: `tests/integer64.sh` already pins
down exactly which behaviours each future step must flip from DIFF to OK.
