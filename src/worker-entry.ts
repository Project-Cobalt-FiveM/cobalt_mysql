import { parentPort, receiveMessageOnPort, workerData } from 'node:worker_threads';
import { Serve } from './worker';

const port = parentPort!;

Serve(port, workerData, () => receiveMessageOnPort(port));
