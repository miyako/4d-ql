import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { MAX_EXPANDED, writeArchive } from '../src/archive.js';

function model(body, head = '') {
  const result = new WriteProDocument(`<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title>${head}</head><body>${body}</body></html>`);
  render(result);
  return result;
}
function render(result) { const host = document.createElement('div'); result.render(host, messages.en); return host; }
const selection = (startRun, start, endRun = startRun, end = start) => ({ startRun, start, endRun, end });
const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

describe('continuous native-XML operations', () => {
  it('toggles decorations independently and clears inherited inline highlights', () => {
    const doc = model('<p><span style="-d4-custom:keep;text-decoration:underline;background-color:yellow">Text</span></p>');
    doc.decorateSelection(selection(0, 0, 0, 4), 'line-through', true);
    render(doc);
    expect(doc.decoration(doc.runs[0])).toEqual(['underline', 'line-through']);
    doc.decorateSelection(selection(0, 0, 0, 4), 'underline', false);
    render(doc);
    expect(doc.decoration(doc.runs[0])).toEqual(['line-through']);
    doc.formatSelection(selection(0, 0, 0, 4), 'background-color', 'transparent');
    const host = render(doc);
    expect(host.querySelector('[data-run]').style.backgroundColor).toBe('transparent');
    expect(host.querySelector('p > span').style.backgroundColor).toBe('');
    expect(doc.serialize()).toContain('-d4-custom:keep');
  });

  it('creates safe inert links and removes URLs without flattening native formatting', () => {
    const doc = model('<p><span style="-d4-custom:keep;font-style:italic">Read more</span></p>');
    for (const url of ['javascript:alert(1)', 'data:text/html,test', 'https://name:password@example.org', '/relative']) {
      expect(() => doc.setLink(selection(0, 0, 0, 9), url)).toThrow('linkURL');
    }
    doc.setLink(selection(0, 0, 0, 9), 'https://example.org/');
    const host = render(doc);
    expect(host.querySelector('a')).toBeNull();
    expect(host.querySelector('[data-run]').textContent).toBe('Read more');
    doc.setLink(selection(0, 3), 'mailto:editor@example.org');
    expect(doc.document.querySelector('a').getAttribute('href')).toBe('mailto:editor@example.org');
    doc.removeLink(selection(0, 3));
    expect(doc.document.querySelector('a')).toBeNull();
    expect(doc.serialize()).toContain('-d4-custom:keep;font-style:italic');
    doc.paste(selection(0, 9), '<a href="https://example.org/">Safe</a><a href="javascript:alert(1)">Unsafe</a>', '');
    expect(doc.document.querySelectorAll('a').length).toBe(1);
    expect(doc.document.querySelector('p').textContent).toBe('Read moreSafeUnsafe');
    const locked = model('<p><a href="https://example.org/">Safe<span style="-d4-ref:formula">X</span></a></p>');
    const before = locked.serialize();
    expect(() => locked.setLink(selection(0, 2), 'https://example.org/changed')).toThrow('protected');
    expect(() => locked.removeLink(selection(0, 2))).toThrow('protected');
    expect(locked.serialize()).toBe(before);
  });

  it('restores persisted backward selections after XML merges adjacent text nodes', () => {
    const doc = model('<p>Hello world</p>');
    doc.rememberSelection({ ...selection(0, 6, 0, 11), backward: true });
    const caret = doc.replaceText(selection(0, 6, 0, 11), 'Reader');
    render(doc);
    doc.rememberSelection(selection(doc.runs.indexOf(caret.node), 6));
    const restored = WriteProDocument.unpack(doc.pack());
    const undo = restored.undo();
    render(restored);
    expect(restored.resolveSelection(undo.selection)).toEqual({ ...selection(0, 6, 0, 11), backward: true });
    const redo = restored.undo(true);
    render(restored);
    expect(restored.resolveSelection(redo.selection)).toEqual({ ...selection(0, 12), backward: false });
  });

  it('restores empty cursor slots on both sides of inline objects', () => {
    for (const index of [0, 1]) {
      const doc = model(`<p><img src="${png}"/></p>`);
      doc.rememberSelection(selection(index, 0));
      doc.editRun(index, 'Caption');
      render(doc);
      doc.rememberSelection(selection(index, 7));
      const restored = WriteProDocument.unpack(doc.pack());
      const undo = restored.undo();
      render(restored);
      expect(restored.resolveSelection(undo.selection)).toEqual({ ...selection(index, 0), backward: false });
      const redo = restored.undo(true);
      render(restored);
      expect(restored.resolveSelection(redo.selection)).toEqual({ ...selection(index, 7), backward: false });
    }
  });

  it('formats and replaces across character styles, retaining native declarations', () => {
    const doc = model('<p><span style="-d4-custom:keep">Hello </span><span style="font-style:italic">world</span></p>');
    doc.formatSelection(selection(0, 3, 1, 3), 'font-weight', 'bold');
    expect(doc.document.querySelector('p').textContent).toBe('Hello world');
    expect(doc.serialize()).toContain('-d4-custom:keep');
    render(doc);
    doc.undo();
    render(doc);
    doc.replaceText(selection(0, 3, 1, 3), 'p');
    expect(doc.document.querySelector('p').textContent).toBe('Helpld');
    doc.undo();
    expect(doc.document.querySelector('p').textContent).toBe('Hello world');
  });

  it('splits at the caret and merges without flattening inline formatting', () => {
    const doc = model('<p class="Normal"><span style="color:red">Hello world</span></p>');
    doc.splitParagraph(selection(0, 6));
    expect([...doc.document.querySelectorAll('p')].map(p => p.textContent)).toEqual(['Hello ', 'world']);
    expect(doc.document.querySelectorAll('p span[style="color:red"]').length).toBe(2);
    render(doc);
    doc.mergeBoundary(1, true);
    expect(doc.document.querySelectorAll('p').length).toBe(1);
    expect(doc.document.querySelector('p').textContent).toBe('Hello world');
  });

  it('rejects ranges touching protected formulas and structural deletion across cells', () => {
    const doc = model('<p>A<span style="-d4-ref:formula">X</span>B</p>');
    expect(() => doc.replaceText(selection(0, 0, 1, 1), 'no')).toThrow('protected');
    const table = model('<table><tr><td><p>A</p></td><td><p>B</p></td></tr></table>');
    const before = table.serialize();
    expect(() => table.replaceText(selection(0, 0, 1, 1), 'no')).toThrow('structuralSelection');
    expect(table.serialize()).toBe(before);
  });

  it('groups contiguous typing and separates explicit formatting transactions', () => {
    const doc = model('<p>A</p>');
    doc.editRun(0, 'Ab');
    doc.editRun(0, 'Abc');
    expect(doc.undoStack.length).toBe(1);
    doc.formatSelection(selection(0, 0, 0, 3), 'font-weight', 'bold');
    expect(doc.undoStack.length).toBe(2);
    doc.undo();
    expect(doc.document.querySelector('p').textContent).toBe('Abc');
    doc.undo();
    expect(doc.document.querySelector('p').textContent).toBe('A');
  });

  it('sanitizes rich paste and preserves separate paragraphs', () => {
    const doc = model('<p>Before after</p>');
    doc.paste(selection(0, 7), '<p><b>One</b><img src="https://invalid.test/x"/><script>bad()</script></p><p><i>Two</i></p>', '');
    expect([...doc.document.querySelectorAll('p')].map(p => p.textContent)).toEqual(['Before One', 'Twoafter']);
    expect(doc.document.querySelector('script,img')).toBeNull();
    expect(doc.serialize()).toContain('font-weight:bold');
    expect(doc.serialize()).toContain('font-style:italic');
  });

  it('pastes real lists and exits an empty list item with Enter', () => {
    const doc = model('<p>\u200b</p>');
    doc.paste(selection(0, 0), '<div><ul><li><p>One</p></li><li>Two</li></ul></div>', '');
    expect(doc.document.querySelectorAll('ul > li').length).toBe(2);
    expect(doc.document.querySelector('p ul,p p')).toBeNull();
    const list = model('<ul><li>\u200b</li></ul>');
    list.splitParagraph(selection(0, 0));
    expect(list.document.querySelector('ul')).toBeNull();
    expect(list.document.querySelector('body > p')).not.toBeNull();
  });

  it('rolls back edits that exceed the combined archive budget without adding undo steps', () => {
    const doc = model('<p>Before</p>');
    const before = doc.serialize();
    doc.files['large.bin'] = new Uint8Array(MAX_EXPANDED - new TextEncoder().encode(before).length - 300);
    expect(() => doc.editRun(0, 'x'.repeat(1000))).toThrow('tooLarge');
    expect(doc.serialize()).toBe(before);
    expect(doc.undoStack).toEqual([]);
    render(doc);
    doc.editRun(0, 'After');
    expect(doc.document.querySelector('p').textContent).toBe('After');
    expect(() => writeArchive({}, 'Document.html', 'x'.repeat(MAX_EXPANDED + 1))).toThrow('tooLarge');
  });

  it('rejects destructive paragraph operations at native section breaks', () => {
    const doc = model('<p style="-d4-section-break-after:always">A</p><p>B</p>');
    const before = doc.serialize();
    expect(() => doc.splitParagraph(selection(0, 1))).toThrow('protected');
    expect(() => doc.mergeBoundary(1, true)).toThrow('protected');
    expect(doc.serialize()).toBe(before);
  });
});

describe('styles, tables and search', () => {
  it('applies named styles while retaining generated classes and supports lists', () => {
    const doc = model('<p class="Normal _p1" style="-d4-custom:keep">Hello</p>');
    doc.styleBlocks(selection(0, 0), 'Heading_1');
    expect(doc.document.querySelector('p').getAttribute('class')).toBe('_p1 Heading_1');
    expect(doc.serialize()).toContain('-d4-custom:keep');
    doc.toggleList(0, 'ul');
    expect(doc.document.querySelector('ul li').textContent).toBe('Hello');
    render(doc);
    doc.toggleList(0, 'ul');
    expect(doc.document.querySelector('body > p').textContent).toBe('Hello');
  });

  it('edits simple table structure and refuses merged-cell mutations', () => {
    const doc = model('<p>Start</p>');
    doc.insertTable(0, 2, 2);
    render(doc);
    doc.tableEdit(0, 'addRow');
    render(doc);
    doc.tableEdit(0, 'addColumn');
    expect(doc.document.querySelectorAll('tr').length).toBe(3);
    expect(doc.document.querySelectorAll('td').length).toBe(9);
    render(doc);
    doc.tableEdit(0, 'removeColumn');
    render(doc);
    doc.tableEdit(0, 'removeRow');
    expect(doc.document.querySelectorAll('td').length).toBe(4);
    const merged = model('<table><tr><td colspan="2"><p>Merged</p></td></tr></table>');
    expect(() => merged.tableEdit(0, 'addRow')).toThrow('mergedTable');
  });

  it('finds and replaces text spanning adjacent formatting runs', () => {
    const doc = model('<p>Hello <span>world</span></p><p>Hello world</p>');
    expect(doc.find('HELLO WORLD').length).toBe(2);
    doc.replaceMatches('Hello world', 'Goodbye', true);
    expect([...doc.document.querySelectorAll('p')].map(p => p.textContent)).toEqual(['Goodbye', 'Goodbye']);
    doc.undo();
    expect(doc.document.querySelector('p').textContent).toBe('Hello world');
  });

  it('keeps archive resources in recoverable snapshots and version restores', () => {
    const doc = model('<p>Original</p>');
    doc.files['image.bin'] = new Uint8Array([1, 2, 3]);
    const initial = doc.serialize();
    doc.editRun(0, 'Changed');
    const recovered = WriteProDocument.unpack(doc.pack());
    recovered.undo();
    expect(recovered.document.querySelector('p').textContent).toBe('Original');
    recovered.undo(true);
    expect(recovered.document.querySelector('p').textContent).toBe('Changed');
    expect(recovered.files['image.bin']).toEqual(new Uint8Array([1, 2, 3]));
    recovered.restoreVersion(initial);
    expect(recovered.document.querySelector('p').textContent).toBe('Original');
    recovered.undo();
    expect(recovered.document.querySelector('p').textContent).toBe('Changed');
  });

  it('resolves raster assets relative to the HTML entry and round-trips inserted pictures', () => {
    const doc = new WriteProDocument('<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p>Picture <img src="assets/photo.png"/></p></body></html>',
      { 'Book/assets/photo.png': Uint8Array.from(atob(png.split(',')[1]), char => char.charCodeAt(0)) }, 'Book/Doc.html');
    const host = render(doc);
    expect(host.querySelector('img').src).toBe(png);
    const fresh = model('<p>\u200b</p>');
    fresh.insertImage(selection(0, 0), png, 100, 50, 'Example');
    render(fresh);
    fresh.changeImage(0, 150);
    const exported = WriteProDocument.open(fresh.export());
    expect(exported.document.querySelector('img').getAttribute('style')).toContain('height:75pt');
    expect(exported.document.querySelector('img').getAttribute('alt')).toBe('Example');
    fresh.undo();
    render(fresh);
    fresh.changeImage(0);
    expect(fresh.document.querySelector('img')).toBeNull();
  });

  it('keeps image-only paragraphs editable after restore and moves/removes images without deleting adjacent text', () => {
    const doc = model(`<p><img src="${png}"/></p><p>After</p>`);
    const before = doc.serialize();
    expect(doc.runs[0].length).toBe(0);
    expect(doc.dirty).toBe(false);
    doc.moveImage(0, selection(doc.runs.findIndex(node => node.data === 'After'), 2));
    render(doc);
    expect(doc.document.querySelectorAll('p')[1].querySelector('img')).not.toBeNull();
    doc.undo();
    render(doc);
    expect(doc.serialize()).toBe(before);
    const caret = doc.deleteInlineBoundary(doc.runs.findLastIndex(node => node.parentElement.closest('p') === doc.document.querySelector('p')), true);
    expect(caret).not.toBeNull();
    expect(doc.document.querySelector('img')).toBeNull();
    expect(doc.document.querySelectorAll('p')[1].textContent).toBe('After');
    doc.undo();
    render(doc);
    doc.editRun(0, 'Caption');
    expect(doc.document.querySelector('p').textContent).toBe('Caption');
  });
});
