import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { nativeMetadata } from '../src/native-ranges.js';
import { defaultTab, parseTabs, tabDeclarations, tabTypes } from '../src/flow-settings.js';

const xml = (body, style = '', metadata = '') => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Flow</title>${metadata}<style>${style}</style></head><body>${body}</body></html>`;
const render = model => model.render(document.createElement('article'), messages.en);
const caret = (run = 0, offset = 0) => ({ startRun: run, endRun: run, start: offset, end: offset });
const tabs = '-d4-tab-stop-offset:36pt 72pt 18pt;-d4-tab-stop-type:left right center;-d4-tab-stop-leading:\'\' \'.\' \'_\'';

describe('section-aware native columns', () => {
  it('reads and resets native-generated column overrides without dropping a native rule', () => {
    const doc = WriteProDocument.open(new Uint8Array(readFileSync(resolve('tests/fixtures/flow/layout-columns-section.4wp'))));
    const body = doc.document.querySelector('body').outerHTML;
    expect(doc.columnSetup().settings).toEqual({ count: 2, gap: '18pt' });
    expect(doc.columnSetup(2).settings).toEqual({ count: 3, gap: '0.5cm' });
    doc.setColumns(2, { gap: null });
    expect(doc.columnSetup(2).settings).toEqual({ count: 3, gap: '18pt' });
    expect(doc.serialize()).toContain('column-rule-style:solid');
    expect(doc.document.querySelector('body').outerHTML).toBe(body);
  });
  it('edits independent overrides, resets duplicates by absence and keeps body, rules and unknown CSS intact', () => {
    const doc = new WriteProDocument(xml('<p style="-d4-section-break-after:continuous">AB</p><p>CD</p>',
      'div.section0{column-count:2;column-gap:18pt}div.section2{column-count:3;column-gap:12pt;column-rule-style:solid;-d4-opaque:keep}div.section2{column-gap:20pt}'));
    const body = doc.document.querySelector('body').outerHTML;
    expect(doc.columnSetup(2)).toMatchObject({ settings: { count: 3, gap: '20pt' }, reason: null });
    doc.setColumns(2, { gap: null });
    expect(doc.columnSetup(2).settings).toEqual({ count: 3, gap: '18pt' });
    doc.setColumns(0, { count: 4, gap: '10.123456789mm' });
    expect(doc.columnSetup(2).settings).toEqual({ count: 3, gap: '10.123456789mm' });
    doc.setColumns(2, { count: null });
    expect(doc.columnSetup(2).overrides).toEqual({});
    expect(doc.serialize()).toContain('column-rule-style:solid;-d4-opaque:keep');
    expect(doc.document.querySelector('body').outerHTML).toBe(body);
    const edited = doc.serialize();
    doc.undo();
    const restored = WriteProDocument.unpack(doc.pack());
    restored.undo(true);
    expect(restored.serialize()).toBe(edited);
    const host = document.createElement('article');
    restored.render(host, messages.en);
    expect([...host.querySelectorAll('.section-columns')].map(node => node.style.columnCount)).toEqual(['4', '4']);
  });

  it('rejects invalid counts, units, impossible widths and geometry changes that would collapse columns', () => {
    const doc = new WriteProDocument(xml('<p>AB</p>'));
    for (const count of [0, 21, 1.5, '2', NaN]) expect(() => doc.setColumns(0, { count })).toThrow('columnsInvalid');
    for (const gap of ['-1pt', '1px', '10001pt', 'NaNpt']) expect(() => doc.setColumns(0, { gap })).toThrow('columnsInvalid');
    expect(() => doc.setColumns(0, { count: 20, gap: '100pt' })).toThrow('columnsWidth');
    doc.setColumns(1, { count: 2, gap: '200pt' });
    expect(() => doc.setPageSetup({ width: '300pt' })).toThrow('columnsWidth');
    expect(() => doc.setSectionSetup(1, { margins: { top: '0pt', right: '210pt', bottom: '0pt', left: '210pt' } })).toThrow('columnsWidth');
    expect(doc.undoLabels).toEqual(['columnsSetup']);
  });

  it.each(['p{column-count:2}', 'div.section1{column-count:2!important}', '@media print{div.section1{column-gap:12pt}}', 'div.section1{column-count:auto}'])('protects unsupported column scope: %s', style => {
    const doc = new WriteProDocument(xml('<p>AB</p>', style));
    const before = doc.serialize();
    expect(() => doc.setColumns(1, { count: 3 })).toThrow('columnsUnsupported');
    expect(doc.serialize()).toBe(before);
  });
});

describe('native paragraph tabs', () => {
  it.each([[1, 'left'], [10, 'right'], [19, 'center'], [28, 'decimal'], [37, 'bar']])('reads full-4D-generated tab fixture %i without changing archive bytes', (index, type) => {
    const bytes = new Uint8Array(readFileSync(resolve(`tests/fixtures/flow/layout-tabs-${index}.4wp`)));
    const doc = WriteProDocument.open(bytes);
    render(doc);
    expect(doc.paragraphTabs(doc.blocks[0])).toEqual({
      stops: [{ position: '36pt', type, leader: '' }, { position: '72pt', type: 'right', leader: '.' }],
      default: { position: '18pt', type, leader: '' },
    });
    expect(doc.export()).toEqual(bytes);
  });

  it('respects native-generated named style and generated direct formatting cascades', () => {
    const doc = WriteProDocument.open(new Uint8Array(readFileSync(resolve('tests/fixtures/flow/layout-cascade.4wp'))));
    render(doc);
    expect(doc.paragraphTabs(doc.blocks[0])).toEqual({ stops: [{ position: '48pt', type: 'center', leader: '.' }], default: { position: '30pt', type: 'left', leader: '' } });
    expect(doc.paragraphTabs(doc.blocks[1])).toEqual({ stops: [], default: { position: '20pt', type: 'left', leader: '' } });
    const before = doc.serialize();
    doc.setParagraphTabs(caret(), settings => settings);
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toHaveLength(0);
  });

  it.each(tabTypes)('retains the last %s tab as the default interval rather than an absolute stop', type => {
    const settings = { stops: [{ position: '36pt', type, leader: '.' }], default: { position: '18.123456789pt', type, leader: '_' } };
    expect(parseTabs(tabDeclarations(settings))).toEqual(settings);
  });

  it('changes one stop across partial/mixed paragraphs without flattening styles or touching the end-only paragraph', () => {
    const doc = new WriteProDocument(xml('<p class="Tabbed" style="color:red;-d4-opaque:keep">AB<span>CD</span></p><p>EF</p><p>GH</p>',
      `p.Tabbed{${tabs};font-weight:bold}`));
    render(doc);
    const before = doc.serialize();
    const selection = { startRun: 0, start: 1, endRun: 3, end: 0 };
    expect(doc.tabBlocks(selection)).toHaveLength(2);
    doc.setParagraphTabs(selection, settings => ({ ...settings, stops: [...settings.stops, { position: '100pt', type: 'bar', leader: '-' }] }));
    expect(doc.paragraphTabs(doc.blocks[0]).stops).toHaveLength(3);
    expect(doc.paragraphTabs(doc.blocks[1]).stops).toHaveLength(1);
    expect(doc.paragraphTabs(doc.blocks[2])).toEqual({ stops: [], default: defaultTab });
    expect(doc.blocks[0].getAttribute('class')).toBe('Tabbed');
    expect(doc.blocks[0].getAttribute('style')).toContain('color:red;-d4-opaque:keep');
    const edited = doc.serialize();
    doc.undo();
    expect(doc.serialize()).toBe(before);
    const recovered = WriteProDocument.unpack(doc.pack());
    recovered.undo(true);
    expect(recovered.serialize()).toBe(edited);
    expect(recovered.undoLabels).toEqual(['tabsSetup']);
  });

  it('includes an end paragraph when selection ends at the start of its later inline run', () => {
    const doc = new WriteProDocument(xml('<p>AB</p><p>CD<span>EF</span></p>'));
    render(doc);
    expect(doc.tabBlocks({ startRun: 0, start: 1, endRun: 2, end: 0 })).toHaveLength(2);
  });

  it('clears only a chosen stop, preserves default type/leader and resets to native factory rather than style inheritance', () => {
    const doc = new WriteProDocument(xml('<p class="Tabbed">AB</p>', `p.Tabbed{${tabs};font-weight:bold}`));
    render(doc);
    doc.setParagraphTabs(caret(), settings => ({ ...settings, stops: settings.stops.slice(1) }));
    expect(doc.paragraphTabs(doc.blocks[0])).toEqual({ stops: [{ position: '72pt', type: 'right', leader: '.' }], default: { position: '18pt', type: 'center', leader: '_' } });
    doc.resetParagraphTabs(caret());
    expect(doc.paragraphTabs(doc.blocks[0])).toEqual({ stops: [], default: defaultTab });
    expect(doc.values(doc.blocks[0])['font-weight']).toBe('bold');
    expect(doc.serialize()).toContain(`p.Tabbed{${tabs};font-weight:bold}`);
    const count = doc.undoStack.length;
    doc.resetParagraphTabs(caret());
    expect(doc.undoStack).toHaveLength(count);
  });

  it('preserves formula XML, exact offsets and resources during formatting and registered real tab insertion', () => {
    const doc = new WriteProDocument(xml('<p>AB<span style="-d4-ref:\'1+1\'">SAVED</span>😀日</p>', '',
      '<meta name="bookmarks" content="{&quot;span&quot;:[0,2],&quot;point&quot;:[1,1]}"/>'));
    render(doc);
    const formula = doc.formulaElements()[0].outerHTML;
    const bookmarks = nativeMetadata(doc.document).bookmarks;
    doc.setParagraphTabs(caret(), settings => ({ ...settings, default: { ...settings.default, position: '18pt' } }));
    expect(nativeMetadata(doc.document).bookmarks).toEqual(bookmarks);
    render(doc);
    doc.replaceText(caret(0, 1), '\t');
    expect(doc.nativeView().text).toBe('A\tB\ufffc😀日');
    expect(nativeMetadata(doc.document).bookmarks).toEqual({ span: [1, 4], point: [2, 2] });
    expect(doc.formulaElements()[0].outerHTML).toBe(formula);
  });

  it.each([
    'p{-d4-tab-stop-offset:0pt}', 'p{-d4-tab-stop-offset:36pt 36pt 12pt}',
    'p{-d4-tab-stop-offset:12pt;-d4-tab-stop-leading:"日"}', 'p{-d4-tab-stop-offset:12pt!important}',
    '@media print{p{-d4-tab-stop-offset:12pt}}', 'body{-d4-tab-stop-offset:12pt}',
  ])('protects malformed/unsupported native tab data: %s', style => {
    const doc = new WriteProDocument(xml('<p>AB</p>', style));
    render(doc);
    expect(() => doc.resetParagraphTabs(caret())).toThrow('tabsUnsupported');
    expect(doc.undoStack).toHaveLength(0);
  });

  it('rejects invalid tab edits atomically across all selected paragraphs', () => {
    const doc = new WriteProDocument(xml('<p>AB</p><p>CD</p>'));
    render(doc);
    const before = doc.serialize();
    let index = 0;
    expect(() => doc.setParagraphTabs({ startRun: 0, start: 0, endRun: 1, end: 1 }, settings => {
      settings.default.position = index++ ? '0pt' : '12pt';
      return settings;
    })).toThrow('tabsInvalid');
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toHaveLength(0);
  });

  it('protects unverified inherited inline tab scopes instead of overwriting them', () => {
    const doc = new WriteProDocument(xml('<div style="-d4-tab-stop-offset:12pt"><p>AB</p></div>'));
    render(doc);
    const before = doc.serialize();
    expect(() => doc.resetParagraphTabs(caret())).toThrow('tabsUnsupported');
    expect(doc.serialize()).toBe(before);
  });

  it('does not bypass the cross-cell insertion guard for tab characters', () => {
    const doc = new WriteProDocument(xml('<p>BEFORE</p><table><tr><td><p>AB</p></td><td><p>CD</p></td></tr></table><p>AFTER</p>', '',
      '<meta name="bookmarks" content="{&quot;cross&quot;:[7,11]}"/>'));
    render(doc);
    const before = doc.serialize();
    expect(() => doc.replaceText(caret(1, 2), '\t')).toThrow('bookmarkCrossInsert');
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toHaveLength(0);
  });
});
