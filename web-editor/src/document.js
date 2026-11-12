import * as css from 'css-tree';
import { DocumentError, MAX_ARCHIVE, MAX_EXPANDED, readArchive, writeArchive } from './archive.js';
import { nativeBody, nativeBoundary, nativeMetadata, spliceBookmarks, writeBookmarks } from './native-ranges.js';

const XHTML = 'http://www.w3.org/1999/xhtml';
const SAFE_TAGS = new Set(['p', 'li', 'ul', 'ol', 'span', 'a', 'br', 'img', 'table', 'tbody', 'thead', 'tfoot', 'tr', 'td', 'th', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup', 'div']);
const SAFE_PROPERTIES = /^(color|background-color|font-(family|size|weight|style|variant)|text-(align|decoration|indent|transform|shadow)|line-height|letter-spacing|word-spacing|white-space|direction|vertical-align|list-style-type|border(-(color|style|width|radius|collapse|spacing))?|padding(-(top|right|bottom|left))?|margin(-(top|right|bottom|left))?|width|height|min-height)$/;
const SAFE_VALUE = /^[#(),.%\w\s'"+/-]+$/u;
const FORMAT = new Set(['font-weight', 'font-style', 'text-decoration', 'font-size', 'font-family', 'color', 'background-color']);
const INLINE_TAGS = new Set(['span', 'a', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup']);
const BUILTIN_STYLES = {
  Normal: 'font-family:Arial;font-size:12pt;font-weight:normal;font-style:normal',
  Heading_1: 'font-family:Arial;font-size:24pt;font-weight:bold;margin:16pt 0pt 10pt',
  Heading_2: 'font-family:Arial;font-size:16pt;font-weight:bold;margin:12pt 0pt 8pt',
  Quote: 'font-style:italic;margin:12pt 0pt 12pt 18pt',
};

function linkURL(value) {
  if (typeof value !== 'string' || value.length > 2048 || /[\u0000-\u0020]/.test(value)) return null;
  try {
    const url = new URL(value);
    return ['https:', 'http:', 'mailto:'].includes(url.protocol) && !url.username && !url.password ? url.href : null;
  } catch { return null; }
}

function validBookmark(value) {
  if (value === null) return true;
  const point = saved => saved && Array.isArray(saved.path) && saved.path.length <= 64 &&
    saved.path.every(index => Number.isInteger(index) && index >= 0 && index < 20000) &&
    Number.isInteger(saved.offset) && saved.offset >= 0 && saved.offset <= MAX_EXPANDED &&
    (saved.empty === undefined || typeof saved.empty === 'boolean') && (saved.atEnd === undefined || typeof saved.atEnd === 'boolean');
  return value && point(value.start) && point(value.end) && typeof value.backward === 'boolean';
}

// Editor-only cursor slots; these are not 4D bookmark character offsets.
function selectionLength(node) {
  return node.nodeType === 3 ? node.length : ['img', 'br'].includes(node.localName) ? 1 : 0;
}

function base64(bytes) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  return btoa(binary);
}

function rasterType(bytes) {
  if (bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71) return 'png';
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'jpeg';
  if (bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 56) return 'gif';
  if (String.fromCharCode(...bytes.subarray(0, 4)) === 'RIFF' && String.fromCharCode(...bytes.subarray(8, 12)) === 'WEBP') return 'webp';
  return null;
}

function cleanPaste(html, plain, owner) {
  if (html.length + plain.length > 2 * 1024 * 1024) throw new DocumentError('tooLarge');
  const fragment = owner.createDocumentFragment();
  if (!html) {
    plain.replace(/\r\n?/g, '\n').split('\n').forEach(line => {
      const paragraph = owner.createElementNS(XHTML, 'p');
      paragraph.textContent = line;
      fragment.append(paragraph);
    });
    return fragment;
  }
  const template = document.createElement('template');
  template.innerHTML = html;
  let count = 0;
  function copy(source, target, level = 0) {
    if (++count > 5000 || level > 32) throw new DocumentError('tooLarge');
    for (const child of source.childNodes) {
      if (child.nodeType === 3) target.append(owner.createTextNode(child.data));
      else if (child.nodeType === 1) {
        const tag = child.localName.toLowerCase();
        if (['script', 'style', 'iframe', 'object', 'svg', 'math', 'img', 'link', 'meta'].includes(tag)) continue;
        if (tag === 'div' && child.querySelector('p,div,ul,ol,h1,h2,h3')) { copy(child, target, level + 1); continue; }
        const href = tag === 'a' ? linkURL(child.getAttribute('href')) : null;
        let mapped = { div: 'p', h1: 'p', h2: 'p', h3: 'p', b: 'span', strong: 'span', i: 'span', em: 'span', u: 'span', s: 'span', a: href ? 'a' : 'span' }[tag] || tag;
        if (mapped === 'p' && target.localName === 'li') {
          if (target.childNodes.length) target.append(owner.createElementNS(XHTML, 'br'));
          mapped = 'span';
        }
        if (!['p', 'span', 'a', 'br', 'ul', 'ol', 'li', 'sub', 'sup'].includes(mapped)) { copy(child, target, level + 1); continue; }
        const element = owner.createElementNS(XHTML, mapped);
        if (href) element.setAttribute('href', href);
        const styles = declarations(child.getAttribute('style') || '');
        if (['b', 'strong', 'h1', 'h2', 'h3'].includes(tag)) styles['font-weight'] = 'bold';
        if (['i', 'em'].includes(tag)) styles['font-style'] = 'italic';
        if (tag === 'u') styles['text-decoration'] = 'underline';
        if (tag === 's') styles['text-decoration'] = 'line-through';
        for (const [key, value] of Object.entries(styles)) {
          if ((FORMAT.has(key) || key === 'text-align') && SAFE_VALUE.test(value) && value.length < 200 &&
            !/url|expression|var\(/i.test(value)) setProperty(element, key, value);
        }
        copy(child, element, level + 1);
        target.append(element);
      }
    }
  }
  copy(template.content, fragment);
  return fragment;
}

function parse(source) {
  if (source.length > MAX_EXPANDED || new TextEncoder().encode(source).length > MAX_EXPANDED) throw new DocumentError('tooLarge');
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
    this.undoLabels = [];
    this.redoLabels = [];
    this.undoSelections = [];
    this.redoSelections = [];
    this.selection = null;
    this.resourceCache = new Map();
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
    this.readOnly = false;
    this.hasBookmarks = false;
    try {
      const { bookmarks } = nativeMetadata(this.document);
      this.hasBookmarks = Object.keys(bookmarks).length > 0;
      if (this.hasBookmarks) {
        const body = this.nativeView();
        if (!body.supports(bookmarks) || Object.values(bookmarks).some(pair => !pair.every(offset => nativeBoundary(body.text, offset)))) throw new DocumentError('protected');
      }
    } catch (error) {
      if (!(error instanceof DocumentError) || error.code !== 'protected') throw error;
      this.readOnly = true;
    }
    this.runs = [];
    this.blocks = [];
    this.images = [];
    this.cells = [];
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

  checkpoint(label = 'edit', group = null, snapshot = this.serialize()) {
    const now = Date.now();
    if (group && this.group === group && now - this.groupTime < 1200) {
      this.groupTime = now;
      this.redoStack = [];
      this.redoLabels = [];
      this.redoSelections = [];
      return;
    }
    this.group = group;
    this.groupTime = now;
    this.undoStack.push(snapshot);
    this.undoLabels.push(label);
    this.undoSelections.push(this.selection);
    let length = this.undoStack.reduce((sum, item) => sum + item.length, 0);
    while (this.undoStack.length > 1 && (this.undoStack.length > 100 || length > 4 * 1024 * 1024)) {
      length -= this.undoStack.shift().length;
      this.undoLabels.shift();
      this.undoSelections.shift();
    }
    this.redoStack = [];
    this.redoLabels = [];
    this.redoSelections = [];
  }

  endGroup() { this.group = null; }

  mutate(label, change, group = null, restore = false) {
    const before = this.serialize();
    try {
      if (!restore && this.readOnly) throw new DocumentError('protected');
      const metadata = restore ? { bookmarks: {} } : nativeMetadata(this.document);
      const tracked = !restore && Object.keys(metadata.bookmarks).length > 0;
      this.nativeTransaction = tracked ? {
        text: this.nativeView().text,
        bookmarks: metadata.bookmarks, meta: metadata.meta,
      } : null;
      const result = change();
      if (tracked) {
        const body = this.nativeView();
        if (body.text !== this.nativeTransaction.text ||
          !body.supports(this.nativeTransaction.bookmarks) ||
          JSON.stringify(nativeMetadata(this.document).bookmarks) !== JSON.stringify(this.nativeTransaction.bookmarks)) throw new DocumentError('protected');
      }
      const after = this.serialize();
      const hasBookmarks = restore ? this.hasBookmarks : Object.keys(nativeMetadata(this.document).bookmarks).length > 0;
      if (!restore && !tracked && hasBookmarks) throw new DocumentError('protected');
      if (after !== before) {
        parse(after);
        const resources = Object.entries(this.files).reduce((sum, [name, bytes]) => sum + (name === this.entry ? 0 : bytes.length), 0);
        if (new TextEncoder().encode(after).length + resources + 256 > MAX_EXPANDED) throw new DocumentError('tooLarge');
        this.checkpoint(label, group, before);
      }
      this.hasBookmarks = hasBookmarks;
      return result;
    } catch (error) {
      this.document = parse(before);
      this.refresh();
      throw error;
    } finally {
      this.nativeTransaction = null;
      this.nativeDepth = false;
    }
  }

  nativeView() {
    return nativeBody(this.document, element => this.values(element), image => this.imageSource(image));
  }

  nativeChange(range, change) {
    const transaction = this.nativeTransaction;
    if (!transaction || this.nativeDepth) return change();
    const body = this.nativeView();
    if (body.text !== transaction.text ||
      JSON.stringify(nativeMetadata(this.document).bookmarks) !== JSON.stringify(transaction.bookmarks)) throw new DocumentError('protected');
    const removals = Array.isArray(range) ? range : null;
    const start = removals ? null : range.startContainer ? body.point(range.startContainer, range.startOffset) : range.start;
    const end = removals ? null : range.endContainer ? body.point(range.endContainer, range.endOffset) : range.end;
    const edits = removals || [{ start, end }];
    if (!edits.length || edits.some((edit, index) => !nativeBoundary(body.text, edit.start) ||
      !nativeBoundary(body.text, edit.end) || edit.end < edit.start ||
      index > 0 && edit.end > edits[index - 1].start)) throw new DocumentError('protected');
    this.nativeDepth = true;
    let result;
    try { result = change(); }
    finally { this.nativeDepth = false; }
    const after = this.nativeView().text;
    if (removals) {
      // Measure column deletion atomically, not its temporarily irregular rows.
      const expected = removals.reduce((text, edit) => text.slice(0, edit.start - 1) + text.slice(edit.end - 1), body.text);
      if (after !== expected) throw new DocumentError('protected');
      for (const edit of removals) transaction.bookmarks = spliceBookmarks(transaction.bookmarks, edit.start, edit.end, 0);
    } else {
      const length = after.length - body.text.length + end - start;
      if (!after.isWellFormed() || length < 0 || after.slice(0, start - 1) !== body.text.slice(0, start - 1) ||
        after.slice(start - 1 + length) !== body.text.slice(end - 1)) throw new DocumentError('protected');
      transaction.bookmarks = spliceBookmarks(transaction.bookmarks, start, end, length);
    }
    transaction.text = after;
    writeBookmarks(transaction.meta, transaction.bookmarks);
    return result;
  }

  nativeOffset(node, atEnd = false) {
    if (!this.nativeTransaction) return 1;
    const body = this.nativeView();
    return node ? body.bounds(node)[atEnd ? 'end' : 'start'] : body.text.length + 1;
  }

  undo(redo = false) {
    const from = redo ? this.redoStack : this.undoStack;
    const to = redo ? this.undoStack : this.redoStack;
    if (!from.length) return;
    this.endGroup();
    const labels = redo ? this.redoLabels : this.undoLabels;
    const selections = redo ? this.redoSelections : this.undoSelections;
    (redo ? this.undoLabels : this.redoLabels).push(labels.pop() || 'edit');
    (redo ? this.undoSelections : this.redoSelections).push(this.selection);
    to.push(this.serialize());
    this.document = parse(from.pop());
    this.selection = selections.pop() || null;
    this.refresh();
    return this.selection ? { selection: this.selection } : null;
  }

  rememberSelection(selection) {
    const point = (index, offset) => {
      const node = this.runs[index];
      const block = node.parentElement.closest('p,li');
      const walker = this.document.createTreeWalker(block, 5);
      let position = offset;
      while (walker.nextNode() && walker.currentNode !== node) position += selectionLength(walker.currentNode);
      const path = [];
      for (let current = block; current.localName !== 'body'; current = current.parentElement) {
        path.unshift([...current.parentElement.children].indexOf(current));
      }
      return { path, offset: position, empty: !node.length, atEnd: node.length > 0 && offset === node.length };
    };
    this.selection = {
      start: point(selection.startRun, selection.start),
      end: point(selection.endRun, selection.end), backward: Boolean(selection.backward),
    };
    return this.selection;
  }

  resolveSelection(bookmark) {
    const point = (saved, forward, preferEmpty = false) => {
      let block = this.document.querySelector('body');
      for (const index of saved.path) block = block?.children[index];
      if (!block || !['p', 'li'].includes(block.localName)) throw new DocumentError('selection');
      const walker = this.document.createTreeWalker(block, 5);
      let offset = 0;
      let last = null;
      let empty = null;
      while (walker.nextNode()) {
        const node = walker.currentNode;
        const index = this.runs.indexOf(node);
        if (index >= 0) {
          if (!node.length && saved.offset === offset) empty = { index, offset: 0 };
          if (node.length || !last) last = { index, offset: node.length };
          if (saved.offset < offset + node.length || !forward && node.length && saved.offset === offset + node.length) {
            return preferEmpty && empty ? empty : { index, offset: Math.max(0, saved.offset - offset) };
          }
        }
        offset += selectionLength(node);
      }
      if (!last) throw new DocumentError('selection');
      return preferEmpty && empty ? empty : last;
    };
    const collapsed = bookmark.start.offset === bookmark.end.offset && JSON.stringify(bookmark.start.path) === JSON.stringify(bookmark.end.path);
    const first = point(bookmark.start, collapsed ? !bookmark.start.atEnd : true, collapsed && bookmark.start.empty);
    const last = collapsed ? first : point(bookmark.end, false);
    return { startRun: first.index, start: first.offset, endRun: last.index, end: last.offset, backward: bookmark.backward };
  }

  editRun(index, value) {
    const node = this.runs[index];
    if (!node || this.protected(node.parentElement)) throw new DocumentError('protected');
    if (node.data === value) return;
    const range = this.document.createRange();
    range.selectNodeContents(node);
    return this.mutate('typing', () => this.nativeChange(range, () => {
      const block = node.parentElement.closest('p,li');
      const emptyParagraph = !value && block && block.textContent === node.data && !block.querySelector('img,br');
      node.data = emptyParagraph ? '\u200b' : value;
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
    }), node);
  }

  formatRun(index, property, value, start = 0, end = null) {
    const node = this.runs[index];
    if (!node || this.protected(node.parentElement)) throw new DocumentError('protected');
    if (!FORMAT.has(property) || !SAFE_VALUE.test(value) || /url|expression|var\(/i.test(value)) throw new DocumentError('invalidDocument');
    end ??= node.length;
    if (start < 0 || end > node.length || start >= end) return;
    return this.formatSelection({ startRun: index, endRun: index, start, end }, property, value)?.node;
  }

  alignBlock(index, alignment) {
    const block = this.blocks[index];
    if (!block || this.protected(block) || !['left', 'center', 'right', 'justify'].includes(alignment)) throw new DocumentError('protected');
    this.mutate('paragraph', () => setProperty(block, 'text-align', alignment));
  }

  addParagraph(index = null) {
    if (this.readOnly) throw new DocumentError('protected');
    const after = this.blocks[index];
    if (after && (after.parentElement.localName !== 'body' || this.protected(after))) throw new DocumentError('protected');
    return this.mutate('paragraph', () => {
      const offset = this.nativeOffset(after, true);
      return this.nativeChange({ start: offset, end: offset }, () => {
        const paragraph = this.document.createElementNS(XHTML, 'p');
        paragraph.setAttribute('class', 'Normal');
        paragraph.textContent = '\u200b';
        if (after) after.after(paragraph);
        else this.document.querySelector('body').append(paragraph);
        return { node: paragraph.firstChild, offset: 0 };
      });
    });
  }

  range(selection) {
    if (!selection) throw new DocumentError('selection');
    const first = this.runs[selection.startRun];
    const last = this.runs[selection.endRun];
    if (!first || !last || selection.start < 0 || selection.end < 0 ||
      selection.start > first.length || selection.end > last.length ||
      selection.startRun > selection.endRun || first === last && selection.start > selection.end) throw new DocumentError('selection');
    const range = this.document.createRange();
    range.setStart(first, selection.start);
    range.setEnd(last, selection.end);
    this.guardRange(range);
    return range;
  }

  guardRange(range) {
    if (this.readOnly) throw new DocumentError('protected');
    for (const element of this.document.querySelectorAll('body *')) {
      if (range.intersectsNode(element) && this.protected(element)) throw new DocumentError('protected');
      if (range.intersectsNode(element) && element.localName === 'img' && !this.imageSource(element)) throw new DocumentError('protected');
    }
  }

  selectedBlocks(selection) {
    const range = this.range(selection);
    return this.blocks.filter(block => range.intersectsNode(block));
  }

  formatSelection(selection, property, value) {
    if (!FORMAT.has(property) || !SAFE_VALUE.test(value) || /url|expression|var\(/i.test(value)) throw new DocumentError('invalidDocument');
    return this.transformSelection(selection, property, () => value);
  }

  decoration(node) {
    for (let current = node.parentElement; current; current = current.parentElement) {
      const value = this.values(current)['text-decoration'];
      if (value !== undefined) return value.match(/\b(?:underline|line-through|overline)\b/g) || [];
    }
    return [];
  }

  decorateSelection(selection, decoration, enabled) {
    if (!['underline', 'line-through'].includes(decoration)) throw new DocumentError('invalidDocument');
    return this.transformSelection(selection, 'text-decoration', node => {
      const values = new Set(this.decoration(node));
      if (enabled) values.add(decoration);
      else values.delete(decoration);
      return [...values].join(' ') || 'none';
    });
  }

  transformSelection(selection, property, valueFor, tag = 'span') {
    const range = this.range(selection);
    const pieces = this.runs.filter(node => range.intersectsNode(node)).map(node => ({
      node, start: node === range.startContainer ? range.startOffset : 0,
      end: node === range.endContainer ? range.endOffset : node.length,
    })).filter(piece => piece.end > piece.start);
    if (!pieces.length && range.collapsed && range.startContainer.nodeType === 3 && !range.startContainer.length) {
      pieces.push({ node: range.startContainer, start: 0, end: 0 });
    }
    return this.mutate(tag === 'a' ? 'link' : 'format', () => {
      let caret;
      for (const { node, start, end } of pieces.reverse()) {
        const value = valueFor(node);
        const selected = end > start ? node.splitText(start) : node;
        const tail = end > start ? selected.splitText(end - start) : null;
        if (end === start) selected.data = '\u200b';
        const span = this.document.createElementNS(XHTML, tag);
        if (tag === 'a') span.setAttribute('href', value);
        else setProperty(span, property, value);
        selected.replaceWith(span);
        span.append(selected);
        if (node !== selected && !node.data) node.remove();
        if (tail && !tail.data) tail.remove();
        caret ??= { node: selected, offset: selected.length };
      }
      return caret;
    });
  }

  setLink(selection, value) {
    const href = linkURL(value);
    if (!href) throw new DocumentError('linkURL');
    const range = this.range(selection);
    const first = this.runs[selection.startRun].parentElement.closest('a');
    const last = this.runs[selection.endRun].parentElement.closest('a');
    if (first && first === last) {
      range.selectNodeContents(first);
      this.guardRange(range);
      return this.mutate('link', () => first.setAttribute('href', href));
    }
    if (range.collapsed || [...this.document.querySelectorAll('a')].some(anchor => range.intersectsNode(anchor))) throw new DocumentError('linkSelection');
    return this.transformSelection(selection, null, () => href, 'a');
  }

  removeLink(selection) {
    const range = this.range(selection);
    const anchors = [...this.document.querySelectorAll('a')].filter(anchor => range.intersectsNode(anchor));
    if (!anchors.length) throw new DocumentError('linkSelection');
    for (const anchor of anchors) {
      range.selectNodeContents(anchor);
      this.guardRange(range);
    }
    this.mutate('link', () => {
      for (const anchor of anchors) {
        const span = this.document.createElementNS(XHTML, 'span');
        for (const attribute of anchor.attributes) if (attribute.name !== 'href') span.setAttributeNS(attribute.namespaceURI, attribute.name, attribute.value);
        span.append(...anchor.childNodes);
        anchor.replaceWith(span);
      }
    });
  }

  structureSafe(block) {
    if (!block || this.protected(block)) throw new DocumentError('protected');
    const values = this.values(block);
    if (values['-d4-section-break-after'] || values['page-break-after'] === 'always' || values['break-after'] === 'column') {
      throw new DocumentError('protected');
    }
    const range = this.document.createRange();
    range.selectNodeContents(block);
    this.guardRange(range);
  }

  replaceRange(range, content) {
    return this.nativeChange(range, () => this.replaceRangeContents(range, content));
  }

  replaceRangeContents(range, content) {
    const blockOf = node => (node.nodeType === 1 ? node : node.parentElement).closest('p,li');
    const first = blockOf(range.startContainer);
    const last = blockOf(range.endContainer);
    if (!first || !last) throw new DocumentError('selection');
    if (first !== last) {
      if (first.parentElement !== last.parentElement || first.localName !== last.localName) throw new DocumentError('structuralSelection');
      const siblings = [...first.parentElement.children];
      for (const block of siblings.slice(siblings.indexOf(first), siblings.indexOf(last) + 1)) {
        if (block.localName !== first.localName) throw new DocumentError('structuralSelection');
        this.structureSafe(block);
      }
    }
    if (range.collapsed && range.startContainer.nodeType === 3 && range.startContainer.data === '\u200b') {
      range.setStart(range.startContainer, 0);
      range.setEnd(range.endContainer, 1);
    }
    range.deleteContents();
    const marker = this.document.createComment('insertion');
    range.insertNode(marker);
    if (first !== last && last.isConnected) {
      first.append(marker);
      first.append(...last.childNodes);
      last.remove();
    }
    const walker = this.document.createTreeWalker(first, 4);
    const empty = [];
    while (walker.nextNode()) if (!walker.currentNode.length) empty.push(walker.currentNode);
    for (const node of empty) node.remove();
    marker.before(content);
    marker.remove();
  }

  replaceText(selection, text, label = 'typing') {
    const range = this.range(selection);
    const fragment = this.document.createDocumentFragment();
    let node;
    text.replace(/\r\n?/g, '\n').split('\n').forEach((line, index) => {
      if (index) fragment.append(this.document.createElementNS(XHTML, 'br'));
      node = this.document.createTextNode(line);
      fragment.append(node);
    });
    return this.mutate(label, () => {
      this.replaceRange(range, fragment);
      return { node, offset: node.length };
    }, label === 'typing' ? this.hasBookmarks ? 'range-typing' : node : null);
  }

  splitParagraph(selection, lineBreak = false) {
    const range = this.range(selection);
    const block = this.runs[selection.startRun].parentElement.closest('p,li');
    this.structureSafe(block);
    if (lineBreak) return this.replaceText(selection, '\n', 'paragraph');
    if (block.localName === 'li' && !block.textContent.replace(/\u200b/g, '').trim() && !block.querySelector('img,br,ul,ol')) {
      const node = this.runs[selection.startRun];
      this.toggleList(this.blocks.indexOf(block), block.parentElement.localName);
      return { node, offset: 0 };
    }
    return this.mutate('paragraph', () => this.nativeChange(range, () => {
      const empty = this.document.createTextNode('');
      this.replaceRange(range, empty);
      const tail = this.document.createRange();
      tail.setStartAfter(empty);
      tail.setEnd(block, block.childNodes.length);
      const next = block.cloneNode(false);
      next.removeAttribute('id');
      const fragment = tail.extractContents();
      for (const element of fragment.querySelectorAll('[id]')) {
        if ([...this.document.querySelectorAll('[id]')].some(other => other.id === element.id)) element.removeAttribute('id');
      }
      next.append(fragment);
      empty.remove();
      if (!block.textContent && !block.querySelector('img,br')) block.textContent = '\u200b';
      if (!next.textContent && !next.querySelector('img,br')) next.textContent = '\u200b';
      block.after(next);
      const walker = this.document.createTreeWalker(next, 4);
      const node = walker.nextNode();
      if (!node) { next.append(this.document.createTextNode('\u200b')); return { node: next.lastChild, offset: 0 }; }
      return { node, offset: 0 };
    }));
  }

  mergeBoundary(index, backward) {
    const node = this.runs[index];
    const block = node?.parentElement.closest('p,li');
    const other = backward ? block?.previousElementSibling : block?.nextElementSibling;
    if (!other || other.localName !== block.localName) return null;
    this.structureSafe(block);
    this.structureSafe(other);
    return this.mutate('paragraph', () => {
      const first = backward ? other : block;
      const last = backward ? block : other;
      const start = this.nativeOffset(first, true);
      const end = this.nativeOffset(last);
      return this.nativeChange({ start, end }, () => {
        const marker = this.document.createTextNode('');
        if (first.textContent === '\u200b' && !first.querySelector('img,br')) first.textContent = '';
        first.append(marker, ...last.childNodes);
        last.remove();
        return { node: marker, offset: 0 };
      });
    });
  }

  deleteInlineBoundary(index, backward) {
    const node = this.runs[index];
    const block = node.parentElement.closest('p,li');
    const neighbors = backward ? this.runs.slice(0, index).reverse() : this.runs.slice(index + 1);
    const other = neighbors.find(candidate => candidate.length || candidate.parentElement.closest('p,li') !== block);
    const sameBlock = other?.parentElement.closest('p,li') === block;
    const gap = this.document.createRange();
    if (backward) {
      gap.setStart(sameBlock ? other : block, sameBlock ? other.length : 0);
      gap.setEnd(node, 0);
    } else {
      gap.setStart(node, node.length);
      gap.setEnd(sameBlock ? other : block, sameBlock ? 0 : block.childNodes.length);
    }
    const objects = [...block.querySelectorAll('img,br')].filter(element => gap.intersectsNode(element));
    const object = backward ? objects.at(-1) : objects[0];
    if (!object) return null;
    this.guardRange(gap);
    return this.mutate('typing', () => {
      const range = this.document.createRange();
      range.selectNode(object);
      return this.nativeChange(range, () => {
        const caret = this.document.createTextNode('');
        object.replaceWith(caret);
        return { node: caret, offset: 0 };
      });
    });
  }

  paste(selection, html, plain) {
    const fragment = cleanPaste(html, plain, this.document);
    const range = this.range(selection);
    const block = this.runs[selection.startRun].parentElement.closest('p,li');
    this.structureSafe(block);
    return this.mutate('paste', () => this.nativeChange(range, () => {
      const marker = this.document.createTextNode('');
      this.replaceRange(range, marker);
      const hasBlocks = [...fragment.children].some(child => ['p', 'ul', 'ol', 'li'].includes(child.localName));
      if (!hasBlocks) {
        marker.before(fragment);
        return { node: marker, offset: 0 };
      }
      const tailRange = this.document.createRange();
      tailRange.setStartAfter(marker);
      tailRange.setEnd(block, block.childNodes.length);
      const tail = tailRange.extractContents();
      const paragraphs = [];
      let inline = null;
      for (const child of [...fragment.childNodes]) {
        if (child.nodeType === 1 && ['p', 'ul', 'ol'].includes(child.localName)) {
          paragraphs.push(child);
          inline = null;
        } else if (child.nodeType !== 3 || child.data.trim() || inline) {
          if (!inline) { inline = this.document.createElementNS(XHTML, 'p'); paragraphs.push(inline); }
          inline.append(child);
        }
      }
      let current = block;
      let container = block;
      paragraphs.forEach((paragraph, index) => {
        if (['ul', 'ol'].includes(paragraph.localName)) {
          if (block.localName === 'li') current.append(paragraph);
          else { current.after(paragraph); current = paragraph; }
          container = paragraph.querySelector('li:last-child') || paragraph;
        } else if (index === 0) {
          if (!block.textContent.replace(/\u200b/g, '').trim()) {
            for (const [property, value] of Object.entries(declarations(paragraph.getAttribute('style') || ''))) setProperty(block, property, value);
          }
          marker.before(...paragraph.childNodes);
          container = block;
        }
        else {
          const next = block.cloneNode(false);
          next.removeAttribute('id');
          for (const attr of paragraph.attributes) next.setAttribute(attr.name, attr.value);
          next.append(...paragraph.childNodes);
          current.after(next);
          current = next;
          container = next;
        }
      });
      marker.remove();
      const caret = this.document.createTextNode('');
      container.append(caret, tail);
      if (paragraphs[0] && ['ul', 'ol'].includes(paragraphs[0].localName) && !block.textContent && !block.querySelector('img,br,ul,ol')) block.remove();
      for (const paragraph of [block, container]) {
        if (!paragraph.textContent && !paragraph.querySelector('img,br')) paragraph.prepend(this.document.createTextNode('\u200b'));
      }
      return { node: caret, offset: 0 };
    }));
  }

  styleNames() {
    return [...new Set([...Object.keys(BUILTIN_STYLES), ...this.styles.map(rule => /^p\.([A-Za-z][\w-]*)$/.exec(rule.selector)?.[1]).filter(Boolean)])];
  }

  styleBlocks(selection, style) {
    const blocks = this.selectedBlocks(selection);
    if (!this.styleNames().includes(style)) throw new DocumentError('invalidDocument');
    return this.mutate('style', () => {
      const names = this.styleNames();
      if (!this.styles.some(rule => rule.selector === `p.${style}`) && BUILTIN_STYLES[style]) {
        const sheet = this.document.createElementNS(XHTML, 'style');
        sheet.setAttribute('type', 'text/css');
        sheet.textContent = `p.${style},li.${style}{${BUILTIN_STYLES[style]}}`;
        this.document.querySelector('head').append(sheet);
      }
      for (const block of blocks) {
        const classes = (block.getAttribute('class') || '').split(/\s+/).filter(name => name && !names.includes(name));
        block.setAttribute('class', [...classes, style].join(' '));
      }
      this.styles = rules(this.document);
    });
  }

  paragraphProperty(selection, property, value) {
    if (!['text-align', 'margin-left', 'margin-bottom', 'line-height'].includes(property) ||
      !SAFE_VALUE.test(value)) throw new DocumentError('invalidDocument');
    const blocks = this.selectedBlocks(selection);
    this.mutate('paragraph', () => { for (const block of blocks) setProperty(block, property, value); });
  }

  toggleList(index, kind) {
    const block = this.blocks[index];
    this.structureSafe(block);
    if (!['ul', 'ol'].includes(kind)) throw new DocumentError('invalidDocument');
    this.mutate('list', () => {
      if (block.localName === 'li') {
        const list = block.parentElement;
        if (list.localName !== kind) {
          for (const item of list.children) this.structureSafe(item);
          const replacement = this.document.createElementNS(XHTML, kind);
          for (const attr of list.attributes) replacement.setAttribute(attr.name, attr.value);
          replacement.append(...list.childNodes);
          list.replaceWith(replacement);
        } else {
          const after = list.cloneNode(false);
          after.removeAttribute('id');
          while (block.nextSibling) after.append(block.nextSibling);
          const paragraph = this.document.createElementNS(XHTML, 'p');
          for (const attr of block.attributes) paragraph.setAttribute(attr.name, attr.value);
          paragraph.append(...block.childNodes);
          block.remove();
          list.after(paragraph);
          if (after.childNodes.length) paragraph.after(after);
          if (!list.childNodes.length) list.remove();
        }
      } else {
        const list = this.document.createElementNS(XHTML, kind);
        const item = this.document.createElementNS(XHTML, 'li');
        for (const attr of block.attributes) item.setAttribute(attr.name, attr.value);
        item.append(...block.childNodes);
        block.replaceWith(list);
        list.append(item);
      }
    });
  }

  tableEdit(cellIndex, action) {
    const cell = this.cells[cellIndex];
    const table = cell?.closest('table');
    if (!table || this.protected(table)) throw new DocumentError('protected');
    const range = this.document.createRange();
    range.selectNodeContents(table);
    this.guardRange(range);
    const rows = [...table.querySelectorAll('tr')].filter(row => row.closest('table') === table);
    if (rows.some(row => [...row.children].some(item => Number(item.getAttribute('rowspan') || 1) !== 1 ||
      Number(item.getAttribute('colspan') || 1) !== 1)) || rows.some(row => row.children.length !== rows[0].children.length)) {
      throw new DocumentError('mergedTable');
    }
    const row = cell.parentElement;
    const column = [...row.children].indexOf(cell);
    if (action === 'removeRow' && rows.length === 1 || action === 'removeColumn' && row.children.length === 1) throw new DocumentError('tableMinimum');
    if (!['addRow', 'removeRow', 'addColumn', 'removeColumn'].includes(action)) throw new DocumentError('invalidDocument');
    if (this.hasBookmarks && action === 'addColumn') throw new DocumentError('bookmarkColumn');
    this.mutate('table', () => {
      const emptyCell = template => {
        const fresh = template.cloneNode(false);
        fresh.removeAttribute('id');
        const paragraph = this.document.createElementNS(XHTML, 'p');
        paragraph.setAttribute('class', 'Normal');
        paragraph.textContent = '\u200b';
        fresh.append(paragraph);
        return fresh;
      };
      if (action === 'addRow') {
        // Native append inserts before the previous final row terminator.
        const offset = this.nativeOffset(row, true) - (row === rows.at(-1) ? 1 : 0);
        this.nativeChange({ start: offset, end: offset }, () => {
          const fresh = this.document.createElementNS(XHTML, 'tr');
          for (const old of row.children) fresh.append(emptyCell(old));
          row.after(fresh);
        });
      }
      if (action === 'removeRow') this.nativeChange({
        start: this.nativeOffset(row), end: this.nativeOffset(row, true),
      }, () => row.remove());
      if (action === 'addColumn') for (const item of rows) item.children[column].after(emptyCell(item.children[column]));
      if (action === 'removeColumn') {
        const removed = rows.reverse().map(item => item.children[column]);
        const removals = removed.map(cell => ({ start: this.nativeOffset(cell), end: this.nativeOffset(cell, true) }));
        this.nativeChange(removals, () => { for (const cell of removed) cell.remove(); });
      }
    });
  }

  insertTable(index, rowCount = 2, columnCount = 2) {
    const after = this.blocks[index];
    if (this.readOnly || after && (after.parentElement.localName !== 'body' || this.protected(after))) throw new DocumentError('protected');
    if (!Number.isInteger(rowCount) || !Number.isInteger(columnCount) || rowCount < 1 || rowCount > 20 || columnCount < 1 || columnCount > 10) throw new DocumentError('tableSize');
    this.mutate('table', () => {
      const offset = this.nativeOffset(after, true);
      return this.nativeChange({ start: offset, end: offset }, () => {
        const table = this.document.createElementNS(XHTML, 'table');
        table.setAttribute('style', 'border-collapse:collapse;width:100%');
        for (let r = 0; r < rowCount; r++) {
          const row = this.document.createElementNS(XHTML, 'tr');
          for (let c = 0; c < columnCount; c++) {
            const cell = this.document.createElementNS(XHTML, 'td');
            cell.setAttribute('style', 'border:1pt solid #A8B9CD;padding:4pt');
            const paragraph = this.document.createElementNS(XHTML, 'p');
            paragraph.setAttribute('class', 'Normal');
            paragraph.textContent = '\u200b';
            cell.append(paragraph);
            row.append(cell);
          }
          table.append(row);
        }
        if (after) after.after(table);
        else this.document.querySelector('body').append(table);
        const paragraph = this.document.createElementNS(XHTML, 'p');
        paragraph.setAttribute('class', 'Normal');
        paragraph.textContent = '\u200b';
        table.after(paragraph);
      });
    });
  }

  imageSource(image) {
    const src = image.getAttribute('src') || '';
    if (/^data:image\/(?:png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(src)) return src;
    if (!src || /^(?:[a-z][\w+.-]*:|\/\/|\/)/i.test(src)) return null;
    if (this.resourceCache.has(src)) return this.resourceCache.get(src);
    let path;
    try { path = decodeURIComponent(new URL(src, `https://archive.invalid/${this.entry}`).pathname.slice(1)); }
    catch { return null; }
    const bytes = this.files[path];
    const type = bytes && rasterType(bytes);
    const result = type ? `data:image/${type};base64,${base64(bytes)}` : null;
    if (result) this.resourceCache.set(src, result);
    return result;
  }

  insertImage(selection, src, width, height, alt) {
    const range = this.range(selection);
    if (!/^data:image\/(?:png|jpeg);base64,[a-z0-9+/=]+$/i.test(src) ||
      src.length > 12 * 1024 * 1024 || !Number.isFinite(width) || !Number.isFinite(height) ||
      width <= 0 || height <= 0) throw new DocumentError('imageType');
    return this.mutate('image', () => {
      const image = this.document.createElementNS(XHTML, 'img');
      image.setAttribute('src', src);
      image.setAttribute('alt', alt);
      const fitted = Math.min(450, width * .75);
      image.setAttribute('style', `width:${fitted}pt;height:${fitted * height / width}pt;-d4-img-display-mode:proportionalCentered`);
      const fragment = this.document.createDocumentFragment();
      const node = this.document.createTextNode('');
      fragment.append(image, node);
      this.replaceRange(range, fragment);
      return { node, offset: 0 };
    });
  }

  changeImage(index, width = null, naturalRatio = null) {
    const image = this.images[index];
    if (!image || this.protected(image) || !this.imageSource(image)) throw new DocumentError('protected');
    const values = this.values(image);
    const number = value => {
      const match = /^([\d.]+)(pt|px)?$/.exec(value || '');
      return match ? Number(match[1]) * (match[2] === 'px' ? .75 : 1) : null;
    };
    const oldWidth = number(values.width);
    const oldHeight = number(values.height);
    const ratio = oldWidth && oldHeight ? oldHeight / oldWidth : naturalRatio;
    if (width !== null && (!Number.isFinite(width) || width < 12 || width > 1200 || !Number.isFinite(ratio) || ratio <= 0)) throw new DocumentError('imageSize');
    this.mutate('image', () => {
      if (width === null) {
        const range = this.document.createRange();
        range.selectNode(image);
        this.nativeChange(range, () => image.remove());
      }
      else {
        setProperty(image, 'width', `${width}pt`);
        setProperty(image, 'height', `${width * ratio}pt`);
      }
    });
  }

  moveImage(index, selection) {
    const image = this.images[index];
    if (!image || this.protected(image) || !this.imageSource(image)) throw new DocumentError('protected');
    const range = this.range(selection);
    if (!range.collapsed) throw new DocumentError('selection');
    return this.mutate('image', () => {
      const removal = this.document.createRange();
      removal.selectNode(image);
      this.nativeChange(removal, () => image.remove());
      const fragment = this.document.createDocumentFragment();
      const node = this.document.createTextNode('');
      fragment.append(image, node);
      this.replaceRange(range, fragment);
      return { node, offset: 0 };
    });
  }

  find(query, caseSensitive = false) {
    if (!query) return [];
    const matches = [];
    const grouped = new Map();
    this.runs.forEach((node, index) => {
      const block = node.parentElement.closest('p,li');
      if (!grouped.has(block)) grouped.set(block, []);
      grouped.get(block).push({ node, index });
    });
    for (const block of this.blocks) {
      const runs = grouped.get(block) || [];
      const text = runs.map(item => item.node.data).join('');
      const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), caseSensitive ? 'gu' : 'giu');
      for (const match of text.matchAll(pattern)) {
        const offset = match.index;
        let start = 0;
        let first;
        let last;
        for (const item of runs) {
          if (!first && offset < start + item.node.length) first = { index: item.index, offset: offset - start };
          if (offset + match[0].length <= start + item.node.length) { last = { index: item.index, offset: offset + match[0].length - start }; break; }
          start += item.node.length;
        }
        if (first && last) matches.push({ startRun: first.index, start: first.offset, endRun: last.index, end: last.offset });
        if (matches.length > 1000) throw new DocumentError('tooManyMatches');
      }
    }
    return matches;
  }

  replaceMatches(query, replacement, all = false, index = 0, caseSensitive = false) {
    const matches = this.find(query, caseSensitive);
    const selected = all ? matches : matches.slice(index, index + 1);
    const ranges = selected.map(match => this.range(match));
    return this.mutate('replace', () => {
      let caret;
      for (const range of ranges.reverse()) {
        const node = this.document.createTextNode(replacement);
        this.replaceRange(range, node);
        caret = { node, offset: node.length };
      }
      return caret;
    });
  }

  restoreVersion(xml) {
    const restored = parse(xml);
    this.mutate('restore', () => { this.document = restored; this.refresh(); }, null, true);
  }

  pack() {
    return {
      xml: this.serialize(), files: this.files, entry: this.entry, original: this.original, initial: this.initial,
      undo: [...this.undoStack], redo: [...this.redoStack], undoLabels: [...this.undoLabels], redoLabels: [...this.redoLabels],
      selection: this.selection, undoSelections: [...this.undoSelections], redoSelections: [...this.redoSelections],
    };
  }

  static unpack(data) {
    if (!data || typeof data.xml !== 'string' || typeof data.entry !== 'string' || !data.files ||
      data.original != null && (!(data.original instanceof Uint8Array) || data.original.length > MAX_ARCHIVE) ||
      Object.keys(data.files).length > 512 || Object.values(data.files).some(value => !(value instanceof Uint8Array)) ||
      Object.values(data.files).reduce((sum, value) => sum + value.length, 0) > 32 * 1024 * 1024) throw new DocumentError('invalidDocument');
    const model = new WriteProDocument(data.xml, data.files, data.entry, data.original);
    if (typeof data.initial === 'string') { parse(data.initial); model.initial = data.initial; }
    for (const [field, key] of [['undoStack', 'undo'], ['redoStack', 'redo'], ['undoLabels', 'undoLabels'], ['redoLabels', 'redoLabels']]) {
      const values = data[key] || [];
      if (!Array.isArray(values) || values.length > 100 || values.some(value => typeof value !== 'string' || value.length > MAX_EXPANDED)) throw new DocumentError('invalidDocument');
      model[field] = values;
    }
    if ([...model.undoStack, ...model.redoStack].reduce((sum, value) => sum + value.length, 0) > 2 * MAX_EXPANDED) throw new DocumentError('tooLarge');
    for (const [field, stack] of [['undoSelections', model.undoStack], ['redoSelections', model.redoStack]]) {
      const values = data[field] ?? stack.map(() => null);
      if (!Array.isArray(values) || values.length !== stack.length || values.some(value => !validBookmark(value))) throw new DocumentError('invalidDocument');
      model[field] = values;
    }
    if (!validBookmark(data.selection ?? null)) throw new DocumentError('invalidDocument');
    model.selection = data.selection ?? null;
    return model;
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
    this.images = [];
    this.cells = [];
    const body = this.document.querySelector('body');
    for (const element of body.querySelectorAll('img,br')) {
      if (this.protected(element) || element.localName === 'img' && !this.imageSource(element) || !element.closest('p,li')) continue;
      if (element.previousSibling?.nodeType !== 3) element.before(this.document.createTextNode(''));
      if (element.nextSibling?.nodeType !== 3) element.after(this.document.createTextNode(''));
    }
    const project = (source, target, locked = false, inBlock = false, decoration = '', background = '') => {
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
          if (background) run.style.backgroundColor = background;
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
            const src = this.imageSource(child);
            if (src) {
              const image = document.createElement('img');
              image.src = src;
              image.alt = child.getAttribute('alt') || labels.image;
              image.loading = 'lazy';
              for (const [property, value] of Object.entries(values)) {
                if (['width', 'height'].includes(property) && /^[\d.]+(?:pt|px|%)$/.test(value)) image.style.setProperty(property, value);
              }
              badge.dataset.image = this.images.push(child) - 1;
              if (!this.protected(child)) {
                badge.tabIndex = 0;
                badge.setAttribute('role', 'button');
                badge.setAttribute('aria-label', labels.image);
              }
              badge.replaceChildren(image);
            }
          }
          target.append(badge);
          continue;
        }
        const element = document.createElement(tag === 'a' ? 'span' : tag);
        for (const [property, value] of Object.entries(values)) {
          if (property !== 'text-decoration' && !(property === 'background-color' && INLINE_TAGS.has(tag)) && SAFE_PROPERTIES.test(property) && SAFE_VALUE.test(value) && value.length < 200 &&
            !/url|expression|var\(|!important/i.test(value)) element.style.setProperty(property, value);
        }
        for (const attr of ['rowspan', 'colspan', 'start']) {
          const value = child.getAttribute(attr);
          if (/^\d{1,3}$/.test(value || '')) element.setAttribute(attr, value);
        }
        const isBlock = ['p', 'li'].includes(tag);
        if (isBlock) {
          const walker = this.document.createTreeWalker(child, 4);
          if (!walker.nextNode()) child.append(this.document.createTextNode(''));
        }
        if (['td', 'th'].includes(tag)) element.dataset.cell = this.cells.push(child) - 1;
        if (isBlock) element.dataset.block = this.blocks.push(child) - 1;
        const isLocked = locked || this.protected(child);
        if (isLocked) element.classList.add('locked-content');
        if (tag === 'a') element.classList.add('inert-link');
        const nextDecoration = values['text-decoration'];
        const safeDecoration = nextDecoration && SAFE_VALUE.test(nextDecoration) && nextDecoration.length < 100;
        const nextBackground = INLINE_TAGS.has(tag) && values['background-color'];
        const safeBackground = nextBackground && SAFE_VALUE.test(nextBackground) && nextBackground.length < 100 && !/url|expression|var\(/i.test(nextBackground);
        project(child, element, isLocked, inBlock || isBlock, safeDecoration ? nextDecoration : decoration, safeBackground ? nextBackground : background);
        target.append(element);
      }
    };
    project(body, host);
  }
}
