import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { pageDisplay, pagePoints, pagePaperSize } from '../src/page-setup.js';
import { messages } from '../src/i18n.js';

const source = style => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page</title><meta name="bookmarks" content="{&quot;anchor&quot;:[0,1]}"/><style>${style}</style></head><body><p>AB<span style="-d4-ref:'1+1'">SAVED</span>CD</p><table><tr><td><p>EF</p></td></tr></table></body></html>`;
const model = style => new WriteProDocument(source(style), { 'opaque.4dfo': Uint8Array.of(0, 255, 17) });

describe('document page setup', () => {
  it('patches only native defaults and retains body, formulas, bookmark metadata, resources and section declarations', () => {
    const doc = model('div.section0 { -d4-page-width:595pt;-d4-opaque:keep }div.section2 { -d4-page-margin:2.5cm 2.5cm 2.5cm 40pt;-d4-page-orientation:landscape }');
    const body = doc.document.querySelector('body').outerHTML;
    const bookmarks = doc.document.querySelector('meta').outerHTML;
    doc.setPageSetup({ width: '612pt', height: '792pt', orientation: 'landscape', top: '30pt' });
    expect(doc.document.querySelector('body').outerHTML).toBe(body);
    expect(doc.document.querySelector('meta').outerHTML).toBe(bookmarks);
    expect(doc.files['opaque.4dfo']).toEqual(Uint8Array.of(0, 255, 17));
    expect(doc.serialize()).toContain('-d4-opaque:keep');
    expect(doc.serialize()).toContain('div.section2 { -d4-page-margin:2.5cm 2.5cm 2.5cm 40pt;-d4-page-orientation:landscape }');
    expect(doc.pageSetup().geometry).toMatchObject({ width: '612pt', height: '792pt', orientation: 'landscape', top: '30pt', left: '2.5cm' });
    const reopened = WriteProDocument.open(doc.export());
    expect(reopened.pageSetup().geometry).toEqual(doc.pageSetup().geometry);
  });

  it('adds defaults to native documents without a section0 rule and recovers coherent undo/redo', () => {
    const doc = model('p { font-family:Arial }');
    const initial = doc.serialize();
    doc.setPageSetup({ width: '630pt', height: '810pt' });
    const edited = doc.serialize();
    expect(doc.undoLabels).toEqual(['pageSetup']);
    doc.undo();
    expect(doc.serialize()).toBe(initial);
    const recovered = WriteProDocument.unpack(doc.pack());
    recovered.undo(true);
    expect(recovered.serialize()).toBe(edited);
    recovered.restoreVersion(initial);
    expect(recovered.serialize()).toBe(initial);
    recovered.undo();
    expect(recovered.serialize()).toBe(edited);
  });

  it('uses native whole-point rounding and swaps, never sorts, the base dimensions for orientation', () => {
    const doc = model('');
    doc.setPageSetup({ width: '600.125pt', height: '800.875pt' });
    expect(doc.pageSetup().geometry).toMatchObject({ width: '600pt', height: '801pt' });
    doc.setPageSetup({ width: '900pt', height: '500pt', orientation: 'portrait' });
    expect(pagePaperSize(doc.pageSetup().geometry)).toEqual([900, 500]);
    doc.setPageSetup({ orientation: 'landscape' });
    expect(pagePaperSize(doc.pageSetup().geometry)).toEqual([500, 900]);
  });

  it('does not turn converted display values into document edits', () => {
    const doc = model('div.section0 { -d4-page-margin:12.345mm 0pt 0.5in 1.25cm }');
    const initial = doc.serialize();
    for (const unit of ['pt', 'cm', 'mm', 'in']) {
      expect(Number(pageDisplay(doc.pageSetup().geometry.top, unit))).toBeGreaterThan(0);
    }
    doc.setPageSetup({});
    expect(doc.serialize()).toBe(initial);
    expect(doc.undoStack).toHaveLength(0);
  });

  it.each(['NaNpt', 'Infinitypt', '-1pt', '10001pt', '10%', '1e100pt', 'pt'])('rejects invalid %s without any mutation', value => {
    const doc = model('');
    const before = doc.serialize();
    expect(() => doc.setPageSetup({ top: value })).toThrow('pageInvalid');
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toHaveLength(0);
  });

  it('rejects empty paper and zero text areas, including conflicts with retained section overrides', () => {
    const doc = model('');
    expect(() => doc.setPageSetup({ width: '0pt' })).toThrow('pageInvalid');
    expect(() => doc.setPageSetup({ left: '595pt' })).toThrow('pageMarginsInvalid');
    const sections = model('div.section2 { -d4-page-margin:10pt 200pt }');
    expect(() => sections.setPageSetup({ width: '300pt' })).toThrow('pageSectionMargins');
    expect(sections.undoStack).toHaveLength(0);
  });

  it.each([
    'div.section0 { -d4-page-width:calc(10pt + 1in) }',
    'div.section0 { -d4-page-margin:-1pt }',
    'div.section0 { -d4-page-margin-left:10pt }',
    '@media print { div.section0 { -d4-page-width:612pt } }',
    'div.section2 { -d4-page-width:612pt }',
    'div.section1First { -d4-page-margin:10pt }',
    'div.section0 { -d4-page-width:612pt !important }',
    'div.section0 { -D4-PAGE-WIDTH:612pt }',
    'div.section00 { -d4-page-width:612pt }',
  ])('protects unsupported geometry rather than stripping it: %s', style => {
    const doc = model(style);
    expect(doc.pageSetup().reason).toBe('pageUnsupported');
    expect(() => doc.setPageSetup({ width: '612pt' })).toThrow('pageUnsupported');
    expect(doc.serialize()).toBe(doc.initial);
  });

  it('allows geometry-only changes in protected content without relaxing text guards', () => {
    const doc = model('p { -d4-section-break-after:always }');
    expect(doc.readOnly).toBe(true);
    doc.setPageSetup({ width: '612pt' });
    expect(doc.readOnly).toBe(true);
    expect(() => doc.addParagraph()).toThrow('protected');
    expect(() => doc.mutate('pageSetup', () => { doc.document.querySelector('p').textContent = 'corrupt'; })).toThrow('protected');
    expect(doc.document.querySelector('p').textContent).toBe('ABSAVEDCD');
  });

  it('keeps earlier CSS rules and unknown declarations intact across repeated page edits', () => {
    const doc = model('div.section0 { -d4-page-width:600pt;-d4-opaque:keep }div.section0 { -d4-page-height:800pt }');
    doc.setPageSetup({ width: '630pt' });
    doc.setPageSetup({ height: '810pt' });
    expect(doc.pageSetup().geometry).toMatchObject({ width: '630pt', height: '810pt' });
    expect(doc.serialize()).toContain('div.section0 { -d4-page-width:600pt;-d4-opaque:keep }');
  });

  it('has complete, distinct page translations for all six languages', () => {
    for (const locale of Object.keys(messages)) {
      for (const key of Object.keys(messages.en).filter(key => key.startsWith('page'))) expect(messages[locale][key]).toBeTruthy();
      expect(messages[locale].pageSetup).not.toContain('undefined');
    }
    expect(pagePoints('1in')).toBe(72);
  });
});
