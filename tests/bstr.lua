local bstr = require("srz.bstr")

local st = bstr.new()

st:write(1, 1)
st:write(0, 1)
st:write(0xFFFF, 16)
local str = st:finalize()
st = bstr.new(str)
print(st:read(1))
print(st:read(1))
print(st:read(16))
