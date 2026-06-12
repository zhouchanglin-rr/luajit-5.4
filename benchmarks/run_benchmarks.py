#!/usr/bin/env python3
"""
run_benchmarks.py - Time each benchmark under both engines and compare.

For every benchmark we:
  * run it N times on each engine and keep the *minimum* wall-clock time
    (minimum is the most stable estimator: it filters scheduler noise),
  * capture stdout (a checksum line) and require it to be identical across
    engines  -> correctness-under-load check,
  * report LuaJIT speedup = time(lua5.4.8) / time(luajit).

Outputs a human table to stdout and writes results.json + results.md.
"""
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "build", "bin")
LUA54 = os.path.join(BIN, "lua54")
LUAJIT = os.path.join(BIN, "luajit")
BDIR = os.path.join(ROOT, "benchmarks")

# (name, script, args)  -- "full" sizes; pass --quick to scale down.
BENCH = [
    ("fib",          "fib.lua",          ["34"]),
    ("ackermann",    "ackermann.lua",    ["3", "9"]),
    ("mandelbrot",   "mandelbrot.lua",   ["800"]),
    ("nbody",        "nbody.lua",        ["500000"]),
    ("spectralnorm", "spectralnorm.lua", ["550"]),
    ("fannkuch",     "fannkuch.lua",     ["10"]),
    ("matmul",       "matmul.lua",       ["160"]),
    ("sieve",        "sieve.lua",        ["3000000", "4"]),
    ("string_ops",   "string_ops.lua",  ["3000"]),
]

QUICK = {
    "fib": ["30"], "ackermann": ["3", "7"], "mandelbrot": ["300"],
    "nbody": ["50000"], "spectralnorm": ["200"], "fannkuch": ["9"],
    "matmul": ["90"], "sieve": ["1000000", "2"], "string_ops": ["800"],
}


def run_once(engine, script, args):
    t0 = time.perf_counter()
    p = subprocess.run([engine, os.path.join(BDIR, script)] + args,
                       capture_output=True, text=True)
    dt = time.perf_counter() - t0
    return dt, p.stdout.strip(), p.returncode


def bench(engine, script, args, reps):
    best, out, rc = float("inf"), None, 0
    for _ in range(reps):
        dt, o, r = run_once(engine, script, args)
        best = min(best, dt)
        out, rc = o, r
    return best, out, rc


def main():
    quick = "--quick" in sys.argv
    reps = 5 if not quick else 3
    for e in (LUA54, LUAJIT):
        if not os.path.exists(e):
            sys.exit(f"missing engine {e}; run scripts/build.sh first")

    rows = []
    print(f"{'BENCHMARK':<14}{'Lua5.4.8 (s)':>14}{'LuaJIT (s)':>13}"
          f"{'Speedup':>10}  {'OUTPUT':>8}")
    print("-" * 70)
    for name, script, full_args in BENCH:
        args = QUICK[name] if quick else full_args
        t_ref, o_ref, rc_ref = bench(LUA54, script, args, reps)
        t_jit, o_jit, rc_jit = bench(LUAJIT, script, args, reps)
        match = (o_ref == o_jit and rc_ref == 0 and rc_jit == 0)
        speed = (t_ref / t_jit) if t_jit > 0 else 0.0
        rows.append({
            "name": name, "args": args,
            "lua54_s": round(t_ref, 4), "luajit_s": round(t_jit, 4),
            "speedup": round(speed, 2), "match": match,
            "output_ref": o_ref, "output_jit": o_jit,
        })
        print(f"{name:<14}{t_ref:>14.4f}{t_jit:>13.4f}{speed:>9.2f}x"
              f"  {'MATCH' if match else 'MISMATCH':>8}")
    print("-" * 70)

    speeds = [r["speedup"] for r in rows if r["match"] and r["speedup"] > 0]
    geo = 1.0
    for s in speeds:
        geo *= s
    geo = geo ** (1.0 / len(speeds)) if speeds else 0.0
    allmatch = all(r["match"] for r in rows)
    print(f"Correctness under load: {'ALL MATCH' if allmatch else 'MISMATCH(ES)!'}")
    print(f"Geometric-mean LuaJIT speedup: {geo:.2f}x  "
          f"(min {min(speeds):.2f}x, max {max(speeds):.2f}x)")

    meta = {
        "reps": reps, "quick": quick,
        "geomean_speedup": round(geo, 2),
        "all_match": allmatch, "results": rows,
    }
    with open(os.path.join(BDIR, "results.json"), "w") as f:
        json.dump(meta, f, indent=2)
    _write_md(meta)


def _write_md(meta):
    lines = [
        "# Benchmark Results: LuaJIT vs reference Lua 5.4.8",
        "",
        f"- Repetitions per benchmark: {meta['reps']} (minimum time kept)",
        f"- Mode: {'quick' if meta['quick'] else 'full'}",
        f"- Correctness under load: "
        f"{'all outputs identical' if meta['all_match'] else 'MISMATCHES PRESENT'}",
        f"- **Geometric-mean LuaJIT speedup: {meta['geomean_speedup']}x**",
        "",
        "| Benchmark | Args | Lua 5.4.8 (s) | LuaJIT (s) | Speedup | Output |",
        "|-----------|------|---------------|-----------|---------|--------|",
    ]
    for r in meta["results"]:
        lines.append(
            f"| {r['name']} | `{' '.join(r['args'])}` | {r['lua54_s']:.4f} | "
            f"{r['luajit_s']:.4f} | **{r['speedup']:.2f}x** | "
            f"{'match' if r['match'] else 'MISMATCH'} |")
    with open(os.path.join(BDIR, "results.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
