import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { inspectPDF, geometry } from './native-print-cases.mjs';
import { messages } from '../src/i18n.js';

const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s\u200b]/gu, '');
const tokens = text => text.match(/C\d+[AB][12]/g) || [];
const markerTypes = { bullet: '\u25a0', disc: '\u25cf', circle: '\u25cb', 'hollow-square': '\u25a1', diamond: '\u2666' };
const marker = (item, column, index) => {
  if (markerTypes[item.name]) return markerTypes[item.name];
  const number = (item.name === 'limit' ? 3998 : column === 0 ? 7 : 12) + (item.flow ? index : 0);
  if (item.name === 'latin') return `${String.fromCharCode(96 + number)}.`;
  if (item.name === 'upper-latin') return `${String.fromCharCode(64 + number)}.`;
  if (item.name === 'roman') return column === 0 ? 'VII.' : 'XII.';
  if (item.name === 'lower-roman') return column === 0 ? 'vii.' : 'xii.';
  if (item.name === 'format') return `(${number})`;
  return `${number}.`;
};

export async function prepareCellListCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/cell-list-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 18);
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/cell-list-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const source = `cell-list-source-${item.name}.4wp`;
    const files = unzipSync(await readFile(resolve(directory, `Output/cell-list-${item.name}-original.4wp`)));
    files['Resources/cell-list-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `cell-list-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/cell-list-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source, pagedTable: { rows: item.rows } };
    const native = inspectPDF(resolve(directory, `Output/cell-list-${item.name}.pdf`));
    assert.equal(item.finalCells.length, item.rows * 2);
    for (const cell of item.finalCells) {
      assert(cell.paragraphs.length >= 2);
      assert.equal(cell.paragraphs[0].start, item.name === 'limit' ? 3998 : cell.column === 1 ? 7 : 12);
      assert.equal(cell.paragraphs[0].indent, item.name === 'limit' ? '48pt' : '24pt');
      assert.equal(cell.paragraphs[0].font, 'Arial');
    }
    const nativeWords = native.pages.flatMap(sheet => sheet.words);
    const areaTokens = words => words.map(word => word.text).filter(text => /^S[12](FIRST|LEFT|RIGHT)(HEADER|FOOTER)$/.test(text)).sort();
    if (item.name === 'mixed') {
      let second = false;
      for (const [index, sheet] of native.pages.entries()) {
        const first = index === 0 || sheet.words.some(word => word.text === 'CELLSECONDSECTION');
        second ||= sheet.words.some(word => word.text === 'CELLSECONDSECTION');
        const prefix = `S${second ? 2 : 1}${first ? 'FIRST' : index % 2 ? 'LEFT' : 'RIGHT'}`;
        assert.deepEqual(areaTokens(sheet.words), [`${prefix}FOOTER`, `${prefix}HEADER`],
          'Independent native PDF establishes section-first priority and physical facing parity');
      }
      assert(second, 'Independent native landscape second section is present');
    }
    const nativeTablePages = native.pages.filter(sheet => sheet.words.some(word =>
      /^C\d+[AB][12]$/.test(word.text) && Number(word.text.match(/^C(\d+)/)[1]) > item.headers));
    for (const sheet of nativeTablePages) for (let row = 1; row <= item.headers; row++) {
      for (const suffix of ['A1', 'A2', 'B1', 'B2']) assert(sheet.words.some(word => word.text === `C${row}${suffix}`),
        `${item.name}: complete native leading list-bearing headers repeat`);
    }
    for (let row = 1; row <= item.rows; row++) for (let column = 0; column < 2; column++) {
      for (let index = 0; index < 2; index++) {
        const token = `C${row}${column ? 'B' : 'A'}${index + 1}`;
        const words = nativeWords.filter(word => word.text === token);
        assert.equal(words.length, row <= item.headers ? nativeTablePages.length : 1, `${item.name}: independent native PDF token ${token}`);
        if (item.name === 'oversize') continue;
        for (const word of words) {
          const sheet = native.pages.find(sheet => sheet.words.includes(word));
          assert(sheet.words.some(candidate => normalize(candidate.text) === marker(item, column, index) &&
            Math.abs(candidate.y - word.y) < 2 && candidate.right <= word.x + .25 && word.x - candidate.right < 18),
          `${item.name}: independent native marker geometry for ${token}`);
        }
      }
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('CELLSTART');
      await download(`cell-list-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      if (item.name === 'oversize') {
        await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await download(`cell-list-after-${item.name}`, expected, page);
        assert.deepEqual(await readFile(resolve(directory, `Input/cell-list-after-${item.name}.4wp`)), Buffer.from(original));
        results.push({ name: item.name, oversizedRowFallback: true, originalBytesUnchanged: true });
        continue;
      }
      await expect(page.locator('#paged-view .browser-page').first()).toBeVisible();
      const sheets = page.locator('#paged-view .browser-page');
      const cells = await sheets.evaluateAll(sheets => sheets.map(sheet => {
        const origin = sheet.getBoundingClientRect();
        return [...sheet.querySelectorAll('.page-body table tr')].map(row => [...row.cells].map(cell => {
          const bounds = cell.getBoundingClientRect();
          return {
            text: cell.textContent, width: bounds.width, height: bounds.height,
            x: (bounds.left - origin.left) * .75, y: (bounds.top - origin.top) * .75,
            right: (bounds.right - origin.left) * .75, bottom: (bounds.bottom - origin.top) * .75,
            markers: [...cell.querySelectorAll('.paged-list-marker')].map(marker => {
              const rect = marker.getBoundingClientRect();
              const item = marker.parentElement.getBoundingClientRect();
              return { text: marker.textContent, font: getComputedStyle(marker).fontFamily,
                x: (rect.left - origin.left) * .75, y: (rect.top - origin.top) * .75,
                right: (rect.right - origin.left) * .75, bottom: (rect.bottom - origin.top) * .75,
                contentX: (item.left - origin.left) * .75 };
            }),
          };
        }));
      }));
      const widths = cells.flat().map(row => row.map(cell => cell.width));
      for (const value of widths) for (const [column, width] of value.entries()) {
        assert(Math.abs(width * .75 - (column ? 140 : 90)) < .05, `${item.name}: frozen native unequal widths`);
      }
      const rows = cells.flat();
      const dataRows = rows.filter(row => Number(tokens(row[0].text)[0].match(/^C(\d+)/)[1]) > item.headers);
      assert.deepEqual(dataRows.flatMap(row => row.flatMap(cell => tokens(cell.text))),
        Array.from({ length: item.rows - item.headers }, (_, index) => {
          const row = item.headers + index + 1;
          return [`C${row}A1`, `C${row}A2`, `C${row}B1`, `C${row}B2`];
        }).flat(), `${item.name}: complete ordered row and cell membership`);
      for (const pageRows of cells.filter(rows => rows.length)) {
        for (let header = 0; header < item.headers; header++) assert.equal(tokens(pageRows[header][0].text)[0], `C${header + 1}A1`);
        for (const row of pageRows) for (const [column, cell] of row.entries()) {
          assert.deepEqual(cell.markers.map(value => value.text), [marker(item, column, 0), marker(item, column, 1)]);
          for (const value of cell.markers) {
            assert.match(value.font, /Arial/);
            assert(value.x >= cell.x - .25 && value.right <= value.contentX && value.y >= cell.y - .25 &&
              value.bottom <= cell.bottom + .25, `${item.name}: marker stays inside its owning complete cell`);
          }
        }
      }
      const bold = await page.locator('#paged-view li .text-run').evaluateAll(runs => {
        const selected = runs.filter(run => /C\d+[AB][12]/.test(run.textContent));
        return selected.length > 0 && selected.every(run =>
          Number(getComputedStyle(run).fontWeight) >= 600 && getComputedStyle(run).color === 'rgb(19, 87, 36)');
      });
      assert(bold, `${item.name}: nonempty per-TOKEN computed bold/color`);
      if (item.name === 'seam') {
        await expect(sheets.first()).toHaveAttribute('data-sections', '1 2');
        assert(cells[0].length > 0 && cells[0].length < item.rows, 'Cell lists consume residual seam capacity');
      }
      const count = await sheets.count();
      const pageGeometry = await sheets.evaluateAll(sheets => sheets.map(sheet => ({
        section: Number(sheet.dataset.section), width: Number.parseFloat(sheet.style.width), height: Number.parseFloat(sheet.style.height),
        areas: [...sheet.querySelectorAll('.page-area')].map(area => area.textContent).sort(),
      })));
      const seen = new Set();
      for (const [index, sheet] of pageGeometry.entries()) {
        const nativeGeometry = geometry(item.sections.sections[sheet.section - 1].geometry);
        assert(Math.abs(sheet.width - nativeGeometry.width) < .05 && Math.abs(sheet.height - nativeGeometry.height) < .05,
          'Browser paper dimensions match independent native getters');
        if (item.name === 'mixed') {
          const prefix = `S${sheet.section}${!seen.has(sheet.section) ? 'FIRST' : index % 2 ? 'LEFT' : 'RIGHT'}`;
          assert.deepEqual(sheet.areas, [`${prefix}FOOTER`, `${prefix}HEADER`], 'Cell-list pages retain physical first/facing area semantics');
        }
        seen.add(sheet.section);
      }
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.evaluate(() => {
        window.cellListResize = new Promise(resolve => window.addEventListener('resize', () => resolve(), { once: true }));
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.evaluate(() => window.cellListResize);
      await expect(sheets).toHaveCount(count);
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const path = resolve(directory, `Output/cell-list-browser-${item.name}.pdf`);
      await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(path);
      assert(printed.pages.length >= count);
      for (const [index, sheet] of pageGeometry.entries()) {
        assert(Math.abs(printed.pages[index].width - sheet.width) < 1 && Math.abs(printed.pages[index].height - sheet.height) < 1,
          'Printed cell-list sheets retain unscaled native paper geometry');
        if (item.name === 'mixed') assert.deepEqual(areaTokens(printed.pages[index].words), sheet.areas,
          'Printed physical first/facing areas match measured cell-list pages');
      }
      assert.deepEqual(printed.pages.slice(count).flatMap(sheet => tokens(sheet.words.map(word => word.text).join(''))), [],
        'Unused-area appendices must not duplicate any table content');
      const printedCells = cells.map((rows, index) => rows.map(row => row.map(cell =>
        printed.pages[index].words.filter(word => {
          const x = (word.x + word.right) / 2;
          const y = (word.y + word.bottom) / 2;
          return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
        }).sort((a, b) => Math.abs(a.y - b.y) > 1 ? a.y - b.y : a.x - b.x).map(word => word.text).join(''))));
      assert.deepEqual(printedCells.map(rows => rows.map(row => row.map(normalize))),
        cells.map(rows => rows.map(row => row.map(cell => normalize(cell.text)))),
        `${item.name}: every printed cell, marker and wrapped word matches measured membership`);
      for (const [index, pageRows] of cells.entries()) for (const row of pageRows) for (const cell of row) {
        for (const value of cell.markers) {
          assert(printed.pages[index].words.some(word => normalize(word.text) === value.text &&
            Math.abs(word.x - value.x) < .5 && Math.abs(word.right - value.right) < .5 &&
            word.y >= value.y - 1 && word.bottom <= value.bottom + 1), `${item.name}: unscaled PDF marker geometry`);
        }
      }
      if (item.name === 'mixed') {
        await expect(page.locator('#paged-view img')).toHaveCount(1);
        await expect(page.locator('#paged-view .formula-object')).toHaveCount(1);
        assert.match(execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
      }
      await download(`cell-list-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/cell-list-after-${item.name}.4wp`)), Buffer.from(original));
      if (item.name === 'seam') await page.locator('#editing-scope').selectOption('body');
      else await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBCELL');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`cell-list-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`cell-list-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`cell-list-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      results.push({ name: item.name, nativePages: native.pages.length, browserPages: count,
        cells, printedCells, exactCellMarkerMembership: true, originalBytesUnchanged: true, nativeUndoRecoveryExports: true });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/cell-list-browser-report.json'), JSON.stringify(results, null, 2));
}
