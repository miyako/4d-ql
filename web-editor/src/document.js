import * as css from 'css-tree';
import { DocumentError, readArchive, writeArchive } from './archive.js';

const XHTML = 'http://www.w3.org/1999/xhtml';
const SAFE_TAGS = new Set(['p', 'li', 'ul', 'ol', 'span', 'a', 'br', 'table', 'tbody', 'thead', 'tfoot', 'tr', 'td', 'th', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup', 'div']);
const SAFE_PROPERTIES = /^(color|background-color|font-(family|size|weight|style|variant)|text-(align|decoration|indent|transform|shadow)|line-height|letter-spacing|word-spacing|white-space|direction|vertical-align|list-style-type|border(-(color|style|width|radius|collapse|spacing))?|padding(-(top|right|bottom|left))?|margin(-(top|right|bottom|left))?|width|height|min-height)$/;
const SAFE_VALUE = /^[#(),.%\w\s'"+/-]+$/u;
const FORMAT = new Set(['font-weight', 'font-style', 'text-decoration', 'font-size', 'font-family', 'color']);

function parse(source) {
  if (/<!DOCTYPE|<!ENTITY/i.test(source)) throw new DocumentError('invalidDocument');
  const document = new DOMParser().parseFromString(source, 'application/xhtml+xml');
  if (document.querySelector('parsererror') || document.documentElement.localName !== 'html' ||
    document.documentElement.namespaceURI !== XHTML ||
    !document.querySelector('head') || !document.querySelector('body') ||
    document.getElementsByTagName('*').length > 20000) throw new DocumentError('invalidDocument');
  let count = 0;
  function depth(node, level) {
    if (level > 64 || ++count > 60000) throw new DocumentError('tooLarge');
    for (const child of node.childNodes) depth(child, level + 1);
  }
  depth(document.documentElement, 0);
  return document;
}

function declarations(source) {
  const result = {};
  try {
    const ast = css.parse(source, { context: 'declarationList' });
    ast.children.forEach(node => {
      if (node.type === 'Declaration') result[node.property.toLowerCase()] = css.generate(node.value);
    });
  } catch {
    // Unrecognized CSS remains in the source, but is never projected into the UI.
  }
  return result;
}

function rules(document) {
  const result = [];
  for (const element of document.querySelectorAll('head style')) {
    try {
      const ast = css.parse(element.textContent);
      ast.children.forEach(rule => {
        if (rule.type !== 'Rule') return;
        const selectors = css.generate(rule.prelude).split(',');
        for (const selector of selectors) {
          if (!/^[a-z][a-z0-9]*(?:\.[\w-]+)*$/i.test(selector)) continue;
          result.push({
            selector,
            specificity: selector.split('.').length - 1,
            values: declarations(css.generate(rule.block).slice(1, -1)),
          });
        }
      });
    } catch {
      // Unsupported stylesheet syntax is preserved, not executed.
    }
  }
  return result.sort((a, b) => a.specificity - b.specificity);
}

function setProperty(element, property, value) {
  // CSSOM would discard the native -d4-* declarations.
  const existing = element.getAttribute('style') || '';
  element.setAttribute('style', `${existing}${existing ? ';' : ''}${property}:${value}`);
}

export class WriteProDocument {
  constructor(source, files = {}, entry = 'Document.html', original = null) {
    this.document = parse(source);
    this.files = files;
    this.entry = entry;
    this.original = original;
    this.initial = this.serialize();
    this.undoStack = [];
    this.redoStack = [];
    this.refresh();
  }

  static open(bytes) {
    const files = readArchive(bytes);
    const entries = Object.keys(files).filter(name => /\.x?html$/i.test(name));
    if (entries.length !== 1) throw new DocumentError('ambiguousDocument');
    let source;
    try {
      source = new TextDecoder('utf-8', { fatal: true }).decode(files[entries[0]]);
    } catch {
      throw new DocumentError('invalidDocument');
    }
    return new WriteProDocument(source, files, entries[0], bytes.slice());
  }

  static create(title = 'Untitled') {
    const model = new WriteProDocument(`<html xmlns="${XHTML}" xmlns:d4="http://www.4D.com"><head><title/><meta name="datetimeCreation" content="${new Date().toISOString()}"/><style type="text/css">body { -d4-version:2.20;background-color:#FFFFFF }p,li { white-space:pre-wrap;margin:0pt;padding:0pt;font-family:Arial;font-size:12pt }p.Normal,li.Normal { white-space:pre-wrap }</style></head><body><p class="Normal">\u200b</p></body></html>`);
    model.document.querySelector('title').textContent = title;
    model.initial = model.serialize();
    return model;
  }

  refresh() {
    this.styles = rules(this.document);
    this.readOnly = [...this.document.querySelectorAll('meta')].some(meta =>
      ['bookmarks', 'ranges'].includes((meta.getAttribute('name') || '').toLowerCase()) &&
      !['', '{}', '[]'].includes((meta.getAttribute('content') || '').trim()));
    this.runs = [];
    this.blocks = [];
  }

  get title() { return this.document.querySelector('title')?.textContent || 'Document'; }
  get dirty() { return this.serialize() !== this.initial; }
  serialize() { return new XMLSerializer().serializeToString(this.document); }

  values(element) {
    const values = {};
    for (const rule of this.styles) if (element.matches(rule.selector)) Object.assign(values, rule.values);
    return Object.assign(values, declarations(element.getAttribute('style') || ''));
  }

  protected(element) {
    for (let current = element; current?.nodeType === 1; current = current.parentElement) {
      const values = this.values(current);
      if (current.namespaceURI !== XHTML || !SAFE_TAGS.has(current.localName) && current.localName !== 'body' ||
        values['-d4-protected'] === 'true' || Object.keys(values).some(key => /^-d4-(ref|anchor)/.test(key)) ||
        /section\d.*(Header|Footer)/i.test(current.getAttribute('class') || '') ||
        ['hidden', 'collapse'].includes(values.visibility) || values.display === 'none') return true;
      if (current.localName === 'body') break;
    }
    return this.readOnly;
  }

  checkpoint() {
    this.undoStack.push(this.serialize());
    let length = this.undoStack.reduce((sum, item) => sum + item.length, 0);
    while (this.undoStack.length > 1 && (this.undoStack.length > 100 || length > 4 * 1024 * 1024)) {
      length -= this.undoStack.shift().length;
    }
    this.redoStack = [];
  }

  undo(redo = false) {
    const from = redo ? this.redoStack : this.undoStack;
    const to = redo ? this.undoStack : this.redoStack;
    if (!from.length) return;
    to.push(this.serialize());
    this.document = parse(from.pop());
    this.refresh();
  }

  editRun(index, value) {
    const node = this.runs[index];
    if (!node || this.protected(node.parentElement)) throw new DocumentError('protected');
    if (node.data === value) return;
    this.checkpoint();
    node.data = value;
    if (/[\r\n]/.test(value)) {
      const fragment = this.document.createDocumentFragment();
      let last;
      value.replace(/\r\n?/g, '\n').split('\n').forEach((piece, index) => {
        if (index) fragment.append(this.document.createElementNS(XHTML, 'br'));
        last = this.document.createTextNode(piece);
        fragment.append(last);
      });
      node.replaceWith(fragment);
      return last;
    }
  }

  formatRun(index, property, value, start = 0, end = null) {
    const node = this.runs[index];
    if (!node || this.protected(node.parentElement)) throw new DocumentError('protected');
    if (!FORMAT.has(property) || !SAFE_VALUE.test(value) || /url|expression|var\(/i.test(value)) throw new DocumentError('invalidDocument');
    end ??= node.length;
    if (start < 0 || end > node.length || start >= end) return;
    this.checkpoint();
    const selected = node.splitText(start);
    const tail = selected.splitText(end - start);
    const span = this.document.createElementNS(XHTML, 'span');
    setProperty(span, property, value);
    selected.replaceWith(span);
    span.append(selected);
    if (!node.data) node.remove();
    if (!tail.data) tail.remove();
    return selected;
  }

  alignBlock(index, alignment) {
    const block = this.blocks[index];
    if (!block || this.protected(block) || !['left', 'center', 'right', 'justify'].includes(alignment)) throw new DocumentError('protected');
    this.checkpoint();
    setProperty(block, 'text-align', alignment);
  }

  addParagraph(index = null) {
    if (this.readOnly) throw new DocumentError('protected');
    const after = this.blocks[index];
    if (after && (after.parentElement.localName !== 'body' || this.protected(after))) throw new DocumentError('protected');
    this.checkpoint();
    const paragraph = this.document.createElementNS(XHTML, 'p');
    paragraph.setAttribute('class', 'Normal');
    paragraph.textContent = '\u200b';
    if (after) after.after(paragraph);
    else this.document.querySelector('body').append(paragraph);
  }

  export() {
    if (!this.dirty && this.original) return this.original.slice();
    const copy = parse(this.serialize());
    let modified = [...copy.querySelectorAll('meta')].find(meta => meta.getAttribute('name') === 'datetimeModified');
    if (!modified) {
      modified = copy.createElementNS(XHTML, 'meta');
      modified.setAttribute('name', 'datetimeModified');
      copy.querySelector('head').append(modified);
    }
    modified.setAttribute('content', new Date().toISOString());
    return writeArchive(this.files, this.entry, '\ufeff' + new XMLSerializer().serializeToString(copy));
  }

  render(host, labels) {
    host.replaceChildren();
    this.runs = [];
    this.blocks = [];
    const body = this.document.querySelector('body');
    const project = (source, target, locked = false, inBlock = false, decoration = '') => {
      for (const child of source.childNodes) {
        if (child.nodeType === 3) {
          if (!inBlock) {
            target.append(document.createTextNode(child.data));
            continue;
          }
          const run = document.createElement('span');
          const index = this.runs.push(child) - 1;
          run.dataset.run = index;
          run.className = 'text-run';
          run.textContent = child.data;
          if (decoration) run.style.textDecoration = decoration;
          if (!locked && !this.readOnly) {
            run.setAttribute('contenteditable', 'plaintext-only');
            run.setAttribute('role', 'textbox');
            run.setAttribute('aria-label', labels.editText);
            run.spellcheck = true;
            run.tabIndex = 0;
            if (!child.data || child.data === '\u200b') run.dataset.empty = '';
          }
          target.append(run);
          continue;
        }
        if (child.nodeType !== 1) continue;
        const tag = child.localName;
        const values = this.values(child);
        const hidden = values.display === 'none' || values.visibility === 'hidden' ||
          /section\d.*(Header|Footer)/i.test(child.getAttribute('class') || '');
        if (hidden) {
          const badge = document.createElement('div');
          badge.className = 'preserved-object';
          badge.textContent = labels.preserved;
          target.append(badge);
          continue;
        }
        const native = Object.keys(values).some(key => /^-d4-(ref|anchor)/.test(key));
        if (native || tag === 'img' || !SAFE_TAGS.has(tag) || child.namespaceURI !== XHTML) {
          const badge = document.createElement('span');
          badge.className = 'preserved-object';
          badge.textContent = tag === 'img' ? labels.image : labels.preserved;
          if (tag === 'img' && !native) {
            const src = child.getAttribute('src') || '';
            if (/^data:image\/(?:png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(src)) {
              const image = document.createElement('img');
              image.src = src;
              image.alt = child.getAttribute('alt') || labels.image;
              image.loading = 'lazy';
              badge.replaceChildren(image);
            }
          }
          target.append(badge);
          continue;
        }
        const element = document.createElement(tag === 'a' ? 'span' : tag);
        for (const [property, value] of Object.entries(values)) {
          if (property !== 'text-decoration' && SAFE_PROPERTIES.test(property) && SAFE_VALUE.test(value) && value.length < 200 &&
            !/url|expression|var\(|!important/i.test(value)) element.style.setProperty(property, value);
        }
        for (const attr of ['rowspan', 'colspan', 'start']) {
          const value = child.getAttribute(attr);
          if (/^\d{1,3}$/.test(value || '')) element.setAttribute(attr, value);
        }
        const isBlock = ['p', 'li'].includes(tag);
        if (isBlock) element.dataset.block = this.blocks.push(child) - 1;
        const isLocked = locked || this.protected(child);
        if (isLocked) element.classList.add('locked-content');
        if (tag === 'a') element.classList.add('inert-link');
        const nextDecoration = values['text-decoration'];
        const safeDecoration = nextDecoration && SAFE_VALUE.test(nextDecoration) && nextDecoration.length < 100;
        project(child, element, isLocked, inBlock || isBlock, safeDecoration ? nextDecoration : decoration);
        target.append(element);
      }
    };
    project(body, host);
  }
}
