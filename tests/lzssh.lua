local xxh = require("srz.xxh32")
local lzssh = require("srz.lzssh")
local srz = require("srz")

local input = io.stdin:read("*a")
local ihash = xxh.sum(input)
local comp, stree = lzssh.encode(input, "lzss-custom")
--local decomp = lzssh.decode(comp)
local bstr = {}
local f = io.open("/tmp/treetest.bin", "w")
f:write(stree)
f:close()
print("=============================")
local st = require("srz.bstr").new(stree)
local special = {
	[256] = "STOP",
	[257] = "MATCH"
}
--[[while true do
	local t = st:read(1)
	if not t then break end
	if t == 1 then
		local tok = st:read(9)
		print(1, special[tok] or ("`"..string.char(tok).."`"))
	else
		print(0)
	end
end]]
print("=============================")
local tree = lzssh.loadtree(stree)
local dec = lzssh.decode(comp, tree)
local dhash = xxh.sum(dec)

print(ihash, dhash)
if ihash ~= dhash then
	print(input)
	print("====================================")
	print(dec)
	print("FAIL")
end
print("=============================")
print("container test")
print("=============================")
local zblk = srz.compress_block(input)
local uzblk = assert(srz.decompress_block(zblk))
local uzhash = xxh.sum(uzblk)
print(ihash, uzhash)
if ihash ~= uzhash then
	print(input)
	print("====================================")
	print(dec)
	print("FAIL")
end