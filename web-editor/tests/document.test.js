import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { strToU8, unzipSync, zipSync } from 'fflate';
import { WriteProDocument } from '../src/document.js';
import { readArchive, MAX_ARCHIVE } from '../src/archive.js';
import { languages, messages, detectLanguage } from '../src/i18n.js';

const fixtures = resolve('../Tests/FourDFileKitTests/Fixtures/WritePro');
const fixture = name => new Uint8Array(readFileSync(resolve(fixtures, `${name}.4wp`)));
const source = body => `<html xmlns="http://www.w3.org/1999/xhtml" xmlns:d4="http://www.4D.com"><head><title>Test</title><style>p { font-size:12pt }p.protected { -d4-protected:true }</style></head><body>${body}</body></html>`;
const render = model => {
  const host = document.createElement('article');
  model.render(host, messages.en);
  return host;
};

describe('real 4D 21.2 archives', () => {
  it.each(['text', 'layout', 'objects', 'table', 'media', 'more'])('round-trips untouched %s byte-for-byte', name => {
    const bytes = fixture(name);
    const model = WriteProDocument.open(bytes);
    const host = render(model);
    expect(host.textContent.length).toBeGreaterThan(0);
    expect(model.export()).toEqual(bytes);
    expect(host.querySelector('script,a,style,iframe')).toBeNull();
    expect([...host.querySelectorAll('img')].every(img => img.src.startsWith('data:image/'))).toBe(true);
  });

  it.each(['text', 'layout', 'table', 'more'])('edits %s without changing native structure or styles', name => {
    const model = WriteProDocument.open(fixture(name));
    render(model);
    const before = new DOMParser().parseFromString(model.serialize(), 'application/xhtml+xml');
    const original = model.runs.find(node => !model.protected(node.parentElement));
    const index = model.runs.indexOf(original);
    const initialText = original.data;
    model.editRun(index, 'Edited 日本語 & <text>');
    const reopened = WriteProDocument.open(model.export());
    expect(reopened.document.querySelector('head style').textContent).toBe(before.querySelector('head style').textContent);
    const walker = before.createTreeWalker(before.querySelector('body'), 4);
    while (walker.nextNode()) {
      if (walker.currentNode.data === initialText) {
        walker.currentNode.data = 'Edited 日本語 & <text>';
        break;
      }
    }
    expect(reopened.document.querySelector('body').outerHTML).toBe(before.querySelector('body').outerHTML);
    expect(reopened.document.querySelector('meta[name="datetimeModified"]')).not.toBeNull();
  });

  it.each(['objects', 'media'])('locks bookmarked %s to preserve offsets', name => {
    const model = WriteProDocument.open(fixture(name));
    const host = render(model);
    expect(model.readOnly).toBe(true);
    expect(host.querySelector('[contenteditable]')).toBeNull();
    expect(() => model.editRun(0, 'changed')).toThrow('protected');
    expect(() => model.addParagraph()).toThrow('protected');
  });

  it('respects protected paragraphs, formulas and data-source tables', () => {
    const model = WriteProDocument.open(fixture('more'));
    const host = render(model);
    expect([...host.querySelectorAll('[data-run]')].find(run => run.textContent === 'Protected paragraph').hasAttribute('contenteditable')).toBe(false);
    const table = WriteProDocument.open(fixture('table'));
    const tableHost = render(table);
    expect(tableHost.querySelector('table [contenteditable]')).not.toBeNull();
    expect(tableHost.textContent).toContain(messages.en.preserved);
    expect(table.document.querySelector('#t2')).not.toBeNull();
  });
});

describe('editing and export', () => {
  it('formats a selected substring while retaining unknown native attributes and resources', () => {
    const xml = source('<p><span style="-d4-custom:opaque;color:red">Hello world</span></p><d4:unknown value="keep"/>');
    const resource = new Uint8Array([0, 255, 4, 3]);
    const model = WriteProDocument.open(zipSync({ 'Doc.html': strToU8(xml), 'native.4dfo': resource }));
    render(model);
    model.formatRun(0, 'font-weight', 'bold', 6, 11);
    const reopened = WriteProDocument.open(model.export());
    expect(reopened.document.querySelector('p').textContent).toBe('Hello world');
    expect(reopened.document.querySelector('p span').getAttribute('style')).toBe('-d4-custom:opaque;color:red');
    expect(reopened.document.querySelector('p span span').textContent).toBe('world');
    expect(reopened.document.getElementsByTagNameNS('http://www.4D.com', 'unknown').length).toBe(1);
    expect(reopened.files['native.4dfo']).toEqual(resource);
    model.undo();
    expect(model.serialize()).toBe(model.initial);
    model.undo(true);
    expect(model.document.querySelector('p span span').textContent).toBe('world');
  });

  it('creates valid XHTML, adds paragraphs and exports text line breaks', () => {
    const model = WriteProDocument.create('New <document>');
    render(model);
    model.editRun(0, 'first\nsecond & <third>');
    model.addParagraph(0);
    const reopened = WriteProDocument.open(model.export());
    expect(reopened.title).toBe('New <document>');
    expect(reopened.document.querySelectorAll('body > p').length).toBe(2);
    expect(reopened.document.querySelector('p br')).not.toBeNull();
    expect(reopened.document.querySelector('p').textContent).toBe('firstsecond & <third>');
    expect(reopened.document.querySelector('style').textContent).toContain('-d4-version:2.20');
  });

  it('preserves native declarations when adding paragraph alignment', () => {
    const model = new WriteProDocument(source('<p style="-d4-custom:\'a;b\';-d4-keep-next:true;text-align:left">Hello</p>'));
    render(model);
    model.alignBlock(0, 'right');
    expect(model.blocks[0].getAttribute('style')).toContain("-d4-custom:'a;b';-d4-keep-next:true");
    expect(model.blocks[0].getAttribute('style')).toMatch(/text-align:right$/);
  });
});

describe('untrusted documents and bounded archives', () => {
  it('never projects executable markup, URLs, external styles or arbitrary CSS', () => {
    const model = new WriteProDocument(source('<p onclick="alert(1)" style="background-image:url(https://example.com/a);position:fixed;color:red"><a href="javascript:alert(1)">Link</a><script>alert(1)</script><img src="https://example.com/tracker"/><svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg></p>'));
    const host = render(model);
    expect(host.querySelector('script,a,svg,style,link')).toBeNull();
    expect(host.querySelector('[onclick],[href],[src]')).toBeNull();
    expect(host.querySelector('p').style.cssText).toBe('font-size: 12pt; color: red;');
    expect(model.serialize()).toContain('onclick');
  });

  it('rejects invalid XML, DTDs, excessive depth and ambiguous HTML entries', () => {
    expect(() => new WriteProDocument(source('<p>broken'))).toThrow('invalidDocument');
    expect(() => new WriteProDocument('<!DOCTYPE html>' + source('<p>no</p>'))).toThrow('invalidDocument');
    expect(() => new WriteProDocument(source('<div>'.repeat(70) + '</div>'.repeat(70)))).toThrow('tooLarge');
    expect(() => WriteProDocument.open(zipSync({ 'a.html': strToU8(source('')), 'b.html': strToU8(source('')) }))).toThrow('ambiguousDocument');
    expect(() => WriteProDocument.open(zipSync({ 'readme.txt': strToU8('text') }))).toThrow('ambiguousDocument');
  });

  it('rejects CRC corruption, unsafe paths and oversized compressed / expanded input', () => {
    const bytes = zipSync({ 'Doc.html': strToU8(source('<p>CRC</p>')) }, { level: 0 });
    const broken = bytes.slice();
    broken[40] ^= 1;
    expect(() => readArchive(broken)).toThrow('invalidArchive');
    expect(() => readArchive(zipSync({ '../Doc.html': strToU8('x') }))).toThrow('invalidArchive');
    expect(() => readArchive(new Uint8Array(MAX_ARCHIVE + 1))).toThrow('tooLarge');
    expect(() => readArchive(zipSync({ 'bomb.bin': new Uint8Array(33 * 1024 * 1024) }))).toThrow('tooLarge');
    expect(() => readArchive(bytes.slice(0, -4))).toThrow('invalidArchive');
  });

  it('retains resources after editing without relying on HTML entry naming', () => {
    const model = WriteProDocument.open(zipSync({
      'nested/日本語.xhtml': strToU8(source('<p>Archive</p>')),
      'nested/picture.bin': new Uint8Array([4, 5, 6]),
    }));
    render(model);
    model.editRun(0, 'Modified');
    const output = unzipSync(model.export());
    expect(Object.keys(output)).toEqual(['nested/日本語.xhtml', 'nested/picture.bin']);
    expect(output['nested/picture.bin']).toEqual(new Uint8Array([4, 5, 6]));
  });
});

describe('localization', () => {
  it('provides complete messages in all six languages', () => {
    for (const language of Object.keys(languages)) {
      expect(Object.keys(messages[language]).sort()).toEqual(Object.keys(messages.en).sort());
      expect(Object.values(messages[language]).every(text => typeof text === 'string' && text.length > 0)).toBe(true);
    }
    expect(detectLanguage(['pt-BR', 'fr-CA', 'en'])).toBe('fr');
    expect(detectLanguage(['nl'])).toBe('en');
  });
});
