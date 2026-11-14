local report <const> = Bench.report

---@param from integer
---@param to integer
---@param amount integer
---@param fault? 'sql' | 'lua'
---@return boolean
local function transfer(from, to, amount, fault)
	return MySQL.startTransaction(function(query)
		local debit <const> = query('UPDATE cobalt_bench_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { amount, from, amount })
		if debit.affectedRows ~= 1 then return false end

		query('UPDATE cobalt_bench_accounts SET balance = balance + ? WHERE id = ?', { amount, to })

		if fault == 'sql' then query('INSERT INTO cobalt_bench_ledger (nope) VALUES (?)', { 1 }) end
		if fault == 'lua' then error('ledger write refused') end

		query('INSERT INTO cobalt_bench_ledger (from_id, to_id, amount) VALUES (?, ?, ?)', { from, to, amount })
	end)
end

local function balances()
	return MySQL.query.await('SELECT id, balance FROM cobalt_bench_accounts ORDER BY id')
end

local function ledger()
	return MySQL.scalar.await('SELECT COUNT(*) FROM cobalt_bench_ledger')
end

Bench.step('money transactions', function()
	MySQL.query.await('DROP TABLE IF EXISTS `cobalt_bench_ledger`, `cobalt_bench_accounts`')
	MySQL.query.await('CREATE TABLE `cobalt_bench_accounts` (`id` INT NOT NULL, `balance` INT NOT NULL, PRIMARY KEY (`id`))')
	MySQL.query.await('CREATE TABLE `cobalt_bench_ledger` (`id` INT NOT NULL AUTO_INCREMENT, `from_id` INT, `to_id` INT, `amount` INT, PRIMARY KEY (`id`))')
	MySQL.insert.await('INSERT INTO cobalt_bench_accounts (id, balance) VALUES (1, 100), (2, 0), (3, 100)')

	report('money.ok', transfer(1, 2, 40))
	report('money.okState', { balances(), ledger() })

	report('money.short', transfer(1, 2, 500))
	report('money.shortState', { balances(), ledger() })

	report('money.sqlFault', transfer(1, 2, 10, 'sql'))
	report('money.sqlFaultState', { balances(), ledger() })

	report('money.luaFault', transfer(1, 2, 10, 'lua'))
	report('money.luaFaultState', { balances(), ledger() })

	report('money.selectInside', MySQL.startTransaction(function(query)
		local rows <const> = query('SELECT balance FROM cobalt_bench_accounts WHERE id = ? FOR UPDATE', { 1 })
		local header <const> = query('UPDATE cobalt_bench_accounts SET balance = balance WHERE id = ?', { 1 })
		report('money.queryShapes', { rows, header })
		return true
	end))

	local results <const> = {}
	local pending = 10

	for i = 1, 10 do
		CreateThread(function()
			results[i] = transfer(3, 2, 30)
			pending -= 1
		end)
	end

	while pending > 0 do Wait(0) end

	local succeeded = 0

	for i = 1, 10 do
		if results[i] then succeeded += 1 end
	end

	report('money.raceSucceeded', succeeded)
	report('money.raceState', { balances(), ledger() })

	MySQL.query.await('DROP TABLE `cobalt_bench_ledger`, `cobalt_bench_accounts`')
end)
