import * as css from 'css-tree';
import { DocumentError } from './archive.js';
import { pagePoints, pagePaperSize } from './page-setup.js';

export const areaClass = /^section([1-9]\d*)(First|Left|Right)?(Header|Footer)$/;
const XHTML = 'http://www.w3.org/1999/xhtml';
const inline = new Set(['span', 'a', 'br', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup']);

export function headerAreas(model) {
  const layout = model.sectionLayout();
  const areas = [];
  let reason = layout.reason ? 'headerAssociation' : null;
  const enabled = new Set();
  try {
    for (const style of model.document.querySelectorAll('head style')) {
      const ast = css.parse(style.textContent, { onParseError: () => { throw new Error('CSS'); } });
      css.walk(ast, node => {
        if (node.type !== 'Rule') return;
        const selector = css.generate(node.prelude);
        if (!/section\d+(?:First|Left|Right|Header|Footer)/i.test(selector)) return;
        if (!/^div\.section[1-9]\d*(?:(?:First|Left|Right)?(?:Header|Footer)?)$/.test(selector) ||
          ![...ast.children].includes(node)) throw new Error('association');
        if (/^div\.section\d+(First|Left|Right)$/.test(selector) &&
          ![...node.block.children].some(declaration => declaration.type === 'Declaration' &&
            declaration.property === 'white-space' && !declaration.important &&
            css.generate(declaration.value) === 'normal')) throw new Error('variant');
        enabled.add(selector.slice(4));
      });
    }
  } catch { reason = 'headerAssociation'; }
  for (const element of model.document.querySelectorAll('body *')) {
    const name = element.getAttribute('class') || '';
    if (!/section\d.*(Header|Footer)/i.test(name)) continue;
    const match = name.match(areaClass);
    if (!match || element.localName !== 'div' || element.parentElement.localName !== 'body' ||
      Number(match[1]) > layout.sections.length || areas.some(area => area.name === name)) {
      reason = 'headerAssociation';
      continue;
    }
    const variant = match[2] || '';
    if (variant && (!enabled.has(`section${match[1]}${variant}`) ||
      ['Left', 'Right'].includes(variant) && (!enabled.has(`section${match[1]}Left`) || !enabled.has(`section${match[1]}Right`)))) reason = 'headerAssociation';
    areas.push({ name, section: Number(match[1]), variant, kind: match[3], element });
  }
  let trailing = false;
  for (const element of model.document.querySelector('body').children) {
    if (areas.some(area => area.element === element)) trailing = true;
    else if (trailing && ['p', 'table', 'ul', 'ol'].includes(element.localName)) reason = 'headerAssociation';
  }
  for (const name of enabled) {
    if (areaClass.test(name) && !areas.some(area => area.name === name)) reason = 'headerAssociation';
    const match = name.match(/^section(\d+)(First|Left|Right)$/);
    if (match && (Number(match[1]) > layout.sections.length ||
      match[2] !== 'First' && (!enabled.has(`section${match[1]}Left`) || !enabled.has(`section${match[1]}Right`)))) reason = 'headerAssociation';
  }
  return { areas, reason, sections: layout.sections, variants: [...enabled].filter(name => /^section\d+(First|Left|Right)$/.test(name)) };
}

export const areaSides = ['top', 'right', 'bottom', 'left'];

export function areaRules(document, name) {
  const found = [];
  for (const style of document.querySelectorAll('head style')) {
    const ast = css.parse(style.textContent, { positions: true, onParseError: () => { throw new DocumentError('headerAssociation'); } });
    for (const rule of ast.children) if (rule.type === 'Rule' && css.generate(rule.prelude) === `div.${name}`) {
      found.push({ style, rule, text: style.textContent.slice(rule.block.loc.start.offset, rule.block.loc.end.offset) });
    }
  }
  return found;
}

export function variantPlan(model, section, variant, enabled) {
  const state = model.headerAreas();
  if (state.reason || !state.sections.some(item => item.index === section) ||
    !['First', 'Left', 'Right'].includes(variant) || typeof enabled !== 'boolean') throw new DocumentError('headerAssociation');
  const variants = variant === 'First' ? ['First'] : ['Left', 'Right'];
  const names = variants.flatMap(value => [`section${section}${value}`, `section${section}${value}Header`, `section${section}${value}Footer`]);
  const active = state.variants.includes(`section${section}${variant}`);
  if (active === enabled) return { names: [], sources: [], areas: [], copies: [] };
  const areas = state.areas.filter(area => area.section === section && variants.includes(area.variant));
  const sources = enabled ? state.areas.filter(area => area.section === section && !area.variant) : [];
  for (const name of names) {
    for (const { rule } of areaRules(model.document, name)) {
      if (enabled || ![...rule.block.children].every(node => node.type === 'Declaration' &&
        !node.important && (name.endsWith('Header') || name.endsWith('Footer') ?
          node.property === 'margin' : node.property === 'white-space' && css.generate(node.value) === 'normal'))) {
        throw new DocumentError('headerVariantProtected');
      }
    }
  }
  for (const area of [...areas, ...sources]) {
    if (headerContentReason(model, area.element) ||
      [...area.element.attributes].some(attribute => !['class', 'style'].includes(attribute.name)) ||
      [...area.element.querySelectorAll('*')].some(element => element.hasAttribute('id') ||
        !enabled && model.formula(element))) throw new DocumentError('headerVariantProtected');
  }
  for (const area of sources) {
    if (areaPosition(model, area.name).reason || areaRules(model.document, area.name).some(({ rule }) =>
      ![...rule.block.children].every(node => node.type === 'Declaration' && node.property === 'margin' && !node.important))) {
      throw new DocumentError('headerVariantProtected');
    }
  }
  const copies = sources.flatMap(area => [...area.element.querySelectorAll('*')].filter(element => model.formula(element)))
    .flatMap(element => variants.map(() => element.outerHTML));
  return { names, variants, sources, areas, copies };
}

export function areaPosition(model, name) {
  const area = model.headerAreas().areas.find(area => area.name === name);
  try {
    if (!area || model.headerAreas().reason) throw new DocumentError('headerPositionProtected');
    let margin;
    for (const style of model.document.querySelectorAll('head style')) {
      const ast = css.parse(style.textContent, { onParseError: () => { throw new DocumentError('headerPositionProtected'); } });
      css.walk(ast, node => {
        if (node.type !== 'Rule') return;
        const selector = css.generate(node.prelude);
        const matches = selector === `div.${name}` || (() => {
          try { return area.element.matches(selector); } catch { return true; }
        })();
        if (!matches) return;
        for (const declaration of node.block.children) {
          if (declaration.type !== 'Declaration' || !/^margin(?:-|$)/i.test(declaration.property)) continue;
          if (![...ast.children].includes(node) || selector !== `div.${name}` ||
            declaration.property !== 'margin' || declaration.important) throw new DocumentError('headerPositionProtected');
          margin = css.generate(declaration.value);
        }
      });
    }
    if (!margin || /(?:^|;)\s*margin(?:-|:)/i.test(area.element.getAttribute('style') || '')) throw new DocumentError('headerPositionProtected');
    const parts = margin.trim().split(/\s+/);
    if (parts.length > 4) throw new DocumentError('headerPositionProtected');
    parts.forEach(pagePoints);
    const [top, right = top, bottom = top, left = right] = parts;
    const geometry = model.sectionSetup(area.section);
    if (geometry.reason) throw new DocumentError('headerPositionProtected');
    return { area, values: { top, right, bottom, left }, geometry: geometry.geometry, reason: null };
  } catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    return { area, reason: 'headerPositionProtected' };
  }
}

export function validateAreaPosition(values, geometry) {
  areaSides.forEach(side => pagePoints(values[side]));
  const [width, height] = pagePaperSize(geometry);
  if (pagePoints(values.left) + pagePoints(values.right) >= width ||
    pagePoints(values.top) + pagePoints(values.bottom) >= height) throw new DocumentError('headerPositionInvalid');
}

export function headerContentReason(model, root) {
  if (root && (!root.textContent.isWellFormed() || Object.keys(model.values(root)).some(key => /^-d4-(anchor|ref|protected)/.test(key)) ||
    model.values(root).display === 'none')) return 'headerUnsupported';
  if (!root || !root.children.length || [...root.childNodes].some(node =>
    node.nodeType === 3 && node.data.trim() || node.nodeType === 1 && node.localName !== 'p')) return 'headerUnsupported';
  const check = element => {
    if (element.namespaceURI !== XHTML) return false;
    const values = model.values(element);
    if (Object.keys(values).some(key => /^-d4-(anchor|protected|section)/.test(key)) ||
      ['hidden', 'collapse'].includes(values.visibility) || values.display === 'none' ||
      ['page-break-after', 'break-after'].some(key => values[key] && values[key] !== 'auto' && values[key] !== 'avoid')) return false;
    const formula = model.formula(element);
    if (formula) return formula.supported;
    if (element.localName !== 'p' && !inline.has(element.localName)) return false;
    return [...element.children].every(child => child.localName !== 'p' && check(child));
  };
  return [...root.children].every(check) ? null : 'headerUnsupported';
}

export function removeAreaRules(document, name) {
  for (const style of document.querySelectorAll('head style')) {
    const ast = css.parse(style.textContent, { positions: true });
    const rules = [...ast.children].filter(rule => rule.type === 'Rule' && css.generate(rule.prelude) === `div.${name}`);
    let text = style.textContent;
    for (const rule of rules.reverse()) text = text.slice(0, rule.loc.start.offset) + text.slice(rule.loc.end.offset);
    if (text !== style.textContent) style.textContent = text;
  }
}

// Exclude only the requested content, or its wrapper/rules for create/remove.
// Everything else must retain its exact serialized XML.
export function outsideArea(document, name, structure = false) {
  const copy = document.cloneNode(true);
  for (const target of Array.isArray(name) ? name : [name]) {
    const area = [...copy.querySelectorAll('body > div')].find(element => element.getAttribute('class') === target);
    if (structure) {
      area?.remove();
      removeAreaRules(copy, target);
      for (const style of copy.querySelectorAll('head style')) if (!style.textContent.trim()) style.remove();
    } else area?.replaceChildren();
  }
  return new XMLSerializer().serializeToString(copy);
}
