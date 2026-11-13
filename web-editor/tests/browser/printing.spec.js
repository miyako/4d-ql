import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { zipSync, strToU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const source = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Print evidence</title><style>p{font:12pt Arial;margin:0;white-space:pre-wrap}${style}</style></head><body>${body}</body></html>`;
async function open(page, style = '', body = '<p>FIRST</p>') {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'print.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(source(style, body)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Print evidence');
}
async function bytes(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  return readFileSync(await (await pending).path());
}
async function pdf(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.pdf`);
  await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
  const text = execFileSync('pdftotext', ['-layout', path, '-'], { encoding: 'utf8' });
  const bbox = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  const pages = [...bbox.matchAll(/<page width="([\d.]+)" height="([\d.]+)">([\s\S]*?)<\/page>/g)].map(match => ({
    width: Number(match[1]), height: Number(match[2]),
    words: [...match[3].matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<\/word>/g)].map(word => ({
      x: Number(word[1]), y: Number(word[2]), right: Number(word[3]), bottom: Number(word[4]), text: word[5],
    })),
  }));
  expect(pages.length).toBeGreaterThan(0);
  return { text, pages, path };
}
function inside(pages, margins) {
  for (const page of pages) for (const word of page.words) {
    expect(word.x).toBeGreaterThanOrEqual(margins.left - 1);
    expect(word.right).toBeLessThanOrEqual(page.width - margins.right + 1);
    expect(word.y).toBeGreaterThanOrEqual(margins.top - 1);
    expect(word.bottom).toBeLessThanOrEqual(page.height - margins.bottom + 1);
  }
}

test('PDF uses actual mixed paper sizes, margins and explicit breaks outside columns', async ({ page }, testInfo) => {
  await open(page, 'div.section0{-d4-page-width:612pt;-d4-page-height:792pt;-d4-page-margin:24pt 30pt 36pt 42pt;column-count:2;column-gap:18pt}div.section2{-d4-page-orientation:landscape}',
    '<p style="page-break-after:always">FIRST</p><p style="page-break-after:always;-d4-section-break-after:always">SECOND</p><p>THIRD</p>');
  const surfaces = page.locator('#paper .section-paper');
  await expect(surfaces.first()).toHaveCSS('width', '816px');
  await expect(surfaces.nth(1)).toHaveCSS('width', '1056px');
  const output = await pdf(page, testInfo, 'mixed');
  expect(output.pages.map(item => [Math.round(item.width), Math.round(item.height)])).toEqual([[612, 792], [612, 792], [792, 612]]);
  expect(output.pages.map(item => item.words.map(word => word.text).join(' '))).toEqual(['FIRST', 'SECOND', 'THIRD']);
  for (const item of output.pages) expect(item.words[0].x).toBeCloseTo(42, 0);
  inside(output.pages, { top: 24, right: 30, bottom: 36, left: 42 });
  expect(output.text).not.toContain('4WP Editor');
});

test('continuous sections share identical paper but changed geometry starts a browser page', async ({ page }, testInfo) => {
  await open(page, 'div.section0{-d4-page-width:420pt;-d4-page-height:595pt;-d4-page-margin:30pt}div.section3{-d4-page-orientation:landscape}',
    '<p style="-d4-section-break-after:continuous">SAMEONE</p><p style="-d4-section-break-after:continuous">SAMETWO</p><p>CHANGED</p>');
  const output = await pdf(page, testInfo, 'continuous');
  expect(output.pages).toHaveLength(2);
  expect(output.pages[0].words.map(word => word.text)).toEqual(['SAMEONE', 'SAMETWO']);
  expect([Math.round(output.pages[1].width), Math.round(output.pages[1].height)]).toEqual([595, 420]);
  expect(output.pages[1].words[0].text).toBe('CHANGED');
});

test('hidden native associations retain a visible placeholder without adding default-size browser pages', async ({ page }, testInfo) => {
  await open(page, 'div.section0{-d4-page-width:420pt;-d4-page-height:595pt;-d4-page-margin:24pt}',
    '<p>BODY</p><div class="section1Header" style="visibility:hidden"><p>ORIGINAL HEADER</p></div>');
  const before = await bytes(page);
  const output = await pdf(page, testInfo, 'associated');
  for (const sheet of output.pages) {
    expect(Math.abs(sheet.width - 420)).toBeLessThan(1);
    expect(Math.abs(sheet.height - 595)).toBeLessThan(1);
  }
  expect(output.text).toContain('BODY');
  expect(output.text).toContain(messages.en.preserved);
  expect(await bytes(page)).toEqual(before);
});

test('a document change during image preparation aborts printing instead of opening a stale document', async ({ page }) => {
  const pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';
  await open(page, '', `<p>FIRST<img src="data:image/png;base64,${pixel}"/></p>`);
  await page.evaluate(() => {
    window.printCalls = 0;
    window.print = () => window.printCalls++;
    HTMLImageElement.prototype.decode = () => new Promise(resolve => { window.finishPrintImage = resolve; });
  });
  await page.locator('#print-toggle').click();
  await page.locator('#print-open').click();
  await expect.poll(() => page.evaluate(() => typeof window.finishPrintImage)).toBe('function');
  await page.locator('#paper [contenteditable]').first().fill('CHANGED');
  await page.evaluate(() => window.finishPrintImage());
  await expect(page.locator('#error-message')).toHaveText(messages.en.printFailed);
  expect(await page.evaluate(() => window.printCalls)).toBe(0);
  await expect(page.locator('#paper')).toContainText('CHANGED');
});

test('long text, tables, raster images and inert formula/unsupported placeholders survive small-paper printing without clipping', async ({ page }, testInfo) => {
  const rows = Array.from({ length: 60 }, (_, index) => `<tr><td><p>ROW${index}LEFT</p></td><td><p>ROW${index}RIGHT</p></td></tr>`).join('');
  const lines = Array.from({ length: 80 }, (_, index) => `<p>TEXT${index} word word word word word word</p>`).join('');
  const pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';
  await open(page, 'div.section0{-d4-page-width:298pt;-d4-page-height:420pt;-d4-page-margin:24pt}',
    `${lines}<table style="width:900pt">${rows}</table><p><img src="data:image/png;base64,${pixel}" style="width:400pt;height:400pt"/><span style="-d4-ref:'1+1'">CACHED</span><img src="https://invalid.example/tracker"/>TAILEND</p>`);
  let requests = 0;
  page.on('request', request => { if (request.url().includes('invalid.example')) requests++; });
  const output = await pdf(page, testInfo, 'long');
  for (let index = 0; index < 80; index++) expect(output.text).toContain(`TEXT${index}`);
  for (let index = 0; index < 60; index++) {
    expect(output.text).toContain(`ROW${index}LEFT`);
    expect(output.text).toContain(`ROW${index}RIGHT`);
  }
  for (const text of ['CACHED', '1+1', 'TAILEND', messages.en.image]) expect(output.text).toContain(text);
  inside(output.pages, { top: 24, right: 24, bottom: 24, left: 24 });
  expect(requests).toBe(0);
  expect(execFileSync('pdfimages', ['-list', output.path], { encoding: 'utf8' })).toMatch(/\d+\s+\d+\s+image/);
});

test('print dialog cancellation and print-media output preserve selection, zoom, dirty history and recovery', async ({ page }, testInfo) => {
  await open(page);
  await page.locator('#paper [contenteditable]').fill('EDITED');
  await page.locator('#undo').click();
  await page.locator('#paper [contenteditable]').evaluate(element => {
    element.focus();
    getSelection().setBaseAndExtent(element.firstChild, 1, element.firstChild, 4);
  });
  await page.locator('#zoom').selectOption('2');
  const before = await bytes(page);
  const state = await page.locator('#save-state').textContent();
  await page.locator('#settings-toggle').click();
  await page.locator('#theme').selectOption('dark');
  await page.locator('#page-toggle').click();
  for (const unit of ['cm', 'in', 'pt', 'mm']) await page.locator('#page-units').selectOption(unit);
  await page.locator('#paper [contenteditable]').evaluate(element => {
    element.focus();
    getSelection().setBaseAndExtent(element.firstChild, 1, element.firstChild, 4);
  });
  await page.locator('#print-toggle').click();
  await page.evaluate(() => {
    window.printCalls = 0;
    window.print = () => {
      window.printCalls++;
      dispatchEvent(new Event('beforeprint'));
      dispatchEvent(new Event('afterprint'));
    };
  });
  const selection = await page.evaluate(() => ({ text: getSelection().toString(), offset: getSelection().anchorOffset }));
  await page.locator('#print-open').click();
  expect(await page.evaluate(() => window.printCalls)).toBe(1);
  expect(await page.evaluate(() => ({ text: getSelection().toString(), offset: getSelection().anchorOffset }))).toEqual(selection);
  await expect(page.locator('#print-document')).toHaveCount(0);
  await expect(page.locator('#paper')).toHaveCSS('zoom', '2');
  await expect(page.locator('#save-state')).toHaveText(state);
  expect(await bytes(page)).toEqual(before);
  const dark = await pdf(page, testInfo, 'dark-zoom');
  await page.locator('#zoom').selectOption('1');
  await page.locator('#theme').selectOption('light');
  const light = await pdf(page, testInfo, 'light');
  expect(dark.pages).toEqual(light.pages);
  const raster = output => execFileSync('pdftoppm', ['-f', '1', '-singlefile', '-scale-to', '40', output.path]);
  const darkRaster = raster(dark);
  expect(darkRaster).toEqual(raster(light));
  const header = /^P6\s+\d+\s+\d+\s+255\s/.exec(darkRaster.toString('latin1'))[0].length;
  expect([...darkRaster.subarray(header, header + 3)]).toEqual([255, 255, 255]);
  await expect(page.locator('#redo')).toBeEnabled();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  await expect(page.locator('#paper')).toContainText('EDITED');
});

test('unsupported printing fails explicitly in the panel and native browser print flow', async ({ page }, testInfo) => {
  await open(page, 'p{-d4-page-width:300pt}');
  const before = await bytes(page);
  await page.locator('#print-toggle').click();
  await expect(page.locator('#print-open')).toBeDisabled();
  await expect(page.locator('#print-protection')).toHaveText(messages.en.printUnsupported);
  const output = await pdf(page, testInfo, 'unsupported');
  expect(output.text.replace(/\s+/g, ' ')).toContain('Printing is unavailable');
  expect(await bytes(page)).toEqual(before);
});

test('print-only minimum text area fails explicitly rather than clipping native-valid tiny paper', async ({ page }, testInfo) => {
  await open(page, 'div.section0{-d4-page-width:10pt;-d4-page-height:10pt;-d4-page-margin:0pt}', '<p>ABCD</p>');
  const before = await bytes(page);
  await page.locator('#print-toggle').click();
  await expect(page.locator('#print-open')).toBeDisabled();
  await expect(page.locator('#print-protection')).toHaveText(messages.en.printTooSmall);
  const output = await pdf(page, testInfo, 'too-small');
  expect(output.text.replace(/\s+/g, ' ')).toContain('Browser printing requires at least 72 pt');
  expect(await bytes(page)).toEqual(before);
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`print controls and limits are keyboard-accessible on mobile in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await open(page);
    await page.getByRole('button', { name: messages[locale].print, exact: true }).click();
    await expect(page.getByRole('button', { name: messages[locale].printOpen, exact: true })).toBeVisible();
    await expect(page.locator('#print-panel')).toContainText(messages[locale].printLimits);
    expect(await page.locator('#print-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await page.locator('#settings-toggle').click();
    for (const theme of ['system', 'dark', 'light']) {
      await page.locator('#theme').selectOption(theme);
      await expect(page.getByRole('button', { name: messages[locale].printOpen, exact: true })).toBeVisible();
    }
    await page.locator('#print-close').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#print-toggle')).toBeFocused();
  });
}
