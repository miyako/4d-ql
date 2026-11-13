import assert from 'node:assert/strict';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { preview } from 'vite';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export async function evidencePreview(directory, defaultPort, name) {
  const port = Number(process.env.WP_PREVIEW_PORT || defaultPort);
  assert(Number.isSafeInteger(port) && port > 0 && port <= 65535 && port !== 4179, 'Use a separate exclusive evidence preview port');
  const server = await preview({ root, configFile: resolve(root, 'vite.config.js'),
    preview: { host: '127.0.0.1', port, strictPort: true } });
  const url = server.resolvedUrls.local[0];
  const assets = [];
  const visit = async (relative = '') => {
    for (const entry of await readdir(resolve(root, 'dist', relative), { withFileTypes: true })) {
      const path = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await visit(path);
      else {
        const intended = await readFile(resolve(root, 'dist', path));
        const response = await fetch(new URL(path, url));
        assert.equal(response.status, 200, `Missing served production asset: ${path}`);
        const served = Buffer.from(await response.arrayBuffer());
        assert.deepEqual(served, intended, `Unexpected served production bytes: ${path}`);
        assets.push({ path, bytes: served.length, sha256: hash(served) });
      }
    }
  };
  try {
    await visit();
    await writeFile(resolve(directory, `${name}-served-assets.json`), JSON.stringify({ url, assets }, null, 2));
  } catch (error) {
    await new Promise(resolve => server.httpServer.close(resolve));
    throw error;
  }
  return {
    ...server,
    async close() {
      await new Promise(resolve => server.httpServer.close(resolve));
      let responsive = false;
      try { await fetch(url); responsive = true; } catch (error) {
        assert(error instanceof TypeError && error.cause?.code === 'ECONNREFUSED', `Unexpected port cleanup error: ${error}`);
      }
      assert(!responsive, 'Owned preview port still responds after shutdown');
      await writeFile(resolve(directory, `${name}-port-closed.json`), JSON.stringify({ url, responsive }, null, 2));
    },
  };
}
