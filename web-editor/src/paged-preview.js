import * as css from 'css-tree';
import { WriteProDocument } from './document.js';
import { DocumentError } from './archive.js';
import { paperGeometry } from './layout-preview.js';
import { pagePoints } from './page-setup.js';
import { paragraphBreak } from './sections.js';
import { areaLabel } from './header-messages.js';
import { headerContentReason } from './headers-footers.js';

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
        const values = model.values(element);
        if (element.localName !== 'p' || element.querySelector('img,table,ul,ol') ||
          ['width', 'height', 'min-height'].some(key => values[key]) ||
          paragraphBreak(values) === 'continuous') return 'pagedShape';
        for (const child of element.querySelectorAll('*')) {
          const formula = model.formula(child);
          if (formula && !formula.supported) return 'pagedShape';
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
    return 'pagedSettings';
  }
  return null;
}

export function createPagedProjection(model, labels) {
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
  try {
    copy.render(rendered, labels);
    const mappings = copy.projection;
    const areaContent = new Map();
    for (const area of state.areas) {
      const content = document.createElement('div');
      copy.setScope(area.name);
      copy.render(content, labels);
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
      for (const element of section.elements) {
        const paragraph = mappings.get(element);
        if (!paragraph || paragraph.localName !== 'p' ||
          paragraph.querySelector('.preserved-object:not(.formula-object)')) throw new DocumentError('pagedShape');
        flow.append(paragraph);
        if (['marginTop', 'marginRight', 'marginBottom', 'marginLeft'].some(side =>
          parseFloat(getComputedStyle(paragraph)[side]) < 0)) throw new DocumentError('pagedShape');
        const fits = () => {
          const bounds = flow.getBoundingClientRect();
          const last = paragraph.getBoundingClientRect();
          const margin = parseFloat(getComputedStyle(paragraph).marginBottom) || 0;
          return last.bottom + margin <= bounds.bottom + .25 && flow.scrollWidth <= flow.clientWidth + 1 &&
            [...paragraph.querySelectorAll('.text-run,.formula-object')].every(run =>
              [...run.getClientRects()].every(rect => rect.top >= bounds.top - .25 && rect.bottom <= bounds.bottom + .25 &&
                rect.left >= bounds.left - .25 && rect.right <= bounds.right + .25));
        };
        if (!flow.getBoundingClientRect().height) throw new DocumentError('pagedUnavailable');
        if (!fits()) {
          paragraph.remove();
          if (!flow.children.length) throw new DocumentError('pagedOverflow');
          newPage();
          flow.append(paragraph);
          if (!fits()) throw new DocumentError('pagedOverflow');
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
    for (const element of root.querySelectorAll('*')) {
      for (const attribute of [...element.attributes]) {
        if (['contenteditable', 'tabindex', 'role', 'spellcheck'].includes(attribute.name) ||
          attribute.name.startsWith('data-') && !['data-page', 'data-section', 'data-area'].includes(attribute.name)) element.removeAttribute(attribute.name);
      }
      if (element.localName === 'span' && element.classList.contains('text-run')) element.style.whiteSpace = 'pre-wrap';
    }
    root.remove();
    return { root, rules: rules.join('\n'), pages: pageNumber };
  } finally {
    staging.remove();
  }
}
