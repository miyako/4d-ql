import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { geometry, inspectPDF } from './native-print-cases.mjs';

const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s\u200b]/gu, '').normalize('NFC');
const tokens = text => normalize(text).match(/COLTOKEN\d+/g) || [];

function pdfColumns(sheet, paper, columns) {
  const width = (paper.width - paper.left - paper.right - (columns.count - 1) * parseFloat(columns.gap)) / columns.count;
  return Array.from({ length: columns.count }, (_, index) => {
    const left = paper.left + index * (width + parseFloat(columns.gap));
    return sheet.words.filter(word => {
      const x = (word.x + word.right) / 2;
      const y = (word.y + word.bottom) / 2;
      return x >= left - .25 && x <= left + width + .25 && y >= paper.top && y <= paper.height - paper.bottom;
    }).sort((a, b) => {
      const distance = (a.y + a.bottom - b.y - b.bottom) / 2;
      const sameLine = Math.abs(distance) <= Math.min(a.bottom - a.y, b.bottom - b.y) / 2;
      return sameLine ? a.x - b.x : distance;
    }).map(word => word.text).join('');
  });
}

export async function prepareColumnCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/paged-column-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 7);
  const results = [];
  for (const item of report.cases) {
    const source = `paged-column-source-${item.name}.4wp`;
    const files = unzipSync(await readFile(resolve(directory, `Output/paged-column-${item.name}-original.4wp`)));
    files['Resources/column-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `paged-column-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/paged-column-${item.name}-edited.4wp`)));
    const native = inspectPDF(resolve(directory, `Output/paged-column-${item.name}.pdf`));
    const papers = item.sections.sections.map(section => geometry(section.geometry));
    const columns = item.layout.sections;
    assert.deepEqual(columns[0], { count: item.name === 'three' ? 3 : item.name === 'four' ? 4 : item.name === 'narrow' ? 5 : 2,
      gap: item.name === 'three' ? '0pt' : '18pt' });
    if (item.name === 'mixed') assert.deepEqual(columns[1], { count: 3, gap: '12pt' });
    if (item.name === 'breaks') {
      assert.equal(native.pages.length, 3);
      assert.deepEqual(native.pages.map(sheet => sheet.words.filter(word => /^(COL[ABC]|PAGED)$/.test(word.text)).map(word => word.text)),
        [['COLA', 'COLB'], ['COLC'], ['PAGED']]);
      for (const [index, token, x] of [[0, 'COLA', 36], [0, 'COLB', 249], [1, 'COLC', 36], [2, 'PAGED', 36]]) {
        assert(Math.abs(native.pages[index].words.find(word => word.text === token).x - x) < .5,
          'Independent native PDF must establish equal column geometry and explicit break advancement');
      }
      assert.deepEqual(native.pages.map(sheet => sheet.words.filter(word => /^COL(?:FIRST|LEFT|RIGHT)HEADER$/.test(word.text)).map(word => word.text)),
        [['COLFIRSTHEADER'], ['COLLEFTHEADER'], ['COLRIGHTHEADER']]);
    } else {
      const nativeText = native.pages.flatMap(sheet => {
        const section = sheet.width === 420 ? 1 : 0;
        return pdfColumns(sheet, papers[section], columns[section]);
      }).join('');
      assert.deepEqual(tokens(nativeText), Array.from({ length: 120 }, (_, i) => `COLTOKEN${i}`));
      assert(normalize(nativeText).includes('LISTONE') && normalize(nativeText).includes('LISTTWO'));
      assert.match(execFileSync('pdfimages', ['-list', resolve(directory, `Output/paged-column-${item.name}.pdf`)], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    const expected = { flow: { source, action: 'identity' }, resources: source };
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('COLUMNSTART');
      await download(`paged-column-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      const supported = !['rule', 'narrow'].includes(item.name);
      let measured;
      let printed;
      if (!supported) {
        await expect(page.locator('#paged-status')).toContainText('Paged columns require');
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await expect(page.locator('#paper')).toContainText('COLUMNEND');
      } else {
        await expect(page.locator('#paged-view .browser-page').nth(1)).toBeVisible();
        measured = await page.locator('#paged-view .browser-page').evaluateAll(sheets => sheets.map(sheet => {
          const bounds = sheet.getBoundingClientRect();
          return { section: Number(sheet.dataset.section), width: parseFloat(sheet.style.width), height: parseFloat(sheet.style.height),
            areas: [...sheet.querySelectorAll('.page-area')].map(area => ({ name: area.dataset.area, text: area.textContent })),
            columns: [...sheet.querySelectorAll('.page-column')].map(column => {
              const rect = column.getBoundingClientRect();
              return { text: column.textContent, x: (rect.left - bounds.left) * .75, width: rect.width * .75,
                fits: [...column.querySelectorAll('p,li,.text-run,.preserved-object,img')].every(run =>
                  [...run.getClientRects()].every(rectangle => rectangle.top >= rect.top - .25 && rectangle.bottom <= rect.bottom + .25 &&
                    rectangle.left >= rect.left - .25 && rectangle.right <= rect.right + .25)) };
            }) };
        }));
        const bodyText = measured.flatMap(sheet => sheet.columns.map(column => column.text)).join('');
        if (item.name === 'breaks') assert.deepEqual(measured.map(sheet => sheet.columns.map(column => column.text)),
          [['COLUMNSTARTCOLA', 'COLB'], ['COLC', ''], ['PAGEDCOLUMNEND', '']]);
        else assert.deepEqual(tokens(bodyText), Array.from({ length: 120 }, (_, i) => `COLTOKEN${i}`));
        for (const sheet of measured) {
          const paper = papers[sheet.section - 1];
          const nativeColumns = columns[sheet.section - 1];
          const width = (paper.width - paper.left - paper.right - (nativeColumns.count - 1) * parseFloat(nativeColumns.gap)) / nativeColumns.count;
          assert.equal(sheet.columns.length, nativeColumns.count);
          assert.equal(sheet.width, paper.width);
          assert.equal(sheet.height, paper.height);
          for (const [index, column] of sheet.columns.entries()) {
            assert(column.fits, 'All content must fit its own column without shrinking or clipping');
            assert(Math.abs(column.width - width) < .05);
            assert(Math.abs(column.x - (paper.left + index * (width + parseFloat(nativeColumns.gap)))) < .05);
          }
        }
        await page.locator('#settings-toggle').click();
        await page.locator('#zoom').selectOption('2');
        await page.locator('#theme').selectOption('dark');
        await page.setViewportSize({ width: 390, height: 844 });
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(measured.length);
        const path = resolve(directory, `Output/paged-column-browser-${item.name}.pdf`);
        await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
        printed = inspectPDF(path);
        for (const [index, sheet] of measured.entries()) {
          const paper = papers[sheet.section - 1];
          assert.equal(printed.pages[index].width, paper.width);
          assert.equal(printed.pages[index].height, paper.height);
          const content = pdfColumns(printed.pages[index], paper, columns[sheet.section - 1]);
          assert.deepEqual(content.map(tokens), sheet.columns.map(column => tokens(column.text)),
            'Printed tokens must retain exact measured page/column membership');
          assert.deepEqual(content.map(normalize), sheet.columns.map(column => normalize(column.text)),
            'Every printed column must retain complete measured content, including styled runs, lists and inert formula text');
          for (const area of sheet.areas) assert(normalize(printed.pages[index].words.map(word => word.text).join('')).includes(normalize(area.text)));
        }
        if (item.name !== 'breaks') {
          assert.match(execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }), /\d+\s+\d+\s+image/);
          await expect(page.locator('#paged-view img')).toHaveCount(1);
          await expect(page.locator('#paged-view .paged-list-marker')).toHaveCount(2);
        }
        await page.screenshot({ path: resolve(directory, `Output/paged-column-${item.name}-mobile.png`) });
      }
      await download(`paged-column-after-${item.name}`, expected, page);
      assert.deepEqual(new Uint8Array(await readFile(resolve(directory, `Input/paged-column-after-${item.name}.4wp`))), original,
        'Preview, PDF, resize, theme and zoom must leave original archive bytes unchanged');
      await page.locator('#editing-scope').selectOption('section1FirstHeader');
      await page.locator('#paper [contenteditable]').first().fill('WEBCOLUMN');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`paged-column-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`paged-column-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`paged-column-recovered-redo-${item.name}`, edited, page);
      await page.locator('#paged-panel > summary').click();
      if (supported) await expect(page.locator('#paged-view')).toContainText('WEBCOLUMN');
      else await expect(page.locator('#paged-status')).toContainText('Paged columns require');
      assert.deepEqual(errors, []);
      assert.deepEqual(external, [], 'Column preparation must remain local-only');
      results.push({ name: item.name, supported, nativePages: native.pages.length, browserPages: measured?.length,
        measured, printedPages: printed?.pages.length, independentNativeGeometryAndBreaks: true, exactPrintColumnMembership: supported,
        unchangedOriginalBytes: true, headerUndoRecoveryExports: true,
        limits: 'Sequential browser flow only; no native wrapping, final-column balancing, formula evaluation or page-count parity.' });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/paged-column-browser-report.json'), JSON.stringify(results, null, 2));
}
