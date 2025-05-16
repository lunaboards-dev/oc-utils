local tokens = {
	"function",
	"local",
	"and",
	"or",
	"then",
	"if",
	"do",
	"end",
	"while",
	"end",
	"repeat",
	"goto",
	"continue",
	"==",
	"type",
	"require"
}

for i=1, #tokens do
	tokens[tokens[i]] = 400+i-1
end

local tok = {
	tokens = tokens
}

function tok.find(str, offset)
	for i=1, #tokens do
		local t = tokens[i]
		if str:sub(1, #t) == tokens then
			return 400+i-1, #t
		end
	end
end

function tokens.lookup(id)
	return tokens[id-400+1]
end

return tok