import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const geometry = 'div.section0{-d4-page-width:300pt;-d4-page-height:360pt;-d4-page-margin:60pt 30pt}';
const xml = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Paged evidence</title><style>p{font:12pt Arial;line-height:18pt;margin:0;white-space:pre-wrap}${geometry}${style}</style></head><body>${body}</body></html>`;
async function open(page, style = '', body = '<p>BODY</p>') {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'paged.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml(style, body)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Paged evidence');
}
async function preview(page) {
  await page.locator('#paged-panel > summary').click();
  await expect(page.locator('#paged-status')).not.toBeEmpty();
  await expect(page.locator('#paged-status')).not.toHaveText(messages.en.pagedLoading);
}
function contents(bytes) {
  const archive = unzipSync(bytes);
  return { xml: strFromU8(archive['Document.html']).replace(/<meta name="datetimeModified"[^>]*\/>/g, ''), sentinel: archive['sentinel.bin'] };
}
async function bytes(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  return readFileSync(await (await pending).path());
}
async function pdf(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.pdf`);
  await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
  const bbox = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  return [...bbox.matchAll(/<page width="([\d.]+)" height="([\d.]+)">([\s\S]*?)<\/page>/g)].map(match => ({
    width: Math.round(Number(match[1])), height: Math.round(Number(match[2])),
    words: [...match[3].matchAll(/<word[^>]*>([^<]*)<\/word>/g)].map(word => word[1]),
  }));
}
function variants(section = 1) {
  return ['First', 'Left', 'Right'].map(variant => `div.section${section}${variant}{white-space:normal}`).join('') +
    ['', 'First', 'Left', 'Right'].flatMap(variant => ['Header', 'Footer'].map(kind =>
      `div.section${section}${variant}${kind}{margin:10pt 30pt}`)).join('');
}
function areas(section = 1) {
  return ['', 'First', 'Left', 'Right'].flatMap(variant => ['Header', 'Footer'].map(kind =>
    `<div class="section${section}${variant}${kind}" style="visibility:hidden;height:0"><p>S${section}${variant || 'Default'}${kind}</p></div>`)).join('');
}

test('automatic page boundaries retain each paragraph once and PDF matches actual preview pages', async ({ page }, testInfo) => {
  const body = Array.from({ length: 40 }, (_, i) => `<p>LINE${i} WORD</p>`).join('');
  await open(page, '', body);
  const before = await bytes(page);
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(4);
  const texts = await sheets.locator('.page-body').allTextContents();
  expect(texts.map(text => [...text.matchAll(/LINE(\d+)/g)].map(match => Number(match[1])))).toEqual([
    Array.from({ length: 13 }, (_, i) => i), Array.from({ length: 13 }, (_, i) => i + 13),
    Array.from({ length: 13 }, (_, i) => i + 26), [39],
  ]);
  expect(await page.locator('#paged-view').locator('[contenteditable],[data-run]').count()).toBe(0);
  expect(await sheets.evaluateAll(elements => elements.every(sheet => {
    const body = sheet.querySelector('.page-body').getBoundingClientRect();
    return [...sheet.querySelectorAll('.page-body > p')].every(p => p.getBoundingClientRect().bottom <= body.bottom + .25);
  }))).toBe(true);
  const printed = await pdf(page, testInfo, 'boundaries');
  expect(printed).toHaveLength(4);
  expect(printed.map(sheet => sheet.words.filter(word => word.startsWith('LINE')))).toEqual(texts.map(text => text.match(/LINE\d+/g)));
  expect(printed.every(sheet => sheet.width === 300 && sheet.height === 360)).toBe(true);
  expect(await bytes(page)).toEqual(before);
});

test('the 500-sheet boundary is enforced without discarding any source paragraphs', async ({ page }) => {
  const body = count => Array.from({ length: count }, (_, index) =>
    `<p${index < count - 1 ? ' style="page-break-after:always"' : ''}>PAGE${index}</p>`).join('');
  await open(page, '', body(500));
  await expect(page.locator('#paper p')).toHaveCount(500);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(500);
  await open(page, '', body(501));
  await expect(page.locator('#paper p')).toHaveCount(501);
  const before = await bytes(page);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  await expect(page.locator('#paper')).toContainText('PAGE500');
  expect(await bytes(page)).toEqual(before);
});

test('explicit page/section breaks select first/facing areas on mixed geometry and retain unused areas', async ({ page }, testInfo) => {
  await open(page, `${variants()}${variants(2)}div.section2{-d4-page-orientation:landscape}`,
    '<p style="page-break-after:always">ONE</p><p style="page-break-after:always">TWO</p><p style="page-break-after:always;-d4-section-break-after:always">THREE</p><p style="page-break-after:always">FOUR</p><p>FIVE</p>' + areas() + areas(2));
  await preview(page);
  const sheets = page.locator('#paged-view .browser-page');
  await expect(sheets).toHaveCount(5);
  expect(await sheets.evaluateAll(elements => elements.map(sheet => [...sheet.querySelectorAll('[data-area]')].map(area => area.dataset.area)))).toEqual([
    ['section1FirstHeader', 'section1FirstFooter'], ['section1LeftHeader', 'section1LeftFooter'],
    ['section1RightHeader', 'section1RightFooter'], ['section2FirstHeader', 'section2FirstFooter'],
    ['section2RightHeader', 'section2RightFooter'],
  ]);
  const output = await pdf(page, testInfo, 'variants');
  expect(output.slice(0, 5).map(sheet => [sheet.width, sheet.height])).toEqual([[300, 360], [300, 360], [300, 360], [360, 300], [360, 300]]);
  for (let i = 0; i < 5; i++) expect(output[i].words).toContain(['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE'][i]);
  expect(output[1].words).toContain('S1LeftHeader');
  expect(output[4].words).toContain('S2RightFooter');
  expect(output.slice(5).flatMap(sheet => sheet.words)).toContain('S1DefaultHeader');
  expect(output.slice(5).flatMap(sheet => sheet.words)).toContain('S2LeftHeader');
});

test('first-left parity, missing enabled areas and absent section areas do not inherit', async ({ page }) => {
  const content = areas().replace(/<div class="section1FirstHeader"[\s\S]*?<\/div>/, '')
    .replace(/<div class="section1LeftFooter"[\s\S]*?<\/div>/, '');
  await open(page, variants().replace('div.section1FirstHeader{margin:10pt 30pt}', '').replace('div.section1LeftFooter{margin:10pt 30pt}', '') +
    'div.section0{-d4-page-first-right:false}',
  '<p style="page-break-after:always">ONE</p><p style="page-break-after:always">TWO</p><p style="page-break-after:always;-d4-section-break-after:always">THREE</p><p>FOUR</p>' + content);
  await preview(page);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(4);
  expect(await page.locator('#paged-view .browser-page').evaluateAll(elements => elements.map(sheet =>
    [...sheet.querySelectorAll('[data-area]')].map(area => area.dataset.area)))).toEqual([
    ['section1FirstFooter'], ['section1RightHeader', 'section1RightFooter'], ['section1LeftHeader'], [],
  ]);
});

test('preview resize/zoom/themes, print cancellation, edits and recovery preserve archive and history', async ({ page }, testInfo) => {
  await open(page, '', '<p>ORIGINAL</p>');
  await page.locator('#paper [contenteditable]').fill('EDITED');
  const edited = await bytes(page);
  await page.locator('#undo').click();
  const undone = await bytes(page);
  await preview(page);
  const baseline = await pdf(page, testInfo, 'before');
  await page.locator('#settings-toggle').click();
  for (const theme of ['dark', 'system', 'light']) {
    await page.locator('#theme').selectOption(theme);
    await page.locator('#zoom').selectOption('2');
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.locator('#paged-view .browser-page')).toHaveCount(1);
    expect(await pdf(page, testInfo, theme)).toEqual(baseline);
  }
  await page.evaluate(() => {
    window.print = () => { dispatchEvent(new Event('beforeprint')); dispatchEvent(new Event('afterprint')); };
  });
  await page.locator('#print-toggle').click();
  await page.locator('#print-open').click();
  expect(await bytes(page)).toEqual(undone);
  await expect(page.locator('#redo')).toBeEnabled();
  await page.locator('#redo').click();
  await expect(page.locator('#paged-view')).toContainText('EDITED');
  expect(contents(await bytes(page))).toEqual(contents(edited));
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await preview(page);
  await expect(page.locator('#paged-view')).toContainText('EDITED');
  expect(contents(await bytes(page))).toEqual(contents(edited));
});

test('oversized blocks and areas fall back explicitly without partial pages or lost print content', async ({ page }, testInfo) => {
  await open(page, '', '<p>' + Array.from({ length: 30 }, (_, i) => `LONG${i}<br/>`).join('') + '</p><p>TAIL</p>');
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedOverflow);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  const output = await pdf(page, testInfo, 'fallback');
  const words = output.flatMap(sheet => sheet.words).join(' ');
  for (let i = 0; i < 30; i++) expect(words).toContain(`LONG${i}`);
  expect(words).toContain('TAIL');
  expect(words).toContain('Paged preview unavailable');
  await open(page, 'div.section1Header{margin:0pt}', '<p>BODY</p><div class="section1Header" style="visibility:hidden;height:0"><p>' + 'OVERFLOW<br/>'.repeat(10) + '</p></div>');
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedAreas);
  await expect(page.locator('#paper')).toContainText('BODY');
  await page.locator('#editing-scope').selectOption('section1Header');
  await expect(page.locator('#paper')).toContainText('OVERFLOW');
});

test('inert formula cards keep source and stored text without page-field evaluation', async ({ page }, testInfo) => {
  await open(page, '', '<p>START<span style="-d4-ref:\'This:C1470.pageNumber\'">SAVED</span>END</p>');
  await preview(page);
  await expect(page.locator('#paged-view .formula-source')).toContainText('pageNumber');
  await expect(page.locator('#paged-view .formula-value')).toContainText('SAVED');
  const output = await pdf(page, testInfo, 'formula');
  expect(output.flatMap(sheet => sheet.words).join(' ')).toContain('SAVED');
});

test('formula paragraphs near a page boundary keep identical measured heights in preview and print media', async ({ page }, testInfo) => {
  await open(page, '', '<p>LINE</p>'.repeat(10) + '<p><span style="-d4-ref:\'1+1\'">SAVED</span></p>');
  const before = await bytes(page);
  await preview(page);
  const count = await page.locator('#paged-view .browser-page').count();
  const heights = await page.locator('#paged-view .page-body > p').evaluateAll(elements =>
    elements.map(element => element.getBoundingClientRect().height));
  await page.emulateMedia({ media: 'print' });
  await page.evaluate(() => dispatchEvent(new Event('beforeprint')));
  expect(await page.locator('#print-document .browser-page').count()).toBe(count);
  expect(await page.locator('#print-document .page-body > p').evaluateAll(elements =>
    elements.map(element => element.getBoundingClientRect().height))).toEqual(heights);
  const output = await pdf(page, testInfo, 'formula-boundary');
  expect(output).toHaveLength(count);
  expect(output.flatMap(sheet => sheet.words).filter(word => word === 'SAVED')).toHaveLength(1);
  await page.emulateMedia({ media: 'screen' });
  await page.evaluate(() => dispatchEvent(new Event('afterprint')));
  expect(await bytes(page)).toEqual(before);
});

test('oversized unused areas fall back with all exported lines instead of clipping or returning partial pages', async ({ page }, testInfo) => {
  const unused = Array.from({ length: 50 }, (_, index) => `UNUSED${index} word word word<br/>`).join('');
  await open(page, 'div.section1First{white-space:normal}div.section1FirstHeader{margin:10pt 30pt}div.section1Header{margin:10pt 30pt}',
    '<p>BODY</p><div class="section1FirstHeader" style="visibility:hidden;height:0"><p>FIRST</p></div>' +
    `<div class="section1Header" style="visibility:hidden;height:0"><p>${unused}</p></div>`);
  await preview(page);
  await expect(page.locator('#paged-status')).toHaveText(messages.en.pagedAreas);
  await expect(page.locator('#paged-view .browser-page')).toHaveCount(0);
  const output = await pdf(page, testInfo, 'unused-long');
  const words = output.flatMap(sheet => sheet.words);
  for (let index = 0; index < 50; index++) expect(words.filter(word => word === `UNUSED${index}`)).toHaveLength(1);
  expect(words.filter(word => word === 'BODY')).toHaveLength(1);
  expect(words.filter(word => word === 'FIRST')).toHaveLength(1);
  expect(output.every(sheet => sheet.width === 300 && sheet.height === 360)).toBe(true);
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`paged controls, fallback and keyboard work on mobile in ${locale}`, async ({ page }) => {
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await page.setViewportSize({ width: 390, height: 844 });
    await open(page, 'div.section0{column-count:2}', '<p>BODY</p>');
    await page.locator('#paged-panel > summary').click();
    await expect(page.locator('#paged-status')).toHaveText(messages[locale].pagedShape);
    expect(await page.locator('#paged-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await page.locator('#paged-panel > summary').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#paged-panel')).not.toHaveAttribute('open');
    await expect(page.locator('#paged-panel > summary')).toBeFocused();
  });
}
