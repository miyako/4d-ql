import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { pageDisplay } from '../src/page-setup.js';
import * as css from 'css-tree';

const margins = value => Object.fromEntries(['top', 'right', 'bottom', 'left'].map(side => [side, value]));
const targets = {
  letterLandscape: { width: '612pt', height: '792pt', orientation: 'landscape', ...margins('30pt') },
  customPortrait: { width: '630pt', height: '810pt', orientation: 'portrait', ...margins('0pt') },
  a5: { width: '420pt', height: '595pt', orientation: 'portrait', ...margins('36pt') },
  fractionalMargin: { top: '12.345mm', right: '0pt', bottom: '0.5in', left: '1.25cm' },
  wide: { width: '900pt', height: '500pt', orientation: 'landscape', ...margins('36pt') },
};

function assertPreserved(source, edited) {
  assert.equal(edited.document.querySelector('body').outerHTML, source.document.querySelector('body').outerHTML, 'Geometry changed body/formula/table XML');
  assert.deepEqual([...edited.document.querySelectorAll('meta')].filter(node => node.getAttribute('name') !== 'datetimeModified').map(node => node.outerHTML),
    [...source.document.querySelectorAll('meta')].filter(node => node.getAttribute('name') !== 'datetimeModified').map(node => node.outerHTML), 'Geometry changed bookmark/metadata XML');
  for (const [name, bytes] of Object.entries(source.files)) {
    if (name !== source.entry) assert.deepEqual(edited.files[name], bytes, `Geometry changed resource ${name}`);
  }
  const nativeStyles = model => {
    const result = [];
    for (const element of model.document.querySelectorAll('head style')) {
      const ast = css.parse(element.textContent);
      ast.children.forEach(rule => {
        if (rule.type === 'Rule' && css.generate(rule.prelude) === 'div.section0') {
          rule.block.children.forEach(node => {
            if (node.type !== 'Declaration' || !['-d4-page-width', '-d4-page-height', '-d4-page-orientation', '-d4-page-margin'].includes(node.property)) result.push(css.generate(node));
          });
        } else result.push(css.generate(rule));
      });
    }
    return result;
  };
  assert.deepEqual(nativeStyles(edited), nativeStyles(source), 'Geometry changed section overrides or unrelated native declarations');
}

export async function preparePageCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/page-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102', 'Page evidence must use installed full 4D 21.2');
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/page-errors.json'), 'utf8')), [], 'Native page probe errors');
  for (const item of report.validation) assert.equal(item.errors.length, item.value < 0 ? 1 : 0, 'Native validation oracle');
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  const sources = [
    ...Object.keys(targets).map(target => ({ target, file: 'Output/page-default.4wp' })),
    { target: 'letterLandscape', file: 'Output/page-sections-original.4wp' },
    { target: 'letterLandscape', file: 'Output/page-fractional.4wp' },
    ...['table', 'objects', 'layout', 'more'].map(name => ({ target: 'letterLandscape', file: `Input/${name}-original.4wp` })),
    ...cases.filter(item => /complex-model-.*identity$/.test(item.name)).map(item => ({ target: 'letterLandscape', file: `Input/${item.file}` })),
    ...cases.filter(item => /^formula-original-/.test(item.name)).map(item => ({ target: 'letterLandscape', file: `Input/${item.file}` })),
  ];
  assert(sources.length >= 25, 'Missing complex/formula sources for geometry preservation');
  const errors = [];
  try {
    for (const [index, item] of sources.entries()) {
      const files = unzipSync(await readFile(resolve(directory, item.file)));
      files['Resources/page-sentinel.bin'] = Uint8Array.of(0, 255, 17, 128, 42);
      const bytes = zipSync(files);
      const sourceFile = `page-source-${index}.4wp`;
      await writeFile(resolve(directory, 'Input', sourceFile), bytes);
      const source = WriteProDocument.open(bytes);
      const edited = WriteProDocument.open(bytes);
      assert.equal(edited.pageSetup().reason, null, `${item.file}: geometry unexpectedly protected`);
      edited.setPageSetup(targets[item.target]);
      assertPreserved(source, edited);
      const name = `page-model-${index}-${item.target}`;
      await writeFile(resolve(directory, 'Input', `${name}.4wp`), edited.export());
      const page = { source: sourceFile, target: item.target };
      cases.push({ name, file: `${name}.4wp`, page, resources: sourceFile });
      if (index >= 11 && !/identity/.test(item.file)) continue;
      const browserPage = await browser.newPage({ acceptDownloads: true });
      browserPage.on('pageerror', error => errors.push(error.message));
      browserPage.on('dialog', dialog => dialog.accept());
      try {
        await browserPage.goto(url);
        await browserPage.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
        await expect(browserPage.locator('#save-state')).toHaveText(source.readOnly ? 'Read-only' : 'Ready');
        await browserPage.locator('#page-toggle').click();
        await browserPage.locator('#page-units').selectOption('pt');
        for (const [field, value] of Object.entries(targets[item.target])) {
          if (field === 'orientation') await browserPage.locator('#page-orientation').selectOption(value);
          else await browserPage.locator('#page-' + field).fill(pageDisplay(value, 'pt'));
        }
        await browserPage.locator('#page-apply').click();
        await expect(browserPage.getByRole('alert')).toBeHidden();
        await download(`page-browser-${index}`, { page, resources: sourceFile }, browserPage);
        await browserPage.locator('#undo').click();
        await download(`page-browser-undo-${index}`, { page: { ...page, target: 'identity' }, resources: sourceFile }, browserPage);
        await expect(browserPage.locator('#draft-state')).toHaveText('Local draft saved');
        await browserPage.reload();
        await expect(browserPage.locator('#recovery-notice')).toBeVisible();
        await browserPage.locator('#redo').click();
        await download(`page-browser-recovered-${index}`, { page, resources: sourceFile }, browserPage);
      } finally { await browserPage.close(); }
    }
    assert.deepEqual(errors, [], 'Page browser runtime errors');
  } finally { dom.window.close(); }
}

export async function verifyPageCase(directory, entry, actual) {
  const original = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, 'Input', entry.page.source))));
  const input = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, 'Input', entry.file))));
  assertPreserved(original, input);
  const nativeExpected = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/${entry.name}-expected.4wp`))));
  const nativeActual = WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, `Output/${entry.name}.4wp`))));
  assert.equal(nativeActual.document.querySelector('body').outerHTML, nativeExpected.document.querySelector('body').outerHTML, `${entry.name}: native reexport changed formula/table/body XML`);
  assert.deepEqual(nativeActual.bookmarks(), nativeExpected.bookmarks(), `${entry.name}: native raw bookmark pairs differ`);
  const pageBoxes = async suffix => {
    const pdf = await readFile(resolve(directory, `Output/${entry.name}${suffix}.pdf`), 'latin1');
    const boxes = [...pdf.matchAll(/\/MediaBox\s*\[([^\]]+)\]/g)].map(match => match[1].trim().split(/\s+/).map(Number));
    assert(boxes.length, `${entry.name}: missing native PDF page geometry`);
    return boxes;
  };
  assert.deepEqual(await pageBoxes(''), await pageBoxes('-expected'), `${entry.name}: native PDF page boxes differ from independent native edit`);
  for (const stage of ['imported', 'reopened']) {
    assert(actual.pageExpected, `${entry.name}: missing independently native-mutated reference`);
    for (const key of ['page', 'text', 'metadata', 'bookmarks', 'tables', 'images', 'formulas', 'links', 'first']) {
      if (key === 'page') {
        const points = geometry => Object.fromEntries(Object.entries(geometry).map(([field, value]) => {
          if (field === 'orientation') return [field, value];
          const factors = { pt: 1, mm: 72 / 25.4, cm: 72 / 2.54, in: 72 };
          const [, number, unit] = value.match(/^([\d.]+)(pt|mm|cm|in)$/);
          return [field, Math.round(Number(number) * factors[unit] * 1e6) / 1e6];
        }));
        const normalized = page => ({ document: points(page.document), sections: page.sections.map(points) });
        assert.deepEqual(normalized(actual[stage].page), normalized(actual.pageExpected.page), `${entry.name}: native ${stage} geometry differs`);
      } else assert.deepEqual(actual[stage][key], actual.pageExpected[key], `${entry.name}: native ${stage} changed ${key}`);
    }
  }
}
