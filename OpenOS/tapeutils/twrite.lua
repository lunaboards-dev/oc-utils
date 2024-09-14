local component = require("component")
local inet = assert(component.internet, "no internet component")
local uptime = require("computer").uptime

local dev, url = ...

local tape = assert(component.proxy(component.get(dev)))

local size, read, close
if url:sub(1, 5) == "file:" then
	local h = assert(io.open(url:sub(6), "rb"))
	size = h:seek("end", 0)
	h:seek("set", 0)
	read = function(amt)
		amt = math.min(amt, 8192)
		return h:read(amt)
	end
	close = function()h:close()end
else
	local h = inet.request(url, nil, {["User-Agent"] = "Wget/OpenComputers"})
	if h.finishConnect then
		local function try_connect()
			local ok, err = h.finishConnect()
			if type(ok) == "nil" then error("Failed to connect: "..err) end
			return ok
		end
		while not try_connect() do os.sleep(0) end
	end

	local code, res, headers = h.response()
	if code ~= 200 then
		error(string.format("Failed to connect: %d %s", code, res))
	end
	size = tonumber(headers["Content-Length"][1], 10)
	read = function(amt)
		return h.read(amt)
	end
	close = h.close
end
io.write(string.format("0/%d bytes (0%%) - 0 bytes/s", size))
local pos = 0
local rstime = uptime()
local start = uptime()
local lsize = 0
local function nan_guard(n)
	if n ~= n or math.abs(n) == math.huge then return -1 end
	return n
end
local function bps()
	return nan_guard(pos/(uptime()-rstime))--nan_guard(lsize/(uptime()-start))
end
local function remaining()
	return nan_guard((size-pos)//bps())
end
local function progress()
	return (pos/size)*100
end
local function get_read_amount()
	local ramt = (size-512) - pos
	if ramt <= 0 then ramt = 512 end
	return ramt
end

local function to_human_time(t)
	local u = "smh"
	local i = 1
	local r = ""
	t = t // 1
	while i < 4 do
		local p = t % 60
		t = t // 60
		r = string.format("%d%s%s", p, u:sub(i,i), r)
		i = i + 1
		if t == 0 then return r end
	end
	return r
end

local function to_human_bytes(b)
	local units = {"bytes", "KiB", "MiB"}
	local i = 1
	b = b // 1
	while b >= 1024 do
		b = b / 1024
		i = i + 1
		if i == #units then break end
	end
	return string.format("%.1f %s", b, units[i])
end
local partition_table = read(512)
tape.seek((tape.getSize()-512)-tape.getPosition())
tape.write(partition_table)
local last_sleep = uptime()
tape.seek(-tape.getPosition())
while true do
	local sector = read(math.huge)
	if not sector then break end
	tape.write(sector)
	pos = pos + #sector
	lsize = #sector
	io.write(string.format("\27[2K\r%s/%s (%.1f%%) - %s/s (%s remaining)", to_human_bytes(pos), to_human_bytes(size), progress(), to_human_bytes(bps()), to_human_time(remaining()//1)))
	start = uptime()
	if last_sleep > 4 then os.sleep(0) last_sleep = uptime() end
end
print("Write complete.")
close()