local fs = require("filesystem")
local args, opts = require("shell").parse(...)

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
	eprint("Usage: sarc <-caexlh> [-vV] <archive> [paths...]")
end

if args.h then
	usage()
	eprint("")
	eprint("Main modes:")
	eprint("  -c: Create archive")
	eprint("  -a: Append to archive")
	eprint("  -e: Extract single files")
	eprint("  -x: Extract entire archive")
	eprint("  -l: List archive contents")
	eprint("Options:")
	eprint("  -v: Verbose output")
	eprint("  -V: Verify (read) or write hashes (write). Requires xxh64 to be installed.")
	os.exit(0)
end

if not args.c or args.a or args.e or args.x or args.l or #args < 1 then
	usage()
	os.exit(1)
end

local function write_header(f, ftype, fname, hdr)
	f:write(string.format("%s\t%s\n", ftype, fname))
	for k, v in pairs(hdr) do
		f:write(string.format("%s:%s\n", k, tostring(v)))
	end
	f:write("\n")
end
local function add_file(f, path, pathpart)
	local fname = path:match("[^/]+$")
	write_header(f, "file", pathpart..fname, {
		size=fs.size(path),
		mtime=fs.lastModified
	})
	local h = io.open(path, "rb")
	while true do
		local c = h:read(4096)
		if not c or c == "" then
			break
		end
		f:write(c)
	end
	h:close()
	f:write("\n")
end

local function add_dir(f, path, pathpart)
	local fname = path:match("[^/]+$")
	write_header(f, "dir", pathpart..fname, {})
	f:write("\n")
	for ent in fs.list(path) do
		local npath = path.."/"..ent
		local ppart = pathpart..fname.."/"
		if fs.isDirectory(npath) then
			add_dir(f, npath, ppart)
		else
			add_file(f, npath, pathpart)
		end
	end
end

if args.c then
	local ofi = io.open(args[1], "wb")
	for i=2, #args do
		if fs.isDirectory(args[i]) then
			add_dir(ofi, args[i], "")
		else
			add_file(ofi, args[i], "")
		end
	end
	ofi:seek("cur", -1)
	ofi:write(".")
	ofi:close()
end