local ocfs = {}

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
					vals[i] = tbl[fields[i]]
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

ocfs.signature = 0xA738

ocfs.superblock = struct {
	{signature = "H"},
	{version = "B"},
	{reserved = "B"},
	{first_block = "I3"},
	{group_size = "I3"},
	{total_blocks = "I3"},
	{free_blocks = "I3"},
	{nodes_per_group = "H"},
	{volume_name = "c16"},
	{uuid = "c16"}
}

ocfs.nodegroup = struct {
	{version = "B"},
	{next_group = "I3"},
	{allocated_nodes = "H"}
}

ocfs.inode = struct {
	{nlinks="H"},
	{size_last="H"},
	{attributes="B"},
	{block_count="I3"},
	{mtime="I6"},
	{ctime="I6"},
	{[1]="I3"},
	{[2]="I3"},
	{[3]="I3"},
	{[4]="I3"},
	{[5]="I3"},
	{[6]="I3"},
	{[7]="I3"},
	{[8]="I3"},
	{[9]="I3"},
	{[10]="I3"},
	{sip="I3"},
	{dip_list="I3"}
}

--[[

	function signature(str)
		local res = 0
		for i=1, #str do
			res = ((res << 13) | (res >> 3)) & 0xFFFF
			res = res ~ str:byte(i)
			res = ((res >> 8) | (res << 8)) & 0xFFFF
		end
		return res
	end

	struct ocfs_superblock {
		uint16_t signature; // 0xA738
		uint8_t version;
		uint8_t reserved;
		uint24_t first_block;
		uint24_t group_size;
		uint24_t total_blocks;
		uint24_t free_blocks;
		char volume_name[16];
		char uuid[16];
	};

	struct ocfs_nodegroup {
		uint8_t version;
		uint24_t next_group;
		uint16_t allocated_nodes;
	};

	struct ocfs_inode {
		uint16_t nlinks;
		uint16_t size_last;
		uint8_t attributes;
		uint24_t block_count;
		uint48_t mtime;
		uint48_t ctime;
		uint24_t blocks[10];
		uint24_t sip;
		uint24_t dip_list;
	};
]]

function ocfs.find_superblock(disk, offset)
	offset = offset or 1
	for i=1, 16 do
		local dat = disk.readSector(offset+i-1)
		local sb = ocfs.superblock(dat)
		if sb.signature == ocfs.signature then
			return sb, i
		end
	end
end

--[[
function ocfs.load_bitmap(disk, true_offset)
	local sb = ocfs.superblock(disk.readSector(true_offset))
	local bitmap_size = sb.total_blocks // 8
	local bitmap_blocks = math.ceil(bitmap_size / 512)
	local bitmap = ""
	for i=1, bitmap_blocks do
		bitmap = bitmap .. disk.readSector(true_offset+i)
	end
	return sb, bitmap
end

function ocfs.save_bitmap(disk, true_offset, bitmap)
	local sb = ocfs.superblock(disk.readSector(true_offset))
	local bitmap_size = sb.total_blocks // 8
	local bitmap_blocks = math.ceil(bitmap_size / 512)
	for i=1, bitmap_blocks do
		disk.writeSector(true_offset+i, bitmap:sub(1, 512))
		bitmap = bitmap:sub(512)
	end
end

function ocfs.allocate_block(disk, true_offset)
	local sb, bitmap = ocfs.load_bitmap(disk, true_offset)

end
]]

return ocfs