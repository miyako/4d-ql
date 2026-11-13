import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { pagedCapability, createPagedProjection, selectedPageArea, pageListMarker, pagedColumnGeometry } from '../src/paged-preview.js';
import { messages } from '../src/i18n.js';

const source = (style, body) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Pages</title><style>${style}</style></head><body>${body}</body></html>`;

describe('derived paged projection safety and area selection', () => {
  it('admits area-free compatible single-column seams without flattening overrides, names or inheritance', () => {
    const body = '<p style="-d4-section-break-after:continuous">A</p><p>B</p>';
    for (const style of ['', "div.section1{-d4-section-name:'First'}div.section2{-d4-section-name:'Second'}",
      'div.section0{-d4-page-margin:36pt}div.section2{-d4-page-margin:0.5in;column-count:1}']) {
      const model = new WriteProDocument(source(style, body));
      const before = model.pack();
      const mappings = model.projection;
      expect(pagedCapability(model)).toBeNull();
      expect(model.sectionLayout().sections.map(section => section.index)).toEqual([1, 2]);
      expect(model.pack()).toEqual(before);
      expect(model.projection).toBe(mappings);
    }
  });

  it('rejects unsupported continuous seams atomically, including empty areas and enabled but absent variants', () => {
    const seam = '<p style="-d4-section-break-after:continuous">A</p><p>B</p>';
    for (const [style, body] of [
      ['div.section2{-d4-page-margin:40pt}', seam],
      ['div.section2{-d4-page-orientation:landscape}', seam],
      ['div.section0{-d4-page-width:480pt;-d4-page-height:480pt}div.section2{-d4-page-orientation:landscape}', seam],
      ['div.section0{column-count:2}', seam],
      ['div.section2{column-count:2}', seam],
      ['div.section2{column-gap:20pt}', seam],
      ['div.section1Header{margin:10pt}', seam + '<div class="section1Header" style="visibility:hidden;height:0"><p></p></div>'],
      ['div.section2First{white-space:normal}', seam],
      ['div.section1Left{white-space:normal}div.section1Right{white-space:normal}', seam],
      ['div.section0{column-rule-style:solid}', seam],
      ['p{direction:rtl}', seam],
      ['p{column-span:all}', seam],
      ['', '<p style="break-after:column">START</p>' + seam],
    ]) {
      const model = new WriteProDocument(source(style, body));
      const before = model.pack();
      expect(pagedCapability(model)).toBe('pagedContinuous');
      expect(() => createPagedProjection(model, messages.en)).toThrow(expect.objectContaining({ code: 'pagedContinuous' }));
      expect(model.pack()).toEqual(before);
      expect(document.querySelector('.paged-measure')).toBeNull();
    }
  });
  it('admits bounded equal native columns and exact inherited gap geometry without source changes', () => {
    const paper = { width: 480, margins: [60, 36, 60, 36] };
    for (const [count, gap, width] of [[2, 18, 195], [3, 0, 136], [4, 18, 88.5], [4, 40, 72]]) {
      const model = new WriteProDocument(source(`div.section0{column-count:${count};column-gap:${gap}pt}`, '<p>TEXT</p>'));
      const before = model.pack();
      expect(pagedColumnGeometry(model, 1, paper)).toEqual({ count, gap, width });
      expect(pagedCapability(model)).toBeNull();
      expect(model.pack()).toEqual(before);
    }
    const model = new WriteProDocument(source('div.section0{column-count:2;column-gap:18pt}div.section2{column-count:3;column-gap:0pt}',
      '<p style="page-break-after:always;-d4-section-break-after:always">FIRST</p><p>SECOND</p>'));
    expect(pagedColumnGeometry(model, 2, paper)).toEqual({ count: 3, gap: 0, width: 136 });
  });

  it('rejects unsupported column shapes, rules, direction and column-content breaks atomically', () => {
    for (const [style, body] of [
      ['div.section0{column-count:5}', '<p>TEXT</p>'],
      ['div.section0{column-gap:73pt}', '<p>TEXT</p>'],
      ['div.section0{column-rule-style:solid}', '<p>TEXT</p>'],
      ['div.section1{column-width:100pt}', '<p>TEXT</p>'],
      ['p{column-span:all}', '<p>TEXT</p>'],
      ['@media print{div.section1{column-rule-style:none}}', '<p>TEXT</p>'],
      ['p{direction:rtl}', '<p>TEXT</p>'],
      ['', '<p style="column-span:all">TEXT</p>'],
      ['', '<p><span style="break-after:column">TEXT</span></p>'],
      ['', '<p style="break-after:column;page-break-after:always">A</p><p>B</p>'],
      ['', '<p>BEFORE</p><table><tr><td><p>CELL</p></td></tr></table><p>AFTER</p>'],
    ]) {
      const model = new WriteProDocument(source(`div.section0{column-count:2}${style}`, body));
      const before = model.pack();
      expect(pagedCapability(model)).toBe('pagedColumns');
      expect(() => createPagedProjection(model, messages.en)).toThrow(expect.objectContaining({ code: 'pagedColumns' }));
      expect(model.pack()).toEqual(before);
    }
    const model = new WriteProDocument(source('div.section0{column-count:2}', '<p style="break-after:column">A</p><p>B</p>'));
    expect(pagedCapability(model)).toBeNull();
  });
  it('admits rectangular paragraph tables and only leading native header rows, preserving the source', () => {
    const table = rows => `<p>BEFORE</p><table>${rows}</table><p>AFTER</p>`;
    const row = (style = '', cell = '<p>CELL</p>') => `<tr style="${style}"><td>${cell}</td><td><p>SECOND</p></td></tr>`;
    for (const rows of [row() + row(), row('-d4-header:true') + row(), row('-d4-header:true') + row('-d4-header:true') + row()]) {
      const model = new WriteProDocument(source('', table(rows)));
      const before = model.pack();
      expect(pagedCapability(model)).toBeNull();
      expect(model.pack()).toEqual(before);
    }
    for (const rows of [row() + row('-d4-header:true'), row('-d4-header:true'), row('-d4-header:unknown') + row(),
      row('', '<ul><li>LIST<ul><li>NESTED</li></ul></li></ul>'), row('', '<table><tr><td><p>NESTED</p></td></tr></table>'),
      '<tr><td colspan="2"><p>MERGED</p></td></tr>' + row(),
      row() + '<tr><td><p>IRREGULAR</p></td></tr>', row('height:900pt')]) {
      const model = new WriteProDocument(source('', table(rows)));
      expect(pagedCapability(model)).toBe('pagedTables');
    }
    const cells = count => '<td><p>A</p></td>'.repeat(count);
    for (const [rowCount, columnCount, reason] of [[1000, 1, null], [1001, 1, 'pagedTables'],
      [10, 1000, null], [11, 910, 'pagedTables']]) {
      const model = new WriteProDocument(source('', table(row())));
      model.document.querySelector('table').innerHTML = `<tr>${cells(columnCount)}</tr>`.repeat(rowCount);
      expect(pagedCapability(model)).toBe(reason);
    }
  }, 15000);

  it('admits bounded mixed flat cell lists without inventing counters or changing live mappings', () => {
    for (const list of ['<ul><li style="margin-left:24pt;list-style-type:square">A</li><li>B</li></ul>',
      '<ol start="7"><li>A</li><li>B</li></ol>',
      '<ol start="7"><li>A</li></ol><ol start="7"><li>B</li></ol>',
      '<ol start="3999"><li style="list-style-type:upper-roman">A</li></ol>']) {
      const model = new WriteProDocument(source('', `<p>BEFORE</p><table><tr style="-d4-header:true"><td>${list}</td></tr><tr><td><p>INTRO</p>${list}<p>TAIL</p></td></tr></table><p>AFTER</p>`));
      model.render(document.createElement('article'), messages.en);
      const before = model.pack();
      const mappings = model.projection;
      expect(pagedCapability(model)).toBeNull();
      expect(model.pack()).toEqual(before);
      expect(model.projection).toBe(mappings);
    }
    for (const list of ['<ol start="3999"><li>A</li><li>B</li></ol>',
      '<ol start="0"><li>A</li></ol>', '<ol reversed=""><li>A</li></ol>', '<ol><li value="7">A</li></ol>',
      '<ul><li style="-d4-list-level:1">A</li></ul>', '<ul><li style="list-style-type:custom">A</li></ul>',
      '<ol><li style="-d4-list-string-format-ltr:\'##\'">A</li></ol>',
      '<ul><li style="-d4-list-string-format-ltr:\'(#)\'">A</li></ul>',
      '<ol><li style="-d4-list-font:url(font)">A</li></ol>',
      '<ul><li><p>AMBIGUOUS</p></li></ul>']) {
      const model = new WriteProDocument(source('', `<p>BEFORE</p><table><tr><td>${list}</td></tr></table><p>AFTER</p>`));
      const before = model.pack();
      expect(pagedCapability(model)).toBe('pagedTables');
      expect(model.pack()).toEqual(before);
    }
  });

  it('bounds total cell-list markers independently of rows and cells', () => {
    const model = new WriteProDocument(source('', '<p>BEFORE</p><table><tr><td><p>A</p></td></tr></table><p>AFTER</p>'));
    const cell = model.document.querySelector('td');
    const list = count => `<ol>${'<li>A</li>'.repeat(count)}</ol>`;
    cell.innerHTML = list(3999) + list(3999) + list(2002);
    expect(pagedCapability(model)).toBeNull();
    cell.append(cell.firstElementChild.cloneNode(true));
    expect(pagedCapability(model)).toBe('pagedTables');
  }, 30000);

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
      ['', '<table><tr><td><p>CELL</p></td></tr></table>', 'pagedShape'],
      ['', '<ul><li>ITEM<ul><li>NESTED</li></ul></li></ul>', 'pagedShape'],
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

  it('admits flat native levels and retains positional numbering and native marker formats', () => {
    const model = new WriteProDocument(source('', '<ol start="27"><li style="margin-left:20pt;list-style-type:upper-latin">A</li><li style="list-style-type:decimal;-d4-list-string-format-ltr:\'(#)\'">B</li></ol>'));
    expect(pagedCapability(model)).toBeNull();
    expect(pageListMarker({ 'list-style-type': 'upper-latin' }, 27, 'ol')).toBe('AA.');
    expect(pageListMarker({ 'list-style-type': 'lower-roman' }, 49, 'ol')).toBe('xlix.');
    expect(pageListMarker({ '-d4-list-string-format-ltr': "'(#)'" }, 28, 'ol')).toBe('(28)');
    expect(pageListMarker({ '-d4-list-style-type': 'hollow-square' }, 1, 'ul')).toBe('\u25a1');
    expect(pageListMarker({ 'list-style-type': 'disc' }, 1, 'ul', true)).toBe('\u25cf');
    expect(pageListMarker({ 'list-style-type': 'diamond' }, 1, 'ul', true)).toBe('\u2666');
    expect(pageListMarker({ 'list-style-type': 'disc' }, 1, 'ul')).toBe('\u2022');
    expect(pageListMarker({ 'list-style-type': 'diamond' }, 1, 'ul')).toBe('\u25c6');
    for (const values of [{ '-d4-list-style-type': 'custom' }, { '-d4-list-level': '2' },
      { '-d4-list-string-format-ltr': "'#.#'" }]) expect(() => pageListMarker(values, 1, 'ol')).toThrow();
  });
});
