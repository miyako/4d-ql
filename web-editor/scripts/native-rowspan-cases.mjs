import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync, strFromU8 } from 'fflate';
import { expect } from '@playwright/test';
import { nativeTableGrid } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import { inspectPDF } from './native-print-cases.mjs';

// Expected browser outcomes per native shape. Excluded shapes keep the terminal localized atomic fallback.
export const rowspanShapes = {
  vertical: null, header: null, 'two-headers': null, mixed: null, unicode: null, lists: null,
  // The browser's protected formula display beside a four-item cell list makes that band taller than the page body.
  rich: 'pagedBand',
  media: null, seam: null, chain: null,
  tall: 'pagedBand',
  // Full 4D 21.2 silently declines a merge from a header row into a body row, so this native table is admitted as stored.
  'header-cross': null,
  'no-witness': 'pagedTables',
};
const tokens = text => text.match(/R\d+[ABC]/g) || [];
const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s​]/gu, '');
const span = (cell, name) => Number(cell.getAttribute(name) || 1);
// Fallback CJK/emoji glyph boxes have other ascents: a word joins a printed line when its vertical
// centre lies inside that line's first word box, then each line reads left to right.
const readingOrder = (lines, word) => {
  const line = lines.at(-1);
  const centre = (word.y + word.bottom) / 2;
  if (line && centre >= line[0].y && centre <= line[0].bottom) line.push(word);
  else lines.push([word]);
  return lines;
};

// Bands are derived from the native-exported XML only: rows tied by a native rowspan.
export function nativeBands(rows) {
  const bands = [];
  for (let start = 0, end = 0; start < rows.length; start = end) {
    end = start + 1;
    for (let index = start; index < end; index++) for (const cell of rows[index].children) end = Math.max(end, index + span(cell, 'rowspan'));
    bands.push([start, end]);
  }
  return bands;
}

export async function prepareRowspanCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/rowspan-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(rowspanShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/rowspan-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const files = unzipSync(await readFile(resolve(directory, `Output/rowspan-${item.name}-original.4wp`)));
    const html = strFromU8(files[Object.keys(files).find(name => name.endsWith('.html'))]);
    const dom = new JSDOM(html, { contentType: 'application/xhtml+xml' });
    const grid = nativeTableGrid(dom.window.document.querySelector('table'));
    const fallback = rowspanShapes[item.name];
    const witness = grid.rows.findIndex(row => row.children.length === 3 &&
      [...row.children].every(cell => !cell.hasAttribute('colspan') && !cell.hasAttribute('rowspan')));
    const bands = nativeBands(grid.rows);
    assert.equal(grid.columns, 3);
    // A full-width multi-row merge collapses into one native row (mixed: 25 rows); counts come from native getters.
    assert.equal(grid.rows.length, item.rows);
    assert.equal(item.rows, item.name === 'mixed' ? 25 : 26);
    assert(dom.window.document.querySelector('td[rowspan]'), `${item.name}: native original must actually serialize a vertical merge`);
    if (item.name === 'no-witness') assert.equal(witness, -1);
    else assert(witness >= 0, `${item.name}: native width witness`);
    if (item.name === 'header-cross') {
      assert.deepEqual(item.merges[0], [1, 1, 1, 2], 'The header-crossing merge was requested natively');
      assert.deepEqual(grid.rows.slice(0, 2).map(row => [...row.children].map(cell => tokens(cell.textContent))),
        [[['R1A'], ['R1B'], ['R1C']], [['R2A'], ['R2B'], ['R2C']]],
        'Full 4D declined the header-crossing merge');
    }
    if (item.headers) assert(bands.some(([, end]) => end === item.headers), 'Native header rows are whole bands');
    if (!fallback) assert(bands.some(([start, end]) => end - start > 1), `${item.name}: at least one native multi-row band`);
    const source = `rowspan-source-${item.name}.4wp`;
    files['Resources/rowspan-sentinel.bin'] = Uint8Array.of(0, 255, 23, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `rowspan-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/rowspan-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source, pagedTable: { rows: item.rows, columns: 3 } };
    const native = inspectPDF(resolve(directory, `Output/rowspan-${item.name}.pdf`));
    const nativeWords = native.pages.map(sheet => sheet.words.map(word => word.text).join(''));
    const nativeTablePages = nativeWords.filter(text => tokens(text).some(token => Number(token.match(/^R(\d+)/)[1]) > item.headers));
    const nativeTokenCounts = {};
    for (let row = 1; row <= 26; row++) for (const column of ['A', 'B', 'C']) {
      const token = `R${row}${column}`;
      nativeTokenCounts[token] = nativeWords.reduce((count, text) => count + tokens(text).filter(value => value === token).length, 0);
    }
    // Native PDF completeness is independent of the browser outcome.
    {
      assert.equal(item.cells.length, item.rows * 3);
      const serialized = new Set(tokens(grid.rows.map(row => row.textContent).join(' ')));
      for (const [token, count] of Object.entries(nativeTokenCounts)) {
        const header = grid.rows.slice(0, item.headers).some(row => tokens(row.textContent).includes(token));
        assert.equal(count, !serialized.has(token) ? 0 : header ? nativeTablePages.length : 1,
          `${item.name}: complete independent native PDF token ${token}`);
      }
      if (witness >= 0) assert.deepEqual(item.cells.filter(cell => cell.row === witness + 1).map(cell => cell.width), ['50pt', '70pt', '110pt']);
      if (item.name === 'rich' || item.name === 'lists') {
        const text = nativeWords.join('');
        assert(text.includes('●') && text.includes('♦'), `${item.name}: native disc and diamond cell markers`);
        if (item.name === 'rich') assert(text.includes('ROWCR21C'));
      }
      if (item.name === 'media') assert(nativeWords.join('').includes('ROWCR6C'));
      if (item.name === 'unicode') assert(nativeWords.join('').includes('日本') && nativeWords.join('').includes('🚃'));
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.rowspanWholeMeasurements = [];
      const bounds = Element.prototype.getBoundingClientRect;
      Element.prototype.getBoundingClientRect = function () {
        if (this.localName === 'table' && this.closest('.paged-measure .page-body') && this.style.tableLayout !== 'fixed') {
          window.rowspanWholeMeasurements.push([...this.rows].map(row => [...row.cells].map(cell => {
            const rect = bounds.call(cell);
            return { width: rect.width, height: rect.height, colSpan: cell.colSpan, rowSpan: cell.rowSpan };
          })));
        }
        return bounds.call(this);
      };
    });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('ROWSTART');
      await download(`rowspan-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      if (fallback) {
        await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await download(`rowspan-after-${item.name}`, expected, page);
        assert.deepEqual(await readFile(resolve(directory, `Input/rowspan-after-${item.name}.4wp`)), Buffer.from(original));
        assert.deepEqual(errors, []);
        results.push({ name: item.name, nativeExcludedShape: true, fallback, nativeMerges: item.merges, nativeBands: bands,
          nativePages: native.pages.length, nativeTokenCounts, terminalLocalizedAtomicFallback: true, untouchedOriginalBytes: true });
        continue;
      }
      const sheets = page.locator('#paged-view .browser-page');
      await expect(sheets.nth(1)).toBeVisible();
      const count = await sheets.count();
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const reference = await page.evaluate(() => window.rowspanWholeMeasurements[0]);
      assert(reference?.length === item.rows, 'Observe the actual unfrozen whole table in its owning physical flow');
      const fragments = await sheets.evaluateAll(sheets => sheets.map(sheet => {
        const origin = sheet.getBoundingClientRect();
        return [...sheet.querySelectorAll('.page-body table tr')].map(row => [...row.cells].map(cell => {
          const bounds = cell.getBoundingClientRect();
          const runs = [...cell.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img')];
          return { text: cell.textContent, colSpan: cell.colSpan, rowSpan: cell.rowSpan, width: bounds.width, height: bounds.height,
            x: (bounds.left - origin.left) * .75, y: (bounds.top - origin.top) * .75,
            right: (bounds.right - origin.left) * .75, bottom: (bounds.bottom - origin.top) * .75,
            markers: [...cell.querySelectorAll('.paged-list-marker')].map(marker => marker.textContent),
            inside: runs.every(run => [...run.getClientRects()].every(rect =>
              rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25 &&
              rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25)),
          };
        }));
      }));
      const sourceRows = grid.rows.map(row => [...row.children].map(cell => tokens(cell.textContent)));
      const tableSheets = fragments.filter(rows => rows.length);
      // Fragments are complete bands: every data row exactly once, in native reading order.
      const dataRows = tableSheets.flatMap(rows => rows.slice(item.headers));
      assert.deepEqual(dataRows.map(row => row.map(cell => tokens(cell.text))), sourceRows.slice(item.headers),
        `${item.name}: complete ordered native-source row/cell/token membership`);
      const allTokens = dataRows.flatMap(row => row.flatMap(cell => tokens(cell.text)));
      assert.equal(new Set(allTokens).size, allTokens.length, `${item.name}: every body token exactly once`);
      const boundaries = [];
      let index = item.headers;
      for (const rows of tableSheets) {
        for (let header = 0; header < item.headers; header++) {
          assert.deepEqual(rows[header].map(cell => tokens(cell.text)), sourceRows[header], 'Complete native leading header repeats');
        }
        boundaries.push(index);
        for (const [position, row] of rows.entries()) {
          const at = position < item.headers ? position : index + position - item.headers;
          for (const [column, cell] of row.entries()) {
            assert.equal(cell.colSpan, reference[at][column].colSpan, 'Native horizontal merge preserved');
            assert.equal(cell.rowSpan, reference[at][column].rowSpan, 'Native vertical merge preserved');
            assert(Math.abs(cell.width - reference[at][column].width) <= .25 &&
              Math.abs(cell.height - reference[at][column].height) <= .25,
            `${item.name} row ${at + 1} cell ${column + 1}: frozen ${cell.width}x${cell.height}, whole ${reference[at][column].width}x${reference[at][column].height}`);
            assert(cell.inside, 'Every inline atom and marker stays in its owning cell');
          }
        }
        index += rows.length - item.headers;
      }
      const starts = new Set(bands.map(([start]) => start));
      assert(boundaries.every(start => starts.has(start)), `${item.name}: page fragments start only at native band boundaries`);
      if (item.name === 'seam') {
        await expect(sheets.first()).toHaveAttribute('data-sections', '1 2');
        assert(fragments[0].length > 0 && fragments[0].length < item.rows, 'Banded table consumes bounded residual compatible-seam capacity');
      }
      if (item.name === 'rich' || item.name === 'lists') {
        const markers = dataRows.flatMap(row => row.flatMap(cell => cell.markers));
        assert(markers.includes('●') && markers.includes('♦'), 'Disc and diamond cell markers in merged bands');
      }
      if (item.name === 'media') {
        await expect(page.locator('#paged-view td[rowspan] img')).toHaveCount(1);
        await expect(page.locator('#paged-view td[rowspan] .formula-object')).toHaveCount(1);
        assert(dom.window.document.querySelectorAll('td[rowspan] a[href="https://example.invalid/row"]').length > 0);
        assert(await page.locator('#paged-view td[rowspan] .inert-link').count() > 0);
      }
      if (item.name === 'unicode') assert(dataRows.flat().map(cell => cell.text).join('').includes('🚃é'));
      await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.evaluate(() => {
        window.rowspanResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.evaluate(() => window.rowspanResize);
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const pdf = resolve(directory, `Output/rowspan-browser-${item.name}.pdf`);
      await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(pdf);
      assert(printed.pages.length >= count);
      assert.deepEqual(printed.pages.slice(count).flatMap(sheet => tokens(sheet.words.map(word => word.text).join(''))), []);
      const printedCells = fragments.map((rows, index) => rows.map(row => row.map(cell =>
        printed.pages[index].words.filter(word => {
          const x = (word.x + word.right) / 2;
          const y = (word.y + word.bottom) / 2;
          return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
        }).sort((a, b) => a.y + a.bottom - b.y - b.bottom).reduce(readingOrder, []).flatMap(line =>
          line.sort((a, b) => a.x - b.x)).map(word => word.text).join(''))));
      assert.deepEqual(printedCells.map(rows => rows.map(row => row.map(normalize))),
        fragments.map(rows => rows.map(row => row.map(cell => normalize(cell.text)))),
        `${item.name}: exact complete printed cell/text/marker/formula membership`);
      for (const sheet of printed.pages.slice(0, count)) {
        assert(Math.abs(sheet.width - 300) < 1 && Math.abs(sheet.height - 360) < 1, 'Unscaled native paper geometry');
      }
      if (item.name === 'media') assert.match(execFileSync('pdfimages', ['-list', pdf], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
      await download(`rowspan-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/rowspan-after-${item.name}.4wp`)), Buffer.from(original));
      if (item.name !== 'seam') await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBROW');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`rowspan-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`rowspan-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`rowspan-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      results.push({ name: item.name, witness: witness + 1, nativeMerges: item.merges, nativeBands: bands, nativeGetters: item.cells,
        nativePages: native.pages.length, nativeTokenCounts, browserPages: count, fragmentStarts: boundaries, fragments, reference,
        printedCells, untouchedOriginalBytes: true, exactOrderedNativeMembership: true, exactPDFCellMembership: true,
        unchangedFragmentGeometry: true });
    } finally {
      await page.close();
      dom.window.close();
    }
  }
  await writeFile(resolve(directory, 'Output/rowspan-browser-report.json'), JSON.stringify(results, null, 2));
}
