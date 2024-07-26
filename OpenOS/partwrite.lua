local libpart = require("libpart")
local shell = require("shell")

local args = table.pack(...)
if args.n ~= 2 then
	io.stderr:write("Usage: partwrite <device> <file>\n")
	os.exit(1)
end

local dev = assert(libpart.proxy(args[1]))
local f = assert(io.open(args[2], "rb"))

local bs = dev.getSectorSize()
local cap_sec = dev.getCapacity()//bs


local function pad(block)
    return block .. string.rep("\0", bs-#block)
end

io.stdout:write("Writing sectors (0/"..cap_sec..")")
for i=1, cap_sec do
	local dat = f:read(bs)
	dev.writeSector(i, pad(dat or ""))
	io.stdout:write("\rWriting sectors ("..i.."/"..cap_sec..")")
end

f:close()
print("\nWrite complete.")