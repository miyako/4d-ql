import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { outsideArea } from '../src/headers-footers.js';
import { nativeMetadata } from '../src/native-ranges.js';

export async function prepareHeaderCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/header-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/header-errors.json'), 'utf8')), []);
  assert.deepEqual(report.bookmarkErrors.map(error => error.code), [110], 'Native header bookmarks must fail explicitly');
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  try {
    for (const item of report.cases) {
      for (const action of ['edit', 'variantEdit', 'variantFooterEdit', 'createEmpty', 'create', 'remove', 'grow', 'paragraph', 'lineBreak', 'footerEdit']) {
        if (['variantEdit', 'variantFooterEdit'].includes(action) && !['first', 'facing', 'right'].includes(item.name)) continue;
        const stages = ['original', 'edit', 'variantEdit', 'variantFooterEdit', 'createEmpty', 'create', 'remove', 'split', 'merge', 'disable', 'grow', 'paragraph', 'lineBreak', 'footerEdit'];
        const source = `header-${item.name}-${stages[stages.indexOf(action) - 1]}.4wp`;
        const sourceFile = `source-${item.name}-${action}.4wp`;
        const files = unzipSync(await readFile(resolve(directory, 'Output', source)));
        files['Resources/header-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
        const bytes = zipSync(files);
        await writeFile(resolve(directory, 'Input', sourceFile), bytes);
        const expected = `header-${item.name}-${action}.4wp`;
        const model = WriteProDocument.open(bytes);
        const scope = action === 'footerEdit' ? 'section1Footer' : ['variantEdit', 'variantFooterEdit'].includes(action) ?
          `section1${{ first: 'First', facing: 'Left', right: 'Right' }[item.name]}${action === 'variantFooterEdit' ? 'Footer' : 'Header'}` : 'section1Header';
        model.setScope(scope);
        model.render(document.createElement('article'), messages.en);
        if (['edit', 'variantEdit', 'variantFooterEdit', 'footerEdit'].includes(action)) {
          const outside = outsideArea(model.document, scope);
          model.replaceText({ startRun: 0, endRun: 0, start: 1, end: 3 }, '日é');
          model.render(document.createElement('article'), messages.en);
          model.formatSelection({ startRun: 0, endRun: 1, start: 0, end: 1 }, 'font-weight', 'bold');
          assert.equal(outsideArea(model.document, scope), outside, 'Header edit changed body, metadata or sibling area');
        } else if (['grow', 'paragraph', 'lineBreak'].includes(action)) {
          const selection = { startRun: 0, endRun: 0, start: action === 'paragraph' ? 4 : action === 'lineBreak' ? 1 : 0,
            end: action === 'paragraph' ? 4 : action === 'lineBreak' ? 1 : 0 };
          if (action === 'grow') model.replaceText(selection, '日😀 ');
          else model.splitParagraph(selection, action === 'lineBreak');
        } else {
          if (action !== 'create') model.changeHeaderArea(2, 'Header', action === 'remove');
          if (action === 'create') {
            model.setScope('section2Header');
            model.render(document.createElement('article'), messages.en);
            model.editRun(0, 'SECOND HEADER');
          }
          if (action !== 'create') model.changeHeaderArea(2, 'Footer', action === 'remove');
          if (action === 'create') {
            model.setScope('section2Footer');
            model.render(document.createElement('article'), messages.en);
            model.editRun(0, 'SECOND FOOTER');
          }
        }
        const name = `header-model-${item.name}-${action}`;
        await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
        cases.push({ name, file: `${name}.4wp`, header: { expected }, resources: sourceFile });
        if (!['edit', 'variantEdit', 'variantFooterEdit', 'footerEdit', 'grow', 'paragraph', 'lineBreak'].includes(action)) continue;
        const page = await browser.newPage({ acceptDownloads: true });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', dialog => dialog.accept());
        try {
          await page.goto(url);
          await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
          await page.locator('#editing-scope').selectOption(scope);
          const run = page.locator('#paper [contenteditable]').first();
          await run.evaluate((element, action) => {
            element.focus();
            const offset = action === 'paragraph' ? 4 : action === 'grow' ? 0 : 1;
            window.getSelection().setBaseAndExtent(element.firstChild, offset, element.firstChild, ['edit', 'variantEdit', 'variantFooterEdit', 'footerEdit'].includes(action) ? 3 : offset);
          }, action);
          if (['grow', 'paragraph', 'lineBreak'].includes(action)) {
            if (action === 'grow') await page.keyboard.insertText('日😀 ');
            else await page.keyboard.press(action === 'lineBreak' ? 'Shift+Enter' : 'Enter');
          } else {
            await page.keyboard.insertText('日é');
            await page.locator('#paper').evaluate(paper => {
              const runs = [...paper.querySelectorAll('[contenteditable]')];
              runs[0].focus();
              window.getSelection().setBaseAndExtent(runs[0].firstChild, 0, runs[1].firstChild, 1);
            });
            await page.locator('#bold').click();
          }
          await expect(page.getByRole('alert')).toBeHidden();
          await download(`header-browser-${item.name}-${action}`, { header: { expected }, resources: sourceFile }, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          await expect(page.locator('#editing-scope')).toHaveValue(scope);
          await download(`header-recovered-${item.name}-${action}`, { header: { expected }, resources: sourceFile }, page);
          assert.deepEqual(errors, []);
        } finally { await page.close(); }
      }
    }
  } finally { dom.window.close(); }
}

export async function verifyHeaderCase(directory, entry, actual) {
  const open = async path => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, path))));
  const expected = await open(`Output/${entry.header.expected}`);
  const actualModel = await open(`Output/${entry.name}.4wp`);
  const report = JSON.parse(await readFile(resolve(directory, 'Output/header-report.json'), 'utf8'));
  const [, kind, action] = entry.header.expected.match(/^header-(.+?)-([^.]+)\.4wp$/);
  const expectedStats = report.cases.find(item => item.name === kind).stages.find(stage => stage.name === action).stats;
  assert.deepEqual(actual.headerImported, expectedStats, `${entry.name}: native coordinates, body bookmarks, text or area margins differ`);
  assert.deepEqual(actual.headerImported, actual.headerReopened, `${entry.name}: native header getters changed on reopen`);
  const areaTexts = model => model.headerAreas().areas.map(area => [area.name, area.element.textContent]);
  assert.deepEqual(areaTexts(actualModel), areaTexts(expected), `${entry.name}: native section/variant content differs`);
  assert.equal(actualModel.document.querySelector('body').outerHTML, expected.document.querySelector('body').outerHTML,
    `${entry.name}: native body/area text, formatting or formula XML differs`);
  assert.deepEqual([...actualModel.document.querySelectorAll('head style')].map(style => style.textContent).join(''),
    [...expected.document.querySelectorAll('head style')].map(style => style.textContent).join(''),
    `${entry.name}: native association or margin declarations differ`);
  assert.deepEqual(nativeMetadata(actualModel.document).bookmarks, nativeMetadata(expected.document).bookmarks);
}
