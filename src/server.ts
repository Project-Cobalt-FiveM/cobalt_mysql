import type { Envelope, Failure, Outcome, Request } from './protocol';

import { ParseArguments, SetNamedPlaceholders } from './args';
import { Call, Send, Start } from './bridge';
import { ConnectionOptions } from './config';
import { Op, lastPublicOp } from './protocol';

type Answer = [unknown] | [null, string];
type Callback = (result: unknown, error?: string) => void;
type SessionQuery = (query: string, params?: unknown) => Promise<unknown>;

const resourceName = GetCurrentResourceName();
const connectionString =
  GetConvar('mysql_connection_string', '') || process.env.DB_CONNECTION || 'mysql://root@localhost';
const inlineBudgetMs = Math.max(0, GetConvarInt('mysql_inline_budget_ms', 2));

let slowQueryMs = 200;
let debug: boolean | string[] = false;
let dbVersion = '';
let connected = false;
let markConnected: () => void;
const connectionReady = new Promise<void>((resolve) => (markConnected = resolve));

function readDebug() {
  slowQueryMs = GetConvarInt('mysql_slow_query_warning', 200);

  try {
    const value = GetConvar('mysql_debug', 'false');
    debug = value === 'false' ? false : JSON.parse(value);
  } catch {
    debug = true;
  }
}

function debugging(resource: string) {
  return debug === true || (Array.isArray(debug) && debug.includes(resource));
}

function statementCount(request: Request) {
  if (request.op === Op.Transaction) return Array.isArray(request.query) ? Math.max(1, request.query.length) : 1;
  if (request.op !== Op.Prepare && request.op !== Op.RawExecute) return 1;
  if (!Array.isArray(request.params) || !request.params.every(Array.isArray)) return 1;

  return Math.max(1, request.params.length);
}

function describe(request: Request, count: number): [string, unknown] {
  if (request.op === Op.Transaction) return [`TRANSACTION (${count} statements)`, undefined];
  if (request.op === Op.Prepare || request.op === Op.RawExecute) return [String(request.query), request.params];

  try {
    return ParseArguments(request.query, request.params);
  } catch {
    return [String(request.query), request.params];
  }
}

function logQuery(request: Request, ms: number) {
  const count = statementCount(request);
  if (ms / count < slowQueryMs && !debugging(request.resource)) return;

  const [query, params] = describe(request, count);
  console.log(`${dbVersion} ^3${request.resource} took ${ms.toFixed(4)}ms to execute a query!
${query}${params ? ` ${JSON.stringify(params)}` : ''}^0`);
}

function cleanMessage(error: Failure | string) {
  return typeof error === 'object' ? error.message : error.replace(/SCRIPT ERROR: citizen:[\w/.]+:\d+[:\s]+/, '');
}

function logError(
  resource: string,
  isPromise: boolean,
  error: Failure | string,
  query?: unknown,
  params?: unknown,
  withParams = false,
) {
  const message = cleanMessage(error);
  const output = `${resource} was unable to execute a query!${query ? `\nQuery: ${query}` : ''}${withParams ? `\n${JSON.stringify(params)}` : ''}\n${message}`;

  TriggerEvent('oxmysql:error', { query, parameters: params, message, err: error, resource });

  if (!isPromise) console.error(output);
  return output;
}

function logTransactionError(request: Request, failure: Failure) {
  const message = `${request.resource} was unable to complete a transaction!\n${failure.sql}\n${failure.message}`;

  console.error(message);
  TriggerEvent('oxmysql:transaction-error', {
    query: failure.sql,
    parameters: request.params,
    message: failure.message,
    err: failure,
    resource: request.resource,
  });
}

function isQueryOp(op: Op) {
  return op <= Op.Update;
}

function answer(request: Request, isPromise: boolean, outcome: Outcome): Answer {
  if (outcome.ok) {
    if (request.op !== Op.SessionQuery) logQuery(request, outcome.ms);
    return [outcome.value];
  }

  const { failure } = outcome;

  if (request.op === Op.Transaction && failure.stage === 'transaction') {
    logTransactionError(request, failure);
    return [false];
  }

  if (request.op === Op.SessionQuery) return [null, failure.message];

  const withParams = isQueryOp(request.op) && failure.stage === 'query';
  return [null, logError(request.resource, isPromise, failure, failure.query, failure.params, withParams)];
}

function dispatch(request: Request, isPromise: boolean, inline: boolean): Answer | Promise<Answer> {
  const outcome = inline ? Call(request, inlineBudgetMs) : Send(request);

  if (outcome instanceof Promise) return outcome.then((result) => answer(request, isPromise, result));
  return answer(request, isPromise, outcome);
}

function toRequest(op: unknown, query: unknown, params: unknown, resource: unknown, session: unknown): Request | null {
  if (typeof op !== 'number' || !Number.isInteger(op) || op < 0 || op > lastPublicOp) return null;

  return {
    op,
    query,
    params: params ?? null,
    resource: typeof resource === 'string' ? resource : GetInvokingResource() || resourceName,
    session: typeof session === 'number' ? session : 0,
  };
}

function call(
  op: unknown,
  query: unknown,
  params: unknown,
  resource: unknown,
  isPromise: unknown,
  session: unknown,
  deferred: unknown,
) {
  const request = toRequest(op, query, params, resource, session);
  if (!request) return [null, `${resourceName}: unknown operation ${op}`];

  return dispatch(request, isPromise === true, deferred !== true);
}

function endTransaction(
  session: unknown,
  commit: unknown,
  resource: unknown,
  scriptError: unknown,
): boolean | Promise<boolean> {
  const owner = typeof resource === 'string' ? resource : GetInvokingResource() || resourceName;
  const failed = typeof scriptError === 'string';
  const op = failed || commit === false ? Op.Rollback : Op.Commit;
  const outcome = Call(
    { op, query: null, params: null, resource: owner, session: typeof session === 'number' ? session : 0 },
    inlineBudgetMs,
  );

  const settle = (result: Outcome) => {
    if (failed) {
      logError(owner, false, scriptError);
      return false;
    }

    if (!result.ok) {
      logError(owner, false, result.failure);
      return false;
    }

    return result.value === true;
  };

  return outcome instanceof Promise ? outcome.then(settle) : settle(outcome);
}

function invoke(cb: Callback, resource: string, result: unknown, error?: string) {
  try {
    cb(result, error);
  } catch (err) {
    if (typeof err !== 'string') return;
    if (err.includes('SCRIPT ERROR:')) return console.log(err);

    console.log(`^1SCRIPT ERROR in invoking resource ${resource}: ${err}^0`);
  }
}

function pickCallback(params: unknown, cb: unknown): Callback | undefined {
  if (typeof cb === 'function') return cb as Callback;
  if (typeof params === 'function') return params as Callback;
}

function classic(op: Op) {
  return (
    query: unknown,
    params: unknown = [],
    cb?: unknown,
    invokingResource = GetInvokingResource(),
    isPromise?: boolean,
  ) => {
    const callback = pickCallback(params, cb);
    const request: Request = {
      op,
      query,
      params: typeof params === 'function' ? [] : params,
      resource: invokingResource,
      session: 0,
    };

    Promise.resolve(dispatch(request, isPromise === true, false)).then(([value, error]) => {
      if (!callback) return;
      if (error === undefined) return invoke(callback, invokingResource, value);
      if (isPromise) invoke(callback, invokingResource, null, error);
    });
  };
}

async function startTransaction(
  transactions: (query: SessionQuery) => Promise<boolean>,
  invokingResource = GetInvokingResource(),
) {
  const opened = await Send({ op: Op.Begin, query: null, params: null, resource: invokingResource, session: 0 });

  if (!opened.ok) {
    logError(invokingResource, false, opened.failure);
    return false;
  }

  const session = opened.value as number;
  const query: SessionQuery = async (sql, values) => {
    const [result, error] = await dispatch(
      { op: Op.SessionQuery, query: sql, params: values, resource: invokingResource, session },
      true,
      false,
    );
    if (error !== undefined) throw new Error(error);
    return result;
  };

  try {
    const commit = await transactions(query);
    return endTransaction(session, commit !== false, invokingResource, undefined);
  } catch (error) {
    return endTransaction(session, false, invokingResource, error instanceof Error ? error.message : String(error));
  }
}

function asPromise(method: ReturnType<typeof classic>) {
  return (query: unknown, params: unknown = [], invokingResource = GetInvokingResource()) =>
    new Promise((resolve, reject) => {
      method(
        query,
        params,
        (result: unknown, error?: string) => (error ? reject(new Error(error)) : resolve(result)),
        invokingResource,
        true,
      );
    });
}

const store = (query: string, cb: (value: string) => void) => cb(query);
const awaitConnection = async () => {
  await connectionReady;
  return true;
};

const queryMethods = {
  query: classic(Op.Query),
  single: classic(Op.Single),
  scalar: classic(Op.Scalar),
  update: classic(Op.Update),
  insert: classic(Op.Insert),
  transaction: classic(Op.Transaction),
  prepare: classic(Op.Prepare),
  rawExecute: classic(Op.RawExecute),
};

const surface: Record<string, (...args: never[]) => unknown> = {
  isReady: () => connected,
  awaitConnection,
  ...queryMethods,
  startTransaction,
  store,
  execute: queryMethods.query,
  fetch: queryMethods.query,
};

const ghmattiAliases: Record<string, string> = {
  query: 'execute',
  scalar: 'scalar',
  transaction: 'transaction',
  store: 'store',
};
const mysqlAsyncAliases: Record<string, string> = {
  isReady: 'is_ready',
  update: 'mysql_execute',
  insert: 'mysql_insert',
  query: 'mysql_fetch_all',
  scalar: 'mysql_fetch_scalar',
  transaction: 'mysql_transaction',
  store: 'mysql_store',
};

function provide(resource: string, name: string, fn: Function) {
  on(`__cfx_export_${resource}_${name}`, (setCb: (fn: unknown) => void) => setCb(fn));
}

function register(name: string, fn: Function) {
  exports(name, fn);
  provide('oxmysql', name, fn);
}

const queryFunctions = new Set<Function>(Object.values(queryMethods));

for (const [name, fn] of Object.entries(surface)) {
  register(name, fn);

  const promised = queryFunctions.has(fn)
    ? asPromise(fn as ReturnType<typeof classic>)
    : async (...args: never[]) => fn(...args);
  register(`${name}_async`, promised);
  register(`${name}Sync`, promised);

  if (ghmattiAliases[name]) {
    provide('ghmattimysql', ghmattiAliases[name], fn);
    provide('ghmattimysql', `${ghmattiAliases[name]}Sync`, promised);
  }

  if (mysqlAsyncAliases[name]) provide('mysql-async', mysqlAsyncAliases[name], fn);
}

register('call', call);
register('endTransaction', endTransaction);

function onWorkerEvent(envelope: Exclude<Envelope, { outcome: Outcome }>) {
  if ('ready' in envelope) {
    dbVersion = `^5[${envelope.ready}]`;
    connected = true;
    markConnected();
    console.log(`${dbVersion} ^2Database server connection established!^0`);
    if (envelope.multipleStatements)
      console.warn('multipleStatements is enabled. Used incorrectly, this option may cause SQL injection.');
    return;
  }

  if ('connectFailed' in envelope) {
    console.log(envelope.connectFailed);
    console.log('See https://github.com/overextended/oxmysql/issues/154 for more information.');
    console.log(envelope.options);
    return;
  }

  console.warn(envelope.warn);
}

RegisterCommand(
  'oxmysql_debug',
  (source: number, args: string[]) => {
    if (source !== 0) return console.log('^3This command can only be run server side^0');

    const [action, resource] = args;

    if (action === 'add' && resource) {
      const list = Array.isArray(debug) ? debug : [];
      list.push(resource);
      SetConvar('mysql_debug', JSON.stringify(list));
      readDebug();
      return console.log(`^3Added ${resource} to mysql_debug^0`);
    }

    if (action === 'remove' && resource && Array.isArray(debug) && debug.includes(resource)) {
      const list = debug.filter((entry) => entry !== resource);
      SetConvar('mysql_debug', list.length ? JSON.stringify(list) : 'false');
      readDebug();
      return console.log(`^3Removed ${resource} from mysql_debug^0`);
    }

    console.log('^3Usage: oxmysql_debug add|remove <resource>^0');
  },
  true,
);

on('onResourceStop', (resource: string) => {
  if (resource === resourceName || !connected) return;

  Send({ op: Op.ReleaseResource, query: null, params: null, resource, session: 0 });
});

readDebug();
setInterval(readDebug, 1000);
SetNamedPlaceholders(ConnectionOptions(connectionString).namedPlaceholders);

const threaded = Start(
  {
    connectionString,
    isolationLevel: GetConvarInt('mysql_transaction_isolation_level', 2),
    resultSetWarning: GetConvarInt('mysql_resultset_warning', 1000),
    transactionTimeoutMs: 30000,
  },
  onWorkerEvent,
);

if (!threaded) {
  console.log(
    `^3Queries run on the server thread. Add "add_unsafe_worker_permission ${resourceName}" to server.cfg for the fast path.^0`,
  );
}
