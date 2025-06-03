local lfs = require("lfs")
local parser = require("argparse")("sarc")

parser:mutex(
	parser:flag("--create -c", "Create archive"),
	parser:flag("--append -a", "Append to archive"),
	parser:flag("--extract-file -e"),
	parser:flag("--extract -x"),
	parser:flag("--list -l")
)
parser:flag("--verbose -v")

parser:argument("archive")

parser:argument("paths"):args("*")

local args = parser:parse()

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

if not args.create and not args.append and not args.extract_file and not args.extract and not args.list and not args.archive then
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
	local attr = lfs.attributes(path)
	write_header(f, "file", pathpart..fname, {
		size=attr.size,
		mtime=attr.modification
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
	for ent in lfs.dir(path) do
		if ent == "." or ent == ".." then goto continue end
		local npath = path.."/"..ent
		local ppart = pathpart..fname.."/"
		if lfs.attributes(npath, "mode") == "directory" then
			add_dir(f, npath, ppart)
		else
			add_file(f, npath, ppart)
		end
		::continue::
	end
end

local function read_header(f)
	local fl = f:read("*l")
	local ftype, path = fl:match("(%S+)\t(.+)")
	local l = f:read("*l")
	local stat = {}
	while l ~= "" do
		local k, v = l:match("([^:]+):(.+)")
		stat[k] = v
		l = f:read("*l")
	end
	stat.type = ftype
	stat.path = path
	return stat
end

local function write_files(ofi)
	for i=1, #args.paths do
		if lfs.attributes(args.paths[i], "mode") == "directory" then
			add_dir(ofi, args.paths[i], "")
		else
			add_file(ofi, args.paths[i], "")
		end
	end
	ofi:seek("cur", -1)
	ofi:write(".")
	ofi:close()
end

local function read_files(ifi, func)
	while true do
		local hdr = read_header(ifi)
		func(hdr)
		local nx = ifi:read(1)
		if nx ~= "\n" then
			break
		end
	end
end

local function check_header(file)
	local ln = file:read("*l")
	return ln == "sarc1.0"
end

if args.create then
	local ofi = io.open(args.archive, "wb")
	ofi:write("sarc1.0\n")
	write_files(ofi)
elseif args.list then
	local ifi = io.open(args.archive, "rb")
	if not check_header(ifi) then panic(args.archive, "not a sarc archive") end
	read_files(ifi, function(hdr)
		if hdr.type ~= "dir" then
			ifi:seek("cur", tonumber(hdr.size, 10))
		end
		if args.verbose then
			print(string.format("%4s\t%-10s\t%s", hdr.type, hdr.size or "n/a", hdr.path))
		else
			print(hdr.path)
		end
	end)
elseif args.append then
	local ofi = io.open(args.archive, "r+b")
	if not check_header(ofi) then panic(args.archive, "not a sarc archive") end
	ofi:seek("end", -1)
	ofi:write("\n")
	write_files()
elseif args.extract_file then
	if #args.paths ~= 1 then
		eprint("Single path required")
		os.exit(1)
	end
	local spath = args.paths[1]
	local ifi = io.open(args.archive, "rb")
	if not check_header(ifi) then panic(args.archive, "not a sarc archive") end
	read_files(ifi, function(hdr)
		--print(">"..hdr.path.."<", ">"..spath.."<")
		if hdr.path == spath then
			if hdr.type ~= "file" then
				panic(spath, "not a file")
			end
			local size = tonumber(hdr.size, 10)
			while size > 0 do
				local cnk = ifi:read(math.min(size, 4096))
				if not cnk then
					panic(args.archive, "unexpected eof")
				end
				size = size - #cnk
				io.stdout:write(cnk)
			end
			os.exit(0)
		else
			if hdr.size then
				local size = tonumber(hdr.size, 10)
				ifi:seek("cur", size)
			end
		end
	end)
	panic(spath, "not found")
elseif args.extract then
	local ifi = io.open(args.archive, "rb")
	if not check_header(ifi) then panic(args.archive, "not a sarc archive") end
	read_files(ifi, function(hdr)
		
	end)
end