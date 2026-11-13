import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { inspectPDF } from './native-print-cases.mjs';

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
}
