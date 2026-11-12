import { test, expect } from '@playwright/test';
import { zipSync, strToU8 } from 'fflate';

async function select(page, first, start, last, end, backward = false) {
  await page.locator('#paper').evaluate((paper, bounds) => {
    const runs = paper.querySelectorAll('[data-run]');
    const a = [runs[bounds.first].firstChild, bounds.start];
    const b = [runs[bounds.last].firstChild, bounds.end];
    window.getSelection().setBaseAndExtent(...(bounds.backward ? b : a), ...(bounds.backward ? a : b));
  }, { first, start, last, end, backward });
}

test('mixed formatting preserves backward selections, independent decorations and clear highlighting', async ({ page }) => {
  await page.goto('/');
  const xml = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Selections</title></head><body><p><span style="font-weight:bold;font-size:18pt;text-decoration:underline;background-color:yellow">Alpha</span><span style="font-size:12pt;text-decoration:line-through">Beta</span></p></body></html>';
  await page.locator('#file').setInputFiles({ name: 'selection.4wp', mimeType: 'application/zip', buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml) })) });
  await expect(page.locator('#document-title')).toHaveText('Selections');
  await select(page, 0, 0, 1, 4, true);
  for (const id of ['bold', 'underline', 'strike']) await expect(page.locator(`#${id}`)).toHaveAttribute('aria-pressed', 'mixed');
  await expect(page.locator('#size')).toHaveValue('__mixed__');
  await page.locator('#strike').click();
  await page.locator('#underline').click();
  await expect(page.locator('#strike')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#underline')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#highlight').selectOption('#fff2a8');
  await page.locator('#highlight').selectOption('transparent');
  expect(await page.locator('[data-run]').evaluateAll(runs => runs.every(run => getComputedStyle(run).backgroundColor === 'rgba(0, 0, 0, 0)'))).toBe(true);
  await page.locator('#undo').click();
  await expect(page.locator('#highlight')).toHaveValue('#fff2a8');
  await page.locator('#redo').click();
  await expect(page.locator('#highlight')).toHaveValue('transparent');
  expect(await page.evaluate(() => [window.getSelection().getRangeAt(0).toString(), window.getSelection().anchorNode.textContent, window.getSelection().focusNode.textContent])).toEqual(['AlphaBeta', 'Beta', 'Alpha']);
  expect(await page.locator('#paper').evaluate(paper => {
    const clipboardData = new DataTransfer();
    paper.dispatchEvent(new ClipboardEvent('cut', { clipboardData, bubbles: true, cancelable: true }));
    return clipboardData.getData('text/plain');
  })).toBe('AlphaBeta');
  await page.locator('#undo').click();
  await expect(page.locator('#paper p')).toHaveText('AlphaBeta');
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  expect(await page.evaluate(() => window.getSelection().getRangeAt(0).toString())).toBe('AlphaBeta');
});

test('undo and redo restore replacement selections and typing does not retain the blank sentinel', async ({ page }) => {
  await page.goto('/');
  await page.locator('#new').click();
  await page.locator('[contenteditable]').first().focus();
  await expect(page.locator('#highlight')).toHaveValue('transparent');
  await page.locator('[contenteditable]').first().fill('Hello world');
  await select(page, 0, 6, 0, 11, true);
  await page.keyboard.type('Reader');
  await expect(page.locator('#paper p')).toHaveText('Hello Reader');
  await page.locator('#undo').click();
  await expect(page.locator('#paper p')).toHaveText('Hello world');
  expect(await page.evaluate(() => window.getSelection().toString())).toBe('world');
  await page.locator('#redo').click();
  await expect(page.locator('#paper p')).toHaveText('Hello Reader');
  expect(await page.evaluate(() => [window.getSelection().isCollapsed, window.getSelection().focusOffset])).toEqual([true, 12]);
  await page.keyboard.type('!');
  await expect(page.locator('#paper p')).toHaveText('Hello Reader!');
});

test('links remain inert and invalid URLs fail explicitly', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('#new').click();
  await page.locator('[contenteditable]').first().fill('Read more');
  await select(page, 0, 0, 0, 9);
  await page.locator('#link-toggle').click();
  await page.locator('#link-url').fill('https://example.org/');
  await page.locator('#apply-link').click();
  await expect(page.locator('#paper a')).toHaveCount(0);
  await expect(page.locator('#paper .inert-link')).toHaveText('Read more');
  await page.locator('#link-url').fill('javascript:alert(1)');
  await page.locator('#apply-link').click();
  await expect(page.getByRole('alert')).toBeVisible();
  await page.locator('#remove-link').click();
  await expect(page.locator('#paper .inert-link')).toHaveCount(0);
  await expect(page.locator('#paper p')).toHaveText('Read more');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('plain-text clipboard paste is literal and denied or stale reads report errors', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'clipboard', { value: {
      readText: () => {
        if (window.denyClipboard) return Promise.reject(new Error('Synthetic denial'));
        if (window.delayClipboard) return new Promise(resolve => { window.finishClipboard = resolve; });
        return Promise.resolve('<b>Plain</b>\nNext');
      },
    } });
  });
  await page.goto('/');
  await page.locator('#new').click();
  await page.locator('.editing-tools summary').click();
  await page.locator('#paste-plain').click();
  await expect(page.locator('#paper > p')).toHaveText(['<b>Plain</b>', 'Next']);
  await page.evaluate(() => { window.denyClipboard = true; });
  await page.locator('#paste-plain').click();
  await expect(page.getByRole('alert')).toContainText('clipboard');
  await page.evaluate(() => { window.denyClipboard = false; window.delayClipboard = true; });
  await page.locator('#paste-plain').click();
  await page.locator('[contenteditable]').first().fill('Changed');
  await page.evaluate(() => window.finishClipboard('Old clipboard'));
  await expect(page.getByRole('alert')).toContainText('changed');
  await expect(page.locator('#paper > p').first()).toHaveText('Changed');
  await select(page, 0, 0, 0, 7);
  await page.locator('[data-run]').first().evaluate(element => {
    element.dispatchEvent(new KeyboardEvent('keydown', { key: 'v', ctrlKey: true, shiftKey: true, bubbles: true }));
    const clipboardData = new DataTransfer();
    clipboardData.setData('text/plain', 'Literal');
    clipboardData.setData('text/html', '<strong>Formatted</strong>');
    element.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
  });
  await expect(page.locator('#paper > p').first()).toHaveText('Literal');
  expect(await page.locator('[data-run]').first().evaluate(element => getComputedStyle(element).fontWeight)).toBe('400');
});
