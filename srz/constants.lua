local STOP = 511
local MATCH = 510
local LZMATCH = 0x100
local LUATOK = 0x180
local LUATOK_MAX = LUATOK + 31
local REP = LUATOK_MAX + 1
local REP_COUNT = 16
local REPMAX = REP + REP_COUNT - 1
local PAD_00 = REPMAX + 1
local PAD_00_MAX = PAD_00 + REP_COUNT - 1
local PAD_FF = PAD_00_MAX + 1
local PAD_FF_MAX = PAD_FF + REP_COUNT - 1
local LEN_MIN = 4
local REP_MIN = 3

return function()
	return STOP, MATCH, LZMATCH, LUATOK, LUATOK_MAX, REP, REP_COUNT, REPMAX, PAD_00, PAD_00_MAX, PAD_FF, PAD_FF_MAX, LEN_MIN, REP_MIN
end