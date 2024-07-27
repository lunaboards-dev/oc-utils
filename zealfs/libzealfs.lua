local zealfs = {}

local function struct(tbl)
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

zealfs.magic = string.byte("Z")

zealfs.header = struct {
	{magic = "B"},
	{version = "B"},
	{bitmap_size = "B"},
	{free_pages = "B"},
	{pages_bitmap = "c32"},
	-- Extension: ID
	{id_hi = "H"},
	{id_lo = "H"},
	{resv0 = "c24"}
}

zealfs.flag_occupied = 0x80 -- 1 << 7
zealfs.flag_dir = 1
zealfs.IS_DIR = zealfs.flag_dir | zealfs.flag_occupied

zealfs.dirent = struct {
	endian = "<",
	{flags = "B"},
	{name = "c16"},
	{start_page = "B"},
	{size="H"},
	{date = "c8"},
	{resv0="c4"}
}

local function proxy_smaller(dev)
	local proxy = {}

	local phy = dev.getSectorSize()
	local phy_to_logical = 256/phy

	proxy.readByte = dev.readByte
	proxy.writeByte = dev.writeByte
	function proxy.getSectorSize()
		return 256
	end
	proxy.setLabel = dev.setLabel
	proxy.getLabel = dev.getLabel

	local function logical_to_phy(sec)
		return (sec-1)*phy_to_logical+1
	end

	function proxy.readSector(n)
		local rtn = {}
		local pos = logical_to_phy(n)
		for i=1, phy_to_logical do
			rtn[i] = dev.readSector(pos+i-1)
		end
		return (table.concat(rtn))
	end

	function proxy.writeSector(n, val)
		local pos = logical_to_phy(n)
		for i=1, phy_to_logical do
			dev.writeSector(pos+i-1, val:sub(1, phy))
			val = val:sub(phy+1)
		end
	end
	proxy.getPlatterCount = dev.getPlatterCount
	proxy.getCapacity = dev.getCapacity
	proxy.isReadOnly = proxy.isReadOnly

	return proxy
end

local function proxy_larger(dev)
	local proxy = {}

	local phy = dev.getSectorSize()
	local logical_to_phy = phy/256

	proxy.readByte = dev.readByte
	proxy.writeByte = dev.writeByte
	function proxy.getSectorSize()
		return 256
	end
	proxy.setLabel = dev.setLabel
	proxy.getLabel = dev.getLabel
	proxy.address = dev.address

	local function phy_to_logical(sec)
		local sec_0 = sec-1
		local pos = (sec_0//logical_to_phy)+1
		local off = ((sec_0%logical_to_phy)*256)+1
		return pos, off
	end

	function proxy.readSector(n)
		local pos, off = phy_to_logical(n)
		local dat = dev.readSector(pos)
		return dat:sub(off, off+255)
	end

	function proxy.writeSector(n, val)
		val = val:sub(1, 256)
		val = val..string.rep("\0", 256-#val)
		local pos, off = phy_to_logical(n)
		local sec = dev.readSector(pos)
		local wdat = sec:sub(1, off-1)..val..sec:sub(off+256)
		dev.writeSector(pos, wdat)
	end
	proxy.getPlatterCount = dev.getPlatterCount
	proxy.getCapacity = dev.getCapacity
	proxy.isReadOnly = proxy.isReadOnly

	return proxy
end

function zealfs.block_proxy(dev)
	local sec = dev.getSectorSize()
	if sec < 256 then
		return proxy_smaller(dev)
	elseif sec > 256 then
		return proxy_larger(dev)
	else
		return dev
	end
end

local function from_bcd(b)
	local int = 0
	for i=1, #b do
		local byte = b:byte(i)
		local hi, lo = byte >> 4, byte & 0xF
		int = int * 100
		int = int + (hi*10) + lo
	end
	return int
end

local function to_bcd(n)
	local r = 0
	local i = 0
	while n > 0 do
		local d = n % 10
		r = r | (d << (i*4))
		i = i + 1
		n = n // 10
	end
	return r
end

function zealfs.from_bcddate(bcd)
	local year = from_bcd(bcd:sub(1, 2))
	local month = from_bcd(bcd:sub(3, 3))
	local day = from_bcd(bcd:sub(4, 4))
	local date = from_bcd(bcd:sub(5, 5))
	local hours = from_bcd(bcd:sub(6, 6))
	local minutes = from_bcd(bcd:sub(7, 7))
	local seconds = from_bcd(bcd:sub(8, 8))
	return os.time {
		year = year,
		month = month,
		day = day,
		hour = hours,
		min = minutes,
		sec = seconds
	}
end

function zealfs.to_bcddate(time)
	local date = os.date("!*t", time)
	return (string.pack(">HBBBBBB",
		to_bcd(date.year),
		to_bcd(date.month),
		to_bcd(date.day),
		to_bcd(date.wday),
		to_bcd(date.hour),
		to_bcd(date.min),
		to_bcd(date.sec)
	))
end

return zealfs