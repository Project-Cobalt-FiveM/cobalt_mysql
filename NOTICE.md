# Notice

cobalt_mysql is a modified work of **oxmysql** by [Linden](https://github.com/thelindat), [Luke](https://github.com/LukeWasTakenn), [Dunak](https://github.com/dunak-debug) and contributors, copyright © 2021-2026. The original source code is available at https://github.com/overextended/oxmysql. oxmysql is licensed under the LGPL-3.0 or later. This work is under the Project Cobalt License in [LICENSE](LICENSE).

## Derived from oxmysql 2.14.3

- `lib/MySQL.lua`: the public Lua surface (`safeArgs`, the query store, the `Sync`/`Async` aliases, `MySQL.ready`, `mysql_option`) is oxmysql's. The query path and `startTransaction` are rewritten to call this resource's `call` export.
- `src/args.ts`: argument parsing ported from `parseArguments`, `parseExecute` and `parseTransaction`.
- `src/config.ts`: connection-string parsing and the type casts ported from `config.ts` and `typeCast.ts`.
- `src/server.ts` and `src/worker.ts`: the export names, the `ghmattimysql` and `mysql-async` aliases, the response shapes and the error, slow-query and transaction-error output follow oxmysql's `index.ts`, `rawQuery.ts`, `rawExecute.ts`, `rawTransaction.ts`, `startTransaction.ts` and `logger/index.ts`.
- `patches/`: oxmysql's patches for mysql2 3.24.5 and named-placeholders 1.1.6, unchanged.

## Modifications

- Queries run on a worker thread that owns the pools. The server thread waits a short, configurable time for the answer and returns it inside the export call when it arrives.
- `MySQL.transaction` sends its statements as multi-statement packets instead of one round trip per statement.
- Multi-set `SELECT` prepares run across several connections.
- `startTransaction` releases its connection when it times out or when the owning resource stops.
- The `/mysql` UI, the logger service and the update check are gone.

## Lumo

The worker-thread design, the inline answer and the chunked transactions follow the architecture described by [Lumo](https://github.com/Kr3mu/lumo). Lumo publishes no licence, so this resource uses none of its code. It was written from scratch.
