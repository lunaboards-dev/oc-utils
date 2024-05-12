local component = require("component")
local shell = require("shell")
local ocfs = require("libocfs")
local libpart = require("libpart")

local args, opts = shell.parse(...)

local uuid = opts.uuid or require("uuid").next()
local label = opts.label or ""
local offset = opts.offset and tonumber(opts.offset) or 1
local group_size = opts.group_size and (tonumber(opts.group_size)) or 2048
local nodes = opts.nodes and tonumber(opts.nodes) or 256

local disk = libpart.proxy(args[1])

local capacity_blocks = disk.getCapacity()/disk.getSectorSize()
local bitmap_blocks = math.ceil(capacity_blocks/4096)
local groups = math.ceil(capacity_blocks/group_size)

local function a2b(addr)
    local d = ""
    for pair in addr:gmatch("%x%x") do
        d = d .. tonumber(pair, 16)
    end
    return d
end

local function pad(block)
    return block .. string.rep("\0", disk.getSectorSize()-#block)
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
    uuid = a2b(uuid),
    nodes_per_group = nodes
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
local payload = (ocfs.dirent {
    node = 1,
    name = "."
})..(ocfs.dirent {
    node = 1,
    name = ".."
})

disk.writeSector(first_block, pad((ocfs.nodegroup {
    version = 0,
    next_group = 0,
    allocated_nodes = 1
})..ocfs.inode {
    nlinks = 2,
    size_last = 512-#payload,
    attributes = 0,
    block_count = 1,
    mtime = os.time(),
    ctime = os.time(),
    sip = 0,
    dip_list = 0,
    first_block+1, 0, 0, 0, 0, 0, 0, 0, 0, 0
}))

disk.writeSector(first_block, pad(payload))

for i=1, #bitmap_blocks, 512 do
    disk.writeSector(offset+i+1, bitmap_blocks:sub(i, i+511))
end
