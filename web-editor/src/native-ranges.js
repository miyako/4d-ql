import { DocumentError } from './archive.js';
import { paragraphBreak } from './sections.js';

const XHTML = 'http://www.w3.org/1999/xhtml';
const INLINE = new Set(['span', 'a', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup', 'br', 'img']);
const textValue = text => text.replace(/\u200b/g, '');

export function nativeTableGrid(element) {
  const fail = () => {
    const error = new DocumentError('protected');
    error.reason = 'bookmarkTableShape';
    throw error;
  };
  const children = node => [...node.childNodes].filter(child => child.nodeType !== 8 && !(child.nodeType === 3 && !child.data.length));
  const rows = children(element);
  if (!rows.length || rows.some(row => row.localName !== 'tr')) fail();
  const span = (cell, name) => {
    const value = cell.getAttribute(name);
    if (value !== null && !/^[1-9]\d*$/.test(value)) fail();
    return Number(value || 1);
  };
  const columns = [...rows[0].children].reduce((count, cell) => count + span(cell, 'colspan'), 0);
  if (!columns || columns > 1000) fail();
  const grid = rows.map(() => Array(columns).fill(false));
  let merged = false;
  for (const [index, row] of rows.entries()) {
    let column = 0;
    for (const cell of children(row)) {
      if (!['td', 'th'].includes(cell.localName)) fail();
      while (grid[index][column]) column++;
      const width = span(cell, 'colspan');
      const height = span(cell, 'rowspan');
      if (column + width > columns || index + height > rows.length) fail();
      merged ||= width > 1 || height > 1;
      for (let r = index; r < index + height; r++) for (let c = column; c < column + width; c++) {
        if (grid[r][c]) fail();
        grid[r][c] = true;
      }
      column += width;
    }
    if (grid[index].some(occupied => !occupied)) fail();
  }
  return { rows, columns, merged };
}

export function nativeBoundary(text, offset) {
  return Number.isSafeInteger(offset) && offset >= 1 && offset <= text.length + 1 &&
    !(/[\uD800-\uDBFF]/.test(text[offset - 2] || '') && /[\uDC00-\uDFFF]/.test(text[offset - 1] || ''));
}

// Native range objects use origin 1; serialized bookmark pairs use origin 0.
// Both count UTF-16 with an exclusive end. Breaks and pictures occupy one slot.
export function nativeBody(document, values, imageSource = image => /^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(image.getAttribute('src') || ''), formula = () => false) {
  const positions = new Map();
  const tables = [];
  let text = '';
  let blocks = 0;
  const fail = (reason = 'bookmarkStructure') => {
    const error = new DocumentError('protected');
    error.reason = reason;
    throw error;
  };
  const check = (element, isFormula = false) => {
    const style = values(element);
    if (element.namespaceURI !== XHTML ||
      [...element.attributes].some(attribute => attribute.namespaceURI && attribute.namespaceURI !== 'http://www.w3.org/XML/1998/namespace') ||
      Object.keys(style).some(key => /^-d4-anchor/.test(key) || /^-d4-section/.test(key) &&
        !(key === '-d4-section-break-after' && element.localName === 'p' && element.parentElement?.localName === 'body') ||
        !isFormula && /^-d4-ref/.test(key)) ||
      /section\d.*(Header|Footer)/i.test(element.getAttribute('class') || '') ||
      style['break-after'] === 'column' ||
      style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility)) fail();
    if (style['-d4-section-break-after'] || style['page-break-after']) {
      try {
        const kind = paragraphBreak(style);
        if (kind && (element.localName !== 'p' || element.parentElement?.localName !== 'body' ||
          element.nextElementSibling?.localName !== 'p')) fail();
      } catch (error) {
        if (!(error instanceof DocumentError)) throw error;
        fail();
      }
    }
  };
  const inline = node => {
    const start = text.length + 1;
    if (node.nodeType === 3) {
      if (/[\r\n]/.test(node.data)) fail();
      text += textValue(node.data);
      positions.set(node, { start, end: text.length + 1 });
    } else if (node.nodeType === 1) {
      const isFormula = formula(node);
      check(node, isFormula);
      if (!INLINE.has(node.localName)) fail(['ul', 'ol'].includes(node.localName) ? 'bookmarkNestedList' : 'bookmarkStructure');
      if (isFormula) {
        text += '\ufffc';
        positions.set(node, { start, end: text.length + 1 });
      } else if (node.localName === 'br' || node.localName === 'img') {
        if (node.childNodes.length || node.localName === 'img' && !imageSource(node)) fail();
        text += node.localName === 'br' ? '\n' : '\ufffc';
        positions.set(node, { start, end: text.length + 1 });
      } else contents(node);
    } else if (node.nodeType !== 8) fail();
  };
  const contents = element => {
    const start = text.length + 1;
    const offsets = [start];
    for (const child of element.childNodes) {
      inline(child);
      offsets.push(text.length + 1);
    }
    positions.set(element, { start, end: text.length + 1, offsets });
  };
  const children = element => [...element.childNodes].filter(child => child.nodeType !== 8 && !(child.nodeType === 3 && !child.data.length));
  const table = element => {
    check(element);
    const { rows, merged } = nativeTableGrid(element);
    const start = text.length + 1;
    const regions = [];
    const rowRegions = [];
    const offsets = [start];
    for (const row of rows) {
      check(row);
      const cells = children(row);
      const rowStart = text.length + 1;
      const rowOffsets = [rowStart];
      const cellRegions = [];
      // Full 4D counts one terminator per cell and an additional one per row.
      for (const cell of cells) {
        const cellStart = text.length + 1;
        container(cell);
        text += '\r';
        positions.set(cell, { ...positions.get(cell), start: cellStart, end: text.length + 1 });
        regions.push([cellStart, text.length + 1]);
        cellRegions.push({ element: cell, start: cellStart, end: text.length + 1 });
        rowOffsets.push(text.length + 1);
      }
      regions.push([text.length + 1, text.length + 2]);
      text += '\r';
      positions.set(row, { start: rowStart, end: text.length + 1, offsets: rowOffsets });
      rowRegions.push({ element: row, start: rowStart, end: text.length + 1, cells: cellRegions });
      offsets.push(text.length + 1);
    }
    positions.set(element, { start, end: text.length + 1, offsets });
    tables.push({ element, start, end: text.length + 1, regions, rows: rowRegions, merged });
  };
  const container = element => {
    check(element);
    if (element.localName !== 'body' && !element.children.length) fail();
    const start = text.length + 1;
    const offsets = [start];
    let previous = null;
    for (const child of element.childNodes) {
      if (child.nodeType === 8 || child.nodeType === 3 && !child.data.length) {
        offsets.push(text.length + 1);
        continue;
      }
      if (child.nodeType !== 1) fail();
      if (previous && previous.localName !== 'table') text += '\r';
      if (['body', 'td', 'th'].includes(element.localName) && ['ul', 'ol'].includes(child.localName)) container(child);
      else if ((['body', 'td', 'th'].includes(element.localName) && child.localName === 'p') ||
        (['ul', 'ol'].includes(element.localName) && child.localName === 'li')) {
        check(child);
        blocks++;
        contents(child);
      } else if (element.localName === 'body' && child.localName === 'table') {
        if (!previous || previous.localName !== 'p' || child.nextElementSibling?.localName !== 'p') fail();
        table(child);
      } else fail(['ul', 'ol', 'li'].includes(element.localName) ? 'bookmarkNestedList' : 'bookmarkStructure');
      previous = child;
      offsets.push(text.length + 1);
    }
    positions.set(element, { start, end: text.length + 1, offsets });
  };
  container(document.querySelector('body'));
  if (!blocks || !text.isWellFormed()) fail();
  return {
    text,
    tables,
    supports(bookmarks) {
      // Interior cross-cell ranges support additions, not destructive or table
      // commands. Ranges entering/leaving a table normalize even on text edits.
      return Object.values(bookmarks).every(([first, last]) => first === last || tables.every(table =>
        last <= table.start || first >= table.end || first <= table.start && last >= table.end ||
        first >= table.start && last <= table.end));
    },
    crossesCells(bookmarks, point) {
      return Object.values(bookmarks).some(([first, last]) => first !== last &&
        (point === undefined || first < point && point < last) && tables.some(table =>
        last > table.start && first < table.end && !(first <= table.start && last >= table.end) &&
        !table.regions.some(([start, end]) => first >= start && last <= end)));
    },
    columnBoundary(element, bookmarks) {
      const table = tables.find(table => table.element === element);
      if (!table) fail();
      return Object.values(bookmarks).some(([first, last]) =>
        first < table.end && last === table.end ||
        table.rows.some(row => first === row.end - 1 && last <= row.end));
    },
    point(node, offset) {
      const position = positions.get(node);
      const result = node.nodeType === 3 ? position?.start + textValue(node.data.slice(0, offset)).length : position?.offsets?.[offset];
      if (!Number.isInteger(result)) fail();
      return result;
    },
    bounds(node) {
      const result = positions.get(node);
      if (!result) fail();
      return result;
    },
    locate(offset, forward = true) {
      if (!nativeBoundary(text, offset)) fail();
      const candidates = [...positions].filter(([node, position]) => node.nodeType === 3 &&
        offset >= position.start && offset <= position.end);
      const match = candidates.find(([, position]) => forward ? offset < position.end : offset > position.start) || candidates[0];
      if (match) {
        const [node, position] = match;
        let index = 0;
        let counted = position.start;
        while (index < node.length && counted < offset) {
          if (node.data[index] !== '\u200b') counted++;
          index++;
        }
        return { node, offset: index };
      }
      for (const [node, position] of positions) {
        const index = position.offsets?.indexOf(offset);
        if (index >= 0) return { node, offset: index };
        if (node.nodeType === 1 && (['br', 'img'].includes(node.localName) || formula(node)) &&
          (offset === position.start || offset === position.end)) {
          return { node: node.parentNode, offset: [...node.parentNode.childNodes].indexOf(node) + Number(offset === position.end) };
        }
      }
      fail();
    },
  };
}

export function nativeMetadata(document) {
  const metas = [...document.querySelectorAll('meta')].filter(meta =>
    ['bookmarks', 'ranges'].includes((meta.getAttribute('name') || '').toLowerCase()));
  const bookmarks = metas.filter(meta => meta.getAttribute('name').toLowerCase() === 'bookmarks');
  if (bookmarks.length > 1 || metas.some(meta => meta.parentElement?.localName !== 'head' ||
    meta.getAttribute('name').toLowerCase() === 'ranges' && !['', '{}', '[]'].includes((meta.getAttribute('content') || '').trim()))) {
    throw new DocumentError('protected');
  }
  const meta = bookmarks[0];
  if (!meta || ['', '{}', '[]'].includes((meta.getAttribute('content') || '').trim())) return { meta, bookmarks: {} };
  let data;
  try { data = JSON.parse(meta.getAttribute('content')); }
  catch { throw new DocumentError('protected'); }
  if (!data || Array.isArray(data) || typeof data !== 'object' ||
    Object.values(data).some(pair => !Array.isArray(pair) || pair.length !== 2 ||
      !pair.every(Number.isSafeInteger) || pair[0] < 0 || pair[1] < pair[0] ||
      pair[1] >= Number.MAX_SAFE_INTEGER)) throw new DocumentError('protected');
  // JSON.parse alone would silently discard duplicate (including escaped) keys.
  const names = [...meta.getAttribute('content').matchAll(/("(?:\\.|[^"\\])*")\s*:/g)].map(match => JSON.parse(match[1]));
  if (new Set(names).size !== names.length || names.length !== Object.keys(data).length) throw new DocumentError('protected');
  return { meta, bookmarks: Object.fromEntries(Object.entries(data).map(([name, pair]) => [name, pair.map(offset => offset + 1)])) };
}

export function writeBookmarks(meta, bookmarks) {
  meta.setAttribute('content', JSON.stringify(Object.fromEntries(
    Object.entries(bookmarks).map(([name, pair]) => [name, pair.map(offset => offset - 1)]),
  )));
}

// Editor replacements deliberately replay native deletion followed by insertion,
// not the different, content-dependent WP SET TEXT atomic-replacement behavior.
export function spliceBookmarks(bookmarks, start, end, length, pointAfter = false) {
  return Object.fromEntries(Object.entries(bookmarks).flatMap(([name, [first, last]]) => {
    if (end > start) {
      if (first === last ? start < first && first < end : start <= first && last <= end) return [];
      const shift = point => point <= start ? point : point >= end ? point - (end - start) : start;
      first = shift(first);
      last = shift(last);
    }
    if (first === last) {
      if (start < first || pointAfter && start === first) first = last = first + length;
    } else {
      if (start <= first) first += length;
      if (start < last) last += length;
    }
    return [[name, [first, last]]];
  }));
}
