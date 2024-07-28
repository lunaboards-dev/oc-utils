local component = component
local computer = computer
local dev = component.proxy(computer.getBootAddress())
local hdr = "HHHHHHHHHHHHH"
local osdi_ent = "<IIc8I3c13"
local oinvoke, oproxy, olist = component.invoke, component.proxy, component.list

local function get_osdi()
	local ents, s0, off, ent = {}, dev.readSector(1), 1
	while off < #s0 do
		ent = {}
		ent.start, ent.size, ent.type, ent.flags, ent.name, off = osdi_ent:unpack(s0, off)
		ent.valid = ent.type ~= string.rep("\0", 8)
		table.insert(ents, ent)
	end
	local hdr = table.remove(ents, 1)
	if hdr.type ~= "OSDI\xAA\xAA\x55\x55" or hdr.start ~= 1 then return nil end
	return ents
end

local function get_mtpt()
	local last = dev.getCapacity()//dev.getSectorSize()
	local ents, slast, off, ent = {}, dev.readSector(last), 1
	while off < #slast do
		ent = {}
		ent.name, ent.type, ent.start, ent.size, off = mtpt_ent:unpack(slast, off)
		ent.valid = ent.name ~= string.rep("\0", 20)
		table.insert(ents, ent)
	end
	local hdr = table.remove(ents, 1)
	if hdr.type ~= "mtpt" then return nil end
	return ents
end

local parts = get_osdi() or get_mtpt() or error("no partitions table")

local part
for i=1, #parts do
	if parts[i].type == "btpt" or parts[i].type == "bootpart" then
		part = parts[i]
		break
	end
end

local offset = part.start

local buffer = dev.readSector(offset)
local buffer_pos = 0
local pos = 0

local sz = dev.getSectorSize()

local function get_blk(pos)
	local blk = pos // sz
	local bpos = pos % sz + 1
	return blk, bpos
end

local function buffer_blk(blk)
	buffer = dev.readSector(blk+offset)
	buffer_pos = blk*sz
end

local function read(amt)
	if pos + amt > buffer_pos + #buffer then
		local blkid = get_blk(buffer_pos+#buffer)
		buffer = buffer .. dev.readSector(blkid+offset)
		return read(amt)
	end
	local dp = pos - buffer_pos + 1
	local dat = buffer:sub(dp, dp+amt-1)
	pos = pos + amt
	local pblk = get_blk(pos)
	if pblk ~= get_blk(buffer_pos) then
		buffer_blk(pblk)
	end
	return dat
end

local function seek(amt)
	pos = pos + (amt or 0)
	local pblk = get_blk(pos)
	if pblk ~= get_blk(buffer_pos) then
		buffer_blk(pblk)
	end
	return pos
end

local magic = tonumber("070707", 8)
local p_file = tonumber("0664", 8)
local p_exec = tonumber("0775", 8)

local function read_entry()
	local head = read(hdr:packsize())
	local en
	if string.unpack("<H", head) == magic then
		en = "<"
	elseif string.unpack(">H", head) == magic then
		en = ">"
	else
		error("bad file")
	end
	local ent = {}
	ent.magic, ent.dev, ent.ino, ent.mode, ent.uid, ent.gid, ent.nlink,
		ent.rdev, ent.mtime_hi, ent.mtime_lo, ent.namesize, ent.fsize_hi,
		ent.fsize_lo = string.unpack(en..hdr, head)
	ent.name = assert(read(ent.namesize)):sub(1, ent.namesize - 1)
	ent.fsize = (ent.fsize_hi << 16) | ent.fsize_lo
	ent.mtime = (ent.mtime_hi << 16) | ent.mtime_lo
	if ent.namesize & 1 > 0 then
		seek(1)
	end
	return ent
end

-- Load file table
local files = setmetatable({}, {__index = function(t, k)
	if k:sub(1,1) == "/" then
		return rawget(t, k:sub(2))
	end
end})
while true do
	local fpos = seek(0)
	local ent = read_entry()
	if ent.name == "TRAILER!!!" then break end
	local ftype = ent.mode & 0xF000
	if ftype == 0x4000 or ftype == 0x8000 then
		files[ent.name] = {
			dir = ftype == 0x4000,
			size = ent.fsize,
			mod = ent.mtime,
			fpos = fpos,
			fstart = seek(0)
		}
	end
	seek(ent.fsize)
	if ent.fsize & 1 > 0 then
		seek(1)
	end
end

local proxy = {}

local function normalize_path(p)
	return (p:gsub("^/", ""):gsub("/$", ""):gsub("/+", "/"))
end

function proxy.getLabel()
	local n = part.name:gsub("\0+$","")
	if n == "" then return end
	return n
end

function proxy.setLabel()end

function proxy.isReadOnly()
	return true
end

function proxy.exists(path)
	path = normalize_path(path)
	return not not files[path]
end

function proxy.isDirectory(path)
	path = normalize_path(path)
	return files[path] and files[path].dir
end

function proxy.list(path)
	path = normalize_path(path)
	if path == "" then
		local res = {}
		for k, v in pairs(files) do
			if not k:find("/") then table.insert(res, k..(v.dir and "/" or "")) end
		end
		return res
	end
	if path:sub(#path, #path) ~= "/" then
		path = path .. "/"
	end
	local results = {}
	for k, v in pairs(files) do
		if k:sub(1, #path) == path then
			--oinvoke(component.list("ocelot")(), "log", string.format("path part: (%s)%s %d %q", path, k:sub(#path+1), k:find("/", #path+1) or -42069, (k:sub(1, #path) == path) and (not k:find("/", #path+1))))
		end
		if (k:sub(1, #path) == path) and (not k:find("/", #path+1)) then
			local fname = k:sub(#path+1)
			if v.dir then
				fname = fname .. "/"
			end
			table.insert(results, fname)
		end
	end
	return results
end

function proxy.spaceTotal()
	return part.size*sz
end

function proxy.spaceUsed()
	return part.size*sz
end

function proxy.lastModified(path)
	path = normalize_path(path)
	return files[path] and files[path].mod
end

function proxy.size(path)
	path = normalize_path(path)
	return files[path] and files[path].size
end

local function ro()return nil,"read only"end

proxy.makeDirectory = ro
proxy.remove = ro
proxy.rename = ro
proxy.write = ro

function proxy.open(path, mode)
	path = normalize_path(path)
	if mode ~= "r" and mode ~= "rb" and mode then return nil, "read only" end
	local f = files[path]
	if not f then return nil, path..": not found" end
	local h = {
		f = f,
		spos = f.fstart,
		pos = 0
	}
	return h
end

function proxy.seek(h, whence, where)
	if h.closed then return nil, "closed" end
	if whence == "set" then
		h.pos = where
	elseif whence == "cur" then
		h.pos = h.pos + where
	elseif whence == "end" then
		h.pos = h.f.size + where
	end
	return h.pos
end

function proxy.read(h, amt)
	if h.closed then return nil, "closed" end
	if h.pos > h.f.size or h.pos < 0 then return nil end
	seek((h.spos+h.pos)-seek())
	local ramt = amt
	if h.pos + amt > h.f.size then ramt = h.f.size - h.pos end
	h.pos = math.min(h.pos + amt, h.f.size+1)
	return read(ramt)
end

function proxy.close(h)
	h.closed = true
end

local addr = "cpio-"..dev.address

function component.invoke(caddr, method, ...)
	if addr == caddr then
		
		return proxy[method](...)
	end
	return oinvoke(caddr, method, ...)
end

function component.proxy(caddr)
	if addr == caddr then
		return setmetatable({}, {__index=proxy})
	end
	return oproxy(caddr)
end

function computer.getBootAddress()
	return addr
end

proxy.address = addr

function component.list(comp, exact)
	if comp == "filesystem" then
		local rtv = olist(comp)
		rtv[addr] = "filesystem"
		local call = pairs(rtv)
		return setmetatable(rtv, {__call=call})
	end
	return olist(comp, exact)
end

local init = files["init.lua"]
if not init then error("no init.lua") end
seek((init.fstart)-seek())
local code = read(init.size)
local e

xpcall(function()
	assert(load(code, "=init.lua"))()
end, function(err)
	--oinvoke(component.list("ocelot")(), "log", debug.traceback(err))
	e = err
end)
--while true do computer.pullSignal() end
if e then error(e) end