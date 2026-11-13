import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { createPrintProjection } from '../src/printing.js';
import { messages } from '../src/i18n.js';

export function inspectPDF(path) {
  const xml = execFileSync('pdftotext', ['-bbox', path, '-'], { encoding: 'utf8' });
  const pages = [...xml.matchAll(/<page width="([\d.]+)" height="([\d.]+)">([\s\S]*?)<\/page>/g)].map(match => ({
    width: Number(match[1]), height: Number(match[2]),
    words: [...match[3].matchAll(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<\/word>/g)].map(word => ({
      x: Number(word[1]), y: Number(word[2]), right: Number(word[3]), bottom: Number(word[4]), text: word[5],
    })),
  }));
  assert(pages.length, `No PDF pages: ${path}`);
  return { pages, text: execFileSync('pdftotext', ['-layout', path, '-'], { encoding: 'utf8' }) };
}

// Independent native getter values, not the editor's page/section resolver.
export function geometry(native) {
  const points = value => {
    const [, number, unit] = String(value).match(/^([\d.]+)(pt|cm|mm|in)$/);
    return Number(number) * { pt: 1, cm: 72 / 2.54, mm: 72 / 25.4, in: 72 }[unit];
  };
  const width = points(native.width);
  const height = points(native.height);
  return {
    width: native.orientation === 1 ? height : width,
    height: native.orientation === 1 ? width : height,
    top: points(native.top), right: points(native.right), bottom: points(native.bottom), left: points(native.left),
  };
}

export async function preparePrintCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/print-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 8);
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/print-errors.json'), 'utf8')), []);
  const results = [];
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  try {
    for (const item of report.cases) {
      const sourceFile = `print-source-${item.name}.4wp`;
      const bytes = new Uint8Array(await readFile(resolve(directory, `Output/print-${item.name}.4wp`)));
      await writeFile(resolve(directory, 'Input', sourceFile), bytes);
      const model = WriteProDocument.open(bytes);
      const snapshot = model.pack();
      createPrintProjection(model, messages.en);
      assert.deepEqual(model.pack(), snapshot, 'Print mutated live model/history/metadata');
      const native = inspectPDF(resolve(directory, `Output/print-${item.name}.pdf`));
      const geometries = item.sections.sections.map(section => geometry(section.geometry));
      const page = await browser.newPage({ acceptDownloads: true });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      try {
        await page.goto(url);
        await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
        await expect(page.locator('#paper')).toContainText('FIRST');
        const flow = { source: sourceFile, action: 'identity' };
        await download(`print-browser-before-${item.name}`, { flow, resources: sourceFile }, page);
        await page.locator('#settings-toggle').click();
        await page.locator('#theme').selectOption('dark');
        await page.locator('#zoom').selectOption('2');
        await page.locator('#page-toggle').click();
        for (const unit of ['cm', 'in', 'pt', 'mm']) await page.locator('#page-units').selectOption(unit);
        await page.locator('#paper [data-run]').first().evaluate(element => {
          element.focus();
          getSelection().setBaseAndExtent(element.firstChild, 0, element.firstChild, Math.min(3, element.textContent.length));
        });
        const selection = await page.evaluate(() => getSelection().toString());
        await page.locator('#print-toggle').click();
        await page.evaluate(() => {
          window.print = () => {
            dispatchEvent(new Event('beforeprint'));
            dispatchEvent(new Event('afterprint'));
          };
        });
        await page.locator('#print-open').click();
        await expect(page.locator('#error')).toBeHidden();
        assert.equal(await page.evaluate(() => getSelection().toString()), selection);
        const path = resolve(directory, `Output/print-browser-${item.name}.pdf`);
        await page.pdf({ path, preferCSSPageSize: true, printBackground: true });
        const printed = inspectPDF(path);
        const raster = execFileSync('pdftoppm', ['-f', '1', '-singlefile', '-scale-to', '40', path]);
        const header = /^P6\s+\d+\s+\d+\s+255\s/.exec(raster.toString('latin1'))[0].length;
        assert.deepEqual([...raster.subarray(header, header + 3)], [255, 255, 255], 'Dark chrome leaked into paper margins');
        for (const token of item.tokens) {
          assert(printed.text.includes(token), `${item.name}: browser PDF lost ${token}`);
          assert(native.text.includes(token), `${item.name}: native PDF lost ${token}`);
        }
        for (const output of [native, printed]) for (const sheet of output.pages) {
          assert(geometries.some(geometry => Math.abs(sheet.width - geometry.width) < 1 && Math.abs(sheet.height - geometry.height) < 1),
            `${item.name}: PDF size differs from independent native effective section getters`);
        }
        for (const sheet of printed.pages) {
          const matching = geometries.filter(geometry => Math.abs(sheet.width - geometry.width) < 1 && Math.abs(sheet.height - geometry.height) < 1);
          for (const word of sheet.words) assert(matching.some(geometry =>
            word.x >= geometry.left - 1 && word.right <= sheet.width - geometry.right + 1 &&
            word.y >= geometry.top - 1 && word.bottom <= sheet.height - geometry.bottom + 1),
          `${item.name}: clipped or out-of-margin browser word ${word.text}`);
        }
        for (const [token, sectionIndex] of [['FIRST', 0], ['SECOND', 0], ['THIRD', 1], ...(item.name === 'mixed' ? [['FOURTH', 2]] : [])]) {
          const sheet = printed.pages.find(sheet => sheet.words.some(word => word.text.includes(token)));
          const word = sheet?.words.find(word => word.text.includes(token));
          const expected = geometries[sectionIndex];
          assert(sheet && Math.abs(sheet.width - expected.width) < 1 && Math.abs(sheet.height - expected.height) < 1,
            `${item.name}: ${token} is not on its native section's paper geometry`);
          assert(Math.abs(word.x - expected.left) < 1, `${item.name}: ${token} does not start at its section's native left margin`);
        }
        if (['portrait', 'landscape', 'wide', 'tabs'].includes(item.name)) {
          assert.equal(printed.pages.length, 3, 'Explicit two breaks must produce three browser pages');
          assert.equal(native.pages.length, 3);
          assert(Math.abs(printed.pages[0].words[0].x - geometries[0].left) < 1);
        }
        if (['columns', 'rich'].includes(item.name)) {
          assert.match(execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }), /\d+\s+\d+\s+image/, 'Missing safe raster image in browser PDF');
          assert(printed.text.includes('PRINTCACHE'), 'Formula source/stored value placeholder lost');
        }
        await download(`print-browser-after-${item.name}`, { flow, resources: sourceFile }, page);
        assert.deepEqual(new Uint8Array(await readFile(resolve(directory, `Input/print-browser-after-${item.name}.4wp`))), bytes, 'Printing changed original archive bytes');
        assert.deepEqual(errors, []);
        results.push({ name: item.name, nativePages: native.pages.length, browserPages: printed.pages.length,
          nativeGeometry: geometries, browserSheets: printed.pages.map(sheet => ({ width: sheet.width, height: sheet.height, words: sheet.words.length })),
          contentTokens: item.tokens.length, unchangedArchive: true, whitePaperMargin: true,
          ...(item.name === 'tabs' ? {
            nativeFirstLine: native.pages[0].words, browserFirstLine: printed.pages[0].words,
            nativeTabGetters: item.flow.paragraphs[0], tabRendering: 'Native alignment/leaders deliberately not reproduced; browser uses only the default interval.',
          } : {}),
          limits: 'Geometry/content only. No font, wrapping, tab alignment/leader or pagination equivalence is asserted.' });
      } finally { await page.close(); }
    }
    await writeFile(resolve(directory, 'Output/print-browser-report.json'), JSON.stringify(results, null, 2));
  } finally { dom.window.close(); }
}
