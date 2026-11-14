local resourceName <const> = GetCurrentResourceName()
local included <const> = debug.getinfo(1, 'S').source:match('^@@([^/]+)/') or 'oxmysql'
local host <const> = (included == 'mysql-async' or included == 'ghmattimysql') and 'oxmysql' or included
local exportPrefix <const> = ('__cfx_export_%s_'):format(host)
local TriggerEvent <const> = TriggerEvent
local GetResourceState <const> = GetResourceState
local CreateThreadNow <const> = Citizen.CreateThreadNow
local type <const> = type

---@enum MySQLOp
local Op <const> = {
	query = 0,
	single = 1,
	scalar = 2,
	insert = 3,
	update = 4,
	prepare = 5,
	rawExecute = 6,
	transaction = 7,
	begin = 8,
	sessionQuery = 9,
}

local options <const> = {
	return_callback_errors = false,
}

for i = 1, GetNumResourceMetadata(resourceName, 'mysql_option') do
	options[GetResourceMetadata(resourceName, 'mysql_option', i - 1)] = true
end

---@type table<string, function>
local refs = {}

AddEventHandler('onResourceStop', function()
	if GetResourceState(host) ~= 'started' then refs = {} end
end)

---@param name string
---@return function
local function ref(name)
	local fn = refs[name]
	if fn then return fn end

	TriggerEvent(exportPrefix .. name, function(exported) fn = exported end)
	if not fn then error(('No such export %s in resource %s'):format(name, host), 3) end

	refs[name] = fn
	return fn
end

---@param op MySQLOp
---@param query any
---@param parameters any
---@param isPromise boolean
---@param session? integer
---@param deferred? boolean
---@return table reply `{ value }` or `{ nil, error }`
local function call(op, query, parameters, isPromise, session, deferred)
	return ref('call')(op, query, parameters, resourceName, isPromise, session or 0, deferred)
end

local GetGameTimer <const> = GetGameTimer
local isyieldable <const> = coroutine.isyieldable
local streakLimitMs <const> = 50
local idleGapMs <const> = 100
local streakStart = 0
local lastAnswer = 0

local function yieldAfterLongStreak()
	local now <const> = GetGameTimer()

	if now - lastAnswer > idleGapMs then streakStart = now end

	lastAnswer = now

	if now - streakStart < streakLimitMs or not isyieldable() then return end

	Wait(0)
	streakStart = GetGameTimer()
	lastAnswer = streakStart
end

---@param op MySQLOp
---@param query any
---@param parameters any
local function await(op, query, parameters)
	local reply <const> = call(op, query, parameters, true)
	local err <const> = reply[2]

	yieldAfterLongStreak()

	if err then error(err, 3) end

	return reply[1]
end

---@param op MySQLOp
---@param query any
---@param parameters any
---@param cb? function|table
local function dispatch(op, query, parameters, cb)
	local returnErrors <const> = options.return_callback_errors

	CreateThreadNow(function()
		local reply <const> = call(op, query, parameters, returnErrors, 0, true)
		local err <const> = reply[2]

		if not cb then return end
		if not err then return cb(reply[1]) end
		if returnErrors then cb(nil, err) end
	end)
end

---@type string[]
local queryStore <const> = {}

---@param query string|integer|table
---@param parameters? table|function
---@param cb? function|table
---@param transaction? boolean
---@return string|table query
---@return table? parameters
---@return function|table? cb
local function safeArgs(query, parameters, cb, transaction)
	local queryType <const> = type(query)

	if queryType == 'number' then
		query = queryStore[query]
		assert(query, 'First argument received invalid query store reference')
	elseif transaction then
		if queryType ~= 'table' then
			error(("First argument expected table, received '%s'"):format(query))
		end
	elseif queryType ~= 'string' then
		error(("First argument expected string, received '%s'"):format(query))
	end

	if parameters then
		local paramType <const> = type(parameters)

		if paramType ~= 'table' and paramType ~= 'function' then
			error(("Second argument expected table or function, received '%s'"):format(parameters))
		end

		if paramType == 'function' or parameters.__cfx_functionReference then
			cb = parameters
			parameters = nil
		end
	end

	if cb and parameters then
		local cbType <const> = type(cb)

		if cbType ~= 'function' and (cbType == 'table' and not cb.__cfx_functionReference) then
			error(("Third argument expected function, received '%s'"):format(cb))
		end
	end

	return query, parameters, cb
end

local mysql_method_mt <const> = {
	__call = function(self, query, parameters, cb)
		query, parameters, cb = safeArgs(query, parameters, cb, self.method == 'transaction')
		return dispatch(Op[self.method], query, parameters, cb)
	end,
}

local MySQL <const> = setmetatable(MySQL or {}, {
	__index = function(_, index)
		return function(...)
			return exports[host][index](nil, ...)
		end
	end,
})

for method, op in pairs(Op) do
	if op <= Op.transaction then
		MySQL[method] = setmetatable({
			method = method,
			await = function(query, parameters)
				query, parameters = safeArgs(query, parameters, nil, method == 'transaction')
				return await(op, query, parameters)
			end,
		}, mysql_method_mt)
	end
end

local alias <const> = {
	fetchAll = 'query',
	fetchScalar = 'scalar',
	fetchSingle = 'single',
	insert = 'insert',
	execute = 'update',
	transaction = 'transaction',
	prepare = 'prepare',
}

local alias_mt <const> = {
	__index = function(self, key)
		if alias[key] then
			local method <const> = MySQL[alias[key]]
			MySQL.Async[key] = method
			MySQL.Sync[key] = method.await
			alias[key] = nil
			return self[key]
		end
	end,
}

---@param query string
---@param cb? fun(storeId: integer): any
---@return any
local function addStore(query, cb)
	assert(type(query) == 'string', 'The SQL Query must be a string')

	local storeN <const> = #queryStore + 1
	queryStore[storeN] = query

	return cb and cb(storeN) or storeN
end

MySQL.Sync = setmetatable({ store = addStore }, alias_mt)
MySQL.Async = setmetatable({ store = addStore }, alias_mt)

---@param cb? fun(): any
---@return any
local function onReady(cb)
	while GetResourceState(host) ~= 'started' do
		Wait(50)
	end

	ref('awaitConnection')()

	return cb and cb() or true
end

MySQL.ready = setmetatable({
	await = onReady,
}, {
	__call = function(_, cb)
		CreateThreadNow(function() onReady(cb) end)
	end,
})

---@param cb fun(query: fun(sql: string, values?: table): any): boolean?
---@return boolean committed
function MySQL.startTransaction(cb)
	local opened <const> = call(Op.begin, nil, nil, false)
	local session <const> = opened[1]

	if not session then return false end

	local queryError

	---@param sql string
	---@param values? table
	---@return any
	local function query(sql, values)
		local reply <const> = call(Op.sessionQuery, sql, values, true, session)
		queryError = reply[2]

		yieldAfterLongStreak()

		if queryError then error(queryError, 0) end

		return reply[1]
	end

	local ok <const>, result <const> = pcall(cb, query)
	local finish <const> = ref('endTransaction')

	if not ok then
		return finish(session, false, resourceName, result == queryError and result or 'SCRIPT ERROR: ' .. tostring(result))
	end

	return finish(session, result ~= false, resourceName)
end

_ENV.MySQL = MySQL
