local dev = component.proxy(computer.getBootAddress())

local function log(s, ...)
	if ziptie and ziptie.log then
		ziptie.log(string.format(s, ...))
	end
end

local function panic(s, ...)
	if ziptie then
		log("PANIC: "..s, ...)
		for line in debug.traceback():gmatch("[^\n]+") do
			log(line:gsub("\t", "  "))
		end
		while true do computer.pullSignal() end
	else
		error(string.format(s, ...))
	end
end

local header = "<BBBBc32HHc24"
local entry = "<Bc16BHc8c4"

local offset
local function read_page_raw_smaller(page)
	local page_0 = page
	local phys = 256/dev.getSectorSize()
	local sec = page_0*(phys)+1
	local out = ""
	for i=1, phys do
		out = out .. dev.readSector(sec+offset+i-2)
	end
	return out
end

local function read_page_raw_larger(page)
	local page_0 = page
	local log = dev.getSectorSize()/256
	local pos = (page_0//log)+1
	local off = ((page_0%log)*256)+1
	local dat = dev.readSector(pos+offset-1)
	return dat:sub(off, off+255)
end

local read_page_raw
if dev.getSectorSize() > 256 then
	read_page_raw = read_page_raw_larger
elseif dev.getSectorSize() < 256 then
	read_page_raw = read_page_raw_smaller
else
	read_page_raw = dev.readSector
end

local function read_page(page)
	local dat = read_page_raw(page)
	if page == 0 then
		return dat:sub(header:packsize()+1)
	end
	return dat
end

local function read_dirents(page)
	local dat = read_page(page)
	local ents, off, ent = {}, 1
	while off < #dat do
		ent = {}
		ent.flags, ent.name, ent.start_page, ent.size, ent.date, _, off = entry:unpack(dat, off)
		table.insert(ents, ent)
	end
	return ents
end

local flag_occupied = 0x80
local flag_dir = 1
local function bit_test(a, b, c)
	return a & b == (c or b)
end

local function get_file(path, ignore_case)
	local page, last_ent = 0
	for part in path:gmatch("[^/]+") do
		if last_ent and not bit_test(last_ent.flags, flag_dir) then return nil, "not found" end
		local ents = read_dirents(page)
		if ignore_case then part = part:lower() end
		for i=1, #ents do
			local e = ents[i]
			local name = e.name:gsub("\0+$", "")
			if ignore_case then name = name:lower() end
			if name == part and bit_test(e.flags, flag_occupied) then
				last_ent = e
				page = e.start_page
				goto found
			end
		end
		do return nil, "not found" end
		::found::
	end
	if bit_test(last_ent.flags, flag_dir) then return nil, "not a file" end
	local res = {}
	while page ~= 0 do
		local pd = read_page(page)
		table.insert(res, pd:sub(2))
		page = pd:byte()
	end
	return table.concat(res):sub(1, last_ent.size)
end

local osdi_ent, mtpt_ent = "<IIc8I3c13", ">c20c4II"

local function get_osdi()
	--log("trying osdi...")
	local ents, s0, off, ent = {}, dev.readSector(1), 1
	while off < #s0 do
		ent = {}
		ent.start, ent.size, ent.type, ent.flags, ent.name, off = osdi_ent:unpack(s0, off)
		ent.valid = ent.type ~= string.rep("\0", 8)
		table.insert(ents, ent)
	end
	local hdr = table.remove(ents, 1)
	if hdr.type ~= "OSDI\xAA\xAA\x55\x55" or hdr.start ~= 1 then return nil end
	--log("found osdi")
	return ents
end

local function get_mtpt()
	--log("trying mtpt...")
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
	log("found mtpt")
	return ents
end
local bt
local function try_zealfs()
	local fshdr = {}
	local hdr = read_page_raw(0)
	fshdr.magic, fshdr.version, _, _, _, fshdr.id_hi, fshdr.id_lo = header:unpack(hdr)
	--log("see magic %.2x, version %d", fshdr.magic, fshdr.version)
	if fshdr.magic ~= string.byte("Z") or fshdr.version ~= 1 then
		--panic("not a zealfs partition")
		return nil
	end
	return fshdr
end

local function assert_die(v, s)
	if not v then
		panic("assertion failed: %s", s)
	end
	return v
end
xpcall(function()
	local parts = get_osdi() or get_mtpt()
	if not parts then
		panic("no known partition tables")
	end
	local valid_parts = {}
	for i=1, #parts do
		if parts[i].valid then
			table.insert(valid_parts, parts[i])
			local pname = parts[i].name:gsub("\0+$", "")
			parts[i].id = i
			if pname ~= "" then
				valid_parts[pname:lower()] = parts[i]
			end
			if parts[i].type == "bootpart" or parts[i].type == "blpt" then
				valid_parts[0] = parts[i]
			end
		end
	end
	local hdr
	if valid_parts[0] then
		--log("trying bootpart partition...")
		offset = valid_parts[0].start
		hdr = try_zealfs()
		if hdr then goto found end
	end
	if valid_parts.boot then
		--log("trying LABEL=boot...")
		offset = valid_parts.boot.start
		hdr = try_zealfs()
		if hdr then goto found end
	end
	for i=1, #valid_parts do
		--log("trying part %d...", valid_parts[i].id)
		offset = valid_parts[i].start
		hdr = try_zealfs()
		if hdr then goto found end
	end
	panic("could not found zealfs partition")
	::found::
	--log("found partition ID %.4X:%.4X", hdr.id_hi, hdr.id_lo)
	local function try_get_file(path, ignore_case)
		log("try load: %s", path)
		local f = get_file(path, ignore_case)
		if f then
			assert_die(load(f, "="..path))(get_file)
			panic("returned from bootloader!")
		end
	end

	try_get_file("init.lua", true)
	try_get_file("boot.lua", true)
	try_get_file("boot/init.lua", true)
	try_get_file("kernel.lua", true)
	try_get_file("boot/kernel.lua", true)
end, function(err)
	if ziptie then
		panic(err)
	else
		bt = err
	end
end)

if bt then error(bt) end
while true do computer.pullSignal() end