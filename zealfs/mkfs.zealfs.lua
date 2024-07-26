local libpart = require("libpart")
local zealfs = require("libzealfs")
local shell = require("shell")

local args, opts = shell.parse(...)

local disk = libpart.proxy(args[1])
local pages = disk.getCapacity()//256

print("mkfs.zealfs (version 0.1)\n")

local blksize = disk.getSectorSize()

for i=0, 15 do
	if blksize == (1 << i) then
		goto ok
	end
end
io.stderr:write("Block size is not a power of two! ("..blksize..")\n")
os.exit(1)
::ok::

local zdisk = zealfs.block_proxy(disk)

local id = opts.id
if id then
	local id_hi, id_lo = id:match("(%x%x%x%x)-(%x%x%x%x)")
	id = {tonumber(id_hi, 16), tonumber(id_lo, 16)}
else
	id = {math.random(0xFFFF), math.random(0xFFFF)}
end

if not opts.f and pages > 256 then
	io.stderr:write(string.format("Page count is over 256! (%d)\n", pages))
	io.stderr:write("If you meant to do this, pass -f\n")
	os.exit(1)
end

pages = math.min(pages, 256)

local header = {
	magic = zealfs.magic,
	version = 1,
	bitmap_size = pages / 8,
	free_pages = pages - 1,
	pages_bitmap = "\1",
	id_hi = id[1],
	id_lo = id[2],
	resv0 = "",
}

print("Device: "..args[1])
print(string.format("ID: %.4X:%.4X", id[1], id[2]))
print(string.format("%d pages.", pages))

zdisk.writeSector(1, zealfs.header(header))