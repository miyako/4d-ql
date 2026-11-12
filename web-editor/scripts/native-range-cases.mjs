import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';

const selection = (startRun, start, endRun = startRun, end = start) => ({ startRun, start, endRun, end });

export async function prepareRangeCases(directory, cases) {
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/range-errors.json'), 'utf8')), [], 'Native probe errors');
  const report = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
  assert.equal(report.splices.length, 165, 'Native splice coverage');
  assert.equal(new Set(report.splices.map(item => JSON.stringify(item.edit))).size, 165, 'Unique native splices');
  assert.equal(report.offsets.length, 11, 'Native offset coverage');
  assert.equal(report.operations.length, 10, 'Native structural operation coverage');
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  const render = model => model.render(document.createElement('article'), {});
  const save = async (model, name, expected) => {
    const file = `${name}.4wp`;
    await writeFile(resolve(directory, 'Input', file), model.export());
    cases.push({ name, file, ranges: { text: expected.text, bookmarks: expected.bookmarks } });
  };
  const original = new Uint8Array(await readFile(resolve(directory, 'Output/range-editing.4wp')));
  for (const [index, item] of report.splices.entries()) {
    const model = WriteProDocument.open(original);
    assert(!model.readOnly, 'Native base document must be editable');
    render(model);
    model.replaceText(selection(0, item.edit.start - 1, 0, item.edit.end - 1), item.edit.text);
    await save(model, `range-splice-${index}`, item);
  }
  for (const item of report.offsets) {
    const model = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/range-${item.name}.4wp`))));
    assert(!model.readOnly, `${item.name}: offsets supported`);
    render(model);
    await save(model, `range-offset-${item.name}`, item);
  }
  const image = `data:image/png;base64,${(await readFile(resolve(directory, 'Resources/checker.png'))).toString('base64')}`;
  for (const item of report.operations) {
    const model = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/range-edit-${item.name}-original.4wp`))));
    assert(!model.readOnly, `${item.name}: structure supported`);
    render(model);
    switch (item.name) {
      case 'split': model.splitParagraph(selection(0, 3)); break;
      case 'lineBreak': model.splitParagraph(selection(0, 3), true); break;
      case 'pictureInsert': model.insertImage(selection(0, 3), image, 48, 32, 'checker'); break;
      case 'richPaste': model.paste(selection(0, 3), '<p><b>XY</b></p><p>Z</p>', ''); break;
      case 'join': model.mergeBoundary(1, true); break;
      case 'pictureDelete': model.changeImage(0); break;
      case 'pictureMove': model.moveImage(0, selection(1, 3)); break;
      case 'appendParagraph': model.addParagraph(0); break;
      case 'format': model.formatSelection(selection(0, 1, 0, 7), 'font-weight', 'bold'); break;
      case 'emptyTyping': model.replaceText(selection(0, 0), '😀日'); break;
      default: assert.fail(`Unknown native operation ${item.name}`);
    }
    const expectedPairs = Object.fromEntries(Object.entries(item.after.bookmarks).map(([name, value]) => [name, [value.start, value.end]]));
    assert.deepEqual(nativeMetadata(model.document).bookmarks, expectedPairs, `${item.name}: native range mismatch`);
    await save(model, `range-operation-${item.name}`, item.after);
  }
  dom.window.close();
}
