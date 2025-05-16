local shell = require("shell")
local srz = require("srz")

local function eprint(...)
	local strings = table.pack(...)
	for i=1, strings.n do
		strings[i] = tostring(strings[i])
	end
	io.stderr:write(table.concat(strings, "\t"), "\n")
end

local function panic(path, err)
	eprint(string.format("%s: %s", path, err))
	os.exit(1)
end

local function usage()
	eprint("Usage: srz <-dc> [-qk1..7 --out=PATH] [file]")
end

local args, opts = shell.parse(...)
if opts.h then
	usage()
	eprint("")
	eprint("\t   -d: Decompress")
	eprint("\t   -c: Compress")
	eprint("\t   -q: Quiet")
	eprint("\t   -k: Keep file")
	eprint("\t-1..7: Compression level (Default: 4)")
	eprint("\t--out: Output file")
	os.exit(0)
end

if not opts.d and not opts.c then
	usage()
	os.exit(1)
end

local lvl

for i=1, 7 do
	if opts[tostring(i)] then
		if lvl then
			eprint("Multiple compression levels are not allowed.")
			usage()
			os.exit(1)
		end
		lvl = i
	end
end

lvl = lvl or 4

local blksize = 1 << (lvl+13)

local file = opts[1]
local hand, err
if not file or file == "-" then
	hand = io.stdin
else
	hand, err = io.open(file, "r")
	if not hand then
		panic(file, err)
	end
end

local ohand
if args.out then
	ohand, err = io.open(args.out, "w")
	if not ohand then
		panic(args.out, err)
	end
else
	ohand = io.stdout
end

if opts.d then
	local magic = ohand:read(4)
	if magic ~= "srz\0" then
		panic(hand == io.stdin and "stdin" or file, "not compressed with srz")
	end
	while true do
		local hdr = ohand:read(srz.blk_hdr:packsize())
		if not hdr or #hdr < srz.blk_hdr:packsize() then break end
		local _, dskz, treez = srz.blk_hdr:unpack(hdr)
		local blkdat = ohand:read(dskz+treez+4)
		local dat = srz.decompress_block(hdr..blkdat)
		hand:write(dat)
		if not opts.q then io.stderr:write(".") end
	end
	ohand:close()
	hand:flush()
	hand:close()
else
	ohand:write("srz\0")
	while true do
		local blk = hand:read(blksize)
		if not blk then break end
		ohand:write(srz.compress_block(blk))
		if not opts.q then io.stderr:write(".") end
	end
	ohand:close()
	hand:flush()
	hand:close()
end

if not opts.k or hand ~= io.stdin then
	os.remove(file)
end