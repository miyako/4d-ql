import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, unzipSync, strToU8, strFromU8 } from 'fflate';
import evidence from '../fixtures/native-formulas.json' with { type: 'json' };
import { messages } from '../../src/i18n.js';

async function open(page, name = 'supplied', bookmarks = true) {
  let xml = evidence.variants.find(item => item.name === name).xml;
  if (!bookmarks) xml = xml.replace(/<meta name="bookmarks"[^>]+\/>/, '');
  await page.goto('/');
  await page.locator('#file').setInputFiles({
    name: 'formula.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Doc.html': strToU8(xml), 'opaque.4dfo': new Uint8Array([0, 255, 7]) })),
  });
  await expect(page.locator('.formula-object')).toBeVisible();
}

async function select(page, text, start, end = start) {
  await page.locator('#paper [contenteditable]').filter({ hasText: new RegExp(`^${text}$`) }).evaluate((element, [start, end]) => {
    element.focus();
    getSelection().setBaseAndExtent(element.firstChild, start, element.firstChild, end);
  }, [start, end]);
}

async function snapshot(page) {
  const waiting = page.waitForEvent('download');
  await page.locator('#download').click();
  const files = unzipSync(readFileSync(await (await waiting).path()));
  const xml = strFromU8(files['Doc.html']);
  const data = await page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
    return {
      body: doc.querySelector('body').outerHTML,
      formula: doc.querySelector('body p span[style*="-d4-ref"]').outerHTML,
      bookmarks: doc.querySelector('meta[name="bookmarks"]')?.getAttribute('content'),
    };
  }, xml);
  return { ...data, resource: Array.from(files['opaque.4dfo']) };
}

test('typing, IME, cut/paste, replace and recovered history retain authoritative formulas and resources', async ({ page }) => {
  await open(page);
  const original = await snapshot(page);
  await select(page, 'AB', 2);
  await page.keyboard.type('XY');
  await select(page, 'CD', 0);
  await page.locator('#paper [contenteditable]').filter({ hasText: /^CD$/ }).evaluate(element => {
    element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    element.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertCompositionText', data: '日', isComposing: true }));
    element.textContent = '日CD';
    element.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '日本語' }));
  });
  await expect(page.locator('#paper')).toContainText('日本語CD');
  await select(page, 'AB', 0, 1);
  await page.locator('#paper').evaluate(paper => {
    paper.dispatchEvent(new ClipboardEvent('cut', { clipboardData: new DataTransfer(), bubbles: true, cancelable: true }));
  });
  await select(page, '日本語', 3);
  await page.locator('#paper').evaluate(paper => {
    const clipboardData = new DataTransfer();
    clipboardData.setData('text/html', '<p><b>P</b></p><p>Q</p>');
    paper.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
  });
  await expect(page.getByRole('alert')).toBeHidden();
  await page.locator('#find-toggle').click();
  await page.locator('#find-query').fill('CD');
  await page.locator('#replacement').fill('EF');
  await page.locator('#replace-all').click();
  await expect(page.locator('#paper')).toContainText('EF');
  const changed = await snapshot(page);
  expect(changed.formula).toBe(original.formula);
  expect(changed.resource).toEqual(original.resource);
  await page.locator('#undo').click();
  await expect(page.locator('#paper')).toContainText('CD');
  await page.locator('#redo').click();
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  expect(await snapshot(page)).toEqual(changed);
});

test('typing, formatting, paste and deletion selections cannot cross or enter an atomic formula', async ({ page }) => {
  await open(page);
  const original = await snapshot(page);
  const cross = async (intoBadge = false) => {
    await page.locator('#paper').evaluate((paper, intoBadge) => {
      const first = paper.querySelector('[data-run]').firstChild;
      const last = intoBadge ? paper.querySelector('.formula-source').lastChild : paper.querySelectorAll('[data-run]')[1].firstChild;
      first.parentElement.focus();
      getSelection().setBaseAndExtent(first, 1, last, 1);
    }, intoBadge);
  };
  for (const action of ['type', 'cut', 'paste', 'format', 'badge']) {
    await cross(action === 'badge');
    if (action === 'type' || action === 'badge') await page.keyboard.type('X');
    else if (action === 'format') await page.keyboard.press('ControlOrMeta+b');
    else await page.locator('#paper').evaluate((paper, action) => {
      const clipboardData = new DataTransfer();
      clipboardData.setData('text/plain', 'X');
      paper.dispatchEvent(new ClipboardEvent(action, { clipboardData, bubbles: true, cancelable: true }));
    }, action);
    if (action === 'format') await expect(page.locator('#bold')).toBeDisabled();
    else await expect(page.getByRole('alert'), action).toBeVisible();
    expect(await snapshot(page)).toEqual(original);
    if (await page.getByRole('alert').isVisible()) await page.locator('#dismiss-error').click();
  }
  for (const [text, offset, key] of [['AB', 2, 'Delete'], ['CD', 0, 'Backspace']]) {
    await select(page, text, offset);
    await page.keyboard.press(key);
    await expect(page.getByRole('alert')).toBeVisible();
    expect(await snapshot(page)).toEqual(original);
    await page.locator('#dismiss-error').click();
  }
});

test('unbookmarked surrounding edits, paragraph split/join and formatting preserve the formula object', async ({ page }) => {
  await open(page, 'suppliedZero', false);
  const original = await snapshot(page);
  await select(page, 'AB', 1);
  await page.keyboard.press('Enter');
  await expect(page.locator('#paper .section-flow > p')).toHaveCount(2);
  await page.keyboard.press('Backspace');
  await expect(page.locator('#paper .section-flow > p')).toHaveCount(1);
  await select(page, 'CD', 0, 2);
  await page.locator('#bold').click();
  await select(page, 'CD', 1);
  await page.keyboard.insertText('😀日');
  const after = await snapshot(page);
  expect(after.formula).toBe(original.formula);
  expect(after.bookmarks).toBeUndefined();
  expect(after.body).toContain('😀日');
  await expect(page.getByRole('alert')).toBeHidden();
});

test('all six languages, themes and mobile show explicit missing values with keyboard-readable source', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await open(page, 'zero');
  await page.locator('#settings-toggle').click();
  for (const locale of ['en', 'ja', 'fr', 'de', 'es', 'it']) {
    await page.locator('#language').selectOption(locale);
    for (const theme of ['light', 'dark']) {
      await page.locator('#theme').selectOption(theme);
      const badge = page.getByRole('group', { name: messages[locale].formulaReadonly });
      await expect(badge).toContainText(messages[locale].formulaUnavailable);
      await expect(badge.locator('.formula-source')).toHaveText(`${messages[locale].formulaSource}: 0`);
      await badge.focus();
      await expect(badge).toBeFocused();
      expect(await badge.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
    }
  }
});
