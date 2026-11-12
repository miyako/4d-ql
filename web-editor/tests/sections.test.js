import { describe, it, expect } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { nativeMetadata } from '../src/native-ranges.js';

const xml = (body, style = '', metadata = '') => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Sections</title>${metadata}<style>${style}</style></head><body>${body}</body></html>`;
const render = model => model.render(document.createElement('article'), messages.en);
const caret = (run, offset) => ({ startRun: run, endRun: run, start: offset, end: offset });
const bookmarks = '<meta name="bookmarks" content="{&quot;span&quot;:[0,2],&quot;point&quot;:[1,1]}"/>';

describe('native flat sections and breaks', () => {
  it.each(['page', 'section', 'continuous'])('inserts %s atomically at Unicode/formula boundaries and recovers exact history', kind => {
    const doc = new WriteProDocument(xml('<p>AB<span style="-d4-ref:\'1+1\'">SAVED</span>😀日</p>', '', bookmarks));
    render(doc);
    const before = doc.serialize();
    const formula = doc.formulaElements()[0];
    doc.insertBreak(caret(0, 1), kind);
    expect(doc.nativeView().text).toBe('A\rB\ufffc😀日');
    expect(nativeMetadata(doc.document).bookmarks).toEqual({ span: [1, 4], point: [2, 2] });
    expect(doc.formulaElements()[0]).toBe(formula);
    expect(formula.outerHTML).toContain('SAVED');
    expect(doc.undoLabels).toEqual(['breakEdit']);
    const edited = doc.serialize();
    doc.undo();
    expect(doc.serialize()).toBe(before);
    const recovered = WriteProDocument.unpack(doc.pack());
    recovered.undo(true);
    expect(recovered.serialize()).toBe(edited);
    render(recovered);
    recovered.removeBreak(0);
    expect(recovered.nativeView().text).toBe('A\rB\ufffc😀日');
    expect(recovered.sectionLayout().sections).toHaveLength(1);
    expect(recovered.undoLabels).toEqual(['breakEdit', 'breakEdit']);
    render(recovered);
    recovered.splitParagraph(caret(0, 0));
    expect(recovered.nativeView().text).toBe('\rA\rB\ufffc😀日');
  });

  it('finds flat section identities and edits only explicit orientation/margin groups and names', () => {
    const doc = new WriteProDocument(xml('<p class="end">AB</p><p>CD</p><div class="section2Header" style="visibility:hidden">Header</div>',
      'p.end{page-break-after:always;-d4-section-break-after:always}div.section0{-d4-page-margin:30pt}div.section2{-d4-opaque:keep;-d4-section-name:"Original"}div.section2First{-d4-opaque:subsection}'));
    const body = doc.document.querySelector('body').outerHTML;
    expect(doc.sectionIndex(doc.document.querySelectorAll('p')[1])).toBe(2);
    expect(doc.sectionSetup(2).overrides).toEqual({});
    doc.setSectionSetup(2, { orientation: 'landscape', margins: { top: '12pt', right: '13pt', bottom: '14pt', left: '15pt' }, name: '日本語 A & B😀' });
    expect(doc.sectionSetup(2)).toMatchObject({ name: '日本語 A & B😀', geometry: { width: '595pt', orientation: 'landscape', top: '12pt', left: '15pt' } });
    expect(doc.document.querySelector('body').outerHTML).toBe(body);
    expect(doc.serialize()).toContain('-d4-opaque:keep');
    expect(doc.serialize()).toContain('div.section2First{-d4-opaque:subsection}');
    doc.setSectionSetup(2, { orientation: null, margins: null });
    expect(doc.sectionSetup(2)).toMatchObject({ overrides: {}, geometry: { orientation: 'portrait', left: '30pt' } });
    doc.setPageSetup({ left: '40pt' });
    expect(doc.sectionSetup(2).geometry.left).toBe('40pt');
    expect(doc.document.querySelector('body').outerHTML).toBe(body);
  });

  it('inherits by absence, clears all duplicate declarations on reset and preserves equal explicit values on no-op', () => {
    const doc = new WriteProDocument(xml('<p>AB</p>', 'div.section1{-d4-page-margin:2.5cm;-d4-page-orientation:portrait;-d4-opaque:keep}div.section1{-d4-page-margin:30pt}'));
    doc.setSectionSetup(1, {});
    expect(doc.undoStack).toHaveLength(0);
    doc.setSectionSetup(1, { margins: null, orientation: null });
    expect(doc.sectionSetup(1).overrides).toEqual({});
    expect(doc.serialize()).not.toContain('-d4-page-margin:');
    expect(doc.serialize()).toContain('-d4-opaque:keep');
  });

  it('splits only the last section, copies its verified geometry but not its name, and protects lossy merges', () => {
    const doc = new WriteProDocument(xml('<p class="end">AB</p><p>CD</p>', 'p.end{page-break-after:always;-d4-section-break-after:always}div.section2{-d4-section-name:"Keep";-d4-page-margin:30pt;-d4-page-orientation:landscape}'));
    render(doc);
    doc.insertBreak(caret(1, 1), 'continuous');
    expect(doc.sectionSetup(2).name).toBe('Keep');
    expect(doc.sectionSetup(3)).toMatchObject({ name: '', geometry: { left: '30pt', orientation: 'landscape' } });
    render(doc);
    const before = doc.serialize();
    expect(() => doc.removeBreak(1)).toThrow('sectionProtected');
    expect(doc.serialize()).toBe(before);
  });

  it.each([
    ['<p>AB</p><div class="section1Header" style="visibility:hidden">Header</div>', ''],
    ['<p>AB</p>', 'div.section1First{-d4-opaque:keep}'],
    ['<p>AB</p>', 'div.section1{column-count:2}'],
    ['<p>AB</p>', '@media print{div.section1{-d4-opaque:keep}}'],
  ])('protects section associations and unsupported native declarations', (body, style) => {
    const doc = new WriteProDocument(xml(body, style));
    render(doc);
    const before = doc.serialize();
    expect(() => doc.insertBreak(caret(0, 1), 'section')).toThrow('sectionProtected');
    expect(doc.serialize()).toBe(before);
  });

  it('rejects selected text, cell boundaries, malformed ranges and surrogate splits without mutation', () => {
    const doc = new WriteProDocument(xml('<p>A😀B</p>'));
    render(doc);
    expect(() => doc.insertBreak({ ...caret(0, 0), end: 1 }, 'page')).toThrow('breakCaret');
    expect(() => doc.insertBreak(caret(0, 2), 'page')).toThrow('protected');
    expect(doc.undoStack).toHaveLength(0);
    const malformed = new WriteProDocument(xml('<p>AB</p>', '', '<meta name="ranges" content="{&quot;generic&quot;:1}"/>'));
    render(malformed);
    expect(() => malformed.insertBreak(caret(0, 1), 'page')).toThrow('protected');
    const table = new WriteProDocument(xml('<p>AB</p><table><tr><td><p>CD</p></td></tr></table><p>EF</p>'));
    render(table);
    expect(() => table.insertBreak(caret(1, 1), 'page')).toThrow('breakCaret');
    expect(table.undoStack).toHaveLength(0);
  });

  it('rejects invalid section settings and keeps unsupported scope declarations intact', () => {
    const doc = new WriteProDocument(xml('<p>AB</p>'));
    expect(() => doc.setSectionSetup(1, { margins: { top: '900pt', right: '0pt', bottom: '0pt', left: '0pt' } })).toThrow('pageMarginsInvalid');
    expect(() => doc.setSectionSetup(1, { name: '\u0000' })).toThrow('sectionNameInvalid');
    for (const name of [' leading ', 'A"B', "O'Reilly", 'slash\\name']) expect(() => doc.setSectionSetup(1, { name })).toThrow('sectionNameInvalid');
    expect(() => doc.setSectionSetup(1, { width: '600pt' })).toThrow('pageInvalid');
    expect(doc.undoStack).toHaveLength(0);
    const scoped = new WriteProDocument(xml('<p>AB</p>', '@media print{div.section1{-d4-section-name:"Hidden"}}'));
    expect(() => scoped.setSectionSetup(1, { name: 'Lost' })).toThrow('sectionUnsupported');
  });

  it('does not let ordinary paragraph style changes add or remove section boundaries', () => {
    const doc = new WriteProDocument(xml('<p class="Boundary">AB</p><p>CD</p>',
      'p.Boundary{page-break-after:always;-d4-section-break-after:always}'));
    render(doc);
    const before = doc.serialize();
    expect(() => doc.styleBlocks(caret(0, 0), 'Normal')).toThrow('protected');
    expect(doc.serialize()).toBe(before);
    render(doc);
    expect(() => doc.styleBlocks(caret(1, 0), 'Boundary')).toThrow('protected');
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toHaveLength(0);
  });
});
