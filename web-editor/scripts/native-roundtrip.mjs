import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, expect } from '@playwright/test';
import { preview } from 'vite';
import { unzipSync, strFromU8 } from 'fflate';
import { JSDOM } from 'jsdom';
import { nativeMetadata } from '../src/native-ranges.js';
import { prepareRangeCases, prepareBookmarkCases } from './native-range-cases.mjs';
import { prepareFormulaCases, verifyFormulaCase } from './native-formula-cases.mjs';

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
  const browserErrors = [];
  const watch = page => page.on('pageerror', error => browserErrors.push(error.message));
  try {
    const page = await browser.newPage({ acceptDownloads: true });
    watch(page);
    page.on('dialog', dialog => dialog.accept());
    await page.goto(server.resolvedUrls.local[0]);
    await page.getByRole('button', { name: 'New document', exact: true }).waitFor();
    const download = async (name, extra = {}, source = page) => {
      const waiting = source.waitForEvent('download');
      await source.getByRole('button', { name: 'Download .4wp', exact: true }).click();
      await expect(source.getByRole('alert'), `${name}: export failed`).toBeHidden();
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
    const rangeReport = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
    for (const kind of ['split', 'lineBreak', 'richPaste', 'join']) {
      const native = rangeReport.operations.find(item => item.name === kind);
      await page.locator('#file').setInputFiles(resolve(directory, `Output/range-edit-${kind}-original.4wp`));
      await expect(page.locator('#save-state')).toHaveText('Ready');
      await expect(page.locator('#paper p').first()).toHaveText(kind === 'join' ? 'abc' : 'abcdefghi');
      await page.locator('#paper p').nth(kind === 'join' ? 1 : 0).locator('[contenteditable]').first().evaluate((element, offset) => {
        element.focus();
        window.getSelection().collapse(element.firstChild, offset);
      }, kind === 'join' ? 0 : 3);
      if (kind === 'richPaste') {
        await page.locator('#paper').evaluate(paper => {
          const clipboardData = new DataTransfer();
          clipboardData.setData('text/html', '<p><b>XY</b></p><p>Z</p>');
          paper.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
        });
      } else await page.keyboard.press(kind === 'join' ? 'Backspace' : kind === 'lineBreak' ? 'Shift+Enter' : 'Enter');
      await download(`range-browser-${kind}`, { ranges: { text: native.after.text, bookmarks: native.after.bookmarks } });
    }
    for (const [offset, text] of [[0, 'XY'], [3, '😀日']]) {
      await page.locator('#file').setInputFiles(resolve(directory, 'Output/range-editing.4wp'));
      await expect(page.locator('#save-state')).toHaveText('Ready');
      await expect(page.locator('#paper p')).toHaveText('abcdefghi');
      await page.locator('[contenteditable]').first().evaluate((element, offset) => {
        element.focus();
        window.getSelection().collapse(element.firstChild, offset);
      }, offset);
      if (offset) await page.keyboard.insertText(text);
      else await page.keyboard.type(text);
      const native = rangeReport.splices.find(item => item.edit.start === offset + 1 && item.edit.end === offset + 1 && item.edit.text === text);
      await download(`range-browser-typing-${offset}`, { ranges: { text: native.text, bookmarks: native.bookmarks } });
    }
    for (const kind of [
      'typing', 'cellStart', 'cellEnd', 'cut', 'splitCell', 'joinCell', 'pasteCell', 'unicodeCell', 'emptyCellTyping',
      'addRow', 'appendRow', 'removeRow', 'removeLastRow', 'removeColumn', 'removeLastColumn',
      'insertTable', 'listSplit', 'listJoin', 'listPaste', 'listTyping', 'listCell',
    ]) {
      const page = await browser.newPage({ acceptDownloads: true });
      watch(page);
      page.on('dialog', dialog => dialog.accept());
      await page.goto(server.resolvedUrls.local[0]);
      const native = rangeReport.structures.find(item => item.name === kind);
      assert(native, `Missing independent native ${kind} operation`);
      await page.locator('#new').click();
      await page.locator('#file').setInputFiles(resolve(directory, `Output/structure-${kind}-original.4wp`));
      await expect(page.locator('#paper')).toContainText('BEFORE');
      const rowEdits = { addRow: [0, 'add-row'], appendRow: [2, 'add-row'], removeRow: [0, 'remove-row'], removeLastRow: [2, 'remove-row'], removeColumn: [0, 'remove-column'], removeLastColumn: [1, 'remove-column'] };
      const target = rowEdits[kind]
        ? page.locator('#paper td').nth(rowEdits[kind][0]).locator('[contenteditable]').first()
        : kind === 'emptyCellTyping' ? page.locator('#paper td [contenteditable]').first()
        : page.locator('#paper [contenteditable]').filter({ hasText: new RegExp(`^${kind === 'insertTable' ? 'BEFORE' : kind === 'joinCell' ? 'B' : kind.startsWith('list') && kind !== 'listCell' ? 'CD' : 'AB'}$`) }).first();
      const offset = ['cellStart', 'cut', 'joinCell', 'listJoin', 'listCell', 'emptyCellTyping'].includes(kind) || rowEdits[kind] ? 0 : kind === 'cellEnd' ? 2 : kind === 'insertTable' ? 6 : 1;
      await target.evaluate((element, { offset, cut }) => {
        element.focus();
        window.getSelection().setBaseAndExtent(element.firstChild, offset, element.firstChild, cut ? 2 : offset);
      }, { offset, cut: kind === 'cut' });
      if (rowEdits[kind] || kind === 'insertTable') {
        if (await page.locator('details').getAttribute('open') === null) await page.locator('summary').click();
        await page.locator(`#${rowEdits[kind]?.[1] || 'insert-table'}`).click();
      } else if (['cut', 'pasteCell', 'listPaste'].includes(kind)) {
        await page.locator('#paper').evaluate((paper, cut) => {
          const clipboardData = new DataTransfer();
          if (!cut) clipboardData.setData('text/html', '<p><b>XY</b></p><p>Z</p>');
          paper.dispatchEvent(new ClipboardEvent(cut ? 'cut' : 'paste', { clipboardData, bubbles: true, cancelable: true }));
        }, kind === 'cut');
      } else if (['splitCell', 'listSplit', 'joinCell', 'listJoin'].includes(kind)) {
        await page.keyboard.press(kind.endsWith('Split') || kind === 'splitCell' ? 'Enter' : 'Backspace');
      } else if (kind === 'listCell') await page.locator('#bullets').click();
      else await page.keyboard.insertText(kind === 'unicodeCell' ? '😀日é' : ['listTyping', 'emptyCellTyping'].includes(kind) ? '😀日' : 'XY');
      await expect(page.getByRole('alert')).toBeHidden();
      console.log(`Native browser case: ${kind}`);
      await download(`structure-browser-${kind}`, { ranges: { text: native.after.text, bookmarks: native.after.bookmarks } }, page);
      await page.close();
    }
    for (const kind of ['create', 'collapsed', 'rename', 'delete', 'case', 'cellText', 'cellPoint', 'cellTerminator', 'rowSeparator', 'wholeTable', 'listRange']) {
      const source = await browser.newPage({ acceptDownloads: true });
      watch(source);
      source.on('dialog', dialog => dialog.accept());
      await source.goto(server.resolvedUrls.local[0]);
      await source.locator('#file').setInputFiles(resolve(directory, `Output/bookmark-${kind}-original.4wp`));
      const native = rangeReport.management.operations.find(item => item.name === kind);
      await expect(source.locator('#save-state')).toHaveText('Ready');
      const select = async (start, end = start) => {
        await source.locator('#paper [data-run]').first().evaluate((element, [start, end]) => {
          element.focus();
          getSelection().setBaseAndExtent(element.firstChild, start, element.firstChild, end);
        }, [start, end]);
      };
      if (native.bounds) {
        await source.locator('#paper').evaluate((paper, kind) => {
          const range = document.createRange();
          const cells = paper.querySelectorAll('td');
          const table = paper.querySelector('table');
          if (kind === 'listRange') {
            const items = paper.querySelectorAll('li');
            range.setStart(items[1].querySelector('[data-run]').firstChild, 0);
            range.setEnd(items[2].querySelector('[data-run]').firstChild, 2);
          } else if (kind === 'wholeTable') range.selectNodeContents(table);
          else if (kind === 'rowSeparator') {
            range.setStart(table.firstChild, table.firstChild.childNodes.length);
            range.setEnd(table, 1);
          } else {
            const text = cells[0].querySelector('[data-run]').firstChild;
            range.setStart(text, kind === 'cellText' ? 0 : 2);
            if (kind === 'cellTerminator') range.setEnd(cells[0].parentNode, 1);
            else range.setEnd(text, 2);
          }
          getSelection().removeAllRanges();
          getSelection().addRange(range);
          document.dispatchEvent(new Event('selectionchange'));
        }, kind);
      } else await select(1, 3);
      await source.locator('#bookmarks-toggle').click();
      const create = async name => {
        await source.locator('#bookmark-name').fill(name);
        await source.locator('#bookmark-create').click();
        await expect(source.getByRole('alert')).toBeHidden();
      };
      await create(native.bounds ? 'managed' : '日本語😀é');
      if (kind === 'collapsed') { await select(3); await create('point'); }
      if (kind === 'case') {
        await select(0, 1); await create('ABC');
        await select(4, 6); await create('abc');
      }
      if (kind === 'rename') {
        await source.locator('#bookmark-name').fill('renamed_日本語😀é');
        await source.locator('#bookmark-rename').click();
      }
      if (kind === 'delete') await source.locator('#bookmark-delete').click();
      await expect(source.getByRole('alert')).toBeHidden();
      const archive = unzipSync(await readFile(resolve(directory, `Output/bookmark-${kind}-native.4wp`)));
      const xml = strFromU8(Object.entries(archive).find(([name]) => /\.html$/i.test(name))[1]);
      const serialized = await source.evaluate(xml => {
        const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
        return Object.fromEntries(Object.entries(JSON.parse(doc.querySelector('meta[name="bookmarks"]')?.getAttribute('content') || '{}')).map(([name, pair]) => [name, pair.map(offset => offset + 1)]));
      }, xml);
      await download(`bookmark-browser-${kind}`, { ranges: { text: native.after.text, bookmarks: native.after.bookmarks, serialized } }, source);
      if (['create', 'collapsed', 'rename', 'delete', 'cellTerminator'].includes(kind)) {
        await source.locator('#undo').click();
        await source.locator('#redo').click();
        await expect(source.locator('#draft-state')).toHaveText('Local draft saved');
        await source.reload();
        await expect(source.locator('#recovery-notice')).toBeVisible();
        await download(`bookmark-browser-recovered-${kind}`, { ranges: { text: native.after.text, bookmarks: native.after.bookmarks, serialized } }, source);
      }
      await source.close();
    }
    await prepareRangeCases(directory, cases);
    await prepareBookmarkCases(directory, cases);
    await prepareFormulaCases(directory, cases, browser, server.resolvedUrls.local[0]);
    assert.deepEqual(browserErrors, [], 'Browser runtime errors');
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
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  for (const entry of cases) {
    const actual = results.get(entry.name);
    assert(actual?.imported && actual?.reopened, `${entry.name}: missing native import/reopen evidence`);
    const before = actual.imported;
    const after = actual.reopened;
    if (entry.formula) await verifyFormulaCase(directory, entry, actual);
    for (const key of ['text', 'metadata', 'bookmarks', 'images', 'imagePixels', 'tables', 'first']) assert.deepEqual(after[key], before[key], `${entry.name}: native re-export changed ${key}`);
    if (entry.ranges) {
      assert.equal(before.text, entry.ranges.text, `${entry.name}: text differs from native edit`);
      assert.deepEqual(before.bookmarks, entry.ranges.bookmarks, `${entry.name}: bookmarks differ from native edit`);
      if (entry.ranges.serialized) {
        const dom = new JSDOM();
        for (const file of [`Input/${entry.file}`, `Output/${entry.name}.4wp`]) {
          const files = unzipSync(await readFile(resolve(directory, file)));
          const xml = strFromU8(Object.entries(files).find(([name]) => /\.html$/i.test(name))[1]);
          const doc = new dom.window.DOMParser().parseFromString(xml, 'application/xhtml+xml');
          assert.deepEqual(nativeMetadata(doc).bookmarks, entry.ranges.serialized, `${entry.name}: serialized ${file} differs`);
        }
        dom.window.close();
      }
    }
    for (const key of ['formulas', 'links']) assert.deepEqual(stable(after[key]), stable(before[key]), `${entry.name}: native re-export changed ${key}`);
    if (entry.reference) {
      const baseline = results.get(entry.reference).imported;
      assert.equal(before.text, (entry.edited ? 'WEB-CHECK ' : '') + baseline.text, `${entry.name}: native text differs`);
      for (const key of ['metadata', 'bookmarks', 'images', 'tables']) assert.deepEqual(before[key], baseline[key], `${entry.name}: browser changed ${key}`);
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
  dom.window.close();
}

await (mode === 'prepare' ? prepare() : verify());
