local mtf = require("srz.mtf")
local input = arg[1]

local encoded = mtf.encode(input)
local decoded = mtf.decode(encoded)

print(input, decoded)