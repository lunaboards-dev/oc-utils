local zealfs = require("libzealfs")
local libpart = require("libpart")

local args = {...}

if #args ~= 2 then
	io.stderr:write("Usage: mount.ocfs <device> <mountpoint>\n")
	os.exit(1)
end

local dev = libpart.proxy(args[1])

local blksize = dev.getSectorSize()

for i=0, 15 do
	if blksize == (1 << i) then
		goto ok
	end
end
io.stderr:write("Block size is not a power of two! ("..blksize..")\n")
os.exit(1)
::ok::

local disk = zealfs.block_proxy(dev)
local page0 = disk.readSector(1)
local header = zealfs.header(page0)
if header.magic ~= zealfs.magic or header.version ~= 1 then
	io.stderr:write("Not a ZealFS partiton!\n")
	os.exit(1)
end

local root_dir = page0:sub(#zealfs.header+1)

local function save_sb()
	disk.writeSector(1, zealfs.header(header)..root_dir)
end

local _debug
local function dprint(...)
	if _debug then print(...) end
end

local function write_page(n, data)
	dprint("WRITE", n, #data)
	if n == 0 then
		root_dir = data
		save_sb()
		return
	end
	disk.writeSector(n+1, data)
end

local function read_page(n)
	--dprint("READ", n)
	local dat = disk.readSector(n+1)
	if n == 0 then
		return dat:sub(#zealfs.header+1)
	end
	return dat
end


local function test_used_pages()
	local used = 0
	for i=1, #header.pages_bitmap do
		for j=0, 7 do
			if header.pages_bitmap:byte(i) & (1 << j) > 0 then
				used = used + 1
			end
		end
	end
	return used
end

local function space_total()
	return math.min(disk.getCapacity(), header.bitmap_size*8*256)
end

local function space_free()
	return header.free_pages*256
end

local function first_free()
	for i=1, header.bitmap_size do
		local byte = header.pages_bitmap:byte(i)
		for j=0, 7 do
			if byte & (1 << j) == 0 then
				return ((i-1)*8)+j
			end
		end
	end
end

local function bit_test(a, b, c)
	return a & b == (c or b)
end

local function alloc_check(n)
	local n0 = n
	local byte, bit = (n0 // 8)+1, (n0 % 8)
	local v = header.pages_bitmap:byte(byte)
	--print("CHECK", n, byte, bit, v)
	return bit_test(v, 1 << bit)
end

local function free_page(n)
	dprint("FREE", n)
	local n0 = n
	write_page(n, string.rep("\0", 256))
	local byte, bit = (n0 // 8)+1, (n0 % 8)
	local v, mask = header.pages_bitmap:byte(byte), (1 << bit) ~ 0xFF
	header.pages_bitmap = header.pages_bitmap:sub(1, byte-1)..string.char(v & mask)..header.pages_bitmap:sub(byte+1)
	if bit_test(v, 1 << bit) then
		header.free_pages = header.free_pages + 1
	end
end

local function alloc_page(n)
	dprint("ALLOC", n)
	local n0 = n
	local byte, bit = (n0 // 8)+1, (n0 % 8)
	local v = header.pages_bitmap:byte(byte)
	header.pages_bitmap = header.pages_bitmap:sub(1, byte-1)..string.char(v | (1 << bit))..header.pages_bitmap:sub(byte+1)
	if not bit_test(v, 1 << bit) then
		header.free_pages = header.free_pages - 1
	end
end

local function test_alloc(n, msg)
	if not alloc_check(n) then
		dprint("DEBUG", n, msg)
	end
end

local function read_dirents(n)
	test_alloc(n, "dirent read from unallocated page")
	local page = read_page(n)
	local ents = {}
	local off, dirent = 1
	while off < #page do
		dirent, off = zealfs.dirent(page, nil, off)
		table.insert(ents, dirent)
	end
	return ents
end

local function write_dirents(n, ents)
	test_alloc(n, "dirent write to unallocated page")
	local page = {}
	for i=1, #ents do
		page[i] = zealfs.dirent(ents[i])
	end
	write_page(n, table.concat(page))
end

local function check_path_part(s)
	if #s > 16 then
		error(string.format("path part '%s' too long (%d > 16)", s, #s))
	end
end

local proxy = {}

function proxy.spaceTotal()
	return space_total()
end

function proxy.spaceUsed()
	--return space_total()-space_free()
	return test_used_pages()*256
end

function proxy.isReadOnly()
	return disk.isReadOnly and disk.isReadOnly()
end

function proxy.getLabel()
	return disk.getLabel()
end

function proxy.setLabel(name)
	return disk.setLabel(name)
end

local function path_parts(path)
	local gm_iter = path:gmatch("[^/]+")
	return function()
		local p = gm_iter()
		if p then
			check_path_part(p)
		end
		return p
	end
end

local function walk_path(path, force)
	local part = path_parts(path)
	local page = 1
	local function next_page(p)
		page = p
	end
	local p = part()
	local forced
	return function()
		if not p and force and not forced then
			p = ""
			forced = true
		end
		if not page or not p then return end
		local ents = read_dirents(page)
		local _page = page
		page = nil
		local cpart = p
		p = part()
		return cpart, ents, next_page, _page, p
	end
end

local function trim_name(s)
	return s:gsub("\0+$", "")
end

-- acts like -p
--[[function proxy.makeDirectory(path)
	--[[local page = 1
	for part in path_parts(path) do
		local ents = read_dirents(page)] ]
	for part, ents, next_page, page in walk_path(path) do
		local free_ent
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.IS_DIR)then
				--page = e.start_page
				next_page(e.start_page)
				goto continue
			elseif not free_ent and e.flags & zealfs.flag_occupied == 0 then
				free_ent = i
			elseif name == part and bit_test(e.flags, zealfs.IS_DIR, zealfs.flag_occupied) then
				return nil, "not a directory"
			end
		end
		if not free_ent then
			error("no free entries")
		end
		local new_page = first_free()
		if not new_page then
			return nil, "no free space"
		end
		ents[free_ent] = {
			flags = zealfs.IS_DIR,
			name = part,
			start_page = new_page,
			size = 0x100,
			date = zealfs.to_bcddate(libpart.realtime()),
			resv0 = ""
		}
		alloc_page(new_page)
		write_dirents(page, ents)
		--page = next_page
		next_page(new_page)
		::continue::
	end
	save_sb()
end]]

function proxy.makeDirectory(path)
	local page = 0
	for part in path_parts(path) do
		local ents = read_dirents(page)
		local free_ent
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.IS_DIR) then
				page = e.start_page
				goto continue
			elseif not free_ent and not bit_test(e.flags, zealfs.flag_occupied) then
				free_ent = i
			elseif name == part and bit_test(e.flags, zealfs.IS_DIR, zealfs.flag_occupied) then
				return nil, "not a directory"
			end
		end
		if not free_ent then
			error("no free entries")
		end
		local new_page = first_free()
		if not new_page then
			return nil, "no free space"
		end
		ents[free_ent] = {
			flags = zealfs.IS_DIR,
			name = part,
			start_page = new_page,
			size = 0x100,
			date = zealfs.to_bcddate(libpart.realtime()),
			resv0 = ""
		}
		alloc_page(new_page)
		write_dirents(page, ents)
		page = new_page
		::continue::
	end
	save_sb()
	return true
end

--[[local function get_parent(path)
	local parent_end = path:find("[^/]+$")
	if not parent_end or parent_end == 1 then
		return "", 1, read_dirents(1)
	end
	local ppath = path:sub(1, parent_end-1)
	local _ents, _page, _ents
	for part, ents, next_page, page in walk_path(path) do
		for i=1, #ents do
			if trim_name(ents[i].name) == part & bit_test(ents[i].flags, zealfs.IS_DIR) then
				next_page(ents[i].start_page)
				break
			end
		end
	end
end]]

local function stat(path)
	local page = 0
	local last_ent
	for part in path_parts(path) do
		if last_ent and not bit_test(last_ent.flags, zealfs.IS_DIR) then
			return nil, "not a directory"
		end
		local ents = read_dirents(page)
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.flag_occupied) then
				last_ent = e
				page = e.start_page
				goto found
			end
		end
		do
			return nil, "not found"
		end
		::found::
	end
	return last_ent
end

function proxy.exists(path)
	local st = stat(path)
	return not not st
end

function proxy.list(path)
	--[[for part, ents, next_page, page, nextpart in walk_path(path) do
		if not nextpart then
			local names = {}
			for i=1, #ents do
				local e = ents[i]
				local name = trim_name(e.name)
				print(e.flags)
				if bit_test(e.flags, zealfs.flag_occupied) then
					if bit_test(e.flags, zealfs.flag_dir) then
						name = name .. "/"
					end
					table.insert(names, name)
				end
			end
			return names
		end
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(ents[i].flags, zealfs.IS_DIR) then
				next_page(e.start_page)
				break
			end
		end
	end
	return nil, "not found"]]
	local page = 0
	--local last_ent
	for part in path_parts(path) do
		local ents = read_dirents(page)
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.IS_DIR) then
				--last_ent = e
				page = e.start_page
				goto found
			end
		end
		do
			return nil, "not found"
		end
		::found::
	end
	local ents = read_dirents(page)
	local nlist = {}
	for i=1, #ents do
		local e = ents[i]
		if bit_test(e.flags, zealfs.flag_occupied) then
			local name = trim_name(e.name)
			if bit_test(e.flags, zealfs.IS_DIR) then
				name = name .. "/"
			end
			table.insert(nlist, name)
		end
	end
	return nlist
end

function proxy.isDirectory(path)
	local st = stat(path)
	if not st then return false end
	return bit_test(st.flags, zealfs.flag_dir)
end

function proxy.size(path)
	local st = stat(path)
	if not st then return end
	return st.size
end

function proxy.lastModified(path)
	local st = stat(path)
	if not st then return end
	return zealfs.from_bcddate(st.date)
end

-- i hate this
function proxy.remove(path)
	dprint("DEL", path)
	local function delete_node(page, dir)
		dprint("DEL_NODE", page, dir)
		local npage = read_page(page):byte()
		free_page(page)
		if dir then
			local ents = read_dirents(page)
			for i=1, #ents do
				if bit_test(ents[i].flags, zealfs.flag_occupied) then
					delete_node(ents[i].page, bit_test(ents[i].flags, zealfs.flag_dir))
				end
			end
		else
			dprint("NEXT_PAGE", npage)
			if npage ~= 0 then
				delete_node(npage)
			end
		end
	end

	local last_ent
	local last_ent_
	local last_page
	local page = 0
	for part in path_parts(path) do
		if last_ent_ and bit_test(last_ent_.flags, zealfs.IS_DIR) then
			return nil, "not found"
		end
		local ents = read_dirents(page)
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.flag_occupied) then
				last_page = page
				last_ent_ = e
				page = e.start_page
				last_ent = i
				goto found
			end
		end
		do
			return nil, "not found"
		end
		::found::
	end
	if not last_page then return false end
	local _ents = read_dirents(last_page)
	delete_node(page, bit_test(_ents[last_ent].flags, zealfs.IS_DIR))
	_ents[last_ent].flags = 0
	write_dirents(last_page, _ents)
	save_sb()
end

local handles = {}

local function read_around(h, size)
	local hand = handles[h]
	local pages = hand.pages
	local st_byte = hand.pos-1
	local start_page = (st_byte//255)+1
	local start_offset = (st_byte % 255)+1
	local end_byte = st_byte+size
	local end_page = (end_byte//255)+1
	local rtv = {}
	dprint("READ_AROUND", start_page, end_page, #pages)
	for i=start_page, end_page do
		if pages[i] then
			table.insert(rtv, read_page(pages[i]):sub(2))
		end
	end
	local dat = table.concat(rtv)
	return dat, start_offset, start_offset+size-1, start_page
end

local function raw_write(h, startpage, data)
	dprint("RAW_WRITE", h, startpage, #data)
	local hand = handles[h]
	local pages = hand.pages
	local offset = 1
	local i = startpage
	local len = #data
	while len-offset > 0 do
		--[[if not pages[i] then return nil, "out of storage" end
		dprint("SHOULD_NEW", len-offset)
		if len-offset > 255 and not pages[i+1] then
			local next_page = first_free()
			dprint("NEW_PAGE", next_page)
			if next_page then
				table.insert(pages, next_page)
			end
		end]]
		if not pages[i] then
			local next_page = first_free()
			if not next_page then
				return nil, "no free space"
			end
			pages[i] = next_page
			alloc_page(next_page)
			-- this is jank as fuck
			if pages[i-1] then
				write_page(pages[i-1], string.char(pages[i])..read_page(pages[i-1]):sub(2))
			end
		end
		write_page(pages[i], string.char(pages[i+1] or 0)..data:sub(offset, offset+254))
		--alloc_page(pages[i])
		i = i + 1
		offset = offset + 255
	end
	return true
end

local function get_pages(page)
	local _page = read_page(page)
	dprint("PAGE_INDEX", _page:byte())
	local pages = {}
	while _page:byte() ~= 0 do
		dprint("PAGE", page)
		table.insert(pages, page)
		page = _page:byte()
		_page = read_page(page)
		dprint("PAGE_INDEX", _page:byte())
	end
	dprint("PAGE", page)
	table.insert(pages, page)
	return pages
end

local function vhandle(parentpage, entry, mode)
	local ents = read_dirents(parentpage)
	local e = ents[entry]
	local h = {
		mode = mode,
		parent = parentpage,
		ent_id = entry,
		pos = 1,
		size = e.size,
		pages = get_pages(e.start_page)
	}
	local hi = #handles+1
	handles[hi] = h
	return h, hi
end

local function update_entry(page, ent, nvals)
	dprint("UPDATE", page, ent)
	local ents = read_dirents(page)
	local e = ents[ent]
	for k, v in pairs(nvals) do
		e[k] = v
	end
	write_dirents(page, ents)
end

function proxy.open(path, mode)
	dprint("OPEN", path, mode)
	local last_ent, free_ent
	local last_ent_, free_ent_
	local last_page, fname
	local page = 0
	local nfound
	for part in path_parts(path) do
		if (last_ent_ and bit_test(last_ent_.flags, zealfs.IS_DIR)) or free_ent then
			return nil, "not found"
		end
		local ents = read_dirents(page)
		nfound = true
		free_ent = nil
		free_ent_ = nil
		for i=1, #ents do
			local e = ents[i]
			local name = trim_name(e.name)
			if name == part and bit_test(e.flags, zealfs.flag_occupied) then
				last_page = page
				last_ent_ = e
				page = e.start_page
				last_ent = i
				nfound = false
				goto found
			elseif not free_ent and not bit_test(e.flags, zealfs.flag_occupied) then
				free_ent = i
				free_ent_ = e
				last_page = page
				fname = part
			end
		end
		::found::
	end
	if not last_page then return false end
	if last_ent and bit_test(last_ent_.flags, zealfs.IS_DIR) then return false, "not a file" end
	if nfound and not free_ent then return nil, "no free entries" end
	-- File must exist
	if mode == "r" or mode == "rb" then
		if nfound then return nil, "not found" end
		local h, hid = vhandle(last_page, last_ent, "r")
		h.pages = get_pages(last_ent_.start_page)
		return hid
	elseif mode == "w" or mode == "wb" then
		local ent = free_ent or last_ent
		if free_ent then
			local first_page = first_free()
			if not first_page then return nil, "no free pages" end
			alloc_page(first_page)
			update_entry(last_page, free_ent, {
				flags = zealfs.flag_occupied,
				start_page = first_page,
				date = zealfs.to_bcddate(libpart.realtime()),
				name = fname
			})
			save_sb()
		end
		local h, hid = vhandle(last_page, ent, "w")
		update_entry(last_page, ent, {
			size = 0
		})
		h.size = 0
		return hid
	elseif mode == "a" or mode == "ab" then
		local ent = free_ent or last_ent
		if free_ent then
			local first_page = first_free()
			if not first_page then return nil, "no free pages" end
			alloc_page(first_page)
			update_entry(last_page, free_ent, {
				flags = zealfs.flag_occupied,
				start_page = first_page,
				date = zealfs.to_bcddate(libpart.realtime()),
				name = fname,
				size = 0
			})
			save_sb()
		end
		local h, hid = vhandle(last_page, ent, "a")
		--h.pages = get_pages(last_ent_.start_page)
		h.pos = h.size
		return hid
	end
	return nil, "unknown mode "..mode
end

-- We write directly to the disk because OpenOS should do the buffering.
function proxy.write(handle, data)
	if not handles[handle] then return nil, "closed" end
	local h = handles[handle]
	if h.mode ~= "w" and h.mode ~= "a" then return nil, "not open for writing" end
	local dat, start_offset, end_offset, start_page = read_around(handle, #data)
	dprint("R_AROUND", #dat, start_offset, end_offset, start_page)
	dat = dat:sub(1, start_offset-1)..data..dat:sub(end_offset+1)
	local ok, why = raw_write(handle, start_page, dat)
	if not ok then return false, why end
	h.pos = h.pos + #data
	if h.pos-1 > h.size then
		local osize = h.size
		h.size = h.pos-1
		dprint("NEWSIZE", osize, h.size)
	end
	update_entry(h.parent, h.ent_id, {
		date = zealfs.to_bcddate(libpart.realtime()),
		size = h.size
	})
	save_sb()
	return true
end

function proxy.read(handle, amt)
	dprint("P_READ", handle, amt)
	if not handles[handle] then return nil, "closed" end
	local h = handles[handle]
	if h.mode ~= "r" then return nil, "not open for reading" end
	if h.pos > h.size then return nil end
	if amt+h.pos > h.size then
		local oamt = amt
		amt = h.size-h.pos+1
		dprint("P_READ_BOUND", amt, oamt)
	end
	local dat, start_offset, end_offset, start_page = read_around(handle, amt)
	dprint("R_AROUND", #dat, start_offset, start_page)
	h.pos = h.pos + amt
	return dat:sub(start_offset, start_offset+amt-1)--math.min(end_offset, h.size))
end

function proxy.seek(handle, whence, where)
	if not handles[handle] then return nil, "closed" end
	local h = handles[handle]
	if h.mode == "a" then return h.pos end
	if whence == "set" then
		h.pos = where
	elseif whence == "cur" then
		h.pos = h.pos + where
	elseif whence == "end" then
		h.pos = h.size + where
	end
	-- order here is important
	if h.pos > h.size then
		h.pos = h.size
	end
	if h.pos < 1 then
		h.pos = 1
	end
	return h.pos
end

function proxy.close(handle)
	--if not handles[handle] then return nil, "closed" end
	local hand = handles[handle]
	if hand and (hand.mode == "w" or hand.mode == "a") then
		-- Clean up page allocation
		local needed_pages = math.max(math.ceil(hand.size/255), 1)
		local last_needed = hand.pages[needed_pages]
		dprint("CLEANUP", needed_pages, #hand.pages)
		local _p = read_page(last_needed)
		_p = string.char(0) .._p:sub(2)
		write_page(last_needed, _p)
		for i=needed_pages+1, #hand.pages do
			free_page(hand.pages[i])
		end
		update_entry(hand.parent, hand.ent_id, {
			date = zealfs.to_bcddate(libpart.realtime()),
			size = hand.size
		})
		save_sb()
	end
	handles[handle] = nil
	return true
end

assert(require("filesystem").mount(proxy, args[2]))