import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';

const selection = (startRun, start, endRun = startRun, end = start) => ({ startRun, start, endRun, end });

export async function prepareBookmarkCases(directory, cases) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
  assert.equal(report.management.names.length, 160, 'Native name matrix missing');
  assert.equal(report.management.operations.length, 13, 'Native management coverage');
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  const open = async file => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, 'Output', file))));
  const render = model => model.render(document.createElement('article'), {});
  const save = async (model, name, nativeFile, expected) => {
    const native = await open(nativeFile);
    const serialized = nativeMetadata(native.document).bookmarks;
    assert.deepEqual(nativeMetadata(model.document).bookmarks, serialized, `${name}: raw metadata differs from native`);
    const file = `${name}.4wp`;
    await writeFile(resolve(directory, 'Input', file), model.export());
    cases.push({ name, file, ranges: { text: expected.text, bookmarks: expected.bookmarks, serialized } });
  };
  const original = 'bookmark-create-original.4wp';
  for (const [index, item] of report.management.names.entries()) {
    const model = await open(original);
    render(model);
    const names = Object.keys(item.after.bookmarks);
    if (names.length !== 1 || names[0] !== item.name) {
      if (!names.length) assert.deepEqual(item.errors.map(error => error.code), [110], 'Expected native empty-name error');
      else assert.deepEqual(item.errors, [], 'Native normalization errors');
      assert.throws(() => model.changeBookmark(item.name, { selection: selection(0, 1, 0, 3) }), /bookmarkNameInvalid/, `Native normalization must be rejected: ${JSON.stringify(item.name)}`);
      continue;
    }
    assert.deepEqual(item.errors, [], 'Accepted native name errors');
    model.changeBookmark(item.name, { selection: selection(0, 1, 0, 3) });
    await save(model, `bookmark-name-${index}`, item.file, item.after);
  }
  for (const item of report.management.operations) {
    const model = await open(`bookmark-${item.name}-original.4wp`);
    render(model);
    if (item.bounds) {
      const body = model.nativeView();
      const first = body.locate(item.bounds[0]);
      const last = body.locate(item.bounds[1], item.bounds[0] === item.bounds[1]);
      // Creation UI accepts text/caret selections; native-only structural slots
      // remain navigation evidence rather than a widened browser selection API.
      if (first.node.nodeType !== 3 || last.node.nodeType !== 3) continue;
      model.changeBookmark('managed', { selection: selection(model.runs.indexOf(first.node), first.offset, model.runs.indexOf(last.node), last.offset) });
    } else {
      model.changeBookmark('日本語😀é', { selection: selection(0, 1, 0, 3) });
      if (item.name === 'collapsed') model.changeBookmark('point', { selection: selection(0, 3) });
      if (item.name === 'rename') model.changeBookmark('renamed_日本語😀é', { previous: '日本語😀é' });
      if (item.name === 'delete') model.changeBookmark('', { previous: '日本語😀é', remove: true });
      if (item.name === 'case') {
        model.changeBookmark('ABC', { selection: selection(0, 0, 0, 1) });
        model.changeBookmark('abc', { selection: selection(0, 4, 0, 6) });
      }
      if (item.name === 'duplicate' || item.name === 'renameDuplicate') {
        if (item.name === 'renameDuplicate') model.changeBookmark('other', { selection: selection(0, 0, 0, 1) });
        const before = model.serialize();
        assert.throws(() => item.name === 'duplicate'
          ? model.changeBookmark('日本語😀é', { selection: selection(0, 4, 0, 6) })
          : model.changeBookmark('other', { previous: '日本語😀é' }), /bookmarkDuplicate/);
        assert.equal(model.serialize(), before, 'Duplicates must not overwrite');
        continue;
      }
    }
    await save(model, `bookmark-model-${item.name}`, `bookmark-${item.name}-native.4wp`, item.after);
    const packed = WriteProDocument.unpack(model.pack());
    packed.undo();
    packed.undo(true);
    assert.equal(packed.serialize(), model.serialize(), `${item.name}: recovered undo/redo`);
  }
  dom.window.close();
}

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
    cases.push({ name, file, ranges: { text: expected.text, bookmarks: expected.bookmarks, ...(expected.serialized && { serialized: expected.serialized }) } });
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
  assert.equal(report.structures.length, 64, 'Native table/list operation coverage');
  for (const item of report.structures) {
    const original = new Uint8Array(await readFile(resolve(directory, `Output/structure-${item.name}-original.4wp`)));
    const model = WriteProDocument.open(original);
    if (item.name.startsWith('boundary-')) {
      if (item.name === 'boundary-table') {
        assert(model.readOnly, 'Partial cross-cell bookmarks must remain protected');
        assert.deepEqual(model.export(), original, 'Protected cross-cell archive must stay byte-identical');
        await save(model, 'structure-protected-boundaries', item.before);
      }
      continue;
    }
    assert(!model.readOnly, `${item.name}: native structure supported`);
    render(model);
    const run = text => {
      const index = model.runs.findIndex(node => node.data === text);
      assert(index >= 0, `${item.name}: missing run ${text}`);
      return index;
    };
    switch (item.name) {
      case 'table': case 'nested': case 'indentedList': break;
      case 'indent': model.paragraphProperty(selection(run('CD'), 0), 'margin-left', '48pt'); break;
      case 'listSplit': model.splitParagraph(selection(run('CD'), 1)); break;
      case 'listJoin': model.mergeBoundary(run('CD'), true); break;
      case 'listToggle': model.toggleList(model.blocks.indexOf(model.runs[run('CD')].parentElement.closest('li')), 'ol'); break;
      case 'listPaste': model.paste(selection(run('CD'), 1), '<p><b>XY</b></p><p>Z</p>', ''); break;
      case 'listTyping': model.replaceText(selection(run('CD'), 1), '😀日'); break;
      case 'addRow': model.tableEdit(0, 'addRow'); break;
      case 'appendRow': model.tableEdit(2, 'addRow'); break;
      case 'removeRow': model.tableEdit(0, 'removeRow'); break;
      case 'removeLastRow': model.tableEdit(2, 'removeRow'); break;
      case 'removeColumn': model.tableEdit(0, 'removeColumn'); break;
      case 'removeLastColumn': model.tableEdit(1, 'removeColumn'); break;
      case 'addColumn': case 'appendColumn':
        assert.throws(() => model.tableEdit(0, 'addColumn'), /bookmarkColumn/);
        // Retain native counterexamples without claiming browser equivalence.
        continue;
      case 'typing': model.replaceText(selection(run('AB'), 1), 'XY'); break;
      case 'cellStart': model.replaceText(selection(run('AB'), 0), 'XY'); break;
      case 'cellEnd': model.replaceText(selection(run('AB'), 2), 'XY'); break;
      case 'cut': model.replaceText(selection(run('AB'), 0, run('AB'), 2), '', 'cut'); break;
      case 'splitCell': model.splitParagraph(selection(run('AB'), 1)); break;
      case 'joinCell': model.mergeBoundary(run('B'), true); break;
      case 'pasteCell': model.paste(selection(run('AB'), 1), '<p><b>XY</b></p><p>Z</p>', ''); break;
      case 'listCell': model.toggleList(model.blocks.indexOf(model.runs[run('AB')].parentElement), 'ul'); break;
      case 'pictureCell': model.insertImage(selection(run('AB'), 1), image, 48, 32, 'checker'); break;
      case 'unicodeCell': model.replaceText(selection(run('AB'), 1), '😀日é'); break;
      case 'emptyCellTyping': model.replaceText(selection(run('\u200b'), 0), '😀日'); break;
      case 'unicodeDelete': {
        const index = run('A😀日éB');
        model.replaceText(selection(index, 1, index, 4), '');
        break;
      }
      case 'pictureDelete': model.changeImage(0); break;
      case 'pictureMove': model.moveImage(0, selection(run('GH'), 1)); break;
      case 'insertTable': model.insertTable(0); break;
      default: assert.fail(`Unknown structural operation ${item.name}`);
    }
    const native = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/structure-${item.name}-native.4wp`))));
    assert.deepEqual(nativeMetadata(model.document).bookmarks, nativeMetadata(native.document).bookmarks, `${item.name}: serialized offsets differ from native edit`);
    await save(model, `structure-${item.name}`, { ...item.after, serialized: nativeMetadata(native.document).bookmarks });
  }
  dom.window.close();
}
