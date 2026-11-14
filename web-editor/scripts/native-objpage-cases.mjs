import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { messages } from '../src/i18n.js';
import { inspectPDF } from './native-print-cases.mjs';

// Browser outcome per native shape (wp_objpage_probe, full 4D 21.2 F0012102). Native PDFs are the oracle for which
// pages each object is drawn on, never for coordinates, wrapping or page counts.
export const objpageShapes = {
  'doc-front': 'placed', 'doc-behind': 'placed', 'section-front': 'placed', 'section-behind': 'placed',
  // Native square wrap reflows body text (5 native pages); the browser draws a reserved box without text flow.
  square: 'placed',
  // Section-wide objects repeat on the section's first, left and right variant pages.
  variants: 'placed', unicode: 'placed',
  // A specific page target is drawn on that page only: appendix, not placed.
  'page-target': 'appendix',
  // 4D normalizes a section 2 + page 1 request to page 1 of the document (section getter -1): appendix.
  'section-page': 'appendix',
  // On the page shared through a continuous seam 4D draws only the outgoing section's objects: protected, appendix.
  continuous: 'appendix',
  // Document-wide objects repeat on every automatically paginated page.
  auto: 'placed',
};
const layers = { 0: 'behind', 1: 'front', 3: 'wrap-square' };

// Native page -> section from the authored break list and the carried-forward OBJPn marker on each native page.
function nativeSections(item, pages) {
  const markerSection = [1];
  let section = 1;
  for (const step of item.breaks) {
    if (step === 'A') continue;
    if (step === 'S' || step === 'C') section++;
    markerSection.push(section);
  }
  let current = 1;
  return pages.map(words => {
    const markers = words.map(word => /^OBJP(\d+)$/.exec(word)).filter(Boolean).map(match => Number(match[1]));
    const first = markers.length ? markerSection[markers[0] - 1] : current;
    if (markers.length) current = markerSection[markers.at(-1) - 1];
    return { first, markers };
  });
}

function imagesPerPage(path, count) {
  const pages = Array(count).fill(0);
  for (const line of execFileSync('pdfimages', ['-list', path], { encoding: 'utf8' }).split('\n').slice(2).filter(Boolean)) {
    pages[Number(line.trim().split(/\s+/)[0]) - 1]++;
  }
  return pages;
}

export async function prepareObjpageCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/objpage-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.deepEqual(report.cases.map(item => item.name), Object.keys(objpageShapes));
  assert.deepEqual(JSON.parse(await readFile(resolve(directory, 'Output/objpage-errors.json'), 'utf8')), []);
  const results = [];
  for (const item of report.cases) {
    const outcome = objpageShapes[item.name];
    // Independent native getters, by native ID, before and after re-import of the stored file.
    const byId = stats => [...stats.objects].sort((a, b) => a.id.localeCompare(b.id));
    assert.deepEqual(byId(item.reopened), byId(item.stats), `${item.name}: re-imported native object getters`);
    const objects = item.requested.map((spec, index) => {
      const native = item.stats.objects.find(object => object.id === item.objects[index]);
      assert(native, `${item.name}: native object ${item.objects[index]}`);
      return { ...spec, id: native.id, section: native.attributes.section, page: native.attributes.page, layout: layers[native.attributes.layout] };
    });
    assert(objects.filter(object => object.kind === 'picture').length <= 1, 'One picture per shape keeps PDF image counts unambiguous');
    for (const object of objects) assert(['front', 'behind', 'wrap-square'].includes(object.layout), `${item.name}: known native layer getter`);
    if (item.name === 'section-page') assert.deepEqual([objects[0].section, objects[0].page], [-1, 1], 'Native page setter clears the section');
    const native = inspectPDF(resolve(directory, `Output/objpage-${item.name}.pdf`));
    const reopened = inspectPDF(resolve(directory, `Output/objpage-${item.name}-reopened.pdf`));
    const nativeWords = native.pages.map(sheet => sheet.words.map(word => word.text));
    assert.deepEqual(reopened.pages.map(sheet => sheet.words.map(word => word.text)), nativeWords, `${item.name}: stored file alone reproduces the native PDF`);
    const nativeImages = imagesPerPage(resolve(directory, `Output/objpage-${item.name}.pdf`), native.pages.length);
    const has = (words, token) => words.some(word => word === token || word.length >= 12 && token.startsWith(word));
    const nativeObjects = nativeWords.map((words, index) => objects.filter(object =>
      object.kind === 'picture' ? nativeImages[index] > 0 : has(words, object.token)).map(object => object.id).sort());
    const pages = nativeSections(item, nativeWords);
    // Native membership rule, derived from the PDF: every page of the same section carries the same objects.
    const bySection = new Map();
    pages.forEach((page, index) => {
      const key = String(page.first);
      if (!bySection.has(key)) bySection.set(key, nativeObjects[index]);
      if (outcome === 'placed') assert.deepEqual(nativeObjects[index], bySection.get(key), `${item.name}: native page ${index + 1} section membership`);
    });
    if (outcome === 'placed') {
      for (const object of objects) {
        const expected = pages.map(page => object.section === -1 || page.first === object.section);
        assert.deepEqual(nativeObjects.map(ids => ids.includes(object.id)), expected, `${item.name}: native ${object.id} on every page of its target`);
      }
    }
    if (item.name === 'page-target') assert.deepEqual(nativeObjects, [[], ['textBox1'], ['img1'], []]);
    if (item.name === 'section-page') assert.deepEqual(nativeObjects, [['textBox1'], [], [], []]);
    if (item.name === 'continuous') {
      assert.deepEqual(nativeWords.map(words => words.filter(word => /^OBJP\d$/.test(word))), [['OBJP1'], ['OBJP2', 'OBJP3'], ['OBJP4']]);
      assert.deepEqual(nativeObjects, [['img1'], ['img1'], ['textBox1']], 'Shared seam page draws only the outgoing section objects');
    }
    if (item.name === 'variants') {
      assert.deepEqual(nativeWords.slice(0, 4).map(words => words.filter(word => /^OBJ(FIRST|LEFT|RIGHT)HEADER$/.test(word))),
        [['OBJFIRSTHEADER'], ['OBJLEFTHEADER'], ['OBJRIGHTHEADER'], ['OBJLEFTHEADER']]);
    }
    if (item.name === 'auto') assert(native.pages.length > 2, 'Native automatic pagination');
    const files = unzipSync(await readFile(resolve(directory, `Output/objpage-${item.name}-original.4wp`)));
    files['Resources/objpage-sentinel.bin'] = Uint8Array.of(0, 255, 31, 128);
    const original = zipSync(files);
    const source = `objpage-source-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', source), original);
    const target = `objpage-target-${item.name}.4wp`;
    await writeFile(resolve(directory, 'Input', target), await readFile(resolve(directory, `Output/objpage-${item.name}-edited.4wp`)));
    const expected = { flow: { source, action: 'identity' }, resources: source };
    const page = await browser.newPage({ acceptDownloads: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    try {
      await page.goto(url);
      await page.locator('#file').setInputFiles(resolve(directory, 'Input', source));
      await expect(page.locator('#paper')).toContainText('OBJP1');
      await download(`objpage-before-${item.name}`, expected, page);
      await page.locator('#paged-panel > summary').click();
      const sheets = page.locator('#paged-view .browser-page');
      await expect(sheets.first()).toBeVisible();
      const count = await sheets.count();
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const preview = await sheets.evaluateAll(sheets => sheets.map(sheet => ({
        section: Number(sheet.dataset.sections.split(' ')[0]),
        markers: (sheet.querySelector('.page-body').textContent.match(/OBJP\d+/g) || []),
        objects: [...sheet.querySelectorAll(':scope > .paged-object')].map(object => object.dataset.object).sort(),
        layers: Object.fromEntries([...sheet.querySelectorAll(':scope > .paged-object')].map(object => [object.dataset.object, object.dataset.layer])),
        text: Object.fromEntries([...sheet.querySelectorAll(':scope > .paged-text-box')].map(object => [object.dataset.object, object.textContent])),
      })));
      const appendix = await page.locator('#paged-view .paged-object-appendix').evaluateAll(sheets => sheets.map(sheet => sheet.dataset.object));
      const notices = await page.locator('#paged-objects > p').evaluateAll(items => items.map(item => item.dataset.notice));
      if (outcome === 'placed') {
        assert.deepEqual(appendix, []);
        assert.deepEqual(notices, [...(objects.some(object => object.layout === 'wrap-square') ? ['pagedObjectWrap'] : []), 'pagedObjectPlaced']);
        for (const sheet of preview) {
          assert.deepEqual(sheet.objects, bySection.get(String(sheet.section)), `${item.name}: browser sheet follows native section membership`);
          for (const object of objects.filter(object => sheet.objects.includes(object.id))) {
            assert.equal(sheet.layers[object.id], object.layout, 'Native layer');
            if (object.kind === 'box') assert.equal(sheet.text[object.id], item.stats.objects.find(entry => entry.id === object.id).text, 'Complete Unicode box text');
          }
        }
        // Explicitly broken pages carry the same OBJPn marker in both renderings: compare them page by page.
        pages.forEach((nativePage, index) => {
          if (!nativePage.markers.length) return;
          const sheet = preview.find(entry => entry.markers[0] === `OBJP${nativePage.markers[0]}`);
          assert(sheet, `${item.name}: browser page for OBJP${nativePage.markers[0]}`);
          assert.deepEqual(sheet.objects, nativeObjects[index], `${item.name}: exact native objects on OBJP${nativePage.markers[0]}`);
        });
        if (item.name === 'auto') assert(count > 2 && preview.every(sheet => sheet.objects.length === 2), 'Every automatic browser page');
      } else {
        assert(preview.every(sheet => !sheet.objects.length), `${item.name}: other targets are never placed`);
        assert.deepEqual([...appendix].sort(), objects.map(object => object.id).sort(), `${item.name}: each object once on an appendix sheet`);
        assert.deepEqual(notices, ['pagedObjectAppendix']);
      }
      await expect(page.locator('#paged-view [contenteditable],#paged-view [data-run]')).toHaveCount(0);
      await page.locator('#settings-toggle').click();
      await page.locator('#theme').selectOption('dark');
      await page.locator('#zoom').selectOption('2');
      await page.evaluate(() => {
        window.objpageResize = new Promise(resolve => window.addEventListener('resize', resolve, { once: true }));
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.evaluate(() => window.objpageResize);
      await expect(page.locator('#paged-status')).toHaveText(`${count} · ${messages.en.pagedSheet}`);
      const pdf = resolve(directory, `Output/objpage-browser-${item.name}.pdf`);
      await page.pdf({ path: pdf, preferCSSPageSize: true, printBackground: true });
      const printed = inspectPDF(pdf);
      assert.equal(printed.pages.length, count + appendix.length + await page.locator('#paged-view .paged-unused:not(.paged-object-appendix)').count());
      const printedImages = imagesPerPage(pdf, printed.pages.length);
      const printedObjects = printed.pages.slice(0, count).map((sheet, index) => objects.filter(object =>
        object.kind === 'picture' ? printedImages[index] > 0 : has(sheet.words.map(word => word.text), object.token)).map(object => object.id).sort());
      assert.deepEqual(printedObjects, preview.map(sheet => sheet.objects), `${item.name}: printed pages carry exactly the previewed objects`);
      for (const object of objects.filter(object => object.kind === 'box')) {
        const total = printed.pages.reduce((sum, sheet) => sum + sheet.words.filter(word => word.text === object.token).length, 0);
        assert.equal(total, outcome === 'placed' ? preview.filter(sheet => sheet.objects.includes(object.id)).length : 1, `${item.name}: printed ${object.token}`);
      }
      for (const sheet of printed.pages) assert(Math.abs(sheet.width - 300) < 1 && Math.abs(sheet.height - 360) < 1, 'Unscaled native paper geometry');
      await download(`objpage-after-${item.name}`, expected, page);
      assert.deepEqual(await readFile(resolve(directory, `Input/objpage-after-${item.name}.4wp`)), Buffer.from(original));
      await page.locator('#paper [contenteditable]').first().fill('WEBOBJ');
      const edited = { ...expected, flow: { source: target, action: 'identity' } };
      await download(`objpage-edited-${item.name}`, edited, page);
      await expect(page.locator('#paged-view .browser-page').first()).toContainText('WEBOBJ');
      await page.locator('#undo').click();
      await download(`objpage-undo-${item.name}`, expected, page);
      await expect(page.locator('#draft-state')).toHaveText('Local draft saved');
      await page.reload();
      await expect(page.locator('#recovery-notice')).toBeVisible();
      await page.locator('#redo').click();
      await download(`objpage-recovered-redo-${item.name}`, edited, page);
      assert.deepEqual(errors, []);
      results.push({ name: item.name, outcome, nativeObjects: objects, nativePages: native.pages.length, nativePageSections: pages,
        nativePageObjects: nativeObjects, browserPages: count, browserPageObjects: preview.map(({ section, markers, objects }) => ({ section, markers, objects })),
        appendix, notices, printedPageObjects: printedObjects, untouchedOriginalBytes: true,
        limits: 'Native page membership only; no coordinate, wrapping, layering-order or page-count parity.' });
    } finally {
      await page.close();
    }
  }
  await writeFile(resolve(directory, 'Output/objpage-browser-report.json'), JSON.stringify(results, null, 2));
}
