import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';

const additions = new Set(['typing', 'unicode', 'middleTyping', 'lastTyping', 'beforeTyping', 'afterTyping', 'split', 'lineBreak', 'paste', 'picture']);
const rectangular = new Set(['grid', 'uneven', 'empty']);
const subset = (object, names) => Object.fromEntries(Object.entries(object).filter(([name]) => names.has(name)));

// Scope is selected from independently measured native cell/text ranges, not
// the editor's mapping, affinities or predictions of the operation's result.
export async function complexScenarios(directory, report) {
  const dom = new JSDOM();
  const result = [];
  const archive = async (item, suffix) => {
    const files = unzipSync(await readFile(resolve(directory, `Output/complex-${item.name}-${suffix}.4wp`)));
    const entry = Object.keys(files).find(name => /\.html$/i.test(name));
    const document = new dom.window.DOMParser().parseFromString(strFromU8(files[entry]), 'application/xhtml+xml');
    return { files, entry, document, pairs: nativeMetadata(document).bookmarks };
  };
  for (const item of report) {
    assert(Number.isInteger(item.tableStart) && Number.isInteger(item.tableEnd), `${item.name}: native table text bounds missing`);
    assert(item.cells.every(cell => Number.isInteger(cell.start) && cell.end > cell.start), `${item.name}: native cell text bounds missing`);
    const column = ['addColumn', 'appendColumn'].includes(item.operation);
    if (column && !rectangular.has(item.shape) ||
      !column && !additions.has(item.operation) && !['identity', 'format', 'cut'].includes(item.operation)) continue;
    const scope = column ? 'column' : item.operation === 'cut' ? 'cells' : 'interior';
    const original = await archive(item, 'original');
    const native = await archive(item, 'native');
    const rowSeparators = item.cells.filter(cell => cell.column === Math.max(...item.cells.map(cell => cell.column))).map(cell => cell.end);
    const names = new Set(Object.entries(original.pairs).filter(([, [start, end]]) => {
      const outside = end <= item.tableStart || start >= item.tableEnd;
      const encloses = start <= item.tableStart && end >= item.tableEnd;
      if (scope === 'interior') {
        const within = start >= item.tableStart && end <= item.tableEnd;
        const sameCell = item.cells.some(cell => start >= cell.start && end <= cell.end);
        const cross = within && !encloses && !sameCell && start !== end;
        if (additions.has(item.operation) && (cross && start < item.point && item.point < end ||
          start === item.tableStart && end > item.tableEnd && item.point === item.tableStart)) return false;
        return outside || encloses || within;
      }
      if (scope === 'column' && (rowSeparators.includes(start) || end === item.tableEnd && start < end)) return false;
      return outside || encloses || item.cells.some(cell => start >= cell.start && end <= cell.end);
    }).map(([name]) => name));
    assert(names.size > 20, `${item.name}: empty native scope`);
    const before = subset(original.pairs, names);
    const serialized = subset(native.pairs, names);
    original.document.querySelector('meta[name="bookmarks"]').setAttribute('content',
      JSON.stringify(Object.fromEntries(Object.entries(before).map(([name, pair]) => [name, pair.map(offset => offset - 1)]))));
    const xml = new dom.window.XMLSerializer().serializeToString(original.document);
    original.files[original.entry] = strToU8(xml);
    original.files['Resources/range-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128, 42, 0, 10, 13);
    result.push({
      name: item.name, shape: item.shape, operation: item.operation, point: item.point, scope,
      bytes: zipSync(original.files), xml, before, serialized,
      after: { text: item.after.text, bookmarks: subset(item.after.bookmarks, names), serialized },
    });
  }
  dom.window.close();
  return result;
}

export function applyComplex(model, item, image) {
  const point = model.nativeView().locate(item.point);
  const selection = {
    startRun: model.runs.indexOf(point.node), start: point.offset,
    endRun: model.runs.indexOf(point.node), end: point.offset,
  };
  assert(selection.startRun >= 0, `${item.name}: native insertion point is not text`);
  switch (item.operation) {
    case 'identity': break;
    case 'typing': case 'middleTyping': case 'lastTyping': case 'beforeTyping': case 'afterTyping':
      model.replaceText(selection, 'XY'); break;
    case 'unicode': model.replaceText(selection, '😀日é'); break;
    case 'split': model.splitParagraph(selection); break;
    case 'lineBreak': model.splitParagraph(selection, true); break;
    case 'paste': model.paste(selection, '<p><b>XY</b></p><p>Z</p>', ''); break;
    case 'picture': model.insertImage(selection, image, 48, 32, 'checker'); break;
    case 'format': model.formatSelection({ ...selection, end: selection.end + (item.shape === 'empty' ? 0 : 1) }, 'font-weight', 'bold'); break;
    case 'cut':
      if (item.shape !== 'empty') model.replaceText({ ...selection, end: selection.end + 1 }, '', 'cut');
      break;
    case 'addColumn': case 'appendColumn': {
      const cell = item.operation === 'addColumn' ? model.cells[0] : model.cells.findLast(cell => cell.parentElement === model.cells[0].parentElement);
      model.tableEdit(model.cells.indexOf(cell), 'addColumn');
      break;
    }
    default: assert.fail(`Unknown complex operation ${item.operation}`);
  }
}

export async function prepareComplexCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
  assert.equal(report.complex.length, 108, 'Native complex matrix coverage');
  const scenarios = await complexScenarios(directory, report.complex);
  const image = `data:image/png;base64,${(await readFile(resolve(directory, 'Resources/checker.png'))).toString('base64')}`;
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  for (const item of scenarios) {
    const model = WriteProDocument.open(item.bytes);
    assert(!model.readOnly, `${item.name}: native scope must be editable`);
    model.render(document.createElement('article'), {});
    assert.doesNotThrow(() => applyComplex(model, item, image), `${item.name}: native operation`);
    assert.deepEqual(nativeMetadata(model.document).bookmarks, item.serialized, `${item.name}: raw native pairs`);
    if (item.operation !== 'identity' && !(item.operation === 'cut' && item.shape === 'empty')) {
      const recovered = WriteProDocument.unpack(model.pack());
      recovered.undo();
      assert.deepEqual(nativeMetadata(recovered.document).bookmarks, item.before, `${item.name}: recovered undo`);
      recovered.undo(true);
      assert.deepEqual(nativeMetadata(recovered.document).bookmarks, item.serialized, `${item.name}: recovered redo`);
    }
    const name = `complex-model-${item.name}`;
    await writeFile(resolve(directory, `Input/${name}.4wp`), model.export());
    cases.push({ name, file: `${name}.4wp`, ranges: item.after, resources: `complex-source-${item.name}.4wp` });
    await writeFile(resolve(directory, `Input/complex-source-${item.name}.4wp`), item.bytes);
  }
  dom.window.close();

  const browserCases = scenarios.filter(item =>
    item.scope === 'column' || ['typing', 'unicode'].includes(item.operation) ||
    item.shape === 'grid' && ['split', 'lineBreak', 'paste', 'picture'].includes(item.operation));
  for (const item of browserCases) {
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('dialog', dialog => dialog.accept());
    await page.goto(url);
    await page.locator('#file').setInputFiles({ name: `${item.name}.4wp`, mimeType: 'application/zip', buffer: Buffer.from(item.bytes) });
    await expect(page.locator('#paper')).toContainText('BEFORE');
    const cell = item.operation === 'appendColumn' ? page.locator('#paper tr').first().locator('td').last() : page.locator('#paper td').first();
    await cell.locator('[contenteditable]').first().evaluate(element => {
      element.focus();
      getSelection().collapse(element.firstChild, 0);
    });
    if (item.scope === 'column') {
      await page.locator('.editing-tools summary').click();
      await page.locator('#add-column').click();
    } else if (['split', 'lineBreak'].includes(item.operation)) await page.keyboard.press(item.operation === 'split' ? 'Enter' : 'Shift+Enter');
    else if (item.operation === 'paste') await page.locator('#paper').evaluate(paper => {
      const clipboardData = new DataTransfer();
      clipboardData.setData('text/html', '<p><b>XY</b></p><p>Z</p>');
      paper.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
    });
    else if (item.operation === 'picture') await page.locator('#image-file').setInputFiles(resolve(directory, 'Resources/checker.png'));
    else await page.keyboard.insertText(item.operation === 'unicode' ? '😀日é' : 'XY');
    await expect(page.getByRole('alert')).toBeHidden();
    const extra = { ranges: item.after, resources: `complex-source-${item.name}.4wp` };
    await download(`complex-browser-${item.name}`, extra, page);
    await page.locator('#undo').click();
    await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
    await page.reload();
    await expect(page.locator('#recovery-notice')).toBeVisible();
    await page.locator('#redo').click();
    await download(`complex-browser-recovered-${item.name}`, extra, page);
    assert.deepEqual(errors, [], `${item.name}: browser errors`);
    await page.close();
  }
}
