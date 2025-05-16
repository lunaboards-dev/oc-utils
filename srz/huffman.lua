local bstr = require("srz.bstr")
-- I'll be quite honest, i haven't got a fucking clue what i'm doing
local huff = {}

local STOP = 256
local MATCH = 257

local function build_freq(str)
	local fr = {
		[STOP] = 1,

	}
	for i=1, #str do
		local b = str:byte(i)
		fr[b] = (fr[b] or 0) + 1
	end
	local frlist = {}
	for k, v in pairs(fr) do
		table.insert(frlist, {v, k})
	end
	table.sort(frlist, function(a, b)
		return a[1] < b[1]
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
		--table.insert(queue, {
		pq_insert(queue, {
			freq = left.freq + right.freq,
			left = left,
			right = right
		})
	end
	local tree = queue[1]
	local lookup = {}
	local stree = bstr.new()
	local function preorder(root, cur, len)
		if not root.left and not root.right then
			lookup[root.dat] = {cur, len, root.freq}
			stree:write(1, 1)
			stree:write(root.dat, 7)
			return
		end
		stree:write(0, 1)
		preorder(root.left, cur << 1, len + 1)
		preorder(root.right, 1 | (cur << 1), len + 1)
	end
	preorder(tree, 0, 0)
	return lookup, tree, stree:finalize()
end

function huff.encode(str)
	local freq, flist = build_freq(str)
	-- Build huffman tree
	local lookup, tree, stree = build_tree(freq)
	--io.stderr:write(string.format("serialized tree size: %d (theoretical is %d)\n", #stree, 10*#flist//8))
	--[[for i=1, #freq do
		--io.stderr:write(tostring(freq[i][2]), "\t", freq[i][1], "\n")
		local fent = freq[i]
		local char, freq = fent[2], fent[1]
		io.stderr:write(string.format("%s\t%d\t%d\t%d\n", char, lookup[char][1], lookup[char][2] or -1, freq))
	end]]
	local res = bstr.new()
	for i=1, #str do
		local r = lookup[str:byte(i)]
		res:write(r[1], r[2])
	end
	res:write(lookup[STOP][1], lookup[STOP][2])
	return res:finalize(), stree
end

return huff