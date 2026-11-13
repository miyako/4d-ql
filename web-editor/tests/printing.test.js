import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { createPrintProjection } from '../src/printing.js';
import { messages } from '../src/i18n.js';

const source = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Print</title><meta name="bookmarks" content="{&quot;point&quot;:[0,1]}"/><style>${style}</style></head><body>${body}</body></html>`;

describe('isolated print projection', () => {
  it('uses section geometry and page breaks outside columns without changing XML, resources, history or editor mappings', () => {
    const model = new WriteProDocument(source(
      'div.section0{-d4-page-width:612pt;-d4-page-height:792pt;-d4-page-margin:24pt 30pt 36pt 42pt;column-count:2;column-gap:18pt}div.section2{-d4-page-orientation:landscape}',
      '<p style="page-break-after:always">FIRST</p><p style="page-break-after:always;-d4-section-break-after:always">SECOND</p><p>THIRD<span style="-d4-ref:\'1+1\'">SAVED</span></p>'),
    { 'sentinel.bin': Uint8Array.of(0, 255, 17) });
    const host = document.createElement('article');
    model.render(host, messages.en);
    model.setPageSetup({ left: '43pt' });
    const before = model.pack();
    const mappings = model.projection;
    const { root, rules } = createPrintProjection(model, messages.en);
    expect(model.pack()).toEqual(before);
    expect(model.projection).toBe(mappings);
    expect(root.textContent).toContain('FIRSTSECONDTHIRD');
    expect(root.querySelector('.formula-source').textContent).toContain('1+1');
    expect(root.querySelector('.formula-value').textContent).toContain('SAVED');
    expect(rules).toContain('size: 612pt 792pt; margin: 24pt 30pt 36pt 43pt');
    expect(rules).toContain('size: 792pt 612pt; margin: 24pt 30pt 36pt 43pt');
    expect(root.querySelectorAll('.section-columns')).toHaveLength(3);
    expect(root.querySelectorAll('.print-new-page')).toHaveLength(2);
    expect(root.querySelector('[contenteditable],[data-run],[tabindex],.explicit-break')).toBeNull();
    expect(root.querySelectorAll('p')).toHaveLength(3);
  });

  it('keeps content and placeholders inert rather than copying source CSS, URLs or native subtrees', () => {
    const model = new WriteProDocument(source('p{color:red;background-image:url(https://invalid.example/tracker)}',
      '<p><a href="https://invalid.example">LINK</a><img src="https://invalid.example/tracker"/><span style="-d4-ref:\'evil()\'">CACHED</span><script>window.pwned=1</script></p>'));
    const { root } = createPrintProjection(model, messages.en);
    expect(root.querySelector('a,script,style,link,img')).toBeNull();
    expect(root.innerHTML).not.toContain('https://');
    expect(root.textContent).toContain('LINK');
    expect(root.textContent).toContain('CACHED');
    expect(root.textContent).toContain(messages.en.image);
    expect(root.querySelectorAll('.preserved-object')).toHaveLength(3);
  });

  it('rejects ambiguous geometry and column settings, never silently printing defaults', () => {
    for (const style of ['p{-d4-page-width:300pt}', 'div.section0{column-count:0}', 'div.section0{-d4-page-margin:9999pt}']) {
      const model = new WriteProDocument(source(style, '<p>REAL TEXT</p>'));
      const before = model.serialize();
      expect(() => createPrintProjection(model, messages.en)).toThrow(expect.objectContaining({ code: 'printUnsupported' }));
      expect(model.serialize()).toBe(before);
    }
  });

  it('uses the same named page for continuous sections with identical geometry and a different page for geometry changes', () => {
    const model = new WriteProDocument(source('div.section3{-d4-page-orientation:landscape}',
      '<p style="-d4-section-break-after:continuous">A</p><p style="-d4-section-break-after:continuous">B</p><p>C</p>'));
    const { root } = createPrintProjection(model, messages.en);
    expect([...root.querySelectorAll('.section-paper')].map(element => element.style.page)).toEqual(['wppaper0', 'wppaper0', 'wppaper1']);
    expect(root.querySelectorAll('.print-new-page')).toHaveLength(0);
  });

  it('rejects native-valid tiny paper and narrow columns before Chromium can clip glyphs, without clamping native settings', () => {
    for (const style of [
      'div.section0{-d4-page-width:10pt;-d4-page-height:10pt;-d4-page-margin:0pt}',
      'div.section0{-d4-page-width:200pt;-d4-page-margin:0pt;column-count:3;column-gap:0pt}',
    ]) {
      const model = new WriteProDocument(source(style, '<p>REAL TEXT</p>'));
      const snapshot = model.pack();
      expect(() => createPrintProjection(model, messages.en)).toThrow(expect.objectContaining({ code: 'printTooSmall' }));
      expect(model.pack()).toEqual(snapshot);
    }
  });

  it('keeps hidden native associations as placeholders on named document paper instead of unnamed browser-default pages', () => {
    const model = new WriteProDocument(source('div.section0{-d4-page-width:420pt;-d4-page-height:595pt;-d4-page-margin:24pt}',
      '<p>BODY</p><div class="section1Header" style="visibility:hidden"><p>ORIGINAL HEADER</p></div>'));
    const before = model.serialize();
    const { root } = createPrintProjection(model, messages.en);
    expect(root.style.page).toBe('wppaper0');
    expect(root.querySelector('.preserved-object').textContent).toBe(messages.en.preserved);
    expect(model.serialize()).toBe(before);
  });
});
