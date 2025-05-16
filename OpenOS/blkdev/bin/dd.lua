-- Disk destroyer
local _args = {...}

local known_args = {
	of = true,
	["if"] = true,
	od = true,
	id = true,
	bs = true,
	count = true,
	status = true,
	skip = true,
}

local args = {}

for i=1, #_args do
	local k, v = _args[i]:match("([^=]+)=(.+)")
	args[k] = v
end

