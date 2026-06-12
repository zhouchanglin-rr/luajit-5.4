# Benchmark Results: LuaJIT vs reference Lua 5.4.8

- Repetitions per benchmark: 5 (minimum time kept)
- Mode: full
- Correctness under load: all outputs identical
- **Geometric-mean LuaJIT speedup: 6.28x**

| Benchmark | Args | Lua 5.4.8 (s) | LuaJIT (s) | Speedup | Output |
|-----------|------|---------------|-----------|---------|--------|
| fib | `34` | 0.3151 | 0.0578 | **5.45x** | match |
| ackermann | `3 9` | 0.1838 | 0.0305 | **6.03x** | match |
| mandelbrot | `800` | 0.6441 | 0.0801 | **8.04x** | match |
| nbody | `500000` | 0.8439 | 0.1116 | **7.56x** | match |
| spectralnorm | `550` | 0.4198 | 0.0180 | **23.38x** | match |
| fannkuch | `10` | 1.4221 | 0.3019 | **4.71x** | match |
| matmul | `160` | 0.0604 | 0.0077 | **7.89x** | match |
| sieve | `3000000 4` | 0.6637 | 0.1809 | **3.67x** | match |
| string_ops | `3000` | 0.0637 | 0.0266 | **2.39x** | match |
