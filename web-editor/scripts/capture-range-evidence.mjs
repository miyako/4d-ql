import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { unzipSync, strFromU8 } from 'fflate';

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
await writeFile(new URL('../tests/fixtures/native-ranges.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
