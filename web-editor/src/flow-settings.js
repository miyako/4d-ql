import * as css from 'css-tree';
import { DocumentError } from './archive.js';
import { pagePoints, pagePaperSize } from './page-setup.js';

export const tabProperties = ['-d4-tab-stop-offset', '-d4-tab-stop-type', '-d4-tab-stop-leading'];
export const tabTypes = ['left', 'right', 'center', 'decimal', 'bar'];
export const tabLeaders = ['', '.', '-', '_'];
export const defaultTab = { position: '1.25cm', type: 'left', leader: '' };

export function validateColumns(settings, geometry) {
  const { count, gap } = settings;
  if (!Number.isInteger(count) || count < 1 || count > 20) throw new DocumentError('columnsInvalid');
  let spacing;
  try { spacing = pagePoints(gap); }
  catch (error) {
    if (!(error instanceof DocumentError)) throw error;
    throw new DocumentError('columnsInvalid');
  }
  if ((count - 1) * spacing >= pagePaperSize(geometry)[0] - pagePoints(geometry.left) - pagePoints(geometry.right)) {
    throw new DocumentError('columnsWidth');
  }
}

export function validateTabs(settings) {
  if (!settings || !Array.isArray(settings.stops) || !settings.default || settings.stops.length > 128) throw new DocumentError('tabsInvalid');
  let previous = 0;
  for (const [index, stop] of [...settings.stops, settings.default].entries()) {
    if (!stop || typeof stop !== 'object') throw new DocumentError('tabsInvalid');
    let position;
    try { position = pagePoints(stop.position); }
    catch (error) {
      if (!(error instanceof DocumentError)) throw error;
      throw new DocumentError('tabsInvalid');
    }
    if (position <= 0 || !tabTypes.includes(stop.type) || !tabLeaders.includes(stop.leader) ||
      index < settings.stops.length && position <= previous) throw new DocumentError('tabsInvalid');
    previous = position;
  }
}

export function parseTabs(values) {
  const tokens = (property, type) => {
    if (!values[property]) return null;
    const nodes = css.parse(values[property], { context: 'value' }).children.toArray();
    if (!nodes.length || nodes.some(node => node.type !== type)) throw new DocumentError('tabsUnsupported');
    return nodes.map(node => type === 'String' ? node.value : css.generate(node));
  };
  try {
    const positions = tokens(tabProperties[0], 'Dimension') || [defaultTab.position];
    const types = tokens(tabProperties[1], 'Identifier') || positions.map(() => defaultTab.type);
    const leaders = tokens(tabProperties[2], 'String') || positions.map(() => defaultTab.leader);
    if (positions.length !== types.length || positions.length !== leaders.length) throw new DocumentError('tabsUnsupported');
    const stops = positions.map((position, index) => ({ position, type: types[index], leader: leaders[index] }));
    const result = { stops: stops.slice(0, -1), default: stops.at(-1) };
    validateTabs(result);
    return result;
  } catch (error) {
    if (!(error instanceof DocumentError) && error.name !== 'SyntaxError') throw error;
    throw new DocumentError('tabsUnsupported');
  }
}

export function tabDeclarations(settings) {
  validateTabs(settings);
  const all = [...settings.stops, settings.default];
  return {
    [tabProperties[0]]: all.map(stop => stop.position).join(' '),
    [tabProperties[1]]: all.map(stop => stop.type).join(' '),
    [tabProperties[2]]: all.map(stop => css.generate({ type: 'String', value: stop.leader })).join(' '),
  };
}
