import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const source = (style = '', body = '<p>AB</p><p>CD</p><p>EF</p>') =>
  `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Flow</title><meta name="bookmarks" content="{&quot;span&quot;:[0,2]}"/><style>${style}</style></head><body>${body}</body></html>`;
async function open(page, style, body) {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'flow.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(source(style, body)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Flow');
}
async function select(page, first = 0, last = first, end = 0) {
  await page.locator('#paper').evaluate((paper, { first, last, end }) => {
    const runs = paper.querySelectorAll('[data-run]');
    runs[first].focus();
    getSelection().setBaseAndExtent(runs[first].firstChild, 0, runs[last].firstChild, end);
  }, { first, last, end });
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const archive = unzipSync(readFileSync(await (await pending).path()));
  return { xml: strFromU8(archive['Document.html']).replace(/<meta name="datetimeModified"[^>]*\/>/g, ''), archive };
}

test('column defaults, independent inheritance and responsive section projection preserve precision and recovery', async ({ page }) => {
  await open(page, 'div.section0{column-count:2;column-gap:18.123456789pt}div.section2{column-rule-style:solid}',
    '<p style="-d4-section-break-after:continuous">AB</p><p>CD</p>');
  await page.locator('#page-toggle').click();
  const original = await download(page);
  for (const unit of ['cm', 'in', 'mm', 'pt']) await page.locator('#page-units').selectOption(unit);
  await page.locator('#columns-apply').click();
  expect((await download(page)).xml).toBe(original.xml);
  await expect(page.locator('#undo')).toBeDisabled();
  await page.locator('#page-target').selectOption('2');
  await expect(page.locator('#column-inherit-count')).toBeChecked();
  await expect(page.locator('#column-inherit-gap')).toBeChecked();
  await page.locator('#column-inherit-count').uncheck();
  await page.locator('#column-count').fill('3');
  await page.locator('#columns-apply').click();
  await expect(page.locator('#error')).toBeHidden();
  await expect(page.locator('.section-columns[data-section="2"]')).toHaveCSS('column-count', '3');
  const edited = await download(page);
  expect(edited.xml).toContain('column-gap:18.123456789pt');
  expect(edited.xml).toContain('column-rule-style:solid');
  expect(edited.archive['sentinel.bin']).toEqual(Uint8Array.of(0, 255, 17));
  await page.locator('#undo').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(edited.xml);
  await page.locator('#page-toggle').click();
  await page.locator('#page-target').selectOption('2');
  await page.locator('#column-inherit-count').check();
  await page.locator('#columns-apply').click();
  expect((await download(page)).xml).not.toContain('column-count:3');
});

test('mixed partial paragraph tabs edit one stop and only changed default fields without flattening inherited styles', async ({ page }) => {
  await open(page, 'p.Tabbed{-d4-tab-stop-offset:36pt 72pt 18.123456789pt;-d4-tab-stop-type:left right center;-d4-tab-stop-leading:\'\' \'.\' \'_\';color:red}',
    '<p class="Tabbed" style="-d4-opaque:keep">AB</p><p>CD</p><p>EF</p>');
  await select(page, 0, 2, 0);
  await page.locator('#tabs-toggle').click();
  await expect(page.locator('#tabs-status')).toContainText('2');
  await expect(page.locator('#tabs-status')).toContainText(messages.en.mixed);
  await page.locator('#tab-units').selectOption('pt');
  await page.locator('#tab-position').fill('100');
  await page.locator('#tab-type').selectOption('decimal');
  await page.locator('#tab-leader').selectOption('-');
  await page.locator('#tab-stop-apply').click();
  await expect(page.locator('#error')).toBeHidden();
  let edited = await download(page);
  expect(edited.xml).toContain('class="Tabbed" style="-d4-opaque:keep;');
  expect(edited.xml).toContain('18.123456789pt');
  expect(edited.xml).toContain('<p>EF</p>');
  await page.locator('#tab-stop-list').selectOption('100');
  await page.locator('#tab-stop-remove').click();
  await page.locator('#tab-default-type').selectOption('bar');
  await page.locator('#tab-default-apply').click();
  edited = await download(page);
  expect(edited.xml).toContain('18.123456789pt');
  expect(edited.xml).toContain('1.25cm');
  expect(edited.xml).toContain('bar');
  expect(edited.xml).toContain('<p>EF</p>');
  await page.locator('#tab-reset').click();
  await expect(page.locator('#error')).toBeHidden();
  expect((await download(page)).xml).toContain('-d4-tab-stop-offset:1.25cm');
});

test('tab character insertion uses native offsets beside an immutable formula and survives undo/recovery', async ({ page }) => {
  await open(page, '', '<p>AB<span style="-d4-ref:\'1+1\'">SAVED</span>😀日</p>');
  await select(page);
  await page.locator('#insert-tab').click();
  await expect(page.locator('#error')).toBeHidden();
  const edited = await download(page);
  expect(edited.xml).toContain('>\tAB<span');
  expect(edited.xml).toContain('SAVED');
  expect(edited.xml).toContain('[1,3]');
  await page.locator('#undo').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(edited.xml);
});

test('invalid input and custom native leaders remain explicit protected errors without document mutation', async ({ page }) => {
  await open(page, 'p{-d4-tab-stop-offset:36pt;-d4-tab-stop-leading:"日"}');
  const original = await download(page);
  await select(page);
  await page.locator('#tabs-toggle').click();
  await expect(page.locator('#tabs-status')).toHaveText(messages.en.tabsUnsupported);
  await expect(page.locator('#tab-stop-apply')).toBeDisabled();
  await page.locator('#page-toggle').click();
  await page.locator('#column-count').fill('1.5');
  await page.locator('#columns-apply').click();
  await expect(page.locator('#error-message')).toHaveText(messages.en.columnsInvalid);
  expect((await download(page)).xml).toBe(original.xml);
});

test('unit preferences stay synchronized across both open panels without rewriting tab or column precision', async ({ page }) => {
  await open(page, 'div.section0{column-gap:18.123456789pt}p{-d4-tab-stop-offset:20.123456789pt}');
  await select(page);
  await page.locator('#tabs-toggle').click();
  await page.locator('#page-toggle').click();
  const before = await download(page);
  await page.locator('#page-units').selectOption('cm');
  await expect(page.locator('#tab-units')).toHaveValue('cm');
  await page.locator('#tab-default-apply').click();
  await page.locator('#tab-units').selectOption('in');
  await expect(page.locator('#page-units')).toHaveValue('in');
  await page.locator('#columns-apply').click();
  expect((await download(page)).xml).toBe(before.xml);
  await expect(page.locator('#undo')).toBeDisabled();
  await page.locator('#tab-interval').fill('');
  await page.locator('#tabs-close').click();
  await page.locator('#page-units').selectOption('pt');
  await expect(page.locator('#error')).toBeHidden();
  expect((await download(page)).xml).toBe(before.xml);
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`column/tab keyboard controls and notices on mobile in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await open(page);
    await select(page);
    await page.locator('#tabs-toggle').click();
    await expect(page.getByRole('combobox', { name: messages[locale].tabStop, exact: true })).toBeVisible();
    await expect(page.locator('#tabs-panel')).toContainText(messages[locale].flowPreview);
    await expect(page.locator('#tabs-panel')).toContainText(messages[locale].tabsHelp);
    await page.locator('#tab-type').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#tabs-toggle')).toBeFocused();
    await page.locator('#page-toggle').click();
    await expect(page.getByRole('spinbutton', { name: messages[locale].columnCount, exact: true })).toBeVisible();
    await page.locator('#settings-toggle').click();
    for (const theme of ['system', 'dark', 'light']) {
      await page.locator('#theme').selectOption(theme);
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
      expect(await page.locator('#page-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    }
  });
}
