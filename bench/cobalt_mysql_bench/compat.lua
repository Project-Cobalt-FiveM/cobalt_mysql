local report <const> = Bench.report

---@param name string
---@param fn function
local function attempt(name, fn, ...)
	local ok <const>, result <const> = pcall(fn, ...)

	if ok then return report(name, result) end

	report(name .. '.error', (tostring(result):gsub('^.-:%d+: ', '')))
end

local function waitFor(name, start)
	local result
	local done = false

	start(function(...)
		result = table.pack(...)
		done = true
	end)

	local deadline <const> = GetGameTimer() + 5000

	while not done and GetGameTimer() < deadline do Wait(0) end

	report(name, done and result or 'callback never ran')
end

Bench.step('return shapes', function()
	MySQL.query.await('DROP TABLE IF EXISTS `cobalt_bench_types`')
	MySQL.query.await([[CREATE TABLE `cobalt_bench_types` (
		`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
		`name` VARCHAR(32) NULL,
		`flag` TINYINT(1) NULL,
		`small` TINYINT NULL,
		`bits` BIT(1) NULL,
		`wide` BIT(8) NULL,
		`big` BIGINT NULL,
		`ubig` BIGINT UNSIGNED NULL,
		`price` DECIMAL(12, 2) NULL,
		`ratio` DOUBLE NULL,
		`born` DATE NULL,
		`seen` DATETIME NULL,
		`stamp` TIMESTAMP NULL,
		`doc` JSON NULL,
		`blob` BLOB NULL,
		`text` TEXT NULL,
		`raw` VARBINARY(8) NULL,
		PRIMARY KEY (`id`)
	)]])

	local insertSql <const> = [[INSERT INTO cobalt_bench_types
		(name, flag, small, bits, wide, big, ubig, price, ratio, born, seen, stamp, doc, `blob`, `text`, raw)
		VALUES (?, ?, ?, b'1', b'10100101', ?, ?, ?, ?, ?, ?, ?, ?, UNHEX('00FF10'), ?, UNHEX('0102'))]]

	local firstId <const> = MySQL.insert.await(insertSql, {
		'alpha', true, 7, 9007199254740993, '18446744073709551615', 1234.5, 0.25,
		'2026-01-02', '2026-03-04 05:06:07', '2026-05-06 07:08:09', '{"a":[1,2],"b":"x"}', 'hello',
	})
	report('insert.id', firstId)

	local secondId <const> = MySQL.insert.await('INSERT INTO cobalt_bench_types (name, flag) VALUES (?, ?)', { 'beta', false })
	report('insert.second', secondId - firstId)

	attempt('single.types', function() return MySQL.single.await('SELECT * FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('single.nulls', function() return MySQL.single.await('SELECT * FROM cobalt_bench_types WHERE id = ?', { secondId }) end)
	attempt('prepare.types', function() return MySQL.prepare.await('SELECT * FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('rawExecute.types', function() return MySQL.rawExecute.await('SELECT * FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('query.rows', function() return MySQL.query.await('SELECT id - ? AS rel, name FROM cobalt_bench_types ORDER BY id', { firstId }) end)
	attempt('query.empty', function() return MySQL.query.await('SELECT * FROM cobalt_bench_types WHERE id = 0') end)
	attempt('single.missing', function() return MySQL.single.await('SELECT * FROM cobalt_bench_types WHERE id = 0') end)
	attempt('scalar.value', function() return MySQL.scalar.await('SELECT name FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('scalar.null', function() return MySQL.scalar.await('SELECT text FROM cobalt_bench_types WHERE id = ?', { secondId }) end)
	attempt('scalar.missing', function() return MySQL.scalar.await('SELECT name FROM cobalt_bench_types WHERE id = 0') end)
	attempt('scalar.zero', function() return MySQL.scalar.await('SELECT 0') end)
	attempt('scalar.false', function() return MySQL.scalar.await('SELECT flag FROM cobalt_bench_types WHERE id = ?', { secondId }) end)
	attempt('query.expressions', function() return MySQL.query.await("SELECT 1 + 1 AS two, 'x' AS s, NULL AS n, 1.5 AS f, CAST(2 AS DECIMAL(5,1)) AS d, NOW() > 0 AS t") end)

	attempt('params.named.colon', function() return MySQL.scalar.await('SELECT name FROM cobalt_bench_types WHERE id = :id', { id = firstId }) end)
	attempt('params.named.at', function() return MySQL.scalar.await('SELECT name FROM cobalt_bench_types WHERE id = @id', { ['@id'] = firstId }) end)
	attempt('params.keyed', function() return MySQL.query.await('SELECT ? AS a, ? AS b, ? AS c', { [1] = 'one', [3] = 'three' }) end)
	attempt('params.missing', function() return MySQL.query.await('SELECT ? AS a, ? AS b', { 'only' }) end)
	attempt('params.array', function() return MySQL.query.await('SELECT name FROM cobalt_bench_types WHERE id IN (?) ORDER BY id', { { firstId, secondId } }) end)
	attempt('params.none', function() return MySQL.scalar.await('SELECT COUNT(*) FROM cobalt_bench_types') end)
	attempt('params.bool', function() return MySQL.query.await('SELECT ? AS t, ? AS f', { true, false }) end)
	attempt('params.table', function() return MySQL.query.await('SELECT ? AS j', { json.encode({ k = 1 }) }) end)
	attempt('params.quote', function() return MySQL.scalar.await('SELECT ?', { "it's \\ \"quoted\"; DROP" }) end)
	attempt('params.questionInString', function() return MySQL.query.await("SELECT '?' AS literal, ? AS bound", { 'v' }) end)

	attempt('update.affected', function() return MySQL.update.await('UPDATE cobalt_bench_types SET small = small WHERE id >= ?', { firstId }) end)
	attempt('update.changed', function() return MySQL.update.await('UPDATE cobalt_bench_types SET small = 3 WHERE id = ?', { secondId }) end)
	attempt('update.none', function() return MySQL.update.await('UPDATE cobalt_bench_types SET small = 3 WHERE id = 0') end)
	attempt('query.headerShape', function() return MySQL.query.await('UPDATE cobalt_bench_types SET small = 4 WHERE id = ?', { secondId }) end)
	attempt('insert.headerViaQuery', function() return MySQL.query.await('INSERT INTO cobalt_bench_types (name) VALUES (?)', { 'gamma' }).affectedRows end)
	attempt('insert.multiRow', function() return MySQL.insert.await('INSERT INTO cobalt_bench_types (name) VALUES ?', { { { 'd1' }, { 'd2' } } }) ~= nil end)

	attempt('prepare.scalar', function() return MySQL.prepare.await('SELECT name FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('prepare.row', function() return MySQL.prepare.await('SELECT id - ? AS rel, name FROM cobalt_bench_types WHERE id = ?', { firstId, firstId }) end)
	attempt('prepare.rows', function() return MySQL.prepare.await('SELECT name FROM cobalt_bench_types WHERE id IN (?, ?) ORDER BY id', { firstId, secondId }) end)
	attempt('prepare.none', function() return MySQL.prepare.await('SELECT name FROM cobalt_bench_types WHERE id = ?', { 0 }) end)
	attempt('prepare.sets', function() return MySQL.prepare.await('SELECT name FROM cobalt_bench_types WHERE id = ?', { { firstId }, { secondId } }) end)
	attempt('prepare.update', function() return MySQL.prepare.await('UPDATE cobalt_bench_types SET small = ? WHERE id = ?', { 5, secondId }) end)
	attempt('prepare.updateSets', function() return MySQL.prepare.await('UPDATE cobalt_bench_types SET small = ? WHERE id = ?', { { 6, firstId }, { 6, secondId } }) end)
	report('prepare.insert', type(MySQL.prepare.await('INSERT INTO cobalt_bench_types (name) VALUES (?)', { 'p' })))
	attempt('prepare.keyed', function() return MySQL.prepare.await('SELECT ? AS a, ? AS b', { [1] = 'x', [2] = 'y' }) end)
	attempt('prepare.lowercase', function() return MySQL.prepare.await('update cobalt_bench_types set small = 1 where id = ?', { secondId }) end)
	attempt('rawExecute.update', function() return MySQL.rawExecute.await('UPDATE cobalt_bench_types SET small = 2 WHERE id = ?', { secondId }) end)
	attempt('rawExecute.sets', function() return MySQL.rawExecute.await('SELECT name FROM cobalt_bench_types WHERE id = ?', { { firstId }, { secondId } }) end)

	attempt('transaction.ok', function() return MySQL.transaction.await({ { 'UPDATE cobalt_bench_types SET small = 8 WHERE id = ?', { firstId } }, { 'SELECT 1', {} } }) end)
	attempt('transaction.mixed', function() return MySQL.transaction.await({ { 'SELECT 1', {} }, 'SELECT 2' }) end)
	attempt('transaction.shared', function() return MySQL.transaction.await({ 'UPDATE cobalt_bench_types SET small = ? WHERE id = ?' }, { 9, firstId }) end)
	attempt('transaction.fail', function()
		return MySQL.transaction.await({
			{ 'UPDATE cobalt_bench_types SET small = 10 WHERE id = ?', { firstId } },
			{ 'INSERT INTO cobalt_bench_types (nope) VALUES (?)', { 1 } },
		})
	end)
	attempt('transaction.failRolledBack', function() return MySQL.scalar.await('SELECT small FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('transaction.semicolon', function() return MySQL.transaction.await({ "UPDATE cobalt_bench_types SET name = 'a;b' WHERE id = " .. secondId .. ';' }) end)
	attempt('transaction.comment', function() return MySQL.transaction.await({ 'UPDATE cobalt_bench_types SET small = 11 WHERE id = ' .. secondId .. ' -- trailing', 'SELECT 2' }) end)
	attempt('transaction.twoStatements', function() return MySQL.transaction.await({ 'SELECT 1; SELECT 2' }) end)
	attempt('transaction.empty', function() return MySQL.transaction.await({}) end)

	attempt('error.await.query', MySQL.query.await, 'SELECT nope FROM cobalt_bench_types WHERE id = ?', { 1 })
	attempt('error.await.prepare', MySQL.prepare.await, 'SELECT nope FROM cobalt_bench_types WHERE id = ?', { 1 })
	attempt('error.await.tooMany', MySQL.query.await, 'SELECT ?', { 1, 2 })
	attempt('error.await.badQuery', MySQL.query.await, 'SELEC 1')
	attempt('error.args', MySQL.query.await, 42)

	waitFor('callback.query', function(done) MySQL.query('SELECT name FROM cobalt_bench_types WHERE id = ?', { firstId }, done) end)
	waitFor('callback.noParams', function(done) MySQL.scalar('SELECT 5', done) end)
	waitFor('callback.insert', function(done) MySQL.insert('INSERT INTO cobalt_bench_types (name) VALUES (?)', { 'cb' }, function(id) done(type(id)) end) end)
	waitFor('callback.transaction', function(done) MySQL.transaction({ 'SELECT 1' }, done) end)
	waitFor('callback.error', function(done)
		MySQL.query('SELECT nope FROM cobalt_bench_types', {}, done)
		SetTimeout(500, function() done('no callback on error') end)
	end)

	local order <const> = {}
	MySQL.update('UPDATE cobalt_bench_types SET small = 12 WHERE id = ?', { firstId }, function() order[#order + 1] = 'callback' end)
	order[#order + 1] = 'after call'
	attempt('callback.firstSmall', function() return MySQL.scalar.await('SELECT small FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	Wait(100)
	report('callback.order', order)

	attempt('alias.fetchAll', function() return MySQL.Sync.fetchAll('SELECT name FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('alias.fetchScalar', function() return MySQL.Sync.fetchScalar('SELECT name FROM cobalt_bench_types WHERE id = ?', { firstId }) end)
	attempt('alias.execute', function() return MySQL.Sync.execute('UPDATE cobalt_bench_types SET small = 13 WHERE id = ?', { firstId }) end)
	local stored <const> = MySQL.Async.store('SELECT name FROM cobalt_bench_types WHERE id = ?')
	attempt('alias.store', function() return MySQL.scalar.await(stored, { firstId }) end)

	attempt('slow.scalar', function() return MySQL.scalar.await('SELECT 7 AS v, SLEEP(0.02) AS s') end)
	attempt('slow.insideTransaction', function()
		return MySQL.startTransaction(function(query)
			report('slow.insideTransaction.rows', query('SELECT SLEEP(0.02) AS s, ? AS v', { 'x' }))
			return true
		end)
	end)
	attempt('large.count', function() return #MySQL.query.await('SELECT seq FROM seq_1_to_5000') end)
	attempt('large.last', function() return MySQL.query.await('SELECT seq FROM seq_1_to_5000')[5000] end)

	local parallel <const> = {}
	local remaining = 20

	for i = 1, 20 do
		CreateThread(function()
			parallel[i] = MySQL.scalar.await('SELECT ? * 2 AS v' .. (i % 3 == 0 and ', SLEEP(0.01) AS s' or ''), { i })
			remaining -= 1
		end)
	end

	while remaining > 0 do Wait(0) end

	report('parallel.results', parallel)

	attempt('ready.await', function() return MySQL.ready.await() end)
	attempt('isReady', function() return MySQL.isReady() end)
	report('state', GetResourceState('oxmysql'))
	report('version', GetResourceMetadata('oxmysql', 'version', 0))
	report('checkDependency', { lib and lib.checkDependency and lib.checkDependency('oxmysql', '2.4.0') })

	MySQL.query.await('DROP TABLE `cobalt_bench_types`')
end)
