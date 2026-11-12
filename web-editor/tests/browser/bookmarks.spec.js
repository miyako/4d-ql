import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, strToU8, strFromU8, unzipSync } from 'fflate';
import structuralEvidence from '../fixtures/native-structures.json' with { type: 'json' };

async function open(page) {
  const xml = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Bookmarks</title><meta name="bookmarks" content="{&quot;span&quot;:[2,5],&quot;point&quot;:[3,3],&quot;all&quot;:[0,9]}"/></head><body><p>abcdefghi</p></body></html>';
  await page.goto('/');
  await page.locator('#file').setInputFiles({ name: 'bookmarks.4wp', mimeType: 'application/zip', buffer: Buffer.from(zipSync({ 'Document.html': strToU8(xml) })) });
  await expect(page.locator('#document-title')).toHaveText('Bookmarks');
}

async function select(page, start, end = start) {
  await page.locator('#paper').evaluate((paper, bounds) => {
    const walker = document.createTreeWalker(paper.querySelector('p'), NodeFilter.SHOW_TEXT);
    const points = [];
    let offset = 0;
    while (walker.nextNode()) {
      const node = walker.currentNode;
      points.push({ node, start: offset, end: offset + node.length });
      offset += node.length;
    }
    const point = value => {
      const item = points.find(item => item.start <= value && item.end >= value && item.node.length);
      return [item.node, value - item.start];
    };
    const [node] = point(bounds.start);
    node.parentElement.focus();
    window.getSelection().setBaseAndExtent(...point(bounds.start), ...point(bounds.end));
  }, { start, end });
}

async function downloaded(page) {
  const waiting = page.waitForEvent('download');
  await page.locator('#download').click();
  const bytes = readFileSync(await (await waiting).path());
  const files = unzipSync(bytes);
  const xml = strFromU8(Object.entries(files).find(([name]) => /\.html$/i.test(name))[1]);
  return page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
    return { text: doc.querySelector('body').textContent, bookmarks: JSON.parse(doc.querySelector('meta[name="bookmarks"]').getAttribute('content')) };
  }, xml);
}

const structural = name => structuralEvidence.structures.find(item => item.name === name);
const serialized = item => Object.fromEntries(Object.entries(item.serialized).map(([name, pair]) => [name, pair.map(offset => offset - 1)]));
async function openStructural(page, name) {
  await page.goto('/');
  await page.locator('#file').setInputFiles({
    name: `${name}.4wp`, mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(structural(name).xml) })),
  });
  await expect(page.locator('#paper')).toContainText('BEFORE');
}
async function selectRun(run, start, end = start) {
  await run.evaluate((element, { start, end }) => {
    element.focus();
    window.getSelection().setBaseAndExtent(element.firstChild, start, element.firstChild, end);
  }, { start, end });
}

test('bookmark-aware typing, Unicode, deletion, cut, undo and recovered redo keep offsets', async ({ page }) => {
  await open(page);
  await expect(page.locator('#readonly-notice')).toContainText('Bookmarks are adjusted');
  await select(page, 0);
  await page.keyboard.type('aa');
  await expect(page.locator('#paper p')).toHaveText('aaabcdefghi');
  expect((await downloaded(page)).bookmarks).toEqual({ span: [4, 7], point: [5, 5], all: [2, 11] });
  await select(page, 5);
  await page.keyboard.insertText('😀日');
  expect((await downloaded(page)).bookmarks).toEqual({ span: [4, 10], point: [5, 5], all: [2, 14] });
  await select(page, 8);
  await page.keyboard.press('Backspace');
  await page.keyboard.press('Backspace');
  expect((await downloaded(page)).bookmarks).toEqual({ span: [4, 7], point: [5, 5], all: [2, 11] });
  await select(page, 4, 7);
  await page.locator('#paper').evaluate(paper => {
    paper.dispatchEvent(new ClipboardEvent('cut', { clipboardData: new DataTransfer(), bubbles: true, cancelable: true }));
  });
  expect((await downloaded(page)).bookmarks).toEqual({ all: [2, 8] });
  await page.locator('#undo').click();
  expect((await downloaded(page)).bookmarks).toEqual({ span: [4, 7], point: [5, 5], all: [2, 11] });
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect((await downloaded(page)).bookmarks).toEqual({ all: [2, 8] });
});

test('paragraph/paste changes and table insertion preserve bookmarks', async ({ page }) => {
  await open(page);
  await select(page, 3);
  await page.keyboard.press('Enter');
  expect((await downloaded(page)).bookmarks).toEqual({ span: [2, 6], point: [3, 3], all: [0, 10] });
  await page.locator('#paper p').nth(1).locator('[contenteditable]').first().evaluate(element => {
    element.focus();
    window.getSelection().collapse(element.firstChild, 0);
  });
  await page.keyboard.press('Backspace');
  await expect(page.locator('#paper p')).toHaveText('abcdefghi');
  expect((await downloaded(page)).bookmarks).toEqual({ span: [2, 5], point: [3, 3], all: [0, 9] });
  await select(page, 3);
  await page.locator('#paper').evaluate(paper => {
    const clipboardData = new DataTransfer();
    clipboardData.setData('text/html', '<p><b>XY</b></p><p>Z</p>');
    paper.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
  });
  expect((await downloaded(page)).bookmarks).toEqual({ span: [2, 9], point: [3, 3], all: [0, 13] });
  const before = await downloaded(page);
  await page.locator('summary').click();
  await page.locator('#insert-table').click();
  await expect(page.locator('#paper table')).toHaveCount(1);
  expect((await downloaded(page)).bookmarks).toEqual(before.bookmarks);
});

test('table Unicode editing, undo and recovered redo keep native ranges coherent', async ({ page }) => {
  await openStructural(page, 'unicodeCell');
  await selectRun(page.locator('#paper td [contenteditable]').first(), 1);
  await page.keyboard.insertText('😀日é');
  const edited = await downloaded(page);
  expect(edited.bookmarks).toEqual(serialized(structural('unicodeCell')));
  await page.locator('#undo').click();
  await expect(page.locator('#paper td').first()).toHaveText('AB');
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#redo').click();
  expect(await downloaded(page)).toEqual(edited);
});

for (const [name, cell, button] of [
  ['addRow', 0, 'add-row'], ['appendRow', 2, 'add-row'],
  ['removeRow', 0, 'remove-row'], ['removeLastRow', 2, 'remove-row'],
  ['removeColumn', 0, 'remove-column'], ['removeLastColumn', 1, 'remove-column'],
]) {
  test(`table ${name} matches independently native-generated ranges`, async ({ page }) => {
    await openStructural(page, name);
    await selectRun(page.locator('#paper td').nth(cell).locator('[contenteditable]').first(), 0);
    await page.locator('summary').click();
    await page.locator(`#${button}`).click();
    expect((await downloaded(page)).bookmarks).toEqual(serialized(structural(name)));
    await page.locator('#undo').click();
    await expect(page.locator('#paper td')).toHaveCount(4);
    await page.locator('#redo').click();
    expect((await downloaded(page)).bookmarks).toEqual(serialized(structural(name)));
  });
}

test('native indented list splitting preserves levels and bookmark positions', async ({ page }) => {
  await openStructural(page, 'listSplit');
  await selectRun(page.locator('#paper li [contenteditable]').filter({ hasText: /^CD$/ }), 1);
  await page.keyboard.press('Enter');
  expect((await downloaded(page)).bookmarks).toEqual(serialized(structural('listSplit')));
  await expect(page.locator('#paper ul li').nth(1)).toHaveCSS('margin-left', '32px');
  await expect(page.locator('#paper ul li').nth(2)).toHaveCSS('margin-left', '32px');
});

test('partial cross-cell bookmarks and column insertion are visibly protected', async ({ page }) => {
  await openStructural(page, 'boundary-table');
  await expect(page.locator('#readonly-notice')).toContainText('Read-only');
  await expect(page.locator('#paper [contenteditable]')).toHaveCount(0);
  await page.locator('#file').setInputFiles({
    name: 'table.4wp', mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(structural('table').xml) })),
  });
  await expect(page.locator('#paper td [contenteditable]')).toHaveCount(4);
  const before = await downloaded(page);
  await selectRun(page.locator('#paper td [contenteditable]').first(), 0);
  await page.locator('summary').click();
  await page.locator('#add-column').click();
  await expect(page.getByRole('alert')).toContainText('Adding columns');
  expect(await downloaded(page)).toEqual(before);
});

test('bookmark typing groups undo, maps IME commits and rejects unmapped input', async ({ page }) => {
  await open(page);
  await select(page, 0);
  await page.keyboard.type('XYZ');
  await page.locator('#undo').click();
  await expect(page.locator('#paper p')).toHaveText('abcdefghi');
  await select(page, 3);
  await page.locator('[contenteditable]').first().evaluate(element => {
    element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    element.dispatchEvent(new CompositionEvent('compositionend', { data: '日本😀', bubbles: true }));
  });
  expect((await downloaded(page)).bookmarks).toEqual({ span: [2, 9], point: [3, 3], all: [0, 13] });
  const before = await downloaded(page);
  await select(page, 3);
  expect(await page.locator('[contenteditable]').first().evaluate(element => {
    return element.dispatchEvent(new InputEvent('beforeinput', { inputType: 'deleteWordBackward', bubbles: true, cancelable: true }));
  })).toBe(false);
  await expect(page.getByRole('alert')).toBeVisible();
  expect(await downloaded(page)).toEqual(before);
});
