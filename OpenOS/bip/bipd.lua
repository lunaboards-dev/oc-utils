local component = require("component")
local event = require("event")
local fs = require("filesystem")

local function die(err)
	io.stderr:write(err,"\n")
	os.exit(1)
end

local function read_ini(file, tbl)
	local current_key
	local current_tbl
	local linen = 1
	for line in file:lines() do
		line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub(";.+", "")
		if line == "" then goto continue end
		if line:match("%[[%a%-]+%]") then
			if current_key then
				tbl[current_key] = current_tbl
			end
			current_key = line:sub(2, #line-1)
			current_tbl = {}
		elseif line:match("[%w%-]+%s*=%s*.+") then
			if not current_key then die("key-value pair with no group! (line "..linen..")") end
			local k, v = line:match("([%w%-]+)%s*=%s*(.+)")
			if type(current_tbl[k]) == "table" then
				table.insert(current_tbl[k], v)
			elseif type(current_key[k]) ~= "nil" then
				current_tbl[k] = {current_tbl[k], k}
			else
				current_tbl[k] = v
			end
		else
			die("bad key or group (line "..linen..")")
		end
		::continue::
		linen = linen + 1
	end
	if current_key then
		tbl[current_key] = current_tbl
	end
end

local function write_ini(file, tbl)
	for group, kvp in pairs(tbl) do
		file:write(string.format("[%s]\n", group))
		for k, v in pairs(kvp) do
			if type(v) == "table" then
				for i=1, #v do
					file:write(string.format("%s=%s\n", k, tostring(v[i])))
				end
			else
				file:write(string.format("%s=%s\n", k, tostring(v)))
			end
		end
		file:write("\n")
	end
end

local rules = {
	machines = {},
	groups = {},
	targets = {},
}
local states = {}
local target_pattern = "([^:]+):(%d+)/(.+)"

local function save_rules()
	local f = io.open("/etc/bipd.ini", "w")
	write_ini(f, rules)
	f:close()
end

local function handle_agent(_, modem, target, port, _, version)
	local dev = component.proxy(modem)
	if port == 9900 and version == 1 then
		if not rules.machines[target] then
			rules.machines[target] = "default"
			save_rules()
		end
		local grp = rules.machines[target]
		if not rules.groups[grp] then
			rules.groups[grp] = "default"
			save_rules()
		end
		local tgt = rules.groups[grp]
		local targets = rules.targets[tgt]
		if not targets then
			dev.send(target, 9900, -1, "no target")
		elseif type(targets) == "table" then
			if not states[tgt] then
				states[tgt] = 1
			end
			local real_target = targets[states[tgt]]
			local host, vport, path = real_target:match(target_pattern)
			dev.send(target, 9900, 1, host, tonumber(vport), path)
			states[tgt] = states[tgt] + 1
			if states[tgt] > #targets then
				states[tgt] = 1
			end
		else
			local host, vport, path = targets:match(target_pattern)
			dev.send(target, 9900, 1, host, tonumber(vport), path)
		end
	elseif port == 9900 then
		dev.send(target, 9900, -2, "unknown version")
	end
end

local function load_rules()
	if fs.exists("/etc/bipd.ini") then
		rules = {}
		local f = io.open("/etc/bipd.ini", "r")
		read_ini(f, rules)
		f:close()
	end
end

function start()
	for modem in component.list("modem") do
		component.invoke(modem, "open", 9900)
	end
	load_rules()
	event.listen("modem_message", handle_agent)
	event.push("dans_add_service", "modem", 9900, "boot/bip", "BIP server")
end

function stop()
	for modem in component.list("modem") do
		component.invoke(modem, "close", 9900)
	end
	event.ignore("modem_message", handle_agent)
	event.push("dans_rm_service", "modem", 9900, "boot/bip", "BIP server")
end

local function find_machine(addr)
	for k, v in pairs(rules.machines) do
		if k:sub(1, #addr) == addr then
			return k
		end
	end
end

function group(grp, action, arg)
	load_rules()
	if action == "del" then
		rules.groups[grp] = nil
		for k, v in pairs(rules.machines) do
			if v == grp then
				rules.machines[k] = "default"
			end
		end
	elseif action == "add" then
		local mach = arg --find_machine(addr)
		if #mach < 36 then
			mach = find_machine(arg)
			if not mach then
				die("unable to find machine")
			end
		end
		rules.machines[mach] = grp
		rules.groups[grp] = rules.groups[grp] or "default"
	elseif action == "rm" then
		local mach = arg --find_machine(addr)
		if #mach < 36 then
			mach = find_machine(arg)
			if not mach then
				die("unable to find machine")
			end
		end
		rules.machines[mach] = "default"
	elseif action == "target" then
		if not rules.targets[arg] then
			die("no such target")
		end
		rules.groups[grp] = arg
	elseif action == "list" then
		for k, v in pairs(rules.machines) do
			if v == grp then
				print(k)
			end
		end
	else
		die("unknown action")
	end
	save_rules()
end

local function del_target(tgt)
	rules.targets[tgt] = nil
	for k, v in pairs(rules.groups) do
		if v == tgt then
			rules.groups[k] = "default"
		end
	end
end

function target(tgt, action, host)
	load_rules()
	if action == "add" then
		if not host:match(target_pattern) then
			die("bad target pattern")
		end
		if not rules.targets[tgt] then
			rules.targets[tgt] = host
		elseif type(rules.targets[tgt]) == "string" then
			rules.targets[tgt] = {rules.targets[tgt], host}
		else
			table.insert(rules.targets[tgt], host)
		end
	elseif action == "rm" then
		if type(rules.targets[tgt]) == "string" and rules.targets[tgt] == host then
			del_target(tgt)
		elseif type(rules.targets[tgt]) == "table" then
			local tl = rules.targets[tgt]
			for i=1, #tl do
				if tl[i] == host then
					table.remove(tl, i)
					if #tl == 1 then
						rules.targets[tgt] = tl[1]
					end
				end
			end
		end
	elseif action == "del" then
		del_target(tgt)
	elseif action == "list" then
		local tl = rules.targets[tgt]
		for i=1, #tl do
			print(tl[i])
		end
	else
		die("unknown action")
	end
	save_rules()
end

function save()
	save_rules()
end