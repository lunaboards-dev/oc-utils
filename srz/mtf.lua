local mtf = {}

function mtf.encode(str)
	local dict = ""
	for i=0, 255 do
		dict = dict .. string.char(i)
	end
	local build = ""
	for i=1, #str do
		local c = str:sub(i,i)
		local pos = string.find(dict, c, 1, true)
		local left = dict:sub(1, pos-1)
		local right = dict:sub(pos+1)
		dict = c .. left .. right
		build = build .. string.char(pos-1)
	end
	return build
end

function mtf.decode(str)
	local dict = ""
	for i=0, 255 do
		dict = dict .. string.char(i)
	end
	local build = ""
	for i=1, #str do
		local pos = str:byte(i)+1
		--local pos = string.find(dict, c, 1, true)
		local c = dict:sub(pos, pos)
		local left = dict:sub(1, pos-1)
		local right = dict:sub(pos+1)
		dict = c .. left .. right
		build = build .. c
	end
	return build
end

return mtf