local shell = require("shell")
local fs = require("filesystem")

local magic = tonumber("070707", 8)
local p_file = tonumber("0664", 8)
local p_exec = tonumber("0775", 8)
local chunk_size = 2048
local hdr = "HHHHHHHHHHHHH"


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
	eprint("Usage: cpio <-oith> [-dv --format=<bin|newc> --<F/file>=path] [paths...]")
end

local args, opts = shell.parse(...)
if opts.h then
	usage()
	os.exit(0)
end
if not (opts.o or opts.i or opts.t) then
	usage()
	os.exit(1)
end
local file, err = opts.o and io.stdout or io.stdin
if opts.F or opts.file then
	file, err = io.open(opts.F or opts.file, opts.o and "wb" or "rb")
	if not file then eprint(string.format("%s: %s", opts.F or opts.file, err)) os.exit(1) end
end

local function matches_paths(path)
	for i=1, #args do
		local pat = args[i]
		local ret = true
		if pat:sub(1,1) == ":" then
			pat = pat:sub(2)
			ret = false
		end
		if path:match(pat) then
			return ret
		end
	end
end

local bytes = 0

local function skip(amt)
	bytes = bytes + amt
	if opts.F then
		file:seek("cur", amt)
	else
		while amt > 0 do
			local s = assert(file:read((amt > chunk_size) and chunk_size or amt))
			amt = amt - #s
		end
	end
end

local function nextc(bytes)
	return assert(file:read(bytes))
end

local function next_file()
	bytes = bytes + 2
	local buffer = assert(file:read(2))
	local en = "<"
	while buffer and #buffer == 2 do
		if string.unpack("<H", buffer) then
			goto found
		elseif string.unpack(">H", buffer) then
			en = ">"
			goto found
		end
		buffer = buffer:sub(2) .. assert(file:read(1))
		bytes = bytes + 1
	end
	eprint("panic: unexpected EOF")
	os.exit(1)
	::found::
	local hdrsize = hdr:packsize()-2
	local head = buffer .. assert(file:read(hdrsize))
	bytes = bytes + hdrsize
	local ent = {}
	ent.magic, ent.dev, ent.ino, ent.mode, ent.uid, ent.gid, ent.nlink,
		ent.rdev, ent.mtime_hi, ent.mtime_lo, ent.namesize, ent.fsize_hi,
		ent.fsize_lo = string.unpack(en..hdr, head)
	ent.name = assert(file:read(ent.namesize)):sub(1, ent.namesize - 1)
	ent.fsize = (ent.fsize_hi << 16) | ent.fsize_lo
	ent.mtime = (ent.mtime_hi << 16) | ent.mtime_lo
	if ent.namesize & 1 > 0 then
		skip(1)
	end
	bytes = bytes + ent.namesize
	if ent.name == "TRAILER!!!" then return end
	return ent
end

local function skamt(n, max)
	local sk = n % max
	if sk == 0 then return 0 end
	return max - sk
end

local function readhex(n)
	return tonumber(nextc(n), 16)
end

local function tohex(n, v)
	return string.format("%."..v.."X", n)
end

local function next_file_newc()
	local sig = nextc(6)
	if sig ~= "070701" then error("unexpected EOF") end
	local ent = {
		ino = readhex(8),
		mode = readhex(8),
		uid = readhex(8),
		gid = readhex(8),
		nlink = readhex(8),
		mtime = readhex(8),
		fsize = readhex(8),
		dmaj = readhex(8),
		dmin = readhex(8),
		rdmaj = readhex(8),
		rdmin = readhex(8),
		namesize = readhex(8),
		csum = readhex(8),
	}
	ent.name = nextc(ent.namesize):sub(1, ent.namesize-1)
	skip(skamt(ent.namesize, 4))
	if ent.name == "TRAILER!!!" then return end
	return ent
end

local x0 = "00000000"

local real_next_file = (opts.foramt == "newc") and next_file_newc or next_file

local pwd = shell.getWorkingDirectory()
if opts.o then
	local function write(data)
		if opts.format == "newc" then
			data = data .. string.rep("\0", skamt(#data, 4))
		else
			if #data & 1 > 0 then
				data = data .. "\0"
			end
		end
		file:write(data)
		bytes = bytes + #data
	end
	local inode = 0
	local function write_stat(mode, size, mtime, nlink, name)
		if opts.format == "newc" then
			write(
				"070701".. -- magic
				tohex(inode).. -- inode
				tohex(mode).. -- mode
				x0.. -- uid
				x0.. -- gid
				tohex(nlink).. -- nlinks
				tohex(mtime).. -- mtime
				tohex(size).. -- fsize
				x0.. -- dev major
				x0.. -- dev minor
				x0.. -- rdev major
				x0.. -- rdev minor
				tohex(#name+1).. -- name size
				x0.. -- checksum
				name.."\0" -- name + null terminator
			)
		else
			write(string.pack(hdr, magic, 0, inode, mode, 0, 0, nlink, 0, (mtime >> 16) & 0xFFFF, mtime & 0xFFFF, #name+1, size >> 16, size & 0xFFFF)..name.."\0")
		end
		inode = inode + 1
	end
	for line in io.stdin:lines() do
		local rpath = line
		if line:sub(1,1) ~= "/" then
			rpath = fs.concat(pwd, line)
		end
		rpath = "/"..fs.canonical(rpath)
		local size = fs.size(rpath)
		local mtime = fs.lastModified(rpath)
		local dir = fs.isDirectory(rpath)
		local nlink = ((dir and rpath == "/") and 2) or (dir and 2) or 1
		local mode = (dir and 0x4000 or 0x8000) | ((dir or line:sub(#line-3) == ".lua") and p_exec or p_file)
		write_stat(mode, dir and 0 or size, mtime, nlink, line)
		if not dir then
			local h, err = io.open(rpath, "rb")
			if not h then panic(line, err) end
			local last = ""
			repeat
				last = h:read(chunk_size)
				if last then
					write(last)
				end
			until not last or #last ~= chunk_size
			h:close()
		end
		if opts.v then eprint(line) end
	end
	write_stat(0, 0, 0, 0, "TRAILER!!!")
	if opts.F then
		file:close()
	end
elseif opts.t then
	for ent in real_next_file do
		if opts.v then
			local rwx = "xwr"
			local mode = ""
			for i=0, 8 do
				mode = ((ent.mode & (1 << i) > 0) and rwx:sub(i % 3 + 1, i % 3 + 1) or "-") .. mode
			end
			mode = (ent.mode >> 12 == 4 and "d" or "-") .. mode
			print(string.format("%s %9d %s %s", mode, ent.fsize, os.date("%b %d %H:%M"), ent.name))
		else
			print(ent.name)
		end
		if opts.format == "newc" then
			skip(skamt(ent.fsize, 4))
		else
			skip(ent.fsize + (ent.fsize & 1))
		end
	end
elseif opts.i then
	for ent in real_next_file do
		do
			local dir = ent.mode >> 12 == 4
			local path = fs.path(ent.name)
			if opts.d and not dir then
				fs.makeDirectory(fs.concat(pwd, fs.canonical(path)))
			elseif opts.d then
				fs.makeDirectory(fs.concat(pwd, fs.canonical(ent.name)))
				goto continue
			elseif dir then
				goto continue
			end
			local fd = io.open(ent.name, "wb")
			if not fd then
				if opts.format == "newc" then
					skip(skamt(ent.fsize, 4))
				else
					skip(ent.fsize + (ent.fsize & 1))
				end
				goto continue
			end
			local amt = ent.fsize
			bytes = bytes + amt
			while amt > 0 do
				local sz = (amt < chunk_size) and amt or chunk_size
				local last = assert(file:read(sz))
				if #last ~= sz then
					eprint("unexpected eof")
					os.exit(1)
				end
				fd:write(last)
				amt = amt - #last
			end
			fd:close()
			if opts.format == "newc" then
				skip(skamt(ent.fsize, 4))
			else
				if ent.fsize & 1 > 0 then
					skip(1)
				end
			end
		end
		::continue::
		if (opts.v) then
			print(ent.name)
		end
	end
end

eprint(string.format("%d blocks.", math.ceil(bytes/512)))