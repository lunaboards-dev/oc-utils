-- Special not-quite LZSS implementation, which spits out tokenized data
local MATCH = 510
local LZMATCH = 0x100
local MIN_MATCH = 3
local MAX_MATCH = MIN_MATCH+31
local MAX_WINDOW_BITS = 12
local WINDOW_SIZE = 1 << MAX_WINDOW_BITS

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

function lz.compress(str, std)
	local offset = MIN_MATCH+1
	local output = {str:sub(1, MIN_MATCH)}
	local tokens = {}
	while offset <= #str do
		local window = str:sub(offset-WINDOW_SIZE, offset-1)
		local pos, matchlen
		for i=MAX_MATCH, MIN_MATCH, -1 do
			local tok = str:sub(offset, offset+i-1)
			pos = window:find(tok, 1, true)
			if pos then matchlen = i break end
		end
		--local pos = window:find(tok, 1, true)
		if pos then
			--[[local matchlen = MIN_MATCH
			while str:sub(offset, offset+matchlen) == window:sub(pos, pos+matchlen) and matchlen < MAX_MATCH do
				matchlen = matchlen + 1
			end]]
			local winpos = offset-#window-1
			local matchpos = winpos + pos
			local mpos = offset-matchpos-1
			if not std then
				local mpos_l = vli(mpos)
				local tid = LZMATCH | (mpos_l << 4) | (matchlen-MIN_MATCH)
				tokens[tid] = (tokens[tid] or 0) + 1
				table.insert(output, {
					token = tid,
					len = mpos_l,
					size = matchlen,
					pos = mpos
				})
			else
				tokens[MATCH] = (tokens[MATCH] or 0) + 1
				table.insert(output, {
					token = MATCH,
					size = matchlen,
					pos = mpos
				})
			end
			table.insert(output, "")
			offset = offset + matchlen
		else
			output[#output] = output[#output] .. str:sub(offset, offset)
			offset = offset + 1
		end
	end
	local tdat = {}
	for i=1, #output do
		local c = output[i]
		if type(c) == "string" then
			table.insert(tdat, c)
		end
	end
	return output, table.concat(tdat), tokens
end

return lz