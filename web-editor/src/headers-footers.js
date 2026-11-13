import * as css from 'css-tree';

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
  return { areas, reason, sections: layout.sections, variants: [...enabled].filter(name => /^section\d+(First|Left|Right)$/.test(name)) };
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
  const area = [...copy.querySelectorAll('body > div')].find(element => element.getAttribute('class') === name);
  if (structure) {
    area?.remove();
    removeAreaRules(copy, name);
    for (const style of copy.querySelectorAll('head style')) if (!style.textContent.trim()) style.remove();
  } else area?.replaceChildren();
  return new XMLSerializer().serializeToString(copy);
}
