local oc, fs = pcall(require, "filesystem")
local pc, lfs = pcall(require, "lfs")
local blk = {}

function blk.check(path, opts)
	if not oc and not pc then error("unknown platform! this will only work if manually invoked...") end
	if oc then
		return fs.exists(path)
	else
		return lfs.attributes(path)
	end
end

function blk:init(path, opts)
	opts.bs = tonumber(opts.bs or "512", 10)
	local hand = io.open(self.path, "r+b")
	if opts.count then
		opts.count = tonumber(opts.count, 10)
	else
		opts.count = math.ceil(hand:seek("end", 0)/opts.bs)
	end
	self.fill = string.char(tonumber(opts.fill or "00", 16))
	self.opts = opts or {}
	self.hand = hand
	self.path = path
	return self.hand
end

function blk:read(id)
	self.hand:seek("set", id*self.opts.bs)
	local dat = self.hand:read(self.opts.bs)
	dat = dat .. string.rep(self.fill, self.opts.bs-#dat)
	return dat
end

function blk:write(id, data)
	if self.opts.ro then return nil, "read only" end
	self.hand:seek("set", id*self.opts.bs)
	self.hand:write(data)
	return true
end

function blk:readonly()
	return self.opts.ro
end

function blk:blocks()
	return self.opts.count
end

function blk:blksize()
	return self.opts.bs
end

function blk:size()
	return self.opts.count*self.opts.bs
end

function blk:ready()
	return true
end

function blk:class()
	return self.opts.phys and "physical" or "logical"
end

return blk