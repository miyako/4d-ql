import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { inspectPDF } from './native-print-cases.mjs';
import { prepareColumnCases } from './native-column-cases.mjs';
import { prepareContinuousCases } from './native-continuous-cases.mjs';
import { prepareCellListCases } from './native-cell-list-cases.mjs';
import { prepareColspanCases } from './native-colspan-cases.mjs';
import { prepareRowspanCases } from './native-rowspan-cases.mjs';

export async function preparePagedCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/paged-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 4);
  const results = [];
  const tokens = words => words.filter(word => /^S[12](?:FIRST|LEFT|RIGHT|DEFAULT)(?:HEADER|FOOTER)$/.test(word)).sort();
  for (const item of report.cases) {
    const expected = `paged-${item.name}-original.4wp`;
    const native = inspectPDF(resolve(directory, `Output/paged-${item.name}.pdf`));
    assert.equal(native.pages.length, 6, 'Native explicit section/page break oracle must have six pages');
    const expectedAreas = item.name === 'missing' ?
      [['S1FIRSTFOOTER'], ['S1LEFTFOOTER', 'S1LEFTHEADER'], ['S1RIGHTHEADER'], [], [], []] :
      item.name === 'left' ?
        [['S1FIRSTFOOTER', 'S1FIRSTHEADER'], ['S1RIGHTFOOTER', 'S1RIGHTHEADER'], ['S1LEFTFOOTER', 'S1LEFTHEADER'],
          ['S2FIRSTFOOTER', 'S2FIRSTHEADER'], ['S2LEFTFOOTER', 'S2LEFTHEADER'], ['S2RIGHTFOOTER', 'S2RIGHTHEADER']] :
        [['S1FIRSTFOOTER', 'S1FIRSTHEADER'], ['S1LEFTFOOTER', 'S1LEFTHEADER'], ['S1RIGHTFOOTER', 'S1RIGHTHEADER'],
          ['S2FIRSTFOOTER', 'S2FIRSTHEADER'], ['S2RIGHTFOOTER', 'S2RIGHTHEADER'], ['S2LEFTFOOTER', 'S2LEFTHEADER']];
    assert.deepEqual(native.pages.map(sheet => tokens(sheet.words.map(word => word.text))), expectedAreas,
      'Independent native PDF must establish section-first reset, physical parity and missing-area semantics');
    const files = unzipSync(await readFile(resolve(directory, 'Output', expected)));
    files['Resources/paged-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const source = `paged-source-${item.name}.4wp`;
    const bytes = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), bytes);
    cases.push({ name: `paged-source-${item.name}`, file: source, header: { expected }, resources: source });
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('PAGED1');
      await download(`paged-before-${item.name}`, { header: { expected }, resources: source }, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view .browser-page')).toHaveCount(6);
      const preview = await page.locator('#paged-view .browser-page').evaluateAll(sheets => sheets.map(sheet => ({
        text: [...sheet.querySelectorAll('.page-area')].map(area => area.textContent).sort(),
        body: sheet.querySelector('.page-body').textContent,
        width: parseFloat(sheet.style.width), height: parseFloat(sheet.style.height),
      })));
      assert.deepEqual(preview.map(sheet => sheet.text), expectedAreas);
      for (let index = 0; index < 6; index++) {
        assert.equal(preview[index].body, `PAGED${index + 1}`);
        assert(Math.abs(preview[index].width - native.pages[index].width) < 1);
        assert(Math.abs(preview[index].height - native.pages[index].height) < 1);
      }
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.setViewportSize({ width: 390, height: 844 });
      await expect(page.locator('#paged-view .browser-page')).toHaveCount(6);
      const path = resolve(directory, `Output/paged-browser-${item.name}.pdf`);
      await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(path);
      assert.deepEqual(printed.pages.slice(0, 6).map(sheet => tokens(sheet.words.map(word => word.text))), expectedAreas);
      for (let index = 0; index < 6; index++) {
        assert.equal(printed.pages[index].words.filter(word => /^PAGED\d+$/.test(word.text)).map(word => word.text).join(''), `PAGED${index + 1}`);
        assert(Math.abs(printed.pages[index].width - native.pages[index].width) < 1);
        assert(Math.abs(printed.pages[index].height - native.pages[index].height) < 1);
      }
      await download(`paged-after-${item.name}`, { header: { expected }, resources: source }, page);
      assert.deepEqual(new Uint8Array(await readFile(resolve(directory, `Input/paged-after-${item.name}.4wp`))), bytes,
        'Preview/print/resize/zoom/theme changed authoritative archive bytes');
      await page.locator('#editing-scope').selectOption('section1FirstFooter');
      await page.locator('#paper [contenteditable]').first().fill('WEBPAGED');
      const edited = { header: { expected: `paged-${item.name}-edited.4wp` }, resources: source };
      await download(`paged-edited-${item.name}`, edited, page);
      await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBPAGED');
      await page.locator('#undo').click();
      await download(`paged-undo-${item.name}`, { header: { expected }, resources: source }, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`paged-recovered-redo-${item.name}`, edited, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view .browser-page')).toHaveCount(6);
      await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBPAGED');
      assert.deepEqual(errors, []);
      results.push({ name: item.name, nativePages: 6, browserBodyPages: 6, printedPages: printed.pages.length,
        selectedAreas: expectedAreas, geometry: preview.map(({ width, height }) => ({ width, height })),
        unchangedOriginalArchive: true, realBrowserUndoRecoveryExports: true,
        limits: 'Native content selection and paper geometry only. Browser paragraph boundaries and top/bottom area bands are not native line/position parity.' });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/paged-browser-report.json'), JSON.stringify(results, null, 2));
  await prepareExpandedCases(directory, cases, browser, url, download);
  await preparePagedTableCases(directory, cases, browser, url, download);
  await prepareColumnCases(directory, cases, browser, url, download);
  await prepareContinuousCases(directory, cases, browser, url, download);
  await prepareCellListCases(directory, cases, browser, url, download);
  await prepareColspanCases(directory, cases, browser, url, download);
  await prepareRowspanCases(directory, cases, browser, url, download);
}

async function preparePagedTableCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/paged-table-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 3);
  const results = [];
  const rowTokens = text => text.match(/TABROW\d+/g) || [];
  for (const item of report.cases) {
    const source = `paged-table-source-${item.name}.4wp`;
    const files = unzipSync(await readFile(resolve(directory, `Output/paged-table-${item.name}-original.4wp`)));
    files['Resources/table-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `paged-table-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/paged-table-${item.name}-edited.4wp`)));
    const native = inspectPDF(resolve(directory, `Output/paged-table-${item.name}.pdf`));
    assert.deepEqual(native.pages.flatMap(sheet => sheet.words.map(word => word.text).filter(word => /^TABROW\d+$/.test(word))),
      Array.from({ length: 40 }, (_, i) => `TABROW${i}`));
    assert.equal(item.cells.length, (40 + item.headers) * 2);
    for (const cell of item.cells) assert.equal(cell.width, cell.column === 1 ? '70pt' : '130pt');
    if (item.headers) assert(native.pages.filter(sheet => sheet.words.some(word => /^TABROW\d+$/.test(word.text)))
      .every(sheet => sheet.words.some(word => word.text === 'HEADA')), 'Independent native repeated-header PDF evidence');
    if (item.headers === 2) assert(native.pages.filter(sheet => sheet.words.some(word => /^TABROW\d+$/.test(word.text)))
      .every(sheet => sheet.words.some(word => word.text === 'HEAD2A')), 'Independent second native header row must repeat');
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const expected = { flow: { source, action: 'identity' }, resources: source, pagedTable: { rows: 40 + item.headers } };
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('TABLESTART');
      await download(`paged-table-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view .browser-page').nth(1)).toBeVisible();
      const bodies = page.locator('#paged-view .browser-page .page-body');
      const content = await bodies.allTextContents();
      assert.deepEqual(rowTokens(content.join(' ')), Array.from({ length: 40 }, (_, i) => `TABROW${i}`));
      const tables = page.locator('#paged-view table');
      const measured = await tables.evaluateAll(tables => tables.map(table => ({
        widths: [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width),
        rows: [...table.rows].map(row => row.textContent),
        heights: [...table.rows].map(row => row.getBoundingClientRect().height),
        bottom: table.getBoundingClientRect().bottom,
        bodyBottom: table.closest('.page-body').getBoundingClientRect().bottom,
      })));
      const cells = await page.locator('#paged-view .browser-page').evaluateAll(sheets => sheets.map(sheet => {
        const page = sheet.getBoundingClientRect();
        return [...sheet.querySelectorAll('.page-body table td,.page-body table th')].map(cell => {
          const bounds = cell.getBoundingClientRect();
          return { text: cell.textContent, x: (bounds.left - page.left) * .75, y: (bounds.top - page.top) * .75,
            right: (bounds.right - page.left) * .75, bottom: (bounds.bottom - page.top) * .75 };
        });
      }));
      for (const fragment of measured) {
        assert.deepEqual(fragment.widths, measured[0].widths);
        for (const [column, width] of fragment.widths.entries()) assert(Math.abs(width * .75 - Number.parseFloat(item.cells[column].width)) < .05,
          'Browser column geometry must retain the independently native-authored width');
        assert(fragment.bottom <= fragment.bodyBottom + .25);
        assert(fragment.rows.some(text => /TABROW\d+/.test(text)));
        if (item.headers) assert(fragment.rows[0].includes('HEADA'));
        if (item.headers === 2) assert(fragment.rows[1].includes('HEAD2A'));
      }
      for (let i = 0; i < measured.length - 1; i++) {
        const nextRow = measured[i + 1].heights[item.headers];
        assert(measured[i].bottom + nextRow > measured[i].bodyBottom - .25,
          'A fragment must exhaust the measured row capacity, not split arbitrarily');
      }
      const count = await bodies.count();
      await page.locator('#settings-toggle').click();
      await page.locator('#zoom').selectOption('2');
      await page.locator('#theme').selectOption('dark');
      await page.setViewportSize({ width: 390, height: 844 });
      await expect(bodies).toHaveCount(count);
      const path = resolve(directory, `Output/paged-table-browser-${item.name}.pdf`);
      await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(path);
      if (item.name === 'mixed') {
        assert.match(execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
        await expect(page.locator('#paged-view img')).toHaveCount(1);
      }
      const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
        ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s\u200b]/gu, '');
      const printedCells = cells.map((cells, index) => cells.map(cell => printed.pages[index].words.filter(word => {
        const x = (word.x + word.right) / 2;
        const y = (word.y + word.bottom) / 2;
        return x >= cell.x - .25 && x <= cell.right + .25 && y >= cell.y - .25 && y <= cell.bottom + .25;
      }).sort((a, b) => Math.abs(a.y - b.y) > 1 ? a.y - b.y : a.x - b.x).map(word => word.text).join('')));
      assert.deepEqual(printedCells.map(cells => cells.map(normalize)), cells.map(cells => cells.map(cell => normalize(cell.text))),
        'Every printed cell must retain complete content, including tokens wrapped across measured lines');
      assert.deepEqual(printedCells.map(cells => cells.flatMap(text => rowTokens(normalize(text)))), content.map(rowTokens),
        'Print must match actual measured row/page membership');
      const previewWidths = measured.map(fragment => fragment.widths);
      await page.emulateMedia({ media: 'print' });
      await page.evaluate(() => dispatchEvent(new Event('beforeprint')));
      assert.deepEqual(await page.locator('#print-document table').evaluateAll(tables => tables.map(table =>
        [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width))), previewWidths);
      await page.evaluate(() => dispatchEvent(new Event('afterprint')));
      await page.emulateMedia({ media: 'screen' });
      await page.evaluate(() => { window.print = () => { dispatchEvent(new Event('beforeprint')); dispatchEvent(new Event('afterprint')); }; });
      await page.locator('#print-toggle').click();
      await page.locator('#print-open').click();
      await download(`paged-table-after-${item.name}`, expected, page);
      assert.deepEqual(new Uint8Array(await readFile(resolve(directory, `Input/paged-table-after-${item.name}.4wp`))), original);
      await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBTABLE');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`paged-table-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`paged-table-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`paged-table-recovered-redo-${item.name}`, edited, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view')).toContainText('WEBTABLE');
      assert.deepEqual(errors, []);
      results.push({ name: item.name, nativePages: native.pages.length, browserPages: count,
        measured, cells, printedCells, exactPrintRowMembership: true, printWidths: previewWidths, originalBytesUnchanged: true,
        independentNativeGetters: true, actualUndoRecoveryExports: true, printCancel: true });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/paged-table-browser-report.json'), JSON.stringify(results, null, 2));
}

export function verifyPagedTableCase(entry, actual) {
  assert.deepEqual(actual.tableImported, actual.tableExpected, `${entry.name}: native imported table getters changed`);
  assert.deepEqual(actual.tableReopened, actual.tableExpected, `${entry.name}: native reopened table getters changed`);
}

async function prepareExpandedCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/expanded-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 3);
  const results = [];
  for (const item of report.cases) {
    const source = `expanded-source-${item.name}.4wp`;
    const files = unzipSync(await readFile(resolve(directory, `Output/expanded-${item.name}-original.4wp`)));
    files['Resources/expanded-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const editedSource = `expanded-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', editedSource), await readFile(resolve(directory, `Output/expanded-${item.name}-edited.4wp`)));
    const native = inspectPDF(resolve(directory, `Output/expanded-${item.name}.pdf`));
    for (const token of item.tokens) assert(native.text.includes(token), `${item.name}: missing native PDF token ${token}`);
    const page = await browser.newPage({ acceptDownloads: true });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('EXPANDED');
      const expected = { flow: { source, action: 'identity' }, resources: source };
      await download(`expanded-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view .browser-page').nth(1)).toBeVisible();
      const bodies = page.locator('#paged-view .page-body');
      const content = await bodies.allTextContents();
      for (const token of item.tokens) assert(content.join('').includes(token), `${item.name}: lost preview token ${token}`);
      assert(await bodies.evaluateAll(bodies => bodies.every(body => {
        const bounds = body.getBoundingClientRect();
        return [...body.querySelectorAll('.text-run,.preserved-object,img')].every(run =>
          [...run.getClientRects()].every(rect => rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25 &&
            rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25));
      })), 'Measured fragment content exceeds body boundaries');
      const count = await bodies.count();
      await page.locator('#settings-toggle').click();
      await page.locator('#zoom').selectOption('2');
      await page.locator('#theme').selectOption('dark');
      await page.setViewportSize({ width: 390, height: 844 });
      await expect(bodies).toHaveCount(count);
      const path = resolve(directory, `Output/expanded-browser-${item.name}.pdf`);
      await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(path);
      assert.equal(printed.pages.length, count);
      assert.deepEqual(printed.pages.map(sheet => sheet.words.map(word => word.text).filter(word => /^FLOW\d+$/.test(word)).sort()),
        content.map(text => (text.match(/FLOW\d+/g) || []).sort()), 'Printed tokens must match measured page membership exactly');
      if (item.name === 'images') {
        assert.match(execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
        await expect(page.locator('#paged-view img')).toHaveCount(1);
        assert(printed.text.includes('EXPANDEDCACHE'));
      }
      await download(`expanded-after-${item.name}`, expected, page);
      assert.deepEqual(new Uint8Array(await readFile(resolve(directory, `Input/expanded-after-${item.name}.4wp`))), original);
      await page.locator('#paper [contenteditable]').first().fill('WEBEXPANDED');
      const edited = { flow: { source: editedSource, action: 'identity' }, resources: source };
      await download(`expanded-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`expanded-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`expanded-recovered-redo-${item.name}`, edited, page);
      await page.locator('#paged-panel > summary').click();
      await expect(page.locator('#paged-view')).toContainText('WEBEXPANDED');
      results.push({ name: item.name, browserPages: count, nativePages: native.pages.length, exactPageTokens: true,
        unchangedOriginalArchive: true, independentNativeEditTarget: true, actualUndoRecoveryExports: true });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/expanded-browser-report.json'), JSON.stringify(results, null, 2));
}
