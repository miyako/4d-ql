import { expect, test } from '@playwright/test';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { strFromU8, unzipSync } from 'fflate';

const fixtures = fileURLToPath(new URL('../../../Tests/FourDFileKitTests/Fixtures/WritePro/', import.meta.url));

test('create, format a selection, undo, redo, download and reopen', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  let run = page.locator('[contenteditable]').first();
  await run.fill('Hello world');
  await expect(page.locator('#save-state')).toHaveText('Unsaved changes');
  await run.evaluate(element => {
    const range = document.createRange();
    range.setStart(element.firstChild, 6);
    range.setEnd(element.firstChild, 11);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
  });
  await page.getByRole('button', { name: 'Bold', exact: true }).click();
  await expect(page.locator('#paper span[style*="font-weight"]')).toHaveText('world');
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('#paper span[style*="font-weight"]')).toHaveCount(0);
  await page.getByRole('button', { name: 'Redo', exact: true }).click();
  await expect(page.locator('#paper span[style*="font-weight"]')).toHaveText('world');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe('Untitled.4wp');
  const bytes = readFileSync(await download.path());
  const files = unzipSync(bytes);
  expect(strFromU8(files['Document.html'])).toContain('font-weight:bold');
  await page.locator('#file').setInputFiles({ name: 'edited.4wp', mimeType: 'application/zip', buffer: bytes });
  await expect(page.locator('#paper')).toContainText('Hello world');
  await expect(page.locator('#save-state')).toHaveText('Ready');
  expect(errors).toEqual([]);
});

test('real fixtures preserve protected content and invalid input does not replace the document', async ({ page }) => {
  await page.goto('/');
  await page.locator('#file').setInputFiles(`${fixtures}objects.4wp`);
  await expect(page.locator('#readonly-notice')).toBeVisible();
  await expect(page.locator('[contenteditable]')).toHaveCount(0);
  await expect(page.locator('#document-title')).toHaveText('Objects probe');
  await page.locator('#file').setInputFiles({ name: 'bad.4wp', mimeType: 'application/zip', buffer: Buffer.from('not a zip') });
  await expect(page.getByRole('alert')).toContainText('Invalid, corrupt or unsupported ZIP');
  await expect(page.locator('#document-title')).toHaveText('Objects probe');
  await page.locator('#file').setInputFiles(`${fixtures}text.4wp`);
  await expect(page.locator('[contenteditable]').first()).toHaveText('Document title');
  await expect(page.getByRole('alert')).toBeHidden();
});

test('six languages, appearance persistence and mobile layout', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('#settings-toggle').click();
  for (const [locale, open] of [['fr', 'Ouvrir un .4wp'], ['de', '.4wp öffnen'], ['es', 'Abrir .4wp'], ['it', 'Apri .4wp'], ['ja', '.4wpを開く'], ['en', 'Open .4wp']]) {
    await page.locator('#language').selectOption(locale);
    await expect(page.locator('#open')).toHaveText(open);
    await expect(page.locator('html')).toHaveAttribute('lang', locale);
  }
  await page.locator('#theme').selectOption('dark');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await page.locator('[contenteditable]').first().fill('Mobile text');
  await page.getByRole('button', { name: 'Add paragraph', exact: true }).click();
  await expect(page.locator('#paper p')).toHaveCount(2);
});

test('line breaks and collapsed-caret formatting retain the complete run', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  const run = page.locator('[contenteditable]').first();
  await run.fill('A paragraph');
  await run.press('ArrowLeft');
  await page.getByRole('button', { name: 'Italic', exact: true }).click();
  await expect(page.locator('#paper span[style*="font-style"]')).toHaveText('A paragraph');
  const active = page.locator('[contenteditable]').first();
  await active.press('End');
  await active.press('Shift+Enter');
  await page.keyboard.type('Next line');
  await expect(page.locator('#paper br')).toHaveCount(1);
  await expect(page.locator('#paper')).toContainText('Next line');
});

test('whole-run formatting toggles off and blank paper accepts focus', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await page.locator('#paper').click({ position: { x: 150, y: 170 } });
  await expect(page.locator('[contenteditable]').first()).toBeFocused();
  await page.keyboard.type('Format me');
  for (const [name, property, on, off] of [
    ['Bold', 'fontWeight', '700', '400'],
    ['Italic', 'fontStyle', 'italic', 'normal'],
    ['Underline', 'textDecorationLine', 'underline', 'none'],
  ]) {
    await page.getByRole('button', { name, exact: true }).click();
    expect(await page.locator('[contenteditable]').first().evaluate((element, prop) => getComputedStyle(element)[prop], property)).toBe(on);
    await page.getByRole('button', { name, exact: true }).click();
    expect(await page.locator('[contenteditable]').first().evaluate((element, prop) => getComputedStyle(element)[prop], property)).toBe(off);
  }
});

test('preloaded brief is editable and exports as a complete native document', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#document-title')).toHaveText('North Room - concept brief');
  await expect(page.locator('#save-state')).toHaveText('Ready');
  await expect(page.locator('#paper')).toContainText('slower afternoons.');
  await expect(page.locator('#paper .preserved-object')).toHaveCount(0);
  await expect(page.locator('#paper table tr')).toHaveCount(3);
  const opening = page.locator('#paper table [contenteditable]').last();
  await opening.fill('Six weeks to welcome our first readers');
  await expect(page.locator('#save-state')).toHaveText('Unsaved changes');
  const pending = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Download .4wp', exact: true }).click();
  const download = await pending;
  expect(download.suggestedFilename()).toBe('North Room - concept brief.4wp');
  const bytes = readFileSync(await download.path());
  const xml = strFromU8(unzipSync(bytes)['North Room.html']);
  expect(xml).toContain('-d4-version:2.20');
  expect(xml).toContain('Six weeks to welcome our first readers');
  await page.locator('#file').setInputFiles({ name: 'brief.4wp', mimeType: 'application/zip', buffer: bytes });
  await expect(page.locator('#paper table [contenteditable]').last()).toHaveText('Six weeks to welcome our first readers');
  await expect(page.locator('#paper')).toContainText('slower afternoons.');
  await expect(page.locator('#save-state')).toHaveText('Ready');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(page.locator('#document-title')).toHaveText('Untitled');
  await expect(page.locator('#paper table')).toHaveCount(0);
});
