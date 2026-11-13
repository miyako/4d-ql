import * as css from 'css-tree';
import { DocumentError } from './archive.js';
import { pagePoints } from './page-setup.js';
import { headerContentReason } from './headers-footers.js';

export const objectFields = { width: 'width', height: 'height', x: '-d4-anchor-h-offset', y: '-d4-anchor-v-offset' };
export const placementFields = {
  page: '-d4-anchor-page', section: '-d4-anchor-section', hAlign: '-d4-anchor-h-align',
  vAlign: '-d4-anchor-v-align', layout: '-d4-anchor-layout',
};
export const placementProperties = [...Object.values(placementFields), 'z-index'];
const allowed = /^(width|height|padding(?:-(?:top|right|bottom|left))?|background-color|border(?:-(?:style|width|color))?|position|display|z-index|-d4-anchor-(?:page|section|origin|h-offset|v-offset|h-align|v-align|layout)|-d4-img-display-mode)$/;
export const objectScope = scope => scope.startsWith('object:');

function textBoxRule(document, element) {
  return objectRule(document, element);
}

function objectRule(document, element) {
  const name = element.getAttribute('class') || '';
  if (!(element.localName === 'div' ? /^_div[1-9]\d*$/ : /^_img[1-9]\d*$/).test(name)) throw new DocumentError('objectProtected');
  const found = [];
  for (const style of document.querySelectorAll('head style')) {
    const ast = css.parse(style.textContent, { positions: true });
    for (const rule of ast.children) if (rule.type === 'Rule' &&
      css.generate(rule.prelude) === `${element.localName}.${name}`) found.push({ style, rule });
  }
  if (document.querySelectorAll(`.${name}`).length !== 1 || found.length !== 1) {
    throw new DocumentError('objectProtected');
  }
  return found[0];
}

function patchRule({ style }, patches) {
  style.textContent = patchText(style.textContent, patches);
}

function patchText(text, patches) {
  for (const { start, end, value } of patches.sort((a, b) => b.start - a.start)) text = text.slice(0, start) + value + text.slice(end);
  return text;
}

function stripInlineProperties(element, properties) {
  const text = element.getAttribute('style');
  if (text === null) return;
  const ast = css.parse(text, { context: 'declarationList', positions: true });
  const patches = [...ast.children].filter(node => node.type === 'Declaration' && properties.includes(node.property))
    .map(node => ({
      start: node.loc.start.offset, end: node.loc.end.offset + (text[node.loc.end.offset] === ';' ? 1 : 0), value: '',
    }));
  if (!patches.length) return;
  const result = patchText(text, patches);
  if (result.trim()) element.setAttribute('style', result);
  else element.removeAttribute('style');
}

export function setTextBoxGeometry(document, element, changes) {
  const target = textBoxRule(document, element);
  const properties = Object.fromEntries(Object.entries(changes).map(([field, value]) => [objectFields[field], value]));
  patchProperties(target, properties);
}

function patchProperties(target, properties) {
  const found = new Set(), patches = [];
  for (const node of target.rule.block.children) {
    if (node.type !== 'Declaration' || !Object.hasOwn(properties, node.property)) continue;
    found.add(node.property);
    patches.push(properties[node.property] === null ? {
      start: node.loc.start.offset,
      end: node.loc.end.offset + (target.style.textContent[node.loc.end.offset] === ';' ? 1 : 0), value: '',
    } : { start: node.value.loc.start.offset, end: node.value.loc.end.offset, value: properties[node.property] });
  }
  const missing = Object.entries(properties).filter(([property, value]) => value !== null && !found.has(property))
    .map(([property, value]) => `${property}:${value};`).join('');
  const start = target.rule.block.loc.start.offset + 1;
  if (missing) patches.push({ start, end: start, value: missing });
  patchRule(target, patches);
}

export function objectPlacement(model) {
  const state = model.objectState();
  const values = Object.fromEntries(Object.entries(placementFields).map(([field, property]) =>
    [field, state.values[property] || ({ page: 'all', section: 'all', hAlign: 'offset', vAlign: 'offset', layout: 'front' })[field]]));
  // Native left/top are zero (offset mode), not independently stored alignments.
  if (values.hAlign === 'left') values.hAlign = 'offset';
  if (values.vAlign === 'top') values.vAlign = 'offset';
  let reason = state.reason;
  try { if (!reason) objectRule(model.document, state.item.element); }
  catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    reason = 'objectProtected';
  }
  return { ...state, values, reason };
}

export function validatePlacement(model, values) {
  const index = value => value === 'all' || typeof value === 'string' && /^[1-9]\d*$/.test(value) &&
    Number.isSafeInteger(Number(value)) && Number(value) <= 10000;
  if (Object.keys(values).length !== 5 || Object.keys(values).some(key => !Object.hasOwn(placementFields, key)) ||
    !index(values.page) || !index(values.section) ||
    values.section !== 'all' && (values.page !== 'all' || Number(values.section) > model.sectionLayout().sections.length) ||
    !['offset', 'center', 'right'].includes(values.hAlign) ||
    !['offset', 'center', 'bottom'].includes(values.vAlign) ||
    !['front', 'behind', 'wrap-square'].includes(values.layout)) throw new DocumentError('objectPlacementInvalid');
}

export function setObjectPlacement(model, state, changes) {
  const properties = Object.fromEntries(Object.entries(changes).map(([field, value]) =>
    [placementFields[field], value === 'offset' || value === 'all' ? null : value]));
  if (Object.hasOwn(changes, 'layout')) properties['z-index'] = changes.layout === 'behind' ? '-1' : null;
  patchProperties(objectRule(model.document, state.item.element), properties);
  stripInlineProperties(state.item.element, Object.keys(properties));
}

export function objectCreationReason(model) {
  return model.sectionLayout().reason || model.headerAreas().reason ? 'objectProtected' : null;
}

export function newObjectIdentity(model, kind) {
  if (!['textBox', 'anchoredPicture'].includes(kind) || objectCreationReason(model)) throw new DocumentError('objectProtected');
  const source = model.serialize();
  const prefix = kind === 'textBox' ? 'textBox' : 'img', classPrefix = kind === 'textBox' ? '_div' : '_img';
  let index = 1;
  // Include opaque references and orphaned CSS, not just live IDs. Never reuse their identities.
  for (const match of source.matchAll(new RegExp(`(?:${prefix}|${classPrefix})(\\d+)`, 'g'))) {
    if (!Number.isSafeInteger(Number(match[1])) || Number(match[1]) >= 1000000) throw new DocumentError('objectProtected');
    index = Math.max(index, Number(match[1]) + 1);
  }
  return { id: `${prefix}${index}`, className: `${classPrefix}${index}` };
}

export function objectDeletionReason(model) {
  const state = model.objectState();
  if (state.reason) return state.reason;
  if ([state.item.element, ...state.item.element.querySelectorAll('*')].some(element => model.formula(element))) return 'objectDeleteProtected';
  const outside = model.document.cloneNode(true);
  [...outside.querySelectorAll('body > *')].find(element => element.id === state.item.id).remove();
  if (new RegExp(`(^|[^\\w-])${state.item.id}([^\\w-]|$)`).test(new XMLSerializer().serializeToString(outside))) return 'objectDeleteProtected';
  return null;
}

export function outsideObjectChange(document, plan) {
  const copy = document.cloneNode(true);
  [...copy.querySelectorAll('body > *')].find(element => element.id === plan.id)?.remove();
  if (plan.style) [...copy.querySelectorAll('head > style')].find(element => element.textContent === plan.style)?.remove();
  return new XMLSerializer().serializeToString(copy);
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
      values['z-index'] && values['z-index'] !== '-1' ||
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
      if ([...inline.children].some(node => [...Object.values(objectFields), ...placementProperties, '-d4-anchor-origin']
        .includes(node.property))) throw new DocumentError('objectProtected');
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
    const properties = Array.isArray(geometry) ? geometry : Object.values(objectFields);
    if (element.localName === 'div' || Array.isArray(geometry)) {
      const target = objectRule(copy, element);
      patchRule(target, [...target.rule.block.children].filter(node =>
        node.type === 'Declaration' && properties.includes(node.property)).map(node => ({
        start: node.loc.start.offset,
        end: node.loc.end.offset + (target.style.textContent[node.loc.end.offset] === ';' ? 1 : 0), value: '',
      })));
    }
    if (Array.isArray(geometry)) stripInlineProperties(element, properties);
    else {
      const ast = css.parse(element.getAttribute('style') || '', { context: 'declarationList' });
      ast.children.forEach((node, item) => {
        if (node.type === 'Declaration' && properties.includes(node.property)) ast.children.remove(item);
      });
      const style = css.generate(ast);
      if (style) element.setAttribute('style', style);
      else element.removeAttribute('style');
    }
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
