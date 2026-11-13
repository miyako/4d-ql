import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync, strFromU8, strToU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

async function open(page, kind = 'paper') {
  await page.goto('/');
  await page.locator('#file').setInputFiles(`tests/fixtures/media/media-${kind}-original.4wp`);
  await expect(page.locator('#editing-scope option[value="object:textBox1"]')).toHaveCount(1);
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const bytes = readFileSync(await (await pending).path());
  const archive = unzipSync(bytes);
  return { bytes, archive, xml: strFromU8(Object.entries(archive).find(([name]) => /\.html$/i.test(name))[1])
    .replace(/<meta name="datetimeModified"[^>]*\/>/g, '') };
}
test('object creation, native placement, deletion, versions and recovered history are document-wide', async ({ page }) => {
  await page.goto('/');
  page.on('dialog', dialog => dialog.accept());
  await page.locator('#file').setInputFiles('tests/fixtures/media/object-paper-original.4wp');
  const original = await download(page);
  await page.locator('#object-picture-file').setInputFiles('../Tests/Fixtures/wpfixture/Resources/checker.png');
  await expect(page.locator('#editing-scope')).toHaveValue('object:img2');
  await expect(page.locator('#paper img')).toHaveJSProperty('naturalWidth', 48);
  await page.getByLabel(messages.en.objectInitialText, { exact: true }).fill('NEW BOX 😀 日é');
  await page.getByRole('button', { name: messages.en.objectCreateBox, exact: true }).click();
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox2');
  await expect(page.locator('#paper')).toHaveText('NEW BOX 😀 日é');
  await page.locator('#object-section').selectOption('2');
  await expect(page.locator('#object-page')).toHaveValue('all');
  await page.locator('#object-hAlign').selectOption('center');
  await page.locator('#object-vAlign').selectOption('bottom');
  await page.locator('#object-layout').selectOption('behind');
  await page.locator('#object-placement-form button').click();
  await expect(page.locator('#object-form button')).toBeDisabled();
  const placed = await download(page);
  await page.locator('#history-toggle').click();
  await page.locator('#version-name').fill('Placed objects');
  await page.locator('#save-version').click();
  await page.locator('#history-toggle').click();
  await page.locator('#object-page').fill('2');
  await page.locator('#object-placement-form button').click();
  await expect(page.getByRole('alert')).toContainText(messages.en.objectPlacementInvalid);
  expect((await download(page)).xml).toBe(placed.xml);
  await page.locator('#object-page').fill('all');
  await page.locator('#object-hAlign').selectOption('offset');
  await page.locator('#object-vAlign').selectOption('offset');
  await page.locator('#object-layout').selectOption('wrap-square');
  await page.locator('#object-placement-form button').click();
  await expect(page.locator('#object-form button')).toBeEnabled();
  await page.locator('#object-delete').click();
  await expect(page.locator('#editing-scope')).toHaveValue('body');
  await expect(page.locator('#editing-scope option[value="object:textBox2"]')).toHaveCount(0);
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox2');
  await page.locator('#redo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('body');
  await page.locator('#history-toggle').click();
  await page.locator('#version-list li').filter({ hasText: 'Placed objects' }).getByRole('button', { name: 'Restore', exact: true }).click();
  expect((await download(page)).xml).toBe(placed.xml);
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope option[value="object:textBox2"]')).toHaveCount(0);
  await page.locator('#editing-scope').selectOption('object:textBox1');
  await expect(page.locator('#object-delete')).toBeDisabled();
  await expect(page.locator('#object-delete-state')).toHaveText(messages.en.objectDeleteProtected);
  const retained = xml => page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
    return [...doc.querySelectorAll('body > p,body > div#textBox1,body > img#img1,body > div.section1Header,meta[name="bookmarks"]')].map(node => node.outerHTML);
  }, xml);
  expect(await retained((await download(page)).xml)).toEqual(await retained(original.xml));
});

test('native box text, geometry, formatting and recovery stay separate from body and picture resources', async ({ page }) => {
  await open(page);
  const original = await download(page);
  await page.locator('#editing-scope').selectOption('object:textBox1');
  await expect(page.locator('#paper')).toHaveText('BOX 😀 日é');
  await page.locator('#paper [contenteditable]').first().fill('BOX EDIT 😀');
  await page.locator('#paper [contenteditable]').first().evaluate(element => {
    element.focus();
    getSelection().selectAllChildren(element);
  });
  await page.locator('#bold').click();
  await page.locator('#object-units').selectOption('pt');
  await page.getByLabel(messages.en.objectWidth, { exact: true }).fill('210.125');
  await page.getByLabel(messages.en.objectX, { exact: true }).fill('30.5');
  await page.getByRole('button', { name: messages.en.objectApply, exact: true }).click();
  expect((await page.locator('#paper').boundingBox()).width).toBeCloseTo(210.125 * 96 / 72, 1);
  const edited = await download(page);
  expect(edited.xml).toContain('width:210.125pt');
  expect(edited.xml).toContain('-d4-anchor-h-offset:30.5pt');
  expect(edited.xml).toContain('font-weight:bold');
  const parse = xml => page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
    return { body: [...doc.querySelectorAll('body > p')].map(element => element.outerHTML), picture: doc.querySelector('img').outerHTML,
      bookmarks: doc.querySelector('meta[name="bookmarks"]').getAttribute('content') };
  }, xml);
  expect(await parse(edited.xml)).toEqual(await parse(original.xml));
  await page.locator('#undo').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox1');
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(edited.xml);
  await page.locator('#editing-scope').selectOption('body');
  await expect(page.locator('#paper [contenteditable]')).toHaveCount(0);
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox1');
  await expect(page.getByRole('alert')).toBeHidden();
});

test('native wrapped pictures decode from inert payloads without rewriting their source', async ({ page }) => {
  const requests = [];
  page.on('request', request => { if (!new URL(request.url()).hostname.match(/^(127\.0\.0\.1|localhost)$/)) requests.push(request.url()); });
  await open(page, 'wrapper');
  const original = await download(page);
  await page.locator('#editing-scope').selectOption('object:img1');
  await expect(page.locator('#paper img')).toHaveJSProperty('naturalWidth', 48);
  await expect(page.locator('#paper')).toContainText(messages.en.mediaProjection);
  await page.locator('#object-units').selectOption('pt');
  await page.locator('#object-width').fill('120');
  await page.locator('#object-form button').click();
  expect((await page.locator('#paper img').boundingBox()).width).toBeCloseTo(160, 1);
  const edited = await download(page);
  const source = xml => /src="([^"]+)"/.exec(xml)[1];
  expect(source(edited.xml)).toBe(source(original.xml));
  expect(source(edited.xml)).toMatch(/^data:application\/4DPicture/);
  expect(requests.filter(url => !url.startsWith('data:'))).toEqual([]);
});

test('aligned anchors, nested content and formula pictures remain protected with explicit notices', async ({ page }) => {
  await open(page, 'aligned');
  await page.locator('#editing-scope').selectOption('object:textBox1');
  await expect(page.locator('#object-state')).toHaveText(messages.en.objectAligned);
  await expect(page.locator('#object-form button')).toBeDisabled();
  await page.locator('#paper [contenteditable]').fill('TEXT ONLY');
  await expect(page.getByRole('alert')).toBeHidden();
  await page.locator('#download').click();
  page.on('dialog', dialog => dialog.accept());
  await page.locator('#file').setInputFiles('tests/fixtures/media/media-nested-original.4wp');
  await page.locator('#editing-scope').selectOption('object:textBox1');
  await expect(page.locator('#paper [contenteditable]')).toHaveCount(0);
  await expect(page.locator('#object-state')).toHaveText(messages.en.objectProtected);
  await page.locator('#file').setInputFiles('tests/fixtures/media/media-formula-original.4wp');
  await page.locator('#editing-scope').selectOption('object:img1');
  await expect(page.locator('#object-form button')).toBeDisabled();
  await expect(page.locator('#object-state')).toHaveText(messages.en.objectProtected);
});

test('malformed, unsupported and decode-failing pictures stay visible and never request an external URL', async ({ page }) => {
  await page.goto('/');
  const blocked = [];
  await page.route('https://invalid.example/**', route => { blocked.push(route.request().url()); return route.abort(); });
  const bytes = unzipSync(readFileSync('tests/fixtures/media/media-paper-original.4wp'));
  const entry = Object.keys(bytes).find(name => /\.html$/i.test(name));
  let xml = strFromU8(bytes[entry]);
  // Corrupt a PNG checksum, and separately admit a JPEG header with no decodable scan.
  const png = Buffer.from(/src="data:image\/png;base64,([^"]+)"/.exec(xml)[1], 'base64');
  png[41] = 0;
  const jpeg = Buffer.from([255, 216, 255, 192, 0, 11, 8, 0, 1, 0, 1, 1, 1, 17, 0, 255, 217]);
  const extras = `<p><img src="https://invalid.example/tracker"/><img src="data:image/png;base64,AAAA"/><img src="data:image/svg+xml;base64,PHN2Zy8+"/><img src="data:image/png;base64,${png.toString('base64')}"/><img src="data:image/jpeg;base64,${jpeg.toString('base64')}"/></p>`;
  xml = xml.replace('<body>', `<body>${extras}`);
  bytes[entry] = strToU8(xml);
  const archive = zipSync(bytes);
  await page.locator('#file').setInputFiles({ name: 'malformed.4wp', mimeType: 'application/zip', buffer: Buffer.from(archive) });
  await expect(page.locator('#paper')).toContainText(messages.en.mediaUnsupported);
  await expect(page.locator('#paper')).toContainText(messages.en.mediaMalformed);
  await page.locator('#paper img').evaluateAll(images => images.forEach(image => { image.loading = 'eager'; }));
  await expect(page.locator('#paper img')).toHaveCount(0);
  await expect(page.locator('#paper .preserved-object').filter({ hasText: messages.en.mediaMalformed })).toHaveCount(3);
  expect(blocked).toEqual([]);
  expect((await download(page)).bytes).toEqual(Buffer.from(archive));
});

test('browser print appends supported stored content once and leaves the active object/history untouched', async ({ page }, testInfo) => {
  await open(page);
  await page.locator('#editing-scope').selectOption('object:textBox1');
  const before = await download(page);
  await page.locator('#print-toggle').click();
  await page.evaluate(() => { window.print = () => {}; });
  await page.locator('#print-open').click();
  await expect(page.locator('#print-document .object-appendix img')).toHaveJSProperty('naturalWidth', 48);
  await expect(page.locator('#print-document .object-appendix')).toContainText('BOX 😀 日é');
  const pdf = testInfo.outputPath('objects.pdf');
  await page.pdf({ path: pdf, preferCSSPageSize: true });
  const text = execFileSync('pdftotext', ['-layout', pdf, '-'], { encoding: 'utf8' });
  expect(text.match(/BOX/g)).toHaveLength(1);
  expect(text).toContain('BODY');
  await page.evaluate(() => dispatchEvent(new Event('afterprint')));
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox1');
  expect((await download(page)).xml).toBe(before.xml);
  await expect(page.locator('#undo')).toBeDisabled();
});

for (const locale of Object.keys(messages)) test(`object controls remain accessible on mobile in ${locale} and all themes`, async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
  await open(page);
  await page.locator('#editing-scope').selectOption('object:textBox1');
  await expect(page.getByLabel(messages[locale].objectWidth, { exact: true })).toBeVisible();
  await page.locator('#object-units').selectOption('pt');
  const original = await download(page);
  for (const unit of ['cm', 'in', 'mm', 'pt']) await page.locator('#object-units').selectOption(unit);
  await page.locator('#object-form button').click();
  await page.locator('#object-placement-form button').click();
  expect((await download(page)).xml).toBe(original.xml);
  await page.locator('#settings-toggle').click();
  for (const theme of ['system', 'dark', 'light']) {
    await page.locator('#theme').selectOption(theme);
    expect(await page.locator('#object-panel').evaluate(panel => panel.scrollWidth <= panel.clientWidth)).toBe(true);
    await expect(page.getByLabel(messages[locale].objectX, { exact: true })).toBeVisible();
    await expect(page.getByLabel(messages[locale].objectPage, { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: messages[locale].objectCreateBox, exact: true })).toBeVisible();
  }
  await page.getByLabel(messages[locale].objectWidth, { exact: true }).fill('0');
  await page.locator('#object-form button').click();
  await expect(page.getByRole('alert')).toContainText(messages[locale].objectInvalid);
  expect((await download(page)).xml).toBe(original.xml);
  await page.getByRole('button', { name: messages[locale].objectCreateBox, exact: true }).click();
  await expect(page.locator('#editing-scope')).toHaveValue('object:textBox2');
  await expect(page.locator('#undo')).toHaveAttribute('title', `${messages[locale].undo} · ${messages[locale].objectCreate}`);
});
