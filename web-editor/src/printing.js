import { WriteProDocument } from './document.js';
import { DocumentError } from './archive.js';
import { paperGeometry } from './layout-preview.js';
import { pagePoints } from './page-setup.js';
import { areaLabel } from './header-messages.js';

export function printCapability(model) {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  if (setup.reason || layout.reason) return 'printUnsupported';
  for (const section of layout.sections) {
    const columns = model.columnSetup(section.index);
    if (columns.reason) return 'printUnsupported';
    const paper = paperGeometry({ ...setup.geometry, ...setup.sections.get(section.index) });
    const width = (paper.width - paper.margins[1] - paper.margins[3] -
      (columns.settings.count - 1) * pagePoints(columns.settings.gap)) / columns.settings.count;
    if (width < 72 || paper.height - paper.margins[0] - paper.margins[2] < 72) return 'printTooSmall';
  }
  return null;
}

export function createPrintProjection(model, labels) {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  const reason = printCapability(model);
  if (reason) throw new DocumentError(reason);
  // Rendering registers editor mappings and cursor slots. Keep both off the live model.
  const copy = new WriteProDocument(model.serialize(), model.files, model.entry);
  const root = document.createElement('div');
  root.id = 'print-document';
  root.className = 'paper';
  copy.render(root, labels);
  root.removeAttribute('style');
  const rules = [];
  const pages = new Map();
  let previousBreak = null;
  for (const section of layout.sections) {
    const geometry = paperGeometry({ ...setup.geometry, ...setup.sections.get(section.index) });
    const key = JSON.stringify(geometry);
    if (!pages.has(key)) {
      const name = `wppaper${pages.size}`;
      pages.set(key, name);
      rules.push(`@page ${name} { size: ${geometry.width}pt ${geometry.height}pt; margin: ${geometry.margins.map(value => `${value}pt`).join(' ')}; }`);
    }
    const surface = root.querySelector(`.section-paper[data-section="${section.index}"]`);
    if (!surface) throw new DocumentError('printFailed');
    surface.removeAttribute('style');
    surface.style.page = pages.get(key);
    surface.style.setProperty('--print-height', `${geometry.height - geometry.margins[0] - geometry.margins[2]}pt`);
    if (previousBreak === 'section') surface.classList.add('print-new-page');
    previousBreak = surface.querySelector('.explicit-break:last-child')?.dataset.break;
  }
  root.style.page = pages.values().next().value;
  for (const marker of root.querySelectorAll('.explicit-break')) {
    if (marker.dataset.break === 'page' && marker.nextElementSibling) marker.nextElementSibling.classList.add('print-new-page');
    marker.remove();
  }
  const areas = copy.headerAreas().areas;
  if (areas.length) {
    const appendix = document.createElement('section');
    appendix.className = 'header-appendix';
    const notice = document.createElement('p');
    notice.textContent = labels.headerPrint;
    appendix.append(notice);
    for (const area of areas) {
      const heading = document.createElement('h3');
      heading.textContent = areaLabel(area, labels);
      const content = document.createElement('div');
      copy.setScope(area.name);
      if (copy.headerReason()) {
        content.textContent = labels[copy.headerReason()];
      } else copy.render(content, labels);
      appendix.append(heading, content);
    }
    root.append(appendix);
  }
  const objects = copy.storedObjects();
  if (objects.length) {
    const appendix = document.createElement('section');
    appendix.className = 'header-appendix object-appendix';
    const notice = document.createElement('p');
    notice.textContent = labels.objectHelp;
    appendix.append(notice);
    for (const item of objects) {
      const heading = document.createElement('h3');
      heading.textContent = `${labels[item.kind]} · ${item.id}`;
      const content = document.createElement('div');
      copy.setScope(item.name);
      if (copy.objectState().reason) content.textContent = labels.objectProtected;
      else copy.render(content, labels);
      appendix.append(heading, content);
    }
    root.append(appendix);
  }
  for (const element of root.querySelectorAll('*')) {
    for (const attribute of [...element.attributes]) {
      if (['contenteditable', 'tabindex', 'role', 'spellcheck', 'aria-label'].includes(attribute.name) ||
        attribute.name.startsWith('data-')) element.removeAttribute(attribute.name);
    }
    if (element.localName === 'img') element.loading = 'eager';
  }
  return { root, rules: rules.join('\n') };
}
