local formats = {
	list = {}
}

function formats.add(name, fmt)
	formats.list[name] = fmt
end

local function add_format(fmt)
	formats.add(fmt, require("archive.formats."..fmt:gsub("%-", "")))
end

--add_format("cpio-bin")
add_format("cpio-newc")
--add_format("tar")
--add_format("mtar")
--add_format("sarc")
--add_format("zip")

return formats