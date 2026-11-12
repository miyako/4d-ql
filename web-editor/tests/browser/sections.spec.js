import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import { messages } from '../../src/i18n.js';

const xml = (body = '<p>AB<span style="-d4-ref:\'1+1\'">SAVED</span>😀日</p>', style = '') =>
  `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Sections</title><meta name="bookmarks" content="{&quot;span&quot;:[0,2]}"/><style>${style}</style></head><body>${body}</body></html>`;
async function open(page, body, style) {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'sections.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml(body, style)), 'sentinel.bin': Uint8Array.of(0, 255, 17) })) });
  await expect(page.locator('#document-title')).toHaveText('Sections');
}
async function caret(page, offset = 1) {
  await page.locator('#paper [contenteditable]').first().evaluate((element, offset) => {
    element.focus();
    window.getSelection().collapse(element.firstChild, offset);
  }, offset);
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const archive = unzipSync(readFileSync(await (await pending).path()));
  return { xml: strFromU8(archive['Document.html']).replace(/<meta name="datetimeModified"[^>]*\/>/g, ''), archive };
}
test('section break, inherited settings, safe removal, undo/redo and reload downloads preserve formulas and resources', async ({ page }) => {
  await open(page);
  await caret(page);
  await page.locator('#page-toggle').click();
  await page.locator('#break-kind').selectOption('continuous');
  await page.locator('#break-insert').click();
  await expect(page.locator('#error')).toBeHidden();
  await expect(page.locator('#paper [role="separator"]')).toHaveText(messages.en.breakContinuous);
  await expect(page.locator('#section-active')).toHaveText('Active section: 2');
  await page.locator('#page-target').selectOption('2');
  await expect(page.locator('#section-inherit-orientation')).toBeChecked();
  await expect(page.locator('#section-inherit-margins')).toBeChecked();
  await expect(page.locator('#page-width')).toBeDisabled();
  await page.locator('#break-remove').click();
  await expect(page.locator('#paper p')).toHaveCount(2);
  await expect(page.locator('#paper [role="separator"]')).toHaveCount(0);
  await page.locator('#undo').click();
  await page.locator('#page-target').selectOption('2');
  await page.locator('#section-name').fill('日本語 & A😀');
  await page.locator('#section-inherit-orientation').uncheck();
  await page.locator('#page-orientation').selectOption('landscape');
  await page.locator('#section-inherit-margins').uncheck();
  await page.locator('#page-units').selectOption('pt');
  await page.locator('#page-left').fill('40');
  await page.locator('#page-apply').click();
  await expect(page.locator('#error')).toBeHidden();
  const edited = await download(page);
  expect(edited.xml).toContain('-d4-page-orientation:landscape');
  expect(edited.xml).toContain('SAVED');
  expect(edited.archive['sentinel.bin']).toEqual(Uint8Array.of(0, 255, 17));
  await page.locator('#break-remove').click();
  await expect(page.locator('#error-message')).toHaveText(messages.en.sectionProtected);
  expect((await download(page)).xml).toBe(edited.xml);
  await page.locator('#dismiss-error').click();
  await page.locator('#undo').click();
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect((await download(page)).xml).toBe(edited.xml);
  await page.locator('#page-toggle').click();
  await page.locator('#page-target').selectOption('2');
  await page.locator('#section-inherit-orientation').check();
  await page.locator('#section-inherit-margins').check();
  await page.locator('#page-apply').click();
  expect((await download(page)).xml).not.toContain('-d4-page-orientation:landscape');
});

for (const kind of ['page', 'section']) {
  test(`inserts ${kind} at the end and protects ranged selections`, async ({ page }) => {
    await open(page, '<p>AB</p>');
    await caret(page, 2);
    await page.locator('#page-toggle').click();
    await page.locator('#break-kind').selectOption(kind);
    await page.locator('#break-insert').click();
    await expect(page.locator('#paper p')).toHaveCount(2);
    await expect(page.locator('#paper [role="separator"]')).toHaveCount(1);
    await page.locator('#undo').click();
    await page.locator('#paper [contenteditable]').first().evaluate(element => {
      element.focus();
      window.getSelection().selectAllChildren(element);
    });
    await page.locator('#break-insert').click();
    await expect(page.locator('#error-message')).toHaveText(messages.en.breakCaret);
    await expect(page.locator('#paper p')).toHaveCount(1);
  });
}

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`section controls and break markers are accessible on mobile across themes in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(locale => localStorage.setItem('4wp-language', locale), locale);
    await open(page);
    await caret(page, 0);
    await page.locator('#page-toggle').click();
    await page.locator('#break-kind').selectOption('section');
    await page.getByRole('button', { name: messages[locale].breakInsert, exact: true }).click();
    await expect(page.getByRole('separator', { name: messages[locale].breakSection, exact: true })).toBeVisible();
    await page.locator('#page-target').selectOption('2');
    await expect(page.getByRole('textbox', { name: messages[locale].sectionName, exact: true })).toBeVisible();
    await page.getByRole('checkbox', { name: messages[locale].sectionInheritMargins, exact: true }).focus();
    await page.keyboard.press('Space');
    await expect(page.locator('#page-left')).toBeEnabled();
    expect(await page.locator('#page-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await page.locator('#settings-toggle').click();
    for (const theme of ['system', 'dark', 'light']) {
      await page.locator('#theme').selectOption(theme);
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
      await expect(page.getByRole('checkbox', { name: messages[locale].sectionInheritOrientation, exact: true })).toBeVisible();
    }
    await page.locator('#section-name').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#page-toggle')).toBeFocused();
    await expect(page.locator('#page-panel')).toBeHidden();
  });
}
