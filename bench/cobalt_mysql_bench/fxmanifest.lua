fx_version 'cerulean'
game 'common'
lua54 'yes'

name 'cobalt_mysql_bench'
author 'Project Cobalt'
description 'Benchmark and return-shape comparison for any oxmysql provider'
version '1.0.0'

dependencies { 'oxmysql', 'ox_lib' }

server_scripts {
	'@ox_lib/init.lua',
	'@oxmysql/lib/MySQL.lua',
	'encode.lua',
	'compat.lua',
	'money.lua',
	'docs.lua',
	'timing.lua',
	'main.lua',
}
