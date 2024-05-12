local component = require("component")
local part = {}
local osdi_hdr, mtpt_hdr = "<IIc8I3c13", ">c20c4II"

function part.mtpt(disk)
	local last_sector = disk.getCapacity()//disk.getSectorSize()
	local sec = disk.readSector(last_sector)
	local name, ptype, start, size, offset = mtpt_hdr:unpack(sec)
	if ptype == "mtpt" then
		local ents = {
			type = "mtpt"
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
		return ents
	end
end

function part.osdi(disk)
	local sec = disk.readSector(1)
	local start, size, ptype, flags, name, offset = osdi_hdr:unpack(sec)
	if start == 1 and ptype == "OSDI\xAA\xAA\x55\x55" then
		-- decode OSDI
		local ents = {
			type = "osdi"
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
				valid = ptype == string.rep("\0", 8)
			})
		end
		return ents
	end
end

local parts = {
	mtpt = part.mtpt,
	osdi = part.osdi
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
	local ptype, addr, pn = str:match("(%w+)%(([%x%-]+), ?(%n+)%)")
	ptype = ptype:lower()
	if parts[ptype] then
		local comp = component.proxy(assert(component.get(addr, "drive")))
		local p = parts[ptype](comp)
		if p then
			return p[tonumber(pn, 10)], comp
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
	local pinfo, dsk = part.parse(id)
	local sec_count = dsk.getCapacity()/dsk.getSectorSize()
	local start_sec_offset = (pinfo.start+1)*dsk.getSectorSize()+1
	local proxy = {}
	function proxy.readByte(offset)
		return dsk.readByte(start_sec_offset+offset-1)
	end
	function proxy.writeByte(offset, val)
		return dsk.writeByte(start_sec_offset+offset-1, val)
	end
	proxy.getSectorSize = dsk.getSectorSize
	function proxy.getLabel()
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

	return proxy
end

return part