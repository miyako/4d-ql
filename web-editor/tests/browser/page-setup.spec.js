import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, strToU8, strFromU8, unzipSync } from 'fflate';
import { messages } from '../../src/i18n.js';

const xml = style => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page test</title><meta name="bookmarks" content="{&quot;anchor&quot;:[0,1]}"/><style>${style}</style></head><body><p>AB<span style="-d4-ref:'1+1'">SAVED</span>CD</p></body></html>`;
async function open(page, style = '') {
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'page.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Page.html': strToU8(xml(style)), 'sentinel.bin': Uint8Array.of(0, 255, 42) })) });
  await expect(page.locator('#document-title')).toHaveText('Page test');
  await page.locator('#page-toggle').click();
}
async function download(page) {
  const pending = page.waitForEvent('download');
  await page.locator('#download').click();
  const files = unzipSync(readFileSync(await (await pending).path()));
  return { files, xml: strFromU8(files['Page.html']) };
}
test('presets, custom geometry, native rounding, orientation, validation, undo/redo and reload recovery', async ({ page }) => {
  await open(page);
  await page.locator('#page-units').selectOption('pt');
  await page.locator('#page-preset').selectOption('letter');
  await page.locator('#page-orientation').selectOption('landscape');
  for (const side of ['top', 'right', 'bottom', 'left']) await page.locator('#page-' + side).fill('30');
  await expect(page.locator('#page-native-size')).toHaveText('792 × 612');
  await page.locator('#page-apply').click();
  await expect(page.locator('#error')).toBeHidden();
  await expect(page.locator('#paper')).toHaveCSS('width', '1056px');
  const first = await download(page);
  expect(first.xml).toContain('-d4-page-width:612pt');
  expect(first.xml).toContain('-d4-page-orientation:landscape');
  expect(first.files['sentinel.bin']).toEqual(Uint8Array.of(0, 255, 42));
  expect(first.xml).toContain('content="{&quot;anchor&quot;:[0,1]}"');
  await page.locator('#undo').click();
  await expect(page.locator('#page-width')).toHaveValue('595');
  await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#page-toggle').click();
  await page.locator('#redo').click();
  await expect(page.locator('#page-width')).toHaveValue('612');
  await page.locator('#page-width').fill('600.125');
  await page.locator('#page-height').fill('800.875');
  await expect(page.locator('#page-native-size')).toHaveText('801 × 600');
  await page.locator('#page-apply').click();
  await expect(page.locator('#page-width')).toHaveValue('600');
  await page.locator('#page-left').fill('800');
  await page.locator('#page-apply').click();
  await expect(page.locator('#error-message')).toHaveText(messages.en.pageMarginsInvalid);
  await expect(page.locator('#page-left')).toHaveValue('30');
});

test('unit-only changes and apply preserve exact fractional native declarations and original archive', async ({ page }) => {
  await open(page, 'div.section0 { -d4-page-margin:12.345mm 0pt 0.5in 1.25cm;-d4-opaque:keep }');
  const original = await download(page);
  for (const unit of ['in', 'cm', 'pt', 'mm']) await page.locator('#page-units').selectOption(unit);
  await page.locator('#page-apply').click();
  expect((await download(page)).xml).toBe(original.xml);
  await expect(page.locator('#undo')).toBeDisabled();
  await page.reload();
  await page.locator('#page-toggle').click();
  await expect(page.locator('#page-units')).toHaveValue('mm');
});

test('section overrides remain intact, conflicts fail explicitly and unsupported controls are identified', async ({ page }) => {
  const style = 'div.section2 { -d4-page-margin:10pt 200pt;-d4-page-orientation:portrait }';
  await open(page, style);
  await expect(page.locator('#page-overrides')).toBeVisible();
  await page.locator('#page-units').selectOption('pt');
  await page.locator('#page-width').fill('300');
  await page.locator('#page-apply').click();
  await expect(page.locator('#error-message')).toHaveText(messages.en.pageSectionMargins);
  await page.locator('#dismiss-error').click();
  await page.locator('#page-width').fill('630');
  await page.locator('#page-apply').click();
  expect((await download(page)).xml).toContain(style);
  await page.locator('#file').setInputFiles({ name: 'unsupported.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Page.html': strToU8(xml('div.section0 { -d4-page-width:calc(10pt + 1in) }')) })) });
  await expect(page.locator('#page-protection')).toHaveText(messages.en.pageUnsupported);
  await expect(page.locator('#page-width')).toBeDisabled();
  await expect(page.locator('#page-units')).toBeEnabled();
});

for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
  test(`page controls are localized, keyboard-accessible and usable on mobile in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.addInitScript(locale => {
      localStorage.setItem('4wp-language', locale);
      localStorage.setItem('4wp-theme', 'dark');
    }, locale);
    await open(page);
    await expect(page.getByRole('heading', { name: messages[locale].pageSetup, exact: true })).toBeVisible();
    await expect(page.getByRole('spinbutton', { name: messages[locale].pageWidth, exact: true })).toBeVisible();
    await expect(page.locator('#page-units')).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(page.locator('#page-preset')).toBeFocused();
    expect(await page.locator('#page-panel').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await page.locator('#settings-toggle').click();
    for (const theme of ['light', 'system', 'dark']) {
      await page.locator('#theme').selectOption(theme);
      await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
      await expect(page.getByRole('spinbutton', { name: messages[locale].pageWidth, exact: true })).toBeVisible();
    }
    await page.locator('#page-units').focus();
    await page.keyboard.press('Escape');
    await expect(page.locator('#page-panel')).toBeHidden();
    await expect(page.locator('#page-toggle')).toBeFocused();
  });
}
