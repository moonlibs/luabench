local M = {}

local clock = require 'clock'

function M.bench_global_timeout(b)
	if b.N == 1 then return end
	local deadlime = clock.time() + b.T
	local i = 0
	while true do
		i = i + 1
		if clock.time() > deadlime then
			b.N = i
			break
		end
	end
end

return M
