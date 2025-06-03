local STOP, MATCH, LZMATCH, LUATOK, LUATOK_MAX, REP, REP_COUNT, REPMAX, PAD_00, PAD_00_MAX, PAD_FF, PAD_FF_MAX, LEN_MIN, REP_MIN = require("srz.constants")()
local POS_BITS = 12
local LEN_BITS = 16 - POS_BITS
local POS_SIZE = 1 << POS_BITS
local LEN_SIZE = 1 << LEN_BITS

local lz = {}

local function vli(v)
	local running = 0
	for i=1, 4 do
		running = (1 << (i*3))-1
		--running = running | (8 << (i*3))
		if v <= running then
			return i-1
		end
	end
	error("integer too large ("..v.." > "..running..")")
end

local esc = {}

local _esc = "().%+-*?[^$"
for i=1, #_esc do
	local c = _esc:sub(i,i)
	esc[c] = "%"..c
end

function lz.lzss_compress(input, custom)
	local offset = 1
	local chunks = {}
	local window = ''
	local tokens = {}
	local buffer = {}
	local len_bits = custom and (17 - POS_BITS) or LEN_BITS
	local len_size = 1 << len_bits
	local total_symbols = 0
	local function repsearch()
		local c = input:sub(offset, offset)--sub(offset, offset)
		local rep = input:match((esc[c] or c).."+", offset)
		local len = #rep
		return math.min(len, REP_MIN+REP_COUNT-1), c:byte()
		--[[for i=1, REP_MIN + REP_COUNT-1 do
			local o = offset+i
			if input:byte(o) ~= c then
				return i-1, c
			end
		end]]
		--[[for i=1, REP_MIN + REP_COUNT - 1 do
			local k = input:byte(offset+i)
			if c ~= k then
				return i, c
			end
		end
		return REP_MIN + REP_COUNT-1, c]]
	end
	local function search()
		for i = len_size + LEN_MIN - 1, LEN_MIN, -1 do
			local str = string.sub(input, offset, offset + i - 1)
			local pos = string.find(window, str, 1, true)
			if pos then
				return pos, str
			end
		end
	end

	while offset <= #input do

		--for i = 0, 7 do
			--if offset <= #input then
				local pos, str = search()
				if not pos then
					local count, char = repsearch()
					if count >= REP_MIN then
						str = input:sub(offset, offset):rep(count)
						local tok = REP + (count - REP_MIN)
						table.insert(chunks, table.concat(buffer))
						buffer = {}
						if char == 0 then
							tok = PAD_00 + (count - REP_MIN)
						elseif char == 0xFF then
							tok = PAD_FF + (count - REP_MIN)
						end
						table.insert(chunks, {
							token = tok,
							data = char,
							count = count
						})
						--io.stderr:write("REP\t", tok, "\n")
						tokens[tok] = (tokens[tok] or 0) + 1
						total_symbols = total_symbols + 1
						if char ~= 0 and char ~= 0xFF then--true then
							tokens[char] = (tokens[char] or 0) + 1
							total_symbols = total_symbols + 1
						end
						--table.insert(buffer, string.char(char))
						goto continue
					end
				end
				if pos and #str >= LEN_MIN then
					local winpos = offset-#window-1
					local matchpos = winpos + pos
					local mpos = offset-matchpos-1
					table.insert(chunks, table.concat(buffer))
					buffer = {}
					if custom then
						local mpos_l = vli(mpos)
						local tok = LZMATCH | (mpos_l << 5) | (#str-LEN_MIN)
						table.insert(chunks, {
							token = tok,
							len = mpos_l,
							size = #str,
							pos = mpos
						})
						--io.stderr:write("LZM\t", tok, "\n")
						tokens[tok] = (tokens[tok] or 0) + 1
						total_symbols = total_symbols + 1
					else
						table.insert(chunks, table.concat(buffer))
						buffer = {}
						table.insert(chunks, {
							token = MATCH,
							size = #str,
							pos = mpos
						})
						tokens[MATCH] = (tokens[MATCH] or 0) + 1
						total_symbols = total_symbols + 1
					end
				else
					local char = input:byte(offset)
					tokens[char] = (tokens[char] or 0) + 1
					str = string.sub(input, offset, offset)
					table.insert(buffer, str)
					total_symbols = total_symbols + 1
				end
				::continue::
				window = string.sub(window .. str, -POS_SIZE)
				offset = offset + #str
			--else
				--break
			--end
		--end
	end
	if #buffer > 0 then
		table.insert(chunks, table.concat(buffer))
	end
	return chunks, tokens, total_symbols
end

return lz