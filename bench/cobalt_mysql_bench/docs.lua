local docsTotal = 0

local function execQuery(msg, fn, query, parameters)
	local start <const> = os.nanotime()
	local result <const> = fn(query, parameters)
	local elapsed <const> = (os.nanotime() - start) / 1e6

	docsTotal += elapsed
	print(('BENCH docs | %s | %d queries | %.3f ms'):format(msg, type(query) == 'string' and 1 or #query, elapsed))

	return result
end

Bench.step('oxmysql documentation benchmark', function()
	MySQL.query.await('CREATE TABLE IF NOT EXISTS `test_table` (`id` INT UNSIGNED NOT NULL AUTO_INCREMENT, PRIMARY KEY (`id`))')
	docsTotal = 0

	local initTable <const> = {
		'DROP TABLE `test_table`',
		[[CREATE TABLE `test_table` (
		`id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
		`username` VARCHAR(50) NOT NULL DEFAULT '0',
		`identifier` VARCHAR(50) NOT NULL DEFAULT '0',
		PRIMARY KEY (`id`)
		)]],
		'TRUNCATE `test_table`',
		'ALTER TABLE `test_table` AUTO_INCREMENT = 1',
	}

	Bench.report('docs.init', execQuery('initialise test_table', MySQL.transaction.await, initTable))

	local queries = {
		{ query = 'INSERT INTO `test_table` (identifier) VALUES (?)', values = { 'abcdef1' } },
		{ query = 'UPDATE `test_table` SET `username` = ? WHERE `id` = LAST_INSERT_ID()', values = { 'bob1' } },
	}

	Bench.report('docs.tx1', execQuery('{ query: string, values: string }[] transaction', MySQL.transaction.await, queries))

	queries = {
		{ 'INSERT INTO `test_table` (identifier) VALUES (?)', { 'abcdef2' } },
		{ 'UPDATE `test_table` SET `username` = ? WHERE `id` = LAST_INSERT_ID()', { 'bob2' } },
	}

	Bench.report('docs.tx2', execQuery('[string, any[]][] transaction', MySQL.transaction.await, queries))

	queries = {
		'INSERT INTO `test_table` (identifier) VALUES ("abcdef3")',
		'UPDATE `test_table` SET `username` = "bob3" WHERE `id` = LAST_INSERT_ID()',
	}

	Bench.report('docs.tx3', execQuery('string[] transaction', MySQL.transaction.await, queries))

	local insertUsers <const> = {}

	for i = 1, 10000 do
		insertUsers[i] = { 'INSERT INTO `test_table` (username, identifier) VALUES (?, ?)', { 'Testuser_' .. i, 'abcdef' .. i } }
	end

	Bench.report('docs.tx10k', execQuery('insert ' .. #insertUsers .. ' test users', MySQL.transaction.await, insertUsers))

	local selectUserIds <const> = {}

	for i = 1, 10000 do
		if i % 4 == 0 then
			selectUserIds[math.tointeger(i / 4)] = { 'abcdef' .. i }
		end
	end

	local selected <const> = execQuery('select every 4th userid', MySQL.prepare.await, 'SELECT `id` FROM `test_table` WHERE `identifier` = ? LIMIT 1', selectUserIds)
	Bench.report('docs.select4th.count', #selected)
	Bench.report('docs.select4th.first', selected[1])
	Bench.report('docs.select4th.last', selected[#selected])

	local insertid <const> = execQuery('insert', MySQL.insert.await, 'INSERT INTO `test_table` (identifier) VALUES (?)', { 'abcdef' })
	local update <const> = execQuery('update', MySQL.update.await, 'UPDATE `test_table` SET `username` = ? WHERE `id` = ?', { 'bobby', insertid })
	local scalar <const> = execQuery('scalar', MySQL.scalar.await, 'SELECT `username` FROM `test_table` WHERE `id` = ?', { insertid })
	local single <const> = execQuery('single', MySQL.single.await, 'SELECT * FROM `test_table` WHERE `id` = ?', { insertid })
	local prepared <const> = execQuery('prepare', MySQL.prepare.await, 'SELECT `username` FROM `test_table` WHERE `id` = ?', { insertid })

	Bench.report('docs.results', { insertid, update, scalar, single, prepared })
	Bench.report('docs.query', execQuery('query', MySQL.query.await, 'SELECT `username` FROM `test_table` WHERE `id` = ? LIMIT 1', { 419 }))

	print(('BENCH docs | total | %.3f ms'):format(docsTotal))
end)
