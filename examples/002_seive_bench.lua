local lb = require 'luabench'

local M = {}

local function make_seiver(limit)
	local flags = table.new(limit, 0)
	return function(b)
		for _ = 1, b.N do
			local count = 0
			table.clear(flags)
			for j = 1, limit do
				flags[j] = 1
			end
			for j = 2, limit do
				if flags[j] == 1 then
					for k = j+j, limit, j do
						flags[k] = 0
					end
					count = count + 1
				end
			end
		end
	end
end

---@param b luabench.B
function M.bench_seive(b)
	b:run("seive-100", make_seiver(100))
	b:run("seive-1000", make_seiver(1000))
	b:run("seive-10000", make_seiver(10000))
	b:run("seive-100000", make_seiver(100000))
end

return M
