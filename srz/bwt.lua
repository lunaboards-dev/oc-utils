local bwt = {}

local function sort_suf(a, b)
	return a[1] < b[1]
end

local function gen_sent(str)
	local prob = {}
	local lookup = {}
	for i=0, 255 do
		lookup[i] = true
	end
	for i=1, #str do
		local b = str:byte(i)
		lookup[b] = nil
		prob[b] = (prob[b] or 0) + 1
	end
	local c = next(lookup)
	if not c then
		local pv = {}
		for i=0, 255 do
			table.insert(pv, {prob[i], i})
		end
		table.sort(pv, sort_suf)
		-- Get the least common byte and the second least common byte that isn't 0
		local sent = pv[1][2]
		for i=2, 256 do
			if pv[i][2] ~= 0 then
				local sc, ec = string.char(sent), string.char(pv[i][2])
				local estr = str:gsub("[%"..sc.."%"..ec.."]", function(mat)
					if mat == sc then
						return ec.."\0"
					elseif mat == ec then
						return ec.."\1"
					end
				end)
				return sc, ec, estr
			end
		end
		error("internal error, didn't find a non-zero character after pv[256]")
	end
	return string.char(c)
end

function bwt.encode(str)
	local rots = {}
	local sent, esc, estr = gen_sent(str)
	if not sent then error("unable to generate sentinel character, cannot continue") end
	if estr then
		str = estr
	end
	str = str .. sent
	local strl = #str
	for i=1, strl do
		table.insert(rots, {str:sub(i), i-1})
	end
	table.sort(rots, sort_suf)
	local built = ""
	local ori
	for i=1, strl do
		--local rot = rots[i]
		local pos = rots[i][2]
		local j = pos-1
		if j < 0 then
			j = j + strl
		end
		built = built .. str:sub(j+1, j+1)
		if pos == 0 then
			ori = i-1
		end
		--built = built .. rots[i]:sub(#rots[i])
	end
	return built, sent, ori, esc
end

function bwt.decode(str)

end

return bwt