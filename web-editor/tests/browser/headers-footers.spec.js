import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const xml = (header = 'HEADER😀') => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Header scopes</title><meta name="bookmarks" content="{&quot;body&quot;:[0,2]}"/><style>div.section0{-d4-page-width:612pt;-d4-page-height:792pt;-d4-page-margin:36pt}div.section1First{white-space:normal}</style></head><body><p style="-d4-section-break-after:continuous">BODY ONE</p><p>BODY TWO</p><div class="section1Header" style="visibility:hidden;height:0"><p>${header}</p></div><div class="section1FirstHeader" style="visibility:hidden;height:0"><p>FIRST HEADER</p></div><div class="section2Footer" style="visibility:hidden;height:0"><p>SECOND FOOTER</p></div></body></html>`;
async function open(page, header) {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'headers.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml(header)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Header scopes');
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const bytes = readFileSync(await (await pending).path());
  const archive = unzipSync(bytes);
  return { bytes, archive, xml: strFromU8(Object.entries(archive).find(([name]) => /\.html$/i.test(name))[1])
    .replace(/<meta name="datetimeModified"[^>]*\/>/g, '') };
}
test('header edits, cross-run formatting, undo/reload and scope switches preserve body bookmarks and nonactive areas', async ({ page }) => {
  await open(page, 'AB<span style="-d4-ref:\'1+1\'">CACHED</span>CD');
  await expect(page.locator('#paper [contenteditable]')).toHaveCount(0);
  await page.locator('#editing-scope').selectOption('section1Header');
  const original = await download(page);
  await page.locator('#paper [contenteditable]').first().fill('EDITED');
  await page.locator('#paper [contenteditable]').first().evaluate(element => {
    element.focus();
    window.getSelection().selectAllChildren(element);
  });
  await page.locator('#bold').click();
  await expect(page.locator('#error')).toBeHidden();
  const edited = await download(page);
  expect(edited.xml).toContain('font-weight:bold');
  expect(edited.xml).toContain('CACHED');
  expect(edited.xml).toContain('FIRST HEADER');
  expect(edited.xml).toContain('BODY ONE');
  expect(edited.xml).toContain('&quot;body&quot;:[0,2]');
  expect(edited.archive['sentinel.bin']).toEqual(original.archive['sentinel.bin']);
  await page.locator('#undo').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(edited.xml);
  await page.locator('#editing-scope').selectOption('section1FirstHeader');
  await expect(page.locator('#paper')).toHaveText('FIRST HEADER');
  await page.locator('#paper [contenteditable]').fill('FIRST EDIT');
  await page.locator('#editing-scope').selectOption('body');
  await expect(page.locator('#paper')).toContainText('BODY ONE');
  await expect(page.locator('#paper')).not.toContainText('FIRST EDIT');
  expect((await download(page)).xml).toContain('FIRST EDIT');
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('section1FirstHeader');
  await expect(page.locator('#paper')).toHaveText('FIRST HEADER');
  await page.locator('#redo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('section1FirstHeader');
  await expect(page.locator('#paper')).toHaveText('FIRST EDIT');
});

test('IME commits stay in their area and delayed composition events cannot mutate a newly selected scope', async ({ page }) => {
  await open(page);
  await page.locator('#editing-scope').selectOption('section1Header');
  await page.locator('#paper [contenteditable]').evaluate(element => {
    element.focus();
    window.getSelection().collapse(element.firstChild, 1);
    element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    element.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '日' }));
  });
  await expect(page.locator('#paper')).toHaveText('H日EADER😀');
  await page.locator('#paper [contenteditable]').first().evaluate(element => {
    element.focus();
    window.getSelection().collapse(element.firstChild, 0);
    element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
  });
  await page.locator('#editing-scope').selectOption('section2Footer');
  const before = await download(page);
  await page.locator('#paper').evaluate(paper => paper.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: 'WRONG AREA' })));
  await expect(page.locator('#paper')).toHaveText('SECOND FOOTER');
  expect((await download(page)).xml).toBe(before.xml);
});

test('creates/removes default content only in safe sections and recovers the selected footer', async ({ page }) => {
  page.on('dialog', dialog => dialog.accept());
  await open(page);
  await page.locator('#header-section').selectOption('1');
  await expect(page.locator('#header-create')).toBeDisabled();
  await page.locator('#header-section').selectOption('2');
  await page.locator('#header-kind').selectOption('Header');
  await page.locator('#header-create').click();
  await expect(page.locator('#editing-scope')).toHaveValue('section2Header');
  await page.locator('#paper [contenteditable]').fill('NEW SECOND HEADER');
  await page.locator('#header-remove').click();
  await expect(page.locator('#editing-scope')).toHaveValue('body');
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('section2Header');
  await expect(page.locator('#paper')).toHaveText('NEW SECOND HEADER');
  await page.locator('#editing-scope').selectOption('section2Footer');
  await page.locator('#paper [contenteditable]').fill('EDITED FOOTER');
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#editing-scope')).toHaveValue('section2Footer');
  await expect(page.locator('#paper')).toHaveText('EDITED FOOTER');
});

test('unsupported header tables remain visible, protected and byte-preserved on untouched download', async ({ page }) => {
  await open(page, '<table><tr><td><p>TABLE CONTENT</p></td></tr></table>');
  const before = await download(page);
  await page.locator('#editing-scope').selectOption('section1Header');
  await expect(page.locator('#scope-protection')).toHaveText(messages.en.headerUnsupported);
  await expect(page.locator('#paper [contenteditable]')).toHaveCount(0);
  await expect(page.locator('#paper')).toContainText('TABLE CONTENT');
  expect((await download(page)).bytes).toEqual(before.bytes);
});

test('browser PDF includes labeled native content appendix and original paper geometry without changing the download', async ({ page }, testInfo) => {
  await open(page);
  await page.locator('#editing-scope').selectOption('section1Header');
  const before = await download(page);
  const path = testInfo.outputPath('headers.pdf');
  await page.pdf({ path, preferCSSPageSize: true });
  const text = execFileSync('pdftotext', ['-layout', path, '-'], { encoding: 'utf8' }).replace(/\s+/g, ' ');
  const bbox = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  for (const token of ['BODY ONE', 'HEADER', 'FIRST HEADER', 'SECOND FOOTER', 'content appendix', 'Native section 2']) expect(text).toContain(token);
  for (const match of bbox.matchAll(/<page width="([\d.]+)" height="([\d.]+)">/g)) {
    expect(Number(match[1])).toBeCloseTo(612, 0);
    expect(Number(match[2])).toBeCloseTo(792, 0);
  }
  expect((await download(page)).bytes).toEqual(before.bytes);
  await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`header scope keyboard controls fit mobile and all themes in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await open(page);
    await expect(page.getByLabel(messages[locale].editingScope, { exact: true })).toBeVisible();
    await page.locator('#editing-scope').focus();
    await page.keyboard.press('Tab');
    await expect(page.locator('#header-section')).toBeFocused();
    if (locale === 'en') {
      await page.locator('#editing-scope').focus();
      await page.keyboard.press('n');
    } else await page.locator('#editing-scope').selectOption('section1Header');
    await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
    await expect(page.locator('#scope-state')).toContainText(messages[locale].headerHeader);
    await page.locator('#paper [contenteditable]').fill(`EDIT ${locale}`);
    await page.locator('#settings-toggle').click();
    for (const theme of ['system', 'light', 'dark']) {
      await page.locator('#theme').selectOption(theme);
      await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
      expect(await page.locator('.scope-panel').evaluate(panel => panel.scrollWidth <= panel.clientWidth)).toBe(true);
      await expect(page.locator('#paper')).toContainText(`EDIT ${locale}`);
    }
    await page.locator('#editing-scope').selectOption('section1FirstHeader');
    await expect(page.locator('#scope-state')).toContainText(messages[locale].headerFirst);
    await expect(page.locator('#header-facing')).toHaveText(messages[locale].headerFacing);
    await page.locator('.header-position summary').click();
    await expect(page.locator('#header-position-state')).toHaveText(messages[locale].headerPositionProtected);
    expect(await page.locator('.scope-panel').evaluate(panel => panel.scrollWidth <= panel.clientWidth)).toBe(true);
  });
}

test('paired variant deletion requires confirmation, preserves defaults and recovers Undo/Redo downloads', async ({ page }) => {
  let accept = false;
  const confirmations = [];
  page.on('dialog', async dialog => {
    confirmations.push(dialog.message());
    if (accept) await dialog.accept(); else await dialog.dismiss();
  });
  await page.goto('/');
  await page.locator('#file').setInputFiles(new URL('../fixtures/headers/variant-both-original.4wp', import.meta.url).pathname);
  const original = await download(page);
  await page.locator('#header-facing').click();
  await expect(page.locator('#header-facing')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#editing-scope option[value="section1LeftFooter"]')).toHaveCount(1);
  await page.locator('#editing-scope').selectOption('section1LeftHeader');
  await page.locator('#paper [contenteditable]').fill('UNIQUE LEFT');
  const edited = await download(page);
  await page.locator('#history-toggle').click();
  await page.locator('#version-name').fill('Variant original');
  await page.locator('#save-version').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.locator('#header-facing').click();
  expect(confirmations).toEqual([messages.en.headerVariantRemove]);
  expect((await download(page)).xml).toBe(edited.xml);
  accept = true;
  await page.locator('#header-facing').click();
  await expect(page.locator('#editing-scope')).toHaveValue('body');
  expect((await download(page)).xml).not.toContain('UNIQUE LEFT');
  await page.locator('#undo').click();
  expect((await download(page)).xml).toBe(edited.xml);
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await page.locator('#redo').click();
  await expect(page.locator('#header-facing')).toHaveAttribute('aria-pressed', 'false');
  await page.locator('#header-facing').click();
  const recreated = await download(page);
  expect(recreated.xml).not.toContain('UNIQUE LEFT');
  expect(recreated.xml).toContain('HEADER 😀 日é');
  for (const [name, bytes] of Object.entries(original.archive)) if (!/\.html$/i.test(name)) expect(recreated.archive[name]).toEqual(bytes);
  await page.locator('#history-toggle').click();
  await page.locator('#version-list li').filter({ hasText: 'Variant original' }).getByRole('button', { name: 'Restore', exact: true }).click();
  expect((await download(page)).xml).toBe(edited.xml);
  await expect(page.locator('#editing-scope')).toHaveValue('body');
  await page.locator('#undo').click();
  expect((await download(page)).xml).toBe(recreated.xml);
});

test('native positioning preserves precision across unit changes and recovery, rejecting invalid values explicitly', async ({ page }) => {
  await page.goto('/');
  await page.locator('#file').setInputFiles(new URL('../fixtures/headers/variant-geometry-original.4wp', import.meta.url).pathname);
  await page.locator('#editing-scope').selectOption('section1Header');
  await page.locator('.header-position summary').click();
  const before = await download(page);
  for (const unit of ['pt', 'cm', 'in', 'mm']) await page.locator('#header-units').selectOption(unit);
  await page.locator('#header-position-form button').click();
  expect((await download(page)).bytes).toEqual(before.bytes);
  await page.locator('#header-units').selectOption('pt');
  await page.locator('#header-right').fill('11.25');
  await page.locator('#header-position-form button').click();
  const changed = await download(page);
  expect(changed.xml).toContain('12.345mm 11.25pt 14pt 50pt');
  await page.locator('#header-left').fill('-1');
  await page.locator('#header-position-form button').click();
  await expect(page.locator('#error')).toContainText(messages.en.headerPositionInvalid);
  expect((await download(page)).xml).toBe(changed.xml);
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
  expect((await download(page)).xml).toBe(changed.xml);
  await page.locator('#undo').click();
  await expect(page.locator('#editing-scope')).toHaveValue('section1Header');
  expect((await download(page)).xml).toBe(before.xml);
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(changed.xml);
});
