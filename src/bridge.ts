import type { Envelope, Outcome, Port, Request, WorkerSettings } from './protocol';

import { deserialize, serialize } from 'node:v8';
import { Worker } from 'node:worker_threads';
import { Handoff, Slot, State, createShared, views } from './protocol';
import { Serve } from './worker';

type Events = (envelope: Exclude<Envelope, { outcome: Outcome }>) => void;

const shared = createShared();
const { control, request: requestArea, reply: replyArea } = views(shared);
const spinMs = 0.5;
const resourceName = GetCurrentResourceName();
const pending = new Map<number, (outcome: Outcome) => void>();

let port: Port;
let threaded = false;
let lastId = 0;

function nextId() {
  lastId = lastId === 0x7fffffff ? 1 : lastId + 1;
  return lastId;
}

function receive(envelope: Envelope, events: Events) {
  if (envelope.id === 0) return events(envelope as Exclude<Envelope, { outcome: Outcome }>);

  const resolve = pending.get(envelope.id);
  if (!resolve) return;

  pending.delete(envelope.id);
  resolve((envelope as { outcome: Outcome }).outcome);
}

function localPorts(): [Port, Port] {
  const listeners: ((message: unknown) => void)[] = [];
  const end = (self: 0 | 1): Port => ({
    postMessage: (message) => queueMicrotask(() => listeners[1 - self]?.(message)),
    on: (_event, listener) => (listeners[self] = listener),
  });

  return [end(0), end(1)];
}

function serveInProcess(settings: WorkerSettings, events: Events) {
  const [main, worker] = localPorts();
  main.on('message', (envelope: Envelope) => receive(envelope, events));
  Serve(worker, { settings, shared });
  port = main;
}

export function Start(settings: WorkerSettings, events: Events): boolean {
  try {
    const worker = new Worker(`${GetResourcePath(resourceName)}/dist/worker.js`, { workerData: { settings, shared } });
    worker.on('message', (envelope: Envelope) => receive(envelope, events));
    worker.on('error', (error) => console.log(`^1query worker failed: ${error.message}^0`));
    port = worker;
    threaded = true;
  } catch {
    serveInProcess(settings, events);
  }

  return threaded;
}

function cloneFailure(error: unknown): Outcome {
  const message = error instanceof Error ? error.message : String(error);
  return { ok: false, failure: { stage: 'parse', message }, ms: 0 };
}

export function Send(request: Request): Promise<Outcome> {
  const id = nextId();

  return new Promise((resolve) => {
    try {
      port.postMessage({ id, request, sync: false });
    } catch (error) {
      return resolve(cloneFailure(error));
    }

    pending.set(id, resolve);
    ScheduleResourceTick(resourceName);
  });
}

function handOver(id: number, request: Request) {
  if (Atomics.compareExchange(control, Slot.Handoff, Handoff.Listening, Handoff.Writing) !== Handoff.Listening) {
    port.postMessage({ id, request, sync: true });
    return;
  }

  let bytes: Buffer;

  try {
    bytes = serialize({ id, request, sync: true });
  } catch (error) {
    Atomics.store(control, Slot.Handoff, Handoff.Listening);
    throw error;
  }

  if (bytes.length > requestArea.length) {
    Atomics.store(control, Slot.Handoff, Handoff.Listening);
    port.postMessage({ id, request, sync: true });
    return;
  }

  bytes.copy(requestArea, 0);
  control[Slot.RequestLength] = bytes.length;
  Atomics.store(control, Slot.Handoff, Handoff.Ready);
}

function waitForReply(id: number, budgetMs: number) {
  const spinUntil = performance.now() + Math.min(spinMs, budgetMs);

  for (let spins = 1; Atomics.load(control, Slot.State) === id; spins++) {
    if ((spins & 63) !== 0 || performance.now() < spinUntil) continue;

    Atomics.wait(control, Slot.State, id, Math.max(0, budgetMs - spinMs));
    break;
  }
}

export function Call(request: Request, budgetMs: number): Outcome | Promise<Outcome> {
  if (!threaded || budgetMs <= 0) return Send(request);

  const id = nextId();
  Atomics.store(control, Slot.State, id);

  try {
    handOver(id, request);
  } catch (error) {
    Atomics.store(control, Slot.State, State.Idle);
    return cloneFailure(error);
  }

  waitForReply(id, budgetMs);

  const state = Atomics.compareExchange(control, Slot.State, id, State.Idle);

  if (state === State.Done) {
    const outcome = deserialize(replyArea.subarray(0, control[Slot.ReplyLength])) as Outcome;
    Atomics.store(control, Slot.State, State.Idle);
    return outcome;
  }

  if (state === State.Posted) Atomics.store(control, Slot.State, State.Idle);

  ScheduleResourceTick(resourceName);
  return new Promise((resolve) => pending.set(id, resolve));
}
