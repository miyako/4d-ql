import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { nativeBody, nativeMetadata, spliceBookmarks } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import evidence from './fixtures/native-ranges.json';
import structuralEvidence from './fixtures/native-structures.json';

const initial = { span: [3, 6], point: [4, 4], all: [1, 10] };
const selection = (startRun, start, endRun = startRun, end = start) => ({ startRun, start, endRun, end });
const render = model => model.render(document.createElement('article'), messages.en);
const make = (body = '<p>abcdefghi</p>', bookmarks = initial, head = '') => {
  const content = JSON.stringify(Object.fromEntries(Object.entries(bookmarks).map(([name, pair]) => [name, pair.map(value => value - 1)]))).replace(/"/g, '&quot;');
  const model = new WriteProDocument(`<html xmlns="http://www.w3.org/1999/xhtml"><head><meta name="bookmarks" content="${content}"/>${head}</head><body>${body}</body></html>`);
  render(model);
  return model;
};
const ranges = model => nativeMetadata(model.document).bookmarks;
const structural = name => {
  const item = structuralEvidence.structures.find(item => item.name === name);
  const model = new WriteProDocument(item.xml);
  render(model);
  return { model, item, run: text => model.runs.findIndex(node => node.data === text) };
};

describe('full 4D F0012102 evidence', () => {
  it.each(evidence.offsets)('counts native $name offsets and converts serialized origin zero', item => {
    const model = new WriteProDocument(item.xml);
    expect(model.readOnly).toBe(false);
    const body = nativeBody(model.document, element => model.values(element));
    expect(body.text.length + 1).toBe(item.end);
    expect(body.text.replace(/\n/g, '\r').replace(/\ufffc/g, '\u00a0')).toBe(item.text);
    expect(ranges(model)).toEqual(item.bookmarks);
  });

  it.each(evidence.splices)('matches native delete/insert $edit', item => {
    expect(spliceBookmarks(evidence.initial, item.edit.start, item.edit.end, item.edit.text.length)).toEqual(item.bookmarks);
    const model = make(undefined, evidence.initial);
    model.replaceText(selection(0, item.edit.start - 1, 0, item.edit.end - 1), item.edit.text);
    expect(ranges(model)).toEqual(item.bookmarks);
    expect(nativeBody(model.document, element => model.values(element)).text).toBe(item.text);
    const reopened = WriteProDocument.open(model.export());
    expect(reopened.readOnly).toBe(false);
    expect(ranges(reopened)).toEqual(item.bookmarks);
  });
});

describe('range-safe transactions', () => {
  it('creates the first Unicode and collapsed bookmarks, rejects destructive names, and recovers undo/redo', () => {
    let model = make('<p>A😀日éB</p>', {});
    model.changeBookmark('日本語😀é', { selection: selection(0, 1, 0, 3) });
    expect(ranges(model)).toEqual({ '日本語😀é': [2, 4] });
    render(model);
    model.changeBookmark('__proto__', { selection: selection(0, 3) });
    expect(ranges(model)).toEqual({ '日本語😀é': [2, 4], ['__proto__']: [4, 4] });
    for (const name of ['', 'two words', 'a.b', 'a"\\&<>', 'a\u0000b', '\ud800', '\uffff']) {
      const before = model.serialize();
      expect(() => model.changeBookmark(name, { selection: selection(0, 0) })).toThrow('bookmarkNameInvalid');
      expect(model.serialize()).toBe(before);
      render(model);
    }
    expect(() => model.changeBookmark('__proto__', { selection: selection(0, 0) })).toThrow('bookmarkDuplicate');
    render(model);
    model.changeBookmark('Renamed_日本語', { previous: '日本語😀é' });
    expect(ranges(model)).toEqual({ ['__proto__']: [4, 4], 'Renamed_日本語': [2, 4] });
    model = WriteProDocument.unpack(model.pack());
    model.undo();
    expect(ranges(model)).toEqual({ '日本語😀é': [2, 4], ['__proto__']: [4, 4] });
    model.undo(true);
    model.changeBookmark('', { previous: 'Renamed_日本語', remove: true });
    expect(ranges(model)).toEqual({ ['__proto__']: [4, 4] });
    model.undo();
    expect(ranges(model)).toEqual({ ['__proto__']: [4, 4], 'Renamed_日本語': [2, 4] });
  });

  it('rejects duplicate renames and surrogate-splitting ranges without changing content or history', () => {
    const model = make('<p>A😀B</p>', { abc: [1, 2], ABC: [4, 5] });
    const before = model.serialize();
    expect(() => model.changeBookmark('ABC', { previous: 'abc' })).toThrow('bookmarkDuplicate');
    expect(model.serialize()).toBe(before);
    render(model);
    expect(() => model.changeBookmark('bad', { selection: selection(0, 2) })).toThrow('protected');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toHaveLength(0);
  });

  it('keeps native table raw endpoints when renaming and maps every structural boundary without textContent guesses', () => {
    const { model } = structural('table');
    const before = ranges(model);
    const body = model.nativeView();
    for (let offset = 1; offset <= body.text.length + 1; offset++) {
      const point = body.locate(offset);
      expect(body.point(point.node, point.offset)).toBe(offset);
    }
    for (const { name, start, end } of model.bookmarks()) {
      const mapped = model.bookmarkRange(name);
      if (mapped.selection) {
        const range = model.range(mapped.selection);
        expect([body.point(range.startContainer, range.startOffset), body.point(range.endContainer, range.endOffset)]).toEqual([start, end]);
      }
    }
    model.changeBookmark('renamed', { previous: 'unit10' });
    expect(ranges(model).renamed).toEqual(before.unit10);
    expect(model.nativeView().text).toBe(body.text);
    render(model);
    const ab = model.runs.findIndex(node => node.data === 'AB');
    const cd = model.runs.findIndex(node => node.data === 'CD');
    expect(() => model.changeBookmark('crossCell', { selection: selection(ab, 1, cd, 1) })).toThrow('bookmarkRange');
  });

  it('maps bookmarks across Unicode, soft breaks, pictures and paragraph boundaries to their native offsets', () => {
    for (const item of evidence.offsets) {
      const model = new WriteProDocument(item.xml);
      render(model);
      const body = model.nativeView();
      for (let offset = 1; offset <= body.text.length + 1; offset++) {
        if (!/[\uD800-\uDBFF]/.test(body.text[offset - 2] || '') || !/[\uDC00-\uDFFF]/.test(body.text[offset - 1] || '')) {
          const point = body.locate(offset);
          expect(body.point(point.node, point.offset), `${item.name}: ${offset}`).toBe(offset);
        }
      }
      for (const { name } of model.bookmarks()) expect(model.bookmarkRange(name).range).toBeDefined();
    }
  });

  it('keeps protected documents and protected text immutable for bookmark operations', () => {
    const locked = make('<p><span style="-d4-protected:true">abcdefghi</span></p>', {});
    expect(() => locked.changeBookmark('name', { selection: selection(0, 0, 0, 3) })).toThrow('protected');
    const { model } = structural('boundary-table');
    const before = model.serialize();
    expect(() => model.changeBookmark('name', { previous: 'whole' })).toThrow('protected');
    expect(() => model.changeBookmark('', { previous: 'whole', remove: true })).toThrow('protected');
    expect(model.serialize()).toBe(before);
  });

  it('protects duplicate metadata keys rather than silently dropping a bookmark during management', () => {
    for (const content of ['{"a":[0,1],"a":[2,3]}', '{"a":[0,1],"\\u0061":[2,3]}', '{"a":{"hidden":[0,1]},"a":[2,3]}']) {
      const model = make();
      model.document.querySelector('meta[name="bookmarks"]').setAttribute('content', content);
      model.refresh();
      expect(model.readOnly).toBe(true);
      const before = model.serialize();
      expect(() => model.changeBookmark('new', { previous: 'a' })).toThrow('protected');
      expect(model.serialize()).toBe(before);
    }
    const model = make('<p>abc</p>', { 'a":b': [1, 2] });
    expect(model.readOnly).toBe(false);
    expect(model.bookmarks()[0].name).toBe('a":b');
  });

  it.each([
    ['addRow', 0, 'addRow'], ['appendRow', 2, 'addRow'],
    ['removeRow', 0, 'removeRow'], ['removeLastRow', 2, 'removeRow'],
    ['removeColumn', 0, 'removeColumn'], ['removeLastColumn', 1, 'removeColumn'],
  ])('matches native %s including collapsed cell/row boundaries and whole-table ranges', (name, cell, action) => {
    const { model, item } = structural(name);
    expect(model.readOnly).toBe(false);
    model.tableEdit(cell, action);
    expect(ranges(model)).toEqual(item.serialized);
    const recovered = WriteProDocument.unpack(model.pack());
    recovered.undo();
    expect(recovered.serialize()).toBe(model.initial);
    recovered.undo(true);
    expect(ranges(recovered)).toEqual(item.serialized);
  });

  it.each([
    ['cellStart', 0, 'XY'], ['typing', 1, 'XY'], ['cellEnd', 2, 'XY'],
    ['cut', 0, ''], ['unicodeCell', 1, '😀日é'],
  ])('matches native %s inside a cell without changing its neighbors', (name, offset, text) => {
    const { model, item, run } = structural(name);
    model.replaceText(selection(run('AB'), offset, run('AB'), name === 'cut' ? 2 : offset), text);
    expect(ranges(model)).toEqual(item.serialized);
    expect([...model.document.querySelectorAll('td')].slice(1).map(cell => cell.textContent)).toEqual(['CD', 'EF', 'GH']);
  });

  it('registers table insertion, split/join and rich paste in a cell', () => {
    for (const name of ['insertTable', 'splitCell', 'joinCell', 'pasteCell']) {
      const { model, item, run } = structural(name);
      if (name === 'insertTable') model.insertTable(0);
      if (name === 'splitCell') model.splitParagraph(selection(run('AB'), 1));
      if (name === 'joinCell') model.mergeBoundary(run('B'), true);
      if (name === 'pasteCell') model.paste(selection(run('AB'), 1), '<p><b>XY</b></p><p>Z</p>', '');
      expect(ranges(model)).toEqual(item.serialized);
      expect(WriteProDocument.open(model.export()).readOnly).toBe(false);
    }
  });

  it('types non-BMP text into a native empty cell without consuming its terminator', () => {
    const { model, item, run } = structural('emptyCellTyping');
    model.replaceText(selection(run('\u200b'), 0), '😀日');
    expect(ranges(model)).toEqual(item.serialized);
    expect(model.nativeView().text.length + 1).toBe(item.after.end);
    expect(model.document.querySelectorAll('td').length).toBe(4);
  });

  it('preserves native list-level indentation through typing and paragraph changes', () => {
    for (const name of ['indent', 'listSplit', 'listJoin', 'listTyping', 'listPaste']) {
      const { model, item, run } = structural(name);
      if (name === 'indent') model.paragraphProperty(selection(run('CD'), 0), 'margin-left', '48pt');
      if (name === 'listSplit') model.splitParagraph(selection(run('CD'), 1));
      if (name === 'listJoin') model.mergeBoundary(run('CD'), true);
      if (name === 'listTyping') model.replaceText(selection(run('CD'), 1), '😀日');
      if (name === 'listPaste') model.paste(selection(run('CD'), 1), '<p><b>XY</b></p><p>Z</p>', '');
      expect(ranges(model)).toEqual(item.serialized);
      if (name !== 'listJoin') {
        expect(model.values(model.document.querySelector('ul').lastElementChild).margin).toContain('24pt');
      }
    }
  });

  it('protects partial cross-cell bookmarks and column insertion without losing history', () => {
    const protectedModel = structural('boundary-table').model;
    expect(protectedModel.readOnly).toBe(true);
    expect(() => protectedModel.replaceText(selection(1, 0), 'x')).toThrow('protected');
    const { model } = structural('table');
    const before = model.serialize();
    expect(() => model.tableEdit(0, 'addColumn')).toThrow('bookmarkColumn');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toEqual([]);
    expect(() => model.replaceText(selection(1, 1, 2, 1), 'x')).toThrow('structuralSelection');
    expect(model.serialize()).toBe(before);
  });

  it('checks multi-cell deletion registrations atomically and rolls back an incorrect span', () => {
    const { model } = structural('table');
    const before = model.serialize();
    expect(() => model.mutate('table', () => model.nativeChange(
      [{ start: 8, end: 9 }], () => model.document.querySelector('td').remove(),
    ))).toThrow('protected');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toEqual([]);
  });

  it('uses the actual insertion point in repeated text, including non-BMP text', () => {
    const model = make('<p>aaaa😀日本</p>', { word: [2, 4], end: [9, 9] });
    model.replaceText(selection(0, 0), 'a');
    expect(ranges(model)).toEqual({ word: [3, 5], end: [10, 10] });
    render(model);
    const index = model.runs.findIndex(node => node.data.includes('😀'));
    model.replaceText(selection(index, 4, index, 6), '日');
    expect(ranges(model)).toEqual({ word: [3, 5], end: [9, 9] });
  });

  it('updates paragraph split/join, soft breaks, flat lists, paste and cut', () => {
    const model = make();
    model.splitParagraph(selection(0, 3));
    expect(ranges(model)).toEqual({ span: [3, 7], point: [4, 4], all: [1, 11] });
    render(model);
    model.mergeBoundary(1, true);
    expect(ranges(model)).toEqual(initial);
    render(model);
    model.splitParagraph(selection(0, 3), true);
    expect(ranges(model)).toEqual({ span: [3, 7], point: [4, 4], all: [1, 11] });
    render(model);
    model.deleteInlineBoundary(0, false);
    expect(ranges(model)).toEqual(initial);
    render(model);
    model.toggleList(0, 'ul');
    expect(ranges(model)).toEqual(initial);
    model.toggleList(0, 'ul');
    render(model);
    model.paste(selection(0, 3), '<p><b>XY</b></p><p>Z</p>', '');
    expect(ranges(model)).toEqual({ span: [3, 10], point: [4, 4], all: [1, 14] });
    render(model);
    const last = model.runs.findIndex(node => node.data === 'defghi');
    model.replaceText(selection(0, 2, last, 2), '', 'cut');
    expect(ranges(model)).toEqual({ all: [1, 7] });
  });

  it('handles inline images, movement and adjacent empty cursor slots', () => {
    const model = make();
    model.insertImage(selection(0, 3), 'data:image/png;base64,AA==', 48, 32, 'Test');
    expect(ranges(model)).toEqual({ span: [3, 7], point: [4, 4], all: [1, 11] });
    render(model);
    const index = model.runs.findIndex(node => node.data === 'defghi');
    model.moveImage(0, selection(index, 3));
    expect(ranges(model)).toEqual({ ...initial, all: [1, 11] });
    render(model);
    model.changeImage(0);
    expect(ranges(model)).toEqual(initial);
  });

  it('keeps formatting offsets and stores text plus ranges atomically in history/recovery', () => {
    const model = make();
    model.formatSelection(selection(0, 1, 0, 7), 'font-weight', 'bold');
    expect(ranges(model)).toEqual(initial);
    render(model);
    model.replaceText(selection(1, 2), '日本😀');
    const edited = model.serialize();
    const recovered = WriteProDocument.unpack(model.pack());
    expect(recovered.serialize()).toBe(edited);
    recovered.undo();
    expect(ranges(recovered)).toEqual(initial);
    recovered.undo(true);
    expect(recovered.serialize()).toBe(edited);
    recovered.restoreVersion(model.initial);
    expect(ranges(recovered)).toEqual(initial);
    recovered.undo();
    expect(recovered.serialize()).toBe(edited);
  });

  it('tracks replace-all as separate splices, not one bounding diff', () => {
    const model = make('<p>aXaXa</p>', { middle: [4, 5], last: [5, 6] });
    model.replaceMatches('a', 'YY', true);
    expect(ranges(model)).toEqual({ middle: [6, 7] });
    expect(model.document.querySelector('p').textContent).toBe('YYXYYXYY');
  });

  it('refuses edits and imported endpoints splitting surrogate pairs', () => {
    const model = make('<p>A😀日本</p>', { word: [2, 4] });
    const before = model.serialize();
    expect(() => model.replaceText(selection(0, 2), 'x')).toThrow('protected');
    expect(model.serialize()).toBe(before);
    expect(make('<p>A😀日本</p>', { half: [2, 3] }).readOnly).toBe(true);
  });

  it('counts empty paragraphs and added paragraphs without counting placeholder text', () => {
    const model = make('<p>\u200b</p><p>abc</p>', { word: [2, 5], point: [1, 1] });
    model.replaceText(selection(0, 0), '日');
    expect(ranges(model)).toEqual({ word: [3, 6], point: [1, 1] });
    render(model);
    model.addParagraph(0);
    expect(ranges(model)).toEqual({ word: [4, 7], point: [1, 1] });
  });

  it('rolls back unsupported structures and unregistered text or metadata changes', () => {
    const model = make();
    const before = model.serialize();
    for (const change of [
      () => model.paste(selection(0, 2), '<ul><li>A<ul><li>B</li></ul></li></ul>', ''),
      () => model.mutate('edit', () => { model.runs[0].data = 'unregistered'; }),
      () => model.mutate('edit', () => {
        model.runs[0].data = 'unregistered';
        model.nativeChange({ start: 1, end: 1 }, () => {});
      }),
      () => model.mutate('edit', () => model.document.querySelector('meta').setAttribute('content', '{}')),
    ]) {
      expect(change).toThrow('protected');
      expect(model.serialize()).toBe(before);
      expect(model.undoStack).toEqual([]);
      render(model);
    }
  });

  it.each([
    'not-json', '{"x":[-1,2]}', '{"x":[3,2]}', '{"x":[0,999]}', '{"x":[0,1.5]}', '{"x":"id"}',
  ])('keeps unsupported bookmark metadata read-only: %s', content => {
    const model = make();
    model.document.querySelector('meta').setAttribute('content', content);
    const reopened = new WriteProDocument(model.serialize());
    expect(reopened.readOnly).toBe(true);
    expect(() => reopened.mutate('edit', () => {})).toThrow('protected');
  });

  it('protects generic ranges, noncanonical tables, formulas, nested HTML lists and hidden containers', () => {
    for (const body of [
      '<table><tr><td><p>abcdefghi</p></td></tr></table>',
      '<p>a<span style="-d4-ref:formula">bc</span>defghi</p>',
      '<ul><li>abc<ul><li>defghi</li></ul></li></ul>',
      '<p style="display:none">abcdefghi</p>',
      '<p>abcdefghi</p><ul/>',
      '<p>abcdefghi</p> \n',
    ]) expect(make(body).readOnly).toBe(true);
    expect(make(undefined, initial, '<meta name="ranges" content="{&quot;x&quot;:[0,1]}"/>').readOnly).toBe(true);
    expect(make(undefined, initial, '<meta name="bookmarks" content="{}"/>').readOnly).toBe(true);
  });
});
