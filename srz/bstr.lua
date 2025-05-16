local bstr = {}

function bstr.new(str)
	return setmetatable({
		--width = width,
		buffer = str and str:byte(1) or 0,
		idx = 0,
		str = str or "",
		off = str and 1
	}, {__index=bstr})
end

function bstr:write(bits, size)
	local fullmask = (1 << size)-1
	if self.off then return end
	local wamt = math.min(8-self.idx, size)
	--io.stderr:write(wamt,"\n")
	local msk = 0xFF >> (8-wamt)
	if bits & fullmask ~= bits then
		error("overflow ("..bits.." > "..fullmask..")")
	end
	self.buffer = self.buffer | ((bits & msk) << self.idx)
	size = size - wamt
	bits = bits >> wamt
	self.idx = self.idx + wamt
	if self.idx == 8 then
		self.str = self.str .. string.char(self.buffer)
		self.buffer = 0
		self.idx = 0
	end
	if size > 0 then
		self:write(bits, size)
	end
end

function bstr:read(bits)
	if self.eof or not self.off then return end
	local ramt = math.min(8-self.idx, bits)
	local mask = 0xFF >> (8-ramt)
	local dat = (self.buffer >> self.idx) & mask
	self.idx = self.idx + ramt
	bits = bits - ramt
	if self.idx == 8 then
		self.off = self.off + 1
		if (self.off > #self.str) then
			self.eof = true
		end
		self.buffer = self.str:byte(self.off)
		self.idx = 0
	end
	if bits > 0 and not self.eof then
		return dat | (self:read(bits) << ramt)
	end
	return dat
end

function bstr:finalize()
	if self.idx > 0 then
		self:write(0, 8-self.idx)
	end
	return self.str
end

return bstr