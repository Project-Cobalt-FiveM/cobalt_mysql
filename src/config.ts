import type { PoolOptions, TypeCastField, TypeCastNext } from 'mysql2';

type RawOptions = Record<string, unknown>;

const binaryCharset = 63;

function castDate(field: TypeCastField, suffix: string) {
  const value = field.string();
  return value ? new Date(value + suffix).getTime() : null;
}

export function TypeCastExecute(field: TypeCastField, next: TypeCastNext) {
  switch (field.type) {
    case 'DATETIME':
    case 'DATETIME2':
    case 'TIMESTAMP':
    case 'TIMESTAMP2':
    case 'NEWDATE':
      return castDate(field, '');
    case 'DATE':
      return castDate(field, ' 00:00:00');
    default:
      return next();
  }
}

function typeCast(field: TypeCastField & { charset?: number }, next: TypeCastNext) {
  switch (field.type) {
    case 'TINY': {
      if (field.length !== 1) return next();

      const value = field.string();
      return value === null ? null : value === '1';
    }
    case 'BIT': {
      const buffer = field.buffer();
      if (!buffer) return null;

      return buffer.length === 1 ? buffer[0] === 1 : buffer[0];
    }
    case 'TINY_BLOB':
    case 'MEDIUM_BLOB':
    case 'LONG_BLOB':
    case 'BLOB': {
      if (field.charset !== binaryCharset) return field.string();

      const value = field.buffer();
      return value === null ? [value] : [...value];
    }
    default:
      return TypeCastExecute(field, next);
  }
}

const uriPattern =
  /^(?:([^:/?#.]+):)?(?:\/\/(?:([^/?#]*)@)?([\w\d\-Ā-￿.%]*)(?::([0-9]+))?)?([^?#]+)?(?:\?([^#]*))?$/;

function parseUri(connectionString: string): RawOptions {
  const groups = connectionString.match(uriPattern);
  if (!groups) {
    throw new Error('mysql_connection_string is not a valid URI. Use the key=value form if the password contains # or ?.');
  }

  const auth = groups[2] ? groups[2].split(':') : [];
  const query = groups[6] ? Object.fromEntries(groups[6].split('&').map((pair) => pair.split('='))) : {};

  return {
    user: auth[0] || undefined,
    password: auth[1] || undefined,
    host: groups[3],
    port: Number.parseInt(groups[4] ?? ''),
    database: groups[5]?.replace(/^\/+/, ''),
    ...query,
  };
}

function parseKeyValue(connectionString: string): RawOptions {
  return connectionString
    .replace(/(?:host(?:name)|ip|server|data\s?source|addr(?:ess)?)=/gi, 'host=')
    .replace(/(?:user\s?(?:id|name)?|uid)=/gi, 'user=')
    .replace(/(?:pwd|pass)=/gi, 'password=')
    .replace(/(?:db)=/gi, 'database=')
    .split(';')
    .reduce<RawOptions>((options, pair) => {
      const [key, value] = pair.split('=');
      if (key) options[key] = value;
      return options;
    }, {});
}

export interface ConnectionConfig {
  options: PoolOptions;
  namedPlaceholders: boolean;
  warnings: string[];
}

export function ConnectionOptions(connectionString: string): ConnectionConfig {
  const options = connectionString.includes('mysql://') ? parseUri(connectionString) : parseKeyValue(connectionString);
  const warnings: string[] = [];

  for (const key of ['dateStrings', 'flags', 'ssl']) {
    const value = options[key];
    if (typeof value !== 'string') continue;

    try {
      options[key] = JSON.parse(value);
    } catch (error) {
      warnings.push(`^3Failed to parse property ${key} in configuration (${error})!^0`);
    }
  }

  const flags = Array.isArray(options.flags) ? (options.flags as string[]) : [];
  flags.push(options.database ? 'CONNECT_WITH_DB' : '-CONNECT_WITH_DB');

  return {
    namedPlaceholders: options.namedPlaceholders !== 'false',
    warnings,
    options: {
      connectTimeout: 60000,
      trace: false,
      supportBigNumbers: true,
      jsonStrings: true,
      ...options,
      typeCast,
      namedPlaceholders: false,
      flags,
    } as PoolOptions,
  };
}

export function IsolationStatement(level: number) {
  const statement = 'SET SESSION TRANSACTION ISOLATION LEVEL';

  switch (level) {
    case 1:
      return `${statement} REPEATABLE READ`;
    case 3:
      return `${statement} READ UNCOMMITTED`;
    case 4:
      return `${statement} SERIALIZABLE`;
    default:
      return `${statement} READ COMMITTED`;
  }
}

export function MaskedOptions(options: PoolOptions) {
  return options.password ? { ...options, password: '******' } : options;
}
