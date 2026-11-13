import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { createPrintProjection } from '../src/printing.js';
import { outsideArea } from '../src/headers-footers.js';

const source = (content = 'HEADER', extra = '', css = '') =>
  `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Areas</title><meta name="bookmarks" content="{&quot;body&quot;:[0,2]}"/><style>div.section0{-d4-page-margin:36pt}div.section1Header{margin:1cm 36pt 0.5cm}${css}</style></head><body><p style="-d4-section-break-after:continuous">BODY ONE</p><p>BODY TWO</p><div class="section1Header" style="visibility:hidden;height:0"><p class="Normal">${content}</p></div>${extra}</body></html>`;
const render = model => model.render(document.createElement('article'), messages.en);
const range = (start = 0, end = start) => ({ startRun: 0, endRun: 0, start, end });

describe('isolated native header/footer scopes', () => {
  it('edits and formats only the selected area with body bookmarks protected, then restores history and recovery scope', () => {
    const model = new WriteProDocument(source('HEADER😀'), { 'sentinel.bin': Uint8Array.of(0, 255) });
    expect(model.readOnly).toBe(true);
    model.setScope('section1Header');
    expect(model.editingReadOnly).toBe(false);
    render(model);
    const outside = outsideArea(model.document, model.scope);
    model.rememberSelection(range(1, 3));
    model.replaceText(range(1, 3), '日é');
    render(model);
    model.formatSelection({ startRun: 0, start: 0, endRun: 1, end: 1 }, 'font-weight', 'bold');
    expect(model.scopeRoot.textContent).toBe('H日éDER😀');
    expect(outsideArea(model.document, model.scope)).toBe(outside);
    model.undo();
    model.undo();
    expect(model.scopeRoot.textContent).toBe('HEADER😀');
    model.undo(true);
    const recovered = WriteProDocument.unpack(model.pack());
    expect(recovered.scope).toBe('section1Header');
    render(recovered);
    recovered.undo(true);
    expect(recovered.scopeRoot.querySelector('[style*="bold"]')).not.toBeNull();
    expect(recovered.files['sentinel.bin']).toEqual(Uint8Array.of(0, 255));
    expect(outsideArea(recovered.document, recovered.scope)).toBe(outside);
  });

  it('preserves immutable formula XML and sibling variants through paragraph edits, and rejects destructive selection', () => {
    const model = new WriteProDocument(source('AB<span style="-d4-ref:\'1+1\'">CACHED</span>CD',
      '<div class="section1FirstHeader" style="visibility:hidden;height:0"><p>FIRST</p></div>', 'div.section1First{white-space:normal}'));
    model.setScope('section1Header');
    render(model);
    const formula = model.scopeRoot.querySelector('span').outerHTML;
    const outside = outsideArea(model.document, model.scope);
    model.splitParagraph(range(1));
    render(model);
    expect(model.scopeRoot.children).toHaveLength(2);
    expect(model.scopeRoot.querySelector('span').outerHTML).toBe(formula);
    expect(outsideArea(model.document, model.scope)).toBe(outside);
    expect(() => model.changeHeaderArea(1, 'Header', true)).toThrow();
    const before = model.serialize();
    expect(() => model.replaceText({ startRun: 0, start: 0, endRun: model.runs.length - 1, end: 1 }, 'LOST')).toThrow();
    expect(model.serialize()).toBe(before);
  });

  it('creates/removes default areas atomically and never creates/removes variants by guessing', () => {
    const model = new WriteProDocument(source());
    const original = model.serialize();
    model.changeHeaderArea(2, 'Footer');
    expect(model.scope).toBe('section2Footer');
    render(model);
    model.editRun(0, 'SECOND');
    model.changeHeaderArea(2, 'Footer', true);
    expect(model.scope).toBe('body');
    expect(model.document.querySelector('.section2Footer')).toBeNull();
    model.changeHeaderArea(2, 'Footer');
    expect(model.scopeRoot.textContent).toBe('');
    expect(() => model.changeHeaderArea(2, 'FirstHeader')).toThrow();
    model.undo();
    model.undo();
    model.undo();
    model.undo();
    expect(model.serialize()).toBe(original);
  });

  it.each([
    ['table', '<table><tr><td><p>CELL</p></td></tr></table>'],
    ['anchored', '<span style="-d4-anchor-page:all">ANCHORED</span>'],
    ['protected', '<span style="-d4-protected:true">LOCKED</span>'],
    ['unknown formula', '<span style="-d4-ref-type:unknown">UNKNOWN</span>'],
    ['nested list', '<ul><li>LIST</li></ul>'],
  ])('protects unsupported %s without flattening', (_, content) => {
    const model = new WriteProDocument(source(content));
    model.setScope('section1Header');
    const before = model.serialize();
    render(model);
    expect(model.headerReason()).toBe('headerUnsupported');
    expect(() => model.editRun(0, 'LOST')).toThrow();
    expect(model.serialize()).toBe(before);
  });

  it('protects duplicate, orphaned and unenabled variant associations', () => {
    for (const [extra, css] of [
      ['<div class="section1Header"><p>DUPLICATE</p></div>', ''],
      ['<div class="section9Footer"><p>ORPHAN</p></div>', ''],
      ['<div class="section1LeftHeader"><p>LEFT</p></div>', 'div.section1Left{}'],
      ['<div class="section1FirstHeader"><p>FIRST</p></div>', 'div.section1First{}'],
      ['', 'div.section1Header,div.section2Header{margin:1cm}'],
    ]) {
      const model = new WriteProDocument(source('HEADER', extra, css));
      model.setScope('section1Header');
      expect(model.headerReason()).toBe('headerAssociation');
      expect(() => model.changeHeaderArea(2, 'Footer')).toThrow();
    }
  });

  it('rolls back any mutation outside the active area, including native metadata and sibling content', () => {
    const model = new WriteProDocument(source());
    model.setScope('section1Header');
    const before = model.serialize();
    for (const change of [
      () => { model.document.querySelector('body > p').textContent = 'LOST'; },
      () => { model.document.querySelector('meta').setAttribute('content', '{}'); },
      () => { model.scopeRoot.setAttribute('class', 'section2Header'); },
    ]) {
      expect(() => model.mutate('typing', change)).toThrow();
      expect(model.serialize()).toBe(before);
      expect(() => model.mutate('headerSetup', change, null, false, 'section2Footer')).toThrow();
      expect(model.serialize()).toBe(before);
    }
  });

  it('rejects malformed UTF-16 and edits inside surrogate pairs without changing XML or history', () => {
    const model = new WriteProDocument(source('HEADER😀'));
    model.setScope('section1Header');
    render(model);
    const before = model.serialize();
    expect(() => model.replaceText(range(7), 'X')).toThrow();
    expect(model.serialize()).toBe(before);
    render(model);
    expect(() => model.editRun(0, '\ud83d')).toThrow();
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toHaveLength(0);
  });

  it('restores the changed scope on undo even when the edit had no saved text selection', () => {
    const model = new WriteProDocument(source('HEADER', '<div class="section2Footer"><p>FOOTER</p></div>'));
    model.setScope('section1Header');
    render(model);
    model.editRun(0, 'CHANGED HEADER');
    model.setScope('section2Footer');
    model.undo();
    expect(model.scope).toBe('section1Header');
    expect(model.scopeRoot.textContent).toBe('HEADER');
    const recovered = WriteProDocument.unpack(model.pack());
    recovered.undo(true);
    expect(recovered.scope).toBe('section1Header');
    expect(recovered.document.querySelector('.section1Header').textContent).toBe('CHANGED HEADER');
  });

  it('rejects rich pasted structures rather than flattening tables, images, lists or native references', () => {
    const model = new WriteProDocument(source());
    model.setScope('section1Header');
    render(model);
    const before = model.serialize();
    for (const html of ['<table><tr><td>LOST</td></tr></table>', '<img src="x"/>', '<ul><li>LIST</li></ul>', '<span style="-d4-ref:1+1">CACHED</span>']) {
      expect(() => model.paste(range(), html, '')).toThrow(expect.objectContaining({ code: 'headerUnsupported' }));
      expect(model.serialize()).toBe(before);
    }
  });

  it('prints all stored supported areas once with explicit labels on a disposable projection, regardless of editing scope', () => {
    const model = new WriteProDocument(source('HEADER', '<div class="section2Footer" style="visibility:hidden;height:0"><p>FOOTER</p></div>'));
    model.setScope('section1Header');
    render(model);
    const before = model.pack();
    const { root } = createPrintProjection(model, messages.en);
    expect(root.querySelector('.header-appendix').textContent).toContain(messages.en.headerPrint);
    expect(root.querySelector('.header-appendix').textContent).toContain('Native section 2 · Default · Footer');
    expect(root.querySelector('.header-appendix').textContent).toContain('HEADER');
    expect(root.querySelector('.header-appendix').textContent).toContain('FOOTER');
    expect(root.querySelector('[contenteditable]')).toBeNull();
    expect(model.pack()).toEqual(before);
  });
});
