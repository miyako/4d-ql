import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { JSDOM } from 'jsdom';
import { unzipSync, zipSync } from 'fflate';
import { expect } from '@playwright/test';
import { WriteProDocument } from '../src/document.js';
import { messages } from '../src/i18n.js';
import { outsideObject } from '../src/objects.js';
import { inspectPDF } from './native-print-cases.mjs';

const pictureGeometry = { width: '111.125pt', height: '72.25pt', x: '12.345mm', y: '20.5pt' };
const boxGeometry = { width: '210.125pt', height: '100.25pt', x: '30.5pt', y: '40.75pt' };
const selection = (end = 3) => ({ startRun: 0, start: 0, endRun: 0, end });

export async function prepareMediaCases(directory, cases, browser, url, download) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/media-report.json'), 'utf8'));
  assert.equal(report.version, 'F0012102');
  assert.equal(report.cases.length, 7);
  for (const item of report.cases) {
    assert.equal(item.stages.length, 7);
    for (const stage of item.stages) assert.deepEqual(stage.stats.body, item.stages[0].stats.body, `${item.name}: body range changed`);
    assert.equal(item.stages[0].stats.objects.length, 2);
    assert.equal(item.stages.at(-1).stats.objects.length, 0);
    const box = item.stages.find(stage => stage.name === 'text').stats.objects.find(object => object.id === 'textBox1');
    assert(box.text.startsWith('EDITé 😀 日é'), 'Text-box range must be independent of body coordinates');
  }
  const originalPDF = inspectPDF(resolve(directory, 'Output/media-paper-original.pdf'));
  const movedPDF = inspectPDF(resolve(directory, 'Output/media-paper-geometry.pdf'));
  const word = pdf => pdf.pages.flatMap(page => page.words).find(word => word.text === 'BOX');
  assert(word(originalPDF) && word(movedPDF), 'Native PDFs must render stored box text');
  assert(Math.abs(word(originalPDF).x - word(movedPDF).x - 149.5) < 0.1);
  assert(Math.abs(word(originalPDF).y - word(movedPDF).y - 159.25) < 0.1);
  await writeFile(resolve(directory, 'Output/media-pdf-report.json'), JSON.stringify({
    nativeVersion: report.version, originalTextBox: word(originalPDF), movedTextBox: word(movedPDF),
    xDelta: -149.5, yDelta: -159.25,
    limits: 'Native paper-relative placement only. Browser objects are isolated views and a once-per-object print appendix, not equivalent wrapping/layers/pagination.',
  }, null, 2));
  const dom = new JSDOM();
  for (const key of ['document', 'DOMParser', 'XMLSerializer']) globalThis[key] = dom.window[key];
  try {
    for (const item of report.cases) {
      for (const action of ['identity', 'geometry', 'text', 'format']) {
        if (action !== 'identity' && item.name === 'nested' ||
          action === 'geometry' && ['aligned', 'formula'].includes(item.name)) continue;
        const previous = { identity: 'original', geometry: 'original', text: 'geometry', format: 'text' }[action];
        const expected = action === 'identity' ? previous : action;
        const source = `media-${item.name}-${previous}.4wp`;
        const files = unzipSync(await readFile(resolve(directory, 'Output', source)));
        files['Resources/media-sentinel.bin'] = Uint8Array.of(17, 0, 255, 128);
        const bytes = zipSync(files);
        const sourceFile = `source-media-${item.name}-${action}.4wp`;
        await writeFile(resolve(directory, 'Input', sourceFile), bytes);
        const metadata = { media: { kind: item.name, stage: expected, source: sourceFile }, resources: sourceFile };
        const model = WriteProDocument.open(bytes);
        if (action === 'geometry') {
          for (const [id, values] of [['img1', pictureGeometry], ['textBox1', boxGeometry]]) {
            model.setScope(`object:${id}`);
            model.setObjectGeometry(values);
          }
        } else if (action !== 'identity') {
          model.setScope('object:textBox1');
          model.render(document.createElement('article'), messages.en);
          if (action === 'text') model.replaceText(selection(), 'EDITé');
          else model.formatSelection(selection(5), 'font-weight', 'bold');
        }
        const name = `media-model-${item.name}-${action}`;
        await writeFile(resolve(directory, 'Input', `${name}.4wp`), model.export());
        cases.push({ name, file: `${name}.4wp`, ...metadata });
        const page = await browser.newPage({ acceptDownloads: true });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', dialog => dialog.accept());
        try {
          await page.goto(url);
          await page.locator('#file').setInputFiles(resolve(directory, 'Input', sourceFile));
          if (action === 'geometry') {
            for (const [id, values] of [['img1', pictureGeometry], ['textBox1', boxGeometry]]) {
              await page.locator('#editing-scope').selectOption(`object:${id}`);
              await page.locator('#object-units').selectOption('pt');
              for (const [field, value] of Object.entries(values)) {
                await page.locator('#object-units').selectOption(value.slice(-2));
                await page.locator(`#object-${field}`).fill(value.slice(0, -2));
              }
              await page.locator('#object-form button').click();
            }
          } else if (action !== 'identity') {
            await page.locator('#editing-scope').selectOption('object:textBox1');
            await page.locator('#paper [contenteditable]').first().evaluate((element, end) => {
              element.focus();
              getSelection().setBaseAndExtent(element.firstChild, 0, element.firstChild, end);
            }, action === 'text' ? 3 : 5);
            if (action === 'text') await page.keyboard.insertText('EDITé');
            else await page.locator('#bold').click();
          } else {
            await page.locator('#editing-scope').selectOption('object:textBox1');
            await expect(page.locator('#paper')).toContainText('BOX');
          }
          await expect(page.getByRole('alert')).toBeHidden();
          await download(`media-browser-${item.name}-${action}`, metadata, page);
          await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
          await page.reload();
          await expect(page.locator('#recovery-notice')).toBeVisible();
          await download(`media-recovered-${item.name}-${action}`, metadata, page);
          if (action !== 'identity') {
            const count = action === 'geometry' ? 2 : 1;
            for (let index = 0; index < count; index++) await page.locator('#undo').click();
            await download(`media-undo-${item.name}-${action}`, {
              ...metadata, media: { ...metadata.media, stage: previous },
            }, page);
            await expect(page.locator('#draft-state')).toHaveText(messages.en.draftSaved);
            await page.reload();
            await expect(page.locator('#recovery-notice')).toBeVisible();
            for (let index = 0; index < count; index++) await page.locator('#redo').click();
            await download(`media-recovered-redo-${item.name}-${action}`, metadata, page);
          }
          assert.deepEqual(errors, []);
        } finally { await page.close(); }
      }
    }
  } finally { dom.window.close(); }
}

export async function verifyMediaCase(directory, entry, actual) {
  const report = JSON.parse(await readFile(resolve(directory, 'Output/media-report.json'), 'utf8'));
  const expected = report.cases.find(item => item.name === entry.media.kind).stages.find(stage => stage.name === entry.media.stage).stats;
  assert.deepEqual(actual.mediaImported, expected, `${entry.name}: native getters/text/ranges differ from independent native operation`);
  assert.deepEqual(actual.mediaReopened, expected, `${entry.name}: reopen changed object state`);
  const open = async path => WriteProDocument.open(new Uint8Array(await readFile(resolve(directory, path))));
  const source = await open(`Input/${entry.media.source}`);
  const edited = await open(`Input/${entry.file}`);
  const before = outsideObject(source.document, 'textBox1', true);
  const after = outsideObject(edited.document, 'textBox1', true);
  // Compare all nonactive content independently of native normalization/class naming.
  const normalize = xml => {
    const model = new WriteProDocument(xml);
    const image = model.document.querySelector('body > img');
    image?.removeAttribute('style');
    model.document.querySelector('body > div')?.replaceChildren();
    model.document.querySelector('meta[name="datetimeModified"]')?.remove();
    return model.serialize();
  };
  assert.equal(normalize(after), normalize(before), `${entry.name}: nonactive source XML changed`);
  for (const image of source.document.querySelectorAll('img')) {
    const retained = image.id ? [...edited.document.querySelectorAll('img')].find(element => element.id === image.id) : null;
    if (retained) assert.equal(retained.getAttribute('src'), image.getAttribute('src'), `${entry.name}: original media bytes changed`);
  }
  const formulas = model => model.formulaElements().map(element => element.outerHTML);
  assert.deepEqual(formulas(edited), formulas(source), `${entry.name}: formula subtree changed`);
  if (entry.media.stage === 'format') {
    const reopened = await open(`Output/${entry.name}.4wp`);
    const box = reopened.storedObjects().find(item => item.id === 'textBox1').element;
    const first = box.querySelector('span');
    assert(first && reopened.values(first)['font-weight'] === 'bold', `${entry.name}: native did not retain box formatting`);
  }
}
