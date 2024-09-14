local tamd = require("tamd")
local component = require("component")
local tape = component.proxy(component.get(...))

local lbl = assert(tamd.read(tape), "bad label")

local formats = {
	[0] = "dfpwm"
}

print("Album: "..lbl.album)
print(string.format("Sample rate: %.1fkHz", lbl.sample_rate/10))
print("Audio format: "..(formats[lbl.format] or "<unknown>"))
print("Total length: "..tamd.to_human_time_alt(tamd.byte_to_second(lbl.size, lbl.sample_rate*100)))
print("Tracks:")
for i=1, #lbl.tracks do
	local trk = lbl.tracks[i]
	print(string.format("  %d. %s - %s (%s)", i, trk.artist, trk.name, tamd.to_human_time_alt(tamd.byte_to_second(trk.length, lbl.sample_rate*100))))
end