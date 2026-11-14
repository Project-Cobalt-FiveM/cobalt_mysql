fx_version 'cerulean'
game 'common'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
node_version '22'

name 'cobalt_mysql'
author 'Project Cobalt'
description 'oxmysql-compatible MariaDB layer with a worker-thread pool and an inline fast path'
version '2.14.3'
license 'Project Cobalt License'

server_script 'dist/server.js'

provide 'oxmysql'
provide 'mysql-async'
provide 'ghmattimysql'

convar_category 'OxMySQL' {
	'Configuration',
	{
		{ 'Connection string', 'mysql_connection_string', 'CV_STRING', 'mysql://user:password@localhost/database' },
		{ 'Debug', 'mysql_debug', 'CV_BOOL', 'false' },
	},
}
