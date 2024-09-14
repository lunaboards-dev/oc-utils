--[[
	struct tdda_track {
		uint32_t offset;
		uint32_t length;
		string track_name;
		string artist;
		string genre;
	};
	struct tdda_label {
		uint32_t total_length;
		uint16_t sample_rate;
		uint8_t audio_format;
		string album;
		uint8_t tracks;
		struct tdda_track tracks[];
	};
]]

local tdda_track = "<IIs1s1s1"
local tdda_label = "<IHBs1B"
local mtpt_entry = ">c20c4II"

local tamd = {}

local function dev_setpos(dev, pos)
	dev.seek((pos)-dev.getPosition())
end

function tamd.read(dev)
	dev_setpos(dev, dev.getSize()-512)
	local _, meta = mtpt_entry:unpack(dev.read(mtpt_entry:packsize()))
	if meta ~= "mtpt" then return nil end
	local start_pos, md_size, audio_start_pos
	while true do
		local dat = dev.read(mtpt_entry:packsize())
		if not dat or #dat < mtpt_entry:packsize() then break end
		local name, ptype, offset, size = mtpt_entry:unpack(dat)
		if ptype == "tamd" then
			start_pos = (offset-1)*512
			md_size = size*512
			break
		elseif ptype == "tdda" then
			audio_start_pos = (offset-1)*512
		end
	end
	if not start_pos or not audio_start_pos then return end
	dev_setpos(dev, start_pos)
	local md = dev.read(md_size)
	local total_length, sample_rate, aformat, album, track_count, offset = tdda_label:unpack(md)
	local tracks = {}
	for i=1, track_count do
		local trk = {}
		trk.offset, trk.length, trk.name, trk.artist, trk.genre, offset = tdda_track:unpack(md, offset)
		table.insert(tracks, trk)
	end
	return {
		start = audio_start_pos,
		size = total_length,
		sample_rate = sample_rate,
		format = aformat,
		album = album,
		tracks = tracks
	}
end

function tamd.to_human_time_alt(t)
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

function tamd.to_human_time(t)
	local i = 1
	local parts = {}
	t = t // 1
	while i < 4 do
		local p = t % 60
		t = t // 60
		table.insert(parts, string.format("%.2d", p))
		i = i + 1
		if t == 0 then return table.concat(parts, ":") end
	end
	return table.concat(parts, ":")
end

function tamd.byte_to_second(b, sr)
	return (b*8)/sr
end

return tamd