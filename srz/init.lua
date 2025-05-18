--local lzss = require("srz.lzss")
local xxh = require("srz.xxh32")
local huff = require("srz.lzssh")--require("srz.huffman")

local srz = {}

--local blk_hdr = "IIIHc2"
local blk_hdr = "IIH"
srz.blk_hdr = blk_hdr

function srz.compress_block(dat)
	local zdat, tree = huff.encode(dat)
	local cnk = blk_hdr:pack(#dat, #zdat, #tree)..tree..zdat
	local hash = xxh.sum(cnk)
	return cnk..string.pack("I", hash)
end

function srz.decompress_block(dat)
	local hash = string.unpack("I", dat, #dat-3)
	local chash = xxh.sum(dat:sub(1, #dat-4))
	if hash ~= chash then return nil, string.format("checksum failed (expected %.8x, calculated %.8x)", hash, chash) end
	local oriz, dskz, treez, offset = blk_hdr:unpack(dat)
	local _tree = dat:sub(offset, offset+treez-1)
	local zdat = dat:sub(offset+treez, #dat-5)
	local tree = huff.loadtree(_tree)
	local rdat = huff.decode(zdat, tree)
	if #rdat ~= oriz then return nil, string.format("size mismatch (header: %d ~= actual: %d)", oriz, #rdat) end
	return rdat
end

function srz.compress_stream(handle, blksize)

end

function srz.decompress_stream()

end

return srz