import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';

const selection = (run, start, end = start) => ({ startRun: run, start, endRun: run, end });

export async function prepareFormulaCases(directory, cases, browser, url) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
  assert.equal(report.formulas.length, 14, 'Independent native formula variants');
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  const render = model => model.render(document.createElement('article'), messages.en);
  const errors = [];
  try {
    for (const item of report.formulas) {
      const sourceFile = `formula-${item.name}-original.4wp`;
      const bytes = new Uint8Array(await readFile(resolve(directory, 'Output', sourceFile)));
      const original = WriteProDocument.open(bytes);
      render(original);
      const formula = { sourceFile, expected: item.native };
      await writeFile(resolve(directory, 'Input', sourceFile), bytes);
      cases.push({ name: `formula-original-${item.name}`, file: sourceFile, formula });
      if (!item.operations.length) {
        assert(original.readOnly, `${item.name}: unsupported formula structure must remain protected`);
        continue;
      }
      assert.equal(item.operations.length, 20, `${item.name}: native operation coverage`);
      assert.equal(new Set(item.operations.map(operation => operation.name)).size, 20, `${item.name}: unique native operations`);
      assert.equal(original.nativeView().text, 'AB\ufffcCD', `${item.name}: formula is one native slot`);
      for (const operation of item.operations) {
        const model = WriteProDocument.open(bytes);
        render(model);
        const run = text => model.runs.findIndex(node => node.data === text);
        switch (operation.name) {
          case 'before': model.replaceText(selection(run('AB'), 1), '😀日'); break;
          case 'start': model.replaceText(selection(run('AB'), 2), 'XY'); break;
          case 'end': model.replaceText(selection(run('CD'), 0), 'XY'); break;
          case 'after': model.replaceText(selection(run('CD'), 1), '😀日'); break;
          case 'cut': model.replaceText(selection(run('AB'), 0, 2), '', 'cut'); break;
          case 'replace': model.replaceText(selection(run('CD'), 0, 2), 'XY'); break;
          case 'format': model.formatSelection(selection(run('CD'), 0, 2), 'font-weight', 'bold'); break;
          case 'break': model.splitParagraph(selection(run('CD'), 1), true); break;
          case 'paste':
          case 'pasteBefore':
          case 'pasteStart':
          case 'pasteEnd':
            model.paste(selection(run(['pasteBefore', 'pasteStart'].includes(operation.name) ? 'AB' : 'CD'),
              operation.name === 'pasteStart' ? 2 : operation.name === 'pasteEnd' ? 0 : 1), '<p><b>XY</b></p><p>Z</p>', '');
            break;
          default: {
            const caret = model.splitParagraph(selection(run(/Before|Start/.test(operation.name) ? 'AB' : 'CD'),
              operation.name.endsWith('Start') ? 2 : operation.name.endsWith('End') ? 0 : 1));
            if (operation.name.startsWith('join')) {
              render(model);
              model.mergeBoundary(model.runs.indexOf(caret.node), true);
            }
          }
        }
        const native = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/formula-${item.name}-${operation.name}-native.4wp`))));
        const serialized = nativeMetadata(native.document).bookmarks;
        assert.deepEqual(nativeMetadata(model.document).bookmarks, serialized, `${item.name}/${operation.name}: native raw pairs`);
        const ranges = { text: operation.after.text, bookmarks: operation.after.bookmarks, serialized };
        const formula = { sourceFile, expected: operation.native };
        const name = `formula-model-${item.name}-${operation.name}`;
        await writeFile(resolve(directory, `Input/${name}.4wp`), model.export());
        cases.push({ name, file: `${name}.4wp`, ranges, formula });

        const page = await browser.newPage({ acceptDownloads: true });
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', dialog => dialog.accept());
        try {
          await page.goto(url);
          await page.locator('#file').setInputFiles(resolve(directory, 'Output', sourceFile));
          await page.locator('.formula-object').waitFor();
          const before = ['before', 'start', 'cut', 'splitBefore', 'joinBefore', 'splitStart', 'joinStart', 'pasteBefore', 'pasteStart'].includes(operation.name);
          const offset = operation.name === 'cut' || ['end', 'replace', 'format', 'splitEnd', 'joinEnd', 'pasteEnd'].includes(operation.name)
            ? 0 : ['start', 'splitStart', 'joinStart', 'pasteStart'].includes(operation.name) ? 2 : 1;
          await page.locator('#paper [contenteditable]').filter({ hasText: before ? /^AB$/ : /^CD$/ }).evaluate((element, { offset, select }) => {
            element.focus();
            getSelection().setBaseAndExtent(element.firstChild, offset, element.firstChild, select ? 2 : offset);
          }, { offset, select: ['cut', 'replace', 'format'].includes(operation.name) });
          switch (operation.name) {
            case 'before':
              await page.locator('#paper [contenteditable]').filter({ hasText: /^AB$/ }).evaluate(element => {
                element.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
                element.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertCompositionText', data: '😀日', isComposing: true }));
                element.textContent = 'A😀日B';
                element.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '😀日' }));
              });
              break;
            case 'after': await page.keyboard.insertText('😀日'); break;
            case 'start':
            case 'end':
            case 'replace': await page.keyboard.type('XY'); break;
            case 'format': await page.locator('#bold').click(); break;
            case 'cut':
            case 'paste':
            case 'pasteBefore':
            case 'pasteStart':
            case 'pasteEnd':
              await page.locator('#paper').evaluate((paper, cut) => {
                const clipboardData = new DataTransfer();
                if (!cut) clipboardData.setData('text/html', '<p><b>XY</b></p><p>Z</p>');
                paper.dispatchEvent(new ClipboardEvent(cut ? 'cut' : 'paste', { clipboardData, bubbles: true, cancelable: true }));
              }, operation.name === 'cut');
              break;
            default:
              await page.keyboard.press(operation.name === 'break' ? 'Shift+Enter' : 'Enter');
              if (operation.name.startsWith('join')) await page.keyboard.press('Backspace');
          }
          await page.waitForFunction(() => document.querySelector('#error').hidden);
          const download = async name => {
            const waiting = page.waitForEvent('download');
            await page.locator('#download').click();
            await (await waiting).saveAs(resolve(directory, `Input/${name}.4wp`));
            cases.push({ name, file: `${name}.4wp`, ranges, formula });
          };
          await download(`formula-browser-${item.name}-${operation.name}`);
          if (item.name === 'supplied' && ['before', 'splitBefore', 'paste'].includes(operation.name)) {
            await page.locator('#undo').click();
            await page.locator('#redo').click();
            await page.waitForFunction(() => document.querySelector('#draft-state').textContent === 'Local draft saved');
            await page.reload();
            await page.locator('#recovery-notice').waitFor();
            await download(`formula-recovered-${item.name}-${operation.name}`);
          }
        } finally { await page.close(); }
      }
    }
    assert.deepEqual(errors, [], 'Formula browser runtime errors');
  } finally { dom.window.close(); }
}

export async function verifyFormulaCase(directory, entry, actual) {
  const original = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, 'Output', entry.formula.sourceFile))));
  const input = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, 'Input', entry.file))));
  const output = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/${entry.name}.4wp`))));
  assert.deepEqual(input.formulaElements().map(node => node.outerHTML), original.formulaElements().map(node => node.outerHTML),
    `${entry.name}: browser changed original formula XML/cache/attributes`);
  for (const [name, bytes] of Object.entries(original.files)) {
    if (name !== original.entry) assert.deepEqual(input.files[name], bytes, `${entry.name}: changed archive resource ${name}`);
  }
  const signature = model => model.formulaElements().map(node => {
    const { source, name, value } = model.formula(node);
    return { source, name, value };
  });
  assert.deepEqual(signature(output), signature(original), `${entry.name}: native reexport changed formula source/cache`);
  for (const key of ['text', 'metadata', 'bookmarks', 'formulas', 'images', 'tables']) {
    assert.deepEqual(actual.imported[key], entry.formula.expected[key], `${entry.name}: native ${key} differs from independent operation`);
  }
}
