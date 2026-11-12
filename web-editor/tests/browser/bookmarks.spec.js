import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { zipSync, strToU8, strFromU8, unzipSync } from 'fflate';
import structuralEvidence from '../fixtures/native-structures.json' with { type: 'json' };
import complexEvidence from '../fixtures/native-complex.json' with { type: 'json' };

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
  return JSON.parse(await page.evaluate(xml => {
    const doc = new DOMParser().parseFromString(xml, 'application/xhtml+xml');
    return JSON.stringify({ text: doc.querySelector('body').textContent, bookmarks: JSON.parse(doc.querySelector('meta[name="bookmarks"]').getAttribute('content')) });
  }, xml));
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

test('bookmark panel creates, navigates, validates, renames, deletes and recovers atomic history', async ({ page }) => {
  await open(page);
  await select(page, 1, 4);
  await page.locator('#bookmarks-toggle').click();
  await expect(page.locator('#bookmark-name')).toBeFocused();
  await page.locator('#bookmark-name').fill('日本語😀é');
  await page.locator('#bookmark-name').press('Enter');
  await expect(page.locator('#bookmark-list button')).toHaveCount(4);
  expect((await downloaded(page)).bookmarks['日本語😀é']).toEqual([1, 4]);
  await page.locator('#bookmark-list button').filter({ hasText: /^日本語😀é$/ }).click();
  expect(await page.evaluate(() => getSelection().toString())).toBe('bcd');
  await expect(page.locator('#bookmark-status')).toContainText('[1, 4)');
  await page.locator('#bookmark-name').fill('span');
  await page.locator('#bookmark-rename').click();
  await expect(page.getByRole('alert')).toContainText('Nothing was overwritten');
  expect((await downloaded(page)).bookmarks['日本語😀é']).toEqual([1, 4]);
  await page.locator('#dismiss-error').click();
  await page.locator('#bookmark-name').fill('bad name');
  await page.locator('#bookmark-rename').click();
  await expect(page.getByRole('alert')).toContainText('name was not changed');
  await page.locator('#dismiss-error').click();
  await page.locator('#bookmark-name').fill('Renamed_日本語');
  await page.locator('#bookmark-rename').click();
  await expect(page.locator('#bookmark-list button').filter({ hasText: /^Renamed_日本語$/ })).toBeVisible();
  await page.locator('#history-toggle').click();
  await page.locator('#version-name').fill('Bookmark version');
  await page.locator('#save-version').click();
  await page.locator('#history-toggle').click();
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.locator('#bookmark-delete').click();
  await expect(page.locator('#bookmark-list button')).toHaveCount(3);
  await page.locator('#undo').click();
  await expect(page.locator('#bookmark-list button')).toHaveCount(4);
  await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
  await page.reload();
  await expect(page.locator('#recovery-notice')).toBeVisible();
  await page.locator('#bookmarks-toggle').click();
  await expect(page.locator('#bookmark-list button')).toHaveCount(4);
  await page.locator('#redo').click();
  await expect(page.locator('#bookmark-list button')).toHaveCount(3);
  await page.locator('#history-toggle').click();
  await page.locator('#version-list li').filter({ hasText: 'Bookmark version' }).getByRole('button').click();
  await expect(page.locator('#bookmark-list button')).toHaveCount(4);
  expect((await downloaded(page)).bookmarks.Renamed_日本語).toEqual([1, 4]);
});

test('first and collapsed bookmarks persist and restore through download and native-offset navigation', async ({ page }) => {
  await page.goto('/');
  await page.locator('#new').click();
  await page.locator('#paper [contenteditable]').fill('A😀日éB');
  await select(page, 1, 3);
  await page.locator('#bookmarks-toggle').click();
  await page.locator('#bookmark-name').fill('__proto__');
  await page.locator('#bookmark-create').click();
  await select(page, 3);
  await page.locator('#bookmark-name').fill('point');
  await page.locator('#bookmark-create').click();
  await page.locator('#bookmark-list button').filter({ hasText: /^point$/ }).click();
  expect(await page.evaluate(() => [getSelection().isCollapsed, getSelection().anchorOffset])).toEqual([true, 3]);
  const file = await downloaded(page);
  expect(file.bookmarks).toEqual({ ['__proto__']: [1, 3], point: [3, 3] });
  await page.locator('#bookmark-list button').filter({ hasText: /^point$/ }).click();
  await page.keyboard.insertText('XY');
  expect((await downloaded(page)).bookmarks).toEqual({ ['__proto__']: [1, 3], point: [3, 3] });
});

test('table bookmarks navigate raw endpoints without applying native getter cell normalization', async ({ page }) => {
  await openStructural(page, 'table');
  await page.locator('#bookmarks-toggle').click();
  await page.locator('#bookmark-list button').filter({ hasText: /^unit10$/ }).click();
  await expect(page.locator('#bookmark-status')).toContainText('[9, 10)');
  await expect(page.locator('#paper .bookmark-boundary')).toHaveCount(1);
  await expect(page.locator('#bookmark-list button').filter({ hasText: /^unit10$/ })).toBeFocused();
  await expect(page.locator('#bookmark-create')).toBeDisabled();
  const before = (await downloaded(page)).bookmarks;
  await page.locator('#bookmark-name').fill('rawBoundary');
  await page.locator('#bookmark-rename').click();
  expect((await downloaded(page)).bookmarks.rawBoundary).toEqual(before.unit10);
  await page.locator('#bookmark-list button').filter({ hasText: /^unit8$/ }).click();
  expect(await page.evaluate(() => getSelection().toString())).toBe('A');
  await expect(page.locator('#bookmark-status')).toContainText('[7, 8)');
});

test('bookmark controls remain localized, keyboard accessible, responsive and protected', async ({ page }) => {
  await openStructural(page, 'boundary-table');
  await page.locator('#bookmarks-toggle').click();
  await expect(page.locator('#bookmark-create')).toBeDisabled();
  await page.locator('#bookmark-list button').filter({ hasText: /^whole$/ }).click();
  await expect(page.locator('#bookmark-rename')).toBeDisabled();
  await expect(page.locator('#bookmark-delete')).toBeDisabled();
  await page.locator('#bookmark-name').focus();
  await page.keyboard.press('Escape');
  await expect(page.locator('#bookmarks-panel')).toBeHidden();
  await expect(page.locator('#bookmarks-toggle')).toBeFocused();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator('#settings-toggle').click();
  for (const [locale, title] of [['ja', 'ブックマーク'], ['fr', 'Signets'], ['de', 'Lesezeichen'], ['es', 'Marcadores'], ['it', 'Segnalibri'], ['en', 'Bookmarks']]) {
    await page.locator('#language').selectOption(locale);
    await expect(page.locator('#bookmarks-toggle')).toHaveText(title);
  }
  for (const theme of ['light', 'dark', 'system']) {
    await page.locator('#theme').selectOption(theme);
    await page.locator('#bookmarks-toggle').click();
    await expect(page.locator('#bookmark-name')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.locator('#bookmark-name').press('Escape');
  }
});

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
  await page.locator('.editing-tools summary').click();
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
    await page.locator('.editing-tools summary').click();
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
  await page.locator('.editing-tools summary').click();
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

async function openComplex(page, name) {
  const item = complexEvidence.cases.find(item => item.name === name);
  await page.goto('/');
  await page.locator('#file').setInputFiles({
    name: `${name}.4wp`, mimeType: 'application/zip',
    buffer: Buffer.from(zipSync({ 'Document.html': strToU8(item.xml), 'Resources/opaque.bin': Uint8Array.of(0, 255, 128) })),
  });
  await expect(page.locator('#paper')).toContainText('BEFORE');
  return item;
}

for (const name of ['grid-addColumn', 'grid-appendColumn', 'uneven-addColumn', 'uneven-appendColumn', 'empty-addColumn', 'empty-appendColumn']) {
  test(`bookmarked ${name} downloads native pairs and recovers coherent undo/redo`, async ({ page }) => {
    const item = await openComplex(page, name);
    const firstRow = page.locator('#paper tr').first().locator('td');
    await selectRun((name.includes('append') ? firstRow.last() : firstRow.first()).locator('[contenteditable]').first(), 0);
    await page.locator('.editing-tools summary').click();
    await page.locator('#add-column').focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('alert')).toBeHidden();
    expect((await downloaded(page)).bookmarks).toEqual(serialized(item));
    await page.locator('#undo').click();
    await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
    await page.reload();
    await page.locator('#redo').click();
    expect((await downloaded(page)).bookmarks).toEqual(serialized(item));
  });
}

test('cross-cell bookmarks allow endpoint additions and management but explain protected operations', async ({ page }) => {
  await openComplex(page, 'grid-identity');
  await page.locator('#capabilities summary').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#capability-list')).toContainText('bookmark spans cells');
  await selectRun(page.locator('#paper td [contenteditable]').first(), 2);
  const before = await downloaded(page);
  await selectRun(page.locator('#paper td [contenteditable]').first(), 2);
  await page.keyboard.insertText('X');
  await expect(page.getByRole('alert')).toContainText('Insertion inside a bookmark spanning cells');
  expect(await downloaded(page)).toEqual(before);
  await page.locator('#dismiss-error').click();
  await selectRun(page.locator('#paper td [contenteditable]').first(), 0);
  await page.keyboard.insertText('XY');
  const item = complexEvidence.cases.find(item => item.name === 'grid-typing');
  expect((await downloaded(page)).bookmarks).toEqual(serialized(item));
  await page.locator('#bookmarks-toggle').click();
  await page.locator('#bookmark-list button').filter({ hasText: /^b9_12$/ }).click();
  await page.locator('#bookmark-name').fill('cross_日本語');
  await page.locator('#bookmark-rename').click();
  expect((await downloaded(page)).bookmarks.cross_日本語).toEqual(serialized(item).b9_12);
});

test('merged-table typing preserves geometry, versions and localized accessible capability notices', async ({ page }) => {
  const item = await openComplex(page, 'rectangle-typing');
  await page.locator('#history-toggle').click();
  await page.locator('#version-name').fill('Merged original');
  await page.locator('#save-version').click();
  await page.locator('#history-toggle').click();
  await selectRun(page.locator('#paper td [contenteditable]').first(), 0);
  await page.keyboard.insertText('XY');
  expect((await downloaded(page)).bookmarks).toEqual(serialized(item));
  await expect(page.locator('#paper td').first()).toHaveAttribute('rowspan', '2');
  await expect(page.locator('#paper td').first()).toHaveAttribute('colspan', '2');
  await page.locator('.editing-tools summary').click();
  await expect(page.locator('#add-row')).toHaveAttribute('aria-describedby', 'table-capability');
  await page.locator('#add-row').focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('alert')).toContainText('merged or irregular tables');
  await page.locator('#dismiss-error').click();
  await page.locator('#history-toggle').click();
  await page.locator('#version-list li').filter({ hasText: 'Merged original' }).getByRole('button').click();
  expect((await downloaded(page)).bookmarks).toEqual(Object.fromEntries(Object.entries(item.before).map(([name, pair]) => [name, pair.map(offset => offset - 1)])));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator('#settings-toggle').click();
  for (const [locale, title] of [['ja', '編集機能と制限'], ['fr', 'Capacités de modification'], ['de', 'Bearbeitungsmöglichkeiten'], ['es', 'Capacidades de edición'], ['it', 'Capacità di modifica'], ['en', 'Editing capabilities']]) {
    await page.locator('#language').selectOption(locale);
    await expect(page.locator('#capabilities summary')).toHaveText(title);
    await page.locator('#capabilities summary').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#capability-list')).toBeVisible();
    await page.keyboard.press('Enter');
  }
  for (const theme of ['light', 'dark', 'system']) {
    await page.locator('#theme').selectOption(theme);
    await expect(page.locator('#capabilities summary')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
});
