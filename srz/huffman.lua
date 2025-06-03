local lz = require("srz.lzss")
local bstr = require("srz.bstr")
-- I'll be quite honest, i haven't got a fucking clue what i'm doing

local POS_BITS = 12
local LEN_BITS = 16 - POS_BITS
local POS_SIZE = 1 << POS_BITS
local LEN_SIZE = 1 << LEN_BITS

local huff = {}

local STOP, MATCH, LZMATCH, LUATOK, LUATOK_MAX, REP, REP_COUNT, REPMAX, PAD_00, PAD_00_MAX, PAD_FF, PAD_FF_MAX, LEN_MIN, REP_MIN = require("srz.constants")()
local token_decode = setmetatable({
	[STOP] = "STOP",
	[MATCH] = "MATCH<S>"
}, {__index=function(_, i)
	if type(i) ~= "number" then return "'"..i.."'" end
	if i > 31 and i < 127 then
		return "`"..string.char(i).."`"
	elseif i > 255 then
		return string.format("MATCH<%d:%d>", (i >> 4) & 7, i & 0xF)
	else
		return string.format("<\\%d>", i)
	end
end})

local token_writeout = setmetatable({
	[STOP] = "\27[33m<STOP>\27[0m\n",
	[MATCH] = "\27[33m<MATCH[S]>\27[0m"
}, {__index=function(_, i)
	if type(i) ~= "number" then return "'"..i.."'" end
	if i < 256 then
		return string.char(i)
	elseif i & 0x180 == 0x100 then
		local pos_l = (i >> 5) & 3
		local len = (i & 31) + 4
		return string.format("\27[33m<MATCH[%d:%d]>\27[0m", (i >> 4) & 7, i & 0xF)
	elseif i >= REP and i <= REPMAX then
		return string.format("\27[33m<REP[%d]>\27[0m", i-REP+3)
	elseif i >= PAD_00 and i <= PAD_00_MAX then
		return string.format("\27[33m<PAD-00[%d]>\27[0m", i-PAD_00+3)
	elseif i >= PAD_FF and i <= PAD_FF_MAX then
		return string.format("\27[33m<PAD-FF[%d]>\27[0m", i-PAD_FF+3)
	else
		return string.format("\27[27m<UNKNOWN[%d]>\27[0m", i)
	end
end})

local dbg = n

local function dwrite(...)
	if dbg then io.stderr:write(...) end
end

local function dprint(...)
	local v = table.pack(...)
	for i=1, #v do v[i] = tostring(v) end
	dwrite(table.concat(v, "\t"), "\n")
end

local function mangle_string(v)
	local bwt, sent, idx, esc = require("srz.bwt").encode(v)
	return require("srz.mtf").encode(v), sent, idx, esc
end

local function build_freq(chunks, matches)
	local fr = matches
	fr[STOP] = 1
	--[[for i=1, #str do
		local b = str:byte(i)
		fr[b] = (fr[b] or 0) + 1
	end]]
	--[[for c=1, #chunks do
		local cnk = chunks[c]
		if type(cnk) == "string" then
			local rstr, sent, idx, escc = mangle_string(cnk)
			chunks[c] = rstr
			for i=1, #rstr do
				local b = rstr:byte(i)
				fr[b] = (fr[b] or 0) + 1
			end
		end
	end]]
	local frlist = {}
	for k, v in pairs(fr) do
		table.insert(frlist, {v, k})
	end
	table.sort(frlist, function(a, b)
		return a[1] > b[1]
	end)
	return frlist, fr
end

local function pq_insert(queue, val)
	for i=1, #queue do
		if val.freq > queue[i].freq then
			table.insert(queue, i, val)
			return
		end
	end
	table.insert(queue, val)
end

local function build_tree(nodes)
	local queue = {}
	for i=1, #nodes do
		table.insert(queue, {dat = nodes[i][2], freq=nodes[i][1]})
	end
	while #queue >=2 do
		local left = table.remove(queue)
		local right = table.remove(queue)
		pq_insert(queue, {
			freq = (left.freq + right.freq),
			left = left,
			right = right
		})
	end
	local tree = queue[1]
	local lookup = {}
	local stree = bstr.new()
	local function preorder(root, cur, len, debug)
		if not root.left and not root.right then
			lookup[root.dat] = {cur, len, root.freq}
			stree:write(1, 1)
			stree:write(root.dat, 9)
			return
		end
		stree:write(0, 1)
		
		preorder(root.left, cur, len + 1, debug.."0")
		preorder(root.right, cur | (1 << len), len + 1, debug.."1")
	end
	preorder(tree, 0, 0, "")
	return lookup, tree, stree:finalize()
end

function huff.encode(str)
	local tokens, tokcount = lz.lzss_compress(str, true)
	local freq, flist = build_freq(tokens, tokcount)
	-- Build huffman tree
	local lookup, tree, stree = build_tree(freq)
	local res = bstr.new()
	local times_written = {}
	local longest_match = 0
	local furthest_match = 0
	local function wval(token)
		dwrite(token_writeout[token])
		local r = lookup[token]
		if not r then dwrite("unknown token "..token_decode[token].."!\n") end
		times_written[token] = (times_written[token] or 0) + 1
		res:write(r[1], r[2])
	end
	for e=1, #tokens do
		local ent = tokens[e]
		if type(ent) == "string" then
			for i=1, #ent do
				wval(ent:byte(i))
			end
		elseif ent.token >= REP and ent.token <= PAD_FF_MAX then
			local dl = lookup[ent.data][2]
			local rep_count = ent.count-LEN_MIN
			if lookup[REP + rep_count] and lookup[ent.token][2] > lookup[REP + rep_count][2] then
				ent.token = REP + rep_count
			end
			if lookup[ent.token][2]+dl < dl*ent.count then
				wval(ent.token)
				if ent.token <= REPMAX then
					wval(ent.data)
				end
			else
				for i=1, ent.count do
					wval(ent.data)
				end
			end
		elseif ent.token & 0x180 == 0x100 then
			wval(ent.token)
			local back, len = ent.pos, ent.size
			if len > longest_match then
				longest_match = len
			end
			if back > furthest_match then
				furthest_match = back
			end
			
			res:write(ent.pos, (ent.len+1)*3)
		elseif ent.token == MATCH then
			wval(ent.token)
			local back, len = ent.pos, ent.size

			if len > longest_match then
				longest_match = len
			end
			if back > furthest_match then
				furthest_match = back
			end
			res:write(((back - 1) << LEN_BITS) | (len - LEN_MIN), 16)
		else
			error("unknown token: "..ent.token)
		end
	end
	wval(STOP)
	local special = {[STOP] = "STOP", [MATCH] = "MATCH"}
	-- Stats, might be nice to have
	local stats = {
		tokens = {},
		longest = longest_match,
		furthest = furthest_match
	}
	for i=1, #freq do
		local frq, tok = freq[i][1], freq[i][2]
		local writes = times_written[tok]
		local size = lookup[tok][2]
		local sval = special[tok]
		sval = token_decode[tok]
		table.insert(stats.tokens, {
			frequency = frq,
			token = tok,
			writes = writes,
			size = size,
			stringval = sval
		})
	end
	return res:finalize(), stree, stats
end

function huff.loadtree(tdat)
	local tbuf = bstr.new(tdat)
	local function load_branch(rep)
		local bt = tbuf:read(1)
		if bt == 1 then
			local tok = tbuf:read(9)
			return {dat = tok, rep = rep}
		else
			return {
				load_branch(rep.."0"),
				load_branch(rep.."1")
			}
		end
	end
	local tree = load_branch("")
	return tree
end

function huff.decode(data, tree)
	dwrite("decode\n")
	local str = bstr.new(data)
	local function read_token(branch)
		local b = str:read(1)
		if not b then return end
		local next = branch[b+1]
		if next.dat then return next.dat end
		return read_token(next)
	end
	local buf = ""
	while true do
		local tok = read_token(tree)
		if not tok then break end
		if tok == STOP then
			break
		elseif tok == MATCH then -- pretty sure this is broken
			local info = str:read(16)
			local back = (info >> LEN_BITS)+1
			local len = info & (LEN_SIZE-1) + LEN_MIN
			local pos = #buf-back+1
			buf = buf .. buf:sub(pos, pos+len-1)
			dwrite(string.format("\27[32m<MATCH[s]:%d/-%d:%d>\27[0m", pos, back, len))
		elseif tok >= REP and tok <= REPMAX then
			local rc = read_token(tree)
			if not rc then error("unexpected eof") end
			if rc > 255 then error("invalid repeat token: "..rc) end
			local count = tok-REP+REP_MIN
			dwrite(string.format("\27[32m<REP[%d]:%d/%d>\27[0m", rc, count, tok-REP))
			buf = buf .. string.char(rc):rep(count)
		elseif tok > 255 then
			local pos_l = (tok >> 5) & 3
			local len = (tok & 31) + LEN_MIN
			local back = str:read((pos_l+1)*3)+1
			local pos = #buf-back+1
			dwrite(string.format("\27[32m<MATCH[%d:%d]:%d/-%d:%d>\27[0m", pos_l, len, pos, back, len))
			buf = buf .. buf:sub(pos, pos+len-1)
		else
			dwrite(string.char(tok))
			buf = buf .. string.char(tok)
		end
	end
	return buf
end

return huff