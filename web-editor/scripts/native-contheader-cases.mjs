import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { messages } from '../src/i18n.js';
import { inspectPDF } from './native-print-cases.mjs';
import { atParity } from './native-continuous-cases.mjs';

// Browser outcome per native shape (wp_contheader_probe, full 4D 21.2 F0012102). Native PDFs, read page by page, are
// the oracle for which section's header and footer text is drawn on which page, never for positions or page counts.
export const contheaderShapes = {
  'default-both': 'paged', 'outgoing-only': 'paged', 'incoming-only': 'paged', 'first-incoming': 'paged',
  'facing-incoming': 'paged', 'first-facing-both': 'paged', 'first-outgoing': 'paged', 'chain-short': 'paged',
  'chain-long': 'paged', 'page-break-incoming': 'paged',
  // The incoming section's content starts at the top of a new page: native uses its first-page areas there.
  'fresh-top': 'paged',
  'single-page': 'paged', unicode: 'paged', 'newpage-after': 'paged', 'footer-only': 'paged',
  // Native continues section 2 on the shared page at x = 72 pt: a mid-page body geometry change stays protected.
  'margin-areas': 'fallback',
  // Native starts a new landscape page for section 2: geometry-changing seams stay protected.
  'orientation-areas': 'fallback',
};
const areaToken = /CH\d(?:DEFAULT|FIRST|LEFT|RIGHT)(?:HEADER|FOOTER)/g;
const bodyToken = /^(?:CHSTART|CH\d+BODY\d+)$/;
const sectionOf = word => word === 'CHSTART' ? 1 : Number(word.match(/^CH(\d+)BODY/)[1]);
const firstWord = section => section === 1 ? 'CHSTART' : `CH${section}BODY1`;

// The native membership rule, independent of the editor: a page draws the areas of the section in effect at its top
// (the owner), that section's first-page areas only on the page where its content starts, otherwise physical
// left/right parity (page 1 is a right page), otherwise its default areas; a section without areas draws none.
function ruleAreas(requested, owner, startsHere, pageNumber) {
  const spec = requested[owner - 1];
  if (spec.areas === 'none') return [];
  const variant = startsHere && spec.areas.includes('first') ? 'FIRST' :
    spec.areas.includes('facing') ? (pageNumber % 2 ? 'RIGHT' : 'LEFT') : 'DEFAULT';
  return (spec.areas === 'footer' ? ['FOOTER'] : ['HEADER', 'FOOTER']).map(kind => `CH${owner}${variant}${kind}`).sort();
}
function analyse(pages) {
  return pages.map((page, index) => {
    const body = page.body;
    assert(body.length, 'Every page carries body text');
    const owner = sectionOf(body[0]);
    return { page: index + 1, owner, startsHere: body.includes(firstWord(owner)), body, areas: [...page.areas].sort() };
  });
}

export async function prepareContheaderCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/contheader-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(contheaderShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/contheader-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const outcome = contheaderShapes[item.name];
    const requested = item.requested;
    // Independent native getters: every stored area holds exactly the requested text, and the stored file alone
    // reproduces the sections, the areas and the native PDF after re-import.
    const stored = item.areas.map(area => `${area.section}:${area.variant}:${area.kind}:${area.text}`).sort();
    const wanted = requested.flatMap((spec, index) => spec.areas === 'none' ? [] : ['DEFAULT',
      ...(spec.areas.includes('first') ? ['FIRST'] : []), ...(spec.areas.includes('facing') ? ['LEFT', 'RIGHT'] : [])]
      .flatMap(variant => (spec.areas === 'footer' ? ['FOOTER'] : ['HEADER', 'FOOTER']).map(kind =>
        `${index + 1}:${variant}:${kind}:CH${index + 1}${variant}${kind}${spec.text || ''}`))).sort();
    assert.deepEqual(stored, wanted, `${item.name}: native area getters`);
    assert.deepEqual(item.reopened, item.sections, `${item.name}: re-imported native section getters`);
    assert.equal(item.sections.sections.length, requested.length);
    // Paragraph breaks (type 4) aside, the native break getters list page (2), new-page section (1) and continuous
    // section (5) breaks in document order.
    assert.deepEqual(item.sections.breaks.map(entry => entry.type).filter(type => type !== 4),
      requested.flatMap((spec, index) => [...(spec.pageBreak ? [2] : []), ...(index < item.joins.length ? [item.joins[index] === 'C' ? 5 : 1] : [])]),
      `${item.name}: native break getters`);
    const native = inspectPDF(resolve(directory, `Output/contheader-${item.name}.pdf`));
    const reopened = inspectPDF(resolve(directory, `Output/contheader-${item.name}-reopened.pdf`));
    const nativeWords = native.pages.map(page => page.words.map(word => word.text));
    assert.deepEqual(reopened.pages.map(page => page.words.map(word => word.text)), nativeWords, `${item.name}: stored file alone reproduces the native PDF`);
    const nativePages = analyse(nativeWords.map(words => ({
      body: words.filter(word => bodyToken.test(word)), areas: words.join(' ').match(areaToken) || [],
    })));
    assert.deepEqual(nativePages.flatMap(page => page.body), ['CHSTART', ...requested.flatMap((spec, index) =>
      Array.from({ length: spec.length }, (_, line) => `CH${index + 1}BODY${line + 1}`))], `${item.name}: every native paragraph once, in order`);
    if (outcome === 'paged') {
      for (const page of nativePages) assert.deepEqual(page.areas, ruleAreas(requested, page.owner, page.startsHere, page.page),
        `${item.name}: native page ${page.page} follows the membership rule`);
    }
    // Shape-specific native observations that the rule alone would not pin down.
    const tokensOn = index => nativePages[index].areas;
    if (item.name === 'first-incoming') assert.deepEqual(tokensOn(1), ['CH2DEFAULTFOOTER', 'CH2DEFAULTHEADER'], 'First areas are not deferred past a shared page');
    if (item.name === 'fresh-top') {
      assert.deepEqual(nativePages.map(page => page.owner), [1, 2, 2]);
      assert.deepEqual(tokensOn(1), ['CH2FIRSTFOOTER', 'CH2FIRSTHEADER'], 'A section starting at a page top uses its first areas');
      assert.deepEqual(tokensOn(2), ['CH2RIGHTFOOTER', 'CH2RIGHTHEADER']);
    }
    if (item.name === 'chain-short') assert(nativePages.every(page => !page.areas.some(token => token.startsWith('CH2'))), 'A section entirely on a shared page never draws its areas');
    if (item.name === 'margin-areas') {
      const word = native.pages[0].words.find(word => word.text === 'CH2BODY1');
      assert(Math.abs(word.x - 72) < .5, 'Native margin change applies mid-page on the shared page');
    }
    if (item.name === 'orientation-areas') {
      assert.deepEqual(native.pages.map(page => [page.width, page.height]).slice(0, 2), [[300, 360], [360, 300]]);
      assert.equal(nativePages[1].body[0], 'CH2BODY1', 'Native orientation change starts a new page');
    }
    const files = unzipSync(await readFile(resolve(directory, `Output/contheader-${item.name}-original.4wp`)));
    files['Resources/contheader-sentinel.bin'] = Uint8Array.of(0, 255, 41, 128);
    const original = zipSync(files);
    const source = `contheader-source-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `contheader-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/contheader-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source };
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    const external = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(url) && !request.url().startsWith('data:')) external.push(request.url()); });
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('CHSTART');
      await download(`contheader-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      let browserPages = [];
      let printedAreas = [];
      let notices = [];
      if (outcome === 'fallback') {
        await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedContinuous);
        await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
        await expect(page.locator('#paper')).toContainText(`CH2BODY${requested[1].length}`);
      } else {
        const sheets = page.locator('#paged-view .browser-page');
        await expect(sheets.first()).toBeVisible();
        const count = await sheets.count();
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const measured = await sheets.evaluateAll(sheets => sheets.map(sheet => ({
          owner: Number(sheet.dataset.section),
          body: sheet.querySelector('.page-body').textContent.match(/CHSTART|CH\d+BODY\d+/g) || [],
          texts: [...sheet.querySelectorAll(':scope > .page-area')].map(area => area.textContent),
        })));
        browserPages = analyse(measured.map(sheet => ({ body: sheet.body, areas: sheet.texts.join(' ').match(/CH\d(?:DEFAULT|FIRST|LEFT|RIGHT)(?:HEADER|FOOTER)/g) || [] })));
        assert.deepEqual(browserPages.flatMap(sheet => sheet.body), nativePages.flatMap(sheet => sheet.body), `${item.name}: every browser paragraph once, in order`);
        browserPages.forEach((sheet, index) => {
          assert.equal(measured[index].owner, sheet.owner, `${item.name}: browser sheet owner is the section at its top`);
          assert.deepEqual(sheet.areas, ruleAreas(requested, sheet.owner, sheet.startsHere, sheet.page), `${item.name}: browser sheet ${sheet.page} follows the native rule`);
        });
        // Cross-check against the native PDF itself: page 1 and each section's first own page carry the same areas.
        assert.deepEqual(browserPages[0].areas, nativePages[0].areas, `${item.name}: page 1 areas`);
        for (let section = 1; section <= requested.length; section++) {
          const nativeFirst = nativePages.find(entry => entry.owner === section);
          const browserFirst = browserPages.find(entry => entry.owner === section);
          assert.equal(Boolean(browserFirst), Boolean(nativeFirst), `${item.name}: section ${section} owns a page in both renderings`);
          if (nativeFirst) assert.deepEqual(browserFirst.areas, atParity(nativeFirst.areas, nativeFirst.page, browserFirst.page), `${item.name}: first page owned by section ${section}`);
        }
        // Complete Unicode area text, exactly as the native getters return it.
        for (const text of measured.flatMap(sheet => sheet.texts)) {
          assert(item.areas.some(area => area.text === text.trim()), `${item.name}: complete area text ${text}`);
        }
        notices = await page.locator('#paged-objects > p').evaluateAll(items => items.map(entry => entry.dataset.notice));
        assert.deepEqual(notices, ['pagedSeamAreas']);
        await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
        await page.locator('#settings-toggle').click();
        await page.locator('#theme').selectOption('dark');
        await page.locator('#zoom').selectOption('2');
        await page.evaluate(() => {
          window.contheaderResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
        });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.evaluate(() => window.contheaderResize);
        await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
        const pdf = resolve(directory, `Output/contheader-browser-${item.name}.pdf`);
        await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(pdf);
        assert.equal(printed.pages.length, count + await page.locator('#paged-view .paged-unused').count());
        printedAreas = printed.pages.slice(0, count).map(sheet => (sheet.words.map(word => word.text).join(' ').match(areaToken) || []).sort());
        assert.deepEqual(printedAreas, browserPages.map(sheet => sheet.areas), `${item.name}: printed pages carry exactly the previewed areas`);
        assert.deepEqual(printed.pages.slice(0, count).map(sheet => sheet.words.map(word => word.text).filter(word => bodyToken.test(word))),
          browserPages.map(sheet => sheet.body), `${item.name}: printed body membership`);
        for (const sheet of printed.pages) assert(Math.abs(sheet.width - 300) < 1 && Math.abs(sheet.height - 360) < 1, 'Unscaled native paper geometry');
      }
      await download(`contheader-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/contheader-after-${item.name}.4wp`)), Buffer.from(original));
      await page.locator('#paper [contenteditable]').first().fill('WEBCH');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`contheader-edited-${item.name}`, edited, page);
      if (outcome === 'paged') await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBCH');
      else await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedContinuous);
      await page.locator('#undo').click();
      await download(`contheader-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`contheader-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      results.push({ name: item.name, outcome, requested, joins: item.joins, nativePages: nativePages.map(({ body, ...page }) => ({ ...page, firstBody: body[0], lastBody: body.at(-1) })),
        browserPages: browserPages.map(({ body, ...page }) => ({ ...page, firstBody: body[0], lastBody: body.at(-1) })), printedAreas, notices,
        untouchedOriginalBytes: true,
        limits: 'Native header/footer page membership only; no position, wrapping or page-count parity. Browser pages are measured by the browser.' });
    } finally {
      await page.close();
    }
  }
  await writeFile(resolve(directory, 'Output/contheader-browser-report.json'), JSON.stringify(results, null, 2));
}
