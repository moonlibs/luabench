# luabench

**luabench** is a benchmarking tool designed for unit benchmarking of Lua modules in Tarantool. It draws inspiration from Go's `testing/benchmark`, bringing similar functionality to the Lua ecosystem. With luabench, you can easily measure and analyze the performance of your Lua code.

## Features and Capabilities

- **Selective Benchmarking:** Targets files with '_bench.lua' suffix in the working directory.
- **Customizable Duration and Iterations:** Specify the benchmark duration (`-d`) in seconds (e.g., `-d 10s`) or iterations (e.g., `-d 1000x`).
- **Sequential Execution:** Each benchmark function is executed in a separate fiber sequentially, not concurrently.
- **Performance Metrics:** Reports the average time per operation and average operations per second, along with total allocated memory for each benchmark test.
- **Output Format:** Benchmark results are output to stdout in the same format as Go's `testing/benchmark`.
- **Skipping and Failing Benchmarks:** Users can skip a benchmark by calling `b:skip("<skip-reason>")` or fail a benchmark using `b:fail("<fail-reason>")`.

## Status

Early proof-of-concept

Latest release: `0.1.1`

## Installation

**Via Tarantool Rocks:**

```bash
tt rocks --server https://moonlibs.org install luabench 0.1.1
```

**Manual Download:**
Download `luabench.lua` from [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench) and execute it.

## Usage

Create a file named `001_example_bench.lua` in your working project and write a benchmark test like the following:

```lua
-- Example benchmark test
local M = {}

---@param b luabench.B
function M.bench_sum(b)
    local sum = 0
    for i = 1, b.N do
        sum = sum + i
    end
end

return M
```

Define benchmark functions with the `bench_` prefix. These functions should accept a `luabench.B` type argument and respect the `b.N` field for loop iterations. Benchmarks can be skipped or failed using `b:skip("<skip-reason>")` or `b:fail("<fail-reason>")`, respectively.

To parameterize benchmarks, use sub-benchmarks as follows:

```lua
-- Sub-benchmark example
local M = {}

function M.bench_insert(b)
    b:run("table-100", function(sb)
        for i = 1, sb.N do
            t[i%100+1] = true
        end
    end)
    b:run("table-1000", function(sb)
        for i = 1, sb.N do
            t[i%1000+1] = true
        end
    end)
end

return M
```

### Command Line Usage

```bash
Usage: luabench [-v] [--version] [--bmf] [-j <j>] [--no-preambule]
       [-d <d>] [-h] [<path>]

Runs lua code benchmarks

Arguments:
   path                  Run benchmark from specified paths (default: .)

Options:
   -v, --verbose         Increase verbosity
   --version             Prints version
   --bmf                 Reports benchmark in BMF format
   -j <j>                Ons or Offs jit
   --no-preambule        Hides preambule
   -d <d>                test duration limit
   -h, --help            Show this help message and exit.
```

### Example Output

```bash
.rocks/bin/luabench -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-x86_64-Release (dynamic)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common -msse2 -Wformat -Wformat-security -Werror=format-security -fstack-protector-strong -fPIC -fmacro-prefix-map=/tmp/tarantool-20240417-5649-53mktp/tarantool-3.1.0=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O3 -DNDEBUG
CPU: Apple M2 Pro @ 10
JIT: Disabled
Duration: 100 iters

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100                50.00 ns/op       20000000 op/s       29 B/op   +2.92KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100              1100 ns/op            909091 op/s      126 B/op   +12.34KB

--- SKIP:  001_bench::bench_sum: no summing for today
```

### Enabling/Disabling JIT

You may specify `-jon` or `-joff` to enable or disable jit by force

```bash
.rocks/bin/luabench -jon -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-x86_64-Release (dynamic)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common -msse2 -Wformat -Wformat-security -Werror=format-security -fstack-protector-strong -fPIC -fmacro-prefix-map=/tmp/tarantool-20240417-5649-53mktp/tarantool-3.1.0=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O3 -DNDEBUG
CPU: Apple M2 Pro @ 10
JIT: Enabled
JIT: SSE2 SSE3 SSE4.1 fold cse dce fwd dse narrow loop abc sink fuse
Duration: 100 iters

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100             14270 ns/op             70077 op/s       36 B/op   +3.56KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100              9340 ns/op            107066 op/s      149 B/op   +14.62KB

--- SKIP:  001_bench::bench_sum: no summing for today
```

### Bencher support

With flag `--bmf` `luabench` prints out to stdout Benchmark results in Bencher Json format.

```bash
.rocks/bin/luabench --bmf -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-x86_64-Release (dynamic)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common -msse2 -Wformat -Wformat-security -Werror=format-security -fstack-protector-strong -fPIC -fmacro-prefix-map=/tmp/tarantool-20240417-5649-53mktp/tarantool-3.1.0=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O3 -DNDEBUG
CPU: Apple M2 Pro @ 10
JIT: Disabled
Duration: 100 iters

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100                50.00 ns/op       20000000 op/s       29 B/op   +2.92KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100              1090 ns/op            917431 op/s      126 B/op   +12.34KB

--- SKIP:  001_bench::bench_sum: no summing for today
{"001_bench::bench_insert:temporary-space":{"latency":{"value":1090},"throughput":{"value":917431},"net_bytes":{"value":126}},"001_bench::bench_insert:rewrite-1000":{"latency":{"value":50},"throughput":{"value":20000000},"net_bytes":{"value":29}}}
```

With [bencher](https://bencher.dev/) you may run luabench as follows:

```bash
bencher run --project <PROJECT> --adapter json '.rocks/bin/luabench -d 1000x --bmf examples/001_bench.lua'
```

## Dependencies

No external dependencies required.

## Contributing

Contributions are welcome! Feel free to suggest pull requests at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).

## License

luabench is MIT licensed. See [LICENSE](https://github.com/moonlibs/luabench/blob/master/LICENSE) for more details.

## Contact

For support, feedback, or contributions, please file tickets at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).
