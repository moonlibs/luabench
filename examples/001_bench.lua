local lb = require 'luabench'

lb.before_all(function(b)
	local fio = require 'fio'
	local dir = fio.tempdir()
	fio.mktree(dir)

	b.dir = dir

	box.cfg{ memtx_memory = 2^30, memtx_dir = dir, wal_dir = dir, vinyl_dir = dir, log_level = 1 }
	box.schema.space.create('temporary', { if_not_exists = true, temporary = true })
	box.space.temporary:create_index('primary', { type = 'HASH' })
end)

lb.after_all(function(b)
	local fio = require 'fio'
	fio.rmtree(b.dir)
end)

local M = {}

---@param b luabench.B
function M.bench_sum(b)
	b:skip("no summing for today")
	local sum = 0
	for i = 1, b.N do
		sum = sum + i
	end
end

---@param b luabench.B
function M.bench_insert(b)
	local t = {}
	b:run("local-table", function (sb)
		sb:skip("no local-table")
		for i = 1, sb.N do
			t[i] = true
		end
		table.clear(t)
	end)

	b:run("rewrite-1000", function(sb)
		for i = 1, sb.N do
			t[i%1000+1] = true
		end
		table.clear(t)
	end)

	b:run("temporary-space", function(sb)
		local temporary = box.space.temporary
		local replace = temporary.replace
		local tbl = table.new(2, 0)
		for i = 1, sb.N do
			tbl[1] = i%1000+1
			tbl[2] = true
			replace(temporary, tbl)
		end
	end)
end

return M
