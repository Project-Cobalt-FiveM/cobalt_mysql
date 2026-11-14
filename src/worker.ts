import type { Pool, PoolConnection } from 'mysql2/promise';
import type { Connection as CoreConnection, Query as CoreQuery } from 'mysql2';
import type { Envelope, Failure, Outcome, Port, Request, WorkerSettings } from './protocol';
import type { ParsedStatement } from './args';

import { createPool } from 'mysql2/promise';
import { deserialize, serialize } from 'node:v8';
import { ExecuteType, ParseArguments, ParseExecute, ParseTransaction, SetNamedPlaceholders } from './args';
import { ConnectionOptions, IsolationStatement, MaskedOptions, TypeCastExecute } from './config';
import { Handoff, Op, Slot, State, views } from './protocol';

export interface WorkerData {
  settings: WorkerSettings;
  shared: SharedArrayBuffer;
}

type QueryType = 'insert' | 'update' | 'scalar' | 'single' | null;

interface Session {
  connection: PoolConnection;
  resource: string;
  timer: ReturnType<typeof setTimeout>;
}

interface SyncRequest {
  id: number;
  request: Request;
  sync: boolean;
}

class QueryError extends Error {
  public constructor(
    message: string,
    public readonly stage: Failure['stage'],
    public readonly detail: Partial<Failure> = {},
  ) {
    super(message);
  }
}

let settings: WorkerSettings;
let control: Int32Array;
let requestArea: Buffer;
let replyArea: Buffer;
let port: Port;
let receive: () => { message: unknown } | undefined = () => undefined;
let config: ReturnType<typeof ConnectionOptions>;
let isolation: string;
const retryMs = 30000;
const listenMs = 0.25;
const chunkBytes = 1 << 20;
const sessions = new Map<number, Session>();

let pool: Pool | undefined;
let multiPool: Pool | undefined;
let nextSession = 0;
let inFlight = 0;
let markReady: () => void;
const ready = new Promise<void>((resolve) => (markReady = resolve));

function post(envelope: Envelope) {
  port.postMessage(envelope);
}

function warn(message: string) {
  post({ id: 0, warn: message });
}

function withIsolation(target: Pool) {
  target.pool.on('connection', (connection) => connection.query(isolation));
  return target;
}

async function connect() {
  for (const warning of config.warnings) warn(warning);

  while (!pool) {
    const candidate = withIsolation(createPool(config.options));

    try {
      const [rows] = (await candidate.query('SELECT VERSION() as version')) as [{ version: string }[], unknown];
      pool = candidate;
      multiPool = withIsolation(createPool({ ...config.options, multipleStatements: true }));
      post({ id: 0, ready: rows[0]!.version, multipleStatements: config.options.multipleStatements === true });
      markReady();
    } catch (error) {
      const err = error as { code?: string; errno?: number; message: string };
      const message = err.message.includes('auth_gssapi_client')
        ? 'Requested authentication using unknown plugin auth_gssapi_client.'
        : err.message;

      post({
        id: 0,
        connectFailed: `^3Unable to establish a connection to the database (${err.code})!\n^1Error${err.errno ? ` ${err.errno}` : ''}: ${message}^0`,
        options: JSON.stringify(MaskedOptions({ ...config.options, typeCast: undefined })),
      });
      await candidate.end().catch(() => undefined);
      await new Promise((resolve) => setTimeout(resolve, retryMs));
    }
  }
}

function checkResultSet(resource: string, query: string, rows: unknown) {
  const length = Array.isArray(rows) ? rows.length : 0;
  if (length < settings.resultSetWarning) return;

  warn(`${resource} executed a query with an oversized result set (${length} results)!\n${query}`);
}

function parseResponse(type: QueryType, result: unknown): unknown {
  switch (type) {
    case 'insert':
      return (result as { insertId?: number } | undefined)?.insertId ?? null;
    case 'update':
      return (result as { affectedRows?: number } | undefined)?.affectedRows ?? null;
    case 'single':
      return (result as unknown[] | undefined)?.[0] ?? null;
    case 'scalar': {
      const row = (result as Record<string, unknown>[] | undefined)?.[0];
      return (row && Object.values(row)[0]) ?? null;
    }
    default:
      return result ?? null;
  }
}

const queryTypes: Record<number, QueryType> = {
  [Op.Query]: null,
  [Op.Single]: 'single',
  [Op.Scalar]: 'scalar',
  [Op.Insert]: 'insert',
  [Op.Update]: 'update',
};

function sqlFailure(error: unknown, stage: Failure['stage'], detail: Partial<Failure> = {}): QueryError {
  const err = error as { message?: string; code?: string; errno?: number; sqlState?: string; sql?: string };

  return new QueryError(String(err.message ?? error), stage, {
    code: err.code,
    errno: err.errno,
    sqlState: err.sqlState,
    sql: err.sql,
    ...detail,
  });
}

function parsed<T>(parse: () => T, detail: Partial<Failure>): T {
  try {
    return parse();
  } catch (error) {
    throw new QueryError((error as Error).message, 'parse', detail);
  }
}

async function runQuery(req: Request) {
  const [query, params] = parsed(() => ParseArguments(req.query, req.params), { query: req.query, params: req.params });

  try {
    const [result] = await pool!.query(query, params);
    checkResultSet(req.resource, query, result);
    return parseResponse(queryTypes[req.op]!, result);
  } catch (error) {
    throw sqlFailure(error, 'query', { query, params });
  }
}

function unpackExecute(type: QueryType, response: unknown[]) {
  if (response.length !== 1) return response;

  const first = response[0];
  if (type !== null) return first;

  const row = (first as Record<string, unknown>[])[0];
  if (row && Object.keys(row).length === 1) return Object.values(row)[0];

  return row;
}

const parallelMinimum = 32;
const readOnly = /^\s*SELECT\s/i;

function lanesFor(query: string, runs: number) {
  if (runs < parallelMinimum || !readOnly.test(query)) return 1;

  const limit = Number(config.options.connectionLimit ?? 10);
  return Math.max(1, Math.min(Math.floor(limit / 2), Math.ceil(runs / parallelMinimum)));
}

async function executeLane(
  query: string,
  sets: unknown[][],
  placeholders: number,
  results: unknown[],
  lane: number,
  lanes: number,
) {
  const connection = await pool!.getConnection();

  try {
    for (let index = lane; index < results.length; index += lanes) {
      const values = sets[index];

      if (values && placeholders > values.length) {
        for (let i = values.length; i < placeholders; i++) values[i] = null;
      }

      [results[index]] = await connection.execute({ sql: query, values: values ?? [], typeCast: TypeCastExecute });
    }
  } finally {
    connection.release();
  }
}

async function runExecute(req: Request, unpack: boolean) {
  const [query, type, placeholders, sets] = parsed(
    () => {
      const kind = ExecuteType(req.query);
      const count = (req.query as string).split('?').length - 1;
      return [req.query as string, kind, count, ParseExecute(count, req.params)] as const;
    },
    { query: req.query, params: req.params },
  );

  const results = new Array<unknown>(sets.length === 0 ? 1 : sets.length);
  const lanes = lanesFor(query, results.length);

  try {
    await Promise.all(
      Array.from({ length: lanes }, (_, lane) => executeLane(query, sets, placeholders, results, lane, lanes)),
    );
  } catch (error) {
    throw sqlFailure(error, 'query', { query, params: sets });
  }

  const response: unknown[] = [];

  for (const result of results) {
    if (Array.isArray(result) && result.length > 1) {
      for (const value of result) response.push(unpack ? parseResponse(type, value) : value);
    } else {
      response.push(unpack ? parseResponse(type, result) : result);
    }

    checkResultSet(req.resource, query, result);
  }

  return unpack ? unpackExecute(type, response) : response.length === 1 ? response[0] : response;
}

function trailingSemicolons(sql: string) {
  let end = sql.length;

  while (end > 0) {
    const c = sql.charCodeAt(end - 1);
    if (c !== 59 && c > 32) break;
    end--;
  }

  return end;
}

function isSingleStatement(sql: string, end: number) {
  let quote = 0;

  for (let i = 0; i < end; i++) {
    const c = sql.charCodeAt(i);

    if (quote) {
      if (c === 92 && quote !== 96) i++;
      else if (c === quote) quote = 0;
    } else if (c === 39 || c === 34 || c === 96) {
      quote = c;
    } else if (c === 35 || (c === 45 && sql.charCodeAt(i + 1) === 45 && sql.charCodeAt(i + 2) <= 32)) {
      const newline = sql.indexOf('\n', i);
      if (newline < 0 || newline >= end) return true;
      i = newline;
    } else if (c === 47 && sql.charCodeAt(i + 1) === 42) {
      const close = sql.indexOf('*/', i + 2);
      if (close < 0) return false;
      i = close + 1;
    } else if (c === 59) {
      return false;
    }
  }

  return quote === 0;
}

function chunkable(formatted: string[]) {
  const trimmed: string[] = [];

  for (const sql of formatted) {
    const end = trailingSemicolons(sql);
    if (end === 0 || !isSingleStatement(sql, end)) return null;

    trimmed.push(sql.slice(0, end));
  }

  return trimmed;
}

function chunked(statements: string[]) {
  const chunks: { first: number; sql: string[] }[] = [];
  let current = { first: 0, sql: ['START TRANSACTION'] };
  let bytes = 0;

  statements.forEach((sql, index) => {
    if (bytes + sql.length > chunkBytes && current.sql.length > 0) {
      chunks.push(current);
      current = { first: index, sql: [] };
      bytes = 0;
    }

    current.sql.push(sql);
    bytes += sql.length + 2;
  });

  current.sql.push('COMMIT');
  chunks.push(current);
  return chunks;
}

function coreConnection(connection: PoolConnection): CoreConnection {
  return connection.connection as unknown as CoreConnection;
}

function multiQuery(connection: PoolConnection, sql: string) {
  return new Promise<void>((resolve, reject) => {
    const command: CoreQuery & { _resultIndex?: number } = coreConnection(connection).query(
      sql,
      (error: Error | null) => {
        if (!error) return resolve();

        Object.assign(error, { resultIndex: command._resultIndex ?? 0 });
        reject(error);
      },
    );
  });
}

async function runChunks(statements: string[]) {
  const connection = await multiPool!.getConnection();

  try {
    for (const [position, chunk] of chunked(statements).entries()) {
      try {
        await multiQuery(connection, chunk.sql.join('\n;'));
      } catch (error) {
        const offset = position === 0 ? -1 : 0;
        const failed = statements[chunk.first + (error as { resultIndex: number }).resultIndex + offset];
        await connection.query('ROLLBACK').catch(() => undefined);
        throw sqlFailure(error, 'transaction', { sql: failed });
      }
    }
  } finally {
    connection.release();
  }
}

async function runSequential(statements: ParsedStatement[]) {
  const connection = await pool!.getConnection();

  try {
    await connection.beginTransaction();

    for (const statement of statements) await connection.query(statement.query, statement.params);

    await connection.commit();
  } catch (error) {
    await connection.rollback().catch(() => undefined);
    throw sqlFailure(error, 'transaction');
  } finally {
    connection.release();
  }
}

async function runTransaction(req: Request) {
  const statements = parsed(() => ParseTransaction(req.query, req.params), {});
  const formatted = statements.map((statement) => pool!.format(statement.query, statement.params as unknown[]));
  const simple = chunkable(formatted);

  try {
    if (simple) await runChunks(simple);
    else await runSequential(statements);
  } catch (caught) {
    const error = caught instanceof QueryError ? caught : sqlFailure(caught, 'transaction');
    const fallback = statements
      .map((statement) => `${statement.query} ${JSON.stringify(statement.params || [])}`)
      .join('\n');
    throw new QueryError(error.message, 'transaction', {
      ...error.detail,
      sql: error.detail.sql || `${fallback}\n${JSON.stringify(req.params)}`,
    });
  }

  return true;
}

function discard(id: number, session: Session) {
  clearTimeout(session.timer);
  sessions.delete(id);
  session.connection
    .rollback()
    .catch(() => undefined)
    .finally(() => session.connection.release());
}

async function begin(req: Request) {
  const connection = await pool!.getConnection();

  try {
    await connection.beginTransaction();
  } catch (error) {
    connection.release();
    throw sqlFailure(error, 'session');
  }

  const id = ++nextSession;
  const session: Session = {
    connection,
    resource: req.resource,
    timer: setTimeout(() => discard(id, session), settings.transactionTimeoutMs),
  };

  sessions.set(id, session);
  return id;
}

async function sessionQuery(req: Request) {
  const [query, params] = parsed(() => ParseArguments(req.query, req.params), {});
  const session = sessions.get(req.session);
  const context = () => `Query: ${query}\n${JSON.stringify(params)}\n`;

  if (!session) {
    throw new QueryError(`${context()}Connection used by transaction timed out after 30 seconds.`, 'session');
  }

  try {
    const [result] = await session.connection.query(query, params);
    return result;
  } catch (error) {
    throw sqlFailure(error, 'session', { message: `${context()}${(error as Error).message}` });
  }
}

async function finish(req: Request, commit: boolean) {
  const session = sessions.get(req.session);
  if (!session) throw new QueryError('Transaction has timed out after 30 seconds.', 'session');

  clearTimeout(session.timer);
  sessions.delete(req.session);

  try {
    if (commit) await session.connection.commit();
    else await session.connection.rollback();
  } catch (error) {
    await session.connection.rollback().catch(() => undefined);
    throw sqlFailure(error, 'session');
  } finally {
    session.connection.release();
  }

  return commit;
}

function releaseResource(resource: string) {
  for (const [id, session] of sessions) {
    if (session.resource === resource) discard(id, session);
  }

  return true;
}

function run(req: Request): Promise<unknown> | unknown {
  switch (req.op) {
    case Op.Query:
    case Op.Single:
    case Op.Scalar:
    case Op.Insert:
    case Op.Update:
      return runQuery(req);
    case Op.Prepare:
      return runExecute(req, true);
    case Op.RawExecute:
      return runExecute(req, false);
    case Op.Transaction:
      return runTransaction(req);
    case Op.Begin:
      return begin(req);
    case Op.SessionQuery:
      return sessionQuery(req);
    case Op.Commit:
      return finish(req, true);
    case Op.Rollback:
      return finish(req, false);
    case Op.ReleaseResource:
      return releaseResource(req.resource);
    default: {
      const unknownOp: never = req.op;
      throw new QueryError(`Unknown operation ${unknownOp}`, 'parse');
    }
  }
}

function toFailure(error: unknown): Failure {
  if (error instanceof QueryError)
    return { stage: error.stage, ...error.detail, message: error.detail.message ?? error.message };

  return { stage: 'query', message: String((error as Error)?.message ?? error) };
}

async function handle({ id, request, sync }: SyncRequest) {
  const started = performance.now();
  inFlight++;

  let outcome: Outcome;

  try {
    if (!pool) await ready;
    outcome = { ok: true, value: await run(request), ms: performance.now() - started };
  } catch (error) {
    outcome = { ok: false, failure: toFailure(error), ms: performance.now() - started };
  }

  inFlight--;

  if (sync && replyInline(id, outcome)) {
    if (inFlight === 0) listen();
    return;
  }

  post({ id, outcome });
}

function replyInline(id: number, outcome: Outcome) {
  if (Atomics.load(control, Slot.State) !== id) return false;

  const bytes = serialize(outcome);

  if (bytes.length > replyArea.length) {
    if (Atomics.compareExchange(control, Slot.State, id, State.Posted) === id) Atomics.notify(control, Slot.State);
    return false;
  }

  bytes.copy(replyArea, 0);
  control[Slot.ReplyLength] = bytes.length;

  if (Atomics.compareExchange(control, Slot.State, id, State.Done) !== id) return false;

  Atomics.notify(control, Slot.State);
  return true;
}

function listen() {
  Atomics.store(control, Slot.Handoff, Handoff.Listening);

  const until = performance.now() + listenMs;
  let message: { message: SyncRequest } | undefined;

  for (let spins = 1; ; spins++) {
    const handoff = Atomics.load(control, Slot.Handoff);

    if (handoff === Handoff.Ready) {
      const length = control[Slot.RequestLength]!;
      const next = deserialize(requestArea.subarray(0, length)) as SyncRequest;
      Atomics.store(control, Slot.Handoff, Handoff.Idle);
      if (message) handle(message.message);
      handle(next);
      return;
    }

    if (handoff !== Handoff.Listening || (spins & 127) !== 0) continue;

    message ??= receive() as { message: SyncRequest } | undefined;

    if (
      (message || performance.now() >= until) &&
      Atomics.compareExchange(control, Slot.Handoff, Handoff.Listening, Handoff.Idle) === Handoff.Listening
    ) {
      break;
    }
  }

  if (message) handle(message.message);
}

export function Serve(target: Port, data: WorkerData, poll?: typeof receive) {
  port = target;
  if (poll) receive = poll;
  settings = data.settings;
  ({ control, request: requestArea, reply: replyArea } = views(data.shared));
  config = ConnectionOptions(settings.connectionString);
  isolation = IsolationStatement(settings.isolationLevel);
  SetNamedPlaceholders(config.namedPlaceholders);

  port.on('message', handle);
  connect();
}
