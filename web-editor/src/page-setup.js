import { DocumentError } from './archive.js';

export const pageUnits = { pt: 1, mm: 72 / 25.4, cm: 72 / 2.54, in: 72 };
export const paperPresets = {
  a4: [595, 842], a3: [842, 1191], a5: [420, 595],
  letter: [612, 792], legal: [612, 1008], tabloid: [792, 1224],
};
export const pageFields = ['width', 'height', 'top', 'right', 'bottom', 'left'];

export function pagePoints(value) {
  const match = typeof value === 'string' && value.trim().match(/^(\d+(?:\.\d*)?|\.\d+)(pt|mm|cm|in)$/);
  const points = match ? Number(match[1]) * pageUnits[match[2]] : NaN;
  if (!Number.isFinite(points) || points > 10000) throw new DocumentError('pageInvalid');
  return points;
}

export function pageDisplay(value, unit) {
  return String(Number((pagePoints(value) / pageUnits[unit]).toFixed(10)));
}

export function pagePaperSize(geometry) {
  const sides = [Math.round(pagePoints(geometry.width)), Math.round(pagePoints(geometry.height))];
  return geometry.orientation === 'landscape' ? sides.reverse() : sides;
}

export function validatePageGeometry(geometry) {
  const [width, height] = pagePaperSize(geometry);
  if (width < 1 || height < 1 || !['portrait', 'landscape'].includes(geometry.orientation)) throw new DocumentError('pageInvalid');
  if (pagePoints(geometry.left) + pagePoints(geometry.right) >= width ||
    pagePoints(geometry.top) + pagePoints(geometry.bottom) >= height) throw new DocumentError('pageMarginsInvalid');
}
