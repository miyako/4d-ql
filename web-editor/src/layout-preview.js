import { pagePaperSize, pagePoints } from './page-setup.js';

export function paperGeometry(geometry) {
  const [width, height] = pagePaperSize(geometry);
  const margins = ['top', 'right', 'bottom', 'left'].map(side => pagePoints(geometry[side]));
  return { width, height, margins };
}

export function projectLayout(model, host) {
  const setup = model.pageSetup();
  const layout = model.sectionLayout();
  host.classList.remove('layout-preview');
  for (const property of ['width', 'min-width', 'max-width', 'min-height', 'padding']) host.style.removeProperty(property);
  if (setup.reason) return;
  const defaults = paperGeometry(setup.geometry);
  host.style.width = `${defaults.width}pt`;
  host.style.minWidth = `${defaults.width}pt`;
  host.style.maxWidth = 'none';
  host.style.minHeight = `${defaults.height}pt`;
  host.style.padding = defaults.margins.map(value => `${value}pt`).join(' ');
  if (layout.reason) return;
  host.classList.add('layout-preview');
  host.style.padding = '0';
  let maxWidth = defaults.width;
  for (const section of layout.sections) {
    const geometry = paperGeometry({ ...setup.geometry, ...setup.sections.get(section.index) });
    maxWidth = Math.max(maxWidth, geometry.width);
    const surface = document.createElement('div');
    surface.className = 'section-paper';
    surface.dataset.section = section.index;
    surface.style.width = `${geometry.width}pt`;
    surface.style.minHeight = `${geometry.height}pt`;
    surface.style.padding = geometry.margins.map(value => `${value}pt`).join(' ');
    const columns = model.columnSetup(section.index);
    let flow;
    for (const source of section.elements) {
      const element = model.projection.get(source);
      if (element?.parentNode !== host) continue;
      if (!surface.parentNode) element.before(surface);
      if (!flow) {
        flow = document.createElement('div');
        flow.className = 'section-flow';
        flow.dataset.section = section.index;
        if (!columns.reason && columns.settings.count > 1) {
          flow.classList.add('section-columns');
          flow.style.columnCount = String(columns.settings.count);
          flow.style.columnGap = `${pagePoints(columns.settings.gap)}pt`;
        }
        surface.append(flow);
      }
      const marker = element.nextElementSibling?.classList.contains('explicit-break') ? element.nextElementSibling : null;
      flow.append(element);
      if (marker) {
        surface.append(marker);
        if (!marker.classList.contains('continuous-break')) flow = null;
      }
    }
  }
  host.style.width = `${maxWidth}pt`;
  host.style.minWidth = `${maxWidth}pt`;
}
