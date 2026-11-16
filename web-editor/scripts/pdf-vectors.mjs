import { execFileSync } from 'node:child_process';

// Stroked and filled vector paths of one PDF page, read with poppler's pdftocairo -svg (glyph definitions dropped).
// Only straight segments are decoded: each path becomes its list of points plus its paint attributes and transform.
export function pageVectors(path, page) {
  const svg = execFileSync('pdftocairo', ['-svg', '-f', String(page), '-l', String(page), path, '-'], { encoding: 'utf8', maxBuffer: 1 << 28 })
    .replace(/<defs>[\s\S]*?<\/defs>/g, '');
  const attribute = (text, name) => text.match(new RegExp(` ${name}="([^"]*)"`))?.[1] ?? null;
  return [...svg.matchAll(/<path([^>]*)\/>/g)].map(([, text]) => {
    const transform = attribute(text, 'transform');
    const matrix = transform?.match(/^matrix\(([^)]*)\)$/)?.[1].split(/[ ,]+/).map(Number) || [1, 0, 0, 1, 0, 0];
    const numbers = (attribute(text, 'd') || '').match(/[MLHVCZ]|-?[\d.]+(?:e-?\d+)?/gi) || [];
    const points = [];
    let command = null;
    let curved = false;
    for (let i = 0; i < numbers.length;) {
      if (/[A-Za-z]/.test(numbers[i])) { command = numbers[i++].toUpperCase(); if (command === 'Z') continue; if (command === 'C') curved = true; continue; }
      if (command === 'C') { const [x, y] = [Number(numbers[i + 4]), Number(numbers[i + 5])]; points.push([x, y]); i += 6; continue; }
      if (command === 'H') { points.push([Number(numbers[i++]), points.at(-1)?.[1] ?? 0]); continue; }
      if (command === 'V') { points.push([points.at(-1)?.[0] ?? 0, Number(numbers[i++])]); continue; }
      points.push([Number(numbers[i]), Number(numbers[i + 1])]);
      i += 2;
    }
    const [a, b, c, d, e, f] = matrix;
    return {
      points: points.map(([x, y]) => [a * x + c * y + e, b * x + d * y + f]),
      curved,
      scale: Math.hypot(a, b),
      stroke: attribute(text, 'stroke'),
      fill: attribute(text, 'fill'),
      strokeWidth: attribute(text, 'stroke-width') === null ? null : Number(attribute(text, 'stroke-width')) * Math.hypot(a, b),
      dash: attribute(text, 'stroke-dasharray'),
    };
  });
}

// Bounding box of a decoded path.
export function bounds(vector) {
  const xs = vector.points.map(point => point[0]);
  const ys = vector.points.map(point => point[1]);
  return { left: Math.min(...xs), right: Math.max(...xs), top: Math.min(...ys), bottom: Math.max(...ys) };
}
