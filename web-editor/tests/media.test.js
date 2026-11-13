import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { WriteProDocument } from '../src/document.js';
import { mediaSource } from '../src/media-source.js';
import { outsideObject } from '../src/objects.js';
import { createPrintProjection } from '../src/printing.js';
import { messages } from '../src/i18n.js';

const fixture = kind => WriteProDocument.open(new Uint8Array(readFileSync(`tests/fixtures/media/media-${kind}-original.4wp`)));
const render = model => { const host = document.createElement('article'); model.render(host, messages.en); return host; };
const selection = (start, end = start) => ({ startRun: 0, start, endRun: 0, end });
const lifecycleFixture = stage => WriteProDocument.open(new Uint8Array(readFileSync(`tests/fixtures/media/object-paper-${stage}.4wp`)));

describe('native object lifecycle and placement', () => {
  it('creates isolated native objects without changing body, formulas, associations or nonactive XML', () => {
    let model = lifecycleFixture('original');
    const before = model.serialize();
    const source = model.document.querySelector('img').getAttribute('src');
    model.createObject('anchoredPicture', source);
    expect(model.scope).toBe('object:img2');
    expect(model.objectState().geometry).toEqual({ width: '48pt', height: '32pt', x: '0pt', y: '0pt' });
    expect(model.scopeRoot.getAttribute('src')).toBe(source);
    model.createObject('textBox', 'NEW BOX 😀 日é');
    expect(model.scope).toBe('object:textBox2');
    expect(model.headerReason()).toBeNull();
    expect(model.scopeRoot.textContent).toBe('NEW BOX 😀 日é');
    const created = model.serialize();
    model = WriteProDocument.unpack(model.pack());
    model.undo();
    expect(model.scope).toBe('body');
    model.undo();
    expect(model.serialize()).toBe(before);
    model.undo(true); model.undo(true);
    expect(model.serialize()).toBe(created);
    model.setScope('object:img2');
    model.deleteObject();
    expect(model.scope).toBe('body');
    model.setScope('object:textBox2');
    model.deleteObject();
    const remaining = model.document.cloneNode(true);
    const original = new DOMParser().parseFromString(before, 'application/xhtml+xml');
    expect(remaining.querySelector('body').outerHTML).toBe(original.querySelector('body').outerHTML);
    expect([...remaining.querySelectorAll('head style')].slice(0, -2).map(node => node.outerHTML))
      .toEqual([...original.querySelectorAll('head style')].map(node => node.outerHTML));
    model = WriteProDocument.unpack(model.pack());
    model.undo();
    expect(model.scope).toBe('object:textBox2');
    model.undo(true);
    expect(model.scope).toBe('body');
    model.createObject('textBox');
    expect(model.scope).toBe('object:textBox3');
    expect(model.scopeRoot.querySelector('p')).not.toBeNull();
  });

  it('changes only the selected object placement, clearing class and inline alignment together', () => {
    const model = lifecycleFixture('align');
    model.setScope('object:img2');
    model.scopeRoot.setAttribute('style', '/* retained native metadata */width: 48pt;-d4-anchor-h-align:right;');
    model.refresh();
    const before = model.serialize();
    const outside = outsideObject(model.document, 'img2', [
      '-d4-anchor-page', '-d4-anchor-section', '-d4-anchor-h-align', '-d4-anchor-v-align', '-d4-anchor-layout', 'z-index',
    ]);
    model.setObjectPlacement({ section: '2', page: 'all', hAlign: 'offset', vAlign: 'offset', layout: 'wrap-square' });
    expect(model.scopeRoot.getAttribute('style')).toBe('/* retained native metadata */width: 48pt;');
    expect(model.objectState().geometryReason).toBeNull();
    expect(model.objectPlacement().values).toEqual({ section: '2', page: 'all', hAlign: 'offset', vAlign: 'offset', layout: 'wrap-square' });
    expect(outsideObject(model.document, 'img2', [
      '-d4-anchor-page', '-d4-anchor-section', '-d4-anchor-h-align', '-d4-anchor-v-align', '-d4-anchor-layout', 'z-index',
    ])).toBe(outside);
    model.setObjectGeometry({ x: '12pt', y: '24pt' });
    model.undo(); model.undo();
    expect(model.serialize()).toBe(before);
    model.setScope('object:textBox2');
    model.setObjectPlacement({ hAlign: 'offset', vAlign: 'offset', layout: 'behind' });
    expect(model.objectState().values['z-index']).toBe('-1');
    expect(model.scopeRoot.hasAttribute('style')).toBe(false);
    model.setObjectPlacement({ layout: 'front' });
    expect(model.objectState().values['z-index']).toBeUndefined();
  });

  it('rejects invalid targets and preserves unsupported, formula-bearing and referenced objects', () => {
    const model = lifecycleFixture('box');
    model.setScope('object:textBox2');
    const before = model.serialize();
    for (const changes of [{ page: '0' }, { page: 'NaN' }, { page: '10001' }, { page: '2', section: '2' },
      { section: '3', page: 'all' }, { hAlign: 'left' }, { layout: 'wrap-tight' }, { extra: '1' }]) {
      expect(() => model.setObjectPlacement(changes)).toThrow('objectPlacementInvalid');
      expect(model.serialize()).toBe(before);
    }
    for (const text of ['a\nb', '\u0000', '\uD800', 'a'.repeat(10001)]) {
      expect(() => model.createObject('textBox', text)).toThrow('objectTextInvalid');
      expect(model.serialize()).toBe(before);
    }
    for (const source of ['https://example.test/x.png', 'data:image/png;base64,AAAA']) {
      expect(() => model.createObject('anchoredPicture', source)).toThrow();
      expect(model.serialize()).toBe(before);
    }
    model.setScope('object:textBox1');
    expect(() => model.deleteObject()).toThrow('objectDeleteProtected');
    model.setScope('object:textBox2');
    model.document.querySelector('body > p').setAttribute('data-native-ref', 'textBox2');
    expect(() => model.deleteObject()).toThrow('objectDeleteProtected');
    expect(model.scopeRoot.isConnected).toBe(true);
    model.scopeRoot.setAttribute('data-unknown', 'retain');
    expect(() => model.deleteObject()).toThrow('objectProtected');
  });

  it('rejects unsafe cascades and never reuses IDs mentioned in opaque metadata', () => {
    const model = lifecycleFixture('original');
    model.document.querySelector('head').append(model.document.createComment('native reference textBox9'));
    model.createObject('textBox');
    expect(model.scope).toBe('object:textBox10');
    model.document.querySelector('head style').textContent += 'div{width:7pt}';
    model.refresh();
    const before = model.serialize();
    expect(() => model.createObject('textBox')).toThrow('objectProtected');
    expect(model.serialize()).toBe(before);
    expect(() => model.deleteObject()).toThrow('objectProtected');
  });

  it('uses the actual unique owned class after native layering renumbers CSS without renaming IDs', () => {
    const model = WriteProDocument.open(new Uint8Array(readFileSync('tests/fixtures/media/object-section-layoutSwap.4wp')));
    model.setScope('object:textBox2');
    expect(model.scopeRoot.getAttribute('class')).toBe('_div1');
    expect(model.objectPlacement().reason).toBeNull();
    const retained = outsideObject(model.document, 'textBox2', [
      '-d4-anchor-page', '-d4-anchor-section', '-d4-anchor-h-align', '-d4-anchor-v-align', '-d4-anchor-layout', 'z-index',
    ]);
    model.setObjectPlacement({ layout: 'front' });
    expect(outsideObject(model.document, 'textBox2', [
      '-d4-anchor-page', '-d4-anchor-section', '-d4-anchor-h-align', '-d4-anchor-v-align', '-d4-anchor-layout', 'z-index',
    ])).toBe(retained);
    model.setObjectGeometry({ width: '210pt' });
    expect(model.objectState().geometry.width).toBe('210pt');
    expect(model.objectState('object:textBox1').values.width).toBe('8cm');
  });
});

describe('native media preservation', () => {
  it('extracts only the bounded single-codec native wrapper and retains its exact source', () => {
    const model = fixture('wrapper');
    const picture = model.document.querySelector('img');
    const source = picture.getAttribute('src');
    const info = model.imageInfo(picture);
    expect(info).toMatchObject({ wrapped: true, type: 'png', width: 48, height: 32 });
    expect(info.src).not.toContain('application/4DPicture');
    const before = model.serialize();
    model.setScope('object:img1');
    expect(render(model).querySelector('img').src).toBe(info.src);
    model.setObjectGeometry({ width: '111.125pt', height: '72.25pt' });
    expect(picture.getAttribute('src')).toBe(source);
    expect(model.serialize()).not.toBe(before);
    model.undo();
    expect(model.serialize()).toBe(before);
    const bytes = Uint8Array.from(atob(source.split(',')[1]), char => char.charCodeAt(0));
    for (const index of [4, 8, 12, 16, 20, 24, 28, bytes.length - 131 - 8]) {
      const corrupt = bytes.slice();
      corrupt[index] ^= 0x7f;
      const result = mediaSource(`data:application/4DPicture;base64,${btoa(String.fromCharCode(...corrupt))}`, {}, 'Doc.html');
      expect(result.src).toBeNull();
      expect(result.reason).toMatch(/^media/);
    }
    expect(mediaSource('data:application/4DPicture;base64,' + btoa('TCP4' + String.fromCharCode(...bytes.slice(-131))), {}, 'Doc.html').src).toBeNull();
  });

  it('isolates text-box edits, formatting, geometry, undo and recovery from body ranges and all other objects', () => {
    const model = fixture('paper');
    expect(model.readOnly).toBe(true);
    expect(model.objectState('object:textBox1').reason).toBeNull();
    model.setScope('object:textBox1');
    const before = model.serialize();
    const outside = outsideObject(model.document, 'textBox1');
    render(model);
    model.replaceText(selection(0, 3), 'EDITé');
    render(model);
    model.formatSelection(selection(0, 5), 'font-weight', 'bold');
    expect(outsideObject(model.document, 'textBox1')).toBe(outside);
    expect(model.scopeRoot.textContent).toBe('EDITé 😀 日é');
    expect(model.scopeRoot.querySelector('[style*="bold"]')).not.toBeNull();
    const text = model.scopeRoot.innerHTML;
    const outsideGeometry = outsideObject(model.document, 'textBox1', true);
    model.setObjectGeometry({ width: '210.125pt', height: '100.25pt', x: '30.5pt', y: '40.75pt' });
    expect(model.scopeRoot.innerHTML).toBe(text);
    expect(model.objectState().geometry.width).toBe('210.125pt');
    expect(model.scopeRoot.hasAttribute('style')).toBe(false);
    expect(outsideObject(model.document, 'textBox1', true)).toBe(outsideGeometry);
    const after = model.serialize();
    let recovered = WriteProDocument.unpack(model.pack());
    recovered.undo();
    recovered = WriteProDocument.unpack(recovered.pack());
    recovered.undo(true);
    expect(recovered.serialize()).toBe(after);
    expect(recovered.scope).toBe('object:textBox1');
    recovered.undo(); recovered.undo(); recovered.undo();
    expect(recovered.serialize()).toBe(before);
  });

  it('preserves immutable formulas and protects nested images, identity-bearing content and unknown anchors', () => {
    const formula = fixture('formula');
    formula.setScope('object:textBox1');
    render(formula);
    const object = formula.scopeRoot.querySelector('span').outerHTML;
    formula.editRun(0, 'CHANGED');
    expect(formula.scopeRoot.querySelector('span').outerHTML).toBe(object);
    const before = formula.serialize();
    expect(() => formula.mutate('typing', () => formula.scopeRoot.querySelector('span').remove())).toThrow('protected');
    expect(formula.serialize()).toBe(before);
    formula.setScope('object:img1');
    expect(formula.objectState().reason).toBe('objectProtected');
    expect(() => formula.setObjectGeometry({ width: '100pt' })).toThrow('objectProtected');
    const nested = fixture('nested');
    nested.setScope('object:textBox1');
    expect(nested.editingReadOnly).toBe(true);
    expect(render(nested).querySelector('[contenteditable]')).toBeNull();
    for (const style of ['-d4-anchor-unknown:1', '-d4-anchor-section:99', '-d4-anchor-origin:content-box', 'width:999pt!important',
      'width:calc(10pt + 2%)', '-d4-anchor-h-offset:-1pt', '-d4-img-display-mode:unknown', 'height:5000pt', 'width:10pt',
      '-d4-anchor-h-align:unknown', '-d4-anchor-v-align:unknown', '-d4-anchor-h-align:right', '-d4-anchor-page:2', 'z-index:99']) {
      const model = fixture('paper');
      model.setScope('object:textBox1');
      model.scopeRoot.setAttribute('style', style);
      expect(model.objectState().reason).toBe('objectProtected');
    }
    const identity = fixture('paper');
    identity.document.querySelector('div p').id = 'retained';
    identity.setScope('object:textBox1');
    expect(identity.objectState().reason).toBe('objectProtected');
    const shared = fixture('paper');
    shared.document.querySelector('body > p').classList.add('_div1');
    expect(shared.objectState('object:textBox1').reason).toBe('objectProtected');
    const generic = fixture('paper');
    generic.document.querySelector('head style').textContent += 'div._div10{width:190pt}';
    generic.refresh();
    expect(generic.objectState('object:textBox1').reason).toBeNull();
    generic.document.querySelector('head style').textContent += 'div{width:190pt}';
    generic.refresh();
    expect(generic.objectState('object:textBox1').reason).toBe('objectProtected');
  });

  it('keeps aligned offsets protected but permits independently scoped text edits', () => {
    const model = fixture('aligned');
    model.setScope('object:textBox1');
    expect(model.objectState().geometryReason).toBe('objectAligned');
    const before = model.serialize();
    expect(() => model.setObjectGeometry({ x: '10pt' })).toThrow('objectAligned');
    expect(model.serialize()).toBe(before);
    render(model);
    model.editRun(0, 'ALIGNED TEXT');
    expect(model.scopeRoot.textContent).toBe('ALIGNED TEXT');
  });

  it('rejects invalid geometry and out-of-scope transactions atomically', () => {
    const model = fixture('paper');
    model.setScope('object:textBox1');
    const before = model.serialize();
    for (const changes of [{ width: '0pt' }, { y: '-1pt' }, { x: '1201pt' }, { width: 'NaNpt' }, { z: '1pt' }]) {
      expect(() => model.setObjectGeometry(changes)).toThrow('objectInvalid');
      expect(model.serialize()).toBe(before);
    }
    expect(() => model.mutate('typing', () => { model.document.querySelector('body > p').textContent = 'BAD'; })).toThrow('objectProtected');
    expect(() => model.mutate('objectGeometry', () => model.scopeRoot.setAttribute('style', 'padding:50pt'))).toThrow('objectProtected');
    expect(model.serialize()).toBe(before);
    expect(model.undoStack).toHaveLength(0);
    model.setObjectGeometry({ width: '180pt' });
    expect(model.undoStack).toHaveLength(0);
    const style = model.document.querySelector('head style');
    const retained = 'padding:4pt;/* native metadata */\n  ';
    style.textContent = style.textContent.replace('padding:4pt;', retained);
    model.refresh();
    model.setObjectGeometry({ width: '210.125pt', height: '100.25pt' });
    expect(style.textContent).toContain(retained);
  });

  it('prints supported objects once as an inert appendix without mutating editor scope or mappings', () => {
    const model = fixture('paper');
    model.setScope('object:textBox1');
    render(model);
    const before = model.serialize(), runs = [...model.runs], projection = model.projection;
    const { root } = createPrintProjection(model, messages.en);
    expect(root.querySelector('.object-appendix').textContent).toContain('BOX 😀 日é');
    expect(root.querySelector('.object-appendix img').src).toMatch(/^data:image\/png/);
    expect(root.querySelector('.object-appendix').textContent).toContain(messages.en.objectHelp);
    expect(root.querySelector('[contenteditable], [src^="http"],script,iframe')).toBeNull();
    expect(model.serialize()).toBe(before);
    expect(model.scope).toBe('object:textBox1');
    expect(model.runs).toEqual(runs);
    expect(model.projection).toBe(projection);
  });

  it('rejects missing, external, active, oversized and truncated media with an explicit reason', () => {
    const model = fixture('paper');
    const source = model.document.querySelector('img').getAttribute('src');
    const png = Uint8Array.from(atob(source.split(',')[1]), char => char.charCodeAt(0));
    const files = { 'Book/assets/photo.png': png };
    expect(mediaSource('assets/photo.png', files, 'Book/Doc.html').src).toBe(source);
    for (const src of ['https://example.test/x', '//example.test/x', 'data:image/svg+xml;base64,PHN2Zy8+', 'missing.png',
      'data:image/png;base64,AAAA', source.slice(0, -4)]) {
      const info = mediaSource(src, files, 'Book/Doc.html');
      expect(info.src).toBeNull();
      expect(info.reason).toMatch(/^media/);
    }
    const huge = png.slice();
    new DataView(huge.buffer).setUint32(16, 4000000);
    expect(mediaSource('huge.png', { 'huge.png': huge }, 'Doc.html').reason).toBe('mediaBudget');
    expect(mediaSource('big.png', { 'big.png': new Uint8Array(8 * 1024 * 1024 + 1) }, 'Doc.html').reason).toBe('mediaBudget');
  });

  it('admits bounded static GIF/WebP but rejects animation and truncated containers', () => {
    const gif = Uint8Array.from(atob('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'), char => char.charCodeAt(0));
    const webp = Uint8Array.from(atob('UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA'), char => char.charCodeAt(0));
    for (const [type, bytes] of [['gif', gif], ['webp', webp]]) {
      expect(mediaSource(`image.${type}`, { [`image.${type}`]: bytes }, 'Doc.html')).toMatchObject({ type, width: 1, height: 1 });
      expect(mediaSource('truncated', { truncated: bytes.slice(0, -1) }, 'Doc.html').reason).toBe('mediaMalformed');
    }
    const animated = Uint8Array.from([...gif.slice(0, -1), ...gif.slice(gif.indexOf(0x2c))]);
    expect(mediaSource('animated', { animated }, 'Doc.html').reason).toBe('mediaUnsupported');
    const animatedWebp = webp.slice();
    animatedWebp.set(new TextEncoder().encode('ANIM'), 12);
    expect(mediaSource('animated', { animated: animatedWebp }, 'Doc.html').reason).toBe('mediaUnsupported');
    const losslessJpeg = Uint8Array.of(255, 216, 255, 195, 0, 11, 8, 0, 1, 0, 1, 1, 1, 17, 0, 255, 217);
    expect(mediaSource('lossless', { lossless: losslessJpeg }, 'Doc.html').reason).toBe('mediaUnsupported');
  });

  it('enforces cumulative unique-source and decoded-pixel budgets before projecting more images', () => {
    const model = fixture('paper');
    const gif = 'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
    const image = document.createElement('img');
    model.resourceCache.clear();
    for (let index = 0; index < 129; index++) {
      image.setAttribute('src', `data:image/gif;base64,${' '.repeat(index)}${gif}`);
      const info = model.imageInfo(image);
      if (index < 128) expect(info.src).not.toBeNull();
      else expect(info).toEqual({ src: null, reason: 'mediaBudget' });
    }
    expect(model.imageInfo(image)).toEqual({ src: null, reason: 'mediaBudget' });
    const canvas = Uint8Array.from(atob(gif), char => char.charCodeAt(0));
    const view = new DataView(canvas.buffer);
    view.setUint16(6, 10000, true);
    view.setUint16(8, 4000, true);
    model.resourceCache.clear();
    for (let index = 0; index < 3; index++) {
      image.setAttribute('src', `data:image/gif;base64,${' '.repeat(index)}${btoa(String.fromCharCode(...canvas))}`);
      const info = model.imageInfo(image);
      if (index < 2) expect(info).toMatchObject({ width: 10000, height: 4000 });
      else expect(info).toEqual({ src: null, reason: 'mediaBudget' });
    }
    model.resourceCache.clear();
    for (let index = 0; index < 512; index++) {
      image.setAttribute('src', `https://invalid.example/${index}`);
      expect(model.imageInfo(image).reason).toBe('mediaUnsupported');
    }
    image.setAttribute('src', `data:image/gif;base64,${gif}`);
    expect(model.imageInfo(image)).toEqual({ src: null, reason: 'mediaBudget' });
  });
});
