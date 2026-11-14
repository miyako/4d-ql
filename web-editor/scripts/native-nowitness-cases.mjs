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
import { nativeBands } from './native-rowspan-cases.mjs';

// Expected browser outcomes per native shape (wp_nowitness_probe, full 4D 21.2 F0012102). Every shape is authored
// without a merge-free row; protected shapes keep the terminal localized atomic fallback for the native reason noted.
export const nowitnessShapes = {
  alternate: null, header: null, 'two-headers': null, band: null, block: null, stair: null, rich: null, seam: null,
  // A declared 2pt border makes full 4D store drifting merged widths (187.5pt, 188pt, ... per row): no exact grid.
  border2: 'pagedTables',
  pad5: null,
  // Per-column padding: a column that never stands alone carries no padding of its own in the stored file.
  uneven: 'pagedTables',
  // Full 4D removes the never-separated column B, so the stored three-column grid is fully determined.
  gap: null,
  // Full 4D removes the column merged in every row, leaving a plain two-column table with a witness.
  pair: null,
  // The exactly resolved native columns are wider than the page text width; the browser never shrinks them.
  wide: 'pagedTables',
};
// Column widths (pt) that the native authoring setters requested, after full 4D's own column removal.
const expectedColumns = {
  alternate: [50, 70, 110], header: [50, 70, 110], 'two-headers': [50, 70, 110], band: [50, 70, 110], block: [50, 70, 110],
  stair: [30, 50, 40, 60], rich: [50, 70, 110], seam: [50, 70, 110], pad5: [50, 70, 110],
  gap: [87, 40, 60], pair: [127, 110], wide: [80, 90, 100],
};
const tokens = text => text.match(/R\d+[A-D]/g) || [];
const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s​]/gu, '');
const readingOrder = (lines, word) => {
  const line = lines.at(-1);
  const centre = (word.y + word.bottom) / 2;
  if (line && centre >= line[0].y && centre <= line[0].bottom) line.push(word);
  else lines.push([word]);
  return lines;
};

// Independent resolution from the native-exported XML only (not the editor's code): outer widths add up, where
// outer = stored width + 2 x padding + 1pt. Returns null when a boundary is unfixed or two cells disagree.
export function nativeStoredColumns(document, grid) {
  const rules = new Map();
  for (const match of document.querySelector('style').textContent.matchAll(/td\.(_td\d+)\s*\{([^}]*)\}/g)) {
    rules.set(match[1], Object.fromEntries(match[2].split(';').filter(Boolean).map(entry => entry.split(':').map(part => part.trim()))));
  }
  const occupied = grid.rows.map(() => Array(grid.columns).fill(false));
  const cells = [];
  for (const [index, row] of grid.rows.entries()) {
    let column = 0;
    for (const cell of row.children) {
      while (occupied[index][column]) column++;
      const across = Number(cell.getAttribute('colspan') || 1);
      const down = Number(cell.getAttribute('rowspan') || 1);
      for (let r = index; r < index + down; r++) for (let c = column; c < column + across; c++) occupied[r][c] = true;
      const rule = rules.get(cell.getAttribute('class'));
      cells.push({ start: column, end: column + across, width: parseFloat(rule.width), padding: parseFloat(rule.padding) });
      column += across;
    }
  }
  const paddings = new Set(cells.map(cell => cell.padding));
  const positions = Array(grid.columns + 1).fill(null);
  positions[0] = 0;
  for (let changed = true; changed;) {
    changed = false;
    for (const { start, end, width, padding } of cells) {
      const outer = width + 2 * padding + 1;
      if (positions[start] !== null && positions[end] === null) { positions[end] = positions[start] + outer; changed = true; }
      if (positions[end] !== null && positions[start] === null) { positions[start] = positions[end] - outer; changed = true; }
    }
  }
  const consistent = positions.every(position => position !== null) &&
    cells.every(({ start, end, width, padding }) => Math.abs(positions[end] - positions[start] - width - 2 * padding - 1) < 1e-6);
  const padding = [...paddings][0];
  return { paddings: [...paddings], consistent,
    columns: consistent && paddings.size === 1 ? positions.slice(1).map((position, index) => position - positions[index] - 2 * padding - 1) : null };
}

export async function prepareNowitnessCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/nowitness-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(nowitnessShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/nowitness-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const files = unzipSync(await readFile(resolve(directory, `Output/nowitness-${item.name}-original.4wp`)));
    const html = strFromU8(files[Object.keys(files).find(name => name.endsWith('.html'))]);
    const dom = new JSDOM(html, { contentType: 'application/xhtml+xml' });
    const grid = nativeTableGrid(dom.window.document.querySelector('table'));
    const fallback = nowitnessShapes[item.name];
    const witness = grid.rows.findIndex(row => row.children.length === grid.columns &&
      [...row.children].every(cell => !cell.hasAttribute('colspan') && !cell.hasAttribute('rowspan')));
    const bands = nativeBands(grid.rows);
    const stored = nativeStoredColumns(dom.window.document, grid);
    assert.equal(grid.rows.length, item.rows);
    assert.equal(item.rows, 26);
    assert.equal(grid.columns, item.columns, `${item.name}: native column count`);
    assert.equal(item.cells.length, item.rows * item.columns);
    if (item.name === 'pair') {
      // Full 4D removed the always-merged column: a plain two-column grid with no merges at all.
      assert.equal(item.requestedWidths.length, 3);
      assert.equal(grid.merged, false);
      assert.equal(witness, 0);
    } else {
      assert(grid.merged, `${item.name}: native original must actually serialize merges`);
      assert.equal(witness, -1, `${item.name}: no merge-free native row`);
    }
    if (item.name === 'gap') assert.equal(item.requestedWidths.length, 4, 'Full 4D removed the never-separated column');
    // Native column getters never report a width for a merged column, before or after native re-import.
    assert.deepEqual(item.reopenedColumns, item.nativeColumns, `${item.name}: re-imported native column getters`);
    if (!['band', 'pair'].includes(item.name)) assert(item.nativeColumns.some(column => column.width === ''), `${item.name}: no native column width`);
    assert.deepEqual(item.reopenedCells.map(cell => cell.width), item.cells.map(cell => cell.width), `${item.name}: re-imported stored widths`);
    if (item.name === 'border2') {
      assert.equal(stored.consistent, false, 'Native 2pt-border widths do not resolve one grid');
      assert(new Set(item.cells.filter(cell => cell.row % 2 === 0 && cell.column === 2).map(cell => cell.width)).size > 1, 'Drifting native widths');
    } else if (item.name === 'uneven') {
      assert.equal(stored.paddings.length > 1, true, 'Native per-column padding is serialized per cell');
      assert.equal(stored.consistent, true);
    } else {
      assert.deepEqual(stored.paddings, [item.name === 'pad5' ? 5 : 3]);
      assert.deepEqual(stored.columns.map(value => Math.round(value * 1000) / 1000), expectedColumns[item.name],
        `${item.name}: stored widths resolve exactly the natively requested columns`);
    }
    if (item.name === 'wide') assert(stored.columns.reduce((sum, value) => sum + value, 0) > 240, 'Native columns exceed the 240pt text width');
    if (item.headers) assert(bands.some(([, end]) => end === item.headers), 'Native header rows are whole bands');
    const source = `nowitness-source-${item.name}.4wp`;
    files['Resources/nowitness-sentinel.bin'] = Uint8Array.of(0, 255, 23, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `nowitness-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/nowitness-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source, pagedTable: { rows: item.rows, columns: item.columns } };
    const native = inspectPDF(resolve(directory, `Output/nowitness-${item.name}.pdf`));
    const nativeWords = native.pages.map(sheet => sheet.words.map(word => word.text).join(''));
    const nativeTablePages = nativeWords.filter(text => tokens(text).some(token => Number(token.match(/^R(\d+)/)[1]) > item.headers));
    const nativeTokenCounts = {};
    const serialized = new Set(tokens(grid.rows.map(row => row.textContent).join(' ')));
    for (const token of serialized) {
      nativeTokenCounts[token] = nativeWords.reduce((count, text) => count + tokens(text).filter(value => value === token).length, 0);
      const header = grid.rows.slice(0, item.headers).some(row => tokens(row.textContent).includes(token));
      assert.equal(nativeTokenCounts[token], header ? nativeTablePages.length : 1, `${item.name}: complete independent native PDF token ${token}`);
    }
    assert.equal(serialized.size, 26 * item.requestedWidths.length, `${item.name}: every authored token is serialized once`);
    if (item.name === 'rich') {
      const text = nativeWords.join('');
      assert(text.includes('●') && text.includes('♦') && text.includes('NOWC'), 'Native rich markers and formula');
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.nowitnessWholeMeasurements = [];
      const bounds = Element.prototype.getBoundingClientRect;
      Element.prototype.getBoundingClientRect = function () {
        if (this.localName === 'table' && this.closest('.paged-measure .page-body') &&
          (this.style.tableLayout !== 'fixed' || this.querySelector(':scope > colgroup[data-native-columns]'))) {
          window.nowitnessWholeMeasurements.push([...this.rows].map(row => [...row.cells].map(cell => {
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
      await expect(page.locator('#paper')).toContainText('NOWSTART');
      await download(`nowitness-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      if (fallback) {
        await expect(page.locator('#paged-status')).toHaveText(messages.en[fallback]);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await download(`nowitness-after-${item.name}`, expected, page);
        assert.deepEqual(await readFile(resolve(directory, `Input/nowitness-after-${item.name}.4wp`)), Buffer.from(original));
        assert.deepEqual(errors, []);
        results.push({ name: item.name, nativeProtectedShape: true, fallback, nativeMerges: item.merges, nativeColumns: item.nativeColumns,
          nativeGetters: item.cells, storedResolution: stored, nativePages: native.pages.length, nativeTokenCounts,
          terminalLocalizedAtomicFallback: true, untouchedOriginalBytes: true });
        continue;
      }
      const sheets = page.locator('#paged-view .browser-page');
      await expect(sheets.nth(1)).toBeVisible();
      const count = await sheets.count();
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const reference = await page.evaluate(() => window.nowitnessWholeMeasurements[0]);
      assert(reference?.length === item.rows, 'Observe the actual whole table in its owning physical flow');
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
      // The frozen colgroup of every fragment carries exactly the independently resolved native columns.
      const frozen = await page.locator('#paged-view .page-body table').evaluateAll(tables => tables.map(table =>
        [...table.querySelectorAll(':scope > colgroup > col')].map(col => parseFloat(col.style.width))));
      assert(frozen.length > 1);
      for (const columns of frozen) {
        assert.equal(columns.length, item.columns);
        columns.forEach((value, index) => assert(Math.abs(value - stored.columns[index] * 4 / 3) <= .25,
          `${item.name}: frozen column ${index + 1} ${value}px, native ${stored.columns[index]}pt`));
      }
      const sourceRows = grid.rows.map(row => [...row.children].map(cell => tokens(cell.textContent)));
      const tableSheets = fragments.filter(rows => rows.length);
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
        assert(fragments[0].length > 0 && fragments[0].length < item.rows, 'No-witness table consumes bounded residual compatible-seam capacity');
      }
      if (item.name === 'rich') {
        const markers = dataRows.flatMap(row => row.flatMap(cell => cell.markers));
        assert(markers.includes('●') && markers.includes('♦'), 'Disc and diamond cell markers in merged cells');
        await expect(page.locator('#paged-view td[colspan] img')).toHaveCount(1);
        await expect(page.locator('#paged-view td[colspan] .formula-object')).toHaveCount(1);
        assert(dom.window.document.querySelectorAll('td[colspan] a[href="https://example.invalid/nowitness"]').length > 0);
        assert(await page.locator('#paged-view td[colspan] .inert-link').count() > 0);
      }
      await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.evaluate(() => {
        window.nowitnessResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.evaluate(() => window.nowitnessResize);
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const pdf = resolve(directory, `Output/nowitness-browser-${item.name}.pdf`);
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
      if (item.name === 'rich') assert.match(execFileSync('pdfimages', ['-list', pdf], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
      await download(`nowitness-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/nowitness-after-${item.name}.4wp`)), Buffer.from(original));
      if (item.name !== 'seam') await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBNOW');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`nowitness-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`nowitness-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`nowitness-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      results.push({ name: item.name, witness: witness + 1, nativeMerges: item.merges, nativeColumns: item.nativeColumns,
        nativeGetters: item.cells, storedResolution: stored, nativeBands: bands, nativePages: native.pages.length, nativeTokenCounts,
        browserPages: count, fragmentStarts: boundaries, frozenColumns: frozen, fragments, reference, printedCells,
        untouchedOriginalBytes: true, exactOrderedNativeMembership: true, exactPDFCellMembership: true, unchangedFragmentGeometry: true });
    } finally {
      await page.close();
      dom.window.close();
    }
  }
  await writeFile(resolve(directory, 'Output/nowitness-browser-report.json'), JSON.stringify(results, null, 2));
}
