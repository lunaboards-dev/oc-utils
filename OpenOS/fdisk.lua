local shell = require("shell")
local component = require("component")
local osdi_hdr, mtpt_hdr = "<IIc8I3c13", ">c20c4II"
local args, opts = shell.parse(...)

local function last_sector(tape)
	local size = tape.getSize()
	local blks = size//512
	--print("size", size/512, size//512)
	local last_blk = (blks-1)*512
	--print("lastblk vs size", last_blk, size, last_blk-size)
	local last_blk_size = size-last_blk
	--print("blks vs lastblksize", blks, last_blk_size)
	return blks, last_blk_size
end

local devs = {
	["tape_drive"] = {
		read = function(prox, sec)
			local lb, lbs = last_sector(prox)
			local pos = prox.getPosition()
			prox.seek(((sec-1)*512)-pos)
			--print((sec == lb) and lbs or 512, lbs)
			return prox.read((sec == lb) and lbs or 512)
		end,
		write = function(prox, sec, data)
			--local lb, lbs = last_sector(prox)
			local pos = prox.getPosition()
			prox.seek(((sec-1)*512)-pos)
			prox.write(data)
		end,
		size = function(prox, sec)
			local lb, lbs = last_sector(prox)
			return (sec == lb) and lbs or 512
		end,
		last = function(prox)
			local lb, lbs = last_sector(prox)
			return lb
		end
	},
	["ossm_eeprom"] = {
		read = "blockRead",
		write = "blockWrite",
		size = "blockSize",
		last = function(prox)
			return prox.numBlocks()
		end
	},
	["drive"] = {
		read = "readSector",
		write = "writeSector",
		size = "getSectorSize",
		last = function(prox)
			local size = prox.getCapacity()
			local blksize = prox.getSectorSize()
			return size//blksize
		end
	}
}

local menu = {
	["Generic"] = {
		d = "delete a partition",
		F = "list free unpartitioned space",
		l = "list known partition types",
		n = "add a new partition",
		p = "print the partition table",
		t = "change a partition type",
		--v = "verify the partition table",
		--i = "print information about a partition",
		f = "set flags",
		L = "set partition label",
		D = "set disk label"
	},
	["Misc"] = {
		m = "print this menu"
	},
	["Save & Exit"] = {
		w = "write table to disk and exit",
		q = "quit without saving changes"
	},
	[true] = {
		a = "mark a partition as active",
		o = "create a new empty OSDI partition table",
		M = "create a new empty MTPT (minitel) partition table"
	}
	--[[["Create a new label"] = {
		o = "create a new empty OSDI partition table",
		m = "create a new empty MTPT (minitel) partition table"
	}]]
}

local known_partitions = {
	osdi = {
		{["foxfs"] = "FoxFS"},
		{["zryainit"] = "Zorya NEO Init"},
		{["BOOTCODE"] = "Bootloader code"},
		{["openos"] = "OpenOS Root (/)"},
		{["SIMPLEFS"] = "SimpleFS"},
		{["VelxBoot"] = "VXBoot Boot Partition"},
		{["fencroot"] = "Fennec Root (/)"},
		{["fencusr"] = "Fennec /usr"},
		{["fenchome"] = "Fennec /home"},
		{["fencsrv"] = "Fennec /srv"},
		{["rtfs"] = "RTFS"},
		{["mtpt"] = "MTPT Partition Table"},
		{["bootpart"] = "Bootloader partition"},
	},
	mtpt = {
		{["rtfs"] = "RTFS"},
		{["boot"] = "Bootloader code"},
		{["oosr"] = "OpenOS Root (/)"},
		{["vxbp"] = "VXBoot Boot Partition"},
		{["osdi"] = "OSDI Partition Table"},
		{["blpt"] = "Bootloader partition"}
	}
}

local function get_type(pt, idx)
	if type(idx) == "number" then
		return next(known_partitions[pt][idx])
	else
		for i=1, #known_partitions[pt] do
			local k, v = next(known_partitions[pt][i])
			if k == idx:gsub("\0+$", "") then
				return v
			end
		end
	end
end

local function die(msg)
	io.stderr:write(msg,"\n")
	os.exit(1)
end

local function resolve(dev)
	return component.get(dev, "drive") or component.get(dev, "tape_drive") or component.get("ossm_eeprom") or die(string.format("can't resolve %s into a component", dev))
end

local function dev_wrap(dev)
	local complete = resolve(dev)
	local ct = component.type(complete)
	local prox = component.proxy(complete)
	local function mfunc(func)
		return function(...)
			if type(devs[ct][func]) == "function" then
				return devs[ct][func](prox, ...)
			else
				return component.invoke(complete, devs[ct][func], ...)
			end
		end
	end
	return {
		read = mfunc("read"),
		write = mfunc("write"),
		size = mfunc("size"),
		last = mfunc("last"),
		type = ct,
		addr = complete
	}
end

local function osdi_read(dev)
	local sec = dev.read(1)
	local nc = 1
	local tbl = {type="osdi"}
	while nc < #sec do
		local ent = {}
		ent.start, ent.size, ent.type, ent.flags, ent.name, nc = osdi_hdr:unpack(sec, nc)
		table.insert(tbl, ent)
	end
	return tbl
end

local function mtpt_read(dev)
	local sec = dev.read(dev.last())
	local nc = 1
	local tbl = {type="mtpt"}
	while nc < #sec do
		local ent = {}
		ent.name, ent.type, ent.start, ent.size, nc = mtpt_hdr:unpack(sec, nc)
		table.insert(tbl, ent)
	end
	return tbl
end

local function detect_table(dev)
	if dev.type ~= "tape_drive" then
		local tbl = osdi_read(dev)
		local sig = tbl[1]
		if sig.start == 1 and sig.type == "OSDI\xAA\xAA\x55\x55" then
			return tbl
		end
	end
	local tbl = mtpt_read(dev)
	local sig = tbl[1]
	if sig.type == "mtpt" then
		return tbl
	end
end

local function prompt(msg)
	io.stdout:write(msg..": ")
	return io.read()
end

local function valid_command(c)
	if #c > 1 then return end
	for k, v in pairs(menu) do
		for cv in pairs(v) do
			if cv == c then
				return true
			end
		end
	end
end

local function eprint(msg)
	io.stderr:write(msg, "\n")
end

if not args[1] or opts.h then
	print("usage: fdisk [-h] <device address>")
end

local odev = dev_wrap(args[1])

local tbl = detect_table(odev)
local function flag_set(char, name)
	return {char=char, name=name, set=true}
end
local function flag(char, name)
	return {char=char, name=name}
end

local no_flag = flag("?", "Unknown")

local ptypes = {
	osdi = {
		name = "OSDI",
		read = osdi_read,
		pack = osdi_hdr,
		loc = 1,
		start = 2,
		_end = odev.last(),
		sig = {start = 1, size = 0, flags = 0, type = "OSDI\xAA\xAA\x55\x55", name = ""},
		write = function()
			local tval = {}
			for i=1, #tbl do
				local te = tbl[i]
				local ent = osdi_hdr:pack(te.start, te.size, te.type, te.flags, te.name)
				table.insert(tval, ent)
			end
			odev.write(1, table.concat(tval))
		end,
		free = function(ent)
			return ent.type:gsub("\0+$", "") == ""
		end,
		flags = "%.24s",
		flags_short = "%.12s",
		flag_list = {
			short = 12,
			flag("o", "OS partition"),
			flag("b", "bootloader partition"),
			flag("p", "POSIX permissions"),
			flag_set("r", "read-only"),
			flag_set("h", "hidden"),
			flag_set("s", "system critical partition"),
			flag("z", "Zorya special"),
			flag("m", "managed FS emulation"),
			flag("r", "raw data"),
			flag_set("A", "active"),
			flag("o", "OEFI hint"),
			flag("o", "OEFI hint"),
			-- System specific flags
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
			no_flag,
		},
		namesize = 13,
		typesize = 8
	},
	mtpt = {
		name = "MTPT (minitel)",
		read = mtpt_read,
		pack = mtpt_hdr,
		sig = {start = 0, size = 0, type = "mtpt", name = ""},
		loc = odev.last(),
		start = 1,
		_end = odev.last()-1,
		write = function()
			local tval = {}
			for i=1, #tbl do
				local te = tbl[i]
				local ent = mtpt_hdr:pack(te.name, te.type, te.start, te.size)
				table.insert(tval, ent)
			end
			odev.write(odev.last(), table.concat(tval))
		end,
		free = function(ent)
			return ent.name:gsub("\0+$", "") == ""
		end,
		flags = false,
		namesize = 20,
		typesize = 4
	}
}

local function free_sectors(start, _end)
	local parts = {}
	for i=2, #tbl do
		if not ptypes[tbl.type].free(tbl[i]) then
			table.insert(parts, {start = tbl[i].start, _end = tbl[i].start+tbl[i].size-1})
		end
	end
	table.sort(parts, function(a, b)
		return a.start < b.start
	end)
	local free_space = {}
	local free_start = start
	for i=1, #parts do
		--print("start", free_start)
		local p = parts[i]
		if p.start-1 >= free_start then
			table.insert(free_space, {
				start = free_start,
				_end = p.start-1
			})
		end
		free_start = p._end+1
		--print("end", free_start)
	end
	if free_start <= _end then
		table.insert(free_space, {
			start = free_start,
			_end = _end
		})
	end
	return free_space
end

local function ranges_to_human(ran)
	local str = {}
	for i=1, #ran do
		local r = ran[i]
		if r.start == r._end then
			table.insert(str, tostring(r.start))
		else
			table.insert(str, string.format("%d-%d", r.start, r._end))
		end
	end
	return table.concat(str, ", ")
end

local function create_table(ptype)
	local part = ptypes[ptype]
	local pcount = odev.size(part.loc)//part.pack:packsize()
	tbl = {type=ptype}
	tbl[1] = part.sig
	for i=2, pcount do
		tbl[i] = {start=0, size=0, flags=0, type="", name = ""}
	end
	print(string.format("Created new %s partition table", ptypes[ptype].name))
end

local open_type
if not tbl then
	print("Device does not contain a recognized partition table.")
	if odev.type == "tape_drive" then
		create_table("mtpt")
	else
		create_table("osdi")
	end
else
	open_type = tbl.type
end

local function adv_prompt(msg, check)
	while true do
		local res = prompt(msg)
		if check(res) then
			return res
		end
	end
end

local function collection_to_human(col)
	local groups = {}
	local cur_min, cur
	for i=1, #col do
		local e = col[i]
		if not cur_min then
			cur_min = e
			cur = e
		elseif cur + 1 ~= e then
			if cur_min == cur then
				table.insert(groups, tostring(cur_min))
			else
				table.insert(groups, string.format("%d-%d", cur_min, cur))
			end
			cur_min = e
			cur = e
		else
			cur = e
		end
	end
	if cur_min == cur then
		table.insert(groups, tostring(cur_min))
	else
		table.insert(groups, string.format("%d-%d", cur_min, cur))
	end
	return table.concat(groups, ", ")
end

local function get_free()
	local free = {}
	for i=2, #tbl do
		if ptypes[tbl.type].free(tbl[i]) then
			table.insert(free, i-1)
		end
	end
	return free
end

local function get_used()
	local used = {}
	for i=2, #tbl do
		if not ptypes[tbl.type].free(tbl[i]) then
			table.insert(used, i-1)
		end
	end
	return used
end

local function invert(l)
	local il = {}
	for i=1, #l do
		il[l[i]] = i
	end
	return il
end

local function list_types()
	local h = assert(io.popen("less -", "w"))
	for i=1, #known_partitions[tbl.type] do
		local k, v = next(known_partitions[tbl.type][i])
		h:write(string.format("%.2x %"..#tbl[1].type.."s: %s\n", i, k, v))
	end
	h:close()
end

-- if you make a multi-GiB partition i will hurt you
local sizes = {" bytes", "KiB", "MiB"}
local function to_human(n)
	for i=1, #sizes-1 do
		if n <= 1024 then
			return string.format("%.1f%s", n, sizes[i])
		end
		n = n / 1024
	end
	return string.format("%.1f%s", n, sizes[#sizes])
end

local function serialize_flags(flag_list, flags, short)
	local bit = 1
	local fstr = ""
	local fl = {}
	for i=1, short or #flag_list do
		local set = flags & bit > 0
		fstr = (set and flag_list[i].char or "-") .. fstr
		bit = bit << 1
		if set then table.insert(fl, flag_list[i]) end
	end
	return fstr, fl
end

local dev_names = {
	drive = "Disk",
	tape_drive = "Tape",
	ossm_eeprom = "EEPROM"
}

while true do
	local pt = ptypes[tbl.type]
	local cmd = prompt("Command (m for help)")
	if not valid_command(cmd) then if cmd ~= "" then eprint(cmd..": unknown command") end goto continue end
	--[[
		Set or view flags
	]]
	if cmd == "f" then
		if not pt.flags then
			eprint("No flags.")
			goto continue
		end
		local flag_list = {}
		for i=1, #pt.flag_list do
			local fl = pt.flag_list[i]
			if fl.set then
				table.insert(flag_list, fl)
				flag_list[fl.char] = 1 << (i-1)
			end
		end
		local used = get_used()
		if #used == 0 then
			eprint("No partitions.")
			goto continue
		end
		local lookup = invert(used)
		local range = collection_to_human(used)
		local part = adv_prompt(string.format("Select a partition (%s, q to quit) [%d]", range, used[#used]), function(r)
			return r == "q" or r == "" or (tonumber(r, 10) and lookup[tonumber(r, 10)])
		end)
		if part == "q" then goto continue end
		if part == "" then
			part = used[#used]
		else
			part = tonumber(part, 10)
		end
		while true do
			local fv, fl = serialize_flags(pt.flag_list, tbl[part+1].flags)
			print(string.format("Flags: "..pt.flags.."\n", fv))
			for i=1, #flag_list do
				print(string.format("  %s   %s", flag_list[i].char, flag_list[i].name))
			end
			print("  ?   print all set flag meanings")
			print("  q   exits this submenu")
			local fls = prompt("Flag (q to exit)")
			if fls == "?" then
				for i=1, #fl do
					print(string.format("  %s   %s", fl[i].char, fl[i].name))
				end
			elseif flag_list[fls] then
				tbl[part+1].flags = tbl[part+1].flags ~ flag_list[fls]
			elseif fls == "q" then
				goto continue
			else
				eprint("Unknown command or flag.")
			end
		end
	--[[
		List types
	]]
	elseif cmd == "l" then
		list_types()
	--[[
		Drive label
	]]
	elseif cmd == "D" then
		local label = prompt("Enter disk label")
		label = label:sub(1, pt.namesize)
		tbl[1].name = label
		--component.invoke(odev.addr, "setLabel", label)
		print(string.format("Drive label set to '%s'", label))
	--[[
		Set partition label
	]]
	elseif cmd == "L" then
		local used = get_used()
		if #used == 0 then
			eprint("No partitions.")
			goto continue
		end
		local lookup = invert(used)
		local range = collection_to_human(used)
		local part = adv_prompt(string.format("Select a partition (%s, q to quit) [%d]", range, used[#used]), function(r)
			return r == "q" or r == "" or (tonumber(r, 10) and lookup[tonumber(r, 10)])
		end)
		if part == "q" then goto continue end
		if part == "" then
			part = used[#used]
		else
			part = tonumber(part, 10)
		end
		local label = adv_prompt("Enter label", function(r)
			if tbl.type == "mtpt" then
				return #r > 0
			end
			return true
		end)
		tbl[part+1].name = label:sub(1, pt.namesize)
		print(string.format("Partition %d label set to '%s'", part, label))
	--[[
		Delete partition
	]]
	elseif cmd == "d" then
		local used = get_used()
		if #used == 0 then
			eprint("No partitions.")
			goto continue
		end
		local lookup = invert(used)
		local range = collection_to_human(used)
		local part = adv_prompt(string.format("Select a partition to delete (%s, q to quit) [%d]", range, used[#used]), function(r)
			return r == "q" or r == "" or (tonumber(r, 10) and lookup[tonumber(r, 10)])
		end)
		if part == "q" then goto continue end
		if part == "" then
			part = used[#used]
		else
			part = tonumber(part, 10)
		end
		tbl[part+1] = {size = 0, start = 0, type = "", name = "", flags = ""}
		print(string.format("Partition %d has been deleted.", part))
	--[[
		Change type
	]]
	elseif cmd == "t" then
		local used = get_used()
		if #used == 0 then
			eprint("No partitions.")
			goto continue
		end
		local lookup = invert(used)
		local range = collection_to_human(used)
		local part = adv_prompt(string.format("Select a partition (%s, q to quit) [%d]", range, used[#used]), function(r)
			return r == "q" or r == "" or (tonumber(r, 10) and lookup[tonumber(r, 10)])
		end)
		if part == "q" then goto continue end
		if part == "" then
			part = used[#used]
		else
			part = tonumber(part, 10)
		end
		local _newpt
		local newpt = adv_prompt("New type (L to list types, q to quit)", function(r)
			if r == "q" then return true end
			if r == "L" then
				list_types()
				return
			end
			if r:sub(1, 1) == "*" then
				_newpt = r:sub(2)
				return true
			elseif r:sub(1,1) == "#" then
				_newpt = ""
				if #r % 2 > 0 then
					eprint("invalid type")
					return
				end
				for i=1, #r, 2 do
					local hex = tonumber(r:sub(i, i+1), 16)
					if not hex then eprint("malformed hex pair") return end
					_newpt = string.char(hex)
				end
				return true
			end
			if tonumber(r, 16) then
				local _pt = known_partitions[tbl.type][tonumber(r, 16)]
				if _pt then
					_newpt = next(_pt)
					return true
				end
			end
		end)
		if newpt == "q" then goto continue end
		tbl[part+1].type = _newpt:sub(1, pt.typesize)
		print(string.format("Partition %d type set to '%s'.", part, get_type(tbl.type, _newpt) or "Unknown"))
	--[[
		Print partition table
	]]
	elseif cmd == "p" then
		local sec_count = odev.last()
		local size = odev.size()*sec_count
		print(string.format("%s %s: %s, %d bytes, %d sectors", dev_names[odev.type], odev.addr, to_human(size),size, sec_count))
		print(string.format("%s label: %s", dev_names[odev.type], tbl[1].name))
		print(string.format("Sector size: %d bytes", odev.size()))
		print("Partition table type: "..tbl.type.."\n")
		local list = {}
		if pt.flags then
			list[1] = {"Part", "Flags", "Start", "Sectors", "Size", "ID", "Type", "Label"}
		else
			list[1] = {"Part", "Start", "Sectors", "Size", "ID", "Type", "Label"}
		end
		local sizes = {}
		for i=1, #list[1] do
			sizes[i] = #list[1][i]
		end
		for i=2, #tbl do
			if pt.free(tbl[i]) then goto next end
			local ent = {}
			local function add_entry(format, ...)
				table.insert(ent, string.format(format, ...))
				local pos = #ent
				--print(pos)
				if #ent[pos] > sizes[pos] then
					sizes[pos] = #ent[pos]
				end
			end
			add_entry("%d", i-1)
			if pt.flags then
				add_entry(pt.flags_short, (serialize_flags(pt.flag_list, tbl[i].flags, pt.flag_list.short)))
			end
			add_entry("%d", tbl[i].start)
			add_entry("%d", tbl[i].size)
			add_entry(to_human(tbl[i].size * odev.size()))
			add_entry(string.rep("%.2x", #tbl[i].type), tbl[i].type:byte(1, #tbl[i].type))
			add_entry(get_type(tbl.type, tbl[i].type) or "Unknown")
			add_entry(tbl[i].name)
			table.insert(list, ent)
			::next::
		end
		for i=1, #list do
			local line = {}
			for j=1, #list[i] do
				local s = list[i][j]
				line[j] = s .. string.rep(" ", sizes[j]-#s)
				if sizes[j] %2 == 1 then
					line[j] = line[j] .. " "
				end
			end
			print(table.concat(line, " "))
		end
	--[[
		New partition
	]]
	elseif cmd == "n" then
		local free = get_free()
		local secs = free_sectors(pt.start, pt._end)
		if #free == 0 then
			eprint("No free partitions.")
			goto continue
		end
		if #secs == 0 then
			eprint("No free sectors.")
			goto continue
		end
		local lookup = invert(free)
		local part = adv_prompt(string.format("Partition number (%s, q to quit) [%d]", collection_to_human(free), free[1]), function(r)
			return (tonumber(r, 10) and lookup[tonumber(r, 10)]) or r == "q" or r == ""
		end)
		if part == "q" then goto continue end
		if part == "" then
			part = free[1]
		else
			part = tonumber(part, 10)
		end
		local max
		local start_sec = adv_prompt(string.format("Start sector (%s, q to quit) [%d]", ranges_to_human(secs), secs[1].start), function(r)
			if r == "q" or r == "" then return true end
			local n = tonumber(r, 10)
			if not n then return end
			for i=1, #secs do
				if n >= secs[i].start and n <= secs[i]._end then
					max = secs[i]._end
					return true
				end
			end
		end)
		if start_sec == "q" then goto continue end
		if start_sec == "" then
			start_sec = secs[1].start
			max = secs[1]._end
		else
			start_sec = tonumber(start_sec, 10)
		end
		local _sig = {K=2, M = 2048}
		local end_sec_n
		local end_sec = adv_prompt(string.format("End sector, +sectors or +size{K,M} (%d-%d, q to quit) [%d]", start_sec, max, max), function(r)
			if r == "q" or r == "" then return true end
			local add, num, size = r:match("^(%+?)(%d+)([KM]?)$")
			local n = tonumber(num, 10)
			if not n then return end
			if size ~= "" then
				n = n * _sig[size]
			end
			if add == "+" then
				n = n + start_sec - 1
			end
			end_sec_n = n
			return n >= start_sec and n <= max
		end)
		if end_sec == "q" then goto continue end
		if end_sec == "" then
			end_sec = max
		else
			end_sec = end_sec_n
		end
		local label = ""
		if tbl.type == "mtpt" then
			label = adv_prompt("Enter a label", function(v)
				return #v > 0
			end)
		end
		local default_part, name = get_type(tbl.type, 1)
		local size = end_sec-start_sec+1
		tbl[part+1] = {start = start_sec, size = size, type = default_part, name = label:sub(1, pt.namesize), flags = 0}
		print(string.format("Created a new '%s' partition of %s", name, to_human(odev.size()*size)))
	--[[
		New partition tables
	]]
	elseif cmd == "o" and odev.type ~= "tape_drive" then
		create_table("osdi")
	elseif cmd == "M" then
		create_table("mtpt")
	--[[
		Help
	]]
	elseif cmd == "m" then
		local keys = {}
		for k, v in pairs(menu) do
			if k ~= true then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for i=1, #keys do
			print(keys[i])
			local ent = menu[keys[i]]
			local coms = {}
			for k, v in pairs(ent) do
				table.insert(coms, k)
			end
			table.sort(coms)
			for j=1, #coms do
				print(string.format("  %s   %s", coms[j], ent[coms[j]]))
			end
		end
		print("Create a new label")
		if odev.type ~= "tape_drive" then
			print(string.format("  %s   %s", "o", menu[true].o))
		end
		print(string.format("  %s   %s", "M", menu[true].M))
	--[[
		Quit
	]]
	elseif cmd == "w" then
		print("Writing changes to disk...")
		ptypes[tbl.type].write()
		if tbl.type ~= open_type and open_type then
			local loc = ptypes[open_type].loc
			odev.write(loc, string.rep("\0", odev.size(loc)))
		end
		local lbl = tbl[1].name
		if lbl == "" then
			lbl = nil
		end
		component.invoke(odev.addr, "setLabel", lbl)
		require("computer").pushSignal("reload_partitions", odev.addr)
		os.exit()
	elseif cmd == "q" then
		os.exit()
	else
		eprint(cmd..": not implemented")
	end
	::continue::
end