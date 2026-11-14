local rounds <const> = 5

---@param name string
---@param calls integer
---@param fn fun(i: integer)
local function measure(name, calls, fn)
	local perCall <const> = {}

	for round = 1, rounds do
		local start <const> = os.nanotime()

		for i = 1, calls do fn(i) end

		perCall[round] = (os.nanotime() - start) / 1e3 / calls
	end

	table.sort(perCall)
	print(('BENCH micro | %s | median %.1f us | min %.1f us | max %.1f us | %d calls x %d rounds'):format(name, perCall[(rounds + 1) // 2], perCall[1], perCall[rounds], calls, rounds))
end

Bench.step('small reads and writes', function()
	MySQL.query.await('DROP TABLE IF EXISTS `cobalt_bench_players`')
	MySQL.query.await([[CREATE TABLE `cobalt_bench_players` (
		`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
		`license` VARCHAR(64) NOT NULL,
		`money` INT NOT NULL DEFAULT 0,
		PRIMARY KEY (`id`),
		UNIQUE KEY `license` (`license`)
	)]])

	local rows <const> = {}

	for i = 1, 2000 do rows[i] = { ('INSERT INTO `cobalt_bench_players` (license, money) VALUES (?, ?)'), { 'license:' .. i, i } } end

	MySQL.transaction.await(rows)

	measure('scalar.await', 2000, function(i) MySQL.scalar.await('SELECT money FROM cobalt_bench_players WHERE id = ?', { i }) end)
	measure('single.await', 2000, function(i) MySQL.single.await('SELECT * FROM cobalt_bench_players WHERE id = ?', { i }) end)
	measure('query.await', 2000, function(i) MySQL.query.await('SELECT * FROM cobalt_bench_players WHERE id = ?', { i }) end)
	measure('query.await by license', 2000, function(i) MySQL.query.await('SELECT id, money FROM cobalt_bench_players WHERE license = ?', { 'license:' .. i }) end)
	measure('prepare.await', 2000, function(i) MySQL.prepare.await('SELECT money FROM cobalt_bench_players WHERE id = ?', { i }) end)
	measure('update.await', 300, function(i) MySQL.update.await('UPDATE cobalt_bench_players SET money = money + 1 WHERE id = ?', { i }) end)

	local next = 100000

	measure('insert.await (single row)', 300, function()
		next += 1
		MySQL.insert.await('INSERT INTO cobalt_bench_players (license, money) VALUES (?, ?)', { 'license:' .. next, 0 })
	end)

	local batch <const> = {}

	for i = 1, 10000 do batch[i] = { 'INSERT INTO `cobalt_bench_players` (license, money) VALUES (?, ?)', { 'bulk:' .. i, i } } end

	local start <const> = os.nanotime()
	local committed <const> = MySQL.transaction.await(batch)
	print(('BENCH micro | 10k inserts in one MySQL.transaction | %.3f ms | %s'):format((os.nanotime() - start) / 1e6, tostring(committed)))

	measure('startTransaction (read + guarded write)', 300, function(i)
		MySQL.startTransaction(function(query)
			local row <const> = query('SELECT money FROM cobalt_bench_players WHERE id = ? FOR UPDATE', { i })[1]
			return query('UPDATE cobalt_bench_players SET money = ? WHERE id = ? AND money = ?', { row.money - 1, i, row.money }).affectedRows == 1
		end)
	end)

	MySQL.query.await('DROP TABLE `cobalt_bench_players`')
end)
