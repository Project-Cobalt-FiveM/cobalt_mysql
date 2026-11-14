import createCompiler from 'named-placeholders';

export type Params = unknown[];
export type NamedConverter = (query: string, params: Record<string, unknown>) => [string, unknown[]];
export type ExecuteType = 'insert' | 'update' | null;

export interface ParsedStatement {
  query: string;
  params: Params;
}

let convertNamed: NamedConverter | null = null;

export function SetNamedPlaceholders(enabled: boolean) {
  convertNamed = enabled ? (createCompiler() as NamedConverter) : null;
}

const placeholderPattern = /\?(?!\?)/g;

export function ParseArguments(query: unknown, params?: unknown): [string, Params] {
  if (typeof query !== 'string') throw new Error(`Expected query to be a string but received ${typeof query} instead.`);

  let sql = query;
  let values = params;

  if (
    convertNamed &&
    values &&
    typeof values === 'object' &&
    !Array.isArray(values) &&
    (sql.includes(':') || sql.includes('@'))
  ) {
    [sql, values] = convertNamed(sql, values as Record<string, unknown>);
  }

  if (!values || typeof values === 'function') values = [];

  const placeholders = sql.match(placeholderPattern)?.length ?? 0;

  if (!Array.isArray(values)) {
    const keyed = values as Record<number, unknown>;
    const list: unknown[] = [];

    for (let i = 0; i < placeholders; i++) list[i] = keyed[i + 1] ?? null;

    return [sql, list];
  }

  if (!placeholders) return [sql, values];

  const missing = placeholders - values.length;

  if (missing > 0) return [sql, [...values, ...new Array(missing).fill(null)]];
  if (missing < 0) throw new Error(`Expected ${placeholders} parameters, but received ${values.length}.`);

  return [sql, values];
}

export function ExecuteType(query: unknown): ExecuteType {
  if (typeof query !== 'string') throw new Error(`Expected query to be a string but received ${typeof query} instead.`);

  switch (query.substring(0, query.indexOf(' '))) {
    case 'INSERT':
      return 'insert';
    case 'UPDATE':
    case 'DELETE':
      return 'update';
    default:
      return null;
  }
}

function fromKeyed(value: object) {
  const list: unknown[] = [];

  for (const [key, entry] of Object.entries(value)) list[Number.parseInt(key) - 1] = entry;

  return list;
}

export function ParseExecute(placeholders: number, params: unknown): unknown[][] {
  if (!params || typeof params !== 'object') return [];

  const list = Array.isArray(params) ? params : fromKeyed(params);

  if (list.every(Array.isArray)) return list as unknown[][];
  if (!list.every((item) => typeof item === 'object')) return [[...list]];

  return list.map((value) => {
    const row: unknown[] = Array.isArray(value)
      ? value
      : Object.assign(new Array(placeholders), fromKeyed(value as object));

    for (let i = 0; i < placeholders; i++) {
      if (row[i] === undefined) row[i] = null;
    }

    return row;
  });
}

interface KeyedStatement {
  query: string;
  parameters?: unknown;
  values?: unknown;
}

function isKeyedStatement(value: unknown): value is KeyedStatement {
  return typeof value === 'object' && value !== null && (value as KeyedStatement).query !== undefined;
}

export function ParseTransaction(queries: unknown, params: unknown): ParsedStatement[] {
  if (!Array.isArray(queries)) throw new Error(`Transaction queries must be array, received '${typeof queries}'.`);

  const shared = !params || typeof params === 'function' ? [] : params;

  if (Array.isArray(queries[0])) {
    return queries.map((entry: unknown[]) => {
      if (typeof entry[1] !== 'object')
        throw new Error(`Transaction parameters must be array or object, received '${typeof entry[1]}'.`);

      const [query, values] = ParseArguments(entry[0], entry[1]);
      return { query, params: values };
    });
  }

  return queries.map((entry: unknown) => {
    const [query, values] = isKeyedStatement(entry)
      ? ParseArguments(entry.query, entry.parameters || entry.values)
      : ParseArguments(entry, shared);

    return { query, params: values };
  });
}
