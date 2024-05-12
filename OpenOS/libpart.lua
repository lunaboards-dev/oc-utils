local component = require("component")
local part = {}
local osdi_hdr, mtpt_hdr = "<IIc8I3c13", ">c20c4II"

function part.read(disk)
	local last_sector = disk.getCapacity()//disk.getSectorSize()
	local sec = disk.readSector(1)
	local start, size, ptype, flags, name, offset = osdi_hdr:unpack(sec)
	if start == 1 and ptype == "OSDI\xAA\xAA\x55\x55" then
		-- decode OSDI
		local ents = {
			type = "osdi"
		}

		for i=offset, #sec, osdi_hdr:packsize() do
			start, size, ptype, flags, name, offset = osdi_hdr:unpack(sec, offset)
			table.insert(ents, {
				start = start,
				size = size,
				type = ptype,
				flags = flags,
				name = name
			})
		end
		return ents
	end
	sec = disk.readSector(last_sector)
	name, ptype, start, size, offset = mtpt_hdr:unpack(sec)
	if ptype == "mtpt" then
		local ents = {
			type = "mtpt"
		}
		for i=offset, #sec, mtpt_hdr:packsize() do
			name, ptype, start, size, offset = mtpt_hdr:unpack(sec, offset)
			table.insert(ents, {
				start = start,
				size = size,
				type = ptype,
				name = name
			})
		end
		return ents
	end
	return nil, "unknown partition table"
end

-- parse partition identifiers
function part.parse(str)

end

return part