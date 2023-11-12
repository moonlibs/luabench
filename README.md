# luabench

**luabench** is a benchmarking tool designed for unit benchmarking of Lua modules in Tarantool. It draws inspiration from Go's `testing/bench`, bringing similar functionality to the Lua ecosystem. With luabench, you can easily measure and analyze the performance of your Lua code.

## Features and Capabilities

- **Selective Benchmarking:** Targets files with '_bench.lua' suffix in the working directory.
- **Customizable Duration and Iterations:** Specify the benchmark duration (`-d`) in seconds (e.g., `-d 10s`) or iterations (e.g., `-d 1000x`).
- **Sequential Execution:** Each benchmark function is executed in a separate fiber sequentially, not concurrently.
- **Performance Metrics:** Reports the average time per operation and average operations per second, along with total allocated memory for each benchmark test.
- **Output Format:** Benchmark results are output to stdout in the same format as Go's `testing/bench`.
- **Skipping and Failing Benchmarks:** Users can skip a benchmark by calling `b:skip("<skip-reason>")` or fail a benchmark using `b:fail("<fail-reason>")`.

## Installation

**Via Tarantool Rocks:**

```bash
tt rocks --server https://moonlibs.org install luabench
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
Usage: luabench [-v] [-d <d>] [-h] [<path>]

Runs lua code benchmarks

Arguments:
   path                  Run benchmark from specified paths (default: .)

Options:
   -v, --verbose         Increase verbosity
   -d <d>                Test duration limit
   -h, --help            Show this help message and exit.
```

### Example Output

```bash
.rocks/bin/luabench -d 100x examples/001_bench.lua
Tarantool version: 2.11.1-0-g96877bd
Tarantool build: Darwin-arm64-RelWithDebInfo
CPU: Apple M1 @ 8
JIT: Disabled
Duration: 100 iters

--- SKIP:  001_bench::bench_insert:local-table

--- BENCH: 001_bench::bench_insert:rewrite-1000
     100                30.00 ns/op       33333333 op/s       38 B/op   +3.72KB

--- BENCH: 001_bench::bench_insert:temporary-space
     100               410.0 ns/op         2439024 op/s       91 B/op   +8.96KB

--- SKIP:  001_bench::bench_sum
```

## Dependencies

No external dependencies required.

## Contributing

Contributions are welcome! Feel free to suggest pull requests at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).

## License

luabench is MIT licensed. See [LICENSE](https://github.com/moonlibs/luabench/blob/master/LICENSE) for more details.

## Contact

For support, feedback, or contributions, please file tickets at [github.com/moonlibs/luabench](https://github.com/moonlibs/luabench).
