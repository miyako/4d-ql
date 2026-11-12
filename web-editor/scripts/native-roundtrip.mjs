import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect } from '@playwright/test';
import { preview } from 'vite';
import { unzipSync, strFromU8 } from 'fflate';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = resolve(root, '../Tests/FourDFileKitTests/Fixtures/WritePro');
const [mode, destination] = process.argv.slice(2);
assert(destination && ['prepare', 'verify'].includes(mode), 'Usage: native-roundtrip.mjs prepare|verify OUTPUT_DIRECTORY');
const directory = resolve(destination);
const manifestPath = resolve(directory, 'Input/cases.json');

async function prepare() {
  await mkdir(resolve(directory, 'Input'), { recursive: true });
  const server = await preview({
    root, configFile: resolve(root, 'vite.config.js'),
    preview: { host: '127.0.0.1', port: 4187, strictPort: true },
  });
  const browser = await chromium.launch();
  const cases = [];
  try {
    const page = await browser.newPage({ acceptDownloads: true });
    page.on('dialog', dialog => dialog.accept());
    await page.goto(server.resolvedUrls.local[0]);
    await page.getByRole('button', { name: 'New document', exact: true }).waitFor();
    const download = async (name, extra = {}) => {
      const waiting = page.waitForEvent('download');
      await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
      const file = `${name}.4wp`;
      await (await waiting).saveAs(resolve(directory, 'Input', file));
      cases.push({ name, file, ...extra });
    };
    await download('example');
    await page.getByRole('button', { name: 'New document', exact: true }).click();
    await page.locator('[contenteditable]').first().fill('Native editor sample');
    for (const name of ['Bold', 'Italic', 'Underline', 'Strikethrough']) await page.getByRole('button', { name, exact: true }).click();
    await page.locator('#size').selectOption('18');
    await page.locator('#highlight').selectOption('#fff2a8');
    await page.locator('[contenteditable]').first().evaluate(element => {
      window.getSelection().selectAllChildren(element);
    });
    await page.locator('#link-toggle').click();
    await page.locator('#link-url').fill('https://example.org/editor');
    await page.locator('#apply-link').click();
    await page.locator('[contenteditable]').first().evaluate(element => {
      element.focus();
      window.getSelection().collapse(element.firstChild, element.textContent.length);
    });
    const objectArchive = unzipSync(await readFile(resolve(fixtures, 'objects.4wp')));
    const html = strFromU8(Object.entries(objectArchive).find(([name]) => /\.html$/i.test(name))[1]);
    const png = Buffer.from(/src="data:image\/png;base64,([^"]+)"/.exec(html)[1], 'base64');
    await page.locator('#image-file').setInputFiles({ name: 'native-check.png', mimeType: 'image/png', buffer: png });
    await expect(page.locator('#paper img')).toHaveCount(1);
    await page.locator('summary').click();
    await page.getByRole('button', { name: 'Insert table', exact: true }).click();
    await page.locator('table [contenteditable]').first().fill('Native cell');
    await download('new-document');
    for (const name of ['text', 'layout', 'objects', 'table', 'media', 'more']) {
      const file = `${name}-original.4wp`;
      const bytes = await readFile(resolve(fixtures, `${name}.4wp`));
      await writeFile(resolve(directory, 'Input', file), bytes);
      cases.push({ name: `${name}-original`, file });
      const originalArchive = unzipSync(bytes);
      const source = strFromU8(Object.entries(originalArchive).find(([name]) => /\.html$/i.test(name))[1]);
      const title = await page.evaluate(source => new DOMParser().parseFromString(source, 'application/xhtml+xml').querySelector('title').textContent, source);
      await page.locator('#file').setInputFiles(resolve(fixtures, `${name}.4wp`));
      await expect(page.locator('#document-title')).toHaveText(title);
      const editable = page.locator('#paper [contenteditable]').first();
      const edited = await editable.count() > 0;
      if (edited) await editable.fill('WEB-CHECK ' + await editable.textContent());
      await download(`${name}-browser`, { reference: `${name}-original`, edited });
    }
    await writeFile(manifestPath, JSON.stringify({ cases }, null, 2));
  } finally {
    await browser.close();
    await new Promise((resolve, reject) => server.httpServer.close(error => error ? reject(error) : resolve()));
  }
}

function stable(items) {
  return items.map(item => JSON.stringify(item)).sort();
}

async function verify() {
  const { cases } = JSON.parse(await readFile(manifestPath, 'utf8'));
  const report = JSON.parse(await readFile(resolve(directory, 'Output/native-report.json'), 'utf8'));
  assert.deepEqual(report.errors, [], `Native 4D errors: ${JSON.stringify(report.errors)}`);
  assert.equal(report.cases.length, cases.length, 'Native case count');
  const results = new Map(report.cases.map(item => [item.name, item]));
  for (const entry of cases) {
    const actual = results.get(entry.name);
    assert(actual?.imported && actual?.reopened, `${entry.name}: missing native import/reopen evidence`);
    const before = actual.imported;
    const after = actual.reopened;
    for (const key of ['text', 'metadata', 'images', 'imagePixels', 'tables', 'first']) assert.deepEqual(after[key], before[key], `${entry.name}: native re-export changed ${key}`);
    for (const key of ['formulas', 'links']) assert.deepEqual(stable(after[key]), stable(before[key]), `${entry.name}: native re-export changed ${key}`);
    if (entry.reference) {
      const baseline = results.get(entry.reference).imported;
      assert.equal(before.text, (entry.edited ? 'WEB-CHECK ' : '') + baseline.text, `${entry.name}: native text differs`);
      for (const key of ['metadata', 'images', 'tables']) assert.deepEqual(before[key], baseline[key], `${entry.name}: browser changed ${key}`);
      for (const key of ['bold', 'italic', 'underline', 'strike', 'size', 'color', 'background']) assert.deepEqual(before.first[key], baseline.first[key], `${entry.name}: browser changed first-character ${key}`);
      for (const key of ['formulas', 'links']) assert.deepEqual(stable(before[key]), stable(baseline[key]), `${entry.name}: browser changed ${key}`);
      if (!entry.edited) assert.deepEqual(await readFile(resolve(directory, 'Input', entry.file)), await readFile(resolve(directory, 'Input', `${entry.reference}.4wp`)), `${entry.name}: read-only archive changed`);
    }
  }
  const fresh = results.get('new-document').reopened;
  assert(fresh.text.includes('Native editor sample') && fresh.text.includes('Native cell'), 'New native document text');
  assert.equal(fresh.images, 1, 'New native image');
  assert.equal(fresh.tables, 1, 'New native table');
  assert.equal(fresh.first.bold, true, 'New native bold');
  assert.equal(fresh.first.italic, true, 'New native italic');
  assert.equal(fresh.first.underline, true, 'New native underline');
  assert.equal(fresh.first.strike, true, 'New native strikethrough');
  assert.equal(fresh.first.text, 'N', 'Actual first native glyph');
  assert.equal(fresh.first.background, 0xfff2a8, 'New native highlight');
  assert(fresh.links.some(link => link.url === 'https://example.org/editor'), 'New native hyperlink');
  assert.deepEqual(fresh.imagePixels, { width: 48, height: 32 }, 'Native image decoded at original pixel dimensions');
  assert.equal(fresh.first.size, '18pt', 'New native font size');
  console.log(`Native 4D ${report.version}: ${cases.length} import/export/reopen cases passed.`);
}

await (mode === 'prepare' ? prepare() : verify());
