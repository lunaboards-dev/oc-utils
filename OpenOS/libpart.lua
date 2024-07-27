local component = require("component")
local part = {}
local osdi_hdr, mtpt_hdr = "<IIc8I3c13", ">c20c4II"

function part.mtpt(disk)
	local last_sector = disk.getCapacity()//disk.getSectorSize()
	local sec = disk.readSector(last_sector)
	local name, ptype, start, size, offset = mtpt_hdr:unpack(sec)
	if ptype == "mtpt" then
		local ents = {
			type = "mtpt",
			label = name
		}
		for i=offset, #sec, mtpt_hdr:packsize() do
			name, ptype, start, size, offset = mtpt_hdr:unpack(sec, offset)
			name = name:gsub("\0+$", "")
			table.insert(ents, {
				start = start,
				size = size,
				type = ptype,
				name = name,
				valid = name ~= ""
			})
		end
		return ents, function()
			local pack = {(mtpt_hdr:pack(ents.label, "mtpt", 0, 0))}
			for i=1, #ents do
				local e = ents[i]
				table.insert(pack, (mtpt_hdr:pack(e.name, e.type, e.start, e.size)))
			end
			disk.writeSector(last_sector, table.concat(pack))
		end
	end
end

function part.osdi(disk)
	local sec = disk.readSector(1)
	local start, size, ptype, flags, name, offset = osdi_hdr:unpack(sec)
	if start == 1 and ptype == "OSDI\xAA\xAA\x55\x55" then
		-- decode OSDI
		local ents = {
			type = "osdi",
			label = name
		}

		for i=offset, #sec, osdi_hdr:packsize() do
			start, size, ptype, flags, name, offset = osdi_hdr:unpack(sec, offset)
			name = name:gsub("\0+$", "")
			table.insert(ents, {
				start = start,
				size = size,
				type = ptype,
				flags = flags,
				name = name,
				valid = ptype ~= string.rep("\0", 8)
			})
		end
		return ents, function()
			local pack = {
				(osdi_hdr:pack(1, 0, "OSDI\xAA\xAA\x55\x55", 0, ents.label))
			}
			for i=1, #ents do
				local e = ents[i]
				table.insert(pack, (osdi_hdr:pack(e.start, e.size, e.type, e.flags. e.name)))
			end
			disk.writeSector(1, table.concat(pack))
		end
	end
end

local parts = {
	mtpt = part.mtpt,
	osdi = part.osdi
}

local fields = {
	mtpt = {
		name = 20
	},
	osdi = {
		name = 13
	}
}

function part.read(disk)
	local mtpt = part.mtpt(disk)
	if mtpt then return mtpt end
	local osdi = part.osdi(disk)
	if osdi then return osdi end
	return nil, "unknown partition table"
end

-- parse partition identifiers
function part.parse(str)
	local ptype, addr, pn = str:match("(%w+)%(([%x%-]+), ?(%d+)%)")
	if not ptype then error("bad identifier") end
	ptype = ptype:lower()
	if parts[ptype] then
		local comp = component.proxy(assert(component.get(addr, "drive")))
		local p, sync = parts[ptype](comp)
		if p then
			return p[tonumber(pn, 10)], comp, sync, string.format("%s(%s, %d)", ptype, comp.address, tonumber(pn, 10)), ptype
		end
	end
end

function part.list()
	local dlist = {}
	for dsk in component.list("drive") do
		local prox = component.proxy(dsk)
		local mtpt = part.mtpt(prox)
		if mtpt then
			for i=1, #mtpt do
				local p = mtpt[i]
				if p.valid then
					table.insert(dlist, string.format("mtpt(%s, %d)", dsk:sub(1, 3), i))
				end
			end
		end

		local osdi = part.osdi(prox)
		if osdi then
			for i=1, #osdi do
				local p = osdi[i]
				if p.valid then
					table.insert(dlist, string.format("osdi(%s, %d)", dsk:sub(1, 3), i))
				end
			end
		end
	end
	return dlist
end

function part.proxy(id)
	local pinfo, dsk, sync, fid, pt = part.parse(id)
	local sec_count = dsk.getCapacity()/dsk.getSectorSize()
	local start_sec_offset = (pinfo.start+1)*dsk.getSectorSize()+1
	local proxy = {}
	proxy.address = fid
	function proxy.readByte(offset)
		return dsk.readByte(start_sec_offset+offset-1)
	end
	function proxy.writeByte(offset, val)
		return dsk.writeByte(start_sec_offset+offset-1, val)
	end
	proxy.getSectorSize = dsk.getSectorSize
	function proxy.getLabel()
		if pinfo.name == "" then return nil end
		return pinfo.name
	end
	function proxy.readSector(n)
		return dsk.readSector(pinfo.start+n-1)
	end
	function proxy.writeSector(n, val)
		return dsk.writeSector(pinfo.start+n-1, val)
	end
	proxy.getPlatterCount = dsk.getPlatterCount
	function proxy.getCapacity()
		return pinfo.size*dsk.getSectorSize()
	end
	function proxy.setLabel(lab)
		pinfo.name = lab:sub(1, fields[pt].name)
		sync()
	end
	return proxy
end

local ut = require("computer").uptime
local f = io.open("/tmp/.rt", "w"):close()
local st = ut()
local lm = require("filesystem").lastModified("/tmp/.rt")
os.remove("/tmp/.rt")
if (lm/(1000^4) > 1) then
	lm = lm / 1000
	part.host_linux = true
end
local epoch = lm-st


function part.realtime()
	return epoch + ut()
end

function part.struct(tbl)
	local str = ""
	local fields = {}
	local n = #tbl
	for i=1, n do
		local k, v = next(tbl[i])
		fields[i] = k
		str = str .. v
	end
	fields.n = n
	return setmetatable({}, {
		__call = function(_, val, t, offset)
			if type(val) == "string" then
				t = t or {}
				local vals = table.pack(string.unpack(str, val, offset))
				for i=1, fields.n do
					t[fields[i]] = vals[i]
				end
				return t, vals[#vals]
			elseif type(val) == "table" then
				local vals = {}
				for i=1, fields.n do
					if not val[fields[i]] then
						error("missing field "..fields[i])
					end
					vals[i] = val[fields[i]]
				end
				vals.n = fields.n
				return string.pack(str, table.unpack(vals))
			else
				error("expected string or table, got "..type(val))
			end
		end,
		__len = function()
			return string.packsize(str)
		end
	})
end

return part