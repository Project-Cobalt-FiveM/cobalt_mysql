import { build } from 'esbuild';
import { writeFileSync } from 'node:fs';

const shared = { bundle: true, platform: 'node', target: ['node22'], format: 'cjs', keepNames: true, legalComments: 'inline', logLevel: 'info' };

await build({ ...shared, entryPoints: ['src/server.ts'], outfile: 'dist/server.js' });
await build({ ...shared, entryPoints: ['src/worker-entry.ts'], outfile: 'dist/worker.js' });

writeFileSync('.yarn.installed', new Date().toISOString());
