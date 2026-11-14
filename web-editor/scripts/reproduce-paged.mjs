import assert from 'node:assert/strict';
import { readFile, writeFile, copyFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { evidencePreview } from './evidence-preview.mjs';
import { chromium, expect } from '@playwright/test';
import { preparePagedCases } from './native-paged-cases.mjs';

assert(process.argv[2] && process.argv[3], 'Usage: reproduce-paged.mjs NEW_EVIDENCE_DIRECTORY SEALED_63_BASELINE [--compare]');
assert(!process.argv[4] || process.argv[4] === '--compare', 'Unknown baseline reproduction mode');
const directory = resolve(process.argv[2]);
const baseline = resolve(process.argv[3]);
assert.notEqual(directory, baseline, 'Baseline evidence must never be overwritten');
assert(!(await readdir(directory)).includes('SHA256-MANIFEST.json'), 'Sealed evidence must never be overwritten');
const prior = JSON.parse(await readFile(resolve(baseline, 'Input/cases.json'), 'utf8')).cases;
assert.equal(prior.length, 2671, 'The exact #63 baseline, including actual Cancel definitions, is required');
const affected = entry => /^(paged-|expanded-|tables-cancel-|columns-cancel-|continuous-paged-|seams-cancel-|cell-list-|cell-lists-cancel-|colspan-|colspans-cancel-|rowspan-|rowspans-cancel-|nowitness-|nowitnesses-cancel-)/.test(entry.name);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const compare = async () => {
  const current = JSON.parse(await readFile(resolve(directory, 'Input/cases.json'), 'utf8')).cases;
  const byName = new Map(current.map(entry => [entry.name, entry]));
  assert.equal(byName.size, current.length, 'Duplicate case names');
  const hashes = [];
  for (const entry of prior) {
    assert.deepEqual(byName.get(entry.name), entry, `Changed baseline definition: ${entry.name}`);
    if (!affected(entry)) {
      const bytes = await readFile(resolve(directory, 'Input', entry.file));
      assert.deepEqual(bytes, await readFile(resolve(baseline, 'Input', entry.file)), `Changed unaffected input: ${entry.name}`);
      hashes.push({ name: entry.name, file: entry.file, sha256: hash(bytes) });
    }
  }
  const dependencies = JSON.parse(await readFile(resolve(directory, 'baseline-dependency-hashes.json'), 'utf8'));
  for (const entry of dependencies) assert.equal(hash(await readFile(resolve(directory, 'Input', entry.file))), entry.sha256,
    `Changed retained dependency: ${entry.file}`);
  await writeFile(resolve(directory, 'baseline-comparison.json'), JSON.stringify({
    baseline, baselineDefinitions: prior.length, unchangedDefinitions: prior.length,
    finalCases: current.length, unaffectedInputs: hashes.length, unaffectedHashes: hashes,
    independentlyComparedDependencies: dependencies.length,
    regeneratedBaselinePagedExports: prior.filter(affected).length, newObjectPaginationCases: current.length - prior.length,
  }, null, 2));
  console.log(`${prior.length} baseline definitions, ${hashes.length} unaffected hashes and ${dependencies.length} dependencies unchanged; ${current.length} final cases.`);
};
if (process.argv[4] === '--compare') {
  await compare();
} else {
  const generated = JSON.parse(await readFile(resolve(directory, 'Input/cases.json'), 'utf8')).cases;
  const generatedByName = new Map(generated.map(entry => [entry.name, entry]));
  for (const entry of prior.filter(entry => !entry.name.includes('-cancel-'))) {
    assert.deepEqual(generatedByName.get(entry.name), entry, `Changed generated baseline definition: ${entry.name}`);
  }
  const cases = prior.filter(entry => !affected(entry));
  const baselineFiles = new Set(await readdir(resolve(baseline, 'Input')));
  const dependencies = new Set();
  const references = value => {
    if (typeof value === 'string' && baselineFiles.has(value)) dependencies.add(value);
    else if (value && typeof value === 'object') Object.values(value).forEach(references);
  };
  cases.forEach(references);
  const hashes = [];
  for (const file of dependencies) {
    await copyFile(resolve(baseline, 'Input', file), resolve(directory, 'Input', file));
    const bytes = await readFile(resolve(directory, 'Input', file));
    assert.deepEqual(bytes, await readFile(resolve(baseline, 'Input', file)));
    hashes.push({ file, sha256: hash(bytes) });
  }
  await writeFile(resolve(directory, 'baseline-dependency-hashes.json'), JSON.stringify(hashes, null, 2));
  const server = await evidencePreview(directory, 4187, 'final-reproduction');
  const browser = await chromium.launch();
  try {
    const download = async (name, extra, page) => {
      const waiting = page.waitForEvent('download');
      await page.locator('#download').click();
      await expect(page.getByRole('alert'), `${name}: export failed`).toBeHidden();
      const file = `${name}.4wp`;
      await (await waiting).saveAs(resolve(directory, 'Input', file));
      cases.push({ name, file, ...extra });
    };
    await preparePagedCases(directory, cases, browser, server.resolvedUrls.local[0], download);
    const byName = new Map(cases.map(entry => [entry.name, entry]));
    for (const entry of prior.filter(entry => !entry.name.includes('-cancel-'))) assert.deepEqual(byName.get(entry.name), entry);
    await writeFile(resolve(directory, 'Input/cases.json'), JSON.stringify({ cases }, null, 2));
    console.log('Final production paged exports regenerated; run all eleven actual Cancel modes before --compare and --recheck.');
  } finally {
    await browser.close();
    await server.close();
  }
}
