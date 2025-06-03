-- Reads/writes archive files
local args, opts = require("shell").parse(...)
local fs = require("filesystem")
local formats = require("archive.formats")

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
	eprint("Usage: archive <-caexlh> [-v --format=<format>] <archive> [paths...]")
	if opts.h then
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
		eprint("  --format: Specify format. Default is assumed from header or file extension.")
		os.exit(0)
		local flist = {}
		for k, v in pairs(formats.list) do
			table.insert(flist, k)
		end
		table.sort(flist)
		eprint("Formats:")
		for i=1, #flist do
			local fstr = flist[i]
			local ext = formats.list[flist[i]].ext
			if ext then
				fstr = fstr .. " (."..ext..")"
			end
			eprint("  "..fstr)
		end
	end
end

if args.h then
	usage()
	os.exit(0)
end

if not args[1] then
	usage()
	os.exit(1)
end

local function write_files(f, arc)

end

if opts.c then

end