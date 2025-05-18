local srz = require("srz")

local ipt = io.stdin:read("*a")

--[[local blk1, eblk = srz.compress_block(ipt, "custom")
local blk2 = srz.compress_block(ipt, "custom-std")
local blk3 = srz.compress_block(ipt, "lzss")]]
local zblk = require("srz._lzss").compress(ipt)
--local lzblk, tree = require("srz.lzssh").fast_compress(ipt)

--io.stderr:write("raw: ", #ipt, "\tcompressed block: ", #blk, "\tlzss.compress (ref): ", #zblk, "\tonly lzss: ", #lzblk, "\n")
local function eprint(pat, ...)
	io.stderr:write(string.format(pat, ...), "\n")
end

local sizes = {
	["lzss.compress"] = #zblk
}

local ratios = {
	["lzss.compress"] = (#zblk/#ipt)
}

local blks = {}

local impl = {
	--"custom",
	--"custom-std",
	--"lzss",
	"lzss-custom"
}

for i=1, #impl do
	local m = impl[i]
	eprint(":: srz<%s>", m)
	local blk = srz.compress_block(ipt, m)
	local size = #blk
	local ratio = size/#ipt
	sizes[m] = size
	ratios[m] = ratio
	blks[m] = blk
end

eprint("raw: %d", #ipt)
eprint("lzss.compress (ref): %d (%.1f%%)", #zblk, ratios["lzss.compress"]*100)

for i=1, #impl do
	local m = impl[i]
	eprint("srz<%s>: %d (%.1f%%)", m, sizes[m], ratios[m]*100)
end

--require("srz.huffman").encode(eblk)

io.stdout:write(blks["lzss-custom"])