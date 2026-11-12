import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';
import { JSDOM } from 'jsdom';
import { nativeMetadata } from '../src/native-ranges.js';
import { complexScenarios } from './native-complex-cases.mjs';

const directory = resolve(process.argv[2]);
assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/range-errors.json'), 'utf8')), []);
const report = JSON.parse(await readFile(resolve(directory, 'Output/range-report.json'), 'utf8'));
assert.equal(report.splices.length, 165, 'Native splice coverage');
assert.equal(report.offsets.length, 11, 'Native offset coverage');
assert.equal(report.operations.length, 10, 'Native structural operation coverage');
const pairs = bookmarks => Object.fromEntries(Object.entries(bookmarks).map(([name, value]) => [name, [value.start, value.end]]));
const offsets = [];
for (const item of report.offsets) {
  const files = unzipSync(await readFile(resolve(directory, `Output/range-${item.name}.4wp`)));
  const xml = strFromU8(Object.entries(files).find(([name]) => /\.html$/i.test(name))[1]);
  offsets.push({ name: item.name, xml, text: item.text, start: item.start, end: item.end, bookmarks: pairs(item.bookmarks), units: item.units });
}
const result = {
  version: report.version,
  source: 'Full 4D wp_range_check; delete then insert (not atomic WP SET TEXT replacement). Regenerate with scripts/capture-range-evidence.mjs EVIDENCE_DIRECTORY.',
  initial: pairs(report.baseline.bookmarks),
  offsets,
  splices: report.splices.map(item => ({ edit: item.edit, text: item.text, bookmarks: pairs(item.bookmarks) })),
};
await mkdir(new URL('../tests/fixtures/', import.meta.url), { recursive: true });
if (!process.argv.includes('--complex-only')) await writeFile(new URL('../tests/fixtures/native-ranges.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
const dom = new JSDOM();
const archive = async (name, suffix) => {
  const files = unzipSync(await readFile(resolve(directory, `Output/structure-${name}-${suffix}.4wp`)));
  return strFromU8(Object.entries(files).find(([name]) => /\.html$/i.test(name))[1]);
};
const structures = [];
for (const item of report.structures) {
  if (item.name.startsWith('boundary-') && item.name !== 'boundary-table') continue;
  const xml = await archive(item.name, 'original');
  const after = new dom.window.DOMParser().parseFromString(await archive(item.name, 'native'), 'application/xhtml+xml');
  structures.push({ name: item.name, xml, before: item.before, after: item.after, serialized: nativeMetadata(after).bookmarks });
}
assert.equal(structures.length, 33, 'Native table/list coverage');
if (!process.argv.includes('--complex-only')) {
  await writeFile(new URL('../tests/fixtures/native-structures.json', import.meta.url), JSON.stringify({ version: report.version, structures }) + '\n');
  assert.equal(report.formulas.length, 14, 'Native formula coverage');
  const variants = [];
  const stats = value => ({ text: value.text, bookmarks: pairs(value.bookmarks), end: value.end });
  for (const item of report.formulas) {
    const files = unzipSync(await readFile(resolve(directory, `Output/formula-${item.name}-original.4wp`)));
    const xml = strFromU8(Object.entries(files).find(([name]) => /\.html$/i.test(name))[1]).replace(/^\ufeff/, '');
    variants.push({
      name: item.name, xml, before: stats(item.before), formulas: item.native.formulas,
      operations: item.operations.map(operation => ({ name: operation.name, after: stats(operation.after) })),
    });
  }
  await writeFile(new URL('../tests/fixtures/native-formulas.json', import.meta.url), JSON.stringify({ version: report.version, variants }) + '\n');
}
dom.window.close();
const scenarios = await complexScenarios(directory, report.complex);
const samples = scenarios.filter(item => ['typing', 'unicode'].includes(item.operation) || item.scope === 'column' ||
  ['colspan', 'rowspan', 'rectangle'].includes(item.shape) && item.operation === 'cut' ||
  item.name === 'grid-identity' || item.name === 'grid-format' ||
  item.name === 'grid-middleTyping' || item.name === 'uneven-lastTyping');
const sampleDOM = new JSDOM();
const compact = samples.map(({ bytes, ...item }) => {
  const names = new Set(Object.entries(item.before).filter(([, [start, end]]) =>
    end - start <= 1 || start === 1 || start === 9).map(([name]) => name));
  const keep = object => Object.fromEntries(Object.entries(object).filter(([name]) => names.has(name)));
  const document = new sampleDOM.window.DOMParser().parseFromString(item.xml, 'application/xhtml+xml');
  document.querySelector('meta[name="bookmarks"]').setAttribute('content', JSON.stringify(Object.fromEntries(
    Object.entries(keep(item.before)).map(([name, pair]) => [name, pair.map(offset => offset - 1)]))));
  return {
    ...item, xml: new sampleDOM.window.XMLSerializer().serializeToString(document),
    before: keep(item.before), serialized: keep(item.serialized),
    after: { ...item.after, bookmarks: keep(item.after.bookmarks), serialized: keep(item.serialized) },
  };
});
assert.equal(compact.length, 25, 'Representative complex table coverage');
await writeFile(new URL('../tests/fixtures/native-complex.json', import.meta.url), JSON.stringify({
  version: report.version, source: 'Full 4D wp_complex_probe; native cell text bounds and exhaustive raw pair matrix. Regenerate with scripts/capture-range-evidence.mjs EVIDENCE_DIRECTORY --complex-only.',
  cases: compact,
}, null, 2) + '\n');
sampleDOM.window.close();
