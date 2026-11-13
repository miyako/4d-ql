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

export function pageListMarker(values, number, kind) {
  const type = values['-d4-list-style-type'] || values['list-style-type'] || (kind === 'ol' ? 'decimal' : 'disc');
  if (Object.keys(values).some(key => key.startsWith('-d4-list-') &&
    !['-d4-list-style-type', '-d4-list-string-format-ltr', '-d4-list-font'].includes(key))) throw new DocumentError('pagedShape');
  if (!Number.isSafeInteger(number) || number < 1 || number > 3999) throw new DocumentError('pagedShape');
  if (Object.hasOwn(bullets, type)) return bullets[type];
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

function pagedTable(model, element) {
  try {
    if (element.children.length > 1000 || element.querySelectorAll('td,th').length > 10000) throw new DocumentError('pagedTables');
    const grid = nativeTableGrid(element);
    if (grid.merged || grid.rows.length > 1000 || grid.rows.length * grid.columns > 10000 ||
      element.previousElementSibling?.localName !== 'p' || element.nextElementSibling?.localName !== 'p') throw new DocumentError('pagedTables');
    let headers = 0;
    for (const [index, row] of grid.rows.entries()) {
      const header = model.values(row)['-d4-header'];
      if ((header && header !== 'true' && header !== 'false') ||
        (header === 'true' && headers !== index)) throw new DocumentError('pagedTables');
      if (header === 'true') headers++;
      for (const cell of row.children) {
        if (!cell.children.length || [...cell.childNodes].some(node => node.nodeType === 3 && node.data.trim())) throw new DocumentError('pagedTables');
        for (const block of cell.children) {
          if (block.localName !== 'p') throw new DocumentError('pagedTables');
          bodyParagraphs(block);
        }
      }
    }
    if (headers === grid.rows.length) throw new DocumentError('pagedTables');
    for (const node of [element, ...element.querySelectorAll('*')]) {
      const values = model.values(node);
      if (Object.keys(values).some(key => /^-d4-(ref|anchor)/.test(key) && !model.formula(node)?.supported) ||
        values.display === 'none' || ['hidden', 'collapse'].includes(values.visibility) ||
        paragraphBreak(values) || (node.localName !== 'img' &&
        ['height', 'min-height', 'max-height'].some(key => values[key]))) throw new DocumentError('pagedTables');
    }
    return { ...grid, headers };
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
  fragment.append(range.cloneContents());
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
        attribute.name.startsWith('data-') && !['data-page', 'data-section', 'data-area'].includes(attribute.name)) element.removeAttribute(attribute.name);
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

export function pagedCapability(model) {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  const areas = model.headerAreas();
  if (setup.reason || layout.reason || areas.reason) return 'pagedSettings';
  if (model.storedObjects().length) return 'pagedShape';
  try {
    firstRight(model);
    const body = model.document.querySelector('body');
    if ([...body.childNodes].some(node => node.nodeType === 3 && node.data.trim())) return 'pagedShape';
    for (const section of layout.sections) {
      const columns = model.columnSetup(section.index);
      if (columns.reason) return 'pagedSettings';
      if (columns.settings.count !== 1) return 'pagedShape';
      const paper = paperGeometry({ ...setup.geometry, ...setup.sections.get(section.index) });
      if (paper.width - paper.margins[1] - paper.margins[3] < 72 ||
        paper.height - paper.margins[0] - paper.margins[2] < 72) return 'pagedSettings';
      for (const element of section.elements) {
        if (element.localName === 'table' && (element.previousElementSibling?.localName !== 'p' ||
          element.nextElementSibling?.localName !== 'p')) return 'pagedShape';
        const blocks = element.localName === 'table' ?
          pagedTable(model, element).rows.flatMap(row => [...row.children].flatMap(cell => [...cell.children])) : [element];
        for (const block of blocks) for (const [index, paragraph] of bodyParagraphs(block).entries()) {
          const values = model.values(paragraph);
          if (paragraph.querySelector('table,ul,ol') || ['width', 'height', 'min-height'].some(key => values[key]) ||
            paragraphBreak(values) === 'continuous' || paragraph.localName === 'li' && paragraphBreak(values)) return 'pagedShape';
          if (paragraph.localName === 'li') pageListMarker({ ...model.values(block), ...values },
            Number(block.getAttribute('start') || 1) + index, block.localName);
          for (const child of paragraph.querySelectorAll('*')) {
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
    return ['pagedShape', 'pagedOverflow', 'pagedTables'].includes(error.code) ? error.code : 'pagedSettings';
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
    for (const section of state.sections) {
      const setup = copy.sectionSetup(section.index);
      const paper = paperGeometry(setup.geometry);
      firstPaper ||= paper;
      const [top, right, bottom, left] = paper.margins;
      const pageName = `wppaged${section.index}`;
      rules.push(`@page ${pageName} { size: ${paper.width}pt ${paper.height}pt; margin: 0; }`);
      let sheet;
      let flow;
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
        flow = document.createElement('div');
        flow.className = 'page-body';
        Object.assign(flow.style, { top: `${top}pt`, left: `${left}pt`, right: `${right}pt`, bottom: `${bottom}pt` });
        sheet.append(flow);
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
      newPage();
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
          const { rows, headers } = pagedTable(copy, element);
          const table = mappings.get(element);
          if (!table || table.localName !== 'table' ||
            table.querySelector('.preserved-object:not(.formula-object):not(.paged-image)')) throw new DocumentError('pagedTables');
          for (const { segment } of new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(table.textContent)) {
            if (segment && ++budget.count > 100000) throw new DocumentError('pagedOverflow');
          }
          const align = copy.values(element)['-d4-table-align'];
          if (align && !['left', 'center', 'right'].includes(align)) throw new DocumentError('pagedTables');
          table.style.alignSelf = 'flex-start';
          if (align === 'center' || align === 'right') table.style.marginLeft = 'auto';
          if (align === 'center') table.style.marginRight = 'auto';
          // Measure the whole table once, then freeze its grid before selecting rows.
          flow.append(table);
          const width = table.getBoundingClientRect().width;
          const widths = [...table.rows[0].cells].map(cell => cell.getBoundingClientRect().width);
          const reference = [...table.rows].map(row => [...row.cells].map(cell => {
            const bounds = cell.getBoundingClientRect();
            return { width: bounds.width, height: bounds.height };
          }));
          if (!width || widths.some(value => value <= 0)) throw new DocumentError('pagedUnavailable');
          for (const node of [table, ...table.querySelectorAll('tr,td,th,p,li,ul,ol')]) {
            const style = getComputedStyle(node);
            if (['marginTop', 'marginRight', 'marginBottom', 'marginLeft'].some(side => parseFloat(style[side]) < 0)) throw new DocumentError('pagedTables');
          }
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
          let start = headers;
          let first = true;
          while (start < rows.length) {
            const fragment = table.cloneNode(false);
            fragment.append(cols.cloneNode(true));
            if (!first) fragment.style.marginTop = '0';
            const fragmentRows = document.createElement('tbody');
            fragment.append(fragmentRows);
            for (let index = 0; index < headers; index++) fragmentRows.append(mappings.get(rows[index]).cloneNode(true));
            flow.append(fragment);
            let end = start;
            while (end < rows.length) {
              const row = mappings.get(rows[end]).cloneNode(true);
              fragmentRows.append(row);
              fragment.style.marginBottom = end === rows.length - 1 ? table.style.marginBottom : '0';
              if (!fits(fragment)) { row.remove(); break; }
              end++;
            }
            if (end === start) {
              fragment.remove();
              if (!flow.children.length) throw new DocumentError('pagedOverflow');
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
              }
            }
            start = end;
            first = false;
            if (start < rows.length) newPage();
          }
          continue;
        }
        const items = bodyParagraphs(element);
        for (const [itemIndex, item] of items.entries()) {
          const paragraph = mappings.get(item);
          if (!paragraph || !['p', 'li'].includes(paragraph.localName) ||
            paragraph.querySelector('.preserved-object:not(.formula-object):not(.paged-image)')) throw new DocumentError('pagedShape');
          const wrap = (content, first = true, last = true) => {
            if (item.localName === 'p') return content;
            const list = mappings.get(element).cloneNode(false);
            if (element.localName === 'ol') list.setAttribute('start', String(Number(element.getAttribute('start') || 1) + itemIndex));
            if (itemIndex || !first) list.style.marginTop = '0';
            if (itemIndex !== items.length - 1 || !last) list.style.marginBottom = '0';
            content.style.listStyleType = 'none';
            content.style.position = 'relative';
            if (first) {
              const marker = document.createElement('span');
              marker.className = 'paged-list-marker';
              marker.textContent = pageListMarker({ ...copy.values(element), ...copy.values(item) },
                Number(element.getAttribute('start') || 1) + itemIndex, element.localName);
              const font = copy.values(item)['-d4-list-font'];
              if (font && !/url|expression|var\(|[;{}]/i.test(font)) marker.style.fontFamily = font;
              content.prepend(marker);
            }
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
                newPage();
                continue;
              }
              block = wrap(paragraphFragment(paragraph, points[start], points[best], start === 0, best === points.length - 1),
                start === 0, best === points.length - 1);
              flow.append(block);
              if (!fits(block)) throw new DocumentError('pagedOverflow');
              start = best;
              if (start < points.length - 1) newPage();
            }
          }
        }
        if (paragraphBreak(copy.values(element)) === 'page' && element !== section.elements.at(-1)) newPage();
      }
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
