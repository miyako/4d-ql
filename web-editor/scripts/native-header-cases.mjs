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
import { inspectPDF } from './native-print-cases.mjs';

export async function prepareVariantCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/variant-report.json'), 'utf8'));
  const pdf = name => inspectPDF(resolve(directory, `Output/variant-${name}.pdf`));
  const both = pdf('both-edit');
  const distance = pdf('both-distance');
  const footer = pdf('both-firstFooterDistance');
  const pageMargin = pdf('both-pageMargin');
  const geometry = pdf('geometry-distance');
  const word = (output, page, text) => {
    const found = output.pages[page].words.find(word => word.text === text);
    assert(found, `Missing native PDF word ${text} on page ${page + 1}`);
    return found;
  };
  assert.equal(both.pages.length, 4);
  assert.equal(word(both, 1, 'LEFT').y < 72, true, 'Left header must be effective on page two');
  assert.equal(word(both, 2, 'UNIQUE').y > 700, true, 'Right footer must be effective on page three');
  assert.equal(word(geometry, 1, 'UNIQUE').y > 500, true, 'First-left landscape page must put right variant on page two');
  assert.equal(word(geometry, 2, 'LEFT').y < 80, true, 'First-left landscape page must put left variant on page three');
  assert.equal(word(distance, 0, 'HEADER').x, 13.75, 'First-page area must take priority over left/right');
  assert(Math.abs(word(both, 0, 'HEADER').y - word(distance, 0, 'HEADER').y - (72 / 2.54 - 10.125)) < 0.1);
  assert.equal(word(footer, 0, 'FOOTER').x, 21.75);
  assert(Math.abs(word(footer, 0, 'FOOTER').y - word(distance, 0, 'FOOTER').y - (18.125 - 36 / 2.54)) < 0.1);
  assert.equal(word(pageMargin, 0, 'BODY').x - word(footer, 0, 'BODY').x, 18);
  assert.equal(word(pageMargin, 0, 'FOOTER').y - word(footer, 0, 'FOOTER').y, -18);
  assert(!both.pages[3].words.some(word => ['HEADER', 'FOOTER'].includes(word.text)), 'Absent section areas must not inherit content');
  for (const item of report.cases) {
    for (const stage of item.stages) {
      if (item.name === 'multi') assert.deepEqual(stage.stats.sections[1], item.stages[0].stats.sections[1], 'Another section changed');
      else assert(stage.stats.sections[1].scopes.every(scope => scope.areas.length === 0));
    }
    const original = item.stages[0].stats.sections[0].scopes.find(scope => scope.variant === 0).areas;
    const first = item.stages.find(stage => stage.name === 'first').stats.sections[0].scopes.find(scope => scope.variant === 1).areas;
    assert.deepEqual(first, original, `${item.name}: native first-page creation must copy both current default areas and distances`);
  }
  assert.equal(report.observations.length, 4);
  const missingFirst = pdf('observation-removeFirstHeader');
  const missingRight = pdf('observation-removeRightFooter');
  const missingDefault = pdf('observation-removeDefaultHeader');
  const firstOnly = pdf('observation-createFirstHeader');
  assert(!missingFirst.pages[0].words.some(word => word.text === 'HEADER'), 'An absent enabled first header must not fall back to default');
  assert(!missingRight.pages[2].words.some(word => word.text === 'FOOTER'), 'An absent enabled right footer must not fall back to default');
  for (const page of missingDefault.pages.slice(0, 3)) assert(page.words.some(word => word.text === 'HEADER'), 'Removing a default must retain copied variant content');
  assert(firstOnly.pages[0].words.some(word => word.text === 'ONLY'));
  for (const page of firstOnly.pages.slice(1)) assert(!page.words.some(word => word.text === 'ONLY'), 'A first-only area must not create or populate defaults or facing areas');
  await writeFile(resolve(directory, 'Output/variant-pdf-report.json'), JSON.stringify({
    nativeVersion: report.version, pages: both.pages.length, firstPagePriority: true, facingPair: true,
    firstLeftLandscape: true, absentSectionContentNotInherited: true,
    absentEnabledAreaDoesNotFallBack: true, defaultAndVariantContentIndependent: true,
    firstHeader: word(distance, 0, 'HEADER'), firstFooter: word(footer, 0, 'FOOTER'),
    footerMovesWithBodyBottomMargin: true,
    limits: 'Independent native PDFs establish these scoped positions/content only. Browser preview/print stays a labeled content appendix, not repeating native placement.',
  }, null, 2));
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  try {
    for (const item of report.cases) {
      for (let index = 1; index < item.stages.length; index++) {
        const action = item.stages[index].name;
        if (action === 'left' && ['leftFirst', 'rightFirst'].includes(item.name) ||
          item.name === 'formula' && ['edit', 'deleteLeft', 'deleteRight', 'deleteFirst', 'deleteFirstAgain'].includes(action)) continue;
        const source = `variant-${item.name}-${item.stages[index - 1].name}.4wp`;
        const files = unzipSync(await readFile(resolve(directory, 'Output', source)));
        files['Resources/variant-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128);
        const bytes = zipSync(files);
        const sourceFile = `source-variant-${item.name}-${action}.4wp`;
        await writeFile(resolve(directory, 'Input', sourceFile), bytes);
        const expected = `variant-${item.name}-${action}.4wp`;
        const metadata = { header: { expected }, resources: sourceFile };
        const model = WriteProDocument.open(bytes);
        const positions = action === 'distance' ? [
          ['section1FirstHeader', { top: '10.125pt', right: '11.25pt', bottom: '12.5pt', left: '13.75pt' }],
          ['section1RightFooter', { top: '14.125pt', right: '15.25pt', bottom: '16.5pt', left: '17.75pt' }],
        ] : action === 'firstFooterDistance' ? [
          ['section1FirstFooter', { top: '18.125pt', right: '19.25pt', bottom: '20.5pt', left: '21.75pt' }],
        ] : [];
        const scopes = model.headerAreas().areas.map(area => area.name);
        if (['first', 'firstAgain', 'left', 'right', 'deleteLeft', 'deleteRight', 'deleteFirst', 'deleteFirstAgain'].includes(action)) {
          model.setHeaderVariant(1, /First|first/.test(action) ? 'First' : /Right|right/.test(action) ? 'Right' : 'Left', !action.startsWith('delete'));
        } else if (positions.length) {
          for (const [name, values] of positions) if (scopes.includes(name)) model.setHeaderPosition(values, name);
        } else if (action === 'pageMargin') {
          model.setSectionSetup(1, { margins: { top: '90pt', right: '90pt', bottom: '90pt', left: '90pt' } });
        } else if (action === 'edit') {
          for (const [name, text] of [['section1LeftHeader', 'LEFT UNIQUE'], ['section1RightFooter', 'RIGHT UNIQUE']]) {
            if (!scopes.includes(name)) continue;
            model.setScope(name);
            model.render(document.createElement('article'), messages.en);
            model.editRun(0, text);
          }
        }
        const name = `variant-model-${item.name}-${action}`;
        await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
        cases.push({ name, file: `${name}.4wp`, ...metadata });
        if (!['both', 'geometry', 'empty', 'formula', 'multi'].includes(item.name) || action === 'pageMargin') continue;
        const page = await browser.newPage({ acceptDownloads: true });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', dialog => dialog.accept());
        try {
          await page.goto(url);
          await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
          if (positions.length) {
            for (const [name, values] of positions) if (scopes.includes(name)) {
              await page.locator('#editing-scope').selectOption(name);
              await page.locator('.header-position summary').click();
              await page.locator('#header-units').selectOption('pt');
              for (const [side, value] of Object.entries(values)) await page.locator(`#header-${side}`).fill(value.slice(0, -2));
              await page.locator('#header-position-form button').click();
              await page.locator('.header-position summary').click();
            }
          } else if (action === 'edit') {
            for (const [name, text] of [['section1LeftHeader', 'LEFT UNIQUE'], ['section1RightFooter', 'RIGHT UNIQUE']]) if (scopes.includes(name)) {
              await page.locator('#editing-scope').selectOption(name);
              await page.locator('#paper [contenteditable]').first().fill(text);
            }
          } else {
            await page.locator(/First|first/.test(action) ? '#header-first' : '#header-facing').click();
          }
          await expect(page.getByRole('alert')).toBeHidden();
          await download(`variant-browser-${item.name}-${action}`, metadata, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          await download(`variant-recovered-${item.name}-${action}`, metadata, page);
          const count = positions.length ? positions.filter(([name]) => scopes.includes(name)).length :
            action === 'edit' ? ['section1LeftHeader', 'section1RightFooter'].filter(name => scopes.includes(name)).length : 1;
          if (count && ['both', 'geometry', 'multi'].includes(item.name)) {
            for (let undo = 0; undo < count; undo++) await page.locator('#undo').click();
            await download(`variant-undo-${item.name}-${action}`, { header: { expected: source }, resources: sourceFile }, page);
            await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
            await page.reload();
            await expect(page.locator('#recovery-notice')).toBeVisible();
            for (let redo = 0; redo < count; redo++) await page.locator('#redo').click();
            await download(`variant-recovered-redo-${item.name}-${action}`, metadata, page);
          }
          assert.deepEqual(errors, []);
        } finally { await page.close(); }
      }
    }
  } finally { dom.window.close(); }
}

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
  const reportKind = entry.header.expected.startsWith('paged-') ? 'paged' : entry.header.expected.startsWith('variant-') ? 'variant' : 'header';
  const report = JSON.parse(await readFile(resolve(directory, `Output/${reportKind}-report.json`), 'utf8'));
  const [, kind, action] = entry.header.expected.match(/^(?:header|variant|paged)-(.+?)-([^.]+)\.4wp$/);
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
