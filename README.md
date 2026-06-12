# luajit-5.4

A working bench comparing **LuaJIT** against the **reference Lua 5.4.8** (PUC-Rio)
interpreter, plus a first, scoped step toward porting Lua 5.4 language features
into LuaJIT.

This repository vendors both engines, builds them from source, verifies that
LuaJIT produces byte-for-byte identical output to Lua 5.4.8 on a shared test
suite, measures LuaJIT's performance speedup on a benchmark suite, and adds a
real (compiled, tested) port of the Lua 5.4 `local x <const>` attribute to
LuaJIT's parser.

> **Scope note (please read).** "Porting LuaJIT to Lua 5.4" in the *complete*
> sense — making LuaJIT's bytecode VM and trace compiler implement all Lua 5.4
> semantics (integer/float subtypes, `//` and native bitwise operators, 64-bit
> integer arithmetic with overflow wrap, to-be-closed `<close>` variables, the
> generational GC, `string.pack`, `utf8`, etc.) — is a multi-person, multi-month
> effort. This repo does **not** claim to be that. It delivers the parts that
> can be built and *verified* now: reproducible builds, a cross-engine
> correctness oracle, a performance comparison, one fully-working language-feature
> port (`<const>`), and an honest, empirically-grounded roadmap for the rest.

## Layout

```
vendor/lua-5.4.8/   Reference Lua 5.4.8 source (lua/lua @ tag v5.4.8)
vendor/luajit/      LuaJIT 2.1 source + the <const> and integer-subtype ports
scripts/build.sh    Builds lua54, luajit (standard) and luajit-int (subtype)
tests/cases/*.lua   Cross-engine correctness cases (common 5.1/5.4 subset)
tests/run_tests.sh  Runs every case on BOTH engines, requires identical stdout
tests/show_differences.sh  Probes Lua 5.4 features to catalog porting gaps
tests/check_5x_syntax.sh   Audits Lua 5.3/5.4 feature support
tests/integer_subtype.sh   Validates the integer/float subtype (luajit-int)
benchmarks/*.lua    Classic Lua benchmarks (checksummed)
benchmarks/run_benchmarks.py  Times both engines, verifies output, reports speedup
port/               Standalone reference diffs of the LuaJIT ports
docs/PORTING.md     Feature-by-feature porting analysis and roadmap
docs/INTEGER_SUBTYPE_PLAN.md  Design + plan for the integer/float subtype
```

## Quick start

```bash
scripts/build.sh                 # build build/bin/lua54 and build/bin/luajit
tests/run_tests.sh               # correctness: LuaJIT output == Lua 5.4.8
tests/show_differences.sh        # catalog of remaining 5.4 feature gaps
python3 benchmarks/run_benchmarks.py          # full performance comparison
python3 benchmarks/run_benchmarks.py --quick  # fast smaller run
```

## Correctness

`tests/run_tests.sh` runs 11 programs written in the language subset common to
both engines under **both** `lua54` and `luajit`, and requires their stdout to
be **byte-for-byte identical** (the Lua 5.4.8 output is the oracle). Programs use
explicit `string.format` so that integer-vs-float *display* differences never
leak into the comparison.

```
01_arithmetic  02_strings   03_tables   04_closures   05_metatables
06_coroutines  07_errors    08_control  09_algorithms 10_const_5_4  11_utf8
```

Result: **11 / 11 identical.** Case `10_const_5_4` exercises the new `<const>`
port; `11_utf8` exercises the ported `utf8` library — both pass only because
LuaJIT now matches Lua 5.4.8 for those features.

## Performance: LuaJIT speedup over reference Lua 5.4.8

Hardware: Intel Xeon Platinum 8488C, Amazon Linux 2023, gcc 11.5, `-O2`.
Each benchmark is run 5x per engine; the minimum wall-clock time is kept; every
benchmark prints a checksum that must match across engines (correctness under
load). Speedup = `time(Lua 5.4.8) / time(LuaJIT)`.

| Benchmark | Args | Lua 5.4.8 (s) | LuaJIT (s) | Speedup |
|-----------|------|--------------:|-----------:|--------:|
| fib | `34` | 0.3151 | 0.0578 | **5.45x** |
| ackermann | `3 9` | 0.1838 | 0.0305 | **6.03x** |
| mandelbrot | `800` | 0.6441 | 0.0801 | **8.04x** |
| nbody | `500000` | 0.8439 | 0.1116 | **7.56x** |
| spectralnorm | `550` | 0.4198 | 0.0180 | **23.38x** |
| fannkuch | `10` | 1.4221 | 0.3019 | **4.71x** |
| matmul | `160` | 0.0604 | 0.0077 | **7.89x** |
| sieve | `3000000 4` | 0.6637 | 0.1809 | **3.67x** |
| string_ops | `3000` | 0.0637 | 0.0266 | **2.39x** |

**Geometric-mean speedup: 6.28x** (min 2.39x on the library/string-bound
workload, max 23.38x on the tight floating-point loop). The smallest speedups
are on `string_ops` and `sieve`, which spend most of their time in C library
routines / large table writes that LuaJIT cannot accelerate as dramatically as
numeric loops — exactly the expected shape for a tracing JIT.

Live numbers are regenerated into `benchmarks/results.md` / `results.json`.

## The `<const>` port

LuaJIT (Lua 5.1 lineage) does not understand the Lua 5.4 attribute syntax. This
repo adds full support for `local name <const> = expr`:

- declaration and use behave exactly like Lua 5.4;
- reassigning a const (directly or via an upvalue) is a **compile-time error**
  with the same message as Lua 5.4: `attempt to assign to const variable 'x'`;
- unknown attributes are rejected (`unknown attribute 'foo'`);
- `<close>` is parsed and **explicitly rejected** (its to-be-closed runtime
  semantics are not implemented), so code fails loudly instead of silently
  misbehaving.

Implementation touches three small, well-contained spots in the parser
(`vendor/luajit/src/lj_parse.c`, `lj_errmsg.h`); see `docs/PORTING.md` and
`port/` for details. It compiles cleanly and passes the cross-engine suite.

## The integer/float subtype (`luajit-int`)

`scripts/build.sh` also produces `build/bin/luajit-int`, a dual-number LuaJIT
build that implements a real runtime **integer/float subtype** (Lua 5.3/5.4):

- `math.type(x)` returns `"integer"`/`"float"`/`nil`;
- integer literals/arithmetic stay integer, float literals/operations stay
  float (`math.type(2^2)` → `float`, `math.type(1+2)` → `integer`);
- floats print with a decimal point (`print(3.0)` → `3.0`, `"x="..4.0` → `x=4.0`);
- `math.tointeger`, `math.maxinteger`, `math.mininteger` are available.

`tests/integer_subtype.sh` verifies **12/12** within-range parity against Lua
5.4.8. Performance is within ~2-3% of standard LuaJIT (still 5-20x over Lua
5.4.8), so the subtype costs almost nothing.

**Boundary (honest):** LuaJIT's dual-number integers are **32-bit**, while Lua
5.4's are **64-bit**. Integers above 2^31 promote to float and then print with a
`.0` — so integer-heavy programs in the 2^31-2^53 range differ from 5.4. That is
why the *standard* `luajit` (all-double, exact to 2^53) remains the baseline for
the benchmark/correctness comparison, and the full 64-bit subtype is tracked as
Milestone 2 in [docs/INTEGER_SUBTYPE_PLAN.md](docs/INTEGER_SUBTYPE_PLAN.md).

## Remaining gaps and roadmap

`tests/show_differences.sh` empirically lists what still differs. See
[docs/PORTING.md](docs/PORTING.md) for the full feature-by-feature analysis,
difficulty estimates, and a staged porting plan.

## Provenance & licensing

- Lua 5.4.8: PUC-Rio, MIT license (`vendor/lua-5.4.8/`, from `lua/lua` tag `v5.4.8`).
- LuaJIT: Mike Pall, MIT license (`vendor/luajit/`, from `LuaJIT/LuaJIT`).

Both are unmodified except for the documented `<const>` parser change in LuaJIT.
