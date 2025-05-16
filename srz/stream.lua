local xxh = require("srz.xxh32")
local stm = {}

local str = {}

local function bm(bits, shift)
	return {bits << shift, shift}
end

local function mask(int, bm)
	return (int & bm[1]) >> bm[2]
end

function stm.string(_str)

end

function stm.file(hand)

end

function str:read()

end

function str:write()

end

function str:flush()

end

return stm