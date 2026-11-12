import { describe, expect, it } from 'vitest';
import { strToU8, zipSync } from 'fflate';
import { WriteProDocument } from '../src/document.js';
import { nativeMetadata } from '../src/native-ranges.js';
import { messages } from '../src/i18n.js';
import evidence from './fixtures/native-formulas.json';

const render = (model, labels = messages.en) => {
  const host = document.createElement('article');
  model.render(host, labels);
  return host;
};
const select = (run, start, end = start) => ({ startRun: run, start, endRun: run, end });
const make = (markup, head = '') => new WriteProDocument(`<html xmlns="http://www.w3.org/1999/xhtml"><head>${head}</head><body><p>AB${markup}CD</p></body></html>`);

describe('full 4D F0012102 formula evidence', () => {
  it.each(evidence.variants)('preserves $name source/cache and maps only proven native slots', item => {
    const model = new WriteProDocument(item.xml);
    const host = render(model);
    if (['picture', 'dataSource'].includes(item.name)) {
      expect(model.readOnly).toBe(true);
      expect(host.querySelector('[contenteditable]')).toBeNull();
      expect(host.textContent).toContain(messages.en.formulaUnsupported);
      return;
    }
    expect(model.readOnly).toBe(false);
    expect(model.nativeView().text).toBe('AB\ufffcCD');
    expect(model.nativeView().text.length + 1).toBe(item.before.end);
    expect(nativeMetadata(model.document).bookmarks).toEqual(item.before.bookmarks);
    const badge = host.querySelector('.formula-object');
    const value = item.name === 'supplied' ? 'SAVED' : item.name === 'suppliedZero' ? '0' : messages.en.formulaUnavailable;
    expect(badge.querySelector('.formula-value').textContent).toBe(`${messages.en.formulaValue}: ${value}`);
    expect(badge.querySelector('[contenteditable]')).toBeNull();
    expect(model.runs.map(node => node.data)).toEqual(['AB', 'CD']);
    const body = model.nativeView();
    for (let offset = 1; offset <= item.before.end; offset++) {
      const point = body.locate(offset);
      expect(body.point(point.node, point.offset)).toBe(offset);
    }
  });

  it.each(evidence.variants.filter(item => item.operations.length))('matches independent native surrounding edits for $name', item => {
    for (const operation of item.operations) {
      const model = new WriteProDocument(item.xml);
      render(model);
      const formula = model.formulaElements()[0].outerHTML;
      const run = text => model.runs.findIndex(node => node.data === text);
      const apply = () => {
        switch (operation.name) {
          case 'before': return model.replaceText(select(run('AB'), 1), '😀日');
          case 'start': return model.replaceText(select(run('AB'), 2), 'XY');
          case 'end': return model.replaceText(select(run('CD'), 0), 'XY');
          case 'after': return model.replaceText(select(run('CD'), 1), '😀日');
          case 'cut': return model.replaceText(select(run('AB'), 0, 2), '', 'cut');
          case 'replace': return model.replaceText(select(run('CD'), 0, 2), 'XY');
          case 'format': return model.formatSelection(select(run('CD'), 0, 2), 'font-weight', 'bold');
          case 'break': return model.splitParagraph(select(run('CD'), 1), true);
          case 'paste':
          case 'pasteBefore':
          case 'pasteStart':
          case 'pasteEnd':
            return model.paste(select(run(['pasteBefore', 'pasteStart'].includes(operation.name) ? 'AB' : 'CD'),
              operation.name === 'pasteStart' ? 2 : operation.name === 'pasteEnd' ? 0 : 1), '<p><b>XY</b></p><p>Z</p>', '');
          default: {
            const before = /Before|Start/.test(operation.name);
            const caret = model.splitParagraph(select(run(before ? 'AB' : 'CD'),
              operation.name.endsWith('Start') ? 2 : operation.name.endsWith('End') ? 0 : 1));
            if (operation.name.startsWith('join')) {
              render(model);
              return model.mergeBoundary(model.runs.indexOf(caret.node), true);
            }
          }
        }
      };
      apply();
      expect(model.formulaElements()[0].outerHTML, operation.name).toBe(formula);
      expect(model.nativeView().text.replace(/\n/g, '\r').replace('\ufffc', item.formulas[0].source), operation.name).toBe(operation.after.text);
      expect(nativeMetadata(model.document).bookmarks, operation.name).toEqual(operation.after.bookmarks);
      const recovered = WriteProDocument.unpack(model.pack());
      const after = recovered.serialize();
      recovered.undo();
      recovered.undo(true);
      expect(recovered.serialize()).toBe(after);
      expect(WriteProDocument.open(model.export()).formulaElements()[0].outerHTML).toBe(formula);
    }
  });
});

describe('protected formula projection and transactions', () => {
  it('uses inert decoded CSS strings and does not infer a result from the source or a placeholder', () => {
    const model = make('<span class="f"><span style="font-weight:bold">&lt;img src=x onerror=alert(1)&gt;</span></span>',
      `<style>span.f{-d4-ref:'Uppercase:C13("attack")';-d4-ref-name:'name\\27 &lt;script&gt;'}</style>`);
    const host = render(model);
    expect(host.querySelector('.formula-source').textContent).toContain('Uppercase:C13("attack")');
    expect(host.querySelector('.formula-value').textContent).toContain('<img src=x onerror=alert(1)>');
    expect(host.querySelector('.formula-object').textContent).toContain("name'<script>");
    expect(host.querySelector('img,script,[onerror]')).toBeNull();
    expect(model.nativeView().text).toBe('AB\ufffcCD');
    expect(model.tracksNativeEdits).toBe(true);
    model.replaceText(select(1, 0), '日本語');
    expect(model.formulaElements()[0].textContent).toBe('<img src=x onerror=alert(1)>');
    expect(model.hasBookmarks).toBe(false);
  });

  it('rejects crossing edits, boundary deletion and unregistered same-slot formula mutations atomically', () => {
    const model = make(`<span style="-d4-ref:'0'">0</span>`);
    render(model);
    const before = model.serialize();
    for (const edit of [
      () => model.replaceText({ startRun: 0, start: 1, endRun: 1, end: 1 }, 'x'),
      () => model.formatSelection({ startRun: 0, start: 1, endRun: 1, end: 1 }, 'font-weight', 'bold'),
      () => model.deleteInlineBoundary(0, false),
      () => model.deleteInlineBoundary(1, true),
      () => model.mutate('edit', () => { model.formulaElements()[0].textContent = 'changed'; }),
      () => model.mutate('edit', () => model.formulaElements()[0].remove()),
    ]) {
      expect(edit).toThrow('protected');
      expect(model.serialize()).toBe(before);
      expect(model.undoStack).toHaveLength(0);
      render(model);
    }
    expect(model.find('BC')).toEqual([]);
    expect(model.find('0')).toEqual([]);
    model.replaceMatches('CD', 'EF', true);
    expect(model.formulaElements()[0].textContent).toBe('0');
  });

  it.each([
    `<span style="-d4-ref:''">cached?</span>`,
    `<span style="-d4-ref-url:url('opaque.4dfo');-d4-ref-name:'Compiled'">cached?</span>`,
    `<span style="-d4-ref-name:'Name only'">cached?</span>`,
    `<span style="-d4-ref:'0'"><img src="https://example.org/track"/></span>`,
    `<span style="-d4-ref:'0'"><span style="-d4-ref:'1'">1</span></span>`,
  ])('keeps unsupported references protected with exact resource payloads: %s', markup => {
    const resource = new Uint8Array([0, 1, 255, 7]);
    const original = make(markup).serialize();
    const bytes = zipSync({ 'Doc.html': strToU8(original), 'opaque.4dfo': resource });
    const model = WriteProDocument.open(bytes);
    const host = render(model);
    expect(host.querySelector('.formula-object').textContent).toContain(messages.en.formulaUnsupported);
    expect(host.querySelector('.formula-value').textContent).toContain(messages.en.formulaUnavailable);
    expect(host.querySelector('img,[src],[href]')).toBeNull();
    expect(model.export()).toEqual(bytes);
    model.replaceText(select(0, 1), 'X');
    const reopened = WriteProDocument.open(model.export());
    expect(reopened.files['opaque.4dfo']).toEqual(resource);
    expect(reopened.formulaElements()[0].outerHTML).toBe(model.formulaElements()[0].outerHTML);
  });

  it('localizes formula labels in all six languages', () => {
    for (const labels of Object.values(messages)) {
      const host = render(make(`<span style="-d4-ref:'0'">&#160;</span>`), labels);
      expect(host.querySelector('.formula-object').getAttribute('aria-label')).toBe(labels.formulaReadonly);
      expect(host.textContent).toContain(labels.formulaUnavailable);
      expect(host.textContent).not.toContain('undefined');
    }
  });
});
