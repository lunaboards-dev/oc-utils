local lzssh = require("srz.huffman")

local ipt = io.stdin:read("*a")

local dec, stree = lzssh.encode(ipt)

local dl = #dec+#stree

io.stderr:write(string.format("%d -> %d (%.1f%%)\n", #ipt, dl, (dl/#ipt)*100))