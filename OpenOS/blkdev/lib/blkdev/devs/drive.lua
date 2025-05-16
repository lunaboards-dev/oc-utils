local component = require("component")

local blk = {}

function blk.check(id, opts)
	local ct = component.type(id)
	return ct and ct:sub(1, 5) == "drive"
end

function blk:init(id, opts)
	self.dev = component.proxy(id)
	self.opts = opts or {}
end

function blk:read(id)
	return self.dev.readSector(id)
end

function blk:write(id, data)
	return self.dev.writeSector(id)
end

function blk:readonly()
	return self.opts.ro or self.dev.isReadOnly()
end

function blk:blocks()
	return self:size()//self:blksize()
end

function blk:blksize()
	return self.dev.getSectorSize()
end

function blk:size()
	return self.dev.getCapacity()
end

function blk:ready()
	return true
end

function blk:class()
	return "physical"
end

return blk