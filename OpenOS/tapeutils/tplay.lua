local component = require("component")
local tamd = require("tamd")
local dev, skip = ...
local tape = component.proxy(component.get(dev))
local event = require("event")

local label = assert(tamd.read(tape), "bad label")
local function get_track_info()
	local pos = tape.getPosition()
	local offset_pos = pos-label.start
	for i=1, #label.tracks do
		local trk = label.tracks[i]
		if pos >= trk.offset and pos <= trk.offset+trk.length-1 then
			return pos-trk.offset, trk, label.tracks[i-1], label.tracks[i+1]
		end
	end
end
tape.seek(label.start-tape.getPosition())
tape.play()
local exit
local function intfunction()
	tape.stop()
	exit = true
	event.ignore("interrupted", intfunction)
end
event.listen("interrupted", intfunction)

local function print_status()
	local pos = tape.getPosition()-label.start
	local offset, ctrk, ptrk, ntrk = get_track_info()
	print(string.format("\27[2K\rAlbum: %s (%s / %s)", label.album,
						tamd.to_human_time_alt(tamd.byte_to_second(pos, label.sample_rate*100)),
						tamd.to_human_time_alt(tamd.byte_to_second(label.size, label.sample_rate*100))))
	if not ptrk then
		print("\27[2K\r\27[0m-")
	else
		print(string.format("\27[2K\r%s", ptrk.name))
	end
	local trk_pos = tamd.to_human_time_alt(tamd.byte_to_second(offset, label.sample_rate*100))
	local trk_len = tamd.to_human_time_alt(tamd.byte_to_second(ctrk.length, label.sample_rate*100))
	print(string.format("\27[2K\r\27[33m%s\27[0m (%s / %s)", ctrk.name, trk_pos, trk_len))
	local progress = offset/ctrk.length
	local w = component.gpu.getViewport()
	local bar_size = w-14
	local _bar_prog = math.ceil(progress*bar_size)-1
	local bar_progressed = string.rep(" ", math.min(_bar_prog, bar_size-1))
	local bar_empty = string.rep(" ", (bar_size-#bar_progressed)-1)
	print(string.format("%6s \27[47m%s\27[0m▓%s %6s", trk_pos, bar_progressed, bar_empty, trk_len))
	if not ntrk then
		print("\27[2K\r\27[0m-")
	else
		print(string.format("\27[2K\r%s", ntrk.name))
	end
end
if skip then
	local sk = tonumber(skip, 10)
	tape.seek(label.tracks[sk].offset)
end
while not exit do
	--local offset, trk = get_track_info()
	--[[local pos = tamd.to_human_time(tamd.byte_to_second_alt(offset, label.sample_rate*100))
	local max = tamd.to_human_time(tamd.byte_to_second_alt(trk.length, label.sample_rate*100))]]
	--io.stdout:write(string.format("\27[2K\rNow playing: %s - %s (%s/%s)", trk.artist, trk.name))
	print_status()
	print("\27[6A")
	os.sleep(0.5)
end
print("\n\n\n\n")
