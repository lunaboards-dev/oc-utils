local tdda_track = "<IIs1s1s1"
local tdda_label = "<IHBs1B"
local probe_command = "ffprobe %q 2>&1 | grep -A90 'Metadata:'"
local convert_command = "ffmpeg -i %q -ac 1 -ar 48k -c:a dfpwm -f dfpwm pipe:1"

local parser = require("argparse")()

parser:argument("source", "Source files")
parser:argument("output", "Output file")

parser:option("--album-name", "Sets album name.")
parser:option("--pad", "Pad tracks to set block size."):convert(tonumber)

local args = parser:parse()

local function pad(dat, padding)
	padding = padding or 512
	local pad_bytes = padding-(#dat % padding)
	if pad_bytes < padding then
		dat = dat .. string.rep("\0", pad_bytes)
	end
	return dat
end

local function assert_close(h)
	local ok, xtype, code = h:close()
	if not ok then
		error(string.format("Failed to convert file: %s (%s %d)", source, xtype, code))
	end
end

local function convert_file(source)
	local h = assert(io.popen(convert_command:format(source), "r"))
	local dat = h:read("*a")
	assert_close(h)
	return dat
end

local function strip(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function get_file_info(source)
	local h = assert(io.popen(probe_command:format(source), "r"))
	local meta = {path=source}
	for line in h:lines() do
		line = strip(line)
		local tag = strip(line:match("[^:]+")):lower()
		local value = line:match(":%s*(.+)")
		if tag == "duration" then assert_close(h) return meta end
		if tag ~= "metadata" then
			meta[tag] = value
		end
	end
	assert_close(h)
end

local bad_files = {
	jpg = 1,
	png = 1,
	jpeg = 1
}

local dir = assert(io.popen(string.format("find %q", args.source), "r"))

local album_name = args.album_name
local files = {}
for line in dir:lines() do
	print(line)
	local ext = line:match("%.([^%.]+)$")
	if ext and not bad_files[ext] then
		print("CONVERT", line)
		local meta = get_file_info(line)
		if not album_name then album_name = meta.album end
		local dat = convert_file(line)
		if args.pad then
			dat = pad(dat, args.pad)
		end
		meta.data = dat
		table.insert(files, meta)
	end
end

table.sort(files, function(a, b)
	local trk_a, trk_b = a.track and tonumber(a.track, 10) or math.huge, b.track and tonumber(b.track, 10)  or math.huge
	if trk_a == trk_b then return a.title < b.title end
	return trk_a < trk_b
end)
local track_info = {}
local data = ""
for i=1, #files do
	local f = files[i]
	local trk_info = tdda_track:pack(#data, #f.data, f.title, f.artist, "")
	table.insert(track_info, trk_info)
	data = data .. f.data
end

local header = pad(tdda_label:pack(#data, 480, 0, album_name or "", #track_info)..table.concat(track_info), args.pad)

data = pad(data, args.pad)

local function s_count(s)
	return #s // (args.pad or 512)
end

local mtpt_header = ">c20c4II"
local parts = mtpt_header:pack("", "mtpt", 0, 0) ..
	mtpt_header:pack("Album", "tdda", 1, s_count(data)) ..
	mtpt_header:pack("Metadata", "tamd", s_count(data)+1, s_count(header))

local of = assert(io.open(args.output, "wb"))
local body = data..header --require("lz16").compress(data..header)
of:write(pad(parts, args.pad), body)
of:close()
