import { describe, expect, it } from 'vitest';
import { unzipSync } from 'fflate';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata, writeBookmarks } from '../src/native-ranges.js';
import { applyComplex } from '../scripts/native-complex-cases.mjs';
import evidence from './fixtures/native-complex.json';
import structures from './fixtures/native-structures.json';

const selection = (run, start, end = start) => ({ startRun: run, start, endRun: run, end });
const render = model => model.render(document.createElement('article'), {});
const open = item => {
  const model = new WriteProDocument(item.xml, { 'Resources/opaque.bin': Uint8Array.of(0, 255, 17, 128) });
  render(model);
  return model;
};
const single = (pair, name = 'grid-identity') => {
  const model = open(evidence.cases.find(item => item.name === name));
  writeBookmarks(model.document.querySelector('meta[name="bookmarks"]'), { cross: pair });
  model.refresh();
  render(model);
  return model;
};

describe('independent full-4D complex table oracles', () => {
  it('retains formula-only transaction tracking through column insertion without creating bookmark metadata', () => {
    const model = open(evidence.cases.find(item => item.name === 'grid-identity'));
    model.document.querySelector('meta[name="bookmarks"]').remove();
    const formula = model.document.createElementNS('http://www.w3.org/1999/xhtml', 'span');
    formula.setAttribute('style', "-d4-ref:'0'");
    formula.textContent = '0';
    model.document.querySelector('body > p').append(formula);
    model.refresh();
    render(model);
    const original = formula.outerHTML;
    expect(model.formulaTracking).toBe(true);
    expect(model.hasBookmarks).toBe(false);
    model.tableEdit(0, 'addColumn');
    expect(model.nativeView().text).toBe('BEFORE\ufffc\rAB\r\rCD\r\rEF\r\rGH\r\rAFTER');
    expect(model.formulaElements()[0].outerHTML).toBe(original);
    expect(model.document.querySelector('meta[name="bookmarks"]')).toBeNull();
    const recovered = WriteProDocument.unpack(model.pack());
    recovered.undo();
    recovered.undo(true);
    expect(recovered.formulaTracking).toBe(true);
    expect(recovered.formulaElements()[0].outerHTML).toBe(original);
  });

  it('keeps formula atoms immutable alongside the cross-cell insertion guard', () => {
    const model = single([9, 12]);
    const formula = model.document.createElementNS('http://www.w3.org/1999/xhtml', 'span');
    formula.setAttribute('style', "-d4-ref:'0'");
    formula.textContent = '0';
    model.document.querySelector('body > p:last-child').append(formula);
    model.refresh();
    render(model);
    const before = model.serialize();
    expect(model.formulaTracking).toBe(true);
    expect(() => model.replaceText(selection(1, 2), 'X')).toThrow('bookmarkCrossInsert');
    expect(model.serialize()).toBe(before);
    render(model);
    expect(() => model.mutate('edit', () => { model.formulaElements()[0].textContent = 'changed'; })).toThrow('protected');
    expect(model.serialize()).toBe(before);
    render(model);
    model.replaceText(selection(1, 1), 'XY');
    expect(nativeMetadata(model.document).bookmarks.cross).toEqual([11, 14]);
    expect(model.formulaElements()[0].outerHTML).toBe(formula.outerHTML);
  });

  it.each(evidence.cases)('matches native $name raw pairs and recovered undo/redo', item => {
    const model = open(item);
    expect(model.readOnly).toBe(false);
    applyComplex(model, item);
    expect(nativeMetadata(model.document).bookmarks).toEqual(item.serialized);
    expect(unzipSync(model.export())['Resources/opaque.bin']).toEqual(Uint8Array.of(0, 255, 17, 128));
    const recovered = WriteProDocument.unpack(model.pack());
    if (!['identity', 'format'].includes(item.operation)) {
      recovered.undo();
      expect(nativeMetadata(recovered.document).bookmarks).toEqual(item.before);
      recovered.undo(true);
      expect(nativeMetadata(recovered.document).bookmarks).toEqual(item.serialized);
    }
  });

  it('protects interior cross-cell insertions, deletion, replacement and structural edits atomically', () => {
    const model = single([9, 12]);
    const before = model.serialize();
    const run = model.runs.findIndex(node => node.data === 'AB');
    expect(() => model.replaceText(selection(run, 2), 'X')).toThrow('bookmarkCrossInsert');
    render(model);
    expect(() => model.replaceText(selection(run, 0, 1), '')).toThrow('bookmarkCrossDelete');
    render(model);
    expect(() => model.replaceText(selection(run, 0, 1), 'X')).toThrow('bookmarkCrossDelete');
    render(model);
    for (const action of ['addRow', 'removeRow', 'addColumn', 'removeColumn']) {
      expect(model.tableCapability(0, action)).toBe('bookmarkCrossStructure');
      expect(() => model.tableEdit(0, action)).toThrow('bookmarkCrossStructure');
    }
    expect(() => model.insertTable(0)).toThrow('bookmarkCrossStructure');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toEqual([]);
    render(model);
    model.replaceText(selection(model.runs.findIndex(node => node.data === 'AB'), 1), 'XY');
    expect(nativeMetadata(model.document).bookmarks.cross).toEqual([11, 14]);
  });

  it('keeps merged geometry and cell paragraphs intact while protecting all row/column edits', () => {
    for (const shape of ['colspan', 'rowspan', 'rectangle']) {
      const item = evidence.cases.find(item => item.name === `${shape}-typing`);
      const model = open(item);
      const geometry = () => [...model.document.querySelectorAll('td')].map(cell =>
        [cell.getAttribute('rowspan'), cell.getAttribute('colspan')]);
      const before = geometry();
      applyComplex(model, item);
      expect(geometry()).toEqual(before);
      render(model);
      for (const action of ['addRow', 'removeRow', 'addColumn', 'removeColumn']) {
        expect(() => model.tableEdit(0, action)).toThrow('mergedTable');
      }
      const cell = model.document.querySelector('td');
      cell.setAttribute('rowspan', '99');
      model.refresh();
      expect(model.readOnly).toBe(true);
      expect(model.readOnlyReason).toBe('bookmarkTableShape');
    }
  });

  it('protects native column separator counterexamples rather than dropping or moving their bookmarks', () => {
    const model = new WriteProDocument(structures.structures.find(item => item.name === 'table').xml);
    render(model);
    const before = model.serialize();
    expect(model.tableCapability(0, 'addColumn')).toBe('bookmarkColumnBoundary');
    expect(() => model.tableEdit(0, 'addColumn')).toThrow('bookmarkColumnBoundary');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toEqual([]);
  });

  it('rolls back insertion that would move an enclosing endpoint into an unsupported table-crossing range', () => {
    const model = single([8, 24]);
    const before = model.serialize();
    expect(() => model.replaceText(selection(1, 0), 'XY')).toThrow('bookmarkTableCross');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toEqual([]);
  });

  it('explains partial-table, nested-list and malformed metadata protection separately', () => {
    const model = single([7, 9]);
    expect(model.readOnly).toBe(true);
    expect(model.readOnlyReason).toBe('bookmarkTableCross');
    const nested = new WriteProDocument('<html xmlns="http://www.w3.org/1999/xhtml"><head><meta name="bookmarks" content="{&quot;a&quot;:[0,1]}"/></head><body><ul><li>A<ul><li>B</li></ul></li></ul></body></html>');
    expect(nested.readOnlyReason).toBe('bookmarkNestedList');
    const malformed = new WriteProDocument('<html xmlns="http://www.w3.org/1999/xhtml"><head><meta name="ranges" content="native-unknown"/></head><body><p>ABC</p></body></html>');
    expect(malformed.readOnlyReason).toBe('bookmarkMetadata');
  });
});
