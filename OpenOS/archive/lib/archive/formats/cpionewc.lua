local cpio = {
	padding = 4,
	header = {"070701"},
	type = "tape"
}

local function readhex(f, n)
	return tonumber(f:read(n), 16)
end

function cpio.read(file)

end

function cpio.write(file)

end

return cpio