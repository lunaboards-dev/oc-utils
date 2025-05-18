-- this seems dumb but it's actually a really good bit of test data
local lzssh = require("srz.lzssh")
local bee = ""
do
	local f = io.open("bee.txt", "r")
	bee = f:read("*a")
	f:close()
end
--bee = bee:sub(1, 0x1FFF)
local cmp, _tree = lzssh.encode(bee)
local tree = lzssh.loadtree(_tree)
local dec = lzssh.decode(cmp, tree)
print("")
io.stderr:write(string.format("%d -> %d (%.1f%%)\n", #bee, #cmp, (#cmp/#bee)*100))
local function lines(str)
	local list = {}
	for line in str:gmatch("[^\n]*") do
		table.insert(list, line)
	end
	return list
end
if (bee ~= dec) then
	io.stderr:write("Mismatch between original and decompressed.\n")
	local bl, dl = lines(bee), lines(dec)
	for i=1, math.max(#bl, #dl) do
		local l1, l2 = bl[i], dl[i]
		if not l2 then
			io.stderr:write(string.format("%d: %s -> (NULL)\n", i, l1))
			--break
		elseif not l1 then
			io.stderr:write(string.format("%d: (NULL) -> %s\n", i, l2))
			--break
		elseif l1 ~= l2 then
			io.stderr:write(string.format("%d: %s -> %s\n", i, l1, l2))
			--break
		end
	end
end