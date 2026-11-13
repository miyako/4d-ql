import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { pagedCapability, createPagedProjection, selectedPageArea } from '../src/paged-preview.js';
import { messages } from '../src/i18n.js';

const source = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Pages</title><style>${style}</style></head><body>${body}</body></html>`;

describe('derived paged projection safety and area selection', () => {
  it('selects first before facing, uses physical parity, and never borrows missing content', () => {
    const state = {
      variants: ['section1First', 'section1Left', 'section1Right', 'section2First', 'section2Left', 'section2Right'],
      areas: ['Header', 'Footer'].flatMap(kind => ['', 'First', 'Left', 'Right'].map(variant => ({ section: 1, kind, variant }))),
    };
    expect(selectedPageArea(state, 1, true, 1, true, 'Header').variant).toBe('First');
    expect(selectedPageArea(state, 1, false, 2, true, 'Header').variant).toBe('Left');
    expect(selectedPageArea(state, 1, false, 2, false, 'Footer').variant).toBe('Right');
    expect(selectedPageArea(state, 1, false, 3, false, 'Header').variant).toBe('Left');
    expect(selectedPageArea(state, 2, true, 4, true, 'Header')).toBeUndefined();
    state.areas = state.areas.filter(area => area.variant !== 'First' && !(area.variant === 'Right' && area.kind === 'Footer'));
    expect(selectedPageArea(state, 1, true, 1, true, 'Header')).toBeUndefined();
    expect(selectedPageArea(state, 1, false, 3, true, 'Footer')).toBeUndefined();
    state.variants = [];
    expect(selectedPageArea(state, 1, false, 3, true, 'Footer').variant).toBe('');
  });

  it('does not change source XML, selected scope, archive bytes, history, or live editor mappings on failure', () => {
    const model = new WriteProDocument(source(
      'div.section1Header{margin:10pt}', '<p>BODY</p><div class="section1Header" style="visibility:hidden;height:0"><p>HEADER</p></div>'),
    { 'sentinel.bin': Uint8Array.of(0, 255, 17) });
    model.setScope('section1Header');
    model.render(document.createElement('article'), messages.en);
    const before = model.pack();
    const mappings = model.projection;
    expect(pagedCapability(model)).toBeNull();
    expect(model.pack()).toEqual(before);
    expect(() => createPagedProjection(model, messages.en)).toThrow(expect.objectContaining({ code: 'pagedUnavailable' }));
    expect(model.pack()).toEqual(before);
    expect(model.projection).toBe(mappings);
    expect(document.querySelector('.paged-measure')).toBeNull();
  });

  it('rejects unsupported shapes/settings without substituting partial pages', () => {
    for (const [style, body, reason] of [
      ['div.section0{column-count:2}', '<p>TEXT</p>', 'pagedShape'],
      ['', '<p style="-d4-section-break-after:continuous">A</p><p>B</p>', 'pagedShape'],
      ['', '<table><tr><td><p>CELL</p></td></tr></table>', 'pagedShape'],
      ['', '<ul><li>ITEM</li></ul>', 'pagedShape'],
      ['', '<p><img src="https://invalid.example"/></p>', 'pagedShape'],
      ['p{-d4-page-width:300pt}', '<p>TEXT</p>', 'pagedSettings'],
      ['p{-d4-page-first-right:false}', '<p>TEXT</p>', 'pagedSettings'],
      ['@media print{div.section0{-d4-page-first-right:false}}', '<p>TEXT</p>', 'pagedSettings'],
      ['div.section1Header{margin:10pt}', '<p>TEXT</p><div class="section1Header" style="visibility:hidden;height:0"><p style="height:1pt;min-height:0pt">OVERFLOW</p></div>', 'pagedAreas'],
      ['', '<p><span style="-d4-ref-name:\'Unknown reference\'">OPAQUE</span></p>', 'pagedShape'],
    ]) {
      const model = new WriteProDocument(source(style, body));
      const before = model.pack();
      expect(pagedCapability(model)).toBe(reason);
      expect(() => createPagedProjection(model, messages.en)).toThrow(expect.objectContaining({ code: reason }));
      expect(model.pack()).toEqual(before);
    }
  });
});
