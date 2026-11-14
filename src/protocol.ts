export const enum Op {
  Query = 0,
  Single = 1,
  Scalar = 2,
  Insert = 3,
  Update = 4,
  Prepare = 5,
  RawExecute = 6,
  Transaction = 7,
  Begin = 8,
  SessionQuery = 9,
  Commit = 10,
  Rollback = 11,
  ReleaseResource = 12,
}

export const lastPublicOp = Op.SessionQuery;

export interface Request {
  op: Op;
  query: unknown;
  params: unknown;
  resource: string;
  session: number;
}

export interface Failure {
  message: string;
  code?: string;
  errno?: number;
  sqlState?: string;
  sql?: string;
  query?: unknown;
  params?: unknown;
  stage: 'parse' | 'query' | 'transaction' | 'session';
}

export type Outcome = { ok: true; value: unknown; ms: number } | { ok: false; failure: Failure; ms: number };

export type Envelope =
  | { id: number; outcome: Outcome }
  | { id: 0; ready: string; multipleStatements: boolean }
  | { id: 0; connectFailed: string; options: string }
  | { id: 0; warn: string };

export interface WorkerSettings {
  connectionString: string;
  isolationLevel: number;
  resultSetWarning: number;
  transactionTimeoutMs: number;
}

export const enum Slot {
  State = 0,
  ReplyLength = 1,
  Handoff = 2,
  RequestLength = 3,
}

export const enum State {
  Idle = 0,
  Done = -1,
  Posted = -2,
}

export const enum Handoff {
  Idle = 0,
  Listening = 1,
  Writing = 2,
  Ready = 3,
}

export interface Port {
  postMessage(message: unknown): void;
  on(event: 'message', listener: (message: any) => void): unknown;
}

export const controlBytes = 64;
export const requestBytes = 1 << 20;
export const replyBytes = 8 << 20;

export function createShared() {
  return new SharedArrayBuffer(controlBytes + requestBytes + replyBytes);
}

export function views(shared: SharedArrayBuffer) {
  return {
    control: new Int32Array(shared, 0, controlBytes >> 2),
    request: Buffer.from(shared, controlBytes, requestBytes),
    reply: Buffer.from(shared, controlBytes + requestBytes, replyBytes),
  };
}
