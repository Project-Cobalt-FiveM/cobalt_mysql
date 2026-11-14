---@meta

---@class CobaltMySQLExports
local CobaltMySQLExports = {}

---**Server.** Runs one operation for `@oxmysql/lib/MySQL.lua` and returns `{ value }` or `{ nil, error }`, inline when the answer arrives within `mysql_inline_budget_ms`.
---@param op integer 0 query, 1 single, 2 scalar, 3 insert, 4 update, 5 prepare, 6 rawExecute, 7 transaction, 8 begin, 9 query inside a transaction
---@param query string|table|nil
---@param parameters table|nil
---@param resource string the calling resource, used in logs
---@param isPromise boolean true when the caller raises or returns the error instead of having it printed
---@param session integer startTransaction session id, or 0
---@param deferred? boolean skip the inline wait
---@return table reply
function CobaltMySQLExports:call(op, query, parameters, resource, isPromise, session, deferred) end

---**Server.** Commits or rolls back a `startTransaction` session and returns whether it committed.
---@param session integer
---@param commit boolean
---@param resource string
---@param scriptError? string the error that ended the transaction function
---@return boolean committed
function CobaltMySQLExports:endTransaction(session, commit, resource, scriptError) end

---**Server.** oxmysql's callback form, kept for scripts that call `exports.oxmysql` directly.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function CobaltMySQLExports:query(query, parameters, cb) end

---**Server.** As `query`, returning the first row.
---@param query string
---@param parameters? table
---@param cb? fun(row: table?, err?: string)
function CobaltMySQLExports:single(query, parameters, cb) end

---**Server.** As `query`, returning the first column of the first row.
---@param query string
---@param parameters? table
---@param cb? fun(value: any, err?: string)
function CobaltMySQLExports:scalar(query, parameters, cb) end

---**Server.** As `query`, returning the insert id.
---@param query string
---@param parameters? table
---@param cb? fun(insertId: integer?, err?: string)
function CobaltMySQLExports:insert(query, parameters, cb) end

---**Server.** As `query`, returning the affected row count.
---@param query string
---@param parameters? table
---@param cb? fun(affectedRows: integer?, err?: string)
function CobaltMySQLExports:update(query, parameters, cb) end

---**Server.** Runs a prepared statement once per parameter set.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function CobaltMySQLExports:prepare(query, parameters, cb) end

---**Server.** As `prepare`, returning mysql2's raw results.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function CobaltMySQLExports:rawExecute(query, parameters, cb) end

---**Server.** Runs every statement in one transaction and passes whether it committed.
---@param queries table
---@param parameters? table
---@param cb? fun(committed: boolean)
function CobaltMySQLExports:transaction(queries, parameters, cb) end

---**Server.** Runs `fn` on one connection inside a transaction; it commits unless `fn` returns `false` or errors.
---@param fn fun(query: fun(sql: string, values?: table): any): boolean?
---@return boolean committed
function CobaltMySQLExports:startTransaction(fn) end

---**Server.** Whether the pool has connected.
---@return boolean
function CobaltMySQLExports:isReady() end

---**Server.** Waits until the pool has connected.
---@return true
function CobaltMySQLExports:awaitConnection() end

---**Server.** Passes `query` back unchanged, for mysql-async's `store`.
---@param query string
---@param cb fun(query: string)
function CobaltMySQLExports:store(query, cb) end

---**Server.** As `query`; oxmysql's older name.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function CobaltMySQLExports:execute(query, parameters, cb) end

---**Server.** As `query`; oxmysql's older name.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function CobaltMySQLExports:fetch(query, parameters, cb) end

---**Server.** As `query`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:query_async(query, parameters) end

---**Server.** As `query`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:querySync(query, parameters) end

---**Server.** As `single`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return table?
function CobaltMySQLExports:single_async(query, parameters) end

---**Server.** As `single`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return table?
function CobaltMySQLExports:singleSync(query, parameters) end

---**Server.** As `scalar`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:scalar_async(query, parameters) end

---**Server.** As `scalar`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:scalarSync(query, parameters) end

---**Server.** As `insert`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return integer?
function CobaltMySQLExports:insert_async(query, parameters) end

---**Server.** As `insert`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return integer?
function CobaltMySQLExports:insertSync(query, parameters) end

---**Server.** As `update`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return integer?
function CobaltMySQLExports:update_async(query, parameters) end

---**Server.** As `update`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return integer?
function CobaltMySQLExports:updateSync(query, parameters) end

---**Server.** As `prepare`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:prepare_async(query, parameters) end

---**Server.** As `prepare`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:prepareSync(query, parameters) end

---**Server.** As `rawExecute`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:rawExecute_async(query, parameters) end

---**Server.** As `rawExecute`, returning the result to an awaiting caller and raising on error.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:rawExecuteSync(query, parameters) end

---**Server.** As `transaction`, returning the result to an awaiting caller and raising on error.
---@param queries table
---@param parameters? table
---@return boolean
function CobaltMySQLExports:transaction_async(queries, parameters) end

---**Server.** As `transaction`, returning the result to an awaiting caller and raising on error.
---@param queries table
---@param parameters? table
---@return boolean
function CobaltMySQLExports:transactionSync(queries, parameters) end

---**Server.** As `query_async`; `execute` is oxmysql's older name for `query`.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:execute_async(query, parameters) end

---**Server.** As `querySync`; `execute` is oxmysql's older name for `query`.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:executeSync(query, parameters) end

---**Server.** As `query_async`; `fetch` is oxmysql's older name for `query`.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:fetch_async(query, parameters) end

---**Server.** As `querySync`; `fetch` is oxmysql's older name for `query`.
---@param query string
---@param parameters? table
---@return any
function CobaltMySQLExports:fetchSync(query, parameters) end

---**Server.** As `isReady`, returned to an awaiting caller.
---@return boolean
function CobaltMySQLExports:isReady_async() end

---**Server.** As `isReady`, returned to an awaiting caller.
---@return boolean
function CobaltMySQLExports:isReadySync() end

---**Server.** As `awaitConnection`, returned to an awaiting caller.
---@return true
function CobaltMySQLExports:awaitConnection_async() end

---**Server.** As `awaitConnection`, returned to an awaiting caller.
---@return true
function CobaltMySQLExports:awaitConnectionSync() end

---**Server.** As `startTransaction`, returned to an awaiting caller.
---@param fn fun(query: fun(sql: string, values?: table): any): boolean?
---@return boolean committed
function CobaltMySQLExports:startTransaction_async(fn) end

---**Server.** As `store`, returned to an awaiting caller.
---@param query string
---@param cb fun(query: string)
function CobaltMySQLExports:store_async(query, cb) end

---**Server.** As `startTransaction`, returned to an awaiting caller.
---@param fn fun(query: fun(sql: string, values?: table): any): boolean?
---@return boolean committed
function CobaltMySQLExports:startTransactionSync(fn) end

---**Server.** As `store`, returned to an awaiting caller.
---@param query string
---@param cb fun(query: string)
function CobaltMySQLExports:storeSync(query, cb) end

---`exports.oxmysql`, which cobalt_mysql provides with the same surface.
---@class OxmysqlExports : CobaltMySQLExports

---`exports.ghmattimysql`, which cobalt_mysql provides.
---@class GhmattimysqlExports
local GhmattimysqlExports = {}

---**Server.** As cobalt_mysql's `query`.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function GhmattimysqlExports:execute(query, parameters, cb) end

---**Server.** As cobalt_mysql's `query_async`.
---@param query string
---@param parameters? table
---@return any
function GhmattimysqlExports:executeSync(query, parameters) end

---**Server.** As cobalt_mysql's `scalar`.
---@param query string
---@param parameters? table
---@param cb? fun(value: any, err?: string)
function GhmattimysqlExports:scalar(query, parameters, cb) end

---**Server.** As cobalt_mysql's `scalar_async`.
---@param query string
---@param parameters? table
---@return any
function GhmattimysqlExports:scalarSync(query, parameters) end

---**Server.** As cobalt_mysql's `transaction`.
---@param queries table
---@param parameters? table
---@param cb? fun(committed: boolean)
function GhmattimysqlExports:transaction(queries, parameters, cb) end

---**Server.** As cobalt_mysql's `transaction_async`.
---@param queries table
---@param parameters? table
---@return boolean committed
function GhmattimysqlExports:transactionSync(queries, parameters) end

---**Server.** As cobalt_mysql's `store`.
---@param query string
---@param cb fun(query: string)
function GhmattimysqlExports:store(query, cb) end

---**Server.** As cobalt_mysql's `store_async`.
---@param query string
---@param cb fun(query: string)
function GhmattimysqlExports:storeSync(query, cb) end

---`exports['mysql-async']`, which cobalt_mysql provides.
---@class MysqlAsyncExports
local MysqlAsyncExports = {}

---**Server.** As cobalt_mysql's `isReady`: whether the database connection is up. mysql-async's `MySQL.ready` polls it.
---@return boolean
function MysqlAsyncExports:is_ready() end

---**Server.** As cobalt_mysql's `update`.
---@param query string
---@param parameters? table
---@param cb? fun(affectedRows: integer?, err?: string)
function MysqlAsyncExports:mysql_execute(query, parameters, cb) end

---**Server.** As cobalt_mysql's `insert`.
---@param query string
---@param parameters? table
---@param cb? fun(insertId: integer?, err?: string)
function MysqlAsyncExports:mysql_insert(query, parameters, cb) end

---**Server.** As cobalt_mysql's `query`.
---@param query string
---@param parameters? table
---@param cb? fun(result: any, err?: string)
function MysqlAsyncExports:mysql_fetch_all(query, parameters, cb) end

---**Server.** As cobalt_mysql's `scalar`.
---@param query string
---@param parameters? table
---@param cb? fun(value: any, err?: string)
function MysqlAsyncExports:mysql_fetch_scalar(query, parameters, cb) end

---**Server.** As cobalt_mysql's `transaction`.
---@param queries table
---@param parameters? table
---@param cb? fun(committed: boolean)
function MysqlAsyncExports:mysql_transaction(queries, parameters, cb) end

---**Server.** As cobalt_mysql's `store`.
---@param query string
---@param cb fun(query: string)
function MysqlAsyncExports:mysql_store(query, cb) end
