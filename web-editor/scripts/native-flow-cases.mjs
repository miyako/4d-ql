import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { zipSync, unzipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import { tabTypes, tabLeaders, defaultTab } from '../src/flow-settings.js';
import { pagePoints } from '../src/page-setup.js';

const stop = (position, type = 'left', leader = '') => ({ position, type, leader });
const nativeStop = item => ({ ...item, type: tabTypes.indexOf(item.type) });
const nativeParagraph = (index, settings) => ({ index, stops: settings.stops.map(nativeStop), default: nativeStop(settings.default) });
function selection(model, first = 0, last = first, insertion = false) {
  model.render(document.createElement('article'), messages.en);
  const startRun = model.runs.findIndex(node => node.parentElement.closest('p,li') === model.blocks[first]);
  const endRun = model.runs.findIndex(node => node.parentElement.closest('p,li') === model.blocks[last]);
  assert(startRun >= 0 && endRun >= 0);
  return { startRun, endRun, start: insertion ? 1 : 0, end: insertion ? 1 : first === last ? 0 : 1 };
}

export async function prepareFlowCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/layout-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 49);
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/layout-errors.json'), 'utf8')), []);
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  for (const item of report.cases.filter(item => ['"', '\\'].includes(item.leader))) {
    const bytes = new Uint8Array(await readFile(resolve(directory, 'Output', `${item.name}.4wp`)));
    const model = WriteProDocument.open(bytes);
    model.render(document.createElement('article'), messages.en);
    assert.throws(() => model.resetParagraphTabs(selection(model)), { code: 'tabsUnsupported' });
    assert.deepEqual(model.export(), bytes, 'Uneditable lossy native leaders must preserve original archive bytes');
  }
  const entries = [
    ...['layout-base', 'layout-columns-section', 'layout-cascade', 'layout-cascade-reset', 'layout-rich', 'layout-associated',
      ...report.cases.filter(item => item.type !== undefined && item.leader !== '"').map(item => item.name)].map(source => ({ source, action: 'identity' })),
    ...['layout-base', 'layout-rich', 'layout-associated', 'layout-columns-section'].flatMap(source => [
      { source, action: 'columns', index: 0, count: 2, gap: '18pt', browser: true },
      { source, action: 'columns', index: 2, count: 3, gap: '0.5cm', browser: true },
    ]),
    { source: 'layout-columns-section', action: 'columns', index: 2, count: null, gap: null, browser: true },
    { source: 'layout-columns-section', action: 'columns', index: 2, gap: null, browser: true },
    ...tabTypes.flatMap(type => tabLeaders.map(leader => ({
      source: 'layout-base', action: 'set', first: 0, last: 0, browser: true,
      settings: { stops: [stop('36pt', type, leader)], default: defaultTab },
    }))),
    ...tabTypes.flatMap(type => tabLeaders.map(leader => ({
      source: 'layout-base', action: 'default', first: 0, last: 0, browser: true,
      settings: { stops: [], default: stop('18pt', type, leader) },
    }))),
    ...['layout-base', 'layout-cascade', 'layout-rich'].flatMap(source => [
      { source, action: 'set', first: 0, last: 1, settings: { stops: [stop('36pt', 'decimal', '.'), stop('72pt', 'right', '_')], default: stop('18pt', 'center', '-') } },
      { source, action: 'reset', first: 0, last: 1, browser: true },
      { source, action: 'insert', first: 0, last: 0, browser: true, point: 2 },
    ]),
    { source: 'layout-tabs-1', action: 'remove', first: 0, last: 0, browser: true, position: 36,
      settings: { stops: [stop('72pt', 'right', '.')], default: stop('18pt') } },
    { source: 'layout-cascade', action: 'interval', first: 0, last: 1, browser: true,
      paragraphs: [
        nativeParagraph(0, { stops: [stop('48pt', 'center', '.')], default: stop('18.123456789pt') }),
        nativeParagraph(1, { stops: [], default: stop('18.123456789pt') }),
      ] },
    { source: 'layout-rich', action: 'set', first: 4, last: 4, browser: true,
      settings: { stops: [stop('36pt', 'right', '.')], default: defaultTab } },
    { source: 'layout-rich', action: 'insert', first: 4, last: 4, browser: true,
      point: report.rich.paragraphs[4].start + 1 },
  ];
  try {
    for (const [index, edit] of entries.entries()) {
      const sourceFile = `flow-source-${index}.4wp`;
      const files = unzipSync(await readFile(resolve(directory, 'Output', `${edit.source}.4wp`)));
      files['Resources/flow-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
      const bytes = zipSync(files);
      await writeFile(resolve(directory, 'Input', sourceFile), bytes);
      const model = WriteProDocument.open(bytes);
      const before = model.serialize();
      const selected = selection(model, edit.first, edit.last, edit.action === 'insert');
      const metadata = nativeMetadata(model.document).bookmarks;
      const flow = { ...edit, source: sourceFile };
      delete flow.browser;
      if (edit.action === 'columns') model.setColumns(edit.index, Object.fromEntries(['count', 'gap'].filter(key => Object.hasOwn(edit, key)).map(key => [key, edit[key]])));
      else if (edit.action === 'insert') model.replaceText(selected, '\t');
      else if (edit.action !== 'identity') {
        flow.paragraphs = edit.paragraphs || Array.from({ length: edit.last - edit.first + 1 }, (_, offset) =>
          edit.action === 'reset' ? { index: edit.first + offset } : nativeParagraph(edit.first + offset, edit.settings));
        if (edit.action === 'reset') model.resetParagraphTabs(selected);
        else {
          flow.action = 'tabs';
          model.setParagraphTabs(selected, settings => edit.action === 'remove' ? { ...settings, stops: settings.stops.filter(item => pagePoints(item.position) !== edit.position) } :
            edit.action === 'interval' ? { ...settings, default: { ...settings.default, position: '18.123456789pt' } } : structuredClone(edit.settings));
        }
      }
      if (edit.action !== 'insert') assert.deepEqual(nativeMetadata(model.document).bookmarks, metadata, 'Formatting changed raw bookmark offsets');
      const changed = model.serialize() !== before;
      assert.equal(model.undoStack.length, Number(changed), 'Flow operation must be one atomic transaction');
      const name = `flow-model-${index}-${edit.action}`;
      await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
      cases.push({ name, file: `${name}.4wp`, flow, resources: sourceFile });
      if (!edit.browser) continue;
      const page = await browser.newPage({ acceptDownloads: true });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('dialog', dialog => dialog.accept());
      try {
        await page.goto(url);
        await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
        await expect(page.locator('#document-title')).toHaveText(model.title);
        await page.locator('#paper').evaluate((paper, selected) => {
          const first = paper.querySelector(`[data-run="${selected.startRun}"]`);
          const last = paper.querySelector(`[data-run="${selected.endRun}"]`);
          first.focus();
          getSelection().setBaseAndExtent(first.firstChild, selected.start, last.firstChild, selected.end);
        }, selected);
        if (edit.action === 'columns') {
          await page.locator('#page-toggle').click();
          await page.locator('#page-target').selectOption(String(edit.index));
          const unit = typeof edit.gap === 'string' ? edit.gap.match(/[a-z]+$/)[0] : 'pt';
          await page.locator('#page-units').selectOption(unit);
          for (const key of ['count', 'gap'].filter(key => Object.hasOwn(edit, key))) {
            if (edit.index) await page.locator('#column-inherit-' + key).setChecked(edit[key] === null);
            if (edit[key] !== null) await page.locator('#column-' + key).fill(String(key === 'count' ? edit[key] : Number.parseFloat(edit[key])));
          }
          await page.locator('#columns-apply').click();
        } else if (edit.action === 'insert') await page.locator('#insert-tab').click();
        else {
          await page.locator('#tabs-toggle').click();
          await page.locator('#tab-units').selectOption('pt');
          if (edit.action === 'reset') await page.locator('#tab-reset').click();
          else if (edit.action === 'remove') {
            await page.locator('#tab-stop-list').selectOption(String(edit.position));
            await page.locator('#tab-stop-remove').click();
          } else if (edit.action === 'interval' || edit.action === 'default') {
            await page.locator('#tab-interval').fill(edit.action === 'interval' ? '18.123456789' : '18');
            if (edit.action === 'default') {
              await page.locator('#tab-default-type').selectOption(edit.settings.default.type);
              await page.locator('#tab-default-leader').selectOption(edit.settings.default.leader);
            }
            await page.locator('#tab-default-apply').click();
          } else {
            const item = edit.settings.stops[0];
            await page.locator('#tab-position').fill(String(pagePoints(item.position)));
            await page.locator('#tab-type').selectOption(item.type);
            await page.locator('#tab-leader').selectOption(item.leader);
            await page.locator('#tab-stop-apply').click();
          }
        }
        await expect(page.getByRole('alert')).toBeHidden();
        await download(`flow-browser-${index}`, { flow, resources: sourceFile }, page);
        if (changed) {
          await page.locator('#undo').click();
          await download(`flow-browser-undo-${index}`, { flow: { ...flow, action: 'identity' }, resources: sourceFile }, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          await page.locator('#redo').click();
          await download(`flow-browser-recovered-${index}`, { flow, resources: sourceFile }, page);
        }
        assert.deepEqual(errors, [], 'Flow browser runtime errors');
      } finally { await page.close(); }
    }
  } finally { dom.window.close(); }
}

export async function verifyFlowCase(directory, entry, actual) {
  const normalize = value => JSON.parse(JSON.stringify(value), (key, item) =>
    ['gap', 'width', 'height', 'top', 'right', 'bottom', 'left'].includes(key) && typeof item === 'string' ?
      Math.round(pagePoints(item) * 1e6) / 1e6 : item);
  for (const stage of ['Imported', 'Reopened']) {
    assert.deepEqual(normalize(actual[`flow${stage}`]), normalize(actual.flowExpected), `${entry.name}: effective native columns/tab arrays differ at ${stage}`);
    assert.deepEqual(normalize(actual[`flowSections${stage}`]), normalize(actual.flowSectionsExpected), `${entry.name}: native section geometry or hidden associations differ`);
  }
  for (const stage of ['imported', 'reopened']) for (const key of ['text', 'metadata', 'bookmarks', 'tables', 'images', 'formulas', 'links', 'first']) {
    assert.deepEqual(actual[stage][key], actual.flowWebExpected[key], `${entry.name}: native ${stage} changed ${key}`);
  }
  const open = async path => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, path))));
  const expected = await open(`Output/${entry.name}-expected.4wp`);
  const reexport = await open(`Output/${entry.name}.4wp`);
  assert.deepEqual(nativeMetadata(reexport.document).bookmarks, nativeMetadata(expected.document).bookmarks, `${entry.name}: raw native bookmark pairs differ`);
  assert.equal(reexport.document.querySelector('body').outerHTML, expected.document.querySelector('body').outerHTML, `${entry.name}: native reexport body differs`);
  assert.deepEqual([...reexport.document.querySelectorAll('head style')].map(node => node.textContent),
    [...expected.document.querySelectorAll('head style')].map(node => node.textContent), `${entry.name}: native reexport declarations differ`);
}
