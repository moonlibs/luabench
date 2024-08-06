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

Latest release: `0.3.0`

## Installation

**Via Tarantool Rocks:**

```bash
tt rocks --server https://moonlibs.org install luabench 0.3.0
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
Usage: luabench [-v] [--version] [-t <timeout>] [--bmf] [-j <j>]
       [--no-preambule] [-d <d>] [-h] [<path>]

Runs lua code benchmarks

Arguments:
   path                  Run benchmark from specified paths (default: .)

Options:
   -v, --verbose         Increase verbosity
   --version             Prints version
          -t <timeout>,  global timeout (default: 60)
   --bmf                 Reports benchmark in BMF format (default: false)
   -j <j>                Ons or Offs jit
   --no-preambule        Hides preambule
   -d <d>                test duration limit (default: 3s)
   -h, --help            Show this help message and exit.
```

### Example Output

```bash
.rocks/bin/luabench -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-arm64-RelWithDebInfo (static)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common  -fmacro-prefix-map=/var/folders/8x/1m5v3n6d4mn62g9w_65vvt_r0000gn/T/tarantool_install934702387=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O2 -g -DNDEBUG -ggdb -O2
CPU: Apple M1 @ 8
JIT: Disabled
Duration: 100 iters
Global timeout: 60

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100                30.00 ns/op       33333333 op/s       29 B/op   +2.92KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100               600.0 ns/op         1666667 op/s      126 B/op   +12.34KB

--- SKIP:  001_bench::bench_sum: no summing for today
```

### Enabling/Disabling JIT

You may specify `-jon` or `-joff` to enable or disable jit by force

```bash
.rocks/bin/luabench -jon -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-arm64-RelWithDebInfo (static)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common  -fmacro-prefix-map=/var/folders/8x/1m5v3n6d4mn62g9w_65vvt_r0000gn/T/tarantool_install934702387=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O2 -g -DNDEBUG -ggdb -O2
CPU: Apple M1 @ 8
JIT: Enabled
JIT: fold cse dce fwd dse narrow loop abc sink fuse
Duration: 100 iters
Global timeout: 60

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100               380.0 ns/op         2631579 op/s       36 B/op   +3.56KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100              1040 ns/op            961538 op/s      149 B/op   +14.61KB

--- SKIP:  001_bench::bench_sum: no summing for today
```

### Bencher support

With flag `--bmf` `luabench` prints out to stdout Benchmark results in Bencher Json format.

```bash
.rocks/bin/luabench --bmf -d 100x examples/001_bench.lua
Tarantool version: Tarantool 3.1.0-0-g96f6d88
Tarantool build: Darwin-arm64-RelWithDebInfo (static)
Tarantool build flags:  -fexceptions -funwind-tables -fasynchronous-unwind-tables -fno-common  -fmacro-prefix-map=/var/folders/8x/1m5v3n6d4mn62g9w_65vvt_r0000gn/T/tarantool_install934702387=. -std=c11 -Wall -Wextra -Wno-gnu-alignof-expression -Wno-cast-function-type -O2 -g -DNDEBUG -ggdb -O2
CPU: Apple M1 @ 8
JIT: Enabled
JIT: fold cse dce fwd dse narrow loop abc sink fuse
Duration: 100 iters
Global timeout: 60

--- SKIP:  001_bench::bench_insert:local-table: no local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100               340.0 ns/op         2941176 op/s       36 B/op   +3.56KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100              1100 ns/op            909091 op/s      149 B/op   +14.61KB

--- SKIP:  001_bench::bench_sum: no summing for today
{"001_bench::bench_insert:temporary-space":{"latency":{"values":[],"len":2,"value":5360},"bytes":{"values":[],"len":2,"value":0},"throughput":{"values":[],"len":2,"value":186567},"net_bytes":{"values":[],"len":2,"value":160}},"001_bench::bench_insert:rewrite-1000":{"latency":{"values":[],"len":2,"value":3240},"bytes":{"values":[],"len":2,"value":0},"throughput":{"values":[],"len":2,"value":308641},"net_bytes":{"values":[],"len":2,"value":43}}}
```

With [bencher](https://bencher.dev/) you may run luabench as follows:

```bash
bencher run --project <PROJECT> --adapter json '.rocks/bin/luabench -d 1000x --bmf examples/001_bench.lua'
```

Also handy script to catch this `.env` file

```bash
BENCHER_PROJECT=luabench
BENCHER_ADAPTER=json
BENCHER_TESTBED=localhost
LUABENCH_DURATION=3s
LUABENCH_USE_BMF=true
LUABENCH_PATH=examples/001_bench.lua
```

with following command

```bash
env $(cat .env | xargs) bencher run '.rocks/bin/luabench'
```

## Configuration of luabench with .luabench file

Starting with `luabench 0.3.0` it is possible to configurate parameters of `luabench` via `.luabench` file.

```lua
-- Root path of files with benchmarks (relative path of .luabench file)
path = 'benchmarks/'
-- Goal wall-time duration of each benchmark run
duration = '3s'
-- Status of jit ('on', 'off' or nothing)
jit = 'on'
-- Enables report with bmf (set to true for bencher.dev)
bmf = false
-- Global fiber slice timeout for each benchmark.
timeout = 60
```

## Dependencies

No external dependencies required.

## Contributing

Contributions are welcome! Feel free to suggest pull requests at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).

## License

luabench is MIT licensed. See [LICENSE](https://github.com/moonlibs/luabench/blob/master/LICENSE) for more details.

## Contact

For support, feedback, or contributions, please file tickets at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).
