import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { nativeBody, nativeMetadata, spliceBookmarks } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import evidence from './fixtures/native-ranges.json';

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
      () => model.insertTable(0),
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

  it('protects generic ranges, tables, formulas, nested lists and hidden containers', () => {
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
