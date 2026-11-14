---@class Bench
---@field encode fun(value: any): string
---@field report fun(name: string, value: any)
---@field steps { name: string, run: fun() }[]
Bench = { steps = {} }

local function encode(value)
	local kind <const> = type(value)

	if kind == 'nil' then return 'nil' end
	if kind == 'string' then return ('%q'):format(value) end
	if kind == 'number' then return math.type(value) == 'integer' and tostring(value) or ('%.6g'):format(value) end
	if kind ~= 'table' then return tostring(value) end

	local keys <const> = {}

	for key in pairs(value) do keys[#keys + 1] = key end

	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == 'number'
	end)

	local parts <const> = {}

	for i, key in ipairs(keys) do
		parts[i] = ('%s=%s'):format(type(key) == 'string' and key or ('[%s]'):format(key), encode(value[key]))
	end

	return ('{%s}'):format(table.concat(parts, ','))
end

Bench.encode = encode

function Bench.report(name, value)
	print(('COMPAT %s %s'):format(name, encode(value)))
end

---@param name string
---@param run fun()
function Bench.step(name, run)
	Bench.steps[#Bench.steps + 1] = { name = name, run = run }
end
