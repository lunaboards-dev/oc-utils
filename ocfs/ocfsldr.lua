local disk = component.proxy(computer.getBootAddress())
local osdi_hdr = "<IIc8I3c13"
local superblock = "HBxI3I3I3I3Hc16c16"
local nodegroup = "BI3HH"
local inode = "HHBI3I6I6"

local sec = disk.readSector(1)

local start, size

for i=1, 16 do
	local _start, _size, ptype, flags, name = osdi_hdr:unpack(sec, osdi_hdr:packsize()*(i-1)+1)
	if ptype == "openos\0\0" then
		start = _start
		size = _size
		goto p_found
	end
end
error("boot partition not found")
::p_found::
local sb_offset
local sig, ver, fblock, gsize, tblocks, free, nodes, name, uuid
for i=1, 8 do
	sig, ver, fblock, gsize, tblocks, free, nodes, name, uuid = superblock:unpack(disk.readSector(start+i))
	if sig == 0xA738 then
		sb_offset = i
		goto s_found
	end
end
error("superblock not found")
::s_found::
local bitmap_size = math.ceil(tblocks/4096)
local base_offset = sb_offset+bitmap_size+1

local inode_size = inode:packsize()+36
local function read_inode(sec, offset)
	local n = {blocks={}}
	n.nlinks, n.size, n.attr, n.blocks, n.mtime, n.ctime, offset = inode:unpack(sec, offset)
	n.dat = sec:sub(offset, offset+35)
	for i=1, 10 do
		n.blocks[i], offset = string.unpack("I3", offset)
	end
	n.sip, n.dip, offset = string.unpack("I3I3", offset)
	return n, offset
end

local function get_inode(node)
	node = node - 1
	local group = node//nodes
	local node_pos = node % nodes
	local group_offset = group*gsize
	local offset = group_offset+base_offset
	while node_pos > 8 do
		local _ver, nextg, bmoff, allocated = nodegroup:unpack(disk.readSector(offset))
		offset = nextg
		node_pos = node_pos - 9
	end
	local sdat = disk.readSector(offset)
	return read_inode(sdat, (node_pos * inode_size)+nodegroup:packsize()+1)
end

local function read_node(node)
	local use_extents = node.attr & 4 > 0
	local inline = node.attr & 8 > 0
	if inline then return node.dat end
	if node.sip > 0 then
		if #node.blocks < 11 then
			local sec = disk.readSector(node.sip)
			local block, offset = 0, 0
			for i=1, 170 do
				block, offset = string.unpack("I3", offset)
				table.insert(node.blocks, block)
			end
		end
	end
	local buffer = {}
	if use_extents then
		for i=1, #node.blocks, 2 do
			local xstart, xsize = node.blocks[i], node.blocks[i+1]
			for j=1, xsize do
				table.insert(buffer, disk.readSector(xstart+j-1))
			end
		end
	else
		for i=1, #node.blocks do
			table.insert(buffer, disk.readSector(node.blocks[i]))
		end
	end
	local _buf = table.concat(buffer)
	return _buf:sub(1, #_buf-node.size)
end

local function readfile(path)
	local inode = 1
	for match in path:gmatch("[^/]+") do
		local node = get_inode(inode)
		if node.attr >> 6 ~= 0 then
			error("file not found: "..path)
		end
		local dat = read_node(node)
		local offset = 1
		while true do
			local _inode, name, _o = string.unpack("I3s1", dat, offset)
			offset = _o
			if name == match then
				inode = _inode
			end
		end
	end
	return read_node(get_inode(inode))
end

load(readfile("init.lua"), "=init.lua")(readfile)