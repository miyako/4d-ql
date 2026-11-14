import * as css from 'css-tree';
import { WriteProDocument } from './document.js';
import { DocumentError } from './archive.js';
import { paperGeometry } from './layout-preview.js';
import { pagePoints } from './page-setup.js';
import { paragraphBreak } from './sections.js';
import { areaLabel } from './header-messages.js';
import { headerContentReason } from './headers-footers.js';
import { nativeTableGrid } from './native-ranges.js';

const bullets = { disc: '\u2022', circle: '\u25cb', square: '\u25a0', 'hollow-square': '\u25a1', diamond: '\u25c6', club: '\u2663', none: '' };
const numbered = new Set(['decimal', 'decimal-leading-zero', 'lower-alpha', 'upper-alpha', 'lower-latin', 'upper-latin', 'lower-roman', 'upper-roman']);
const cellListTypes = new Set(['disc', 'circle', 'square', 'hollow-square', 'diamond',
  'decimal', 'lower-latin', 'upper-latin', 'lower-roman', 'upper-roman']);

export function pageListMarker(values, number, kind, inCell = false) {
  const type = values['-d4-list-style-type'] || values['list-style-type'] || (kind === 'ol' ? 'decimal' : 'disc');
  if (Object.keys(values).some(key => key.startsWith('-d4-list-') &&
    !['-d4-list-style-type', '-d4-list-string-format-ltr', '-d4-list-font'].includes(key))) throw new DocumentError('pagedShape');
  if (!Number.isSafeInteger(number) || number < 1 || number > 3999) throw new DocumentError('pagedShape');
  if (Object.hasOwn(bullets, type)) {
    if (inCell && type === 'disc') return '\u25cf';
    if (inCell && type === 'diamond') return '\u2666';
    return bullets[type];
  }
  if (!numbered.has(type)) throw new DocumentError('pagedShape');
  let text = String(number);
  if (type === 'decimal-leading-zero') text = text.padStart(2, '0');
  if (/alpha|latin/.test(type)) {
    text = '';
    for (let n = number; n > 0; n = Math.floor((n - 1) / 26)) text = String.fromCharCode(97 + (n - 1) % 26) + text;
  }
  if (/roman/.test(type)) {
    text = '';
    let n = number;
    for (const [value, symbol] of [[1000, 'm'], [900, 'cm'], [500, 'd'], [400, 'cd'], [100, 'c'], [90, 'xc'],
      [50, 'l'], [40, 'xl'], [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i']]) {
      while (n >= value) { text += symbol; n -= value; }
    }
  }
  if (type.startsWith('upper-')) text = text.toUpperCase();
  const format = values['-d4-list-string-format-ltr'];
  if (!format) return `${text}.`;
  if (!/^(['"])[^'"\\\r\n]{0,80}\1$/.test(format) || format.slice(1, -1).split('#').length !== 2) throw new DocumentError('pagedShape');
  return format.slice(1, -1).replace('#', text);
}

function bodyParagraphs(element) {
  if (element.localName === 'p') return [element];
  if (!['ul', 'ol'].includes(element.localName) || !element.children.length ||
    [...element.childNodes].some(node => node.nodeType === 3 && node.data.trim()) ||
    [...element.children].some(item => item.localName !== 'li' || item.querySelector('p,li,ul,ol,table'))) throw new DocumentError('pagedShape');
  const start = element.getAttribute('start') || '1';
  if (!/^[1-9]\d{0,3}$/.test(start) || element.hasAttribute('reversed') ||
    [...element.children].some(item => item.hasAttribute('value'))) throw new DocumentError('pagedShape');
  return [...element.children];
}

function prepareListItem(model, list, item, index, content, first = true) {
  content.style.listStyleType = 'none';
  content.style.position = 'relative';
  if (!first) return;
  const marker = document.createElement('span');
  marker.className = 'paged-list-marker';
  const itemValues = model.values(item);
  const values = { ...model.values(list), ...itemValues };
  marker.textContent = pageListMarker(values, Number(list.getAttribute('start') || 1) + index, list.localName, Boolean(list.closest('td,th')));
  const font = itemValues['-d4-list-font'];
  if (font && !/url|expression|var\(|[;{}]/i.test(font)) marker.style.fontFamily = font;
  content.prepend(marker);
}

const points = value => (/^(?:0|[1-9]\d{0,4})(?:\.\d{1,3})?pt$/.test(value || '') ? Number(value.slice(0, -2)) : null);

// Full 4D 21.2 (wp_nowitness_probe) stores every merged cell's content width so that outer widths add up:
// width + 2 x padding + the default 1pt solid border equals the sum of its columns' outer widths. Native column
// getters report no width for merged columns, so the stored cell widths are the only evidence. A grid is resolved
// only when uniform padding and default borders make that rule exact, every column boundary is fixed by some
// cell edge, and every redundant cell agrees; anything else (declared border widths, per-column padding,
// drifting stored widths, an unfixed boundary) stays atomic. Returns column widths in points, as a witness row would.
function nativeColumnWidths(model, element, grid) {
  const fail = () => { throw new DocumentError('pagedTables'); };
  // The native default stylesheet declares border-width:1pt on table, tr and td; any other border geometry is unproven.
  const border = values => Object.entries(values).some(([key, value]) => /^border/.test(key) &&
    !['border-style', 'border-color', 'border-width', 'border-collapse', 'border-spacing'].includes(key)) ||
    (values['border-width'] !== undefined && values['border-width'] !== '1pt');
  const table = model.values(element);
  if (table['border-style'] !== 'solid' || table['border-collapse'] !== 'collapse' || border(table)) fail();
  const occupied = grid.rows.map(() => Array(grid.columns).fill(false));
  const edges = Array.from({ length: grid.columns + 1 }, () => []);
  let padding = null;
  for (const [index, row] of grid.rows.entries()) {
    if (border(model.values(row))) fail();
    let column = 0;
    for (const cell of row.children) {
      while (occupied[index][column]) column++;
      const across = Number(cell.getAttribute('colspan') || 1);
      const down = Number(cell.getAttribute('rowspan') || 1);
      for (let r = index; r < index + down; r++) for (let c = column; c < column + across; c++) occupied[r][c] = true;
      const values = model.values(cell);
      const width = points(values.width);
      padding ??= points(values.padding);
      if (!width || padding === null || points(values.padding) !== padding || values['border-style'] !== 'solid' ||
        border(values) || Object.keys(values).some(key => /^padding-/.test(key))) fail();
      const outer = width + 2 * padding + 1;
      edges[column].push([column + across, outer]);
      edges[column + across].push([column, -outer]);
      column += across;
    }
  }
  const positions = Array(grid.columns + 1).fill(null);
  positions[0] = 0;
  for (const queue = [0]; queue.length;) {
    const boundary = queue.shift();
    for (const [other, distance] of edges[boundary]) {
      const position = positions[boundary] + distance;
      if (positions[other] === null) {
        positions[other] = position;
        queue.push(other);
      } else if (Math.abs(positions[other] - position) > 1e-6) fail();
    }
  }
  if (positions.some(position => position === null)) fail();
  const widths = positions.slice(1).map((position, index) => position - positions[index] - 2 * padding - 1);
  if (widths.some(width => width <= 0)) fail();
  return widths;
}

function pagedTable(model, element) {
  try {
    if (element.children.length > 1000 || element.querySelectorAll('td,th').length > 10000) throw new DocumentError('pagedTables');
    const grid = nativeTableGrid(element);
    const span = (cell, name) => Number(cell.getAttribute(name) || 1);
    // A width witness owns every grid column itself: rows covered by a vertical merge never qualify.
    const witness = grid.rows.findIndex(row => row.children.length === grid.columns && [...row.children].every(cell =>
      span(cell, 'colspan') === 1 && span(cell, 'rowspan') === 1));
    if (grid.rows.length > 1000 || grid.rows.length * grid.columns > 10000) throw new DocumentError('pagedTables');
    // Without a witness, only the native stored cell widths may fix the column grid (M2); otherwise atomic fallback.
    const resolved = witness < 0 ? nativeColumnWidths(model, element, grid) : null;
    if (element.previousElementSibling?.localName !== 'p' || element.nextElementSibling?.localName !== 'p') throw new DocumentError('pagedTables');
    // Rows tied together by vertical merges form one unbreakable band [start, end).
    const bands = [];
    for (let start = 0, end = 0; start < grid.rows.length; start = end) {
      end = start + 1;
      for (let index = start; index < end; index++) {
        for (const cell of grid.rows[index].children) end = Math.max(end, index + span(cell, 'rowspan'));
      }
      bands.push([start, end]);
    }
    let headers = 0;
    let markers = 0;
    for (const [index, row] of grid.rows.entries()) {
      const header = model.values(row)['-d4-header'];
      if ((header && header !== 'true' && header !== 'false') ||
        (header === 'true' && headers !== index)) throw new DocumentError('pagedTables');
      if (header === 'true') headers++;
      for (const cell of row.children) {
        if (!cell.children.length || [...cell.childNodes].some(node => node.nodeType === 3 && node.data.trim())) throw new DocumentError('pagedTables');
        for (const block of cell.children) {
          const items = bodyParagraphs(block);
          if (block.localName !== 'p') {
            markers += items.length;
            if (markers > 10000) throw new DocumentError('pagedTables');
            const listValues = model.values(block);
            for (const [index, item] of items.entries()) {
              const values = { ...listValues, ...model.values(item) };
              const type = values['-d4-list-style-type'] || values['list-style-type'] || (block.localName === 'ol' ? 'decimal' : 'disc');
              if (!cellListTypes.has(type) || (values['-d4-list-string-format-ltr'] && !numbered.has(type)) ||
                /url|expression|var\(|[;{}]/i.test(values['-d4-list-font'] || '')) throw new DocumentError('pagedTables');
              pageListMarker(values, Number(block.getAttribute('start') || 1) + index, block.localName);
            }
          }
        }
      }
    }
    // Repeated headers must be whole bands; a merge crossing into the body has no unambiguous repetition.
    if (headers === grid.rows.length || (headers && !bands.some(([, end]) => end === headers))) throw new DocumentError('pagedTables');
    for (const node of [element, ...element.querySelectorAll('*')]) {
      const values = model.values(node);
      if (Object.keys(values).some(key => /^-d4-(ref|anchor)/.test(key) && !model.formula(node)?.supported) ||
        values.display === 'none' || ['hidden', 'collapse'].includes(values.visibility) ||
        paragraphBreak(values) || values['break-after'] === 'column' || (node.localName !== 'img' &&
        ['height', 'min-height', 'max-height'].some(key => values[key]))) throw new DocumentError('pagedTables');
    }
    return { ...grid, headers, witness, resolved, bands: bands.filter(([start]) => start >= headers) };
  } catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    throw new DocumentError('pagedTables');
  }
}

function inlineImage(model, source) {
  const info = model.imageInfo(source);
  const values = model.values(source);
  if (!info.src || Object.keys(values).some(key => /^-d4-(anchor|ref)/.test(key)) ||
    !['scaledtofit', 'proportional', 'proportionalcentered', 'truncated', 'truncatedcentered']
      .includes((values['-d4-img-display-mode'] || 'scaledToFit').toLowerCase())) throw new DocumentError('pagedShape');
  for (const property of ['width', 'height']) {
    if (values[property] && (pagePoints(values[property]) <= 0 || pagePoints(values[property]) > 10000)) throw new DocumentError('pagedShape');
  }
  return info;
}

export async function preparePagedProjection(model, labels) {
  const copy = new WriteProDocument(model.serialize(), model.files, model.entry);
  const reason = pagedCapability(copy);
  if (reason) throw new DocumentError(reason);
  const decoded = new Map();
  const deadline = performance.now() + 10000;
  for (const source of copy.document.querySelectorAll('body img')) {
    const info = inlineImage(copy, source);
    if (decoded.has(info.src)) continue;
    const image = new Image();
    image.src = info.src;
    let timer;
    try {
      await Promise.race([image.decode(), new Promise((_, reject) => {
        timer = setTimeout(() => reject(new DocumentError('pagedUnavailable')), Math.max(0, deadline - performance.now()));
      })]);
      if (!image.naturalWidth || !image.naturalHeight) throw new DocumentError('pagedShape');
      decoded.set(info.src, { width: image.naturalWidth, height: image.naturalHeight });
      if ([...decoded.values()].reduce((sum, size) => sum + size.width * size.height, 0) > 80_000_000) throw new DocumentError('pagedShape');
    } catch (error) {
      if (error instanceof DocumentError) throw error;
      throw new DocumentError('pagedShape');
    } finally { clearTimeout(timer); }
  }
  return createPagedProjection(copy, labels, decoded);
}

function lineBoundaries(paragraph, budget) {
  const points = [{ node: paragraph, offset: 0 }];
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  let bottom = -Infinity;
  const visit = node => {
    if (node.nodeType === 3) {
      for (const { index, segment } of segmenter.segment(node.data)) {
        if (++budget.count > 100000) throw new DocumentError('pagedOverflow');
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + segment.length);
        const rect = range.getBoundingClientRect();
        if (rect.height && rect.top >= bottom - .25 && bottom !== -Infinity) points.push({ node, offset: index });
        if (rect.height) bottom = Math.max(bottom, rect.bottom);
      }
    } else if (node.nodeType === 1 && (node.localName === 'br' || node.classList.contains('preserved-object'))) {
      const rect = node.getBoundingClientRect();
      if (rect.height && rect.top >= bottom - .25 && bottom !== -Infinity) {
        points.push({ node: node.parentNode, offset: [...node.parentNode.childNodes].indexOf(node) });
      }
      if (rect.height) bottom = Math.max(bottom, rect.bottom);
    } else for (const child of node.childNodes) visit(child);
  };
  for (const child of paragraph.childNodes) visit(child);
  points.push({ node: paragraph, offset: paragraph.childNodes.length });
  return points;
}

function paragraphFragment(paragraph, start, end, first, last) {
  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset);
  const fragment = paragraph.cloneNode(false);
  let content = range.cloneContents();
  let ancestor = range.commonAncestorContainer;
  if (ancestor.nodeType === 3) ancestor = ancestor.parentNode;
  // cloneContents omits a shared inline ancestor; retain its formatting on middle fragments.
  while (ancestor !== paragraph) {
    const wrapper = ancestor.cloneNode(false);
    wrapper.append(content);
    content = wrapper;
    ancestor = ancestor.parentNode;
  }
  fragment.append(content);
  if (!first) {
    fragment.style.marginTop = '0';
    fragment.style.textIndent = '0';
  }
  if (!last) fragment.style.marginBottom = '0';
  return fragment;
}

function makeInert(root) {
  for (const element of root.querySelectorAll('*')) {
    if (['p', 'li'].includes(element.localName) || element.classList.contains('text-run')) element.style.whiteSpace = 'break-spaces';
    for (const attribute of [...element.attributes]) {
      if (['contenteditable', 'tabindex', 'role', 'spellcheck'].includes(attribute.name) ||
        attribute.name.startsWith('data-') && !['data-page', 'data-section', 'data-sections', 'data-area', 'data-column'].includes(attribute.name)) element.removeAttribute(attribute.name);
    }
  }
}

function firstRight(model) {
  let value = true;
  for (const style of model.document.querySelectorAll('head style')) {
    const ast = css.parse(style.textContent, { onParseError: () => { throw new DocumentError('pagedSettings'); } });
    css.walk(ast, node => {
      if (node.type !== 'Rule') return;
      for (const declaration of node.block.children) {
        if (declaration.type !== 'Declaration' || declaration.property.toLowerCase() !== '-d4-page-first-right') continue;
        const text = css.generate(declaration.value);
        if (![...ast.children].includes(node) || css.generate(node.prelude) !== 'div.section0' ||
          declaration.property !== '-d4-page-first-right' || declaration.important ||
          !['true', 'false'].includes(text)) throw new DocumentError('pagedSettings');
        value = text === 'true';
      }
    });
  }
  for (const element of model.document.querySelectorAll('[style]')) {
    if (/-d4-page-first-right\s*:/i.test(element.getAttribute('style'))) throw new DocumentError('pagedSettings');
  }
  return value;
}

export function selectedPageArea(state, section, first, page, rightFirst, kind) {
  const variant = first && state.variants.includes(`section${section}First`) ? 'First' :
    state.variants.includes(`section${section}Left`) ? ((page % 2 === 1) === rightFirst ? 'Right' : 'Left') : '';
  return state.areas.find(area => area.section === section && area.variant === variant && area.kind === kind);
}

export function pagedColumnGeometry(model, index, paper, strict = false) {
  const setup = model.columnSetup(index);
  if (setup.reason) throw new DocumentError('pagedColumns');
  const { count } = setup.settings;
  const gap = pagePoints(setup.settings.gap);
  const width = (paper.width - paper.margins[1] - paper.margins[3] - gap * (count - 1)) / count;
  if (count === 1 && !strict) return { count, gap, width };
  if (count > 4 || gap > 72 || width < 72) throw new DocumentError('pagedColumns');
  const rules = new Map();
  for (const style of model.document.querySelectorAll('head style')) {
    const ast = css.parse(style.textContent, { onParseError: () => { throw new DocumentError('pagedColumns'); } });
    const scoped = new Set();
    for (const rule of ast.children) {
      if (rule.type !== 'Rule') continue;
      const match = css.generate(rule.prelude).match(/^div\.section(0|[1-9]\d*)$/);
      if (!match) continue;
      const values = rules.get(Number(match[1])) || {};
      for (const node of rule.block.children) {
        if (node.type !== 'Declaration' || !/^column-/i.test(node.property)) continue;
        if (node.important || node.property !== node.property.toLowerCase() ||
          !['column-count', 'column-gap', 'column-rule-style', 'column-rule-width', 'column-rule-color'].includes(node.property)) {
          throw new DocumentError('pagedColumns');
        }
        scoped.add(node);
        values[node.property] = css.generate(node.value);
      }
      rules.set(Number(match[1]), values);
    }
    css.walk(ast, node => {
      if (node.type !== 'Declaration') return;
      if (/^(columns|column-)/i.test(node.property) && !scoped.has(node) ||
        /^(direction|writing-mode)$/i.test(node.property) &&
        !['ltr', 'horizontal-tb'].includes(css.generate(node.value))) throw new DocumentError('pagedColumns');
    });
  }
  const values = { ...rules.get(0), ...rules.get(index) };
  if (values['column-rule-style'] && values['column-rule-style'] !== 'none' ||
    [...model.document.querySelectorAll('[style]')].some(element =>
      /(?:^|;)\s*(?:columns|column-[\w-]+)\s*:/i.test(element.getAttribute('style')))) throw new DocumentError('pagedColumns');
  for (const element of model.document.querySelectorAll('body,body *')) {
    const style = model.values(element);
    if (style.direction && style.direction !== 'ltr' || style['writing-mode'] && style['writing-mode'] !== 'horizontal-tb') {
      throw new DocumentError('pagedColumns');
    }
  }
  return { count, gap, width };
}

function pagedBreak(values) {
  const kind = paragraphBreak(values);
  const column = values['break-after'] || 'auto';
  if (!['auto', 'avoid', 'column'].includes(column) || column === 'column' && kind) throw new DocumentError('pagedColumns');
  return column === 'column' ? 'column' : kind;
}

function continuousSections(model, layout, setup, areas) {
  for (let index = 1; index < layout.sections.length; index++) {
    const previous = layout.sections[index - 1];
    if (paragraphBreak(model.values(previous.elements.at(-1))) !== 'continuous') continue;
    const section = layout.sections[index];
    const geometries = [previous, section].map(item => ({ ...setup.geometry, ...setup.sections.get(item.index) }));
    const papers = geometries.map(paperGeometry);
    const columns = [previous, section].map((item, i) => pagedColumnGeometry(model, item.index, papers[i], true));
    if (columns.some(column => column.count !== 1) || columns[0].gap !== columns[1].gap ||
      geometries[0].orientation !== geometries[1].orientation || JSON.stringify(papers[0]) !== JSON.stringify(papers[1]) ||
      [previous, section].some(item => areas.areas.some(area => area.section === item.index) ||
        areas.variants.some(name => name.startsWith(`section${item.index}First`) ||
          name.startsWith(`section${item.index}Left`) || name.startsWith(`section${item.index}Right`)) ||
        item.elements.some(element => model.values(element)['break-after'] === 'column'))) {
      throw new DocumentError('pagedContinuous');
    }
  }
}

export function pagedCapability(model) {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  const areas = model.headerAreas();
  if (setup.reason || layout.reason || areas.reason) return 'pagedSettings';
  if (model.storedObjects().length) return 'pagedShape';
  try {
    continuousSections(model, layout, setup, areas);
  } catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    return 'pagedContinuous';
  }
  try {
    firstRight(model);
    const body = model.document.querySelector('body');
    if ([...body.childNodes].some(node => node.nodeType === 3 && node.data.trim())) return 'pagedShape';
    for (const section of layout.sections) {
      const paper = paperGeometry({ ...setup.geometry, ...setup.sections.get(section.index) });
      if (paper.width - paper.margins[1] - paper.margins[3] < 72 ||
        paper.height - paper.margins[0] - paper.margins[2] < 72) return 'pagedSettings';
      const columns = pagedColumnGeometry(model, section.index, paper);
      for (const element of section.elements) {
        if (columns.count > 1 && element.localName === 'table') return 'pagedColumns';
        if (element.localName === 'table' && (element.previousElementSibling?.localName !== 'p' ||
          element.nextElementSibling?.localName !== 'p')) return 'pagedShape';
        const blocks = element.localName === 'table' ?
          pagedTable(model, element).rows.flatMap(row => [...row.children].flatMap(cell => [...cell.children])) : [element];
        for (const block of blocks) for (const [index, paragraph] of bodyParagraphs(block).entries()) {
          const values = model.values(paragraph);
          const kind = pagedBreak(values);
          if (paragraph.querySelector('table,ul,ol') || ['width', 'height', 'min-height'].some(key => values[key]) ||
            paragraph.localName === 'li' && kind) return 'pagedShape';
          if (paragraph.localName === 'li') pageListMarker({ ...model.values(block), ...values },
            Number(block.getAttribute('start') || 1) + index, block.localName);
          for (const child of paragraph.querySelectorAll('*')) {
            if (model.values(child)['break-after'] === 'column') return 'pagedColumns';
            const formula = model.formula(child);
            if (formula && !formula.supported) return 'pagedShape';
            if (child.localName === 'img') inlineImage(model, child);
          }
        }
      }
    }
    for (const area of areas.areas) {
      if (headerContentReason(model, area.element) || model.headerPosition(area.name).reason ||
        [...area.element.querySelectorAll('p')].some(paragraph =>
          ['width', 'height', 'min-height'].some(key => model.values(paragraph)[key]))) return 'pagedAreas';
    }
  } catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    return ['pagedShape', 'pagedOverflow', 'pagedBand', 'pagedTables', 'pagedColumns'].includes(error.code) ? error.code : 'pagedSettings';
  }
  return null;
}

export function createPagedProjection(model, labels, decoded = new Map()) {
  // All rendering, scope changes and measurement belong to a disposable model.
  const copy = new WriteProDocument(model.serialize(), model.files, model.entry);
  const reason = pagedCapability(copy);
  if (reason) throw new DocumentError(reason);
  const state = copy.headerAreas();
  const rightFirst = firstRight(copy);
  const root = document.createElement('article');
  root.className = 'paper paged-document';
  root.setAttribute('aria-label', labels.pagedPreview);
  const staging = document.createElement('div');
  staging.className = 'paged-measure';
  staging.append(root);
  document.body.append(staging);
  const rendered = document.createElement('div');
  const rules = [];
  const used = new Set();
  let pageNumber = 0;
  const budget = { count: 0 };
  try {
    copy.render(rendered, labels);
    makeInert(rendered);
    const mappings = copy.projection;
    for (const source of copy.document.querySelectorAll('body img')) {
      const info = inlineImage(copy, source);
      const dimensions = decoded.get(info.src);
      if (!dimensions) throw new DocumentError('pagedUnavailable');
      const badge = mappings.get(source);
      const image = badge?.querySelector('img');
      if (!image) throw new DocumentError('pagedShape');
      const values = copy.values(source);
      let width = values.width ? pagePoints(values.width) : null;
      let height = values.height ? pagePoints(values.height) : null;
      width ??= height ? height * dimensions.width / dimensions.height : dimensions.width * .75;
      height ??= width * dimensions.height / dimensions.width;
      image.style.width = `${width}pt`;
      image.style.height = `${height}pt`;
      image.style.setProperty('--paged-image-height', `${height}pt`);
      image.style.maxWidth = 'none';
      image.style.maxHeight = 'none';
      image.loading = 'eager';
      badge.classList.add('paged-image');
    }
    const areaContent = new Map();
    for (const area of state.areas) {
      const content = document.createElement('div');
      copy.setScope(area.name);
      copy.render(content, labels);
      makeInert(content);
      content.removeAttribute('style');
      content.className = 'page-area';
      areaContent.set(area.name, content);
    }
    let firstPaper;
    let sheet;
    let flow;
    let columnIndex;
    let flows;
    let previous;
    for (const section of state.sections) {
      const setup = copy.sectionSetup(section.index);
      const paper = paperGeometry(setup.geometry);
      firstPaper ||= paper;
      const [top, right, bottom, left] = paper.margins;
      const columns = pagedColumnGeometry(copy, section.index, paper);
      const pageName = `wppaged${section.index}`;
      rules.push(`@page ${pageName} { size: ${paper.width}pt ${paper.height}pt; margin: 0; }`);
      let localPage = 0;
      const newPage = () => {
        if (++pageNumber > 500) throw new DocumentError('pagedOverflow');
        sheet = document.createElement('section');
        sheet.className = 'browser-page';
        sheet.dataset.page = String(pageNumber);
        sheet.dataset.section = String(section.index);
        sheet.setAttribute('aria-label', `${labels.pagedSheet} ${pageNumber} · ${labels.sectionLabel} ${section.index}`);
        sheet.style.width = `${paper.width}pt`;
        sheet.style.height = `${paper.height}pt`;
        sheet.style.page = pageName;
        const body = document.createElement('div');
        body.className = 'page-body';
        Object.assign(body.style, { top: `${top}pt`, left: `${left}pt`, right: `${right}pt`, bottom: `${bottom}pt` });
        flows = [body];
        columnIndex = 0;
        if (columns.count > 1) {
          body.classList.add('page-columns');
          body.style.gap = `${columns.gap}pt`;
          flows = Array.from({ length: columns.count }, (_, index) => {
            const column = document.createElement('div');
            column.className = 'page-column';
            column.dataset.column = String(index + 1);
            column.style.width = `${columns.width}pt`;
            body.append(column);
            return column;
          });
        }
        flow = flows[0];
        sheet.append(body);
        root.append(sheet);
        for (const kind of ['Header', 'Footer']) {
          const area = selectedPageArea(state, section.index, localPage === 0, pageNumber, rightFirst, kind);
          if (!area) continue;
          const position = copy.headerPosition(area.name);
          if (position.reason) throw new DocumentError('pagedAreas');
          const margins = Object.fromEntries(Object.entries(position.values).map(([side, value]) => [side, pagePoints(value)]));
          const content = areaContent.get(area.name).cloneNode(true);
          content.dataset.area = area.name;
          content.setAttribute('aria-label', areaLabel(area, labels));
          Object.assign(content.style, { left: `${margins.left}pt`, right: `${margins.right}pt` });
          const header = kind === 'Header';
          content.style[header ? 'top' : 'bottom'] = `${header ? margins.top : margins.bottom}pt`;
          sheet.append(content);
          const available = header ? top - margins.top - margins.bottom : bottom - margins.top - margins.bottom;
          if (available < 0 || margins.left + margins.right >= paper.width ||
            content.getBoundingClientRect().height > available * 4 / 3 + .25 ||
            content.scrollHeight > content.clientHeight + 1 ||
            content.scrollWidth > content.clientWidth + 1) throw new DocumentError('pagedAreas');
          used.add(area.name);
        }
        localPage++;
      };
      const nextColumn = () => {
        if (++columnIndex === columns.count) newPage();
        else flow = flows[columnIndex];
      };
      // A shared page already counts for the new section, without resetting physical numbering.
      if (previous && paragraphBreak(copy.values(previous.elements.at(-1))) === 'continuous') localPage = 1;
      else newPage();
      const fits = candidate => {
        const bounds = flow.getBoundingClientRect();
        const last = candidate.getBoundingClientRect();
        const margin = parseFloat(getComputedStyle(candidate).marginBottom) || 0;
        return last.top >= bounds.top - .25 && last.bottom + margin <= bounds.bottom + .25 && flow.scrollWidth <= flow.clientWidth + 1 &&
          [...candidate.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img,td,th')].every(run =>
            [...run.getClientRects()].every(rect => rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25 &&
              rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25));
      };
      for (const element of section.elements) {
        if (element.localName === 'table') {
          const { rows, headers, witness, merged, bands, resolved } = pagedTable(copy, element);
          const table = mappings.get(element);
          if (!table || table.localName !== 'table' ||
            table.querySelector('.preserved-object:not(.formula-object):not(.paged-image)')) throw new DocumentError('pagedTables');
          for (const row of rows) for (const cell of row.children) for (const block of cell.children) {
            if (block.localName === 'p') continue;
            const list = mappings.get(block);
            if (!list || !['ul', 'ol'].includes(list.localName)) throw new DocumentError('pagedTables');
            list.style.display = 'flow-root';
            for (const [index, item] of bodyParagraphs(block).entries()) {
              const content = mappings.get(item);
              if (!content || content.localName !== 'li') throw new DocumentError('pagedTables');
              prepareListItem(copy, block, item, index, content);
            }
          }
          table.dataset.section = String(section.index);
          for (const { segment } of new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(table.textContent)) {
            if (segment && ++budget.count > 100000) throw new DocumentError('pagedOverflow');
          }
          const align = copy.values(element)['-d4-table-align'];
          if (align && !['left', 'center', 'right'].includes(align)) throw new DocumentError('pagedTables');
          table.style.alignSelf = 'flex-start';
          if (align === 'center' || align === 'right') table.style.marginLeft = 'auto';
          if (align === 'center') table.style.marginRight = 'auto';
          // Measure the whole table once, then freeze its grid before selecting rows.
          // A no-witness grid is laid out on its natively resolved columns before that single measurement.
          const preset = resolved && document.createElement('colgroup');
          if (resolved) {
            preset.dataset.nativeColumns = '';
            for (const value of resolved) {
              const col = document.createElement('col');
              col.style.width = `${value}pt`;
              preset.append(col);
            }
            table.prepend(preset);
            table.style.tableLayout = 'fixed';
            table.style.width = `${resolved.reduce((sum, value) => sum + value, 0)}pt`;
            for (const row of table.rows) for (const cell of row.cells) cell.style.width = 'auto';
          }
          flow.append(table);
          const width = table.getBoundingClientRect().width;
          const widths = resolved ? resolved.map(value => value * 4 / 3) :
            [...table.rows[witness].cells].map(cell => cell.getBoundingClientRect().width);
          const reference = [...table.rows].map(row => [...row.cells].map(cell => {
            const bounds = cell.getBoundingClientRect();
            return { width: bounds.width, height: bounds.height };
          }));
          if (!width || widths.some(value => value <= 0)) throw new DocumentError('pagedUnavailable');
          if (resolved) {
            const bounds = flow.getBoundingClientRect();
            const box = table.getBoundingClientRect();
            if (box.left < bounds.left - .25 || box.right > bounds.right + .25) throw new DocumentError('pagedTables');
            const offsets = [0];
            for (const value of widths) offsets.push(offsets.at(-1) + value);
            const occupied = [...table.rows].map(() => Array(widths.length).fill(false));
            for (const [index, row] of [...table.rows].entries()) {
              let column = 0;
              for (const cell of row.cells) {
                while (occupied[index][column]) column++;
                for (let r = index; r < index + cell.rowSpan; r++) for (let c = column; c < column + cell.colSpan; c++) occupied[r][c] = true;
                if (Math.abs(cell.getBoundingClientRect().width - (offsets[column + cell.colSpan] - offsets[column])) > .25) throw new DocumentError('pagedTables');
                column += cell.colSpan;
              }
            }
          }
          for (const node of [table, ...table.querySelectorAll('tr,td,th,p,li,ul,ol')]) {
            const style = getComputedStyle(node);
            if (['marginTop', 'marginRight', 'marginBottom', 'marginLeft'].some(side => parseFloat(style[side]) < 0)) throw new DocumentError('pagedTables');
          }
          for (const cell of table.querySelectorAll('td,th')) {
            if (!merged && !cell.querySelector('.paged-list-marker')) continue;
            const bounds = cell.getBoundingClientRect();
            if (![...cell.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img')].every(run =>
              [...run.getClientRects()].every(rect => rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25 &&
                rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25))) throw new DocumentError('pagedTables');
          }
          // The frozen colgroup below carries the same resolved widths for every fragment.
          preset?.remove();
          table.style.width = `${width}px`;
          table.style.tableLayout = 'fixed';
          const cols = document.createElement('colgroup');
          for (const value of widths) {
            const col = document.createElement('col');
            col.style.width = `${value}px`;
            cols.append(col);
          }
          table.prepend(cols);
          for (const row of table.rows) for (const cell of row.cells) cell.style.width = 'auto';
          table.remove();
          let band = 0;
          let start = headers;
          let first = true;
          while (band < bands.length) {
            const fragment = table.cloneNode(false);
            fragment.append(cols.cloneNode(true));
            if (!first) fragment.style.marginTop = '0';
            const fragmentRows = document.createElement('tbody');
            fragment.append(fragmentRows);
            for (let index = 0; index < headers; index++) fragmentRows.append(mappings.get(rows[index]).cloneNode(true));
            flow.append(fragment);
            let end = start;
            let next = band;
            while (next < bands.length) {
              const added = [];
              for (let index = bands[next][0]; index < bands[next][1]; index++) {
                added.push(mappings.get(rows[index]).cloneNode(true));
              }
              fragmentRows.append(...added);
              fragment.style.marginBottom = bands[next][1] === rows.length ? table.style.marginBottom : '0';
              if (!fits(fragment)) { added.forEach(row => row.remove()); break; }
              end = bands[next][1];
              next++;
            }
            if (end === start) {
              fragment.remove();
              if (!flow.children.length) throw new DocumentError(bands[band][1] - bands[band][0] > 1 ? 'pagedBand' : 'pagedOverflow');
              newPage();
              continue;
            }
            fragment.style.marginBottom = end === rows.length ? table.style.marginBottom : '0';
            if (!fits(fragment)) throw new DocumentError('pagedOverflow');
            for (const [index, row] of [...fragmentRows.rows].entries()) {
              const original = reference[index < headers ? index : start + index - headers];
              for (const [column, cell] of [...row.cells].entries()) {
                const bounds = cell.getBoundingClientRect();
                if (Math.abs(bounds.width - original[column].width) > .25 ||
                  Math.abs(bounds.height - original[column].height) > .25) throw new DocumentError('pagedTables');
                if (merged && ![...cell.querySelectorAll('.text-run,.preserved-object,.paged-list-marker,img')].every(run =>
                  [...run.getClientRects()].every(rect => rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25 &&
                    rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25))) throw new DocumentError('pagedTables');
              }
            }
            start = end;
            band = next;
            first = false;
            if (band < bands.length) nextColumn();
          }
          continue;
        }
        const items = bodyParagraphs(element);
        for (const [itemIndex, item] of items.entries()) {
          const paragraph = mappings.get(item);
          if (!paragraph || !['p', 'li'].includes(paragraph.localName) ||
            paragraph.querySelector('.preserved-object:not(.formula-object):not(.paged-image)')) throw new DocumentError('pagedShape');
          paragraph.dataset.section = String(section.index);
          const wrap = (content, first = true, last = true) => {
            if (item.localName === 'p') return content;
            const list = mappings.get(element).cloneNode(false);
            if (element.localName === 'ol') list.setAttribute('start', String(Number(element.getAttribute('start') || 1) + itemIndex));
            if (itemIndex || !first) list.style.marginTop = '0';
            if (itemIndex !== items.length - 1 || !last) list.style.marginBottom = '0';
            prepareListItem(copy, element, item, itemIndex, content, first);
            list.style.display = 'flow-root';
            list.append(content);
            return list;
          };
          let block = wrap(paragraph);
          flow.append(block);
          if (['marginTop', 'marginRight', 'marginBottom', 'marginLeft'].some(side =>
            parseFloat(getComputedStyle(paragraph)[side]) < 0 || parseFloat(getComputedStyle(block)[side]) < 0)) throw new DocumentError('pagedShape');
          if (!flow.getBoundingClientRect().height) throw new DocumentError('pagedUnavailable');
          if (!fits(block)) {
            // Cut only at measured visual lines, keeping graphemes and inline atoms intact.
            paragraph.querySelector(':scope > .paged-list-marker')?.remove();
            const points = lineBoundaries(paragraph, budget);
            block.remove();
            let start = 0;
            while (start < points.length - 1) {
              let low = start + 1;
              let high = points.length - 1;
              let best = start;
              while (low <= high) {
                const end = Math.floor((low + high) / 2);
                block = wrap(paragraphFragment(paragraph, points[start], points[end], start === 0, end === points.length - 1),
                  start === 0, end === points.length - 1);
                flow.append(block);
                const fit = fits(block);
                block.remove();
                if (fit) { best = end; low = end + 1; } else high = end - 1;
              }
              if (best === start) {
                if (!flow.children.length) throw new DocumentError('pagedOverflow');
                nextColumn();
                continue;
              }
              block = wrap(paragraphFragment(paragraph, points[start], points[best], start === 0, best === points.length - 1),
                start === 0, best === points.length - 1);
              flow.append(block);
              if (!fits(block)) throw new DocumentError('pagedOverflow');
              start = best;
              if (start < points.length - 1) nextColumn();
            }
          }
        }
        if (element !== section.elements.at(-1)) {
          const kind = pagedBreak(copy.values(element));
          if (kind === 'page') newPage();
          if (kind === 'column') nextColumn();
        }
      }
      previous = section;
    }
    for (const page of root.querySelectorAll('.browser-page')) {
      page.dataset.sections = [...new Set([...page.querySelectorAll('.page-body [data-section]')].map(block => block.dataset.section))].join(' ');
    }
    const unused = state.areas.filter(area => !used.has(area.name));
    if (pageNumber + unused.length > 500) throw new DocumentError('pagedOverflow');
    for (const area of unused) {
      const appendix = document.createElement('section');
      appendix.className = 'browser-appendix paged-unused';
      appendix.style.page = 'wppaged1';
      appendix.style.width = `${firstPaper.width}pt`;
      appendix.style.height = `${firstPaper.height}pt`;
      const flow = document.createElement('div');
      flow.className = 'page-body';
      const [top, right, bottom, left] = firstPaper.margins;
      Object.assign(flow.style, { top: `${top}pt`, right: `${right}pt`, bottom: `${bottom}pt`, left: `${left}pt` });
      const notice = document.createElement('p');
      notice.textContent = labels.pagedUnused;
      const heading = document.createElement('h3');
      heading.textContent = areaLabel(area, labels);
      const content = areaContent.get(area.name);
      content.className = 'unused-area';
      flow.append(notice, heading, content);
      appendix.append(flow);
      root.append(appendix);
      if (content.getBoundingClientRect().bottom > flow.getBoundingClientRect().bottom + .25 ||
        content.scrollHeight > content.clientHeight + 1 ||
        flow.scrollWidth > flow.clientWidth + 1) throw new DocumentError('pagedAreas');
    }
    makeInert(root);
    root.remove();
    return { root, rules: rules.join('\n'), pages: pageNumber };
  } finally {
    staging.remove();
  }
}
