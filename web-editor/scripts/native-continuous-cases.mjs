import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { geometry, inspectPDF } from './native-print-cases.mjs';

const normalize = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, entity =>
  ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[entity]).replace(/[\s\u200b]/gu, '').normalize('NFC');
const tokens = text => normalize(text).match(/SEAM[12]TOKEN\d+/g) || [];
const positives = new Set(['compatible', 'explicit', 'overflow', 'chain', 'newpage']);

export async function prepareContinuousCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/continuous-paged-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 14);
  const results = [];
  for (const item of report.cases) {
    const source = `continuous-paged-source-${item.name}.4wp`;
    const files = unzipSync(await readFile(resolve(directory, `Output/continuous-paged-${item.name}-original.4wp`)));
    files['Resources/continuous-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
    const original = zipSync(files);
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `continuous-paged-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/continuous-paged-${item.name}-edited.4wp`)));
    const native = inspectPDF(resolve(directory, `Output/continuous-paged-${item.name}.pdf`));
    const papers = item.sections.sections.map(section => geometry(section.geometry));
    const count = item.name.includes('overflow') ? 120 : 6;
    const expectedTokens = [1, 2].flatMap(section => Array.from({ length: count }, (_, i) => `SEAM${section}TOKEN${i}`));
    assert(item.sections.breaks.some(item => item.type === 5), 'Independent native continuous break getter is required');
    assert.deepEqual(item.sections.sections.map(item => item.name), papers.map((_, i) => `Native seam ${i + 1}`));
    if (!['columns', 'column-change'].includes(item.name)) {
      assert.deepEqual(tokens(native.pages.flatMap(page => page.words.map(word => word.text)).join('')), expectedTokens);
    } else {
      assert.deepEqual(item.layout.sections, [{ count: 2, gap: '18pt' },
        item.name === 'columns' ? { count: 2, gap: '18pt' } : { count: 3, gap: '12pt' }]);
      assert.equal(native.pages.length, 1);
      assert.deepEqual(tokens(native.pages[0].words.map(word => word.text).join('')).sort(), [...expectedTokens].sort());
      const before = native.pages[0].words.find(word => word.text === 'SEAM1TOKEN2');
      const after = native.pages[0].words.find(word => word.text === 'SEAM2TOKEN0');
      assert(Math.abs(before.x - 249) < .5 && Math.abs(before.y - 60.14) < .5,
        'Native pre-seam columns rebalance into the second column despite remaining page height');
      assert(Math.abs(after.x - 36) < .5 && Math.abs(after.y - 115.94) < .5,
        'The following native section resumes below the preceding column group on the same page');
    }
    const supported = positives.has(item.name);
    if (supported) {
      assert.deepEqual(papers[0], papers[1], 'Positive originals must independently establish compatible effective geometry');
      assert(item.layout.sections.every(item => item.count === 1));
      const shared = native.pages.find(page => page.words.some(word => word.text === 'SEAM2TOKEN0'));
      assert(shared.words.some(word => /^SEAM1TOKEN\d+$/.test(word.text)) || item.name === 'explicit' &&
        shared.words.some(word => word.text === 'BEFORESEAM'), 'Native boundary must continue on the occupied physical page');
      if (item.name === 'newpage') {
        assert.equal(native.pages.length, 2);
        assert(native.pages[1].words.some(word => word.text === 'S3DEFAULTHEADER'));
      }
    }
    if (item.name === 'margin-change') {
      const word = native.pages[0].words.find(word => word.text === 'SEAM2TOKEN0');
      assert(Math.abs(word.x - 72) < .5, 'Native margin change applies at the seam, not a fabricated page break');
    }
    if (item.name === 'orientation-change') assert.deepEqual(native.pages.map(page => [page.width, page.height]), [[480, 420], [420, 480]]);
    if (item.name.startsWith('areas') || item.name.startsWith('variants')) {
      assert(native.pages[0].words.some(word => word.text === (item.name.startsWith('variants') ? 'S1FIRSTHEADER' : 'S1DEFAULTHEADER')));
      assert(!native.pages[0].words.some(word => /^S2.*(?:HEADER|FOOTER)$/.test(word.text)));
      if (item.name.endsWith('overflow')) {
        const shared = native.pages.find(page => page.words.some(word => word.text === 'SEAM2TOKEN0'));
        assert(shared.words.some(word => /^S1.*HEADER$/.test(word.text)));
        const after = native.pages[native.pages.indexOf(shared) + 1];
        assert(after.words.some(word => word.text === (item.name.startsWith('variants') ? 'S2LEFTHEADER' : 'S2DEFAULTHEADER')));
        assert(!after.words.some(word => word.text === 'S2FIRSTHEADER'), 'Native first area is not deferred to the later physical page');
      }
    }
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    const identity = { flow: { source, action: 'identity' }, resources: source };
    let measured;
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('SEAMSTART');
      await download(`continuous-paged-before-${item.name}`, identity, page);
      await page.locator('#paged-panel > summary').click();
      if (!supported) {
        await expect(page.locator('#paged-status')).toContainText('Continuous-section pages require');
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await expect(page.locator('#paper')).toContainText('SEAMEND');
      } else {
        await expect(page.locator('#paged-view .browser-page').first()).toBeVisible();
        measured = await page.locator('#paged-view .browser-page').evaluateAll(sheets => sheets.map(sheet => {
          const body = sheet.querySelector('.page-body');
          const bounds = body.getBoundingClientRect();
          return { page: Number(sheet.dataset.page), owner: Number(sheet.dataset.section), sections: sheet.dataset.sections,
            text: body.textContent, width: parseFloat(sheet.style.width), height: parseFloat(sheet.style.height),
            areas: [...sheet.querySelectorAll('.page-area')].map(area => ({ name: area.dataset.area, text: area.textContent })),
            fits: [...body.querySelectorAll('p,.text-run')].every(run => [...run.getClientRects()].every(rect =>
              rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25 &&
              rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25)) };
        }));
        assert.deepEqual(tokens(measured.map(sheet => sheet.text).join('')), expectedTokens);
        assert(measured.every((sheet, i) => sheet.fits && sheet.page === i + 1));
        assert(measured.some(sheet => sheet.sections.split(' ').includes('1') && sheet.sections.split(' ').includes('2')),
          'The evidenced seam must share a measured physical page, not just avoid a fallback notice');
        assert(await page.locator('#paged-view .text-run').filter({ hasText: /SEAM[12]TOKEN\d+/ }).evaluateAll(runs =>
          runs.length > 0 && runs.every(run => getComputedStyle(run).fontWeight === '700' &&
            getComputedStyle(run).color === 'rgb(19, 87, 36)')), 'All nonempty TOKEN runs must retain computed bold/color across fragments');
        await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
        await page.locator('#settings-toggle').click();
        await page.locator('#zoom').selectOption('2');
        await page.locator('#theme').selectOption('dark');
        await page.setViewportSize({ width: 390, height: 844 });
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(measured.length);
        const path = resolve(directory, `Output/continuous-paged-browser-${item.name}.pdf`);
        await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(path);
        for (const [i, sheet] of measured.entries()) {
          const paper = papers[sheet.owner - 1];
          assert.equal(printed.pages[i].width, sheet.width);
          assert.equal(printed.pages[i].height, sheet.height);
          const body = printed.pages[i].words.filter(word => word.y >= paper.top - .25 &&
            word.bottom <= paper.height - paper.bottom + .25).map(word => word.text).join('');
          assert.deepEqual(tokens(body), tokens(sheet.text), 'Print must retain exact measured token/page membership');
          assert.equal(normalize(body), normalize(sheet.text), 'Every measured paragraph must print completely, in order');
          assert(printed.pages[i].words.every(word => word.x >= 0 && word.right <= sheet.width + .25 &&
            word.y >= 0 && word.bottom <= sheet.height + .25));
          for (const area of sheet.areas) assert(normalize(printed.pages[i].words.map(word => word.text).join('')).includes(normalize(area.text)));
        }
        await page.screenshot({ path: resolve(directory, `Output/continuous-paged-${item.name}-mobile.png`) });
      }
      await download(`continuous-paged-after-${item.name}`, identity, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/continuous-paged-after-${item.name}.4wp`)), Buffer.from(original));
      if (item.editScope !== 'body') await page.locator('#editing-scope').selectOption(item.editScope);
      await page.locator('#paper [contenteditable]').first().fill('WEBSEAM');
      const edited = { ...identity, flow: { source: target, action: 'identity' } };
      await download(`continuous-paged-edited-${item.name}`, edited, page);
      await page.locator('#undo').click();
      await download(`continuous-paged-undo-${item.name}`, identity, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`continuous-paged-recovered-redo-${item.name}`, edited, page);
      await page.locator('#paged-panel > summary').click();
      if (supported) await expect(page.locator('#paged-view')).toContainText('WEBSEAM');
      else await expect(page.locator('#paged-status')).toContainText('Continuous-section pages require');
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      results.push({ name: item.name, supported, nativePages: native.pages.length, measured,
        unchangedOriginalBytes: true, nativeMutationUndoRecoveryExports: true,
        limits: 'Area-free compatible single-column seams only. No native wrapping, balancing, exact pagination/page counts or footer coordinates.' });
    } finally { await page.close(); }
  }
  await writeFile(resolve(directory, 'Output/continuous-paged-browser-report.json'), JSON.stringify(results, null, 2));
}
