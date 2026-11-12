import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';
import { pagePoints } from '../src/page-setup.js';
import { messages } from '../src/i18n.js';

const kinds = { 1: 'section', 2: 'page', 5: 'continuous' };
const settings = { name: '日本語 & Section😀', orientation: 'portrait',
  margins: { top: '12pt', right: '13pt', bottom: '14pt', left: '15pt' } };

function caret(model, point) {
  model.render(document.createElement('article'), messages.en);
  const { node, offset } = model.nativeView().locate(point);
  const index = model.runs.indexOf(node);
  assert(index >= 0, 'Native boundary must map to an editable text run');
  return { startRun: index, endRun: index, start: offset, end: offset };
}

export async function prepareSectionCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/section-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 27);
  assert.equal(report.names.length, 17);
  assert(report.names.some(item => item.name.includes("'") && item.name !== item.reopened), 'Missing native quoted-name roundtrip counterexample');
  for (const item of report.names.filter(item => !/['"\\\u0000-\u001f]/u.test(item.name) && item.name.trim() === item.name)) {
    assert.equal(item.name, item.reopened, 'Accepted section names must survive independent native export/reimport');
  }
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/section-errors.json'), 'utf8')), []);
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  const entries = [
    ...report.cases.filter(item => item.type).flatMap(item => [
      { source: `${item.name}-original`, action: 'insert', point: item.point, type: item.type },
      { source: `${item.name}-insert`, action: 'remove', point: item.point },
    ]),
    ...['inherited', 'overridden', 'associated'].flatMap(kind => [
      { source: `section-${kind}-7-original`, action: 'settings', index: 2, name: settings.name, orientation: 0 },
      { source: `section-${kind}-7-original`, action: 'reset', index: 2 },
      { source: `section-${kind}-7-original`, action: 'defaults' },
    ]),
    { source: 'section-settings', action: 'reset', index: 2 },
    { source: 'section-overridden-7-original', action: 'insert', point: 8, type: 5 },
    ...[1, 5].map(type => ({ source: 'section-combined', action: 'insert', point: 9, type })),
    ...report.cases.filter(item => item.type).map(item =>
      ({ source: `${item.name}-insert`, action: 'typing', point: 1 })),
    ...report.names.filter(item => !/['"\\\u0000-\u001f]/u.test(item.name) && item.name.trim() === item.name && item.name !== '').map(item =>
      ({ source: 'section-inherited-7-original', action: 'name', index: 2, name: item.name })),
  ];
  try {
    for (const [index, edit] of entries.entries()) {
      const sourceFile = `section-source-${index}.4wp`;
      const files = unzipSync(await readFile(resolve(directory, 'Output', `${edit.source}.4wp`)));
      files['Resources/section-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
      const bytes = zipSync(files);
      await writeFile(resolve(directory, 'Input', sourceFile), bytes);
      const section = { ...edit, source: sourceFile };
      const model = WriteProDocument.open(bytes);
      const originalBody = model.document.querySelector('body').outerHTML;
      const originalBookmarks = nativeMetadata(model.document).bookmarks;
      if (edit.action === 'insert') model.insertBreak(caret(model, edit.point), kinds[edit.type]);
      else if (edit.action === 'typing') model.replaceText(caret(model, edit.point), 'XY');
      else if (edit.action === 'remove') {
        model.render(document.createElement('article'), messages.en);
        const block = model.blocks.findIndex(block => model.nativeView().bounds(block).end === edit.point);
        assert(block >= 0);
        model.removeBreak(block);
      } else {
        if (edit.action === 'defaults') model.setPageSetup({ width: '612pt', height: '792pt', orientation: 'landscape',
          top: '30pt', right: '30pt', bottom: '30pt', left: '30pt' });
        else model.setSectionSetup(edit.index, edit.action === 'settings' ? settings : edit.action === 'name' ? { name: edit.name } : { orientation: null, margins: null });
        assert.equal(model.document.querySelector('body').outerHTML, originalBody, 'Section geometry/metadata changed body XML');
        assert.deepEqual(nativeMetadata(model.document).bookmarks, originalBookmarks);
      }
      assert.equal(model.undoStack.length, edit.action === 'reset' && edit.source.includes('inherited') ? 0 : 1, 'Section edits must be one atomic transaction');
      const name = `section-model-${index}-${edit.action}`;
      await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
      cases.push({ name, file: `${name}.4wp`, section, resources: sourceFile });
      if (['reset', 'defaults', 'name', 'typing'].includes(edit.action) || edit.source === 'section-overridden-7-original' && edit.action === 'insert') continue;
      const page = await browser.newPage({ acceptDownloads: true });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      try {
        await page.goto(url);
        await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
        await expect(page.locator('#document-title')).toHaveText(model.title);
        if (edit.action === 'insert') {
          const original = WriteProDocument.open(bytes);
          const selection = caret(original, edit.point);
          await page.locator(`[data-run="${selection.startRun}"]`).evaluate((element, offset) => {
            element.focus();
            window.getSelection().collapse(element.firstChild, offset);
          }, selection.start);
        }
        await page.locator('#page-toggle').click();
        if (edit.action === 'insert') {
          await page.locator('#break-kind').selectOption(kinds[edit.type]);
          await page.locator('#break-insert').click();
        } else if (edit.action === 'remove') {
          await page.locator('#break-remove').click();
        } else {
          await page.locator('#page-target').selectOption(String(edit.index));
          await page.locator('#section-name').fill(settings.name);
          await page.locator('#section-inherit-orientation').uncheck();
          await page.locator('#page-orientation').selectOption('portrait');
          await page.locator('#section-inherit-margins').uncheck();
          await page.locator('#page-units').selectOption('pt');
          for (const [side, value] of Object.entries(settings.margins)) await page.locator('#page-' + side).fill(String(pagePoints(value)));
          await page.locator('#page-apply').click();
        }
        await expect(page.getByRole('alert')).toBeHidden();
        await download(`section-browser-${index}`, { section, resources: sourceFile }, page);
        await page.locator('#undo').click();
        await download(`section-browser-undo-${index}`, { section: { ...section, action: 'identity' }, resources: sourceFile }, page);
        await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
        await page.reload();
        await expect(page.locator('#recovery-notice')).toBeVisible();
        await page.locator('#redo').click();
        await download(`section-browser-recovered-${index}`, { section, resources: sourceFile }, page);
        assert.deepEqual(errors, [], 'Section browser runtime errors');
      } finally { await page.close(); }
    }
  } finally { dom.window.close(); }
}

export async function verifySectionCase(directory, entry, actual) {
  const normalize = value => JSON.parse(JSON.stringify(value), (key, item) =>
    ['width', 'height', 'top', 'right', 'bottom', 'left'].includes(key) && typeof item === 'string' ?
      Math.round(pagePoints(item) * 1e6) / 1e6 : item);
  for (const stage of ['sectionImported', 'sectionReopened']) {
    assert.deepEqual(normalize(actual[stage]), normalize(actual.sectionExpected), `${entry.name}: native ${stage} break slots, names, inheritance or header/footer associations differ`);
  }
  for (const stage of ['imported', 'reopened']) {
    for (const key of ['text', 'metadata', 'bookmarks', 'tables', 'images', 'formulas', 'links', 'first']) {
      assert.deepEqual(actual[stage][key], actual.sectionWebExpected[key], `${entry.name}: native ${stage} changed ${key}`);
    }
  }
  const open = async path => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, path))));
  const nativeExpected = await open(`Output/${entry.name}-expected.4wp`);
  const nativeActual = await open(`Output/${entry.name}.4wp`);
  assert.equal(nativeActual.document.querySelector('body').outerHTML, nativeExpected.document.querySelector('body').outerHTML, `${entry.name}: native body/hidden XML differs`);
  assert.deepEqual([...nativeActual.document.querySelectorAll('head style')].map(node => node.textContent),
    [...nativeExpected.document.querySelectorAll('head style')].map(node => node.textContent), `${entry.name}: native section/subsection/anchor declarations differ`);
  assert.deepEqual(nativeMetadata(nativeActual.document).bookmarks, nativeMetadata(nativeExpected.document).bookmarks, `${entry.name}: native raw bookmark offsets differ`);
  if (['settings', 'reset', 'defaults', 'name', 'identity'].includes(entry.section.action)) {
    const source = await open(`Input/${entry.section.source}`);
    const input = await open(`Input/${entry.file}`);
    assert.equal(input.document.querySelector('body').outerHTML, source.document.querySelector('body').outerHTML, `${entry.name}: geometry changed original body/association XML`);
  }
}
