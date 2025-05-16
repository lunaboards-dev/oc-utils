local bwt = require("srz.bwt")

local ipt = io.stdin:read("*a")

local trf, sent = bwt.encode(ipt)

print(ipt, trf:gsub("%"..sent, "\27[32m$\27[0m"), string.byte(sent))