import * as css from 'css-tree';
import { DocumentError } from './archive.js';
import { pagePoints } from './page-setup.js';
import { areaRules, headerContentReason } from './headers-footers.js';

export const objectFields = { width: 'width', height: 'height', x: '-d4-anchor-h-offset', y: '-d4-anchor-v-offset' };
const allowed = /^(width|height|padding(?:-(?:top|right|bottom|left))?|background-color|border(?:-(?:style|width|color))?|position|display|z-index|-d4-anchor-(?:page|section|origin|h-offset|v-offset|h-align|v-align|layout)|-d4-img-display-mode)$/;
export const objectScope = scope => scope.startsWith('object:');

function textBoxRule(document, element) {
  const name = `_div${element.id.slice(7)}`;
  const found = areaRules(document, name);
  if (element.getAttribute('class') !== name || document.querySelectorAll(`.${name}`).length !== 1 || found.length !== 1) {
    throw new DocumentError('objectProtected');
  }
  return found[0];
}

function patchRule({ style }, patches) {
  let text = style.textContent;
  for (const { start, end, value } of patches.sort((a, b) => b.start - a.start)) text = text.slice(0, start) + value + text.slice(end);
  style.textContent = text;
}

export function setTextBoxGeometry(document, element, changes) {
  const target = textBoxRule(document, element);
  const properties = Object.fromEntries(Object.entries(changes).map(([field, value]) => [objectFields[field], value]));
  const found = new Set(), patches = [];
  for (const node of target.rule.block.children) {
    if (node.type !== 'Declaration' || !Object.hasOwn(properties, node.property)) continue;
    found.add(node.property);
    patches.push({ start: node.value.loc.start.offset, end: node.value.loc.end.offset, value: properties[node.property] });
  }
  const missing = Object.entries(properties).filter(([property]) => !found.has(property)).map(([property, value]) => `${property}:${value};`).join('');
  const start = target.rule.block.loc.start.offset + 1;
  if (missing) patches.push({ start, end: start, value: missing });
  patchRule(target, patches);
}

export function storedObjects(model) {
  const body = model.document.querySelector('body');
  return [...body.children].filter(element => ['img', 'div'].includes(element.localName) &&
    (Object.keys(model.values(element)).some(key => key.startsWith('-d4-anchor-')) ||
      /^(?:textBox|img)\d+$/.test(element.id))).map(element => ({
    element, id: element.id, name: `object:${element.id}`, kind: element.localName === 'div' ? 'textBox' : 'anchoredPicture',
  }));
}

export function objectState(model, name = model.scope) {
  const item = storedObjects(model).find(item => item.name === name);
  const values = item ? model.values(item.element) : {};
  const geometry = Object.fromEntries(Object.entries(objectFields).map(([field, property]) =>
    [field, values[property] || (['width', 'height'].includes(field) ? 'auto' : '0pt')]));
  let reason = null;
  try {
    if (!item || !/^(?:textBox|img)[1-9]\d*$/.test(item.id) ||
      [...model.document.querySelectorAll('[id]')].filter(element => element.id === item.id).length !== 1 ||
      (item.kind === 'textBox') !== item.id.startsWith('textBox') ||
      item.element.namespaceURI !== 'http://www.w3.org/1999/xhtml' ||
      [...item.element.attributes].some(attribute => !['id', 'class', 'style', ...(item.kind === 'textBox' ? [] : ['src', 'alt'])].includes(attribute.name)) ||
      Object.keys(values).some(key => !allowed.test(key)) ||
      values.position !== 'absolute' || values.display !== 'none' ||
      !['front', 'behind', 'wrap-square'].includes(values['-d4-anchor-layout']) ||
      values['-d4-anchor-origin'] && values['-d4-anchor-origin'] !== 'paper-box' ||
      values['-d4-anchor-h-align'] && !['left', 'center', 'right'].includes(values['-d4-anchor-h-align']) ||
      values['-d4-anchor-v-align'] && !['top', 'center', 'bottom'].includes(values['-d4-anchor-v-align']) ||
      model.sectionLayout().reason) throw new DocumentError('objectProtected');
    validateObjectGeometry(Object.fromEntries(Object.entries(geometry).filter(([, value]) => value !== 'auto')));
    if (values['-d4-img-display-mode'] && !['scaledToFit', 'proportional', 'proportionalCentered', 'truncated', 'truncatedCentered']
      .includes(values['-d4-img-display-mode'])) throw new DocumentError('objectProtected');
    const section = values['-d4-anchor-section'];
    const page = values['-d4-anchor-page'];
    if (section && section !== 'all' && (!/^[1-9]\d*$/.test(section) || Number(section) > model.sectionLayout().sections.length) ||
      page && page !== 'all' && (!/^[1-9]\d*$/.test(page) || !Number.isSafeInteger(Number(page)))) throw new DocumentError('objectProtected');
    let trailing = false;
    for (const element of model.document.querySelector('body').children) {
      if (element === item.element) trailing = true;
      else if (trailing && ['p', 'table', 'ul', 'ol'].includes(element.localName)) throw new DocumentError('objectProtected');
    }
    // Reject metadata hidden in conditional/complex/important selectors that the safe cascade ignores.
    for (const style of model.document.querySelectorAll('head style')) {
      const ast = css.parse(style.textContent, { onParseError: () => { throw new DocumentError('objectProtected'); } });
      css.walk(ast, node => {
        if (node.type !== 'Rule') return;
        const selector = css.generate(node.prelude);
        let matches;
        try { matches = item.element.matches(selector); } catch { matches = true; }
        const references = selector.split(/[^\w-]+/).some(token => token === item.id || item.element.classList.contains(token));
        if (!matches && !references) return;
        if (![...ast.children].includes(node) || selector !== `${item.element.localName}.${[...item.element.classList].join('.')}` ||
          [...node.block.children].some(declaration => declaration.type !== 'Declaration' || declaration.important)) throw new DocumentError('objectProtected');
      });
    }
    const inline = css.parse(item.element.getAttribute('style') || '', {
      context: 'declarationList', onParseError: () => { throw new DocumentError('objectProtected'); },
    });
    if ([...inline.children].some(node => node.type !== 'Declaration' || node.important)) throw new DocumentError('objectProtected');
    if (item.kind === 'textBox') {
      textBoxRule(model.document, item.element);
      // 4D imports box geometry from its identity-owned class, ignoring inline overrides.
      if ([...inline.children].some(node => Object.values(objectFields).includes(node.property))) throw new DocumentError('objectProtected');
    }
    if (item.kind === 'anchoredPicture' && (!model.imageSource(item.element) || model.formula(item.element)) ||
      item.kind === 'textBox' && ([...item.element.querySelectorAll('[id]')].length ||
        headerContentReason(model, item.element, true))) throw new DocumentError('objectProtected');
  } catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    reason = 'objectProtected';
  }
  // Alignment and auto dimensions are preserved, not reinterpreted as offsets/sizes.
  const geometryReason = reason || (values['-d4-anchor-h-align'] || values['-d4-anchor-v-align'] ? 'objectAligned' : null);
  return { item, values, geometry, reason, geometryReason };
}

export function outsideObject(document, id, geometry = false) {
  const copy = document.cloneNode(true);
  const element = [...copy.querySelectorAll('body > *')].find(element => element.id === id);
  if (!element) throw new DocumentError('objectProtected');
  if (geometry) {
    if (element.localName === 'div') {
      const target = textBoxRule(copy, element);
      patchRule(target, [...target.rule.block.children].filter(node =>
        node.type === 'Declaration' && Object.values(objectFields).includes(node.property)).map(node => ({
        start: node.loc.start.offset,
        end: node.loc.end.offset + (target.style.textContent[node.loc.end.offset] === ';' ? 1 : 0), value: '',
      })));
    }
    const ast = css.parse(element.getAttribute('style') || '', { context: 'declarationList' });
    ast.children.forEach((node, item) => {
      if (node.type === 'Declaration' && Object.values(objectFields).includes(node.property)) ast.children.remove(item);
    });
    const style = css.generate(ast);
    if (style) element.setAttribute('style', style);
    else element.removeAttribute('style');
  }
  else element.replaceChildren();
  return new XMLSerializer().serializeToString(copy);
}

export function validateObjectGeometry(changes) {
  if (!changes || !Object.keys(changes).length || Object.keys(changes).some(key => !Object.hasOwn(objectFields, key))) throw new DocumentError('objectInvalid');
  for (const [field, value] of Object.entries(changes)) {
    let points;
    try { points = pagePoints(value); } catch { throw new DocumentError('objectInvalid'); }
    if (points > 1200 || ['width', 'height'].includes(field) && points < 1) throw new DocumentError('objectInvalid');
  }
}
