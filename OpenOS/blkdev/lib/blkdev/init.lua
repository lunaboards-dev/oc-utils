local bdev = {
	devs = {}
}

function bdev.register(name, proto)
	bdev.devs[name] = proto
end

function bdev.proxy(id, opts)
	for k, v in pairs(bdev.devs) do
		if v.check(id, opts or {}) then
			local dev = setmetatable({}, {__index=v})
			dev:init(id, opts or {})
			dev.__bdtype = k
			return dev
		end
	end
	error("unknown device type")
end

bdev.register("loop", require("blkdev.devs.loop"))
bdev.register("drv", require("blkdev.devs.drive"))

return bdev