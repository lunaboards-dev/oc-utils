local cpio = {
	padding = 2,
	header = {"\xc7\x71", "\x71\xc7"},
	type = "tape",
	ext = "cpio"
}

function cpio.read_entry(file)

end

function cpio.write_entry(file, ent)

end

function cpio.leadout(file)

end

return cpio