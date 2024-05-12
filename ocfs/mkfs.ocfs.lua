local component = require("component")
local shell = require("shell")
local ocfs = require("libocfs")

local args, opts = shell.parse(...)

local uuid = opts.uuid or require("uuid").next()
local label = opts.label or ""
local offset = opts.offset and tonumber(opts.offset) or 1
local group_size = opts.group_size and (tonumber(opts.group_size)) or 2048
local nodes = opts.nodes and tonumber(opts.nodes) or 256

local disk = component.get(args[1], "drive")

local capacity_blocks = disk.getCapacity()/disk.getBlockSize()
local bitmap_blocks = capacity_blocks/4096
local groups = capacity_blocks/group_size

local function a2b(addr)
    local d = ""
    for pair in addr:gmatch("%x%x") do
        d = d .. tonumber(pair, 16)
    end
    return d
end

local function pad(block)
    return block .. string.rep("\0", disk.getBlockSize()-#block)
end

local first_block = offset + bitmap_blocks + 1
local bitmap = string.rep("\0", capacity_blocks/8)
local function set_map(block, v)
    local byte = (block//8)+1
    local bit = (block % 8)
    local left = bitmap:sub(1, byte-1)
    local bval = bitmap:byte(byte)
    local right = bitmap:sub(byte+2)
    bval = (bval & ((1 << bit) ~ 0xFF)) | (v << bit)
    bitmap = left .. string.char(bval) .. right
end

local superblock = ocfs.superblock {
    signature = ocfs.signature,
    version = 0,
    reserved = 0,
    first_block = first_block,
    group_size = group_size,
    total_blocks = capacity_blocks,
    free_blocks = capacity_blocks - (first_block + groups),
    volume_name = label,
    uuid = a2b(uuid)
}

for i=1, offset do
    disk.writeBlock(i, pad(""))
    set_map(i, 1)
end

disk.writeSector(offset+1, pad(superblock))
set_map(offset+1, 1)
for i=1, bitmap_blocks do
    set_map(offset+1+i, 1)
end

for i=1, groups do
    local g_offset = first_block + ((i-1)*group_size)
    disk.writeSector(g_offset, pad(ocfs.nodegroup {
        version = 0,
        next_group = 0,
        allocated_nodes = 0
    }))
    set_map(g_offset, 1)
end

disk.writeSector(first_block, pad((ocfs.nodegroup {

})..ocfs.inode {

}))

for i=1, #bitmap_blocks, 512 do
    disk.writeSector(offset+i+1, bitmap_blocks:sub(i, i+511))
end
