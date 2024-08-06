#!/usr/bin/env tarantool
local json = require 'json'
local fio = require 'fio'
local log = {
	info = function(...)
		local nargs = select('#', ...)
		if nargs == 1 then
			io.stdout:write(tostring(...).."\n")
		elseif nargs > 1 then
			io.stdout:write(string.format(...).."\n")
		end
	end,
	error = function(...)
		local nargs = select('#', ...)
		if nargs == 1 then
			io.stderr:write(tostring(...).."\n")
		elseif nargs > 1 then
			io.stderr:write(string.format(...).."\n")
		end
	end,
	warn = function(...)
		local nargs = select('#', ...)
		if nargs == 1 then
			io.stderr:write(tostring(...).."\n")
		elseif nargs > 1 then
			io.stderr:write(string.format(...).."\n")
		end
	end,
}

local fiber = require 'fiber'
local clock = require 'clock'
local misc = require 'misc'

local err_fail = box.error.new({ code = 0x01, type = 'LuaBenchError', reason = 'Benchmark is failed' })
local err_skip = box.error.new({ code = 0x02, type = 'LuaBenchError', reason = 'Benchmark is skipped' })

---@class luabench.B
---@field N number
---@field name string
---@field run fun(self: luabench.B, name: string, func: fun(b: luabench.B))
---@field set_bytes fun(self: luabench.B, bytes: number)
---@field fail fun(self: luabench.B) immediately fail benchmark
---@field fatal fun(self: luabench.B, log_message: any?) fail benchmark with log message
---@field skip fun(self: luabench.B, skip_reason: any?) skip benchmark with reason
---@field package run1 fun(self: luabench.B): boolean
---@field package do_bench fun(self: luabench.B): table?
---@field package is_failed fun(self: luabench.B): boolean, string?
---@field package is_skipped fun(self: luabench.B): boolean, string?
---@field package set_bench_time fun(self: luabench.B, bt: luabench.bench_time)

---@class luabench.bench_time
---@field iters? number
---@field seconds? number

---@class luabench.R
---@field duration number in nanoseconds
---@field N number performed iterations
---@field net_bytes number bytes allocated
---@field bytes number bytes set by benchmark
---@field runs luabench.R[] recorded runs of benchmark

---@param runs luabench.R[]
---@param func fun(luabench.R):number
local statistics = function(runs, func)
	---@type number[]
	local values = {}
	local result = {
		max = 0,
		min = math.huge,
		avg = nil,
		len = #runs,
		values = values,
	}
	for _, run in ipairs(runs) do
		local value = func(run)
		table.insert(values, value)
	end
	table.sort(values)

	local n = #values
	-- exclude ≤10% and ≥90% of values
	local tenth = math.ceil(n*0.1)
	for _ = 1, tenth do
		table.remove(values, 1)
		table.remove(values)
	end

	result.min = values[1]
	result.max = values[1]

	if #values == 0 then
		return result
	end

	local sum = 0
	for _, value in ipairs(values) do
		if value > result.max then
			result.max = value
		end
		if value < result.min then
			result.min = value
		end
		sum = sum + value
	end
	result.avg = sum / #values
	local stdev = 0
	for _, value in ipairs(values) do
		stdev = stdev + math.abs(value - result.avg)^2
	end
	result.stdev = math.sqrt(stdev / #values)
	if result.avg ~= 0 then
		result.stdev_pct = (result.stdev / result.avg)*100
	else
		result.stdev_pct = (result.stdev / 1.0)*100
	end
	result.lower_value = result.min
	result.upper_value = result.max
	return result
end

---@type table<string, {report: fun(self: any, b: luabench.B, r: luabench.R), finish: fun(self: any)}>
local reporters; reporters = {
	plain = {
		report = function(_, b, r)
			---@cast r luabench.R
			if b:is_failed() then
				log.error("\n--- FAIL:  %s: %s", b.name, select(2, b:is_failed()))
			elseif b:is_skipped() then
				log.warn ("\n--- SKIP:  %s: %s", b.name, select(2, b:is_skipped()))
			elseif r then
				log.info ("\n--- BENCH: %s\n%s", b.name, tostring(r))
			end
		end,
		finish = function() end,
	},
	bmf = {
		stack = {},
		report = function(self, b, r)
			---@cast r luabench.R
			if b:is_failed() then
				log.error("\n--- FAIL:  %s: %s", b.name, select(2, b:is_failed()))
			elseif b:is_skipped() then
				log.warn ("\n--- SKIP:  %s: %s", b.name, select(2, b:is_skipped()))
			elseif r and r.duration ~= 0 then
				log.warn ("\n--- BENCH: %s\n%s", b.name, tostring(r))

				local stats = {
					latency = statistics(r.runs, function(run)
						return math.floor(tonumber(tonumber(run.duration) / run.N))
					end),
					throughput = statistics(r.runs, function(run)
						return math.floor(tonumber(run.N*1e9 / tonumber(run.duration)))
					end),
					net_bytes = statistics(r.runs, function(run)
						return math.floor(tonumber(tonumber(run.net_bytes) / run.N))
					end),
					bytes = statistics(r.runs, function(run)
						return math.floor(tonumber(tonumber(run.bytes or 0) / run.N))
					end),
				}
				stats.latency.value = math.floor(tonumber(tonumber(r.duration) / r.N))
				stats.throughput.value = math.floor(tonumber(r.N*1e9 / tonumber(r.duration)))
				stats.net_bytes.value = math.floor(tonumber(tonumber(r.net_bytes) / r.N))
				stats.bytes.value = math.floor(tonumber(tonumber(r.bytes or 0) / r.N))
				self.stack[b.name] = stats
			end
		end,
		finish = function(self)
			log.info(json.encode(self.stack))
		end
	},
}

local reporter = reporters.plain

local get_global_timeout, set_global_timeout do
	local global_timeout = 60

	function get_global_timeout() return global_timeout end
	function set_global_timeout(t) global_timeout = t end
end

---@param x number
---@param unit string
local function pretty(x, unit)
	local y = math.abs(tonumber(x))

	local format
	if y == 0 or y >= 999.95 then
		format = '%10.0f %s'
	elseif y >= 99.995 then
		format = '%12.1f %s'
	elseif y >= 9.9995 then
		format = '%13.2f %s'
	elseif y >= 0.99995 then
		format = '%14.3f %s'
	elseif y >= 0.099995 then
		format = '%15.4f %s'
	elseif y >= 0.0099995 then
		format = '%16.5f %s'
	elseif y >= 0.00099995 then
		format = '%17.6f %s'
	else
		format = '%18.7f %s'
	end

	return string.format(format, x, unit)
end

---@param b number
---@return string
local function pretty_mem(b)
	local sign = b > 0 and "+" or ""
	if b > 2^20 then
		return ("%s%.2fMB"):format(sign, b / 2^20)
	elseif b > 2^10 then
		return ("%s%.2fKB"):format(sign, b / 2^10)
	else
		return ("%s%dB"):format(sign, b)
	end
end

---@param name string
---@param func fun(b: luabench.B)
---@param bench_time luabench.bench_time
---@return luabench.B
local function newB(name, func, bench_time)
	local skipped = false
	local finished = false
	local failed = false
	local fail_reason
	local skip_reason

	local has_sub = false

	local function is_failed() return failed, fail_reason end

	local function is_skipped() return skipped, skip_reason end

	local function skip(_, ...)
		if ... then
			skip_reason = ...
		end
		skipped = true
		finished = true
		err_skip:raise()
	end

	local function fail()
		failed = true
		finished = true
		err_fail:raise()
	end

	local function fatal(_, ...)
		log.error(...)
		fail()
	end

	local clock_realtime64 = clock.realtime64
	local collectgarbage = collectgarbage

	local timerOn = false
	local started_at
	local duration = 0LL

	local start_bytes = 0
	local net_bytes = 0
	local bytes = 0

	local getmetrics = misc.getmetrics

	local function start_timer(_)
		if timerOn then return end
		start_bytes = getmetrics().gc_allocated
		started_at = clock_realtime64()
		timerOn = true
	end

	local function stop_timer(_)
		if not timerOn then return end
		duration = duration + clock_realtime64() - started_at
		net_bytes = getmetrics().gc_allocated - start_bytes
		timerOn = false
	end

	local function reset_timer(_)
		if timerOn then
			started_at = clock_realtime64()
			start_bytes = getmetrics().gc_allocated
		end
		duration = 0
		net_bytes = 0
		bytes = 0
	end

	local function rungc()
		local cycles = 0
		local mem2
		repeat
			local mem1 = collectgarbage("count")
			collectgarbage('collect')
			mem2 = collectgarbage("count")
			cycles = cycles + 1
		until mem2 > 0.75*mem1
	end

	local benchN = name
	local benchF = func

	local function runN(self, n, dur)
		fiber.self():set_joinable(true)
		self.N = n
		self.T = get_global_timeout()

		fiber.yield()
		if dur and fiber.set_slice then
			fiber.set_slice({ err = self.T, warn = math.max(dur, self.T / 2) })
		end

		rungc()

		reset_timer(self)
		start_timer(self)
		benchF(self)
		stop_timer(self)

		self.prev_n = n
		self.prev_duration = duration

		local result = self:get_result() --[[@as luabench.R]]

		table.insert(result.runs, {
			net_bytes = net_bytes,
			bytes = bytes,
			duration = duration,
			N = self.N,
		})

		if fiber.check_slice then
			fiber.check_slice()
		end
	end

	---@param self luabench.B
	---@return boolean should_continue
	local function run1(self)
		local fib = fiber.create(runN, self, 1, get_global_timeout())
		local r = { fib:join() }
		local success = table.remove(r, 1)

		if not success then
			local err = r[1]
			if err ~= err_fail and err ~= err_skip then
				failed = true
				fail_reason = err
			end
			return false
		end

		if has_sub then
			-- has sub benchmark
			return false
		end

		if failed then
			-- was failed, don't need to continue
			return false
		end

		if skipped then
			-- benchmark was skipped
			return false
		end

		if finished then
			-- already finished, don't need to continue
			return false
		end

		return true
	end

	---@type luabench.R
	local result = setmetatable({
		runs = {},
	}, {
		__tostring = function(self)
			local t = {}

			t[1] = ("%8d"):format(self.N)
			if self.duration ~= 0 then
				table.insert(t, pretty(tonumber(self.duration) / self.N, 'ns/op'))
				table.insert(t, pretty(self.N*1e9 / tonumber(self.duration), 'op/s'))
			end

			if type(self.bytes) ~= 'number' then
				self.bytes = 0
			end

			local mbs
			if self.bytes <= 0 or self.duration <= 0 or self.N <= 0 then
				mbs = 0
			else
				mbs = (tonumber(self.bytes) * self.N / 1e6) / (tonumber(self.duration) / 1e9)
			end

			if mbs ~= 0 then
				table.insert(t, ('%7.2f MB/s'):format(mbs))
			end

			table.insert(t, ("%8d B/op"):format(tonumber(self.net_bytes) / self.N))
			table.insert(t, pretty_mem(tonumber(self.net_bytes)))
			return table.concat(t, '\t')
		end,
	})

	local function get_result() return result end

	---Runs given benchmark as sub-benchmark
	---
	---And awaits it's result
	---
	---Firstly, it runs benchmark as `run1` and if `run1` allows
	---further execution it reruns benchmark in `do_bench` func
	---
	---@param _name string name of benchmark
	---@param _func fun() benchmark function
	---@return boolean success returns true when benchmark finished successfully
	local function run(_, _name, _func)
		has_sub = true

		local fullname
		if benchN == '' then
			fullname = _name
		else
			fullname = ("%s:%s"):format(benchN, _name)
		end

		local sub = newB(fullname, _func, bench_time)
		local res
		if sub:run1() then
			res = sub:do_bench()
		end

		reporter:report(sub, res)
		return not sub:is_failed()
	end

	local function min(a,b)
		if a < b then
			return a
		else
			return b
		end
	end
	local function max(a, b)
		if a < b then
			return b
		else
			return a
		end
	end

	local function launch(self)
		if bench_time.iters then
			if bench_time.iters > 1 then
				runN(self, bench_time.iters, get_global_timeout())
			end
		else
			local d = bench_time.seconds*1e9
			local goalns = d
			local n = 1LL
			while not failed and duration < d and n < 1e9 do
				local last = n
				local prev_iters = self.N
				local prev_ns = duration
				-- print("duration:", duration, "need:", d, "required_n: ", n, "real_n:", self.N)

				if prev_ns <= 0 then
					prev_ns = 1
				end

				if prev_iters < n then
					break
				end

				n = tonumber(goalns) / tonumber(prev_ns) * prev_iters
				n = n + n/5
				n = min(n, 100*last)
				n = max(n, last+1)
				n = min(n, 1e9)

				local dur = tonumber(prev_ns * (tonumber(n) / tonumber(prev_iters))) / 1e9
				runN(self,
					tonumber(n),
					dur
				)
			end
			-- print(duration, failed, d, n)
		end

		result.N = self.N
		result.duration = duration
		result.bytes = self.bytes
		result.net_bytes = net_bytes
	end

	---do_bench is private method to run full benchmark in separate fiber
	---
	---it creates new fiber with `launch` as main fiber function
	---
	---and awaits it's result
	---@param self any
	---@return table? result
	local function do_bench(self)
		local fib = fiber.new(launch, self)
		fib:set_joinable(true)
		local success, err = fib:join()

		if not success then
			log.error("Benchmark failed: %s", err)
			failed = true
			fail_reason = tostring(err)
			return nil
		end

		return result
	end

	---Resets bench_time
	---@param _ any
	---@param bt luabench.bench_time
	local function set_bench_time(_, bt)
		bench_time = bt
	end

	---@type luabench.B
	local B = {
		N = 0,
		name = name,

		skip = skip,
		fail = fail,
		fatal = fatal,
		is_failed = is_failed,
		is_skipped = is_skipped,
		set_bench_time = set_bench_time,

		set_bytes = nil,

		run = run,

		-- private
		runN = runN,
		run1 = run1,

		-- private
		do_bench = do_bench,

		-- private
		get_result = get_result,
	}

	function B.set_bytes(obj, b)
		if obj == B then
			bytes = b
		elseif tonumber(obj) then
			---@cast obj number
			bytes = obj
		end
	end

	return B
end

--- Default global benchmark context
local gbctx = newB("", function() end, { seconds = 1 })

local M = {
	before_all_triggers = {},
	after_all_triggers = {},
}

M._VERSION = '0.2.0'

function M.before_all(func)
	table.insert(M.before_all_triggers, func)
end

function M.after_all(func)
	table.insert(M.after_all_triggers, func)
end

---Runs list of triggers ony be one
---@param list any
---@return integer failed_triggers
local function run_triggers(list)
	local failed = 0
	for _, trigger in pairs(list) do
		local ok, err = pcall(trigger, gbctx)
		if not ok then
			local gi = debug.getinfo(trigger)
			log.error("Trigger %s:%s failed: %s", gi.source:sub(2), gi.linedefined, err)
			failed = failed + 1
		end
	end
	return failed
end

-- resolve circular dependencies
package.loaded['luabench'] = M

---@param root string
---@param recurse string[]
local function traverse(root, recurse)
	local list = assert(fio.listdir(root))
	for _, item in ipairs(list) do
		local full_path = fio.pathjoin(root, item)
		-- you won't have problems if you just skip symlinks ;)
		if not fio.readlink(full_path) then
			if fio.path.is_dir(full_path) then
				traverse(full_path, recurse)
			elseif fio.path.is_file(full_path) then
				table.insert(recurse, full_path)
			-- otherwise just skip
			end
		end
	end
end

---@class luabench.benchmark_file
---@field module table<string,fun(any)>
---@field funcs string[]
---@field file string

---requires benchmark file
---@param file string
---@return luabench.benchmark_file
local function load_benchmark_file(file)
	local env = setmetatable({}, {__index=_G})
	local loader, err = loadfile(file, "bt", env)
	if loader == nil then
		log.error("During parsing file %s: %s", file, err)
		os.exit(1)
	end

	local ok, module = pcall(loader, file)
	if not ok then
		log.error("During loading file %s: %s", file, module)
		os.exit(1)
	end

	if type(module) ~= 'table' then
		log.error('Benchmark file expected to return "table", received %q (file: %q)',
		type(module), file)
		os.exit(1)
	end

	-- now we traverse module-table to find 'bench_' function
	local funcs = {}
	for name, func in pairs(module) do
		if type(name) == 'string' and name:startswith('bench_') then
			if type(func) == 'function' then
				table.insert(funcs, name)
			end
		end
	end

	if #funcs == 0 then
		log.warn("Benchmark file has no bench_XXX functions (file: %q)", file)
	end

	table.sort(funcs)

	return {
		file = file,
		module = module,
		funcs = funcs,
	}
end

local function cpu_info()
	local cpu_name = ''
	if jit.os =='OSX' then
		local cpu = io.popen('sysctl machdep.cpu'):read("*a")
		local info = {}
		for _, line in ipairs(cpu:split("\n")) do
			local name, value = unpack(line:split(": "))
			info[name] = value
		end
		if info['machdep.cpu.brand_string'] then
			cpu_name = info['machdep.cpu.brand_string']
			if info['machdep.cpu.core_count'] then
				cpu_name = cpu_name .. " @ " .. info['machdep.cpu.core_count']
			end
		end
	elseif jit.os == 'Linux' then
		local file = io.open('/proc/cpuinfo', 'r')
		if file then
			local cpu_model, cpu_mhz = '', ''
			for line in file:lines() do
				if line:find(':') then
					local name, value = unpack(line:split(": "))
					name = name:rstrip():lower()
					if name == 'model name' then
						cpu_model = value
					elseif name == 'cpu mhz' then
						cpu_mhz = value
					end
				end
			end

			if cpu_model ~= "" then
				if cpu_mhz == '' or cpu_model:find('MHz') or cpu_model:find('GHz') then
					cpu_name = cpu_model
				else
					cpu_name = cpu_model .. ' @ ' .. cpu_mhz .. 'MHz'
				end
			end
		end
	end
	return cpu_name
end

---Runs benchmark from cli
---@param args table
local function run(args)
	local path = args.path
	assert(type(path) == 'string')

	---@type string[]
	local tree = {}
	if not fio.path.exists(path) then
		log.error("Path %s does not exists", path)
		os.exit(1)
	elseif fio.path.is_file(path) then
		tree[1] = path
	elseif fio.path.is_dir(path) then
		-- do traverse
		traverse(path, tree)
	else
		log.error("Given path %s is not a file nor directory", path)
		os.exit(1)
	end

	-- now filter files with suffix '_bench.lua'
	-- and perform init/load phase (it might fail)
	local files = {}
	local benchmarks = {}
	for _, file in ipairs(tree) do
		if file:endswith('_bench.lua') then
			local _, err = fio.stat(file)
			if err == nil then
				table.insert(files, file)
				benchmarks[file] = load_benchmark_file(file)
			else
				log.error(err)
			end
		end
	end

	table.sort(files)

	-- now we start benchmarking, file by file
	-- for each benchmark-function we must create benchmark-context
	-- but only before execution

	-- global benchmark context

	if run_triggers(M.before_all_triggers) ~= 0 then
		os.exit(1)
	end

	set_global_timeout(args.timeout)

	-- print-out preambule
	if not args.no_preambule then
		local tarantool = require 'tarantool'
		log.warn("Tarantool version: %s %s", tarantool.package, tarantool.version)
		log.warn("Tarantool build: %s (%s)", tarantool.build.target, tarantool.build.linking)
		log.warn("Tarantool build flags: %s", tarantool.build.flags)

		local cpu_name = cpu_info()
		if cpu_name then
			log.warn("CPU: %s", cpu_name)
		end

		local jits = { jit.status() }
		local jit_enabled = table.remove(jits, 1)
		log.warn("JIT: %s", jit_enabled and "Enabled" or "Disabled")
		if jit_enabled then
			log.warn("JIT: %s", table.concat(jits, " "))
		end
		log.warn("Duration: %s",
			args.duration.seconds and ("%ss"):format(args.duration.seconds)
				or ("%s iters"):format(args.duration.iters)
		)
		log.warn("Global timeout: %s", args.timeout)
	end

	gbctx:set_bench_time(args.duration)
	if args.bmf then
		reporter = reporters.bmf
		table.insert(M.after_all_triggers, 1, function() reporter:finish()  end)
	end

	for _, file in ipairs(files) do
		local bench_file = benchmarks[file]

		for _, func_name in ipairs(bench_file.funcs) do
			local name = ('%s::%s'):format(fio.basename(bench_file.file, ".lua"), func_name)
			local func = bench_file.module[func_name]

			local report = gbctx:run(name, func)

			if not report then
				log.error("%s failed", name)
			end
		end
	end

	if run_triggers(M.after_all_triggers) ~= 0 then
		os.exit(1)
	end

	return true
end

local mod_name = ...
if not mod_name or not mod_name:endswith("luabench") then
	local defaults = {
		timeout  = 60,
		bmf      = false,
		jit      = nil,
		duration = '3s',
		path     = '.',
	}
	local options = {
		timeout  = os.getenv('LUABENCH_TIMEOUT'),
		bmf      = os.getenv('LUABENCH_USE_BMF'),
		jit      = os.getenv('LUABENCH_JIT'),
		duration = os.getenv('LUABENCH_DURATION'),
		path     = os.getenv('LUABENCH_PATH'),
	}
	local function merge(dst, src)
		for k, v in pairs(src) do
			if dst[k] == nil then dst[k] = v end
		end
		return dst
	end
	local function def(target)
		if defaults[target] ~= nil then
			return (' (default: %s)'):format(defaults[target])
		else
			return ''
		end
	end
	local dotluabench do
		dotluabench = {}
		local cwd = fio.abspath('.')
		repeat
			local path = fio.pathjoin(cwd, '.luabench')
			if fio.path.is_file(path) then
				local fh = io.open(path, 'r')
				if not fh then break end
				local content = fh:read("*a")
				local loader = loadstring(content, '.luabench')
				if loader then
					debug.setfenv(loader, dotluabench)
					if not pcall(loader) then
						dotluabench = {}
					elseif dotluabench.path then
						local dot_path = dotluabench.path:gsub('/+', '/'):gsub('/$', '')
						local abs_path = fio.abspath(dot_path)
						if abs_path ~= dot_path then
							-- it is relative?
							dotluabench.path = fio.pathjoin(cwd, dot_path)
						end
					end
				end
				break
			end
			cwd = fio.dirname(cwd)
		until path == '/.luabench'
	end
	local parser = require 'argparse'()
		:name "luabench"
		:description "Runs lua code benchmarks"
		:add_help(true)

	parser:flag "-v" "--verbose"
		:target "verbose"
		:description "Increase verbosity"

	parser:flag "--version"
		:description "Prints version"
		:action(function() print("luabench " .. M._VERSION) os.exit(0) end)

	parser:option "-t" "--timeout"
		:target "timeout"
		:description("global timeout"..def 'timeout')

	parser:argument "path"
		:target "path"
		:args "0-1"
		:description ("Run benchmark from specified paths"..def 'path')

	parser:flag "--bmf"
		:target "bmf"
		:description ("Reports benchmark in BMF format"..def 'bmf')

	parser:option "-j"
		:target "jit"
		:args "1"
		:description ("Ons or Offs jit"..def 'jit')

	parser:flag "--no-preambule"
		:target "no_preambule"
		:description "Hides preambule"

	parser:flag "--description"
		:hidden(true)

	parser:option "-d"
		:target "duration"
		:description ("test duration limit"..def 'duration')

	local function convert_duration(x)
		local iters = x:match('^([0-9]+)x$')
		if iters then
			return { iters = tonumber(iters) }
		end

		local units = {
			ns = 1,
			['µs'] = 1e3,
			us = 1e3,
			ms = 1e6,
			s  = 1e9,
			m  = 60*1e9,
			h  = 24*60*1e9,
		}

		local len = #x
		local pos = 1

		local dur = 0ULL
		while pos < len do
			local s, f = string.find(x, '^[0-9]+', pos)
			if not s then
				return nil, ("malformed duration at position %d for %q"):format(pos, x)
			end

			local int = tonumber(x:sub(s, f))
			local fract = 0
			pos = f+1

			do
				-- check fraction
				local ds, df = x:find('^%.[0-9]+', pos)
				if ds then
					-- got fraction
					fract = tonumber(x:sub(ds, df)) or 0
					pos = df+1
				end
			end

			local us, uf = x:find('^[^0-9]+', pos)
			if not us then
				return nil, ("malformed duration: time unit not given at position %d for %q")
					:format(pos, x)
			end

			local unit = x:sub(us, uf)
			if not units[unit] then
				return nil, ("malformed duration: unknown time unit given %q"):format(unit)
			end
			-- we can lose accuracy in this loop
			dur = dur + (tonumber(int) + fract)*units[unit]
			pos = uf+1
		end

		local seconds = tonumber(dur) / 1e9
		return { seconds = tonumber(seconds) }
	end

	local args = parser:parse()
	if args.description then
		print(parser._description)
		os.exit(0)
	end

	args = merge(args, options)
	args = merge(args, dotluabench)
	args = merge(args, defaults)

	if args.jit then
		local opt = args.jit
		if opt == 'on' then
			jit.on()
		elseif opt == 'off' then
			jit.off()
			jit.flush()
			collectgarbage('collect')
		end
	end
	if type(args.duration) == 'string' then
		args.duration = convert_duration(args.duration)
	end

	os.exit(run(args))
end

return M
