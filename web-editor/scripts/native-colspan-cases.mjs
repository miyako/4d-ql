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

const tokens = text => text.match(/R\d+[ABC]/g) || [];
const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s\u200b]/gu, '');

export async function prepareColspanCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/colspan-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 10);
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/colspan-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const files = unzipSync(await readFile(resolve(directory, `Output/colspan-${item.name}-original.4wp`)));
    const html = strFromU8(files[Object.keys(files).find(name => name.endsWith('.html'))]);
    const dom = new JSDOM(html, { contentType: 'application/xhtml+xml' });
    const grid = nativeTableGrid(dom.window.document.querySelector('table'));
    const excluded = ['no-witness', 'vertical', 'mixed', 'overflow'].includes(item.name);
    const witness = grid.rows.findIndex(row => [...row.children].every(cell => !cell.hasAttribute('colspan') && !cell.hasAttribute('rowspan')));
    assert.equal(grid.columns, 3);
    assert.equal(grid.rows.length, 26);
    assert(grid.merged, 'Native originals must actually serialize merges');
    if (item.name === 'no-witness') assert.equal(witness, -1);
    else if (item.name === 'vertical' || item.name === 'mixed') assert(dom.window.document.querySelector('td[rowspan]'), 'Native excluded original must actually retain a vertical span');
    else assert(witness >= 1, 'Native width witness is deliberately not the first row');
    if (item.name === 'late-witness' || item.name === 'two-headers') assert.equal(witness, 5);
    const source = `colspan-source-${item.name}.4wp`;
    files['Resources/colspan-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `colspan-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/colspan-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source, pagedTable: { rows: 26, columns: 3 } };
    const native = inspectPDF(resolve(directory, `Output/colspan-${item.name}.pdf`));
    const nativeTablePages = native.pages.filter(sheet => sheet.words.some(word =>
      tokens(word.text).some(token => Number(token.match(/^R(\d+)/)[1]) > item.headers)));
    if (!excluded) {
      assert.equal(item.cells.length, 78);
      for (let row = 1; row <= 26; row++) for (const column of ['A', 'B', 'C']) {
        const token = `R${row}${column}`;
        assert.equal(native.pages.flatMap(sheet => sheet.words).filter(word => tokens(word.text).includes(token)).length,
          row <= item.headers ? nativeTablePages.length : 1, `${item.name}: complete independent native PDF token ${token}`);
      }
      const witnessCells = item.cells.filter(cell => cell.row === witness + 1);
      assert.deepEqual(witnessCells.map(cell => cell.width), ['50pt', '70pt', '110pt']);
      if (item.name === 'rich') {
        const text = native.pages.flatMap(sheet => sheet.words).map(word => word.text).join('');
        assert(text.includes('\u25cf') && text.includes('\u2666') && text.includes('SPANCACHE'));
      }
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.colspanWholeMeasurements = [];
      const bounds = Element.prototype.getBoundingClientRect;
      Element.prototype.getBoundingClientRect = function () {
        if (this.localName === 'table' && this.closest('.paged-measure .page-body') && this.style.tableLayout !== 'fixed') {
          window.colspanWholeMeasurements.push([...this.rows].map(row => [...row.cells].map(cell => {
            const rect = bounds.call(cell);
            return { width: rect.width, height: rect.height, span: cell.colSpan };
          })));
        }
        return bounds.call(this);
      };
    });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('SPANSTART');
      await download(`colspan-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      if (excluded) {
        await expect(page.locator('#paged-status')).toHaveText(messages.en[item.name === 'overflow' ? 'pagedOverflow' : 'pagedTables']);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await download(`colspan-after-${item.name}`, expected, page);
        assert.deepEqual(await readFile(resolve(directory, `Input/colspan-after-${item.name}.4wp`)), Buffer.from(original));
        assert.deepEqual(errors, []);
        results.push({ name: item.name, nativeExcludedShape: true, terminalLocalizedAtomicFallback: true, untouchedOriginalBytes: true });
        continue;
      }
      const sheets = page.locator('#paged-view .browser-page');
      await expect(sheets.nth(1)).toBeVisible();
      const count = await sheets.count();
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const reference = await page.evaluate(() => window.colspanWholeMeasurements[0]);
      assert(reference?.length === 26, 'Observe the actual unfrozen whole table in its owning physical flow, not a continuous-view proxy');
      const cells = await sheets.evaluateAll(sheets => sheets.map(sheet => {
        const origin = sheet.getBoundingClientRect();
        return [...sheet.querySelectorAll('.page-body table tr')].map(row => [...row.cells].map(cell => {
          const bounds = cell.getBoundingClientRect();
          const runs = [...cell.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img')];
          return { text: cell.textContent, span: cell.colSpan, width: bounds.width, height: bounds.height,
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
      const dataRows = cells.flat().filter(row => Number(tokens(row[0].text)[0].match(/^R(\d+)/)[1]) > item.headers);
      assert.deepEqual(dataRows.map(row => row.map(cell => tokens(cell.text))), sourceRows.slice(item.headers),
        `${item.name}: complete ordered native-source row/cell/token membership`);
      for (const rows of cells.filter(rows => rows.length)) {
        for (let header = 0; header < item.headers; header++) {
          assert.deepEqual(rows[header].map(cell => tokens(cell.text)), sourceRows[header], 'Complete native leading header repeats');
        }
        for (const row of rows) {
          const index = Number(tokens(row[0].text)[0].match(/^R(\d+)/)[1]) - 1;
          for (const [column, cell] of row.entries()) {
            assert.equal(cell.span, reference[index][column].span, 'Native horizontal merge preserved');
            assert(Math.abs(cell.width - reference[index][column].width) <= .25 &&
              Math.abs(cell.height - reference[index][column].height) <= .25,
            `${item.name} row ${index + 1} cell ${column + 1}: frozen ${cell.width}x${cell.height}, whole ${reference[index][column].width}x${reference[index][column].height}`);
            assert(cell.inside, 'Every inline atom and marker stays in its owning cell');
          }
        }
      }
      if (item.name === 'seam') {
        await expect(sheets.first()).toHaveAttribute('data-sections', '1 2');
        assert(cells[0].length > 0 && cells[0].length < 26, 'Merged table consumes bounded residual compatible-seam capacity');
      }
      if (item.name === 'rich') {
        await expect(page.locator('#paged-view img')).toHaveCount(1);
        await expect(page.locator('#paged-view .formula-object')).toHaveCount(1);
        assert.equal(dom.window.document.querySelectorAll('td[colspan] a[href="https://example.invalid/span"]').length, 2);
        await expect(page.locator('#paged-view .inert-link')).toHaveCount(2);
        await expect(page.locator('#paged-view td[colspan] img')).toHaveCount(1);
        await expect(page.locator('#paged-view td[colspan] .formula-object')).toHaveCount(1);
        for (const rows of cells.filter(rows => rows.length)) {
          assert.deepEqual(rows[0].flatMap(cell => cell.markers), ['\u25cf', '\u25cf']);
        }
        assert.deepEqual(cells.flat().filter(row => tokens(row[0].text)[0] === 'R4A').flatMap(row =>
          row.flatMap(cell => cell.markers)), ['\u2666', '\u2666']);
        assert.deepEqual(cells.flat().filter(row => !['R1A', 'R4A'].includes(tokens(row[0].text)[0])).flatMap(row =>
          row.flatMap(cell => cell.markers)), []);
        assert(await page.locator('#paged-view .inert-link .text-run').evaluateAll(runs =>
          runs.length > 0 && runs.every(run => getComputedStyle(run).fontStyle === 'italic')));
      }
      await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.evaluate(() => {
        window.colspanResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.evaluate(() => window.colspanResize);
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const pdf = resolve(directory, `Output/colspan-browser-${item.name}.pdf`);
      await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(pdf);
      assert(printed.pages.length >= count);
      assert.deepEqual(printed.pages.slice(count).flatMap(sheet => tokens(sheet.words.map(word => word.text).join(''))), []);
      const printedCells = cells.map((rows, index) => rows.map(row => row.map(cell =>
        printed.pages[index].words.filter(word => {
          const x = (word.x + word.right) / 2;
          const y = (word.y + word.bottom) / 2;
          return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
        }).sort((a, b) => Math.abs(a.y - b.y) > 1 ? a.y - b.y : a.x - b.x).map(word => word.text).join(''))));
      assert.deepEqual(printedCells.map(rows => rows.map(row => row.map(normalize))),
        cells.map(rows => rows.map(row => row.map(cell => normalize(cell.text)))),
        `${item.name}: exact complete printed cell/text/marker/formula membership`);
      for (const sheet of printed.pages.slice(0, count)) {
        assert(Math.abs(sheet.width - 300) < 1 && Math.abs(sheet.height - 360) < 1, 'Unscaled native paper geometry');
      }
      if (item.name === 'rich') assert.match(execFileSync('pdfimages', ['-list', pdf], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
      await download(`colspan-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/colspan-after-${item.name}.4wp`)), Buffer.from(original));
      if (item.name !== 'seam') await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBSPAN');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`colspan-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`colspan-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`colspan-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      results.push({ name: item.name, witness: witness + 1, nativeGetters: item.cells, nativePages: native.pages.length,
        browserPages: count, cells, reference, printedCells, untouchedOriginalBytes: true,
        exactOrderedNativeMembership: true, exactPDFCellMembership: true, unchangedFragmentGeometry: true });
    } finally {
      await page.close();
      dom.window.close();
    }
  }
  await writeFile(resolve(directory, 'Output/colspan-browser-report.json'), JSON.stringify(results, null, 2));
}
